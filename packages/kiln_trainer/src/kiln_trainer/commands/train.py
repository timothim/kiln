"""``train`` subcommand — LoRA SFT via ``mlx_lm.lora``.

Flow:

1. Resolve hyperparameters (``hyperparams.defaults_for`` with CLI overrides).
2. Allocate a run directory.
3. Validate + split the ChatML JSONL into ``<run_dir>/data/{train,valid[,test]}.jsonl``.
4. Write a YAML config for the LoRA parameters (rank/alpha/keys) that
   ``mlx_lm.lora`` only accepts via ``--config`` in 0.21.
5. Spawn the trainer subprocess and parse its stdout into IPC events.
6. Forward SIGTERM to the child and emit ``done(interrupted=True)`` on
   interrupt; otherwise emit ``done(interrupted=False)`` on clean exit.

Stdout parsing anchors on the exact format printed by ``mlx_lm.tuner.trainer``
(0.21.5): e.g. ``Iter 10: Train loss 1.234, Learning Rate 1.000e-04, ...``.
"""

from __future__ import annotations

import argparse
import queue
import re
import signal
import subprocess
import sys
import threading
from pathlib import Path
from typing import IO, Any

from kiln_trainer import chatml, events, hyperparams, runtime

# mlx_lm.tuner.trainer prints these exact forms in 0.21.5:
#   "Iter {it}: Train loss {x:.3f}, Learning Rate {lr:.3e}, ... Tokens/sec {tps:.3f}, ..."
#   "Iter {it}: Val loss {x:.3f}, Val took {t:.3f}s"
#   "Iter {it}: Saved adapter weights to {file} and {versioned}."
#   "Saved final weights to {file}."
_RE_TRAIN_ITER = re.compile(r"^Iter\s+(\d+):\s+Train loss\s+([\d.]+)")
_RE_VAL_ITER = re.compile(r"^Iter\s+(\d+):\s+Val loss\s+([\d.]+)")
_RE_LR = re.compile(r"Learning Rate\s+([\d.eE+-]+)")
_RE_TOKENS_PER_S = re.compile(r"Tokens/sec\s+([\d.]+)")
_RE_SAVE = re.compile(r"^Iter\s+(\d+):\s+Saved adapter weights to\s+(\S+)")
_RE_FINAL_SAVE = re.compile(r"^Saved final weights to\s+(\S+?)\.?$")


def run(args: argparse.Namespace) -> int:
    # (1) resolve hyperparameters
    try:
        hp = hyperparams.defaults_for(args.model)
    except ValueError as exc:
        events.emit(
            events.error(code="model_not_found", message=str(exc), recoverable=False, stage="sft")
        )
        return 2

    epochs = args.epochs if args.epochs is not None else hp["epochs"]
    batch_size = args.batch_size if args.batch_size is not None else hp["batch_size"]
    learning_rate = args.learning_rate if args.learning_rate is not None else hp["learning_rate"]
    lora_layers = args.lora_layers if args.lora_layers is not None else hp["lora_layers"]
    rank = args.rank if args.rank is not None else hp["rank"]
    alpha = hp["alpha"]
    max_seq_length = args.max_seq_length if args.max_seq_length is not None else hp["max_seq_length"]

    # (2) run_dir
    run_dir = Path(args.run_dir) if args.run_dir else runtime.make_run_dir()
    adapter_dir = run_dir / "adapters"
    adapter_dir.mkdir(parents=True, exist_ok=True)

    # (3) data splits
    try:
        counts = chatml.write_splits(run_dir, args.dataset, seed=args.seed)
    except chatml.ChatMLValidationError as exc:
        events.emit(events.error(code="data_invalid", message=str(exc), recoverable=False, stage="sft"))
        return 1
    except FileNotFoundError as exc:
        events.emit(
            events.error(
                code="data_invalid",
                message=f"dataset not found: {exc}",
                recoverable=False,
                stage="sft",
            )
        )
        return 1

    if counts["train"] == 0:
        events.emit(
            events.error(code="data_invalid", message="training set is empty", recoverable=False, stage="sft")
        )
        return 1

    runtime.log("dataset prepared", **{f"n_{k}": v for k, v in counts.items()})

    # (4) compute iters
    if args.iters is not None:
        iters = max(1, args.iters)
    else:
        iters_per_epoch = max(1, counts["train"] // batch_size)
        iters = max(10, epochs * iters_per_epoch)

    # (5) YAML config (rank/alpha/keys are YAML-only in mlx-lm 0.21.*)
    config_path = run_dir / "lora_config.yaml"
    config_path.write_text(
        _render_lora_yaml(
            rank=rank,
            alpha=alpha,
            keys=hp["lora_keys"],
        ),
        encoding="utf-8",
    )

    # (6) build subprocess command
    cmd = _build_cmd(
        args=args,
        run_dir=run_dir,
        adapter_dir=adapter_dir,
        config_path=config_path,
        iters=iters,
        batch_size=batch_size,
        learning_rate=learning_rate,
        lora_layers=lora_layers,
        max_seq_length=max_seq_length,
    )
    runtime.log("spawning trainer", iters=iters, batch_size=batch_size, rank=rank, alpha=alpha)

    if args.sample_prompts_file is not None:
        runtime.log(
            "sample-prompts-file accepted; Growing Model samples deferred to M6",
            path=str(args.sample_prompts_file),
        )

    # (7) install SIGTERM handler and spawn
    triggered = runtime.install_sigterm_handler()
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
    except FileNotFoundError as exc:
        events.emit(
            events.error(code="subprocess_failed", message=str(exc), recoverable=False, stage="sft")
        )
        return 1

    # (8) background readers to avoid deadlock on stderr fill-up
    out_q: queue.Queue[str | None] = queue.Queue()
    err_q: queue.Queue[str | None] = queue.Queue()
    if proc.stdout is None or proc.stderr is None:
        raise runtime.PipeUnavailableError(
            f"trainer subprocess missing pipe handles: "
            f"stdout={proc.stdout!r}, stderr={proc.stderr!r}"
        )
    threading.Thread(target=_drain, args=(proc.stdout, out_q), daemon=True).start()
    threading.Thread(target=_drain, args=(proc.stderr, err_q), daemon=True).start()

    handler = _LineHandler(stage="sft")
    interrupted = False
    poll_interval = 0.1

    while True:
        if triggered.is_set() and not interrupted:
            interrupted = True
            runtime.log("SIGTERM received; forwarding to trainer child")
            try:
                proc.send_signal(signal.SIGTERM)
            except ProcessLookupError:
                pass

        try:
            line = out_q.get(timeout=poll_interval)
        except queue.Empty:
            if proc.poll() is not None and out_q.empty():
                break
            continue

        if line is None:  # EOF from reader
            break
        handler.handle(line.rstrip("\n"))

    # Drain stderr into our stderr log.
    _drain_remaining(err_q, label="trainer stderr")

    # Make sure the child really is dead.
    if proc.poll() is None:
        try:
            proc.wait(timeout=4.0)
        except subprocess.TimeoutExpired:
            runtime.log("trainer still alive after 4s; sending SIGKILL")
            proc.kill()
            try:
                proc.wait(timeout=1.0)
            except subprocess.TimeoutExpired:
                pass

    # (9) emit done
    latest = runtime.find_latest_adapter(adapter_dir)
    artifact = handler.last_checkpoint or (str(latest) if latest else str(adapter_dir / "adapters.safetensors"))
    events.emit(events.done(stage="sft", artifact=artifact, interrupted=interrupted))

    if interrupted:
        return 0
    rc = proc.returncode or 0
    if rc != 0:
        events.emit(
            events.error(
                code="subprocess_failed",
                message=f"trainer exited with code {rc}",
                recoverable=False,
                stage="sft",
            )
        )
        return rc
    return 0


class _LineHandler:
    """Stateful parser: carries the last-seen train loss so val lines can emit
    a well-formed :func:`events.progress` (which requires ``loss``)."""

    def __init__(self, *, stage: str) -> None:
        self.stage = stage
        self._last_train_loss: float | None = None
        self.last_checkpoint: str | None = None

    def handle(self, text: str) -> None:
        m_save = _RE_SAVE.search(text)
        if m_save:
            it = int(m_save.group(1))
            path = m_save.group(2).rstrip(".")
            events.emit(events.checkpoint(path=path, iter=it))
            self.last_checkpoint = path
            return

        m_final = _RE_FINAL_SAVE.search(text)
        if m_final:
            path = m_final.group(1).rstrip(".")
            self.last_checkpoint = path
            return

        m_train = _RE_TRAIN_ITER.search(text)
        if m_train:
            it = int(m_train.group(1))
            loss = float(m_train.group(2))
            self._last_train_loss = loss
            kwargs: dict[str, Any] = {"stage": self.stage, "iter": it, "loss": loss}
            m_tps = _RE_TOKENS_PER_S.search(text)
            if m_tps:
                kwargs["tokens_per_s"] = float(m_tps.group(1))
            m_lr = _RE_LR.search(text)
            if m_lr:
                kwargs["learning_rate"] = float(m_lr.group(1))
            events.emit(events.progress(**kwargs))
            return

        m_val = _RE_VAL_ITER.search(text)
        if m_val:
            if self._last_train_loss is None:
                runtime.log("val line before any train line; skipped", line=text)
                return
            events.emit(
                events.progress(
                    stage=self.stage,
                    iter=int(m_val.group(1)),
                    loss=self._last_train_loss,
                    val_loss=float(m_val.group(2)),
                )
            )
            return

        if text.strip():
            runtime.log("trainer stdout", line=text)


def _render_lora_yaml(*, rank: int, alpha: int, keys: tuple[str, ...]) -> str:
    """Render the YAML consumed by ``mlx_lm.lora --config``.

    ``dropout`` and ``scale`` track MLX-LM's defaults (``mlx_lm.lora``
    :data:`CONFIG_DEFAULTS`). ``keys`` is the fully qualified module path
    list — ``linear_to_lora_layers`` matches by exact name."""
    lines = [
        "lora_parameters:",
        f"  rank: {rank}",
        f"  alpha: {alpha}",
        "  dropout: 0.0",
        "  scale: 10.0",
        "  keys:",
    ]
    for key in keys:
        lines.append(f"    - {key}")
    lines.append("")
    return "\n".join(lines)


def _build_cmd(
    *,
    args: argparse.Namespace,
    run_dir: Path,
    adapter_dir: Path,
    config_path: Path,
    iters: int,
    batch_size: int,
    learning_rate: float,
    lora_layers: int,
    max_seq_length: int,
) -> list[str]:
    if args.trainer_entry:
        base = [sys.executable, str(args.trainer_entry)]
    else:
        base = [sys.executable, "-m", args.trainer_module]
    return base + [
        "--model", args.model,
        "--train",
        "--fine-tune-type", "lora",
        "--data", str(run_dir / "data"),
        "--adapter-path", str(adapter_dir),
        "--config", str(config_path),
        "--iters", str(iters),
        "--batch-size", str(batch_size),
        "--learning-rate", str(learning_rate),
        "--num-layers", str(lora_layers),
        "--save-every", str(args.save_every),
        "--val-batches", str(args.val_batches),
        "--max-seq-length", str(max_seq_length),
        "--grad-checkpoint",
        "--seed", str(args.seed),
    ]


def _drain(fh: IO[str], q: "queue.Queue[str | None]") -> None:
    """Ship lines from ``fh`` onto ``q`` and terminate with ``None``."""
    try:
        for line in fh:
            q.put(line)
    finally:
        q.put(None)
        try:
            fh.close()
        except Exception:
            pass


def _drain_remaining(q: "queue.Queue[str | None]", *, label: str) -> None:
    while True:
        try:
            line = q.get(timeout=0.05)
        except queue.Empty:
            return
        if line is None:
            return
        runtime.log(label, line=line.rstrip("\n"))

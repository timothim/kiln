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
import json
import queue
import re
import signal
import subprocess
import sys
import threading
from pathlib import Path
from typing import IO, Any, Callable

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

    # Demo-friendly checkpoint cadence. mlx_lm.lora 0.21.5 only writes
    # ``adapters.safetensors`` at ``save-every`` milestones — it does not
    # auto-save the final state. With the default save-every=50 and a
    # small corpus (iters=10–40) the user gets nothing on disk and the
    # downstream Sample / Export / Chat all 404. Cap save-every so we
    # always produce 3 checkpoints minimum, plus a guaranteed last one.
    effective_save_every = min(args.save_every, max(2, iters // 3))
    runtime.log(
        "save-every cadence",
        requested=args.save_every,
        effective=effective_save_every,
        iters=iters,
    )

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
        save_every=effective_save_every,
    )
    runtime.log("spawning trainer", iters=iters, batch_size=batch_size, rank=rank, alpha=alpha)

    if args.sample_prompts_file is not None:
        runtime.log(
            "sample-prompts-file set; Growing Model samples will use this list at each checkpoint",
            path=str(args.sample_prompts_file),
        )

    advisor_state: _AdvisorState | None = None
    if getattr(args, "enable_advisor", False):
        advisor_state = _AdvisorState(
            mode=getattr(args, "advisor_mode", "cloud"),
            iter_total=iters,
            advisor_entry=getattr(args, "advisor_entry", None),
        )
        runtime.log(
            "training advisor enabled",
            mode=advisor_state.mode,
            iters=iters,
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

    def _on_checkpoint(it: int, adapter_path: str) -> None:
        captured_samples = _emit_samples_after_checkpoint(
            adapter_path=adapter_path,
            iter=it,
            model=args.model,
            sampler_entry=args.sampler_entry,
            prompts_file=args.sample_prompts_file,
        )
        if advisor_state is not None and captured_samples:
            _emit_advisor_observation_after_checkpoint(
                state=advisor_state,
                iter_now=it,
                samples=captured_samples,
                loss_trajectory=handler.loss_trajectory,
            )

    handler = _LineHandler(stage="sft", on_checkpoint=_on_checkpoint)
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
    a well-formed :func:`events.progress` (which requires ``loss``).

    Optional ``on_checkpoint`` callback fires after every ``checkpoint`` event
    is emitted — M6.5 uses it to kick off the Growing Model sampler. The
    callback receives ``(iter, adapter_path)``. Exceptions raised by the
    callback are caught and logged so a sampler failure never breaks training.
    """

    def __init__(
        self,
        *,
        stage: str,
        on_checkpoint: Callable[[int, str], None] | None = None,
    ) -> None:
        self.stage = stage
        self._last_train_loss: float | None = None
        self.last_checkpoint: str | None = None
        self._on_checkpoint = on_checkpoint
        # Saturday-final: the Training Advisor consumes a rolling
        # window of recent loss values to anchor its observation. We
        # capture every train-iter loss; the consumer truncates.
        self.loss_trajectory: list[float] = []

    def handle(self, text: str) -> None:
        m_save = _RE_SAVE.search(text)
        if m_save:
            it = int(m_save.group(1))
            path = m_save.group(2).rstrip(".")
            events.emit(events.checkpoint(path=path, iter=it))
            self.last_checkpoint = path
            if self._on_checkpoint is not None:
                try:
                    self._on_checkpoint(it, path)
                except Exception as exc:
                    runtime.log(
                        "on_checkpoint callback raised; continuing training",
                        iter=it,
                        error=str(exc),
                    )
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
            self.loss_trajectory.append(loss)
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
    save_every: int | None = None,
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
        "--save-every", str(save_every if save_every is not None else args.save_every),
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


# ---------- M6.5: Growing Model samples at each checkpoint ----------


_SAMPLER_BUDGET_S: float = 30.0


def _emit_samples_after_checkpoint(
    *,
    adapter_path: str,
    iter: int,
    model: str,
    sampler_entry: str | None,
    prompts_file: Path | None,
    budget_s: float = _SAMPLER_BUDGET_S,
) -> list[dict[str, Any]]:
    """Run ``sample-batch`` against the freshly-saved adapter, emit a
    ``sample`` event for each prompt, and return the captured samples
    so the Training Advisor (when enabled) can feed them into Opus
    without re-running the sampler.

    This runs synchronously on the main training loop — the ~10 s pause is
    acceptable because mlx_lm has already flushed the checkpoint and any
    trainer stdout that queues up meanwhile is captured by the drain thread.

    Never raises. On timeout, non-zero exit, or malformed subprocess stdout,
    we ``runtime.log`` a warning (stderr) and return ``[]``; training keeps
    running. No ``error`` event is emitted on stdout because a failed
    Growing Model sample is not a failed training run.
    """
    cmd = [
        sys.executable,
        "-m",
        "kiln_trainer",
        "sample-batch",
        "--model",
        model,
        "--adapter-path",
        adapter_path,
        "--max-tokens",
        "150",
        "--temp",
        "0.7",
    ]
    if prompts_file is not None:
        cmd += ["--prompts-file", str(prompts_file)]
    if sampler_entry is not None:
        cmd += ["--generator-entry", sampler_entry]

    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=budget_s,
        )
    except subprocess.TimeoutExpired:
        runtime.log(
            "sample-batch exceeded budget; skipping samples for this checkpoint",
            iter=iter,
            budget_s=budget_s,
        )
        return []
    except (FileNotFoundError, OSError) as exc:
        runtime.log(
            "sample-batch failed to spawn",
            iter=iter,
            error=str(exc),
        )
        return []

    if proc.returncode != 0:
        runtime.log(
            "sample-batch exited non-zero; skipping samples",
            iter=iter,
            returncode=proc.returncode,
            stderr_tail=proc.stderr[-400:] if proc.stderr else "",
        )
        return []

    return _reemit_generations_as_samples(proc.stdout, iter=iter)


def _reemit_generations_as_samples(stdout_text: str, *, iter: int) -> list[dict[str, Any]]:
    """Parse sample-batch stdout and emit one ``sample`` event per
    ``generation`` event, tagged with ``iter``. Other event types (ready,
    done, error) are ignored. Returns the parsed ``{prompt, completion}``
    pairs for downstream consumers (the Training Advisor)."""
    captured: list[dict[str, Any]] = []
    for line in stdout_text.splitlines():
        if not line.strip():
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(ev, dict) or ev.get("event") != "generation":
            continue
        prompt_id = ev.get("prompt_id")
        completion = ev.get("completion")
        if not isinstance(prompt_id, str) or not isinstance(completion, str):
            continue
        tokens_per_s_raw = ev.get("tokens_per_s")
        tokens_per_s: float | None
        if isinstance(tokens_per_s_raw, (int, float)):
            tokens_per_s = float(tokens_per_s_raw)
        else:
            tokens_per_s = None
        events.emit(
            events.sample(
                iter=iter,
                prompt_id=prompt_id,
                completion=completion,
                tokens_per_s=tokens_per_s,
            )
        )
        captured.append({"prompt": prompt_id, "completion": completion})
    return captured


# ---------- PR #23: Training Advisor (post-checkpoint observation) ----------


_ADVISOR_BUDGET_S: float = 25.0


class _AdvisorState:
    """Carries the advisor mode + total iteration count across checkpoints.

    The advisor is invoked once per checkpoint (immediately after the
    Growing Model sampler runs), not on a wall-clock 30 s timer. This
    deliberate variation from the original design pairs each observation
    with the freshly-generated samples that motivated it; checkpoints in
    practice fire every 30–60 s anyway. Documented in PR #23.
    """

    __slots__ = ("mode", "iter_total", "advisor_entry")

    def __init__(self, *, mode: str, iter_total: int, advisor_entry: str | None) -> None:
        if mode not in ("cloud", "local"):
            raise ValueError(f"advisor mode must be cloud|local, got {mode!r}")
        self.mode = mode
        self.iter_total = int(iter_total)
        self.advisor_entry = advisor_entry  # hidden test seam


def _emit_advisor_observation_after_checkpoint(
    *,
    state: _AdvisorState,
    iter_now: int,
    samples: list[dict[str, Any]],
    loss_trajectory: list[float],
    budget_s: float = _ADVISOR_BUDGET_S,
) -> None:
    """Spawn the training-advisor module with the post-checkpoint state
    snapshot. Re-emits the resulting ``advisor_observation`` event onto
    our own stdout so the Swift parent can stream it into the panel.

    Never raises. On timeout, non-zero exit, missing API key, or
    malformed subprocess stdout we ``runtime.log`` a warning and return
    silently; training keeps running with a "no observation this iter"
    gap in the panel.
    """
    if state.advisor_entry is not None:
        cmd = [sys.executable, str(state.advisor_entry), "--mode", state.mode]
    else:
        cmd = [
            sys.executable,
            "-m",
            "kiln_trainer.training_advisor",
            "--mode",
            state.mode,
        ]

    payload = json.dumps({
        "samples": samples,
        "loss_trajectory": loss_trajectory[-24:],
        "iter": iter_now,
        "iter_total": state.iter_total,
    })

    try:
        proc = subprocess.run(
            cmd,
            input=payload,
            capture_output=True,
            text=True,
            timeout=budget_s,
        )
    except subprocess.TimeoutExpired:
        runtime.log(
            "training-advisor exceeded budget; no observation for this iter",
            iter=iter_now,
            budget_s=budget_s,
        )
        return
    except (FileNotFoundError, OSError) as exc:
        runtime.log("training-advisor failed to spawn", iter=iter_now, error=str(exc))
        return

    if proc.returncode != 0:
        runtime.log(
            "training-advisor exited non-zero; no observation",
            iter=iter_now,
            returncode=proc.returncode,
            stderr_tail=(proc.stderr or "")[-400:],
        )
        return

    for line in (proc.stdout or "").splitlines():
        if not line.strip():
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(ev, dict) or ev.get("event") != "advisor_observation":
            continue
        content = ev.get("content")
        model_id = ev.get("model")
        if not isinstance(content, str) or not isinstance(model_id, str):
            continue
        events.emit(
            events.advisor_observation(
                iter=iter_now,
                content=content,
                model=model_id,
            )
        )

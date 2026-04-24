"""``sample-batch`` subcommand — batched Growing Model generation.

Loads the base model + adapter once via the MLX-LM Python API, iterates a
list of prompts, and emits one ``generation`` JSON-line event per prompt
plus a terminal ``done(stage="generation")``. The train orchestrator spawns
this once per checkpoint and re-emits each ``generation`` event as a
``sample`` event with the checkpoint's ``iter`` tagged on.

Why a batched subcommand:

- 3 fixed prompts × 1 invocation means ONE model load per checkpoint,
  not three. Closes the budget gap between the 5–10 s ideal and the
  30 s abort cap documented in the M6.5 spec.

Prompt resolution:

1. ``--prompts-file`` (if given) — JSON list of ``{id, text}``.
2. :data:`kiln_trainer.sample_prompts.DEFAULT_PROMPTS` (fallback).

Test seam:

``--generator-entry <script>`` replaces the inline MLX path entirely. When
set, we spawn the script with ``--prompts-file`` + ``--adapter-path``,
forward SIGTERM, and proxy its stdout verbatim to our own. Tests use
``tests/fixtures/fake_batch_generator.py`` which emits the same
``generation`` / ``done`` envelope our real path produces.
"""

from __future__ import annotations

import argparse
import json
import queue
import signal
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import IO

from kiln_trainer import events, runtime, sample_prompts


def run(args: argparse.Namespace) -> int:
    prompts = _load_prompts(args.prompts_file)
    if not prompts:
        events.emit(
            events.error(
                code="data_invalid",
                message="sample-batch: no prompts to run",
                recoverable=False,
                stage="generation",
            )
        )
        return 1

    if args.generator_entry:
        return _run_via_seam(args=args, prompts=prompts)
    return _run_inline_mlx(args=args, prompts=prompts)


def _load_prompts(path: Path | None) -> list[dict[str, str]]:
    if path is None:
        return [dict(p) for p in sample_prompts.DEFAULT_PROMPTS]
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        runtime.log("sample-batch: failed to read --prompts-file", path=str(path), error=str(exc))
        return []
    if not isinstance(data, list):
        runtime.log("sample-batch: --prompts-file must be a JSON list", path=str(path))
        return []
    out: list[dict[str, str]] = []
    for entry in data:
        if not isinstance(entry, dict) or "id" not in entry or "text" not in entry:
            runtime.log("sample-batch: skipping malformed prompt entry", entry=str(entry))
            continue
        out.append({"id": str(entry["id"]), "text": str(entry["text"])})
    return out


def _run_via_seam(*, args: argparse.Namespace, prompts: list[dict[str, str]]) -> int:
    with tempfile.NamedTemporaryFile(
        "w", suffix=".json", delete=False, encoding="utf-8"
    ) as tf:
        json.dump(prompts, tf)
        resolved_path = Path(tf.name)

    try:
        cmd = [
            sys.executable,
            str(args.generator_entry),
            "--prompts-file", str(resolved_path),
            "--adapter-path", str(args.adapter_path),
            "--max-tokens", str(args.max_tokens),
            "--temp", str(args.temp),
        ]
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
                events.error(
                    code="subprocess_failed",
                    message=str(exc),
                    recoverable=False,
                    stage="generation",
                )
            )
            return 1

        if proc.stdout is None or proc.stderr is None:
            raise runtime.PipeUnavailableError(
                f"sample-batch seam missing pipe handles: "
                f"stdout={proc.stdout!r}, stderr={proc.stderr!r}"
            )

        out_q: queue.Queue[str | None] = queue.Queue()
        err_q: queue.Queue[str | None] = queue.Queue()
        threading.Thread(target=_drain, args=(proc.stdout, out_q), daemon=True).start()
        threading.Thread(target=_drain, args=(proc.stderr, err_q), daemon=True).start()

        interrupted = False
        while True:
            if triggered.is_set() and not interrupted:
                interrupted = True
                try:
                    proc.send_signal(signal.SIGTERM)
                except ProcessLookupError:
                    pass

            try:
                line = out_q.get(timeout=0.1)
            except queue.Empty:
                if proc.poll() is not None and out_q.empty():
                    break
                continue

            if line is None:
                break
            sys.stdout.write(line)
            sys.stdout.flush()

        _drain_remaining(err_q, label="sample-batch seam stderr")

        if proc.poll() is None:
            try:
                proc.wait(timeout=4.0)
            except subprocess.TimeoutExpired:
                proc.kill()
                try:
                    proc.wait(timeout=1.0)
                except subprocess.TimeoutExpired:
                    pass
        return proc.returncode or 0
    finally:
        try:
            resolved_path.unlink()
        except FileNotFoundError:
            pass


def _run_inline_mlx(*, args: argparse.Namespace, prompts: list[dict[str, str]]) -> int:
    try:
        from mlx_lm import generate, load  # type: ignore[import-not-found]
    except ImportError as exc:
        events.emit(
            events.error(
                code="subprocess_failed",
                message=f"sample-batch: mlx_lm not importable: {exc}",
                recoverable=False,
                stage="generation",
            )
        )
        return 1

    triggered = runtime.install_sigterm_handler()
    try:
        model, tokenizer = load(args.model, adapter_path=str(args.adapter_path))
    except Exception as exc:
        events.emit(
            events.error(
                code="adapter_invalid",
                message=f"sample-batch: failed to load model + adapter: {exc}",
                recoverable=False,
                stage="generation",
            )
        )
        return 1

    interrupted = False
    for entry in prompts:
        if triggered.is_set():
            interrupted = True
            break
        t0 = time.monotonic()
        try:
            text = generate(
                model,
                tokenizer,
                prompt=entry["text"],
                max_tokens=args.max_tokens,
            )
        except Exception as exc:
            runtime.log(
                "sample-batch: generation failed; skipping prompt",
                prompt_id=entry["id"],
                error=str(exc),
            )
            continue
        dt = max(time.monotonic() - t0, 1e-6)
        try:
            tokens = len(tokenizer.encode(text))
        except Exception:
            tokens = len(text.split())
        events.emit(
            events.generation(
                prompt=entry["text"],
                completion=text,
                tokens=tokens,
                tokens_per_s=tokens / dt,
                prompt_id=entry["id"],
            )
        )

    events.emit(
        events.done(
            stage="generation",
            artifact=str(args.adapter_path),
            interrupted=interrupted,
        )
    )
    return 0


def _drain(fh: IO[str], q: "queue.Queue[str | None]") -> None:
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

"""``ready`` event must fire within 500 ms of sidecar start.

Per ``packages/kiln_trainer/CLAUDE.md``:

    On startup: emit ``{"event":"ready",...}`` within 500 ms. No computation
    before that.

This is the only hard latency contract the sidecar has with the Swift parent.
If it slips, the UI's "spawning" spinner gets visibly laggy and the demo feels
broken. We lock it down here with a real subprocess measurement so that any
future ``import`` creep in the hot path (e.g. someone adds ``import mlx`` at
module scope in cli.py) trips the test instead of the demo.

Uses the ``train`` subcommand with ``--trainer-entry fake_trainer.py`` to stay
on a known-cheap path. We read only the first stdout line, then SIGTERM the
child so the test cleans up quickly regardless of what the trainer was doing.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path


# Generous ceiling on slow machines / CI while still locking the order of
# magnitude. In practice `ready` fires in ~50–100 ms on an M-series Mac.
READY_BUDGET_S = 0.500


def test_ready_event_emitted_within_500ms(
    tmp_path: Path, tiny_dataset: Path, fake_trainer: Path
) -> None:
    run_dir = tmp_path / "run"
    cmd = [
        sys.executable,
        "-m",
        "kiln_trainer",
        "train",
        "--dataset", str(tiny_dataset),
        "--model", "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
        "--run-dir", str(run_dir),
        "--iters", "1",
        "--save-every", "100",
        "--val-batches", "1",
        "--trainer-entry", str(fake_trainer),
    ]
    # Make the fake trainer sleep per iter so it is still alive when we
    # terminate() it after reading ready. Keeps cleanup deterministic.
    env = {**os.environ, "KILN_FAKE_SLEEP_PER_ITER": "10"}

    t0 = time.monotonic()
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )

    try:
        assert proc.stdout is not None
        first_line = proc.stdout.readline()
        elapsed = time.monotonic() - t0

        assert first_line, (
            f"sidecar exited before emitting first stdout line. "
            f"stderr={proc.stderr.read() if proc.stderr else ''!r}"
        )

        parsed = json.loads(first_line)
        assert parsed["event"] == "ready", (
            f"first line must be ready, got {parsed!r}"
        )
        # Ready payload contract — keep the test honest about schema.
        assert "version" in parsed
        assert "mlx" in parsed

        assert elapsed < READY_BUDGET_S, (
            f"ready took {elapsed * 1000:.0f} ms "
            f"(budget {READY_BUDGET_S * 1000:.0f} ms). "
            f"Something heavy got imported before events.emit(ready)."
        )
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2.0)

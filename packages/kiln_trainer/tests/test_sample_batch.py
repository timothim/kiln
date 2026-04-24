"""Tests for :mod:`kiln_trainer.commands.sample_batch`.

End-to-end subprocess tests invoke ``python -m kiln_trainer sample-batch ...``
with ``--generator-entry tests/fixtures/fake_batch_generator.py`` so the inline
MLX path is never exercised in CI.
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path


def _events(text: str) -> list[dict]:
    return [json.loads(ln) for ln in text.splitlines() if ln.strip()]


def _adapter(tmp_path: Path) -> Path:
    adapter = tmp_path / "adapters" / "adapters.safetensors"
    adapter.parent.mkdir(parents=True, exist_ok=True)
    adapter.write_bytes(b"")
    return adapter.parent


def _run_sample_batch(
    tmp_path: Path,
    fake_batch_generator: Path,
    *,
    prompts_file: Path | None = None,
    timeout: float = 10.0,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    adapter_dir = _adapter(tmp_path)
    cmd = [
        sys.executable,
        "-m",
        "kiln_trainer",
        "sample-batch",
        "--model", "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
        "--adapter-path", str(adapter_dir),
        "--generator-entry", str(fake_batch_generator),
    ]
    if prompts_file is not None:
        cmd += ["--prompts-file", str(prompts_file)]
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=timeout,
        env={**os.environ, **(env or {})},
    )


def test_sample_batch_emits_generation_per_prompt(
    tmp_path: Path, fake_batch_generator: Path
) -> None:
    prompts_file = tmp_path / "prompts.json"
    prompts_file.write_text(
        json.dumps(
            [
                {"id": "first",  "text": "first prompt"},
                {"id": "second", "text": "second prompt"},
                {"id": "third",  "text": "third prompt"},
            ]
        ),
        encoding="utf-8",
    )
    result = _run_sample_batch(tmp_path, fake_batch_generator, prompts_file=prompts_file)
    assert result.returncode == 0, result.stderr

    events = _events(result.stdout)
    types = [e["event"] for e in events]
    assert types[0] == "ready"
    assert types.count("generation") == 3
    assert types[-1] == "done"

    gens = [e for e in events if e["event"] == "generation"]
    assert [g["prompt_id"] for g in gens] == ["first", "second", "third"]
    for g in gens:
        assert g["completion"].startswith("echo: ")
        assert isinstance(g["tokens"], int)
        assert isinstance(g["tokens_per_s"], float)


def test_sample_batch_defaults_to_builtin_prompts_when_no_file(
    tmp_path: Path, fake_batch_generator: Path
) -> None:
    result = _run_sample_batch(tmp_path, fake_batch_generator)
    assert result.returncode == 0, result.stderr

    gens = [e for e in _events(result.stdout) if e["event"] == "generation"]
    assert [g["prompt_id"] for g in gens] == [
        "week_focus",
        "birthday_msg",
        "perfect_sunday",
    ]
    texts = [g["prompt"] for g in gens]
    assert texts == [
        "What should I work on this week?",
        "Write a one-line birthday message for a friend.",
        "Describe your perfect Sunday.",
    ]


def test_sample_batch_sigterm_emits_done_interrupted(
    tmp_path: Path, fake_batch_generator: Path
) -> None:
    adapter_dir = _adapter(tmp_path)
    cmd = [
        sys.executable,
        "-m",
        "kiln_trainer",
        "sample-batch",
        "--model", "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
        "--adapter-path", str(adapter_dir),
        "--generator-entry", str(fake_batch_generator),
    ]
    env = {**os.environ, "KILN_FAKE_BATCH_SLEEP_PER_PROMPT": "2.0"}

    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env
    )
    assert proc.stdout is not None
    first = proc.stdout.readline()
    assert json.loads(first)["event"] == "ready"
    # The fake sleeps 2 s before each generation; give it enough time to be
    # deep inside the first sleep, then SIGTERM.
    time.sleep(0.4)

    t0 = time.monotonic()
    proc.send_signal(signal.SIGTERM)
    tail, _err = proc.communicate(timeout=10.0)
    elapsed = time.monotonic() - t0

    assert elapsed < 5.0
    assert proc.returncode == 0
    events = _events(first + tail)
    done = [e for e in events if e["event"] == "done"][-1]
    assert done["stage"] == "generation"
    assert done["interrupted"] is True
    # Should not have emitted a generation event for the in-flight prompt.
    gens = [e for e in events if e["event"] == "generation"]
    assert len(gens) == 0

"""Tests for :mod:`kiln_trainer.commands.sample`.

Unit-tests the verbose-output parser, then end-to-end tests the subcommand
wiring with ``fake_generator.py`` standing in for ``mlx_lm.generate``.
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import pytest

from kiln_trainer.commands.sample import _GenerateOutputParser


def _events(text: str) -> list[dict]:
    return [json.loads(ln) for ln in text.splitlines() if ln.strip()]


# ---------- Unit: _GenerateOutputParser ----------


def test_parser_extracts_single_line_completion() -> None:
    p = _GenerateOutputParser()
    for ln in [
        "Loading model...",  # pre-delim noise is ignored
        "==========",
        "hello world",
        "==========",
        "Prompt: 3 tokens, 100.000 tokens-per-sec",
        "Generation: 5 tokens, 25.500 tokens-per-sec",
        "Peak memory: 0.5 GB",
    ]:
        p.feed(ln)
    assert p.completion == "hello world"
    assert p.tokens == 5
    assert p.tokens_per_s == 25.5


def test_parser_preserves_multiline_completion() -> None:
    p = _GenerateOutputParser()
    for ln in [
        "==========",
        "line 1",
        "line 2",
        "line 3",
        "==========",
        "Generation: 10 tokens, 50.0 tokens-per-sec",
    ]:
        p.feed(ln)
    assert p.completion == "line 1\nline 2\nline 3"


def test_parser_strips_trailing_blank_line_from_completion() -> None:
    """mlx_lm always emits a bare ``print()`` (= one extra blank line) after
    the streamed completion. We must strip it so the emitted ``completion``
    matches what the user sees."""
    p = _GenerateOutputParser()
    for ln in ["==========", "hello", "", "=========="]:
        p.feed(ln)
    assert p.completion == "hello"


def test_parser_ignores_everything_before_first_delimiter() -> None:
    p = _GenerateOutputParser()
    p.feed("some warning about tokenizer")
    p.feed("loading weights")
    p.feed("==========")
    p.feed("the reply")
    p.feed("==========")
    p.feed("Generation: 2 tokens, 10.0 tokens-per-sec")
    assert p.completion == "the reply"


# ---------- End-to-end subprocess ----------


def _run_sample(
    tmp_path: Path,
    fake_generator: Path,
    *,
    prompt: str = "What's up?",
    prompt_id: str | None = None,
    timeout: float = 10.0,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    adapter = tmp_path / "adapters" / "adapters.safetensors"
    adapter.parent.mkdir(parents=True, exist_ok=True)
    adapter.write_bytes(b"")
    cmd = [
        sys.executable,
        "-m",
        "kiln_trainer",
        "sample",
        "--model", "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
        "--adapter-path", str(adapter.parent),
        "--prompt", prompt,
        "--generator-entry", str(fake_generator),
    ]
    if prompt_id is not None:
        cmd += ["--prompt-id", prompt_id]
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=timeout,
        env={**os.environ, **(env or {})},
    )


def test_sample_emits_ready_generation_done(
    tmp_path: Path, fake_generator: Path
) -> None:
    result = _run_sample(tmp_path, fake_generator, prompt="hello")
    assert result.returncode == 0, result.stderr
    events = _events(result.stdout)

    types = [e["event"] for e in events]
    assert types[0] == "ready"
    assert "generation" in types
    assert types[-1] == "done"


def test_generation_event_carries_completion_and_stats(
    tmp_path: Path, fake_generator: Path
) -> None:
    result = _run_sample(tmp_path, fake_generator, prompt="say hi")
    assert result.returncode == 0, result.stderr
    gen = next(e for e in _events(result.stdout) if e["event"] == "generation")
    assert gen["prompt"] == "say hi"
    assert "echo: say hi" in gen["completion"]
    assert gen["tokens"] == 8  # 2 parts * 4 (per fake_generator)
    assert gen["tokens_per_s"] == 45.678


def test_prompt_id_echoed_on_generation_event(
    tmp_path: Path, fake_generator: Path
) -> None:
    result = _run_sample(
        tmp_path, fake_generator, prompt="ping", prompt_id="prompt-42"
    )
    assert result.returncode == 0, result.stderr
    gen = next(e for e in _events(result.stdout) if e["event"] == "generation")
    assert gen["prompt_id"] == "prompt-42"


def test_done_event_stage_generation(
    tmp_path: Path, fake_generator: Path
) -> None:
    result = _run_sample(tmp_path, fake_generator)
    assert result.returncode == 0, result.stderr
    done = [e for e in _events(result.stdout) if e["event"] == "done"][-1]
    assert done["stage"] == "generation"
    assert done.get("interrupted") is False


def test_sample_sigterm_emits_done_interrupted(
    tmp_path: Path, fake_generator: Path, tiny_dataset: Path
) -> None:
    adapter = tmp_path / "adapters" / "adapters.safetensors"
    adapter.parent.mkdir(parents=True, exist_ok=True)
    adapter.write_bytes(b"")
    cmd = [
        sys.executable,
        "-m",
        "kiln_trainer",
        "sample",
        "--model", "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
        "--adapter-path", str(adapter.parent),
        "--prompt", "hello",
        "--generator-entry", str(fake_generator),
    ]
    # Hold the fake generator between the delimiter and the stats so SIGTERM
    # lands while the parent's parser is in the post-completion state.
    env = {**os.environ, "KILN_FAKE_GENERATE_SLEEP": "2.0"}
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env
    )
    assert proc.stdout is not None
    first = proc.stdout.readline()
    assert json.loads(first)["event"] == "ready"
    # Give the child time to reach the second ==========.
    time.sleep(0.3)

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


def test_stdin_prompt_when_dash(
    tmp_path: Path, fake_generator: Path
) -> None:
    adapter = tmp_path / "adapters" / "adapters.safetensors"
    adapter.parent.mkdir(parents=True, exist_ok=True)
    adapter.write_bytes(b"")
    cmd = [
        sys.executable,
        "-m",
        "kiln_trainer",
        "sample",
        "--model", "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
        "--adapter-path", str(adapter.parent),
        "--prompt", "-",
        "--generator-entry", str(fake_generator),
    ]
    result = subprocess.run(
        cmd,
        input="piped prompt",
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    gen = next(e for e in _events(result.stdout) if e["event"] == "generation")
    assert gen["prompt"] == "piped prompt"

"""Tests for :mod:`kiln_trainer.commands.export`.

Three layers:

1. Unit tests for helpers (``_slugify``, ``_gguf_outtype``).
2. End-to-end subprocess tests using fake fuser / gguf-convert / ollama
   fixtures. These cover the happy path, the skip flags, error codes, and the
   Modelfile rendering.
3. A SIGTERM interruption test.
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

from kiln_trainer.commands.export import _slugify


def _events(text: str) -> list[dict]:
    return [json.loads(ln) for ln in text.splitlines() if ln.strip()]


# ---------- Unit ----------


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("Tim", "tim"),
        ("Tim Cook", "tim-cook"),
        ("  Multiple   Spaces  ", "multiple-spaces"),
        ("user@example.com", "user-example-com"),
        ("x", "x"),
        ("___", "user"),
        ("", "user"),
        ("Tim-O'Brien", "tim-o-brien"),
    ],
)
def test_slugify(raw: str, expected: str) -> None:
    assert _slugify(raw) == expected


# ---------- End-to-end subprocess ----------


def _prep_dirs(tmp_path: Path) -> tuple[Path, Path, Path]:
    """Create the adapter directory and locate the fake llama.cpp dir."""
    adapter_dir = tmp_path / "adapters"
    adapter_dir.mkdir()
    (adapter_dir / "adapters.safetensors").write_bytes(b"")
    run_dir = tmp_path / "export-run"
    llama_cpp = Path(__file__).parent / "fixtures" / "llama.cpp"
    return adapter_dir, run_dir, llama_cpp


def _build_cmd(
    *,
    tmp_path: Path,
    adapter_dir: Path,
    run_dir: Path,
    llama_cpp: Path,
    fixtures_dir: Path,
    model: str = "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
    user_name: str | None = "Tim",
    output_name: str | None = None,
    skip_gguf: bool = False,
    skip_ollama: bool = False,
) -> list[str]:
    cmd = [
        sys.executable,
        "-m",
        "kiln_trainer",
        "export",
        "--model", model,
        "--adapter-path", str(adapter_dir),
        "--run-dir", str(run_dir),
        "--fuser-entry", str(fixtures_dir / "fake_fuser.py"),
        "--llama-cpp-dir", str(llama_cpp),
        "--ollama-bin", str(fixtures_dir / "fake_ollama.py"),
    ]
    if user_name is not None:
        cmd += ["--user-name", user_name]
    if output_name is not None:
        cmd += ["--output-name", output_name]
    if skip_gguf:
        cmd.append("--skip-gguf")
    if skip_ollama:
        cmd.append("--skip-ollama")
    return cmd


def test_happy_path_emits_done_for_each_stage(
    tmp_path: Path, fixtures_dir: Path
) -> None:
    adapter_dir, run_dir, llama_cpp = _prep_dirs(tmp_path)
    cmd = _build_cmd(
        tmp_path=tmp_path, adapter_dir=adapter_dir, run_dir=run_dir,
        llama_cpp=llama_cpp, fixtures_dir=fixtures_dir,
    )
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, result.stderr
    events = _events(result.stdout)

    types = [e["event"] for e in events]
    assert types[0] == "ready"
    # Expect exactly one done for each stage, in order.
    dones = [e for e in events if e["event"] == "done"]
    assert [d["stage"] for d in dones] == ["fuse", "gguf", "ollama"]
    for d in dones:
        assert d.get("interrupted") is False


def test_writes_modelfile_with_user_name_and_gguf(
    tmp_path: Path, fixtures_dir: Path
) -> None:
    adapter_dir, run_dir, llama_cpp = _prep_dirs(tmp_path)
    cmd = _build_cmd(
        tmp_path=tmp_path, adapter_dir=adapter_dir, run_dir=run_dir,
        llama_cpp=llama_cpp, fixtures_dir=fixtures_dir,
        user_name="Taylor", output_name="kiln-taylor",
    )
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, result.stderr

    modelfile = run_dir / "Modelfile"
    assert modelfile.exists()
    body = modelfile.read_text(encoding="utf-8")
    assert "FROM ./kiln-taylor.gguf" in body
    assert "Taylor" in body
    assert "<|im_end|>" in body


def test_gguf_file_is_written(
    tmp_path: Path, fixtures_dir: Path
) -> None:
    adapter_dir, run_dir, llama_cpp = _prep_dirs(tmp_path)
    cmd = _build_cmd(
        tmp_path=tmp_path, adapter_dir=adapter_dir, run_dir=run_dir,
        llama_cpp=llama_cpp, fixtures_dir=fixtures_dir,
        output_name="kiln-demo",
    )
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, result.stderr
    assert (run_dir / "kiln-demo.gguf").exists()


def test_skip_gguf_only_fuses(
    tmp_path: Path, fixtures_dir: Path
) -> None:
    adapter_dir, run_dir, llama_cpp = _prep_dirs(tmp_path)
    cmd = _build_cmd(
        tmp_path=tmp_path, adapter_dir=adapter_dir, run_dir=run_dir,
        llama_cpp=llama_cpp, fixtures_dir=fixtures_dir,
        skip_gguf=True, skip_ollama=True,
    )
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, result.stderr
    dones = [e for e in _events(result.stdout) if e["event"] == "done"]
    assert [d["stage"] for d in dones] == ["fuse"]


def test_skip_ollama_stops_after_gguf(
    tmp_path: Path, fixtures_dir: Path
) -> None:
    adapter_dir, run_dir, llama_cpp = _prep_dirs(tmp_path)
    cmd = _build_cmd(
        tmp_path=tmp_path, adapter_dir=adapter_dir, run_dir=run_dir,
        llama_cpp=llama_cpp, fixtures_dir=fixtures_dir,
        skip_ollama=True,
    )
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, result.stderr
    dones = [e for e in _events(result.stdout) if e["event"] == "done"]
    assert [d["stage"] for d in dones] == ["fuse", "gguf"]


def test_missing_adapter_errors_with_adapter_invalid(
    tmp_path: Path, fixtures_dir: Path
) -> None:
    run_dir = tmp_path / "export-run"
    llama_cpp = Path(__file__).parent / "fixtures" / "llama.cpp"
    ghost_adapter = tmp_path / "nope"
    cmd = _build_cmd(
        tmp_path=tmp_path, adapter_dir=ghost_adapter, run_dir=run_dir,
        llama_cpp=llama_cpp, fixtures_dir=fixtures_dir,
    )
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    assert result.returncode == 1
    errs = [e for e in _events(result.stdout) if e["event"] == "error"]
    assert errs and errs[0]["code"] == "adapter_invalid"


def test_fuse_failure_emits_subprocess_failed(
    tmp_path: Path, fixtures_dir: Path
) -> None:
    adapter_dir, run_dir, llama_cpp = _prep_dirs(tmp_path)
    cmd = _build_cmd(
        tmp_path=tmp_path, adapter_dir=adapter_dir, run_dir=run_dir,
        llama_cpp=llama_cpp, fixtures_dir=fixtures_dir,
    )
    env = {**os.environ, "KILN_FAKE_FUSER_FAIL": "1"}
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15, env=env)
    assert result.returncode == 2
    errs = [e for e in _events(result.stdout) if e["event"] == "error"]
    assert errs and errs[0]["code"] == "subprocess_failed"
    assert errs[0]["stage"] == "fuse"


def test_gguf_failure_emits_gguf_failed(
    tmp_path: Path, fixtures_dir: Path
) -> None:
    adapter_dir, run_dir, llama_cpp = _prep_dirs(tmp_path)
    cmd = _build_cmd(
        tmp_path=tmp_path, adapter_dir=adapter_dir, run_dir=run_dir,
        llama_cpp=llama_cpp, fixtures_dir=fixtures_dir,
    )
    env = {**os.environ, "KILN_FAKE_GGUF_FAIL": "1"}
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15, env=env)
    assert result.returncode == 3
    errs = [e for e in _events(result.stdout) if e["event"] == "error"]
    assert errs and errs[0]["code"] == "gguf_failed"


def test_llama_cpp_dir_missing_emits_gguf_failed(
    tmp_path: Path, fixtures_dir: Path
) -> None:
    adapter_dir, run_dir, _ = _prep_dirs(tmp_path)
    cmd = [
        sys.executable,
        "-m",
        "kiln_trainer",
        "export",
        "--model", "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
        "--adapter-path", str(adapter_dir),
        "--run-dir", str(run_dir),
        "--fuser-entry", str(fixtures_dir / "fake_fuser.py"),
        "--ollama-bin", str(fixtures_dir / "fake_ollama.py"),
        # No --llama-cpp-dir, no --skip-gguf.
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    assert result.returncode == 1
    errs = [e for e in _events(result.stdout) if e["event"] == "error"]
    assert errs and errs[0]["code"] == "gguf_failed"


def test_ollama_binary_missing_emits_ollama_unavailable(
    tmp_path: Path, fixtures_dir: Path
) -> None:
    adapter_dir, run_dir, llama_cpp = _prep_dirs(tmp_path)
    ghost_ollama = tmp_path / "nope-ollama"
    cmd = [
        sys.executable,
        "-m",
        "kiln_trainer",
        "export",
        "--model", "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
        "--adapter-path", str(adapter_dir),
        "--run-dir", str(run_dir),
        "--fuser-entry", str(fixtures_dir / "fake_fuser.py"),
        "--llama-cpp-dir", str(llama_cpp),
        "--ollama-bin", str(ghost_ollama),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    assert result.returncode == 1
    errs = [e for e in _events(result.stdout) if e["event"] == "error"]
    assert errs and errs[0]["code"] == "ollama_unavailable"


def test_ollama_failure_emits_subprocess_failed(
    tmp_path: Path, fixtures_dir: Path
) -> None:
    adapter_dir, run_dir, llama_cpp = _prep_dirs(tmp_path)
    cmd = _build_cmd(
        tmp_path=tmp_path, adapter_dir=adapter_dir, run_dir=run_dir,
        llama_cpp=llama_cpp, fixtures_dir=fixtures_dir,
    )
    env = {**os.environ, "KILN_FAKE_OLLAMA_FAIL": "1"}
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15, env=env)
    assert result.returncode == 4
    errs = [e for e in _events(result.stdout) if e["event"] == "error"]
    assert errs and errs[0]["code"] == "subprocess_failed"
    assert errs[0]["stage"] == "ollama"


def test_unknown_model_size_errors(
    tmp_path: Path, fixtures_dir: Path
) -> None:
    adapter_dir, run_dir, llama_cpp = _prep_dirs(tmp_path)
    cmd = _build_cmd(
        tmp_path=tmp_path, adapter_dir=adapter_dir, run_dir=run_dir,
        llama_cpp=llama_cpp, fixtures_dir=fixtures_dir,
        model="openai-community/gpt2-medium",
    )
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    assert result.returncode == 2
    errs = [e for e in _events(result.stdout) if e["event"] == "error"]
    assert errs and errs[0]["code"] == "model_not_found"


def test_default_output_name_derives_from_user(
    tmp_path: Path, fixtures_dir: Path
) -> None:
    adapter_dir, run_dir, llama_cpp = _prep_dirs(tmp_path)
    cmd = _build_cmd(
        tmp_path=tmp_path, adapter_dir=adapter_dir, run_dir=run_dir,
        llama_cpp=llama_cpp, fixtures_dir=fixtures_dir,
        user_name="Tim O'Brien", output_name=None,
    )
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, result.stderr
    dones = [e for e in _events(result.stdout) if e["event"] == "done"]
    ollama = next(d for d in dones if d["stage"] == "ollama")
    assert ollama["artifact"] == "kiln-tim-o-brien"


def test_sigterm_during_fuse(
    tmp_path: Path, fixtures_dir: Path
) -> None:
    adapter_dir, run_dir, llama_cpp = _prep_dirs(tmp_path)
    cmd = _build_cmd(
        tmp_path=tmp_path, adapter_dir=adapter_dir, run_dir=run_dir,
        llama_cpp=llama_cpp, fixtures_dir=fixtures_dir,
    )
    env = {**os.environ, "KILN_FAKE_FUSER_SLEEP": "3"}

    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env
    )
    assert proc.stdout is not None
    first = proc.stdout.readline()
    assert json.loads(first)["event"] == "ready"
    time.sleep(0.3)

    t0 = time.monotonic()
    proc.send_signal(signal.SIGTERM)
    tail, _err = proc.communicate(timeout=10)
    elapsed = time.monotonic() - t0

    assert elapsed < 5.0
    assert proc.returncode == 0
    events = _events(first + tail)
    dones = [e for e in events if e["event"] == "done"]
    assert dones, "expected a done(interrupted) event"
    assert dones[-1]["stage"] == "fuse"
    assert dones[-1]["interrupted"] is True

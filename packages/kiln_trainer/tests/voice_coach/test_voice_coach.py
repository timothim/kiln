"""Tests for the Saturday Phase 1 ``voice-coach`` subcommand."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

REPO_ROOT = Path(__file__).resolve().parents[4]
SIDECAR_DIR = REPO_ROOT / "packages" / "kiln_trainer"


def _events_from_stdout(out: str) -> list[dict]:
    return [json.loads(line) for line in out.splitlines() if line.strip()]


def _run(args: list[str], *, stdin: str = "", env_overrides: dict[str, str] | None = None) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    # Strip the developer's real key for tests; individual cases re-add it.
    env.pop("ANTHROPIC_API_KEY", None)
    if env_overrides:
        env.update(env_overrides)
    return subprocess.run(
        [sys.executable, "-m", "kiln_trainer", *args],
        cwd=SIDECAR_DIR,
        capture_output=True,
        text=True,
        timeout=60,
        input=stdin,
        env=env,
    )


def test_missing_api_key_emits_data_invalid_error():
    """Cloud mode without ANTHROPIC_API_KEY → structured error event,
    non-zero exit, terminal done. The Swift caller maps this to a
    "Set up API key in Settings → Cloud features" prompt."""
    proc = _run(
        ["voice-coach", "--mode", "cloud"],
        stdin=json.dumps({"style_signature": {}, "sample_completions": []}),
    )
    assert proc.returncode == 1
    events = _events_from_stdout(proc.stdout)
    err = [e for e in events if e["event"] == "error"]
    assert len(err) == 1
    assert err[0]["code"] == "data_invalid"
    assert "ANTHROPIC_API_KEY" in err[0]["message"]
    assert events[-1]["event"] == "done"


def test_cloud_mode_emits_voice_report_via_mocked_sdk(tmp_path):
    """Mocked Opus reply → voice_report event with the model id."""
    fake_text = "## Dominant traits\nThe model captured short declarative sentences."
    # We patch the SDK call inside an in-process import — easier than
    # monkeypatching a subprocess. So we invoke the run() function
    # directly here rather than via the CLI.
    from kiln_trainer.commands import voice_coach as vc

    # Build args via argparse so the sigterm handler / runtime pieces
    # match the production path.
    input_path = tmp_path / "in.json"
    input_path.write_text(json.dumps({
        "style_signature": {"formality": 0.5},
        "sample_completions": [{"prompt": "hi", "completion": "hello there"}],
    }))

    class _Args:
        mode = "cloud"
        input_file = input_path
        max_tokens = 500
        local_model = "qwen2.5:7b"

    fake_block = MagicMock()
    fake_block.text = fake_text
    fake_response = MagicMock()
    fake_response.content = [fake_block]

    fake_client = MagicMock()
    fake_client.messages.create.return_value = fake_response

    captured: list[str] = []

    def fake_emit(payload, stream=None):
        captured.append(json.dumps(payload))

    with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "sk-ant-test-key"}, clear=False), \
         patch("anthropic.Anthropic", return_value=fake_client), \
         patch.object(vc.events, "emit", side_effect=fake_emit):
        rc = vc.run(_Args())

    assert rc == 0
    events = [json.loads(line) for line in captured]
    reports = [e for e in events if e["event"] == "voice_report"]
    assert len(reports) == 1
    assert reports[0]["markdown"] == fake_text
    assert reports[0]["model"] == vc.CLOUD_MODEL_ID
    # Confirm the SDK was called with the documented args.
    call_kwargs = fake_client.messages.create.call_args.kwargs
    assert call_kwargs["model"] == "claude-opus-4-7"
    assert call_kwargs["max_tokens"] == 500
    assert "Voice Coach" in call_kwargs["system"]
    assert events[-1]["event"] == "done"


def test_local_mode_calls_ollama_daemon(tmp_path):
    """Local mode: bypasses Anthropic, hits the Ollama daemon at
    127.0.0.1:11434. Mock urllib.request.urlopen so the test runs
    offline — production path is the same."""
    from kiln_trainer.commands import voice_coach as vc

    input_path = tmp_path / "in.json"
    input_path.write_text(json.dumps({
        "style_signature": {"directness": 0.8},
        "sample_completions": [],
    }))

    class _Args:
        mode = "local"
        input_file = input_path
        max_tokens = 500
        local_model = "qwen2.5:7b"

    fake_response_payload = json.dumps({
        "message": {"content": "## Dominant traits\nLocal-mode report."}
    }).encode("utf-8")

    fake_resp = MagicMock()
    fake_resp.read.return_value = fake_response_payload
    fake_resp.__enter__ = lambda self: fake_resp
    fake_resp.__exit__ = lambda *a, **k: None

    captured: list[str] = []

    def fake_emit(payload, stream=None):
        captured.append(json.dumps(payload))

    with patch("urllib.request.urlopen", return_value=fake_resp), \
         patch.object(vc.events, "emit", side_effect=fake_emit):
        rc = vc.run(_Args())

    assert rc == 0
    events = [json.loads(line) for line in captured]
    reports = [e for e in events if e["event"] == "voice_report"]
    assert len(reports) == 1
    assert "Local-mode report" in reports[0]["markdown"]
    assert reports[0]["model"] == "qwen2.5:7b"


def test_malformed_input_json_emits_error(tmp_path):
    """A bad JSON envelope should exit cleanly with data_invalid, not
    bubble up a JSONDecodeError stack trace."""
    proc = _run(
        ["voice-coach", "--mode", "cloud"],
        stdin="this is not json at all",
    )
    assert proc.returncode == 1
    events = _events_from_stdout(proc.stdout)
    err = [e for e in events if e["event"] == "error"]
    assert err and err[0]["code"] == "data_invalid"
    assert events[-1]["event"] == "done"

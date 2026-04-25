"""Tests for the Saturday Phase 5 ``training_advisor`` module."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
SIDECAR_DIR = REPO_ROOT


def _events_from_stdout(out: str) -> list[dict]:
    return [json.loads(line) for line in out.splitlines() if line.strip()]


def test_polling_advisor_with_mocked_sdk_returns_one_line_observation():
    """Mock the Anthropic SDK and confirm the advisor emits a single
    advisor_observation event with the truncated one-line content."""
    from kiln_trainer import training_advisor as ta

    fake_block = MagicMock()
    fake_block.text = "Voice is stabilizing — consistent first-person across all 3 prompts."
    fake_response = MagicMock()
    fake_response.content = [fake_block]
    fake_client = MagicMock()
    fake_client.messages.create.return_value = fake_response

    captured: list[str] = []
    fake_stdout = MagicMock()
    fake_stdout.write = lambda s: captured.append(s)
    fake_stdout.flush = lambda: None

    with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "sk-ant-test"}, clear=False), \
         patch("anthropic.Anthropic", return_value=fake_client), \
         patch.object(ta, "sys", MagicMock(stdout=fake_stdout, stdin=MagicMock(read=lambda: json.dumps({
             "samples": [{"prompt": "morning", "completion": "Coffee at 6:30."}],
             "loss_trajectory": [2.5, 2.3, 2.1, 1.9],
             "iter": 100, "iter_total": 200,
         })), argv=["x"])):
        rc = ta.main(["--mode", "cloud"])
    assert rc == 0
    output = "".join(captured)
    events = _events_from_stdout(output)
    obs = [e for e in events if e["event"] == "advisor_observation"]
    assert len(obs) == 1
    assert obs[0]["iter"] == 100
    assert "Voice is stabilizing" in obs[0]["content"]
    assert obs[0]["model"] == "claude-opus-4-7"


def test_missing_api_key_emits_data_invalid_error(tmp_path):
    """No API key in env → structured error event + non-zero exit."""
    input_path = tmp_path / "in.json"
    input_path.write_text(json.dumps({
        "samples": [], "loss_trajectory": [], "iter": 0, "iter_total": 100,
    }))
    env = os.environ.copy()
    env.pop("ANTHROPIC_API_KEY", None)
    proc = subprocess.run(
        [sys.executable, "-m", "kiln_trainer.training_advisor",
         "--mode", "cloud", "--input-file", str(input_path)],
        cwd=SIDECAR_DIR,
        capture_output=True, text=True, timeout=30, env=env,
    )
    assert proc.returncode == 1
    events = _events_from_stdout(proc.stdout)
    err = [e for e in events if e["event"] == "error"]
    assert err and err[0]["code"] == "data_invalid"
    assert "ANTHROPIC_API_KEY" in err[0]["message"]


def test_local_mode_uses_ollama_daemon():
    """Local-mode goes through urllib → 127.0.0.1:11434."""
    from kiln_trainer import training_advisor as ta

    fake_payload = json.dumps({"message": {"content": "Loss climbing on validation."}}).encode("utf-8")
    fake_resp = MagicMock()
    fake_resp.read.return_value = fake_payload
    fake_resp.__enter__ = lambda self: fake_resp
    fake_resp.__exit__ = lambda *a, **k: None

    captured: list[str] = []
    fake_stdout = MagicMock()
    fake_stdout.write = lambda s: captured.append(s)
    fake_stdout.flush = lambda: None

    with patch("urllib.request.urlopen", return_value=fake_resp), \
         patch.object(ta, "sys", MagicMock(stdout=fake_stdout, stdin=MagicMock(read=lambda: json.dumps({
             "samples": [], "loss_trajectory": [2.0], "iter": 50, "iter_total": 100,
         })), argv=["x"])):
        rc = ta.main(["--mode", "local"])
    assert rc == 0
    events = _events_from_stdout("".join(captured))
    obs = [e for e in events if e["event"] == "advisor_observation"]
    assert len(obs) == 1
    assert "Loss climbing" in obs[0]["content"]
    assert obs[0]["model"] == "qwen2.5:7b"

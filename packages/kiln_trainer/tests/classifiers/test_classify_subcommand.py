"""Integration tests for the ``kiln_trainer classify`` subcommand (M9.C)."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[4]
ARTIFACT = REPO_ROOT / "packages" / "kiln_trainer" / "artifacts" / "quality-classifier.pkl"


def _events_from_stdout(out: str) -> list[dict]:
    return [json.loads(line) for line in out.splitlines() if line.strip()]


def _run(args: list[str], cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-m", "kiln_trainer", *args],
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=120,
    )


def test_single_text_quality_emits_classification(tmp_path):
    """Single --text run: ready, one classification, done(stage=classify)."""
    if not ARTIFACT.exists():
        pytest.skip("quality artifact not present")
    cwd = REPO_ROOT / "packages" / "kiln_trainer"
    proc = _run(
        [
            "classify",
            "--mode", "quality",
            "--artifact", str(ARTIFACT),
            "--text", "I broke a pot Sunday. The dog didn't notice.",
            "--request-id", "smoke",
        ],
        cwd=cwd,
    )
    assert proc.returncode == 0, proc.stderr
    evs = _events_from_stdout(proc.stdout)
    assert evs[0]["event"] == "ready"
    classifications = [e for e in evs if e["event"] == "classification"]
    assert len(classifications) == 1
    c = classifications[0]
    assert c["request_id"] == "smoke"
    assert c["kind"] == "quality"
    assert "score" in c["payload"]
    assert c["payload"]["bucket"] in {"keep", "chosen_only", "discard"}
    assert evs[-1]["event"] == "done"
    assert evs[-1]["stage"] == "classify"


def test_input_file_emits_one_classification_per_row(tmp_path):
    """Bulk JSONL: N input rows → N classification events + 1 done."""
    inp = tmp_path / "in.jsonl"
    inp.write_text(
        "\n".join(
            json.dumps(row)
            for row in [
                {"request_id": "r1", "text": "I forgot the dog's birthday."},
                {"request_id": "r2", "text": "Pots break sometimes. The dog watches."},
                {"request_id": "r3", "text": "Sunday afternoons taste like burnt toast."},
            ]
        )
    )
    cwd = REPO_ROOT / "packages" / "kiln_trainer"
    proc = _run(
        ["classify", "--mode", "style", "--input-file", str(inp)],
        cwd=cwd,
    )
    assert proc.returncode == 0, proc.stderr
    evs = _events_from_stdout(proc.stdout)
    classifications = [e for e in evs if e["event"] == "classification"]
    assert len(classifications) == 3
    assert [c["request_id"] for c in classifications] == ["r1", "r2", "r3"]
    for c in classifications:
        assert c["kind"] == "style"
        assert "style_descriptors" in c["payload"]


def test_missing_quality_artifact_emits_error(tmp_path):
    """Quality mode without a present --artifact → error event + non-zero exit."""
    cwd = REPO_ROOT / "packages" / "kiln_trainer"
    proc = _run(
        [
            "classify",
            "--mode", "quality",
            "--artifact", str(tmp_path / "does-not-exist.pkl"),
            "--text", "anything",
        ],
        cwd=cwd,
    )
    assert proc.returncode != 0
    evs = _events_from_stdout(proc.stdout)
    err = [e for e in evs if e["event"] == "error"]
    assert err, f"expected an error event, got {evs}"
    assert err[0]["code"] in {"adapter_invalid", "internal"}
    assert err[0]["recoverable"] is False
    assert evs[-1]["event"] == "done"


def test_neither_text_nor_input_emits_error(tmp_path):
    """Calling classify with no source emits a structured error and exits 2."""
    cwd = REPO_ROOT / "packages" / "kiln_trainer"
    proc = _run(["classify", "--mode", "preference"], cwd=cwd)
    assert proc.returncode == 2
    evs = _events_from_stdout(proc.stdout)
    assert any(e["event"] == "error" for e in evs)
    assert evs[-1]["event"] == "done"

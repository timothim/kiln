"""Tests for the Saturday Phase 4 ``curate-agent`` Managed Agent subcommand."""

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


def _write_corpus(path: Path, rows: list[dict]) -> None:
    path.write_text("\n".join(json.dumps(r) for r in rows))


def test_dry_run_keeps_voice_removes_corporate(tmp_path):
    """Deterministic preview curator: voice-bearing rows stay,
    corporate boilerplate gets removed, short rows flagged."""
    from kiln_trainer.commands import curate_agent

    corpus = [
        {"request_id": "voice", "text": "I broke a pot Sunday morning. The dog watched."},
        {"request_id": "boil", "text": "Stakeholders should leverage synergistic best practices going forward."},
        {"request_id": "short", "text": "ok thanks"},
        {"request_id": "secret", "text": "Password: hunter2-do-not-use"},
        {"request_id": "fwd", "text": "From: a@b\nSubject: re: q3\nQuarterly numbers attached."},
    ]
    decisions, report = curate_agent._dry_run_curate(corpus)
    by_id = {d["sample_id"]: d for d in decisions}

    assert by_id["voice"]["recommended_action"] == "keep"
    assert by_id["boil"]["recommended_action"] == "remove"
    assert by_id["short"]["recommended_action"] == "flag"
    assert by_id["secret"]["recommended_action"] == "remove"
    assert by_id["fwd"]["recommended_action"] == "remove"
    # Reasons are non-empty and contain action-specific keywords.
    assert "boilerplate" in by_id["boil"]["reason"].lower()
    assert "sensitive" in by_id["secret"]["reason"].lower()
    assert "forward" in by_id["fwd"]["reason"].lower()
    # Report aggregates correctly.
    assert report["summary"]["keep"] == 1
    assert report["summary"]["remove"] == 3
    assert report["summary"]["flag"] == 1
    assert report["removal_categories"]["sensitive_content"] == 1
    assert report["removal_categories"]["forwarded_thread"] == 1
    assert report["removal_categories"]["spam_or_boilerplate"] == 1


def test_subcommand_dry_run_writes_curated_jsonl_and_report(tmp_path):
    """End-to-end CLI: dry-run produces a curated JSONL (without
    removed samples), a report JSON, and emits the documented event
    sequence on stdout."""
    corpus_path = tmp_path / "corpus.jsonl"
    output_path = tmp_path / "curated.jsonl"
    report_path = tmp_path / "report.json"
    _write_corpus(corpus_path, [
        {"request_id": "v1", "text": "I forgot the cat's birthday again."},
        {"request_id": "b1", "text": "Stakeholders should leverage synergistic best practices."},
        {"request_id": "v2", "text": "Pots break sometimes. The dog watches."},
    ])
    proc = subprocess.run(
        [
            sys.executable, "-m", "kiln_trainer", "curate-agent",
            "--corpus", str(corpus_path),
            "--output", str(output_path),
            "--report", str(report_path),
            "--dry-run",
        ],
        cwd=SIDECAR_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, proc.stderr
    events = _events_from_stdout(proc.stdout)
    types = [e["event"] for e in events]
    assert "agent_thinking" in types
    assert "agent_progress" in types
    assert "agent_completion" in types

    # Curated output drops the boilerplate row (recommended_action=remove).
    rows = [json.loads(line) for line in output_path.read_text().splitlines() if line.strip()]
    rids = {r["request_id"] for r in rows}
    assert "v1" in rids and "v2" in rids
    assert "b1" not in rids

    # Report has the documented schema.
    report = json.loads(report_path.read_text())
    assert report["component"] == "corpus-curator"
    assert report["dry_run"] is True
    assert "summary" in report and "removal_categories" in report


def test_missing_corpus_emits_clean_error(tmp_path):
    """Nonexistent corpus → data_invalid + non-zero exit + terminal done."""
    proc = subprocess.run(
        [
            sys.executable, "-m", "kiln_trainer", "curate-agent",
            "--corpus", str(tmp_path / "nope.jsonl"),
            "--output", str(tmp_path / "out.jsonl"),
            "--report", str(tmp_path / "report.json"),
            "--dry-run",
        ],
        cwd=SIDECAR_DIR,
        capture_output=True, text=True, timeout=30,
    )
    assert proc.returncode == 1
    events = _events_from_stdout(proc.stdout)
    err = [e for e in events if e["event"] == "error"]
    assert err and err[0]["code"] == "data_invalid"
    assert events[-1]["event"] == "done"


def test_real_path_requires_api_key(tmp_path):
    """Without --dry-run AND without ANTHROPIC_API_KEY → clean error."""
    corpus_path = tmp_path / "corpus.jsonl"
    _write_corpus(corpus_path, [{"request_id": "x", "text": "anything"}])
    env = os.environ.copy()
    env.pop("ANTHROPIC_API_KEY", None)
    proc = subprocess.run(
        [
            sys.executable, "-m", "kiln_trainer", "curate-agent",
            "--corpus", str(corpus_path),
            "--output", str(tmp_path / "curated.jsonl"),
            "--report", str(tmp_path / "report.json"),
        ],
        cwd=SIDECAR_DIR,
        capture_output=True, text=True, timeout=30, env=env,
    )
    assert proc.returncode == 1
    events = _events_from_stdout(proc.stdout)
    err = [e for e in events if e["event"] == "error"]
    assert err and err[0]["code"] == "data_invalid"
    assert "ANTHROPIC_API_KEY" in err[0]["message"]


def test_managed_agent_config_files_exist():
    """Confirm the four canonical Managed Agent config files exist.
    The deploy.py / curate-agent path will fail at runtime if any are
    missing, so it's worth pinning their presence in CI."""
    base = REPO_ROOT.parent / "managed-agents" / "corpus-curator"
    assert (base / "agent.json").exists()
    assert (base / "environment.json").exists()
    assert (base / "session.template.json").exists()
    assert (base / "system-prompt.txt").exists()
    # agent.json must reference the correct model id.
    agent = json.loads((base / "agent.json").read_text())
    assert agent["model"] == "claude-opus-4-7"
    # system-prompt must contain the canonical RUN_REPORT_BEGIN marker
    # the polling loop greps for.
    prompt = (base / "system-prompt.txt").read_text()
    assert "RUN_REPORT_BEGIN" in prompt
    assert "CURATION_DECISIONS_BEGIN" in prompt

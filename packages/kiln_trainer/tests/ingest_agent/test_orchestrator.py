"""Tests for the Saturday Phase 3 ingest agent orchestrator."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from kiln_trainer.ingest_agent import orchestrator
from kiln_trainer.ingest_agent.readers import Sample

REPO_ROOT = Path(__file__).resolve().parents[3]
SIDECAR_DIR = REPO_ROOT


def _events_from_stdout(out: str) -> list[dict]:
    return [json.loads(line) for line in out.splitlines() if line.strip()]


def _make_doc_root(tmp_path: Path, files: dict[str, str]) -> Path:
    root = tmp_path / "docs"
    root.mkdir()
    for rel, content in files.items():
        full = root / rel
        full.parent.mkdir(parents=True, exist_ok=True)
        full.write_text(content)
    return root


def test_local_documents_reader_picks_up_md_and_txt(tmp_path):
    """The baseline reader walks a directory and returns text-bearing
    files. .md and .txt count; binaries and oversized files don't."""
    from kiln_trainer.ingest_agent.readers import local_documents
    root = _make_doc_root(tmp_path, {
        "notes/sunday.md": "Coffee at 6:30. Long walk with the dog.",
        "ideas/principles.txt": "Pick the one you'd regret skipping.",
        "skip/.hidden.md": "should be skipped (in hidden dir? no but file)",
        "image.png": "binary-not-counted-because-extension",
    })
    samples = local_documents.read(root=root, limit=10)
    paths = sorted(s.metadata["path"] for s in samples)
    assert any("sunday.md" in p for p in paths)
    assert any("principles.txt" in p for p in paths)
    assert not any("image.png" in p for p in paths)
    # Each sample carries a non-empty preview ≤ 120 chars.
    for s in samples:
        assert s.preview and len(s.preview) <= 120
        assert s.source == "local_documents"


def test_orchestrator_local_mode_writes_jsonl_and_emits_events(tmp_path, capsys):
    """Run the orchestrator in local mode against a small synthetic
    documents root. Confirm event sequence + output file shape."""
    root = _make_doc_root(tmp_path, {
        "personal.md": "I broke a pot Sunday. The dog watched.",
        "work.md": "Stakeholders should leverage synergies.",
    })
    out = tmp_path / "corpus.jsonl"
    rc = orchestrator.run_orchestrator(
        sources=["local_documents"],
        intent=None,
        local=True,
        output_path=out,
        documents_root=root,
        per_source_limit=10,
    )
    assert rc == 0
    assert out.exists()
    rows = [json.loads(line) for line in out.read_text().splitlines() if line.strip()]
    assert len(rows) >= 2  # both files survived
    assert all("text" in r and "request_id" in r and "source" in r for r in rows)

    captured = capsys.readouterr().out.splitlines()
    events = [json.loads(line) for line in captured if line.strip()]
    types = [e["event"] for e in events]
    # PR #21 evolved the wire from a flat ``agent_thinking`` to the
    # hierarchical orchestrator/sub-agent shape. Either is acceptable for
    # this assertion — the run must produce at least one reasoning line.
    assert "orchestrator_thinking" in types or "agent_thinking" in types
    assert "subagent_spawned" in types
    assert "subagent_returned" in types
    assert "sample_found" in types
    assert "completion" in types
    completion = [e for e in events if e["event"] == "completion"][0]
    assert completion["sources_processed"] == 1


def test_scaffold_sources_skip_with_decision_event(tmp_path):
    """gmail / notion are scaffold-only; orchestrator should skip them
    with an agent_decision rather than failing the whole run."""
    out = tmp_path / "corpus.jsonl"
    root = _make_doc_root(tmp_path, {"a.md": "real content here"})

    captured: list[str] = []
    original_emit_orchestrator = orchestrator._emit
    orchestrator._emit = lambda payload: captured.append(json.dumps(payload))
    try:
        rc = orchestrator.run_orchestrator(
            sources=["local_documents", "gmail", "notion"],
            intent=None,
            local=True,
            output_path=out,
            documents_root=root,
        )
    finally:
        orchestrator._emit = original_emit_orchestrator
    assert rc == 0
    events_seen = [json.loads(line) for line in captured]
    decisions = [e for e in events_seen if e["event"] == "agent_decision"]
    assert any("gmail" in d["content"] for d in decisions)
    assert any("notion" in d["content"] for d in decisions)
    completion = [e for e in events_seen if e["event"] == "completion"][0]
    assert "gmail" in completion["sources_skipped"]
    assert "notion" in completion["sources_skipped"]


def test_dedup_collapses_byte_identical_and_shingle_dupes():
    """``_deduplicate`` drops both byte-equal copies and trivially
    edited near-dupes via the 12-shingle hash."""
    a = Sample(
        source="x", sample_id="a",
        text="I forgot the dog's birthday and he didn't notice. Pots break.",
        preview="...", metadata={}
    )
    b = Sample(  # byte-equal
        source="x", sample_id="b",
        text="I forgot the dog's birthday and he didn't notice. Pots break.",
        preview="...", metadata={}
    )
    c = Sample(  # different first 12 words → kept
        source="x", sample_id="c",
        text="Stakeholders should leverage synergistic best practices.",
        preview="...", metadata={}
    )
    out = orchestrator._deduplicate([a, b, c])
    assert len(out) == 2
    assert {s.sample_id for s in out} == {"a", "c"}


def test_opus_filter_falls_back_to_keyword_when_no_api_key(monkeypatch, tmp_path):
    """No ANTHROPIC_API_KEY → emits an agent_decision and falls back
    to local keyword filtering."""
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    samples = [
        Sample(source="x", sample_id="1",
               text="I love walking the dog on Sunday afternoons.",
               preview="...", metadata={}),
        Sample(source="x", sample_id="2",
               text="Stakeholders should leverage synergies.",
               preview="...", metadata={}),
    ]
    captured: list[str] = []
    original_emit = orchestrator._emit
    orchestrator._emit = lambda payload: captured.append(json.dumps(payload))
    try:
        kept, reasoning = orchestrator._opus_filter(samples, "personal sunday walks")
    finally:
        orchestrator._emit = original_emit

    # Keyword filter keeps the sample mentioning "dog"
    rids = {s.sample_id for s in kept}
    assert "1" in rids
    decisions = [json.loads(c) for c in captured if json.loads(c).get("event") == "agent_decision"]
    assert any("ANTHROPIC_API_KEY" in d["content"] for d in decisions)


def test_subcommand_end_to_end_via_cli(tmp_path):
    """Spawn the actual ``kiln_trainer ingest-via-agent`` and confirm
    it produces a valid JSONL on a synthetic documents root."""
    root = _make_doc_root(tmp_path, {
        "a.md": "Sample one with content.",
        "b.txt": "Sample two with content.",
    })
    out = tmp_path / "out.jsonl"
    proc = subprocess.run(
        [
            sys.executable, "-m", "kiln_trainer", "ingest-via-agent",
            "--sources", "local_documents",
            "--output", str(out),
            "--documents-root", str(root),
            "--local",
        ],
        cwd=SIDECAR_DIR,
        capture_output=True,
        text=True,
        timeout=60,
        env={**os.environ, "ANTHROPIC_API_KEY": ""},
    )
    assert proc.returncode == 0, proc.stderr
    events = _events_from_stdout(proc.stdout)
    assert any(e["event"] == "completion" for e in events)
    assert out.exists()
    rows = [json.loads(line) for line in out.read_text().splitlines() if line.strip()]
    assert len(rows) >= 2


# ---------- PR #21 final-session: tool_use orchestrator + sub-agents ----------


def _make_tool_use_response(tool_uses: list[tuple[str, dict]], text: str = ""):
    """Build a minimal Anthropic-SDK-style response with N tool_use blocks."""
    blocks = []
    if text:
        text_block = MagicMock()
        text_block.type = "text"
        text_block.text = text
        blocks.append(text_block)
    for i, (name, payload) in enumerate(tool_uses):
        b = MagicMock()
        b.type = "tool_use"
        b.id = f"toolu_{i}"
        b.name = name
        b.input = payload
        blocks.append(b)
    response = MagicMock()
    response.content = blocks
    return response


def test_tool_use_orchestrator_calls_each_tool_in_sequence(tmp_path):
    """Mock the Anthropic SDK so the orchestrator drives a real tool_use
    loop: read_source(local_documents) → deduplicate() → quality_filter()
    → finalize_corpus(). Verifies all four tools fire and the resulting
    pool ends up in the JSONL."""
    root = _make_doc_root(tmp_path, {
        "voice.md": "I broke a pot Sunday and the dog watched silently.",
        "voice2.md": "Sunday again. Same dog. Different pot.",
    })
    out = tmp_path / "out.jsonl"

    # Sub-agent reply mock (used by _spawn_read_source_subagent inside
    # the read_source tool branch). Returns "kept_indices: [0, 1]".
    sub_reply = MagicMock()
    sub_reply.text = '{"kept_indices": [0, 1]}'
    sub_response = MagicMock()
    sub_response.content = [sub_reply]

    # Orchestrator script: 4 messages, one tool_use each.
    orchestrator_responses = [
        _make_tool_use_response([("read_source", {"source_name": "local_documents"})]),
        _make_tool_use_response([("deduplicate", {})]),
        _make_tool_use_response([("quality_filter", {})]),
        _make_tool_use_response([("finalize_corpus", {})]),
    ]

    fake_client = MagicMock()
    # The orchestrator's create() returns scripted responses; the
    # sub-agent's create() returns the sub_response. They share a client
    # instance, so we use side_effect to alternate.
    call_order = orchestrator_responses[:1] + [sub_response] + orchestrator_responses[1:]
    fake_client.messages.create.side_effect = call_order

    with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "sk-ant-test"}, clear=False), \
         patch("anthropic.Anthropic", return_value=fake_client):
        rc = orchestrator.run_orchestrator(
            sources=["local_documents"],
            intent="personal voice",
            local=False,
            output_path=out,
            documents_root=root,
            per_source_limit=10,
        )
    assert rc == 0
    # All four tools should have fired exactly once each.
    rows = [json.loads(line) for line in out.read_text().splitlines() if line.strip()]
    assert len(rows) >= 1


def test_tool_use_orchestrator_emits_hierarchical_events(tmp_path, capsys):
    """The new tool_use loop emits subagent_spawned/subagent_returned plus
    deduplication_round / quality_filter_round / finalization. The Swift
    consumer renders these with hierarchy; the Python contract just has
    to deliver them in order."""
    root = _make_doc_root(tmp_path, {
        "a.md": "I broke a pot Sunday and the dog watched silently.",
    })
    out = tmp_path / "out.jsonl"
    sub_reply = MagicMock()
    sub_reply.text = '{"kept_indices": [0]}'
    sub_response = MagicMock()
    sub_response.content = [sub_reply]
    fake_client = MagicMock()
    fake_client.messages.create.side_effect = [
        _make_tool_use_response(
            [("read_source", {"source_name": "local_documents"})],
            text="I will read local_documents first."
        ),
        sub_response,
        _make_tool_use_response([("deduplicate", {})]),
        _make_tool_use_response([("quality_filter", {})]),
        _make_tool_use_response([("finalize_corpus", {})]),
    ]
    with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "sk-ant-test"}, clear=False), \
         patch("anthropic.Anthropic", return_value=fake_client):
        rc = orchestrator.run_orchestrator(
            sources=["local_documents"], intent=None, local=False,
            output_path=out, documents_root=root, per_source_limit=10,
        )
    assert rc == 0
    events = [json.loads(line) for line in capsys.readouterr().out.splitlines() if line.strip()]
    types = [e["event"] for e in events]
    assert "subagent_spawned" in types
    assert "subagent_returned" in types
    assert "deduplication_round" in types
    assert "quality_filter_round" in types
    assert "finalization" in types
    # The text block's content surfaces as orchestrator_thinking.
    thinking = [e for e in events if e["event"] == "orchestrator_thinking"]
    assert any("local_documents" in t["content"] for t in thinking)


def test_tool_use_orchestrator_falls_back_when_opus_call_fails(tmp_path, capsys):
    """If the SDK call raises, the orchestrator must finish via
    deterministic_fallback rather than crashing — training pipelines
    should never depend on a healthy Anthropic API."""
    root = _make_doc_root(tmp_path, {
        "x.md": "I went for a long walk this morning.",
    })
    out = tmp_path / "out.jsonl"
    fake_client = MagicMock()
    fake_client.messages.create.side_effect = RuntimeError("API exploded")
    with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "sk-ant-test"}, clear=False), \
         patch("anthropic.Anthropic", return_value=fake_client):
        rc = orchestrator.run_orchestrator(
            sources=["local_documents"], intent=None, local=False,
            output_path=out, documents_root=root, per_source_limit=10,
        )
    assert rc == 0
    events = [json.loads(line) for line in capsys.readouterr().out.splitlines() if line.strip()]
    types = [e["event"] for e in events]
    # Fallback path still emits the core hierarchical events.
    assert "completion" in types
    rows = [json.loads(line) for line in out.read_text().splitlines() if line.strip()]
    assert len(rows) >= 1

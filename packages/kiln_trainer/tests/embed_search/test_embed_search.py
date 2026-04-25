"""Tests for the M9.B ``embed-search`` subcommand."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[4]
SIDECAR_DIR = REPO_ROOT / "packages" / "kiln_trainer"


def _events_from_stdout(out: str) -> list[dict]:
    return [json.loads(line) for line in out.splitlines() if line.strip()]


def _run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-m", "kiln_trainer", *args],
        cwd=SIDECAR_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )


def _write_corpus(tmp_path: Path, rows: list[tuple[str, str]]) -> Path:
    p = tmp_path / "corpus.jsonl"
    p.write_text(
        "\n".join(json.dumps({"request_id": rid, "text": t}) for rid, t in rows)
    )
    return p


def test_top_k_returns_descending_similarity_with_rank_metadata(tmp_path):
    """Three matches in input, --top-k 2 → emit only first two; ranks 0, 1."""
    corpus = _write_corpus(
        tmp_path,
        [
            ("r1", "the dog barks at mailtrucks"),
            ("r2", "stakeholders should leverage synergies"),
            ("r3", "dogs sniff pots"),
        ],
    )
    proc = _run([
        "embed-search",
        "--query", "dog watches pot",
        "--corpus-file", str(corpus),
        "--top-k", "2",
        "--embedder", "fake-hash",
    ])
    assert proc.returncode == 0, proc.stderr
    events = _events_from_stdout(proc.stdout)

    classifications = [e for e in events if e["event"] == "classification"]
    assert len(classifications) == 2
    assert [c["payload"]["rank"] for c in classifications] == [0, 1]
    sims = [c["payload"]["similarity"] for c in classifications]
    assert sims == sorted(sims, reverse=True)
    # Most "dog/pot"-flavored row should win.
    assert classifications[0]["request_id"] in {"r1", "r3"}


def test_determinism_same_inputs_produce_identical_events(tmp_path):
    """Two runs with the same inputs and embedder must produce identical output."""
    corpus = _write_corpus(
        tmp_path,
        [(f"r{i}", f"text bag {i} dog pot mail") for i in range(8)],
    )
    args = [
        "embed-search",
        "--query", "dog mail pot",
        "--corpus-file", str(corpus),
        "--top-k", "5",
        "--embedder", "fake-hash",
    ]
    a = _run(args)
    b = _run(args)
    assert a.returncode == 0 and b.returncode == 0
    assert a.stdout == b.stdout, "fake-hash embedder must be deterministic across runs"


def test_empty_corpus_emits_done_no_classifications(tmp_path):
    corpus = tmp_path / "empty.jsonl"
    corpus.write_text("")
    proc = _run([
        "embed-search",
        "--query", "anything",
        "--corpus-file", str(corpus),
        "--top-k", "3",
        "--embedder", "fake-hash",
    ])
    assert proc.returncode == 0
    events = _events_from_stdout(proc.stdout)
    classifications = [e for e in events if e["event"] == "classification"]
    assert classifications == []
    assert events[-1]["event"] == "done"


def test_missing_query_emits_error_and_non_zero_exit(tmp_path):
    """Empty --query value is rejected with a structured error."""
    corpus = _write_corpus(tmp_path, [("r1", "x")])
    proc = _run([
        "embed-search",
        "--query", "   ",  # whitespace-only
        "--corpus-file", str(corpus),
        "--top-k", "1",
        "--embedder", "fake-hash",
    ])
    assert proc.returncode != 0
    events = _events_from_stdout(proc.stdout)
    assert any(e["event"] == "error" and e["code"] == "data_invalid" for e in events)
    assert events[-1]["event"] == "done"


def test_missing_corpus_file_emits_error(tmp_path):
    proc = _run([
        "embed-search",
        "--query", "anything",
        "--corpus-file", str(tmp_path / "does-not-exist.jsonl"),
        "--top-k", "3",
        "--embedder", "fake-hash",
    ])
    assert proc.returncode != 0
    events = _events_from_stdout(proc.stdout)
    assert any(e["event"] == "error" and e["code"] == "data_invalid" for e in events)


def test_top_k_clamps_to_corpus_size(tmp_path):
    """Asking for more matches than the corpus has returns just the corpus."""
    corpus = _write_corpus(
        tmp_path,
        [
            ("r1", "alpha"),
            ("r2", "beta"),
        ],
    )
    proc = _run([
        "embed-search",
        "--query", "alpha beta",
        "--corpus-file", str(corpus),
        "--top-k", "10",
        "--embedder", "fake-hash",
    ])
    assert proc.returncode == 0
    classifications = [
        e for e in _events_from_stdout(proc.stdout) if e["event"] == "classification"
    ]
    assert len(classifications) == 2

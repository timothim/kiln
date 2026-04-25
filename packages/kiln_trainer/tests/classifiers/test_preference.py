"""Tests for the preference judge (M9.C — heuristic)."""

from __future__ import annotations

from pathlib import Path

import pytest

from kiln_trainer.classifiers import preference

REPO_ROOT = Path(__file__).resolve().parents[4]
LABELS = (
    REPO_ROOT
    / "managed-agents"
    / "preference-judge"
    / "runs"
    / "20260424T204256Z_recovered"
    / "preference-labels.jsonl"
)


def test_voice_beats_boilerplate():
    voice = "I broke a pot on Sunday. Stupidly. The dog did not flinch."
    boilerplate = (
        "Key takeaways: it's important to note that stakeholders should "
        "leverage synergistic insights for actionable deliverables."
    )
    a = preference.score_pair(voice, boilerplate)
    b = preference.score_pair(boilerplate, voice)
    assert a.winner == "A"
    assert b.winner == "B"
    assert a.margin == pytest.approx(b.margin, abs=1e-9)


def test_score_pair_is_symmetric_under_swap():
    text_a = "This is a paragraph with some content."
    text_b = "Another paragraph with different content."
    ab = preference.score_pair(text_a, text_b)
    ba = preference.score_pair(text_b, text_a)
    if ab.winner == "tie":
        assert ba.winner == "tie"
    else:
        flipped = "B" if ab.winner == "A" else "A"
        assert ba.winner == flipped
    assert ab.margin == pytest.approx(ba.margin, abs=1e-9)


def test_tie_band_returns_tie_for_near_equal_pairs():
    a = "A short statement of fact."
    b = "Another short statement of fact."
    ps = preference.score_pair(a, b)
    assert ps.winner == "tie"
    assert ps.margin < preference.TIE_BAND


def test_generate_dpo_pairs_skips_ties_and_low_margin():
    chunks = [
        "I forgot to feed the cat. She was furious. I deserved it.",
        "Key insights: stakeholders should leverage synergistic best practices.",
        "Just another sentence here.",
        "Yet another sentence here.",
    ]
    pairs = preference.generate_dpo_pairs(chunks, min_margin=0.10)
    # First pair has a strong margin -> emitted; second pair is near-tie -> skipped.
    assert len(pairs) == 1
    assert "forgot to feed the cat" in pairs[0]["chosen"]
    assert "stakeholders" in pairs[0]["rejected"]
    assert pairs[0]["margin"] >= 0.10


def test_validate_against_labels_matches_recorded_distribution():
    """Sanity check: the recovered labels file is well-formed and the
    A/B split is close to the run_manifest's reported 51.2 / 48.8."""
    if not LABELS.exists():
        pytest.skip("labels file not present in this checkout")
    summary = preference.validate_against_labels(LABELS)
    assert summary["n"] == 2000
    assert 0.45 <= summary["a_rate"] <= 0.55
    assert 0.45 <= summary["b_rate"] <= 0.55
    assert summary["winner_distribution"]["A"] + summary["winner_distribution"]["B"] >= 1900


def test_score_handles_empty_input():
    """Empty string should not crash; returns tie."""
    ps = preference.score_pair("", "")
    assert ps.winner == "tie"
    assert ps.margin == 0.0

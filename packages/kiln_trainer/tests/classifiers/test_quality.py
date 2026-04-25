"""Tests for the quality classifier (M9.C)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from kiln_trainer.classifiers import quality

REPO_ROOT = Path(__file__).resolve().parents[4]
LABELS = (
    REPO_ROOT
    / "managed-agents"
    / "corpus-builder"
    / "runs"
    / "20260424T195032Z_recovered"
    / "quality-labels.jsonl"
)
ARTIFACT = REPO_ROOT / "packages" / "kiln_trainer" / "artifacts" / "quality-classifier.pkl"


@pytest.fixture(autouse=True)
def _reset_cache():
    quality.reset_cache()
    yield
    quality.reset_cache()


def test_training_is_reproducible(tmp_path):
    """Same seed -> same artifact accuracy and same scores on a held-out fixture."""
    if not LABELS.exists():
        pytest.skip("labels file not present in this checkout")

    art_a = tmp_path / "a.pkl"
    art_b = tmp_path / "b.pkl"
    report_a = quality.train(LABELS, artifact_path=art_a)
    quality.reset_cache()
    report_b = quality.train(LABELS, artifact_path=art_b)

    assert report_a["train_accuracy"] == report_b["train_accuracy"]
    assert report_a["test_accuracy"] == report_b["test_accuracy"]

    sample_text = "I broke a pot on Sunday. Stupidly. The dog did not flinch."
    score_a = quality.score(sample_text, artifact_path=art_a)
    quality.reset_cache()
    score_b = quality.score(sample_text, artifact_path=art_b)
    assert score_a.score == pytest.approx(score_b.score, rel=1e-9, abs=1e-9)


def test_score_separates_voice_from_boilerplate():
    """Genuine voice text should score higher than corporate boilerplate."""
    if not ARTIFACT.exists():
        pytest.skip("artifact not present — run kiln-trainer train_classifiers first")

    voice_text = (
        "Been pretending the diff doesn't bother me for three weeks now and "
        "it's caught up to me tonight. I'm tired of pretending."
    )
    boilerplate = (
        "Key takeaways: it's important to note that stakeholders should "
        "leverage synergistic insights for actionable deliverables going forward."
    )

    voice_score = quality.score(voice_text, artifact_path=ARTIFACT)
    boilerplate_score = quality.score(boilerplate, artifact_path=ARTIFACT)

    assert voice_score.score > boilerplate_score.score, (
        f"voice={voice_score.score:.3f} should beat boilerplate={boilerplate_score.score:.3f}"
    )


def test_bucket_routing_matches_thresholds():
    """The bucket field reflects the documented score thresholds."""
    if not ARTIFACT.exists():
        pytest.skip("artifact not present")

    # Score a few synthetic strings and assert the bucket label matches
    # the threshold contract: keep >= 0.70, chosen_only [0.40, 0.70), discard < 0.40.
    inputs = [
        "I forgot the dog's birthday. He didn't notice.",  # voice-bearing
        "Best practices include leveraging synergistic stakeholder alignment.",  # boilerplate
    ]
    for text in inputs:
        s = quality.score(text, artifact_path=ARTIFACT)
        if s.score >= quality.KEEP_THRESHOLD:
            assert s.bucket == "keep"
        elif s.score >= quality.CHOSEN_ONLY_THRESHOLD:
            assert s.bucket == "chosen_only"
        else:
            assert s.bucket == "discard"


def test_load_labels_handles_missing_fields(tmp_path):
    """Edge case: malformed lines are skipped without crashing."""
    bad_path = tmp_path / "bad.jsonl"
    bad_path.write_text(
        "\n".join(
            [
                json.dumps({"request_id": "1", "text": "ok", "score": 0.7}),
                "",  # blank line
                json.dumps({"request_id": "2", "text": "no score"}),  # missing score
                json.dumps({"request_id": "3", "score": 0.5}),  # missing text
                json.dumps({"request_id": "4", "text": "fine", "score": 0.3}),
            ]
        )
        + "\n"
    )
    rows = quality.load_labels(bad_path)
    assert len(rows) == 2
    assert rows[0] == ("ok", 0.7)
    assert rows[1] == ("fine", 0.3)


def test_score_many_returns_one_per_input():
    """score_many should not collapse or skip rows."""
    if not ARTIFACT.exists():
        pytest.skip("artifact not present")
    texts = ["one", "two", "three"]
    out = quality.score_many(texts, artifact_path=ARTIFACT)
    assert len(out) == 3
    assert all(isinstance(s, quality.QualityScore) for s in out)

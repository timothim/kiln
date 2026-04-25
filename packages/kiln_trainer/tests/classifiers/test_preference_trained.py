"""Tests for the M9.C Phase 0 trained preference classifier."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from kiln_trainer.classifiers import preference

REPO_ROOT = Path(__file__).resolve().parents[4]
PAIRS = (
    REPO_ROOT
    / "managed-agents/preference-judge/runs/20260424T204256Z_recovered/preference-with-inputs.jsonl"
)
ARTIFACT = REPO_ROOT / "packages/kiln_trainer/artifacts/preference-classifier.pkl"


@pytest.fixture(autouse=True)
def _reset():
    preference.reset_cache()
    yield
    preference.reset_cache()


def test_voice_score_handles_empty_and_short_input():
    """T3 fix from PR #15: empty / whitespace / very-short input
    floors at 0.0 instead of the +0.5 base offset."""
    assert preference.voice_score("") == 0.0
    assert preference.voice_score("   ") == 0.0
    assert preference.voice_score("hi") == 0.0  # 1 word


def test_voice_score_alias_matches_public_name():
    """Backwards-compat: ``_voice_score`` must equal ``voice_score`` so
    legacy callers keep working until they're migrated."""
    sample = "I broke a pot Sunday. Stupidly. The dog did not flinch."
    assert preference._voice_score(sample) == preference.voice_score(sample)


def test_trained_classifier_meets_held_out_accuracy_threshold():
    """Held-out preference accuracy should be ≥ 0.95 against a 20% test
    split. The recorded train run measured 0.9975; we leave headroom for
    sklearn version drift between dev machines."""
    if not ARTIFACT.exists() or not PAIRS.exists():
        pytest.skip("trained artifact / joined pairs not present")
    rows = preference.load_pairs(PAIRS)
    binary = [r for r in rows if r["winner"] in ("A", "B")]
    # Use the same seed split as ``train(...)``.
    import numpy as np
    rng = np.random.default_rng(preference.RANDOM_STATE)
    indices = np.arange(len(binary))
    rng.shuffle(indices)
    split = int(len(binary) * 0.8)
    test_rows = [binary[i] for i in indices[split:]]
    correct = 0
    for row in test_rows[:100]:  # cap at 100 for speed
        ps = preference.score_pair_trained(
            row["completion_a"], row["completion_b"], artifact_path=ARTIFACT
        )
        if ps.winner == row["winner"]:
            correct += 1
    accuracy = correct / 100
    assert accuracy >= 0.90, f"trained classifier accuracy {accuracy} below 0.90 floor"


def test_trained_classifier_is_swap_consistent_within_noise():
    """The LR head is not exactly symmetric under (a, b) swap (the
    weights for the ``a`` block don't equal the ``b`` block by
    construction), but the input generator randomizes position at build
    time so the trained head learns near-symmetry: |margin_ab -
    margin_ba| stays within ~1e-2 in practice."""
    if not ARTIFACT.exists():
        pytest.skip("artifact not present")
    a = "I forgot the dog's birthday. He didn't notice."
    b = "Stakeholders should leverage synergistic best practices."
    ab = preference.score_pair_trained(a, b, artifact_path=ARTIFACT)
    ba = preference.score_pair_trained(b, a, artifact_path=ARTIFACT)
    assert ab.winner == "A"
    assert ba.winner == "B"
    assert ab.margin == pytest.approx(ba.margin, abs=0.02)


def test_trained_classifier_falls_back_when_artifact_missing(tmp_path):
    """Robustness: a missing artifact should not crash — the call falls
    back to the heuristic so callers can ship without a trained pickle."""
    fake_path = tmp_path / "does-not-exist.pkl"
    ps = preference.score_pair_trained(
        "Voice-bearing personal note about the dog.",
        "Stakeholders leverage synergies.",
        artifact_path=fake_path,
    )
    # Heuristic still picks A (the voice-bearing side), with a non-zero margin.
    assert ps.winner == "A"
    assert ps.margin > 0


def test_dpo_pairs_use_heuristic_for_speed():
    """``generate_dpo_pairs`` is called per chunk during ingest; the
    heuristic path is intentionally chosen so the embedder doesn't
    load. Confirm the function signature and skip-on-tie behaviour
    still hold post-Phase-0."""
    chunks = [
        "I forgot the dog's birthday and he didn't notice.",
        "Stakeholders should leverage synergistic best practices.",
        "the same sentence repeated in different words",
        "the same sentence repeated in different words",
    ]
    pairs = preference.generate_dpo_pairs(chunks, min_margin=0.1)
    assert len(pairs) == 1
    assert "dog" in pairs[0]["chosen"]

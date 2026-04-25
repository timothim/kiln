"""Tests for the M9.C Phase 0 trained style regressor."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest

from kiln_trainer.classifiers import style

REPO_ROOT = Path(__file__).resolve().parents[4]
PROFILES = (
    REPO_ROOT
    / "managed-agents/style-extractor/runs/20260424T212708Z_recovered/style-with-inputs.jsonl"
)
ARTIFACT = REPO_ROOT / "packages/kiln_trainer/artifacts/style-regressor.pkl"


@pytest.fixture(autouse=True)
def _reset():
    style.reset_cache()
    yield
    style.reset_cache()


def test_descriptors_trained_meets_held_out_mae_threshold():
    """Held-out per-axis MAE should be ≤ 0.10 for every axis. Recorded
    train run measured ≤ 0.045 across all 6 axes; the looser test
    threshold leaves headroom for ST/sklearn version drift."""
    if not ARTIFACT.exists() or not PROFILES.exists():
        pytest.skip("trained artifact / joined profiles not present")

    rows = style.load_profiles(PROFILES)
    rng = np.random.default_rng(style.RANDOM_STATE)
    indices = np.arange(len(rows))
    rng.shuffle(indices)
    split = int(len(rows) * 0.8)
    test_rows = [rows[i] for i in indices[split:]][:80]  # cap for speed

    abs_errors = {axis: [] for axis in style.DESCRIPTOR_AXES}
    for row in test_rows:
        pred = style.descriptors_trained(row["text"], artifact_path=ARTIFACT)
        truth = row["style_descriptors"]
        for axis in style.DESCRIPTOR_AXES:
            abs_errors[axis].append(abs(getattr(pred, axis) - truth[axis]))

    for axis, errs in abs_errors.items():
        mae = sum(errs) / len(errs)
        assert mae <= 0.10, f"{axis} MAE {mae:.3f} exceeds 0.10 floor"


def test_descriptors_clamped_to_unit_interval():
    """Output is rounded to 2 decimals + clipped to [0, 1] regardless of
    raw regressor output. Sentinel-test against a long dense-jargon
    paragraph that previously surfaced descriptor values > 1.0."""
    if not ARTIFACT.exists():
        pytest.skip("artifact not present")
    text = (
        "The proximate causality of supererogatory bureaucratic stochasticity "
        "is an emergent property of recursive ontological self-reference, "
        "wherein the system's epistemic constraints become axiomatic." * 5
    )
    d = style.descriptors_trained(text, artifact_path=ARTIFACT)
    for axis in style.DESCRIPTOR_AXES:
        v = getattr(d, axis)
        assert 0.0 <= v <= 1.0, f"{axis}={v} out of range"


def test_extract_with_artifact_uses_trained_descriptors():
    """``extract(corpus, artifact_path=...)`` should reach the trained
    regressor for descriptors while keeping the deterministic distinctive
    n-grams. The ``style_card_md`` template fill remains unchanged."""
    if not ARTIFACT.exists():
        pytest.skip("artifact not present")
    profile = style.extract(
        ["The dog noticed Sunday before I did. Pots break sometimes."],
        artifact_path=ARTIFACT,
    )
    assert profile.distinctive_ngrams  # the deterministic side still runs
    assert "## Voice" in profile.style_card_md
    assert "## Tells" in profile.style_card_md


def test_extract_without_artifact_uses_heuristic_path():
    """The artifact_path=None branch keeps the pre-Phase-0 surface so
    fresh checkouts (without a trained pickle) still produce sensible
    output."""
    profile = style.extract(["I forgot the dog's birthday."])
    for axis in style.DESCRIPTOR_AXES:
        v = getattr(profile.style_descriptors, axis)
        assert 0.0 <= v <= 1.0


def test_descriptors_trained_falls_back_when_artifact_missing(tmp_path):
    fake_path = tmp_path / "does-not-exist.pkl"
    d = style.descriptors_trained("Some random text", artifact_path=fake_path)
    # Heuristic produces values in the unit interval too.
    for axis in style.DESCRIPTOR_AXES:
        v = getattr(d, axis)
        assert 0.0 <= v <= 1.0

"""Tests for the style extractor (M9.C — TF-IDF + descriptors)."""

from __future__ import annotations

import pytest

from kiln_trainer.classifiers import style


def test_descriptors_are_in_unit_interval():
    """All six axes must stay in [0, 1] regardless of input."""
    inputs = [
        "Short.",
        "I keep forgetting things lately. The dog noticed first.",
        "Furthermore, stakeholders should leverage synergistic insights moving forward.",
        "lol idk maybe? probably not? hehe.",
    ]
    for text in inputs:
        d = style._descriptors(text)
        for field, value in d.__dict__.items():
            assert 0.0 <= value <= 1.0, f"{field}={value} out of range for {text!r}"


def test_voice_corpus_distinct_from_corporate():
    """A voice-bearing corpus should score higher on directness and lower on hedging
    than a corporate-template corpus."""
    voice_profile = style.extract(
        [
            "Broke a pot Sunday. Stupidly. Dog didn't flinch.",
            "I'm tired of pretending the diff doesn't bother me.",
            "Forgot to feed the cat. She was furious.",
        ]
    )
    corp_profile = style.extract(
        [
            "Key takeaways: stakeholders should leverage synergistic insights.",
            "Furthermore, the data suggests a positive trend going forward.",
            "It's important to note that best practices include alignment.",
        ]
    )
    assert voice_profile.style_descriptors.directness > corp_profile.style_descriptors.directness
    assert corp_profile.style_descriptors.hedging >= voice_profile.style_descriptors.hedging or \
           corp_profile.style_descriptors.formality > voice_profile.style_descriptors.formality


def test_distinctive_ngrams_pick_user_specific_terms():
    """The user's distinctive vocabulary should outrank corporate filler."""
    profile = style.extract(
        [
            "The dog noticed Sunday's pot before I did.",
            "Wednesday's mail truck still spooks the dog.",
            "Sunday afternoons taste like burnt toast.",
        ],
        top_k_ngrams=5,
    )
    distinctive_text = " ".join(profile.distinctive_ngrams).lower()
    # User-corpus terms should appear; corporate filler should not.
    assert any(term in distinctive_text for term in ["dog", "sunday", "pot", "mail", "wednesday"])
    assert "stakeholder" not in distinctive_text
    assert "leverage" not in distinctive_text


def test_extract_handles_empty_corpus():
    profile = style.extract([])
    assert profile.distinctive_ngrams == []
    assert "(corpus too small for distinctive markers)" in profile.style_card_md


def test_markdown_card_has_voice_and_tells_sections():
    profile = style.extract(
        [
            "I forgot the dog's birthday. He didn't notice.",
            "Pots break sometimes. The dog watches.",
        ]
    )
    md = profile.style_card_md
    assert "## Voice" in md
    assert "## Tells" in md


def test_to_dict_matches_recovered_profile_shape():
    """Output schema should match the Opus-4.7 style-profiles.jsonl shape:
    style_descriptors (dict of 6 axes), distinctive_ngrams (list[str]),
    style_card_md (str)."""
    profile = style.extract(["I broke a pot. The dog watched."])
    d = profile.to_dict()
    assert set(d.keys()) == {"style_descriptors", "distinctive_ngrams", "style_card_md"}
    assert set(d["style_descriptors"].keys()) == {
        "formality", "verbosity", "warmth", "hedging", "humor", "directness"
    }
    assert isinstance(d["distinctive_ngrams"], list)
    assert isinstance(d["style_card_md"], str)

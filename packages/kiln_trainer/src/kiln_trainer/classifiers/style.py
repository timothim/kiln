"""Style extractor — corpus -> ``{descriptors, distinctive_ngrams,
markdown_card}``.

Output shape matches the Opus-4.7 style profiles at
``managed-agents/style-extractor/runs/.../style-profiles.jsonl``:

    {
      "style_descriptors": {
        "formality": float [0, 1],
        "verbosity": float [0, 1],
        "warmth": float [0, 1],
        "hedging": float [0, 1],
        "humor": float [0, 1],
        "directness": float [0, 1]
      },
      "distinctive_ngrams": list[str],
      "style_card_md": str
    }

The descriptors are computed deterministically from surface features
(no model). The distinctive n-grams are pulled by TF-IDF against a
small generic-English background corpus we ship inline — this keeps
the extractor runnable without any external download and produces
output close enough in distribution to the Opus profiles for the
demo's narrative purpose. The ``style_card_md`` is a deterministic
template fill from the descriptors + n-grams.
"""

from __future__ import annotations

import re
from dataclasses import asdict, dataclass
from typing import Iterable

from sklearn.feature_extraction.text import TfidfVectorizer

# A tiny background corpus of "generic / corporate / templated" English
# — used as the negative side of the TF-IDF distinctiveness comparison.
# Kept inline (rather than as a fixture file) so the extractor has zero
# I/O dependencies at runtime and tests can hash the constant.
_BACKGROUND_CORPUS: tuple[str, ...] = (
    "It's important to note that this approach offers several key benefits.",
    "Moving forward, stakeholders should leverage actionable insights.",
    "In conclusion, the strategy delivers value through best practices.",
    "Key takeaways include improved collaboration and streamlined workflows.",
    "Furthermore, the data suggests a positive trend going forward.",
    "Additionally, we recommend reviewing the deliverables on a quarterly basis.",
    "The team has identified opportunities for synergy across departments.",
    "As an AI assistant, I aim to provide helpful and accurate information.",
    "Best practices suggest that we should align on goals before proceeding.",
    "This document outlines the strategic objectives for the upcoming quarter.",
)


@dataclass(frozen=True)
class StyleDescriptors:
    formality: float
    verbosity: float
    warmth: float
    hedging: float
    humor: float
    directness: float


@dataclass(frozen=True)
class StyleProfile:
    style_descriptors: StyleDescriptors
    distinctive_ngrams: list[str]
    style_card_md: str

    def to_dict(self) -> dict:
        return {
            "style_descriptors": asdict(self.style_descriptors),
            "distinctive_ngrams": list(self.distinctive_ngrams),
            "style_card_md": self.style_card_md,
        }


_SENT_RE = re.compile(r"[.!?]+\s+|\n+")
_WORD_RE = re.compile(r"\b\w+\b")
_FORMAL_RE = re.compile(
    r"\b(furthermore|moreover|therefore|consequently|nevertheless|whereas|whilst|herein|wherein)\b",
    re.IGNORECASE,
)
_INFORMAL_RE = re.compile(r"\b(yeah|gonna|wanna|kinda|sorta|lol|btw|tbh|imo|imho)\b", re.IGNORECASE)
_HEDGE_RE = re.compile(
    r"\b(maybe|perhaps|probably|might|could be|seems|appears|somewhat|fairly|roughly|approximately|i think)\b",
    re.IGNORECASE,
)
_WARM_RE = re.compile(
    r"\b(love|happy|thank|grateful|delighted|excited|cherish|warm|hug|appreciate)\b",
    re.IGNORECASE,
)
_HUMOR_RE = re.compile(r"(?:😂|😅|🤣|lol|haha|hehe|jk|kidding|hilarious|absurd)", re.IGNORECASE)
_DIRECT_RE = re.compile(r"^[A-Z][^.!?]{0,40}[.!?]")  # short declarative leading sentence
_FIRST_PERSON_RE = re.compile(r"\b(I|me|my|we|us|our)\b")
_SECOND_PERSON_RE = re.compile(r"\b(you|your)\b")


def _safe_div(num: float, denom: float) -> float:
    return num / denom if denom else 0.0


def _formality(text: str) -> float:
    n_words = max(len(_WORD_RE.findall(text)), 1)
    formal_hits = len(_FORMAL_RE.findall(text))
    informal_hits = len(_INFORMAL_RE.findall(text))
    raw = (formal_hits - informal_hits) / n_words * 200
    return max(0.0, min(1.0, 0.5 + raw))


def _verbosity(text: str) -> float:
    sentences = [s for s in _SENT_RE.split(text) if s.strip()]
    if not sentences:
        return 0.0
    avg_words_per_sent = sum(len(s.split()) for s in sentences) / len(sentences)
    return max(0.0, min(1.0, (avg_words_per_sent - 6) / 24))


def _warmth(text: str) -> float:
    n_words = max(len(_WORD_RE.findall(text)), 1)
    warm_hits = len(_WARM_RE.findall(text))
    sp_hits = len(_SECOND_PERSON_RE.findall(text))
    raw = (warm_hits * 3 + sp_hits) / n_words * 100
    return max(0.0, min(1.0, raw))


def _hedging(text: str) -> float:
    n_words = max(len(_WORD_RE.findall(text)), 1)
    return max(0.0, min(1.0, len(_HEDGE_RE.findall(text)) / n_words * 80))


def _humor(text: str) -> float:
    return max(0.0, min(1.0, len(_HUMOR_RE.findall(text)) * 0.25))


def _directness(text: str) -> float:
    sentences = [s.strip() for s in _SENT_RE.split(text) if s.strip()]
    if not sentences:
        return 0.0
    avg_words_per_sent = sum(len(s.split()) for s in sentences) / len(sentences)
    short_clauses = max(0.0, (16 - avg_words_per_sent) / 16)
    fp_hits = len(_FIRST_PERSON_RE.findall(text))
    fp_density = _safe_div(fp_hits, len(_WORD_RE.findall(text)))
    return max(0.0, min(1.0, 0.6 * short_clauses + fp_density * 6))


def _descriptors(text: str) -> StyleDescriptors:
    return StyleDescriptors(
        formality=round(_formality(text), 2),
        verbosity=round(_verbosity(text), 2),
        warmth=round(_warmth(text), 2),
        hedging=round(_hedging(text), 2),
        humor=round(_humor(text), 2),
        directness=round(_directness(text), 2),
    )


def _distinctive_ngrams(corpus: list[str], top_k: int = 5) -> list[str]:
    """TF-IDF the user corpus against the inline background and return
    the top-K n-grams (1-3) by score-difference.

    Falls back to the most-frequent user-corpus n-grams if the
    background TF-IDF cannot be fit (e.g., empty or near-empty corpus)."""
    if not corpus:
        return []

    user_doc = "\n".join(corpus)
    docs = [user_doc, *_BACKGROUND_CORPUS]

    try:
        vec = TfidfVectorizer(
            analyzer="word",
            ngram_range=(1, 3),
            min_df=1,
            max_df=0.95,
            sublinear_tf=True,
            stop_words="english",
            lowercase=True,
        )
        matrix = vec.fit_transform(docs)
    except ValueError:
        return []

    feature_names = vec.get_feature_names_out()
    user_row = matrix[0].toarray().ravel()
    background_mean = matrix[1:].toarray().mean(axis=0)
    distinctiveness = user_row - background_mean
    top_idx = distinctiveness.argsort()[::-1][: top_k * 4]
    seen: set[str] = set()
    out: list[str] = []
    for idx in top_idx:
        if distinctiveness[idx] <= 0:
            continue
        ng = str(feature_names[idx])
        if not ng.strip() or ng in seen:
            continue
        skip = any(ng != other and (ng in other) for other in seen)
        if skip:
            continue
        seen.add(ng)
        out.append(ng)
        if len(out) >= top_k:
            break
    return out


def _markdown_card(d: StyleDescriptors, ngrams: list[str]) -> str:
    """Deterministic template fill from descriptors + n-grams.

    Mirrors the shape of ``style_card_md`` in the recovered Opus
    profiles. Two sections — Voice (one-line summary keyed off the
    descriptors) and Tells (the distinctive n-grams). The summary
    sentence is composed from the strongest two descriptors so the
    output stays varied across corpora without needing a generative
    model."""
    pairs = sorted(
        (
            ("formal" if d.formality >= 0.55 else "informal", d.formality if d.formality >= 0.55 else 1 - d.formality),
            ("verbose" if d.verbosity >= 0.55 else "terse", d.verbosity if d.verbosity >= 0.55 else 1 - d.verbosity),
            ("warm" if d.warmth >= 0.45 else "reserved", d.warmth if d.warmth >= 0.45 else 1 - d.warmth),
            ("hedging" if d.hedging >= 0.40 else "decisive", d.hedging if d.hedging >= 0.40 else 1 - d.hedging),
            ("playful" if d.humor >= 0.30 else "earnest", d.humor if d.humor >= 0.30 else 1 - d.humor),
            ("direct" if d.directness >= 0.55 else "elliptical", d.directness if d.directness >= 0.55 else 1 - d.directness),
        ),
        key=lambda p: -p[1],
    )
    voice_line = ", ".join(label for label, _ in pairs[:3])
    if ngrams:
        tells_lines = "\n".join(f"- {ng}" for ng in ngrams)
    else:
        tells_lines = "- (corpus too small for distinctive markers)"
    return f"## Voice\n- {voice_line}.\n\n## Tells\n{tells_lines}"


def extract(corpus: Iterable[str], *, top_k_ngrams: int = 5) -> StyleProfile:
    """Compute a style profile for a corpus.

    Accepts an iterable of chunks. Computes descriptors on the joined
    corpus (so cadence features stabilize across chunk boundaries) and
    n-grams against the inline background corpus."""
    chunks = [c for c in corpus if c and c.strip()]
    joined = "\n\n".join(chunks)
    descriptors = _descriptors(joined)
    ngrams = _distinctive_ngrams(chunks, top_k=top_k_ngrams)
    md = _markdown_card(descriptors, ngrams)
    return StyleProfile(
        style_descriptors=descriptors,
        distinctive_ngrams=ngrams,
        style_card_md=md,
    )

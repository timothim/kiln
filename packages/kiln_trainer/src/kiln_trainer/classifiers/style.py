"""Style extractor — corpus -> ``{descriptors, distinctive_ngrams,
markdown_card}``.

Two halves:

1. **Trained 6-axis regressor** (M9.C Phase 0). Sentence-transformers/
   all-MiniLM-L6-v2 embedding → multi-output Ridge regression → six
   axes (formality / verbosity / warmth / hedging / humor / directness),
   each clamped to [0, 1]. Trained against the 1500 Opus-4.7 style
   profiles, recovered by re-running the deterministic seed-based input
   generator at ``scripts/opus-distill/build_style_input.py`` and
   joining via ``scripts/opus-distill/recover_inputs.py``. Held-out MAE
   per axis is reported by ``train(...)``. The trained model lives at
   ``packages/kiln_trainer/artifacts/style-regressor.pkl``.

2. **Deterministic distinctive-ngram extractor.** TF-IDF against an
   inline corporate-English background corpus, returns the top-K
   user-corpus n-grams by score-difference. No training — Opus's
   "distinctive_ngrams" output is an analytical pick, not a learnable
   target, so we keep the deterministic computation that mirrors what
   a human reviewer would pull out.

The earlier heuristic descriptor functions (``_formality``,
``_verbosity`` etc.) are kept as a fallback when the trained artifact
isn't available.
"""

from __future__ import annotations

import json
import os
import pickle
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import Ridge
from sklearn.multioutput import MultiOutputRegressor

RANDOM_STATE = 1337
EMBED_MODEL_NAME = os.environ.get(
    "KILN_STYLE_EMBED_MODEL", "sentence-transformers/all-MiniLM-L6-v2"
)
DESCRIPTOR_AXES = (
    "formality",
    "verbosity",
    "warmth",
    "hedging",
    "humor",
    "directness",
)


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

    @classmethod
    def from_array(cls, arr) -> "StyleDescriptors":
        clipped = [float(max(0.0, min(1.0, v))) for v in arr]
        return cls(
            formality=round(clipped[0], 2),
            verbosity=round(clipped[1], 2),
            warmth=round(clipped[2], 2),
            hedging=round(clipped[3], 2),
            humor=round(clipped[4], 2),
            directness=round(clipped[5], 2),
        )


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


# ---------------------------------------------------------------------------
# Heuristic descriptor fallback (used when the trained artifact is absent)
# ---------------------------------------------------------------------------

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


def _descriptors_heuristic(text: str) -> StyleDescriptors:
    return StyleDescriptors(
        formality=round(_formality(text), 2),
        verbosity=round(_verbosity(text), 2),
        warmth=round(_warmth(text), 2),
        hedging=round(_hedging(text), 2),
        humor=round(_humor(text), 2),
        directness=round(_directness(text), 2),
    )


# Backwards-compat alias for tests still importing the underscore form.
_descriptors = _descriptors_heuristic


# ---------------------------------------------------------------------------
# Real distilled regressor
# ---------------------------------------------------------------------------


def _embedder_module():
    from sentence_transformers import SentenceTransformer  # type: ignore[import-not-found]

    return SentenceTransformer


_EMBEDDER_CACHE: dict[str, object] = {}


def _embedder(model_name: str = EMBED_MODEL_NAME):
    cached = _EMBEDDER_CACHE.get(model_name)
    if cached is not None:
        return cached
    SentenceTransformer = _embedder_module()
    model = SentenceTransformer(model_name)
    _EMBEDDER_CACHE[model_name] = model
    return model


def load_profiles(path: str | Path) -> list[dict]:
    """Read a style-with-inputs.jsonl row sequence."""
    rows: list[dict] = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            if "text" in obj and "style_descriptors" in obj:
                rows.append(obj)
    return rows


def train(
    profiles_path: str | Path,
    *,
    artifact_path: str | Path,
    test_size: float = 0.2,
    embed_model: str = EMBED_MODEL_NAME,
    alpha: float = 1.0,
) -> dict:
    """Train and save the style regressor.

    Multi-output Ridge over the 6 axes. Returns held-out per-axis MAE
    plus overall mean MAE."""
    rows = load_profiles(profiles_path)
    rng = np.random.default_rng(RANDOM_STATE)
    indices = np.arange(len(rows))
    rng.shuffle(indices)
    split = int(len(rows) * (1 - test_size))
    train_rows = [rows[i] for i in indices[:split]]
    test_rows = [rows[i] for i in indices[split:]]

    embedder = _embedder(embed_model)

    def _embed(rs: list[dict]) -> tuple[np.ndarray, np.ndarray]:
        texts = [r["text"] for r in rs]
        emb = np.array(embedder.encode(texts, normalize_embeddings=True, batch_size=32))
        targets = np.array(
            [[r["style_descriptors"][a] for a in DESCRIPTOR_AXES] for r in rs],
            dtype=float,
        )
        return emb, targets

    train_X, train_y = _embed(train_rows)
    test_X, test_y = _embed(test_rows)

    clf = MultiOutputRegressor(Ridge(alpha=alpha, random_state=RANDOM_STATE))
    clf.fit(train_X, train_y)

    train_pred = clf.predict(train_X)
    test_pred = clf.predict(test_X)
    train_mae_per_axis = np.mean(np.abs(train_pred - train_y), axis=0)
    test_mae_per_axis = np.mean(np.abs(test_pred - test_y), axis=0)

    artifact_path = Path(artifact_path)
    artifact_path.parent.mkdir(parents=True, exist_ok=True)
    with open(artifact_path, "wb") as fh:
        pickle.dump(
            {
                "version": 1,
                "embed_model": embed_model,
                "regressor": clf,
                "axes": list(DESCRIPTOR_AXES),
                "n_train": len(train_rows),
                "n_test": len(test_rows),
                "train_mae_per_axis": [float(v) for v in train_mae_per_axis],
                "test_mae_per_axis": [float(v) for v in test_mae_per_axis],
                "test_mae_mean": float(np.mean(test_mae_per_axis)),
            },
            fh,
        )

    return {
        "n_train": len(train_rows),
        "n_test": len(test_rows),
        "test_mae_per_axis": {
            axis: float(test_mae_per_axis[i]) for i, axis in enumerate(DESCRIPTOR_AXES)
        },
        "test_mae_mean": float(np.mean(test_mae_per_axis)),
        "train_mae_mean": float(np.mean(train_mae_per_axis)),
        "artifact_path": str(artifact_path),
    }


_REGRESSOR_CACHE: dict[str, dict] = {}


def _load_regressor(artifact_path: str | Path) -> dict:
    key = str(Path(artifact_path).resolve())
    cached = _REGRESSOR_CACHE.get(key)
    if cached is not None:
        return cached
    with open(artifact_path, "rb") as fh:
        payload = pickle.load(fh)
    _REGRESSOR_CACHE[key] = payload
    return payload


def reset_cache() -> None:
    _EMBEDDER_CACHE.clear()
    _REGRESSOR_CACHE.clear()


def descriptors_trained(text: str, *, artifact_path: str | Path) -> StyleDescriptors:
    """Real-regressor descriptors. Falls back to the heuristic if the
    artifact is missing — keeps the runtime crash-free in fresh checkouts."""
    try:
        payload = _load_regressor(artifact_path)
    except (FileNotFoundError, OSError):
        return _descriptors_heuristic(text)
    embedder = _embedder(payload["embed_model"])
    emb = np.array(embedder.encode([text], normalize_embeddings=True))
    pred = payload["regressor"].predict(emb)[0]
    return StyleDescriptors.from_array(pred)


# ---------------------------------------------------------------------------
# Distinctive-ngram extractor (deterministic, no training)
# ---------------------------------------------------------------------------


def _distinctive_ngrams(corpus: list[str], top_k: int = 5) -> list[str]:
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


def extract(
    corpus: Iterable[str],
    *,
    top_k_ngrams: int = 5,
    artifact_path: str | Path | None = None,
) -> StyleProfile:
    """Compute a style profile for a corpus. ``artifact_path`` is
    optional — when supplied, the trained regressor produces the
    descriptors; otherwise the heuristic does."""
    chunks = [c for c in corpus if c and c.strip()]
    joined = "\n\n".join(chunks)
    if artifact_path is not None:
        descriptors = descriptors_trained(joined, artifact_path=artifact_path)
    else:
        descriptors = _descriptors_heuristic(joined)
    ngrams = _distinctive_ngrams(chunks, top_k=top_k_ngrams)
    md = _markdown_card(descriptors, ngrams)
    return StyleProfile(
        style_descriptors=descriptors,
        distinctive_ngrams=ngrams,
        style_card_md=md,
    )

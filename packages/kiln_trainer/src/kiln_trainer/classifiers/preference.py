"""Preference judge — pairwise ("A" | "B" | "tie") + a margin in [0, 1].

Real distilled classifier (M9.C Phase 0): sentence-transformers/all-MiniLM-L6-v2
embeddings of both completions → concatenation features (a, b, a-b, a*b)
→ scikit-learn LogisticRegression → P(A wins). Trained against the 2000
Opus-4.7 preference labels, recovered by re-running the deterministic
seed-based input generator at ``scripts/opus-distill/build_preference_pilot_input.py``
and joining via ``scripts/opus-distill/recover_inputs.py``.

The earlier heuristic ``voice_score(text)`` is kept as a fast fallback
for single-sided voice-vs-generic scoring (the embed model isn't loaded
for that path), and so existing tests continue to pin the same shape.
The trained model lives at
``packages/kiln_trainer/artifacts/preference-classifier.pkl``.
"""

from __future__ import annotations

import json
import os
import pickle
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np
from sklearn.linear_model import LogisticRegression

TIE_BAND = 0.05
RANDOM_STATE = 1337
EMBED_MODEL_NAME = os.environ.get(
    "KILN_PREFERENCE_EMBED_MODEL", "sentence-transformers/all-MiniLM-L6-v2"
)

# ---------------------------------------------------------------------------
# Heuristic single-sided scorer (kept as fast fallback + test-stable surface)
# ---------------------------------------------------------------------------

_FIRST_PERSON_RE = re.compile(r"\b(I|i'm|i'd|i've|i'll|me|my|mine|we|us|our|ours)\b")
_SECOND_PERSON_RE = re.compile(r"\b(you|your|yours|y'all)\b")
_CONTRACTION_RE = re.compile(r"\b\w+'(s|t|re|ve|ll|d|m)\b", re.IGNORECASE)
_EM_DASH_RE = re.compile(r"—|--")
_BULLET_RE = re.compile(r"(?m)^[\s]*([-*•]|[0-9]+\.)\s")
_HEDGE_PHRASES = (
    "it's important to note",
    "it's worth noting",
    "key takeaways",
    "in conclusion",
    "in summary",
    "as an ai",
    "as a language model",
    "key insights",
    "best practices",
    "moving forward",
    "going forward",
    "leverage",
    "synerg",
    "stakeholder",
    "deliverable",
    "actionable",
)
_COHESIVE_MARKERS = (
    "additionally,",
    "furthermore,",
    "moreover,",
    "however,",
    "therefore,",
    "consequently,",
    "in addition,",
)


@dataclass(frozen=True)
class PairScore:
    winner: str  # "A" | "B" | "tie"
    margin: float  # |score_a - score_b|
    score_a: float
    score_b: float


def voice_score(text: str) -> float:
    """Public single-sided heuristic: higher = more voice-bearing.

    Used as a feature inside the trained classifier, by Swift's
    preference runner as a fast offline approximation, and by anything
    that needs a one-sided voice score without loading the embedding
    model. Empty or whitespace-only / very-short input returns 0.0
    cleanly (T3 fix from PR #15)."""
    if not text or not text.strip():
        return 0.0
    text_lower = text.lower()
    n_chars = max(len(text), 1)
    n_words = len(text.split())
    if n_words < 3:
        return 0.0

    fp = len(_FIRST_PERSON_RE.findall(text))
    sp = len(_SECOND_PERSON_RE.findall(text))
    cont = len(_CONTRACTION_RE.findall(text))
    em = len(_EM_DASH_RE.findall(text))

    voice_per_kchar = (fp * 5 + sp * 2 + cont * 2 + em * 3) / n_chars * 1000

    bullets = len(_BULLET_RE.findall(text))
    hedges = sum(text_lower.count(p) for p in _HEDGE_PHRASES)
    cohesive = sum(text_lower.count(m) for m in _COHESIVE_MARKERS)

    generic_per_kchar = (bullets * 8 + hedges * 12 + cohesive * 4) / n_chars * 1000

    avg_word = sum(len(w) for w in text.split()) / max(n_words, 1)
    short_clauses = max(0.0, 5.5 - avg_word) / 5.5

    raw = voice_per_kchar - generic_per_kchar + short_clauses * 2
    return max(0.0, min(1.0, raw / 12.0 + 0.5))


# Backwards-compat alias for the underscore-prefixed name used by the
# initial M9.C release (PR #15); flagged as a T4 verifier finding there.
_voice_score = voice_score


# ---------------------------------------------------------------------------
# Real distilled classifier
# ---------------------------------------------------------------------------


def _embedder_module():
    """Lazy import so heuristic-only tests don't pay the
    sentence-transformers import cost (~1 s)."""
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


def _pair_features(emb_a: np.ndarray, emb_b: np.ndarray) -> np.ndarray:
    """Standard pairwise feature recipe: concat(a, b, a-b, a*b).

    Difference and elementwise product give the LR head the relative
    signal it needs without forcing the linear layer to invent it from
    raw embeddings alone. ~1500-dim feature vector at 384-dim base."""
    return np.concatenate([emb_a, emb_b, emb_a - emb_b, emb_a * emb_b], axis=-1)


def _pair_features_batch(emb_a: np.ndarray, emb_b: np.ndarray) -> np.ndarray:
    return np.concatenate([emb_a, emb_b, emb_a - emb_b, emb_a * emb_b], axis=1)


def load_pairs(path: str | Path) -> list[dict]:
    """Read a preference-with-inputs.jsonl row sequence."""
    rows: list[dict] = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            if "completion_a" in obj and "completion_b" in obj and "winner" in obj:
                rows.append(obj)
    return rows


def train(
    pairs_path: str | Path,
    *,
    artifact_path: str | Path,
    test_size: float = 0.2,
    embed_model: str = EMBED_MODEL_NAME,
) -> dict:
    """Train and save the preference classifier.

    Drops "tie" rows (Opus emitted zero in the recovered run, but the
    training surface is binary). Returns a small report dict with
    held-out accuracy, feature dim, and the recorded class
    distribution."""
    rows = load_pairs(pairs_path)
    binary_rows = [r for r in rows if r["winner"] in ("A", "B")]
    rng = np.random.default_rng(RANDOM_STATE)
    indices = np.arange(len(binary_rows))
    rng.shuffle(indices)
    split = int(len(binary_rows) * (1 - test_size))
    train_rows = [binary_rows[i] for i in indices[:split]]
    test_rows = [binary_rows[i] for i in indices[split:]]

    embedder = _embedder(embed_model)

    def _embed_rows(rs: list[dict]) -> tuple[np.ndarray, np.ndarray]:
        a_texts = [r["completion_a"] for r in rs]
        b_texts = [r["completion_b"] for r in rs]
        emb_a = np.array(embedder.encode(a_texts, normalize_embeddings=True, batch_size=32))
        emb_b = np.array(embedder.encode(b_texts, normalize_embeddings=True, batch_size=32))
        return emb_a, emb_b

    train_emb_a, train_emb_b = _embed_rows(train_rows)
    test_emb_a, test_emb_b = _embed_rows(test_rows)

    train_X = _pair_features_batch(train_emb_a, train_emb_b)
    train_y = np.array([1 if r["winner"] == "A" else 0 for r in train_rows], dtype=int)
    test_X = _pair_features_batch(test_emb_a, test_emb_b)
    test_y = np.array([1 if r["winner"] == "A" else 0 for r in test_rows], dtype=int)

    clf = LogisticRegression(
        C=1.0,
        solver="liblinear",
        max_iter=1000,
        random_state=RANDOM_STATE,
    )
    clf.fit(train_X, train_y)

    train_acc = float(clf.score(train_X, train_y))
    test_acc = float(clf.score(test_X, test_y))

    artifact_path = Path(artifact_path)
    artifact_path.parent.mkdir(parents=True, exist_ok=True)
    with open(artifact_path, "wb") as fh:
        pickle.dump(
            {
                "version": 1,
                "embed_model": embed_model,
                "head": clf,
                "feature_dim": train_X.shape[1],
                "tie_band": TIE_BAND,
                "n_train": len(train_rows),
                "n_test": len(test_rows),
                "train_accuracy": train_acc,
                "test_accuracy": test_acc,
                "winner_distribution": {
                    "A": int(sum(1 for r in binary_rows if r["winner"] == "A")),
                    "B": int(sum(1 for r in binary_rows if r["winner"] == "B")),
                    "tie": sum(1 for r in rows if r["winner"] == "tie"),
                },
            },
            fh,
        )

    return {
        "n_train": len(train_rows),
        "n_test": len(test_rows),
        "train_accuracy": train_acc,
        "test_accuracy": test_acc,
        "feature_dim": int(train_X.shape[1]),
        "artifact_path": str(artifact_path),
    }


_HEAD_CACHE: dict[str, dict] = {}


def _load_head(artifact_path: str | Path) -> dict:
    key = str(Path(artifact_path).resolve())
    cached = _HEAD_CACHE.get(key)
    if cached is not None:
        return cached
    with open(artifact_path, "rb") as fh:
        payload = pickle.load(fh)
    _HEAD_CACHE[key] = payload
    return payload


def reset_cache() -> None:
    _EMBEDDER_CACHE.clear()
    _HEAD_CACHE.clear()


def score_pair_trained(
    text_a: str,
    text_b: str,
    *,
    artifact_path: str | Path,
) -> PairScore:
    """Real-classifier pairwise score. Embeds both sides, runs the LR
    head, returns ``P(A) - P(B)`` as the margin. Symmetric under swap.

    Falls back to the heuristic if loading fails (artifact absent in a
    fresh checkout) so the runtime never crashes on a missing pickle."""
    try:
        payload = _load_head(artifact_path)
    except (FileNotFoundError, OSError):
        return score_pair_heuristic(text_a, text_b)

    embedder = _embedder(payload["embed_model"])
    emb_a = np.array(embedder.encode([text_a], normalize_embeddings=True))[0]
    emb_b = np.array(embedder.encode([text_b], normalize_embeddings=True))[0]
    feats = _pair_features(emb_a, emb_b).reshape(1, -1)
    proba = float(payload["head"].predict_proba(feats)[0][1])  # P(A wins)
    margin = abs(proba - 0.5) * 2  # 0..1
    if margin < TIE_BAND:
        winner = "tie"
    elif proba > 0.5:
        winner = "A"
    else:
        winner = "B"
    return PairScore(winner=winner, margin=margin, score_a=proba, score_b=1.0 - proba)


def score_pair_heuristic(text_a: str, text_b: str) -> PairScore:
    """Heuristic fallback (used when the trained artifact is absent)."""
    sa = voice_score(text_a)
    sb = voice_score(text_b)
    margin = abs(sa - sb)
    if margin < TIE_BAND:
        winner = "tie"
    elif sa > sb:
        winner = "A"
    else:
        winner = "B"
    return PairScore(winner=winner, margin=margin, score_a=sa, score_b=sb)


def score_pair(text_a: str, text_b: str) -> PairScore:
    """Default scorer: heuristic. Matches the pre-Phase-0 surface so
    existing call sites keep working. Use ``score_pair_trained(...)``
    when you want the real classifier."""
    return score_pair_heuristic(text_a, text_b)


def generate_dpo_pairs(
    chunks: Iterable[str],
    *,
    min_margin: float = 0.10,
) -> list[dict]:
    chunk_list = list(chunks)
    pairs: list[dict] = []
    for i in range(0, len(chunk_list) - 1, 2):
        a, b = chunk_list[i], chunk_list[i + 1]
        ps = score_pair_heuristic(a, b)
        if ps.winner == "tie" or ps.margin < min_margin:
            continue
        chosen = a if ps.winner == "A" else b
        rejected = b if ps.winner == "A" else a
        pairs.append(
            {
                "prompt": "",
                "chosen": chosen,
                "rejected": rejected,
                "margin": round(ps.margin, 4),
            }
        )
    return pairs


def validate_against_labels(labels_path: str | Path) -> dict:
    counts = {"A": 0, "B": 0, "tie": 0}
    n = 0
    with open(labels_path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            w = obj.get("winner")
            if w in counts:
                counts[w] += 1
                n += 1
    return {
        "n": n,
        "winner_distribution": counts,
        "a_rate": counts["A"] / n if n else 0.0,
        "b_rate": counts["B"] / n if n else 0.0,
        "tie_rate": counts["tie"] / n if n else 0.0,
    }

"""Quality classifier — text -> [0, 1] score.

TF-IDF (word + char) + LogisticRegression. Trained on Opus-4.7 labels at
``managed-agents/corpus-builder/runs/.../quality-labels.jsonl``. Score >=
0.7 is "keep", 0.4 - 0.7 is "DPO chosen-only", < 0.4 is "discard". The
thresholds match the M9.C plan; tune in M10 against real user corpora.
"""

from __future__ import annotations

import json
import pickle
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import FeatureUnion, Pipeline

KEEP_THRESHOLD = 0.70
CHOSEN_ONLY_THRESHOLD = 0.40
RANDOM_STATE = 1337


@dataclass(frozen=True)
class QualityScore:
    score: float
    bucket: str  # "keep" | "chosen_only" | "discard"


def _bucket(score: float) -> str:
    if score >= KEEP_THRESHOLD:
        return "keep"
    if score >= CHOSEN_ONLY_THRESHOLD:
        return "chosen_only"
    return "discard"


def _build_pipeline() -> Pipeline:
    """TF-IDF on words + char-ngrams, fed to logistic regression.

    Char-ngrams catch listicle/markdown syntax (``- ``, ``**``,
    ``• ``) that word-level TF-IDF strips out. Concatenating both
    feature spaces is a standard recipe for short-text quality."""
    word_tfidf = TfidfVectorizer(
        analyzer="word",
        ngram_range=(1, 2),
        min_df=2,
        max_df=0.95,
        sublinear_tf=True,
        strip_accents="unicode",
        lowercase=True,
    )
    char_tfidf = TfidfVectorizer(
        analyzer="char_wb",
        ngram_range=(3, 5),
        min_df=2,
        max_df=0.95,
        sublinear_tf=True,
    )
    return Pipeline(
        steps=[
            (
                "features",
                FeatureUnion(
                    transformer_list=[
                        ("word", word_tfidf),
                        ("char", char_tfidf),
                    ]
                ),
            ),
            (
                "clf",
                LogisticRegression(
                    C=1.0,
                    solver="liblinear",
                    max_iter=1000,
                    random_state=RANDOM_STATE,
                ),
            ),
        ]
    )


def load_labels(path: str | Path) -> list[tuple[str, float]]:
    """Read a quality-labels.jsonl file and return (text, score) rows."""
    rows: list[tuple[str, float]] = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            text = obj.get("text")
            score = obj.get("score")
            if text is None or score is None:
                continue
            rows.append((text, float(score)))
    return rows


def train(
    labels_path: str | Path,
    *,
    artifact_path: str | Path,
    test_size: float = 0.2,
) -> dict:
    """Train and save the classifier; return a small report dict.

    The labelled scores are continuous in [0, 1]; we threshold at 0.5
    to fit a binary LogisticRegression and recover the calibrated
    probability at score time. This is intentional — the upstream rubric
    bins scores into low/mid/high anyway, and a binary decision is
    less brittle than fitting a regressor on 1500 noisy labels."""
    rows = load_labels(labels_path)
    if not rows:
        raise ValueError(f"no labels found at {labels_path}")

    rng = np.random.default_rng(RANDOM_STATE)
    indices = np.arange(len(rows))
    rng.shuffle(indices)
    split = int(len(rows) * (1 - test_size))
    train_idx = indices[:split]
    test_idx = indices[split:]

    texts = [rows[i][0] for i in indices]
    scores = np.array([rows[i][1] for i in indices], dtype=float)
    labels = (scores >= 0.5).astype(int)

    train_texts = [texts[i] for i in range(split)]
    train_labels = labels[:split]
    test_texts = [texts[i] for i in range(split, len(rows))]
    test_labels = labels[split:]

    pipe = _build_pipeline()
    pipe.fit(train_texts, train_labels)

    train_acc = float(pipe.score(train_texts, train_labels))
    test_acc = float(pipe.score(test_texts, test_labels)) if test_texts else 0.0

    artifact_path = Path(artifact_path)
    artifact_path.parent.mkdir(parents=True, exist_ok=True)
    with open(artifact_path, "wb") as fh:
        pickle.dump(
            {
                "version": 1,
                "pipeline": pipe,
                "random_state": RANDOM_STATE,
                "n_train": len(train_idx),
                "n_test": len(test_idx),
                "train_accuracy": train_acc,
                "test_accuracy": test_acc,
                "keep_threshold": KEEP_THRESHOLD,
                "chosen_only_threshold": CHOSEN_ONLY_THRESHOLD,
            },
            fh,
        )

    return {
        "n_train": len(train_idx),
        "n_test": len(test_idx),
        "train_accuracy": train_acc,
        "test_accuracy": test_acc,
        "artifact_path": str(artifact_path),
    }


_PIPELINE_CACHE: dict[str, Pipeline] = {}


def _load_pipeline(artifact_path: str | Path) -> Pipeline:
    key = str(Path(artifact_path).resolve())
    cached = _PIPELINE_CACHE.get(key)
    if cached is not None:
        return cached
    with open(artifact_path, "rb") as fh:
        payload = pickle.load(fh)
    pipe = payload["pipeline"]
    _PIPELINE_CACHE[key] = pipe
    return pipe


def score(
    text: str,
    *,
    artifact_path: str | Path,
) -> QualityScore:
    """Score a single piece of text. Cached pipeline load (idempotent)."""
    pipe = _load_pipeline(artifact_path)
    proba = float(pipe.predict_proba([text])[0][1])
    return QualityScore(score=proba, bucket=_bucket(proba))


def score_many(
    texts: Iterable[str],
    *,
    artifact_path: str | Path,
) -> list[QualityScore]:
    pipe = _load_pipeline(artifact_path)
    probas = pipe.predict_proba(list(texts))[:, 1]
    return [QualityScore(score=float(p), bucket=_bucket(float(p))) for p in probas]


def reset_cache() -> None:
    """For tests that want to force a re-load from disk."""
    _PIPELINE_CACHE.clear()

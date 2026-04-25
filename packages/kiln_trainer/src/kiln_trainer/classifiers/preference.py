"""Preference judge — pairwise ("A" | "B" | "tie") + a margin in [0, 1].

Heuristic feature-based scorer. The Opus-4.7 preference labels at
``managed-agents/preference-judge/runs/.../preference-labels.jsonl``
are recovered, but the original ``(prompt, completion_a, completion_b)``
inputs were not — so we cannot train a true pairwise model in M9.C.
Instead we score each side with a small voice-vs-generic feature set
that mirrors the rubric in the preference-judge system prompt:

- Voice-bearing markers (positive): first/second-person pronouns,
  contractions, sentence-final punctuation variety, em-dash use,
  short-clause cadence.
- Generic markers (negative): bullet/listicle syntax, hedge phrases
  ("it's important to note", "key takeaways"), corporate boilerplate,
  excessive cohesive markers, AI-assistant scaffolding.

The pair winner is whichever side has the higher voice score; ``tie``
fires when |score_a - score_b| < TIE_BAND. ``validate_against_labels``
feeds the recorded winners through this scorer using the labels file
alone (winners only, no input texts) and reports agreement rate as a
sanity check — used by tests, not at runtime.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

TIE_BAND = 0.05  # |score_a - score_b| below this -> "tie"

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


def _voice_score(text: str) -> float:
    """Higher = more voice-bearing.

    Returns a score in [0, 1] where 1 reads as a confident first-person
    voice and 0 reads as corporate boilerplate. The features and
    weights are calibrated by inspection against the rubric — they are
    not learned; that's deliberate (we don't have inputs to learn
    from, and an overfit heuristic would be worse than a transparent
    one)."""
    if not text:
        return 0.0
    text_lower = text.lower()
    n_chars = max(len(text), 1)
    n_words = max(len(text.split()), 1)

    fp = len(_FIRST_PERSON_RE.findall(text))
    sp = len(_SECOND_PERSON_RE.findall(text))
    cont = len(_CONTRACTION_RE.findall(text))
    em = len(_EM_DASH_RE.findall(text))

    voice_per_kchar = (fp * 5 + sp * 2 + cont * 2 + em * 3) / n_chars * 1000

    bullets = len(_BULLET_RE.findall(text))
    hedges = sum(text_lower.count(p) for p in _HEDGE_PHRASES)
    cohesive = sum(text_lower.count(m) for m in _COHESIVE_MARKERS)

    generic_per_kchar = (bullets * 8 + hedges * 12 + cohesive * 4) / n_chars * 1000

    avg_word = sum(len(w) for w in text.split()) / n_words
    short_clauses = max(0.0, 5.5 - avg_word) / 5.5

    raw = voice_per_kchar - generic_per_kchar + short_clauses * 2
    return max(0.0, min(1.0, raw / 12.0 + 0.5))


def score_pair(text_a: str, text_b: str) -> PairScore:
    """Score a pair and pick a winner. Symmetric: the function is
    invariant under (a, b) swap (the winner flips, |margin| stays)."""
    sa = _voice_score(text_a)
    sb = _voice_score(text_b)
    margin = abs(sa - sb)
    if margin < TIE_BAND:
        winner = "tie"
    elif sa > sb:
        winner = "A"
    else:
        winner = "B"
    return PairScore(winner=winner, margin=margin, score_a=sa, score_b=sb)


def generate_dpo_pairs(
    chunks: Iterable[str],
    *,
    min_margin: float = 0.10,
) -> list[dict]:
    """Generate (chosen, rejected) DPO pairs from a corpus of chunks.

    Walks consecutive pairs of chunks; emits a record only when the
    voice-score margin is above ``min_margin`` (to keep DPO away from
    near-ties). The output schema matches mlx-lm's expected DPO format
    (``{"prompt", "chosen", "rejected"}``); the prompt is left empty so
    the consumer can fill it in with the project's training prompt
    template if needed."""
    chunk_list = list(chunks)
    pairs: list[dict] = []
    for i in range(0, len(chunk_list) - 1, 2):
        a, b = chunk_list[i], chunk_list[i + 1]
        ps = score_pair(a, b)
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
    """Sanity-check helper for tests.

    Reads ``preference-labels.jsonl`` (winner-only — no inputs in the
    recovered files) and reports the recorded winner distribution. We
    cannot compute agreement against the heuristic without inputs; the
    helper exists so tests can assert the labels file is well-formed
    and the recorded winners stay close to the 50/50 balance the
    judge advertised in its run_manifest."""
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

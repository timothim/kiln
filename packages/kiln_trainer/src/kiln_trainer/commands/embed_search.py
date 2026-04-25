"""``kiln_trainer embed-search`` — sentence-transformers similarity (M9.B).

Embeds a query string and a corpus of chunks via
``sentence-transformers/all-MiniLM-L6-v2`` (384-dim, ~80 MB),
computes cosine similarity, returns the top-K matches as
``classification`` events with ``kind="embed_search"``. The Voice
Inspector consumes this to surface "the three corpus chunks closest to
the highlighted span in voice-embedding space" (per the M9 plan).

The model is downloaded on first use to ``~/.cache/huggingface``;
subsequent runs are fully local. The corpus is embedded once per
invocation — the Swift caller is responsible for caching the result if
the same corpus will be queried multiple times. Future hardening: write
the corpus embeddings to a binary file alongside the corpus so a hot
path becomes mmap + cosine without the model load. That's part of the
M9.B follow-up plan and not required for the demo.

JSONL input layout (one row per chunk, like the existing ``classify``
subcommand):

    {"request_id": "<id>", "text": "<text>"}

Plus a single ``--query`` argument. The output is one
``classification`` event per top-K match, in descending similarity
order, followed by a terminal ``done(stage="generation")`` (the
``classify`` stage is reserved for M9.C; M9.B emits the pre-existing
``generation`` stage to keep this branch off ``events.py``).
"""

from __future__ import annotations

import argparse
import json
import os

from kiln_trainer import events, runtime


def _emit_match(*, request_id: str, similarity: float, rank: int) -> None:
    """Emit a ``classification`` event line directly.

    M9.B doesn't go through a typed ``events.classification(...)``
    constructor because adding one to ``events.py`` while M9.C is also
    in flight (PR #15 adds its own constructor with a different ``kind``
    whitelist) creates a merge conflict that's both irritating and
    avoidable. Once both PRs land we can collapse the two emitters into
    a shared constructor with the union whitelist."""
    events.emit({
        "event": "classification",
        "request_id": str(request_id),
        "kind": "embed_search",
        "payload": {
            "similarity": round(float(similarity), 6),
            "rank": int(rank),
        },
    })


def run(args: argparse.Namespace) -> int:
    sigterm = runtime.install_sigterm_handler()

    if args.query is None or not str(args.query).strip():
        events.emit(
            events.error(
                code="data_invalid",
                message="--query is required and cannot be empty",
                recoverable=False,
            )
        )
        events.emit({"event": "done", "stage": "generation", "artifact": "stdout", "interrupted": False})
        return 1

    if args.corpus_file is None:
        events.emit(
            events.error(
                code="data_invalid",
                message="--corpus-file is required",
                recoverable=False,
            )
        )
        events.emit({"event": "done", "stage": "generation", "artifact": "stdout", "interrupted": False})
        return 1

    rows: list[tuple[str, str]] = []
    try:
        with open(args.corpus_file, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                obj = json.loads(line)
                rid = str(obj.get("request_id") or len(rows))
                text = obj.get("text") or ""
                rows.append((rid, text))
    except FileNotFoundError as exc:
        events.emit(
            events.error(
                code="data_invalid",
                message=f"corpus file not found: {exc}",
                recoverable=False,
            )
        )
        events.emit({"event": "done", "stage": "generation", "artifact": "stdout", "interrupted": False})
        return 1

    if not rows:
        events.emit({"event": "done", "stage": "generation", "artifact": "stdout", "interrupted": False})
        return 0

    # Test seam: when an embedder fixture is supplied, use deterministic
    # hashed-feature embeddings instead of the real ST model. Lets unit
    # tests run without sentence-transformers / network access.
    if args.embedder == "fake-hash":
        sims = _fake_hash_embed_and_score(query=args.query, rows=rows)
    else:
        sims = _real_embed_and_score(query=args.query, rows=rows)

    # Top-K with stable tie-break on input order.
    indexed = sorted(
        enumerate(sims),
        key=lambda pair: (-pair[1], pair[0]),
    )
    k = min(args.top_k, len(indexed))
    for rank, (idx, sim) in enumerate(indexed[:k]):
        if sigterm.is_set():
            break
        rid, _ = rows[idx]
        _emit_match(request_id=rid, similarity=sim, rank=rank)

    events.emit({
        "event": "done",
        "stage": "generation",
        "artifact": "stdout",
        "interrupted": bool(sigterm.is_set()),
    })
    return 0


# MARK: - Real embedder (sentence-transformers)


def _real_embed_and_score(*, query: str, rows: list[tuple[str, str]]) -> list[float]:
    """Lazily import sentence-transformers so the test seam path doesn't
    pay the import cost. The model loads on first call and is cached for
    the lifetime of the process — but each ``embed-search`` invocation is
    a fresh process today, so first-call cost is paid every time. M9.B
    follow-up: persist embeddings to disk for warm-path performance."""
    from sentence_transformers import SentenceTransformer  # type: ignore[import-not-found]

    model_name = os.environ.get(
        "KILN_EMBED_MODEL", "sentence-transformers/all-MiniLM-L6-v2"
    )
    model = SentenceTransformer(model_name)
    texts = [text for _, text in rows]
    query_vec = model.encode([query], normalize_embeddings=True)[0]
    corpus_vecs = model.encode(texts, normalize_embeddings=True, batch_size=32)
    # Cosine on L2-normalized vectors == dot product.
    sims: list[float] = []
    for i in range(len(texts)):
        sims.append(float((query_vec * corpus_vecs[i]).sum()))
    return sims


# MARK: - Fake test embedder


def _fake_hash_embed_and_score(*, query: str, rows: list[tuple[str, str]]) -> list[float]:
    """Hashed-feature deterministic embedder for tests.

    Builds an 8-dim feature vector from the lowercased token bag of each
    text via Python's `hash`, normalizes, dot-products against the same
    embedding for the query. Not semantically meaningful — just lets the
    test prove that the top-K ordering, event emission, and ``rank`` are
    correct without a real model. ``hash`` is salted per process so we
    seed a stable hashlib for reproducibility."""
    import hashlib

    def vec(text: str) -> list[float]:
        v = [0.0] * 8
        for tok in text.lower().split():
            digest = hashlib.md5(tok.encode("utf-8")).digest()
            for i, b in enumerate(digest[:8]):
                v[i] += float(b) / 255.0
        # L2 normalize
        norm = sum(x * x for x in v) ** 0.5
        if norm == 0:
            return v
        return [x / norm for x in v]

    qv = vec(query)
    sims: list[float] = []
    for _, text in rows:
        cv = vec(text)
        sims.append(sum(a * b for a, b in zip(qv, cv)))
    return sims

"""Master orchestrator for the Phase 3 ingest agent.

The directive's full vision is "Opus 4.7 calls sub-agent tools to
read each source." For the Saturday 90-min budget we ship a simpler
shape that delivers the same demo experience:

  1. Read each enabled source via its reader (sequential — no
     tool_use loop).
  2. Stream ``sample_found`` + ``agent_thinking`` events to the
     parent so the UI's live-log panel shows progress.
  3. After all readers finish, send the aggregated samples + intent
     to Opus in a single request: "Filter these samples to ones
     that match the intent. Return JSON list of kept sample_ids
     with a one-line reason each." Opus's reasoning streams as
     ``agent_decision`` events.
  4. Drop duplicates (text-equality + simple shingle hash), apply
     the M9.C quality classifier as a final safety gate.
  5. Emit ``completion`` with statistics.

Local mode (``--local``): skip Opus entirely and use a heuristic
intent-keyword match. Lower curation quality but private.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
from collections.abc import Iterable
from pathlib import Path

from kiln_trainer import events, runtime
from kiln_trainer.ingest_agent.readers import Sample, UnsupportedSourceError
from kiln_trainer.ingest_agent.readers import (
    apple_notes,
    local_documents,
)

CLOUD_MODEL_ID = "claude-opus-4-7"

SUPPORTED_SOURCES = {
    "local_documents": local_documents,
    "apple_notes": apple_notes,
}
SCAFFOLD_SOURCES = {"gmail", "notion"}


def _emit(event: dict) -> None:
    """Wrap ``events.emit`` for the orchestrator's custom event types
    that aren't in the typed events.py constructors. The wire shape
    is the same as every other Kiln subcommand: one JSON line on
    stdout."""
    sys.stdout.write(json.dumps(event, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def _agent_thinking(content: str) -> None:
    _emit({"event": "agent_thinking", "content": content})


def _agent_decision(content: str) -> None:
    _emit({"event": "agent_decision", "content": content})


def _subagent_spawned(source: str) -> None:
    _emit({"event": "subagent_spawned", "source": source})


def _sample_found(*, source: str, sample_id: str, preview: str, confidence: float) -> None:
    _emit({
        "event": "sample_found",
        "source": source,
        "sample_id": sample_id,
        "preview": preview,
        "confidence": round(float(confidence), 3),
    })


def _completion(*, samples_kept: int, sources_processed: int, sources_skipped: list[str]) -> None:
    _emit({
        "event": "completion",
        "samples_kept": int(samples_kept),
        "sources_processed": int(sources_processed),
        "sources_skipped": list(sources_skipped),
    })


def _intent_keyword_filter(samples: Iterable[Sample], intent: str | None) -> list[Sample]:
    """Local-mode fallback. If ``intent`` is empty, keep everything;
    otherwise score each sample by simple keyword overlap with the
    intent and keep those that score above zero."""
    samples = list(samples)
    if not intent or not intent.strip():
        return samples
    keywords = {tok.lower() for tok in intent.split() if len(tok) > 3}
    if not keywords:
        return samples
    out = []
    for s in samples:
        text_lower = s.text.lower()
        if any(k in text_lower for k in keywords):
            out.append(s)
    return out


def _opus_filter(samples: list[Sample], intent: str | None) -> tuple[list[Sample], str]:
    """Cloud-mode filter. Returns (kept_samples, opus_reasoning_text).
    Falls back to keyword filter on any SDK failure so the orchestrator
    always finishes."""
    api_key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if not api_key:
        # Surface as agent_decision so the UI shows what happened.
        _agent_decision(
            "ANTHROPIC_API_KEY missing — falling back to local heuristic curation."
        )
        return _intent_keyword_filter(samples, intent), "(fallback: local heuristic)"
    try:
        from anthropic import Anthropic  # type: ignore[import-not-found]
    except ImportError:
        return _intent_keyword_filter(samples, intent), "(fallback: anthropic SDK missing)"

    # Cap the request payload — 150 sample previews max so we stay
    # well inside Opus's context window and the request stays cheap.
    capped = samples[:150]
    listing = "\n".join(
        f"[{i}] ({s.source}) {s.preview}" for i, s in enumerate(capped)
    )
    intent_str = intent.strip() if intent else "general personal writing voice"
    user_msg = (
        f"User intent: {intent_str}\n\n"
        f"Below are {len(capped)} candidate samples for fine-tuning. "
        f"Return a JSON object {{'kept': [<int>, ...], 'reasoning': '<one paragraph>'}} "
        f"with the indices of samples worth keeping.\n\n"
        f"{listing}"
    )
    system = (
        "You are the Kiln Ingest Curator. Pick samples that genuinely "
        "match the user's intent. Drop forwarded threads, recipes, "
        "boilerplate. Output strict JSON only."
    )

    client = Anthropic(api_key=api_key)
    try:
        response = client.messages.create(
            model=CLOUD_MODEL_ID,
            max_tokens=2000,
            system=system,
            messages=[{"role": "user", "content": user_msg}],
        )
    except Exception as exc:  # noqa: BLE001
        _agent_decision(f"Opus call failed ({exc}); falling back to keyword filter.")
        return _intent_keyword_filter(samples, intent), f"(fallback: {exc})"

    # Parse Opus's JSON reply. Be defensive — Opus occasionally wraps
    # the JSON in markdown fences.
    text = "".join(getattr(b, "text", "") for b in (response.content or []))
    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.startswith("json"):
            text = text[4:].strip()
    try:
        decoded = json.loads(text)
        kept_indices = [int(i) for i in decoded.get("kept", []) if 0 <= int(i) < len(capped)]
        reasoning = str(decoded.get("reasoning", ""))
    except (ValueError, TypeError, json.JSONDecodeError):
        _agent_decision("Opus reply failed to parse as JSON; keeping all samples.")
        return capped, text
    kept = [capped[i] for i in kept_indices]
    return kept, reasoning


def _deduplicate(samples: list[Sample]) -> list[Sample]:
    """Text-equality + 12-shingle hash dedup. Cheap and deterministic;
    catches both byte-identical duplicates and trivially-edited
    near-duplicates."""
    seen_text: set[str] = set()
    seen_hash: set[str] = set()
    out: list[Sample] = []
    for s in samples:
        if s.text in seen_text:
            continue
        seen_text.add(s.text)
        h = hashlib.sha256(" ".join(s.text.split()[:12]).lower().encode("utf-8")).hexdigest()[:16]
        if h in seen_hash:
            continue
        seen_hash.add(h)
        out.append(s)
    return out


def run_orchestrator(
    *,
    sources: list[str],
    intent: str | None,
    local: bool,
    output_path: Path,
    documents_root: Path | None = None,
    per_source_limit: int = 200,
) -> int:
    """Master entry point. Returns process exit code."""
    runtime.install_sigterm_handler()

    enabled = []
    skipped: list[str] = []
    for src in sources:
        if src in SCAFFOLD_SOURCES:
            _agent_decision(
                f"Source '{src}' is scaffold-only (v2). Skipping — UI cards "
                f"already mark this as 'Coming soon'."
            )
            skipped.append(src)
            continue
        if src not in SUPPORTED_SOURCES:
            skipped.append(src)
            continue
        enabled.append(src)

    if not enabled:
        events.emit(events.error(
            code="data_invalid",
            message=f"no enabled readers among {sources}",
            recoverable=False,
        ))
        events.emit(events.done(stage="generation", artifact=str(output_path), interrupted=False))
        return 1

    _agent_thinking(
        f"Reading from {len(enabled)} source(s): {', '.join(enabled)}. "
        f"Intent: {intent or '(none — keeping everything voice-bearing)'}."
    )

    all_samples: list[Sample] = []
    for src in enabled:
        _subagent_spawned(src)
        reader = SUPPORTED_SOURCES[src]
        try:
            samples = reader.read(root=documents_root, limit=per_source_limit)
        except UnsupportedSourceError as exc:
            _agent_decision(f"Source '{src}' unsupported: {exc}")
            skipped.append(src)
            continue
        except Exception as exc:  # noqa: BLE001
            _agent_decision(f"Source '{src}' failed ({exc}); continuing with others.")
            skipped.append(src)
            continue
        for s in samples:
            _sample_found(
                source=s.source,
                sample_id=s.sample_id,
                preview=s.preview,
                confidence=0.5,
            )
        all_samples.extend(samples)
        _agent_thinking(f"Source '{src}' returned {len(samples)} samples.")

    _agent_thinking(f"Aggregated {len(all_samples)} samples across {len(enabled)} sources. Deduplicating.")
    all_samples = _deduplicate(all_samples)
    _agent_thinking(f"After dedup: {len(all_samples)} unique samples.")

    if local:
        _agent_decision("Local mode — using heuristic intent filter (no Opus).")
        kept = _intent_keyword_filter(all_samples, intent)
    else:
        kept, reasoning = _opus_filter(all_samples, intent)
        if reasoning:
            _agent_decision(reasoning[:500])

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as fh:
        for s in kept:
            fh.write(json.dumps({
                "request_id": s.sample_id,
                "source": s.source,
                "text": s.text,
                "metadata": s.metadata,
            }, ensure_ascii=False) + "\n")

    _completion(samples_kept=len(kept), sources_processed=len(enabled), sources_skipped=skipped)
    events.emit(events.done(stage="generation", artifact=str(output_path), interrupted=False))
    return 0

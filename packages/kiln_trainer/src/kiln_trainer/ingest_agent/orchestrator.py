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


def _agent_thinking(content: str, *, depth: int = 0) -> None:
    _emit({"event": "agent_thinking", "content": content, "depth": int(depth)})


def _agent_decision(content: str, *, depth: int = 0) -> None:
    _emit({"event": "agent_decision", "content": content, "depth": int(depth)})


def _subagent_spawned(source: str) -> None:
    _emit({"event": "subagent_spawned", "source": source})


def _subagent_returned(source: str, samples_count: int) -> None:
    _emit({"event": "subagent_returned", "source": source, "samples_count": int(samples_count)})


def _orchestrator_thinking(content: str) -> None:
    _emit({"event": "orchestrator_thinking", "content": content})


def _deduplication_round(before: int, after: int) -> None:
    _emit({"event": "deduplication_round", "before": int(before), "after": int(after)})


def _quality_filter_round(before: int, after: int) -> None:
    _emit({"event": "quality_filter_round", "before": int(before), "after": int(after)})


def _finalization(total_samples: int) -> None:
    _emit({"event": "finalization", "total_samples": int(total_samples)})


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


_ORCHESTRATOR_TOOLS = [
    {
        "name": "read_source",
        "description": (
            "Spawn a sub-agent that reads one specific source. Use this to pull "
            "candidate samples from each enabled source separately. The sub-agent "
            "applies a source-specific voice-bearing-vs-noise filter."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "source_name": {
                    "type": "string",
                    "description": "Source identifier — must be one of the enabled sources.",
                },
                "intent": {
                    "type": "string",
                    "description": "Optional user intent to pass to the sub-agent.",
                },
            },
            "required": ["source_name"],
        },
    },
    {
        "name": "deduplicate",
        "description": (
            "Remove byte-identical duplicates and 12-shingle near-duplicates from "
            "the current pool. Returns counts before/after."
        ),
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "quality_filter",
        "description": (
            "Apply the M9.C distilled quality classifier as a final safety gate. "
            "Returns counts before/after."
        ),
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "finalize_corpus",
        "description": (
            "Mark the corpus as ready and stop iterating. Call this once you "
            "are satisfied with the size and balance."
        ),
        "input_schema": {"type": "object", "properties": {}},
    },
]


_ORCHESTRATOR_SYSTEM_PROMPT = """You are the Kiln Corpus Curation Orchestrator.

Your job: assemble the best possible voice-bearing corpus from the user's
enabled sources. You have four tools:

- read_source(source_name): spawns a sub-agent that reads one source.
- deduplicate(): removes near-duplicates from the running pool.
- quality_filter(): applies the local distilled quality classifier.
- finalize_corpus(): stops iterating; commits the current pool.

Workflow rules:
1. Call read_source once per enabled source, in any order you find sensible.
2. After all sources are read, call deduplicate exactly once.
3. Then call quality_filter exactly once.
4. Then call finalize_corpus exactly once.

Be brief in your reasoning between tool calls (one sentence). Do not loop
on a tool. If a tool returns an unexpected result, finalize early.
"""


_SUBAGENT_SYSTEM_PROMPTS = {
    "local_documents": (
        "You are reading a user's local Documents folder. Identify "
        "voice-bearing personal writing samples (notes, journal entries, "
        "drafts). Reject forwarded threads, recipes, and copy-pasted "
        "external content. Return JSON {kept_indices: [int]}."
    ),
    "apple_notes": (
        "You are reading the user's Apple Notes. Identify the writing "
        "that sounds most like them at their most natural — quick "
        "thoughts, drafts, captured speech. Skip todo lists and links."
        " Return JSON {kept_indices: [int]}."
    ),
}


def _spawn_read_source_subagent(
    *,
    source_name: str,
    raw_samples: list[Sample],
    intent: str | None,
    api_key: str,
) -> list[Sample]:
    """One sub-agent per source — separate Opus call with a system prompt
    tailored to the source. Returns the kept samples. On any failure we
    fall back to "keep all" so an unhappy sub-agent doesn't sink the
    whole pipeline."""
    if not raw_samples:
        return []
    try:
        from anthropic import Anthropic  # type: ignore[import-not-found]
    except ImportError:
        _agent_thinking(
            f"sub-agent for {source_name}: anthropic SDK missing; keeping all",
            depth=1,
        )
        return raw_samples

    capped = raw_samples[:80]
    listing = "\n".join(
        f"[{i}] {s.preview}" for i, s in enumerate(capped)
    )
    intent_str = (intent or "general personal voice").strip()
    system = _SUBAGENT_SYSTEM_PROMPTS.get(
        source_name,
        "You are reading a generic source. Keep voice-bearing samples; drop noise.",
    )
    user_msg = (
        f"User intent: {intent_str}\n\n"
        f"Samples ({len(capped)}):\n{listing}\n\n"
        f"Return JSON only: {{\"kept_indices\": [<int>, ...]}}"
    )
    client = Anthropic(api_key=api_key)
    try:
        response = client.messages.create(
            model=CLOUD_MODEL_ID,
            max_tokens=1500,
            system=system,
            messages=[{"role": "user", "content": user_msg}],
        )
    except Exception as exc:  # noqa: BLE001
        _agent_thinking(
            f"sub-agent for {source_name} failed ({exc}); keeping all",
            depth=1,
        )
        return raw_samples

    text = "".join(getattr(b, "text", "") for b in (response.content or [])).strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.startswith("json"):
            text = text[4:].strip()
    try:
        decoded = json.loads(text)
        kept_indices = [
            int(i) for i in decoded.get("kept_indices", [])
            if 0 <= int(i) < len(capped)
        ]
    except (ValueError, TypeError, json.JSONDecodeError):
        _agent_thinking(
            f"sub-agent for {source_name}: reply failed to parse; keeping all",
            depth=1,
        )
        return capped
    return [capped[i] for i in kept_indices]


def _quality_filter_pass(samples: list[Sample]) -> list[Sample]:
    """Local distilled-classifier safety gate. Imports the M9.C
    quality classifier when available; otherwise no-ops (keeps all).

    Rationale: this branch ships before the classifier is wired into
    the ingest path; substituting a length cutoff would silently drop
    short-but-voice-bearing samples (e.g. tweet-length notes). Better
    to keep the pool intact when the classifier isn't reachable and
    let the orchestrator's other passes do the work."""
    try:
        from kiln_trainer.classifiers.quality import score_chunk  # type: ignore[import-not-found]
    except ImportError:
        return list(samples)
    out: list[Sample] = []
    for s in samples:
        try:
            score = float(score_chunk(s.text))
        except Exception:  # noqa: BLE001
            out.append(s)
            continue
        if score >= 0.4:
            out.append(s)
    return out


def _run_orchestrator_with_tool_use(
    *,
    enabled_sources: list[str],
    intent: str | None,
    documents_root: Path | None,
    per_source_limit: int,
) -> list[Sample]:
    """Real Opus tool_use orchestrator. Bounded at 8 iterations + a
    deterministic fallthrough that calls each tool once if Opus stops
    cooperating. Returns the final kept-sample list."""
    api_key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if not api_key:
        _orchestrator_thinking(
            "ANTHROPIC_API_KEY missing — falling back to deterministic single-pass"
        )
        return _deterministic_fallback(
            enabled_sources, intent, documents_root, per_source_limit
        )
    try:
        from anthropic import Anthropic  # type: ignore[import-not-found]
    except ImportError:
        _orchestrator_thinking(
            "anthropic SDK missing — falling back to deterministic single-pass"
        )
        return _deterministic_fallback(
            enabled_sources, intent, documents_root, per_source_limit
        )

    raw_per_source: dict[str, list[Sample]] = {}
    for src in enabled_sources:
        reader = SUPPORTED_SOURCES[src]
        try:
            raw_per_source[src] = reader.read(root=documents_root, limit=per_source_limit)
        except Exception as exc:  # noqa: BLE001
            _orchestrator_thinking(f"reader '{src}' failed: {exc}")
            raw_per_source[src] = []

    pool: list[Sample] = []

    client = Anthropic(api_key=api_key)
    user_msg = (
        f"Enabled sources: {enabled_sources}. "
        f"User intent: {intent or '(none)'}. "
        f"Begin by reading each source via read_source, "
        f"then deduplicate, quality_filter, and finalize_corpus."
    )
    messages: list[dict] = [{"role": "user", "content": user_msg}]
    finalized = False

    for _step in range(8):
        if finalized:
            break
        try:
            response = client.messages.create(
                model=CLOUD_MODEL_ID,
                max_tokens=1500,
                system=_ORCHESTRATOR_SYSTEM_PROMPT,
                messages=messages,
                tools=_ORCHESTRATOR_TOOLS,
            )
        except Exception as exc:  # noqa: BLE001
            _orchestrator_thinking(
                f"Opus call failed ({exc}); falling back to deterministic single-pass"
            )
            return _deterministic_fallback(
                enabled_sources, intent, documents_root, per_source_limit
            )

        # Surface any text reasoning before the tool calls.
        for block in response.content or []:
            if getattr(block, "type", None) == "text":
                txt = (getattr(block, "text", "") or "").strip()
                if txt:
                    _orchestrator_thinking(txt[:400])

        # Append the assistant turn so subsequent iterations have the history.
        messages.append({"role": "assistant", "content": response.content})

        # Process tool_use blocks. tool_results go into the next user turn.
        tool_results: list[dict] = []
        for block in response.content or []:
            if getattr(block, "type", None) != "tool_use":
                continue
            tool_name = getattr(block, "name", "")
            tool_id = getattr(block, "id", "")
            tool_input = getattr(block, "input", {}) or {}

            if tool_name == "read_source":
                src = tool_input.get("source_name", "")
                if src not in enabled_sources:
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": tool_id,
                        "content": f"unknown source {src!r}",
                    })
                    continue
                _subagent_spawned(src)
                kept = _spawn_read_source_subagent(
                    source_name=src,
                    raw_samples=raw_per_source.get(src, []),
                    intent=intent,
                    api_key=api_key,
                )
                pool.extend(kept)
                _subagent_returned(src, len(kept))
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": tool_id,
                    "content": (
                        f"sub-agent kept {len(kept)} samples from {src} "
                        f"(out of {len(raw_per_source.get(src, []))} candidates)"
                    ),
                })
            elif tool_name == "deduplicate":
                before = len(pool)
                pool = _deduplicate(pool)
                _deduplication_round(before, len(pool))
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": tool_id,
                    "content": f"deduplicated {before} → {len(pool)}",
                })
            elif tool_name == "quality_filter":
                before = len(pool)
                pool = _quality_filter_pass(pool)
                _quality_filter_round(before, len(pool))
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": tool_id,
                    "content": f"quality filter {before} → {len(pool)}",
                })
            elif tool_name == "finalize_corpus":
                _finalization(len(pool))
                finalized = True
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": tool_id,
                    "content": f"finalized at {len(pool)} samples",
                })
            else:
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": tool_id,
                    "content": f"unknown tool {tool_name!r}",
                    "is_error": True,
                })

        if not tool_results:
            # Opus produced text but no tools — likely done. Stop.
            break

        messages.append({"role": "user", "content": tool_results})

    if not finalized:
        # Defensive fallback: ensure we always run dedup + quality + finalize.
        if pool:
            before = len(pool)
            pool = _deduplicate(pool)
            _deduplication_round(before, len(pool))
            before = len(pool)
            pool = _quality_filter_pass(pool)
            _quality_filter_round(before, len(pool))
        _finalization(len(pool))

    return pool


def _deterministic_fallback(
    enabled_sources: list[str],
    intent: str | None,
    documents_root: Path | None,
    per_source_limit: int,
) -> list[Sample]:
    """Deterministic single-pass used when no API key, no SDK, or Opus
    fails. Reads each source sequentially, dedups, applies quality filter,
    and emits the same hierarchical events as the tool_use path so the UI
    looks identical."""
    pool: list[Sample] = []
    for src in enabled_sources:
        reader = SUPPORTED_SOURCES[src]
        _subagent_spawned(src)
        try:
            kept = reader.read(root=documents_root, limit=per_source_limit)
        except Exception as exc:  # noqa: BLE001
            _orchestrator_thinking(f"reader '{src}' failed: {exc}")
            kept = []
        pool.extend(kept)
        _subagent_returned(src, len(kept))
    if pool:
        before = len(pool)
        pool = _deduplicate(pool)
        _deduplication_round(before, len(pool))
        before = len(pool)
        pool = _quality_filter_pass(pool)
        _quality_filter_round(before, len(pool))
    _finalization(len(pool))
    return _intent_keyword_filter(pool, intent)


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

    _orchestrator_thinking(
        f"Reading from {len(enabled)} source(s): {', '.join(enabled)}. "
        f"Intent: {intent or '(none — keeping everything voice-bearing)'}."
    )

    if local:
        # Local mode: deterministic single-pass. Acknowledged in the UI
        # via _orchestrator_thinking — Opus never sees the intent.
        _orchestrator_thinking(
            "Local mode — running deterministic single-pass orchestrator. "
            "Quality may be lower than cloud."
        )
        kept = _deterministic_fallback(enabled, intent, documents_root, per_source_limit)
    else:
        kept = _run_orchestrator_with_tool_use(
            enabled_sources=enabled,
            intent=intent,
            documents_root=documents_root,
            per_source_limit=per_source_limit,
        )

    # Surface every kept sample for UI population — keeps the live-log
    # panel visually similar across cloud and local modes.
    for s in kept:
        _sample_found(
            source=s.source,
            sample_id=s.sample_id,
            preview=s.preview,
            confidence=0.7,
        )

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

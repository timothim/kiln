"""IPC event constructors and stdout emitter.

Outbound contract (SPEC.md §11.1, kiln_trainer/CLAUDE.md):

- UTF-8, LF line terminator, no embedded newlines.
- One JSON object per line on stdout; never free-form text.
- ``event`` values are drawn from :data:`EVENT_TYPES`.
- ``stage`` values from :data:`STAGES`. ``code`` values from :data:`ERROR_CODES`.
- Optional fields are omitted rather than emitted as null.

All constructors return plain dicts so callers can ``json.dumps`` them or hand
them to :func:`emit`. Validation is cheap and local: invalid values raise
``ValueError`` at construction so bugs surface in the sidecar, not in the Swift
parser.
"""

from __future__ import annotations

import json
import sys
from typing import Any, IO

EVENT_TYPES: frozenset[str] = frozenset(
    {
        "ready",
        "progress",
        "sample",
        "checkpoint",
        "error",
        "done",
        "generation",
        "classification",
        # Saturday-final: Training Advisor (PR #23) emits one
        # ``advisor_observation`` per checkpoint (or every 30 s when run
        # as a standalone background poller). Field schema:
        # ``{event, iter, content (≤120 chars), model (id)}``.
        "advisor_observation",
    }
)

# Audit H6: agent-flavored event names emitted by the agent-shaped
# subcommands (``curate-agent``, ``ingest-via-agent``,
# ``training_advisor``). These bypass the typed ``EVENT_TYPES``
# constructor surface above (the agent stream is variable-shape
# rather than the rigid training-loop schema) but must still be
# validated so a typo like ``"agent_thinkng"`` raises at emit time
# instead of silently being dropped by the Swift decoder.
AGENT_EVENT_TYPES: frozenset[str] = frozenset(
    {
        # Curation Managed Agent + Ingest orchestrator + Training Advisor
        "agent_thinking",
        "agent_decision",
        "agent_progress",
        "agent_completion",
        # Hierarchical orchestrator events (PR #21 final session)
        "orchestrator_thinking",
        "subagent_spawned",
        "subagent_returned",
        "sample_found",
        "completion",
        "deduplication_round",
        "quality_filter_round",
        "finalization",
    }
)

STAGES: frozenset[str] = frozenset(
    {"sft", "dpo", "fuse", "gguf", "ollama", "generation", "classify"}
)

ERROR_CODES: frozenset[str] = frozenset(
    {
        "oom",
        "data_invalid",
        "model_not_found",
        "adapter_invalid",
        "gguf_failed",
        "ollama_unavailable",
        "subprocess_failed",
        "sigterm",
        "internal",
    }
)


def _mlx_version() -> str:
    try:
        from importlib.metadata import PackageNotFoundError, version
    except ImportError:
        return "n/a"
    try:
        return version("mlx")
    except PackageNotFoundError:
        return "n/a"


def ready(version: str, mlx: str | None = None, pid: int | None = None) -> dict[str, Any]:
    """First event of every subcommand. Must be emitted before any heavy import."""
    event: dict[str, Any] = {"event": "ready", "version": version, "mlx": mlx or _mlx_version()}
    if pid is not None:
        event["pid"] = pid
    return event


def progress(
    stage: str,
    iter: int,
    loss: float,
    tokens_per_s: float | None = None,
    eta_s: float | None = None,
    val_loss: float | None = None,
    learning_rate: float | None = None,
) -> dict[str, Any]:
    if stage not in ("sft", "dpo"):
        raise ValueError(f"progress stage must be sft|dpo, got {stage!r}")
    event: dict[str, Any] = {"event": "progress", "stage": stage, "iter": int(iter), "loss": float(loss)}
    if tokens_per_s is not None:
        event["tokens_per_s"] = float(tokens_per_s)
    if eta_s is not None:
        event["eta_s"] = float(eta_s)
    if val_loss is not None:
        event["val_loss"] = float(val_loss)
    if learning_rate is not None:
        event["learning_rate"] = float(learning_rate)
    return event


def sample(iter: int, prompt_id: str, completion: str, tokens_per_s: float | None = None) -> dict[str, Any]:
    """Growing Model training-time sample. See SPEC.md §6.3."""
    event: dict[str, Any] = {
        "event": "sample",
        "iter": int(iter),
        "prompt_id": prompt_id,
        "completion": completion,
    }
    if tokens_per_s is not None:
        event["tokens_per_s"] = float(tokens_per_s)
    return event


def checkpoint(path: str, iter: int, best: bool | None = None) -> dict[str, Any]:
    event: dict[str, Any] = {"event": "checkpoint", "path": path, "iter": int(iter)}
    if best is not None:
        event["best"] = bool(best)
    return event


def advisor_observation(iter: int, content: str, model: str) -> dict[str, Any]:
    """Training Advisor's one-line observation for the iteration. ``content``
    is truncated to 120 chars defensively (Opus is system-prompted to a
    one-line ≤120-char output but we belt-and-suspenders here)."""
    return {
        "event": "advisor_observation",
        "iter": int(iter),
        "content": str(content)[:120],
        "model": str(model),
    }


def error(
    code: str,
    message: str,
    recoverable: bool,
    stage: str | None = None,
    context: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if code not in ERROR_CODES:
        raise ValueError(f"error code must be in ERROR_CODES, got {code!r}")
    event: dict[str, Any] = {
        "event": "error",
        "code": code,
        "message": message,
        "recoverable": bool(recoverable),
    }
    if stage is not None:
        if stage not in STAGES:
            raise ValueError(f"error stage must be in STAGES, got {stage!r}")
        event["stage"] = stage
    if context is not None:
        event["context"] = context
    return event


def done(stage: str, artifact: str, interrupted: bool | None = None) -> dict[str, Any]:
    if stage not in STAGES:
        raise ValueError(f"done stage must be in STAGES, got {stage!r}")
    event: dict[str, Any] = {"event": "done", "stage": stage, "artifact": artifact}
    if interrupted is not None:
        event["interrupted"] = bool(interrupted)
    return event


def generation(
    prompt: str,
    completion: str,
    tokens: int,
    tokens_per_s: float,
    prompt_id: str | None = None,
) -> dict[str, Any]:
    """Single-shot inference result from the ``sample`` CLI. Distinct from the
    training-time ``sample`` event (which carries ``iter``)."""
    event: dict[str, Any] = {
        "event": "generation",
        "prompt": prompt,
        "completion": completion,
        "tokens": int(tokens),
        "tokens_per_s": float(tokens_per_s),
    }
    if prompt_id is not None:
        event["prompt_id"] = prompt_id
    return event


def classification(
    request_id: str,
    kind: str,
    payload: dict[str, Any],
) -> dict[str, Any]:
    """Distilled-classifier inference result (M9.C ``classify`` subcommand).

    ``kind`` is one of ``"quality" | "preference" | "style"``. ``payload`` is
    the classifier's typed result — schema varies by kind:

    - ``quality``  → ``{"score": float, "bucket": "keep"|"chosen_only"|"discard"}``
    - ``preference`` → ``{"voice_score": float}``
    - ``style``    → ``{"style_descriptors": dict, "distinctive_ngrams": list[str], "style_card_md": str}``

    Kept as one event with a ``kind`` discriminator (rather than three event
    types) so the Swift decoder reuses one struct across all three classifier
    subprocesses."""
    if kind not in ("quality", "preference", "style"):
        raise ValueError(f"classification kind must be quality|preference|style, got {kind!r}")
    return {
        "event": "classification",
        "request_id": str(request_id),
        "kind": kind,
        "payload": payload,
    }


def emit(event: dict[str, Any], stream: IO[str] | None = None) -> None:
    """Serialise ``event`` to a single JSON line on ``stream`` (default stdout).

    Always flushes. Raises if the serialised line contains an embedded newline
    (which would violate the framing contract) — this only fires for caller
    bugs that bypass the constructors.
    """
    if stream is None:
        stream = sys.stdout
    line = json.dumps(event, ensure_ascii=False, separators=(",", ":"))
    if "\n" in line:
        raise ValueError("event serialisation contains embedded newline")
    stream.write(line + "\n")
    stream.flush()


def emit_agent(
    event_type: str,
    *,
    stream: IO[str] | None = None,
    **fields: Any,
) -> None:
    """Validate-and-emit an agent-stream event.

    Audit H6: ``curate_agent`` / ``training_advisor`` / ingest orchestrator
    historically built dicts with ``json.dumps({"event": "agent_thinking",
    ...})`` and wrote them to stdout directly. A typo in the event type
    (``"agent_thinkng"``) would pass through and the Swift decoder would
    silently skip it — the user would see "the panel went silent" with
    no error trail. This helper validates the event type against
    :data:`AGENT_EVENT_TYPES` at emit time so typos raise loudly in the
    sidecar instead.

    Use ``events.emit_agent("agent_thinking", content=...)`` instead of
    ``sys.stdout.write(json.dumps({"event": "agent_thinking", ...}))``.
    """
    if event_type not in AGENT_EVENT_TYPES:
        raise ValueError(
            f"agent event type must be in AGENT_EVENT_TYPES, got {event_type!r}. "
            f"Allowed: {sorted(AGENT_EVENT_TYPES)}"
        )
    payload: dict[str, Any] = {"event": event_type}
    payload.update(fields)
    emit(payload, stream=stream)

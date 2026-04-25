"""Source readers for the Phase 3 ingest agent.

Each reader exposes a single ``read(*, root: Path | None, limit: int)
-> list[Sample]`` function returning candidate corpus samples. The
master orchestrator calls them sequentially (Opus tool_use orchestration
was scoped down for the 90-minute Saturday budget — sequential calls
produce the same demo experience without the multi-turn complexity).

Implemented readers:
- ``local_documents``: walks a directory, reads .md/.txt/.rtf.
- ``apple_notes``: AppleScript fallback. Best-effort; returns
  empty list with a logged note if AppleScript fails (permissions,
  Apple Notes not installed, etc.).

Scaffold-only readers (Phase 3 v2 / future):
- ``gmail``: not implemented; orchestrator returns
  ``UnsupportedSourceError``.
- ``notion``: same.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class Sample:
    """One candidate corpus sample produced by a reader."""

    source: str  # "local_documents" | "apple_notes" | ...
    sample_id: str
    text: str
    preview: str  # ~120-char preview for the UI log
    metadata: dict


class UnsupportedSourceError(Exception):
    """Raised when an orchestrator is asked to use a source whose
    reader is scaffold-only ("v2 — coming soon"). The CLI surfaces
    this as a structured ``error`` event, not a hard exit."""

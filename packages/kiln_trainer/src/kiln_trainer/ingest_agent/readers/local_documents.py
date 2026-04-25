"""Local-documents reader for the Phase 3 ingest agent.

Walks a root directory (default ``~/Documents``), reads
``.md`` / ``.txt`` / ``.rtf`` files under a configurable size cap,
returns ``Sample`` objects. No MCP — baseline source that must work
end-to-end in the demo regardless of any third-party integration.
"""

from __future__ import annotations

import hashlib
import os
from pathlib import Path

from kiln_trainer.ingest_agent.readers import Sample

DEFAULT_EXTENSIONS = (".md", ".txt", ".rtf", ".markdown")
MAX_FILE_BYTES = 256 * 1024  # 256 KB hard cap so we don't slurp huge files


def _preview(text: str, limit: int = 120) -> str:
    collapsed = " ".join(text.split())
    if len(collapsed) <= limit:
        return collapsed
    return collapsed[: limit - 1] + "…"


def read(*, root: Path | None = None, limit: int = 500) -> list[Sample]:
    """Walk ``root`` (default ``~/Documents``), return up to ``limit``
    text-bearing files as Samples.

    Order is filesystem-determined; callers downstream of the
    orchestrator should not depend on it for correctness."""
    if root is None:
        root = Path.home() / "Documents"
    if not root.exists() or not root.is_dir():
        return []

    samples: list[Sample] = []
    for dirpath, dirnames, filenames in os.walk(root):
        # Skip hidden trees + common cruft.
        dirnames[:] = [d for d in dirnames if not d.startswith(".") and d not in {"node_modules", "build", "dist"}]
        for name in filenames:
            if len(samples) >= limit:
                return samples
            ext = Path(name).suffix.lower()
            if ext not in DEFAULT_EXTENSIONS:
                continue
            full = Path(dirpath) / name
            try:
                if full.stat().st_size > MAX_FILE_BYTES:
                    continue
                text = full.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            if not text.strip():
                continue
            sid = hashlib.sha256(str(full).encode("utf-8")).hexdigest()[:16]
            samples.append(
                Sample(
                    source="local_documents",
                    sample_id=sid,
                    text=text,
                    preview=_preview(text),
                    metadata={"path": str(full)},
                )
            )
    return samples

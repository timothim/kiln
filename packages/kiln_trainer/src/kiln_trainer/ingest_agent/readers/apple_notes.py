"""Apple Notes reader — AppleScript fallback (Phase 3).

The Apple Notes MCP ecosystem is still nascent (no mature reference
server as of the demo cut). The Phase 3 directive explicitly allows
falling back to AppleScript here, and that's what we do: shell out
to ``osascript``, ask Notes for every note's body, parse the
delimited result.

This reader requires Notes Automation permission. If the user hasn't
granted it (or the AppleScript fails for any other reason), we
return an empty list and let the orchestrator log a "skipped" event
rather than crashing the whole ingest run.
"""

from __future__ import annotations

import hashlib
import shutil
import subprocess
from pathlib import Path

from kiln_trainer.ingest_agent.readers import Sample

# Two-character separator that's vanishingly unlikely to appear in a
# real note body. AppleScript joins the per-note bodies with this
# string and we split on it to recover the originals.
_RECORD_SEP = "\x1e"

_APPLESCRIPT = """
tell application "Notes"
    set noteCount to count of notes
    set output to ""
    set sep to character id 30
    set lim to {limit}
    repeat with i from 1 to (noteCount as integer)
        if i > lim then exit repeat
        try
            set noteBody to body of note i as string
            set noteName to name of note i as string
            set output to output & noteName & sep & noteBody & sep
        end try
    end repeat
    return output
end tell
"""


def _preview(text: str, limit: int = 120) -> str:
    collapsed = " ".join(text.split())
    if len(collapsed) <= limit:
        return collapsed
    return collapsed[: limit - 1] + "…"


def read(*, root: Path | None = None, limit: int = 200) -> list[Sample]:
    """Best-effort AppleScript scrape of the user's Notes. Returns
    empty list on permission denial / Notes not installed / parse
    failure. ``root`` is ignored (Notes has no on-disk root)."""
    if shutil.which("osascript") is None:
        return []
    script = _APPLESCRIPT.replace("{limit}", str(int(limit)))
    try:
        completed = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            timeout=30.0,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    if completed.returncode != 0:
        return []
    raw = completed.stdout.rstrip(_RECORD_SEP).strip()
    if not raw:
        return []
    parts = raw.split(_RECORD_SEP)
    samples: list[Sample] = []
    # parts arrive as alternating [name, body, name, body, ...]
    for i in range(0, len(parts) - 1, 2):
        name = parts[i].strip()
        body = parts[i + 1].strip()
        if not body:
            continue
        sid = hashlib.sha256(f"{name}/{body[:64]}".encode("utf-8")).hexdigest()[:16]
        samples.append(
            Sample(
                source="apple_notes",
                sample_id=sid,
                text=body,
                preview=_preview(body),
                metadata={"name": name},
            )
        )
    return samples[:limit]

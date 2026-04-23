"""Process-lifecycle helpers for the sidecar.

Three small responsibilities:

- :func:`log` — free-form output on stderr. stdout is reserved for JSON-line
  events (see :mod:`kiln_trainer.events`).
- :func:`install_sigterm_handler` — exposes a ``threading.Event`` that flips
  when SIGTERM arrives, so main-thread loops can notice without blocking.
- :func:`make_run_dir` — creates a unique working directory under
  ``$TMPDIR/kiln`` for artifacts (adapters, fused weights, GGUF, Modelfile).
"""

from __future__ import annotations

import os
import signal
import sys
import threading
import time
from pathlib import Path
from typing import Any


def log(message: str, **fields: Any) -> None:
    """Write a grep-friendly free-form line to stderr."""
    if fields:
        suffix = " " + " ".join(f"{k}={v!r}" for k, v in fields.items())
    else:
        suffix = ""
    print(f"[kiln_trainer] {message}{suffix}", file=sys.stderr, flush=True)


class PipeUnavailableError(RuntimeError):
    """Raised when a ``subprocess.PIPE`` request did not yield a readable handle.

    Should never happen — ``Popen`` with ``stdout=subprocess.PIPE`` always
    produces a stream — but callers guard against it explicitly because plain
    ``assert`` is stripped under ``python -O`` and we do not want silent
    NoneType surprises downstream.
    """


_sigterm_event: threading.Event | None = None


def install_sigterm_handler() -> threading.Event:
    """Install (once) a SIGTERM handler that sets a ``threading.Event`` on
    delivery, and return that event.

    Idempotent: subsequent calls return the same event. This lets
    :func:`kiln_trainer.cli.main` install the handler at the earliest possible
    moment (closing the race window before ``ready``) while individual
    subcommands still call it from inside their ``run(args)`` without clobbering
    the shared flag. Callers poll ``event.is_set()`` in their read loops so
    shutdown cooperates with any blocking subprocess reads.
    """
    global _sigterm_event
    if _sigterm_event is not None:
        return _sigterm_event

    triggered = threading.Event()

    def _handler(signum: int, frame: object) -> None:
        triggered.set()

    signal.signal(signal.SIGTERM, _handler)
    _sigterm_event = triggered
    return triggered


def make_run_dir(base: Path | str | None = None, prefix: str = "run") -> Path:
    """Create a unique run directory.

    Default base is ``$TMPDIR/kiln``. Name is ``<prefix>-<unix_ms>`` and the
    function retries with ``-1``, ``-2``, ... suffixes if the directory
    already exists (tight loops on a coarse clock).
    """
    if base is None:
        tmp = os.environ.get("TMPDIR", "/tmp")
        base_path = Path(tmp) / "kiln"
    else:
        base_path = Path(base)
    base_path.mkdir(parents=True, exist_ok=True)

    stem = f"{prefix}-{int(time.time() * 1000)}"
    candidate = base_path / stem
    suffix = 0
    while candidate.exists():
        suffix += 1
        candidate = base_path / f"{stem}-{suffix}"
    candidate.mkdir(parents=True, exist_ok=False)
    return candidate


def find_latest_adapter(run_dir: Path | str) -> Path | None:
    """Return the newest ``adapters.safetensors`` under ``run_dir`` if any.

    Used on SIGTERM to report whichever checkpoint ``mlx_lm.lora`` last wrote
    before we asked it to stop.
    """
    root = Path(run_dir)
    if not root.exists():
        return None
    candidates = sorted(root.rglob("adapters.safetensors"), key=lambda p: p.stat().st_mtime)
    return candidates[-1] if candidates else None

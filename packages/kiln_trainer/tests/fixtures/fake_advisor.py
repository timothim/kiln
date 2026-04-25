"""Test fixture for the PR #23 advisor wire-through.

Reads ``{samples, loss_trajectory, iter, iter_total}`` from stdin (matching
the contract of ``kiln_trainer.training_advisor``) and emits a single
deterministic ``advisor_observation`` event tagged with whichever ``iter``
arrived. Used by ``test_train.py`` to exercise the post-checkpoint hook
without spawning Anthropic SDK or Ollama.
"""

from __future__ import annotations

import json
import sys


def main() -> int:
    raw = sys.stdin.read()
    try:
        envelope = json.loads(raw or "{}")
    except json.JSONDecodeError:
        envelope = {}
    iter_now = int(envelope.get("iter") or 0)
    sample_count = len(envelope.get("samples") or [])
    sys.stdout.write(json.dumps({
        "event": "advisor_observation",
        "iter": iter_now,
        "content": f"fake observation at iter {iter_now}, samples={sample_count}",
        "model": "fake-advisor-1.0",
    }) + "\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

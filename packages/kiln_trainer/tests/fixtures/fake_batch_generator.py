"""Stand-in for the real MLX path inside :mod:`kiln_trainer.commands.sample_batch`.

Emits one ``generation`` JSON-line event per entry in ``--prompts-file``, then
a terminal ``done(stage="generation")``. The format matches
:func:`kiln_trainer.events.generation` and :func:`kiln_trainer.events.done`
exactly — the sample-batch seam proxies our stdout verbatim to the train
parent, which decodes these events against its own ``events`` constructors.

Timing knobs (env-var based so we don't need to plumb extra CLI flags):

* ``KILN_FAKE_BATCH_SLEEP_PER_PROMPT``: sleep this many seconds before each
  generation event, in 50 ms chunks so SIGTERM is snappy. Used by the
  SIGTERM test to land a signal mid-run.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import sys
import time
from pathlib import Path


def _emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prompts-file", type=Path, required=True)
    parser.add_argument("--adapter-path", type=Path, required=True)
    args, _unknown = parser.parse_known_args()

    stopped = {"flag": False}

    def _on_sigterm(signum: int, frame: object) -> None:
        stopped["flag"] = True

    signal.signal(signal.SIGTERM, _on_sigterm)

    sleep_per_prompt = float(os.environ.get("KILN_FAKE_BATCH_SLEEP_PER_PROMPT", "0") or 0)
    prompts = json.loads(args.prompts_file.read_text(encoding="utf-8"))

    interrupted = False
    for entry in prompts:
        if sleep_per_prompt > 0:
            deadline = time.monotonic() + sleep_per_prompt
            while time.monotonic() < deadline:
                if stopped["flag"]:
                    break
                time.sleep(0.05)
        if stopped["flag"]:
            interrupted = True
            break
        _emit({
            "event": "generation",
            "prompt": entry["text"],
            "prompt_id": entry["id"],
            "completion": f"echo: {entry['text']}",
            "tokens": 12,
            "tokens_per_s": 56.789,
        })

    _emit({
        "event": "done",
        "stage": "generation",
        "artifact": str(args.adapter_path),
        "interrupted": interrupted,
    })
    return 0


if __name__ == "__main__":
    sys.exit(main())

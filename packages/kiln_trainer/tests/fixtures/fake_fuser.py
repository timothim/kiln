"""Stand-in for ``mlx_lm.fuse`` used by the export subcommand tests.

Creates the ``--save-path`` directory with a placeholder ``config.json`` so the
parent can see a successful fuse result, then exits 0. Honours SIGTERM by
exiting 0 immediately (mlx_lm.fuse has no checkpoint to save).

Env-var knobs:

* ``KILN_FAKE_FUSER_FAIL=1`` — exit with code 2 without writing anything,
  useful for error-path tests.
* ``KILN_FAKE_FUSER_SLEEP`` — seconds to sleep after writing, lets the SIGTERM
  test send a signal while the child is alive.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import sys
import time
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--save-path", required=True)
    parser.add_argument("--model")
    parser.add_argument("--adapter-path")
    args, _unknown = parser.parse_known_args()

    if os.environ.get("KILN_FAKE_FUSER_FAIL"):
        print("fake fuser forced failure", file=sys.stderr, flush=True)
        return 2

    stopped = {"flag": False}

    def _on_sigterm(signum: int, frame: object) -> None:
        stopped["flag"] = True

    signal.signal(signal.SIGTERM, _on_sigterm)

    save_path = Path(args.save_path)
    save_path.mkdir(parents=True, exist_ok=True)
    (save_path / "config.json").write_text(
        json.dumps({"model_type": "qwen2", "fake": True}), encoding="utf-8"
    )
    print("Loading pretrained model", flush=True)

    sleep = float(os.environ.get("KILN_FAKE_FUSER_SLEEP", "0") or 0)
    if sleep:
        # Cooperative sleep so SIGTERM tests exit promptly.
        deadline = time.monotonic() + sleep
        while time.monotonic() < deadline:
            if stopped["flag"]:
                return 0
            time.sleep(0.05)

    return 0


if __name__ == "__main__":
    sys.exit(main())

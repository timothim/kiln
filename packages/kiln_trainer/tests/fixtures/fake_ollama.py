#!/usr/bin/env python3
"""Stand-in for the ``ollama`` CLI used by export tests.

Accepts ``create <name> -f <Modelfile>`` and verifies the Modelfile path
exists. Exits 0. ``KILN_FAKE_OLLAMA_FAIL=1`` forces exit 4.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path


def main() -> int:
    if os.environ.get("KILN_FAKE_OLLAMA_FAIL"):
        print("fake ollama forced failure", file=sys.stderr, flush=True)
        return 4

    argv = sys.argv[1:]
    if len(argv) < 4 or argv[0] != "create":
        print(f"fake ollama: unexpected args {argv}", file=sys.stderr, flush=True)
        return 5

    name = argv[1]
    try:
        f_idx = argv.index("-f")
        modelfile = Path(argv[f_idx + 1])
    except (ValueError, IndexError):
        print("fake ollama: -f <Modelfile> required", file=sys.stderr, flush=True)
        return 5

    if not modelfile.exists():
        print(f"fake ollama: Modelfile missing: {modelfile}", file=sys.stderr, flush=True)
        return 6

    print(f"fake ollama: created {name} from {modelfile}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())

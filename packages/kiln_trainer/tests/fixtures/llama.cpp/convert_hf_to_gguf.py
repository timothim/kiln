"""Stand-in for llama.cpp's ``convert_hf_to_gguf.py`` used by export tests.

Accepts the positional ``<hf_dir>`` and the ``--outfile`` / ``--outtype`` flags
that the parent command builds (see
:func:`kiln_trainer.commands.export._build_gguf_cmd`). Writes a zero-byte
file at ``--outfile`` and exits 0. ``KILN_FAKE_GGUF_FAIL=1`` forces failure.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


def main() -> int:
    if os.environ.get("KILN_FAKE_GGUF_FAIL"):
        print("fake gguf convert forced failure", file=sys.stderr, flush=True)
        return 3

    parser = argparse.ArgumentParser()
    parser.add_argument("hf_dir")
    parser.add_argument("--outfile", required=True)
    parser.add_argument("--outtype", default="auto")
    args, _unknown = parser.parse_known_args()

    outfile = Path(args.outfile)
    outfile.parent.mkdir(parents=True, exist_ok=True)
    outfile.write_bytes(b"")
    print(f"fake gguf wrote {outfile} (outtype={args.outtype})", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())

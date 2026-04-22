"""Stand-in for ``mlx_lm.generate`` used by the sample subcommand tests.

Prints stdout in the exact verbose format of ``mlx_lm.utils.generate`` 0.21.5:

.. code-block:: text

    ==========
    <completion>
    ==========
    Prompt: N tokens, X.XXX tokens-per-sec
    Generation: M tokens, Y.YYY tokens-per-sec
    Peak memory: Z.ZZZ GB

The completion is built from the ``--prompt`` string so tests can assert the
round-trip through the parser. Honours SIGTERM by exiting 0 before printing any
stats — which lets :file:`test_sample.py` assert that the parent emits
``done(interrupted=true)`` without a ``generation`` event.
"""

from __future__ import annotations

import argparse
import os
import signal
import sys
import time


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--max-tokens", type=int, default=32)
    args, _unknown = parser.parse_known_args()

    stopped = {"flag": False}

    def _on_sigterm(signum: int, frame: object) -> None:
        stopped["flag"] = True

    signal.signal(signal.SIGTERM, _on_sigterm)

    sleep_before_stats = float(os.environ.get("KILN_FAKE_GENERATE_SLEEP", "0") or 0)

    print("==========", flush=True)
    # Stream the completion in pieces to mimic mlx_lm's token-by-token output.
    completion_parts = [f"echo: {args.prompt}", "second line of the reply"]
    for part in completion_parts:
        if stopped["flag"]:
            return 0
        print(part, flush=True)
    print("==========", flush=True)

    if sleep_before_stats:
        time.sleep(sleep_before_stats)
        if stopped["flag"]:
            return 0

    print("Prompt: 5 tokens, 123.456 tokens-per-sec", flush=True)
    print(
        f"Generation: {len(completion_parts) * 4} tokens, 45.678 tokens-per-sec",
        flush=True,
    )
    print("Peak memory: 1.234 GB", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())

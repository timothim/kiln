"""Stand-in for ``mlx_lm.lora`` used by the trainer IPC tests.

Prints stdout lines in the exact format of ``mlx_lm.tuner.trainer`` 0.21.5 so
the regexes in :mod:`kiln_trainer.commands.train` are exercised without
pulling MLX into the test environment. Honours SIGTERM by writing a final
checkpoint line and exiting 0 — which lets the SIGTERM forwarding test assert
that the parent emits ``done(interrupted=True)``.

Unknown MLX-LM flags (``--num-layers``, ``--grad-checkpoint`` etc.) are
silently tolerated via ``parse_known_args``. The few flags we do read:

* ``--adapter-path``: directory that receives the zero-byte
  ``adapters.safetensors`` stub.
* ``--iters``: loop upper bound.
* ``--save-every``: emit both a ``Saved adapter weights`` line and a
  ``Val loss`` line every N iters.

Timing knobs (env-var based so the parent's :mod:`_build_cmd` does not need to
forward extra flags to us):

* ``KILN_FAKE_SLEEP_PER_ITER``: seconds to sleep between iterations; used by
  ``test_sigterm.py`` to keep us alive long enough to be signalled mid-run.
"""

from __future__ import annotations

import argparse
import os
import signal
import sys
import time
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adapter-path", required=True)
    parser.add_argument("--iters", type=int, default=20)
    parser.add_argument("--save-every", type=int, default=10)
    args, _unknown = parser.parse_known_args()

    sleep_per_iter = float(os.environ.get("KILN_FAKE_SLEEP_PER_ITER", "0") or 0)

    stopped = {"flag": False}

    def _on_sigterm(signum: int, frame: object) -> None:
        stopped["flag"] = True

    signal.signal(signal.SIGTERM, _on_sigterm)

    adapter_dir = Path(args.adapter_path)
    adapter_dir.mkdir(parents=True, exist_ok=True)
    ckpt_path = adapter_dir / "adapters.safetensors"

    for it in range(1, args.iters + 1):
        if stopped["flag"]:
            ckpt_path.write_bytes(b"")
            print(f"Iter {it}: Saved adapter weights to {ckpt_path}.", flush=True)
            return 0
        loss = max(0.1, 1.5 - 0.01 * it)
        print(
            f"Iter {it}: Train loss {loss:.3f}, "
            f"Learning Rate 1.000e-04, Tokens/sec 120.3, "
            f"Trained Tokens {it * 128}, Peak mem 1.2 GB",
            flush=True,
        )
        if it % args.save_every == 0:
            ckpt_path.write_bytes(b"")
            print(f"Iter {it}: Saved adapter weights to {ckpt_path}.", flush=True)
            val_loss = max(0.15, 1.4 - 0.01 * it)
            print(f"Iter {it}: Val loss {val_loss:.3f}, Val took 0.100s", flush=True)
        if sleep_per_iter:
            time.sleep(sleep_per_iter)

    ckpt_path.write_bytes(b"")
    print(f"Saved final weights to {ckpt_path}.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Entry point: ``python -m kiln_trainer <subcommand> [args]``."""

from __future__ import annotations

import sys

from kiln_trainer.cli import main

if __name__ == "__main__":
    sys.exit(main())

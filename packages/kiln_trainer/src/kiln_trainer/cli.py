"""CLI dispatcher for the ``kiln_trainer`` Python sidecar.

Three subcommands — ``train``, ``sample``, ``export`` — each of which runs as a
short-lived process managed by the Swift app. The CLI emits a ``ready`` event
on stdout before any heavy work, per :file:`CLAUDE.md` and SPEC.md §11.1.

Each subcommand implementation lives in :mod:`kiln_trainer.commands`. Hidden
``--*-module`` / ``--*-bin`` flags exist as test seams: they let the test suite
substitute fake MLX/Ollama binaries without touching production code paths.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Sequence

from kiln_trainer import __version__, events, runtime


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="kiln_trainer",
        description="Kiln Python sidecar — wraps MLX-LM for LoRA SFT/DPO, fuse, and generation.",
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    sub = parser.add_subparsers(dest="command", required=True, metavar="COMMAND")

    _build_train_parser(sub)
    _build_sample_parser(sub)
    _build_export_parser(sub)

    return parser


def _build_train_parser(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser(
        "train",
        help="LoRA SFT on a ChatML JSONL corpus",
        description="Run LoRA supervised fine-tuning via mlx_lm.lora.",
    )
    p.add_argument("--dataset", type=Path, required=True, help="ChatML JSONL corpus")
    p.add_argument("--model", required=True, help="HuggingFace model id (e.g. mlx-community/Qwen2.5-3B-Instruct-4bit)")
    p.add_argument("--run-dir", type=Path, default=None, help="working dir for adapters/checkpoints (default: $TMPDIR/kiln/run-<ts>)")
    p.add_argument("--epochs", type=int, default=None)
    p.add_argument("--rank", type=int, default=None)
    p.add_argument("--lora-layers", type=int, default=None)
    p.add_argument("--batch-size", type=int, default=None)
    p.add_argument("--learning-rate", type=float, default=None)
    p.add_argument("--max-seq-length", type=int, default=None)
    p.add_argument("--save-every", type=int, default=50)
    p.add_argument("--val-batches", type=int, default=25)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--iters", type=int, default=None, help="hard override of iters computed from epochs")
    p.add_argument("--sample-prompts-file", type=Path, default=None, help="JSON list of Growing Model prompts")
    # Hidden test seam: lets tests point at tests/fixtures/fake_trainer.py.
    p.add_argument("--trainer-module", default="mlx_lm.lora", help=argparse.SUPPRESS)
    p.add_argument("--trainer-entry", default=None, help=argparse.SUPPRESS)


def _build_sample_parser(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser(
        "sample",
        help="single-shot inference on a trained adapter",
        description="Wrap mlx_lm.generate for a one-off prompt.",
    )
    p.add_argument("--model", required=True)
    p.add_argument("--adapter-path", type=Path, required=True)
    p.add_argument("--prompt", required=True, help='prompt text, or "-" to read from stdin')
    p.add_argument("--prompt-id", default=None, help="optional tag echoed back on the generation event")
    p.add_argument("--max-tokens", type=int, default=200)
    p.add_argument("--temp", type=float, default=0.7)
    p.add_argument("--top-p", type=float, default=0.9)
    p.add_argument("--seed", type=int, default=42)
    # Hidden test seam.
    p.add_argument("--generator-module", default="mlx_lm.generate", help=argparse.SUPPRESS)
    p.add_argument("--generator-entry", default=None, help=argparse.SUPPRESS)


def _build_export_parser(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser(
        "export",
        help="fuse adapter → GGUF → Modelfile → ollama create",
        description="End-to-end export of a trained adapter into an Ollama model.",
    )
    p.add_argument("--model", required=True)
    p.add_argument("--adapter-path", type=Path, required=True)
    p.add_argument("--run-dir", type=Path, default=None)
    p.add_argument("--user-name", default=None, help="display name for the SYSTEM prompt (default: $USER)")
    p.add_argument("--output-name", default=None, help="ollama model name (default: kiln-<user_slug>)")
    p.add_argument("--quantization", default=None, help="Q4_K_M or Q5_K_M (default: per base size)")
    p.add_argument("--skip-gguf", action="store_true", help="skip llama.cpp conversion")
    p.add_argument("--skip-ollama", action="store_true", help="skip 'ollama create' step")
    p.add_argument("--llama-cpp-dir", type=Path, default=None, help="path to a llama.cpp checkout")
    # Hidden test seams.
    p.add_argument("--fuser-module", default="mlx_lm.fuse", help=argparse.SUPPRESS)
    p.add_argument("--fuser-entry", default=None, help=argparse.SUPPRESS)
    p.add_argument("--ollama-bin", default="ollama", help=argparse.SUPPRESS)


def main(argv: Sequence[str] | None = None) -> int:
    # Install the SIGTERM handler first thing, before anything the parent could
    # conceivably race against. If we waited until inside a subcommand, a
    # SIGTERM arriving between ``ready`` and ``install_sigterm_handler`` would
    # kill the process with Python's default disposition — no ``done`` event,
    # no graceful shutdown. The call is idempotent; subcommands call it again.
    runtime.install_sigterm_handler()

    parser = build_parser()
    args = parser.parse_args(argv)

    # Emit ``ready`` before any heavy import. argparse is cheap; we are well
    # under the 500 ms budget (SPEC.md §11, CLAUDE.md).
    events.emit(events.ready(version=__version__))

    if args.command == "train":
        from kiln_trainer.commands import train as train_cmd

        return train_cmd.run(args)
    if args.command == "sample":
        from kiln_trainer.commands import sample as sample_cmd

        return sample_cmd.run(args)
    if args.command == "export":
        from kiln_trainer.commands import export as export_cmd

        return export_cmd.run(args)

    parser.error(f"unknown command {args.command!r}")
    return 2  # pragma: no cover — parser.error exits before reaching here


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())

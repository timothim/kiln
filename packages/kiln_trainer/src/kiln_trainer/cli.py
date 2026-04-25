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


class _SidecarParser(argparse.ArgumentParser):
    """``ArgumentParser`` that emits a structured JSON error event on stdout
    before the default ``stderr + sys.exit(2)`` path.

    Rationale: the Swift parent parses stdout JSON lines. If it passes a bad
    command line (unknown subcommand, missing required flag), argparse's
    default behaviour only writes to stderr — so from Swift's perspective the
    sidecar crashes silently from the stdout channel's point of view. Emitting
    a well-formed ``error`` event first gives the parent a parseable record.

    SPEC §11.3 framing rule: "Unknown event/cmd logged and skipped". Under the
    argparse model (see `DECISIONS.md §L8`) the equivalent is: unknown
    subcommand → exit 2 + structured JSON on stdout. Exit code is unchanged so
    the shell/Swift `Process.terminationStatus` contract still holds.
    """

    def error(self, message: str) -> None:  # type: ignore[override]
        try:
            events.emit(
                events.error(
                    code="internal",
                    message=f"cli parse error: {message}",
                    recoverable=False,
                )
            )
        except Exception:
            # Emission must not swallow the underlying argparse error.
            pass
        super().error(message)  # writes usage + message to stderr, then sys.exit(2)


def build_parser() -> argparse.ArgumentParser:
    parser = _SidecarParser(
        prog="kiln_trainer",
        description="Kiln Python sidecar — wraps MLX-LM for LoRA SFT/DPO, fuse, and generation.",
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    # parser_class propagates _SidecarParser to subparsers so missing/invalid
    # flags on train/sample/export also emit a structured error event.
    sub = parser.add_subparsers(
        dest="command", required=True, metavar="COMMAND", parser_class=_SidecarParser
    )

    _build_train_parser(sub)
    _build_sample_parser(sub)
    _build_sample_batch_parser(sub)
    _build_sample_compare_parser(sub)
    _build_export_parser(sub)
    _build_classify_parser(sub)
    _build_embed_search_parser(sub)
    _build_voice_coach_parser(sub)

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
    # Hidden test seam for the post-checkpoint sampler (M6.5). Threads through
    # to the spawned ``sample-batch`` subprocess so integration tests can swap
    # in ``tests/fixtures/fake_batch_generator.py``.
    p.add_argument("--sampler-entry", default=None, help=argparse.SUPPRESS)


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


def _build_sample_batch_parser(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser(
        "sample-batch",
        help="batched inference for Growing Model samples at each checkpoint",
        description=(
            "Run inference against N fixed prompts on a trained adapter, loading "
            "the model once. Emits one generation event per prompt plus a final "
            "done(stage=generation). Invoked by the train orchestrator after each "
            "checkpoint save (M6.5)."
        ),
    )
    p.add_argument("--model", required=True)
    p.add_argument("--adapter-path", type=Path, required=True)
    p.add_argument(
        "--prompts-file",
        type=Path,
        default=None,
        help=(
            "JSON list of {id, text} prompt entries. Defaults to "
            "kiln_trainer.sample_prompts.DEFAULT_PROMPTS when omitted."
        ),
    )
    p.add_argument("--max-tokens", type=int, default=150)
    p.add_argument("--temp", type=float, default=0.7)
    p.add_argument("--top-p", type=float, default=0.9)
    p.add_argument("--seed", type=int, default=42)
    # Hidden test seam.
    p.add_argument("--generator-entry", default=None, help=argparse.SUPPRESS)


def _build_sample_compare_parser(sub: argparse._SubParsersAction) -> None:
    """``sample-compare`` — Voice Mirror's three-variant side-by-side generation.

    Emits one ``generation`` event per variant (``prompt_id=base|sft|sftdpo``)
    followed by a single ``done(stage=generation)``. Three cold-load
    subprocesses under the hood; see ``scripts/verify-mlx-hotswap.py`` for the
    rationale behind not sharing a single in-process model.
    """
    from kiln_trainer.commands.sample_compare import parse_variant

    p = sub.add_parser(
        "sample-compare",
        help="two- or three-variant comparison for Voice Mirror",
        description=(
            "Run the same prompt through base / SFT / SFT+DPO model variants "
            "and emit one generation event per variant for Voice Mirror."
        ),
    )
    p.add_argument("--model", required=True)
    p.add_argument("--prompt", required=True, help='prompt text, or "-" to read from stdin')
    p.add_argument(
        "--variant",
        action="append",
        type=parse_variant,
        metavar="TAG[:ADAPTER_PATH]",
        help=(
            "Repeatable. TAG is one of base/sft/sftdpo. Adapter-backed tags "
            "require a path (sft:/path/to/adapter.safetensors); base takes no "
            "path. At least one --variant is required."
        ),
    )
    p.add_argument("--max-tokens", type=int, default=200)
    p.add_argument("--temp", type=float, default=0.7)
    p.add_argument("--top-p", type=float, default=0.9)
    p.add_argument("--seed", type=int, default=42)
    # Hidden test seams.
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


def _build_classify_parser(sub: argparse._SubParsersAction) -> None:
    """``classify`` — run a single distilled classifier on text input (M9.C).

    The Swift parent invokes this once per pipeline stage that needs a
    classifier (Dataset Doctor calls ``--mode quality`` per chunk; Style
    Signature Card calls ``--mode style`` once per corpus). One mode per
    invocation keeps the contract narrow and the subprocess cheap; for
    bulk corpus-time gating, pass ``--input-file`` to amortize model load."""
    p = sub.add_parser(
        "classify",
        help="run a distilled classifier on JSONL or single text",
        description=(
            "Score text via the M9.C distilled classifiers (quality / "
            "preference / style). Emits one classification event per row "
            "plus a final done(stage=classify)."
        ),
    )
    p.add_argument(
        "--mode",
        required=True,
        choices=["quality", "preference", "style"],
        help="which classifier to run",
    )
    p.add_argument(
        "--artifact",
        type=Path,
        default=None,
        help="path to the trained sklearn pickle (required for --mode quality)",
    )
    p.add_argument(
        "--input-file",
        type=Path,
        default=None,
        help='JSONL of {"request_id", "text"} rows; omit when using --text',
    )
    p.add_argument(
        "--text",
        default=None,
        help="single text to classify (mutually exclusive with --input-file)",
    )
    p.add_argument(
        "--request-id",
        default=None,
        help="optional id echoed back on the classification event when using --text",
    )


def _build_embed_search_parser(sub: argparse._SubParsersAction) -> None:
    """``embed-search`` — sentence-transformers similarity search (M9.B).

    Embeds a single query string and a corpus of chunks and emits the
    top-K matches as ``classification`` events with ``kind="embed_search"``.
    The Voice Inspector consumes this when the user highlights a span of
    generated text. The model (``all-MiniLM-L6-v2``, 80 MB) downloads on
    first use to ``~/.cache/huggingface``; subsequent runs are local.

    Test seam: ``--embedder fake-hash`` swaps in a deterministic hashed-
    feature embedder so unit tests don't pull the ST model."""
    p = sub.add_parser(
        "embed-search",
        help="sentence-transformers nearest-neighbour search over a corpus",
        description=(
            "Embed a query and a JSONL corpus, emit the top-K matches "
            "as classification events. Used by the Voice Inspector "
            "(M9.B) to surface 'three corpus chunks closest to the "
            "highlighted span'."
        ),
    )
    p.add_argument(
        "--query",
        required=True,
        help="text to find nearest neighbours for",
    )
    p.add_argument(
        "--corpus-file",
        type=Path,
        required=True,
        help='JSONL of {"request_id", "text"} rows',
    )
    p.add_argument(
        "--top-k",
        type=int,
        default=3,
        help="number of nearest neighbours to emit (default: 3)",
    )
    p.add_argument(
        "--embedder",
        default="sentence-transformers",
        choices=["sentence-transformers", "fake-hash"],
        help=argparse.SUPPRESS,
    )


def _build_voice_coach_parser(sub: argparse._SubParsersAction) -> None:
    """``voice-coach`` — Opus 4.7 (or local Qwen) post-export voice analyst.

    Saturday Phase 1. The Swift caller passes ``{style_signature,
    sample_completions}`` over stdin or via ``--input-file`` and
    receives a 150-word markdown report on the user's voice.

    Cloud mode (``--mode cloud``) needs ``ANTHROPIC_API_KEY`` in env;
    local mode (``--mode local``) talks to the Ollama daemon at
    ``127.0.0.1:11434`` and uses ``--local-model`` (default
    ``qwen2.5:7b``) — the runtime equivalent for users who don't want
    to send their voice signature to a third party."""
    p = sub.add_parser(
        "voice-coach",
        help="Opus / local Qwen voice analyst for the post-export report",
        description=(
            "Generate a 150-word markdown report on the user's voice. "
            "Cloud mode uses claude-opus-4-7; local mode uses Ollama."
        ),
    )
    p.add_argument(
        "--mode",
        required=True,
        choices=["cloud", "local"],
        help="cloud → Anthropic SDK / claude-opus-4-7; local → Ollama daemon",
    )
    p.add_argument(
        "--input-file",
        type=Path,
        default=None,
        help="JSON {style_signature, sample_completions}; reads stdin if omitted",
    )
    p.add_argument(
        "--max-tokens",
        type=int,
        default=500,
        help="upper bound on the markdown length (default 500)",
    )
    p.add_argument(
        "--local-model",
        default="qwen2.5:7b",
        help="Ollama model id used when --mode local (default qwen2.5:7b)",
    )


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
    if args.command == "sample-batch":
        from kiln_trainer.commands import sample_batch as sample_batch_cmd

        return sample_batch_cmd.run(args)
    if args.command == "sample-compare":
        from kiln_trainer.commands import sample_compare as sample_compare_cmd

        return sample_compare_cmd.run(args)
    if args.command == "export":
        from kiln_trainer.commands import export as export_cmd

        return export_cmd.run(args)
    if args.command == "classify":
        from kiln_trainer.commands import classify as classify_cmd

        return classify_cmd.run(args)
    if args.command == "embed-search":
        from kiln_trainer.commands import embed_search as embed_search_cmd

        return embed_search_cmd.run(args)
    if args.command == "voice-coach":
        from kiln_trainer.commands import voice_coach as voice_coach_cmd

        return voice_coach_cmd.run(args)

    parser.error(f"unknown command {args.command!r}")
    return 2  # pragma: no cover — parser.error exits before reaching here


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())

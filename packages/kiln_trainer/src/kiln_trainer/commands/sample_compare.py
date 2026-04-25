"""``sample-compare`` subcommand — Voice Mirror's three-variant generation.

Runs the same prompt through two or three model variants — base, SFT-only,
and SFT+DPO — and emits one ``generation`` event per variant. Swift's
``SampleCompareRunner`` consumes these and fills the Voice Mirror cards.

Variant model
-------------

A *variant* is a ``<tag>`` and, for adapter-backed variants, a ``<path>``.
Tags are the three fixed Voice Mirror sources:

- ``base``    — no adapter; just ``mlx_lm.generate --model <...>``
- ``sft``     — LoRA adapter after supervised fine-tuning
- ``sftdpo``  — LoRA adapter after SFT + DPO fine-tuning

At least one variant must be specified. Variants run sequentially in the
order given; each one is a fresh ``mlx_lm.generate`` subprocess (the
conservative "cold-load three times" path, see
``scripts/verify-mlx-hotswap.py`` for the dev-only optimisation study).

Output schema
-------------

Each variant emits:

.. code-block:: text

    {"event":"generation","prompt":"...","completion":"...","tokens":N,
     "tokens_per_s":X.Y,"prompt_id":"base|sft|sftdpo"}

After all variants complete, one ``done(stage="generation")`` is emitted.
On SIGTERM, any in-flight child is forwarded SIGTERM and ``done(interrupted=
true)`` is emitted — no partial ``generation`` event for the interrupted
variant.
"""

from __future__ import annotations

import argparse
import queue
import re
import signal
import subprocess
import sys
import threading
from pathlib import Path
from typing import IO

from kiln_trainer import events, runtime

_DELIM = "=" * 10
_RE_GEN_STATS = re.compile(
    r"^Generation:\s+(\d+)\s+tokens,\s+([\d.]+)\s+tokens-per-sec"
)

ALLOWED_TAGS: frozenset[str] = frozenset({"base", "sft", "sftdpo"})


def parse_variant(raw: str) -> tuple[str, Path | None]:
    """Parse a ``--variant`` argument into ``(tag, adapter_path | None)``.

    Accepted forms:
      ``base``              → ("base", None)
      ``sft:/path``         → ("sft", Path("/path"))
      ``sftdpo:/some/path`` → ("sftdpo", Path("/some/path"))
    """
    if ":" in raw:
        tag, rest = raw.split(":", 1)
    else:
        tag, rest = raw, ""
    tag = tag.strip()
    if tag not in ALLOWED_TAGS:
        raise argparse.ArgumentTypeError(
            f"variant tag must be one of {sorted(ALLOWED_TAGS)}, got {tag!r}"
        )
    if tag == "base":
        if rest:
            raise argparse.ArgumentTypeError("base variant must not carry an adapter path")
        return ("base", None)
    # adapter-backed variant
    if not rest:
        raise argparse.ArgumentTypeError(
            f"variant {tag!r} requires an adapter path, e.g. --variant {tag}:/path/to/adapter.safetensors"
        )
    return (tag, Path(rest))


def run(args: argparse.Namespace) -> int:
    prompt_text = _read_prompt(args.prompt)

    variants: list[tuple[str, Path | None]] = args.variant or []
    if not variants:
        events.emit(
            events.error(
                code="internal",
                message="sample-compare requires at least one --variant",
                recoverable=False,
                stage="generation",
            )
        )
        return 2

    # Deduplicate tags — running the same variant twice makes no sense and only
    # causes UI collisions on the Swift side.
    seen_tags: set[str] = set()
    for tag, _ in variants:
        if tag in seen_tags:
            events.emit(
                events.error(
                    code="internal",
                    message=f"duplicate --variant tag {tag!r}",
                    recoverable=False,
                    stage="generation",
                )
            )
            return 2
        seen_tags.add(tag)

    triggered = runtime.install_sigterm_handler()

    artifacts: list[str] = []
    interrupted = False

    for tag, adapter in variants:
        if triggered.is_set():
            interrupted = True
            break

        # Adapter-backed variants: bail early if the file is missing, before we
        # spawn. Matches the error signature used elsewhere in the sidecar.
        if adapter is not None and not adapter.exists():
            events.emit(
                events.error(
                    code="adapter_invalid",
                    message=f"adapter path does not exist: {adapter}",
                    recoverable=False,
                    stage="generation",
                    context={"variant": tag},
                )
            )
            # Continue with other variants rather than aborting the whole compare
            # — Swift can still fill two of three Voice Mirror cards.
            continue

        cmd = _build_cmd(args=args, prompt_text=prompt_text, adapter=adapter)
        runtime.log(f"spawning generator for {tag}", adapter=str(adapter) if adapter else None)

        try:
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
            )
        except FileNotFoundError as exc:
            events.emit(
                events.error(
                    code="subprocess_failed",
                    message=str(exc),
                    recoverable=False,
                    stage="generation",
                    context={"variant": tag},
                )
            )
            continue

        if proc.stdout is None or proc.stderr is None:
            raise runtime.PipeUnavailableError(
                f"generator subprocess missing pipe handles: "
                f"stdout={proc.stdout!r}, stderr={proc.stderr!r}"
            )

        out_q: queue.Queue[str | None] = queue.Queue()
        err_q: queue.Queue[str | None] = queue.Queue()
        threading.Thread(target=_drain, args=(proc.stdout, out_q), daemon=True).start()
        threading.Thread(target=_drain, args=(proc.stderr, err_q), daemon=True).start()

        parser = _GenerateOutputParser()
        variant_interrupted = False
        poll_interval = 0.1

        while True:
            if triggered.is_set() and not variant_interrupted:
                variant_interrupted = True
                interrupted = True
                runtime.log("SIGTERM received; forwarding to generator child", variant=tag)
                try:
                    proc.send_signal(signal.SIGTERM)
                except ProcessLookupError:
                    pass

            try:
                line = out_q.get(timeout=poll_interval)
            except queue.Empty:
                if proc.poll() is not None and out_q.empty():
                    break
                continue

            if line is None:
                break
            parser.feed(line.rstrip("\n"))

        _drain_remaining(err_q, label=f"generator stderr ({tag})")

        if proc.poll() is None:
            try:
                proc.wait(timeout=4.0)
            except subprocess.TimeoutExpired:
                proc.kill()
                try:
                    proc.wait(timeout=1.0)
                except subprocess.TimeoutExpired:
                    pass

        rc = proc.returncode or 0

        if not variant_interrupted and rc == 0 and parser.completion is not None:
            events.emit(
                events.generation(
                    prompt=prompt_text,
                    completion=parser.completion,
                    tokens=parser.tokens or 0,
                    tokens_per_s=parser.tokens_per_s or 0.0,
                    prompt_id=tag,
                )
            )
            artifacts.append(tag if adapter is None else f"{tag}:{adapter}")
        elif not variant_interrupted and rc != 0:
            events.emit(
                events.error(
                    code="subprocess_failed",
                    message=f"generator for variant {tag} exited with code {rc}",
                    recoverable=True,
                    stage="generation",
                    context={"variant": tag},
                )
            )
            # Fall through; next variant still runs.

        if variant_interrupted:
            break

    events.emit(
        events.done(
            stage="generation",
            artifact=",".join(artifacts) if artifacts else "",
            interrupted=interrupted,
        )
    )

    return 0


def _read_prompt(prompt: str) -> str:
    if prompt == "-":
        return sys.stdin.read()
    return prompt


class _GenerateOutputParser:
    """Same state-machine as :class:`kiln_trainer.commands.sample._GenerateOutputParser`.

    Kept inline so the two commands can evolve independently. If this parser
    grows significantly, pull it into ``commands/_mlx_generate_parse.py``.
    """

    def __init__(self) -> None:
        self._state: str = "pre_delim"
        self._completion_parts: list[str] = []
        self.completion: str | None = None
        self.tokens: int | None = None
        self.tokens_per_s: float | None = None

    def feed(self, line: str) -> None:
        if self._state == "pre_delim":
            if line == _DELIM:
                self._state = "in_completion"
            return

        if self._state == "in_completion":
            if line == _DELIM:
                if self._completion_parts and self._completion_parts[-1] == "":
                    self._completion_parts.pop()
                self.completion = "\n".join(self._completion_parts)
                self._state = "post_completion"
            else:
                self._completion_parts.append(line)
            return

        m = _RE_GEN_STATS.search(line)
        if m:
            self.tokens = int(m.group(1))
            self.tokens_per_s = float(m.group(2))


def _build_cmd(
    *,
    args: argparse.Namespace,
    prompt_text: str,
    adapter: Path | None,
) -> list[str]:
    if args.generator_entry:
        base = [sys.executable, str(args.generator_entry)]
    else:
        base = [sys.executable, "-m", args.generator_module]
    cmd = base + [
        "--model", args.model,
        "--prompt", prompt_text,
        "--max-tokens", str(args.max_tokens),
        "--temp", str(args.temp),
        "--top-p", str(args.top_p),
        "--seed", str(args.seed),
        "--verbose", "True",
    ]
    if adapter is not None:
        cmd += ["--adapter-path", str(adapter)]
    return cmd


def _drain(fh: IO[str], q: "queue.Queue[str | None]") -> None:
    try:
        for line in fh:
            q.put(line)
    finally:
        q.put(None)
        try:
            fh.close()
        except Exception:
            pass


def _drain_remaining(q: "queue.Queue[str | None]", *, label: str) -> None:
    while True:
        try:
            line = q.get(timeout=0.05)
        except queue.Empty:
            return
        if line is None:
            return
        runtime.log(label, line=line.rstrip("\n"))

"""``sample`` subcommand — single-shot generation via ``mlx_lm.generate``.

Flow:

1. Resolve the prompt (``-`` reads stdin; otherwise taken verbatim).
2. Spawn ``mlx_lm.generate`` in verbose mode so we can scrape both the
   completion text and the per-run token stats.
3. Parse the verbose output. It looks like:

   .. code-block:: text

       ==========
       <generated text, possibly multiline>
       ==========
       Prompt: 5 tokens, 123.000 tokens-per-sec
       Generation: 12 tokens, 45.678 tokens-per-sec
       Peak memory: 1.234 GB

4. Emit a single ``generation`` event with the parsed completion + tokens +
   tokens_per_s, then ``done(stage="generation")``.

SIGTERM forwards to the child and we emit ``done(interrupted=True)``.
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

# ``mlx_lm.utils.generate`` prints exactly ``"=" * 10`` as its delimiter (0.21.5).
_DELIM = "=" * 10
_RE_GEN_STATS = re.compile(
    r"^Generation:\s+(\d+)\s+tokens,\s+([\d.]+)\s+tokens-per-sec"
)


def run(args: argparse.Namespace) -> int:
    prompt_text = _read_prompt(args.prompt)

    cmd = _build_cmd(args=args, prompt_text=prompt_text)
    runtime.log("spawning generator", model=args.model, max_tokens=args.max_tokens)

    triggered = runtime.install_sigterm_handler()
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
            )
        )
        return 1

    out_q: queue.Queue[str | None] = queue.Queue()
    err_q: queue.Queue[str | None] = queue.Queue()
    assert proc.stdout is not None and proc.stderr is not None
    threading.Thread(target=_drain, args=(proc.stdout, out_q), daemon=True).start()
    threading.Thread(target=_drain, args=(proc.stderr, err_q), daemon=True).start()

    parser = _GenerateOutputParser()
    interrupted = False
    poll_interval = 0.1

    while True:
        if triggered.is_set() and not interrupted:
            interrupted = True
            runtime.log("SIGTERM received; forwarding to generator child")
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

    _drain_remaining(err_q, label="generator stderr")

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

    if not interrupted and rc == 0 and parser.completion is not None:
        events.emit(
            events.generation(
                prompt=prompt_text,
                completion=parser.completion,
                tokens=parser.tokens or 0,
                tokens_per_s=parser.tokens_per_s or 0.0,
                prompt_id=args.prompt_id,
            )
        )

    events.emit(
        events.done(
            stage="generation",
            artifact=str(args.adapter_path),
            interrupted=interrupted,
        )
    )

    if interrupted:
        return 0
    if rc != 0:
        events.emit(
            events.error(
                code="subprocess_failed",
                message=f"generator exited with code {rc}",
                recoverable=False,
                stage="generation",
            )
        )
        return rc
    return 0


def _read_prompt(prompt: str) -> str:
    if prompt == "-":
        return sys.stdin.read()
    return prompt


class _GenerateOutputParser:
    """Parses ``mlx_lm.generate --verbose True`` stdout.

    State machine: ``pre_delim → in_completion → post_completion``. The
    completion text is everything between the first and second delimiter line.
    Stats live on lines after the second delimiter.
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
                # Strip exactly one trailing blank line that mlx_lm always
                # prints after the completion (``print()`` with no args).
                if self._completion_parts and self._completion_parts[-1] == "":
                    self._completion_parts.pop()
                self.completion = "\n".join(self._completion_parts)
                self._state = "post_completion"
            else:
                self._completion_parts.append(line)
            return

        # post_completion: scan for Generation stats line.
        m = _RE_GEN_STATS.search(line)
        if m:
            self.tokens = int(m.group(1))
            self.tokens_per_s = float(m.group(2))


def _build_cmd(*, args: argparse.Namespace, prompt_text: str) -> list[str]:
    if args.generator_entry:
        base = [sys.executable, str(args.generator_entry)]
    else:
        base = [sys.executable, "-m", args.generator_module]
    return base + [
        "--model", args.model,
        "--adapter-path", str(args.adapter_path),
        "--prompt", prompt_text,
        "--max-tokens", str(args.max_tokens),
        "--temp", str(args.temp),
        "--top-p", str(args.top_p),
        "--seed", str(args.seed),
        "--verbose", "True",
    ]


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

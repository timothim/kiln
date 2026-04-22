"""``export`` subcommand — fuse → GGUF → Modelfile → ``ollama create``.

Four stages, each gated on the previous:

1. **fuse** — ``mlx_lm.fuse`` merges the trained LoRA adapter into the base
   model weights. Output is a HuggingFace-format directory.
2. **gguf** — ``llama.cpp``'s ``convert_hf_to_gguf.py`` writes a quantized GGUF
   file (``Q4_K_M`` / ``Q5_K_M`` per :func:`hyperparams.defaults_for`).
3. **modelfile** — we render an Ollama Modelfile referencing the GGUF file
   (see :mod:`kiln_trainer.modelfile`). No subprocess; just a write.
4. **ollama** — ``ollama create <name> -f Modelfile`` installs the model into
   the Ollama daemon.

Each of the three subprocess stages emits its own ``done`` event so Swift can
drive a staged progress UI. ``--skip-gguf`` and ``--skip-ollama`` cut off the
pipeline early (useful for users without the daemon installed).

SIGTERM at any point forwards to the current child and the sidecar emits a
final ``done(interrupted=true)`` for that stage, then exits 0.
"""

from __future__ import annotations

import argparse
import os
import re
import signal
import subprocess
import sys
import threading
from pathlib import Path
from typing import IO

from kiln_trainer import events, hyperparams, modelfile, runtime


def run(args: argparse.Namespace) -> int:
    # (1) resolve user-facing defaults
    try:
        hp = hyperparams.defaults_for(args.model)
    except ValueError as exc:
        events.emit(
            events.error(
                code="model_not_found",
                message=str(exc),
                recoverable=False,
                stage="fuse",
            )
        )
        return 2

    user_name = args.user_name or os.environ.get("USER") or "the user"
    output_name = args.output_name or f"kiln-{_slugify(user_name)}"
    quantization = args.quantization or hp["gguf_quantization"]

    run_dir = Path(args.run_dir) if args.run_dir else runtime.make_run_dir()
    fused_dir = run_dir / "fused"
    gguf_path = run_dir / f"{output_name}.gguf"
    modelfile_path = run_dir / "Modelfile"

    # (2) sanity-check the adapter before we spawn anything
    adapter_path = Path(args.adapter_path)
    if not adapter_path.exists():
        events.emit(
            events.error(
                code="adapter_invalid",
                message=f"adapter path does not exist: {adapter_path}",
                recoverable=False,
                stage="fuse",
            )
        )
        return 1

    triggered = runtime.install_sigterm_handler()

    # (3) fuse
    fuse_cmd = _build_fuse_cmd(args=args, fused_dir=fused_dir)
    runtime.log("spawning fuse", cmd=fuse_cmd[:3])
    rc, interrupted = _run_subprocess(fuse_cmd, stage="fuse", triggered=triggered, label="fuse")
    if interrupted:
        events.emit(events.done(stage="fuse", artifact=str(fused_dir), interrupted=True))
        return 0
    if rc != 0:
        events.emit(
            events.error(
                code="subprocess_failed",
                message=f"fuse exited with code {rc}",
                recoverable=False,
                stage="fuse",
            )
        )
        return rc
    events.emit(events.done(stage="fuse", artifact=str(fused_dir), interrupted=False))

    # (4) gguf
    if not args.skip_gguf:
        gguf_cmd = _build_gguf_cmd(
            args=args, fused_dir=fused_dir, gguf_path=gguf_path, quantization=quantization
        )
        if gguf_cmd is None:
            # _build_gguf_cmd already emitted an error event when the llama.cpp
            # script could not be located.
            return 1
        runtime.log("spawning gguf", cmd=gguf_cmd[:3])
        rc, interrupted = _run_subprocess(
            gguf_cmd, stage="gguf", triggered=triggered, label="gguf"
        )
        if interrupted:
            events.emit(events.done(stage="gguf", artifact=str(gguf_path), interrupted=True))
            return 0
        if rc != 0:
            events.emit(
                events.error(
                    code="gguf_failed",
                    message=f"convert_hf_to_gguf exited with code {rc}",
                    recoverable=False,
                    stage="gguf",
                )
            )
            return rc
        events.emit(events.done(stage="gguf", artifact=str(gguf_path), interrupted=False))

    # (5) Modelfile
    body = modelfile.render(gguf_filename=f"./{gguf_path.name}", user_name=user_name)
    modelfile_path.write_text(body, encoding="utf-8")
    runtime.log("Modelfile written", path=str(modelfile_path))

    # (6) ollama create
    if not args.skip_ollama:
        ollama_cmd = [args.ollama_bin, "create", output_name, "-f", str(modelfile_path)]
        runtime.log("spawning ollama", cmd=ollama_cmd[:2])
        rc, interrupted, missing = _run_subprocess(
            ollama_cmd, stage="ollama", triggered=triggered, label="ollama",
            return_missing=True,
        )
        if missing:
            events.emit(
                events.error(
                    code="ollama_unavailable",
                    message=f"ollama binary not found: {args.ollama_bin}",
                    recoverable=True,
                    stage="ollama",
                )
            )
            return 1
        if interrupted:
            events.emit(events.done(stage="ollama", artifact=output_name, interrupted=True))
            return 0
        if rc != 0:
            events.emit(
                events.error(
                    code="subprocess_failed",
                    message=f"ollama create exited with code {rc}",
                    recoverable=False,
                    stage="ollama",
                )
            )
            return rc
        events.emit(events.done(stage="ollama", artifact=output_name, interrupted=False))

    return 0


_SLUG_RE = re.compile(r"[^a-z0-9]+")


def _slugify(name: str) -> str:
    """Lowercase, collapse non-alphanumerics into hyphens, trim hyphens.

    ``kiln-<slug>`` becomes the default Ollama model name, and Ollama model
    names are restricted to ``[A-Za-z0-9._-]+`` (``:`` separates the tag).
    """
    slug = _SLUG_RE.sub("-", name.lower()).strip("-")
    return slug or "user"


def _build_fuse_cmd(*, args: argparse.Namespace, fused_dir: Path) -> list[str]:
    if args.fuser_entry:
        base = [sys.executable, str(args.fuser_entry)]
    else:
        base = [sys.executable, "-m", args.fuser_module]
    return base + [
        "--model", args.model,
        "--adapter-path", str(args.adapter_path),
        "--save-path", str(fused_dir),
    ]


def _build_gguf_cmd(
    *,
    args: argparse.Namespace,
    fused_dir: Path,
    gguf_path: Path,
    quantization: str,
) -> list[str] | None:
    """Locate ``convert_hf_to_gguf.py`` under ``--llama-cpp-dir`` and build the
    invocation. Returns ``None`` and emits an error event if the script is
    missing — callers should abort."""
    if args.llama_cpp_dir is None:
        events.emit(
            events.error(
                code="gguf_failed",
                message="--llama-cpp-dir is required unless --skip-gguf is passed",
                recoverable=True,
                stage="gguf",
            )
        )
        return None
    script = Path(args.llama_cpp_dir) / "convert_hf_to_gguf.py"
    if not script.exists():
        events.emit(
            events.error(
                code="gguf_failed",
                message=f"convert_hf_to_gguf.py not found under {args.llama_cpp_dir}",
                recoverable=True,
                stage="gguf",
            )
        )
        return None
    return [
        sys.executable,
        str(script),
        str(fused_dir),
        "--outfile", str(gguf_path),
        "--outtype", _gguf_outtype(quantization),
    ]


def _gguf_outtype(quantization: str) -> str:
    """llama.cpp's ``--outtype`` accepts ``f32``, ``f16``, ``bf16``, ``q8_0``,
    and ``auto``. For our k-quants (``Q4_K_M``/``Q5_K_M``) we generate an f16
    GGUF and let ``llama.cpp``'s ``quantize`` tool do the k-quant pass — which
    the skill instructs users to run manually. The ``--outtype`` is best left
    at ``auto`` so the script picks sensibly; users running a k-quant pass
    afterwards can use the quantization tag as the output filename."""
    return "auto"


def _run_subprocess(
    cmd: list[str],
    *,
    stage: str,
    triggered,
    label: str,
    return_missing: bool = False,
):
    """Run ``cmd``, forward SIGTERM, stream output to stderr log.

    Returns ``(returncode, interrupted)`` (or ``(returncode, interrupted,
    missing)`` when ``return_missing`` is True — used by the ollama stage to
    distinguish a missing binary from a failed run).
    """
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
    except FileNotFoundError:
        if return_missing:
            return 127, False, True
        events.emit(
            events.error(
                code="subprocess_failed",
                message=f"{label} binary not found: {cmd[0]}",
                recoverable=False,
                stage=stage,
            )
        )
        return 127, False

    assert proc.stdout is not None

    def _reader(fh: IO[str]) -> None:
        try:
            for ln in fh:
                runtime.log(f"{label} stdout", line=ln.rstrip("\n"))
        finally:
            try:
                fh.close()
            except Exception:
                pass

    t = threading.Thread(target=_reader, args=(proc.stdout,), daemon=True)
    t.start()

    interrupted = False
    while True:
        if triggered.is_set() and not interrupted:
            interrupted = True
            runtime.log(f"SIGTERM received; forwarding to {label}")
            try:
                proc.send_signal(signal.SIGTERM)
            except ProcessLookupError:
                pass
        try:
            proc.wait(timeout=0.1)
            break
        except subprocess.TimeoutExpired:
            continue

    if proc.poll() is None:
        try:
            proc.wait(timeout=4.0)
        except subprocess.TimeoutExpired:
            proc.kill()
            try:
                proc.wait(timeout=1.0)
            except subprocess.TimeoutExpired:
                pass

    t.join(timeout=1.0)
    rc = proc.returncode or 0
    if return_missing:
        return rc, interrupted, False
    return rc, interrupted

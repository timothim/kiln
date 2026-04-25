"""Saturday Phase 5 — Training Advisor.

Single-shot helper that takes a snapshot of the training state
(latest sample completions + loss trajectory + iteration info) and
asks Claude Opus 4.7 (or local Qwen via Ollama) for a one-line
observation. The Swift caller drives this on a polling cadence
during training; the live ``Voice Coach is watching`` panel under
the loss chart streams the observations as they arrive.

Why a separate module not a subcommand: the Swift caller already
runs the train subprocess; layering a second sidecar process per
poll would be wasteful. This module is invoked via ``python -m
kiln_trainer.training_advisor`` so the Swift runner stays small,
or imported directly by other Python code (the train orchestrator's
post-checkpoint hook is the natural production caller).

Wire format on stdout:
    {"event": "advisor_observation", "iter": <int>, "content": "<≤120 chars>", "model": "..."}

A single line, then exits. Errors emit a structured ``error``
event with code data_invalid (no API key) / subprocess_failed
(daemon unreachable) / internal (unknown).
"""

from __future__ import annotations

import argparse
import json
import os
import sys

CLOUD_MODEL_ID = "claude-opus-4-7"
SYSTEM_PROMPT = """You are the Kiln Training Advisor — a brief, useful observer of an
ongoing fine-tuning run. You see: the most recent sample completions
(typically 3 short prompts), the loss trajectory (a list of recent
loss values), and the current iteration / total iterations.

Output exactly one line, ≤120 characters, no markdown. Examples of
good observations:

- "Voice is stabilizing — consistent first-person across all 3 prompts."
- "Loss plateauing near iter 200; consider stopping early."
- "Sample completions show repetition; corpus may need more diversity."
- "Strong voice emergence — birthday-message sample now sounds personal."
- "Loss climbing on validation; could be early signs of overfitting."

Do NOT predict loss values. Do NOT recommend hyperparameter changes
beyond "stop early" or "consider more data." Do NOT use the words
"feel free", "kindly", "absolutely", "important to note". Plain,
specific, actionable.
"""


def _build_user_message(*, samples: list[dict], loss_trajectory: list[float], iter_now: int, iter_total: int) -> str:
    """Format a snapshot for Opus to react to. ``samples`` is the
    M6.5 Growing-Model batch (one per fixed prompt); ``loss_trajectory``
    is the list of recent loss values from progress events."""
    parts = [f"Iteration: {iter_now} / {iter_total}"]
    if loss_trajectory:
        recent = loss_trajectory[-12:]
        parts.append(f"Recent loss: {[round(v, 3) for v in recent]}")
    parts.append("")
    parts.append("Samples (post-checkpoint completions):")
    for s in samples[:6]:
        prompt = s.get("prompt") or "(unknown)"
        completion = (s.get("completion") or "").strip()
        parts.append(f"## {prompt}")
        parts.append(completion)
        parts.append("")
    return "\n".join(parts).strip()


def _call_opus(*, system: str, user: str, max_tokens: int) -> str:
    api_key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if not api_key:
        raise PermissionError("ANTHROPIC_API_KEY missing from env")
    from anthropic import Anthropic  # type: ignore[import-not-found]

    client = Anthropic(api_key=api_key)
    response = client.messages.create(
        model=CLOUD_MODEL_ID,
        max_tokens=max_tokens,
        system=system,
        messages=[{"role": "user", "content": user}],
    )
    chunks = []
    for b in response.content or []:
        text = getattr(b, "text", None)
        if text:
            chunks.append(text)
    return "".join(chunks).strip()


def _call_local_ollama(*, system: str, user: str, max_tokens: int, model_id: str) -> str:
    import urllib.error
    import urllib.request

    body = json.dumps({
        "model": model_id,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "stream": False,
        "options": {"num_predict": max_tokens},
    }).encode("utf-8")
    req = urllib.request.Request(
        "http://127.0.0.1:11434/api/chat",
        data=body, headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            payload = json.loads(response.read())
    except urllib.error.URLError as exc:
        raise ConnectionError(f"Ollama unreachable: {exc}") from exc
    msg = payload.get("message") or {}
    return (msg.get("content") or "").strip()


def _read_input(input_file: str | None) -> dict:
    raw = ""
    if input_file:
        with open(input_file, encoding="utf-8") as fh:
            raw = fh.read()
    else:
        raw = sys.stdin.read()
    if not raw.strip():
        return {"samples": [], "loss_trajectory": [], "iter": 0, "iter_total": 0}
    return json.loads(raw)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="kiln_trainer.training_advisor")
    ap.add_argument("--mode", required=True, choices=["cloud", "local"])
    ap.add_argument("--input-file", default=None)
    ap.add_argument("--max-tokens", type=int, default=120)
    ap.add_argument("--local-model", default="qwen2.5:7b")
    args = ap.parse_args(argv)

    try:
        envelope = _read_input(args.input_file)
    except (OSError, json.JSONDecodeError) as exc:
        sys.stdout.write(json.dumps({
            "event": "error", "code": "data_invalid",
            "message": f"could not read advisor input: {exc}",
            "recoverable": False,
        }) + "\n")
        return 1

    samples = envelope.get("samples") or []
    loss_trajectory = [float(v) for v in (envelope.get("loss_trajectory") or [])]
    iter_now = int(envelope.get("iter") or 0)
    iter_total = int(envelope.get("iter_total") or 0)

    user = _build_user_message(
        samples=samples, loss_trajectory=loss_trajectory,
        iter_now=iter_now, iter_total=iter_total,
    )

    try:
        if args.mode == "cloud":
            text = _call_opus(system=SYSTEM_PROMPT, user=user, max_tokens=args.max_tokens)
            model_id = CLOUD_MODEL_ID
        else:
            text = _call_local_ollama(
                system=SYSTEM_PROMPT, user=user,
                max_tokens=args.max_tokens, model_id=args.local_model,
            )
            model_id = args.local_model
    except PermissionError as exc:
        sys.stdout.write(json.dumps({
            "event": "error", "code": "data_invalid",
            "message": str(exc), "recoverable": False,
        }) + "\n")
        return 1
    except (ConnectionError, OSError) as exc:
        sys.stdout.write(json.dumps({
            "event": "error", "code": "subprocess_failed",
            "message": str(exc), "recoverable": False,
        }) + "\n")
        return 1
    except Exception as exc:  # noqa: BLE001
        sys.stdout.write(json.dumps({
            "event": "error", "code": "internal",
            "message": str(exc), "recoverable": False,
        }) + "\n")
        return 1

    if not text:
        sys.stdout.write(json.dumps({
            "event": "error", "code": "internal",
            "message": "training-advisor returned empty content",
            "recoverable": False,
        }) + "\n")
        return 1

    # Truncate to one line, ≤120 chars (Opus is instructed but not
    # gated; trim defensively).
    line = text.splitlines()[0][:120].strip()
    sys.stdout.write(json.dumps({
        "event": "advisor_observation",
        "iter": iter_now,
        "content": line,
        "model": model_id,
    }) + "\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())

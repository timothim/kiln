"""``kiln_trainer voice-coach`` — Opus 4.7 post-export voice analyst (Phase 1).

After Ollama export succeeds the Swift app surfaces a "Get Voice Report"
CTA. This subcommand consumes the user's freshly-extracted style
signature plus a small batch of sample completions from their newly
trained adapter, sends them to Claude Opus 4.7 (or local Qwen2.5 via
Ollama in offline mode), and returns a 150-word markdown report
covering:

- dominant voice traits the model has captured,
- contrast vs. base Qwen patterns the user might want to push back on,
- watch-out areas where voice may drift,
- suggested corpus additions for the next training round.

The user opts in via Settings → Cloud features. The Swift caller
threads the API key (loaded from Keychain) into the environment
variable ``ANTHROPIC_API_KEY``; this subcommand never reads a key
from disk or argv. Local-mode (``--mode local``) uses the Ollama
daemon and calls a local model — strictly offline.

Wire format (one JSON object per line on stdout):

    {"event":"ready", ...}
    {"event":"voice_report","markdown":"<150-word markdown>","model":"claude-opus-4-7"}
    {"event":"done","stage":"generation","artifact":"stdout","interrupted":false}

Errors emit a structured ``error`` event before the terminal
``done``. Missing key → ``data_invalid``. Network failure →
``subprocess_failed``. The Swift caller maps these to user-visible
strings.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from kiln_trainer import events, runtime

CLOUD_MODEL_ID = "claude-opus-4-7"
LOCAL_MODEL_DEFAULT = "qwen2.5:7b"
SYSTEM_PROMPT = """You are the Kiln Voice Coach, a personal voice analyst whose job
is to read a user's freshly-extracted style signature and a handful of
sample completions from a model that just learned to write in their
voice. You produce one short markdown report (≈150 words), no more,
covering exactly four sections in this order:

## Dominant traits
What the model has clearly captured. Two or three concrete observations
keyed off the descriptors and ngrams the user supplied.

## Contrast with base
Where the fine-tuned voice has pulled away from the bland Qwen baseline.
Be specific.

## Watch-outs
One or two places the voice may drift on novel prompts. Tie this to the
samples you saw.

## Next training round
Two corpus suggestions (e.g. "more drafts under 400 words", "evening
journal entries"). Concrete and short.

Style: write in the user's own voice register where you can — short
declarative sentences if their corpus is terse, longer if verbose. No
filler, no "it's important to note", no AI-assistant scaffolding. The
report is for the user, not the user's manager.
"""


def _build_user_message(style_signature: dict, sample_completions: list[dict]) -> str:
    """Format the input so Opus has something concrete to react to.

    The signature carries the deterministic descriptors / ngrams the
    Style Signature card produced; the samples are typically the three
    Voice Mirror prompts (week_focus / birthday_msg / perfect_sunday)
    and their post-train completions."""
    parts: list[str] = []
    parts.append("## Style signature")
    parts.append(json.dumps(style_signature, indent=2, ensure_ascii=False))
    parts.append("")
    parts.append("## Sample completions")
    for s in sample_completions[:6]:
        prompt = s.get("prompt") or "(unknown prompt)"
        completion = s.get("completion") or ""
        parts.append(f"### Prompt: {prompt}")
        parts.append(completion.strip())
        parts.append("")
    return "\n".join(parts).strip()


def _call_opus(*, system: str, user: str, max_tokens: int) -> str:
    """Cloud path — Anthropic SDK with claude-opus-4-7. Lazily imports
    the SDK so the local-mode path doesn't pay the import cost."""
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
    blocks = response.content or []
    chunks: list[str] = []
    for b in blocks:
        text = getattr(b, "text", None)
        if text:
            chunks.append(text)
    return "".join(chunks).strip()


def _call_local_ollama(*, system: str, user: str, max_tokens: int, model_id: str) -> str:
    """Local mode — talks to the Ollama daemon at 127.0.0.1:11434.
    Quality drop vs Opus is real but expected; the Voice Coach UI
    rebadges the panel to ``Running locally with Qwen2.5`` so the user
    knows. Lazy ``urllib`` to avoid pulling httpx/requests."""
    import urllib.error
    import urllib.request

    body = json.dumps(
        {
            "model": model_id,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "stream": False,
            "options": {"num_predict": max_tokens},
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        "http://127.0.0.1:11434/api/chat",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            payload = json.loads(response.read())
    except urllib.error.URLError as exc:
        raise ConnectionError(f"Ollama daemon unreachable: {exc}") from exc
    msg = payload.get("message") or {}
    content = msg.get("content") or ""
    return content.strip()


def _read_input(input_file: str | None) -> dict:
    """Reads the {style_signature, sample_completions} envelope from
    ``--input-file`` or stdin. Defaults each side so a partial input
    still produces a sensible report."""
    raw = ""
    if input_file:
        with open(input_file, encoding="utf-8") as fh:
            raw = fh.read()
    else:
        raw = sys.stdin.read()
    if not raw.strip():
        return {"style_signature": {}, "sample_completions": []}
    obj = json.loads(raw)
    return {
        "style_signature": obj.get("style_signature") or {},
        "sample_completions": obj.get("sample_completions") or [],
    }


def run(args: argparse.Namespace) -> int:
    runtime.install_sigterm_handler()

    try:
        envelope = _read_input(args.input_file)
    except (OSError, json.JSONDecodeError) as exc:
        events.emit(
            events.error(
                code="data_invalid",
                message=f"could not read voice-coach input: {exc}",
                recoverable=False,
            )
        )
        events.emit(events.done(stage="generation", artifact="stdout", interrupted=False))
        return 1

    user = _build_user_message(
        envelope["style_signature"], envelope["sample_completions"]
    )

    try:
        if args.mode == "cloud":
            markdown = _call_opus(system=SYSTEM_PROMPT, user=user, max_tokens=args.max_tokens)
            model_id = CLOUD_MODEL_ID
        else:
            markdown = _call_local_ollama(
                system=SYSTEM_PROMPT,
                user=user,
                max_tokens=args.max_tokens,
                model_id=args.local_model,
            )
            model_id = args.local_model
    except PermissionError as exc:
        events.emit(
            events.error(
                code="data_invalid",
                message=str(exc),
                recoverable=False,
            )
        )
        events.emit(events.done(stage="generation", artifact="stdout", interrupted=False))
        return 1
    except (ConnectionError, OSError) as exc:
        events.emit(
            events.error(
                code="subprocess_failed",
                message=f"voice-coach call failed: {exc}",
                recoverable=False,
            )
        )
        events.emit(events.done(stage="generation", artifact="stdout", interrupted=False))
        return 1
    except Exception as exc:  # noqa: BLE001 — surface unknown SDK errors cleanly
        events.emit(
            events.error(
                code="internal",
                message=f"voice-coach unknown error: {exc}",
                recoverable=False,
            )
        )
        events.emit(events.done(stage="generation", artifact="stdout", interrupted=False))
        return 1

    if not markdown:
        events.emit(
            events.error(
                code="internal",
                message="voice-coach returned empty markdown",
                recoverable=False,
            )
        )
        events.emit(events.done(stage="generation", artifact="stdout", interrupted=False))
        return 1

    events.emit(
        {
            "event": "voice_report",
            "markdown": markdown,
            "model": model_id,
        }
    )
    events.emit(events.done(stage="generation", artifact="stdout", interrupted=False))
    return 0

#!/usr/bin/env python3
"""Monitor a Managed Agents session — live progress + token cost.

Usage:
  python scripts/managed-agents/monitor.py <session_id>
  python scripts/managed-agents/monitor.py <session_id> --summary      # one-shot
  python scripts/managed-agents/monitor.py <session_id> --extract      # parse RUN_COMPLETE output

Polls /v1/sessions/<id>/events every 15 seconds, accumulates token usage
from span.model_request_end events, and surfaces PROGRESS {...} lines from
agent.message events (the agent emits these after each batch).

Completion is detected by polling GET /v1/sessions/<id>.status == "idle"
AFTER the agent has emitted a RUN_COMPLETE or RUN_ABORTED marker — not by
any status event (the docs' status values are idle/running/rescheduling/
terminated; there is no "session.status_idle" event type).

--extract: after RUN_COMPLETE, parse the final agent message for
  RUN_MANIFEST_BEGIN/END and QUALITY_LABELS_BEGIN/END markers and write
  the contents to managed-agents/corpus-builder/runs/<ISO>/.
"""
import argparse
import datetime as _dt
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

API_BASE = "https://api.anthropic.com"
BETA_HDR = "managed-agents-2026-04-01"

OPUS_IN_PER_M = 15.0
OPUS_OUT_PER_M = 75.0

REPO = pathlib.Path(__file__).resolve().parents[2]
RUNS_DIR = REPO / "managed-agents" / "corpus-builder" / "runs"


def fetch(url: str) -> dict:
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        sys.exit("ANTHROPIC_API_KEY not set")
    req = urllib.request.Request(
        url=url,
        method="GET",
        headers={
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
            "anthropic-beta": BETA_HDR,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"GET {url} -> {e.code}\n{e.read().decode(errors='replace')}")


def extract_text(event: dict) -> str:
    """agent.message content is a list of content blocks: [{type:text, text:...}]."""
    content = event.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(block.get("text", ""))
        return "".join(parts)
    return ""


def between(text: str, begin: str, end: str) -> str | None:
    i = text.find(begin)
    j = text.find(end, i + len(begin)) if i >= 0 else -1
    if i < 0 or j < 0:
        return None
    return text[i + len(begin) : j].strip()


def write_extract(final_text: str) -> pathlib.Path:
    manifest_raw = between(final_text, "RUN_MANIFEST_BEGIN", "RUN_MANIFEST_END")
    labels_raw = between(final_text, "QUALITY_LABELS_BEGIN", "QUALITY_LABELS_END")
    if manifest_raw is None or labels_raw is None:
        sys.exit("Could not locate RUN_MANIFEST_* or QUALITY_LABELS_* markers in final message.")
    iso = _dt.datetime.now(_dt.UTC).strftime("%Y%m%dT%H%M%SZ")
    out = RUNS_DIR / iso
    out.mkdir(parents=True, exist_ok=True)
    (out / "run_manifest.json").write_text(manifest_raw + "\n")
    (out / "quality-labels.jsonl").write_text(labels_raw + "\n")
    print(f"-> wrote {out}/run_manifest.json")
    print(f"-> wrote {out}/quality-labels.jsonl")
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("session_id")
    ap.add_argument("--summary", action="store_true", help="single pass then exit")
    ap.add_argument("--extract", action="store_true", help="after RUN_COMPLETE, write runs/<ISO>/ locally")
    ap.add_argument("--interval", type=int, default=15)
    args = ap.parse_args()

    sid = args.session_id
    print(f"session: {sid}")
    print(f"timeline: https://console.claude.com/sessions/{sid}\n")

    tokens_in = 0
    tokens_out = 0
    last_seen = 0
    progress_count = 0
    final_text = ""
    run_complete = False
    run_aborted = False
    status = "?"
    start = time.time()

    while True:
        url = f"{API_BASE}/v1/sessions/{sid}/events?limit=200"
        if last_seen:
            url += f"&after={last_seen}"
        events = fetch(url)
        for e in events.get("data", []):
            seq = e.get("sequence_number")
            if seq is not None:
                last_seen = seq
            t = e.get("type", "")
            if t == "span.model_request_end":
                usage = (e.get("model_usage") or {})
                tokens_in += int(usage.get("input_tokens") or 0)
                tokens_out += int(usage.get("output_tokens") or 0)
            elif t == "agent.message":
                text = extract_text(e)
                final_text += text
                for line in text.splitlines():
                    stripped = line.strip()
                    if stripped.startswith("PROGRESS"):
                        progress_count += 1
                        stamp = time.strftime("%H:%M:%S")
                        print(f"[{stamp}] {stripped}")
                    elif stripped == "RUN_COMPLETE":
                        run_complete = True
                    elif stripped == "RUN_ABORTED":
                        run_aborted = True

        cost = tokens_in * OPUS_IN_PER_M / 1_000_000 + tokens_out * OPUS_OUT_PER_M / 1_000_000
        elapsed = int(time.time() - start)
        print(
            f"  tok_in={tokens_in:>8,}  tok_out={tokens_out:>7,}  "
            f"cost~=${cost:6.2f}  progress={progress_count}  elapsed={elapsed}s"
        )
        if cost > 10.0 and progress_count > 0:
            print("  ** cost exceeded $10 alert threshold")

        session = fetch(f"{API_BASE}/v1/sessions/{sid}")
        status = session.get("status", "?")
        if args.summary:
            break
        if status == "terminated":
            print(f"-> session terminated")
            break
        if status == "idle" and (run_complete or run_aborted):
            break
        time.sleep(args.interval)

    print(f"\n-- status={status} run_complete={run_complete} run_aborted={run_aborted} --")
    print(
        f"final: tok_in={tokens_in:,} tok_out={tokens_out:,} "
        f"cost~=${cost:.2f} elapsed={int(time.time()-start)}s"
    )

    if args.extract and run_complete:
        write_extract(final_text)
    elif args.extract and run_aborted:
        print("-> run aborted; writing manifest only")
        manifest_raw = between(final_text, "RUN_MANIFEST_BEGIN", "RUN_MANIFEST_END")
        if manifest_raw is not None:
            iso = _dt.datetime.now(_dt.UTC).strftime("%Y%m%dT%H%M%SZ")
            out = RUNS_DIR / f"{iso}_aborted"
            out.mkdir(parents=True, exist_ok=True)
            (out / "run_manifest.json").write_text(manifest_raw + "\n")
            print(f"-> wrote {out}/run_manifest.json")


if __name__ == "__main__":
    main()

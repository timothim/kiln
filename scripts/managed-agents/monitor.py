#!/usr/bin/env python3
"""Monitor a Managed Agents session — live progress + token cost.

Usage:
  python scripts/managed-agents/monitor.py <session_id>
  python scripts/managed-agents/monitor.py <session_id> --summary   # one-shot

Polls /v1/sessions/<id>/events every 15 seconds, accumulates token usage
from span.model_request_end events, and surfaces "PROGRESS:" lines from
agent.message events (the labeling script emits these every 50 labels).

Exits when session.status_idle arrives or session.error is seen.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

API_BASE = "https://api.anthropic.com"
BETA_HDR = "managed-agents-2026-04-01"

# claude-opus-4-7 posted pricing (USD per 1M tokens) as of April 2026.
OPUS_IN_PER_M = 15.0
OPUS_OUT_PER_M = 75.0


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
        sys.exit(f"GET {url} → {e.code}\n{e.read().decode(errors='replace')}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("session_id")
    ap.add_argument("--summary", action="store_true", help="single pass then exit")
    ap.add_argument("--interval", type=int, default=15)
    args = ap.parse_args()

    sid = args.session_id
    print(f"session: {sid}")
    print(f"timeline: https://console.claude.com/sessions/{sid}\n")

    tokens_in = 0
    tokens_out = 0
    last_seen = 0
    progress_count = 0
    seen_idle = False
    start = time.time()

    while True:
        url = f"{API_BASE}/v1/sessions/{sid}/events?limit=200"
        if last_seen:
            url += f"&after={last_seen}"
        events = fetch(url)
        data = events.get("data", [])
        for e in data:
            last_seen = e.get("sequence_number", last_seen)
            t = e.get("type", "")
            if t == "span.model_request_end":
                usage = e.get("model_usage", {}) or {}
                tokens_in += int(usage.get("input_tokens", 0) or 0)
                tokens_out += int(usage.get("output_tokens", 0) or 0)
            elif t == "agent.message":
                content = e.get("content", "") or ""
                for line in content.splitlines():
                    if line.startswith("PROGRESS:"):
                        progress_count += 1
                        stamp = time.strftime("%H:%M:%S")
                        print(f"[{stamp}] {line.strip()}")
            elif t == "session.error":
                print(f"[ERROR] {json.dumps(e, indent=2)[:500]}")
            elif t == "session.status_idle":
                seen_idle = True

        cost = tokens_in * OPUS_IN_PER_M / 1_000_000 + tokens_out * OPUS_OUT_PER_M / 1_000_000
        elapsed = int(time.time() - start)
        print(
            f"  tok_in={tokens_in:>8,}  tok_out={tokens_out:>7,}  cost≈${cost:6.2f}  "
            f"progress={progress_count}  elapsed={elapsed}s"
        )

        if cost > 10.0 and progress_count > 0:
            print("  ⚠️  cost exceeded $10 alert threshold")

        if seen_idle or args.summary:
            break
        time.sleep(args.interval)

    print("\n— session idle —")
    print(f"final: tok_in={tokens_in:,} tok_out={tokens_out:,} cost≈${cost:.2f} elapsed={int(time.time()-start)}s")


if __name__ == "__main__":
    main()

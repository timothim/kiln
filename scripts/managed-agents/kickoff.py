#!/usr/bin/env python3
"""Kickoff: create the real pilot session and send the protocol-start message.

Assumes upload.py + deploy.py have already populated AGENT_ID / ENV_ID /
INPUT_FILE_ID. Writes SESSION_ID back to the same env file so monitor.py
can be invoked without copy-paste.

Usage:
  python scripts/managed-agents/kickoff.py --component preference-judge
"""
import argparse
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

API_BASE = "https://api.anthropic.com"
BETA_HDR = "managed-agents-2026-04-01"
OUT_ENV = pathlib.Path(os.environ.get("EXPORT_ENV", "/tmp/kiln-distill.env"))


def _env(key: str) -> str:
    v = os.environ.get(key)
    if not v:
        sys.exit(f"{key} not set — source {OUT_ENV} first")
    return v


def request(method: str, path: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode("utf-8") if body else None
    req = urllib.request.Request(
        url=f"{API_BASE}{path}",
        data=data,
        method=method,
        headers={
            "x-api-key": _env("ANTHROPIC_API_KEY"),
            "anthropic-version": "2023-06-01",
            "anthropic-beta": BETA_HDR,
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path} -> {e.code} {e.reason}\n{e.read().decode(errors='replace')}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--component",
        required=True,
        choices=["corpus-builder", "preference-judge", "style-extractor"],
        help="which distilled component this run is for (flows into session metadata + monitor output dir)",
    )
    ap.add_argument(
        "--run-label",
        default="pilot",
        help="short label surfaced in session metadata (default: pilot)",
    )
    args = ap.parse_args()

    agent_id = _env("AGENT_ID")
    env_id = _env("ENV_ID")
    input_file_id = _env("INPUT_FILE_ID")

    session_body = {
        "agent": agent_id,
        "environment_id": env_id,
        "resources": [
            {
                "type": "file",
                "file_id": input_file_id,
                "mount_path": "/workspace/input.jsonl",
            }
        ],
        "metadata": {"component": args.component, "run": args.run_label},
    }

    print(f"-> POST /v1/sessions  component={args.component} run={args.run_label}")
    sesn = request("POST", "/v1/sessions", session_body)
    sid = sesn["id"]
    print(f"  session_id={sid}")

    kickoff_text = (
        "Begin the protocol defined in your system prompt. The input is mounted at "
        "/mnt/session/uploads/workspace/input.jsonl. Write outputs under /workspace/. "
        "Follow all steps in order, emit PROGRESS messages between batches, and finish "
        "with the RUN_COMPLETE marker sequence."
    )

    print("-> sending kickoff message...")
    request(
        "POST",
        f"/v1/sessions/{sid}/events",
        {
            "events": [
                {
                    "type": "user.message",
                    "content": [{"type": "text", "text": kickoff_text}],
                }
            ]
        },
    )

    # Persist SESSION_ID for the monitor script.
    existing = OUT_ENV.read_text() if OUT_ENV.exists() else ""
    lines = [line for line in existing.splitlines() if not line.startswith("export SESSION_ID=")]
    lines.append(f"export SESSION_ID={sid}")
    OUT_ENV.write_text("\n".join(lines) + "\n")
    print(f"-> appended SESSION_ID to {OUT_ENV}")
    print(f"Next: python3 scripts/managed-agents/monitor.py {sid} --component {args.component}")


if __name__ == "__main__":
    main()

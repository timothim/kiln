#!/usr/bin/env python3
"""Preflight: short session that verifies the agent + environment + mounted input
resolve correctly before spending real tokens on the 500-sample pilot.

No API key is required inside the container. This agent is Opus 4.7 and labels rows
in its own inference loop; the container has no ANTHROPIC_API_KEY and doesn't need one.

Environment (required on the caller):
  ANTHROPIC_API_KEY, AGENT_ID, ENV_ID, INPUT_FILE_ID
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

API_BASE = "https://api.anthropic.com"
BETA_HDR = "managed-agents-2026-04-01"


def _env(key: str) -> str:
    v = os.environ.get(key)
    if not v:
        sys.exit(f"{key} not set")
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
        "metadata": {"run": "preflight"},
    }

    print("-> creating preflight session...")
    sesn = request("POST", "/v1/sessions", session_body)
    sid = sesn["id"]
    print(f"  session_id={sid}")

    prompt_text = (
        "Preflight. Do these three checks and report PREFLIGHT_OK on a single line if all pass, "
        "or PREFLIGHT_FAIL step <N> <reason> if any fails. Do not print secrets.\n"
        "1) bash: test -f /workspace/input.jsonl && head -1 /workspace/input.jsonl | head -c 200\n"
        "2) bash: wc -l /workspace/input.jsonl\n"
        "3) Confirm the mounted file is read-only by attempting: bash: touch /workspace/input.jsonl "
        "(expected: permission denied — report that as 'step 3 ok: read-only confirmed')."
    )

    print("-> sending preflight message...")
    request(
        "POST",
        f"/v1/sessions/{sid}/events",
        {
            "events": [
                {
                    "type": "user.message",
                    "content": [{"type": "text", "text": prompt_text}],
                }
            ]
        },
    )

    print("-> polling for completion (up to 180s)...")
    deadline = time.time() + 180
    final_text = ""
    last_seen = 0
    done = False
    while time.time() < deadline and not done:
        events = request("GET", f"/v1/sessions/{sid}/events?limit=50&after={last_seen}")
        for e in events.get("data", []):
            seq = e.get("sequence_number")
            if seq is not None:
                last_seen = seq
            if e.get("type") == "agent.message":
                content = e.get("content", [])
                if isinstance(content, list):
                    for block in content:
                        if isinstance(block, dict) and block.get("type") == "text":
                            final_text += block.get("text", "")
                elif isinstance(content, str):
                    final_text += content
        # Stop when the session returns to idle (cheap re-check; costs one read).
        status = request("GET", f"/v1/sessions/{sid}").get("status")
        if status in ("idle", "terminated") and final_text:
            done = True
            break
        time.sleep(3)

    print("\n--- agent output ---\n" + final_text + "\n---\n")
    if "PREFLIGHT_OK" in final_text:
        print("-> preflight passed")
        request("POST", f"/v1/sessions/{sid}/archive", {})
        sys.exit(0)
    print("-> preflight FAILED")
    sys.exit(1)


if __name__ == "__main__":
    main()

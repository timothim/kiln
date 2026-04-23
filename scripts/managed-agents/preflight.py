#!/usr/bin/env python3
"""Preflight: 10-second session that verifies the agent can see ANTHROPIC_API_KEY,
can reach /workspace/kiln as a git repo, and can call Opus once.

Exits non-zero on any assertion failure so the caller can abort before spending
real tokens on the 500-sample pilot.

Environment (required):
  ANTHROPIC_API_KEY, AGENT_ID, ENV_ID, VAULT_ID, GITHUB_PAT
"""
import json
import os
import pathlib
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
        sys.exit(f"{method} {path} → {e.code} {e.reason}\n{e.read().decode(errors='replace')}")


def main() -> None:
    agent_id = _env("AGENT_ID")
    env_id = _env("ENV_ID")
    vault_id = _env("VAULT_ID")
    github_pat = _env("GITHUB_PAT")

    session_body = {
        "agent_id": agent_id,
        "environment_id": env_id,
        "vault_ids": [vault_id],
        "resources": [
            {
                "type": "github_repository",
                "url": "https://github.com/timothim/kiln",
                "mount_path": "/workspace/kiln",
                "authorization_token": github_pat,
                "branch": "main",
                "depth": 1,
            }
        ],
        "metadata": {"run": "preflight"},
    }

    print("→ creating preflight session…")
    sesn = request("POST", "/v1/sessions", session_body)
    sid = sesn["id"]
    print(f"  session_id={sid}")

    prompt = (
        "Preflight. Run these three checks. Do NOT print the value of ANTHROPIC_API_KEY — presence only.\n"
        "1) test -n \"$ANTHROPIC_API_KEY\" && echo API_KEY_PRESENT || echo API_KEY_MISSING\n"
        "2) cd /workspace/kiln && git log -1 --oneline  # should show a commit\n"
        "3) python -c \"from anthropic import Anthropic; c=Anthropic(); r=c.messages.create(model='claude-opus-4-7', max_tokens=10, messages=[{'role':'user','content':'ping'}]); print(r.content[0].text)\"\n"
        "Print PREFLIGHT_OK as the final line if step 1 prints API_KEY_PRESENT and steps 2 and 3 succeed, otherwise PREFLIGHT_FAIL with the failing step number."
    )
    print("→ sending preflight message…")
    request("POST", f"/v1/sessions/{sid}/events", {"events": [{"type": "user.message", "content": prompt}]})

    print("→ polling for completion (up to 180s)…")
    deadline = time.time() + 180
    final_text = ""
    seen_idle = False
    last_seen = 0
    while time.time() < deadline:
        events = request("GET", f"/v1/sessions/{sid}/events?limit=50&after={last_seen}")
        for e in events.get("data", []):
            last_seen = e.get("sequence_number", last_seen)
            t = e.get("type", "")
            if t == "agent.message":
                final_text += e.get("content", "")
            if t == "session.status_idle":
                seen_idle = True
        if seen_idle:
            break
        time.sleep(3)

    print("\n--- agent output ---\n" + final_text + "\n---\n")
    if "PREFLIGHT_OK" in final_text:
        print("→ preflight passed")
        # Archive the session; we don't need it
        request("POST", f"/v1/sessions/{sid}/archive", {})
        sys.exit(0)
    else:
        print("→ preflight FAILED")
        sys.exit(1)


if __name__ == "__main__":
    main()

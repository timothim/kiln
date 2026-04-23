#!/usr/bin/env python3
"""Deploy the Kiln Distillation Orchestrator agent + environment.

Assembles the agent config (merging system-prompt.txt into agent.json),
POSTs /v1/agents and /v1/environments, and writes the resulting IDs
to /tmp/kiln-distill.env for shell sourcing.

Idempotency: re-running creates a new version of each; the caller can
pin to a specific version via the exported IDs if needed.
"""
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

REPO = pathlib.Path(__file__).resolve().parents[2]
AGENT_DIR = REPO / "managed-agents" / "corpus-builder"
OUT_ENV = pathlib.Path(os.environ.get("EXPORT_ENV", "/tmp/kiln-distill.env"))

API_BASE = "https://api.anthropic.com"
BETA_HDR = "managed-agents-2026-04-01"


def _require_api_key() -> str:
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        sys.exit("ANTHROPIC_API_KEY not set — export it and retry.")
    return key


def post(path: str, body: dict, api_key: str) -> dict:
    req = urllib.request.Request(
        url=f"{API_BASE}{path}",
        data=json.dumps(body).encode("utf-8"),
        method="POST",
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "anthropic-beta": BETA_HDR,
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        sys.exit(f"POST {path} failed: {e.code} {e.reason}\n{body}")


def main() -> None:
    api_key = _require_api_key()

    agent = json.loads((AGENT_DIR / "agent.json").read_text())
    agent["system"] = (AGENT_DIR / "system-prompt.txt").read_text()
    env = json.loads((AGENT_DIR / "environment.json").read_text())

    print(f"→ POST /v1/agents  name={agent['name']} model={agent['model']}")
    agent_resp = post("/v1/agents", agent, api_key)
    agent_id = agent_resp.get("id")
    agent_version = agent_resp.get("version", "?")
    print(f"  agent_id={agent_id} version={agent_version}")

    print(f"→ POST /v1/environments  name={env['name']}")
    env_resp = post("/v1/environments", env, api_key)
    env_id = env_resp.get("id")
    env_version = env_resp.get("version", "?")
    print(f"  env_id={env_id} version={env_version}")

    OUT_ENV.write_text(
        f"export AGENT_ID={agent_id}\n"
        f"export AGENT_VERSION={agent_version}\n"
        f"export ENV_ID={env_id}\n"
        f"export ENV_VERSION={env_version}\n"
    )
    print(f"→ wrote {OUT_ENV}")
    print("Next: source /tmp/kiln-distill.env && upload the input JSONL.")


if __name__ == "__main__":
    main()

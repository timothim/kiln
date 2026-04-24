#!/usr/bin/env python3
"""Deploy a Kiln managed-agent + environment (corpus-builder or preference-judge).

Assembles the agent config (merging system-prompt.txt into agent.json),
POSTs /v1/agents and /v1/environments, and writes the resulting IDs
to /tmp/kiln-distill.env (or $EXPORT_ENV) for shell sourcing.

Idempotency: re-running creates a new version of each; the caller can
pin to a specific version via the exported IDs if needed.

Usage:
  python scripts/managed-agents/deploy.py                            # default: corpus-builder
  python scripts/managed-agents/deploy.py --agent-dir managed-agents/preference-judge
  AGENT_DIR=managed-agents/preference-judge python scripts/managed-agents/deploy.py
  EXPORT_ENV=/tmp/kiln-preference.env python scripts/managed-agents/deploy.py --agent-dir managed-agents/preference-judge
"""
import argparse
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

REPO = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_AGENT_DIR = REPO / "managed-agents" / "corpus-builder"
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


def _resolve_agent_dir(cli_value: str | None) -> pathlib.Path:
    """CLI arg > env var > default. Accept relative paths (resolved against REPO) or absolute."""
    raw = cli_value or os.environ.get("AGENT_DIR")
    if not raw:
        return DEFAULT_AGENT_DIR
    p = pathlib.Path(raw)
    if not p.is_absolute():
        p = REPO / p
    if not p.is_dir():
        sys.exit(f"agent dir not found: {p}")
    return p


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--agent-dir",
        default=None,
        help="path to managed-agents/<component>/ (default: corpus-builder; or set $AGENT_DIR)",
    )
    args = ap.parse_args()

    api_key = _require_api_key()
    agent_dir = _resolve_agent_dir(args.agent_dir)
    print(f"-> using agent dir: {agent_dir.relative_to(REPO)}")

    agent = json.loads((agent_dir / "agent.json").read_text())
    agent["system"] = (agent_dir / "system-prompt.txt").read_text()
    env = json.loads((agent_dir / "environment.json").read_text())

    print(f"-> POST /v1/agents  name={agent['name']} model={agent['model']}")
    agent_resp = post("/v1/agents", agent, api_key)
    agent_id = agent_resp.get("id")
    agent_version = agent_resp.get("version", "?")
    print(f"  agent_id={agent_id} version={agent_version}")

    print(f"-> POST /v1/environments  name={env['name']}")
    env_resp = post("/v1/environments", env, api_key)
    env_id = env_resp.get("id")
    print(f"  env_id={env_id}  (environments are not versioned)")

    OUT_ENV.write_text(
        f"export AGENT_ID={agent_id}\n"
        f"export AGENT_VERSION={agent_version}\n"
        f"export ENV_ID={env_id}\n"
    )
    print(f"-> wrote {OUT_ENV}")
    print("Next: source /tmp/kiln-distill.env && upload the input JSONL.")


if __name__ == "__main__":
    main()

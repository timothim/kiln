#!/usr/bin/env python3
"""Recover session output files produced by a managed-agent run.

Background
----------
The monitor script (scripts/managed-agents/monitor.py) extracts artifacts
by searching the accumulated `agent.message` text for RUN_MANIFEST_*/
<COMPONENT>_LABELS_* markers. That extraction path fails when:

  - the agent never emits the full payload inline in a final message
    (e.g. because container-level bash `cat` truncates large files);
  - the agent interleaves marker words inside narration before actually
    writing the block, confusing the first-match `between()` scan;
  - the agent emits the markers across several messages instead of one
    monolithic delivery block.

All three failure modes occurred in the full-run attempts on
2026-04-24. The agents, however, correctly copied their output files
into `/mnt/session/outputs/` inside the container, and the platform
exposes those files via `GET /v1/files?session_id=<id>` with a
`downloadable=true` flag. This script downloads them and lays them out
on disk in the same shape the monitor's --extract flag would have.

Usage
-----
  # recover by session id (looks up the expected filenames):
  python scripts/managed-agents/recover.py \\
      --component corpus-builder --session-id sesn_011CaNg9MmHC2hDbSvNE6rir

  # or recover all three from /tmp/kiln-*.env sourced into the env:
  python scripts/managed-agents/recover.py --all

Behavior
--------
For each component:
  1. list /v1/files?session_id=<id>
  2. find entries whose filename matches the expected labels + manifest
     for that component
  3. download both via /v1/files/<id>/content
  4. write them under managed-agents/<component>/runs/<new-ISO>_recovered/
  5. annotate the manifest with `recovered_via: "session files"`,
     `recovered_at: <ISO>`, and `recovery_source: { labels_file_id, ... }`
     so downstream consumers can tell at a glance that this run was
     extracted from session storage rather than from RUN_COMPLETE.

This script is intentionally read-only against the API (no POSTs, no
session mutations). It does NOT attempt to re-run an agent.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

API_BASE = "https://api.anthropic.com"
BETA_HDR = "managed-agents-2026-04-01"

REPO = pathlib.Path(__file__).resolve().parents[2]

COMPONENT_SETTINGS: dict[str, dict[str, str]] = {
    "corpus-builder": {
        "runs_dir": "managed-agents/corpus-builder/runs",
        "labels_filename": "quality-labels.jsonl",
        "manifest_filename": "run_manifest.json",
    },
    "preference-judge": {
        "runs_dir": "managed-agents/preference-judge/runs",
        "labels_filename": "preference-labels.jsonl",
        "manifest_filename": "run_manifest.json",
    },
    "style-extractor": {
        "runs_dir": "managed-agents/style-extractor/runs",
        "labels_filename": "style-profiles.jsonl",
        "manifest_filename": "run_manifest.json",
    },
}


def _api_key() -> str:
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        sys.exit("ANTHROPIC_API_KEY not set — export it and retry.")
    return key


def _headers(api_key: str) -> dict[str, str]:
    return {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "anthropic-beta": BETA_HDR,
    }


def _get_json(url: str, api_key: str) -> dict:
    req = urllib.request.Request(url=url, method="GET", headers=_headers(api_key))
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"GET {url} -> {e.code}\n{e.read().decode(errors='replace')}")


def _get_bytes(url: str, api_key: str) -> bytes:
    req = urllib.request.Request(url=url, method="GET", headers=_headers(api_key))
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        sys.exit(f"GET {url} -> {e.code}\n{e.read().decode(errors='replace')}")


def recover_one(component: str, session_id: str, api_key: str) -> pathlib.Path:
    cfg = COMPONENT_SETTINGS[component]
    files = _get_json(f"{API_BASE}/v1/files?session_id={session_id}", api_key).get(
        "data", []
    )
    labels = next(
        (f for f in files if f.get("filename") == cfg["labels_filename"]), None
    )
    manifest = next(
        (f for f in files if f.get("filename") == cfg["manifest_filename"]), None
    )
    if labels is None:
        sys.exit(f"[{component}] no {cfg['labels_filename']} in session {session_id}")
    if manifest is None:
        sys.exit(f"[{component}] no {cfg['manifest_filename']} in session {session_id}")
    if not labels.get("downloadable", False):
        sys.exit(f"[{component}] labels file not downloadable — check scope/permissions")

    labels_bytes = _get_bytes(
        f"{API_BASE}/v1/files/{labels['id']}/content", api_key
    )
    manifest_bytes = _get_bytes(
        f"{API_BASE}/v1/files/{manifest['id']}/content", api_key
    )
    manifest_obj = json.loads(manifest_bytes)

    now = _dt.datetime.now(_dt.UTC)
    manifest_obj["recovered_via"] = "session files (GET /v1/files)"
    manifest_obj["recovered_at"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    manifest_obj["recovery_source"] = {
        "session_id": session_id,
        "labels_file_id": labels["id"],
        "labels_size_bytes": labels.get("size_bytes"),
        "manifest_file_id": manifest["id"],
    }

    iso = now.strftime("%Y%m%dT%H%M%SZ")
    out = REPO / cfg["runs_dir"] / f"{iso}_recovered"
    out.mkdir(parents=True, exist_ok=True)
    (out / cfg["labels_filename"]).write_bytes(labels_bytes)
    (out / cfg["manifest_filename"]).write_text(
        json.dumps(manifest_obj, indent=2) + "\n"
    )
    print(
        f"[{component}] -> {out}/{cfg['labels_filename']} "
        f"({labels.get('size_bytes')} bytes) + {cfg['manifest_filename']}"
    )
    return out


def _load_env_file(path: pathlib.Path) -> dict[str, str]:
    env: dict[str, str] = {}
    if not path.exists():
        return env
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export "):]
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip()
    return env


def _discover_all() -> list[tuple[str, str]]:
    """Pull session IDs for each component from /tmp/kiln-*.env files.

    Convention used by scripts/managed-agents/kickoff.py:
      /tmp/kiln-quality.env      -> corpus-builder
      /tmp/kiln-preference.env   -> preference-judge
      /tmp/kiln-style.env        -> style-extractor
    """
    mapping = {
        "corpus-builder": pathlib.Path("/tmp/kiln-quality.env"),
        "preference-judge": pathlib.Path("/tmp/kiln-preference.env"),
        "style-extractor": pathlib.Path("/tmp/kiln-style.env"),
    }
    out: list[tuple[str, str]] = []
    for component, env_path in mapping.items():
        env = _load_env_file(env_path)
        sid = env.get("SESSION_ID")
        if sid:
            out.append((component, sid))
        else:
            print(f"[{component}] no SESSION_ID in {env_path}; skipping", file=sys.stderr)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--component",
        choices=list(COMPONENT_SETTINGS.keys()),
        help="which component to recover",
    )
    ap.add_argument("--session-id", help="session id to recover from")
    ap.add_argument(
        "--all",
        action="store_true",
        help="recover all three components using /tmp/kiln-*.env conventions",
    )
    args = ap.parse_args()

    api_key = _api_key()

    if args.all:
        targets = _discover_all()
        if not targets:
            sys.exit("no sessions found in /tmp/kiln-*.env files")
    else:
        if not args.component or not args.session_id:
            sys.exit("provide --component and --session-id, or use --all")
        targets = [(args.component, args.session_id)]

    for component, sid in targets:
        recover_one(component, sid, api_key)


if __name__ == "__main__":
    main()

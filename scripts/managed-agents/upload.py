#!/usr/bin/env python3
"""Upload a JSONL input file to Anthropic's Files API; print the file_id.

Appends `export INPUT_FILE_ID=<id>` to $EXPORT_ENV (default /tmp/kiln-distill.env)
so the preflight / kickoff scripts can pick it up.

Usage:
  python scripts/managed-agents/upload.py managed-agents/preference-judge/inputs/pilot-300.jsonl
"""
import argparse
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request
import uuid

API_BASE = "https://api.anthropic.com"
# Upload with the Managed Agents beta header (not files-api-2025-04-14); the
# docs are explicit that files meant for session mounts use the managed-agents
# beta, and uploads made under files-api-* are classified differently and will
# mount as empty in a session. See docs/managed-agents-cheatsheet.md §6.1.
FILES_BETA = "managed-agents-2026-04-01"
OUT_ENV = pathlib.Path(os.environ.get("EXPORT_ENV", "/tmp/kiln-distill.env"))


def _require_api_key() -> str:
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        sys.exit("ANTHROPIC_API_KEY not set — source /tmp/kiln-secrets.env and retry.")
    return key


def _multipart(path: pathlib.Path) -> tuple[bytes, str]:
    boundary = f"----kiln-{uuid.uuid4().hex}"
    data = path.read_bytes()
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{path.name}"\r\n'
        f"Content-Type: application/octet-stream\r\n\r\n"
    ).encode("utf-8") + data + f"\r\n--{boundary}--\r\n".encode("utf-8")
    return body, boundary


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("file", help="path to the JSONL input file")
    args = ap.parse_args()

    api_key = _require_api_key()
    path = pathlib.Path(args.file).resolve()
    if not path.is_file():
        sys.exit(f"file not found: {path}")

    body, boundary = _multipart(path)
    print(f"-> POST /v1/files  file={path.name}  size={len(body)} bytes")
    req = urllib.request.Request(
        url=f"{API_BASE}/v1/files",
        data=body,
        method="POST",
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "anthropic-beta": FILES_BETA,
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            resp = json.loads(r.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"POST /v1/files failed: {e.code} {e.reason}\n{e.read().decode(errors='replace')}")

    file_id = resp.get("id")
    if not file_id:
        sys.exit(f"no id in response: {resp}")

    # Append to the shared env file so preflight / kickoff can pick it up.
    existing = OUT_ENV.read_text() if OUT_ENV.exists() else ""
    lines = [line for line in existing.splitlines() if not line.startswith("export INPUT_FILE_ID=")]
    lines.append(f"export INPUT_FILE_ID={file_id}")
    OUT_ENV.write_text("\n".join(lines) + "\n")

    print(f"  file_id={file_id}")
    print(f"-> appended INPUT_FILE_ID to {OUT_ENV}")
    print(f"Next: source {OUT_ENV} && python3 scripts/managed-agents/preflight.py")


if __name__ == "__main__":
    main()

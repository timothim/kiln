#!/usr/bin/env bash
# post-tool-use: format edited files after any Write/Edit tool call.
# Registered in .claude/settings.json -> hooks.PostToolUse.
# Docs: https://code.claude.com/docs/en/hooks-guide
#
# Input: JSON on stdin with shape {"tool_name": "...", "tool_input": {...}, "tool_response": {...}}
# Output: any non-zero exit is non-fatal to Claude Code; the hook logs and returns 0 unless
#         a fatal misconfiguration is detected.

set -u
LC_ALL=C

payload="$(cat)"
tool_name="$(printf '%s' "$payload" | /usr/bin/env python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")"

case "$tool_name" in
  Write|Edit|MultiEdit)
    file_path="$(printf '%s' "$payload" | /usr/bin/env python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")"
    ;;
  *)
    exit 0
    ;;
esac

[ -z "${file_path}" ] && exit 0
[ ! -f "${file_path}" ] && exit 0

case "${file_path}" in
  *.swift)
    if command -v swift-format >/dev/null 2>&1; then
      swift-format -i "${file_path}" 2>/dev/null || true
    fi
    ;;
  *.py)
    if command -v ruff >/dev/null 2>&1; then
      ruff format "${file_path}" >/dev/null 2>&1 || true
      ruff check --fix --quiet "${file_path}" >/dev/null 2>&1 || true
    fi
    ;;
  *.json)
    if command -v jq >/dev/null 2>&1; then
      tmp="$(mktemp)"
      if jq '.' "${file_path}" > "${tmp}" 2>/dev/null; then
        mv "${tmp}" "${file_path}"
      else
        rm -f "${tmp}"
      fi
    fi
    ;;
esac

exit 0

#!/usr/bin/env bash
# pre-commit: block a git commit unless `make test` passes, and also
# `make design-lint` when DESIGN.md is staged.
# Registered in .claude/settings.json -> hooks.PreToolUse (Bash, matching `git commit`).
# Docs: https://code.claude.com/docs/en/hooks-guide
#
# Input: JSON on stdin with shape {"tool_name": "Bash", "tool_input": {"command": "..."}}
# Decision: exit 2 (with "deny" JSON on stdout) if any gate fails. Exit 0 otherwise.

set -u
LC_ALL=C

payload="$(cat)"
command_text="$(printf '%s' "$payload" | /usr/bin/env python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("command",""))' 2>/dev/null || echo "")"

case "$command_text" in
  *"git commit"*)
    ;;
  *)
    exit 0
    ;;
esac

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "${repo_root}" ] && exit 0

cd "${repo_root}" || exit 0

if ! command -v make >/dev/null 2>&1; then
  exit 0
fi

# --- Gate 1: design-lint when DESIGN.md is staged ------------------------

staged="$(git diff --cached --name-only 2>/dev/null || echo "")"
case "$staged" in
  *DESIGN.md*)
    if ! make design-lint >/tmp/kiln-pre-commit-design.log 2>&1; then
      cat >&2 <<MSG
[pre-commit] \`make design-lint\` failed. DESIGN.md has structural errors.
Log: /tmp/kiln-pre-commit-design.log (tail below)
---
$(tail -40 /tmp/kiln-pre-commit-design.log 2>/dev/null)
MSG
      printf '{"decision":"deny","reason":"make design-lint failed; see /tmp/kiln-pre-commit-design.log"}\n'
      exit 2
    fi
    ;;
esac

# --- Gate 2: make test ---------------------------------------------------

if make -q test >/dev/null 2>&1; then
  :
fi

if ! make test >/tmp/kiln-pre-commit.log 2>&1; then
  cat >&2 <<MSG
[pre-commit] \`make test\` failed. Fix tests before committing.
Log: /tmp/kiln-pre-commit.log (tail below)
---
$(tail -40 /tmp/kiln-pre-commit.log 2>/dev/null)
MSG
  printf '{"decision":"deny","reason":"make test failed; see /tmp/kiln-pre-commit.log"}\n'
  exit 2
fi

exit 0

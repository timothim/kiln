#!/usr/bin/env bash
# stop: on session end, append a five-bullet summary to SESSION_LOG.md.
# Registered in .claude/settings.json -> hooks.Stop.
# Docs: https://code.claude.com/docs/en/hooks-guide
#
# Uses `claude -p` (headless) to summarize the session. If the CLI is not available,
# falls back to a bare timestamp entry.

set -u
LC_ALL=C

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "${repo_root}" ] && repo_root="$(pwd)"
log_file="${repo_root}/SESSION_LOG.md"
[ ! -f "${log_file}" ] && exit 0

ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
branch="$(git -C "${repo_root}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(no branch)")"
touched="$(git -C "${repo_root}" diff --name-only HEAD~1..HEAD 2>/dev/null | head -20 | sed 's/^/    - /')"
[ -z "${touched}" ] && touched="    - (no committed changes since last stop)"

summary=""
if command -v claude >/dev/null 2>&1; then
  summary="$(claude -p "Summarize this Claude Code session in exactly 5 terse bullet points. Use imperative voice. No preamble." 2>/dev/null || true)"
fi
[ -z "${summary}" ] && summary="- (summary unavailable; claude CLI not on PATH)"

test_status="unknown"
if [ -f "${repo_root}/.kiln-last-test-status" ]; then
  test_status="$(cat "${repo_root}/.kiln-last-test-status")"
fi

{
  printf '\n## %s — branch `%s`\n\n' "${ts}" "${branch}"
  printf '%s\n\n' "${summary}"
  printf '**Files touched**\n\n%s\n\n' "${touched}"
  printf '**Tests:** %s\n' "${test_status}"
} >> "${log_file}"

exit 0

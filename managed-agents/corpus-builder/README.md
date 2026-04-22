# Managed Agent — Corpus Builder

A Claude Managed Agent that pulls the user's authorized content from cloud sources and writes normalized JSONL chunks that Kiln then ingests.

Reference: <https://claude.com/blog/claude-managed-agents>.

## Why managed

This workload is:

- **Long-running.** Initial pulls from a Gmail account can take hours; ongoing deltas run for minutes.
- **Resumable.** We keep a per-source cursor and survive restarts.
- **Secret-holding.** OAuth tokens for each connector; better held by the managed agent than by Kiln.app.
- **Multi-service.** Gmail, Notion, GitHub, Slack — a local sidecar would need to juggle four protocols.

These are the exact axes Anthropic's Managed Agents post calls out. We use a managed agent because we would want one even if they didn't give us $5K for it.

## MCP servers used

| Server | Scope | Fallback if not connected |
|---|---|---|
| Gmail | sent-by-user mails (last 365 days, not promotional) | skipped; warn in logs |
| Notion | user's workspaces (databases + pages) | skipped |
| GitHub | user's authored PR descriptions, issue comments, markdown files in personal repos | skipped |
| Slack | DMs authored by the user in connected workspaces | skipped |

No server is required. The agent scales to whichever subset the user has connected.

## What it emits

One JSONL file per source under the target folder (default: `~/Library/Application Support/Kiln/corpus/`):

- `gmail.jsonl` — one row per email authored by the user.
- `notion.jsonl` — one row per block or short doc (≥ 40 words).
- `github.jsonl` — one row per authored comment or PR description.
- `slack.jsonl` — one row per DM authored by the user.

Each row is: `{"source": <name>, "timestamp": <iso8601>, "text": <string>, "source_id": <string>}`.

## How Claude Code deploys it

```
claude agents deploy managed-agents/corpus-builder/agent.yaml
claude agents run corpus-builder --since=<YYYY-MM-DD>
```

To schedule:

```
claude agents schedule corpus-builder --cron "0 */6 * * *"
```

## State and resumption

The agent maintains `state.json` at its own storage path (not in the repo). This file holds the per-source cursor. Re-running with no `--since` resumes from the cursor.

## Secrets

All OAuth tokens live in the managed agent's secret store — never in this repo, never passed to Kiln.app. Kiln.app never sees a token; it only sees the JSONL files.

## Eval

- Target throughput: ≥ 5,000 rows per hour per source when online.
- Target recall: ≥ 95% of user-authored content within the date range (spot-checked against a known truth set for the primary user).
- Privacy invariant: no content written to the repo, ever. The managed agent runs in the cloud; its output lands on the user's Mac.

# Managed Agent — Distillation Orchestrator

A Claude Managed Agent that runs the Opus-as-teacher labeling pass for Kiln's `quality-classifier` distilled component. Deployed as part of the April 2026 "Built with Opus 4.7" hackathon's *Best Use of Managed Agents* submission.

Reference: [docs/managed-agents-cheatsheet.md](../../docs/managed-agents-cheatsheet.md) (compiled from the real Managed Agents documentation).

Directory history: this path was originally reserved for an "MCP Corpus Puller" agent that would pull authored content from Gmail/Notion/GitHub/Slack via MCP. That charter is deferred post-hackathon ([SPEC.md §8.3](../../SPEC.md)); the path now hosts the Distillation Orchestrator.

---

## What it does

Given a mounted JSONL of text snippets (one per line), the agent:

1. Writes a Python script `/workspace/labeler.py` that calls `claude-opus-4-7` concurrently (20-way async fan-out, backoff on 429/5xx).
2. Streams one label per input row to `runs/<ISO-UTC>/quality-labels.jsonl`, capturing score, reason, token counts, and raw Opus response.
3. Writes a `run_manifest.json` with git SHA, timestamps, cost estimate, and label counts.
4. Checks out `managed-agent/distillation-pilot`, commits the run directory, and pushes.

Output format (one JSON row per label):

```json
{
  "request_id": "…",
  "text": "…",
  "opus_response": { /* raw Messages-API response */ },
  "score": 0.83,
  "reason": "…",
  "latency_ms": 2840,
  "input_tokens": 612,
  "output_tokens": 38
}
```

The quality rubric used for each Opus sub-call comes from [`.claude/skills/distillation-pipeline/SKILL.md`](../../.claude/skills/distillation-pipeline/SKILL.md) §3.2 verbatim.

---

## Why managed, not in-app

This is the workload profile Managed Agents exist for:

- **Long-running.** 500-sample pilot: ~25 min wall clock; full 10k: ~8 h.
- **Observable.** The judge submission screenshots the per-turn Console timeline.
- **Secret-holding.** `ANTHROPIC_API_KEY` and the GitHub PAT live in the vault / resource mount — never on the developer's laptop, never in the repo.
- **Resumable.** If a future invocation fails mid-way, the input JSONL is idempotent (keyed on `request_id`), and we can resume from the last-committed label.

It would be strictly worse to run this from a local `scripts/opus-distill/run.py` on Tim's laptop: no cloud observability, no cost isolation, no reusable container.

---

## Files in this directory

| File | Purpose |
|---|---|
| `agent.json` | Agent config (name, model, tools, metadata). System prompt is injected from `system-prompt.txt` at deploy time. |
| `system-prompt.txt` | The operating instructions the agent follows. |
| `environment.json` | Cloud container spec (Ubuntu + pip packages + network allowlist + 60-min wall timeout). |
| `session.template.json` | Session creation body; `${VAR}` placeholders filled via `envsubst` at runtime. |
| `inputs/pilot-500.jsonl` *(gitignored)* | The 500-row input for the pilot run. Generated deterministically by `scripts/opus-distill/build_pilot_input.py`. |
| `runs/<ISO>/quality-labels.jsonl` | Labeled output, committed by the agent on `managed-agent/distillation-pilot`. |
| `runs/<ISO>/run_manifest.json` | Run metadata (git SHA, timestamps, token counts, cost). |

Helper scripts live in `scripts/managed-agents/`:

- `deploy.py` — create the agent + environment (idempotent; writes IDs to `/tmp/kiln-distill.env`).
- `preflight.py` — 10-second verification session to confirm secrets and mounts work before the real run.
- `monitor.py` — subscribes to the live event stream and prints progress + token cost.

---

## Deploying the pilot

Prerequisites (one-time):

```bash
brew install anthropics/tap/ant
ant auth login
export ANTHROPIC_API_KEY=…                 # your org API key
gh auth token > /tmp/github.pat            # PAT with `repo` scope
```

Deploy:

```bash
# 1. Build input locally
python scripts/opus-distill/build_pilot_input.py \
  --out managed-agents/corpus-builder/inputs/pilot-500.jsonl

# 2. Create vault with the API key
export VAULT_ID=$(ant beta:vaults create \
  --name kiln-distill-vault \
  --secret ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  --json | jq -r '.id')

# 3. Deploy agent + environment
python scripts/managed-agents/deploy.py
source /tmp/kiln-distill.env               # exports AGENT_ID, ENV_ID

# 4. Upload input
export INPUT_FILE_ID=$(ant beta:files upload \
  managed-agents/corpus-builder/inputs/pilot-500.jsonl \
  --json | jq -r '.id')

# 5. Pre-flight (10s verification session)
python scripts/managed-agents/preflight.py

# 6. Create + kickoff real session
GITHUB_PAT="$(cat /tmp/github.pat)" \
  envsubst < managed-agents/corpus-builder/session.template.json > /tmp/session.json
export SESSION_ID=$(ant beta:sessions create -f /tmp/session.json --json | jq -r '.id')
ant beta:sessions events send $SESSION_ID \
  --type user.message \
  --content "Begin the quality-classifier labeling pass. Follow the protocol in your system prompt exactly."
```

Monitor:

```bash
ant beta:sessions events stream $SESSION_ID          # live
python scripts/managed-agents/monitor.py $SESSION_ID # aggregated
open "https://console.claude.com/sessions/$SESSION_ID"
```

Stop:

```bash
ant beta:sessions events send $SESSION_ID --type user.interrupt
```

Retrieve output:

```bash
git fetch origin
git checkout managed-agent/distillation-pilot
ls managed-agents/corpus-builder/runs/
```

---

## Budget and success criteria

| Dimension | Target | Hard stop |
|---|---|---|
| Wall clock | ≤ 25 min | 55 min (agent aborts) / 60 min (container timeout) |
| Cost | ≤ $10 tokens + $0.03 container | $20 (agent aborts) |
| Labels written | ≥ 495 / 500 | — |
| Skipped after 3-retry | ≤ 5 | — |

Full pilot success criteria are in the plan: [.claude/plans/stateless-purring-quiche.md §6](../../.claude/plans/stateless-purring-quiche.md).

---

## Session stats (filled post-run)

- Pilot session ID: <!-- FILL after kickoff -->
- Agent version deployed: <!-- FILL -->
- Environment version: <!-- FILL -->
- Pilot wall clock: <!-- FILL -->
- Pilot cost: <!-- FILL -->
- Labels written: <!-- FILL -->
- Skipped: <!-- FILL -->
- Branch URL: <!-- FILL -->

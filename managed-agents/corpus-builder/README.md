# Managed Agent — Distillation Orchestrator

A Claude Managed Agent that produces Opus-4.7 quality labels for Kiln's `quality-classifier` distilled component. Deployed as part of the April 2026 "Built with Opus 4.7" hackathon's *Best Use of Managed Agents* submission.

Reference: [docs/managed-agents-cheatsheet.md](../../docs/managed-agents-cheatsheet.md) — every schema here is quoted from [platform.claude.com/docs/en/managed-agents](https://platform.claude.com/docs/en/managed-agents/overview).

Directory history: this path was originally reserved for an "MCP Corpus Puller" agent that would pull authored content from Gmail/Notion/GitHub/Slack via MCP. That charter is deferred post-hackathon ([SPEC.md §8.3](../../SPEC.md)); the path now hosts the Distillation Orchestrator.

---

## What it does

Given `/workspace/input.jsonl` (one `{request_id, text}` per line), the managed agent — which **is** Opus 4.7 — scores every row directly in its own inference loop using the rubric embedded in `system-prompt.txt`. There is no subprocess calling the Anthropic API from inside the container; the container never sees an API key.

The agent:

1. `read`s `/workspace/input.jsonl`.
2. In batches of ~50, produces `{request_id, text, score, reason}` for each row and `bash`-appends it to `/workspace/quality-labels.jsonl`. Emits a `PROGRESS {...}` `agent.message` after each batch.
3. `write`s `/workspace/run_manifest.json` with counts, timestamps, and score distribution.
4. Emits **one** final `agent.message` containing the full manifest + full labels JSONL between machine-readable markers (`RUN_MANIFEST_BEGIN/END`, `QUALITY_LABELS_BEGIN/END`, then `RUN_COMPLETE`). The developer's monitor script parses the markers and writes the output locally.

Output row format (one JSON object per line):

```json
{
  "request_id": "…",
  "text": "…",
  "score": 0.83,
  "reason": "coherent first-person voice, short but complete thought"
}
```

The rubric used for scoring is the one in [`.claude/skills/distillation-pipeline/SKILL.md`](../../.claude/skills/distillation-pipeline/SKILL.md) §3.2, inlined verbatim in `system-prompt.txt`.

---

## Why managed, not in-app

This is the workload profile Managed Agents exist for:

- **Long-running.** 500-sample pilot: ~25–40 min wall clock; full 10k: ~8–12 h.
- **Observable.** The judge submission screenshots the per-turn Console timeline at `console.claude.com/sessions/{id}`.
- **Reusable container.** Environment + agent are reusable across pilot, full run, and future preference-judge / style-extractor distillations.
- **Cost-isolated.** Session-hour meter is visible; local-laptop runs aren't.

It would be strictly worse to run this from `scripts/opus-distill/run.py` on Tim's laptop: no cloud observability, no cost isolation, no reusable configuration.

---

## Files in this directory

| File | Purpose |
|---|---|
| `agent.json` | Agent config (name, model, tools, metadata). System prompt is injected from `system-prompt.txt` at deploy time. |
| `system-prompt.txt` | The operating instructions the agent follows — including the labeling rubric verbatim. |
| `environment.json` | Cloud container spec: `{config: {type: "cloud", networking: {type: "unrestricted"}}}`. No pip packages needed (no in-container SDK). |
| `session.template.json` | Session create body template. `${AGENT_ID}`, `${ENV_ID}`, `${INPUT_FILE_ID}` filled via `envsubst` at runtime. Uses `{type: "file"}` resource only. |
| `inputs/pilot-500.jsonl` *(gitignored)* | The 500-row input for the pilot. Generated deterministically by `scripts/opus-distill/build_pilot_input.py`. |
| `runs/<ISO>/quality-labels.jsonl` | Labeled output, written by the developer's monitor script after parsing the agent's final message. |
| `runs/<ISO>/run_manifest.json` | Run metadata (timestamps, token counts, cost, score distribution). |

Helper scripts live in `scripts/managed-agents/`:

- `deploy.py` — `POST /v1/agents` + `POST /v1/environments` (writes `AGENT_ID`, `ENV_ID` to `/tmp/kiln-distill.env`).
- `preflight.py` — 10-second verification session to confirm the agent, environment, and input file resource all resolve before the real run.
- `monitor.py` — polls session events and prints progress + token totals.

---

## Deploying the pilot

The canonical step-by-step runbook is [.claude/plans/stateless-purring-quiche.md §5](../../.claude/plans/stateless-purring-quiche.md) — refer to it for the authoritative 12-step sequence with expected outputs, budget, and decision gate. Sketch below:

```bash
# 0. Prereqs (one-time)
brew install anthropics/tap/ant
xattr -d com.apple.quarantine "$(brew --prefix)/bin/ant"
ant auth login
export ANTHROPIC_API_KEY="…"   # your org API key

# 1. Build the input file locally
python scripts/opus-distill/build_pilot_input.py \
  --out managed-agents/corpus-builder/inputs/pilot-500.jsonl
jq -s 'length' managed-agents/corpus-builder/inputs/pilot-500.jsonl   # expect 500 (or ~451 for the current dedup)

# 2. Deploy agent + environment
python scripts/managed-agents/deploy.py
source /tmp/kiln-distill.env                                           # AGENT_ID, ENV_ID

# 3. Upload input file
export INPUT_FILE_ID=$(ant beta:files upload \
  --file managed-agents/corpus-builder/inputs/pilot-500.jsonl \
  --transform id --format yaml)

# 4. Pre-flight (cheap, ~1 min)
python scripts/managed-agents/preflight.py

# 5. Create session
envsubst < managed-agents/corpus-builder/session.template.json > /tmp/session.json
export SESSION_ID=$(ant beta:sessions create \
  --agent "$AGENT_ID" --environment-id "$ENV_ID" \
  --transform id --format yaml <<YAML
resources:
  - type: file
    file_id: $INPUT_FILE_ID
    mount_path: /workspace/input.jsonl
metadata:
  run: quality-pilot-500
YAML
)

# 6. Kick off the run
ant beta:sessions:events send --session-id "$SESSION_ID" <<'YAML'
events:
  - type: user.message
    content:
      - type: text
        text: Begin the quality-classifier labeling pass. Follow the protocol in your system prompt exactly.
YAML

# 7. Monitor
python scripts/managed-agents/monitor.py "$SESSION_ID"    # progress + cost
open "https://console.claude.com/sessions/$SESSION_ID"    # console timeline
```

Cancel (if needed):

```bash
ant beta:sessions:events send --session-id "$SESSION_ID" \
  <<<'events: [{type: user.interrupt}]'
```

Retrieve output (after session reaches `idle` with a `RUN_COMPLETE` marker):

```bash
python scripts/managed-agents/monitor.py "$SESSION_ID" --extract
# → writes managed-agents/corpus-builder/runs/<ISO>/{quality-labels.jsonl,run_manifest.json}

git checkout -b managed-agent/distillation-pilot
git add managed-agents/corpus-builder/runs/
git commit -m "feat(distill): quality pilot labels (500 samples)"
git push -u origin managed-agent/distillation-pilot
```

---

## Budget and success criteria

| Dimension | Target | Hard stop |
|---|---|---|
| Wall clock | ≤ 40 min | 50 min (agent aborts inside) |
| Cost | ≤ $10 tokens + ~$0.05 container | $15 (caller interrupts if breached) |
| Labels written | ≥ 99% of input | — |
| JSON parse rate | ≥ 99% | — |

Full pilot success criteria: [.claude/plans/stateless-purring-quiche.md §6](../../.claude/plans/stateless-purring-quiche.md).

---

## Session stats (filled post-run)

- Pilot session ID: <!-- FILL after kickoff -->
- Agent version deployed: <!-- FILL -->
- Pilot wall clock: <!-- FILL -->
- Pilot cost: <!-- FILL -->
- Labels written: <!-- FILL -->
- Skipped: <!-- FILL -->

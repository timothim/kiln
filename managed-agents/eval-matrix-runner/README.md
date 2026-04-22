# Managed Agent — Eval Matrix Runner

A Claude Managed Agent that re-runs Kiln's full evaluation matrix against the latest adapter on a nightly schedule, writes a markdown report, and surfaces regressions before they reach `main`.

Reference: <https://claude.com/blog/claude-managed-agents>.

## Why managed

- **Scheduled.** Runs every night at 02:00 local, unattended.
- **Long-running.** Full eval pass takes 20–60 minutes.
- **Produces artifacts used by CI.** The `demo-check` command and the `/ship` gate read the latest report.

## What it evaluates

| Metric | What it measures | Source |
|---|---|---|
| `perplexity_held_out` | next-token loss on a held-out user split | sidecar `mlx_lm.generate --eval` |
| `winrate_vs_base` | preference-judge win-rate of fine-tuned vs base | `distilled/preference-judge/` |
| `growing_model_samples` | three fixed prompts generated from the latest adapter | sidecar |
| `latency_256tok` | wall-clock seconds to generate 256 tokens | sidecar |
| `artifact_size_mb` | size on disk of the fused GGUF | filesystem |

## Outputs

- `docs/eval/<YYYY-MM-DD>.md` — full report.
- `docs/eval/latest.md` — symlink or copy of the most recent report. Committed.
- `docs/eval/trend.json` — time series of the headline metrics. Committed.

## How Claude Code deploys it

```
claude agents deploy managed-agents/eval-matrix-runner/agent.yaml
claude agents schedule eval-matrix-runner --cron "0 2 * * *"
```

## Regression handling

- If `winrate_vs_base` drops by > 2% vs the previous successful run, the agent opens a GitHub issue tagged `eval-regression` and posts the diff in the issue body.
- If `perplexity_held_out` drops significantly (> 5%), same.
- No agent-originated merges. Humans triage.

## State

`state.json` holds the last 30 days of headline metrics so the agent can compute the delta quickly without reading the whole history.

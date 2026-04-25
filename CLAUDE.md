# Kiln — Claude Code Operating Rules

<!--
This file is loaded into the context of every Claude Code session in this repo.
Keep it SHORT and SURGICAL. Facts only. Pointers to detail, not the detail itself.
See: https://code.claude.com/docs/en/best-practices
See: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
-->

## Mission

Kiln is a native macOS app that fine-tunes a local LLM to sound like the user from a folder they drop onto it. Fully local at runtime. Opus 4.7 is used during development as a teacher to distill intelligence into small local components — it is never called at runtime. See `SPEC.md` for the full product and pipeline specification.

## Tech stack (locked — do not debate)

- macOS 14+, SwiftUI, Swift 5.9+
- MLX + MLX-LM via a Python 3.11 sidecar; sidecar provisioned with `uv`
- Default base model: `mlx-community/Qwen2.5-3B-Instruct-4bit` (1.5B / 7B alternates per SPEC)
- LoRA via `mlx_lm.lora`, fuse via `mlx_lm.fuse`, GGUF via `llama.cpp`'s `convert_hf_to_gguf.py`
- Ollama hosts the final model
- IPC: JSON-lines over stdout/stderr between Swift and the Python sidecar (`docs/ipc/`)

## Working directory discipline

- One worktree per concern. Branch per worktree, named `m<N>-<slug>` (e.g. `m2-trainer-pipe`).
- Commit at milestone boundaries only; never half-states. Use `/milestone N` to commit a milestone.
- Merges go `feat/* → main` via PR. Every merge triggers the verifier subagent.

## Workflow (enforced)

1. **Plan Mode first.** At the start of every milestone, invoke `/plan <milestone>`. Explore → Plan → Implement → Commit. No code before a written plan.
2. **Verification subagent after every merge.** `.claude/agents/verifier.md` runs in a fresh context. No merge to `main` without a verifier pass.
3. **Skills carry the domain knowledge.** Do not inline MLX, SwiftUI, demo-recording, or distillation details in this file. Load `.claude/skills/<name>/SKILL.md` on demand.
4. **Decisions are logged.** Any non-obvious choice goes into `DECISIONS.md` with options considered and the reason.

## Scope guardrails (do NOT build)

- No user accounts, no cloud sync, no telemetry.
- No training loops written from scratch — wrap MLX-LM, do not re-implement it.
- No React/Electron/webview UI. Pure SwiftUI.
- No LangChain-style agent frameworks. Composable scripts and subagents only. See <https://www.anthropic.com/engineering/building-effective-agents>.
- No model-serving infra beyond Ollama.
- Do not expand the supported base-model list beyond the three in `SPEC.md`.

## YOU MUST

- **Never** ship application code without tests. Swift and Python both.
- **Never** merge to `main` without the verifier subagent returning a clean report.
- **Never** call an Anthropic, OpenAI, or any remote API from the shipped `Kiln.app` runtime. All Opus 4.7 usage is dev-time only, under `scripts/opus-*` and `distilled/`. Violations are auto-flagged by the verifier and by `make ship`.
- **Never** write secrets to the repo. Use `~/.kiln/config.toml` at runtime, document env vars in `README.md`.
- **Never** use force-unwraps (`!`) in Swift outside of test code.
- **Never** block the main thread. All training and inference runs in a detached task or the Python sidecar.

## Pointers

- **What to build:** `SPEC.md` (authoritative), milestones `M0`–`M10`.
- **How Claude is used across the sprint:** `CLAUDE_USAGE.md` (seven distinct modes, evidence collected live).
- **Runbook for multi-worktree orchestration:** `ORCHESTRATION.md`.
- **Skill files (load on demand):** `.claude/skills/mlx-lora-finetuning/`, `.claude/skills/swiftui-polish-kiln/`, `.claude/skills/kiln-demo-recording/`, `.claude/skills/distillation-pipeline/`.
- **Sub-CLAUDEs (imported per subtree):**
  - `apps/Kiln/CLAUDE.md` — SwiftUI rules.
  - `packages/KilnCore/CLAUDE.md` — Swift package rules.
  - `packages/kiln_trainer/CLAUDE.md` — Python sidecar rules.

## Slash commands

`/plan`, `/milestone`, `/review`, `/polish`, `/distill`, `/demo-check`, `/ship` — see `.claude/commands/`.

## Hooks (automatic)

`post-tool-use.sh` formats edited files. `pre-commit.sh` gates commits on `make test`. `stop.sh` appends a five-bullet summary to `SESSION_LOG.md`. See `.claude/settings.json` and <https://code.claude.com/docs/en/hooks-guide>.

## Project status (2026-04-26)

The five-day sprint is complete. M0–M9 shipped, plus the Saturday final push (Voice Coach, MCP server, agent ingestion, Deep Curation, Training Advisor, Behind-the-Scenes). The final completion report is at [`docs/sessions/saturday-final-complete.md`](docs/sessions/saturday-final-complete.md); the post-audit hand-off (the most recent state) is at [`docs/sessions/post-audit-handoff.md`](docs/sessions/post-audit-handoff.md). The submission writeup will land at `docs/submission/writeup.md` ahead of recording.

## Resuming work

If you are picking up this repo in a future session:

1. Read [`docs/sessions/post-audit-handoff.md`](docs/sessions/post-audit-handoff.md) for current status, deferred items, and any outstanding risks.
2. Read [`SPEC.md`](SPEC.md) and [`DECISIONS.md`](DECISIONS.md) for product intent and load-bearing choices.
3. Use `/plan` for any non-trivial milestone before coding. Verifier subagent on every merge to `main`.

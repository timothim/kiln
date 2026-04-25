# Kiln

**Drop a folder. Meet yourself.**

Kiln is a native macOS app that fine-tunes a local LLM to sound like you from a folder of your writing. Corpus prep, LoRA SFT + DPO, fuse, GGUF, Ollama export — fully on your Mac.

> 🎥 Demo recording (3 min) and hero GIF land at `docs/demo/final.mp4` and `docs/demo/hero.gif` ahead of submission.

## Install

```
git clone https://github.com/<your-org>/kiln
cd kiln
make setup
```

## Run

```
make build
open apps/Kiln/build/Release/Kiln.app
```

Drop a folder on the Kiln window. Follow the four stages: Ingest → Profile → Train → Export. When export finishes, Terminal opens on `ollama run kiln-<you>`.

## Architecture

The full multi-agent decomposition is rendered inline by GitHub at [`docs/architecture/multi-agent.mmd`](docs/architecture/multi-agent.mmd). Three layers:

- `apps/Kiln` — SwiftUI frontend.
- `packages/KilnCore` — Swift package (data pipeline, IPC, model lifecycle).
- `packages/kiln_trainer` — Python sidecar wrapping MLX-LM.

Opus 4.7 is used **only during development** to distill three small local models that ship inside the app (`distilled/quality-classifier/`, `distilled/preference-judge/`, `distilled/style-extractor/`). The runtime calls zero APIs.

## Connect to Claude

After training, Kiln exposes your trained voice as a standard MCP server. Claude.app and Claude Code can connect to it and call `write_in_user_voice(prompt, max_tokens)` — your local model writes the reply, and Kiln itself never sees what Claude asked for.

To connect:

1. Train a voice in Kiln (Drop a folder → ingest → train → export to Ollama).
2. Open **Settings → Cloud features → Connect to Claude** and start the MCP server.
3. Copy the JSON snippet shown and paste it into `~/Library/Application Support/Claude/claude_desktop_config.json` under `mcpServers`.
4. Restart Claude.app. The new tool appears as `kiln-voice.write_in_user_voice`.

> 📸 *Screenshot placeholder: Settings panel showing the running MCP server + ready-to-paste JSON snippet.*

The user's voice never leaves the machine. Only the prompt request Claude.app sends through MCP crosses the boundary, and that runs through Claude.app itself, not Kiln.

## Cloud features (opt-in)

Six runtime features call Claude Opus 4.7 directly when you turn them on. **All off by default.** Each carries a "Powered by Claude Opus 4.7" badge in the UI so you always know when your data is leaving the laptop.

- **Voice Coach** — 150-word personalized voice analysis after Ollama export (cloud Opus or local Qwen2.5 fallback).
- **Training Advisor** — Opus watches your training in real time and surfaces one-line observations.
- **Deep Curation** — long-running Managed Agent reviews every sample in your corpus and flags duplicates, sensitive content, voice-inconsistent samples. Cloud-only by design.
- **Agent-driven ingestion** — Opus orchestrates source readers (Local Documents, Apple Notes) and filters to your stated intent.
- **Kiln voice as MCP server** — see the **Connect to Claude** section above.
- **Behind the Scenes** — transparency page documenting how Opus 4.7 + Managed Agents + MCP integrate into Kiln. (Settings → About Kiln.)

> 📸 *Screenshot placeholder: Behind the Scenes page showing the four layers of Opus integration.*

See [`CLAUDE_USAGE.md`](CLAUDE_USAGE.md) §10 for the full per-feature breakdown, or [`docs/sessions/saturday-final.md`](docs/sessions/saturday-final.md) for the implementation session report.

## Documentation

- [`SPEC.md`](SPEC.md) — the authoritative product and pipeline specification.
- [`CLAUDE_USAGE.md`](CLAUDE_USAGE.md) — how Claude was used across the 5-day sprint (the document judges should read).
- [`DECISIONS.md`](DECISIONS.md) — log of non-obvious choices.
- [`ORCHESTRATION.md`](ORCHESTRATION.md) — runbook for the multi-worktree sprint.
- [`.claude/skills/`](.claude/skills/) — operational skills for MLX, SwiftUI, demo recording, distillation.

## License

[MIT](LICENSE).

---

Built during [Built with Opus 4.7](https://claude.com/) — April 2026. Submission: 3-minute demo + 100–200-word writeup land at `docs/demo/final.mp4` and `docs/submission/writeup.md` immediately before submission.

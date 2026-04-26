<div align="center">

```
    ██╗  ██╗██╗██╗     ███╗   ██╗
    ██║ ██╔╝██║██║     ████╗  ██║
    █████╔╝ ██║██║     ██╔██╗ ██║
    ██╔═██╗ ██║██║     ██║╚██╗██║
    ██║  ██╗██║███████╗██║ ╚████║
    ╚═╝  ╚═╝╚═╝╚══════╝╚═╝  ╚═══╝
```

**Train AI to write in your voice. Local. Private. Yours.**

[![Built with Opus 4.7](https://img.shields.io/badge/Built_with-Opus_4.7-D97706?style=flat)](https://www.anthropic.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Python 3.11+](https://img.shields.io/badge/Python-3.11+-3776AB.svg)](https://www.python.org)
[![macOS 14+](https://img.shields.io/badge/macOS-14+-000000.svg)](https://www.apple.com/macos)

</div>

Kiln is a native macOS app that fine-tunes a small local LLM on your own writing in about twenty minutes on a MacBook. Drop a folder of your emails, notes, messages, and Markdown — Kiln dedupes the corpus, scores it with three Opus-distilled classifiers running on-device, runs LoRA fine-tuning via MLX, and exposes the trained voice through Ollama and as an MCP server. Your data never leaves the laptop. Anthropic's Opus 4.7 was used at development time to teach three small classifiers Kiln ships locally, and is available as opt-in cloud advisor features (Voice Coach, Training Advisor, Deep Curation).

> **Submission for** the Built with Opus 4.7 hackathon (April 21–26, 2026). [**▶ Watch the 3-minute demo on YouTube**](https://youtu.be/XFj-7J0CyQU).

---

## The problem

LLMs flatten everyone's voice toward an average of the internet. The more you delegate to them — emails, drafts, replies, social posts — the more your written self drifts toward that average. People write thousands of words a year; that surface area has become someone else's training data, and the loop quietly homogenizes how we all sound.

Kiln inverts the loop: you train the model on **your** writing, run it on **your** machine, and call it from anywhere — even from Claude.app — without your corpus or your prompts ever crossing the network boundary.

---

## What Kiln does

- **Ingest from anywhere.** Drop a folder of writing on the welcome screen, **or** connect a source (Apple Notes, Obsidian, Markdown vaults) and let an Opus 4.7 orchestrator spawn parallel sub-agents — one per source via MCP — to clean and curate the corpus for you.
- **Distill, don't outsource.** Three classifiers (quality, preference, style) ship inside the app. Each was trained from ~1,500–2,000 labels produced by an Opus 4.7 Managed Agent on Anthropic infrastructure. The teacher's judgment lives inside the local pickle files; no runtime API call is needed.
- **Fine-tune locally on Apple Silicon.** LoRA over a 4-bit quantized Qwen 2.5 (3B by default) via MLX-LM. ~20 minutes for a small corpus on M-series hardware. Loss curve, sample completions, and an optional Opus advisor stream live during training.
- **Ship to Ollama and beyond.** When training completes, Kiln fuses the adapter into a GGUF, registers it in Ollama, and starts a local MCP server. Claude.app can connect, see `write_in_user_voice` as a tool, and route writing tasks to your local model — Kiln itself never sees the prompt content.

---

## How it works

```
┌─────────────────────────────────────────────────────────────────┐
│  SOURCES         INGEST           DISTILLED LOCAL    TRAINING   │
│                                                                 │
│  📂 Folder       Opus 4.7         quality-classifier            │
│  📝 Notes  ──▶   orchestrator ──▶ preference-judge   ──▶ MLX    │
│  🟪 Obsidian     + sub-agents     style-extractor       LoRA    │
│  ⌨  Drafts       (parallel,                            on Qwen  │
│                   via MCP)                              2.5     │
│                                                            │    │
│  ┌─────────────────────────────────────────────────────────┘    │
│  │                                                              │
│  ▼                                                              │
│  EXPORT                          ECOSYSTEM                      │
│                                                                 │
│  Fuse → GGUF → Ollama ──▶  Built-in chat (local Ollama)         │
│                                                                 │
│                            MCP server (port 7474)               │
│                                ▲                                │
│                                │                                │
│                            Claude.app, Claude Code,             │
│                            any MCP client                       │
└─────────────────────────────────────────────────────────────────┘
```

A high-resolution Mermaid version is rendered inline at [`docs/architecture/multi-agent.mmd`](docs/architecture/multi-agent.mmd).

The pipeline runs end-to-end on the user's machine. The only places Anthropic's API is reachable are the three opt-in cloud features (Voice Coach, Training Advisor, Deep Curation) — all default to **off**, all have local Qwen-based fallbacks.

---

## Quick start

> **Requires:** macOS 14+, Apple Silicon (M1 or newer), Xcode 15+, Python 3.11+, [`uv`](https://github.com/astral-sh/uv), [Ollama](https://ollama.com).

```bash
# 1. Clone
git clone https://github.com/timothim/kiln.git
cd kiln

# 2. Install Python sidecar deps + verify toolchain
make setup

# 3. Build the .app bundle (Release config)
make build

# 4. Launch the binary directly (preserves cwd → sidecar finds packages/kiln_trainer)
./apps/Kiln/build/Build/Products/Release/Kiln.app/Contents/MacOS/Kiln

# 5. Drop a folder of your writing on the welcome screen.
#    Click Teach. Wait ~20 minutes. Talk to your model.
```

> **Note:** to test the **Built-in Chat** at the end of the flow, run `ollama serve` in a separate terminal first. Without it, the Chat panel will 404 — the rest of the app works without Ollama.

> **Tip:** for the demo flow, drop a folder of 50–100 short writing samples (emails, messages, notes). Smaller corpora work, but you want enough samples for the classifiers to score and for LoRA to specialize. The included `tests/fixtures/demo_corpus/` is reproducible via the `DemoCorpusReproducibilityTests` harness in KilnCore.

---

## Architecture highlights

- **Native macOS app.** SwiftUI, `@Observable @MainActor` view models. No Electron, no React, no webviews. The 22-surface UI was rewritten from a [Claude Design](https://claude.ai)-produced 32-surface interactive HTML prototype on day 5 — see PRs [#31](https://github.com/timothim/kiln/pull/31), [#33](https://github.com/timothim/kiln/pull/33), [#34](https://github.com/timothim/kiln/pull/34), [#35](https://github.com/timothim/kiln/pull/35).
- **Python 3.11 sidecar via `uv`.** All training, classification, and Anthropic API calls live in `packages/kiln_trainer/`. The Swift app spawns `uv run --project <dir> python -m kiln_trainer <command>` and parses JSON-line events on stdout.
- **MLX + LoRA.** `mlx_lm.lora` does the actual training; `mlx_lm.fuse` merges the adapter; `llama.cpp`'s `convert_hf_to_gguf.py` produces the GGUF; `ollama create` registers the model. All wired through one `train` command on the sidecar.
- **Three local classifiers.** Distilled from 5,000 Opus 4.7 labels via Managed Agents:
  - `quality-classifier`: 1,500 labels → 99.0% test accuracy ([manifest](distilled/quality-classifier/manifest.json))
  - `preference-judge`: 2,000 labels → 99.75% test accuracy ([manifest](distilled/preference-judge/manifest.json))
  - `style-extractor`: 1,500 labels → 0.037 mean MAE across 6 stylistic axes ([manifest](distilled/style-extractor/manifest.json))
- **MCP server, both in and out.** Kiln consumes MCP at ingestion (the orchestrator + sub-agent pattern) and exposes MCP at runtime (port 7474, bearer auth, `write_in_user_voice` tool). Built on the official Python `mcp` SDK.
- **Privacy-first by construction.** No telemetry. No analytics. No cloud sync. The runtime makes zero Anthropic API calls unless you opt into a cloud feature in Settings, and each cloud feature has a local Qwen-based fallback.

---

## Built with Opus 4.7

Opus 4.7 is used at four distinct levels:

1. **Build time — multi-agent orchestration via Claude Code.** Tim coded Kiln across four parallel git worktrees, each running its own Claude Code session with scoped CLAUDE.md, skill imports, and a fresh-context **verifier subagent** gating every merge to `main`. Two sibling Claude surfaces produced critical artifacts alongside Claude Code: **Claude Design** generated the 32-surface interactive HTML prototype that drove the day-5 UI rewrite (PRs #31, #33, #34, #35), and **Claude (chat / artifacts)** drafted the 75-second demo storyboard, the pre-record checklist (`scripts/pre-record-checklist.sh`), and the demo-recording script (`docs/demo/script.md`).
2. **Distillation — three Managed Agents on Anthropic infrastructure.** `corpus-builder`, `preference-judge-orchestrator`, and `style-extractor-orchestrator` ran cloud-hosted Opus 4.7 sessions that read JSONL inputs via the Files API and emitted structured manifests + label JSONLs. Outputs are checked into [`distilled/`](distilled/), training scripts in [`packages/kiln_trainer/src/kiln_trainer/classifiers/`](packages/kiln_trainer/src/kiln_trainer/classifiers/).
3. **Runtime — Opus 4.7 inside the product (opt-in).** The ingestion orchestrator (Source Connect), the Training Advisor that watches loss + sample completions live, the Voice Coach that writes a markdown analysis after training, and the Deep Curation Managed Agent for multi-turn corpus review. Each has a local Qwen fallback. Off by default.
4. **Ecosystem — voice as MCP server.** Kiln implements an MCP server that exposes the trained voice as a callable tool. Connect Claude.app to Kiln, and Claude routes writing tasks to your local model — Kiln itself never sees the prompt content beyond what its own MCP layer surfaces.

The full deep-dive — including all metrics, real prompts, and an honest human-vs-Claude breakdown — lives in [**CLAUDE_USAGE.md**](CLAUDE_USAGE.md).

---

## Tech stack

| Layer | Stack |
|---|---|
| Frontend | SwiftUI (native macOS 14+) |
| Backend sidecar | Python 3.11, [`uv`](https://github.com/astral-sh/uv) |
| ML | MLX, MLX-LM 0.21.5, LoRA, Qwen 2.5 (4-bit quantized; 1.5B / 3B / 7B) |
| Inference | Ollama (local), Anthropic SDK 0.40+ (cloud, opt-in) |
| Distillation | Claude Opus 4.7 + Managed Agents |
| Protocol | MCP (Model Context Protocol) — Python `mcp` SDK |
| Build | `xcodegen`, Swift Package Manager, `uv`, GNU Make |

---

## Repo layout

```
apps/Kiln/                  SwiftUI app (KilnApp, RootView, 22 feature views)
packages/KilnCore/          Swift package — IPC, training runners, MCP server
packages/kiln_trainer/      Python sidecar — wraps mlx_lm, ships classifiers
distilled/                  Three classifier manifests + READMEs (the artifacts)
managed-agents/             Five Managed Agent specs
scripts/                    Distillation runners, demo-check, pre-record checklist
docs/
  architecture/             Mermaid diagrams of the system
  audits/                   Pre-merge / post-merge / pre-demo audits
  design/                   DESIGN.md companion + Phase 3 report
  ipc/                      JSON-line event protocol reference
  sessions/                 Engineering session reports (transparency)
  submission/               Hackathon submission artifacts (written summary)
  demo/                     Demo recording materials (final cut on YouTube)
SPEC.md                     Product + pipeline spec (single source of truth)
DESIGN.md                   Token system + design rules
DECISIONS.md                Load-bearing technical decisions, with options + reasoning
CLAUDE.md                   Operating rules for Claude Code workflow
CLAUDE_USAGE.md             Deep dive on Opus 4.7 use across the project
ORCHESTRATION.md            Multi-worktree runbook
```

---

## Documentation

- [`SPEC.md`](SPEC.md) — product and pipeline spec
- [`DESIGN.md`](DESIGN.md) — design tokens, type, motion, copy rules
- [`DECISIONS.md`](DECISIONS.md) — every load-bearing technical decision with options considered
- [`CLAUDE_USAGE.md`](CLAUDE_USAGE.md) — how Opus 4.7 was used (build, distill, runtime, ecosystem)
- [`docs/architecture/multi-agent.mmd`](docs/architecture/multi-agent.mmd) — Mermaid system diagram
- [`docs/audits/`](docs/audits/) — pre-merge audits, post-merge audits, the night-of-demo audit
- [`docs/sessions/`](docs/sessions/) — engineering session reports
- [`docs/submission/written-summary.md`](docs/submission/written-summary.md) — 150-word hackathon writeup

---

## Project status

Built during the Anthropic **Built with Opus 4.7** hackathon (April 21–26, 2026). Status at submission: **v1.0.0-hackathon-submission**. 163 commits, 38 PRs, 226 Swift tests, 215 Python tests passing.

What works end-to-end as of submission:
- Drop folder → ingest pipeline → Dataset Doctor with classifier scores
- LoRA training with live progress, loss sparkline, Growing Model panel, Logs stream
- Sample Before/After comparison
- Voice Mirror (4-column comparison: Base Qwen / SFT / SFT+DPO / your own answer)
- Export to Ollama → Built-in chat → MCP server
- Voice Coach, Training Advisor, Deep Curation (opt-in cloud features)
- Backup with passphrase-encrypted local archive
- Voice Inspector (nearest-sample interpretability), Style Signature Card (PNG export), Kiln Share (`.kiln` bundle export)

What's roadmap:
- Apple Notes / Gmail / Notion connectors are scaffolded; the orchestrator pattern is live for "Local Documents" and the abstract sub-agent slot is in place — third-party source plugins are post-hackathon.
- Nightly eval matrix Managed Agent (`eval-matrix-runner`) — spec authored, deployment deferred.

---

## License

[MIT](LICENSE). Built by [**Timothée Tavernier**](https://github.com/timothim) (INSA Lyon).

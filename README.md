# Kiln

**Drop a folder. Meet yourself.**

Kiln is a native macOS app that fine-tunes a local LLM to sound like you from a folder of your writing. Corpus prep, LoRA SFT + DPO, fuse, GGUF, Ollama export — fully on your Mac.

![demo](docs/demo/hero.gif)

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

![architecture](docs/architecture/overview.svg)

Three layers:

- `apps/Kiln` — SwiftUI frontend.
- `packages/KilnCore` — Swift package (data pipeline, IPC, model lifecycle).
- `packages/kiln_trainer` — Python sidecar wrapping MLX-LM.

Opus 4.7 is used **only during development** to distill three small local models that ship inside the app (`distilled/quality-classifier/`, `distilled/preference-judge/`, `distilled/style-extractor/`). The runtime calls zero APIs.

## Documentation

- [`SPEC.md`](SPEC.md) — the authoritative product and pipeline specification.
- [`CLAUDE_USAGE.md`](CLAUDE_USAGE.md) — how Claude was used across the 5-day sprint (the document judges should read).
- [`DECISIONS.md`](DECISIONS.md) — log of non-obvious choices.
- [`ORCHESTRATION.md`](ORCHESTRATION.md) — runbook for the multi-worktree sprint.
- [`.claude/skills/`](.claude/skills/) — operational skills for MLX, SwiftUI, demo recording, distillation.

## License

[MIT](LICENSE).

---

Built during [Built with Opus 4.7](https://claude.com/) — April 2026. Submission: 3-minute demo at `docs/demo/final.mp4`, 100–200 word writeup at `docs/submission/writeup.md`.

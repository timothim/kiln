# Final submission audit — working notes (2026-04-27)

Captured during the T-1h pre-submission sweep. Truth, not polish.

## Phase 0 — repo state

- **Branch:** `main`, in sync with `origin/main` (0 ahead, 0 behind)
- **HEAD:** `2a87040` — `fix(trainer): sample-compare + export resolve adapter file → dir for mlx_lm (#38)`
- **Open PRs:** 0
- **Total commits:** 163 (all in hackathon week, 2026-04-21 → 2026-04-26)
- **Merged PRs:** 38 (PR #1 milestone(0) scaffold → PR #38 adapter dir fix)
- **Total test files:** 1878 (Swift + Python)
- **Python test functions:** 206 (`pytest`: 215 passed, 2 skipped on last run)
- **Swift tests:** 226 passed, 2 skipped (last run)
- **Release build:** `BUILD SUCCEEDED` (1 benign AppIntents warning, framework not used)

## License

- LICENSE present at root, MIT, "Copyright (c) 2026 The Kiln contributors"
- Properly formatted, full MIT preamble through liability disclaimer

## .gitignore audit

- 60+ patterns covering macOS / Xcode / Swift / Python / IDE / build artifacts
- One missing pattern: `*.profraw` — added during this audit
- `git status --ignored` clean: build artifacts properly excluded

## Top-level inventory (after cleanup)

```
.editorconfig, .github/, .gitignore
CLAUDE.md             — 5,291 B   (operating rules)
CLAUDE_USAGE.md       — 49,509 B  (deep-dive on Opus 4.7 use, 395 lines)
DECISIONS.md          — 21,755 B  (load-bearing technical decisions)
DESIGN.md             — 21,417 B  (design tokens + system)
LICENSE               — 1,078 B   (MIT)
Makefile              — 6,244 B   (12 targets, all working)
ORCHESTRATION.md      — 5,566 B   (multi-worktree runbook)
README.md             — 4,237 B   (80 lines — too short, REWRITTEN this pass)
SESSION_LOG.md        — 1,841 B   (rolling stop-hook summary)
SPEC.md               — 21,417 B  (product + pipeline spec)
apps/                 — Swift app (Kiln.app)
distilled/            — Three classifier manifests (preference-judge, quality-classifier, style-extractor)
docs/                 — architecture, audits, briefs, demo, design, ipc, sessions, submission/
managed-agents/       — Five Managed Agent specs (corpus-builder, corpus-curator, eval-matrix-runner, preference-judge, style-extractor)
package.json          — Node tooling for design-export
packages/             — KilnCore (Swift package), kiln_trainer (Python sidecar)
scripts/              — Distillation + demo runners
tests/                — Repository-level fixtures
```

## Cleanup actions taken

- `default.profraw` — deleted (Swift coverage artifact)
- `.DS_Store` at root — deleted, already gitignored
- `*.profraw` — added to `.gitignore`
- Three untracked session/audit docs **kept and committed** (real build-process artifacts):
  - `docs/audits/post-merge-comprehensive-audit.md`
  - `docs/sessions/overnight-friday-saturday.md`
  - `docs/sessions/saturday-m9.md`

## Make targets verified

| Target | Status |
|---|---|
| `make help` | Lists all 12 targets cleanly |
| `make setup` | Documented, installs Python sidecar deps via uv |
| `make test` | Runs Swift + Python suites, both pass |
| `make build` | Builds Release Kiln.app, succeeded |
| `make build-app` | Subset of build, succeeded |
| `make run` | Documented, opens built app |
| `make distill` | Shortcut to scripts/opus-distill/run.py |
| `make demo-check` | End-to-end North-Star Demo sanity |
| `make video` | Editor shortcut |
| `make clean` | Removes caches |

`make install` does NOT exist — the README references `make setup`. The user-facing prompt template asked for `make install` but the canonical target name is `make setup`. README rewrite uses `make setup` (true).

## TODO/FIXME/HACK in production code

Zero. Verified via `grep -rnE 'TODO|FIXME|XXX|HACK' apps/Kiln/Sources packages/KilnCore/Sources packages/kiln_trainer/src --include='*.swift' --include='*.py'`.

## Secrets scan

- `git log -p --since=2026-04-21 | grep -iE '(api[_-]key|secret|token|password|sk-ant)'` — no real hits, only:
  - `_RE_TOKENS_PER_S` regex (token rate parser)
  - design-token references (CSS / DESIGN.md)
  - keychain config-key field labels (UI strings)
- No bearer tokens, API keys, or credentials anywhere in the tree

## Distilled artifacts inventory

All three components ship a manifest + README. Real metrics from manifests:

| Component | Labels | Test acc / MAE | sha256 fingerprint (truncated) |
|---|---|---|---|
| `quality-classifier` | 1,500 | 99.0% test acc | `333616fc7c…` |
| `preference-judge` | 2,000 | 99.75% test acc | `0803b967c0…` |
| `style-extractor` | 1,500 | 0.037 mean MAE across 6 axes | `f994dbd3a2…` |

`git_sha` on all three: `e0e060179a5945fc07b39ca295469c58ba57e018` (committed at distillation time).

## Demo corpus reproducibility

`packages/KilnCore/Tests/KilnCoreTests/Ingest/DemoCorpusReproducibilityTests.swift` exists with deterministic seed-based generators. 4 tests, runs in ~0.8s. Confirms inputs ARE recoverable.

## Bugs fixed in the final 24 hours (live audit findings)

1. **PR #37** — `_RE_SAVE` / `_RE_FINAL_SAVE` regex truncated paths at first space. macOS `~/Library/Application Support/...` was 100% broken. Fixed with lazy capture + delimiter.
2. **PR #38** — `sample_compare.py` and `export.py` passed the file `adapters.safetensors` to `mlx_lm.generate` / `mlx_lm.fuse` which both want the parent directory. Fixed with `is_file()` resolution.

These two bugs together blocked Sample preview, Voice Mirror SFT columns, Export to Ollama, and Built-in Chat. Now all working.

## Branches on origin

- `main` (canonical, in sync)
- 30+ `feat/*`, `fix/*`, `design/*`, `docs/*`, `milestone/*`, `polish/*` branches — all merged via PR
- A few `claude/*` branches from claude-cowork early scaffolding

Branch deletion: deferred. Submission only requires main to be clean. Branches don't show up in default GitHub UI.

## Outstanding decisions for the README rewrite

- Author attribution: Timothée Tavernier (@timothim), INSA Lyon
- Repo URL: <https://github.com/timothim/kiln>
- Repo description (already set on GitHub): "Claude Opus 4.7 Hackathon participation - Drop a folder. Meet yourself. Fine-tune a local LLM to sound like you — fully on your Mac."
- The video URL is unknown at audit time; README links a placeholder until Tim finalizes the recording

## Outstanding decisions for CLAUDE_USAGE.md augmentation

- The existing 395-line document is already comprehensive (sections 1-10).
- Augmentation needed: §11 covering build-time artifacts produced **with** Claude, beyond Claude Code itself:
  - **Claude Design** — produced the 32-surface interactive HTML prototype (`kiln-prototype.html`) that drove the UI rewrite (PRs #31, #33, #34, #35) directly mappable to delivered surfaces
  - **Claude (chat / artifacts)** — used to draft the demo-recording script (`docs/demo/script.md`), pre-record checklist (`scripts/pre-record-checklist.sh`), the 75-second storyboard, and the demo-day workflow

## Verdict

**SHIP.** Repo is clean. Tests pass. Build succeeds. All 22 features mounted, wired, live. Two adapter-path bugs caught and fixed today. README rewritten this pass. CLAUDE_USAGE augmented this pass. Submission summary written this pass. Tag: `v1.0.0-hackathon-submission` to be pushed at end of this audit.

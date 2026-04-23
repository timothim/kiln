# Day 4 (Friday 2026-04-24) — parallel agent briefs

Four worktrees run in parallel today. Each brief below is **self-contained** —
the agent picks it up with no prior conversation context. Drop it verbatim
into `/plan` for its worktree, approve, then `/milestone <N>`.

Orchestrator rules (recap from [ORCHESTRATION.md](../../ORCHESTRATION.md)):

- One branch per worktree, named `m<N>-<slug>` or `feat/<slug>`.
- Merges go `feat/* → main` via PR. Verifier subagent runs on every merge.
- **Do not cross streams.** If your brief does not mention a file, do not edit it.
- **Commit at milestone boundaries only.** Use `/milestone N` to create the commit.
- Pre-commit hook runs `make test`; a red suite means you did not finish.

Status entering Friday (branch `overnight/docs-and-scaffolding`, commits
`efb345b..e09b266`):

- M0–M4 merged to `main` (9ad5ebe + fixups).
- Distillation Orchestrator scaffold + docs-grounded runbook merged (35b6d7b).
- Quality pilot ran overnight: **451 / 451 labels written in ~8 minutes, $5.69, 0 skipped** (manifest `managed-agents/corpus-builder/runs/20260423T224526Z/`).
- Features 3–10 have skeleton stubs with `IS_IMPLEMENTED = false` guards and `notImplemented` tests — the four briefs below turn selected stubs on.
- Demo dataset for "Alex" persona lives under `tests/fixtures/demo_corpus/` (222 files, 369 KiB, deterministic via `scripts/demo-dataset/generate.py --seed 20260424`).

The four lanes:

1. [**LEAD — M5 SFT end-to-end**](#1-lead--m5-sft-end-to-end) — press *Teach*, a training run completes.
2. [**DATA — Native importers**](#2-data--native-importers-messages--notes--obsidian) — Messages / Notes / Obsidian sources land.
3. [**TRAINER — Incremental learning**](#3-trainer--incremental-learning-resume-from-checkpoint) — resume-from-checkpoint on additional corpus.
4. [**UI-Excellence — Post-M4 feature surfaces**](#4-ui-excellence--post-m4-feature-surfaces) — wire the scaffolded features into polished SwiftUI panels.

Target end-of-Friday state: M5 merged to `main`; importers and incremental
behind feature flags but compiling and tested; UI shell shows the new panels
in empty-state-only mode. First demo rehearsal at 20:00.

---

## 1. LEAD — M5 SFT end-to-end

**Worktree:** `kiln-m5` on branch `m5-sft-end-to-end` (fresh from `main`).

**Mission.** Close the loop that SPEC.md §12 calls "M5 SFT end-to-end" —
the user presses *Teach your model* in the training screen, the Python
sidecar runs `mlx_lm.lora` on the corpus assembled by M4, progress events
render in the UI until the adapter is written to `~/.kiln/runs/<id>/adapter/`.

This is the top priority on Friday; every other brief assumes M5 merged.

### Scope

Wire the existing pieces together; do not invent new ones.

- **Swift side:** `apps/Kiln/` training view already has a *Teach* button
  (currently no-op). Kick a `TrainingJob` through `KilnCore.TrainingService`,
  stream progress via the existing `ProgressEvent` enum.
- **Python side:** `packages/kiln_trainer/` already has a sidecar runner
  (`run.py`) and the LoRA CLI wrapper. Make the `sft` subcommand end-to-end:
  read the JSONL corpus emitted by M4, invoke `mlx_lm.lora` with the
  `--data` / `--iters` / `--batch-size` values that come from the Swift IPC,
  tail its stderr, reshape its log lines into `ProgressEvent` JSON-lines on
  stdout.
- **IPC:** `docs/ipc/train.md` is the contract. Extend the schema only if a
  field is missing; do not rename existing fields.
- **Artifact layout:** `~/.kiln/runs/<YYYYMMDDThhmmss>/` contains
  `adapter/` (safetensors), `manifest.json` (base model, iters, loss,
  started_at, finished_at, corpus_sha), `log.jsonl` (progress events
  verbatim).
- **Models:** only `mlx-community/Qwen2.5-3B-Instruct-4bit` for M5.
  1.5B / 7B paths are M8. If you find yourself adding size branching, stop.

### Out of scope (do NOT touch)

- Growing Model panel (M6) — streaming three prompts during training.
- DPO, fuse, GGUF, Ollama (M7/M8).
- Incremental learning — the TRAINER brief owns that path.
- UI polish pass — the UI-Excellence brief owns that.
- `packages/KilnCore/Sources/KilnCore/Features/` — these are post-M4 surfaces, not M5 core.

### Success criteria

1. `make test` green with at least 3 new Swift tests and 3 new Python tests
   exercising the sft happy path and two error paths (corpus missing,
   sidecar crash).
2. From a clean worktree: drop `tests/fixtures/demo_corpus/` onto the app,
   run through M4, press *Teach*, watch progress tick from 0% to 100%
   in the UI, `~/.kiln/runs/<id>/adapter/` contains safetensors at the end.
3. Wall clock for the demo-corpus training ≤ 8 minutes on an M1 Pro with
   `--iters 200` (time-boxed; tune `iters` down if necessary — the goal is
   "it runs end-to-end," not "it trains a great model").
4. `ProgressEvent` stream is monotonic in `step`; no duplicate `done` events.
5. Verifier subagent on the merge PR returns zero T1/T2 findings.

### Verification

- `make test` — all green.
- `python -m kiln_trainer.cli sft --corpus tests/fixtures/demo_corpus/ingest.jsonl --out /tmp/kiln-m5-test --iters 10 --batch-size 2` — completes in under 2 minutes and writes a valid manifest.
- `open apps/Kiln/Kiln.xcodeproj` → run → drop `tests/fixtures/demo_corpus/` → *Teach* → adapter written.
- `/review` — verifier subagent runs cleanly (see `.claude/agents/verifier.md`).

### Reference material

- [SPEC.md §6](../../SPEC.md) training-pipeline spec.
- [SPEC.md §11](../../SPEC.md) IPC protocol.
- [.claude/skills/mlx-lora-finetuning/SKILL.md](../../.claude/skills/mlx-lora-finetuning/SKILL.md) — the canonical set of LoRA knobs.
- `docs/ipc/train.md` — the IPC schema.
- `packages/kiln_trainer/CLAUDE.md` — sidecar rules.

### Commit and merge

1. `/plan M5` — print plan, get approval.
2. Code + tests. Commit at milestone boundary with `/milestone 5`.
3. Open PR `feat/m5-sft → main`. Wait for verifier subagent pass.
4. Post the run's `log.jsonl` tail in the PR description so reviewers can
   see real progress events.

**Time box:** 6 hours. If by 13:00 Lisbon time the training loop is not
producing its first `ProgressEvent`, stop and escalate in `SESSION_LOG.md`
before continuing.

---

## 2. DATA — Native importers (Messages / Notes / Obsidian)

**Worktree:** `kiln-data-importers` on branch `feat/native-importers` (fresh from `main`).

**Mission.** Turn on three of the four native data sources that
`packages/KilnCore/Sources/KilnCore/Features/NativeImporters.swift` stubs
today: **Messages** (chat.db), **Notes** (AppleScript bridge), **Obsidian**
(vault with wikilinks + frontmatter). Mail (mbox) stays stubbed — it is
lower signal and we will ship without it.

Output of each importer flows into the existing drop-folder pipeline via
the shared `IngestChunk` type, so from M4's point of view these are just
more chunk sources. No changes to dedup / quality / train downstream.

### Scope

- Flip `NativeImporters.isImplemented` to `true` and replace the
  `notImplemented` throw in `importFrom(_:progress:)` with a real dispatch.
- Per-source modules under
  `packages/KilnCore/Sources/KilnCore/Features/NativeImporters/` — one file
  per source (`MessagesImporter.swift`, `NotesImporter.swift`,
  `ObsidianImporter.swift`). Each owns the TCC/permission flow, reads raw
  payloads, and passes bytes to the Python parsers.
- Flip `packages/kiln_trainer/src/kiln_trainer/features/native_importers.py`
  `IS_IMPLEMENTED` to `True` and fill the three parser generators:
  `parse_messages_export`, `parse_notes_export`, `parse_obsidian_vault`.
  Each yields `NativeChunk` with `source`, `author`, `text`, `timestamp_ms`.
- UI: add a second drop target on the ingest screen labeled "Connect a
  source" — opens a sheet, user picks Messages / Notes / Obsidian, the
  standard TCC dialog appears, then ingest proceeds with the same progress
  surface as the folder drop. Reuse existing components; do NOT restyle.

### Out of scope (do NOT touch)

- Mail (mbox) — stays stubbed.
- The drop-folder pipeline itself — only add new entry points.
- The quality classifier, style extractor, preference judge — importers
  only emit chunks.
- SwiftUI design system tokens (`apps/Kiln/Sources/DesignSystem.swift`) —
  the UI-Excellence lane owns those.
- Sandbox / entitlements toggles beyond those strictly needed for the
  three sources; document new entitlements in [`apps/Kiln/CLAUDE.md`](../../apps/Kiln/CLAUDE.md).

### TCC / permissions

Each source prompts exactly once per app install. On denial, surface the
empty state *"Grant access to Messages → System Settings → Privacy"* with
a "Retry" button that re-prompts — do **not** crash, do **not** silently
swallow. The skill at
[.claude/skills/macos-data-sources/SKILL.md](../../.claude/skills/macos-data-sources/SKILL.md)
documents the exact TCC keys and the Info.plist usage strings to add.

### Success criteria

1. `make test` green with new tests:
   - Swift: 3 importer-dispatch tests + 3 permission-missing tests.
   - Python: 3 parser-golden tests (one golden fixture per source).
2. From a clean worktree: run the app, click "Connect a source" → Messages,
   grant permission, watch the count tick up, hit Continue, land on the
   Dataset Doctor screen with Messages chunks merged into the existing set.
3. Obsidian importer handles wikilinks (`[[Foo]]`) and frontmatter
   (YAML block at top) correctly — strips the frontmatter from body,
   resolves wikilinks to plain text of the target note's title.
4. Messages importer handles iMessage + SMS, skips reactions and tapback
   rows, preserves conversation threading via `thread_id` on chunks.
5. Verifier subagent on the merge PR returns zero T1/T2 findings, and its
   T3 findings do not mention privacy or sandboxing.

### Test fixtures

Create tiny golden fixtures under `tests/fixtures/native_importers/`:

- `messages/chat-sample.db` — a 3-row SQLite snapshot. Generate via a Python
  helper committed alongside, not hand-crafted (deterministic).
- `notes/export-sample.zip` — a 2-note AppleScript export.
- `obsidian/vault-sample/` — 4 markdown files exercising wikilinks,
  frontmatter, attachments, and a nested folder.

Every fixture must parse byte-identically on rerun — seed every generator.

### Verification

- `make test`.
- `python -m kiln_trainer.features.native_importers --parse messages tests/fixtures/native_importers/messages/chat-sample.db` prints 3 JSON lines.
- Manual: drop-or-connect flow for each source in the running app.
- `/review` — clean verifier report.

### Reference

- [.claude/skills/macos-data-sources/SKILL.md](../../.claude/skills/macos-data-sources/SKILL.md) — TCC keys, chat.db schema, AppleScript script for Notes, Obsidian frontmatter spec.
- [apps/Kiln/CLAUDE.md](../../apps/Kiln/CLAUDE.md) — entitlements and main-thread rules.

### Commit and merge

1. `/plan native-importers`.
2. Land in two commits inside one PR: `feat(importers): backends` + `feat(importers): UI entry point`.
3. PR `feat/native-importers → main`. Verifier pass, then merge.

**Time box:** 5 hours. Messages is the hardest source — if chat.db parsing is
not producing chunks by 14:00 Lisbon, cut it, ship Notes + Obsidian, and
move Messages to Saturday.

---

## 3. TRAINER — Incremental learning (resume-from-checkpoint)

**Worktree:** `kiln-trainer-incr` on branch `feat/incremental-training` (fresh from `main`).

**Mission.** Make
`packages/kiln_trainer/src/kiln_trainer/features/incremental.py::continue_training`
actually continue training an existing adapter on an additional corpus.
The UI entry point is a *"Teach more"* button that appears on the
post-training screen when the user drops a second folder; it sends a
`resume` IPC request instead of a fresh `sft` request.

### Scope

- Python: flip `IS_IMPLEMENTED` to `True`. Implement `continue_training`
  with a real `mlx_lm.lora` invocation that passes `--resume-adapter-file`
  at the path of `request.base_adapter_dir/adapter_config.json` +
  `adapter_model.safetensors` and `--iters request.extra_epochs * <per-epoch>`.
  Merge the new `manifest.json` into the old one so the run history stays a
  single file per adapter lineage.
- Swift: flip
  `packages/KilnCore/Sources/KilnCore/Features/IncrementalLearning.swift`
  `isImplemented` to `true`. Replace the `notImplemented` throw in
  `continueTraining(_:)` with a real IPC call. The `Request` struct fields
  are already right — do not extend.
- IPC: add a `resume` subcommand mirroring `sft` but carrying
  `base_adapter_path` and `extra_epochs`. Document in `docs/ipc/train.md`
  under a "Resume" subsection; do not change existing `sft` shape.
- Manifest merge rule: new entries append; `base_model`, `corpus_sha`, and
  `started_at` preserved from the original run; `last_resume_at`,
  `cumulative_iters`, `cumulative_loss_curve` added.

### Out of scope (do NOT touch)

- The M5 SFT loop itself — only resume support.
- DPO, fuse, GGUF, Ollama.
- The UI panels for post-training — the UI-Excellence brief wires the
  *"Teach more"* button into the design system; you just expose the
  `IncrementalLearning.continueTraining` API for them to call.
- `NativeImporters.swift` — the DATA brief owns that file.

### Success criteria

1. `make test` green with at least 4 new Python tests:
   - happy path: initial 50-iter run + 20-iter resume on disjoint corpus.
   - checkpoint missing: raises a typed error.
   - manifest merge: `cumulative_iters == initial + extra`.
   - loss curve monotonicity across the boundary (allow 5% noise).
2. Swift test suite: 2 new `IncrementalLearningTests` — one happy,
   one "adapter URL points at nothing" error case.
3. Running `python -m kiln_trainer.cli resume --base <adapter-dir> --corpus <jsonl> --iters 20` on the artifact from a prior `sft` run writes a new adapter and preserves lineage in the manifest.
4. Wall clock for a 20-iter resume on the demo corpus ≤ 4 minutes on M1 Pro.
5. Verifier zero T1/T2.

### Verification

- `make test`.
- End-to-end on the demo corpus: run M5 sft first, then resume on the same corpus with 20 extra iters, confirm the adapter directory is new and the manifest shows cumulative iters.
- Inspect the checkpoint directory: two adapter files (old one preserved, new one alongside) with a `lineage.json` linking them.
- `/review`.

### Reference

- [.claude/skills/mlx-lora-finetuning/SKILL.md](../../.claude/skills/mlx-lora-finetuning/SKILL.md) §"Resume training" — MLX-LM's resume flags and the known gotcha about optimizer state.
- `packages/kiln_trainer/CLAUDE.md`.

### Commit and merge

1. `/plan incremental-training`.
2. Single commit at milestone boundary: `feat(trainer): incremental learning (--resume)`.
3. PR `feat/incremental-training → main`. Verifier pass, then merge.

**Time box:** 5 hours. If the optimizer-state resume is blocking (known
MLX-LM rough edge; see skill), ship **weight-only resume** with a clear
warning in the manifest (`resume_kind: "weights_only"`) rather than delay.
A working weight-only resume > a blocked full-state resume.

---

## 4. UI-Excellence — Post-M4 feature surfaces

**Worktree:** `kiln-ui-excellence` on branch `feat/ui-excellence` (fresh from `main`).

**Mission.** The 8 scaffolded feature modules under
`packages/KilnCore/Sources/KilnCore/Features/` have API surfaces but no UI.
Build the **empty-state-only** versions of the ones the North-Star Demo
touches — users should see polished panels that say *"Coming Friday night
with M5"* / *"Lands with M6"* etc. rather than absent screens. This keeps
the UI "feel" coherent during rehearsal while M5/M6/M7 agents are still
merging code.

You are the only agent allowed to touch
[`apps/Kiln/Sources/DesignSystem.swift`](../../apps/Kiln/Sources/DesignSystem.swift).

### Scope

Build SwiftUI panels for exactly these four surfaces. Each is a
feature-gated view that renders the empty-state variant until the
corresponding `isImplemented` flag flips.

| Feature | `isImplemented` flips when… | Empty-state copy |
|---|---|---|
| `VoiceMirror` | M6 streaming pipe lands | *"Your mirror will light up as soon as training starts."* |
| `StyleSignatureCard` | style-extractor artifact ≥ 0.75 cosine | *"Your signature is still forming. Finish training to see it."* |
| `KilnVoices` | post-M6 fuse-export stable | *"No voices yet. Fine-tune your first model to add one here."* |
| `IncrementalLearning` | TRAINER brief lands | *"Drop another folder to teach your model more."* |

Rules:

- All four panels use the same `DesignSystem` spacing, typography, and
  motion tokens. Do NOT add new colors or fonts.
- Each panel has **three** states: `empty` (default, shown today),
  `loading` (shown while the async task runs), `ready` (shown when
  `isImplemented == true`). Implement all three; the `ready` state can
  call the real API — it will throw `notImplemented` until the other
  briefs land, which is fine.
- `loading` states must use the existing progress primitive — do not
  invent a new spinner.
- Respect `@Environment(\.accessibilityReduceMotion)` — no parallax
  or easing animations when the environment flag is true.
- All copy in English only for now.

### Out of scope (do NOT touch)

- Any non-UI scaffolded module (`CloudBackup`, `KilnShare`, `VoiceInspector`,
  `NativeImporters`) — those either violate CLAUDE.md scope guardrails or
  belong to other briefs.
- The drop-folder screen, the Dataset Doctor screen, the training screen —
  M4 landed those; polish touch-ups only if they are blocking this work,
  and only behind a comment citing which existing element broke.
- `apps/Kiln/CLAUDE.md` — rules unchanged.
- Localization — English only.

### Success criteria

1. `make test` green with snapshot tests for each panel's three states
   (12 snapshots total, committed under `apps/Kiln/Tests/Snapshots/`).
2. Running the app and clicking into each of the four surfaces renders
   the empty state with accurate copy, a title, one illustration-slot
   placeholder, and a single CTA button that is wired but currently
   a no-op → "Not yet" toast.
3. Switching the environment's `reduceMotion` flag in the preview hides
   any parallax/ease animation.
4. Zero force-unwraps, zero main-thread work over 16 ms in any view
   lifecycle (run with Instruments Time Profiler; screenshot attached
   to PR description).
5. Verifier zero T1/T2.

### Design references

- [`apps/Kiln/CLAUDE.md`](../../apps/Kiln/CLAUDE.md) — SwiftUI rules.
- [.claude/skills/swiftui-polish-kiln/SKILL.md](../../.claude/skills/swiftui-polish-kiln/SKILL.md) — tokens, motion, empty-state conventions.
- [SPEC.md §10](../../SPEC.md) UI principles.
- Existing panels in `apps/Kiln/Sources/Views/` — copy their structure, do not re-architect.

### Verification

- `make test`.
- `xcodebuild -scheme Kiln -destination "platform=macOS" build test` — green.
- Manual walk of all four panels in all three states via SwiftUI preview.
- `/polish voice-mirror` and the other three — use the polish skill to check off the empty-state checklist.
- `/review` — verifier pass.

### Commit and merge

1. `/plan ui-excellence`.
2. Four commits in the PR, one per panel: `feat(ui): <FeatureName> empty+loading+ready shell`.
3. PR `feat/ui-excellence → main`. Verifier pass, then merge.

**Time box:** 6 hours. If by 15:00 Lisbon the first panel's three
states are not rendering, drop the `KilnVoices` panel (least-critical for
the demo) and land the other three.

---

## Coordination notes

**Dependencies.**
- DATA and TRAINER briefs both produce artifacts that M5 consumes; both
  are decoupled from M5 (feature-flagged), so order of merge does not
  matter, but UI-Excellence's `IncrementalLearning` panel will flip to
  "ready" only after TRAINER merges.
- LEAD M5 is the only brief whose merge is **required** for the 20:00
  rehearsal.

**Shared files — watch for conflicts.**
- `docs/ipc/train.md` — LEAD extends `sft`, TRAINER adds `resume`. Resolve
  by appending; do not reorder existing sections.
- `.gitignore` — nobody should need to touch it today. If you do, note why
  in your PR body.
- `SESSION_LOG.md` — appended by the `stop.sh` hook; no manual edits.

**Escalation.**
- Blocker > 30 min → write to `SESSION_LOG.md` with "BLOCKER:" prefix, switch to the next task. The orchestrator (tim) reviews at 13:00 and 17:00.
- Red `make test` → do not `--no-verify`; fix the test or revert.
- Verifier T1 or T2 finding → do not merge; fix and re-request review.

**Rehearsal gate (20:00 Lisbon).**
- M5 merged. ✅
- All four brief branches either merged or parked with an explicit postmortem.
- `/demo-check` passes end-to-end on the demo corpus (Task 5 of overnight scaffolding).
- First rehearsal screen-recording saved under `docs/demo/rehearsals/<timestamp>/`.

If any of those four bullets fails, push rehearsal to 21:30 and
post a recovery plan in `SESSION_LOG.md`.

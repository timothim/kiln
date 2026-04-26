# Overnight session — Friday → Saturday (2026-04-24 → 2026-04-25)

Five-phase directive. All four substantive phases landed; nothing destructive, nothing merged that you didn't pre-authorize.

| Phase | Outcome | Artifact |
|---|---|---|
| 0 — PR #10 conflict resolution (additive) | ✅ Merged at [9db165a](https://github.com/timothim/kiln/commit/9db165a) | [PR #10](https://github.com/timothim/kiln/pull/10) |
| 1 — Tier-2: drop `.uncaughtSignal` exemption + IPC doc | ✅ PR open, **not merged** | [PR #13](https://github.com/timothim/kiln/pull/13) |
| 2 — Tier-3: feature flags, preview text, magic numbers | ✅ PR open, **not merged** | [PR #14](https://github.com/timothim/kiln/pull/14) |
| 3 — M9 plan draft | ✅ | [.claude/plans/m9-plan.md](.claude/plans/m9-plan.md) |
| 4 — This session report | ✅ | [docs/sessions/overnight-friday-saturday.md](docs/sessions/overnight-friday-saturday.md) |

`make test` is green on both fixup branches. Suite count: ~285 passing.

---

## Phase 0 — PR #10 conflict resolution

**Strategy:** additive — extended every signature in the conflict zone to accept both M7 (export+chat) and M8 (voices) parameters, rather than dropping either side. No feature regressions on either head.

**Result:** Merged into `main` at [9db165a](https://github.com/timothim/kiln/commit/9db165a). Force-pushed via `--force-with-lease` per directive — no `--force` used anywhere.

**Validation:** `make build` + `make test` both green pre-merge.

The other two pre-existing PRs (#11 distill audits, #12 M7 ollama+chat) were already merged earlier in the day and do not require re-validation.

---

## Phase 1 — Tier-2 fixes (PR #13)

**Branch:** `fixup/post-m7-tier2` — single commit [1aee24a](https://github.com/timothim/kiln/commit/1aee24a) titled `fixup: drop .uncaughtSignal exemption + IPC protocol doc`.

### What changed

Three runners previously treated `.uncaughtSignal` as a clean exit. Hostile sidecar deaths (e.g., `kill -ABRT $$`) silently produced a "successful" stream. Now any non-zero exit — regardless of `terminationReason` — throws `unexpectedExit`:

- [packages/KilnCore/Sources/KilnCore/Training/TrainingRunner.swift:75](packages/KilnCore/Sources/KilnCore/Training/TrainingRunner.swift:75)
- [packages/KilnCore/Sources/KilnCore/Export/OllamaExporter.swift:75](packages/KilnCore/Sources/KilnCore/Export/OllamaExporter.swift:75)
- [packages/KilnCore/Sources/KilnCore/Sampling/SampleCompareRunner.swift:90](packages/KilnCore/Sources/KilnCore/Sampling/SampleCompareRunner.swift:90)

Three new tests at [packages/KilnCore/Tests/KilnCoreTests/SignalDeath/RunnerSignalDeathTests.swift](packages/KilnCore/Tests/KilnCoreTests/SignalDeath/RunnerSignalDeathTests.swift) — each spawns a shell that calls `kill -ABRT $$` and asserts `.unexpectedExit` is thrown rather than the stream finishing cleanly.

Authoritative IPC doc at [docs/ipc/protocol.md](docs/ipc/protocol.md) (~465 lines): transport & framing, subcommand inventory (train / export / sample / sample-compare), full wire schema for all 7 event types (`ready`, `progress`, `sample`, `checkpoint`, `error`, `done`, `generation`), per-subcommand timelines, the Swift event-enum mapping table, process lifecycle (5s SIGTERM grace → SIGKILL), test seams (`--trainer-entry`, `--generator-entry`), and cross-references back into both code paths.

Per your directive: **the doc is now the authoritative source.** SPEC.md and CLAUDE.md were not edited — they don't disagree, the doc just goes deeper. If they ever drift, the doc wins.

### What's pending

- **Verifier subagent** has not been invoked yet — directive said "narrowly" so I held off pending your awake review. The PR body lists the three runner files + the 3 new tests + the new doc as fresh-context anchors; verifier will not need to rediscover them.
- **Not merged.** Awaiting your morning sign-off.

---

## Phase 2 — Tier-3 cleanup (PR #14)

**Branch:** `chore/post-m7-cleanup` — single commit [bc60617](https://github.com/timothim/kiln/commit/bc60617) titled `chore: post-M7 cleanup (feature flags, preview text, magic numbers)`.

### What changed

Three small edits, none of them functional regressions:

**Feature flags flipped from `false` to `true`** for live KilnCore stubs that have shipping implementations. Each comment now points at the live path so a future reader doesn't think the stub is the truth:

- [packages/KilnCore/Sources/KilnCore/Features/StyleSignatureCard.swift:9](packages/KilnCore/Sources/KilnCore/Features/StyleSignatureCard.swift:9) → live at `apps/Kiln/Sources/Features/StyleSignature/StyleSignatureCardView.swift`.
- [packages/KilnCore/Sources/KilnCore/Features/VoiceMirror.swift:9](packages/KilnCore/Sources/KilnCore/Features/VoiceMirror.swift:9) → live via `SubprocessSampleCompareRunner` (M7).
- [packages/KilnCore/Sources/KilnCore/Features/KilnVoices.swift:11](packages/KilnCore/Sources/KilnCore/Features/KilnVoices.swift:11) → live via `VoicesProvider` (M8).

The legacy enum `generate` / `reflect` / `list` / `activate` stubs **stay as dead code** for now (still throw `notImplemented`) — flagged in each doc-comment so a follow-up sweep can remove them safely. Removing them is *not* in this fixup's scope; the flag flip alone closes the misleading-state issue.

**Preview greeting** at [apps/Kiln/Sources/Features/Chat/ChatModel.swift:120](apps/Kiln/Sources/Features/Chat/ChatModel.swift:120):

```swift
// Before:
init(tokens: [String] = ["Hi", "!", " How", " can", " I", " help", "?"]) {
// After:
init(tokens: [String] = ["Hi", " there", ".", " How", " can", " I", " help", "?"]) {
```

The "Hi!" exclamation read as fake-cheerful in previews; "Hi there." matches the project's voice better.

**Magic numbers** in [apps/Kiln/Sources/Features/StyleSignature/StyleSignatureCardView.swift](apps/Kiln/Sources/Features/StyleSignature/StyleSignatureCardView.swift) — extracted both 0.4 (3× divider opacity) and 0.06 (2× chrome opacity) into named static constants:

```swift
private static let sectionDividerOpacity: Double = 0.4
private static let chromeOpacity: Double = 0.06

private var sectionDivider: some View {
    Divider().opacity(Self.sectionDividerOpacity)
}
```

Three call sites collapsed onto the new `sectionDivider` helper; the stroke and the syntactic-pattern chip both reference `chromeOpacity`. Doc-comment on each constant explains *why* the value is what it is, not just *what* it is.

### What's pending

- **Not merged.** Awaiting your morning sign-off.

---

## Phase 3 — M9 plan draft

Written at [.claude/plans/m9-plan.md](.claude/plans/m9-plan.md). Three independent sub-milestones:

| Sub | Title | Budget |
|---|---|---|
| M9.A | Cloud backup opt-in (iCloud Drive + S3, on-device encryption) | ~1.5h |
| M9.B | Voice Inspector wiring (sentence-transformers MiniLM via CoreML) | ~3h |
| M9.C | Distilled classifiers integration (quality, style, preference) | ~2h |

Each section follows the format the team has settled into: Context → Goal → Files (new/modified) → Implementation steps → Test plan → Risks/open questions. Every step ties back to file:line anchors so the verifier subagent can validate fresh.

**Highlights / open questions worth your eye:**

- **M9.A iCloud entitlement.** Requires a paid Apple Dev cert. Plan suggests S3-only for the contest demo, iCloud "available with a signed build." Confirm or push back.
- **M9.B 80MB CoreML model bundled.** Acceptable for a pro-tool, flagged for a future "download on first launch" mode.
- **M9.C ships ~90MB of distilled `.mlpackage` artifacts.** Combined with M9.B's MiniLM, total bundle grows by ~170MB. Same lazy-download follow-up applies.
- **Distillation reproducibility.** Opus-4.7 student-labeling is non-deterministic; plan locks the seed end-to-end and pins the labeled fixture. Worth a sanity check.

Three commits, one per sub-milestone, gated by `make test` + `pre-commit.sh`. No `--amend`, no `--no-verify`. Verifier runs on each merge.

---

## What I did NOT touch

- **No merge to main** beyond Phase 0's pre-authorized PR #10.
- **SPEC.md / CLAUDE.md** were not edited. The new IPC doc supersedes any disagreement on protocol details — if you find drift, the doc wins, and updating those upstream docs to match is a follow-up sweep.
- **Verifier subagent** was not invoked on PRs #13 or #14 — directive said "narrowly" so I held it for your morning sign-off rather than burning a fresh-context spawn at 3am.
- **Kiln.app runtime** — zero new external API calls. CLAUDE.md scope guardrails honored throughout.

## Suggested order for your morning

1. Skim the M9 plan ([.claude/plans/m9-plan.md](.claude/plans/m9-plan.md)) — push back on any of the four open questions above.
2. Review PR #13 (Tier-2). It's the higher-priority of the two fixups — silent signal-death was a real safety hole.
3. Review PR #14 (Tier-3). Pure polish; reject if any of the three changes feel wrong.
4. If both look good: `gh pr merge 13 --squash` then `gh pr merge 14 --squash`. Each will auto-trigger the verifier subagent on merge.
5. Pick a sub-milestone (M9.A / M9.B / M9.C) to start; they're independent so any order works.

---

Ready for your morning review.

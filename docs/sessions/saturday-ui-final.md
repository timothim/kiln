# Saturday UI session — final report

**Session window:** 2026-04-25, autonomous run on `polish/saturday-ui-audit`.
**Scope (per brief):** visual quality, UX flow, design polish only. `apps/Kiln/Sources/{Views,Features}` and `apps/Kiln/Sources/DesignSystem.swift`. **Read-only:** `DESIGN.md`. **Off-limits:** `packages/*` (LEAD's parallel session).
**Output PR:** [#18 polish(saturday): pre-demo UI audit](https://github.com/timothim/kiln/pull/18) — **NOT MERGED** per brief.

---

## Audit summary

`docs/audits/saturday-ui-audit.md` carries the full per-view assessment. Aggregate counts:

| Severity | Count | Action |
|---|---|---|
| Blocker | 2 | Both fixed |
| High | 6 | All 6 fixed |
| Medium | 13 | 8 fixed, 5 deferred (logged) |
| Low | 14 | All deferred (logged) |

**Total findings:** 35.
**Total fixed in this session:** 16.
**Total logged for backlog:** 19.

The 19 logged findings are deliberate deferrals — micro-spacing tweaks (2/3/6 px outside the 4-pt grid), single-site magic numbers, and the seven Phase 3 amber-rule exceptions sanctioned in `docs/design/phase3-report.md` that need a DESIGN.md patch (not a code change) to ratify.

---

## Fixes applied per phase

### Phase 1–2 (read + audit doc)
Five parallel subagent reads covered all 50 view files: Stages+Routing (15), Components (14), DatasetDoctor+Importers (7), Features panels (8), KilnVoices+KilnShare (4). Cross-referenced against `DESIGN.md` and `docs/design/phase3-report.md` to separate drift from sanctioned exceptions. Wrote `docs/audits/saturday-ui-audit.md`: 228 lines, severity-bucketed, every finding pinned to `file:line`, with a forward-looking "DESIGN.md gaps" section.

### Phase 3 (apply fixes)

Six commits, all built clean before commit:

**`e61edce polish(audit-1)` — copy + success state + audit doc**
- IngestErrorView headlines re-written as verb-first instructions (DESIGN.md "errors name the fix").
- CancellingOverlay copy promoted to spec ("Cancelling — your last chunk is saved.").
- ShareExportSheet success state: green checkmark (replaces banned `firing`), single sanctioned exclamation mark, demo-legible import command (padding `xs → sm`, opacity `0.04 → 0.06`).
- ShareExportSheet toggles: explicit accessibility labels + hints per option.
- ShareExportSheet bespoke `Divider().opacity(0.4)` removed, falls back to semantic default.
- ImportSourceButton: catch-all error leads with the recovery path; primary button gets `.accessibilityLabel` + `.accessibilityHint`.
- VoiceInspectorPanel: drop hardcoded "five samples" so the empty state doesn't go stale.

**`106a153 polish(audit-2)` — BackupSettingsView token compliance**
- Replace all spacing literals (16/20/4/12) with `Kiln.Space.*`.
- Replace `.title2`/`.callout`/`.footnote` with `Kiln.Font.*`.
- Replace `.foregroundStyle(.red)` with `Kiln.Palette.danger`.
- Replace `UserDefaults(suiteName: "preview-idle")!` force-unwrap with `?? .standard`.
- Add accessibility hints; promote ISO8601 timestamps to relative format.

**`2fb3a87 refactor(design)` — SectionLabel extraction**
- New `apps/Kiln/Sources/Views/Components/SectionLabel.swift`.
- Removes three private duplicates from VoiceInspectorPanel, StyleSignatureCardView, ShareExportSheet.
- Adds `.accessibilityAddTraits(.isHeader)` so VoiceOver users can navigate sections via the rotor (additive).

**`13dd75a refactor(design)` — Kiln.Opacity tokens (cardFill, codeFill)**
- 23 `Color.primary.opacity(0.04|0.06)` literals replaced with the named tokens across 15 files.
- No visual change; resolved color is identical.

**`ae81554 refactor(design)` — Kiln.Motion semantic tokens**
- Add `microToggle` (.smooth 0.2s), `sampleReveal` (.smooth 0.6s), `skeletonPulse` (.easeInOut 0.9s repeating).
- Replace 5 inline duration literals across GrowingModelPanelView, StyleSignatureCardView, VoiceInspectorPanel, VoiceMirrorView.
- StyleSignature skeleton speeds up by 0.1s — imperceptible at human scale, system-wide consistency wins.

**`acf9172 polish(audit-3)` — chat thinking indicator + trackFill token**
- ChatView: replace bare `…` mid-stream placeholder with a `ProgressView` + "Thinking…" pair, accessibility-labeled.
- Add `Kiln.Opacity.trackFill = 0.08`; replace 9 sites that used the literal for capsule tracks, skeleton bars, user-side chat bubble fill.

### Phase 4 (shared component extraction)

`SectionLabel` is the headline extraction (commit 3 above). One canonical component, three sites consuming it, accessibility uplift on top. The audit doc identified `EmptyState` as already canonical and `Stat` / `LiveCountTicker` as candidates for further consolidation if 3+ surfaces ever drift; left as-is since the value of extracting is below the cost of churning the call sites.

### Phase 5 (demo-flow walkthrough)

Walked the 9-beat demo per `.claude/skills/kiln-demo-recording/SKILL.md` after all fixes landed. No new fixes surfaced — every critical-path view is polished:

| Beat | View | Status |
|---|---|---|
| 0:15-0:40 Drop folder | EmptyDropView | clean — amber wash on `isTargeted`, dropCardMaxWidth respected |
| 0:40-1:15 Dataset Doctor | DatasetDoctorView, IngestProgressView, IngestErrorView | clean — error headlines now name the fix; ingest counters animate |
| 0:40-1:15 Style Profile | StyleSignatureCardView | clean — skeleton uses canonical pulse token |
| 1:15-2:00 Teach | TrainStageView Teach card | clean — sanctioned amber CTA, ember glow |
| 1:15-2:00 Growing Model | GrowingModelPanelView | clean — sampleReveal token paces the per-prompt update |
| 2:00-2:30 Voice Mirror | VoiceMirrorView | clean — microToggle on pin/highlight, skeletonPulse on generating |
| 2:30-2:50 Export | ExportProgressView | clean — green checkmarks on done, amber wash only during running |
| 2:30-2:50 Chat | ChatView | clean — Thinking indicator instead of bare ellipsis |
| 2:50-3:00 Share | CompleteStageView + ShareExportSheet | clean — green check + sanctioned "!" + legible command block |

---

## Shared components extracted

1. **`SectionLabel`** (`apps/Kiln/Sources/Views/Components/SectionLabel.swift`) — replaces three private duplicates. Adds `.accessibilityAddTraits(.isHeader)`.

That's it for this session. The audit doc lists `EmptyState` as already canonical (single source of truth) and flags potential future extractions if drift appears.

---

## Design-system additions

`apps/Kiln/Sources/DesignSystem.swift` grew by two new enum buckets:

```swift
enum Opacity {
    static let cardFill: Double = 0.04
    static let codeFill: Double = 0.06
    static let trackFill: Double = 0.08
}

// Plus three additions to the existing `Motion` enum:
static let microToggle: Animation = .smooth(duration: 0.2)
static let sampleReveal: Animation = .smooth(duration: 0.6)
static let skeletonPulse: Animation = .easeInOut(duration: 0.9)
    .repeatForever(autoreverses: true)
```

Both buckets are documented with rationale comments. **Neither is yet sanctioned in `DESIGN.md`** — the audit doc's "DESIGN.md gaps" section flags them for the next DESIGN.md patch pass.

---

## Commits and PR

| Commit | Subject |
|---|---|
| `e61edce` | polish(audit-1): copy that names the fix, success state, audit doc |
| `106a153` | polish(audit-2): BackupSettingsView design tokens, remove force-unwrap |
| `2fb3a87` | refactor(design): extract shared SectionLabel component |
| `13dd75a` | refactor(design): Kiln.Opacity tokens replace 23 ad-hoc literals |
| `ae81554` | refactor(design): inline animation durations to Kiln.Motion tokens |
| `acf9172` | polish(audit-3): chat thinking indicator + Opacity.trackFill token |

**PR:** https://github.com/timothim/kiln/pull/18
**Status:** open, **not merged** (per brief).
**Branch:** `polish/saturday-ui-audit`

### LEAD's commits also on this branch

The branch shares a working tree with LEAD's parallel correctness/security session, so four `fix(*)` commits were interleaved with mine on the same ref:

- `391ccd3 fix(M9.C): recover inputs and train real distilled classifiers`
- `f493e9e fix(runners): stderr drain ordering across all subprocess runners`
- `4d2b683 fix(security): path-traversal guards in Backup module`
- `d5806b0 fix(classifiers): JSON parse-loop guard and empty-text filter in embed_search`

Scope is `packages/*` only — zero overlap with the polish stack. The PR description documents both stacks; commits are self-contained and cherry-pickable if the reviewer prefers two PRs.

### Verifier verdict

`verifier` subagent ran with fresh context against the full diff before opening the PR.

> **VERDICT: clean — Stack A and Stack B are mergeable**
> Both stacks pass at every checkpoint. Stack A is mechanical token discipline + a thoughtful component extraction with no semantic drift. Stack B is correctness/security work with directly-targeted regression tests.

Two non-blocking findings:
- **[M1]** Path-traversal integration test in Stack B is shallow (re-asserts the unit-level coverage). Cosmetic naming fix — not blocking.
- **[L2]** Audit-doc/code drift on the BackupSettingsView `panelWidth` choice (the audit doc mentioned a `Kiln.Layout.*` token; the implementer chose a private static constant with comment). Not a code issue.

---

## DESIGN.md gaps to ratify

Documented in `docs/audits/saturday-ui-audit.md` under "DESIGN.md gaps". Summary:

1. **`Kiln.Opacity.{cardFill, codeFill, trackFill}`** — three new opacity tokens used across 32 sites. Should be sanctioned.
2. **`Kiln.Motion.{microToggle, sampleReveal, skeletonPulse}`** — three new animation tokens. Should be sanctioned.
3. **Seven Phase 3 amber exceptions** — VoiceMirror heatmap, VoiceInspector highlight, VoiceSplitter active chip, VoiceSelector identity dot, ImportSourceButton progress, MessagesImportView/NotesImportView checkmarks, ExportProgressView green check. All sanctioned by `docs/design/phase3-report.md` but not yet in DESIGN.md.
4. **Sub-4pt micro-grid (2/3/6 px)** — eight component sites use spacings outside the formal 4-pt scale. Either formalize `tight: 2` / `compact: 6` or sweep to nearest 4-multiple.

---

## What Tim should review first

1. **PR #18 description** — confirms the two-stack situation is OK and that LEAD's commits being on this branch isn't a problem for the merge plan.
2. **`apps/Kiln/Sources/Features/KilnShare/ShareExportSheet.swift:142-146`** — the success state (green check + "Exported X!"). This is the demo's last beat; the polish bar is highest here. Confirm the visual reads as a victory in dark mode + light mode.
3. **`apps/Kiln/Sources/Views/DatasetDoctor/IngestErrorView.swift:55-66`** — the new error headlines. Verify the verb-first instructions read as helpful, not bossy.
4. **`docs/audits/saturday-ui-audit.md` § "DESIGN.md gaps"** — the next DESIGN.md patch pass should land these as sanctioned tokens / exceptions. Without ratification, future polish passes will keep flagging the same Phase 3 sites as drift.
5. **Demo dry-run end-to-end at 4K** — every critical-path view was walked through but actual recording will surface anything I missed.

---

UI audit and polish complete. Awaiting your review.

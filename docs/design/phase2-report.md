# Phase 2 report — DESIGN.md adoption across the SwiftUI view layer

**Branch:** `claude/pensive-nash-6bfd2c` -> `feat/ui`
**Date:** 2026-04-23
**Scope:** Regenerate `apps/Kiln/Sources/DesignSystem.swift` as the Swift projection of `/DESIGN.md`, refactor every existing view to consume tokens, fix three amber-drift sites, align `SPEC.md §10.1` with DESIGN.md, log `DECISIONS.md` entry 10. No functional changes, no new views, no hierarchy changes, no animation-timing changes.

## 1. Files refactored, grouped by commit

### Commit 1 — `refactor(design): regenerate DesignSystem.swift from DESIGN.md`

Atomic mass rename forced by a value collision: old Swift `Space.m` = 24pt, DESIGN.md `space.m` = 16pt. The rename ran in strict order (`.l -> .xl`, `.m -> .l`, `.s -> .m`) so freshly-renamed values were never consumed by a later pass.

| File | Renames applied |
|---|---|
| `apps/Kiln/Sources/DesignSystem.swift` | Full rewrite. New: `firing`, `firingWash`, `danger`, `surfaceSunken`, `Font.bodyMD/bodySM/label/numeric`, `Space.sm`. Preserved as aliases: `Font.body`, `Font.caption`, `Radius.control/card/modal`. |
| `Views/Stages/TrainStageView.swift` | Space rename |
| `Views/Stages/ReadyStageView.swift` | Space + Palette rename |
| `Views/Stages/PrepareStageView.swift` | Space rename |
| `Views/Stages/CompleteStageView.swift` | Space rename |
| `Views/EmptyDropView.swift` | Space + Palette rename |
| `Views/SidebarView.swift` | Space rename |
| `Views/Detail/SamplePreviewPanel.swift` | Space rename |
| `Views/Detail/PrepareDetailView.swift` | Space rename |
| `Views/Detail/LogsPanel.swift` | Space rename |
| `Views/Detail/CompleteDetailView.swift` | Space rename |
| `Views/Detail/ChatPanel.swift` | Space rename |
| `Views/DatasetDoctor/IngestErrorView.swift` | Space + Palette rename |
| `Views/DatasetDoctor/IngestProgressView.swift` | Space + Palette rename |
| `Views/DatasetDoctor/DatasetDoctorView.swift` | Space + Palette rename |
| `Views/DatasetDoctor/CancellingOverlay.swift` | Space rename |
| `Views/Components/ReadingIndicator.swift` | Palette rename |
| `Views/Components/SampleCarousel.swift` | Space + Palette rename |
| `Views/Components/StageProgressBar.swift` | Palette rename |
| `Views/Components/StageBadge.swift` | Palette rename |
| `Views/Components/TrainingProgressCapsule.swift` | Palette rename |
| `Views/Components/EmberGlow.swift` | Palette rename |
| `Views/Components/DropHintIcon.swift` | Palette rename |
| `Views/Components/EmptyState.swift` | Space rename |
| `Views/Components/Stat.swift` | Space rename |

25 files, 128 insertions, 84 deletions.

### Commit 2 — `refactor(design): components consume DESIGN.md tokens (+fix amber drift on SampleCarousel, ReadingIndicator)`

- `Views/Components/ReadingIndicator.swift` — **amber fix.** `Kiln.Palette.firing` -> `.secondary`; shadow uses `Color(nsColor: .secondaryLabelColor)`. Motion curve unchanged.
- `Views/Components/SampleCarousel.swift` — **amber fix** (two sites). `SampleCard` and `EmptySampleCard` backgrounds: `firingWash` -> `surfaceSunken`.
- `Views/Components/StageProgressBar.swift` — **drift fix.** Track was `firingWash`, now `surfaceSunken` per DESIGN.md §components split (track/bar).
- `Views/Components/ProjectCard.swift` — tokenized `spacing: 4` -> `Kiln.Space.xxs`.

### Commit 3 — `refactor(design): dataset doctor and ingest views consume DESIGN.md tokens (+fix amber drift on IngestErrorView)`

- `Views/DatasetDoctor/IngestErrorView.swift` — **amber fix** (two sites). Error-panel background `firingWash` -> `surfaceSunken`. Non-cancelled error-icon color `firing` -> `danger` (`#D32F2F`).
- `Views/DatasetDoctor/IngestProgressView.swift` — **drift fix.** Stage-row icon `firing` -> `.secondary`. Ingest is reading, not firing; the StageProgressBar below is the view's single firing accent.

### Commit 4 — `refactor(design): stage, drop zone, detail, and sidebar views consume DESIGN.md tokens`

- `Sources/DesignSystem.swift` — added `Kiln.Layout.centerMinWidth = 360`.
- `Views/RootView.swift` — `.frame(minWidth: 360)` -> `.frame(minWidth: Kiln.Layout.centerMinWidth)`.
- `Views/Detail/SamplePreviewPanel.swift` — tokenized `spacing: 4` -> `Kiln.Space.xxs`.
- `Views/Detail/ChatPanel.swift` — `Kiln.Space.xs - 4` -> `Kiln.Space.xxs`.

### Commit 5 — `docs: align SPEC §10.1 with DESIGN.md spacing hierarchy; DECISIONS entry 10`

- `SPEC.md §10.1` rewritten to reference DESIGN.md as normative, reflect the six-token spacing scale (`xxs, xs, sm, m, l, xl`), document the `danger` / `surfaceSunken` additions and the `label` / `numeric` type tokens.
- `DECISIONS.md` entry 10: "DESIGN.md as single source of truth for design tokens; Swift projection is hand-crafted." Records options considered ((a) Swift-authoritative, (b) DTCG-generated, (c) hand-crafted projection) and the rationale for (c).
- `docs/design/phase2-report.md` (this file).

## 2. Final amber audit

Every remaining `Kiln.Palette.firing` / `firingWash` call site:

| File:line | Usage | Verdict |
|---|---|---|
| `DesignSystem.swift:18,25` | Token definitions | ✓ expected |
| `TrainingProgressCapsule.swift:20,26` | Training progress bar fill + glow | ✓ firing moment |
| `StageProgressBar.swift:16` | Bar (the filled portion) | ✓ firing moment (track is surfaceSunken) |
| `EmberGlow.swift:18,21` | Modifier; applied to firing-moment surfaces | ✓ firing moment |
| `EmptyDropView.swift:50` | Launch drop-zone targeted-state wash | ✓ firing moment (DESIGN.md line 234) |
| `ReadyStageView.swift:53` | Inline drop-zone targeted-state wash | ✓ firing moment (DESIGN.md line 234) |
| `DropHintIcon.swift:9,14` | Hero folder glyph inside the launch drop zone | ✓ firing moment |
| `StageBadge.swift:29,38` | Dot + pill color — **only in `.training` stage**; all others neutral | ✓ firing moment |
| `DatasetDoctorView.swift:90` | "Continue to training" CTA fill | ✓ firing moment (CTA) |

Prose-only mentions of `firing` in doc comments: `IngestProgressView.swift:40-42` (explains why the stage-row icon is secondary), `StageBadge.swift:3`, `EmberGlow.swift:3`, `ReadingIndicator.swift:5`, `StageProgressBar.swift:4`.

No drift remains.

## 3. DESIGN.md gaps discovered (candidates for a Phase 1 patch)

These are intentional literals preserved under the hardcoded-literal policy — rounding them to the nearest legal token would change pixel-exact rhythms tuned during M3/M4. Surfacing here so the review signal is "explicit gap, documented" rather than "invisible drift."

- **Sub-`xxs` spacing (2pt).** Used for typographic-scale gaps between a numeric display and its caption: `LiveCountTicker:12`, `Stat:11`, `SamplePreviewPanel:46` (via `spacing: 6`), and `.padding(.top, 2)` in `ProjectCard:31`. Consider a `tight: 2` token. Current state: kept as literal with explanatory comment where non-obvious.
- **6pt spacing.** Between `xxs`(4) and `xs`(8), used for icon-to-label clusters where neither reads right: `EmptyDropView:31`, `ProjectCard:18`, `StageBadge:9`, `ChatPanel:64`, `SamplePreviewPanel:45`. Appears also as `Kiln.Space.xs - 2` arithmetic at `SidebarView:58` (10pt variant), `ProjectCard:36` (6pt), `LogsPanel:58` (6pt), `ChatPanel:24` (6pt). Consider a `gap-6: 6` token — or accept that inline kerning-scale rhythms don't quantize to the 4-pt grid and keep these as literals.
- **Opacity scale.** `Color.primary.opacity(0.04…0.08)` appears as semantic separator/ghost fills (`CompleteStageView:80`, `ChatPanel:50`, `SamplePreviewPanel:60`, `StageBadge:39`) and `Color.secondary.opacity(0.55)` as an intermediate-state foreground (`StageBadge:32`). Consider a `Kiln.Opacity` enum (`separator: 0.06`, `ghost: 0.04`, `intermediate: 0.55`) for intent-bearing values.
- **`numeric` type token size.** DESIGN.md's `numeric` is 17pt medium. `LiveCountTicker` renders at 13pt (`Kiln.Font.caption` + `.monospacedDigit()`). Switching to the 17pt `numeric` would be a visible regression in a prominent ticker. Consider adding `numericSm` to DESIGN.md for tickers at caption scale.
- **`label` kerning.** DESIGN.md's `label` token specifies `+0.04em`. SwiftUI has no em-relative kerning; the projection comment in `DesignSystem.swift:48` documents the `.kerning(0.44)` call-site pattern, but no label call sites exist today. Deferred; revisit when Phase 3 introduces a label consumer.
- **Hero glyph frame size (92pt).** `DropHintIcon:10` has `.frame(width: 92, height: 92)` — a hand-tuned size that doesn't snap to any existing size token. Consider a `Kiln.Icon.heroFrame` if other hero glyphs want to share this dimension.

## 4. Verification

- `make build` clean at every commit.
- `make test`: 86 Swift + 118 Python tests passing, same counts as pre-Phase-2.
- `make design-lint`: 0 errors, 3 known warnings (the WCAG contrast notes on `#D97706` text-on-amber and the `surface-sunken` label contrast, all pre-existing).

## 5. PR

Opened via `gh pr create --base main --head feat/ui --title "Phase 1+2: adopt DESIGN.md and refactor existing views to consume tokens"` once the branch is fast-forwarded. PR URL appended here on create.

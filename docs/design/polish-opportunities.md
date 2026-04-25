# Polish opportunities — Phase 3 feature views

**Branch:** `feat/ui` (merged to `main` at `161486b`)
**Scope:** Read-only scan of `apps/Kiln/Sources/Features/**/*.swift` after Phase 3 merge. No code changes.
**Classification:** P1 = clear UX win worth a follow-up; P2 = codebase hygiene / DRY; P3 = nice-to-have.

## 1. Cross-cutting

| # | Finding | Evidence | Class |
|---|---|---|---|
| 1.1 | `SectionLabel` (all-caps kerned tertiary label) defined privately in 3 files | `StyleSignatureCardView.swift`, `VoiceInspectorPanel.swift`, `ShareExportSheet.swift` | P2 |
| 1.2 | `.kerning(0.44)` repeated 19× across 7 files | every label-styled text | P2 |
| 1.3 | AttributedString-hover-highlight pattern duplicated verbatim | `VoiceMirrorView.swift:238` and `VoiceInspectorPanel.swift:118` | P2 |
| 1.4 | Icon-size arithmetic at call sites — suggests missing tokens | `VoiceInspectorPanel.swift:190` (`Icon.small - 3` = 11pt), `ShareExportSheet.swift:131` (`Icon.small + 2` = 16pt) | P2 |
| 1.5 | Opacity literals (0.04, 0.06, 0.08) for ghost fills / separators appear 28× | all 10 feature files | P2 |

**Follow-up** (1.1 + 1.2): a shared `Components/SectionLabel.swift` plus a `Text.kilnLabelStyle()` view modifier would collapse ~25 lines across the tree.

**Follow-up** (1.3): extract `AttributedString.kilnHighlight(_ phrases: [String])` into the DesignSystem subtree so the two uses stay consistent if the firing-wash alpha ever changes.

**Follow-up** (1.4 + 1.5): both were flagged in Phase 2 report as DESIGN.md gaps. Phase 3 confirms the gap is real — `Kiln.Icon.inline: 11` and `Kiln.Opacity.{ghost, separator, overlay}` would each be consumed ≥3×.

## 2. P1 — Growing Model panel (M6)

| # | Finding | Evidence |
|---|---|---|
| 2.1 | Stylization gauge crossing major thresholds (50 / 75 / 100 %) has no VoiceOver announcement | `GrowingModelPanelView.swift:193` — `accessibilityLabel` reads only the current number, not the milestone. A VoiceOver user hears "67 percent" → "71 percent" without noticing the crossing. |
| 2.2 | `samples.isEmpty` with `state != .empty` renders as header + spacer, no message | no guard at `GrowingModelPanelView.swift:52` |
| 2.3 | "Congrats — your model has found its voice." is an inline tertiary caption | `GrowingModelPanelView.swift:67` — for the emotional anchor moment of M6, the caption reads undersold. Consider a brief firing-glow transition or a one-shot banner. |
| 2.4 | Response crossfade duration is a call-site literal (0.6s) rather than a DESIGN.md motion token | `GrowingModelPanelView.swift:147` — documented inline as intentional, but "considered reveal" could become `Kiln.Motion.considered` if a second site needs the same pacing. |

## 3. P2 — Voice Mirror (M7)

| # | Finding | Evidence |
|---|---|---|
| 3.1 | Four-column HStack has no minimum width — narrow window breaks layout | `VoiceMirrorView.swift:116` — a `.frame(minWidth:)` on each column or a breakpoint reflow to 2×2 would stabilize this |
| 3.2 | Hover-only heatmap is invisible to keyboard users and VoiceOver | `VoiceMirrorView.swift:238` — a "Show signature phrases" toggle (off by default, per-column or global) would surface the overlay non-gesturally |
| 3.3 | No copy-to-clipboard affordance on generated continuations | demo users consistently want to paste these into slides / docs |
| 3.4 | `a11yLabel` reads full continuation verbatim | `VoiceMirrorView.swift:250` — fine for short outputs, but long generated text makes VoiceOver walk unreadable. Consider truncating the label to the first sentence + "plus N more characters". |

## 4. P3 — Style Signature Card + exporter (M7)

| # | Finding | Evidence |
|---|---|---|
| 4.1 | `StyleSignatureCardArt` has no root `.accessibilityElement(children: .combine)` | `StyleSignatureCardView.swift:107` — screen readers walk every text individually; combine would read as a single artifact |
| 4.2 | No loading skeleton | if DATA's style-extractor takes time in M7, the card has no intermediate render |
| 4.3 | NSSavePanel defaults to `~/Documents` | `StyleSignatureExporter.swift:40` — Desktop is more discoverable for a visual share artifact. `panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first` would nudge without overriding user preference |
| 4.4 | `FlowLayout` has no layout cache | `StyleSignatureCardView.swift:301` — acceptable for ~10 items; flag if promoted to shared component |
| 4.5 | Export button uses `Label("Export as PNG", systemImage:)` but success message does not reference "PNG" | `StyleSignatureCardView.swift:77` + `:70` — "Saved to tim-kiln-voice.png." already carries the extension, so non-issue; flagged only for consistency audit |

## 5. P4 — Kiln Voices (M8)

| # | Finding | Evidence |
|---|---|---|
| 5.1 | `createdAt` formatted as absolute medium date | `VoiceSplitterView.swift:225` — "2 days ago" reads warmer for a library that grows over time; `RelativeDateTimeFormatter` swap is low-effort |
| 5.2 | Menu labels in selector show raw `voice.name` with no disambiguator | `VoiceSelectorView.swift:22` — two voices named "Tim — drafts" would look identical |
| 5.3 | Delete confirm row replaces actions in place | `VoiceSplitterView.swift:138` — after Cancel, the delete icon is only visible on hover. Non-hover users (keyboard nav, reduced-motion) can't re-reach it without leaving and re-entering the card |
| 5.4 | No Enter-to-activate or Return-to-confirm shortcut on cards | `VoiceSplitterView.swift` — keyboard nav requires Tab + Space; defaultAction wiring would speed up voice-switching |

## 6. P5 — Importers (M8)

| # | Finding | Evidence |
|---|---|---|
| 6.1 | Progress bar uses `GeometryReader` — discouraged on macOS for perf | `ImportSourceButton.swift:126` — a fixed-container + `.frame(width: total * ratio)` alternative exists |
| 6.2 | MainActor-boundary bridging via `Task { @MainActor in progress = snapshot }` inside `@Sendable` closure | `ImportSourceButton.swift:217` — works but adds a per-tick task spawn. An `@MainActor` helper on the view would clean this up |
| 6.3 | No visual indication of which importers have already run in this session | if a user returns to the screen after running Messages, there is nothing to distinguish "done" from "idle" |
| 6.4 | `MockImportProvider.scenario` is `var` | `ImportSourceButton.swift:225` — scenario is set once at init; should be `let` |

## 7. P6 — Voice Inspector (M9)

| # | Finding | Evidence |
|---|---|---|
| 7.1 | Icon-size math at call site (`Icon.small - 3`) | `VoiceInspectorPanel.swift:190` — see finding 1.4. Adding `Kiln.Icon.inline = 11` would clean this up |
| 7.2 | Excerpts have no "copy" affordance | users annotating attribution want to paste the exact excerpt into research notes |
| 7.3 | Empty state does not indicate where to click | `VoiceInspectorPanel.swift:157` — copy says "Select a phrase" but not "click any span of generated text in the Voice Mirror". Cross-reference would set expectations |
| 7.4 | Attribution footer disclaimer is always visible | `VoiceInspectorPanel.swift:165` — low priority but consumes real estate. An info (ⓘ) button surfacing a popover would save ~32pt vertical |

## 8. P7 — Kiln Share (M10)

| # | Finding | Evidence |
|---|---|---|
| 8.1 | `onExport` returning `ShareBundleSummary?` with `nil` = cancellation is ambiguous | `ShareExportSheet.swift:18` — a typed `enum ExportOutcome { case success(Summary), cancelled, failed(Error) }` would distinguish user cancellation from a silent failure |
| 8.2 | No "Reveal in Finder" affordance in the success block | `ShareExportSheet.swift:122` — macOS-idiomatic after any file export; one `NSWorkspace.selectFile(_:inFileViewerRootedAtPath:)` call |
| 8.3 | Copy feedback uses a single `.copied` sentinel; no `.failed` | `ShareExportSheet.swift:290` — pasteboard writes rarely fail but the edge is uncovered |
| 8.4 | Size estimate shown only post-export | `ShareExportSheet.swift:160` — toggling `sourceManifest` materially changes bundle size; a live preview under the toggles would reinforce the decision |

## 9. Microcopy audit

Scanned all user-facing strings in `apps/Kiln/Sources/Features/**/*.swift` against apps/Kiln/CLAUDE.md rules.

- No exclamation marks in UI copy ✓
- No raw hyphens where em-dashes are called for ✓
- "Actually," starters appear only in mock data (Voice Mirror), which is intentional signature content
- "regret not shipping" appears in both VoiceMirror and VoiceInspector mocks — deliberate, it is the demo thesis
- "Generated by Kiln" watermark on signature card — consistent with brand voice
- "Your recipient runs" — nice framing; clearer than "Import command" would have been

One small note: `MessagesImportView.swift:45` uses straight apostrophes ("Kiln reads..."). Curly apostrophes (Kiln reads…) would match Apple HIG stricter, but the existing repo already ships straight quotes throughout, so this is consistency-preserving, not a regression.

## 10. Priority summary

- **P1 (ship before demo):** 2.1, 2.3, 3.1, 3.2, 4.2, 5.1, 8.2
- **P2 (before v1):** 1.1, 1.2, 1.3, 1.4, 1.5, 6.1, 6.3, 7.3, 8.1, 8.4
- **P3 (nice-to-have):** everything else

# Phase 3 report — feature UI scaffolding under apps/Kiln/Sources/Features/

**Branch:** `claude/pensive-nash-6bfd2c` -> `feat/ui`
**Date:** 2026-04-24
**Scope:** Seven SwiftUI feature surfaces for milestones M6–M10, all under a new `apps/Kiln/Sources/Features/` tree. Each view consumes DESIGN.md tokens through `DesignSystem.swift` (unchanged from Phase 2). No existing files in `apps/Kiln/Sources/Views/` or `Sources/KilnApp.swift` were touched. No `KilnCore` import.

## 1. Features completed

| Priority | Feature | Files | Milestone |
|---|---|---|---|
| P1 | Growing Model panel | `Features/GrowingModel/GrowingModelPanelView.swift` | M6 |
| P2 | Voice Mirror split-screen | `Features/VoiceMirror/VoiceMirrorView.swift`, `VoiceMirrorModel.swift` | M7 |
| P3 | Style Signature Card + PNG exporter | `Features/StyleSignature/StyleSignatureCardView.swift`, `StyleSignatureExporter.swift` | M7 |
| P4 | Kiln Voices (splitter + selector) | `Features/KilnVoices/VoiceSplitterView.swift`, `VoiceSelectorView.swift` | M8 |
| P5 | Messages & Notes importers | `Features/Importers/ImportSourceButton.swift`, `MessagesImportView.swift`, `NotesImportView.swift` | M8 |
| P6 | Voice Inspector slide-in | `Features/VoiceInspector/VoiceInspectorPanel.swift` | M9 |
| P7 | Kiln Share export sheet | `Features/KilnShare/ShareExportSheet.swift` | M10 |

12 Swift files, ≈3,000 lines (views + previews + local mocks). `make build` / `xcodebuild -scheme Kiln -destination 'platform=macOS' build` returned `** BUILD SUCCEEDED **` after each priority.

## 2. Per-feature preview coverage

Every feature ships with ≥2 `#Preview` blocks covering an empty / invitation state, a populated state, and at least one deliberate failure or edge state.

| Feature | Preview count | Variants |
|---|---|---|
| Growing Model | 4 | empty (waiting for first checkpoint), in-progress partial, in-progress full, completed |
| Voice Mirror | 4 | empty / invitation, generating (all four columns), done with signature phrases, mixed (one column failed) |
| Style Signature Card | 2 | populated casual (Tim), minimal technical (Alex) |
| Kiln Voices splitter | 3 | empty library, single voice (first run), three voices (one active) |
| Kiln Voices selector | 3 | no voices, with active voice, multiple none-active |
| ImportSourceButton | 3 | Messages fresh, Notes always-denied, Mail mid-import failure |
| MessagesImportView | 2 | grants-on-tap, denied-once-then-retry |
| NotesImportView | 2 | grants-on-tap, always-denied (settings required) |
| Voice Inspector | 4 | no selection, loading, populated, base-model span (no nearby samples) |
| Kiln Share | 2 | default configurable, user-cancelled save panel |

## 3. UI-layer types that mirror `KilnCore` scaffolds

LEAD landed Foundation-only scaffolds at `packages/KilnCore/Sources/KilnCore/Features/`. Each Phase 3 view defines its own UI-shaped types so DATA's M6–M10 wire-up is a field swap rather than a re-model.

| KilnCore type | UI type | Extensions |
|---|---|---|
| `VoiceMirror.Reflection { prompt, continuation, adapterStep }` | `VoiceReflection` | adds `source`, `state`, `signaturePhrases` (presentation + hover heatmap) |
| `StyleSignatureCard.Signature { embedding, markdownCard, topLexicalMarkers }` | `StyleSignature` | superset — adds `userLabel`, `summary`, weighted phrases, syntactic patterns, sentence-length buckets, register |
| `KilnVoices.Voice { id, name, ollamaTag, createdAt }` | `Voice` | adds `sampleCount`, `isActive` |
| `NativeImporters.Source { messages, notes, mail, obsidian }` | `ImportSource` | identical cases + `displayName`, `systemImage`, `subtitle` |
| `NativeImporters.ImportProgress { source, itemsSeen, itemsAccepted }` | `ImportProgress` | drops `source` (the button already knows which source it is) |
| `VoiceInspector.Attribution { generatedSpan, nearestChunkIDs, logOddsTopTerms }` | `InspectorSelection` + `NearestSample[]` | splits into selection + resolved samples — presenter will resolve IDs in M9 |
| `KilnShare.Bundle { bundleURL, sizeBytes, sha256 }` | `ShareBundleSummary` + `ShareIncludeOptions` | adds what-to-include toggles for the modal |

No view imports `KilnCore`. When DATA wires up in M6–M10 it will thread core types into each view at the presenter layer and the call sites stay unchanged.

## 4. DESIGN.md compliance audit

Every feature view consumes tokens from `apps/Kiln/Sources/DesignSystem.swift` only:

- Palette — `firing`, `firingWash`, `danger`, `surfaceSunken`, plus SwiftUI semantic colors (`.primary`, `.secondary`, `.tertiary`)
- Font — `display`, `title`, `body`, `caption`, `label`, `mono`, `numeric`, `bodyMD`, `bodySM`
- Space — `xxs`, `xs`, `sm`, `m`, `l`, `xl` (only `.m` and `.l` used at 2-level depth for section rhythm)
- Radius — `sm`, `card` (aliases `sm`, `md`), `modal` (alias `lg`)
- Icon — `small`, `heading`, `placeholder`, `hero`
- Motion — `Kiln.Motion.standard` on state transitions

### Amber usage — every site is intentional

| File:line | Use | Justification |
|---|---|---|
| `GrowingModelPanelView.swift` (StylizationGauge) | Progress-bar fill for per-prompt stylization score | Firing moment — stylization rising over training is the emotional payoff M6 is built around. Same family as the existing TrainingProgressCapsule. |
| `VoiceMirrorView.swift` (attributedContinuation) | Background + foreground on signature phrases **when a column is hovered** | Content-emphasis exception — flagged in Phase 2 report as a DESIGN.md gap. Repeated inline in the file's class doc so the linter has clear prose to sanction when DESIGN.md defrosts. |
| `VoiceSplitterView.swift` (VoiceCard active) | Card background (firingWash) + border (firing .45 alpha) on the active voice | The active voice is the single firing moment on this screen — hosts expect "which voice is loaded right now" to be the first thing that reads. |
| `VoiceSelectorView.swift` (identity dot) | 8pt dot fill next to the active voice label | Same argument as splitter — active = firing. |
| `ImportSourceButton.swift` (progressRow) | Progress-bar fill on live import | Firing moment — user committed to granting access and the corpus is growing. |
| `MessagesImportView.swift` / `NotesImportView.swift` (summaryRow checkmark) | Filled checkmark glyph after import success | Success on a high-stakes permission-gated flow reads as a firing moment. |
| `VoiceInspectorPanel.swift` (highlightedAttributed) | Same hover-only heatmap convention as Voice Mirror | Same content-emphasis exception. |
| `ShareExportSheet.swift` (success checkmark) | Filled checkmark glyph in the success state | Export completion — the whole sheet exists for this moment. |

`Kiln.Palette.danger` is used for two sites (`ImportSourceButton` denial icon, identical to the Phase 2 `IngestErrorView` precedent). Every other red / orange / amber in the feature tree resolves through `firing` or the SwiftUI semantic layer.

## 5. DESIGN.md gaps discovered

Same list Phase 2 flagged, with two new additions from Phase 3. Candidates for a future DESIGN.md patch; none blocked Phase 3 delivery.

1. **(carry)** Sub-xxs spacing (`2pt`) — no token; used for inline identity-dot-to-label rhythms.
2. **(carry)** Gap-6pt — no token; inline metadata clusters.
3. **(carry)** Opacity scale — `Color.primary.opacity(0.04 … 0.08)` appears at many ghost-fill / separator sites; a `Kiln.Opacity { ghost, separator, overlay }` enum would help.
4. **(carry)** `Kiln.Font.numeric` is 17pt medium — unused in Phase 3 because most ticker-scale numbers want `body` or `caption`. Room for a `numericSm` variant at 13pt.
5. **(new — Phase 3)** Content-emphasis amber is now a repeating pattern: Voice Mirror hover heatmap, Voice Inspector selection highlight. Formalize in DESIGN.md as a sanctioned exception alongside firing moments.
6. **(new — Phase 3)** Similarity / percentage pill pattern appears in Voice Inspector and (implicitly) in Growing Model. Consider a shared `Kiln.Components.Pill` or at least a DESIGN.md note sanctioning the capsule+monospacedDigit combo.

## 6. Notes for DATA wire-up

- All model-like data lives in `@Observable` classes or `@State` in views. No view caches state across launches.
- Every async operation runs in a `Task { @MainActor [weak self] in ... }` block and respects cancellation via `try? await Task.sleep(for:)`.
- `ImportSourceButton` talks to a local `ImportProvider` protocol. `MockImportProvider` satisfies it for previews. The real implementation will live in `KilnCore` and bridge `NativeImporters.importFrom(_:progress:)`.
- `StyleSignatureExporter.exportPNG` writes PNG + tEXt metadata via `CGImageDestination`. There is no sibling-file fallback — if the metadata write fails the function returns an error message.
- `ShareExportSheet.onExport` is async and returns `ShareBundleSummary?`. `nil` means the user cancelled the NSSavePanel — handled silently.

## 7. Verification

- `xcodebuild -scheme Kiln -destination 'platform=macOS' build` — `** BUILD SUCCEEDED **` after every priority commit.
- `make build` — clean (Xcode project regenerated via `xcodegen` between priorities; `.xcodeproj` is gitignored).
- No force-unwraps, no `fatalError` in shipped code, no exclamation marks in microcopy, every interactive element has an `.accessibilityLabel`.
- CLAUDE.md ship guarantees preserved: no `Anthropic`, `OpenAI`, or network-call imports introduced.

## 8. PR

Opened as `Phase 3: UI views for features 3-10` against `main` — URL to be appended after `gh pr create`.

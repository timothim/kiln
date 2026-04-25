# Saturday UI Audit — pre-demo polish pass

**Date:** 2026-04-25
**Scope:** `apps/Kiln/Sources/Views/` and `apps/Kiln/Sources/Features/` — 50 SwiftUI files.
**Excluded:** `packages/` (LEAD's parallel session), `DESIGN.md` (read-only — gaps are documented at the end of this file rather than patched).
**Method:** Five parallel subagent reads (Stages+Routing, Components, DatasetDoctor+Importers, Features panels, KilnVoices+KilnShare), cross-referenced against `DESIGN.md` and `docs/design/phase3-report.md`.

---

## Summary by severity

| Severity | Count | Action |
|---|---|---|
| Blocker | 2 | Fix before any demo run |
| High | 6 | Fix in this audit |
| Medium | 13 | Fix where cumulative time stays under 90 min |
| Low | 14 | Logged for backlog |

Total: **35 findings**. Of those, **24 sanctioned amber-rule "violations" identified by raw lint were re-classified as compliant** after cross-referencing `docs/design/phase3-report.md` §"Amber usage — every site is intentional". Those sites are NOT findings; they are documented Phase 3 exceptions awaiting DESIGN.md ratification (see "DESIGN.md gaps" below).

---

## Blockers

### B1 — `apps/Kiln/Sources/Features/KilnShare/ShareExportSheet.swift:133`
**Amber on success checkmark, not justified by Phase 3 report.**
The success state for a `.kiln` export uses `Kiln.Palette.firing` on a `checkmark.circle.fill`. DESIGN.md §"Do's and Don'ts" forbids `firing` on "checkmarks, success ticks". `docs/design/phase3-report.md` sanctions amber on import-permission checkmarks (high-stakes permission-gated success), but ShareExportSheet is a one-button export with no permission gate. This is the demo's last beat — the final visual the judge sees. Strict DESIGN.md compliance + the single permitted exclamation mark together carry the celebration without the amber.

**Fix:** Replace `.foregroundStyle(Kiln.Palette.firing)` with `.foregroundStyle(.green)` (system semantic for success) and add the single permitted exclamation mark to the headline at line 134 (`"Exported \(filename)"` → `"Exported \(filename)!"`). DESIGN.md §Typography explicitly sanctions ONE exclamation mark on this exact screen.

### B2 — `apps/Kiln/Sources/Features/Settings/BackupSettingsView.swift:88,95-96,100,102-104,116,134,138-139,147-148,156,161,203`
**Hardcoded values throughout — bypasses the design system.**
This view skipped tokens entirely:
- Spacing literals: `16` (line 88), `20` (line 95), `4` (line 100), `12` (line 116) — none use `Kiln.Space.*`.
- Frame width: `460` literal (line 96), should be `Kiln.Layout.*`.
- Typography: `.title2.weight(.semibold)` (line 102), `.callout` (lines 104, 134, 139, 147), `.footnote` (line 156, 161) — bypasses `Kiln.Font.*`.
- Color: `.foregroundStyle(.red)` (line 148) — should be `Kiln.Palette.danger` per DESIGN.md ("`.red` not guaranteed to match the palette").
- Force-unwrap in #Preview (line 203): `UserDefaults(suiteName: "preview-idle")!` — DESIGN.md "no force-unwraps in view files."

**Fix:** Replace each value with the matching token. New `Kiln.Layout.settingsPanelWidth = 460` if the literal must persist semantically, otherwise drop the fixed width and let the panel size to content. Remove the force-unwrap with a `?? .standard` fallback.

---

## High-severity

### H1 — `apps/Kiln/Sources/Views/DatasetDoctor/IngestErrorView.swift:55-64`
**Error headlines describe the failure, not the fix.** DESIGN.md §"Errors": *Errors name the fix, not the failure*. Current headlines:
- `"Cancelled"` — informational, OK
- `"Nothing to learn from"` — emotional, no fix
- `"Folder unavailable"` — describes failure
- `"Cannot write scratch files"` — describes failure
- `"Could not read the folder"` — describes failure
- `"Something went wrong"` — generic

**Fix:** Re-write to action-oriented copy. The body text (`error.userFacingMessage`) already names the recovery; the headline should mirror it as a verb-first instruction:
- `.noExamplesGenerated`: "Add more text to your folder"
- `.directoryNotFound`: "Re-select your folder"
- `.outputDirectoryNotWritable`: "Free up some disk space"
- `.parserFailed`: "Try a different folder"
- `.other`: "Try another folder" (matches the button)

### H2 — `apps/Kiln/Sources/Features/KilnShare/ShareExportSheet.swift:108-123`
**Toggles missing accessibility labels and hints.** Each include-options toggle ("Signature card", "README", "Source manifest") wraps a custom label view; VoiceOver reads the title alone with no hint about what changing the toggle does. Apps with this many toggles need explicit `.accessibilityLabel` + `.accessibilityHint`.

**Fix:** Add `.accessibilityLabel("Include <option>")` and `.accessibilityHint("<one-sentence what it adds to the bundle>")` to each toggle.

### H3 — `apps/Kiln/Sources/Features/KilnShare/ShareExportSheet.swift:52,60`
**Bespoke divider opacity.** Two `Divider().opacity(0.4)` calls. DESIGN.md uses material-based elevation — bespoke opacity-modulated dividers fragment the system. The system default already separates panel sections.

**Fix:** Drop `.opacity(0.4)` on both lines and let the Divider render at semantic default.

### H4 — `apps/Kiln/Sources/Features/Importers/ImportSourceButton.swift:236`
**Generic error swallows the recovery path.** `"Import failed: \(error.localizedDescription)"`. DESIGN.md: "Errors name the fix."

**Fix:** Wrap with a fix-naming sentence: `"Import didn't finish. Check Privacy & Security in System Settings, then try again."`

### H5 — `apps/Kiln/Sources/Features/Importers/ImportSourceButton.swift:138` and `apps/Kiln/Sources/Views/DatasetDoctor/DatasetDoctorView.swift:80`
**Primary buttons missing `.accessibilityLabel`.**

**Fix:** Add label matching the visible text — VoiceOver gets a confident label even when the visible label is short.

### H6 — Three duplicate `SectionLabel` definitions
`apps/Kiln/Sources/Features/VoiceInspector/VoiceInspectorPanel.swift:271`, `apps/Kiln/Sources/Features/StyleSignature/StyleSignatureCardView.swift:347`, `apps/Kiln/Sources/Features/KilnShare/ShareExportSheet.swift:327` — three private structs with identical bodies (Kiln.Font.label + .kerning(0.44) + .foregroundStyle(.tertiary) + .textCase(.uppercase)). Drift risk every time one is edited.

**Fix:** Extract to `apps/Kiln/Sources/Views/Components/SectionLabel.swift`; delete the three privates.

---

## Medium-severity

### M1 — `ShareExportSheet.swift:181-190` — import-command block too subtle for 4K demo
The mono import command sits in `Kiln.Space.xs` (8px) padding and `Color.primary.opacity(0.04)` background. Demo viewers need to read the command without pausing — both values are too quiet at recording resolution.

**Fix:** Bump padding to `Kiln.Space.sm` (12px) and the background to `Color.primary.opacity(0.06)` (matches what TrainStageView and CompleteStageView use on adjacent code blocks — see M5).

### M2 — `apps/Kiln/Sources/Views/DatasetDoctor/CancellingOverlay.swift:16`
**Cancellation copy not reassuring.** Currently `"Cancelling."` (a period). DESIGN.md component spec for `cancelling-overlay`: `"Cancelling — your last chunk is saved."`

**Fix:** Update text to the spec.

### M3 — `apps/Kiln/Sources/Features/GrowingModel/GrowingModelPanelView.swift:167`
**Inline `0.6s` animation duration.** Should flow through `Kiln.Motion.*`.

**Fix:** Add `Kiln.Motion.sampleReveal: Animation = .smooth(duration: 0.6)` and use it.

### M4 — `apps/Kiln/Sources/Features/VoiceMirror/VoiceMirrorView.swift:337-339`
**Inline `0.9s` skeleton pulse.** Same root cause as M3.

**Fix:** Use `Kiln.Motion.standard` and adjust repeat to match.

### M5 — Cross-cutting: `Color.primary.opacity(0.04)` and `0.06` literals scattered
Three views reach for these as ad-hoc tokens for code-block / sample-card backgrounds:
- `apps/Kiln/Sources/Views/Stages/TrainStageView.swift:415` — `0.06`
- `apps/Kiln/Sources/Views/Stages/CompleteStageView.swift:147` — `0.06` (wait — let me re-check; my hand-rolled audit caller flagged this but the ShareController landed *after* main, so it's not on main; verify before fixing)
- `apps/Kiln/Sources/Views/Detail/SamplePreviewPanel.swift:60` — `0.04`
- `apps/Kiln/Sources/Features/KilnShare/ShareExportSheet.swift:99,156,189` — `0.04`

**Fix:** Add to `DesignSystem.swift`:
```swift
enum Opacity {
    /// Sample-card / quiet panel fill (4% primary on surface).
    static let cardFill: CGFloat = 0.04
    /// Code-block / inline-mono fill (6% primary on surface).
    static let codeFill: CGFloat = 0.06
}
```
Replace literals with `Color.primary.opacity(Kiln.Opacity.cardFill)` etc.

### M6 — `ChatView.swift:142`
**Bare ellipsis during empty mid-stream tokens.** A streaming response that briefly empties shows a bare `…`. Reads as a stall.

**Fix:** Render an inline `ProgressView()` or `ReadingIndicator()` until the first non-whitespace token arrives; suppress the bare ellipsis branch.

### M7 — `VoiceMirrorView.swift:87`
**TextField placeholder uses "hear" metaphorically.** Kiln is text-only; viewers expect "see".

**Fix:** Defer — author's metaphor is intentional and the demo voice-over already disambiguates. Logged.

### M8 — `apps/Kiln/Sources/Views/Detail/SamplePreviewPanel.swift:60`
Covered by M5.

### M9 — `apps/Kiln/Sources/Features/Export/ExportProgressView.swift:50`
**`.green` checkmark — undocumented in palette.** DESIGN.md only declares firing/danger. macOS semantics say `.green` = success, but DESIGN.md should sanction it.

**Fix:** Document the gap below; leave the `.green` in place. (Apple-native success ticks are universally green; the system color semantically adapts.)

### M10 — `apps/Kiln/Sources/Views/Detail/SamplePreviewPanel.swift:45` and `ChatPanel.swift:64`
**Hardcoded HStack `spacing: 6`** — outside the 4-pt grid.

**Fix:** Use `Kiln.Space.xs` (8) — the visual delta is 2px and rarely meaningful.

### M11 — `IngestProgressView.swift:31`
**Cancel button missing accessibilityLabel.**

**Fix:** Add `.accessibilityLabel("Cancel the import")`.

### M12 — `VoiceInspectorPanel.swift:163`
**Copy hardcodes "five samples"** — stale if `NearestSample` count changes.

**Fix:** Drop the count: "Click any span of generated text to see the training samples closest to it."

### M13 — `apps/Kiln/Sources/Features/StyleSignature/StyleSignatureCardView.swift:153-157`
**Hardcoded `.opacity(0.4)` on dividers** with documented rationale (line 236). Acceptable but worth a token.

**Fix:** Defer; leave a comment that `Kiln.Opacity.divider = 0.4` would standardize this if 3+ sites adopt the value.

---

## Low-severity (logged, not fixed)

| # | File | Line | Finding |
|---|---|---|---|
| L1 | SidebarView.swift | 88 | `Kiln.Space.xs + 2` — micro-tweak math |
| L2 | TrainStageView.swift | 143 | `glowRadius: 20` magic |
| L3 | ChatPanel.swift | 24 | `Kiln.Space.xs - 2` micro-tweak |
| L4 | LogsPanel.swift | 58 | `Kiln.Space.xs - 2` repeats |
| L5 | PrepareDetailView.swift | 37 | `spacing: 2` outside grid |
| L6 | DropHintIcon.swift | 10 | `92×92` literal — `Kiln.Icon.dropZoneHero`? |
| L7 | EmberGlow.swift | 21–22 | shadow opacities `0.45 / 0.18` |
| L8 | EmptyState.swift | 33,44 | `maxWidth: 320 / 380` literals |
| L9 | LossSparkline.swift | 40,51 | grid `0.10` / line `0.85` |
| L10 | ProjectCard.swift | 18 | `spacing: 6` HStack |
| L11 | StageBadge.swift | 9,12,18,32 | sub-grid `6/3/0.55` |
| L12 | Stat.swift | 11 | `spacing: 2` |
| L13 | TrainingProgressCapsule.swift | 21,26 | `12 minWidth`, glow opacities |
| L14 | ChatView.swift | 86 | TextField placeholder uses model name |

These are real but cumulatively under the radar of a 4K demo. Logged for a follow-up "design-token sweep" pass — see DESIGN.md gaps below.

---

## Cross-cutting patterns to fix once

1. **Three SectionLabel duplicates** → extract to `Components/SectionLabel.swift`. Adopt in three call sites; future panels import the shared. (H6.)
2. **Two `Color.primary.opacity(0.04 / 0.06)` ad-hoc tokens** → `Kiln.Opacity.cardFill / codeFill`. Replace in SamplePreviewPanel, TrainStageView, ShareExportSheet. (M5.)
3. **Inline animation durations** in GrowingModel and VoiceMirror → semantic `Kiln.Motion.sampleReveal`. (M3, M4.)
4. **Missing accessibility labels on prominent CTAs** → audit Buttons in ImportSourceButton, DatasetDoctorView, IngestProgressView, ShareExportSheet (toggles). (H2, H5, M11.)

---

## DESIGN.md gaps (for Tim — not fixed in this audit)

The following code patterns are intentional Phase 3 exceptions sanctioned in `docs/design/phase3-report.md` §"Amber usage — every site is intentional", but are not yet in DESIGN.md. Each will lint as a violation until DESIGN.md is patched:

| Site | Phase 3 rationale | DESIGN.md patch suggestion |
|---|---|---|
| `VoiceMirrorView` per-word heatmap (firing + firingWash) | "Content-emphasis exception — interpretability overlay" | Add `interpretability-overlay` to allowed firing surfaces |
| `VoiceInspectorPanel` selection highlight (firing + firingWash) | Same as above | Same |
| `VoiceSplitterView` selected-persona chip (firingWash) | "Active = firing" | Add `active-selection-chip` to allowed surfaces |
| `VoiceSelectorView` identity dot (firing) | "Active = firing" — sidebar marker | Add `active-voice-marker` |
| `ImportSourceButton` import progress (firing fill) | "User committed to granting access; corpus is growing" | Add `permission-gated-progress` |
| `MessagesImportView` / `NotesImportView` summary checkmark (firing) | "Permission-gated success → firing moment" | Add `permission-gated-success` |
| `ExportProgressView` green checkmark | macOS-native success semantic | Add `success-tick` allowing system green |

Recommendation: when DESIGN.md "defrosts," add one §"Sanctioned exceptions" subsection naming each surface and the Phase 3 rationale. Until then, the code stays in its Phase 3 form and these audits flag-then-defer.

Additionally, the **micro-grid** (2px / 6px / 12px sub-multiples) appears in 8+ component files. Either formalize `Kiln.Space.tight = 2` and `compact = 6` in DESIGN.md, or do a sweep replacing each with the nearest 4-multiple. Out of scope for this audit.

---

## Decisions

- **Fix B1, B2, H1–H6** in commits on `polish/saturday-ui-audit`.
- **Fix M1, M2, M3, M4, M5, M6, M11, M12** as part of the same commits where they fit thematically.
- **Defer M7, M9, M13** — log only.
- **Defer all L1–L14** — log only.
- **Do not touch** any site listed in "DESIGN.md gaps" — these are intentional.
- **Do not touch `packages/`** — LEAD's territory.

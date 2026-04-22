---
name: swiftui-polish-kiln
description: Design system, SwiftUI polish rules, microcopy, animation, and empty-state discipline for Kiln. Load whenever Claude Code is writing, modifying, or reviewing a SwiftUI view, writing UI copy, debating typography, spacing, color, or animation, or preparing a polish pass. Enforces the Linear / Raycast / Things / Ivory quality bar.
---

# Kiln — SwiftUI polish rules

Reference: Apple HIG <https://developer.apple.com/design/Human-Interface-Guidelines>. Reference quality bar: Linear, Raycast, Things, Ivory. If a screen would look wrong in their portfolio, it fails.

## 1. Design tokens

All tokens live in `apps/Kiln/Sources/DesignSystem.swift`. Do not hard-code values anywhere else.

### 1.1 Color

- **Accent (single).** Amber `#D97706`. Used only for: ingest drop-zone glow, training progress bar, *Export* CTA, checkpoint pulse. **Never** for body text, icons, or dividers.
- **Base.** Use `.primary`, `.secondary`, `.tertiary` with `.regularMaterial` surfaces. Full dark-mode parity by construction.
- **Never** define a gradient. Flat colors only. Exception: the ember-glow animation (alpha pulse, not color).

### 1.2 Typography (SF Pro)

| Role | Size / Weight | Example |
|---|---|---|
| Display | 28 / semibold | Stage title in Training |
| Title | 22 / semibold | Panel headers |
| Body | 17 / regular | Everything prose |
| Caption | 13 / regular | Stats, timestamps |
| Mono | 13 / regular (SF Mono) | Logs, sample output |

Line height: 1.3× font size (SwiftUI default is fine for headlines, override to 1.4 for body in long paragraphs).

### 1.3 Spacing

4-pt grid. Legal containers: **8, 16, 24, 32**. No 10, no 20, no 28. `.padding(16)` is the default; `.padding(.horizontal, 24)` is the default for cards.

### 1.4 Materials

`.regularMaterial` for the main surfaces. `.ultraThinMaterial` only for the training HUD overlay. Corner radius: **12** for cards, **8** for inline controls, **20** for full-bleed modals. `RoundedRectangle(cornerRadius: 12, style: .continuous)` — always continuous.

## 2. Animation rules

- Default curve: `.smooth(duration: 0.35)`. Never `.bouncy`. Never `.snappy` for anything bigger than a button.
- Stage transitions: `.transition(.opacity.combined(with: .move(edge: .leading)))` with a 12pt offset.
- Numbers that increment use `.contentTransition(.numericText())`.
- The ember glow for training progress: opacity 0.9 → 1.0, 1.8s ease-in-out, repeating. Never a scale pulse — it reads as "alert".
- No animation longer than 600ms. No animation shorter than 200ms on a user-visible state change.
- `withAnimation` wraps state mutation, never view body construction.

## 3. Microcopy

### 3.1 Voice

Confident, concrete, verb-first. Write like Linear, not like enterprise SaaS.

### 3.2 Good vs bad (canonical examples)

| Bad | Good |
|---|---|
| Initiate training process | Teach your model |
| Dataset processed successfully | 2,487 chunks ready |
| Are you sure you want to stop? | Stop the run — your last checkpoint is saved |
| Failed to load model | Ollama isn't running. Start it and try again. |
| Welcome to Kiln! Please select a folder to begin. | Drop a folder. Meet yourself. |
| Model export complete! | Your model is ready. Open Terminal. |
| Loading... | — (use a progress indicator, not text) |

### 3.3 Rules

- No exclamation marks. One exception: the final export success screen (one, not more).
- No emoji.
- Numbers get commas at ≥ 1,000.
- Units are always written out: "minutes", not "min"; "tokens", not "tok".
- Errors name the fix, not the failure.

## 4. Empty states

Every panel has a designed empty state. The empty state is not an afterthought — it is often the first thing the user sees.

Template:

```
+-------------------------+
|        [icon]           |
|      Short headline     |
|   One-sentence context  |
|    [single CTA button]  |
+-------------------------+
```

Examples:

- Ingest (no folder dropped): "Drop a folder to start." + `DropHint` illustration.
- Growing Model (before iter 50): "Your model will start speaking at the first checkpoint."
- Compare (before any run): "Nothing to compare yet. Train a model first."

Never render a blank pane with only a title.

## 5. View architecture

- One view file per screen, `<Stage>View.swift`. View models live beside them as `<Stage>Model.swift` and use `@Observable`.
- Views never own mutable logic. State changes go through the view model.
- Max view body length: 80 lines. Extract subviews past that.
- Never use `GeometryReader` unless unavoidable. Prefer `.containerRelativeFrame` and `.aspectRatio`.

## 6. State management

- `@Observable` classes, not `ObservableObject`.
- One `KilnApp` root environment value holding the sidecar client and app-wide state; everything else is passed explicitly.
- Never use `@EnvironmentObject` — too easy to forget the attach.
- Long-running work: `Task.detached` with cooperative cancellation; never block `MainActor`.

## 7. Common mistakes to avoid ("AI slop aesthetic")

- Gradients labeled "modern". No.
- Three-color brand palettes. One accent only.
- Emoji in titles.
- Centered text on left-aligned layouts.
- Progress bars with percentages that don't move for 30 s. Ember-pulse shows liveness instead.
- Splash screens. Kiln opens straight into the drop zone.
- Toast notifications for success. Success is visible through state change.
- `.bold()` applied to every label in an attempt to add hierarchy.
- Settings pages that expose engineering knobs (rank, alpha). Those live in a hidden Cmd-Opt-K panel, not the main flow.

## 8. Polish pass protocol

When `/polish <View>` runs:

1. Read the view and its view model.
2. Check tokens: any hard-coded numbers, colors, spacings?
3. Check microcopy against §3.
4. Check empty state presence.
5. Check animation curves against §2.
6. Check accessibility: VoiceOver labels on every interactive element, min tap target 44pt, `accessibilityHint` where non-obvious.
7. Output 5 concrete improvements, each with a before/after diff snippet. No vague suggestions.

## 9. Accessibility (non-negotiable)

- VoiceOver labels on every button, including icon-only ones.
- Dynamic Type up to `.accessibility3`. No fixed font sizes on body text.
- Color is never the only signal — always paired with text or icon.
- Reduce Motion honored: ember glow degrades to a static accent.
- Contrast: WCAG AA minimum, measured on the amber accent in both themes.

## 10. The 30-second test

Before opening a PR on a view, stare at the screen for 30 seconds in both light and dark mode. If you want to change anything, change it before opening the PR.

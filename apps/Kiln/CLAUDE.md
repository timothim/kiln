# apps/Kiln — SwiftUI rules

Import skill: `.claude/skills/swiftui-polish-kiln/`. Load it whenever you open a view file in this subtree.

## Scope

This directory contains only the SwiftUI app shell and view layer. No data transformation, no IPC framing, no ML — all of that lives in `packages/KilnCore`.

## View architecture

- One view per screen: `<Stage>View.swift` in `Sources/Views/`.
- One view model per view: `<Stage>Model.swift` in `Sources/Models/`, annotated `@Observable`.
- Views render; view models orchestrate; services in KilnCore do the work.
- Max view body length: 80 lines. Past that, extract subviews.

## State management

- `@Observable` classes, never `ObservableObject`.
- One `KilnApp` root holds the sidecar client and shared state; pass explicitly, not via `@EnvironmentObject`.
- All long-running work: `Task.detached` with cooperative cancellation. Never block `MainActor`.

## Design tokens

All colors, fonts, spacing, corner radii live in `Sources/DesignSystem.swift`. Hard-coded tokens anywhere else are a blocking review finding. See skill §1.

## YOU MUST

- Never force-unwrap (`!`) outside of tests.
- Every user-facing string runs past the microcopy rules in the skill §3.
- Every view has a considered empty state.
- VoiceOver labels on every interactive element.
- No exclamation marks in UI copy (one allowed on final export success).

Pointer: full polish protocol in the skill §8. Run `/polish <view>` for a structured pass.

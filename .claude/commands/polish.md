---
description: Load the swiftui-polish-kiln skill and propose 5 concrete before/after improvements for a SwiftUI view. No vague suggestions — every item is a specific code diff.
argument-hint: <view-file>
---

# /polish

Polish pass on `${1}`.

## Inputs

- `${1}` — path to a SwiftUI view file (typically `apps/Kiln/Sources/<Stage>View.swift`).

## Behavior

1. Load `.claude/skills/swiftui-polish-kiln/SKILL.md` into context.
2. Read `${1}` and its sibling `<Stage>Model.swift` (if present).
3. Apply the Polish Pass Protocol (§8 of the skill):
   - Check design tokens for hard-coded colors, sizes, or spacings.
   - Check microcopy against the Good/Bad table.
   - Check for missing empty states.
   - Check animation curves and durations.
   - Check accessibility: VoiceOver labels, tap targets, Dynamic Type.
4. Produce **exactly 5** improvements, each with:
   - A one-line summary
   - The concrete category (Token / Microcopy / Empty state / Animation / Accessibility)
   - Before snippet (exact current code)
   - After snippet (exact proposed code)
   - One-sentence rationale grounded in the skill's rules

## Output structure

```
Polish report for ${1}
======================

1. [Category] <summary>
   Before:
     <code>
   After:
     <code>
   Why: <rationale>

... (5 items) ...

Quality-bar verdict:
  - Tokens: <pass|fail>
  - Microcopy: <pass|fail>
  - Empty state: <pass|fail>
  - Animation: <pass|fail>
  - A11y: <pass|fail>
```

## Refuses if

- The file is not a SwiftUI view.
- The file already passes all 5 categories — say so and exit.

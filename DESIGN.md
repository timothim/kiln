---
name: Kiln
description: A native macOS app that fine-tunes a local LLM to sound like you — slow, careful, on-device transformation, a kiln firing.
colors:
  firing: "#D97706"
  on-firing: "#FFFFFF"
  firing-wash: "#FCF4EB"
  surface: "#FFFFFF"
  surface-elevated: "#F9F9F9"
  surface-sunken: "#F2F2F7"
  on-surface: "#1C1C1E"
  on-surface-secondary: "#3C3C43"
  on-surface-tertiary: "#8E8E93"
  danger: "#D32F2F"
typography:
  display:
    fontFamily: SF Pro
    fontSize: 28px
    fontWeight: "600"
    lineHeight: 34px
    letterSpacing: -0.02em
  title:
    fontFamily: SF Pro
    fontSize: 22px
    fontWeight: "600"
    lineHeight: 28px
  body-md:
    fontFamily: SF Pro
    fontSize: 17px
    fontWeight: "400"
    lineHeight: 22px
  body-sm:
    fontFamily: SF Pro
    fontSize: 13px
    fontWeight: "400"
    lineHeight: 18px
  label:
    fontFamily: SF Pro
    fontSize: 11px
    fontWeight: "600"
    lineHeight: 14px
    letterSpacing: 0.04em
  mono:
    fontFamily: SF Mono
    fontSize: 13px
    fontWeight: "400"
    lineHeight: 18px
  numeric:
    fontFamily: SF Pro
    fontSize: 17px
    fontWeight: "500"
    lineHeight: 22px
    fontFeature: "tnum"
spacing:
  xxs: 4px
  xs: 8px
  sm: 12px
  m: 16px
  l: 24px
  xl: 32px
rounded:
  sm: 8px
  md: 12px
  lg: 20px
components:
  drop-zone:
    backgroundColor: "{colors.surface-elevated}"
    textColor: "{colors.on-surface}"
    typography: "{typography.body-md}"
    rounded: "{rounded.md}"
    padding: "{spacing.xl}"
  drop-zone-targeted:
    backgroundColor: "{colors.firing-wash}"
    textColor: "{colors.on-surface}"
    typography: "{typography.body-md}"
    rounded: "{rounded.md}"
    padding: "{spacing.xl}"
  live-count-ticker:
    textColor: "{colors.on-surface-secondary}"
    typography: "{typography.numeric}"
  sample-card:
    backgroundColor: "{colors.surface-sunken}"
    textColor: "{colors.on-surface}"
    typography: "{typography.body-md}"
    rounded: "{rounded.md}"
    padding: "{spacing.m}"
  sample-card-empty:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.on-surface-tertiary}"
    typography: "{typography.body-md}"
    rounded: "{rounded.md}"
    padding: "{spacing.m}"
  stage-progress-track:
    backgroundColor: "{colors.surface-sunken}"
    rounded: "{rounded.sm}"
    height: 6px
  stage-progress-bar:
    backgroundColor: "{colors.firing}"
    rounded: "{rounded.sm}"
    height: 6px
  cancelling-overlay:
    backgroundColor: "{colors.surface-elevated}"
    textColor: "{colors.on-surface}"
    typography: "{typography.body-md}"
    rounded: "{rounded.md}"
    padding: "{spacing.l}"
  button-primary:
    backgroundColor: "{colors.firing}"
    textColor: "{colors.on-firing}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "{spacing.sm}"
    height: 32px
  button-secondary:
    backgroundColor: "{colors.surface-elevated}"
    textColor: "{colors.on-surface}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "{spacing.sm}"
    height: 32px
  button-destructive:
    backgroundColor: "{colors.surface-elevated}"
    textColor: "{colors.danger}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "{spacing.sm}"
    height: 32px
---

## Overview

Kiln is slow, careful, on-device transformation. The product metaphor is a kiln firing: you load raw material (a folder of your writing), the app shapes it at its own pace, and a small local model emerges that sounds like you. Nothing leaves the machine. The interface should feel like that metaphor: patient, specific, quietly confident. Not a dashboard.

The visual language is cool neutrals with a single warm amber (`#D97706`, token `firing`) that appears **only during active firing moments**: the ingest drop-zone glow, the training progress bar, the ember pulse around a training view, the *Teach your model* CTA. Every other surface is system-native — SF Pro, `.regularMaterial`, semantic colors that adapt to light and dark mode automatically. The reference quality bar is Linear, Raycast, Things, and Ivory: considered typography, generous whitespace, purposeful motion, empty states that invite rather than apologize. If a Kiln screen would feel out of place in that portfolio, it fails the bar.

## Colors

`firing` is the single brand accent. Use it sparingly and only during firing moments (see *Do's and Don'ts*). The `firing-wash` token is an 8%-opacity blend used on drop-zone target states, training-stage card backgrounds, and the *Teach* CTA pill; it is **not** a general-purpose tint. `on-firing` pairs with `firing` on the one place amber becomes a background: `button-primary`.

Every other color in the app is a macOS semantic color, not a hex. `surface`, `on-surface`, `on-surface-secondary`, and `on-surface-tertiary` are declared here as light-mode hex approximations so that tooling has values to reason about. At runtime, SwiftUI resolves `.primary`, `.secondary`, `.tertiary`, and `.regularMaterial` automatically — the code references SwiftUI's semantic layer, not these hexes. This is a deliberate macOS-native divergence from the DESIGN.md convention (see *Do's and Don'ts → macOS-native conventions*).

- **Never** define or use a gradient. The ember glow is an alpha pulse on a single color, not a color transition.
- **Never** introduce a second accent. One color is the accent; everything else is neutral.
- **Never** use `firing` for body text, icons, dividers, borders, or decorative washes.
- **Dark mode is first-class.** Every surface must be verified in both modes before a view lands.

## Typography

SF Pro for UI text. SF Mono for logs, sample output, and any place where alignment or character-width stability matters. Line heights are 1.2–1.3× the font size for headlines and 1.3× for body. Dynamic Type is honored up to `.accessibility3`.

| Token | Role | Size / Weight | Example |
|---|---|---|---|
| `display` | Stage title | 28 / 600 | "Training" header in the Train stage |
| `title` | Panel header | 22 / 600 | "Recent sample", "Logs" |
| `body-md` | Default body | 17 / 400 | All prose, sample text |
| `body-sm` | Secondary body | 13 / 400 | Footnote captions |
| `label` | Small caps, button label | 11 / 600, +0.04em tracking | Button text, section eyebrows |
| `mono` | Logs, paths, samples | SF Mono 13 / 400 | Sidecar log output |
| `numeric` | Live-count ticker | 17 / 500, `tnum` | `2,487 chunks` in the ingest ticker |

The `numeric` token pairs with SwiftUI's `.contentTransition(.numericText())` so incrementing digits crossfade per-character instead of snapping. Tabular figures (`tnum`) keep the ticker's width stable as digits change.

Rules:

- No bold on every label to fake hierarchy. Use size + weight + color intent instead.
- No exclamation marks anywhere except the final export success screen (one, not more).
- No emoji.
- Numbers get commas at ≥ 1,000. Units are always written out ("minutes", not "min"; "tokens", not "tok").
- Errors name the fix, not the failure.

## Layout

A **4-point grid** governs all spacing. Containers use the tokens below:

| Token | px | Typical use |
|---|---|---|
| `xxs` | 4 | Tight inner rhythm in stacked labels |
| `xs` | 8 | Default gap between related items |
| `sm` | 12 | Icon-to-label gap, badge clusters, half-step rhythms |
| `m` | 16 | Card inner padding, content block gap |
| `l` | 24 | Card outer padding, stage margins |
| `xl` | 32 | Top-level section gaps |

`xxs` and `sm` are intentional extensions to the `{8, 16, 24, 32}` scale in `SPEC.md §10.1`. They are formalized here because M4 shipped 4pt and 12pt rhythms in real code (dataset doctor, sample carousel). `SPEC.md` will be updated to reference DESIGN.md as normative for the spacing scale.

The app layout is a three-pane macOS structure (sidebar · stage · detail). Legal dimensions live as `Kiln.Layout` constants in `DesignSystem.swift` and are not tokens here — they are window-level constraints, not reusable spacings.

## Elevation & Depth

Elevation is expressed through **materials and corner radii**, not shadows.

- **Base surfaces:** `.regularMaterial` — the main app chrome, sidebar, cards.
- **Overlay surface:** `.ultraThinMaterial` — training HUD overlay and the cancelling overlay.
- **Sunken surface:** `surface-sunken` — log panel backgrounds, sample card fills.

Shadows appear only on the ember glow around training-stage views. The glow is an alpha pulse (`opacity 0.9 → 1.0` over 1.8 s, ease-in-out, repeating) on a single color, never a scale pulse (scale reads as "alert") and never a shadow-offset change.

There are **no drop shadows** on cards, buttons, or panels. Depth in Kiln comes from material translucency, not from simulated light.

## Shapes

All corner radii are **continuous** (`RoundedRectangle(cornerRadius: X, style: .continuous)`). Three levels:

| Token | px | Use |
|---|---|---|
| `sm` | 8 | Inline controls (buttons, stage badges) |
| `md` | 12 | Cards, panels, sample cards, drop zone |
| `lg` | 20 | Full-bleed modals, training HUD |

Circular shapes (`Circle()`) are reserved for status dots and avatars. Never use `.clipShape(Circle())` on cards.

## Components

Each component entry in the frontmatter binds to tokens rather than raw values. The Swift projection in `apps/Kiln/Sources/DesignSystem.swift` and the view-level styling in `apps/Kiln/Sources/Views/**` apply these bindings.

- **`drop-zone`** — the landing surface of the app. The user sees this first. Copy: "Drop a folder. Meet yourself." Empty state: a muted `DropHintIcon` inside a dashed outline. Targeted state: swap to `drop-zone-targeted` — the `firing-wash` background lights up to signal the file will be accepted.
- **`live-count-ticker`** — displays ingest progress numbers that update several times per second. Uses `typography.numeric` so digits crossfade on change rather than snap.
- **`sample-card`** — a single `ChunkPreview` rendered with source icon, monospace path, and assistant snippet. Background is `surface-sunken` — a quiet elevated fill, **not** an accent wash. (M3 shipped an accent wash here; Phase 2 reverts it — see *Do's and Don'ts*.)
- **`sample-card-empty`** — the placeholder rendered before the first chunk arrives. Neutral `surface` background with tertiary copy ("Reading your folder.") — no amber.
- **`stage-progress-track`** / **`stage-progress-bar`** — the progress capsule splits into two tokens: the track (`surface-sunken`, always visible) and the fill (`firing`, animates in). Height fixed at 6 px for both.
- **`cancelling-overlay`** — short-lived overlay shown when the user cancels ingest. Body copy: "Cancelling — your last chunk is saved." No accent wash.
- **`button-primary`** — the *Teach your model* CTA. Amber background, white label. The only button in the app that uses `firing` as a background. Used once per stage at most. The amber-on-white contrast ratio (3.19:1) is below WCAG AA for small text; paired with deliberate choices that lift legibility — see *macOS-native conventions* below.
- **`button-secondary`** — every other button. System-elevated surface, primary-colored label.
- **`button-destructive`** — *Stop the run*, *Discard project*. No red fill; only the label is `danger`. Destructive intent is communicated by color + confirmation copy, not by a loud background.

## Do's and Don'ts

### The amber rule (non-negotiable)

**Amber (`firing` / `#D97706`) appears only during training progress visualization and the brand logo.**

Do:

- Use `firing` on `stage-progress-bar` (training fill), `ember-glow` (training-stage view), `button-primary` (the *Teach your model* CTA), ingest drop-zone targeted state, and the app icon.
- Use `firing-wash` on the *targeted* state of the drop zone, the training-stage card background, and the *Teach* CTA's backing pill.

Don't:

- Use `firing` or `firing-wash` on checkmarks, success ticks, "live" labels, identity dots, sidebar active-row markers, decoration on cards, error states, or any form of accent decoration.
- Use `firing` on the ReadingIndicator (the pulsing line shown during ingest file reads). Reading is not firing — it is anticipation. Use `on-surface-secondary` with the ember-glow motion curve instead.
- Use `firing-wash` on sample cards, error panels, or anywhere a neutral elevated surface would read as correct.

This rule codifies drift caught in the M3 verifier audit (`ReadingIndicator`, `SampleCarousel.accentWash` backgrounds, `IngestErrorView.accentWash` backgrounds). New views landing in Phase 2 and Phase 3 must enforce the rule from the start.

### Motion

- Default curve: `Kiln.Motion.standard` (`.smooth(0.35)`). **Never** `.bouncy`. **Never** `.snappy` on anything bigger than a button.
- All motion flows through `Kiln.Motion.*` tokens. **No inline duration literals in view code.**
- The ember pulse is alpha-only: 0.9 → 1.0 over 1.8 s, `Kiln.Motion.glow`. **Never** a scale pulse.
- Numbers that increment use `.contentTransition(.numericText())`.
- No animation longer than 600 ms. No animation shorter than 200 ms on user-visible state changes.
- Reduce Motion degrades the ember glow to a static accent.

### Typography and copy

- **Verb-first, confident, concrete.** "Teach your model" ≻ "Initiate training". "2,487 chunks ready" ≻ "Dataset processed successfully".
- No exclamation marks anywhere, except the final export success screen (one, not more).
- No emoji.
- Numbers get commas at ≥ 1,000. Units are always written out.
- Errors name the fix. "Ollama isn't running. Start it and try again." ≻ "Failed to load model".

### View code

- **No force-unwraps (`!`) in view files.** Compiler warnings are a blocking review finding.
- **No hardcoded hex colors outside `DesignSystem.swift`.** All color values flow from DESIGN.md → `DesignSystem.swift` → views.
- **Every panel has a designed empty state.** An empty pane with only a title is not acceptable.
- **Max view body length: 80 lines.** Past that, extract subviews.
- **One view per screen. One view model per view.** View models are `@Observable`, not `ObservableObject`.
- **Never block `MainActor`.** All long-running work runs in `Task.detached` with cooperative cancellation.

### macOS-native conventions

The `@google/design.md` linter encodes generic design-web conventions. Kiln is a macOS-native SwiftUI app and diverges in ways that are intentional:

- **`missing-primary` warning:** we do not define a `primary` brand color. Our single accent is `firing`, used only for firing moments. A "primary" in the web sense would invite its use everywhere, which contradicts the amber rule above. We accept the warning.
- **`contrast-ratio` warning on `button-primary`:** white label on `firing` resolves to a 3.19:1 ratio — below WCAG AA's 4.5:1 bar for small text, above the 3:1 bar for large text. We accept the warning and pair it with three mitigations: (1) the button renders its label at 11 px semibold with `+0.04em` tracking, which improves perceived weight; (2) the button carries the single warm signal in an otherwise cool UI, so it attracts attention by chromatic contrast rather than luminance contrast; (3) the button's affordance is always reinforced by an adjacent headline ("Drop a folder. Meet yourself.", "Teach your model"), so the label carries identification rather than primary information. Phase 2 will revisit with a `.tint(.orange)`-style system button if Apple's 2026 contrast guidance tightens further.
- **`contrast-ratio` warning in general:** most other Kiln surfaces use SwiftUI's adaptive semantic colors (`.primary`, `.secondary`, `.tertiary`) whose resolved RGB values change between light and dark modes. The hex values in `colors` are light-mode approximations for lint tooling; actual contrast is verified at runtime against SwiftUI's resolved palette in both modes.
- **`orphaned-tokens` warning:** reserved tokens that have no current `components` binding but are declared for Phase 2 / Phase 3 views (training HUD modal, multi-persona picker, voice inspector) will fire this warning. We accept it in exchange for keeping the scale stable as new features land.

We do **not** invent tokens or contort the system to satisfy these rules. Documented divergence beats drift.

### Accessibility (non-negotiable)

- VoiceOver label on every interactive element, including icon-only buttons.
- Dynamic Type up to `.accessibility3`. No fixed font sizes on body text.
- Color is never the only signal — always paired with text or an icon.
- Reduce Motion honored: the ember glow degrades to a static accent.
- Contrast measured in both modes. The amber accent must hit WCAG AA on its intended backgrounds.

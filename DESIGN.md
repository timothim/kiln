---
name: Kiln
description: A native macOS app that fine-tunes a local LLM to sound like you — slow, careful, on-device transformation, a kiln firing. Paper-and-ember aesthetic; warm cream surfaces; serif body type; one accent (amber).
colors:
  # Surface tiers — warm paper rather than cool greys
  paper: "#F5F1EA"            # app background, the canvas
  surface: "#FBF9F4"          # cards, panels
  surface-2: "#F0EBE0"        # secondary fills, chips, kbd
  surface-sunken: "#EBE5D7"   # prompt bars, sunken regions, log blocks
  surface-paper: "#FAF8F4"    # Post-it cards (Advisor, Voice Coach)

  # Foreground tiers — warm browns, not pure neutrals
  on-surface: "#1F1B16"       # primary text, AA against paper
  on-surface-2: "#5C5246"     # secondary text
  on-surface-3: "#8C8073"     # tertiary, captions, mono labels
  on-surface-4: "#B8AE9D"     # placeholder, disabled

  # Hairlines (rgba primary at low alpha)
  hairline: "rgba(31,27,22,0.10)"
  hairline-2: "rgba(31,27,22,0.06)"

  # The one accent — amber, only on firing moments
  firing: "#D97706"
  firing-2: "#B45309"          # hover, deeper accent
  firing-wash: "rgba(217,119,6,0.06)"          # selected row, gentle highlight
  firing-wash-strong: "rgba(217,119,6,0.14)"   # signature-phrase tint, log flash
  on-firing: "#FFFFFF"

  # Status — still warm-toned (no Crayola red, no neon green)
  ok: "#4F7A3D"
  ok-wash: "rgba(79,122,61,0.10)"
  warn: "#B45309"
  warn-wash: "rgba(180,83,9,0.10)"
  danger: "#A0341B"
  danger-wash: "rgba(160,52,27,0.10)"

typography:
  # SERIF for body and headlines — text is the hero (this is an app about your voice)
  display:
    fontFamily: "ui-serif"
    fontSize: 32px
    fontWeight: "500"
    lineHeight: 38px
  title:
    fontFamily: "ui-serif"
    fontSize: 24px
    fontWeight: "500"
    lineHeight: 30px
  body:
    fontFamily: "ui-serif"
    fontSize: 16px
    fontWeight: "400"
    lineHeight: 25px
  # SANS for chrome only — labels, captions, button text
  label:
    fontFamily: "ui-sans-serif"
    fontSize: 13px
    fontWeight: "500"
    lineHeight: 18px
  caption:
    fontFamily: "ui-sans-serif"
    fontSize: 12px
    fontWeight: "400"
    lineHeight: 17px
  # MONO for metadata, paths, keyboard shortcuts, tnum tickers
  meta:
    fontFamily: "ui-monospace"
    fontSize: 11px
    fontWeight: "400"
    lineHeight: 15px
  eyebrow:
    fontFamily: "ui-monospace"
    fontSize: 10px
    fontWeight: "500"
    lineHeight: 14px
    letterSpacing: 0.04em
  # tnum body — for incrementing counters (iter, loss, tokens/s)
  numeric:
    fontFamily: "ui-serif"
    fontSize: 16px
    fontWeight: "500"
    lineHeight: 25px
    fontFeature: "tnum"

spacing:
  s-1: 4px      # tightest inner rhythm
  s-2: 8px      # default gap between related items
  s-3: 12px     # icon-to-label gap, badge clusters
  s-4: 16px     # card inner padding
  s-5: 20px     # comfortable breathing
  s-6: 24px     # card outer padding, stage margins
  s-7: 32px     # top-level section gaps
  s-8: 40px     # full-bleed margins
  s-9: 56px     # hero section breaks
  s-10: 80px    # full-page chrome insets

rounded:
  r-1: 4px      # tags, kbd
  r-2: 6px      # small chips, controls
  r-3: 8px      # buttons, panels
  r-4: 10px     # mid-cards
  r-5: 12px     # canvas card, settings card
  r-6: 16px     # hero card
  r-pill: 999px # pill (chip, tag)

motion:
  # Curves
  kindled: "cubic-bezier(0.32, 0.72, 0, 1)"   # primary curve — almost-EaseOut, slow-to-start
  standard: "cubic-bezier(0.2, 0.7, 0.2, 1)"  # fallback
  # Timings — paired with kindled by default
  t-micro: 0.12s    # hover, press
  t-std: 0.22s      # tab switch, picker open
  t-kind: 0.35s     # surface mount, panel reveal
  t-route: 0.36s    # route crossfade
  t-ember: 1.8s     # ember-pulse cycle (alpha-only)

components:
  drop-zone:
    backgroundColor: "{colors.paper}"
    borderColor: "{colors.firing}"
    borderStyle: "dashed"
    borderWidth: 1.5px
    textColor: "{colors.on-surface}"
    typography: "{typography.body}"
    rounded: "{rounded.r-5}"
    padding: "{spacing.s-7}"
  drop-zone-targeted:
    backgroundColor: "{colors.firing-wash}"
    borderColor: "{colors.firing}"
    borderStyle: "solid"
    borderWidth: 1.5px
    textColor: "{colors.on-surface}"
    typography: "{typography.body}"
    rounded: "{rounded.r-5}"
    padding: "{spacing.s-7}"
  live-count-ticker:
    textColor: "{colors.on-surface-2}"
    typography: "{typography.numeric}"
  sample-card:
    backgroundColor: "{colors.surface}"
    borderColor: "{colors.hairline}"
    textColor: "{colors.on-surface}"
    typography: "{typography.body}"
    rounded: "{rounded.r-3}"
    padding: "{spacing.s-4}"
  post-it-card:
    backgroundColor: "{colors.surface-paper}"
    borderColor: "{colors.hairline}"
    textColor: "{colors.on-surface}"
    typography: "{typography.body}"
    rounded: "{rounded.r-3}"
    padding: "{spacing.s-4}"
    foldedCorner: true
  stage-progress-track:
    backgroundColor: "{colors.surface-sunken}"
    rounded: "{rounded.r-1}"
    height: 6px
  stage-progress-bar:
    backgroundColor: "{colors.firing}"
    rounded: "{rounded.r-1}"
    height: 6px
  log-block:
    backgroundColor: "{colors.surface-sunken}"
    textColor: "{colors.on-surface-3}"
    typography: "{typography.meta}"
    rounded: "{rounded.r-3}"
    padding: "{spacing.s-3}"
  cancelling-overlay:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.on-surface}"
    typography: "{typography.body}"
    rounded: "{rounded.r-5}"
    padding: "{spacing.s-6}"
  button-primary:
    backgroundColor: "{colors.firing}"
    textColor: "{colors.on-firing}"
    typography: "{typography.label}"
    rounded: "{rounded.r-3}"
    padding: "{spacing.s-3}"
    height: 32px
  button-secondary:
    backgroundColor: "{colors.surface-2}"
    textColor: "{colors.on-surface}"
    typography: "{typography.label}"
    rounded: "{rounded.r-3}"
    padding: "{spacing.s-3}"
    height: 32px
  button-ghost:
    backgroundColor: "transparent"
    textColor: "{colors.on-surface-2}"
    typography: "{typography.label}"
    rounded: "{rounded.r-3}"
    padding: "{spacing.s-3}"
    height: 32px
  button-destructive:
    backgroundColor: "{colors.surface-2}"
    textColor: "{colors.danger}"
    typography: "{typography.label}"
    rounded: "{rounded.r-3}"
    padding: "{spacing.s-3}"
    height: 32px
  chip:
    backgroundColor: "{colors.surface-2}"
    textColor: "{colors.on-surface-2}"
    typography: "{typography.meta}"
    rounded: "{rounded.r-pill}"
    padding: "4px 10px"
  chip-firing:
    backgroundColor: "{colors.firing-wash}"
    textColor: "{colors.firing}"
    typography: "{typography.meta}"
    rounded: "{rounded.r-pill}"
    padding: "4px 10px"
---

## Overview

Kiln is slow, careful, on-device transformation. The product metaphor is a kiln firing: you load raw material (a folder of your writing), the app shapes it at its own pace, and a small local model emerges that sounds like you. Nothing leaves the machine. The interface should feel like that metaphor: patient, specific, quietly confident — and the redesign leans warmer to make the patience legible.

The visual language is **paper-and-ember**. Every surface is a warm cream (`paper` `#F5F1EA`); every line of body type is set in **serif** (`ui-serif`, "New York" on macOS) — because Kiln is an app *about your voice*, and text is the hero. There is exactly one accent — `firing` `#D97706`, an amber/ember orange — and it appears only during firing moments: training progress, the drop-zone targeted state, the *Teach your model* CTA, the alive-state ember pulse on the training chip and advisor pill. Everything else is neutral warm-brown. Even success/warn/danger lean warm.

The reference quality bar is Linear, Things 3, Raycast, Arc, WWDC D1. If a Kiln screen would feel out of place in that portfolio, it fails the bar.

## Three load-bearing motion beats

The product story has three named beats. Everything else is in service of them.

1. **The Drop** — folder dragged onto the drop zone, target lights, the model is firing.
2. **The Training Pulse** — watch the trio of personas crystallize, checkpoint by checkpoint, in the user's voice.
3. **The Voice Reveal** — same prompt, side-by-side base vs. fine-tuned answer.

## Colors

`firing` is the single brand accent. Use it sparingly and only during firing moments (see *Do's and Don'ts*). The `firing-wash` token is a 6%-opacity blend used on selected rows / gentle highlights; `firing-wash-strong` (14%) is used on signature-phrase tints and log-flash effects. `on-firing` pairs with `firing` on the one place amber becomes a background: `button-primary`.

Every neutral color is a **warm brown** that adapts to dark mode. `on-surface` is `#1F1B16` against `paper`; the contrast is 13.4:1 — well above AA. The four-tier on-surface scale (`on-surface` → `on-surface-2` → `on-surface-3` → `on-surface-4`) replaces SwiftUI's semantic `.primary` / `.secondary` / `.tertiary` because we need two more steps for placeholder vs. tertiary states.

- **Never** define or use a gradient. The ember glow is an alpha pulse on a single color, not a color transition.
- **Never** introduce a second accent. One color is the accent; everything else is neutral warm.
- **Never** use `firing` for body text, icons, dividers, borders, or decorative washes.
- **Dark mode is first-class.** Every surface ships a warm-dark variant of every token (warm dark surfaces; cream-tinted text). Verify in both modes before a view lands.

## Typography

**Serif** (`ui-serif` → "New York" on macOS) for body, title, display, numeric.
**Sans** (`ui-sans-serif` → SF Pro Text) for labels, captions, button chrome.
**Mono** (`ui-monospace` → SF Mono) for metadata, paths, keyboard shortcuts, log content.

Line heights are 1.2–1.3× the font size for headlines and 1.55× for body — generous, paper-like. Dynamic Type is honored up to `.accessibility3`.

| Token | Role | Family / Size / Weight |
|---|---|---|
| `display` | Modal/sheet headline | serif 32 / 500 / 1.2 |
| `title` | Panel header | serif 24 / 500 / 1.25 |
| `body` | Default body | serif 16 / 400 / 1.55 |
| `label` | Button label, UI label | sans 13 / 500 / 1.4 |
| `caption` | Secondary body, footnote | sans 12 / 400 / 1.4 |
| `meta` | Mono metadata | mono 11 / 400 / 1.4 |
| `eyebrow` | Section eyebrow, kbd | mono 10 / 500, +0.04em tracking |
| `numeric` | Live-count ticker | serif 16 / 500, `tnum` |

The `numeric` token pairs with SwiftUI's `.contentTransition(.numericText())` so incrementing digits crossfade per-character instead of snapping. Tabular figures (`tnum`) keep widths stable as digits change.

Rules:

- **No exclamation marks anywhere except the final export-success screen** (one, not more).
- **No emoji.**
- Numbers get commas at ≥ 1,000. Units are written out ("minutes", not "min"; "tokens", not "tok").
- Errors name the fix, not the failure.

## Layout

A **4-point grid** governs all spacing. Tokens follow the s-N scale: `s-1`/4 → `s-10`/80. The first six (`s-1` to `s-7`) match the prior `xxs/xs/sm/m/l/xl` scale 1:1; the upper three (`s-8`/40, `s-9`/56, `s-10`/80) are new. Swift call sites can keep using either spelling — `Kiln.Space.xxs` / `Kiln.Space.s1` resolve to the same value.

| Token | px | Typical use |
|---|---|---|
| `s-1` | 4 | Tight inner rhythm in stacked labels |
| `s-2` | 8 | Default gap between related items |
| `s-3` | 12 | Icon-to-label gap, badge clusters |
| `s-4` | 16 | Card inner padding, content block gap |
| `s-5` | 20 | Comfortable breathing |
| `s-6` | 24 | Card outer padding, stage margins |
| `s-7` | 32 | Top-level section gaps |
| `s-8` | 40 | Full-bleed margins |
| `s-9` | 56 | Hero section breaks |
| `s-10` | 80 | Full-page chrome insets |

The app shell is a three-pane macOS structure (sidebar · stage · detail). The redesign replaces the chrome but preserves the structure. The main canvas wears the new chrome (`paper` background, `r-5` content card, hairline border, no drop shadow).

## Elevation & Depth

Elevation is expressed through **paper tiers and corner radii**, not shadows.

- **Background:** `paper` — the canvas all surfaces sit on.
- **Card / panel:** `surface` — quiet elevation.
- **Sunken surface:** `surface-sunken` — log panels, prompt bars.
- **Post-it surface:** `surface-paper` — Advisor, Voice Coach (slightly warmer to read as "annotation").
- **Modal:** `surface` with `box-shadow: 0 24px 48px rgba(31,27,22,0.24)`.

Drop shadows appear only on modals and sheets (the only true elevations). Cards, panels, and chips use **hairlines** (`hairline` / `hairline-2`) instead.

## Shapes

All corner radii are **continuous** (`RoundedRectangle(cornerRadius: X, style: .continuous)`).

| Token | px | Use |
|---|---|---|
| `r-1` | 4 | Tags, kbd |
| `r-2` | 6 | Small chips, controls |
| `r-3` | 8 | Buttons, panels |
| `r-4` | 10 | Mid-cards |
| `r-5` | 12 | Canvas card, settings card, modal |
| `r-6` | 16 | Hero card |
| `r-pill` | 999 | Chip, tag |

Circular shapes (`Circle()`) are reserved for status dots and avatars.

## Motion (Kindled)

**Kindled** is the motion personality. A kiln doesn't startle; it warms. Things take a beat to begin (slow attack), glow in the middle (sustained pulse on the active state), and settle back to neutral (no rebound, no overshoot).

The five rules of Kindled:

1. **Slow to start, never bouncy.** Default curve is `kindled` `cubic-bezier(0.32, 0.72, 0, 1)`. Never `.bouncy`. Never `.snappy` on anything bigger than a button.
2. **Alpha, not scale, for "alive."** The ember pulse is opacity 0.55 → 1.0 over 1.8s. Scale-pulses read as alerts; alpha-pulses read as life.
3. **Numbers crossfade per character.** Always `.contentTransition(.numericText())` on numbers that tick.
4. **Type-on/erase is the canonical content arrival animation.** Not a generic skeleton shimmer. Used for advisor messages, before/after, growing model, chat replies.
5. **Crossfades, not slides, between routes.** 360ms.

Timing tokens:

| Token | Duration | Use |
|---|---|---|
| `t-micro` | 0.12s | Hover, press |
| `t-std` | 0.22s | Tab switch, picker open |
| `t-kind` | 0.35s | Surface mount, panel reveal |
| `t-route` | 0.36s | Route crossfade between surfaces |
| `t-ember` | 1.8s | Ember-pulse cycle |

The **ember pulse** is the signature animation. A 1.8s alpha pulse on a 7px filled circle in `firing`, used wherever the model is "alive" (training chip, kiln-noor eyebrow, advisor pill).

Reduce Motion zeroes all `t-*` timings and disables type-on/erase (final string is written immediately). Honored at every animation site via `View.kilnMotion(_:value:)` / `View.kilnTransition(_:)` modifiers in `apps/Kiln/Sources/Views/Components/MotionModifiers.swift`.

## Components

### Buttons

- `button-primary` — `firing` fill, white label, deeper `firing-2` border. The single firing-as-background button. Used once per stage at most.
- `button-secondary` — `surface-2` fill, `on-surface` label. Default chrome button.
- `button-ghost` — transparent, `on-surface-2` label. Hovers to `surface-2`.
- `button-destructive` — `surface-2` fill, `danger` label. Destructive intent communicated by label color + confirmation copy, not loud surfaces.

All buttons get `transform: scale(0.98); opacity: 0.85` on `:active` (`.scaleEffect(0.98).opacity(0.85)` in SwiftUI), and `transition: all t-micro ease-out`.

### Chips

`chip` — pill with `surface-2` fill, mono 11px text. `chip-firing` adds a `firing-wash` background and an inline 7px ember-pulse. Used for "iter 200", "kiln-noor · iter 500", "Training" status.

### Cards & panels

- **Generic card:** `surface` fill, `hairline` 1px border, `r-3` corners, `s-4` padding. No drop shadow.
- **Post-it card** (Advisor / Voice Coach): `surface-paper` fill, the same border, plus a CSS-drawn folded corner (16×16 transparent triangle in the top-right). No box-shadow.
- **Sheet / modal:** `surface` fill, `r-5` corners, drop shadow `0 24px 48px rgba(31,27,22,0.24)`.

### Logs / mono blocks

`surface-sunken` fill, `meta` font (mono 11), line numbers in `on-surface-3`. New rows animate `log-flash` (background flashes `firing-wash-strong` → transparent over 0.6s).

### Sparkline

Drawn with SwiftUI `Canvas`. 1.5px stroke in `firing`. No fill underneath (clean line). The last point is a 4px filled circle pulsing on ember cadence.

### Numbers (`tnum`)

Always `monospacedDigit()`. For digit roll-ups (iter counter), pair with `.contentTransition(.numericText())`.

## Do's and Don'ts

### The amber rule (non-negotiable)

**Amber (`firing` / `firing-wash` / `firing-wash-strong`) appears only during training progress visualization, the drop-zone targeted state, the *Teach your model* CTA, the alive-state ember pulse, and signature-phrase tints in interpretability surfaces.**

Do:

- Use `firing` on `stage-progress-bar` (training fill), the ember pulse on training/advisor chips, the `button-primary` (the *Teach* CTA), the drop-zone targeted state, the brand mark.
- Use `firing-wash` on the *targeted* drop zone, selected rows, gentle highlights.
- Use `firing-wash-strong` on signature-phrase tints (Voice Mirror / Inspector / Before-After) and log-flash effects.

Don't:

- Use `firing` or `firing-wash` on body text, icons, dividers, decorative tints, generic success states (use `ok` / `ok-wash` for non-firing successes).
- Use `firing` on the ReadingIndicator (the pulsing line during ingest file reads). Reading is not firing — it is anticipation. Use `on-surface-2` with the ember-glow motion curve instead.

### Motion

- Default curve: `kindled`. Never `.bouncy`. Never `.snappy` on anything bigger than a button.
- All motion flows through `Kiln.Motion.*` tokens. **No inline duration literals in view code.**
- The ember pulse is alpha-only: 0.55 → 1.0 over 1.8s, `Kiln.Motion.glow` (= `t-ember`). Never a scale pulse.
- Numbers that increment use `.contentTransition(.numericText())`.
- Reduce Motion degrades the ember glow to a static accent, disables type-on, and zeros all transitions.

### Typography and copy

- **Verb-first, confident, concrete.** "Teach your model" ≻ "Initiate training". "2,487 chunks ready" ≻ "Dataset processed successfully".
- No exclamation marks except the final export-success screen (one, not more).
- No emoji.
- Numbers get commas at ≥ 1,000. Units written out.
- Errors name the fix. "Ollama isn't running. Start it and try again." ≻ "Failed to load model".

### View code

- **No force-unwraps (`!`) in view files.** Compiler warnings are a blocking review finding.
- **No hardcoded hex colors outside `DesignSystem.swift`.** All color values flow from DESIGN.md → `DesignSystem.swift` → views.
- **Every panel has a designed empty state.** An empty pane with only a title is not acceptable.
- **Max view body length: 80 lines.** Past that, extract subviews.
- **One view per screen. One view model per view.** View models are `@Observable`, not `ObservableObject`.
- **Never block `MainActor`.** All long-running work runs in `Task.detached` with cooperative cancellation.

### macOS-native conventions

The `@google/design.md` linter encodes generic design-web conventions. Kiln is a macOS-native SwiftUI app and diverges where intentional:

- **`missing-primary` warning:** we do not define a `primary` brand color. Our single accent is `firing`, used only for firing moments. A "primary" in the web sense would invite its use everywhere, which contradicts the amber rule above. Accept the warning.
- **`contrast-ratio` warning on `button-primary`:** white label on `firing` resolves to 3.19:1 — below WCAG AA's 4.5:1 bar for small text, above the 3:1 bar for large text. Accept the warning, paired with three mitigations: (1) the button renders its label at sans 13px / 500, which improves perceived weight; (2) the button carries the single warm signal in an otherwise warm-neutral UI, so it attracts attention by chromatic contrast rather than luminance contrast; (3) the button's affordance is always reinforced by an adjacent headline ("Drop a folder of your writing.", "Teach your model"), so the label carries identification rather than primary information.
- **`orphaned-tokens` warning:** reserved tokens that have no current `components` binding but are declared for future surfaces (storyboard, `share` wax-seal pattern, `bts` 4-stage film) will fire this warning. Accept it in exchange for keeping the scale stable.

### Accessibility (non-negotiable)

- VoiceOver label on every interactive element, including icon-only buttons.
- Dynamic Type up to `.accessibility3`. No fixed font sizes on body text.
- Color is never the only signal — always paired with text or an icon.
- Reduce Motion honored: ember glow → static accent, type-on → final string immediately, all transitions zeroed.
- Contrast measured in both modes. The amber accent must hit WCAG AA on its intended backgrounds.
- All interactive elements have visible `:focus-visible` rings: `firing` 2px outline, 2px offset.

## Information architecture

The shipping app has 22 surfaces in service of the three motion beats. The full surface table (Tier S/A/B per the brief) lives in `docs/design/design-package-reconciliation.md`. The `storyboard` surface from the prototype is *not* shipped — it's a recording aid; the demo uses the real surfaces.

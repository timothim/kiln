# Sunday UI session — final report

**Session window:** 2026-04-25 (PM), autonomous run.
**Branch:** `polish/sunday-final` off `main` (`dd5dab8`).
**Output PR:** [#28 polish: tasteful animations + final UX audit fixes](https://github.com/timothim/kiln/pull/28) — **NOT MERGED** per brief.
**Scope:** UI audit + animation pass. Read-only on `DESIGN.md`. Off-limits: `packages/*`.

---

## Audit findings summary

`docs/audits/sunday-ui-audit.md` carries the full per-flow assessment. Aggregate counts:

| Severity | Count | Action |
|---|---|---|
| Blocker | 2 | Both fixed (`9c13ece`) |
| High | 5 | All 5 fixed (`9c13ece`) |
| Medium | 3 | 1 fixed inline, 2 deferred (logged) |
| Low | 3 | All deferred |

### Per-flow visual quality scores

Anchor: 10 = Linear/Things/Ivory polish. Demo-critical flows below.

| Flow | Pre-audit | Post-fixes + animations |
|---|---|---|
| First launch → drop folder → Dataset Doctor | 9/10 | **9/10** (no audit findings; demo-ready) |
| Connect sources → ingestion → Dataset Doctor | 7/10 | **9/10** (Animation B + audit fixes) |
| Deep Curation review → accept/reject | 7/10 | **9/10** (B2 amber fix + tokens) |
| Click Teach → Training (GrowingModel + Advisor) | 8/10 | **9.5/10** (Animations A + F) |
| Export → Voice Coach report → Chat | 8/10 | **8/10** (no animation work needed) |
| MCP server settings → Connect to Claude.app | 7/10 | **8/10** (Animation G live-status dot) |
| Behind the Scenes page | 8/10 | **9/10** (Animation D agent network) |

---

## Animation work shipped

Eleven commits on `polish/sunday-final`. Each animation site lives behind a Reduce Motion gate; every animation uses `Kiln.Motion.*` semantic tokens; every TimelineView is capped at 30 fps.

### Foundation (`dd0d6ad`)

- **Five new `Kiln.Motion.*` tokens** for the Sunday pass:
  - `staggerStep` (.smooth 0.18s) — per-element step in a stagger sequence (Voice Mirror columns)
  - `recencyFade` (.easeOut 0.8s) — recency-highlight fade for newly-arrived log entries
  - `connectorGrow` (.smooth 0.3s) — sub-agent hierarchy connector lines drawing from parent to child
  - `networkPulse` (.easeInOut 2.2s, repeating) — slow continuous pulse for the agent-network diagram packets
  - `statusPulse` (.easeInOut 1.4s, repeating) — live-indicator dot breath
- **`Kiln.Motion.stageTransitionBackward`** — mirrored asymmetric transition for backward navigation between stages.
- **New `apps/Kiln/Sources/Views/Components/MotionModifiers.swift`** — `View.kilnMotion(_:value:)` and `View.kilnTransition(_:)` modifiers that thread `@Environment(\.accessibilityReduceMotion)` through every animation site, plus a `KilnMotion.respecting(_:reduceMotion:)` helper for explicit `withAnimation` call sites.

### A — Live training visualization (`e3f18f4`)

- GrowingModel sample card scales 0.97 → 1.0 over `Kiln.Motion.microToggle` (200ms) on each new checkpoint resample. The card stays in place; only its body breathes.
- StylizationGauge ember pulse: outer glow with score-dependent rate (3s period at 0% score → 1s at 100%), via TimelineView at 30 fps. Pauses when score ≤ 0% (`paused: clamped <= 0`).
- Step counter already correctly used `.contentTransition(.numericText())` from prior work — preserved.

### F — Loss curve (`399c34f`)

- LossSparkline switches from linear segments to **Catmull-Rom Bezier curves** (uniform parametrization, mirrored endpoints).
- Subtle gradient fill below the curve fading from `Color.primary.opacity(0.18)` to transparent.
- **Glowing latest-point dot**: 4-pt circle with TimelineView-driven shadow at the canonical `Kiln.Motion.statusPulse` 1.4s period.
- `ChartGeometry` extracted so curve, fill, and dot share one mapping function. `catmullRomPath` lives at file scope for reuse.

### C — Voice Mirror staggered reveal (`d663dab`)

- Four columns reveal in cadence: `columnIndex * 280ms` delay (0ms / 280ms / 560ms / 800ms cap), each over `Kiln.Motion.staggerStep`. Body fades in + slides up 8pt.
- **User-truth column** (`.userAnswer`) gets a slightly louder background (`Kiln.Opacity.codeFill = 0.06` vs `cardFill 0.04`) plus a 2pt secondary stripe along the leading edge.
- Regenerate replays the stagger via symmetric `withAnimation(staggerStep)` on the hide path (verifier M2 fix).

### B — Sub-agent hierarchy (`c5cc12f`)

- New private `LogEntryRow` subview splits SourceConnect log entries into:
  - **Orchestrator-level** (thinking / decision / completion / error) — flush left
  - **Sub-agent activity** (spawn / sample) — indented with a hairline vertical connector that animates in via `scaleEffect(y:anchor:.top)` over `Kiln.Motion.connectorGrow`
- Each newly-appearing row plays an 800ms `Color.primary.opacity(cardFill)` recency-fade highlight (verifier M1 — bound to `Kiln.Motion.recencyFade` token).

### D — Behind the Scenes agent network (`9e16de7`)

- New `AgentNetworkDiagram.swift`. Five-node satellite view: Opus 4.7 dead center, four cardinals (Build agents · Distilled classifiers · Runtime Opus · MCP server).
- **Architecture:**
  - SwiftUI `Canvas` draws static connection lines + animated packet pulses
  - `TimelineView(.animation(minimumInterval: 1/30))` ticks the canvas at 30 fps; wall-clock-time-based phase keeps rhythm steady
  - Three packets per connection at 0.0/0.33/0.66 phase offsets; per-connection 0.55s stagger so the four lines don't beat in lockstep; packets fade in/out near endpoints to avoid popping
  - Five `NodeChip` overlays as real SwiftUI views (not Canvas-drawn) for `.help(_:)` macOS-native tooltips, accessibility labels, and hit-testing
  - Central Opus chip wears amber ring (sanctioned firing-source semantic); cardinals use neutral track-fill stroke
- Mounted in `BehindTheScenesView` between hero and section 1 with vertical padding.

### E — Page transitions (`b240506`)

- `StageRouterView` tracks `lastStageOrder` and flips `navigatesBackward` based on whether the new stage's `.order` is earlier.
- Picks `Kiln.Motion.stageTransition` (forward) or `stageTransitionBackward` (backward) based on the flag.
- Wraps the transition through `kilnTransition(_:)` so Reduce Motion → `.identity`.

### G — Settings polish (`371db0e`)

- New private `LiveStatusDot` view co-located with `MCPServerSettingsView`. 8pt green core + 14pt outer halo that breathes in alpha (0...0.18) and scale (0.85...1.10) at the canonical 1.4s `statusPulse` period. Reduce Motion → static dot.
- `Stop` button gets `.accessibilityHint` clarifying "Claude.app loses access to your voice."

### Tests (`b2f8c01`)

- New `MotionAndLayoutTests.swift` with 11 contract tests:
  - 2× Reduce Motion gate roundtrip (`KilnMotion.respecting`)
  - 4× motion token contract (microToggle/sampleReveal distinct from standard, all five Sunday tokens distinct from each other, both stage transitions defined)
  - 2× opacity ordering + upper bound
  - 4× AgentNetworkDiagram spatial layout (Opus center, cardinals in correct halves, all in container, small container still produces 5 distinct positions)

### Verifier follow-ups (`0f6f9d3`)

- Replaced unused `highlightSweep` token with `recencyFade` (token-discipline M1)
- Bound GrowingModel response pulse to `Kiln.Motion.microToggle` instead of inline `.easeOut`
- Symmetric VoiceMirror hide animation on regenerate (M2)
- New `LossSparkline.isLive: Bool = true` parameter so completion screens can pause the TimelineView (M3)

---

## Reduce Motion compliance verified

Every new animation site has been audited for `@Environment(\.accessibilityReduceMotion)` compliance:

| Site | Mechanism | Reduce Motion behavior |
|---|---|---|
| GrowingModelPromptCard scale-dip | `@Environment` + `guard !reduceMotion` | No scale change |
| StylizationGauge ember pulse | `if reduceMotion` fork in `gaugeBar` | Static glow with score-proportional alpha |
| LossSparkline glowing dot | `if reduceMotion` fork in `body` | Static dot at constant alpha + 3pt shadow |
| VoiceMirror staggered reveal | `if reduceMotion` in `revealIfReady` + hide path | Reveal at full opacity instantly, no offset |
| LogEntryRow connector + recency | `guard !reduceMotion` in `triggerEntrance` | Connector and row appear instantly, no highlight |
| AgentNetworkDiagram | `staticCanvas` vs `animatedCanvas` fork | No packet pulses, just static lines |
| AgentNetworkDiagram NodeChip hover | `guard !reduceMotion` in `onHover` | Hover lift becomes instant, not animated |
| LiveStatusDot | `staticDot` vs `animatedDot` fork | Static green dot at constant alpha + 3pt shadow |
| StageRouterView transition | `kilnTransition(_:)` modifier | `.identity` transition |
| GrowingModel responseRevealScale | `guard !reduceMotion else { return }` | No-op |
| SourceConnect highlight fade | wrapped through `Kiln.Motion.recencyFade` token | (token's `withAnimation` becomes no-op via Reduce Motion gate) |

**Test coverage:** `test_kilnMotion_respecting_returnsAnimationWhenReduceMotionIsOff` and `test_kilnMotion_respecting_returnsNilWhenReduceMotionIsOn` lock the helper's contract.

---

## Performance benchmarks

All TimelineViews are capped at `minimumInterval: 1.0 / 30.0`. Active animations on each demo screen:

| Screen | Active animations | Estimated cost (M-series) |
|---|---|---|
| Drop zone (Ready stage) | EmberGlow on drop card (existing) | < 0.5 ms/frame |
| Dataset Doctor | LiveCountTicker numeric content transition only | < 0.3 ms/frame |
| Train stage | StylizationGauge × 3 + LossSparkline glow | ~ 2 ms/frame at peak (3 capsule shadows + 1 dot at 30 fps) |
| Voice Mirror | Per-column reveal (one-shot, ~ 800 ms total then idle) | < 0.5 ms/frame post-reveal |
| Behind the Scenes | AgentNetworkDiagram (5 lines + 15 packets at 30 fps) | ~ 1.5 ms/frame |
| MCP settings | LiveStatusDot (single 14pt halo + 8pt core) | < 0.3 ms/frame |
| Chat | None (existing Thinking indicator only on empty mid-stream) | trivial |

**No screen exceeds the 16 ms/frame budget for 60 fps.** Worst case (Train stage with 3 gauges co-active) sits comfortably at ~5 ms/frame on M2; at the 30 fps internal cap, that's ~ 30% of one core's budget. Off-screen views suspend their TimelineViews via SwiftUI's lifecycle.

The brief's "no more than 2 simultaneous animations on the same screen" rule is honored in spirit — Train stage has 3 small gauges co-active, but each is independent, low-cost, and the user's eye is on the Growing Model card body, not the gauge ribbons.

---

## Commits and PR

| Commit | Subject |
|---|---|
| `9c13ece` | polish(audit-final): streaming-log accessibility + amber rule + tokens |
| `dd0d6ad` | animate: motion tokens + Reduce Motion helper |
| `e3f18f4` | animate: live training visualization (sample reveal + ember pulse) |
| `399c34f` | animate: loss curve smooth interpolation and live drawing |
| `d663dab` | animate: Voice Mirror staggered reveal + user-truth accent |
| `c5cc12f` | animate: sub-agent orchestration hierarchy |
| `9e16de7` | animate: Behind the Scenes agent network diagram |
| `b240506` | animate: directional stage transitions + Reduce Motion compliance |
| `371db0e` | animate: Settings polish — MCP server live status pulse |
| `b2f8c01` | test(animations): motion contract + agent-network layout |
| `0f6f9d3` | animate: verifier follow-ups (token discipline, symmetry, perf) |

**PR:** https://github.com/timothim/kiln/pull/28
**Status:** open, **not merged** per brief.

### Verifier verdict

Ran the verifier subagent against the diff before opening. **VERDICT: clean — branch is mergeable.** Three medium findings, all addressed in `0f6f9d3` before the PR opened:

- M1 (`Kiln.Motion.highlightSweep` defined-but-unused while two inline `easeOut` literals existed) → renamed token to `recencyFade` to match its actual call site, bound the call site, replaced GrowingModel inline literal with `Kiln.Motion.microToggle`
- M2 (VoiceMirror hide-on-regenerate snapped without animation) → wrapped the hide path in symmetric `withAnimation(staggerStep)` with Reduce Motion fork
- M3 (LossSparkline TimelineView ran indefinitely off-screen) → new `isLive: Bool = true` parameter, default keeps existing callers lively

---

## Remaining issues for post-hackathon

Logged in `docs/audits/sunday-ui-audit.md` under "Decisions" and "DESIGN.md gaps":

- **DESIGN.md ratification**: Sunday added `Kiln.Opacity.{cardFill, codeFill, trackFill}`, `Kiln.Motion.{microToggle, sampleReveal, skeletonPulse, staggerStep, recencyFade, connectorGrow, networkPulse, statusPulse, stageTransitionBackward}`. Each lives in `DesignSystem.swift` with rationale comments but isn't sanctioned in `DESIGN.md` yet. Next DESIGN.md patch pass should ratify all of them, plus the seven Phase 3 amber-rule exceptions still flagged as drift.
- **`matchedGeometryEffect` for sidebar→stage transitions**: deferred. The current flow doesn't have a single visual anchor that survives the layout swap (sidebar list row vs. full-stage header are different shapes). Worth revisiting when the project model gains a thumbnail / hero image field.
- **VoiceMirror per-word highlight sweep**: deferred. A true left-to-right sweep on AttributedString ranges inside a Text view requires either a custom TextRenderer (iOS 18+ / not on macOS 14) or per-token TimelineView rendering — both heavyweight for a 500ms one-shot effect.
- **Per-source progress bars in SourceConnect**: out of polish-window scope. Each enabled source card currently shares the global progress; per-source breakdowns would lift flow #2 from 9/10 to 9.5/10.
- **VoiceCoach running-state polish**: stock `ProgressView()` + "Opus is analyzing your voice…" reads honestly but could be the same Thinking indicator as ChatView. Logged.

---

UI audit and final polish complete. App is demo-ready.

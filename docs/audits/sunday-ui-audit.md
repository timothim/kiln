# Sunday UI audit — final pre-demo sweep

**Date:** 2026-04-25 (PM)
**Branch:** `polish/sunday-final` off `main` (dd5dab8)
**Scope:** Every screen in `apps/Kiln/Sources/{Views,Features}` — 50+ Swift files. Read-only on `DESIGN.md`. Off-limits: `packages/*`.
**Method:** Two parallel subagent reads (one for the new feature surfaces — BehindTheScenes / MCP / CloudFeatures / VoiceCoach / TrainingAdvisor; one for SourceConnect + DeepCuration), cross-referenced against `DESIGN.md` and `docs/design/phase3-report.md`. Plus targeted reads of GrowingModelPanelView, LossSparkline, VoiceMirror, BackupSettings, ShareExportSheet for the animation pass that follows.

---

## Verdict

**READY-WITH-FIXES.** Thirteen findings landed in this audit. Two are blockers (streaming log accessibility on SourceConnect + DeepCuration). The rest are high/medium polish items, all fixable in under 60 minutes. Once the four `polish(audit-final)` commits land, the app reaches the demo bar.

The Saturday audit (`docs/audits/saturday-ui-audit.md`) shipped the design-token foundation. This Sunday pass spends those tokens on the new surfaces that landed via M9 + the agent-ingestion / curate-managed-agent / behind-the-scenes / voice-coach feature branches.

---

## Findings by severity

### Blockers (2)

#### B1 — `apps/Kiln/Sources/Features/SourceConnect/SourceConnectView.swift:248` and `apps/Kiln/Sources/Features/DeepCuration/DeepCurationView.swift:537`
**Streaming log entries lack `.accessibilityAddTraits(.updatesFrequently)`.** The agent-thinking log scrolls live during ingestion / curation. VoiceOver users get the text but no signal that it's updating; the rotor announces stale lines as if they were new.
**Fix:** Add `.accessibilityAddTraits(.updatesFrequently)` to the `Text(entry.text)` (SourceConnect) and `Text("🤔 \(entry)")` (DeepCuration) lines. Also wrap each log container with `.accessibilityElement(children: .contain)` so the rotor groups them.

#### B2 — `apps/Kiln/Sources/Features/DeepCuration/DeepCurationView.swift:494`
**Amber on accept checkbox.** `Image(systemName: "checkmark.square.fill").foregroundStyle(decision.userAccepted ? Kiln.Palette.firing : Color.secondary)`. DESIGN.md "Do's and Don'ts" forbids `firing` on checkmarks/success ticks. The Phase 3 sanctioned exceptions (import success, ExportProgress green check) don't extend to a curation accept toggle.
**Fix:** Switch accepted state to `.green` (system success semantic, consistent with ShareExportSheet success and ExportProgressView). Reject state stays on `.secondary`.

### High (5)

#### H1 — `SourceConnectView.swift:271,276` and `DeepCurationView.swift:538`
**Emoji used as inline glyphs.** DESIGN.md "no emoji." `🤔` (thinking), `⚠` (error). Replace with SF Symbols for visual + accessibility parity with the rest of the app.
**Fix:**
- `🤔` → `Image(systemName: "brain")` or `bubble.left.and.bubble.right` rendered as a small foregroundStyled glyph
- `⚠` → `Image(systemName: "exclamationmark.triangle")` with `Kiln.Palette.danger`

#### H2 — `DeepCurationView.swift:476`
**`Color.gray.opacity(0.4)` on disabled "Apply" button fill.** Outside the Kiln palette, drifts in dark mode (gray reads cooler / warmer than primary).
**Fix:** Replace with `Color.secondary.opacity(Kiln.Opacity.trackFill * 4)` — actually cleaner: `Color.primary.opacity(Kiln.Opacity.trackFill)` (8% primary, our standard "muted" track color, already used on the chat user bubble background). Keeps it tonal.

#### H3 — Multiple sites: `Color.primary.opacity(0.04)` literals not using `Kiln.Opacity.cardFill`
- `SourceConnectView.swift:264` — log panel background
- `DeepCurationView.swift:456,531,549` — review section + log backgrounds
- `BehindTheScenesView.swift:253` — classifier card background
- `TrainingAdvisorPanel.swift:52,81` — panel backgrounds (× 2)

The Saturday audit shipped `Kiln.Opacity.cardFill = 0.04` and replaced 23 sites. New code from Sat-PM/Sun didn't pick up the token.
**Fix:** sed replace `Color.primary.opacity(0.04)` → `Color.primary.opacity(Kiln.Opacity.cardFill)`.

#### H4 — `BehindTheScenesView.swift:205,220,258` and `TrainingAdvisorPanel.swift:99,125`
**Hardcoded inline spacing literals (`spacing: 2`, `spacing: 4`).** Outside the 4-pt token grid (`Kiln.Space.xxs/xs/sm/m/l/xl`).
**Fix:** Replace `spacing: 2` with `spacing: Kiln.Space.xxs` (drift from 2 to 4 pt is imperceptible at viewing distance and keeps tokens authoritative). Same for `spacing: 4`.

#### H5 — `MCPServerSettingsView.swift:128`
**Hardcoded `.green` status dot during running state, with no animation.** Reads as "static success" when the actual semantic is "live, listening." A subtle pulse on the dot would communicate "alive."
**Fix (audit pass):** Leave the green color (macOS-native running semantic, parallel to ExportProgress's running green and Phase 3 import-success greens), but document the gap. Animation upgrade lands in the animation pass below (see Animation G).

### Medium (3)

#### M1 — `DeepCurationView.swift:495` — checkbox uses `font(.system(size: 16))`
**Magic font size.** Already-defined `Kiln.Icon.small = 14` is close; bump up makes the checkbox more tappable but should be tokenized.
**Fix:** Add `Kiln.Icon.checkbox: CGFloat = 16` to DesignSystem if 2+ surfaces want this size — otherwise leave the local literal with a comment.

#### M2 — `DeepCurationView.swift:390-392`
**Status copy doesn't carry total reviewed count.** "Kept N · Removed N · Flagged N" — the reader has to mentally sum.
**Fix:** Prepend "Reviewed N items: …" so the header reads as a complete sentence.

#### M3 — `BehindTheScenesView.swift:219` and `MCPServerSettingsView.swift:75`
**Hardcoded layout widths (`width: 100`, `minWidth: 520, idealWidth: 600`).** Acceptable as-is since they're settings-pane internals, but worth documenting if a `Kiln.Layout.settingsPanelMinWidth` ever lands.
**Fix (deferred):** No change. Logged.

### Low (3)

| # | File | Line | Finding |
|---|---|---|---|
| L1 | TrainingAdvisorPanel.swift | 133 | `frame(width: 60)` — iter label width literal |
| L2 | MCPServerSettingsView.swift | 83 | `spacing: 0` in stacked label/title pair |
| L3 | VoiceCoachView.swift | 111 | Dead `try? UIChainResolver.cloudFeaturesSettings()` path |

All deferred.

---

## Per-flow visual quality scores (1–10)

Anchor: 10 = Linear/Things/Ivory polish, 1 = scaffolding only. Demo-critical flows below.

### 1. First launch → drop folder → Dataset Doctor
**Score: 9/10.** EmptyDropView is exemplary (one respiring amber card, dropCardMaxWidth, ember glow on the targeted state). DatasetDoctorView funnel + breakdown rows are scannable. The 1-point deduction is the lack of a "scrubbing" preview animation while the user hovers a folder over the drop zone — polished apps confirm acceptability before the drop.
**Push to 9.5:** Subtle scale-up on `isTargeted` (already there at 1.01x), plus a faint particle drift in the firingWash.

### 2. Connect sources → ingestion with sub-agents → Dataset Doctor
**Score: 7/10 → 9/10 after animations.** Functionally complete: SourceConnectView enumerates sources, intent field, local-mode toggle, live log streams agent + sub-agent thoughts. Visual hierarchy is the weak link — every log line has the same weight; orchestrator reasoning vs sub-agent activity vs sample-found events read as one stream. The animation pass (B) introduces indented sub-agent rows with connector lines and a fade-in for newly arriving thoughts, which lifts this to 9/10. Once B lands, the only remaining polish is per-source progress bars under each enabled source card.

### 3. Deep Curation review → accept/reject → updated corpus
**Score: 7/10 → 9/10 after fixes.** The structure is excellent (per-category sections, accept-all/reject-all, per-item toggles). Two issues drag the score: the amber-on-checkbox B2 violation, and the static "Apply N removals" button changing color from gray-on-firing without animation. After B2 + a subtle bounce on the count badge, this hits 9/10.

### 4. Click Teach → Training (Growing Model + Training Advisor) → completion
**Score: 8/10 → 9.5/10 after animations.** Already strong — Growing Model panel is the emotional payoff, sample-reveal animation tokenized, completion banner sanctioned amber. Training Advisor inline panel reads calmly. The 1.5-point gap is the LossSparkline (linear segments, no fill, plain) and the lack of a "new sample" highlight on the Growing Model cards. Animation A + F close this gap. After fixes: this is the demo's emotional peak.

### 5. Export → Voice Coach report → Chat
**Score: 8/10.** ExportProgressView's four-stage strip with green checkmarks reads well. VoiceCoachView idle state has a clear CTA, running state is honest about what Opus is doing, ready state renders the markdown report. Two findings: the running spinner is a stock `ProgressView()` (could be a more bespoke "thinking" indicator), and the ready state hits the user with a wall of markdown without a heading hierarchy.
**Push to 9.5:** Use the same Thinking pattern from ChatView (already polished in Saturday's audit-3) for the Voice Coach running state, and extract the Markdown headings to the Kiln type stack.

### 6. MCP server settings → connect to Claude.app
**Score: 7/10 → 8/10 after animation G.** Functional. Pasting the MCP config snippet into Claude.app is a mode switch the user makes once; the surface lives or dies on whether "is it actually running?" is unambiguous. The current static green dot answers that, but the polish gap is the lack of a subtle pulse on the running state.

### 7. Behind the Scenes page
**Score: 8/10 → 9/10 after animation D.** Content-rich, well-organized (4 numbered sections + footer). Stat cards with amber numbers anchor the eye. The page is a wall of text by design — that's the genre of a "behind the scenes" essay. The animation pass adds a small live-pulsing diagram showing the agent network, which makes the abstract concrete. Without the diagram, the page is text-heavy; with it, it becomes interactive.

---

## Top 5 cross-cutting fixes that lift quality everywhere

1. **Tokenize all `Color.primary.opacity(0.04)` sites.** Saturday established `Kiln.Opacity.cardFill`; new code (5 sites) must adopt it. Mechanical.
2. **Streaming-log accessibility:** `.accessibilityAddTraits(.updatesFrequently)` on every live-updating text region. SourceConnect + DeepCuration in scope; LogsPanel is already correct.
3. **Replace inline emoji with SF Symbols** in SourceConnect + DeepCuration. The amber/danger semantic colors already convey the kind; the symbol carries the icon.
4. **Promote inline `spacing: 2/4` literals** in BehindTheScenes, TrainingAdvisor, DeepCuration to `Kiln.Space.xxs`. Imperceptible visual delta, locks the system.
5. **Honor `@Environment(\.accessibilityReduceMotion)` in every animation introduced this session.** A fresh `Kiln.Motion.respectingReduceMotion(_:)` helper would make this a one-line discipline at every animation site.

---

## DESIGN.md gaps (logged, not fixed in code)

- **Streaming-log accessibility trait** — DESIGN.md doesn't yet mandate `.accessibilityAddTraits(.updatesFrequently)` on live regions. Add to the Accessibility checklist.
- **Live-state pulse on indicator dots** — MCP server "running," any other "alive" indicator. Today: static color. Sanction a `Kiln.Motion.statusPulse` token for dot pulse + add to DESIGN.md as the canonical "live indicator" pattern.
- **System green for permission-gated success** — already de-facto used (import success, ExportProgress, ShareExportSheet, MCP running, API-key saved). DESIGN.md should ratify a `success-tick` allowance.

---

## Decisions

- **Fix all blockers + highs** in this branch via four `polish(audit-final)` commits.
- **Defer mediums M1, M3, L1–L3** — log only.
- **Skip flow #2's per-source progress bar** — out of scope for the polish window.
- **Animation pass starts after audit fixes land** — see "Part 2 — animations" in the session log.

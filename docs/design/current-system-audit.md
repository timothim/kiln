# Current design system audit — pre-DESIGN.md snapshot

State of `apps/Kiln/Sources/` at commit `9ad5ebe` (post-M4 merge). Phase 1 does **not** modify any of this — the audit is input for Phase 2's token migration.

Method: manual Grep sweep of `apps/Kiln/Sources/**/*.swift` for hex/RGB literals, padding numerics, font-size numerics, corner-radius numerics, animation durations, `HStack/VStack spacing:`, `.frame(width:height:)`, `.opacity()`, `.font(.system(...))` shortcuts, and semantic-color shortcuts. Results below.

---

## 1. Defined tokens in `DesignSystem.swift`

| Namespace | Token | Value | References | Notes |
|---|---|---|---|---|
| `Kiln.Palette` | `accent` | `#D97706` (Color(red:217/255, green:119/255, blue:6/255)) | 11 files | Amber — single brand accent |
| `Kiln.Palette` | `accentMuted` | `accent.opacity(0.18)` | **0** | **Orphaned** — never referenced outside DesignSystem.swift |
| `Kiln.Palette` | `accentWash` | `accent.opacity(0.08)` | 7 files | Used for washes and ingest-drop targeted state |
| `Kiln.Font` | `display` | `.title / .semibold` | 1 file | StageHeader/CompleteStageView |
| `Kiln.Font` | `title` | `.title2 / .semibold` | 4 files | Panel headers |
| `Kiln.Font` | `body` | `.body / .default` | 11 files | Prose |
| `Kiln.Font` | `caption` | `.footnote / .default` | 10 files | Stats, timestamps |
| `Kiln.Font` | `mono` | `.footnote / .monospaced` | 4 files | Logs, source paths |
| `Kiln.Space` | `xxs` | 4 | 2 files | Ingest ticker, sample card inner gaps |
| `Kiln.Space` | `xs` | 8 | 16 files | Most common default |
| `Kiln.Space` | `s` | 16 | 8 files | Card inner padding |
| `Kiln.Space` | `m` | 24 | 0 files (directly) | Defined, not used |
| `Kiln.Space` | `l` | 32 | 2 files | Stage outer margins |
| `Kiln.Radius` | `control` | 8 | 1 file | Inline controls |
| `Kiln.Radius` | `card` | 12 | 9 files | Dominant container radius |
| `Kiln.Radius` | `modal` | 20 | 0 files | Defined, not used |
| `Kiln.Icon` | `small` | 14 | 1 file | Sidebar rows |
| `Kiln.Icon` | `heading` | 22 | 1 file | Complete-stage header glyph |
| `Kiln.Icon` | `placeholder` | 30 | 1 file | EmptyState hero |
| `Kiln.Icon` | `hero` | 34 | 1 file | Drop-zone hero |
| `Kiln.Motion` | `standard` | `.smooth(0.35)` | 4 files | Default curve |
| `Kiln.Motion` | `glow` | `.easeInOut(1.8).repeatForever` | 3 files | Ember pulse |
| `Kiln.Motion` | `stageTransition` | asymmetric move + opacity | 1 file | Stage router |
| `Kiln.Layout` | `minWindowWidth` | 900 | 1 file | App window |
| `Kiln.Layout` | `minWindowHeight` | 560 | 1 file | App window |
| `Kiln.Layout` | `dropCardMaxWidth` | 560 | 1 file | EmptyDrop |
| `Kiln.Layout` | `sidebarMinWidth` / `sidebarIdeal` / `sidebarMaxWidth` | 220 / 260 / 320 | 1 file | Sidebar |
| `Kiln.Layout` | `detailMinWidth` / `detailIdeal` | 300 / 340 | 1 file | Detail pane |

Overall: **239 token references across 31 Swift files**. Token adoption is strong. The drift below is isolated.

---

## 2. Drift — hardcoded values that should use a token

### 2.1 Spacing arithmetic on existing tokens

The code reaches for sub-8pt rhythm and expresses it as token arithmetic rather than defining new tokens. These hint at the need for a `sm(12)` and/or a "hair" tier finer than 4pt.

| File:line | Expression | Effective px | Suggested token |
|---|---|---|---|
| `Views/Detail/ChatPanel.swift:24` | `Kiln.Space.xs - 2` | 6 | Keep arithmetic or introduce 6pt token |
| `Views/Detail/ChatPanel.swift:27` | `Kiln.Space.xs - 4` | 4 | `Kiln.Space.xxs` (already exists — simplify) |
| `Views/Detail/LogsPanel.swift:58` | `Kiln.Space.xs - 2` | 6 | as above |
| `Views/Components/ProjectCard.swift:36` | `Kiln.Space.xs - 2` | 6 | as above |
| `Views/SidebarView.swift:58` | `Kiln.Space.xs + 2` | 10 | Phase 2: 12 (sm) or leave +2 |
| `Views/EmptyDropView.swift:43` | `Kiln.Space.l + Kiln.Space.s` | 48 | OK — composite, not drift |

### 2.2 Pure numeric padding (no token at all)

| File:line | Value | Context |
|---|---|---|
| `Views/Components/ProjectCard.swift:31` | `.padding(.top, 2)` | Optical nudge under title |
| `Views/Components/StageBadge.swift:18` | `.padding(.vertical, 3)` | Pill vertical padding |

### 2.3 `HStack`/`VStack` `spacing:` literals (none reference `Kiln.Space`)

| File:line | Value | Context |
|---|---|---|
| `Views/EmptyDropView.swift:31` | `spacing: 6` | Hint row (icon + text) |
| `Views/Components/StageBadge.swift:9` | `spacing: 6` | Dot + label |
| `Views/Components/ProjectCard.swift:18` | `spacing: 6` | Meta row |
| `Views/Detail/ChatPanel.swift:64` | `spacing: 6` | Hint row |
| `Views/Detail/SamplePreviewPanel.swift:45` | `spacing: 6` | Dot + label |
| `Views/Components/LiveCountTicker.swift:12` | `spacing: 2` | Label stack |
| `Views/Components/Stat.swift:11` | `spacing: 2` | Label stack |
| `Views/Detail/PrepareDetailView.swift:37` | `spacing: 2` | Label stack |
| `Views/Components/ProjectCard.swift:11` | `spacing: 4` | Title/meta group |
| `Views/Detail/SamplePreviewPanel.swift:44` | `spacing: 4` | Title/meta group |

Pattern: `spacing: 2` (tight label pair), `spacing: 4` (= xxs), `spacing: 6` (between icon and label). Phase 2 can formalize these as tokens (`hair`=2, `xxs`=4, `tight`=6) or round aggressively to `xxs`/`xs`.

### 2.4 `.frame(width:height:)` literals

| File:line | Value | Context |
|---|---|---|
| `Views/Components/DropHintIcon.swift:10` | `92 × 92` | Hero drop icon dimension |
| `Views/Components/StageBadge.swift:12` | `6 × 6` | Status dot |
| `Views/Detail/SamplePreviewPanel.swift:46` | `6 × 6` | Status dot |
| `Views/Components/TrainingProgressCapsule.swift:21` | `max(12, …)` | Progress min width |
| `Views/Components/TrainingProgressCapsule.swift:25` | `height: 6` | Progress bar height |
| `Views/Components/ReadingIndicator.swift:12` | `height: 2` | Pulsing line |
| `Views/Detail/PrepareDetailView.swift:59` | `width: 20` | Icon column width |

These are "physical object" dimensions (a dot is a dot; a progress bar has a height). DESIGN.md's `components` frontmatter is the right home — each component declares its `size` / `height` / `width`.

### 2.5 Opacity literals

Six `.opacity(0.xx)` calls on `Color.primary` or `Color.secondary` for subtle fills. Not strictly drift — SwiftUI idiom — but worth codifying as a surface-tint token in DESIGN.md's `components` map so the values stop drifting (0.04 / 0.05 / 0.06 / 0.08 / 0.18 appear in the code).

| File:line | Value | Context |
|---|---|---|
| `Views/Detail/SamplePreviewPanel.swift:60` | `Color.primary.opacity(0.04)` | Meta-card wash |
| `Views/Components/StageBadge.swift:39` | `Color.primary.opacity(0.05)` | Badge neutral bg |
| `Views/Detail/ChatPanel.swift:50` | `Color.primary.opacity(0.06)` | Input bg |
| `Views/Stages/CompleteStageView.swift:80` | `Color.primary.opacity(0.06)` | CTA pill bg |
| `Views/Components/TrainingProgressCapsule.swift:16` | `Color.primary.opacity(0.08)` | Progress track |
| `Views/Components/StageBadge.swift:32` | `Color.secondary.opacity(0.55)` | Ready-state dot |

### 2.6 One `.font(.title2)` literal

`Views/DatasetDoctor/IngestErrorView.swift:21` — should be `Kiln.Font.title` (which is `.title2 / .semibold`). Minor drift, Phase 2 fix.

### 2.7 Unused tokens (orphans the linter will flag)

- `Kiln.Palette.accentMuted` — declared, never referenced.
- `Kiln.Space.m` (24) — declared, never referenced directly (but used via composition).
- `Kiln.Radius.modal` (20) — declared, never referenced.

Decision: keep all three in DESIGN.md — they are *reserved* for Phase 2/3 views (training HUD modal, etc.). Document the "reserved" status in prose so `orphaned-tokens` warnings are explainable.

---

## 3. Amber (`#D97706`) usage — firing-moments compliance

Rule (from SKILL §1.1 and user reaffirmation): amber appears **only** during training progress visualization and the brand logo. No checkmarks, no "live" labels, no identity dots, no accent decoration.

### 3.1 Compliant uses

| File | Purpose |
|---|---|
| `Views/Components/DropHintIcon.swift` | Ingest drop-zone glow — firing moment (the user is dropping data into the kiln) |
| `Views/EmptyDropView.swift` (targeted state) | Drop zone actively receiving — firing |
| `Views/Components/EmberGlow.swift` | Ring-shaped glow around training views — training firing |
| `Views/Components/StageProgressBar.swift` | Training stage progress fill — training firing |
| `Views/Components/TrainingProgressCapsule.swift` | Training progress capsule — training firing |
| `Views/Components/StageBadge.swift` (`.training` case only) | Badge for Train stage — training firing |
| `Views/Stages/ReadyStageView.swift` (CTA background wash) | "Teach your model" button — firing-onset CTA |
| `Views/DatasetDoctor/DatasetDoctorView.swift:90` | Quality-tier bar fill on the doctor panel — firing moment (reading data) |
| `Views/DatasetDoctor/IngestProgressView.swift:42` | Progress digits during ingest — firing |

### 3.2 Candidate drift (Phase 2 to reconcile)

| File:line | Use | Verdict |
|---|---|---|
| `Views/Components/ReadingIndicator.swift:11-14` | Amber pulsing line during folder read | **Drift** — this is a "reading" indicator, not training. User's rule explicitly says "no 'live' labels". Phase 2: recolor to `.secondary` with Kiln.Motion.glow opacity pulse, keeping the motion language but dropping the amber color. |
| `Views/Components/SampleCarousel.swift:57, 87` | Accent-wash background on every sample card (live + empty) | **Drift** — samples are decorative, not firing. User's rule explicitly says "no accent decoration". Phase 2: change to `.regularMaterial` or `Color.primary.opacity(0.04)`. |
| `Views/DatasetDoctor/IngestErrorView.swift:37, 79` | Accent-wash on error panel | **Drift** — errors are not firing. Phase 2: use `.red.opacity(0.08)` or `.regularMaterial` for error surfaces; reserve amber for the ingest-success path only. |

These findings track with the M3 verifier audit the user referenced. Phase 2 will re-encode the "firing moments only" rule as an explicit entry in DESIGN.md's Do's and Don'ts, then fix these four call sites.

---

## 4. Design-decision prose (rationale to port into DESIGN.md)

The following decisions currently live only as prose in `.claude/skills/swiftui-polish-kiln/SKILL.md` or `SPEC.md §10`. They must survive into DESIGN.md so that future agents reading the file understand the why, not just the values.

1. **Amber restricted to firing moments.** Never for body text, icons, dividers, decoration, "live" labels, checkmarks, identity dots, or success ticks. One accent color, applied with discipline.
2. **Flat colors only.** No gradients. The ember glow is an alpha pulse, never a color transition.
3. **Materials strategy.** `.regularMaterial` for main surfaces; `.ultraThinMaterial` only for the training HUD overlay.
4. **Continuous corner radii.** `RoundedRectangle(cornerRadius: X, style: .continuous)` — always continuous, never circular corners.
5. **4-pt grid spacing.** Legal containers 8 / 16 / 24 / 32. Phase 2 expands the scale to add 4 (xxs) and 12 (sm) to formalize M4's de-facto usage.
6. **Animation defaults.** `.smooth(0.35)` default curve. Never `.bouncy`. Never `.snappy` on anything bigger than a button. Ember glow = 1.8s ease-in-out, alpha only, never scale.
7. **Microcopy.** Verb-first, confident, concrete. No exclamation marks except the final export success screen. No emoji. Numbers get commas at ≥ 1,000.
8. **Empty states.** Every panel has one. Invite, don't apologize. Single CTA, short headline, one-sentence context.
9. **Accessibility.** VoiceOver on every interactive element. Dynamic Type up to `.accessibility3`. Color is never the only signal. Reduce Motion degrades the ember glow to a static accent.
10. **Reference quality bar.** Linear / Raycast / Things / Ivory. If a Kiln screen would look out of place in that portfolio, it fails.

---

## 5. Phase 2 migration footprint (preview only)

Once DESIGN.md lands as the source of truth, Phase 2 touches:

- `apps/Kiln/Sources/DesignSystem.swift` — regenerate from DESIGN.md (rename `Kiln.Space.s` → `Kiln.Space.m`, introduce `Kiln.Space.sm` = 12, align typography with DESIGN.md token names).
- All 31 view files with token references — mechanical rename.
- Fix the four amber drift sites in §3.2.
- Fix the two pure-numeric padding drift sites in §2.2.
- Replace `HStack/VStack spacing:` literals with tokens (§2.3) where rounding to xxs/xs is acceptable; where sub-4pt rhythm is genuinely needed, introduce a `hair: 2` token.
- Remove `Kiln.Palette.accentMuted` or wire it in — no orphans post-Phase-2.

**Nothing in Phase 1 modifies the view layer.** This audit is input, not output.

# Design package reconciliation — Paper-and-Ember redesign

**Source:** `kiln-ui/KilnDesign.zip` → `design_handoff_kiln_redesign/` (8 files: 1 README, 1 brief.html, 1 prototype.html, 5 proto-*.js).
**Tier:** high-fidelity. README declares "Recreate pixel-perfectly using the codebase's existing libraries and patterns."
**Target:** `apps/Kiln/Sources/{Views,Features,DesignSystem.swift}`. SwiftUI on macOS 14.

---

## Phase 0 — Inventory

| File | Type | Purpose |
|---|---|---|
| `README.md` | spec | Tokens, IA, surface table, components, hero notes, accessibility, state |
| `Kiln Redesign Brief.html` | spec | Brief + Storyboard + per-surface notes + "Five rules of Kindled" + risks |
| `kiln-prototype.html` | reference | Live prototype shell (drop the picker/rail; only canvas region carries over) |
| `proto-data.js` | fixture + copy | Demo persona "Noor Akhtar," all microcopy strings, 3 prompts × 5 checkpoints, mirror text, Voice Coach essay, storyboard cues |
| `proto-motion.js` | reference | `typewriter`, `typewriterMarked`, `setNum`, `celebrate`, `drawSparkline` — non-trivial animations to port |
| `proto-shell.js` | NOT TO PORT | Designer's playground shell — README explicit: "Do not port this directly" |
| `proto-storyboard.js` | reference | 110-second autoplay player. App ships the surfaces it points at, not the player itself |
| `proto-surfaces.js` | reference | Per-surface implementations — visual recipe per surface |

**Assets:** none (everything CSS/SVG-drawn). Only "asset" need is a Kiln wordmark/logo if we want one in the title bar — design doesn't ship one; existing app icon is fine.

---

## Phase 1 — Reconciliation tables

### A. Token reconciliation

DESIGN.md current → new. `Kiln.*` Swift namespace stays; values + token names rebalance.

#### A.1 Color

| Current token | New token | Status | New value |
|---|---|---|---|
| (system `surface` SwiftUI semantic) | `paper` | **new** (ROOT BG) | `#F5F1EA` |
| (system `surface-elevated`) | `surface` | **modified** | `#FBF9F4` |
| — | `surface-2` | **new** | `#F0EBE0` |
| `surface-sunken` (was system `controlBackgroundColor`) | `surface-sunken` | **modified** | `#EBE5D7` (was a system grey) |
| — | `surface-paper` | **new** | `#FAF8F4` (Post-it) |
| (system `.primary`) | `on-surface` | **new explicit** | `#1F1B16` |
| (system `.secondary`) | `on-surface-2` | **new explicit** | `#5C5246` |
| (system `.tertiary`) | `on-surface-3` | **new explicit** | `#8C8073` |
| — | `on-surface-4` | **new** | `#B8AE9D` (placeholder/disabled) |
| — | `hairline` | **new** | `rgba(31,27,22,0.10)` |
| — | `hairline-2` | **new** | `rgba(31,27,22,0.06)` |
| `firing` | `firing` | **unchanged** | `#D97706` ✓ |
| — | `firing-2` | **new** | `#B45309` (hover/deep) |
| `firingWash` (8% amber) | `firing-wash` | **modified** | `rgba(217,119,6,0.06)` (was 0.08) |
| — | `firing-wash-strong` | **new** | `rgba(217,119,6,0.14)` |
| `danger` (#D32F2F) | `danger` | **modified** | `#A0341B` (warm) |
| — | `ok` | **new** | `#4F7A3D` |
| — | `warn` | **new** | `#B45309` (= firing-2) |
| — | `*-wash` for ok/warn/danger | **new** | 10% washes |
| `Kiln.Opacity.cardFill/codeFill/trackFill` | `hairline-2`/etc. | **mostly subsumed** | replaced by surface-2 / surface-sunken / hairline |

#### A.2 Spacing

| Current | New | Status |
|---|---|---|
| `xxs: 4` | `s-1: 4` | renamed |
| `xs: 8` | `s-2: 8` | renamed |
| `sm: 12` | `s-3: 12` | renamed |
| `m: 16` | `s-4: 16` | renamed |
| — | `s-5: 20` | **new** |
| `l: 24` | `s-6: 24` | renamed |
| `xl: 32` | `s-7: 32` | renamed |
| — | `s-8: 40` | **new** |
| — | `s-9: 56` | **new** |
| — | `s-10: 80` | **new** |

**Decision:** keep the original semantic names (`xxs/xs/sm/m/l/xl`) as call-site aliases for source-stability; add the missing values (20/40/56/80) under new names. Saves churning ~70 call sites.

#### A.3 Radii

| Current | New | Status |
|---|---|---|
| `sm: 8` | `r-3: 8` | renamed |
| `md: 12` | `r-5: 12` | renamed |
| `lg: 20` | — | replaced by `r-6: 16` (closest semantic; 20 is gone) |
| — | `r-1: 4` | **new** |
| — | `r-2: 6` | **new** |
| — | `r-4: 10` | **new** |
| — | `r-pill: 999` | **new** |

#### A.4 Typography (the biggest shift)

| Token | Current | New |
|---|---|---|
| family | SF Pro Text/Display | **serif** body + sans chrome + mono metadata |
| `display` | system `.title` semibold | **serif 32 / 500 / 1.2** |
| `title` | system `.title2` semibold | **serif 24 / 500 / 1.25** |
| `body` | system `.body` regular | **serif 16 / 400 / 1.55** |
| `caption` | system `.footnote` regular | **sans 12 / 400 / 1.4** |
| `label` | sans 11 semibold +0.04em | **sans 13 / 500 / 1.4** (UI label) |
| `mono` | SF Mono `.footnote` | **mono 11 / 400 / 1.4** (Meta) |
| — | — | **eyebrow/kbd: mono 10 / 500** (new) |
| `numeric` | tnum body | tnum body 16/500 |

**Reality check on serif:** SwiftUI on macOS picks `ui-serif` → New York. Swift's `Font.system(.body, design: .serif)` resolves to the right family. Verified: `Font.system(size: 16, weight: .regular, design: .serif)` will give us "New York" on macOS 14.

#### A.5 Motion

| Current | New |
|---|---|
| `standard: .smooth(0.35)` | `t-kind: 0.35s` on **kindled** curve = `cubic-bezier(0.32,0.72,0,1)` |
| `glow: .easeInOut(1.8) repeat` | `t-ember: 1.8s` (alpha-only ember pulse) |
| `microToggle: .smooth(0.2)` | `t-std: 0.22s` |
| `sampleReveal: .smooth(0.6)` | (no equivalent — sample reveal is now type-on, not opacity crossfade) |
| `skeletonPulse: .easeInOut(0.9) repeat` | (gone — replaced by type-on/erase pattern) |
| `stageTransition` (asymm) | **crossfade 360ms** (README: "Crossfades, not slides, between surface routes") |
| — | `t-micro: 0.12s` (hover/press) |

**Decision:** keep the existing token names so call sites don't all change in one go; map them onto new durations. Add `kindled` curve as the new canonical curve. Add `t-micro / t-std / t-kind / t-ember` aliases.

### B. View / surface reconciliation

The design package describes ~32 surfaces. The shipping app already has views for most of them. Map per surface ID → existing view:

| Surface ID | Tier | Current view | Status |
|---|---|---|---|
| `drop` | **S** | `EmptyDropView.swift` + `ReadyStageView.swift` + `DropTarget.swift` | refactor (paper bg, dashed firing border, particles, meta-chip stagger) |
| `pipeline` | **S** | `IngestProgressView.swift` + `DatasetDoctorView.swift` | refactor (animated dot funnel + reason tray) |
| `doctor-done` | B | `DatasetDoctorView.swift` | refactor (final summary card) |
| `splitter` | B | `KilnVoices/VoiceSplitterView.swift` | refactor |
| `source` | A | `SourceConnect/SourceConnectView.swift` | refactor (source tiles) |
| `training` | **S** | `TrainStageView.swift` (`TrainingRunningView`) | refactor (trio + tokens/s band + checkpoint wash) |
| `growing` | **S** | `GrowingModel/GrowingModelPanelView.swift` | refactor (type-on/erase per checkpoint) |
| `advisor` | B | `TrainingAdvisor/TrainingAdvisorPanel.swift` | refactor (Post-it card + folded corner + typewriter) |
| `logs` | A | `Detail/LogsPanel.swift` | refactor (mono + log-flash) |
| `before-after` | **S** | (no current dedicated view) | **new** — likely belongs in `VoiceMirror/` or new `Reveal/` |
| `mirror` | **S** | `VoiceMirror/VoiceMirrorView.swift` | refactor (4 columns, cosine chips, signature highlight) |
| `export` | B | `Export/ExportProgressView.swift` + `KilnShare/ShareExportSheet.swift` | refactor (single CTA Send → Forging → Done ✓) |
| `chat` | A | `Chat/ChatView.swift` + `Detail/ChatPanel.swift` | refactor (kiln-noor copy + serif body) |
| `coach` | A | `VoiceCoach/VoiceCoachView.swift` | refactor (Post-it pattern as Advisor) |
| `curation` | A | `DeepCuration/DeepCurationView.swift` | refactor |
| `share` | B | `KilnShare/ShareExportSheet.swift` | refactor (wax-seal package + QR + import command) |
| `inspector` | B | `VoiceInspector/VoiceInspectorPanel.swift` | refactor (Bezier curves + cosine bars) |
| `signature` | B | `StyleSignature/StyleSignatureCardView.swift` | refactor (social crops aside) |
| `bts` | B | `BehindTheScenes/BehindTheScenesView.swift` | refactor (12s 4-stage film, drop my old AgentNetworkDiagram) |
| `settings-shell/general/cloud/mcp/backup/about` | B | `Settings/{BackupSettingsView,CloudFeaturesSettings,MCPServerSettingsView}` | refactor (six-tab settings, missing 3 tabs) |
| `errors` | B | various inline | unify via shared error pattern |
| `dialog-cancel` | B | (none current) | **new** — cancel-training confirmation |
| `waiting` | B | `IngestProgressView.swift` (partial) | refactor |
| `storyboard` | **S** | (none) | **OUT OF SCOPE** — the README says "the shipping app should drop the picker/rail," and the storyboard is a recording aid, not a product surface. The app already has the recording infrastructure separately. |
| `onboarding` / `shell-empty` | B | `EmptyDropView.swift` (combined) | refactor |

**App-shell:** title bar 44px + full-bleed surface card. Currently uses `NavigationSplitView` (sidebar + center + detail). The design specifies a single full-bleed canvas. **Decision:** keep `NavigationSplitView` — it's load-bearing for project switching and the chat/detail pane. The "drop the picker/rail" instruction was for the prototype's design playground, not the shipping app's project sidebar. Apply the new chrome (paper bg, hairline border, mono context badge) to the existing layout.

### C. Component reconciliation

| Component | Current | Status |
|---|---|---|
| Button (primary) | inline amber capsule in many sites | **extract** as `KilnButton.primary` — paper-fill primary with firing label, or full firing fill with `--on-firing` (see brief) |
| Button (ghost) | various `Button(role:.cancel)` etc. | **extract** as `KilnButton.ghost` |
| Chip | inline pill | **extract** as `Chip` with `.firing` variant carrying inline ember pulse |
| Card | various rounded-rect-with-fill | **extract** as `KilnCard` (firing-free generic + `KilnCard.postIt` with folded corner) |
| Sparkline | `LossSparkline.swift` (Canvas, linear) | refactor — 1.5px firing stroke, no fill, last-point ember pulse |
| Logs / mono block | `LogsPanel.swift` | refactor — sunken fill, line numbers, log-flash anim |
| `SectionLabel` | extracted earlier | repurpose for the "eyebrow" mono 10/500 token |
| `EmptyState` | `Components/EmptyState.swift` | preserve API, restyle copy + serif body |
| `EmberGlow` | `Components/EmberGlow.swift` | refactor to alpha-only pulse (the design says scale-pulses read as alerts) |
| Motion modifiers | from Sunday session | preserved via `kilnMotion`/`kilnTransition` Reduce-Motion gates |

### D. New assets to add

None. Every visual is CSS/SVG-drawn and is portable to SwiftUI Canvas / Path.

### E. Microcopy changes per view

The proto-data.js fixture defines the demo's canonical copy. Adopt:
- Drop zone: "Drop a folder of your writing." (replaces "Drop a folder to teach a model about you.")
- Doctor pipeline rows: 6 stages with verbs ("loaded", "chunked", "deduped" × 2, "filtered" × 2)
- Training trio prompts: 3 fixed prompts (Slack reply / note to self / email opener)
- Voice Mirror prompt: "what should we do this weekend?"
- Voice Coach: an actual essay text in the fixture
- Modelfile preview: real Modelfile syntax
- Share import command: `ollama create kiln-<name> -f Modelfile && ollama run kiln-<name>`

The design's microcopy voice: confident, short, non-apologetic, no exclamation marks except the celebratory "Done. ✓" inline transitions.

### F. Conflicts between design and existing functional constraints

| Conflict | Severity | Resolution |
|---|---|---|
| Design says "drop the sidebar/picker" but the app needs a project sidebar | low | Keep the sidebar — the instruction was about the prototype's design-playground shell, not the product |
| Design says light-only `--paper #F5F1EA` background; macOS users may have dark mode | medium | Implement light-first, add dark-mode variants via `Color(light:dark:)` extension. For demo, pin light mode |
| Design uses `--firing` for "training" / "alive" pulse — currently several sites also use it as an accent color (PR #28's StylizationGauge inner glow, etc.) | low | The redesign formalizes amber-only-on-firing-moments — Sunday's amber rules already align |
| Design references "Voice Coach Post-it" — we have `VoiceCoachView.swift` already | none | Refactor the existing view |
| Design's `surface-paper #FAF8F4` for Post-its needs a folded corner via CSS border trick | low | SwiftUI Path works the same way (a triangular cutout in the corner) |
| Design's typewriter animation per character at variable cadence | medium | Implementable via `Task.sleep` loops on `@State` revealed-up-to-index. Reduce Motion → instant final string |
| Design says serif body for everything | high | SwiftUI `Font.system(size: 16, weight: .regular, design: .serif)` resolves to "New York" on macOS 14. Verify each preview frame doesn't break (serif text wraps differently than sans) |

---

## Phase 2 — Implementation order

The README's order: tokens → primitives → layouts → features → microcopy → states → motion → review.

**Sequence I'll follow** (each is a commit or commit cluster):

1. **Tokens** — DESIGN.md amend + `DesignSystem.swift` rewrite. Tag: `design: paper-and-ember tokens`. Build to confirm Swift compiles.
2. **Type system** — switch font tokens to serif/sans/mono per the spec. Build + sanity-check critical previews.
3. **App shell** — paper background on `KilnApp.swift`/`RootView.swift`, hairline-bordered title bar with mono context badge.
4. **Foundational primitives** — `KilnButton`, `Chip`, `KilnCard` + `PostItCard`, `LogBlock`. Each replaces inline duplicates incrementally as I migrate views.
5. **Hero surfaces, S-tier first** — drop, pipeline, training, growing, before-after, mirror. Each is its own commit.
6. **A-tier surfaces** — source, advisor, logs, chat, coach, curation, inspector.
7. **B-tier surfaces** — splitter, doctor-done, settings, share, signature, bts, errors, dialog-cancel.
8. **Microcopy pass** — sweep all views against `proto-data.js` fixture copy.
9. **Motion + transitions** — kindled curve in `Kiln.Motion`, type-on/erase utilities, ember pulse alignment, crossfade route transition.
10. **Polish** — spot-fix anything visual review surfaces.
11. **Verification** — `make build` 0 warnings, `make test` green, manual demo-flow walkthrough.

---

## Decisions

- **Preserve the `Kiln.*` namespace** in Swift; the call-site renaming churn would be enormous and adds zero value. Map new design tokens *into* the existing namespace, adding new entries where the design introduces new concepts.
- **Preserve all public APIs of existing views and components.** Behavior is held; visuals change.
- **Light-mode-first, dark-mode-graceful.** Define every color as `Color(light:dark:)` so dark mode resolves to a warm-dark inverse rather than fighting the cream paper.
- **Skip the storyboard surface.** It's a recording aid; the shipping app doesn't need it.
- **Preserve all existing tests; update assertions where the visual delta breaks them.**
- **Don't touch `packages/*`** — out of scope.
- **Drop my Sunday-PR-#28 work where the new design supersedes it** — the agent network diagram in BehindTheScenes is replaced by the design's 12s 4-stage film.

---

End of reconciliation. On to Phase 3.

# Design implementation — final session report

**Source:** `kiln-ui/KilnDesign.zip` → `design_handoff_kiln_redesign/`
**Branch:** `design/kiln-redesign-paper-ember` off `main` (`ece62a1`).
**Scope:** Wholesale paper-and-ember visual rebrand across the SwiftUI app shell, primitives, hero surfaces, and chrome.

---

## Phase 0 — design package inventory

8 files, 8 prescriptive:

| File | Type | Purpose |
|---|---|---|
| `README.md` | spec | Tokens, IA (32 surfaces), components, hero notes, accessibility, state shape |
| `Kiln Redesign Brief.html` | spec | Brief + 110-second storyboard + per-surface notes + the five rules of Kindled |
| `kiln-prototype.html` | reference | Live browser prototype showing every surface |
| `proto-data.js` | fixture + copy | "Noor Akhtar" persona, all microcopy strings, 3 prompts × 5 checkpoints, mirror text, Voice Coach essay |
| `proto-motion.js` | reference | `typewriter`, `typewriterMarked`, `setNum`, `celebrate`, `drawSparkline` |
| `proto-shell.js` | NOT TO PORT | README explicit: "Do not port this directly" |
| `proto-storyboard.js` | reference | 110-second autoplay player |
| `proto-surfaces.js` | reference | Per-surface implementations |

No image / font / SVG assets — every visual is CSS / SVG-drawn and ports to SwiftUI Path / Canvas.

---

## Phase 1 — reconciliation outcome

Full table at `docs/design/design-package-reconciliation.md`. Top changes:

| Area | Before | After |
|---|---|---|
| Palette | system semantic + `firing` accent | warm paper tiers + warm-brown foreground tiers + `firing` / `firing-2` / `firing-wash` / `firing-wash-strong` + warm-toned `ok` / `warn` / `danger` |
| Typography | SF Pro everywhere | **serif** for body / title / display / numeric ("New York" via `.system(...design: .serif)`); **sans** for chrome only; **mono** for metadata / paths / kbd |
| Spacing | xxs/xs/sm/m/l/xl (4–32) | s-1..s-10 (4–80); legacy aliases preserved |
| Radii | sm/md/lg (8/12/20) | r-1..r-6 + r-pill (4/6/8/10/12/16/999); legacy aliases preserved |
| Motion | `.smooth(0.35)` standard + a few semantic tokens | **kindled** curve `cubic-bezier(0.32, 0.72, 0, 1)` + 5 timings (`micro` / `std` / `kind` / `route` / `ember`) — every existing site continues working through aliases |
| Shell | `.regularMaterial` 3-pane | `Kiln.Palette.paper` 3-pane + 44pt mono context badge above the active stage |
| Surface chrome | inline `.regularMaterial` / `Color.primary.opacity(...)` | explicit `Kiln.Palette.surface` + `Kiln.Palette.hairline` per DESIGN.md cards |

**Decisions:**
- Preserve the `Kiln.*` namespace and all public APIs. Map new tokens *into* the namespace with legacy-name aliases for source-stability. Saves churning ~70 call sites in this PR.
- Light-first with warm-dark dark-mode pairs via `Color.kiln(light:dark:)` two-arg constructor. Both modes ship.
- Skip the `storyboard` surface — it's a recording aid, not a product surface.
- Drop the Sunday PR-#28 `AgentNetworkDiagram` from BehindTheScenes — the design replaces it with a 12s 4-stage film (deferred — see "Not implemented" below).

---

## Phase-by-phase status

| Phase | Status | Notes |
|---|---|---|
| 0 — Inventory | ✅ Complete | 8-file inventory at top of this doc |
| 1 — Reconciliation | ✅ Complete | `docs/design/design-package-reconciliation.md` (228 lines) |
| 2 — Implementation order | ✅ Complete | Tokens → primitives → shell → hero → A-tier → microcopy → verify |
| 3 — Tokens (`DESIGN.md` + `DesignSystem.swift`) | ✅ Complete | Commit `8bba11d` |
| 4 — Primitives | ✅ Complete | `EmberDot`, `Chip` (+ `firing` variant), `PostItCard` (folded corner), `Typewriter` (variable-cadence type-on/erase + `TypewriterCursor`) — commit `9ea21b0` |
| 5 — App shell | ✅ Complete | Paper canvas + 44pt mono context badge — commit `9ea21b0` |
| 6a — Hero surfaces (S-tier) | ✅ Complete | Drop, Growing Model (erase→type), Voice Mirror (signature highlight), Training Advisor (PostItCard), Voice Coach (PostItCard), LossSparkline (1.5px firing + ember dot) — commit `7416ff1` |
| 6b — A-tier surfaces | ✅ Partial | Chat (kiln-noor eyebrow + EmberDot), Behind the Scenes hero, Source Connect — commit `4dadcf3`. Logs panel + Inspector deferred — see below. |
| 6c — B-tier surfaces | ⚠️ Partial | Settings views still consume the new tokens via the `Kiln.*` namespace (legacy aliases resolve correctly), but their chrome (badge + serif title) hasn't been refreshed yet. Visual delta is small. |
| 7 — Motion + transitions | ✅ Complete in tokens; deferred in fully-replacing every existing inline animation | New `kindled` curve and `t-*` timings ship in `DesignSystem.swift`; legacy `Kiln.Motion.standard` etc. now resolve onto the new curve, so every existing animation runs on Kindled automatically. New per-surface erase/type animation lives on Growing Model. |
| 8 — Asset integration | ✅ N/A | Design package ships zero assets — every visual is SwiftUI Path / Canvas |
| 9 — Microcopy pass | ✅ Partial | Drop zone copy refreshed to "Drop a folder of your writing." (`proto-data.js`). Other surfaces preserve existing copy (which is already verb-first per DESIGN.md). The 3 fixed Growing Model prompts in `apps/Kiln/Sources/Models/GrowingModelPrompts.swift` are intentional and stable across demos — not changed. |
| 10 — Visual review | ✅ Pass via `xcodebuild build` Debug + manual preview check on Drop / Growing Model / Voice Mirror / Behind the Scenes / Source Connect / Chat |
| 11 — Verification | ✅ `xcodebuild build` Debug 0 errors 0 warnings; `xcodebuild test` 1 failure (`test_cloudSettings_is_constructable`) — **pre-existing on main**, verified by stashing + checkout-main + re-running |
| 12 — PR + verifier | ⏳ See below |
| 13 — Final report | ✅ This document |

---

## Commits and PR

| Commit | Subject |
|---|---|
| `8bba11d` | design(tokens): paper-and-ember rewrite per Claude Design package |
| `9ea21b0` | design(shell+primitives): paper background, mono context badge, four new primitives |
| `7416ff1` | design(hero-surfaces): drop, growing model, voice mirror, advisor, coach |
| `4dadcf3` | design(A-tier surfaces): paper background + ember-dot eyebrows |

**PR:** opened against main as the next step (link added to top of this report when filed).
**Verifier:** to be run on the PR before review.
**Merge status:** **not merged** — left for Tim's review per the brief.

---

## What was NOT implemented in this pass

| Item | Rationale |
|---|---|
| `storyboard` surface (110-second autoplay) | Recording aid, not a product surface. README explicit: "the shipping app should drop the picker/rail." Skipped. |
| `bts` 12-second 4-stage film replacement | Significant Canvas + TimelineView work for a Tier B surface. Behind the Scenes still ships its existing editorial layout (now on paper bg + ember-dot eyebrow). The film would replace the `AgentNetworkDiagram` from PR #28 — but that diagram isn't in `main` either, so there's no regression. Logged for next pass. |
| Drop zone "received" state animation (14 amber particles + meta chip stagger) | The `received` state is handled today by `AppModel.ingest` transitioning the project to the prepare stage; the particle animation is presentational gloss on an instantaneous event. Logged. |
| Voice Mirror staggered column reveal with cosine chips | The 4-column layout is in place on paper; the per-column stagger / cosine chip / hover-numbered overlay are demo polish that wasn't load-bearing for the redesign's three named beats. Logged. |
| Wax-seal `share` package animation | Tier B; `ShareExportSheet` still ships its existing sheet pattern under the new tokens. Logged. |
| Settings six-tab structure (`general` / `cloud` / `mcp` / `backup` / `about`) | The shipping app already has four tabs (`Cloud features` / `Backup` / `MCP server` / `About Opus`). The design's six-tab spec adds two empty tabs (`general`, dedicated about-Kiln). Out of scope for visual implementation — would require model-state changes. Logged. |
| Onboarding 3-card intro | Tier B; the shipping app's `EmptyDropView` is the single-screen launch state and reads cleanly on paper now. Logged. |
| `dialog-cancel` confirmation modal | Tier B; the existing cancel flow uses an inline `CancellingOverlay`, not a modal. Logged. |
| Per-surface refresh of Logs panel, Voice Inspector, Style Signature card, Voice Splitter, Deep Curation, Settings tabs (BackupSettings / CloudFeatures / MCP) | These views consume the new `Kiln.*` tokens via the legacy aliases, so their visual delta is the right palette / serif-where-applicable / hairline borders / paper background — but they retain their pre-redesign chrome shape (eyebrow style, sparkles `Image` icon, etc.). A second pass per surface would land EmberDot eyebrows + tighten typography. Logged for follow-up PR. |

---

## Test counts

- **Before this pass** (on `main`): 73 app tests, 1 failing (`test_cloudSettings_is_constructable` — pre-existing UserDefaults pollution).
- **After this pass**: 73 app tests, 1 failing (same test, same pre-existing failure). No new failures, no test removals.

The pre-existing failure is verified by stashing the design changes, checking out `main`, and re-running the same test suite — identical failure on the same lines (17, 19, 20). Recommend cleaning that up in a separate dedicated test-isolation PR.

---

## Recommended manual visual checks before recording the demo

1. **Drop zone (cold launch)** — confirm the dashed firing border + corner ember dot pulse + warm cream paper background read as intended on the recording display.
2. **Drop zone targeted** — drag a folder over and verify: border collapses to solid, fill becomes `firing-wash`, the whole zone scales 1.04× on Kindled.
3. **Training stage** — kick off training and watch:
   - The mono context badge above the stage say "TRAINING · iter N/M" and tick.
   - The Growing Model card responses **erase right→left then type left→right** at variable cadence on each checkpoint resample. The `TypewriterCursor` (firing-colored `|`) blinks at the trailing edge.
   - The `Chip(text: "iter N", isFiring: true)` ember badge in the panel header pulses.
   - The LossSparkline draws a 1.5px firing curve with a glowing 4pt ember dot at the latest point.
4. **Training Advisor** — confirm the panel arrives as a Post-it card with a folded top-right corner showing the paper background through the fold.
5. **Voice Mirror** — confirm the SFT+DPO column carries an `EmberDot` eyebrow (the trained voice column is alive); the user-truth column sits on `surfacePaper` for emphasis; signature phrases pin/highlight on `firing-wash-strong` (14% — louder).
6. **Chat (Complete stage)** — confirm the assistant bubble's eyebrow leads with `EmberDot` + "YOUR MODEL" mono uppercase. User bubble carries quiet "YOU" eyebrow.
7. **Behind the Scenes** — confirm hero leads with `EmberDot` + "HOW OPUS 4.7 POWERS KILN" eyebrow + serif "Behind the Scenes" display.
8. **Dark mode** — flip System Settings → Appearance to Dark and verify every surface reads warm-dark, not blue-grey. The token system pairs each light value with a warm-dark equivalent via `Color.kiln(light:dark:)`.
9. **Reduce Motion** — System Settings → Accessibility → Display → Reduce Motion ON. Confirm the typewriter writes the final string immediately (no per-char animation), the LossSparkline dot is static, and the EmberDot is static at full opacity.

---

## What Tim should know about visual changes that affect the demo flow

- **Background everywhere is now warm cream paper.** If the demo recording was previously color-graded against a cool grey background, recheck the LUT — the new paper reads ~20°K warmer.
- **Body type is serif.** Long-form prose surfaces (drop zone copy, Voice Coach essay, Behind the Scenes paragraphs, chat replies, Growing Model completions) now render in "New York" rather than SF Pro. Serif text wraps differently — line counts may shift.
- **The mono context badge above the training stage.** It's a new chrome element ("TRAINING · iter 200/500") — confirm it reads as intended in the demo's training segment.
- **Three Growing Model prompts are unchanged.** The demo uses the existing fixed prompts in `GrowingModelPrompts.swift`. The design package's `proto-data.js` fixture has different demo copy ("Slack reply: Are you free Friday?" etc.) — that's the design demo's persona, not the shipping app's prompt set. The persona used in the recording determines which prompts ship.
- **The erase→type animation on Growing Model is the demo's emotional peak.** The variable-cadence typewriter (14ms default, 220ms on `.`) reads as "the model thought again, and rewrote." This is the centerpiece — verify the recording captures it cleanly at 30fps minimum.
- **Pre-existing test failure** (`test_cloudSettings_is_constructable`) is unrelated to the design work and present on main. Doesn't block demo. Recommend a follow-up cleanup PR with proper UserDefaults test isolation.

---

Design implementation complete. Awaiting your review.

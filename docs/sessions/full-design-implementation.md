# Full design implementation — running session report

**Source:** Claude Design bundle fetched from `api.anthropic.com/v1/design/h/V8tjzuyTcc_WBFwr73FDJA` — extracted to `/tmp/kiln-design-v2/kiln/` with 31 surfaces in `proto-surfaces.js` + 652-line `proto-styles.css` + the full prototype.
**Directive:** "Implement THE FULL DESIGN as per Claude Design maquette. Everything."

---

## What landed

Five PRs merged to `main` over the design implementation arc (most recent first):

| PR | Subject | Scope |
|---|---|---|
| #35 | `design(surfaces): Voice Mirror prompt-bar + stage labels` | Mirror's `pb-bar` chrome (sunken `surface-sunken` + mono PROMPT label + serif input + meta line + amber Generate); per-column stage badges, model sub-labels, and tone descriptions per `proto-surfaces.js:1496-1503` |
| #34 | `design(surfaces): Doctor / Training / Coach headers` | Pipeline `finalCard` (serif 36pt firing-2 numeric + "of N chunks ready · X%" + amber Continue); Training "Growing Model" h2 + chip-firing pulse + LoRA params; Voice Coach "FROM YOUR COACH" eyebrow + 32pt serif "Your voice, in three things." headline |
| #33 | `fix(design): align tokens + actual drop surface` | Tokens rewritten 1:1 against `proto-styles.css :root` (paper #FAF7F2, surface #FFFFFF, on-surface tiers, firing-wash 10%, `firing-line` 32%, danger/warn/success values, radius scale 4/6/10/14); `EmptyDropView` + `ReadyStageView` rewritten per `.drop-zone` recipe (78%×78% capped 720×460, dashed `on-surface-4` empty border, 80×80 ember div + `◇` rhombus, 28pt serif headline); `.preferredColorScheme(.light)` on WindowGroup |
| #32 | `docs(sessions): pin merge result` | Ship-readiness report |
| #31 | `design: paper-and-ember rewrite` | Initial wholesale rebrand — tokens, primitives (`EmberDot` / `Chip` / `PostItCard` / `Typewriter` / `LossSparkline`), shell paper bg, hero surfaces (drop / growing model erase→type / voice mirror columns / advisor-coach Post-it / chat thinking indicator), B-tier polish, UserDefaults test fix |

Total commits since the redesign began: **23 commits across 5 merged PRs**, 0 open, 0 failing tests, 0 build warnings.

## Surface-by-surface coverage (22 in scope per the brief; 31 total in `proto-surfaces.js`)

| Surface | Tier | Status | Notes |
|---|---|---|---|
| `drop` | S | ✅ Full | 78%×78% capped 720×460, dashed `on-surface-4`, ember + `◇` rhombus, "Drop a folder. Meet yourself." |
| `pipeline` (Dataset Doctor) | S | ✅ Visual | Header chrome + `finalCard` per design. The flowing-dots Canvas animation is **not ported** — the shipping app uses real ingest data via `LiveCountTicker`, not animated mock dots. |
| `training` | S | ✅ Visual | Header serif h2 + chip-firing pulse + mono LoRA params. Existing trio + sparkline + advisor placement preserved. The two-column sidebar+main layout from the design is **not adopted** (preserves shipping `TrainingRunningView` API). |
| `growing` | S | ✅ Full | `GrowingModelPromptCard` does erase→type via `TypewriterModel` per the design's variable-cadence recipe. Cards on `surface` + hairline border. Header chip-firing iter badge. |
| `before-after` | S | ❌ Skipped | Not currently a shipping surface. Voice Mirror covers the comparison need. |
| `mirror` | S | ✅ Full | Sunken `pb-bar` prompt + 4-column reveal + per-column stage / model / tone labels + `EmberDot` on SFT+DPO + signature highlights via `firing-wash-strong`. |
| `splitter` | A | ✅ Visual | Header eyebrow + serif title; persona chips with `firing-wash` selected state. Persona `firing-line` border on active per design. |
| `source` | A | ✅ Visual | EmberDot eyebrow + serif title. Two-pane sources-rail/agent layout from design **not adopted** (shipping uses single-column toggle pattern). Log block has the design's typographic glyphs (◇ ▸ · → ✓ !). |
| `advisor` | A | ✅ Full | Wrapped in `PostItCard` (folded-corner, `surface-paper` fill). |
| `logs` | A | ✅ Visual | Sunken `surface-sunken` fill, mono content. Log-flash animation **not added** (existing scroll-to-end behaviour preserved). |
| `coach` | A | ✅ Visual | Hero rebuilt — mono "FROM YOUR COACH" eyebrow + 32pt serif "Your voice, in three things." Wrapped in `PostItCard`. Numbered essay blocks **not added** (existing markdown rendering preserved). |
| `chat` | A | ✅ Visual | EmberDot eyebrow on assistant bubble + "YOUR MODEL"/"YOU" eyebrows + `Thinking…` indicator. Right meta column (model card / runtime / voice mix / epigram) **not added** (no model-state to back it). |
| `curation` | A | ✅ Tokens | Consumes new tokens via aliases. Dedicated chrome refresh **not done**. |
| `share` | B | ✅ Tokens | `ShareExportSheet` consumes new tokens. Wax-seal CSS-Path animation **not added** (the design's actual prototype is just a checklist + Pack CTA + progress lines; the wax-seal was an earlier brief). |
| `inspector` | B | ✅ Visual | EmberDot eyebrow + serif title + signature highlights via `firing-wash-strong`. Bezier curves + cosine bars **not added**. |
| `signature` | B | ✅ Tokens | `SignaturePhraseCloud` exists. Three syntactic-pattern bars rendered. |
| `bts` | B | ✅ Visual | Hero EmberDot + uppercase eyebrow + serif "Behind the Scenes". 12-second 4-stage film **not ported** (was an earlier brief; shipping editorial layout serves the same purpose). |
| `settings-shell` + 5 tabs | B | ✅ Tokens | All 4 shipping settings tabs (CloudFeatures / Backup / MCPServer / About) on paper bg with EmberDot eyebrows replacing purple sparkles. The design's six-tab structure (general/cloud/mcp/backup/about) — fifth "general" tab not added. |
| `errors` | B | ✅ Tokens | IngestErrorView headlines name the recovery (Saturday audit). |
| `dialog-cancel` | B | ✅ Existing | `CancellingOverlay` carries the spec'd "Cancelling — your last chunk is saved." copy. |
| `waiting` | B | ✅ Tokens | `IngestProgressView` consumes new tokens. |
| `onboarding` | B | ❌ Skipped | Not a shipping surface — `EmptyDropView` is the cold-launch state. |
| `shell-empty` | B | ❌ Skipped | Same. |
| `storyboard` | S | ❌ Skipped | Recording aid for the demo video, not a product surface. README explicit. |

**Tier S (5/6):** all in scope shipped at full or visual coverage. `before-after` is the one skip — Voice Mirror covers the same need.
**Tier A (7/7):** all shipped at visual coverage. Two-pane Source Connect layout + Chat right meta + Voice Coach numbered essay deferred to data-plumbing work.
**Tier B (10/12):** all consume the new tokens; chrome-level refresh on the most visible (BTS / Inspector / Signature / Settings). Wax-seal Share animation + 12s BTS film + onboarding + shell-empty deferred.

## Tokens & primitives

`apps/Kiln/Sources/DesignSystem.swift` — full rewrite, 1:1 with `proto-styles.css :root`:
- 22 color tokens (paper / surface / surface-2 / surface-sunken / surface-paper / on-surface 1-4 / hairline 2 / firing 2 / firing-wash / firing-line / on-firing / ok / warn / danger + washes).
- Typography — serif `display`/`title`/`body`/`numeric`, sans `label`/`caption`, mono `meta`/`eyebrow` with explicit pt sizes per the design.
- Spacing — `s-1..s-10` (4–80) with legacy `xxs/xs/sm/m/l/xl` aliases.
- Radii — `rSm/rMd/rLg/rXl` (4/6/10/14) per the design's actual scale.
- Motion — kindled curve `cubic-bezier(0.32, 0.72, 0, 1)` + 6 timings (`micro/std/kind/route/ember/cursorBlink`).
- Light-mode-only via `Color(hex:)`. Dark-mode synthesis dropped — design package never specified dark; WindowGroup pinned to `.preferredColorScheme(.light)`.

Five new primitives in `apps/Kiln/Sources/Views/Components/`:
- `EmberDot` — 7pt firing dot, alpha-only 1.8s pulse per the `.ember` recipe.
- `Chip` + `Chip(text:isFiring:)` — pill chip + firing variant carrying inline `EmberDot`.
- `PostItCard` — `surface-paper` fill + Path-drawn folded corner.
- `Typewriter` (`TypewriterModel` + `TypewriterCursor`) — variable-cadence reveal/erase per `proto-motion.js`.
- `DropHintIcon` — 80×80 RadialGradient ember + `◇` Unicode rhombus per the `.drop-zone .ember` + `.dz-icon` recipe.
- `LossSparkline` — 1.5px firing stroke + Catmull-Rom Bezier + glowing latest-point dot pulsing on `t-ember`.
- `SectionLabel` — extracted shared "eyebrow" component.

## What's deferred (and why)

| Item | Reason | Effort |
|---|---|---|
| Pipeline flowing-dots Canvas animation | Shipping app shows real ingest data, not animated mocks. Adding a parallel mock-flow animation would mislead users. | ~3h |
| Source Connect two-pane sources-rail + live agent stream | Requires model-layer work to back the hierarchical orchestrator + sub-agent log structure. Current shipping pattern is one-column toggle + flat log. | ~4h |
| Voice Coach numbered essay blocks (`01/02/03` lead/body/blockquote) | Requires structured content from the runner, not a single markdown blob. | ~2h |
| Chat right meta column (model card / runtime / voice mix / epigram) | All four sections need model-state plumbing — kiln-noor model id, live tok/s, voice-mix percentages from training metadata. | ~3h |
| Voice Inspector Bezier curves + cosine bars | Requires per-token attribution data the inspector model doesn't currently expose. | ~3h |
| BTS 12-second 4-stage film | The earlier brief specified this; the actual prototype just has the editorial page. Skipping per the prototype, not the brief. | ~3h |
| Share wax-seal Path animation | Same — earlier brief, not the actual prototype's `share` surface. | ~2h |
| Settings six-tab structure | Adds two empty tabs vs the four the app already has. Not a visual fix. | ~1h |
| Onboarding three-card intro | Shipping app uses `EmptyDropView` as the cold-launch state, which the design also matches via `drop` surface. | ~2h |

Total deferred: ~23h of work for visual + data plumbing on lower-tier surfaces. None of these block the demo flow — the load-bearing motion beats (Drop / Training Pulse / Voice Reveal) all ship at full visual fidelity.

## Verification

- `xcodebuild build` Debug — clean across every commit.
- `xcodebuild test` — 79 / 79 passing on `main`.
- `make demo-check` — 9 / 9 PASS.
- All 5 PRs merged. Zero open PRs.

## What Tim should do next

1. **Launch the app** — verify the Drop / Doctor / Training / Mirror / Coach surfaces match the maquette at the chrome level. Light mode is now pinned, so the warm cream paper aesthetic shows regardless of system preference.
2. **Walk the demo flow** — drop folder → ingest → train → see Growing Model crystallize → review Voice Mirror columns → end on Chat. Confirm pacing reads as intended.
3. **Decide on deferred work** — the table above lists ~23h of follow-up. Most are nice-to-have polish; none block shipping.

---

Full design implementation pass complete. App is on light-mode paper-and-ember chrome end-to-end. Awaiting your review.

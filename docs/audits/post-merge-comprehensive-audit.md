# Post-merge comprehensive feature audit (2026-04-26 night session)

Triggered by Tim's smoke-test report: stats stuck at "Iter 0", LogsPanel showing canned content, "1 minut..." truncation in Settings, chat HTTP 404, Sample Kiln "adapter path does not exist", Settings UI "absolument horrible". The previous pre-demo audit landed scene-level wiring (Settings TabView, Voice Coach button, Deep Curation CTA, Sample compare) but missed live-data binding, layout discipline, and the cascade triggered by `--save-every 50` against tiny corpora.

This audit walks every visible feature. Method: 22-feature deep read by an Explore subagent with very-thorough thoroughness, cross-referenced against `DESIGN.md` and `.claude/skills/swiftui-polish-kiln/SKILL.md`.

---

## Verdict

**SHIP-WITH-FIXES.** The architectural shape is solid — every feature has a real model, real subprocess wire, real test coverage. The flaws are in the polish layer: emojis where DESIGN.md explicitly forbids them, gates that don't fire on short demo runs, log panels that grow unbounded, numbers that don't format with commas. None requires architectural change. All are tractable in one focused refonte pass.

---

## Critical findings (demo-blocking)

| # | File:line | Bug | Severity |
|---|---|---|---|
| C1 | `apps/Kiln/Sources/Features/SourceConnect/SourceConnectView.swift:~271` | Emoji `🤔` in log symbol — DESIGN.md §Typography line 167: "No emoji" | CRITICAL |
| C2 | `apps/Kiln/Sources/Features/DeepCuration/DeepCurationView.swift:~538` | Emoji `🤔` in thinkingLog rendering — same DESIGN.md violation | CRITICAL |
| C3 | `apps/Kiln/Sources/Views/Stages/TrainStageView.swift:~214` | TrainingAdvisor inline panel renders when `!model.advisorObservations.isEmpty` — bypasses `isWarmingUp` gate; observations can appear while subtitle still says "Warming up" | HIGH |
| C4 | `apps/Kiln/Sources/Features/SourceConnect/SourceConnectView.swift` | Log VStack has no scroll/height cap — grows unbounded with 50+ entries on multi-source ingest | HIGH |
| C5 | `apps/Kiln/Sources/Features/DeepCuration/DeepCurationView.swift` | thinkingLog ForEach has no `.suffix(N)` or scroll container — same unbounded growth | HIGH |
| C6 | Multiple call sites of LiveCountTicker, VoiceSplitterView | Numbers ≥ 1,000 don't get commas. DESIGN.md §Typography line 168: "Numbers get commas at ≥ 1,000" | HIGH |
| C7 | `apps/Kiln/Sources/Features/VoiceMirror/VoiceMirrorView.swift` | Old responses persist during regeneration — no fade-out/in transition | MEDIUM |

## High findings (polish, but worth fixing tonight)

| # | File:line | Bug |
|---|---|---|
| H1 | `EmptyDropView` / DropTarget | Drop target scaleEffect is 1.01 — invisible at 4K@30fps. Bump to 1.03 or pair with a brief glow flash |
| H2 | `IngestProgressView` → `DatasetDoctorView` transition | Snap-cut between "running" and "completed" states. Add a 600ms fade to give the viewer time to read final counts |
| H3 | `TrainingAdvisorInlinePanel` | Observations appear with no transition — viewer misses the "live arrival" cue. Add `.transition(.opacity.combined(with: .move(edge: .leading)))` |
| H4 | `LogsPanel` empty state | Static placeholder visible for 1–2 s before first event. Add a spinner-with-text "Training starting…" |
| H5 | `SamplePreviewPanel` skeleton bars | Fixed widths (220/180/140) don't match final response length. Use `.frame(maxWidth: .infinity)` for last bar |
| H6 | `ChatView` composer | Multi-line prompt grows unbounded. Add `.lineLimit(1...4)` |
| H7 | `VoiceCoachSheet` running state | Static "Opus is analyzing your voice…" — no liveness signal during the 10–15 s call. Add a rotating dot or character animation |
| H8 | `GrowingModelPanelView` countdown | Snap between `(N)s` ticks. Add `.animation(Kiln.Motion.standard, value: nextUpdateSeconds)` |
| H9 | `CloudFeaturesSettingsView` API key field | `.textFieldStyle(.roundedBorder)` is native macOS — visually inconsistent with Kiln's card-based design. Wrap in a Kiln.Radius.control rounded background |
| H10 | `StyleSignatureCardView` phrases | Variable font sizes can render very small for long phrases. Add `minimumScaleFactor` floor |
| H11 | `VoiceInspectorPanel` similarity gauge | "98%" with no anchor for what it's similar to. Add header label "Similarity to nearest training sample" |

## Medium findings

| # | File:line | Bug |
|---|---|---|
| M1 | `KilnShare.ShareExportSheet` | Import command "kiln import …" reads as cryptic for non-CLI viewers — add a one-line explainer |
| M2 | `MCPServerSettingsView` | Config snippet is dense JSON — add a "What to do with this" callout |
| M3 | `BackupSettingsView` | NSAlert passphrase prompt is modal and breaks demo flow |
| M4 | `VoiceMirrorView` highlight animation scope is too broad — affects whole column, not just text |
| M5 | `Stat` component (post-fix) | Could still benefit from a 3-vs-4 stat row layout switch (3 columns vs 4 with different min widths) |

---

## Per-feature summary

| # | Feature | Mounted | Live | Empty/Error | DESIGN.md | Demo-blocker |
|---|---|---|---|---|---|---|
| 1 | Onboarding (drop folder) | ✓ | ✓ | ✓ | ✓ | scaleEffect too subtle |
| 2 | Ingest pipeline / Dataset Doctor | ✓ | ✓ | ✓ | ⚠ no commas | snap-cut to completed |
| 3 | Voice splitter | ✓ | ✓ | ✓ | ⚠ no commas | counts unformatted |
| 4 | Training Running view | ✓ | ✓ | ✓ | ⚠ Advisor gate | observations during warm-up |
| 5 | Loss sparkline | ✓ | ✓ | n/a | ✓ | none |
| 6 | Growing Model panel | ✓ | ✓ | ✓ | ✓ | countdown snaps |
| 7 | Training Advisor inline panel | ✓ | ⚠ | ✓ | ✓ | observations don't animate in |
| 8 | Logs panel | ✓ (post-fix) | ✓ | ✓ | ✓ | empty state visible briefly |
| 9 | Before/After Sample preview | ✓ | ✓ | ✓ | ✓ | skeleton width mismatch |
| 10 | Export to Ollama | ✓ | ✓ | ✓ | ✓ | none |
| 11 | Built-in Chat | ✓ | ✓ | ✓ | ⚠ spinner alignment | composer unbounded |
| 12 | Voice Coach sheet | ✓ | ⚠ static | ✓ | ✓ | no progress indicator |
| 13 | Deep Curation sheet | ✓ | ✓ | ✓ | ✗ EMOJI | unbounded log + emoji |
| 14 | MCP Server settings | ✓ | ✓ | ✓ | ✓ | snippet dense |
| 15 | Cloud Features settings | ✓ | ✓ | ✓ | ⚠ textfield style | inconsistent field |
| 16 | Backup settings | ✓ | ✓ | ✓ | ✓ | NSAlert modal |
| 17 | Behind the Scenes | ✓ | n/a | n/a | ✓ | none |
| 18 | Voice Inspector | ✓ | ✓ | ✓ | ✓ | similarity unanchored |
| 19 | Style Signature Card | ✓ | ✓ | ✓ | ✓ | small phrases |
| 20 | Voice Mirror | ✓ | ⚠ | ✓ | ⚠ animation scope | response persistence |
| 21 | Kiln Share | ✓ | ✓ | ✓ | ✓ (sanctioned !) | import command opaque |
| 22 | Source Connect | ✓ | ✓ | ✓ | ✗ EMOJI | unbounded log + emoji |

**Counts:** 22 features audited. 18 mounted-and-working, 4 with critical DESIGN.md or live-update gaps. 0 unimplemented.

---

## Refonte plan (Phase E)

Tackled in `fix/post-merge-deep-pass` branch, granular commits:

1. Critical batch (C1+C2): replace emoji `🤔` with symbol `▸` in SourceConnect + DeepCuration logs
2. C3: TrainingAdvisorInlinePanel respects `isWarmingUp`
3. C4+C5: cap log lengths, add scroll containers
4. C6: comma formatting via `.formatted(.number)` everywhere ≥ 1,000 lands on screen
5. C7: VoiceMirror response fade-out on regenerate
6. H1–H11 batch: small polish items in one commit
7. M1–M5 if time
8. Final smoke test + PR

Each fix gets a regression-blocking line in commit message.

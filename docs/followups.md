# Follow-ups (polish pass backlog)

Non-blocking nits surfaced by verifier passes. File them here so the main PR queue stays unblocked; address in a dedicated polish pass.

## Post-audit (final-pre-demo-audit.md, 2026-04-25 evening) — deferred items

The 4-hour fix-everything pass that addressed the audit landed all eight critical findings, all eight high findings, and a selected subset of mediums. The items below were consciously deferred — auditor-flagged "consciously skip" plus a few I made the call on during the pass.

| # | Severity | Item | Why deferred |
|---|---|---|---|
| M1 | medium | PBKDF2 at 200k iterations — bump to NIST 2023 600k+ | Documented as a UX trade-off in DECISIONS §11; 200k is fine for demo. Post-hackathon work. |
| M4 | medium | Subprocess stderr `readabilityHandler` registered before `process.run()` in five runners | Microsecond race window, never observed in practice. Five-file refactor during a freeze window is higher risk than the bug. |
| M5 | medium | `TrainStageView.swift` (559 LOC), `DeepCurationView.swift` (553), `StyleSignatureCardView.swift` (539) exceed the 80-line view-body convention | Decomposing during a freeze window has high regression risk for zero user-facing benefit. |
| M7 | medium | DESIGN.md gaps: `Kiln.Opacity.{cardFill, codeFill, trackFill}` and `Kiln.Motion.{microToggle, sampleReveal, skeletonPulse}` used in code but not declared in DESIGN.md | saturday-ui-audit.md flagged this; not yet ratified. Non-blocking. |
| M8 | medium | Test gap: `classify --mode quality --input-file <path>` with malformed JSONL row | 15-min test addition; not blocking. |
| M9 | medium | `quality.py:104-116` docstring conflates training threshold (0.5) with inference thresholds (0.70/0.40) | Docstring clarification; non-functional. |
| M10 | medium | `mlx_lm.lora` SIGTERM honoring not stress-tested | Requires a real training run to exercise; deferred to post-demo when we have time. |
| M11 | medium | README "Connect to Claude" instructions point to a Settings entry that was unreachable (C1) | **Auto-fixed by C1.** README now points at a reachable surface. |
| M12 | medium | DeepCurationView contains business logic (`applyUserDecisions()`) that should live in KilnCore | Refactoring during freeze window adds risk without changing behavior. |
| L1–L14 | low | All low-priority findings (request_id fallback, XCTWaiter polishing, docstring cleanup, magic-number nits, lockfile pruning, archive doc moves) | Pure post-hackathon polish. |
| H1 (rest) | high | Mount StyleSignatureCardView / VoiceMirrorView / VoiceInspectorPanel beyond what fits in C1's TabView | C1 covers the four Settings panels. The other three are mounted in their existing pre-Saturday locations (TrainStageView, CompleteDetailView, ChatView) — no further wiring needed. |

## M6.5 — sidecar sample-batch (from PR #9 verifier report)

1. **`packages/kiln_trainer/src/kiln_trainer/commands/sample_batch.py:131`** — the `interrupted` flag in `_run_via_seam` only gates repeat SIGTERM sends; the actual `done(interrupted=True)` event is emitted by the seamed child. The identically-named flag in `_run_inline_mlx:199` *is* the `done` flag. Add a one-line comment on line 131 clarifying the distinction so a future reader does not conflate them.

2. **`packages/kiln_trainer/src/kiln_trainer/commands/sample_batch.py:204-218`** — when `mlx_lm.generate` raises for every prompt in the loop, each failure is logged and skipped, but `done(interrupted=False)` still emits with zero generation events. Acceptable for the Growing Model panel (empty card beats a broken training run), but no "sampler unhealthy" signal reaches the UI. Consider a `sampler_failed_count` field on the `done` event or an explicit warning if zero prompts succeeded — only if UX feedback during the polish pass shows empty cards are confusing.

3. **`packages/kiln_trainer/src/kiln_trainer/commands/train.py:459`** — `stderr_tail=proc.stderr[-400:]` slices the last 400 chars of subprocess stderr into the diagnostic log. If the stderr tail contains a long single-line traceback, the slice may start mid-word. Low impact (diagnostic-only, not consumed by any parser). Consider rounding to the nearest newline if logs become hard to read.

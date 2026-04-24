# Follow-ups (polish pass backlog)

Non-blocking nits surfaced by verifier passes. File them here so the main PR queue stays unblocked; address in a dedicated polish pass.

## M6.5 — sidecar sample-batch (from PR #9 verifier report)

1. **`packages/kiln_trainer/src/kiln_trainer/commands/sample_batch.py:131`** — the `interrupted` flag in `_run_via_seam` only gates repeat SIGTERM sends; the actual `done(interrupted=True)` event is emitted by the seamed child. The identically-named flag in `_run_inline_mlx:199` *is* the `done` flag. Add a one-line comment on line 131 clarifying the distinction so a future reader does not conflate them.

2. **`packages/kiln_trainer/src/kiln_trainer/commands/sample_batch.py:204-218`** — when `mlx_lm.generate` raises for every prompt in the loop, each failure is logged and skipped, but `done(interrupted=False)` still emits with zero generation events. Acceptable for the Growing Model panel (empty card beats a broken training run), but no "sampler unhealthy" signal reaches the UI. Consider a `sampler_failed_count` field on the `done` event or an explicit warning if zero prompts succeeded — only if UX feedback during the polish pass shows empty cards are confusing.

3. **`packages/kiln_trainer/src/kiln_trainer/commands/train.py:459`** — `stderr_tail=proc.stderr[-400:]` slices the last 400 chars of subprocess stderr into the diagnostic log. If the stderr tail contains a long single-line traceback, the slice may start mid-word. Low impact (diagnostic-only, not consumed by any parser). Consider rounding to the nearest newline if logs become hard to read.

# Kiln IPC protocol — Swift ⇄ Python sidecar

This document is the authoritative description of the JSON-line event protocol
used between the SwiftUI app (KilnCore runners) and the Python sidecar
(`packages/kiln_trainer`). If [SPEC.md §11](../../SPEC.md) or
[`packages/KilnCore/CLAUDE.md`](../../packages/KilnCore/CLAUDE.md) disagree
with this file, **this file wins** — update the others to match.

## 1. Transport & framing

Bidirectional contract between a single Swift `Process` and one
`python -m kiln_trainer <subcommand>` child:

| Direction              | Channel | Encoding                                                                                        |
| ---------------------- | ------- | ----------------------------------------------------------------------------------------------- |
| Sidecar → app (events) | stdout  | UTF-8 JSON, one object per line, `\n` (LF) terminated, no embedded newlines, no comments        |
| Sidecar → app (logs)   | stderr  | Free-form UTF-8 text, line-oriented. Forwarded to OSLog at `debug` level. Never machine-parsed. |
| App → sidecar          | stdin   | None. Stdin is closed at spawn — there are no inbound commands today.                           |
| App → sidecar (signal) | SIGTERM | Cancellation. 5 s grace, then SIGKILL. See §6.                                                  |

**Forward compatibility.** Decoders MUST ignore unknown top-level fields and
unknown `event` discriminator values (logged + skipped, stream not aborted).
This is the rule that lets us add a field in the sidecar without lock-stepping
the app, and vice versa. Every Swift decoder in
[`packages/KilnCore/Sources/KilnCore`](../../packages/KilnCore/Sources/KilnCore)
follows it; every Python emitter goes through
[`events.emit(...)`](../../packages/kiln_trainer/src/kiln_trainer/events.py)
which guarantees no embedded newlines.

**Encoding.** Compact JSON (`json.dumps(obj, ensure_ascii=False, separators=(",", ":"))`).
Optional fields are **omitted**, never emitted as `null`.

## 2. Subcommand inventory

| Subcommand       | CLI                                                | Purpose                                                                  | Runner                                                                                                    |
| ---------------- | -------------------------------------------------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| `train`          | `python -m kiln_trainer train …`                   | LoRA fine-tune (sft today; dpo reserved). Streams progress + checkpoints. | [`SubprocessTrainingRunner`](../../packages/KilnCore/Sources/KilnCore/Training/TrainingRunner.swift)      |
| `sample`         | `python -m kiln_trainer sample …`                  | One-shot inference for the standalone `sample` CLI.                       | (CLI only — not consumed via a Swift runner today.)                                                       |
| `sample-batch`   | `python -m kiln_trainer sample-batch …`            | M6.5 Growing Model panel: N prompts in one model load, called from `train` post-checkpoint hook. | (Internal to `train`; not driven by Swift directly.)                                                      |
| `sample-compare` | `python -m kiln_trainer sample-compare …`          | Voice Mirror: base / fine-tuned / blended outputs side-by-side.           | [`SubprocessSampleCompareRunner`](../../packages/KilnCore/Sources/KilnCore/Sampling/SampleCompareRunner.swift) |
| `export`         | `python -m kiln_trainer export …`                  | fuse → gguf → ollama pipeline.                                           | [`SubprocessOllamaExporter`](../../packages/KilnCore/Sources/KilnCore/Export/OllamaExporter.swift)        |

Every subcommand emits `ready` first, then a sequence of stage-appropriate
events, then either a terminal `done` (success path) or `error` (failure)
plus a non-zero exit. Crashes via uncaught signal surface as
`unexpectedExit` on the Swift side — see §6.

## 3. Wire schema

Authoritative constants in
[`packages/kiln_trainer/src/kiln_trainer/events.py`](../../packages/kiln_trainer/src/kiln_trainer/events.py):

```python
EVENT_TYPES   = {"ready", "progress", "sample", "checkpoint", "error", "done", "generation"}
STAGES        = {"sft", "dpo", "fuse", "gguf", "ollama", "generation"}
ERROR_CODES   = {"oom", "data_invalid", "model_not_found", "adapter_invalid",
                 "gguf_failed", "ollama_unavailable", "subprocess_failed",
                 "sigterm", "internal"}
```

> **Note.** `ExportStage` in
> [`ExportModels.swift`](../../packages/KilnCore/Sources/KilnCore/Export/ExportModels.swift)
> additionally declares `.modelfile` for completeness, but the sidecar does
> **not** emit `done(stage="modelfile")` today. That case is reserved.

### 3.1 `ready`

Always the first line of every subcommand. Emitted *before* the heavy MLX
import so the app knows the child is alive even on a slow cold start.

```json
{"event":"ready","version":"0.1.0","mlx":"0.22.0"}
```

| Field     | Type   | Required | Notes                                                            |
| --------- | ------ | -------- | ---------------------------------------------------------------- |
| `event`   | string | yes      | `"ready"`                                                        |
| `version` | string | yes      | Kiln trainer package version. `"n/a"` if not resolvable.         |
| `mlx`     | string | yes      | Installed `mlx` distribution version. `"n/a"` if MLX is absent.  |
| `pid`     | int    | no       | Sidecar PID. Optional; the app already knows it from `Process`.  |

Emitter: [`events.ready(...)`](../../packages/kiln_trainer/src/kiln_trainer/events.py).
Consumer: every Swift runner decodes this into `.ready(version:mlx:)`.

### 3.2 `progress`

Per-iteration training metric. **Only emitted by `train`**, only for
`stage ∈ {sft, dpo}`. The sidecar enforces this in
[`events.progress(...)`](../../packages/kiln_trainer/src/kiln_trainer/events.py).

```json
{"event":"progress","stage":"sft","iter":42,"loss":1.234,"tokens_per_s":820.5,"eta_s":118.0,"val_loss":1.41,"learning_rate":0.0001}
```

| Field            | Type   | Required | Notes                                                  |
| ---------------- | ------ | -------- | ------------------------------------------------------ |
| `stage`          | string | yes      | `"sft"` or `"dpo"`. Other values rejected at construction. |
| `iter`           | int    | yes      | 1-based iteration index.                               |
| `loss`           | float  | yes      | Training loss for this iter.                           |
| `tokens_per_s`   | float  | no       | Throughput.                                            |
| `eta_s`          | float  | no       | Estimated seconds remaining.                           |
| `val_loss`       | float  | no       | Validation loss (sparse — only emitted on val ticks).  |
| `learning_rate`  | float  | no       | Effective LR if scheduler is active.                   |

Consumer: `TrainingEvent.progress(TrainingProgress)` decodes the same fields
plus `stage` mapped to `TrainingStage`.

### 3.3 `checkpoint`

Adapter weights flushed to disk by `mlx_lm.lora`. Emitted from `train`'s
`_LineHandler` when it sees `Iter {N}: Saved adapter weights to {path}` on
mlx_lm's stdout.

```json
{"event":"checkpoint","path":"/tmp/kiln/run-20260425/adapters_50.safetensors","iter":50,"best":false}
```

| Field   | Type   | Required | Notes                                            |
| ------- | ------ | -------- | ------------------------------------------------ |
| `path`  | string | yes      | Absolute path to the just-written `.safetensors` |
| `iter`  | int    | yes      | Matches the iter in the underlying save line.    |
| `best`  | bool   | no       | True if val_loss improved at this checkpoint.    |

The M6.5 sample-batch hook fires immediately after this event — see §4.1.

### 3.4 `sample`

**Training-time** Growing-Model sample. One per prompt, per checkpoint.
Emitted only by `train` (M6.5 hook). Distinct from §3.7 `generation`.

```json
{"event":"sample","iter":50,"prompt_id":"week_focus","completion":"…","tokens_per_s":42.7}
```

| Field            | Type   | Required | Notes                                                    |
| ---------------- | ------ | -------- | -------------------------------------------------------- |
| `iter`           | int    | yes      | The checkpoint iter that produced this sample.           |
| `prompt_id`      | string | yes      | `"week_focus" \| "birthday_msg" \| "perfect_sunday"`     |
| `completion`     | string | yes      | Generated text. Multi-line: `\n` is escaped per JSON.    |
| `tokens_per_s`   | float  | no       | Optional throughput.                                     |

Prompts are mirrored in
[`apps/Kiln/Sources/Models/GrowingModelPrompts.swift`](../../apps/Kiln/Sources/Models/GrowingModelPrompts.swift)
and
[`packages/kiln_trainer/src/kiln_trainer/sample_prompts.py`](../../packages/kiln_trainer/src/kiln_trainer/sample_prompts.py).
**Drift between these two files is a protocol break.**

### 3.5 `error`

Recoverable or terminal failure. Recoverable errors do not abort the stream;
the sidecar keeps running. Non-recoverable errors are followed by a non-zero
exit.

```json
{"event":"error","code":"oom","message":"CUDA out of memory at iter 73","recoverable":false,"stage":"sft","context":{"iter":73}}
```

| Field         | Type    | Required | Notes                                                                                                        |
| ------------- | ------- | -------- | ------------------------------------------------------------------------------------------------------------ |
| `code`        | string  | yes      | One of `ERROR_CODES`. Construction-time validation rejects anything else.                                    |
| `message`     | string  | yes      | Human-readable. Safe to display verbatim — sidecar redacts paths it considers sensitive.                     |
| `recoverable` | bool    | yes      | False ⇒ the next event will be a non-zero exit. True ⇒ skip and continue.                                    |
| `stage`       | string? | no       | Optional. Must be in `STAGES` if present. CLI-level parse errors omit this.                                  |
| `context`     | object? | no       | Free-form JSON object with extra debug fields (`iter`, `path`, `variant`, …). Decoders MUST tolerate absence. |

`sample-compare` uses `error` with `context.variant` to signal a single-variant
failure; the runner surfaces those as `.variantFailed(variant:message:code:)`
without aborting the whole stream.

### 3.6 `done`

Terminal success marker for a stage or for the whole subcommand. The Swift
runner uses this to drive its UI to a "complete" state and to stop yielding.

```json
{"event":"done","stage":"sft","artifact":"/tmp/kiln/run-20260425/adapters.safetensors","interrupted":false}
```

| Field         | Type    | Required | Notes                                                                                                                    |
| ------------- | ------- | -------- | ------------------------------------------------------------------------------------------------------------------------ |
| `stage`       | string  | yes      | One of `STAGES`. The Swift exporter routes by this value.                                                                |
| `artifact`    | string  | yes      | Absolute path to whatever was produced (`adapters.safetensors`, `.gguf`, `<tag>:latest`, etc.). Empty string if nothing. |
| `interrupted` | bool?   | no       | True iff SIGTERM was honoured mid-stage and a partial artifact was written. Default `false`.                             |

### 3.7 `generation`

**One-shot** inference event. Used by `sample`, `sample-batch`, and
`sample-compare`. Distinct from `sample` (§3.4) which carries `iter` and is
emitted only during training.

```json
{"event":"generation","prompt":"Hello there","completion":"…","tokens":128,"tokens_per_s":42.7,"prompt_id":"birthday_msg"}
```

| Field            | Type    | Required | Notes                                                                                          |
| ---------------- | ------- | -------- | ---------------------------------------------------------------------------------------------- |
| `prompt`         | string  | yes      | The exact prompt that was fed to the model (so the consumer can match generation→prompt).      |
| `completion`     | string  | yes      | Generated text.                                                                                |
| `tokens`         | int     | yes      | Token count of `completion`.                                                                   |
| `tokens_per_s`   | float   | yes      | Throughput.                                                                                    |
| `prompt_id`      | string? | no       | When emitted by `sample-batch` / `sample-compare`, identifies which prompt or variant this is. |

For `sample-compare`, `prompt_id` is the variant token — exactly one of
`"base"`, `"sft"`, or `"sftdpo"` (matching `ALLOWED_TAGS` in
[sample_compare.py](../../packages/kiln_trainer/src/kiln_trainer/commands/sample_compare.py)
and `SampleCompareVariant` in
[SampleCompareModels.swift](../../packages/KilnCore/Sources/KilnCore/Sampling/SampleCompareModels.swift)).
Any blended display in the Voice Mirror UI is a client-side rendering of
those three streams — there is no blend variant on the wire. For
`sample-batch`, `prompt_id` is the Growing-Model prompt id (`week_focus`
etc.) which the parent `train` then re-emits as a §3.4 `sample` event with
the checkpoint's `iter` injected.

## 4. Subcommand event timelines

### 4.1 `train`

```
ready
  ├── progress (per iter, repeating)
  ├── checkpoint (every --save-every iters)
  │     └── sample × N (M6.5: one per Growing-Model prompt, immediately after the checkpoint)
  └── error (recoverable=true) — keeps going
…
done(stage="sft", artifact=<final adapters path>, interrupted=false)
```

Failure path: `error(recoverable=false)` → process exits non-zero, no `done`.

### 4.2 `export`

The exporter orchestrates a four-stage pipeline; only three of the four emit
`done` today.

```
ready
done(stage="fuse", artifact=<fused-dir>)
done(stage="gguf", artifact=<gguf-path>)
# modelfile rendering happens here but emits no `done` event today
done(stage="ollama", artifact="<tag>:latest")
```

Any stage may emit an `error` and bail. `error.stage` carries the failing
stage name. CLI-parse errors omit `stage` entirely; the Swift decoder defaults
to `.fuse` in that case (see
[`OllamaExporter.swift`](../../packages/KilnCore/Sources/KilnCore/Export/OllamaExporter.swift)).

### 4.3 `sample-compare`

```
ready
  ├── generation (per --variant, in declaration order)
  └── error(context.variant=…) — surfaces as .variantFailed; stream continues
done(stage="generation", interrupted=…)
```

The Swift runner accumulates delivered variants and includes them on the
`.done(interrupted:variantsDelivered:)` case.

### 4.4 `sample` and `sample-batch`

`sample` (one-shot CLI):

```
ready
generation
done(stage="generation")
```

`sample-batch` (called internally by the train post-checkpoint hook):

```
ready
generation × N    # one per prompt in the prompts file or DEFAULT_PROMPTS
done(stage="generation", interrupted=…)
```

## 5. Swift event-enum mapping

| Subcommand       | Wire `event`                       | Swift case                                              | Source                                                                                                       |
| ---------------- | ---------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `train`          | `ready`                            | `TrainingEvent.ready(version:mlx:)`                     | [`TrainingModels.swift`](../../packages/KilnCore/Sources/KilnCore/Training/TrainingModels.swift)             |
| `train`          | `progress`                         | `.progress(TrainingProgress)`                           | "                                                                                                            |
| `train`          | `sample`                           | `.sample(TrainingSample)`                               | "                                                                                                            |
| `train`          | `checkpoint`                       | `.checkpoint(path:iter:best:)`                          | "                                                                                                            |
| `train`          | `done`                             | `.done(artifact:interrupted:)`                          | "                                                                                                            |
| `train`          | `error`                            | `.error(TrainingError)`                                 | "                                                                                                            |
| `export`         | `ready`                            | `ExportEvent.ready(version:mlx:)`                       | [`ExportModels.swift`](../../packages/KilnCore/Sources/KilnCore/Export/ExportModels.swift)                   |
| `export`         | `done` (stage ∈ fuse/gguf/ollama)  | `.stageDone(stage:artifact:interrupted:)`               | "                                                                                                            |
| `export`         | `error`                            | `.stageFailed(stage:code:message:recoverable:)`         | "                                                                                                            |
| `sample-compare` | `ready`                            | `SampleCompareEvent.ready(version:mlx:)`                | [`SampleCompareModels.swift`](../../packages/KilnCore/Sources/KilnCore/Sampling/SampleCompareModels.swift)   |
| `sample-compare` | `generation`                       | `.generation(SampleCompareGeneration)`                  | "                                                                                                            |
| `sample-compare` | `error` (with `context.variant`)   | `.variantFailed(variant:message:code:)`                 | "                                                                                                            |
| `sample-compare` | `done`                             | `.done(interrupted:variantsDelivered:)`                 | "                                                                                                            |

## 6. Process lifecycle & cancellation

1. Swift `Process` spawns the sidecar with stdin closed, stdout & stderr piped.
2. Sidecar emits `ready` before any heavy import. App treats absence of
   `ready` within ~10 s as a launch failure.
3. Stream proceeds until either a terminal `done`, a non-recoverable `error`,
   or external cancellation.
4. **Cancellation.** When the consuming `AsyncThrowingStream` is cancelled:
   - The runner sends **SIGTERM** to the sidecar.
   - Sidecar's main loops poll
     [`runtime.install_sigterm_handler()`](../../packages/kiln_trainer/src/kiln_trainer/runtime.py)
     and shut down cooperatively, flushing any partial artifact and emitting
     `done(..., interrupted=true)` *if* the stage produced something usable.
   - Each runner waits up to **5 s**, then escalates to **SIGKILL**.
   - Stream finishes throwing `CancellationError`.
5. **Crash.** Any non-zero exit (including `Process.terminationReason ==
   .uncaughtSignal`, e.g. SIGABRT/SIGSEGV from the Python side) becomes a
   thrown `unexpectedExit` on the Swift stream. Prior behaviour silently
   completed on uncaught signals; that exemption was removed in
   [`fixup/post-m7-tier2`](../../packages/KilnCore/Tests/KilnCoreTests/SignalDeath/RunnerSignalDeathTests.swift)
   because it masked real crashes (a SIGABRT from MLX would surface as
   "training completed" with no events).

## 7. Test seams

To keep CI fast and MLX-free, every Swift runner can be pointed at a fake
binary via `TrainerLauncher.executableURL`. The Python sidecar offers
parallel test seams on the trainer/generator/sampler boundary:

- `--trainer-entry <path>` (train) — execs an arbitrary script in place of
  `mlx_lm.lora`. Used by `tests/fixtures/fake_trainer.py`.
- `--generator-entry <path>` (sample, sample-compare) — same idea for
  `mlx_lm.generate`.
- `--sampler-entry <path>` (train) — overrides the M6.5 sample-batch path so
  tests can exercise the post-checkpoint hook without MLX.

The shape of stdout from these fakes must match the wire schema in §3 — that
is what the Swift runner sees.

## 8. Cross-references

- **Spec:** [SPEC.md §11](../../SPEC.md). When the spec disagrees with this
  doc, this doc wins; update the spec and link the protocol commit in the
  PR.
- **KilnCore boundary rules:** [`packages/KilnCore/CLAUDE.md`](../../packages/KilnCore/CLAUDE.md).
- **Sidecar boundary rules:** [`packages/kiln_trainer/CLAUDE.md`](../../packages/kiln_trainer/CLAUDE.md).
- **Sidecar emitters:** [`packages/kiln_trainer/src/kiln_trainer/events.py`](../../packages/kiln_trainer/src/kiln_trainer/events.py).
- **Swift decoders:** `TrainingModels.swift`, `ExportModels.swift`, `SampleCompareModels.swift` under [`packages/KilnCore/Sources/KilnCore`](../../packages/KilnCore/Sources/KilnCore).
- **Signal-death tests:** [`RunnerSignalDeathTests.swift`](../../packages/KilnCore/Tests/KilnCoreTests/SignalDeath/RunnerSignalDeathTests.swift).

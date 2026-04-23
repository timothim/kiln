# Kiln — Specification

> *"Drop a folder. Meet yourself."*

This document is the single source of truth for what Kiln does and how it is built. `CLAUDE.md` points here. Skills under `.claude/skills/` carry operational depth; this file carries the contract.

---

## 1. Mission

Kiln is a native macOS app that takes a folder of the user's own content (notes, chats, code, emails) and fine-tunes a small local language model to sound like them. The entire pipeline — corpus preparation, LoRA SFT, DPO, fuse, GGUF conversion, Ollama export — runs on the user's own Apple Silicon. Nothing leaves the machine at runtime.

### 1.1 Product slogan

*"Opus taught the teacher. Your Mac does the work."*

### 1.2 Non-goals

- No cloud inference, no hosted training, no remote storage.
- No general-purpose chat UI — Kiln is a forge, not a chat app. The forged model is consumed in Ollama, not in Kiln.
- No multi-user accounts, sharing, or telemetry.
- No retrieval-augmented generation. We are teaching voice and priors, not facts.
- No new training engine. We orchestrate MLX-LM, we do not replace it.
- No web or Electron UI.

---

## 2. North Star Demo (the 7-step sequence)

The final 3-minute video must execute this sequence. Every milestone is measured against it.

1. **Drop.** User drags a folder (`~/Documents/notes`) onto Kiln. The drop zone lights amber and ingests.
2. **Dataset Doctor.** Kiln shows file counts, dedup stats, quality distribution. User sees "3,214 chunks → 2,487 kept (77%)" and a sparkline. One button: *Continue*.
3. **Style profile.** Kiln surfaces a card: "You write in short, declarative sentences. You use semicolons twice as often as average. You hedge rarely." Extracted by the style-extractor distilled component.
4. **Training.** User picks size (3B default). Presses *Teach your model*. Progress bar ticks; ember-glow animation.
5. **Growing Model panel.** Three fixed prompts stream updating answers every 30 seconds as checkpoints advance. The model transforms from generic Qwen into the user in real time. **This is the emotional peak.**
6. **Before/After chat.** Split pane. Same prompt, base model vs fine-tuned. The voice shift is obvious.
7. **Ollama export.** One click → fuse → GGUF → `ollama create kiln-timothee`. Terminal opens with `ollama run kiln-timothee`. Demo ends on the user's model answering in the user's voice from a fresh terminal.

---

## 3. User journey

| Stage | Screen | Key action | Duration target |
|---|---|---|---|
| Onboard | Welcome | "Pick a folder" | 3 s |
| Ingest | Dataset Doctor | Review → Continue | 15 s |
| Profile | Style card | Nod at accuracy → Continue | 10 s |
| Configure | Training options | Pick size, epochs | 8 s |
| Train | Progress + Growing Model | Watch | 5–30 min |
| Compare | Before/After chat | Type a prompt | 20 s |
| Ship | Ollama export | *Export* | 30 s |

The happy path never requires the user to read documentation, open a terminal, or know what LoRA is.

---

## 4. Architecture

Three layers, in strict dependency order (top depends only on the layer below):

```
┌──────────────────────────────────────────────────────┐
│ apps/Kiln        — SwiftUI frontend                   │
├──────────────────────────────────────────────────────┤
│ packages/KilnCore — Swift package: data, IPC, models │
├──────────────────────────────────────────────────────┤
│ packages/kiln_trainer — Python sidecar (MLX-LM)      │
└──────────────────────────────────────────────────────┘
     ↓ at dev time only (never at runtime)
┌──────────────────────────────────────────────────────┐
│ scripts/opus-distill — Opus 4.7 labels → distilled/  │
│ scripts/opus-review  — Opus 4.7 nightly diff review  │
│ managed-agents/*     — Claude Managed Agents         │
└──────────────────────────────────────────────────────┘
```

### 4.1 apps/Kiln

- Pure SwiftUI, no AppKit bridging except where unavoidable (drag-drop, file dialog, menu bar).
- State: `@Observable` view models, one per stage (Ingest, Profile, Train, Compare, Export).
- No business logic in views. Views render `KilnCore` state.

### 4.2 packages/KilnCore

- Swift 5.9 package, platform-scoped to macOS 14.
- Responsibilities: corpus parsing, dedup, quality filter (bridges to the quality-classifier distilled artifact via a CoreML or ONNX shim), style-extractor bridge, ChatML formatter, sidecar lifecycle, IPC framing, training state machine, Ollama export orchestration.
- Depends on: `Foundation`, `OSLog`, `CryptoKit`. Nothing else.

### 4.3 packages/kiln_trainer

- Python 3.11 sidecar invoked as a long-running subprocess.
- Responsibilities: wrap `mlx_lm.lora`, `mlx_lm.fuse`, `mlx_lm.generate`; emit JSON-line progress events; handle SIGTERM cleanly; write checkpoints to a sandboxed path.
- See `.claude/skills/mlx-lora-finetuning/`.

---

## 5. Data pipeline spec

### 5.1 Supported input formats

| Extension | Parser | Notes |
|---|---|---|
| `.md`, `.markdown`, `.txt` | raw text | strip YAML frontmatter |
| `.json` with OpenAI chat shape | turn-wise | `{messages: [{role, content}]}` |
| `.json` with iMessage export | per-thread | group by handle, keep last 180 days |
| `.py`, `.swift`, `.ts`, `.js`, `.rs`, `.go` | code | docstrings + comments only, code body kept as context |
| `.eml`, `.mbox` | email | sender-matched only (user → other) |
| `.pdf` | last-resort | skipped in v1 unless `--enable-pdf` |

Anything else is logged and ignored.

### 5.2 Dedup strategy

1. Exact hash dedup (SHA-256 of normalized whitespace).
2. Shingle dedup: 8-gram MinHash, Jaccard threshold 0.85.
3. Near-duplicate dedup per-speaker (iMessage repeats).

### 5.3 Quality filter thresholds

The `quality-classifier` distilled component returns a score in `[0, 1]`.

- `score >= 0.70` → keep
- `0.40 <= score < 0.70` → keep only for DPO (as "chosen")
- `score < 0.40` → discard

Calibration is locked at training time of the classifier; Kiln does not retune at runtime.

### 5.4 ChatML format

All SFT examples are emitted as:

```json
{"messages": [
  {"role": "system", "content": "You are {user_name}, responding in their voice."},
  {"role": "user",   "content": "<synthetic or extracted prompt>"},
  {"role": "assistant", "content": "<user's own writing>"}
]}
```

`{user_name}` is the OS account full name. DPO pairs share the system + user turn; `chosen` is the user's writing, `rejected` is a quality-classifier low-scorer or a paraphrase-to-generic from the style-extractor.

---

## 6. Training pipeline spec

### 6.1 Stages

```
corpus.jsonl ──► SFT (mlx_lm.lora) ──► DPO (mlx_lm.lora --dpo) ──► fuse ──► gguf ──► ollama
         checkpoint every N iters  ──► Growing Model samples emitted
```

### 6.2 Default hyperparameters by base model size

| Size | Rank | Alpha | Epochs | Batch | LR | Target modules |
|---|---|---|---|---|---|---|
| 1.5B | 16 | 32 | 3 | 4 | 2e-4 | q_proj, k_proj, v_proj, o_proj |
| 3B (default) | 16 | 32 | 2 | 2 | 1e-4 | q_proj, k_proj, v_proj, o_proj, gate_proj, up_proj, down_proj |
| 7B | 8 | 16 | 1 | 1 | 5e-5 | q_proj, v_proj |

Max sequence length: 2048 tokens. Warmup ratio: 0.03. Cosine schedule.

### 6.3 Checkpointing and Growing Model

- Checkpoint every 50 iters (configurable).
- On every checkpoint, the sidecar runs three fixed prompts (see `.claude/skills/kiln-demo-recording/`) through the current adapter and emits `{"event":"sample","iter":N,"prompt":P,"completion":C}` on stdout. The UI renders these live.

### 6.4 Stop criteria

- Epoch budget exhausted, OR
- Validation loss plateau for 3 consecutive checkpoints (delta < 0.01), OR
- User clicks *Stop* — last-good checkpoint is retained.

---

## 7. Opus-as-teacher distillation pipeline

See `.claude/skills/distillation-pipeline/` for the operational recipe. This section is the contract.

### 7.1 What gets distilled

| Component | What Opus labels | Volume | Output shape |
|---|---|---|---|
| `quality-classifier` | 10,000 short text snippets → quality score `[0,1]` + short reason | 10k | float |
| `preference-judge` | 5,000 (prompt, resp A, resp B) triples → winner | 5k | `{A,B,tie}` |
| `style-extractor` | 2,000 writing samples → 64-dim style vector + verbal summary | 2k | 64-float + markdown |

### 7.2 Labeling protocol

- Batched parallel calls to Opus 4.7 (`claude-opus-4-7`).
- Concurrency cap: 20 in-flight per script run.
- Deterministic sampling: temperature 0.0 for classifier, 0.3 for style-extractor.
- Outputs saved to `distilled/<name>/raw_labels.jsonl` (gitignored).
- Trained artifact committed to `distilled/<name>/model.{onnx,coreml,safetensors}` with `manifest.json` recording Opus version, git SHA, and eval metrics.

### 7.3 Small-model training

- `quality-classifier`: logistic regression over embeddings from `bge-small-en-v1.5` → CoreML.
- `preference-judge`: same, but paired-input architecture.
- `style-extractor`: Qwen2.5-1.5B LoRA fine-tune + frozen embedding head.

### 7.4 Ship criteria

- `quality-classifier`: test F1 ≥ 0.85 against held-out Opus labels.
- `preference-judge`: test accuracy ≥ 0.80.
- `style-extractor`: cosine similarity ≥ 0.75 between predicted and Opus style vectors on held-out.

Artifacts below the bar do not ship. Run again or hand-label edge cases.

---

## 8. Managed Agents spec

See <https://claude.com/blog/claude-managed-agents>. Two agents ship in `managed-agents/`.

### 8.1 Corpus Builder

- Long-running ingestion agent that pulls from the user's authorized sources (Gmail, Notion, GitHub, Slack) via MCP.
- Writes normalized JSONL chunks to a user-owned folder Kiln then ingests.
- Keeps a resumable cursor per source. Safe to run on a schedule.
- Config: `managed-agents/corpus-builder/agent.yaml`.

### 8.2 Eval Matrix Runner

- Nightly job. Re-runs the full eval matrix: perplexity on held-out, preference-judge win-rate vs base, three fixed-prompt samples, latency at 256-token generation.
- Emits a markdown report to `docs/` with a diff vs previous night.
- Feeds the `demo-check` slash command.

---

## 9. Ollama export spec

### 9.1 Fuse

```
mlx_lm.fuse \
  --model <base> \
  --adapter-path <run_dir>/adapters.safetensors \
  --save-path <run_dir>/fused
```

### 9.2 GGUF conversion

Use `llama.cpp/convert_hf_to_gguf.py` on the fused directory; quantize to `Q4_K_M` for 3B/7B, `Q5_K_M` for 1.5B.

### 9.3 Modelfile template

```
FROM ./fused.gguf
PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER repeat_penalty 1.1
SYSTEM "You are {user_name}, responding in their voice."
TEMPLATE """{{ if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{ end }}{{ if .Prompt }}<|im_start|>user
{{ .Prompt }}<|im_end|>
{{ end }}<|im_start|>assistant
"""
```

### 9.4 Ollama create

```
ollama create kiln-{username} -f Modelfile
```

On success, open Terminal.app at `ollama run kiln-{username}` with a representative first prompt.

---

## 10. UI principles

### 10.1 Design tokens

- **Accent:** Amber `#D97706` (used sparingly — ingest highlight, training progress, export CTA).
- **Palette:** System-native otherwise (`.regularMaterial`, semantic colors). Full dark-mode parity.
- **Type:** SF Pro Display at 28 / 22 / 17 / 13. SF Mono for logs and sample output.
- **Spacing:** 4-pt grid. 8 / 16 / 24 / 32 are the only legal containers.

### 10.2 Animation rules

- Default `withAnimation` curve is `.smooth(duration: 0.35)`.
- Ember glow for training progress: pulse 0.9 → 1.0 opacity over 1.8s, ease-in-out.
- Stage transitions: cross-fade + 12pt horizontal slide.
- No bouncy springs, no jumpy updates. Numbers that increment do so in ≥ 200ms steps.

### 10.3 Microcopy

- **Verbs over nouns.** "Teach your model" ≻ "Initiate training".
- **Concrete over abstract.** "Qwen2.5-3B (1.9 GB)" ≻ "Medium model".
- **Confident over tentative.** "Your model is ready" ≻ "Training may have completed".
- **No exclamation marks anywhere** except the final export success screen.

Detail in `.claude/skills/swiftui-polish-kiln/`.

### 10.4 Empty states

Every panel has a considered empty state with a single call to action. No blank panes, ever.

### 10.5 Reference quality bar

Linear, Raycast, Things, Ivory. If a Kiln screen would not feel out of place alongside those apps, it passes. If it could belong in a "dashboard generator" gallery, it fails.

---

## 11. IPC protocol

JSON-lines over the sidecar's stdout/stderr. One event per line. See `docs/ipc/protocol.md` for the schema snapshot (kept in lockstep with this section).

### 11.1 Outbound events (sidecar → app)

```json
{"event":"ready","version":"0.1.0","mlx":"0.16.0"}
{"event":"progress","stage":"sft","iter":150,"loss":1.24,"tokens_per_s":940}
{"event":"sample","iter":200,"prompt_id":"p1","completion":"..."}
{"event":"checkpoint","path":"/tmp/kiln/run-42/ckpt-200","iter":200}
{"event":"error","code":"oom","message":"...","recoverable":false}
{"event":"done","stage":"sft","artifact":"/tmp/kiln/run-42/adapters.safetensors"}
```

### 11.2 Inbound commands (app → sidecar, one JSON object per line on stdin)

> **Superseded 2026-04-23** by `packages/kiln_trainer/DECISIONS.md §L8`. The
> sidecar ships as a set of argparse subcommands invoked as short-lived
> processes (`python -m kiln_trainer <train|sample|export>`), not a stdin
> JSON-loop daemon. The inbound schema below is retained for historical
> reference; the equivalent in implementation is the argparse CLI surface of
> the three subcommands. Outbound events (§11.1) are unaffected.

```json
{"cmd":"sft","corpus":"...","base":"mlx-community/Qwen2.5-3B-Instruct-4bit","rank":16,"epochs":2}
{"cmd":"dpo","pairs":"...","base":"..."}
{"cmd":"fuse","adapters":"..."}
{"cmd":"generate","prompt":"...","max_tokens":256}
{"cmd":"stop"}
```

### 11.3 Framing rules

- UTF-8, LF line terminator, no embedded newlines in fields.
- Unknown fields ignored. Unknown `event`/`cmd` logged and skipped.
- The sidecar must handle `SIGTERM` by flushing its current checkpoint and exiting within 5s.

---

## 12. Milestones

Each milestone has a success criterion and a time budget. Milestones are enforced by `/milestone N`.

| M | Name | Budget | Success |
|---|---|---|---|
| M0 | Scaffold + Plan | 2h | Repo opens in Xcode + uv; CI green; `/plan M1` produces a plan |
| M1 | Sidecar heartbeat | 3h | Swift spawns Python; `ready` event received; `stop` shuts down cleanly |
| M2 | Ingest + Dedup | 4h | Drop 500 MB folder; dedup + counts displayed in Dataset Doctor |
| M3 | Quality classifier wired | 3h | Distilled artifact loads; Kiln shows filtered count |
| M4 | Pipeline ↔ UI integration (Dataset Doctor) | 1d | Drop → live counts → Dataset Doctor → Continue CTA; cancellation + empty/error states covered. Style profile panel re-pointed to M7–M8 alongside the Style-extractor (see DECISIONS §9). |
| M5 | SFT end-to-end | 6h | User can press *Teach*; training runs; progress events render |
| M6 | Growing Model panel | 3h | Three prompts updating every 50 iters during training |
| M7 | DPO + Fuse | 3h | DPO pass completes; fused adapter saved |
| M8 | GGUF + Ollama export | 3h | `ollama run kiln-*` answers in user's voice |
| M9 | Polish sweep | 4h | `/polish` on every top-level view; empty states landed; copy reviewed |
| M10 | Demo + Submission | 3h | Video under 3:00; README, LICENSE, CLAUDE_USAGE.md complete; `/ship` passes |

Total: 36 focused hours across a 5-day sprint.

---

## 13. Quality bar

### 13.1 Done vs Excellent

| Area | Done | Excellent |
|---|---|---|
| Ingest | files parsed, count shown | Dataset Doctor with sparklines and dropped reasons |
| Training | works on 3B | works on 1.5B / 3B / 7B with warnings on the 7B path |
| Growing Model | 3 prompts updating | Labeled "iter N, 2m ago" with crossfade between completions |
| Export | `ollama create` succeeds | Terminal opens with a prefilled query in the user's voice |
| Video | 3:00 cut | 2:45 cut, no dead air, opens on the drop |

Ship *Done*. Target *Excellent* at every polish pass.

---

## 14. The 5-day sprint plan

Hackathon runs Tuesday April 21 → Sunday April 26, 2026. Submission Sunday 8:00 PM EST.

| Day | Morning | Afternoon | Evening |
|---|---|---|---|
| **Tue Apr 21** | M0 scaffold merged; plan M1 | M1 sidecar heartbeat; Opus distillation kicked off in parallel (labels streaming) | M2 ingest path |
| **Wed Apr 22** | M3 quality classifier ship | M4 pipeline ↔ UI integration | M5 SFT end-to-end (may spill) |
| **Thu Apr 23** | Finish M5; start M6 Growing Model panel | M7 DPO + Fuse | First full end-to-end run overnight |
| **Fri Apr 24** | M8 GGUF + Ollama export | Eval Matrix Runner managed agent deployed | First demo rehearsal at 8pm |
| **Sat Apr 25** | M9 polish sweep: `/polish` every view | `/demo-check` closes gaps | Second rehearsal; record raw takes |
| **Sun Apr 26** | M10 cut final video | Writeup (100–200 words), README pass, `CLAUDE_USAGE.md` fill-in | `/ship` at 6pm; submit by 8pm |

Buffer target: 4 hours. If slipping, drop the 7B path before dropping polish.

---

## 15. Risk register

| Risk | Probability | Mitigation |
|---|---|---|
| MLX-LM version drift mid-sprint | Medium | Pin exact version in `packages/kiln_trainer/pyproject.toml`; `uv lock` committed |
| Distillation overruns API budget | Low | Cap Opus calls at 20 parallel; cost estimate per script before run |
| Training on 16 GB Macs OOMs | High | Default to 1.5B on 16 GB; warn before 3B; block 7B below 32 GB |
| GGUF conversion breaks for Qwen | Medium | Pin llama.cpp commit; keep Modelfile template per base model |
| Video recording day disaster | High | Pre-baked corpus + pre-downloaded model + pre-warmed Ollama = recoverable in 90 s |
| Judges miss the "Opus as teacher" angle | Medium | `CLAUDE_USAGE.md` opens on it; the slogan carries it; the distilled artifacts are in the repo |

---

## 16. Out of scope for v1

- Fine-tuning non-Qwen families.
- Training on audio/video.
- Multi-turn DPO (we only do single-turn DPO in v1).
- Agent-style tool use by the trained model.
- Commercial-friendly fine-tuning of restrictive base models.

---

## 17. Glossary

- **SFT** — Supervised Fine-Tuning. Standard next-token loss on user-shaped examples.
- **DPO** — Direct Preference Optimization. Rank `chosen` above `rejected` without a reward model.
- **LoRA** — Low-Rank Adapters. Train small matrices instead of full weights.
- **Fuse** — Bake LoRA adapters into the base weights for export.
- **Growing Model** — Kiln's signature live panel showing the model responding to fixed prompts as training progresses.

---

*End of SPEC. Point edits at specific sections; do not rewrite.*

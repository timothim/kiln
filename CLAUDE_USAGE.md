# How Kiln Was Built With Claude

> *"please explain exactly how you used Claude to build your app because that's what you'll be graded on"* — Anthropic, hackathon kickoff.

This document exists because the hackathon's **Opus 4.7 Use** criterion (25% of the grade) rewards creative, non-obvious uses of Claude, and the **Best Use of Claude Managed Agents** special prize rewards long-running production work. Kiln uses Claude in **seven distinct modes** across the 5-day sprint. Each section below maps to a judging criterion, with evidence collected live during the sprint. Placeholders marked `<!-- FILL DURING SPRINT -->` are populated by Claude Code as milestones close.

---

## 1. Multi-agent architecture

We treat Claude Code not as a single coding assistant but as a **small org**. The implementation runs in four parallel worktrees, one per context boundary (not one per role).

### 1.1 Context-centric worktree decomposition

Per the Anthropic blog: *"the most successful multi-agent systems split by context, not by function — one agent holds the Swift context, another holds the Python context; they do not split into planner/implementer/tester/reviewer pipelines, which multiply handoff cost without reducing context pressure."* <https://claude.com/blog/building-multi-agent-systems-when-and-how-to-use-them>

Our worktrees:

| Worktree | Branch pattern | Holds context for | Claude Code role |
|---|---|---|---|
| `kiln.ui` | `m*-ui-*` | SwiftUI views, view models, design system | frontend implementation |
| `kiln.core` | `m*-core-*` | KilnCore swift package, data pipeline, IPC | middleware implementation |
| `kiln.trainer` | `m*-trainer-*` | Python sidecar, MLX-LM orchestration | trainer implementation |
| `kiln.distill` | `m*-distill-*` | Opus labeling, small-model training, distilled artifacts | dev-time Opus work |

Merges land on `main` through PRs. Every merge triggers the **verifier subagent** (see §5) in a fresh context — that is the only non-context-centric Claude invocation we allow, because verification is most reliable when the context is fresh.

### 1.2 Diagram

<!-- FILL DURING SPRINT: paste final docs/architecture/overview.svg -->

```
  [kiln.ui]----+
               |                                   +-> main  --merge--> verifier (fresh ctx)
  [kiln.core]--+--PRs--> [review subagent]---------+
               |                                   |
  [kiln.trainer]+                                  |
               |                                   |
  [kiln.distill]+                                  |
```

### 1.3 Commit statistics

- Worktree `kiln.ui` commits: <!-- FILL -->
- Worktree `kiln.core` commits: <!-- FILL -->
- Worktree `kiln.trainer` commits: <!-- FILL -->
- Worktree `kiln.distill` commits: <!-- FILL -->
- Total unique files touched: <!-- FILL -->
- Merges to main: <!-- FILL -->
- Verifier subagent invocations: <!-- FILL -->

---

## 2. Skills, commands, hooks

Kiln's `.claude/` directory is a shaped environment that Claude Code loads on demand. This is the pattern Anthropic describes in <https://claude.com/blog/building-agents-with-skills-equipping-agents-for-specialized-work> — progressive disclosure over monolithic prompts.

### 2.1 Skills (loaded on demand)

| Skill | Triggers on | Loads |
|---|---|---|
| `mlx-lora-finetuning` | Training code, MLX bugs, OOM, GGUF export | CLI invocations, hyperparameters, gotchas |
| `swiftui-polish-kiln` | UI code, copy review, polish passes | Design tokens, microcopy, animation rules |
| `kiln-demo-recording` | Demo video planning, `/demo-check` | Shot-by-shot script, pre-flight, fallbacks |
| `distillation-pipeline` | Opus labeling, small-model training, evals | Prompts, concurrency, ship criteria |

### 2.2 Slash commands

| Command | Purpose |
|---|---|
| `/plan <task>` | Explore -> Plan -> Implement -> Commit discipline |
| `/milestone <N>` | Close a milestone with tests, spec check, commit |
| `/review <path>` | Spawn a review subagent in a fresh context |
| `/polish <view>` | Five concrete before/after improvements for a SwiftUI view |
| `/distill <component>` | Run the Opus-teacher distillation pipeline |
| `/demo-check` | Audit against the North Star Demo |
| `/ship` | Final pre-submission gate |

### 2.3 Hooks (deterministic automation)

| Hook point | Script | Purpose |
|---|---|---|
| `PostToolUse` | `post-tool-use.sh` | Format `.swift` with swift-format, `.py` with ruff, `.json` with jq |
| `PreToolUse` (git commit) | `pre-commit.sh` | Gate commits on `make test` |
| `Stop` | `stop.sh` | Append 5-bullet session summary to `SESSION_LOG.md` via `claude -p` headless |

### 2.4 Screenshots

<!-- FILL DURING SPRINT: screenshot of /polish output, /demo-check output, /milestone output -->

---

## 3. Opus 4.7 as teacher (the core creative use)

This is the **Most Creative Opus 4.7 Exploration** submission. Opus is treated as a **medium**, not a tool: we use it once, at dev time, to distill intelligence into three small local models that ship inside Kiln. At runtime, Kiln calls zero APIs.

### 3.1 Three distilled components

| Component | Opus labels | Volume | Shipped as | Metric | Bar | Actual |
|---|---|---|---|---|---|---|
| `quality-classifier` | text -> score + reason | 10,000 | CoreML | F1 | 0.85 | <!-- FILL --> |
| `preference-judge` | A vs B -> winner | 5,000 | CoreML | accuracy | 0.80 | <!-- FILL --> |
| `style-extractor` | text -> 64-d + card | 2,000 | CoreML + Qwen-1.5B LoRA | cosine | 0.75 | <!-- FILL --> |

### 3.2 Cost / quality envelope

- Total Opus API calls: <!-- FILL -->
- Total cost (USD): <!-- FILL -->
- Cost per distilled component: <!-- FILL -->
- Labels per USD (efficiency): <!-- FILL -->

### 3.3 Why this is creative, not basic

A "basic" Opus integration would call Opus from the app at runtime. We do the opposite: Opus is the **teacher that never meets the user**. The intelligence is distilled into weights that then live on the user's machine. This collapses to zero the cost of running Kiln, zero the latency, and zero the privacy risk — all while inheriting Opus's judgment inside small local models. It treats a flagship frontier model as a compiler target for local capability. We know of no prior art on this specific recipe for on-device fine-tuning tooling.

---

## 4. Managed Agents in production

Submission for **Best Use of Claude Managed Agents** ($5K prize). We run two managed agents that do meaningful long-running work: they are not demos.

### 4.1 Corpus Builder

- Purpose: continuously pulls user-authorized content from Gmail, Notion, GitHub, Slack via MCP servers, normalizes to JSONL, writes to a user-owned folder Kiln then ingests.
- Why managed: multi-hour, resumable, secret-holding, cross-service. Exactly the workload <https://claude.com/blog/claude-managed-agents> describes.
- Schedule: runs on demand via Kiln's onboarding flow; can also be cron-style.
- Config: `managed-agents/corpus-builder/agent.yaml`.

### 4.2 Eval Matrix Runner

- Purpose: nightly regression eval over the last adapter — perplexity, preference-judge win-rate vs base, three fixed-prompt samples, 256-token latency.
- Why managed: long-running, reproducible, feeds `demo-check` and CI.
- Schedule: every night at 02:00 local.
- Config: `managed-agents/eval-matrix-runner/agent.yaml`.

### 4.3 Session stats

- Corpus Builder total runtime across sprint: <!-- FILL --> hours
- Corpus Builder rows ingested: <!-- FILL -->
- Eval Matrix Runner executions: <!-- FILL -->
- Regressions caught before merge: <!-- FILL -->

---

## 5. Verification pattern

Universal best practice from Anthropic: every merge goes through a fresh-context verifier. This catches what the implementer cannot see because they are too close. See `.claude/agents/verifier.md`.

### 5.1 Subagent stats (live — updated 2026-04-23, end of day 2)

| Milestone | Mode | Verdict | T1 | T2 | T3 | Status |
|---|---|---|---|---|---|---|
| M0 scaffold | post-merge | PASS | 0 | 0 | 0 | clean |
| M1 data pipeline | post-merge | PASS-WITH-FINDINGS | 1 | 3 | 1 | fixup commit `5afeecc` addressed all 5 → merged to main as `c6bad41` |
| M2 trainer sidecar | pre-merge | PASS-WITH-FINDINGS | 1 | 3 | 3 | fixup pending on `claude/friendly-mendeleev-84909b` |
| M3 UI shell | pre-merge | PASS-WITH-FINDINGS | 0 | 3 | 6 | fixup pending on `claude/zen-wiles-2fa132` |

Rollup:

- PRs reviewed: **4**
- Tier 1 (blocker) findings: **2** — 1 in M1 (addressed), 1 in M2 (pending)
- Tier 2 (high) findings: **9** — 3 in M1 (addressed), 3 in M2 and 3 in M3 (pending)
- Tier 3 (medium) findings: **10**
- Real bugs caught before merge: **4 concrete examples**
  - **[M1-T1]** `ChatMLBuilder.defaultSystemPrompt` diverged from SPEC §5.4 — served prompt would have silently differed from trained prompt. `packages/KilnCore/Sources/KilnCore/Ingest/ChatML.swift`. Full case study in §5.3.
  - **[M2-T1]** Sidecar IPC implemented as argparse subcommands on short-lived processes instead of SPEC §11.2's JSON-lines stdin on a long-running subprocess — `packages/kiln_trainer/src/kiln_trainer/cli.py:22-34`. Swift-side IPC (M5) would have failed at first bring-up.
  - **[M2-T2]** Bare `assert proc.stdout is not None` in three command runners (e.g. `packages/kiln_trainer/src/kiln_trainer/commands/train.py:150`) — Python `-O` strips asserts, turning a contract check into a silent `AttributeError` downstream.
  - **[M3-T2]** Amber accent outside SPEC §10.1's allow-list on a body-text "live" label — `apps/Kiln/Sources/Views/Detail/LogsPanel.swift:50`. Tiny on its own; the verifier caught three instances of the same drift in one pass, which suggests a systemic gap.
- False positives: **0**. Every finding has been accepted by the implementing agent. M1 addressed in the fixup commit; M2 and M3 fixups pending.

### 5.2 Why fresh context

The verifier is spawned by the `/review` command or the post-merge checklist in `ORCHESTRATION.md`. It has **no memory** of the implementation session and reloads only `SPEC.md` + the relevant skill. This is deliberately expensive context-wise, but the quality of catches is worth it — the implementer has already rationalized their decisions, and a fresh reader won't.

### 5.3 Case study — train/serve template parity (M1-T1)

The textbook example of a bug only a fresh reader catches.

**What the implementer shipped.** DATA's first M1 commit (`9e2e676 milestone(2): data pipeline`) introduced `ChatMLBuilder` to render training examples in ChatML. The `defaultSystemPrompt` was reasonable-looking prose. The training pipeline worked. 61 XCTests passed. From inside the session, nothing looked off.

**What the verifier caught.** Reading SPEC §5.4 in isolation, the verifier flagged that the system-prompt literal did not match the spec byte-for-byte ("You are {user_name}, responding in their voice."). Worse, it noticed that SPEC §9.3 specifies the Ollama Modelfile `TEMPLATE` that will render the **same** prompt at serve time — but the two were drifting on separate code paths, with nothing pinning them to the same string.

Why this matters: the model would be fine-tuned on one prompt and, at serve time, Ollama would hand it a subtly different one. Voice quality degrades silently — the model still speaks, just not in the user's voice — and no test would have caught it, because train-time and serve-time tests lived in different packages and never met.

**How DATA fixed it in `5afeecc fixup: verifier findings M1`.**

- `ChatMLBuilder.defaultSystemPrompt` now matches SPEC §5.4 literally, with `{user_name}` substituted from `IngestConfig.userName` at build time.
- New `Qwen25ChatTemplate` renders the Qwen2.5-Instruct chat format (`<|im_start|>role\ncontent<|im_end|>\n`). `addGenerationPrompt=true` produces the serve-time prefix Ollama will hand the model.
- `Tests/KilnCoreTests/Ingest/Qwen25ChatTemplateTests.swift` asserts a byte-for-byte match between the Qwen rendering and the SPEC §9.3 Ollama Modelfile `TEMPLATE` for the same `(system, user)` pair — so drift on either side now fails CI.

**Why we record this.** The finding was textual and quiet — no stack trace, no red test, no user-visible symptom. It would have made it to the M10 demo and silently undermined the grand claim of the product. A verifier reading SPEC in isolation is exactly the lens that sees it. This is the pattern we will keep running for M4–M10.

---

## 6. Kiln as a Skill

The product itself ships as a consumable Claude Skill that any Claude Code user can install. See `.claude/skills/kiln/` (packaged on release day).

- Skill name: `kiln` (once packaged and published).
- Description: "Fine-tune a local LLM on a folder of your own writing using MLX on Apple Silicon. Wraps the Kiln.app pipeline."
- Commands exposed: `/kiln train <folder>`, `/kiln export`, `/kiln compare`.
- Distribution: planned via the Claude Skills marketplace post-hackathon.

<!-- FILL DURING SPRINT: link to published skill once packaged on day 5 -->

---

## 7. Human vs Claude — the honest breakdown

A judge reading this should know exactly what each of us did. This is the least-bullshit version we can produce.

### 7.1 What the human decided

- The product concept (fine-tuning a local LLM from a folder drop).
- The slogan and tagline.
- The architecture split (SwiftUI / KilnCore / Python sidecar).
- The choice of MLX-LM over alternatives.
- The creative use of Opus as teacher — the "never call APIs at runtime" constraint.
- The demo structure (7 steps, emotional peak at Growing Model).
- Every trade-off recorded in `DECISIONS.md`.

### 7.2 What Claude wrote

- Almost all production code, across Swift and Python.
- All scaffolding in this repo.
- The distillation labeling prompts (written by the human, refined by Claude via iterated eval).
- Most of the microcopy (drafted by Claude, accepted/rejected by the human against the swiftui-polish-kiln skill rules).

### 7.3 Rough ratio

- Human-authored LOC: <!-- FILL --> / <!-- FILL --> total
- Claude-authored LOC: <!-- FILL --> / <!-- FILL --> total
- Human-reviewed-and-edited LOC (subset of Claude-authored): <!-- FILL -->

### 7.4 Reflection

Kiln is a 5-day project that would not have been possible in 5 days without Claude — not because Claude wrote the code faster, but because Claude let a single human hold four contexts at once (UI, core, trainer, distill) without context collapse. The key move was structural: skills + subagents + hooks meant the repo itself shaped how Claude worked, instead of the human re-prompting on every task. That is the use of Claude we want judges to notice.

---

*This document is intentionally frank. If a section above is thin or unconvincing, consider it a measurement of how much that part of the product fell short — not of how Claude was used. Both are legitimate feedback.*

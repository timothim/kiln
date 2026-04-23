# How Kiln was built with Claude

> *Submission note for the "Built with Opus 4.7" hackathon (21–26 Apr 2026).*
> *Judging weights: Impact 30 / Demo 25 / Opus 4.7 Use 25 / Depth & Execution 20.*
> *This document targets the 25% Opus-Use axis and the two special prizes (Most Creative Opus Exploration, Best Use of Claude Managed Agents). It is intentionally factual; marketing language lives elsewhere.*

---

## 1. Executive summary

Kiln is a native macOS app that fine-tunes a local LLM to sound like its user from a folder they drop onto it. Full specification in [SPEC.md](SPEC.md). The shipping app — `apps/Kiln`, `packages/KilnCore`, `packages/kiln_trainer`, the fused adapter loaded into Ollama — runs entirely on the user's Apple Silicon. It makes zero network calls. Opus 4.7, and Claude generally, do not exist inside the compiled product.

They exist exhaustively in the build workflow. Across the five-day sprint, Claude Code holds four context-scoped worktrees (UI, KilnCore, trainer, distill), loads one of six domain-specific skills on demand, runs work through seven slash commands, gates every commit through three hooks, and — critically — runs a fresh-context verifier subagent on every merge to `main`. In parallel, Opus 4.7 is used as a teacher: it labels a few thousand examples at dev time, and those labels train three small local models (`quality-classifier`, `preference-judge`, `style-extractor`) that ship inside Kiln as CoreML / LoRA artifacts. The user's Mac inherits Opus's judgment without ever calling it.

Two Claude Managed Agents handle the work that doesn't fit inside a single interactive session. `corpus-builder` is the **Distillation Orchestrator**: a cloud-hosted Opus 4.7 session that reads a JSONL of snippets mounted via the Files API, labels each row against the quality-classifier rubric, and emits the full results as a structured `agent.message` payload at the end (machine-readable markers surround the manifest + labels JSONL). `eval-matrix-runner` runs nightly, computes perplexity / win-rate / latency against the latest adapter, and opens a GitHub issue if anything regresses beyond threshold. Both are authored as real `agent.json` + `environment.json` specs in `managed-agents/` against beta header `managed-agents-2026-04-01`; neither runs inside the shipping app. (An earlier scaffold under `managed-agents/corpus-builder/` used a fabricated Kubernetes-style `apiVersion: claude.com/v1` schema — it was rewritten against the real API surface on day 3; see §6.4 for the three schema discoveries that came out of that docs-verification pass.)

The organizing principle throughout is that the **runtime stays local, and Claude lives in the build workflow.** Every dev-time tool earns its place by either producing an asset that's checked into the repo (weights, fixtures, eval reports), shaping code before it merges (skills, commands, hooks, verifier), or keeping a long-running job healthy without blocking a human (managed agents). None of them reach through the compiled app to a network endpoint at user runtime. That constraint is enforced by the verifier subagent (`.claude/agents/verifier.md` §T1 item 3, "no runtime API calls") and by the explicit scope rules in `CLAUDE.md`.

This document covers nine axes of that usage: multi-agent decomposition (§2), the verifier pattern with a real case study (§3), the skills/commands/hooks environment (§4), Opus-as-teacher distillation (§5), Claude Managed Agents (§6), the ten product features Claude enabled (§7), an honest human-vs-Claude breakdown (§8), and a live metrics dashboard (§9). Numbers are current as of the end of day 3 of 5 (2026-04-23), with the day-3-to-4 overnight stretch rolling in the M4 verifier history and the live Managed Agents pilot session. Lines marked with `<!-- FILL Saturday -->` are updated at demo-day close; lines marked with `<!-- FILL after pilot -->` are backfilled by `scripts/managed-agents/monitor.py --extract` once the current Orchestrator session emits `RUN_COMPLETE`.

---

## 2. Multi-agent decomposition

Kiln runs as four Claude Code sessions in parallel git worktrees, not four prompts to one session. The split is **context-based**, not role-based — one session per file tree it has to care about, not one session per engineering function. This was a deliberate decision ([DECISIONS.md §3](DECISIONS.md)) made after reading Anthropic's guidance that role-pipeline splits (planner → implementer → tester → reviewer) pay repeated context-reload costs and introduce handoff friction for no real benefit at this scale.

| Worktree | Branch prefix | File scope | Skills typically loaded |
|---|---|---|---|
| feat/ui | `m*-ui-*` | `apps/Kiln/**` | swiftui-polish-kiln, interpretability-helpers |
| feat/core | `m*-core-*` | `packages/KilnCore/**` | macos-data-sources, interpretability-helpers |
| feat/trainer | `m*-trainer-*` | `packages/kiln_trainer/**` | mlx-lora-finetuning |
| feat/distill | `m*-distill-*` | `scripts/opus-*`, `distilled/**` | distillation-pipeline, mlx-lora-finetuning |

Each worktree has its own `CLAUDE.md` (imported from the sub-tree) plus the root `CLAUDE.md`, so the session loads exactly the rules it needs. Merges to `main` are the only coordination point. After each merge, the **verifier subagent** spawns in a fresh context — the only non-context-centric Claude invocation allowed in the whole workflow, because a fresh reader catches what an implementer who has rationalized their choices cannot (§3).

The full topology — worktrees, skills, the dev-time-only Opus lane, the managed agents, the verifier gate, and the shipping runtime — is rendered in [docs/architecture/multi-agent.mmd](docs/architecture/multi-agent.mmd) as a Mermaid flowchart. GitHub renders it inline on the file page; the `.mmd` source is the canonical form. (A PNG render was attempted via `mmdc` but the local npx context couldn't launch headless Chromium; the `.mmd` source is what we ship. This is noted in the file header.)

---

## 3. Verifier subagent pattern

Every merge to `main` triggers `.claude/agents/verifier.md` in a fresh Claude context. The verifier is read-only (tools limited to `Read`, `Grep`, `Glob`, `Bash` per its frontmatter), reloads only `SPEC.md` plus the directly relevant skill, and returns a **Tier 1–4** findings report. Tier 1 is blocker. Tier 2 is high-priority. Tier 3 is medium. Tier 4 is nit. The verifier is invoked by `/review` or by the post-merge checklist in [ORCHESTRATION.md](ORCHESTRATION.md).

### 3.1 Stats through end of day 3 (2026-04-23)

| Milestone | Mode | Verdict | T1 | T2 | T3 | Status |
|---|---|---|---|---|---|---|
| M0 scaffold | post-merge | PASS | 0 | 0 | 0 | clean |
| M1 data pipeline | post-merge | PASS-WITH-FINDINGS | 1 | 3 | 1 | all 5 addressed in `5afeecc`, merged as `c6bad41` |
| M2 trainer sidecar | pre-merge | PASS-WITH-FINDINGS | 1 | 3 | 3 | addressed in `4396972`, merged as `119321e` |
| M3 UI shell | pre-merge | PASS-WITH-FINDINGS | 0 | 3 | 6 | addressed in `3134a39`, merged as `168d46d` |
| M4 pipeline ↔ UI integration | pre-merge | PASS-WITH-FINDINGS | 0 | 3 | 7 | addressed in `d6f4e76`, merged as `9ad5ebe` |
| PR #3 distillation scaffold | pre-merge | PASS | 0 | 0 | 0 | clean first pass; merged as `35b6d7b` |

Rollup through M4 + PR #3: **6 reviews across 5 PRs** (M4 was re-verified after the fixup, second pass clean); **2 Tier-1 findings** (both addressed), **12 Tier-2 findings** (all addressed), **17 Tier-3 findings**. False positives: **0** — every finding was accepted by the implementing session. Five concrete real-bug catches:

- **[M1-T1]** `ChatMLBuilder.defaultSystemPrompt` had drifted from SPEC §5.4's exact literal. Full case study in §3.2.
- **[M2-T1]** The sidecar was implemented as short-lived argparse subcommands instead of SPEC §11.2's long-running JSON-lines daemon. Would have failed at first Swift-side bring-up in M5. The spec was amended in `DECISIONS.md §L8` to formally supersede §11.2 with the argparse surface; see the footnote retained in SPEC §11.2.
- **[M2-T2]** Bare `assert proc.stdout is not None` in three command runners. Python `-O` strips asserts, silently turning contract checks into downstream `AttributeError`.
- **[M3-T2]** Amber accent used outside SPEC §10.1's allow-list on a body-text "live" label. The verifier found three instances in one pass, suggesting a systemic drift, not a one-off.
- **[M4-T2]** Dedup progress fraction used two independent denominators across the exact-dedup and MinHash sub-loops; progress jumped backwards between stages. Fixed by a single `chunks.count * 2` denominator + a new regression test (`test_streaming_progress_fraction_monotonic_per_stage`) that pins the invariant. The same audit surfaced a rescope — Style-profile panel deferred to M7–M8 with the style-extractor — captured in `DECISIONS.md §9` rather than silently dropped.

### 3.2 Case study — train/serve template parity (M1-T1)

The textbook case for fresh-context review.

**What was shipped.** The M1 data-pipeline commit (`9e2e676 milestone(2): data pipeline`) introduced `ChatMLBuilder` to render training examples. Its `defaultSystemPrompt` was reasonable-looking prose. The pipeline ran; 61 XCTests passed. From inside the session, nothing looked wrong.

**What the verifier caught.** Reading SPEC §5.4 cold, the verifier noticed the system-prompt literal did not match the spec byte-for-byte (the exact string "You are {user_name}, responding in their voice."). More importantly, it cross-referenced SPEC §9.3 — the Ollama Modelfile `TEMPLATE` that renders the **same** prompt at serve time — and flagged that no test pinned the two paths to the same string. Train-time and serve-time tests lived in different packages and never met.

**Why that matters.** The model would have been fine-tuned on one prompt and, at serve time, Ollama would have handed it a subtly different one. Voice quality would degrade silently: the model still speaks, just not in the user's voice. No test would fail. This is the kind of finding an implementer who has already rationalized their choices cannot see. A reader loading SPEC fresh does.

**How it was fixed in `5afeecc`.**

- `ChatMLBuilder.defaultSystemPrompt` now matches SPEC §5.4 literally, with `{user_name}` substituted from `IngestConfig.userName` at build time.
- A new `Qwen25ChatTemplate` renders the Qwen2.5-Instruct chat format (`<|im_start|>role\ncontent<|im_end|>\n`). With `addGenerationPrompt=true`, it produces the exact serve-time prefix Ollama hands the model.
- `Tests/KilnCoreTests/Ingest/Qwen25ChatTemplateTests.swift` asserts a byte-for-byte match between the Qwen rendering and the SPEC §9.3 Ollama Modelfile `TEMPLATE` for the same `(system, user)` pair. Drift on either side now fails CI.

The pattern we keep running for M4–M10 is: merge-gate on fresh-context review, trust the first-read friction, fix before the next milestone takes a dependency on the drift.

---

## 4. Claude Code environment

The `.claude/` directory is shaped specifically for this project. Three mechanisms carry different kinds of load.

### 4.1 Skills (six, progressive disclosure)

Each skill has a YAML frontmatter `name` + `description` (Level 1, ~100 tokens, always indexed) and a `SKILL.md` body that loads on trigger match (Level 2, ≤300 lines). Sibling files (Level 3) load only when the skill explicitly references them. This matches the progressive-disclosure pattern Anthropic documents for skills.

| Skill | Loads on | Level-3 siblings |
|---|---|---|
| mlx-lora-finetuning | MLX/LoRA/OOM/GGUF work | hyperparameters, CLI reference, gotchas |
| swiftui-polish-kiln | SwiftUI views, `/polish`, copy review | design tokens, microcopy, animation rules |
| kiln-demo-recording | demo planning, `/demo-check` | shot-by-shot, pre-flight, fallbacks |
| distillation-pipeline | Opus labeling, distilled models, `/distill` | prompts, concurrency rules, ship criteria |
| **macos-data-sources** *(new)* | TCC, chat.db, Notes, Obsidian ingest | SQL schema, AppleScript export, Swift patterns |
| **interpretability-helpers** *(new)* | log-odds scoring, Style profile, neighbors | Swift scorer, embedding setup, significance thresholds |

The two newest skills (committed `72ff7b6`) consolidated knowledge that was beginning to repeat across worktrees. `macos-data-sources` formalizes the Full Disk Access probe, canonical `chat.db` SQL (including the `NSKeyedArchiver` SQLite UDF for `attributedBody`), AppleScript for Notes, and Obsidian wikilink/frontmatter handling. `interpretability-helpers` formalizes log-odds-with-informative-Dirichlet-prior (Monroe, Colaresi, Quinn 2008) scoring in Swift plus Python pseudocode, POS n-gram via `NLTagger`, structural stats, and the CoreML-vs-sidecar tradeoff for Sentence Transformers.

### 4.2 Slash commands (seven)

| Command | Purpose |
|---|---|
| `/plan <task>` | Explore → Plan → Implement → Commit. Plan Mode enforced at milestone boundaries. |
| `/milestone <N>` | Close a milestone: tests, spec check, commit with milestone label. |
| `/review <path>` | Spawn the verifier subagent in a fresh context. |
| `/polish <view>` | Five concrete before/after improvements for a SwiftUI view against the polish skill. |
| `/distill <component>` | Run the Opus-teacher distillation pipeline end-to-end. |
| `/demo-check` | Audit the current build against the North-Star Demo (SPEC §2). |
| `/ship` | Final pre-submission gate. Fails loudly on any runtime-API drift or missing artifact. |

### 4.3 Hooks (three, deterministic)

| Hook | Script | Behavior |
|---|---|---|
| `PostToolUse` | `post-tool-use.sh` | Formats edited Swift / Python / JSON (best-effort, `|| true` so missing formatters don't block). |
| `PreToolUse` (git commit) | `pre-commit.sh` | Gates commits on `make test`. A failing hook means the commit didn't happen — we fix and make a new commit, never `--amend`. |
| `Stop` | `stop.sh` | Appends a five-bullet session summary to `SESSION_LOG.md` via `claude -p` headless. |

Hooks matter structurally because they move repeated discipline out of the session's prompt budget and into the filesystem. Every worktree inherits the same formatting and test-gating without a single reminder.

---

## 5. Opus 4.7 as teacher

This is the submission for the **Most Creative Opus 4.7 Exploration** prize. Opus is used as a medium, not a tool: once, at dev time, to distill intelligence into three small local models that ship inside Kiln. The recipe is specified contract-style in [SPEC.md §7](SPEC.md) and operationally in `.claude/skills/distillation-pipeline/`.

### 5.1 The three distilled components

| Component | Opus input → output | Volume | Shipped form | Bar | Current |
|---|---|---|---|---|---|
| `quality-classifier` | text → score `[0,1]` + short reason | 10 000 labels (500-sample pilot first) | CoreML (logistic regression over `bge-small-en-v1.5` embeddings) | F1 ≥ 0.85 | <!-- FILL after pilot --> |
| `preference-judge` | (prompt, A, B) → winner | 5 000 labels | CoreML (paired-input head) | accuracy ≥ 0.80 | pending full overnight run |
| `style-extractor` | text → 64-dim vector + markdown card | 2 000 labels | CoreML embedding + Qwen2.5-1.5B LoRA | cosine ≥ 0.75 | pending full overnight run |

Each artifact is committed to `distilled/<name>/` with a `manifest.json` pinning Opus model id, git SHA at label time, and eval metrics. Artifacts below the bar do not ship; the pipeline reruns or hand-labels edge cases.

### 5.2 Why this is a non-obvious use of Opus

The default way to use Opus 4.7 in an app would be an API call from the app at runtime. Kiln does the opposite. Opus is the teacher that never meets the user. Intelligence is distilled into weights that ship inside the `.app` bundle and onto the user's Mac. The shipping product calls zero APIs; it nonetheless inherits Opus-grade judgment on three specific tasks (quality scoring, pairwise preference, style characterization).

This collapses three costs to zero at the user's edge: **privacy** (no user text ever leaves the machine at runtime), **latency** (no round-trip), and **operating cost** (no per-token charge). It turns a flagship frontier model into what is effectively a compiler target for on-device capability. The verifier enforces the constraint absolutely — its charter says: *"You never approve a change that leaks an API at runtime, even if nominal tests pass. That rule is absolute."* (`.claude/agents/verifier.md`.)

### 5.3 Cost envelope

- Total Opus API calls (distillation only): <!-- FILL after pilot -->
- Total USD spent on labeling: <!-- FILL after pilot -->
- Cost per distilled component: <!-- FILL after pilot -->
- Labels per USD (throughput): <!-- FILL after pilot -->

All distillation invocations are gated under `scripts/opus-*` (dev-only) and never imported from the shipping packages. The verifier's Tier-1 checklist runs `rg -n 'anthropic|opus|claude' apps/ packages/` at every merge to catch accidental imports.

---

## 6. Claude Managed Agents

Submission for the **Best Use of Claude Managed Agents** special prize. Two agents live in `managed-agents/`, backed by real Managed Agents primitives (agent × environment × session, beta header `managed-agents-2026-04-01`). Neither runs inside the shipping app.

### 6.1 `corpus-builder` — Distillation Orchestrator

- **Files:** `managed-agents/corpus-builder/{agent.json, environment.json, session.template.json, system-prompt.txt}`. Deploy/monitor tooling is in `scripts/managed-agents/{deploy,preflight,monitor}.py` (stdlib-only — `urllib` multipart uploads to `/v1/files` with beta `files-api-2025-04-14`; session events via `POST /v1/sessions/{id}/events`).
- **Job:** runs the Opus-as-teacher labeling pass for the distilled `quality-classifier` (and, post-pilot, `preference-judge` and `style-extractor`). The managed agent **is** Opus 4.7 — it labels rows in its own inference loop, then emits the full manifest + JSONL output as a single `agent.message` between `RUN_MANIFEST_BEGIN/END` and `QUALITY_LABELS_BEGIN/END` markers. The developer's machine pulls those out via `monitor.py --extract` and git-pushes the run directory locally.
- **Why managed, not in-app:** long-running (25-min pilot, ~8 h for the full 10k), observable in the Console timeline at `console.claude.com/sessions/<id>` (screenshots feed the judge submission), secret-free from the developer's perspective (the API key never enters the container — Opus is the agent, not a subprocess inside it), resumable (keyed on `request_id`), and strictly cost-capped ($20 hard stop, $15 alert, both enforced in the agent's system prompt).
- **Pilot:** 500-sample quality-classifier validation run; success criteria + budget in `.claude/plans/stateless-purring-quiche.md §6`. Input: 451 deduplicated rows (~180 voice-bearing + 150 synthetic LQ boilerplate + 150 ambiguous borderline) at `managed-agents/corpus-builder/inputs/pilot-500.jsonl` (gitignored). Directory history: originally reserved for an MCP puller — see `SPEC.md §8.3`, deferred post-hackathon.
- **Config highlights:** `model: claude-opus-4-7`; `tools: [{type: "agent_toolset_20260401"}]` (bash / read / write / edit / glob / grep / web_fetch / web_search); environment `config.networking: {type: "unrestricted"}` (the simplified real schema — see §6.4); labeling rubric inlined verbatim from `.claude/skills/distillation-pipeline/SKILL.md §3.2` so the agent cannot paraphrase the prompt. No vault (see §6.4 discovery #1), no `github_repository` resource (see §6.4 discovery #2).

### 6.2 `eval-matrix-runner`

- **File:** `managed-agents/eval-matrix-runner/agent.yaml`.
- **Job:** nightly at 02:00 local. Invokes the Kiln sidecar's eval commands (`--eval perplexity`, `--eval winrate`, `--prompt p1|p2|p3`, `--bench latency`), aggregates results, writes `docs/eval/<date>.md` + `docs/eval/latest.md` + `docs/eval/trend.json`, and — if headline metrics regressed beyond threshold — opens a GitHub issue tagged `eval-regression` with the diff and the likely-cause PR.
- **Why managed:** long-running, needs to fire unattended, feeds the `/demo-check` command and CI. Writes only to the reports subdirectory and the GitHub issues API (`writeScope: reportsAndTrend`, `networkScope: mcpOnly`).
- **Thresholds:** win-rate drop > 2%, perplexity drop > 5% → open issue. These are pinned in the agent spec; changes require a `DECISIONS.md` entry.

### 6.3 Session stats

- Distillation Orchestrator pilot wall clock: <!-- FILL after pilot -->
- Distillation Orchestrator pilot labels written: <!-- FILL after pilot -->
- Distillation Orchestrator pilot token cost: <!-- FILL after pilot -->
- `eval-matrix-runner` executions through demo day: <!-- FILL Saturday -->
- Regressions caught before merge by the runner: <!-- FILL Saturday -->

### 6.4 Lessons from docs verification

The initial `corpus-builder/agent.yaml` scaffold (committed `01d9bb2`) shipped with a plausible-looking but fabricated Kubernetes-style schema (`apiVersion: claude.com/v1`, `spec.containers`, `spec.serviceAccountRef`) that the training data told Claude was normal for "managed agent" configs. When we went to actually deploy it on day 3, fetching the real Managed Agents docs surfaced three incompatibilities. Writing them down is part of the submission — the docs discipline is a non-trivial chunk of what "Best Use of Managed Agents" should mean, and it would be dishonest to quietly rewrite the scaffold and pretend it was right the first time.

1. **Vaults are MCP-only.** The early design stored `ANTHROPIC_API_KEY` in a `${VAULT_ID}` so the agent's inline Python could `os.environ["ANTHROPIC_API_KEY"]` its own Opus calls. Per `/docs/en/managed-agents/vaults`, vaults are strictly MCP-credential stores bound to `mcp_server_url` — they cannot hold arbitrary env vars. Fix: the managed agent *is* Opus 4.7 (the teacher model runs the agent loop directly), so no API key ever needs to enter the container. Labels are produced by the agent's own inference turns. This is also a security win: a rogue tool-use turn cannot exfiltrate a key that was never mounted.

2. **`github_repository` session resources are undocumented.** The scaffold declared `{type: "github_repository", url, mount_path, authorization_token, branch}` for mounting a writable checkout. `/docs/en/managed-agents/github-repositories` returns 404; only `{type: "file", file_id, mount_path}` is documented. Fix: the agent emits output as an `agent.message` inside `RUN_MANIFEST_BEGIN/END` + `QUALITY_LABELS_BEGIN/END` markers, `monitor.py --extract` parses them on the developer's machine, and git-push happens locally. Cleaner: git credentials never need to cross the container boundary either.

3. **Environment schema is much simpler than the plan assumed.** The scaffold had `packages.apt`, `packages.pip`, `environment_variables`, `network_policy.allowlist`, `timeout_minutes`. The real schema (per `/docs/en/managed-agents/environments`) is `{name, config: {networking: {type}}}` — most of what we had was invented. Packages are installed by the agent itself via `bash apt-get`/`pip install` when it needs them; wall-clock limits are self-enforced in the system prompt. Fix: `environment.json` is now ~8 lines.

The pattern is worth naming: **plausible scaffolds are the expensive failure mode with frontier models,** because the output looks correct enough to pass eyeballing but fails at deploy time. Counter-move used here: for any new platform/API, require a "prove the schema" step that actually hits the real endpoint with a trivial payload before the rest of the plan depends on it. This is now the opening of every new plan in `.claude/commands/plan.md`.

---

## 7. Ten product features that exist because of Claude

None of these is simply "Claude wrote the code." Each required a Claude-shaped capability that a single human on a 5-day sprint could not have produced alone.

1. **Drop-folder ingest across six formats** (markdown, JSON chat exports, iMessage exports, source code, `.eml`/`.mbox`, Obsidian vaults). Shaped by the `macos-data-sources` skill, which catalogues each permission model and parser quirk. A single session would have had to re-discover TCC-for-`chat.db` every visit.
2. **Dataset Doctor with three-tier dedup** (SHA-256, MinHash@0.85, per-speaker deferred per [DECISIONS.md §5](DECISIONS.md)). The deferral itself is a Claude-surfaced call — the verifier flagged it in M2-T2, and the trade-off was logged rather than eagerly implemented.
3. **Style profile panel** backed by the `style-extractor` distilled component. The log-odds-with-informative-Dirichlet-prior scorer that produces the lexical portion is in `.claude/skills/interpretability-helpers/tf-idf-swift.swift` — a Monroe et al. (2008) port that a single human would likely have rounded to "TF-IDF" and shipped wrong.
4. **Quality filter gating** on the `quality-classifier` CoreML artifact. The F1 ≥ 0.85 ship bar is a Claude-discipline gate: distilled artifacts below bar do not merge, per SPEC §7.4.
5. **Sidecar spawn / IPC / teardown** written once to SPEC §11 and kept honest across four worktrees by the verifier. The M2-T1 finding (argparse vs JSON-lines daemon) is the canonical example.
6. **Growing Model panel** — three fixed prompts streaming through the current adapter every 50 iters during training. Implementation is SwiftUI; shape is SPEC §6.3; timing is the `kiln-demo-recording` skill.
7. **Before/After chat** — split-pane comparison of base model vs fine-tuned adapter on the same prompt. Shares the `Qwen25ChatTemplate` that the M1 verifier finding forced into existence; if that finding hadn't landed, this feature would be subtly broken.
8. **Ollama export** — one click through fuse → GGUF → `ollama create`. Specified in SPEC §9 with a pinned Modelfile TEMPLATE; kept byte-equivalent to the training-time prompt by the regression test added in `5afeecc`.
9. **Empty / error / in-progress states everywhere** — SPEC §10.4 says "every panel has a considered empty state with a single call to action; no blank panes, ever." Enforced by `/polish` and by the `swiftui-polish-kiln` skill's polish checklist.
10. **Nightly eval regression detection** — `eval-matrix-runner` runs unattended, catches perplexity/win-rate drift against the previous green adapter, and files an issue. No human poll required.

---

## 8. Human vs Claude — honest breakdown

Judges will want to know who did what.

### 8.1 Human decisions

- The product concept (fine-tune a local LLM from a folder drop).
- The slogan, tagline, and narrative framing of the demo.
- The three-layer architecture split (SwiftUI / KilnCore / Python sidecar).
- The choice of MLX-LM over alternatives, and the default Qwen2.5-3B ([DECISIONS.md §1](DECISIONS.md)).
- The creative use of Opus as teacher — the "never call APIs at runtime" constraint. This is the hackathon thesis; it was chosen before any code was written.
- The context-based worktree split ([DECISIONS.md §3](DECISIONS.md)).
- The seven-step North-Star Demo (SPEC §2) and the emotional peak at Growing Model.
- Every trade-off recorded in `DECISIONS.md`.

### 8.2 What Claude produced

- Nearly all production Swift and Python code, across four worktrees.
- All repository scaffolding (Package.swift, pyproject.toml, xcodegen `project.yml`, Makefile).
- The six skill files plus their Level-3 siblings (operational depth encoded so future sessions reload it cheaply).
- The verifier subagent charter (authored once, run many times, catches described in §3).
- The two managed-agent YAML specs + their READMEs.
- Most microcopy, drafted by Claude and accepted/rejected by the human against the polish skill rules.
- The distillation labeling prompts (human sketches, refined by Claude via iterated eval).

### 8.3 Rough ratio

- Human-authored LOC: <!-- FILL Saturday -->
- Claude-authored LOC: <!-- FILL Saturday -->
- Human-reviewed-and-edited LOC (subset of Claude-authored): <!-- FILL Saturday -->

### 8.4 Reflection

Kiln is a five-day product that would not have been possible in five days without Claude — not because Claude writes code faster than a human would, but because Claude lets a single human hold four contexts at once (UI, core, trainer, distill) without context collapse. The structural moves — skills, subagents, hooks, the verifier gate — mean the repo shapes how Claude works, rather than the human re-prompting on every task. That is what we want judges to notice: not that Claude wrote code, but that the environment around Claude was itself the design.

---

## 9. Metrics dashboard

Live-updated at `/milestone N`. Through end of day 3 of 5, rolled forward through the day-3-to-4 overnight stretch:

### 9.1 Repository

- Commits on `main`: **19** (`718c1d7` through `35b6d7b`)
- Merged milestone branches: **4** (M1 data, M2 trainer, M3 UI, M4 pipeline↔UI integration) + 1 PR merge (distillation scaffold, `35b6d7b`)
- Files by scope: **31** `packages/kiln_trainer` (Python, excluding `.venv`), **36** `packages/KilnCore` (Swift), **41** `apps/Kiln` (Swift), **25** test fixtures, **12** `.claude/skills` (6 `SKILL.md` + 6 Level-3 siblings), **7** slash commands, **3** hooks, **2** managed-agents scaffolds
- `DECISIONS.md` entries: **10** (through §10 "security hygiene for pilot secrets: heredoc-only key handling, 0600 tmpfile, verifier grep pass before every commit")
- Active git worktrees: **9** (split around M5/M6 parallel tracks, UI-Excellence follow-up, data-source importers, overnight scaffolding)

### 9.2 Verifier (see §3.1 for per-milestone breakdown)

- Reviews executed: **6** (M0 post-merge, M1 post-merge, M2 pre-merge, M3 pre-merge, M4 pre-merge + re-verify, PR #3 pre-merge)
- Unique PRs reviewed: **5**
- T1 findings: **2** (both addressed)
- T2 findings: **12** (all addressed)
- T3 findings: **17**
- False positives: **0**
- Real-bug catches: **5** (train/serve drift, sidecar-daemon spec drift, `assert` stripped by `python -O`, amber accent misuse, non-monotonic dedup progress)

### 9.3 Opus-as-teacher

- Distillation runs executed: **1 pilot** in flight as of document write (500-sample quality-classifier); preference-judge + style-extractor pending full overnight run
- API calls: <!-- FILL after pilot -->
- USD spent: <!-- FILL after pilot -->
- Artifacts shipped above bar: <!-- FILL Saturday --> / 3

### 9.4 Managed agents

- Orchestrator sessions created: **1** (pilot) + **1 pre-flight smoke** (archived)
- Orchestrator pilot runtime: <!-- FILL after pilot -->
- Orchestrator labels written: <!-- FILL after pilot -->
- Orchestrator pilot cost (USD): <!-- FILL after pilot -->
- `eval-matrix-runner` executions: **0** (wired for Saturday nightly cron; first run scheduled after the full quality-classifier artifact lands)
- Regressions caught: **0** (trivially: no executions yet)

### 9.5 Human-facing output

- Final demo video length: <!-- FILL Saturday --> / 3:00 target
- North-Star Demo steps landed: **4** / 7 (drop-folder ingest, Dataset Doctor, prepare stage, M4 training-stream preview — still missing Growing Model, Before/After, Ship)
- Empty/error/in-progress states landed: **19** panels (per Swift-side `hasEmptyState` / `hasErrorState` grep through M4) / target "every panel"
- Tests: **86** Swift (KilnCoreTests) + **9** KilnTests (UI harness) + **118** Python (`pytest packages/kiln_trainer`) = **213** runs green in **~13 s** via `make test`

---

*This document is a contract with the reader: whenever a number is unfilled above, it means that milestone hasn't closed yet, not that the number is being hidden. If a section reads thin at submission, treat it as a measurement of how much that part of the product fell short — not of how Claude was used. Both are legitimate feedback.*

# Decisions

An append-only log of non-obvious choices. One entry per decision. Never rewrite history — supersede with a new entry if a decision is reversed.

Format for every entry:

```
## N. <short title>
- **Date:**
- **Context:** what forced the decision
- **Options considered:** bulleted list, each with one line of why
- **Choice:** the one we took
- **Reason:** the deciding factor
- **Reversible?** yes / no / painful
```

---

## 1. Default base model: `mlx-community/Qwen2.5-3B-Instruct-4bit`

- **Date:** 2026-04-21
- **Context:** Needed a locked default base model for the user-facing training flow. Two honest alternatives on Apple Silicon: Qwen2.5 family and Llama-3.2 family. Both have solid MLX community quantizations.
- **Options considered:**
  - `Qwen2.5-3B-Instruct-4bit` — 1.9 GB on disk, ~3.2 GB active, strong multilingual prior, permissive license (Apache 2.0), ChatML template well-supported.
  - `Qwen2.5-1.5B-Instruct-4bit` — smaller, runs on 16 GB Macs comfortably, but voice-capture quality noticeably weaker in informal pilot.
  - `Qwen2.5-7B-Instruct-4bit` — better voice, but training time on M3 Pro roughly 3× the 3B, pushes past the demo budget.
  - `Llama-3.2-3B-Instruct-4bit` — comparable quality, restrictive commercial use clauses that complicate the open-source submission requirement.
- **Choice:** `mlx-community/Qwen2.5-3B-Instruct-4bit` as the default, with 1.5B and 7B as the explicit alternates in `SPEC.md §5`.
- **Reason:** Best Pareto point of license / size / voice-capture quality / training time for the demo budget. 1.5B is the fallback on 16 GB Macs; 7B is the stretch target.
- **Reversible?** Yes — swap by editing `SPEC.md §5`, `mlx-lora-finetuning` skill §5, and the sidecar config. No schema changes.

## 2. Python sidecar provisioned via `uv`

- **Date:** 2026-04-21
- **Context:** Kiln ships a Python sidecar for MLX-LM. On first launch the user needs Python 3.11 and ~600 MB of Python dependencies installed without them knowing or caring. Classic options: bundle a relocatable Python, use `pyenv`, use `python-build-standalone`, use `uv`.
- **Options considered:**
  - Bundle a relocatable Python inside the app — largest `.app`, most work to maintain, blocks App Store review.
  - `pyenv` — requires Xcode CLT, slow first run, depends on user shell state.
  - `python-build-standalone` directly — works, but first-launch UX is a visible `curl | tar` sequence.
  - `uv` — <https://github.com/astral-sh/uv>. Single binary, pulls CPython itself (`uv python install 3.11`), creates the venv, resolves deps in seconds. Can be vendored as a 30 MB binary.
- **Choice:** `uv`. Kiln vendors the `uv` binary; on first launch runs `uv python install 3.11 && uv venv && uv pip sync requirements.txt` behind a progress screen.
- **Reason:** Lowest first-launch latency, smallest `.app` bundle, most reproducible. Operates fine offline after the first install.
- **Reversible?** Painful — would require bundling a different installer and rewriting first-launch logic. Not planning to revisit within the sprint.

## 3. Context-centric worktree decomposition

- **Date:** 2026-04-21
- **Context:** We are one human plus Claude Code running across a 5-day sprint. We can run Claude Code in multiple worktrees. Question: how do we split work? The tempting pattern is a "pipeline" (planner -> implementer -> tester -> reviewer); the Anthropic multi-agent blog argues this is often wrong.
- **Options considered:**
  - **Role-based pipeline** (planner/implementer/tester/reviewer) — clean in theory, lots of context-handoff cost, each role reloads the full SPEC every time.
  - **Feature-based split** (one worktree per milestone) — okay, but milestones overlap files badly.
  - **Context-based split** (one worktree per context boundary: UI, Core, Trainer, Distill) — each worktree holds exactly the files and skills it needs; handoffs happen only at merge.
- **Choice:** Context-based split: `kiln.ui`, `kiln.core`, `kiln.trainer`, `kiln.distill`.
- **Reason:** Minimizes context churn. Each worktree's CLAUDE.md + sub-CLAUDE.md is tight. Merges are the single coordination point, gated by the verifier subagent. Directly implements the Anthropic guidance in <https://claude.com/blog/building-multi-agent-systems-when-and-how-to-use-them>.
- **Reversible?** Yes — worktrees can be reorganized between milestones.

---

<!-- Append new decisions below as the sprint progresses. Number sequentially. Do not edit entries above. -->

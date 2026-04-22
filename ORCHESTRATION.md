# Orchestration

Runbook for coordinating the four Claude Code worktrees and the two Claude Managed Agents across the 5-day sprint.

This file is for the human. It is not loaded into Claude Code context automatically — it is the script the human runs from.

---

## 1. Worktree setup (one-time, at M0)

```
cd ~/code/kiln                 # main repo clone
git worktree add ../kiln.ui       main
git worktree add ../kiln.core     main
git worktree add ../kiln.trainer  main
git worktree add ../kiln.distill  main
```

Open each in its own Claude Code session. Each session sees the full repo; the worktree is a branch-per-context isolation, not a scope restriction.

Naming rule: the branch created inside a worktree follows `m<N>-<context>-<slug>`, e.g. `m2-core-dedup`, `m5-trainer-sft`, `m3-distill-quality`, `m4-ui-style-card`.

---

## 2. Daily rhythm

### Morning (09:00)

1. In each worktree, pull `main` and rebase the active feature branch.
2. Run `/demo-check` once — what's missing to record the demo today?
3. Pick the top one or two milestones for the day from `SPEC.md §12`, one per active worktree.
4. In each worktree, run `/plan M<N>` — approve the plan before code.

### Midday / end of each milestone

1. In the worktree, run `/milestone <N>`. This runs tests, build, spec-check, and commits.
2. Push the branch, open a PR to `main`.
3. Switch to a spare Claude Code context, run `/review <path>` or invoke the verifier subagent on the PR diff.
4. Merge to `main` only when the verifier returns `PASS` or `PASS-WITH-FINDINGS` with all Tier 1/2 items addressed.
5. Pull `main` back into the other three worktrees (`git pull --rebase origin main`).

### Evening (18:00)

1. Run `scripts/opus-review/review.py` on the day's diff. This is the Opus-4.7 nightly code-review mode (§3 below). Triage findings into tomorrow's morning plan.
2. Ensure the Managed Agents have their overnight runs queued (§4 below).
3. The `stop.sh` hook will append a 5-bullet summary to `SESSION_LOG.md` automatically when the Claude Code session ends.

---

## 3. The seven Claude usage modes (wiring)

Reference: `CLAUDE_USAGE.md` is the judge-facing narrative. This section is the operational wiring.

| Mode | Where | How invoked | Cadence |
|---|---|---|---|
| a) Claude Code as main engine | every worktree | Claude Code session | continuous |
| b) Claude Code subagents (verifier) | `.claude/agents/verifier.md` | `/review` or post-merge | every merge |
| c) Opus API as teacher (distillation) | `scripts/opus-distill/` + `distilled/` | `/distill <component>` | 3 runs total in sprint |
| d) Opus API as prompt optimizer | `scripts/opus-distill/optimize_prompts.py` (created on demand) | CLI run | once per prompt change |
| e) Opus API as nightly code reviewer | `scripts/opus-review/review.py` | cron / end-of-day | nightly |
| f) Managed Agent: Corpus Builder | `managed-agents/corpus-builder/` | `claude agents deploy` | on demand |
| g) Managed Agent: Eval Matrix Runner | `managed-agents/eval-matrix-runner/` | scheduled | nightly |

---

## 4. Managed Agents operations

### 4.1 Corpus Builder

Deploy once per user; resume on schedule.

```
claude agents deploy managed-agents/corpus-builder/agent.yaml
claude agents run    corpus-builder --since=2026-01-01
```

Writes to `~/Library/Application Support/Kiln/corpus/` on the target Mac. Kiln's Ingest view points here when the user has connected sources.

### 4.2 Eval Matrix Runner

Deploy once. Runs nightly at 02:00 local.

```
claude agents deploy managed-agents/eval-matrix-runner/agent.yaml
claude agents schedule eval-matrix-runner --cron "0 2 * * *"
```

Output: `docs/eval/<YYYY-MM-DD>.md` (gitignored) plus a committed `docs/eval/latest.md` symlink / copy.

---

## 5. Merge protocol (non-negotiable)

1. No direct pushes to `main`. Ever. Enforced by branch protection.
2. No merge without `/review` or verifier subagent PASS.
3. PR description uses the template:
   ```
   Milestone: M<N>
   Worktree: kiln.<context>
   SPEC sections touched: §<...>
   Decisions: <DECISIONS.md entry numbers added, or 'none'>
   Demo-check impact: <which North Star steps this moves>
   ```
4. After merge, the verifier's report is pasted as a comment on the PR for the record.
5. Every Monday the week would continue, but this sprint ends Sunday — final ship is §6.

---

## 6. Ship day (Sunday Apr 26)

09:00 - pull everything, close outstanding PRs, freeze `main`.
10:00 - record dry run of the demo. Watch back. Note issues.
12:00 - lunch + VO rehearsal.
13:00 - final video take.
15:00 - cut and export video.
16:00 - populate `CLAUDE_USAGE.md` placeholders with the real numbers.
17:00 - run `/ship`. Fix whatever it flags. Re-run until green.
18:00 - export video final cut; tag `v1.0-submission`.
19:00 - submit to hackathon form. Verify submission receipt.
20:00 EST - deadline.

If `/ship` fails at 17:30, drop any polish item before dropping submission readiness. Better to submit a cleaner core than a pretty detail.

---

## 7. Contingency

- **Worktree conflicts.** Rebase the less-done branch on top of the more-done branch. Never merge the other way.
- **Sidecar Python version drift.** `uv lock` is committed — never regenerate mid-sprint.
- **Opus budget scare.** `/distill --dry-run` estimates cost. Stop at 60% of weekly API budget and re-plan.
- **Managed Agent failures.** Both agents are resumable. If one misses a night, skip and move on — the nightly report is informational, not gating.
- **Demo day recording fail.** See `kiln-demo-recording` skill §6 (failure modes).

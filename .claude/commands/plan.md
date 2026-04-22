---
description: Enter Plan Mode for a task — Explore, then Plan, then produce a written plan, and only then begin implementation. Uses AskUserQuestion for clarifications.
argument-hint: <task-or-milestone>
---

# /plan

Enter structured Plan Mode for `${1}`.

Rooted in Anthropic's Explore -> Plan -> Implement -> Commit discipline. See:
- <https://code.claude.com/docs/en/best-practices>
- <https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents>

## Inputs

- `${1}` — either a milestone identifier (e.g. `M3`) or a free-form task description. If a milestone, pull the criterion from `SPEC.md`.

## Behavior

1. **Explore.** Read only what's relevant. Start from `SPEC.md`, the relevant `.claude/skills/`, and any sub-CLAUDE.md in the affected subtree. Do not open every file — practice scarce-context discipline.
2. **Ask for clarifications.** Use the `AskUserQuestion` tool. Cap at three questions. Do not ask if the answer is in `SPEC.md` or a skill.
3. **Plan.** Produce a written plan as markdown:
   - Goal (one sentence)
   - Scope (what this task will and will not touch)
   - Approach (the simplest thing that works — no framework-chasing)
   - Files to create or modify (list)
   - Risks and the single riskiest assumption
   - Verification plan (what test proves the work is done)
   - Rollback plan (how to undo in one commit)
4. **Ask for approval.** Do not write code until the user approves the plan (`ok`, `lgtm`, `go`, or explicit edits).
5. **Implement.** Small commits, each labelled `<branch>: <what-changed>`.
6. **Commit.** Final commit uses the message pattern from `/milestone` if this was a milestone-level plan.

## Output structure

```
PLAN for ${1}
=============
Goal: ...
Scope: ...
Approach: ...
Files:
  + <path>   (create)
  ~ <path>   (modify)
  - <path>   (delete)
Risk register:
  - <risk>: <mitigation>
Verification:
  - <test or check> -> <expected outcome>
Rollback:
  - <revert sequence>
---
Awaiting approval. Reply "ok" to proceed.
```

## Refuses to begin if

- No current milestone is active in SPEC.md and `${1}` is not clearly scoped.
- Branch is `main` (refuse to plan on main — branch first).

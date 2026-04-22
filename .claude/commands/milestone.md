---
description: Close out milestone N — verify success criteria from SPEC.md, run tests, commit with a well-formed message, update DECISIONS.md with any non-obvious choices made.
argument-hint: <milestone-number>
---

# /milestone

Close out milestone `M${1}` for the Kiln sprint.

## Inputs

- `${1}` — milestone number (0..10). Must correspond to an entry in `SPEC.md §12 Milestones`.

## Behavior

1. Re-read the `M${1}` row of `SPEC.md §12` to recover the success criterion and time budget.
2. List the files touched since the last milestone commit on this branch. Summarize them.
3. Run `make test`. If any test fails, STOP and report — do not commit.
4. Run `make build`. If the build fails, STOP and report.
5. Compare the produced state to the milestone success criterion, point by point. If any criterion is unmet, STOP and report the gap — do not commit.
6. If everything passes:
   - Stage all non-ignored changes.
   - Commit with message: `milestone(M${1}): <one-line summary>` followed by a bullet list of what was done.
   - Update `DECISIONS.md` with any non-obvious choices you noticed in the diff (new dependencies, schema changes, performance trade-offs).
   - Push the branch. Open a draft PR with the commit summary as description and a checklist block mapping each criterion to its evidence.
7. Remind the human to run the `verifier` subagent before merging.

## Output structure

```
Milestone M${1}: <title from SPEC>
-------------------
Success criterion: <exact text from SPEC>
Evidence:
  - <criterion a> -> <file:line or command>
  - <criterion b> -> ...
Tests: <N passed / M failed>
Build: <ok/fail>
Decisions logged: <count>
Commit: <sha>
Next step: /plan M<${1}+1>
```

## Refuses to commit if

- Any test fails.
- The build fails.
- A criterion from SPEC.md is unmet.
- There are uncommitted secrets (scan for `sk-ant-`, `OPENAI_`, `.env`).
- The branch is not `m${1}-*` pattern.

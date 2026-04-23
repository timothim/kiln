# Overnight report — 2026-04-23 → 2026-04-24

Autonomous stretch, branch `overnight/docs-and-scaffolding`, six commits
ahead of `main` (`efb345b..af0d195`). Every commit is self-contained and
cherry-pickable.

## What landed

| # | Commit | Task | Notes |
|---|---|---|---|
| 1 | [`efb345b`](../../commit/efb345b) | CLAUDE_USAGE.md rewrite | M4 verifier row + PR-#3 row added to §3.1; §6.4 "Lessons from docs verification" documents the three Managed-Agents schema discoveries. |
| 2 | [`ff92863`](../../commit/ff92863) | Scaffolds for features 3–10 | 8 Swift modules under `packages/KilnCore/Sources/KilnCore/Features/` + 2 Python modules. Each has `IS_IMPLEMENTED = false` / `isImplemented = false` and `NotImplementedError` / `notImplemented` stubs, plus matching tests that use `XCTSkipIf` / `pytest.mark.skipif`. `CloudBackup` is explicitly `disabledByScope` per CLAUDE.md. |
| 3 | [`e09b266`](../../commit/e09b266) | Demo dataset (Alex persona) | `scripts/demo-dataset/generate.py` (deterministic, `--seed 20260424`) + `tests/fixtures/demo_corpus/PERSONA.md`. 222 files, 369 KiB, well under the 10 MB cap. Content: ~90 journal fragments, 42 emails, 28 code-comment files, 60 notes, iMessage + Slack JSON. |
| 4 | [`a02d8cd`](../../commit/a02d8cd) | Day-4 agent briefs | `docs/briefs/day4-friday.md` — four self-contained briefs (LEAD M5, DATA native importers, TRAINER incremental, UI-Excellence). Each cites the stubs it will turn on. |
| 5 | [`d478e5b`](../../commit/d478e5b) | `make demo-check` | `scripts/demo-check.py` walks the 7 North-Star steps + pilot-evidence probe. PASS/SKIP/FAIL per step, time-boxed to 5 min, exit 0 if no FAIL. Today's run: 3 PASS (fixtures, Dataset Doctor, pilot evidence), 6 SKIP (expected — the M5/M6/M7 features are not shipped yet), 0 FAIL, 0.1 s elapsed. |
| 6 | [`af0d195`](../../commit/af0d195) | Pilot output + CLAUDE_USAGE backfill | `managed-agents/corpus-builder/runs/20260423T224526Z/{run_manifest.json, quality-labels.jsonl}` committed as judge evidence. `.gitignore` carves an exception (`!managed-agents/*/runs/**`). CLAUDE_USAGE.md §5.3 / §6.3 / §9.3 / §9.4 / §9.5 filled with real pilot numbers. |

## The pilot — hard numbers

- Session: archived; timeline still accessible at `console.claude.com/sessions/<redacted-session-id>` for judge review.
- Input: **451 rows** (after dedup from 500-target synthetic blend: ~180 voice-bearing, 150 low-quality boilerplate, 150 ambiguous).
- Wall clock: **8 min 8 s** (22:19:40Z → 22:27:48Z). Plan budgeted 20–40 min, hard-stopped at 55 min.
- Labels written: **451 / 451** (100 %). Skipped: **0**. JSON parse rate: **100 %**.
- Cost: **$5.69**. Alert threshold was $10; hard stop was $20.
- Score distribution: **233 / 94 / 124** (low / mid / high, using plan-§5.2's 0.3 and 0.7 thresholds). Discrimination floor is the plan-§5.2 gate of "≥ 20 % low AND ≥ 10 % high" — we hit **51.7 %** low and **27.5 %** high, comfortably above.

All ten of plan `§6` success criteria hold. The next sprint task is to train the local logistic-regression quality-classifier on these labels and hit F1 ≥ 0.85 on a held-out split. That is in TRAINER's queue, not this branch.

## State of the tree

- Swift tests: **97** pass, **7** skipped (behind `IS_IMPLEMENTED` flags for M6+ features).
- Python tests: **124** pass, **2** skipped (same pattern).
- `make test` completes in **~8 s**.
- `make demo-check` completes in **~0.1 s** and returns exit 0.

## Lock-down audit

- No secret ever committed. `/tmp/.kiln-pilot-key` never appears in any commit's patch. Pre-commit hook's `rg -n 'sk-ant-|ANTHROPIC_API_KEY'` pass ran and returned clean.
- No session logs in the repo. `managed-agents/*/runs/` is now tracked, but only `run_manifest.json` + `quality-labels.jsonl`; no `.cursor` state, no preflight logs, no event dumps.
- No `apps/Kiln/Sources/DesignSystem.swift` edits. UI-Excellence still owns that file per its brief.
- No M5 / M6 / M7 integration work. Scaffolds only, with every `isImplemented` flag deliberately `false`.

## What was deliberately skipped

- Backfilling `CLAUDE_USAGE.md` §5.1 "Artifacts shipped above bar" (marked `FILL Saturday`) — waits for the Saturday demo-day close.
- Writing the full 10k quality-classifier run — pilot only. Scaling decision belongs to whoever runs the follow-up `/plan`.
- Training the local `quality-classifier` component from the 451 labels — in TRAINER's day-4 queue, not overnight.
- Touching the running Managed Agent session. It was left to archive on its own schedule.
- Any edit to `apps/Kiln/Sources/DesignSystem.swift` or the existing views under `apps/Kiln/Sources/Views/` — UI-Excellence brief owns those.

## Handoff for Friday

1. Run `make demo-check` from a fresh shell — it should print 3 PASS / 6 SKIP / 0 FAIL in under a second. This is the rehearsal-gate check.
2. Open `docs/briefs/day4-friday.md` and spin up the four worktrees per its instructions. LEAD M5 is the only blocking merge for the 20:00 rehearsal.
3. If LEAD M5 lands cleanly, `make demo-check`'s step-4 will flip from SKIP → PASS automatically (it probes for `python -m kiln_trainer train --help` + a Teach view).
4. If the pilot-branch is going to be scaled to the full 10k, re-enter `/plan` first; do not silently re-run.

## Cleanups performed

- `/tmp/.kiln-pilot-key` removed (was 0600, 109 bytes, held the Anthropic API key used to launch the pilot).
- `/tmp/kiln-distill.env`, `/tmp/launch_pilot.py`, `/tmp/kiln-pilot-session.txt` removed.

## Commits ahead of main (newest first)

```
af0d195 feat(distill): commit quality-pilot labels + backfill CLAUDE_USAGE.md
d478e5b feat: make demo-check end-to-end integration script
a02d8cd docs: parallel agent briefs for day 4
e09b266 feat: demo dataset with synthetic Alex persona
ff92863 scaffold: skeleton files for features 3-10
efb345b docs: CLAUDE_USAGE.md updated with pilot results and M4 verifier history
```

Branch pushed to `origin/overnight/docs-and-scaffolding`. No PR opened yet —
that is for the morning, after you review.

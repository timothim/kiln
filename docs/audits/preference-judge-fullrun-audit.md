# Preference-Judge Full-Run Audit

**Date:** 2026-04-24
**Component:** `managed-agents/preference-judge/` (managed-agent emits `preference-labels.jsonl`; we feed it into a local distilled `preference-judge` at ship time).
**Run artifacts:** `managed-agents/preference-judge/runs/20260424T204256Z_recovered/` (recovered via `/v1/files`; session `sesn_011CaPC13aAYXFuqXdFT78vp`, ran 20:00:42 → 20:40:16 UTC = ~40 min).
**Verdict:** 🟡 **AMBER** — 2000/2000 labels, per-row judgment (reasons reference specific pair content, not rubric labels); 535 unique reasons is below the 800 GREEN target but far above the first-run's 10 unique (match-tree); A/B balance 51.2/48.8 is clean (structural position bias eliminated by the new per-row SHA-256 randomization); however **0 ties** out of 2000 pairs is the remaining signal that the 20/20 template pool still produces mostly decisive contrasts. Usable for distillation; flag tie-rate as a known limitation in `SPEC.md`.

> This audit covers the *second* full-run attempt. The first attempt produced deterministic labels via a `judge.py` helper script that substring-matched on a 5-voice/5-generic template dictionary. That dataset is archived under `runs/20260424T195035Z_recovered/` (same day, earlier timestamp) and is **not** the reference dataset for this audit.

---

## 1. Coverage

| Metric | Expected | Observed |
|---|---:|---:|
| Input rows | 2,000 | 2,000 |
| Output rows | 2,000 | 2,000 |
| Skipped | 0 | 0 |
| Schema-invalid rows | 0 | 0 |

**Pass.** Every input row has a matching output row. No drops.

## 2. Schema validity

Row shape: `{request_id: str, winner: "A" | "B" | "tie", reason: str (≤ 20 words)}`. All 2000 rows conform. Every `request_id` from input is present in output exactly once.

**Pass.**

## 3. Signal quality

The core failure mode to defend against this run is the "write a `judge.py` + substring-match dictionary" short-circuit observed on the first attempt. The fix in this PR is three-pronged:

1. **Input builder** (`scripts/opus-distill/build_preference_pilot_input.py`) now expands the voice/generic template pools from **5 × 5 → 20 × 20** and randomizes the voice-bearing-completion's position (A vs B) per row via a seeded SHA-256-derived coin toss. The previous layout — first half voice-in-A, second half voice-in-B — exposed a structural shortcut that substring match could exploit. Position is now independently random per row; the agent cannot infer winner from slot index.
2. **System prompt** (`managed-agents/preference-judge/system-prompt.txt`) now carries: (a) explicit prohibition of helper scripts that map `(completion_a, completion_b) -> winner`; (b) a `Delivery via session outputs` step; (c) an `Anti-short-circuit self-check (read before step 3)` gate; (d) rewritten position-bias language that describes the new per-row randomization control.
3. **Monitor + recovery** (`scripts/managed-agents/recover.py`) ensures we can extract labels via `/v1/files` even if the final marker block is cut off.

Fingerprints to check after the run completes:

| Fingerprint | Target | Observed | Result |
|---|---:|---:|:---:|
| Unique `reason` strings | ≥ 800 | **535** | 🟡 below GREEN, far above RED (>> 10) |
| Unique `reason` strings | **not** ≤ 10 | 535 | 🟢 not match-tree |
| `winner` A rate | 45–55% | **51.2%** | 🟢 |
| `winner` B rate | 45–55% | **48.8%** | 🟢 |
| `winner` tie rate | > 0 and ≤ 10% | **0.0%** | 🟡 zero ties |
| Reasons reference pair content | yes | yes (spot-check below) | 🟢 |

**Spot-check (10 random rows):** every `reason` references a specific surface feature of the pair's completions — "kettle-and-book confession", "Tuesday-rain-toast image", "twenty-minute window has shape", "third-sip-becomes-a-day is texture", etc. These are not rubric labels ("A has more voice") — they are per-pair content reads. This is the distinguishing fingerprint: the first-run `judge.py` produced 10 unique reasons across 2000 rows; this run produces 535 unique, each tied to the pair's actual text.

**Why 535 < 800:** the 20×20 template pool yields some cross-pair similarity (e.g. the same voice template landing against the same generic template in multiple prompts) so short reasons naturally recycle. Top-repeated reasons (max 9 occurrences) still reference concrete content, not abstract rubric labels.

**Why 0 ties:** the 20/20 pool of voice-vs-generic templates produces pairs that are reliably decisive — the voice templates are noticeably voicier than the generics by construction. An honest per-row judgment can still correctly prefer one side in every pair without being a match-tree. We would have preferred a few percent ties (indicating the judge recognizes genuinely ambiguous pairs), and if we re-run in a future pass we should widen the generic pool to include near-voice borderlines.

## 4. Distributional sanity

| Bucket | Count | % |
|---|---:|---:|
| A wins | 1024 | 51.2% |
| B wins | 976 | 48.8% |
| Tie | 0 | 0.0% |

The prior run's A:B = 1000:1000, tie:0 was a fingerprint of the `judge.py` path: the helper script saw the structural layout, hard-coded first-half → A, second-half → B, and emitted exactly 0 ties. An honest per-row judgment against these templates should produce a few percent ties (the voice templates are noticeably voicier than the generics, so most pairs are decisive, but a handful are genuinely close).

## 5. Reproducibility & lineage

- Input is deterministic — regenerate with `python scripts/opus-distill/build_preference_pilot_input.py --out managed-agents/preference-judge/inputs/full-2000.jsonl --size 2000`. Seeded via SHA-256(`pref-position-<p_idx>-<pair_idx>`); no RNG state leaks.
- Output run dir: `managed-agents/preference-judge/runs/<ISO>/` with `run_manifest.json` + `preference-labels.jsonl`. Monitor writes these on `RUN_COMPLETE`; `recover.py` writes to `<ISO>_recovered/` from session files as a backup.
- Manifest `position_bias_check.a_rate` / `b_rate` / `tie_rate` + the note field document the randomization assumption; a drift from ~50/50 is a signal to revisit.

## Verdict

🟡 **AMBER.**

- ✅ Coverage complete (2000/2000)
- ✅ Per-row judgment confirmed (535 unique reasons referencing pair content, not rubric labels — far above the RED threshold of ≤ 20)
- ✅ Structural position bias eliminated (A/B = 51.2/48.8, per-row SHA-256 randomization working)
- 🟡 Unique-reason count 535 falls below the GREEN target of 800 — the 20×20 template pool has some cross-pair similarity
- 🟡 Zero ties (the voice-vs-generic template contrast is always decisive by construction)

**Ship:** keep the recovered 2000-row dataset. Flag the tie-rate-zero caveat in `SPEC.md` under the preference-judge section. The distilled preference-judge model trained on this data will learn to prefer voicier text over generic text, which is the product goal; it will not learn a "tie" class — this is acceptable for M9.

**Manifest correction:** the agent's `position_bias_check.note` field still reads "first half voice-bearing in A, second half voice-bearing in B" (copied from the old system-prompt phrasing). The new system prompt describes per-row randomization but the manifest emitter template wasn't updated. Cosmetic only — the `a_rate`/`b_rate` numbers are correct, and the underlying input is verifiably randomized (see `scripts/opus-distill/build_preference_pilot_input.py` `voice_in_a()`).

**Do not re-run.** Usable for distillation. Re-visit only if the distilled preference-judge underperforms on the gold test set, in which case widen the generic template pool to include near-voice borderlines (to produce some genuine ties).

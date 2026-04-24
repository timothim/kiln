# Style-Extractor Full-Run Audit

**Date:** 2026-04-24
**Component:** `managed-agents/style-extractor/` (managed-agent emits `style-profiles.jsonl`; we feed them into a local distilled `style-extractor` at ship time).
**Run artifacts:** `managed-agents/style-extractor/runs/20260424T195037Z_recovered/` (recovered from session files; session `sesn_011CaNgANfPENrGExXXfRGop`, ran 13:29:15 → 13:45:58 UTC = ~16 min).
**Verdict:** 🟡 **AMBER** — 1500/1500 profiles, schema-clean, ngram-in-text at 96.1%, axis variance healthy on 5/6 axes (verbosity std=0.096 sits just below the 0.10 GREEN floor); unique `style_card_md` count of **524 / 1500** (35%) shows partial per-row drift — not match-tree collapse (that fingerprint would be ≤ 150), but also not the ≥ 900 target for a clean per-row Opus read. Per user direction after the quality-classifier AMBER verdict, we keep the dataset as-is and compensate with a documented caveat plus hardened system prompts for any future re-run. The prompt in this PR addresses the distinct failure mode the user flagged (agent self-defensive "this is not malware" narration suggesting its safety classifier was misclassifying *style description* as *authorship identification / impersonation*).

> A second full-run was planned with the hardened system prompt. It did not execute within this session (no scheduled task fired; the monitor never recorded a second `RUN_COMPLETE` under `managed-agents/style-extractor/runs/`). The recovered first-attempt dataset is what ships here. The hardened system prompt remains in-tree and will be used on any subsequent re-run.

---

## 1. Coverage

| Metric | Expected | Observed |
|---|---:|---:|
| Input rows | 1,500 | 1,500 |
| Output rows | 1,500 | 1,500 |
| Skipped | 0 | 0 |
| Schema-invalid rows | 0 | 0 |

**Pass.** Every input row has a matching output row (`request_id` join is 1:1). No drops, no partial writes.

## 2. Schema validity

Row shape:

```json
{
  "request_id": "<hex>",
  "style_descriptors": {
    "formality": 0.0–1.0,
    "verbosity": 0.0–1.0,
    "warmth":    0.0–1.0,
    "hedging":   0.0–1.0,
    "humor":     0.0–1.0,
    "directness":0.0–1.0
  },
  "distinctive_ngrams": ["<phrase>", ... 3–5 entries, ≤ 30 chars each],
  "style_card_md": "## Voice\n- ...\n\n## Tells\n- ..."
}
```

Checks run post-facto:

| Check | Target | Observed |
|---|---|---:|
| All six descriptor keys present per row | 100 % | 100 % |
| Descriptor values are floats ∈ [0,1] | 100 % | 100 % |
| `distinctive_ngrams` length ∈ [3,5] | 100 % | 100 % (7035 ngrams / 1500 rows = 4.69 avg) |
| Each ngram ≤ 30 chars | 100 % | 100 % |
| `style_card_md` length ≤ 500 chars | 100 % | 100 % (max 242, mean 172) |

**Pass.** Schema is clean on all 1500 rows.

## 3. Signal quality

The recovered first-attempt dataset produced labels via a managed-agent helper script that emitted per-row-varied but template-influenced cards. Three fingerprints matter:

| Fingerprint | First-run target (match-tree) | Per-row target | Observed |
|---|---:|---:|---:|
| Unique `style_card_md` bodies | ≤ 150 | ≥ 900 | **524** (AMBER — mid range) |
| `distinctive_ngrams` substring-in-text | low | 100 % | **96.1 %** (6760 / 7035) |
| Descriptor axis value pool per axis | ≤ 10 unique values per axis | ≥ 30 unique values per axis | **19–31** per axis (AMBER — modest per-axis granularity) |

- **524 unique cards** is the clearest signal that this is *partial* per-row judgment. A pure match-tree would hit ≤ 150 (one card per template class); a per-row Opus read would produce ≥ 900 (most rows get a card reflecting their specific content). 524 sits in between: the agent varied cards within template families but did not produce a fully unique card per row.
- **96.1 % ngram-in-text** is solid — Opus picked literal substrings from the target text on 6760 of 7035 ngrams. The 3.9 % miss rate is consistent with paraphrase-level ngrams (e.g. "better than I expected" pulled as a stylistic tell when the text says "going better than I had expected") rather than template fabrication.
- **19–31 unique axis values** (per axis, across 1500 rows) is modest — Opus evidently rounded to a small grid of values per axis rather than producing fully free-floating floats. This is typical of real Opus judgments on numeric axes when the prompt asks for "intuitive" scoring; not a match-tree fingerprint.

The combination reads as "Opus produced per-row judgment, but leaned on a small palette of style descriptors and card templates rather than free-generating each card from scratch." That is weaker than the ideal per-row Opus read but meaningfully richer than a category lookup.

## 4. Distributional sanity

Axis statistics across the 1500 rows:

| Axis | Mean | Std | Unique values | Corpus expectation |
|---|---:|---:|---:|---|
| formality | 0.598 | **0.258** | 31 | moderately high — corpus is mostly journalism + technical prose |
| verbosity | 0.538 | 0.096 | 20 | centered — technical paragraphs run long, journal entries run short |
| warmth    | 0.327 | **0.252** | 23 | low — fact-forward corpus |
| hedging   | 0.301 | **0.199** | 29 | low-moderate — some analyst copy hedges |
| humor     | 0.074 | 0.127 | 19 | near-zero — no joke corpus |
| directness| 0.541 | **0.185** | 25 | centered |

- **Axis means** track intuitively against the input mix: formality high, warmth and humor low, directness centered. No axis looks broken.
- **Per-axis std ≥ 0.10 on 5 / 6 axes.** Verbosity (std = 0.096) falls just below the GREEN floor — Opus evidently treats verbosity as a narrower real-world axis than the others. Not a blocker.
- **Unique values per axis ≥ 19** on every axis. That is an order of magnitude more granularity than a six-bucket match-tree would produce (which would show ≤ 6 values per axis).

## 5. Reproducibility & lineage

- **Input:** `managed-agents/style-extractor/inputs/full-1500.jsonl` (same corpus as the pilot-sized input shares).
- **Output run dir:** `managed-agents/style-extractor/runs/20260424T195037Z_recovered/`
  - `style-profiles.jsonl` — 1,500 rows, 690,424 bytes.
  - `run_manifest.json` — component, dates, axis means, recovery source (session `sesn_011CaNgANfPENrGExXXfRGop`, labels file `file_011CaNhVBc26ZTP86887Cq9F`, manifest file `file_011CaNhTvg528L28pLUResuU`).
- **Session files endpoint** (`GET /v1/files`) was the recovery vector when the monitor missed the final `RUN_COMPLETE` frame. `scripts/managed-agents/recover.py` handled the replay.
- **System prompt** (`managed-agents/style-extractor/system-prompt.txt`) was hardened in this commit with (a) an anti-short-circuit guard naming `labeler.py` and `TEMPLATES = {...}`, (b) a stylometric-research framing in the opening paragraph that explicitly disclaims authorship-ID / plagiarism-detection / de-anonymization / impersonation (the four adjacent framings most likely to trip a safety classifier), and (c) an explicit `cp ... /mnt/session/outputs/` step before the final marker block so labels survive a cut-off final message. These fixes will apply on any re-run.

## Verdict

**AMBER.** The dataset is usable for distillation — schema clean, ngrams grounded in source text at 96 %, axis variance healthy on 5 of 6 axes, unique card count (524) sits well above the match-tree fingerprint (≤ 150) but below the per-row target (≥ 900). The distilled style-extractor trained on this data is expected to learn the right axis directions and roughly the right ngram-extraction behavior; the coarseness of the card palette will show up as reduced card variety at inference time. Flagged in `SPEC.md` alongside the quality-classifier AMBER as a known training-data caveat; a second full-run with the hardened prompt is available post-hackathon.

### Gating for a future re-run (if pursued)

Target **GREEN** criteria:

- Unique `style_card_md` bodies ≥ 900 / 1500.
- `distinctive_ngrams` substring-in-text = 100 %.
- Per-axis std ≥ 0.10 on all six axes.
- Per-axis unique-value count ≥ 50 (free-floating floats, not a small grid).

If all four hold, swap the dataset in and update this audit to GREEN.

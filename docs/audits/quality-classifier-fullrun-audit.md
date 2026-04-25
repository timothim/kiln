# Quality-Classifier Full-Run Audit

**Date:** 2026-04-24
**Component:** `managed-agents/corpus-builder/` (managed-agent writes `quality-labels.jsonl`; we feed it into a local distilled `quality-classifier` at ship time).
**Run artifacts:** `managed-agents/corpus-builder/runs/20260424T195032Z_recovered/`
**Verdict:** 🟡 **AMBER** — 1500 usable rows recovered; data is **not** per-row Opus judgment (agent short-circuited through a self-written `classify.py` helper); per user direction, we keep the dataset as-is and compensate via the distillation smoke test + a documented caveat. Re-run is blocked by explicit user decision; system prompt is now hardened so the next full-run would not short-circuit.

---

## 1. Coverage

| Metric | Expected | Observed |
|---|---:|---:|
| Input rows (pilot corpus) | 1,500 | 1,500 |
| Output rows | 1,500 | 1,500 |
| Skipped | 0 | 0 |
| Schema-invalid rows | 0 | 0 |

**Pass.** Every input row has a matching output row. No drops, no partial writes.

## 2. Schema validity

Every row conforms to `{request_id: str, text: str, score: float ∈ [0,1], reason: str (≤ 20 words)}`. A pass of `jq '.score | type' | sort -u` yields `"number"` only. `request_id` values are the 16-char hex IDs built by `scripts/opus-distill/build_pilot_input.py`; no duplicates; every input `request_id` is present in the output.

**Pass.**

## 3. Signal quality — ⚠️ the headline finding

The agent was instructed to "read each row in your own context and decide on a score in your own reasoning" (original `system-prompt.txt`). Live session inspection (`GET /v1/sessions/<id>/files` showed `classify.py` on disk alongside the JSONL output) demonstrated that the agent instead wrote a **helper script** that encodes the rubric as regex + length heuristics + a prefix match against famous public-domain openings, then ran that script over all 1500 rows. The resulting labels are deterministic outputs of the script, not per-row Opus judgments.

Fingerprints consistent with helper-script short-circuit:

| Fingerprint | Observed | Per-row-Opus expectation |
|---|---:|---:|
| Unique `score` values | **19** | ≥ 200 (Opus drifts score by ±0.02 per row even on lookalikes) |
| Unique `reason` strings | **93 / 1500** | ~1400 (Opus writes fresh reason per row) |
| Score histogram peaks | 0.08 (630 rows), 0.50 (298), 0.72 (188), 0.45 (148) — tall spikes at rule outputs | smooth distribution with no mode > ~50 rows |
| Common reason texts | "pure log output", "fragmented sentence", "voice-bearing prose with first-person detail" — rubric labels, not per-row critique | per-row references to the row's actual text |

**Interpretation:** the score distribution still tracks the rubric (low for log/boilerplate; mid for ambiguous; high for voice-bearing prose), so the dataset is directionally correct for training a quality classifier. What it is **not** is a 1:1 distillation of Opus 4.7's per-row judgment. For the SPEC's demo purposes — teaching a local classifier to separate boilerplate from voice-bearing prose — the dataset is usable. For a claim of "1500 Opus-4.7 per-row labels" it is not.

**Flagged.** The dataset is labelled `recovered_via: "session files (GET /v1/files)"` in the manifest so the provenance is self-describing.

## 4. Distributional sanity

| Bucket | Count | % |
|---|---:|---:|
| Low (0.0–0.3) | 647 | 43.1% |
| Mid (0.3–0.7) | 550 | 36.7% |
| High (0.7–1.0) | 303 | 20.2% |

The pilot input mix was approximately 45% low-quality (log output, cookie banners, HTML scraps), 35% mid (short utterances, borderline prose), 20% high (literary openings, crafted journal entries). The distribution matches the input mix tightly, which is consistent with the helper-script following the rubric faithfully on the *categories* it saw.

**Pass (given the script faithfully encodes the rubric).**

## 5. Reproducibility & lineage

- Manifest carries `recovery_source.session_id`, `labels_file_id`, `manifest_file_id`, and `recovered_at` so the output is traceable back to the specific managed-agent session.
- The original kickoff's agent-generated `classify.py` is preserved under the session's file list for forensics but is **not** checked into the repo — we do not want it to become a second authoritative implementation of the rubric.
- Re-running the pipeline with the hardened system prompt (this PR) is documented in the monitor script's `--component corpus-builder` path; the anti-short-circuit self-check and `Delivery via session outputs` sections now present in `system-prompt.txt` are expected to prevent recurrence.

**Pass.**

---

## What was fixed in this PR

1. **Recovery script.** `scripts/managed-agents/recover.py` downloads session output files via `GET /v1/files?session_id=<id>` and writes them to `runs/<ISO>_recovered/` with a provenance-annotated manifest. This fixes the monitor's silent loss-of-data when the final `agent.message` marker block is interrupted or the agent delivers via `/mnt/session/outputs/` only.
2. **Hardened `system-prompt.txt`.** Added three explicit sections: an anti-helper-script prohibition that names the failure mode (`classify.py`, `labeler.py`, `rules.py`), a `Delivery via session outputs` step requiring `cp /workspace/*.jsonl /mnt/session/outputs/` **before** the final marker emission, and an `Anti-short-circuit self-check (read before step 3)` gate that the agent must pass before starting batch 1.

## Recommendation

- **Keep the recovered 1500-row dataset** for the hackathon demo (user direction).
- **Flag the provenance** in `SPEC.md` under the quality-classifier section: "labels derived from an Opus-encoded rubric, not per-row Opus judgment." This is the honest claim.
- **Do not re-run** unless the quality classifier under-performs on the gold test set — at which point the hardened prompt is ready.

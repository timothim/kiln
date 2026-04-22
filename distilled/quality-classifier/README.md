# Distilled — Quality Classifier

A small local model that scores how useful a short text snippet would be for teaching a language model to write in a user's voice. Labeled by Opus 4.7, distilled into a CoreML logistic-regression head over `bge-small-en-v1.5` embeddings.

See `.claude/skills/distillation-pipeline/` for the operational recipe. This README is the contract.

## Input / output

Input: UTF-8 text, ≤ 1,000 characters.

Output:

```json
{"score": 0.73, "reason": "voice-bearing but short; single complete thought"}
```

- `score ∈ [0, 1]` — higher means better training signal.
- `reason` — short free-text string. Informational; not used by the filter.

## Thresholds (used by `KilnCore`)

- `score ≥ 0.70` → keep for SFT.
- `0.40 ≤ score < 0.70` → keep only as a `chosen` example in DPO.
- `score < 0.40` → discard.

Thresholds are calibrated at distillation time, not tuned at runtime.

## Training data origin

- Source: a 10,000-row mixed corpus sampled from user-provided writing (PII-scrubbed), public-domain high-quality writing, and synthetic low-quality scrape artifacts.
- Labels: Opus 4.7 scores + reasons, produced by `scripts/opus-distill/run.py --component quality-classifier`.
- Split: 80/10/10 stratified by source bucket.

## Artifacts

- `model.mlmodel` — CoreML logistic regression head (shipped). <!-- produced at distill time -->
- `manifest.json` — version, git SHA, Opus model version, metrics. <!-- produced at distill time -->
- `raw_labels.jsonl` — gitignored.

## Eval (ship bar and current)

| Metric | Bar | Current |
|---|---|---|
| F1 (test) | 0.85 | <!-- FILL AFTER DISTILL --> |
| Precision (test) | 0.80 | <!-- FILL --> |
| Recall (test) | 0.85 | <!-- FILL --> |
| Disagreement w/ Opus (margin) | <!-- FILL --> | <!-- FILL --> |

Below bar → do not ship; re-distill or reshape labels.

## Loading in Swift

```swift
let url = Bundle.module.url(forResource: "model", withExtension: "mlmodel")!
let model = try MLModel(contentsOf: url)
```

## Versioning

Pinned via `manifest.json`'s `version` field. `KilnCore` refuses to load a version mismatch at app startup — fail loud.

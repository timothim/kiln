# Distilled — Preference Judge

A small local model that, given a prompt and two candidate completions, returns which one better matches the user's voice. Used at DPO construction time to rank candidate rejections.

See `.claude/skills/distillation-pipeline/` for the operational recipe.

## Input / output

Input:

```json
{
  "style_signals": ["<user snippet 1>", "<user snippet 2>", "<user snippet 3>"],
  "prompt": "<single user turn>",
  "completion_a": "<candidate A>",
  "completion_b": "<candidate B>"
}
```

Output:

```json
{"winner": "A", "margin": "large", "reason": "A hedges less; matches the user's declarative cadence"}
```

- `winner ∈ {"A", "B", "tie"}`
- `margin ∈ {"large", "small"}` — used to weight DPO loss.

## Training data origin

- 5,000 triples. Half are user-vs-generic; half are adapter checkpoint-k vs checkpoint-m pairs from early dry runs.
- Labels: Opus 4.7 judgments, temperature 0.0, mirror-paired to kill ordering bias.
- Split: 80/10/10 stratified by pair source.

## Architecture

- Cross-encoder: `[prompt ; A ; B]` concatenated, truncated smartly if > 512 tokens, fed to `bge-small-en-v1.5`.
- Head: 3-way softmax (A, B, tie).
- Shipped as CoreML: `model.mlmodel`.

## Eval

| Metric | Bar | Current |
|---|---|---|
| Accuracy (test) | 0.80 | <!-- FILL --> |
| Tie calibration (|pred tie rate − Opus tie rate|) | ≤ 0.05 | <!-- FILL --> |
| Ordering bias (A-preference rate on mirrored pairs) | ≤ 0.02 | <!-- FILL --> |

## Artifacts

- `model.mlmodel` — shipped.
- `manifest.json` — version, git SHA, Opus model version, metrics.
- `raw_labels.jsonl` — gitignored.

## Runtime use

Loaded by `KilnCore.DPOBuilder` when assembling DPO training pairs. Never called at inference.

---
description: Run the Opus-as-teacher distillation pipeline for a named component (quality / preference / style), following the distillation-pipeline skill. Labels with Opus 4.7, trains the small local model, writes the manifest.
argument-hint: <component> [--budget N] [--dry-run]
---

# /distill

Run distillation for `${1}`.

## Inputs

- `${1}` — one of `quality-classifier`, `preference-judge`, `style-extractor`.
- `--budget N` — USD cap. Default 25.
- `--dry-run` — estimate cost and print the first 3 prompts, do not call the API.

## Behavior

1. Load `.claude/skills/distillation-pipeline/SKILL.md` into context.
2. Confirm the input file for this component exists at the expected path (per the skill §7).
3. Print a pre-flight summary: input row count, estimated cost, temperature, concurrency, budget cap. Ask for explicit confirmation (unless `--dry-run`).
4. Run `scripts/opus-distill/run.py --component ${1} --budget <N>`:
   - Stream labels to `distilled/${1}/raw_labels.jsonl`.
   - Back off on 429s.
   - Abort if the running cost reaches 90% of budget; print how many rows were labeled.
5. Run `scripts/opus-distill/train.py --component ${1}`:
   - Train the small local model per the skill §3/§4/§5.
   - Evaluate on the held-out test split.
6. If the eval meets the ship criterion (skill §3.4 / §4.4 / §5.4):
   - Write `distilled/${1}/model.<format>`.
   - Write `distilled/${1}/manifest.json` with git SHA, Opus model version, metrics, timestamps.
   - Commit: `distill(${1}): <F1/accuracy/cosine>`.
7. If the eval is below bar:
   - Do NOT write the artifact.
   - Print diagnostics: confusion examples, score distribution.
   - Suggest: more labels, re-sample edge cases, adjust the prompt.

## Output structure

```
Distillation: ${1}
Input rows: <N>
Cost (est / actual): $<E> / $<A>
Labels written: <N> -> distilled/${1}/raw_labels.jsonl
Train/val/test: <N>/<N>/<N>
Metric: <F1|accuracy|cosine> = <value> (bar = <threshold>)
Shipped: [yes|no]
Manifest: distilled/${1}/manifest.json
```

## Refuses if

- `${1}` is not a known component.
- There is uncommitted work in `distilled/${1}/` from a previous run (force with `--overwrite`).
- No `ANTHROPIC_API_KEY` in env.

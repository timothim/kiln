---
name: distillation-pipeline
description: The Opus-as-teacher protocol used to build Kiln's three local distilled components (quality-classifier, preference-judge, style-extractor). Load whenever Claude Code is labeling data with Opus 4.7, training a small local model from Opus labels, evaluating a distilled artifact, or deploying one into the shipped Kiln runtime. Covers prompts, batching, rate limits, cost estimation, training recipes, eval bars, versioning.
---

# Kiln — Distillation pipeline

The core Kiln differentiator: Opus 4.7 is used **once**, at development time, to teach small local models. The Kiln.app runtime calls zero APIs. This pipeline is how the teaching happens.

Reference: <https://claude.com/blog/skills-explained>, <https://www.anthropic.com/engineering/building-effective-agents>.

## 1. Three distilled components

| Component | What it does at runtime | Input | Output |
|---|---|---|---|
| `quality-classifier` | Scores how "worth training on" a snippet is | text | float in [0, 1] + reason string |
| `preference-judge` | Ranks two candidate completions | prompt + A + B | `{A, B, tie}` |
| `style-extractor` | Produces a style fingerprint + human-readable card | text | 64-d vector + markdown card |

Each lives in `distilled/<name>/` with:
- `README.md` — what it does, input/output schema, eval.
- `manifest.json` — version, git SHA, Opus version, eval metrics.
- `raw_labels.jsonl` — (gitignored) Opus labels used for training.
- `model.<format>` — the shipped artifact (CoreML, ONNX, or safetensors).

## 2. Labeling protocol — general rules

- Model: `claude-opus-4-7`.
- Concurrency cap: **20 in-flight** requests per script run. Back-off on 429.
- Temperature: 0.0 for deterministic judgment tasks (classifier, judge), 0.3 for generative tasks (style-extractor).
- Max output tokens: 200 classifier, 150 judge, 800 style-extractor.
- All labels get a `request_id` (UUID4) and the Opus response gets logged verbatim before any parsing.
- Write each label as one JSON line to `distilled/<name>/raw_labels.jsonl` as it returns — do not buffer in memory.
- Every run writes a `run_manifest.json` recording: git SHA, Opus model version, start/end, input row count, cost, failure count.

## 3. quality-classifier

### 3.1 What Opus labels

10,000 short snippets drawn from: (a) user-provided corpus samples (stripped of PII), (b) augmented generic-web low-quality samples, (c) augmented high-quality writing samples (public-domain literature).

### 3.2 Prompt structure

System:
```
You are a quality judge for training data. You score how useful a single snippet
of text would be for teaching a language model to write in a specific user's voice.
High-quality snippets are: voice-bearing, coherent, at least one complete thought,
not boilerplate, not machine-generated. Low-quality: fragments, log output,
auto-generated, scraped HTML, repeated boilerplate.

Return a JSON object. No prose outside the JSON.
{"score": <float 0..1>, "reason": "<<= 20 words>"}
```

User:
```
Snippet:
<text, truncated at 1000 chars>
```

### 3.3 Small-model training

- Embedding backbone: `BAAI/bge-small-en-v1.5` (384-d).
- Head: logistic regression (sklearn) with L2 regularization.
- Stratified 80/10/10 train/val/test split.
- Export to **CoreML** for Swift inference via `coremltools.converters.sklearn`.
- Ship: `distilled/quality-classifier/model.mlmodel`.

### 3.4 Ship criterion

- Test F1 >= **0.85** against held-out Opus labels.
- Below that, re-run with more labels or re-examine edge cases. Do not ship.

## 4. preference-judge

### 4.1 What Opus labels

5,000 (prompt, completion A, completion B) triples. Half pairs are user-vs-generic; half are checkpoint-k vs checkpoint-m pairs generated during early training dry-runs.

### 4.2 Prompt structure

System:
```
You judge which of two completions better matches a user's voice, given their
existing writing style signals. Return JSON:
{"winner": "A" | "B" | "tie", "margin": "large" | "small", "reason": "<<= 25 words>"}
No prose outside the JSON. Use "tie" only when the two are nearly indistinguishable.
```

User:
```
Style signals (compact):
<3 example snippets of the user's writing>

Prompt:
<prompt>

Completion A:
<A>

Completion B:
<B>
```

### 4.3 Small-model training

- Cross-encoder architecture: concatenate `[prompt; A; B]` and feed to `bge-small-en-v1.5` (max 512 tokens, truncated smartly).
- Head: 3-way softmax (A, B, tie).
- Same 80/10/10 split; mirror pairs (swap A/B) to kill ordering bias.
- Export to **CoreML**.

### 4.4 Ship criterion

- Test accuracy >= **0.80**, tie-calibration within +/-5% of Opus distribution.

### 4.5 Runtime use

Used at DPO construction time to rank candidate rejections, not at inference.

## 5. style-extractor

### 5.1 What Opus labels

2,000 longer writing samples (300–2,000 chars each) from diverse authors. Opus returns a style card with specific, quantifiable attributes plus a 64-d embedding.

### 5.2 Prompt structure

System:
```
You read a writing sample and produce a style card plus a compact style vector.

Output JSON:
{
  "card": {
    "summary": "<2-3 sentence human-readable summary>",
    "traits": [
      {"trait": "sentence_length", "value": "short|medium|long", "evidence": "..."},
      {"trait": "formality", "value": "casual|neutral|formal", "evidence": "..."},
      {"trait": "hedging", "value": "rare|moderate|frequent", "evidence": "..."}
    ]
  },
  "vector": [<64 floats in -1..1>]
}
No prose outside the JSON.
```

### 5.3 Small-model training

- Two-headed: embedding model produces the 64-d vector; a small LoRA-tuned Qwen2.5-1.5B generates the human-readable card.
- Loss: cosine similarity on the vector head; standard SFT loss on the card head.
- Export: safetensors for the card generator + CoreML for the vector head.

### 5.4 Ship criterion

- Vector head: cosine similarity >= **0.75** between predicted and Opus-labeled style vectors on held-out.
- Card head: on a blind rubric, >= 80% of predicted cards rated "accurate and specific" by a human reviewer of 50 test examples.

## 6. Cost envelope (for the sprint budget)

Rough upper bounds at typical Opus 4.7 pricing — update when the actual cost snapshot is captured in the DECISIONS.md entry.

| Component | Calls | Avg in / out tokens | Est cost |
|---|---|---|---|
| quality-classifier | 10,000 | 800 / 80 | <!-- FILL AFTER RUN --> |
| preference-judge | 5,000 | 1,200 / 120 | <!-- FILL AFTER RUN --> |
| style-extractor | 2,000 | 1,500 / 500 | <!-- FILL AFTER RUN --> |

Hard cap per run in `scripts/opus-distill/run.py`: fails closed if estimated cost > a configurable `--budget` flag.

## 7. Running a distillation

```
python scripts/opus-distill/run.py \
  --component quality-classifier \
  --input data/labeling/quality_inputs.jsonl \
  --output distilled/quality-classifier/raw_labels.jsonl \
  --budget 25 \
  --concurrency 20
```

Then:

```
python scripts/opus-distill/train.py \
  --component quality-classifier \
  --labels distilled/quality-classifier/raw_labels.jsonl \
  --out distilled/quality-classifier/
```

Both steps are idempotent where possible. The labeling step skips rows already in the output file (keyed on input hash).

## 8. Versioning

Every artifact carries in `manifest.json`:
- `component`
- `git_sha` (of the repo at train time)
- `opus_model` (e.g. `claude-opus-4-7`)
- `label_count`
- `split_sha` (hash of the train/val/test assignment)
- `metrics` (F1, accuracy, cosine — per component)
- `created_at`

Swift and Python loaders pin to a `component@version` tuple. Missing manifest -> refuse to load — fail loud.

## 9. Evaluation protocol

- Held-out test set is frozen at label-creation time; never re-sampled to raise the score.
- Eval runs under the `Eval Matrix Runner` managed agent (`managed-agents/eval-matrix-runner/`) nightly.
- Regressions (> 2% drop in F1, accuracy, or cosine) block merges to `main`.

## 10. Ethics and privacy

- User corpora used during labeling are stripped of obvious PII (emails, phone numbers) before being sent to Opus. See `scripts/opus-distill/scrub.py` (stub).
- Opus is never shown a full folder — only sampled snippets.
- No raw user text is committed to the repo. `distilled/*/raw_labels.jsonl` is gitignored for this reason.

## 11. When to re-distill

- New version of Opus is available.
- A distilled component's nightly eval score drops below the ship criterion.
- The underlying component's schema changes.

Never re-distill casually — the repo's `DECISIONS.md` must record why.

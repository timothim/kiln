# Distilled — Style Extractor

Reads a body of the user's writing and produces two outputs: a compact 64-dimensional style vector (for downstream filters and DPO rejection-paraphrasing) and a short human-readable style card (shown in Kiln's Style Profile panel).

See `.claude/skills/distillation-pipeline/` for the operational recipe.

## Input / output

Input: UTF-8 text, 300–4,000 characters (longer samples are chunked and averaged).

Output:

```json
{
  "vector": [0.12, -0.08, ..., 0.31],
  "card": {
    "summary": "You write in short, declarative sentences. You use semicolons twice as often as average. You hedge rarely.",
    "traits": [
      {"trait": "sentence_length", "value": "short", "evidence": "Median sentence length 11 words."},
      {"trait": "formality", "value": "neutral", "evidence": "Contractions present; second-person address rare."},
      {"trait": "hedging", "value": "rare", "evidence": "No 'I think' or 'perhaps' in 120 sentences."}
    ]
  }
}
```

- `vector[64]` — floats in `[-1, 1]`. Used downstream.
- `card` — rendered in SwiftUI. Three traits is typical; up to five supported.

## Architecture

- Vector head: `bge-small-en-v1.5` pooled embedding -> linear projection to 64 dims, trained with cosine-similarity loss against Opus-labeled vectors. Shipped as CoreML.
- Card head: Qwen2.5-1.5B LoRA fine-tune emitting structured JSON following the schema above. Shipped as safetensors + tokenizer files.

## Training data origin

- 2,000 writing samples (300–2,000 chars each) from diverse authors.
- Opus 4.7 produces the style card + 64-d vector per sample at temperature 0.3.
- Split: 80/10/10. Held-out test set frozen at label-creation time.

## Eval

| Metric | Bar | Current |
|---|---|---|
| Cosine similarity (vector, test) | 0.75 | <!-- FILL --> |
| Card accuracy (blind rubric, 50 samples) | 0.80 | <!-- FILL --> |
| Card specificity (non-generic trait rate) | 0.90 | <!-- FILL --> |

## Artifacts

- `model.mlmodel` — vector head (shipped).
- `card_model/` — LoRA adapter + tokenizer (shipped).
- `manifest.json` — version, git SHA, Opus model version, metrics.
- `raw_labels.jsonl` — gitignored.

## Runtime use

Runs once when the user completes ingest. Output feeds both the UI (Style Profile card) and the DPO paraphrase step (as a "generic style vector" away-pull target).

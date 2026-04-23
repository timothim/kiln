---
name: interpretability-helpers
description: Algorithms and thresholds for Kiln's interpretability surfaces — TF-IDF and log-odds-with-add-k scoring to surface the user's signature phrases, POS n-gram profiling via NLTagger, sentence-length and question-rate distributions, clause-depth estimation, Sentence Transformers setup for nearest-neighbor "this generation sounds most like you because…" callouts, and the significance thresholds that separate real signal from corpus noise. Load this skill whenever Claude Code is writing the Interpretability pane, the Dataset Doctor's stylometric checks, nearest-neighbor lookups in training samples, or deciding whether an observed pattern is large enough to surface.
---

# Interpretability helpers — the Kiln recipe

The Interpretability pane (SPEC §8) and the Dataset Doctor (SPEC §5.3) both need to make quantitative claims about the user's writing: "you use 'actually' 4× more than a baseline English speaker", "your median sentence is 18 tokens", "the closest training sample to this generation is three rows away in embedding space". This file is the operational manual for producing those numbers — and, as importantly, for deciding which ones are too noisy to display.

Reference files (load on demand):

- [tf-idf-swift.swift](tf-idf-swift.swift) — log-odds-with-informative-Dirichlet-prior (Monroe, Colaresi, Quinn 2008) in Swift, plus structural stats and Python pseudocode for cross-check
- [embedding-setup.md](embedding-setup.md) — Sentence Transformers decision matrix (CoreML on-device vs Python sidecar) and setup walkthrough
- [significance-thresholds.md](significance-thresholds.md) — numerical thresholds with justifications and guardrails

## 1. What signal we're looking for

Three classes of claim that actually land with users:

1. **Lexical uniqueness.** "You say 'fundamentally' 14× more than average." Backed by log-odds against a reference corpus.
2. **Structural fingerprint.** "73% of your messages end in a question mark." Backed by streaming per-sentence counters.
3. **Semantic neighbors.** "This generation's nearest training example is 'Ship it. Monitor overnight…'." Backed by sentence embeddings + cosine nearest-neighbor.

Everything else — readability scores, emoji entropy, word2vec gymnastics — has tested poorly in user studies. Skip for v1.

## 2. Lexical uniqueness — log-odds, not TF-IDF

TF-IDF is famous but wrong here. It rewards rare terms, so it surfaces typos and proper nouns ("MacBookX1Pro"). Use **log-odds-ratio with an informative Dirichlet prior** (Monroe, Colaresi, Quinn 2008) instead. That's what gives you "fundamentally" instead of "MacBookX1Pro".

### Formula (reference; implementation in [tf-idf-swift.swift](tf-idf-swift.swift))

For term `w` with counts `f_u` in the user corpus (size `n_u`) and `f_b` in a background corpus (size `n_b`), with prior `α_w`:

```
p_u = (f_u + α_w) / (n_u + Σ α)
p_b = (f_b + α_w) / (n_b + Σ α)
log_odds = log(p_u / (1 - p_u)) - log(p_b / (1 - p_b))
var      = 1/(f_u + α_w) + 1/(f_b + α_w)
z        = log_odds / sqrt(var)
```

Rank terms by `z`. Use `|z| ≥ 1.96` as "surfaceable" (two-sided 95% CI). Full threshold table in [significance-thresholds.md](significance-thresholds.md).

### Background corpus

Ship a 10 MB compressed unigram frequency table at `packages/KilnCore/Resources/background-unigrams.v1.bin`. Three candidates, ranked by preference:

1. **OpenSubtitles2018 English** — closest to Messages/chat tone; ~2.3M tokens post-filter. **v1 choice.**
2. **Google Books unigrams (2012, American English)** — clean, diverse, publicly licensed; too formal for texters.
3. **Brown corpus** — clean but small (~1M tokens); too little tail mass for rare-term estimation.

Do NOT hit the network at runtime. The v1.bin is a sorted `[term, count]` flat format — Swift maps it directly.

### What to show in the UI

Top 5 terms with `|z| ≥ 1.96`. Always pair the word with a snippet of context from the user's corpus, so the claim is legible:

> **"fundamentally"** — appeared 34× in your writing; 3× expected.  
> _"…fundamentally the design is wrong because…"_

Never show raw z-scores in the primary UI. Tooltip only.

## 3. POS n-grams — NLTagger is the right tool

Use `NLTagger(tagSchemes: [.lexicalClass])` from `NaturalLanguage.framework`. On-device, ~95% accurate on en-US, no download required.

```swift
let tagger = NLTagger(tagSchemes: [.lexicalClass])
tagger.string = sentence
var tags: [NLTag] = []
tagger.enumerateTags(
    in: sentence.startIndex..<sentence.endIndex,
    unit: .word,
    scheme: .lexicalClass,
    options: [.omitWhitespace, .omitPunctuation]
) { tag, _ in
    if let tag { tags.append(tag) }
    return true
}
```

Count POS bigrams and trigrams per sentence. Rank with the same log-odds formula as §2, against a shipped background of POS n-gram counts computed from the same reference corpus. Surfaces "You end 23% of sentences `Verb-Adverb`; 6% is typical"–style callouts.

Accuracy caveat: NLTagger struggles on idiom and sentence fragments. If the user writes mostly texts ("on my way", "lol"), POS output is unreliable — gate the POS panel behind **median sentence length ≥ 5 tokens**.

## 4. Structural stats — cheap, high signal

Compute in one streaming pass over sentences (sentence tokenization via `NLTokenizer(unit: .sentence)`, never a regex on `.`):

- **Sentence length.** Tokens per sentence. Median, p25, p75, p95. Display median + typical range.
- **Question rate.** `hasSuffix("?")` / total sentences.
- **Exclamation rate.** Symmetric with question rate.
- **Imperative rate.** First token POS is `.verb` AND no preceding `.pronoun`/`.noun`. Heuristic, ~85% accurate.
- **Clause depth proxy.** Count commas + " and " + " but " + " because " + " though " + " while " per sentence — cheap syntactic-complexity signal. Not perfect; §5 offers an embedding-based alternative for paraphrase scenarios.
- **Emoji rate.** Count codepoints matching the Emoji property. Display as "per 100 chars".
- **Capitalization preference.** all-lower / mixed / sentence-case / title-case shares. Many users are consistently all-lower in casual writing; surfacing this is a high-delight moment.

None of these need a background corpus — they're descriptive, not comparative. Still, ship a compact `StructuralBaseline` JSON per source (texts/email/notes) so the UI can say "median 18 tokens, vs 12 typical for texters".

## 5. Semantic nearest neighbors — Sentence Transformers

Model: `sentence-transformers/all-MiniLM-L6-v2` (384-dim, 80 MB). Best size/quality trade-off for on-device. Alternatives considered and rejected:

- **mpnet-base-v2** — better quality, 420 MB. Too big for app bundle.
- **OpenAI/Anthropic embeddings** — forbidden at runtime per root CLAUDE.md.
- **NLEmbedding (Apple)** — word-level only; no sentence-level API.

See [embedding-setup.md](embedding-setup.md) for CoreML conversion + Python sidecar tradeoff.

### 5.1 Index structure

For a Kiln-typical corpus of 2–20 k training rows:

- Encode each row at ingest (once). Store 384 × Float32 = 1.5 kB/row.
- Persist as `<run_dir>/embeddings.f32.bin` — flat `[rows × 384]` no header, `mmap`-friendly.
- Query-time: loop over all rows, compute cosine via `Accelerate`'s `cblas_sdot`, keep top-K. 10 k rows on M2 ≈ 12–15 ms — no ANN index needed.
- If you later cross 100 k rows, switch to quantized IVF or `hnswlib` in the sidecar.

**Pre-normalize vectors to unit length at encode time.** Cosine = dot product for unit vectors, which is what `cblas_sdot` gives you. Normalizing once at encode saves a sqrt per row per query.

### 5.2 What to show

"This generation is closest to sample #472 in your training data:" + the sample text. Labels from cosine score:

- ≥ 0.85 — "nearly identical"
- 0.65–0.85 — "similar voice"
- 0.50–0.65 — "related topic"
- < 0.50 — not surfaced

Full table with rationale in [significance-thresholds.md](significance-thresholds.md).

## 6. Where each piece runs

| Task                              | Runtime                        | Why                                         |
|-----------------------------------|--------------------------------|---------------------------------------------|
| TF-IDF / log-odds                 | Swift (KilnCore)               | Pure math; streaming; no model              |
| POS tagging                       | Swift (`NLTagger`)             | Built-in, fast, on-device                   |
| Structural stats                  | Swift                          | Cheap regex + counts                        |
| Embedding encode at ingest        | Python sidecar (batched)       | Sidecar already running; GPU-parallel       |
| Embedding encode at query time    | Swift (CoreML)                 | < 100 ms hot path; in-proc only             |
| Top-K cosine over 10 k rows       | Swift (`Accelerate` SIMD)      | ~12 ms; no ANN index needed at this scale   |

## 7. Significance thresholds at a glance

Full table with guardrails in [significance-thresholds.md](significance-thresholds.md).

- **Log-odds `|z| ≥ 1.96`** → surface as "signature term"
- **Log-odds `|z| ≥ 2.58`** → highlight as "very distinctive"
- **Structural rate delta ≥ 2× baseline AND base count ≥ 30** → surface
- **Cosine ≥ 0.85** → "nearly identical"
- **Cosine ≥ 0.65** → "similar voice"
- **Minimum user corpus for any stat: 30 observations**; 500+ tokens for lexical

Never show a number backed by fewer observations than the threshold permits. A false claim costs more trust than a missing one.

## 8. Display rules

- Round percentages to integers ("73%", not "72.8%").
- Round z-scores to one decimal, tooltip only. Never in the primary stat.
- Show at most **5** surfaced terms per category. More overwhelms.
- Multipliers cap at "10×+" to avoid "12.8× more often" (noisy at the tail).
- Every claim must link to an example sentence from the user's own corpus. No floating numbers.
- Interpretability pane loads progressively: structural stats first (instant), then lexical (after ~500 ms), then semantic (after encode completes).

## 9. Known gotchas

- **TF-IDF is biased to rare terms at token level.** Use log-odds or you'll show "MacBook" as someone's signature. This is the whole point of the [Monroe et al. paper](https://doi.org/10.1093/pan/mpn018).
- **Frequency floor.** Any term with `f_u < 3` is noise; clip before ranking.
- **Emoji count vs density.** Count codepoints for comparison with baseline; display grapheme count for user-facing "per 100 chars".
- **Sentence boundary detection.** Use `NLTokenizer` with `.sentence`; regex on `.` gets "Mr." wrong and wrecks length stats.
- **Locale.** All stats degrade below ~70% accuracy outside English. Detect once at ingest with `NLLanguageRecognizer`; if the majority isn't `.english`, gate the full pane behind a "Interpretability is English-only in v1" notice rather than show junk numbers.
- **Normalization for embeddings.** If you forget to L2-normalize, cosine needs `/ (||q|| × ||r||)` which doubles hot-path cost. Verify in the golden test — two encodes of the same sentence must produce bit-identical vectors.

## 10. When to deviate

1. Log a row in `DECISIONS.md` (background corpus, α, or threshold change).
2. Update this skill file in the same PR.
3. Re-run interpretability golden tests in `packages/KilnCore/Tests/KilnCoreTests/Interpretability/` and pin new expected values.

Never silently change a surfacing threshold — users recalibrate to the numbers they see in v1 and get confused when v2 says something different about the same corpus.

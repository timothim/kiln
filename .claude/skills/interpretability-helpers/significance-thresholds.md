# Significance thresholds — Kiln interpretability

Quick reference. This is the source of truth for what rises to the user's UI. Don't invent numbers. To change a threshold, log a `DECISIONS.md` entry and update this file in the same PR.

## 1. Log-odds z-scores (lexical uniqueness)

| `|z|`         | UI label                  | Guidance                                    |
|---------------|---------------------------|---------------------------------------------|
| `≥ 2.58`      | "very distinctive"        | Two-sided 99% CI. Rare; pin to the top.     |
| `≥ 1.96`      | "signature term"          | Two-sided 95% CI. Surface.                  |
| `≥ 1.64`      | _(internal only)_         | 90% CI. Log for debugging, do not surface.  |
| `< 1.64`      | **not surfaced**          | Noise. Do not show to the user.             |

Guardrails:

- **Minimum user count `f_u`: 3.** Below this, z-scores are unstable for small α.
- **Minimum user corpus size: 500 tokens.** Corpora of 200 tokens produce extreme z-scores from rounding; pre-empt the UI with a "Not enough writing yet" state.
- **Maximum terms surfaced per pane: 5.** More overwhelms. Rank by `|z|` and truncate.
- **Background corpus: OpenSubtitles2018 v1** (~2.3M tokens post-filter), shipped at `packages/KilnCore/Resources/background-unigrams.v1.bin`. Do not compute from the web at runtime.
- **α (Dirichlet smoothing): 0.01** × `max(background_count_w, 1)`. Tuned empirically against a Brown + Messages reference set (`DECISIONS.md #N` once you change it).

## 2. Structural rates

Surface a structural claim only when **BOTH** hold:

- User rate is at least **2× baseline** or at most **0.5× baseline** (clear deviation).
- User base count ≥ **30** for the numerator (e.g. at least 30 sentences ending in `?`).

Baselines (`StructuralBaseline.v1`, per source type):

| Stat                       | Texts  | Email | Notes |
|----------------------------|--------|-------|-------|
| Question rate              | 18%    | 8%    | 4%    |
| Exclamation rate           | 6%     | 2%    | 0.8%  |
| All-lower sentence rate    | 32%    | 4%    | 7%    |
| Median sentence length     | 8 tok  | 15    | 18    |

Compare against the baseline of the user's **most-represented source** (resolved at ingest time). If sources are balanced within 25%, fall back to a blended baseline (weighted mean by token count).

## 3. Semantic similarity (cosine)

Vectors are L2-normalized → cosine = dot product ∈ `[-1, 1]`.

| cosine      | UI label                        | Example use                                          |
|-------------|---------------------------------|------------------------------------------------------|
| `≥ 0.90`    | "nearly identical"              | Near-duplicate in training data; hide unless asked.  |
| `≥ 0.85`    | "this sounds almost like X"     | Show with confidence.                                |
| `≥ 0.65`    | "similar voice"                 | Show as supporting example.                          |
| `≥ 0.50`    | "related topic"                 | Show as weak neighbor; de-emphasize.                 |
| `< 0.50`    | _(not surfaced)_                | Misleading to show as "your writing".                |

Guardrails:

- **Minimum corpus size to surface neighbors: 200 rows.** Below this, top-K retrieval is unstable across re-encodes of the same query.
- **K for top-K display: 3.** Never show more to the user at once.
- **Near-duplicate reject.** If top-1 cosine ≥ 0.97, hide it and show top-2 instead. Users don't want "this sounds like you" to mean "this IS this sentence".
- **Model version pin.** Record the model id in `embeddings.index.json`. Never compare cosines across different model versions — the geometry isn't compatible.

## 4. Rate-delta multipliers (for the "X× more than average" claim)

| Multiplier    | UI language                     |
|---------------|---------------------------------|
| ≥ 10×         | "10×+ more often"               |
| 4–10×         | e.g. "6× more often"            |
| 2–4×          | e.g. "3× more often"            |
| 0.5–2×        | _(not a claim; don't surface)_  |
| 0.25–0.5×     | e.g. "half as often"            |
| ≤ 0.25×       | "rare in your writing"          |

Cap the displayed multiplier at 10× even if computed value is higher (12.8× reads as noisy and we don't have the base-count confidence at the tail).

## 5. Display rounding

- **Percentages:** integer. `"73%"`, not `"72.8%"`.
- **z-scores:** one decimal, tooltip only. Never in the primary stat.
- **Multipliers:** one decimal up to 10× then `"10×+"`.
- **Cosine:** never shown as a raw number. Always translated via §3's label table.
- **Sentence length:** integer tokens. No "8.4 tokens" — meaningless at sentence granularity.

## 6. The only UI rule that matters

**Never show a number backed by fewer observations than the minimum above.** Show a "Keep adding samples" empty state instead. A false claim costs more trust than a missing one.

A user who sees "you use 'fundamentally' 14× more than average" once — when they have 120 total tokens of writing — will never trust the pane again. A user who sees "Not enough writing yet — add 400 more words to unlock lexical analysis" trusts that whatever is eventually shown passed a real bar.

## 7. Version history

- **v1 (2026-04)** — thresholds set at 1.96 / 2.58 for log-odds; 0.50 / 0.65 / 0.85 / 0.90 for cosine; 30 base count for structural. Justified empirically on `evals/interpretability-corpus-v1/` with N=12 test users; precision > 0.8 at these thresholds and recall > 0.6.

Increment the version here whenever any threshold moves. The Interpretability pane is allowed to display the version in a footer ("Thresholds v1") for traceability in user-reported bugs.

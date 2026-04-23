# Embedding setup — CoreML vs Python sidecar

See [SKILL.md §5](SKILL.md) for the why. This file is the operational walkthrough for setting up `all-MiniLM-L6-v2` for Kiln.

## Decision matrix

| Need                                                     | Ship via                   |
|----------------------------------------------------------|----------------------------|
| Batched encode of 10 000 rows at ingest time             | Python sidecar (batched)   |
| Single-row encode at query time (< 100 ms budget)        | CoreML in-proc (`.mlpackage`) |
| Top-K cosine over pre-encoded 10 k rows                  | Pure Swift + `Accelerate`  |
| One-off user-facing "why is this my top neighbor?" blurb | CoreML + locally computed similarity attribution |

Both paths use the same model: `sentence-transformers/all-MiniLM-L6-v2` (384-dim, 80 MB).

## Python sidecar path (ingest-time batched encode)

The `kiln_trainer` sidecar already has MLX and torch. Add `sentence-transformers` with a DECISIONS.md entry:

```toml
# packages/kiln_trainer/pyproject.toml
[project.dependencies]
"sentence-transformers" = "==2.7.*"
"torch" = "==2.3.*"  # CPU wheel is fine; MiniLM is small
```

CLI invocation (sidecar subcommand):

```bash
python -m kiln_trainer embed \
  --input  <run_dir>/samples.jsonl \
  --output <run_dir>/embeddings.f32.bin \
  --model  sentence-transformers/all-MiniLM-L6-v2 \
  --batch-size 64 \
  --max-seq-length 256 \
  --normalize
```

Progress events (one line per 500 rows):

```json
{"event":"embed_progress","done":4500,"total":10000}
```

Output is a flat `[n_rows × 384]` Float32 binary — **no header**, **no pickle**, **no numpy `.npy`**. The Swift side `mmap`s it and indexes by row offset. Write alongside `embeddings.index.json` with `{"rows": 10000, "dim": 384, "version": 1, "model": "sentence-transformers/all-MiniLM-L6-v2"}`.

**Normalize at write time.** Post-norm cosine = dot product; that's the whole game. If `--normalize` isn't honored, the top-K loop degrades to an inner-product with implicit magnitudes, and near-identical sentences with different lengths drift apart in the ranking.

## CoreML path (query-time, in-proc)

### 1. Convert once as a build step

`scripts/build-coreml-embedding.py`:

```python
import torch, coremltools as ct
from sentence_transformers import SentenceTransformer

m = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
m.eval()

dummy_ids  = torch.zeros(1, 256, dtype=torch.long)
dummy_mask = torch.ones(1, 256, dtype=torch.long)

traced = torch.jit.trace(
    m[0].auto_model,  # the underlying transformer; pooling done in Swift
    (dummy_ids, dummy_mask),
)

mlmodel = ct.convert(
    traced,
    inputs=[
        ct.TensorType(shape=(1, 256), dtype=ct.int32, name="input_ids"),
        ct.TensorType(shape=(1, 256), dtype=ct.int32, name="attention_mask"),
    ],
    outputs=[ct.TensorType(name="last_hidden_state")],
    minimum_deployment_target=ct.target.macOS14,
    compute_units=ct.ComputeUnit.CPU_AND_NE,
)
mlmodel.save("apps/Kiln/Resources/MiniLML6.mlpackage")
```

Ship the resulting `.mlpackage` inside the app bundle.

### 2. Swift inference

```swift
import Accelerate
import CoreML

final class OnDeviceEmbedder {
    private let model: MiniLML6
    private let tokenizer: BertTokenizer

    init() throws {
        self.model = try MiniLML6(configuration: MLModelConfiguration())
        self.tokenizer = try BertTokenizer(vocab: "vocab.txt")
    }

    func encode(_ text: String) throws -> [Float] {
        let (ids, mask) = tokenizer.encode(text, maxLen: 256)
        let inputIds = try MLMultiArray(shape: [1, 256], dataType: .int32)
        let attnMask = try MLMultiArray(shape: [1, 256], dataType: .int32)
        for i in 0..<256 {
            inputIds[i] = NSNumber(value: ids[i])
            attnMask[i] = NSNumber(value: mask[i])
        }
        let out = try model.prediction(input_ids: inputIds, attention_mask: attnMask)
        // Mean-pool last_hidden_state (1, 256, 384) with attention mask; L2-normalize.
        return meanPoolAndNormalize(out.last_hidden_state, mask: attnMask, dim: 384)
    }
}
```

Budget: 15–25 ms per encode on M2 with CPU+NE. Anything over 50 ms means tokenizer overhead — profile with Instruments' Points of Interest before blaming the model.

### 3. Mean pooling + L2 norm (must match the sidecar exactly)

```swift
private func meanPoolAndNormalize(
    _ hs: MLMultiArray, mask: MLMultiArray, dim: Int
) -> [Float] {
    var summed = [Float](repeating: 0, count: dim)
    var n: Float = 0
    let seqLen = 256
    for t in 0..<seqLen {
        let active = Float(truncating: mask[t])
        if active == 0 { continue }
        n += 1
        for d in 0..<dim {
            summed[d] += Float(truncating: hs[[0, t, d] as [NSNumber]])
        }
    }
    var mean = summed.map { $0 / max(n, 1) }
    // L2 normalize
    var sq: Float = 0
    vDSP_svesq(mean, 1, &sq, vDSP_Length(dim))
    let norm = max(sqrt(sq), 1e-12)
    var recip = 1 / norm
    vDSP_vsmul(mean, 1, &recip, &mean, 1, vDSP_Length(dim))
    return mean
}
```

## Cosine top-K via Accelerate

For 10 000 rows × 384 dim against one query vector, SIMD dot product is ~12 ms:

```swift
import Accelerate

func topK(
    query: UnsafePointer<Float>,
    corpus: UnsafePointer<Float>,
    rows: Int,
    dim: Int,
    k: Int
) -> [(row: Int, score: Float)] {
    var scores = [Float](repeating: 0, count: rows)
    for i in 0..<rows {
        let rowPtr = corpus.advanced(by: i * dim)
        scores[i] = cblas_sdot(Int32(dim), query, 1, rowPtr, 1)
    }
    // Vectors are pre-normalized; dot == cosine.
    let indexed = scores.enumerated().sorted { $0.1 > $1.1 }
    return indexed.prefix(k).map { (row: $0.0, score: $0.1) }
}
```

Profile with Instruments: if SIMD isn't firing, check that the corpus pointer is 16-byte-aligned (use `posix_memalign` when allocating the buffer).

## Golden tests (ship three)

`packages/KilnCore/Tests/KilnCoreTests/Interpretability/EmbeddingTests.swift`:

1. **Determinism.** Same sentence encoded twice → identical vectors (bit-exact). Proves no state leaks.
2. **Paraphrase similarity.** `"ship it"` vs `"let's release it"` → cosine > 0.6. Proves the model isn't mis-wired.
3. **Adversarial dissimilarity.** `"ship it"` vs `"hamburger"` → cosine < 0.3. Proves the geometry is real.
4. **Sidecar parity.** A fixed 20-sentence set encoded by the sidecar and by CoreML → per-row cosine ≥ 0.9995 between the two encoders. If this fails, the CoreML conversion rounded something wrong.

If (4) regresses after a model swap or conversion script change, the new build isn't ready. Don't publish.

## When to skip CoreML entirely

If the user's corpus is < 500 rows and only a handful of semantic queries happen per session, batch-encode everything in the sidecar once at ingest and call it done. The incremental CoreML complexity isn't worth it below ~1 k rows. Kiln's default ingest is 2–20 k rows, so plan on CoreML.

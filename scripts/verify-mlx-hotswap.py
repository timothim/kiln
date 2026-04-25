#!/usr/bin/env python3
"""Ten-minute verification: does mlx_lm let us hot-swap a LoRA adapter in-process?

Context
-------
The M7 `sample-compare` subcommand shows three variants side-by-side in Kiln's
Voice Mirror: base / SFT / SFT+DPO. The naive implementation spawns three
`mlx_lm.generate` subprocesses (one per variant), each of which reloads the
whole base model from disk. On a 3B-Instruct-4bit base that's ~5s × 3 = ~15s
of redundant load time before the first token appears.

If mlx_lm's Python API can load the base model once and swap adapters between
generations without leaking state between variants, we can cut that cost ~3×.
But the risk is silent contamination: if adapter-A's weights aren't fully
undone when adapter-B is applied, variant B's completions are corrupted —
and the user sees wrong output with no error.

This script tests that. Run it manually on a box with MLX + a real base model.
It is intentionally NOT part of the automated test suite: it needs multi-
gigabyte weights, GPU time, and ~5–10 minutes wall-clock. The *outcome* of
running it informs which code path `sample_compare.py` uses:

- **PASS** (outputs match between cold-load and hot-swap): safe to load once
  and swap. Add a `--load-once` opt-in flag to `sample-compare`.
- **FAIL** (outputs differ, or adapter-A residue bleeds into adapter-B): stick
  with three subprocesses, which is what `sample-compare` does today.

Until this script is run and passes, `sample-compare` uses the three-
subprocess path — correctness over speed.

Usage
-----
  uv run python scripts/verify-mlx-hotswap.py \\
      --model mlx-community/Qwen2.5-1.5B-Instruct-4bit \\
      --adapter-a /path/to/sft-only.safetensors \\
      --adapter-b /path/to/sft-plus-dpo.safetensors \\
      --prompt "What should I work on this week?"

The script runs six generations and prints a diff table:
  1. cold-load base, generate
  2. cold-load base, apply adapter-A, generate
  3. cold-load base, apply adapter-B, generate
  4. hot-swap path: load once, no adapter, generate
  5. hot-swap path: apply adapter-A, generate
  6. hot-swap path: swap to adapter-B, generate

Expected: cold #1 == hot #4, cold #2 == hot #5, cold #3 == hot #6. Any mismatch
means the hot-swap path is unsafe for `sample-compare`.
"""
from __future__ import annotations

import argparse
import json
import sys
import time


def _generate(model, tokenizer, prompt: str, max_tokens: int, seed: int) -> str:
    # Lazy import so `--help` works without MLX installed.
    from mlx_lm import generate as mlx_generate  # type: ignore[import-not-found]

    return mlx_generate(
        model=model,
        tokenizer=tokenizer,
        prompt=prompt,
        max_tokens=max_tokens,
        temp=0.0,  # greedy — reproducibility matters here, not creativity
        verbose=False,
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--adapter-a", required=True)
    ap.add_argument("--adapter-b", required=True)
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--max-tokens", type=int, default=80)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    try:
        from mlx_lm.utils import load  # type: ignore[import-not-found]
        from mlx_lm.tuner.utils import load_adapters  # type: ignore[import-not-found]
    except ImportError as exc:
        print(
            f"mlx_lm not importable ({exc}); install kiln_trainer's dev extras "
            "and rerun. This script is dev-only.",
            file=sys.stderr,
        )
        return 2

    results: dict[str, str] = {}

    # Cold path: three fresh loads.
    for label, adapter in (("cold_base", None), ("cold_a", args.adapter_a), ("cold_b", args.adapter_b)):
        t0 = time.perf_counter()
        model, tokenizer = load(args.model, adapter_path=adapter)
        out = _generate(model, tokenizer, args.prompt, args.max_tokens, args.seed)
        dt = time.perf_counter() - t0
        results[label] = out
        print(f"[{label}] {dt:.2f}s  {out[:80]!r}", flush=True)
        del model, tokenizer  # encourage GC between loads

    # Hot path: one load, then swap adapters in place.
    t0 = time.perf_counter()
    model, tokenizer = load(args.model, adapter_path=None)
    out = _generate(model, tokenizer, args.prompt, args.max_tokens, args.seed)
    results["hot_base"] = out
    print(f"[hot_base] {time.perf_counter() - t0:.2f}s  {out[:80]!r}", flush=True)

    load_adapters(model, args.adapter_a)
    out = _generate(model, tokenizer, args.prompt, args.max_tokens, args.seed)
    results["hot_a"] = out
    print(f"[hot_a]    {out[:80]!r}", flush=True)

    load_adapters(model, args.adapter_b)
    out = _generate(model, tokenizer, args.prompt, args.max_tokens, args.seed)
    results["hot_b"] = out
    print(f"[hot_b]    {out[:80]!r}", flush=True)

    # Diff the pairs that ought to match.
    pairs = [("cold_base", "hot_base"), ("cold_a", "hot_a"), ("cold_b", "hot_b")]
    mismatches = [p for p in pairs if results[p[0]] != results[p[1]]]

    verdict = "PASS (hot-swap is safe)" if not mismatches else "FAIL (hot-swap contaminates)"
    print("", flush=True)
    print(f"VERDICT: {verdict}", flush=True)
    if mismatches:
        for a, b in mismatches:
            print(f"  MISMATCH {a} != {b}", flush=True)
            print(f"    cold: {results[a]!r}", flush=True)
            print(f"    hot : {results[b]!r}", flush=True)

    # Machine-parseable summary on the last line.
    print(json.dumps({"pass": not mismatches, "mismatches": [list(p) for p in mismatches]}), flush=True)
    return 0 if not mismatches else 1


if __name__ == "__main__":
    sys.exit(main())

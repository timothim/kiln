#!/usr/bin/env python3
"""Opus-as-teacher distillation driver.

Labels a batch of inputs with Opus 4.7 for one of Kiln's three distilled
components (quality-classifier, preference-judge, style-extractor). Streams
labels to a JSONL file. Idempotent: skips rows already present in the output.

This script is a DEV-TIME tool. It is NEVER called from Kiln.app at runtime.

Usage:
    python scripts/opus-distill/run.py \\
        --component quality-classifier \\
        --input data/labeling/quality_inputs.jsonl \\
        --output distilled/quality-classifier/raw_labels.jsonl \\
        --budget 25 \\
        --concurrency 20

Environment:
    ANTHROPIC_API_KEY   required unless --dry-run
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

LOG = logging.getLogger("opus-distill")

OPUS_MODEL = "claude-opus-4-7"

# Per-component temperature / output cap; mirrors .claude/skills/distillation-pipeline §2
COMPONENT_CONFIG: dict[str, dict[str, Any]] = {
    "quality-classifier": {"temperature": 0.0, "max_tokens": 200},
    "preference-judge": {"temperature": 0.0, "max_tokens": 150},
    "style-extractor": {"temperature": 0.3, "max_tokens": 800},
}

# --- Prompts (the authoritative copies; mirrored in the skill file) -----

QUALITY_SYSTEM = """You are a quality judge for training data. You score how useful a single
snippet of text would be for teaching a language model to write in a specific user's voice.
High-quality snippets are: voice-bearing, coherent, at least one complete thought, not
boilerplate, not machine-generated. Low-quality: fragments, log output, auto-generated,
scraped HTML, repeated boilerplate.

Return a JSON object. No prose outside the JSON.
{"score": <float 0..1>, "reason": "<<= 20 words>"}"""

PREFERENCE_SYSTEM = """You judge which of two completions better matches a user's voice, given
their existing writing style signals. Return JSON:
{"winner": "A" | "B" | "tie", "margin": "large" | "small", "reason": "<<= 25 words>"}
No prose outside the JSON. Use "tie" only when the two are nearly indistinguishable."""

STYLE_SYSTEM = """You read a writing sample and produce a style card plus a compact style vector.

Output JSON:
{
  "card": {
    "summary": "<2-3 sentence human-readable summary>",
    "traits": [
      {"trait": "<name>", "value": "<value>", "evidence": "<short>"}
    ]
  },
  "vector": [<64 floats in -1..1>]
}
No prose outside the JSON."""


SYSTEM_PROMPTS = {
    "quality-classifier": QUALITY_SYSTEM,
    "preference-judge": PREFERENCE_SYSTEM,
    "style-extractor": STYLE_SYSTEM,
}


@dataclass
class DistillArgs:
    component: str
    input_path: Path
    output_path: Path
    budget_usd: float
    concurrency: int
    dry_run: bool


def format_user_prompt(component: str, row: dict[str, Any]) -> str:
    """Assemble the user-turn prompt for one labeling row."""
    if component == "quality-classifier":
        text = (row.get("text") or "")[:1000]
        return f"Snippet:\n```\n{text}\n```"
    if component == "preference-judge":
        return (
            "Style signals (compact):\n"
            + "\n".join(f"- {s}" for s in row.get("style_signals", []))
            + f"\n\nPrompt:\n{row.get('prompt', '')}\n\n"
            + f"Completion A:\n{row.get('completion_a', '')}\n\n"
            + f"Completion B:\n{row.get('completion_b', '')}"
        )
    if component == "style-extractor":
        return f"Sample:\n```\n{row.get('text', '')[:2000]}\n```"
    raise ValueError(f"unknown component: {component}")


def already_labeled(output_path: Path) -> set[str]:
    """Return the set of `request_id`s already present in the output file."""
    if not output_path.exists():
        return set()
    seen: set[str] = set()
    with output_path.open("r", encoding="utf-8") as f:
        for line in f:
            try:
                rec = json.loads(line)
                if rid := rec.get("request_id"):
                    seen.add(rid)
            except json.JSONDecodeError:
                continue
    return seen


def estimate_cost(component: str, row_count: int) -> float:
    """Very rough upper bound on the USD cost of labeling `row_count` rows.
    Numbers are placeholders; update when actual pricing is confirmed."""
    # Per-component average in/out tokens — same numbers as the skill cost table.
    cfg = {
        "quality-classifier": (800, 80),
        "preference-judge": (1200, 120),
        "style-extractor": (1500, 500),
    }[component]
    in_tok, out_tok = cfg
    # Placeholder price: $15/Mtok input, $75/Mtok output (conservative upper bound).
    per_row = (in_tok * 15 + out_tok * 75) / 1_000_000
    return round(per_row * row_count, 2)


def call_opus_batch(
    component: str, rows: list[dict[str, Any]], concurrency: int, dry_run: bool
) -> list[dict[str, Any]]:
    """Call Opus for a batch of rows, up to `concurrency` in-flight. Returns
    the list of parsed JSON responses, aligned to `rows`.

    TODO: replace with the async Anthropic SDK implementation:
      from anthropic import AsyncAnthropic
      import asyncio
      client = AsyncAnthropic()
      sem = asyncio.Semaphore(concurrency)
      async def one(row):
          async with sem:
              msg = await client.messages.create(
                  model=OPUS_MODEL,
                  max_tokens=COMPONENT_CONFIG[component]["max_tokens"],
                  temperature=COMPONENT_CONFIG[component]["temperature"],
                  system=SYSTEM_PROMPTS[component],
                  messages=[{"role":"user","content":format_user_prompt(component, row)}],
              )
              return json.loads(msg.content[0].text)
      return asyncio.run(asyncio.gather(*(one(r) for r in rows)))
    """
    if dry_run:
        preview = format_user_prompt(component, rows[0])
        LOG.info("[dry-run] would call Opus on %d rows with concurrency=%d", len(rows), concurrency)
        LOG.info("[dry-run] first user prompt:\n%s", preview[:800])
        return [{"_dry_run": True} for _ in rows]

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        LOG.error("ANTHROPIC_API_KEY not set; use --dry-run for preview")
        sys.exit(2)

    raise NotImplementedError(
        "Wire up the Anthropic async SDK call here; the prompts and parsing are ready."
    )


def write_label(output_path: Path, record: dict[str, Any]) -> None:
    with output_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False))
        f.write("\n")


def load_inputs(input_path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with input_path.open("r", encoding="utf-8") as f:
        for lineno, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as e:
                LOG.warning("skipping malformed line %d: %s", lineno, e)
    return rows


def parse_args(argv: list[str]) -> DistillArgs:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--component", required=True, choices=list(COMPONENT_CONFIG.keys()))
    p.add_argument("--input", type=Path, required=True, dest="input_path")
    p.add_argument("--output", type=Path, required=True, dest="output_path")
    p.add_argument("--budget", type=float, default=25.0, dest="budget_usd", help="hard USD cap")
    p.add_argument("--concurrency", type=int, default=20)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("-v", "--verbose", action="store_true")
    args = p.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    return DistillArgs(
        component=args.component,
        input_path=args.input_path,
        output_path=args.output_path,
        budget_usd=args.budget_usd,
        concurrency=args.concurrency,
        dry_run=args.dry_run,
    )


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])

    if not args.input_path.exists():
        LOG.error("input not found: %s", args.input_path)
        return 2

    rows = load_inputs(args.input_path)
    LOG.info("loaded %d input rows", len(rows))

    already = already_labeled(args.output_path)
    remaining = [r for r in rows if r.get("request_id") and r["request_id"] not in already]
    LOG.info("%d already labeled; %d to go", len(rows) - len(remaining), len(remaining))

    est = estimate_cost(args.component, len(remaining))
    LOG.info("estimated cost: $%.2f (budget: $%.2f)", est, args.budget_usd)
    if est > args.budget_usd and not args.dry_run:
        LOG.error("estimated cost exceeds budget; re-run with --budget > %.2f or reduce input", est)
        return 3

    args.output_path.parent.mkdir(parents=True, exist_ok=True)

    # In real use, stream batches; for the stub we send all at once via the TODO'd call.
    try:
        responses = call_opus_batch(args.component, remaining, args.concurrency, args.dry_run)
    except NotImplementedError as e:
        LOG.error("not wired yet: %s", e)
        return 4

    for row, resp in zip(remaining, responses, strict=False):
        write_label(
            args.output_path,
            {
                "request_id": row.get("request_id"),
                "input": row,
                "opus_model": OPUS_MODEL,
                "response": resp,
            },
        )

    LOG.info("done. wrote %d labels to %s", len(remaining), args.output_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())

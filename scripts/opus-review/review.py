#!/usr/bin/env python3
"""Nightly Opus 4.7 code review.

Reads a git diff, sends it to Opus with a structured review prompt, writes the
response as JSON, and prints a human-readable summary.

This script is a DEV-TIME tool. It is NEVER called from Kiln.app at runtime.

Usage:
    python scripts/opus-review/review.py --range main..HEAD --out docs/reviews/2026-04-22.json
    python scripts/opus-review/review.py --pr 42
    python scripts/opus-review/review.py --dry-run --range main..HEAD

Environment:
    ANTHROPIC_API_KEY   required unless --dry-run
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

LOG = logging.getLogger("opus-review")

OPUS_MODEL = "claude-opus-4-7"
MAX_DIFF_CHARS = 120_000  # hard cap; large diffs get chunked

SYSTEM_PROMPT = """You are a senior engineer reviewing a diff for the Kiln
project — a native macOS app that fine-tunes a local LLM on a folder of the
user's writing. The Kiln runtime calls zero external APIs; dev-time tooling
(this script, the distillation pipeline) is the only place Opus is used.

Review the provided diff for:
  - correctness bugs (off-by-one, wrong type, wrong API contract)
  - concurrency bugs (Swift actor mistakes, Python thread/MLX interaction)
  - memory issues (unbounded accumulators, cycles, large arrays held)
  - API misuse (mlx_lm flags against the pinned version, Ollama REST)
  - security (secrets in logs, shell-exec with user input, outbound network
    from code that ships in Kiln.app)
  - SPEC deviations (compare to the referenced SPEC.md sections)
  - polish opportunities (microcopy, empty states) — low priority

Return strictly valid JSON matching this schema; do NOT include prose outside
the JSON:

{
  "verdict": "pass" | "pass-with-findings" | "request-changes",
  "summary": "<= 3 sentences",
  "findings": [
    {
      "severity": "blocker" | "high" | "medium" | "low" | "nit",
      "category": "correctness" | "concurrency" | "memory" | "api" | "security" | "spec" | "polish",
      "file": "<path>",
      "line": <int or null>,
      "what": "<one sentence>",
      "why":  "<one sentence>",
      "fix":  "<one sentence>"
    }
  ],
  "green_lights": ["<short positive observation>", ...]
}
"""

USER_TEMPLATE = """Review the following diff.

Repository: kiln
Range: {range}
Commits:
{commits}

Relevant SPEC sections (paste inline):
{spec_excerpts}

Diff (may be truncated):
```diff
{diff}
```
"""


@dataclass
class ReviewArgs:
    range: str
    pr: int | None
    out: Path
    dry_run: bool
    spec_path: Path


def run(cmd: list[str]) -> str:
    """Run a shell command; return stdout. Raise on nonzero."""
    LOG.debug("$ %s", " ".join(cmd))
    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return result.stdout


def collect_diff(args: ReviewArgs) -> tuple[str, str]:
    """Return (diff_text, commit_list_text)."""
    if args.pr is not None:
        # TODO: shell out to `gh pr diff <N>` when gh is installed; fallback to range.
        raise NotImplementedError("--pr mode: wire up `gh pr diff` here")

    diff_text = run(["git", "diff", args.range])
    commits = run(["git", "log", "--oneline", args.range])
    if len(diff_text) > MAX_DIFF_CHARS:
        LOG.warning("diff is %d chars; truncating to %d", len(diff_text), MAX_DIFF_CHARS)
        diff_text = diff_text[:MAX_DIFF_CHARS] + "\n... (truncated)"
    return diff_text, commits


def gather_spec_excerpts(spec_path: Path, diff_text: str) -> str:
    """Heuristic: if the diff touches files in `apps/Kiln` or `packages/KilnCore`,
    include SPEC section headers for §4 (Architecture) and §11 (IPC); for
    `packages/kiln_trainer`, include §6 (Training). Keep this file small —
    we want the diff in the context, not the whole spec."""
    if not spec_path.exists():
        return "(SPEC.md not found)"

    try:
        spec = spec_path.read_text(encoding="utf-8")
    except OSError as e:
        LOG.warning("could not read SPEC: %s", e)
        return "(SPEC.md unreadable)"

    sections: list[str] = []
    if "packages/kiln_trainer" in diff_text:
        sections.append(_extract_section(spec, "## 6. Training pipeline spec"))
    if "apps/Kiln" in diff_text or "packages/KilnCore" in diff_text:
        sections.append(_extract_section(spec, "## 4. Architecture"))
        sections.append(_extract_section(spec, "## 11. IPC protocol"))
    if "distilled/" in diff_text or "scripts/opus-distill" in diff_text:
        sections.append(_extract_section(spec, "## 7. Opus-as-teacher distillation pipeline"))

    return "\n\n".join(s for s in sections if s) or "(no matching spec sections)"


def _extract_section(spec: str, header: str) -> str:
    """Return text from `header` to the next top-level `## ` header, or EOF."""
    start = spec.find(header)
    if start < 0:
        return ""
    # Find the next `## ` at the start of a line after `start + len(header)`.
    idx = spec.find("\n## ", start + len(header))
    return spec[start:idx] if idx > 0 else spec[start:]


def call_opus(system: str, user: str, dry_run: bool) -> dict[str, Any]:
    """Send the review request to Opus. Returns the parsed JSON response.

    DRY RUN prints the request and exits; LIVE mode calls the Anthropic API.
    """
    if dry_run:
        print("=== SYSTEM ===")
        print(system)
        print("=== USER ===")
        print(user[:2000])
        print("... (truncated)" if len(user) > 2000 else "")
        return {"verdict": "dry-run", "summary": "", "findings": [], "green_lights": []}

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        LOG.error("ANTHROPIC_API_KEY not set; use --dry-run to test without calling the API")
        sys.exit(2)

    # TODO: replace with `anthropic` SDK call:
    #   from anthropic import Anthropic
    #   client = Anthropic()
    #   msg = client.messages.create(
    #       model=OPUS_MODEL,
    #       max_tokens=4096,
    #       system=system,
    #       messages=[{"role": "user", "content": user}],
    #   )
    #   text = msg.content[0].text
    #   return json.loads(text)
    raise NotImplementedError(
        "Wire up the Anthropic SDK call here; the prompt and parsing are ready."
    )


def write_report(review: dict[str, Any], out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(review, indent=2), encoding="utf-8")
    LOG.info("wrote %s", out)


def print_summary(review: dict[str, Any]) -> None:
    verdict = review.get("verdict", "?")
    findings = review.get("findings", [])
    green = review.get("green_lights", [])
    print(f"\nOpus review verdict: {verdict}")
    print(f"Summary: {review.get('summary', '')}\n")
    by_sev: dict[str, int] = {}
    for f in findings:
        by_sev[f.get("severity", "?")] = by_sev.get(f.get("severity", "?"), 0) + 1
    for sev in ("blocker", "high", "medium", "low", "nit"):
        if by_sev.get(sev):
            print(f"  {sev}: {by_sev[sev]}")
    for g in green[:3]:
        print(f"  + {g}")


def parse_args(argv: list[str]) -> ReviewArgs:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--range", default="main..HEAD", help="git revision range (default: main..HEAD)")
    p.add_argument("--pr", type=int, default=None, help="GitHub PR number (uses `gh pr diff`)")
    p.add_argument(
        "--out",
        type=Path,
        default=Path(f"docs/reviews/{datetime.now(tz=timezone.utc):%Y-%m-%d}.json"),
        help="output JSON path",
    )
    p.add_argument("--dry-run", action="store_true", help="print the request without calling Opus")
    p.add_argument("--spec", type=Path, default=Path("SPEC.md"), help="path to SPEC.md")
    p.add_argument("-v", "--verbose", action="store_true")
    args = p.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    return ReviewArgs(range=args.range, pr=args.pr, out=args.out, dry_run=args.dry_run, spec_path=args.spec)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    try:
        diff_text, commits = collect_diff(args)
    except subprocess.CalledProcessError as e:
        LOG.error("git failed: %s", e.stderr.strip() if e.stderr else e)
        return 2

    spec_excerpts = gather_spec_excerpts(args.spec_path, diff_text)
    user = USER_TEMPLATE.format(range=args.range, commits=commits, spec_excerpts=spec_excerpts, diff=diff_text)

    try:
        review = call_opus(SYSTEM_PROMPT, user, dry_run=args.dry_run)
    except NotImplementedError as e:
        LOG.error("not wired yet: %s", e)
        return 3

    write_report(review, args.out)
    print_summary(review)
    return 0


if __name__ == "__main__":
    sys.exit(main())

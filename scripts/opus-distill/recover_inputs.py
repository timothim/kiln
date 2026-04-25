#!/usr/bin/env python3
"""Re-join Opus-4.7 labels with their original inputs (M9.C Phase 0 recovery).

The recovered Managed-Agents runs at ``managed-agents/<component>/runs/.../``
contain only the *outputs* the agent produced — preference winners, style
profiles, and quality scores. The matching *inputs* (preference pairs and
style source texts) live behind file_ids the public Files API marks
``downloadable=false``, so we can't fetch them by ID.

Two seed-deterministic generators that produced the original uploads are
checked into this repo:

  - ``build_preference_pilot_input.py --size 2000`` → preference pairs
  - ``build_style_input.py --size 1500``           → style source texts

Re-running them locally reproduces the *exact* request_ids the labelling
runs saw — verified against the recovered label files (100% intersection
on both sets). This script joins inputs ↔ labels and writes the merged
JSONL training files used by ``classifiers/preference.py`` and
``classifiers/style.py``.

Usage:
  python scripts/opus-distill/recover_inputs.py --component preference
  python scripts/opus-distill/recover_inputs.py --component style
  python scripts/opus-distill/recover_inputs.py --all
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

PREF_LABELS = (
    REPO_ROOT
    / "managed-agents/preference-judge/runs/20260424T204256Z_recovered/preference-labels.jsonl"
)
STYLE_LABELS = (
    REPO_ROOT
    / "managed-agents/style-extractor/runs/20260424T212708Z_recovered/style-profiles.jsonl"
)
QUALITY_LABELS = (
    REPO_ROOT
    / "managed-agents/corpus-builder/runs/20260424T195032Z_recovered/quality-labels.jsonl"
)

PREF_OUT = (
    REPO_ROOT
    / "managed-agents/preference-judge/runs/20260424T204256Z_recovered/preference-with-inputs.jsonl"
)
STYLE_OUT = (
    REPO_ROOT
    / "managed-agents/style-extractor/runs/20260424T212708Z_recovered/style-with-inputs.jsonl"
)


def _read_jsonl(path: Path) -> list[dict]:
    rows: list[dict] = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def _write_jsonl(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")


def _regenerate_inputs(generator_script: Path, size: int, dest: Path) -> None:
    """Run a build_*_input.py generator with the recorded size."""
    subprocess.run(
        [sys.executable, str(generator_script), "--size", str(size), "--out", str(dest)],
        check=True,
    )


def recover_preference(*, output_path: Path = PREF_OUT) -> dict:
    """Regenerate the 2000-row preference input JSONL via
    ``build_preference_pilot_input.py --size 2000``, join against the
    recovered labels by ``request_id``, and write the joined rows to
    ``output_path``. Returns a small report dict."""
    labels = _read_jsonl(PREF_LABELS)
    label_map = {r["request_id"]: r for r in labels}

    tmp = REPO_ROOT / "managed-agents/preference-judge/runs/20260424T204256Z_recovered/_inputs.jsonl"
    _regenerate_inputs(
        REPO_ROOT / "scripts/opus-distill/build_preference_pilot_input.py",
        size=len(labels),
        dest=tmp,
    )
    inputs = _read_jsonl(tmp)
    tmp.unlink(missing_ok=True)
    input_map = {r["request_id"]: r for r in inputs}

    joined: list[dict] = []
    for rid, label in label_map.items():
        inp = input_map.get(rid)
        if inp is None:
            continue
        joined.append(
            {
                "request_id": rid,
                "prompt": inp["prompt"],
                "completion_a": inp["completion_a"],
                "completion_b": inp["completion_b"],
                "winner": label["winner"],
                "reason": label.get("reason", ""),
            }
        )
    _write_jsonl(output_path, joined)
    return {
        "labels": len(labels),
        "inputs_regenerated": len(inputs),
        "joined": len(joined),
        "missing": len(labels) - len(joined),
        "out": str(output_path),
    }


def recover_style(*, output_path: Path = STYLE_OUT) -> dict:
    """Regenerate the 1500-row style input JSONL via
    ``build_style_input.py --size 1500``, join against the recovered
    style-profiles by ``request_id``, and write the joined rows to
    ``output_path``."""
    labels = _read_jsonl(STYLE_LABELS)
    label_map = {r["request_id"]: r for r in labels}

    tmp = REPO_ROOT / "managed-agents/style-extractor/runs/20260424T212708Z_recovered/_inputs.jsonl"
    _regenerate_inputs(
        REPO_ROOT / "scripts/opus-distill/build_style_input.py",
        size=len(labels),
        dest=tmp,
    )
    inputs = _read_jsonl(tmp)
    tmp.unlink(missing_ok=True)
    input_map = {r["request_id"]: r for r in inputs}

    joined: list[dict] = []
    for rid, label in label_map.items():
        inp = input_map.get(rid)
        if inp is None:
            continue
        joined.append(
            {
                "request_id": rid,
                "text": inp["text"],
                "style_descriptors": label["style_descriptors"],
                "distinctive_ngrams": label.get("distinctive_ngrams", []),
                "style_card_md": label.get("style_card_md", ""),
            }
        )
    _write_jsonl(output_path, joined)
    return {
        "labels": len(labels),
        "inputs_regenerated": len(inputs),
        "joined": len(joined),
        "missing": len(labels) - len(joined),
        "out": str(output_path),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--component",
        choices=["preference", "style"],
        help="join one component's inputs with its labels",
    )
    ap.add_argument(
        "--all",
        action="store_true",
        help="join both preference and style components",
    )
    args = ap.parse_args()

    if not args.all and not args.component:
        ap.error("supply --component or --all")

    if args.all or args.component == "preference":
        report = recover_preference()
        print("preference:", json.dumps(report, indent=2))
    if args.all or args.component == "style":
        report = recover_style()
        print("style:", json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())

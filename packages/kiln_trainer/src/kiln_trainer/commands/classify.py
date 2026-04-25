"""``kiln_trainer classify`` — distilled-classifier inference subcommand (M9.C).

Reads JSONL input rows of ``{"request_id": <str>, "text": <str>}``,
emits one ``classification`` event per row, then a final
``done(stage="classify")``. The Swift parent reads the events to gate
ingestion (quality), populate the Style Signature Card (style), or
generate DPO pairs (preference, applied to chunk windows).

The subcommand keeps a single sklearn pipeline cached across rows in
the parent process, so a 500-row classification run is one model load
+ N predict calls rather than N×N. Heuristic classifiers (preference,
style) carry no model state — they pay only feature-extraction cost
per call.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from kiln_trainer import events, runtime
from kiln_trainer.classifiers import preference, quality, style


def _classify_one(text: str, *, mode: str, artifact_path: Path | None) -> dict:
    if mode == "quality":
        if artifact_path is None or not artifact_path.exists():
            raise FileNotFoundError(
                f"--artifact required for quality classifier; not found: {artifact_path}"
            )
        result = quality.score(text, artifact_path=artifact_path)
        return {"score": round(result.score, 6), "bucket": result.bucket}
    if mode == "style":
        # Single-text style extraction. The style module's idiom is corpus-
        # at-a-time (it pools chunk-level descriptors); we feed the one text
        # as a single-element corpus. Trained regressor when an artifact
        # path is supplied, heuristic fallback otherwise — the runner can
        # ship without a model and still produce sensible output.
        profile = style.extract([text], artifact_path=artifact_path)
        return profile.to_dict()
    if mode == "preference":
        # Single-row preference is meaningless without a counterpart; the
        # mode here scores ``text`` on the voice-vs-generic axis so the
        # Swift caller can pair-rank later. The pairwise trained model
        # is reachable via ``score_pair_trained(...)`` directly when both
        # sides are available.
        return {"voice_score": round(preference.voice_score(text), 6)}
    raise ValueError(f"unknown classifier mode: {mode}")


def run(args: argparse.Namespace) -> int:
    sigterm = runtime.install_sigterm_handler()

    if args.text is not None:
        try:
            payload = _classify_one(
                args.text, mode=args.mode, artifact_path=args.artifact
            )
        except (FileNotFoundError, ValueError) as exc:
            code = "adapter_invalid" if isinstance(exc, FileNotFoundError) else "internal"
            events.emit(events.error(code=code, message=str(exc), recoverable=False))
            events.emit(events.done(stage="classify", artifact="stdout", interrupted=False))
            return 1
        events.emit(
            events.classification(
                request_id=args.request_id or "single",
                kind=args.mode,
                payload=payload,
            )
        )
        events.emit(events.done(stage="classify", artifact="stdout", interrupted=False))
        return 0

    if args.input_file is None:
        events.emit(
            events.error(
                code="internal",
                message="classify requires either --text or --input-file",
                recoverable=False,
            )
        )
        events.emit(events.done(stage="classify", artifact="stdout", interrupted=False))
        return 2

    rows_processed = 0
    interrupted = False
    try:
        with open(args.input_file, encoding="utf-8") as fh:
            for line in fh:
                if sigterm.is_set():
                    interrupted = True
                    break
                line = line.strip()
                if not line:
                    continue
                obj = json.loads(line)
                rid = str(obj.get("request_id") or rows_processed)
                text = obj.get("text") or ""
                try:
                    payload = _classify_one(
                        text, mode=args.mode, artifact_path=args.artifact
                    )
                except (FileNotFoundError, ValueError) as exc:
                    events.emit(
                        events.error(
                            code="internal",
                            message=str(exc),
                            recoverable=True,
                        )
                    )
                    continue
                events.emit(
                    events.classification(request_id=rid, kind=args.mode, payload=payload)
                )
                rows_processed += 1
    except FileNotFoundError as exc:
        events.emit(
            events.error(
                code="internal",
                message=f"input file not found: {exc}",
                recoverable=False,
            )
        )
        events.emit(events.done(stage="classify", artifact="stdout", interrupted=False))
        return 1

    events.emit(events.done(stage="classify", artifact="stdout", interrupted=interrupted))
    return 0

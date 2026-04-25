"""``kiln_trainer ingest-via-agent`` — Phase 3 entry point.

Thin CLI shim that wires argparse → ``ingest_agent.orchestrator.run_orchestrator``.
The heavy lifting (event emission, reader dispatch, Opus call, dedup,
write JSONL) lives in ``ingest_agent/orchestrator.py``."""

from __future__ import annotations

import argparse

from kiln_trainer.ingest_agent.orchestrator import run_orchestrator


def run(args: argparse.Namespace) -> int:
    sources = [s.strip() for s in (args.sources or "").split(",") if s.strip()]
    return run_orchestrator(
        sources=sources,
        intent=args.intent,
        local=args.local,
        output_path=args.output,
        documents_root=args.documents_root,
        per_source_limit=args.per_source_limit,
    )

"""Saturday Phase 3 — agent-orchestrated ingestion (MCP-powered).

Master orchestrator (``orchestrator.py``) reads a list of source
identifiers + an optional user intent string ("personal writing",
"professional emails", etc.), spawns the corresponding readers in
``readers/``, aggregates the candidate samples, and asks Claude
Opus 4.7 (or local Qwen via Ollama) to filter to the user's intent.
The output is a clean JSONL ready for the Dataset Doctor.

Sources implemented:
- ``local_documents``: walks a directory, returns text-bearing files.
  Always available, no MCP, baseline functional source.
- ``apple_notes``: AppleScript scraper fallback. Document the lack
  of a mature Apple Notes MCP server in the PR body.
- ``gmail``, ``notion``: scaffold only ("v2 — coming soon"). Surface
  in UI as grayed-out source cards.

Local mode: when the user toggles "Run agent locally", the
orchestrator skips Opus and uses a deterministic heuristic filter
(quality classifier + simple intent keyword match). Lower quality
curation but private."""

from kiln_trainer.ingest_agent import orchestrator, readers

__all__ = ["orchestrator", "readers"]

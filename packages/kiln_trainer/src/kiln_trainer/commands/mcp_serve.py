"""``kiln_trainer mcp-serve`` — Kiln voice as an MCP stdio server (Phase 2).

The user trained a model. They want Claude.app (or Claude Code) to
write in that voice. This subcommand exposes one tool —
``write_in_user_voice(prompt, max_tokens)`` — over the standard MCP
stdio transport. Claude.app spawns this as a subprocess via its mcp
config (``~/Library/Application Support/Claude/claude_desktop_config.json``)
and gets a tool that proxies completions to the local Ollama daemon
running the user's trained model.

**No cloud anywhere in the data path.** The MCP transport is stdio
(Claude.app ↔ this subprocess); the inference is local Ollama
(127.0.0.1:11434). The user's voice never leaves their machine —
the only thing that crosses the wire is Claude.app's prompt request,
which goes through Claude.app itself, not Kiln.

Auth: stdio MCP doesn't need bearer tokens (the transport is
parent-process-spawned-child, inherently authenticated by the OS).
The directive's "URL + token + ready-to-paste config" turns into a
ready-to-paste JSON config snippet for Claude.app instead — Swift's
``MCPServerManager`` shows that snippet in Settings.

Wire format: standard MCP JSON-RPC over stdio. Not Kiln's own
event-line protocol — this subcommand owns its own stdout for the
MCP transport.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import urllib.error
import urllib.request


DEFAULT_VOICE_NAME = "kiln-tim"


def _query_ollama(*, model: str, prompt: str, max_tokens: int) -> str:
    """Sync helper: hit ``/api/chat`` on the local Ollama daemon and
    return the assistant's content. Used by the async tool handler
    via ``asyncio.to_thread``."""
    body = json.dumps(
        {
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "stream": False,
            "options": {"num_predict": max_tokens},
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        "http://127.0.0.1:11434/api/chat",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            payload = json.loads(response.read())
    except urllib.error.URLError as exc:
        raise ConnectionError(
            f"Ollama daemon unreachable at 127.0.0.1:11434 — start with "
            f"`ollama serve`. ({exc})"
        ) from exc

    msg = payload.get("message") or {}
    content = msg.get("content") or ""
    return content.strip()


async def _serve(voice_name: str) -> None:
    """Start the MCP stdio server. Lazily imports the SDK so the
    test seam path doesn't pay the import cost."""
    from mcp.server import Server
    from mcp.server.stdio import stdio_server
    from mcp.types import TextContent, Tool

    server: Server = Server("kiln-voice")

    @server.list_tools()
    async def _list_tools() -> list[Tool]:
        return [
            Tool(
                name="write_in_user_voice",
                description=(
                    "Generate text in the user's trained Kiln voice "
                    f"(model: {voice_name}). Useful when Claude is "
                    "drafting on behalf of the user and wants the "
                    "output to sound like them."
                ),
                inputSchema={
                    "type": "object",
                    "properties": {
                        "prompt": {
                            "type": "string",
                            "description": (
                                "What to write. The user's trained voice "
                                "will respond as if asked directly."
                            ),
                        },
                        "max_tokens": {
                            "type": "integer",
                            "description": "Max generation length (default 200).",
                            "default": 200,
                            "minimum": 1,
                            "maximum": 1024,
                        },
                    },
                    "required": ["prompt"],
                },
            )
        ]

    @server.call_tool()
    async def _call_tool(name: str, arguments: dict) -> list[TextContent]:
        if name != "write_in_user_voice":
            raise ValueError(f"unknown tool: {name}")
        prompt = arguments.get("prompt", "")
        if not prompt:
            return [TextContent(type="text", text="(no prompt supplied)")]
        max_tokens = int(arguments.get("max_tokens", 200))
        text = await asyncio.to_thread(
            _query_ollama, model=voice_name, prompt=prompt, max_tokens=max_tokens
        )
        return [TextContent(type="text", text=text)]

    async with stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            server.create_initialization_options(),
        )


def run(args: argparse.Namespace) -> int:
    """Entry from ``kiln_trainer mcp-serve``. Long-running. Exits on
    SIGTERM (asyncio cancellation) or stdin close."""
    voice_name = args.voice_name or os.environ.get("KILN_VOICE_NAME", DEFAULT_VOICE_NAME)
    # MCP stdio server claims its own stdout for the JSON-RPC protocol.
    # Anything we want to log goes to stderr.
    sys.stderr.write(f"kiln-voice mcp server starting (voice={voice_name})\n")
    sys.stderr.flush()
    try:
        asyncio.run(_serve(voice_name))
    except KeyboardInterrupt:
        return 0
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"kiln-voice mcp server failed: {exc}\n")
        return 1
    return 0

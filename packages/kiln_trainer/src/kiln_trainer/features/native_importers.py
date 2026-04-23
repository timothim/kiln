"""Python parsers that back the macOS-native importers (chat.db, Notes,
mbox, Obsidian). The permission / TCC flow stays in Swift; this module
only receives already-readable source payloads and emits normalized
chunks. Lands alongside `NativeImporters.swift`.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

IS_IMPLEMENTED: bool = False


@dataclass(frozen=True)
class NativeChunk:
    source: str
    author: str
    text: str
    timestamp_ms: int


def parse_messages_export(_path: Path) -> Iterator[NativeChunk]:
    raise NotImplementedError("messages parser lands with NativeImporters.swift")


def parse_notes_export(_path: Path) -> Iterator[NativeChunk]:
    raise NotImplementedError("notes parser lands with NativeImporters.swift")


def parse_obsidian_vault(_path: Path) -> Iterator[NativeChunk]:
    raise NotImplementedError("obsidian parser lands with NativeImporters.swift")

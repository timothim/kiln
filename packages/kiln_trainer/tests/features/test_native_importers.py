"""Tests for the native-importer parser scaffolds."""
from pathlib import Path

import pytest

from kiln_trainer.features import native_importers


def test_messages_parser_raises_not_implemented():
    with pytest.raises(NotImplementedError):
        list(native_importers.parse_messages_export(Path("/tmp/nope")))


def test_notes_parser_raises_not_implemented():
    with pytest.raises(NotImplementedError):
        list(native_importers.parse_notes_export(Path("/tmp/nope")))


def test_obsidian_parser_raises_not_implemented():
    with pytest.raises(NotImplementedError):
        list(native_importers.parse_obsidian_vault(Path("/tmp/nope")))


def test_is_implemented_flag_is_false_until_m6():
    assert native_importers.IS_IMPLEMENTED is False


@pytest.mark.skipif(
    not native_importers.IS_IMPLEMENTED,
    reason="Native importers land alongside NativeImporters.swift",
)
def test_future_chunks_carry_source_tag():
    pass

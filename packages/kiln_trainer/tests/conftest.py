"""Shared pytest fixtures for the sidecar test suite."""

from __future__ import annotations

from pathlib import Path

import pytest


@pytest.fixture
def fixtures_dir() -> Path:
    return Path(__file__).parent / "fixtures"


@pytest.fixture
def fake_trainer(fixtures_dir: Path) -> Path:
    return fixtures_dir / "fake_trainer.py"


@pytest.fixture
def fake_generator(fixtures_dir: Path) -> Path:
    return fixtures_dir / "fake_generator.py"


@pytest.fixture
def fake_batch_generator(fixtures_dir: Path) -> Path:
    return fixtures_dir / "fake_batch_generator.py"


@pytest.fixture
def tiny_dataset(fixtures_dir: Path) -> Path:
    return fixtures_dir / "tiny_chatml.jsonl"

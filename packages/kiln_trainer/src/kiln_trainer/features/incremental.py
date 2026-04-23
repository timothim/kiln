"""Incremental LoRA training — resume from an existing adapter checkpoint
on additional corpus. The Swift glue lives in
`packages/KilnCore/Sources/KilnCore/Features/IncrementalLearning.swift`;
this module owns the actual mlx_lm.lora invocation plus the manifest
merge.

Lands in M6+. Until then `continue_training` raises NotImplementedError
and `IS_IMPLEMENTED` is False so callers can branch cheaply.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

IS_IMPLEMENTED: bool = False


@dataclass(frozen=True)
class IncrementalRequest:
    base_adapter_dir: Path
    additional_corpus_jsonl: Path
    extra_epochs: int


@dataclass(frozen=True)
class IncrementalResult:
    new_adapter_dir: Path
    steps_added: int
    final_loss: float


def continue_training(request: IncrementalRequest) -> IncrementalResult:
    """Resume training from `request.base_adapter_dir` on the new corpus."""
    raise NotImplementedError("incremental training lands with M6 resume-from-checkpoint")

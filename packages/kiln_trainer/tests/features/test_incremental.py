"""Tests for the incremental-learning scaffold."""
from pathlib import Path

import pytest

from kiln_trainer.features import incremental


def test_continue_training_raises_not_implemented():
    request = incremental.IncrementalRequest(
        base_adapter_dir=Path("/tmp/adapter"),
        additional_corpus_jsonl=Path("/tmp/more.jsonl"),
        extra_epochs=1,
    )
    with pytest.raises(NotImplementedError):
        incremental.continue_training(request)


def test_is_implemented_flag_is_false_until_m6():
    assert incremental.IS_IMPLEMENTED is False, (
        "Flip only when --resume lands in the Python trainer"
    )


@pytest.mark.skipif(
    not incremental.IS_IMPLEMENTED,
    reason="Incremental learning lands in M6 with --resume-from-checkpoint",
)
def test_future_resume_preserves_optimizer_state():
    """Filled in when the feature ships; skip placeholder until then."""
    pass

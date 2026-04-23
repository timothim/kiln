"""IPC event schema tests. Every event must round-trip through JSON as a single
line, terminated by LF, with no embedded newlines. See SPEC.md §11.1."""

from __future__ import annotations

import io
import json

import pytest

from kiln_trainer import events


def test_ready_has_required_fields() -> None:
    event = events.ready(version="0.1.0", mlx="0.16.0")
    assert event["event"] == "ready"
    assert event["version"] == "0.1.0"
    assert event["mlx"] == "0.16.0"
    assert "pid" not in event  # optional, omitted by default


def test_ready_includes_pid_when_provided() -> None:
    event = events.ready(version="0.1.0", mlx="0.16.0", pid=12345)
    assert event["pid"] == 12345


def test_progress_rejects_invalid_stage() -> None:
    with pytest.raises(ValueError, match="progress stage"):
        events.progress(stage="fuse", iter=1, loss=1.0)


def test_progress_emits_minimal_required_fields() -> None:
    event = events.progress(stage="sft", iter=100, loss=1.234)
    assert event == {"event": "progress", "stage": "sft", "iter": 100, "loss": 1.234}


def test_progress_includes_optional_fields_when_provided() -> None:
    event = events.progress(
        stage="dpo",
        iter=50,
        loss=0.5,
        tokens_per_s=900.0,
        eta_s=120.5,
        val_loss=0.6,
        learning_rate=5e-6,
    )
    assert event["tokens_per_s"] == 900.0
    assert event["eta_s"] == 120.5
    assert event["val_loss"] == 0.6
    assert event["learning_rate"] == 5e-6


def test_sample_shape() -> None:
    event = events.sample(iter=200, prompt_id="p1", completion="hello")
    assert event == {"event": "sample", "iter": 200, "prompt_id": "p1", "completion": "hello"}


def test_checkpoint_shape() -> None:
    event = events.checkpoint(path="/tmp/run/ckpt-200", iter=200)
    assert event == {"event": "checkpoint", "path": "/tmp/run/ckpt-200", "iter": 200}


def test_checkpoint_marks_best() -> None:
    event = events.checkpoint(path="/tmp/run/ckpt-200", iter=200, best=True)
    assert event["best"] is True


def test_error_rejects_unknown_code() -> None:
    with pytest.raises(ValueError, match="error code"):
        events.error(code="not_a_real_code", message="x", recoverable=False)


def test_error_allows_stage_and_context() -> None:
    event = events.error(
        code="oom",
        message="MPS backend out of memory",
        recoverable=False,
        stage="sft",
        context={"batch_size": 2},
    )
    assert event["code"] == "oom"
    assert event["stage"] == "sft"
    assert event["context"] == {"batch_size": 2}


def test_done_rejects_invalid_stage() -> None:
    with pytest.raises(ValueError, match="done stage"):
        events.done(stage="not_a_stage", artifact="/tmp/adapters.safetensors")


def test_done_supports_interrupted_flag() -> None:
    event = events.done(
        stage="sft", artifact="/tmp/adapters.safetensors", interrupted=True
    )
    assert event["interrupted"] is True


def test_generation_shape() -> None:
    event = events.generation(
        prompt="Quick take on the deploy?",
        completion="Ship it.",
        tokens=2,
        tokens_per_s=42.0,
    )
    assert event["event"] == "generation"
    assert event["prompt"] == "Quick take on the deploy?"
    assert event["completion"] == "Ship it."
    assert event["tokens"] == 2
    assert event["tokens_per_s"] == 42.0


def test_all_event_types_serialise_as_single_line_json() -> None:
    constructed = [
        events.ready(version="0.1.0", mlx="0.16.0"),
        events.progress(stage="sft", iter=1, loss=1.0, tokens_per_s=800, eta_s=60),
        events.sample(iter=50, prompt_id="p1", completion="hi"),
        events.checkpoint(path="/tmp/ckpt", iter=50),
        events.error(code="sigterm", message="interrupted", recoverable=True),
        events.done(stage="sft", artifact="/tmp/adapters.safetensors"),
        events.generation(prompt="p", completion="c", tokens=1, tokens_per_s=10.0),
    ]
    for event in constructed:
        line = json.dumps(event, ensure_ascii=False, separators=(",", ":"))
        assert "\n" not in line
        # Round-trips cleanly.
        assert json.loads(line) == event
        # Event type is in the closed set.
        assert event["event"] in events.EVENT_TYPES


def test_emit_writes_newline_terminated_line_and_flushes() -> None:
    buf = io.StringIO()
    events.emit(events.ready(version="0.1.0", mlx="0.16.0"), stream=buf)
    out = buf.getvalue()
    assert out.endswith("\n")
    assert out.count("\n") == 1
    parsed = json.loads(out.strip())
    assert parsed["event"] == "ready"


def test_emit_escapes_newlines_in_field_values() -> None:
    """Newlines inside field values must not break the one-event-per-line framing
    — json.dumps escapes them to ``\\n``, so each event still serialises as a
    single line that parses back to the original string."""
    buf = io.StringIO()
    noisy = events.sample(iter=1, prompt_id="p1", completion="line1\nline2")
    events.emit(noisy, stream=buf)
    out = buf.getvalue()
    assert out.count("\n") == 1  # only the framing terminator
    parsed = json.loads(out.strip())
    assert parsed["completion"] == "line1\nline2"

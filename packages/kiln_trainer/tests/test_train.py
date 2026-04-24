"""Tests for :mod:`kiln_trainer.commands.train`.

Split into two layers:

1. Unit tests for :class:`_LineHandler` and :func:`_render_lora_yaml`. These
   never spawn a subprocess — they just feed canned MLX-LM-style lines through
   the parser and assert the stdout JSON-line events.
2. End-to-end subprocess tests that invoke ``python -m kiln_trainer train ...``
   with ``--trainer-entry <fake_trainer.py>``. These exercise the argparse
   wiring, the YAML config, the subprocess plumbing, and the final ``done``
   event.

SIGTERM forwarding lives in :file:`test_sigterm.py` because it needs more
timing control.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

from kiln_trainer.commands.train import (
    _LineHandler,
    _reemit_generations_as_samples,
    _render_lora_yaml,
)


def _events(text: str) -> list[dict]:
    return [json.loads(ln) for ln in text.splitlines() if ln.strip()]


# ---------- Unit: YAML renderer ----------


def test_render_lora_yaml_matches_mlx_lm_schema() -> None:
    out = _render_lora_yaml(
        rank=16, alpha=32, keys=("self_attn.q_proj", "self_attn.v_proj")
    )
    # The MLX-LM 0.21.5 loader expects this exact top-level key.
    assert "lora_parameters:" in out
    assert "  rank: 16" in out
    assert "  alpha: 32" in out
    assert "  dropout: 0.0" in out
    assert "  scale: 10.0" in out
    assert "  keys:" in out
    assert "    - self_attn.q_proj" in out
    assert "    - self_attn.v_proj" in out


def test_render_lora_yaml_preserves_key_order() -> None:
    keys = ("self_attn.q_proj", "self_attn.k_proj", "self_attn.v_proj")
    out = _render_lora_yaml(rank=8, alpha=16, keys=keys)
    positions = [out.index(f"- {k}") for k in keys]
    assert positions == sorted(positions)


# ---------- Unit: _LineHandler ----------


def test_line_handler_emits_progress_on_train_iter(
    capsys: pytest.CaptureFixture[str],
) -> None:
    h = _LineHandler(stage="sft")
    h.handle(
        "Iter 5: Train loss 1.234, Learning Rate 1.000e-04, "
        "Tokens/sec 120.3, Trained Tokens 640, Peak mem 1.2 GB"
    )
    events = _events(capsys.readouterr().out)
    assert events == [
        {
            "event": "progress",
            "stage": "sft",
            "iter": 5,
            "loss": 1.234,
            "tokens_per_s": 120.3,
            "learning_rate": 0.0001,
        }
    ]


def test_line_handler_train_line_without_tokens_per_s(
    capsys: pytest.CaptureFixture[str],
) -> None:
    h = _LineHandler(stage="sft")
    h.handle("Iter 3: Train loss 2.0, Learning Rate 1.000e-04")
    events = _events(capsys.readouterr().out)
    assert len(events) == 1
    assert "tokens_per_s" not in events[0]
    assert events[0]["learning_rate"] == 0.0001


def test_line_handler_val_line_carries_last_train_loss(
    capsys: pytest.CaptureFixture[str],
) -> None:
    h = _LineHandler(stage="sft")
    h.handle("Iter 5: Train loss 1.5, Learning Rate 2.000e-04, Tokens/sec 100.0")
    h.handle("Iter 5: Val loss 1.4, Val took 0.200s")
    events = _events(capsys.readouterr().out)
    assert len(events) == 2
    train_ev, val_ev = events
    assert train_ev["loss"] == 1.5
    assert val_ev["event"] == "progress"
    assert val_ev["loss"] == 1.5  # carried from the train line
    assert val_ev["val_loss"] == 1.4


def test_line_handler_val_before_train_skipped(
    capsys: pytest.CaptureFixture[str],
) -> None:
    h = _LineHandler(stage="sft")
    h.handle("Iter 5: Val loss 1.4, Val took 0.200s")
    assert _events(capsys.readouterr().out) == []


def test_line_handler_emits_checkpoint(
    capsys: pytest.CaptureFixture[str],
) -> None:
    h = _LineHandler(stage="sft")
    h.handle("Iter 50: Saved adapter weights to /tmp/adapters.safetensors.")
    events = _events(capsys.readouterr().out)
    assert events == [
        {"event": "checkpoint", "path": "/tmp/adapters.safetensors", "iter": 50}
    ]
    assert h.last_checkpoint == "/tmp/adapters.safetensors"


def test_line_handler_records_final_save_without_emitting(
    capsys: pytest.CaptureFixture[str],
) -> None:
    h = _LineHandler(stage="sft")
    h.handle("Saved final weights to /tmp/final/adapters.safetensors.")
    # The final-save line is informational; done() is emitted by the caller
    # after proc.wait(), so no public event should fire here.
    assert _events(capsys.readouterr().out) == []
    assert h.last_checkpoint == "/tmp/final/adapters.safetensors"


def test_line_handler_ignores_unrelated_stdout(
    capsys: pytest.CaptureFixture[str],
) -> None:
    h = _LineHandler(stage="sft")
    h.handle("Loading pretrained model")
    h.handle("")  # blank line
    h.handle("Starting training..., iters: 100")
    assert _events(capsys.readouterr().out) == []


# ---------- Unit: M6.5 checkpoint callback + sample re-emitter ----------


def test_line_handler_fires_on_checkpoint_callback(
    capsys: pytest.CaptureFixture[str],
) -> None:
    """Save line → checkpoint event AND on_checkpoint(it, path). This is the
    contract the M6.5 post-checkpoint sampler depends on."""
    captured: list[tuple[int, str]] = []

    def _on_ckpt(it: int, path: str) -> None:
        captured.append((it, path))

    h = _LineHandler(stage="sft", on_checkpoint=_on_ckpt)
    h.handle("Iter 50: Saved adapter weights to /tmp/adapters.safetensors.")

    events = _events(capsys.readouterr().out)
    assert events == [
        {"event": "checkpoint", "path": "/tmp/adapters.safetensors", "iter": 50}
    ]
    assert captured == [(50, "/tmp/adapters.safetensors")]


def test_line_handler_callback_exception_does_not_break_training(
    capsys: pytest.CaptureFixture[str],
) -> None:
    """A sampler failure must never abort training. The checkpoint event is
    already emitted; a raising callback should be swallowed and logged."""

    def _boom(it: int, path: str) -> None:
        raise RuntimeError("sampler exploded")

    h = _LineHandler(stage="sft", on_checkpoint=_boom)
    h.handle("Iter 50: Saved adapter weights to /tmp/adapters.safetensors.")

    out = _events(capsys.readouterr().out)
    assert out == [{"event": "checkpoint", "path": "/tmp/adapters.safetensors", "iter": 50}]


def test_sample_hook_transforms_generation_into_sample_events_with_iter(
    capsys: pytest.CaptureFixture[str],
) -> None:
    """``_reemit_generations_as_samples`` is the core of the post-checkpoint
    closure. Feed it canned sample-batch stdout and assert every
    ``generation`` becomes a ``sample`` with the injected iter."""
    stdout = "\n".join(
        [
            json.dumps({"event": "ready", "version": "0.1.0", "mlx": "n/a"}),
            json.dumps(
                {
                    "event": "generation",
                    "prompt": "What should I work on this week?",
                    "prompt_id": "week_focus",
                    "completion": "Focus on X.",
                    "tokens": 5,
                    "tokens_per_s": 42.0,
                }
            ),
            json.dumps(
                {
                    "event": "generation",
                    "prompt": "Write a one-line birthday message for a friend.",
                    "prompt_id": "birthday_msg",
                    "completion": "Happy birthday!",
                    "tokens": 3,
                    "tokens_per_s": 44.5,
                }
            ),
            json.dumps(
                {
                    "event": "generation",
                    "prompt": "Describe your perfect Sunday.",
                    "prompt_id": "perfect_sunday",
                    "completion": "Coffee, a book, a long walk.",
                    "tokens": 8,
                    "tokens_per_s": 39.7,
                }
            ),
            json.dumps(
                {"event": "done", "stage": "generation", "artifact": "/t/a"}
            ),
        ]
    )

    _reemit_generations_as_samples(stdout, iter=50)

    out = _events(capsys.readouterr().out)
    assert [e["event"] for e in out] == ["sample", "sample", "sample"]
    for ev in out:
        assert ev["iter"] == 50
    assert [e["prompt_id"] for e in out] == [
        "week_focus",
        "birthday_msg",
        "perfect_sunday",
    ]
    assert out[0]["completion"] == "Focus on X."
    assert out[1]["completion"] == "Happy birthday!"
    assert out[2]["completion"] == "Coffee, a book, a long walk."
    for ev in out:
        assert isinstance(ev["tokens_per_s"], float)


def test_sample_hook_skips_malformed_lines(
    capsys: pytest.CaptureFixture[str],
) -> None:
    """Non-JSON lines, non-generation events, and missing fields are ignored."""
    stdout = "\n".join(
        [
            "not json at all",
            json.dumps({"event": "ready", "version": "0.1.0"}),
            json.dumps({"event": "generation"}),  # missing required fields
            json.dumps(
                {
                    "event": "generation",
                    "prompt": "p",
                    "prompt_id": "ok",
                    "completion": "c",
                    "tokens": 1,
                    "tokens_per_s": 1.0,
                }
            ),
        ]
    )

    _reemit_generations_as_samples(stdout, iter=7)

    out = _events(capsys.readouterr().out)
    assert len(out) == 1
    assert out[0] == {
        "event": "sample",
        "iter": 7,
        "prompt_id": "ok",
        "completion": "c",
        "tokens_per_s": 1.0,
    }


# ---------- End-to-end subprocess ----------


def _run_train(
    tmp_path: Path,
    dataset: Path,
    fake_trainer: Path,
    *,
    iters: int = 10,
    save_every: int = 5,
    model: str = "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
    timeout: float = 30.0,
    sampler_entry: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    """Invoke ``python -m kiln_trainer train ...`` with sensible test defaults.

    M6.5: the train subprocess spawns ``sample-batch`` after every checkpoint
    save. If ``sampler_entry`` is not provided, we default to the
    ``fake_batch_generator`` fixture so the child exits instantly instead of
    loading a real MLX model against the zero-byte adapter stub. Tests that
    explicitly exercise the M6.5 pipeline pass ``sampler_entry`` themselves.
    """
    run_dir = tmp_path / "run"
    cmd = [
        sys.executable,
        "-m",
        "kiln_trainer",
        "train",
        "--dataset", str(dataset),
        "--model", model,
        "--run-dir", str(run_dir),
        "--iters", str(iters),
        "--save-every", str(save_every),
        "--val-batches", "1",
        "--trainer-entry", str(fake_trainer),
    ]
    if sampler_entry is None:
        sampler_entry = Path(__file__).parent / "fixtures" / "fake_batch_generator.py"
    cmd += ["--sampler-entry", str(sampler_entry)]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def test_emits_ready_progress_checkpoint_done(
    tmp_path: Path, tiny_dataset: Path, fake_trainer: Path
) -> None:
    result = _run_train(
        tmp_path, tiny_dataset, fake_trainer, iters=10, save_every=5
    )
    assert result.returncode == 0, result.stderr
    events = _events(result.stdout)

    types = [e["event"] for e in events]
    assert types[0] == "ready"
    assert types[-1] == "done"
    assert "progress" in types
    assert "checkpoint" in types


def test_ready_event_carries_version_and_mlx(
    tmp_path: Path, tiny_dataset: Path, fake_trainer: Path
) -> None:
    result = _run_train(tmp_path, tiny_dataset, fake_trainer, iters=5, save_every=10)
    assert result.returncode == 0, result.stderr
    events = _events(result.stdout)
    ready = events[0]
    assert ready["event"] == "ready"
    assert ready["version"] == "0.1.0"
    assert "mlx" in ready  # "n/a" when mlx is not installed


def test_progress_event_fields(
    tmp_path: Path, tiny_dataset: Path, fake_trainer: Path
) -> None:
    result = _run_train(tmp_path, tiny_dataset, fake_trainer, iters=5, save_every=10)
    assert result.returncode == 0, result.stderr
    progress = [
        e
        for e in _events(result.stdout)
        if e["event"] == "progress" and "val_loss" not in e
    ]
    assert progress, "expected at least one train progress event"
    for ev in progress:
        assert ev["stage"] == "sft"
        assert isinstance(ev["iter"], int)
        assert isinstance(ev["loss"], float)
        assert "tokens_per_s" in ev
        assert "learning_rate" in ev


def test_val_line_adds_val_loss_to_progress(
    tmp_path: Path, tiny_dataset: Path, fake_trainer: Path
) -> None:
    result = _run_train(tmp_path, tiny_dataset, fake_trainer, iters=10, save_every=5)
    assert result.returncode == 0, result.stderr
    val_events = [
        e for e in _events(result.stdout) if e["event"] == "progress" and "val_loss" in e
    ]
    assert val_events, "expected at least one val progress event"
    for ev in val_events:
        assert "loss" in ev and "val_loss" in ev


def test_done_event_reports_checkpoint_path(
    tmp_path: Path, tiny_dataset: Path, fake_trainer: Path
) -> None:
    result = _run_train(tmp_path, tiny_dataset, fake_trainer, iters=10, save_every=5)
    assert result.returncode == 0, result.stderr
    done = next(e for e in _events(result.stdout) if e["event"] == "done")
    assert done["stage"] == "sft"
    assert done["artifact"].endswith("adapters.safetensors")
    assert done.get("interrupted") is False


def test_writes_lora_yaml_config(
    tmp_path: Path, tiny_dataset: Path, fake_trainer: Path
) -> None:
    result = _run_train(tmp_path, tiny_dataset, fake_trainer, iters=5, save_every=10)
    assert result.returncode == 0, result.stderr
    config = tmp_path / "run" / "lora_config.yaml"
    assert config.exists()
    body = config.read_text(encoding="utf-8")
    # 1.5B defaults: rank 16, alpha 32, q/k/v/o keys.
    assert "rank: 16" in body
    assert "alpha: 32" in body
    assert "- self_attn.q_proj" in body
    assert "- self_attn.v_proj" in body


def test_writes_data_splits(
    tmp_path: Path, tiny_dataset: Path, fake_trainer: Path
) -> None:
    result = _run_train(tmp_path, tiny_dataset, fake_trainer, iters=5, save_every=10)
    assert result.returncode == 0, result.stderr
    data_dir = tmp_path / "run" / "data"
    assert (data_dir / "train.jsonl").exists()
    assert (data_dir / "valid.jsonl").exists()


def test_unknown_model_size_errors(
    tmp_path: Path, tiny_dataset: Path, fake_trainer: Path
) -> None:
    result = _run_train(
        tmp_path, tiny_dataset, fake_trainer,
        iters=5, save_every=10,
        model="openai-community/gpt2-medium",
    )
    assert result.returncode == 2
    errors = [e for e in _events(result.stdout) if e["event"] == "error"]
    assert errors and errors[0]["code"] == "model_not_found"


def test_empty_dataset_errors(
    tmp_path: Path, fake_trainer: Path
) -> None:
    empty = tmp_path / "empty.jsonl"
    empty.write_text("", encoding="utf-8")
    result = _run_train(tmp_path, empty, fake_trainer, iters=5, save_every=10)
    assert result.returncode == 1
    errors = [e for e in _events(result.stdout) if e["event"] == "error"]
    assert errors and errors[0]["code"] == "data_invalid"


def test_missing_dataset_errors(
    tmp_path: Path, fake_trainer: Path
) -> None:
    missing = tmp_path / "does-not-exist.jsonl"
    result = _run_train(tmp_path, missing, fake_trainer, iters=5, save_every=10)
    assert result.returncode == 1
    errors = [e for e in _events(result.stdout) if e["event"] == "error"]
    assert errors and errors[0]["code"] == "data_invalid"


def test_all_stdout_is_valid_json_lines(
    tmp_path: Path, tiny_dataset: Path, fake_trainer: Path
) -> None:
    """CLAUDE.md: stdout is JSON-lines only. Every non-blank line must parse."""
    result = _run_train(tmp_path, tiny_dataset, fake_trainer, iters=5, save_every=10)
    assert result.returncode == 0, result.stderr
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        json.loads(line)  # will raise on any malformed line


def test_ready_emitted_before_heavy_work(
    tmp_path: Path, tiny_dataset: Path, fake_trainer: Path
) -> None:
    """``ready`` is the first stdout line, per SPEC.md §11 and CLAUDE.md."""
    result = _run_train(tmp_path, tiny_dataset, fake_trainer, iters=5, save_every=10)
    assert result.returncode == 0, result.stderr
    first = result.stdout.splitlines()[0]
    assert json.loads(first)["event"] == "ready"


# ---------- Integration: M6.5 Growing Model samples at each checkpoint ----------


def test_train_emits_sample_events_at_each_checkpoint(
    tmp_path: Path,
    tiny_dataset: Path,
    fake_trainer: Path,
    fake_batch_generator: Path,
) -> None:
    """End-to-end: 20 iters, save every 5 → 4 checkpoints, each followed by 3
    ``sample`` events (one per default prompt) carrying the checkpoint's iter.

    Uses ``--sampler-entry`` to swap the real MLX batch generator for the
    fake, so the test runs without MLX installed. Proves the whole chain:
    _LineHandler → _on_checkpoint closure → sample-batch subprocess →
    _reemit_generations_as_samples → stdout ``sample`` events."""
    run_dir = tmp_path / "run"
    cmd = [
        sys.executable,
        "-m",
        "kiln_trainer",
        "train",
        "--dataset", str(tiny_dataset),
        "--model", "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
        "--run-dir", str(run_dir),
        "--iters", "20",
        "--save-every", "5",
        "--val-batches", "1",
        "--trainer-entry", str(fake_trainer),
        "--sampler-entry", str(fake_batch_generator),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60.0)
    assert result.returncode == 0, result.stderr

    events = _events(result.stdout)
    types = [e["event"] for e in events]
    assert types[0] == "ready"
    assert types[-1] == "done"

    # Checkpoints at iters 5, 10, 15, 20 — one from fake_trainer per save,
    # then the caller records the final weights line too (no extra checkpoint).
    ckpts = [e for e in events if e["event"] == "checkpoint"]
    assert [c["iter"] for c in ckpts] == [5, 10, 15, 20]

    # Three sample events per checkpoint, in the default prompt order.
    samples = [e for e in events if e["event"] == "sample"]
    assert len(samples) == 12  # 4 ckpts × 3 prompts

    expected_ids = ["week_focus", "birthday_msg", "perfect_sunday"]
    for ck_iter, chunk_start in zip([5, 10, 15, 20], range(0, 12, 3)):
        chunk = samples[chunk_start : chunk_start + 3]
        assert [s["iter"] for s in chunk] == [ck_iter, ck_iter, ck_iter]
        assert [s["prompt_id"] for s in chunk] == expected_ids
        for s in chunk:
            assert s["completion"].startswith("echo: ")

    # Each sample block must appear AFTER its checkpoint event.
    for i, ck in enumerate(ckpts):
        ck_pos = events.index(ck)
        block = samples[i * 3 : i * 3 + 3]
        for s in block:
            assert events.index(s) > ck_pos

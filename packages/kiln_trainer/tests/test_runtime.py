"""Tests for runtime helpers: stderr log, SIGTERM event, run_dir creation."""

from __future__ import annotations

import os
import signal
import sys

import pytest

from kiln_trainer import runtime


@pytest.fixture
def restore_sigterm():
    original = signal.getsignal(signal.SIGTERM)
    # Clear any cached event so the installer runs from scratch in this test.
    runtime._sigterm_event = None
    yield
    signal.signal(signal.SIGTERM, original)
    runtime._sigterm_event = None


def test_log_writes_to_stderr(capsys: pytest.CaptureFixture[str]) -> None:
    runtime.log("hello", run_id="abc", n=3)
    captured = capsys.readouterr()
    assert captured.out == ""  # log must never touch stdout
    assert "hello" in captured.err
    assert "run_id='abc'" in captured.err
    assert "n=3" in captured.err


def test_install_sigterm_handler_sets_event(restore_sigterm) -> None:
    event = runtime.install_sigterm_handler()
    assert not event.is_set()
    os.kill(os.getpid(), signal.SIGTERM)
    assert event.wait(timeout=1.0), "SIGTERM handler did not flip the event"


def test_install_sigterm_handler_is_idempotent(restore_sigterm) -> None:
    # The CLI installs the handler early; subcommands install it again on
    # entry. Both calls must share the same threading.Event or one side will
    # miss the SIGTERM flag when the other flips it.
    first = runtime.install_sigterm_handler()
    second = runtime.install_sigterm_handler()
    assert first is second


def test_make_run_dir_creates_unique_dir(tmp_path) -> None:
    first = runtime.make_run_dir(base=tmp_path)
    second = runtime.make_run_dir(base=tmp_path)
    assert first.exists() and second.exists()
    assert first != second
    assert first.parent == tmp_path
    assert first.name.startswith("run-")


def test_make_run_dir_honours_custom_prefix(tmp_path) -> None:
    run = runtime.make_run_dir(base=tmp_path, prefix="sft")
    assert run.name.startswith("sft-")


def test_find_latest_adapter_returns_newest(tmp_path) -> None:
    # No adapters yet.
    assert runtime.find_latest_adapter(tmp_path) is None
    older = tmp_path / "ckpt-50"
    older.mkdir()
    older_adapter = older / "adapters.safetensors"
    older_adapter.write_bytes(b"old")
    newer = tmp_path / "ckpt-100"
    newer.mkdir()
    newer_adapter = newer / "adapters.safetensors"
    newer_adapter.write_bytes(b"new")
    # Ensure mtime ordering is unambiguous.
    os.utime(older_adapter, (1_000_000, 1_000_000))
    os.utime(newer_adapter, (2_000_000, 2_000_000))
    latest = runtime.find_latest_adapter(tmp_path)
    assert latest == newer_adapter


def test_find_latest_adapter_handles_missing_dir(tmp_path) -> None:
    ghost = tmp_path / "does-not-exist"
    assert runtime.find_latest_adapter(ghost) is None

"""CLI parse-error contract.

Per SPEC §11.3 (framing rules) the sidecar must never leave the Swift parent
staring at a stdout stream with nothing on it when something goes wrong. For
the argparse-subcommand model (see ``DECISIONS.md §L8``) the closest analogue
is: invoking an unknown subcommand writes a structured ``error`` event on
stdout before argparse's default ``stderr + sys.exit(2)`` path runs.

End-to-end tests — we spawn the sidecar via ``python -m kiln_trainer`` so we
exercise the real argparse / emission wiring, not a mock.
"""

from __future__ import annotations

import json
import subprocess
import sys


def _run(*argv: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "kiln_trainer", *argv],
        capture_output=True,
        text=True,
    )


def test_unknown_subcommand_emits_structured_error_and_exits_2() -> None:
    result = _run("notacommand")
    assert result.returncode == 2

    lines = [ln for ln in result.stdout.splitlines() if ln.strip()]
    assert lines, f"expected at least one stdout line, got none. stderr={result.stderr!r}"
    first = json.loads(lines[0])
    assert first["event"] == "error"
    assert first["code"] == "internal"
    assert first["recoverable"] is False
    assert "cli parse error" in first["message"]
    assert "notacommand" in first["message"]

    # argparse still writes its usual usage/error to stderr — the structured
    # event is additive, not a replacement.
    assert "invalid choice" in result.stderr


def test_missing_required_arg_on_subcommand_emits_structured_error() -> None:
    # ``train`` requires ``--dataset`` and ``--model``. Missing them goes
    # through the subparser's error(), which is why we propagate the
    # ``_SidecarParser`` class onto subparsers — otherwise the Swift parent
    # would see nothing on stdout.
    result = _run("train")
    assert result.returncode == 2

    lines = [ln for ln in result.stdout.splitlines() if ln.strip()]
    assert lines, f"expected structured error on stdout, got nothing. stderr={result.stderr!r}"
    first = json.loads(lines[0])
    assert first["event"] == "error"
    assert first["code"] == "internal"
    assert first["recoverable"] is False
    assert "cli parse error" in first["message"]


def test_no_args_still_emits_structured_error() -> None:
    # Top-level required=True means argparse's "the following arguments are
    # required: COMMAND" also flows through our overridden error().
    result = _run()
    assert result.returncode == 2

    lines = [ln for ln in result.stdout.splitlines() if ln.strip()]
    assert lines
    first = json.loads(lines[0])
    assert first["event"] == "error"
    assert first["code"] == "internal"


def test_help_flag_does_not_emit_error_event() -> None:
    # ``--help`` exits 0 via parser.exit(), not parser.error(). It must not
    # emit an error event; otherwise a user who runs ``kiln_trainer --help``
    # in a terminal will see a confusing JSON blob mixed into usage output.
    result = _run("--help")
    assert result.returncode == 0
    # No JSON lines on stdout (help text is free-form, not JSON).
    for ln in result.stdout.splitlines():
        if not ln.strip():
            continue
        try:
            parsed = json.loads(ln)
        except json.JSONDecodeError:
            continue
        assert parsed.get("event") != "error", f"--help emitted an error event: {parsed}"


def test_version_flag_does_not_emit_error_event() -> None:
    result = _run("--version")
    assert result.returncode == 0
    for ln in result.stdout.splitlines():
        if not ln.strip():
            continue
        try:
            parsed = json.loads(ln)
        except json.JSONDecodeError:
            continue
        assert parsed.get("event") != "error", f"--version emitted an error event: {parsed}"

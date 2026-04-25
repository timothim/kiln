"""Integration tests for the ``sample-compare`` subcommand (M7).

We use ``fake_generator.py`` as the ``--generator-entry`` so the tests don't
require MLX. The fake speaks the same verbose stdout format as
``mlx_lm.generate``, so the parent parser treats it identically.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from kiln_trainer.commands.sample_compare import parse_variant


# ---------------------------------------------------------------------------
# parse_variant unit coverage


def test_parse_variant_base_no_path() -> None:
    assert parse_variant("base") == ("base", None)


def test_parse_variant_sft_with_path(tmp_path: Path) -> None:
    p = tmp_path / "sft.safetensors"
    p.write_bytes(b"x")
    tag, adapter = parse_variant(f"sft:{p}")
    assert tag == "sft"
    assert adapter == p


def test_parse_variant_sftdpo_with_path(tmp_path: Path) -> None:
    p = tmp_path / "sftdpo.safetensors"
    p.write_bytes(b"x")
    tag, adapter = parse_variant(f"sftdpo:{p}")
    assert tag == "sftdpo"
    assert adapter == p


def test_parse_variant_rejects_unknown_tag() -> None:
    with pytest.raises(Exception, match="variant tag must be"):
        parse_variant("random")


def test_parse_variant_rejects_missing_adapter_path() -> None:
    with pytest.raises(Exception, match="requires an adapter path"):
        parse_variant("sft")


def test_parse_variant_rejects_base_with_path() -> None:
    with pytest.raises(Exception, match="base variant must not carry an adapter path"):
        parse_variant("base:/some/path")


# ---------------------------------------------------------------------------
# End-to-end subprocess cases using fake_generator.py


def _spawn_compare(
    *,
    fake_generator: Path,
    prompt: str,
    variants: list[str],
    extra_args: list[str] | None = None,
) -> subprocess.CompletedProcess[str]:
    cmd = [
        sys.executable,
        "-m",
        "kiln_trainer",
        "sample-compare",
        "--model",
        "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
        "--prompt",
        prompt,
        "--generator-entry",
        str(fake_generator),
        "--max-tokens",
        "16",
    ]
    for v in variants:
        cmd += ["--variant", v]
    if extra_args:
        cmd += extra_args
    # Add the sidecar package to PYTHONPATH so `python -m kiln_trainer` resolves
    # without an editable install.
    env = {**os.environ, "PYTHONPATH": _pythonpath()}
    return subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=20)


def _pythonpath() -> str:
    pkg_src = Path(__file__).parents[1] / "src"
    existing = os.environ.get("PYTHONPATH", "")
    return str(pkg_src) + (os.pathsep + existing if existing else "")


def _parse_events(stdout: str) -> list[dict]:
    out: list[dict] = []
    for line in stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        out.append(json.loads(line))
    return out


def test_sample_compare_emits_one_generation_per_variant(
    fake_generator: Path, tmp_path: Path
) -> None:
    sft_adapter = tmp_path / "sft.safetensors"
    sft_adapter.write_bytes(b"x")
    sftdpo_adapter = tmp_path / "sftdpo.safetensors"
    sftdpo_adapter.write_bytes(b"x")

    result = _spawn_compare(
        fake_generator=fake_generator,
        prompt="What should I work on this week?",
        variants=["base", f"sft:{sft_adapter}", f"sftdpo:{sftdpo_adapter}"],
    )

    assert result.returncode == 0, f"stderr={result.stderr!r}"
    events = _parse_events(result.stdout)
    # ready + 3 generation + done
    assert events[0]["event"] == "ready"
    gens = [e for e in events if e["event"] == "generation"]
    done = [e for e in events if e["event"] == "done"]
    assert len(gens) == 3
    assert [g["prompt_id"] for g in gens] == ["base", "sft", "sftdpo"]
    # Completion is synthesised from the prompt by fake_generator.
    for g in gens:
        assert g["prompt"] == "What should I work on this week?"
        assert g["completion"].startswith("echo:")
        assert g["tokens"] > 0
        assert g["tokens_per_s"] > 0
    assert len(done) == 1
    assert done[0]["stage"] == "generation"
    assert done[0].get("interrupted") is False


def test_sample_compare_skips_variant_with_missing_adapter(
    fake_generator: Path, tmp_path: Path
) -> None:
    """A missing adapter is reported as a recoverable error; other variants proceed."""
    sft_adapter = tmp_path / "sft.safetensors"
    sft_adapter.write_bytes(b"x")
    # sftdpo path intentionally not created
    missing = tmp_path / "missing.safetensors"

    result = _spawn_compare(
        fake_generator=fake_generator,
        prompt="hello",
        variants=["base", f"sft:{sft_adapter}", f"sftdpo:{missing}"],
    )

    assert result.returncode == 0
    events = _parse_events(result.stdout)
    gens = [e for e in events if e["event"] == "generation"]
    errs = [e for e in events if e["event"] == "error"]
    assert [g["prompt_id"] for g in gens] == ["base", "sft"]
    assert any(
        e["code"] == "adapter_invalid" and e.get("context", {}).get("variant") == "sftdpo"
        for e in errs
    )


def test_sample_compare_rejects_no_variants(fake_generator: Path) -> None:
    result = _spawn_compare(
        fake_generator=fake_generator,
        prompt="hello",
        variants=[],
    )
    # Rejected as error event, non-zero exit.
    assert result.returncode == 2
    events = _parse_events(result.stdout)
    errs = [e for e in events if e["event"] == "error"]
    assert any("at least one --variant" in e["message"] for e in errs)


def test_sample_compare_rejects_duplicate_variant_tag(
    fake_generator: Path, tmp_path: Path
) -> None:
    p1 = tmp_path / "a.safetensors"
    p1.write_bytes(b"x")
    p2 = tmp_path / "b.safetensors"
    p2.write_bytes(b"x")
    result = _spawn_compare(
        fake_generator=fake_generator,
        prompt="hello",
        variants=[f"sft:{p1}", f"sft:{p2}"],
    )
    assert result.returncode == 2
    events = _parse_events(result.stdout)
    errs = [e for e in events if e["event"] == "error"]
    assert any("duplicate --variant tag" in e["message"] for e in errs)

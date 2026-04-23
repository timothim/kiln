"""Modelfile rendering — matches SPEC.md §9.3 and the skill §9 template."""

from __future__ import annotations

import pytest

from kiln_trainer import modelfile


def test_render_contains_required_blocks() -> None:
    out = modelfile.render(gguf_filename="./kiln.Q4_K_M.gguf", user_name="Timothée")
    assert "FROM ./kiln.Q4_K_M.gguf" in out
    assert "PARAMETER temperature 0.7" in out
    assert "PARAMETER top_p 0.9" in out
    assert "PARAMETER repeat_penalty 1.1" in out
    assert "PARAMETER num_ctx 4096" in out
    assert 'SYSTEM "You are Timothée, responding in their voice."' in out
    assert "<|im_start|>" in out
    assert "<|im_end|>" in out
    assert 'STOP "<|im_end|>"' in out
    assert 'STOP "<|im_start|>"' in out


def test_render_escapes_double_quote_in_user_name() -> None:
    out = modelfile.render(gguf_filename="./kiln.gguf", user_name='Tim "T-Bone" Smith')
    # Backslash-escaped inside the SYSTEM string.
    assert 'SYSTEM "You are Tim \\"T-Bone\\" Smith, responding in their voice."' in out


def test_render_escapes_backslash_in_user_name() -> None:
    out = modelfile.render(gguf_filename="./kiln.gguf", user_name=r"back\slash")
    assert r'SYSTEM "You are back\\slash, responding in their voice."' in out


def test_render_rejects_newline_in_user_name() -> None:
    with pytest.raises(ValueError, match="must not contain newlines"):
        modelfile.render(gguf_filename="./kiln.gguf", user_name="line1\nline2")


def test_render_rejects_newline_in_filename() -> None:
    with pytest.raises(ValueError, match="must not contain newlines"):
        modelfile.render(gguf_filename="./kiln.gguf\nevil", user_name="Tim")


def test_render_honours_parameter_overrides() -> None:
    out = modelfile.render(
        gguf_filename="./kiln.gguf",
        user_name="Tim",
        temperature=0.3,
        top_p=0.8,
        repeat_penalty=1.15,
        num_ctx=8192,
    )
    assert "PARAMETER temperature 0.3" in out
    assert "PARAMETER top_p 0.8" in out
    assert "PARAMETER repeat_penalty 1.15" in out
    assert "PARAMETER num_ctx 8192" in out


def test_render_template_preserves_chatml_structure() -> None:
    """The TEMPLATE block must contain the Qwen2.5 ChatML shape so Ollama can
    apply roles correctly at inference time. See skill §10 ("Tokenizer")."""
    out = modelfile.render(gguf_filename="./kiln.gguf", user_name="Tim")
    # Both the system and user branches of the Go template must be present.
    assert "{{ if .System }}" in out
    assert "{{ .System }}" in out
    assert "{{ if .Prompt }}" in out
    assert "{{ .Prompt }}" in out
    # Assistant side has no closing conditional — the model fills it in.
    assert "<|im_start|>assistant\n" in out

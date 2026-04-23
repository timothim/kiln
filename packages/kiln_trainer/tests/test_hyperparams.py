"""Hyperparameter defaults match the SPEC.md §6.2 table exactly. If this test
breaks after a knob change, update :file:`SPEC.md` §6.2 and the
``mlx-lora-finetuning`` skill in the same PR — never just change the code."""

from __future__ import annotations

import pytest

from kiln_trainer import hyperparams


def test_three_sizes_supported() -> None:
    assert hyperparams.SUPPORTED_SIZES == ("1.5B", "3B", "7B")


def test_defaults_match_spec_1_5b() -> None:
    hp = hyperparams.DEFAULTS["1.5B"]
    assert hp["rank"] == 16
    assert hp["alpha"] == 32
    assert hp["epochs"] == 3
    assert hp["batch_size"] == 4
    assert hp["learning_rate"] == 2e-4
    assert hp["lora_layers"] == 28
    assert hp["target_modules"] == ("q_proj", "k_proj", "v_proj", "o_proj")
    assert hp["lora_keys"] == (
        "self_attn.q_proj",
        "self_attn.k_proj",
        "self_attn.v_proj",
        "self_attn.o_proj",
    )
    assert hp["gguf_quantization"] == "Q5_K_M"


def test_defaults_match_spec_3b() -> None:
    hp = hyperparams.DEFAULTS["3B"]
    assert hp["rank"] == 16
    assert hp["alpha"] == 32
    assert hp["epochs"] == 2
    assert hp["batch_size"] == 2
    assert hp["learning_rate"] == 1e-4
    assert hp["lora_layers"] == 16
    assert hp["target_modules"] == (
        "q_proj",
        "k_proj",
        "v_proj",
        "o_proj",
        "gate_proj",
        "up_proj",
        "down_proj",
    )
    assert hp["lora_keys"] == (
        "self_attn.q_proj",
        "self_attn.k_proj",
        "self_attn.v_proj",
        "self_attn.o_proj",
        "mlp.gate_proj",
        "mlp.up_proj",
        "mlp.down_proj",
    )
    assert hp["gguf_quantization"] == "Q4_K_M"


def test_defaults_match_spec_7b() -> None:
    hp = hyperparams.DEFAULTS["7B"]
    assert hp["rank"] == 8
    assert hp["alpha"] == 16
    assert hp["epochs"] == 1
    assert hp["batch_size"] == 1
    assert hp["learning_rate"] == 5e-5
    assert hp["lora_layers"] == 8
    assert hp["target_modules"] == ("q_proj", "v_proj")
    assert hp["lora_keys"] == ("self_attn.q_proj", "self_attn.v_proj")
    assert hp["gguf_quantization"] == "Q4_K_M"


def test_max_seq_length_is_2048_across_all_sizes() -> None:
    for size in hyperparams.SUPPORTED_SIZES:
        assert hyperparams.DEFAULTS[size]["max_seq_length"] == 2048


def test_warmup_ratio_is_0_03_across_all_sizes() -> None:
    for size in hyperparams.SUPPORTED_SIZES:
        assert hyperparams.DEFAULTS[size]["warmup_ratio"] == 0.03


@pytest.mark.parametrize(
    "model,expected",
    [
        ("mlx-community/Qwen2.5-1.5B-Instruct-4bit", "1.5B"),
        ("mlx-community/Qwen2.5-3B-Instruct-4bit", "3B"),
        ("mlx-community/Qwen2.5-7B-Instruct-4bit", "7B"),
        ("Qwen2.5-3B", "3B"),  # abbreviated form
        ("qwen2.5-1.5b-foo", "1.5B"),  # lowercase
    ],
)
def test_infer_size_matches_common_names(model: str, expected: str) -> None:
    assert hyperparams.infer_size(model) == expected


def test_infer_size_rejects_unknown() -> None:
    with pytest.raises(ValueError, match="cannot infer"):
        hyperparams.infer_size("openai-community/gpt2-medium")


def test_defaults_for_returns_matched_profile() -> None:
    assert hyperparams.defaults_for("mlx-community/Qwen2.5-3B-Instruct-4bit")["rank"] == 16
    assert hyperparams.defaults_for("Qwen2.5-7B-Instruct")["rank"] == 8

"""Hyperparameter defaults per base-model size.

Authoritative sources:

- :file:`SPEC.md` §6.2 — user-facing defaults table
- :file:`.claude/skills/mlx-lora-finetuning/SKILL.md` §5 — operational
  skill with ``lora-layers`` and target-module lists matched to MLX-LM

If these files disagree, the skill wins (it carries the operational truth);
update SPEC.md and this file in the same PR and add a :file:`DECISIONS.md`
entry. Never hand-tune in caller code — add a named profile here instead.
"""

from __future__ import annotations

from typing import TypedDict


class Hyperparams(TypedDict):
    rank: int
    alpha: int
    lora_layers: int
    epochs: int
    batch_size: int
    learning_rate: float
    max_seq_length: int
    warmup_ratio: float
    target_modules: tuple[str, ...]
    lora_keys: tuple[str, ...]
    gguf_quantization: str


# MLX-LM's ``linear_to_lora_layers`` matches LoRA target modules by fully
# qualified name (see ``mlx_lm.tuner.utils``). ``target_modules`` carries the
# user-facing short names from SPEC.md §6.2; ``lora_keys`` carries the Qwen2.5
# module paths we actually write into the YAML ``lora_parameters.keys`` list.
DEFAULTS: dict[str, Hyperparams] = {
    "1.5B": Hyperparams(
        rank=16,
        alpha=32,
        lora_layers=28,
        epochs=3,
        batch_size=4,
        learning_rate=2e-4,
        max_seq_length=2048,
        warmup_ratio=0.03,
        target_modules=("q_proj", "k_proj", "v_proj", "o_proj"),
        lora_keys=(
            "self_attn.q_proj",
            "self_attn.k_proj",
            "self_attn.v_proj",
            "self_attn.o_proj",
        ),
        gguf_quantization="Q5_K_M",
    ),
    "3B": Hyperparams(
        rank=16,
        alpha=32,
        lora_layers=16,
        epochs=2,
        batch_size=2,
        learning_rate=1e-4,
        max_seq_length=2048,
        warmup_ratio=0.03,
        target_modules=(
            "q_proj",
            "k_proj",
            "v_proj",
            "o_proj",
            "gate_proj",
            "up_proj",
            "down_proj",
        ),
        lora_keys=(
            "self_attn.q_proj",
            "self_attn.k_proj",
            "self_attn.v_proj",
            "self_attn.o_proj",
            "mlp.gate_proj",
            "mlp.up_proj",
            "mlp.down_proj",
        ),
        gguf_quantization="Q4_K_M",
    ),
    "7B": Hyperparams(
        rank=8,
        alpha=16,
        lora_layers=8,
        epochs=1,
        batch_size=1,
        learning_rate=5e-5,
        max_seq_length=2048,
        warmup_ratio=0.03,
        target_modules=("q_proj", "v_proj"),
        lora_keys=("self_attn.q_proj", "self_attn.v_proj"),
        gguf_quantization="Q4_K_M",
    ),
}

SUPPORTED_SIZES: tuple[str, ...] = tuple(DEFAULTS.keys())


def infer_size(model: str) -> str:
    """Infer ``1.5B``/``3B``/``7B`` from an MLX-community model name.

    Matches ``Qwen2.5-1.5B-Instruct-4bit``, ``Qwen2.5-3B-...``, etc. Raises
    :class:`ValueError` on anything else — we do not guess outside the three
    sizes :file:`SPEC.md` §1.2 commits to.
    """
    m = model.lower()
    # Order matters: ``1.5b`` before ``3b`` (since ``5b`` would otherwise match).
    if "1.5b" in m:
        return "1.5B"
    if "3b" in m:
        return "3B"
    if "7b" in m:
        return "7B"
    raise ValueError(
        f"cannot infer base size from model {model!r}; "
        f"supported sizes: {SUPPORTED_SIZES}"
    )


def defaults_for(model: str) -> Hyperparams:
    """Return the hyperparameter profile matched to ``model``'s size tag."""
    return DEFAULTS[infer_size(model)]

"""Ollama Modelfile rendering.

Template from :file:`SPEC.md` §9.3 and the ``mlx-lora-finetuning`` skill §9.
Qwen2.5 ChatML tokens are hard-coded (``<|im_start|>`` / ``<|im_end|>``); if
we ever ship a non-Qwen base we will need a per-family template table.
"""

from __future__ import annotations

DEFAULT_TEMPERATURE = 0.7
DEFAULT_TOP_P = 0.9
DEFAULT_REPEAT_PENALTY = 1.1
DEFAULT_NUM_CTX = 4096


def _escape_system(text: str) -> str:
    """Escape a string for inclusion inside Modelfile ``SYSTEM "..."``.

    Modelfile parses ``SYSTEM "..."`` like a shell string: backslash and
    double-quote are the two characters that must be escaped. Newlines are
    forbidden — we reject rather than silently strip them.
    """
    if "\n" in text or "\r" in text:
        raise ValueError("SYSTEM text must not contain newlines")
    return text.replace("\\", "\\\\").replace('"', '\\"')


def render(
    *,
    gguf_filename: str,
    user_name: str,
    temperature: float = DEFAULT_TEMPERATURE,
    top_p: float = DEFAULT_TOP_P,
    repeat_penalty: float = DEFAULT_REPEAT_PENALTY,
    num_ctx: int = DEFAULT_NUM_CTX,
) -> str:
    """Render a Modelfile string for an Ollama build.

    ``gguf_filename`` is the path (typically just ``./kiln.Q4_K_M.gguf``) placed
    after ``FROM``. ``user_name`` is interpolated into the system prompt.
    """
    if "\n" in gguf_filename or "\r" in gguf_filename:
        raise ValueError("gguf_filename must not contain newlines")
    escaped_name = _escape_system(user_name)
    template = (
        "{{ if .System }}<|im_start|>system\n"
        "{{ .System }}<|im_end|>\n"
        "{{ end }}{{ if .Prompt }}<|im_start|>user\n"
        "{{ .Prompt }}<|im_end|>\n"
        "{{ end }}<|im_start|>assistant\n"
    )
    return (
        f"FROM {gguf_filename}\n"
        f"\n"
        f"PARAMETER temperature {temperature}\n"
        f"PARAMETER top_p {top_p}\n"
        f"PARAMETER repeat_penalty {repeat_penalty}\n"
        f"PARAMETER num_ctx {num_ctx}\n"
        f"\n"
        f'SYSTEM "You are {escaped_name}, responding in their voice."\n'
        f"\n"
        f'TEMPLATE """{template}"""\n'
        f"\n"
        f'STOP "<|im_end|>"\n'
        f'STOP "<|im_start|>"\n'
    )

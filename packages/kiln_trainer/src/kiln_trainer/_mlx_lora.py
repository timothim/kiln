"""mlx_lm.lora launcher with a transformers >=5.x compatibility shim.

Background: mlx_lm 0.21.5's ``ChatDataset`` calls
``tokenizer.apply_chat_template(messages, tools=tools)`` expecting a flat
list of token IDs. transformers 5.x flipped the default of that call to
return a ``BatchEncoding`` dict, so ``iterate_batches`` later crashes
with ``invalid literal for int() with base 10: 'input_ids'`` while it
tries to copy the value into an int32 numpy array. Result for the user:
mlx_lm exits before the first ``Iter N: Saved adapter weights`` line, the
``adapters/`` directory contains only ``adapter_config.json``, and the
Sample / Export / Chat downstream all 404 on a missing
``adapters.safetensors``.

Pinning transformers <5 cascades into other mlx_lm requirements; the
narrower fix is to monkey-patch ``ChatDataset.__init__`` to force
``tokenize=True, return_dict=False`` and then dispatch to
``mlx_lm.lora.main()`` exactly as before.

Used as ``python -m kiln_trainer._mlx_lora``. The Swift app launches the
sidecar via ``python -m kiln_trainer train ...`` which spawns this module
in turn (see ``commands/train.py`` ``--trainer-module`` default).
"""
from __future__ import annotations

import mlx_lm.tuner.datasets as _ds


def _patched_chat_init(
    self,
    data,
    tokenizer,
    chat_key: str = "messages",
    mask_prompt: bool = False,
) -> None:
    self._data = []
    for d in data:
        messages = d[chat_key]
        tools = d.get("tools", None)
        tokens = tokenizer.apply_chat_template(
            messages, tools=tools, tokenize=True, return_dict=False
        )
        # transformers 5.x can wrap a single conversation in an outer list
        # when batched-shape detection kicks in; unwrap so mlx_lm sees a
        # flat list of int token IDs.
        if tokens and isinstance(tokens[0], list):
            tokens = tokens[0]
        if mask_prompt:
            offset_msgs = messages[:-1]
            offset_tokens = tokenizer.apply_chat_template(
                offset_msgs, tools=tools, tokenize=True, return_dict=False
            )
            if offset_tokens and isinstance(offset_tokens[0], list):
                offset_tokens = offset_tokens[0]
            self._data.append((tokens, len(offset_tokens)))
        else:
            self._data.append(tokens)


_ds.ChatDataset.__init__ = _patched_chat_init


from mlx_lm.lora import main  # noqa: E402  patch must run before import


if __name__ == "__main__":
    main()

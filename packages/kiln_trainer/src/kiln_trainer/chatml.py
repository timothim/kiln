"""ChatML JSONL reading, validation, and MLX-LM-compatible splitting.

Input format (SPEC.md §5.4, mlx-lora-finetuning skill §2):

.. code-block:: json

    {"messages": [
      {"role": "system",    "content": "You are {name}, responding in their voice."},
      {"role": "user",      "content": "..."},
      {"role": "assistant", "content": "..."}
    ]}

MLX-LM's ``--data`` flag consumes a directory containing ``train.jsonl`` and
``valid.jsonl`` (plus optional ``test.jsonl``). :func:`write_splits` produces
that directory from a single merged corpus file.
"""

from __future__ import annotations

import json
import random
from pathlib import Path
from typing import Any, Iterator

ALLOWED_ROLES: frozenset[str] = frozenset({"system", "user", "assistant"})


class ChatMLValidationError(ValueError):
    """Raised when a JSONL row violates the ChatML shape. The message carries
    the 1-based line number so callers can point the user at the bad row."""


def iter_rows(path: Path | str) -> Iterator[dict[str, Any]]:
    """Yield validated rows from a ChatML JSONL file. Blank lines skipped."""
    p = Path(path)
    with p.open("r", encoding="utf-8") as f:
        for line_no, raw in enumerate(f, start=1):
            line = raw.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ChatMLValidationError(f"line {line_no}: invalid JSON: {exc.msg}") from exc
            _validate_row(row, line_no)
            yield row


def _validate_row(row: Any, line_no: int) -> None:
    if not isinstance(row, dict):
        raise ChatMLValidationError(f"line {line_no}: row must be a JSON object")
    messages = row.get("messages")
    if not isinstance(messages, list) or not messages:
        raise ChatMLValidationError(
            f"line {line_no}: 'messages' must be a non-empty array"
        )
    for idx, msg in enumerate(messages):
        if not isinstance(msg, dict):
            raise ChatMLValidationError(
                f"line {line_no} message {idx}: must be an object"
            )
        role = msg.get("role")
        content = msg.get("content")
        if role not in ALLOWED_ROLES:
            raise ChatMLValidationError(
                f"line {line_no} message {idx}: role {role!r} must be one of "
                f"{sorted(ALLOWED_ROLES)}"
            )
        if not isinstance(content, str) or not content.strip():
            raise ChatMLValidationError(
                f"line {line_no} message {idx}: content must be a non-empty string"
            )


def split_rows(
    rows: list[dict[str, Any]],
    *,
    valid_ratio: float = 0.05,
    test_ratio: float = 0.02,
    seed: int = 42,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    """Deterministically shuffle and split a row list into (train, valid, test).

    Guarantees: at least one row in valid when the input has ≥ 2 rows, and
    never allocates so many rows to valid+test that train becomes empty.
    """
    rng = random.Random(seed)
    shuffled = list(rows)
    rng.shuffle(shuffled)
    n = len(shuffled)
    if n == 0:
        return [], [], []
    n_valid = max(1, int(n * valid_ratio)) if n >= 2 else 0
    n_test = int(n * test_ratio)
    # Never starve the train split.
    if n_valid + n_test >= n:
        n_test = 0
        n_valid = min(n_valid, n - 1)
    valid = shuffled[:n_valid]
    test = shuffled[n_valid : n_valid + n_test]
    train = shuffled[n_valid + n_test :]
    return train, valid, test


def write_splits(
    run_dir: Path | str,
    source: Path | str,
    *,
    valid_ratio: float = 0.05,
    test_ratio: float = 0.02,
    seed: int = 42,
) -> dict[str, int]:
    """Read ``source`` JSONL, validate, split, write the MLX-LM data directory.

    Writes ``<run_dir>/data/{train,valid[,test]}.jsonl``. Returns per-split
    row counts. ``test.jsonl`` is omitted when the test split is empty
    (MLX-LM treats the file as optional).
    """
    rows = list(iter_rows(source))
    train, valid, test = split_rows(
        rows, valid_ratio=valid_ratio, test_ratio=test_ratio, seed=seed
    )
    data_dir = Path(run_dir) / "data"
    data_dir.mkdir(parents=True, exist_ok=True)
    _write_jsonl(data_dir / "train.jsonl", train)
    _write_jsonl(data_dir / "valid.jsonl", valid)
    if test:
        _write_jsonl(data_dir / "test.jsonl", test)
    return {"train": len(train), "valid": len(valid), "test": len(test)}


def _write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")))
            f.write("\n")

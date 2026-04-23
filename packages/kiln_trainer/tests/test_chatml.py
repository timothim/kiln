"""ChatML validation + split tests. No MLX calls; pure I/O + data discipline."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from kiln_trainer import chatml


def _write_jsonl(path: Path, rows: list[dict]) -> None:
    with path.open("w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False))
            f.write("\n")


def _valid_row(user: str, asst: str) -> dict:
    return {
        "messages": [
            {"role": "system", "content": "You are Tim."},
            {"role": "user", "content": user},
            {"role": "assistant", "content": asst},
        ]
    }


def test_iter_rows_yields_all_valid_rows(tmp_path: Path) -> None:
    path = tmp_path / "train.jsonl"
    rows = [_valid_row(f"q{i}", f"a{i}") for i in range(5)]
    _write_jsonl(path, rows)
    collected = list(chatml.iter_rows(path))
    assert collected == rows


def test_iter_rows_skips_blank_lines(tmp_path: Path) -> None:
    path = tmp_path / "train.jsonl"
    with path.open("w", encoding="utf-8") as f:
        f.write(json.dumps(_valid_row("a", "b")) + "\n")
        f.write("\n")  # blank line in the middle
        f.write("   \n")  # whitespace-only line
        f.write(json.dumps(_valid_row("c", "d")) + "\n")
    collected = list(chatml.iter_rows(path))
    assert len(collected) == 2


def test_iter_rows_rejects_invalid_json(tmp_path: Path) -> None:
    path = tmp_path / "train.jsonl"
    path.write_text("not-json\n", encoding="utf-8")
    with pytest.raises(chatml.ChatMLValidationError, match="line 1.*invalid JSON"):
        list(chatml.iter_rows(path))


def test_iter_rows_rejects_missing_messages(tmp_path: Path) -> None:
    path = tmp_path / "train.jsonl"
    path.write_text(json.dumps({"not_messages": []}) + "\n", encoding="utf-8")
    with pytest.raises(chatml.ChatMLValidationError, match="'messages' must be a non-empty array"):
        list(chatml.iter_rows(path))


def test_iter_rows_rejects_empty_content(tmp_path: Path) -> None:
    path = tmp_path / "train.jsonl"
    bad = {
        "messages": [
            {"role": "system", "content": "sys"},
            {"role": "user", "content": ""},
            {"role": "assistant", "content": "ok"},
        ]
    }
    path.write_text(json.dumps(bad) + "\n", encoding="utf-8")
    with pytest.raises(chatml.ChatMLValidationError, match="content must be a non-empty string"):
        list(chatml.iter_rows(path))


def test_iter_rows_rejects_unknown_role(tmp_path: Path) -> None:
    path = tmp_path / "train.jsonl"
    bad = {"messages": [{"role": "robot", "content": "x"}]}
    path.write_text(json.dumps(bad) + "\n", encoding="utf-8")
    with pytest.raises(chatml.ChatMLValidationError, match="role 'robot'"):
        list(chatml.iter_rows(path))


def test_iter_rows_reports_correct_line_number(tmp_path: Path) -> None:
    path = tmp_path / "train.jsonl"
    with path.open("w", encoding="utf-8") as f:
        f.write(json.dumps(_valid_row("a", "b")) + "\n")
        f.write(json.dumps(_valid_row("c", "d")) + "\n")
        f.write("{not-valid}\n")
    with pytest.raises(chatml.ChatMLValidationError, match="line 3"):
        list(chatml.iter_rows(path))


def test_split_rows_is_deterministic_under_fixed_seed() -> None:
    rows = [_valid_row(f"q{i}", f"a{i}") for i in range(100)]
    a = chatml.split_rows(rows, seed=42)
    b = chatml.split_rows(rows, seed=42)
    assert a == b


def test_split_rows_respects_ratios() -> None:
    rows = [_valid_row(f"q{i}", f"a{i}") for i in range(100)]
    train, valid, test = chatml.split_rows(rows, valid_ratio=0.1, test_ratio=0.05)
    assert len(valid) == 10
    assert len(test) == 5
    assert len(train) == 85
    assert len(train) + len(valid) + len(test) == 100


def test_split_rows_preserves_train_when_corpus_is_tiny() -> None:
    rows = [_valid_row(f"q{i}", f"a{i}") for i in range(3)]
    train, valid, test = chatml.split_rows(rows)
    assert len(train) >= 1  # train must never be empty


def test_write_splits_creates_expected_files(tmp_path: Path) -> None:
    source = tmp_path / "corpus.jsonl"
    rows = [_valid_row(f"q{i}", f"a{i}") for i in range(50)]
    _write_jsonl(source, rows)
    run_dir = tmp_path / "run"
    counts = chatml.write_splits(run_dir, source)
    assert counts["train"] + counts["valid"] + counts["test"] == 50
    assert (run_dir / "data" / "train.jsonl").exists()
    assert (run_dir / "data" / "valid.jsonl").exists()
    # test.jsonl written only when non-empty.
    if counts["test"]:
        assert (run_dir / "data" / "test.jsonl").exists()


def test_write_splits_roundtrip_preserves_rows(tmp_path: Path) -> None:
    source = tmp_path / "corpus.jsonl"
    rows = [_valid_row(f"q{i}", f"a{i}") for i in range(20)]
    _write_jsonl(source, rows)
    run_dir = tmp_path / "run"
    chatml.write_splits(run_dir, source, valid_ratio=0.1, test_ratio=0.1)
    written: list[dict] = []
    for name in ("train.jsonl", "valid.jsonl", "test.jsonl"):
        p = run_dir / "data" / name
        if p.exists():
            for line in p.read_text(encoding="utf-8").splitlines():
                written.append(json.loads(line))
    # Every original row appears once, no duplicates.
    assert sorted((r["messages"][1]["content"] for r in written)) == sorted(
        (r["messages"][1]["content"] for r in rows)
    )

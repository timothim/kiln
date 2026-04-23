# packages/kiln_trainer — Python sidecar rules

Import skill: `.claude/skills/mlx-lora-finetuning/`. Load it whenever you touch training code, MLX flags, or JSONL schema.

## Scope

Python 3.11 sidecar invoked as a long-running subprocess by the Swift app. Wraps `mlx_lm.lora`, `mlx_lm.fuse`, `mlx_lm.generate`. Emits progress as JSON lines on stdout. Reads commands as JSON lines on stdin.

## Emission protocol

Every line on stdout is a single JSON object conforming to the schema in `SPEC.md §11.1`. Never print free-form text on stdout. Free-form log output goes to stderr and is captured by Kiln's logger without being parsed.

- UTF-8 only.
- `\n` terminators only (no `\r\n`).
- One event per line; never split across lines.
- Unknown fields tolerated on input; never emit unknown `event` types on output.

## Process lifecycle

- On startup: emit `{"event":"ready","version":<pyproject version>,"mlx":<mlx version>}` within 500 ms. No computation before that.
- On `{"cmd":"stop"}`: flush current checkpoint, write a final `{"event":"done",...}`, exit 0 within 5 s.
- On `SIGTERM`: same as `stop` — 5 s budget, then the OS will hard-kill.
- Unhandled exceptions: emit `{"event":"error","code":"...","message":"...","recoverable":false}` and exit with code 2.

## Dependencies

Pinned exactly in `pyproject.toml`:

- `mlx-lm==0.21.*`
- `mlx>=0.22,<0.23` (mlx-lm 0.21.5 requires mlx>=0.22 — see local `DECISIONS.md §L7`)
- `safetensors`, `sentencepiece` for tokenizer compatibility.

No other deps without a `DECISIONS.md` entry. This sidecar stays small.

## Testing

- `pytest` in `tests/`.
- Golden-file tests for event emission.
- IPC tests use subprocess + pipe assertions, no MLX calls (mock the training loop).

## YOU MUST

- Never mix logs and events on stdout.
- Never hold a reference to a full model after emitting `done`.
- Never call network endpoints. This is a local sidecar. The verifier will flag any `urllib`, `requests`, `httpx` import that isn't behind an explicit dev-only guard.

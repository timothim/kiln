# packages/KilnCore — Swift package rules

## Scope

Swift package targeting macOS 14. Contains: corpus parsers, dedup, quality-classifier bridge (CoreML), style-extractor bridge, ChatML formatter, sidecar lifecycle, IPC framing, training state machine, Ollama export orchestration.

No UI. No MLX. Those live elsewhere.

## Dependencies

Allowed: `Foundation`, `OSLog`, `CryptoKit`, `CoreML` (for distilled artifacts). Nothing else. Every additional dependency is a `DECISIONS.md` entry.

## Test-first discipline

- No module of this package is merged without at least one test.
- Golden-file tests for IPC framing.
- Property-based tests preferred for dedup (MinHash collisions, hash stability).
- `swift test` must pass on every commit. Enforced by `pre-commit.sh` hook.

## Error handling

- `throws` functions return specific typed errors (`enum IngestError: Error { ... }`).
- Never `fatalError` in library code. The app can crash; the package cannot.
- `try?` is only acceptable in test fixtures. In production code, name the error or propagate it.
- Never force-unwrap. Never force-try. Compile with `-warnings-as-errors`.

## Concurrency

- Prefer `actor` for mutable state shared across tasks.
- `@MainActor` only where explicit UI glue exists — which should be rare here.
- Detached tasks must respect cancellation.

## Files on disk

- Kiln owns `~/Library/Application Support/Kiln/`. Nothing is written outside it without an explicit user-provided path.
- Every file written is sandbox-safe (security-scoped bookmarks for user folders).

Pointer: IPC protocol lives in `SPEC.md §11` and `docs/ipc/protocol.md` — keep both in lockstep.

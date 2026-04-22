---
description: Spawn a fresh-context subagent that reviews a file or directory for concurrency bugs, edge cases, memory issues, API misuse, and security problems. Returns structured findings.
argument-hint: <path>
---

# /review

Spawn a review subagent on `${1}`.

The reviewing subagent runs in a fresh context (see `.claude/agents/verifier.md` pattern) and uses only Read, Grep, Glob. It does not modify files. This is a deliberate separation from the implementing context — second-eyes review is more reliable when it does not share the implementer's mental model.

## Inputs

- `${1}` — a file path, directory path, or glob (e.g. `apps/Kiln/Sources/IngestView.swift`).

## Behavior

1. Spawn a subagent (`Agent` tool) with the `verifier` frontmatter-defined scope narrowed to `${1}`.
2. Prompt the subagent to check for:
   - **Concurrency bugs** — Swift actor violations, Task vs Task.detached misuse, Python threads touching MLX state.
   - **Edge cases** — empty inputs, huge inputs, Unicode, path traversal, symlinks.
   - **Memory issues** — unbounded accumulators, large arrays held after use, Swift reference cycles.
   - **API misuse** — mlx_lm flags vs the pinned version, Ollama REST contract, File system permissions on macOS sandboxed apps.
   - **Security** — secrets leaked into logs, shell-exec with user input, any outbound network call that violates the "no runtime API" rule.
3. The subagent returns a JSON-like structured report:

```
findings:
  - severity: [blocker|high|medium|low|nit]
    category: [concurrency|edge-case|memory|api|security|style]
    file: <path>
    line: <N>
    what: "<one sentence>"
    why: "<one sentence>"
    fix: "<one sentence>"
summary:
  blocker: <N>
  high: <N>
  medium: <N>
  low: <N>
  nit: <N>
```

## Output

The report is printed inline and saved to `.claude/reviews/<timestamp>-${1//\//_}.md` (gitignored).

## Refuses if

- `${1}` points outside the repo.
- `${1}` is the entire repo (> 500 files). Narrow the scope first.

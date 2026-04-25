# Saturday full code audit (2026-04-25)

**Verdict: READY-WITH-CAVEATS.** Codebase is in solid shape after the
M9 ABC merge + Phase 0 real-classifier swap + Phase 1.1-1.5 fixups.
All blocker / high-severity findings fixed in this session; medium and
low items are documented below for tomorrow's review.

## Programmatic baseline

```
$ grep -rn "TODO|FIXME|XXX|HACK"  apps/Kiln/Sources packages/...   →  0 hits
$ grep -rn force-unwrap (~ /\.[a-z]/)                              →  0 hits in production code
$ grep -rn fatalError|preconditionFailure                          →  1 (added by audit fix, see M3)
$ grep -rn "print("  (excluding #if DEBUG)                          →  0 hits
$ make test                                                         →  207 Swift + 183 Python = 390 passing
$ make build                                                        →  clean
$ make demo-check                                                   →  PASS 6 / SKIP 3 / FAIL 0
```

Zero hits on every cosmetic check is itself a positive signal; the
audit narrative below focuses on findings that wouldn't show up in a
grep alone.

## Findings

### High — fixed in this session

| # | File:line | Summary | Fix |
|---|-----------|---------|-----|
| H1 | [packages/kiln_trainer/src/kiln_trainer/classifiers/quality.py:125](packages/kiln_trainer/src/kiln_trainer/classifiers/quality.py:125) | `train_idx` / `test_idx` arrays computed but never used; misleading dead code. | Removed; replaced derived counts with explicit `n_train` / `n_test` ints. |
| H2 | [packages/KilnCore/Sources/KilnCore/Chat/OllamaClient.swift:39](packages/KilnCore/Sources/KilnCore/Chat/OllamaClient.swift:39) | `URL(fileURLWithPath: "/dev/null")` fallback would have surfaced as "cannot connect to /dev/null" if the literal-constant URL ever failed to parse. | Replaced with `preconditionFailure` so a constant-parse regression fails loud at app start instead of generating a misleading runtime error. |

### Medium — fixed in this session

| # | File:line | Summary | Fix |
|---|-----------|---------|-----|
| M3 | [classifiers/preference.py:score_pair_trained](packages/kiln_trainer/src/kiln_trainer/classifiers/preference.py:316) | No exception handler around `_embedder(...).encode(...)`; transient sentence-transformers / HF cache failure would crash the runtime. | Wrapped embedder call in try/except → `score_pair_heuristic` fallback. Same shape as `style.descriptors_trained`. |
| M5 | [packages/KilnCore/Sources/KilnCore/Ingest/ClassifierQualityGate.swift:route](packages/KilnCore/Sources/KilnCore/Ingest/ClassifierQualityGate.swift:90) | Gate degradations (nil runner, runner threw, count mismatch) silently fell back to "all-keep" with no log signal. UI showed `Voice-passed: N` even when classifier never ran. | Added `Logger(subsystem:"dev.kiln.core",category:"classifier-gate")` warnings on every degradation path. UI still hides the funnel ticker via `didRun=false`; OS log captures the reason. |
| M6 | [packages/kiln_trainer/src/kiln_trainer/commands/embed_search.py:84](packages/kiln_trainer/src/kiln_trainer/commands/embed_search.py:84) | Per-row `json.loads` had no try/except — one malformed line killed the run before the terminal `done` event. | Phase 1.3 fix: per-row try/except → recoverable `error` event + skip + continue. Empty-text rows also filtered before the embedder. |
| M7 | [packages/KilnCore/Sources/KilnCore/Backup/BackupService.swift:131](packages/KilnCore/Sources/KilnCore/Backup/BackupService.swift:131) | `appendingPathComponent(entry.path)` accepted `..`-segments and absolute paths in restore. | Phase 1.2 fix: `assertSafeEntryPath(...)` rejects absolutes and `..` components, throws new `BackupError.unsafeEntryPath`. |

### Medium — deferred (logged for Tim's morning review)

| # | File:line | Summary | Recommended fix |
|---|-----------|---------|-----------------|
| M8 | [tests/classifiers/test_classify_subcommand.py:59](packages/kiln_trainer/tests/classifiers/test_classify_subcommand.py:59) | No test covers `--mode quality --input-file` with a malformed JSONL row + missing artifact combination — the classify subcommand's per-row error handling under bulk mode is untested. | Add 1 test covering each branch. ~15 min. |
| M9 | [classifiers/quality.py:104-116](packages/kiln_trainer/src/kiln_trainer/classifiers/quality.py:104) docstring | Describes "threshold at 0.5 for binary fit" but doesn't mention the runtime 0.70 / 0.40 bucket boundaries. | One-line clarification: training threshold ≠ inference thresholds. |

### Low — deferred

| # | File:line | Summary |
|---|-----------|---------|
| L10 | [embed_search.py:109](packages/kiln_trainer/src/kiln_trainer/commands/embed_search.py:109) | `request_id` fallback uses `len(rows)` (correct by accident — index-after-append). Add a comment or pre-compute `idx`. |
| L11 | [VoiceInspectorModelTests.swift:72](apps/Kiln/Tests/KilnTests/VoiceInspectorModelTests.swift:72) | Poll-loop with 10ms sleep up to 2s; flaky on slow CI. Replace with XCTWaiter or async expectation. |
| L12 | [classifiers/preference.py:1-14](packages/kiln_trainer/src/kiln_trainer/classifiers/preference.py:1) module docstring | Says heuristic is the "fast fallback" but post-Phase-0 the trained model is the primary surface. Wording is reversed. |

## Files with zero findings (positive signal)

- `packages/KilnCore/Sources/KilnCore/Sharing/ShareExporter.swift` — solid subprocess isolation, typed errors, no force-unwraps.
- `packages/KilnCore/Sources/KilnCore/Backup/BackupService.swift` (post-fix) — atomic writes, path-traversal guard, error recovery.
- `packages/kiln_trainer/src/kiln_trainer/commands/classify.py` — per-row recovery, staged error/done emission.
- `apps/Kiln/Sources/Features/Chat/ChatModel.swift` — clean cancellation, explicit error translation, no silent failures.
- `apps/Kiln/Sources/Features/VoiceInspector/VoiceInspectorModel.swift` — duplicate-id guard, weak-self closures, async cancellation respected.
- `packages/kiln_trainer/src/kiln_trainer/modelfile.py` — newline rejection strict, escape logic correct.

## Demo recording risk areas

In order of severity:

1. **sentence-transformers first-run download blocks Voice Inspector for 30+ s.** The model (~80 MB) is fetched lazily on first `embed-search` call. If the demo machine's HF cache is cold when Tim taps a chat bubble, the panel's loading spinner stalls visibly. **Mitigation:** before the take, run `python -m kiln_trainer embed-search --query x --corpus-file <small fixture> --top-k 1` once to warm the cache; verify `~/.cache/huggingface/hub/models--sentence-transformers--all-MiniLM-L6-v2/` exists.
2. **Ollama daemon unreachable surfaces only via the chat error banner.** If Tim forgets to start `ollama serve` before the chat segment, the `daemonUnreachable` ChatError fires correctly but the demo loses ~5 s of dead-air. **Mitigation:** add `ollama list` to the pre-flight checklist. The post-audit `preconditionFailure` won't fire here — it's for a different code path.
3. **Quality classifier gate may fall back silently if the kiln_trainer subprocess fails to launch.** Audit fix M5 added OS log warnings, so the failure is now visible in Console.app — but the user-visible UI doesn't flag it. The funnel ticker hides itself (correct behavior) but a curious viewer might wonder why "Voice-passed" doesn't appear in some takes. **Mitigation:** before each take, smoke-test the gate by running `python -m kiln_trainer classify --mode quality --artifact packages/kiln_trainer/artifacts/quality-classifier.pkl --text "test"` and confirming a `classification` event lands on stdout.

## Test counts

| Surface | Pre-audit | Post-audit | Δ |
|---|---|---|---|
| Swift (`make test`) | 196 | 207 | +11 |
| Python (`make test`) | 170 | 183 | +13 |
| **Total** | **366** | **390** | **+24** |

(App-target tests via xcodebuild add ~16 more; not counted in `make test` totals.)

## Next actions

- Land all Phase 1 + Phase 2 commits via PR(s) targeting `main` (Phase 4).
- Write the final session report at `docs/sessions/saturday-final.md` (Phase 5).
- Don't merge — leave for Tim's morning review.

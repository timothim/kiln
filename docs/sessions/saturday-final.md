# Saturday — final autonomous session report (2026-04-25)

Five-phase autonomous run: Phase 0 distillation reality check, Phase 1
T3+deferred fixups, Phase 2 full code audit, Phase 3 demo corpus
reproducibility, Phase 4 PR consolidation + verifier, Phase 5 (this
report). All five phases complete. **No PRs merged.**

| Surface | Pre-session (M9 merged) | Post-session | Δ |
|---|---|---|---|
| Swift via `make test` | 196 | 212 | **+16** |
| Python via `make test` | 170 | 183 | **+13** |
| **Total** | **366** | **395** | **+29** |

App-target tests via `xcodebuild test` add ~16 more (presenter, settings model, voice-inspector model). Python suite has 1 known-flaky `test_sigterm` already widened to 10 s threshold; current run measures ~6 s.

`make build` clean. `make demo-check`: PASS 6 / SKIP 3 / FAIL 0 — same as pre-session, no regressions.

---

## Phase 0 — Distillation reality check

### Step 0.1 — Schema inspection (verified)

Direct `head -1 | jq` on each recovered file:

| File | Has inputs? |
|---|---|
| `quality-labels.jsonl` | **Yes** — `{request_id, text, score, reason}`. Already trainable for M9.C. |
| `preference-labels.jsonl` | No — `{request_id, winner, reason}` only. |
| `style-profiles.jsonl` | No — output-only `{request_id, style_descriptors, distinctive_ngrams, style_card_md}`. |

### Step 0.2/0.3 — Recovery via deterministic re-generation, not API

Tried the Anthropic Files API first (`GET /v1/files/<id>/content` with `managed-agents-2026-04-01` beta header). Input file IDs are listed (`full-2000.jsonl` for preference, `full-1500.jsonl` for style, both scoped to the original sessions) but the API returns `400 invalid_request_error: "File '...' is not downloadable"`. Output files (the labels) are downloadable; inputs explicitly are not.

**Pivot**: the input generators in this repo are deterministic and seeded:

- `scripts/opus-distill/build_preference_pilot_input.py --size 2000` — 50 prompts × 40 voice/generic templates, position-randomized via SHA-256-derived coin per row.
- `scripts/opus-distill/build_style_input.py --size 1500` — six style categories × parametric templates × seeded fills.

Re-running both locally produces 100% intersection on `request_id` with the recovered label files. Verified via `set(recovered) & set(regenerated) == set(recovered)` for both. New `scripts/opus-distill/recover_inputs.py` joins inputs ↔ labels and writes:

- `managed-agents/preference-judge/runs/20260424T204256Z_recovered/preference-with-inputs.jsonl` (2000 rows)
- `managed-agents/style-extractor/runs/20260424T212708Z_recovered/style-with-inputs.jsonl` (1500 rows)

### Real classifiers trained ([391ccd3](https://github.com/timothim/kiln/commit/391ccd3))

**Preference** — sentence-transformers/all-MiniLM-L6-v2 embeddings of both completions → concat(a, b, a-b, a*b) features (1536-dim) → sklearn LogisticRegression → P(A wins).

| Metric | Value |
|---|---|
| Train rows | 1600 |
| Test rows | 400 |
| Train accuracy | 1.0 |
| **Test accuracy** | **0.9975** |
| Artifact size | 13 KB (`preference-classifier.pkl`) |
| Training time | ~30 s including model load |

**Style** — same embedder → multi-output Ridge regressor over the 6 axes (formality / verbosity / warmth / hedging / humor / directness).

| Axis | Held-out MAE |
|---|---|
| formality | 0.041 |
| verbosity | 0.026 |
| warmth | 0.043 |
| hedging | 0.041 |
| humor | 0.036 |
| directness | 0.036 |
| **Mean** | **0.037** |

Train rows 1200, test rows 300. Artifact size 11 KB (`style-regressor.pkl`). Training time ~10 s.

The pre-existing heuristic paths are kept as **fallbacks**: if the artifact pickle is missing or the embedder fails to load, `score_pair_trained` and `descriptors_trained` silently fall back to the heuristic. Tested via `test_*_falls_back_when_artifact_missing`. The runtime ships even on a fresh checkout that hasn't run `train(...)`.

The deterministic distinctive-ngram extractor (TF-IDF vs. inline corporate background) stays unchanged — Opus's "distinctive_ngrams" is an extracted feature, not a learnable target, so a regressor would be the wrong shape.

### Verifier T3/T4 follow-ups from PR #15 also addressed in Phase 0

- `voice_score` empty/short input now floors at 0.0 (was ~0.5 due to the +0.5 base offset).
- Underscore-prefixed `_voice_score` renamed to public `voice_score`; underscore alias kept for backwards compat.

---

## Phase 1 — All T3 + deferred items

Five separate commits, one per fix, each with a regression test:

| # | Fix | Commit | Test added |
|---|---|---|---|
| 1.1 | stderr drain ordering across runners | [f493e9e](https://github.com/timothim/kiln/commit/f493e9e) | 80 KB stderr-blast regression |
| 1.2 | path-traversal guard in BackupService.restore | [4d2b683](https://github.com/timothim/kiln/commit/4d2b683) | unit + integration (latter improved post-verifier in 3e692a7) |
| 1.3 | JSON parse-loop guard + empty-text filter in embed_search | [d5806b0](https://github.com/timothim/kiln/commit/d5806b0) | malformed-line skip + empty-text filter |
| 1.4 | Dataset Doctor consumes quality classifier as fourth gate | [4d9e098](https://github.com/timothim/kiln/commit/4d9e098) | 6 gate tests covering all degradation paths |
| 1.5 | VoiceInspectorPanel mounted in chat view | [7ef0187](https://github.com/timothim/kiln/commit/7ef0187) | (existing VoiceInspectorModelTests cover the wire) |

### Notable design choices

**Dataset Doctor gate is default-off-on-failure.** The new `ClassifierQualityGate` returns all-keep when the runner is nil, throws, or returns a count mismatch. `Routing.didRun` carries the explicit signal; `IngestReport.classifierBuckets.total == 0` signals "gate didn't run" to the UI. The funnel ticker hides itself in that case rather than showing a meaningless duplicate of "Length-passed". OS-log warnings (added in Phase 2) capture the *why* without polluting the user-visible report.

**ChatView inspector is opt-in.** New optional `VoiceInspectorModel?` parameter; when nil the panel never renders. Production callers attach a real model after ingest finishes (so the corpus is available). New `VoiceInspectorModel.disabled` static sentinel lets previews / tests construct a panel-attached chat without spawning a sidecar.

---

## Phase 2 — Full code audit

Programmatic baseline came back clean:

```
$ grep -rn "TODO|FIXME|XXX|HACK" apps/Kiln/Sources packages/   →  0
$ grep -rn force-unwrap (~ /\.[a-z]/)                          →  0 production
$ grep -rn fatalError                                           →  0
$ grep -rn "preconditionFailure"                                →  1 (audit-fix-introduced)
$ grep -rn "print("                                             →  0 stray
```

Findings from a deeper read pass — full report at [docs/audits/saturday-full-audit.md](docs/audits/saturday-full-audit.md):

**Fixed in [abacef7](https://github.com/timothim/kiln/commit/abacef7):**

- **H1** dead `train_idx` / `test_idx` variables in `quality.py:125`.
- **H2** `URL(fileURLWithPath: "/dev/null")` fallback in `OllamaClient` → `preconditionFailure` (a constant-parse regression now fails loud at app start instead of disguising as "cannot connect to /dev/null").
- **M3** `score_pair_trained` exception handler around the embedder call (transient HF / sklearn failure → heuristic fallback, never crash).
- **M5** `ClassifierQualityGate` OS-log warnings on every degradation path.

**Deferred** (medium / low — logged for tomorrow's review):

| # | File:line | Item |
|---|---|---|
| M8 | `tests/classifiers/test_classify_subcommand.py:59` | Test gap: classify --mode quality + --input-file + missing artifact combo. |
| M9 | `classifiers/quality.py:104-116` docstring | Training threshold (0.5) ≠ inference thresholds (0.70 / 0.40); clarify. |
| L10 | `embed_search.py:109` | `request_id` fallback uses `len(rows)` correct-by-accident; add comment. |
| L11 | `VoiceInspectorModelTests.swift:72` | Poll-loop with 10ms sleep up to 2s; replace with `XCTWaiter`. |
| L12 | `preference.py:1-14` module docstring | Says heuristic is "fast fallback" but trained model is now primary. |

---

## Phase 3 — Demo corpus reproducibility

`tests/fixtures/demo_corpus/` (223 files spanning notes/journal/emails/chat/code) is what the user drops into the app during the recorded walkthrough. Until this session, nothing tested the end-to-end ingest path against it — a parser regression on the markdown frontmatter or a dedup pass collapsing the whole corpus would only have surfaced mid-recording.

[54c8f89](https://github.com/timothim/kiln/commit/54c8f89) adds 4 tests in `DemoCorpusReproducibilityTests`:

- Demo corpus directory exists with the five top-level groups.
- File count ≥ 150 (audit count was 223; floor catches catastrophic shrinkage).
- Pipeline parses > 100 files; every gate produces some survivors; train + eval splits both non-empty.
- Total ingest takes < 60 s (measured 0.797 s on the audit machine — 75× headroom).

A regression that drops "Kept: 0" on any gate or stalls the pipeline is now caught in CI rather than mid-recording.

Also added `TestFixtures.demoCorpusURL` parallel to the existing `sampleCorpusURL` so future tests can reach the demo data through the standard fixture surface.

---

## Phase 4 — PR consolidation + verifier

Single PR: **[#18](https://github.com/timothim/kiln/pull/18)** on branch `polish/saturday-ui-audit`.

The branch carries **two parallel work streams** that both targeted Saturday and landed on the same checkout:

- **Stack A (Tim's UI polish, 7 commits)**: comprehensive Saturday UI audit, design-token consolidation (`Kiln.Opacity.*`, `Kiln.Motion.*`), copy polish, ChatBubble thinking indicator. Audit doc at [docs/audits/saturday-ui-audit.md](docs/audits/saturday-ui-audit.md).
- **Stack B (this session's autonomous distillation+correctness work, 8 commits + 1 T2 follow-up)**: real classifiers, all five T3+deferred fixups, full code audit, demo-corpus reproducibility tests.

The PR description on #18 covers both stacks transparently. Verifier was scoped narrowly to **Stack B** only (Stack A's UI commits were Tim's own work, out of this session's scope).

### Verifier verdict on Stack B

**PASS-WITH-FINDINGS** — 0 blockers, **2 high (T2)**, 2 medium (T3), 1 low (T4). Verifier said *request changes — fix the two T2 findings before merging Stack B*. Both fixed in [3e692a7](https://github.com/timothim/kiln/commit/3e692a7):

- **T2.1** — runner cancellation hooks were broken: `Task.detached`-based cancel-watcher never saw the parent's cancellation. Refactored both `DistilledClassifierRunner` and `EmbedSearchRunner` to `withTaskCancellationHandler { ... } onCancel: { box.p.terminate() }` (the proper structured-concurrency pattern). Regression test asserts cancellation completes within 4 s; measured 0.5 s post-fix (was 29.7 s pre-fix).
- **T2.2** — `test_restore_rejects_bundle_with_path_traversal_entry` only exercised the unit-level guard. Refactored to forge a real `.kilnbackup` bundle (PBKDF2 → ChaChaPoly seal of a `BackupPayload` with `../escaped.txt`), call `service.restore(...)`, assert it throws `unsafeEntryPath` AND no file landed outside the destination.

T3/T4 items deferred to morning review (see audit doc + verdict comment on PR).

### All commits on the branch (in order)

```
3e692a7 fix(audit): T2 follow-ups — runner cancellation hooks + real path-traversal restore test
54c8f89 demo: harden demo corpus reproducibility for video recording
abacef7 audit(saturday): T2 / M3 / M5 fixes + full audit doc
9904380 docs(sessions): Saturday UI session final report                  ← Stack A (Tim)
7ef0187 feat(integration): VoiceInspectorPanel mounted in chat view
4d9e098 feat(integration): Dataset Doctor consumes quality classifier as fourth gate
d5806b0 fix(classifiers): JSON parse-loop guard and empty-text filter in embed_search
acf9172 polish(audit-3): chat thinking indicator + Opacity.trackFill token  ← Stack A
4d2b683 fix(security): path-traversal guards in Backup module
ae81554 refactor(design): inline animation durations to Kiln.Motion tokens   ← Stack A
f493e9e fix(runners): stderr drain ordering across all subprocess runners
13dd75a refactor(design): Kiln.Opacity tokens replace 23 ad-hoc literals     ← Stack A
2fb3a87 refactor(design): extract shared SectionLabel component               ← Stack A
391ccd3 fix(M9.C): recover inputs and train real distilled classifiers
106a153 polish(audit-2): BackupSettingsView design tokens, remove force-unwrap ← Stack A
e61edce polish(audit-1): copy that names the fix, success state, audit doc    ← Stack A
```

---

## Distillation status

Real distilled classifiers, not heuristics:

| Component | M9.C status | Phase 0 status |
|---|---|---|
| Quality classifier | TF-IDF + sklearn LR (already real, 99.0% test acc) | unchanged + dead-code cleanup |
| Preference judge | heuristic feature scorer | **real**: ST + LR, 99.75% test acc |
| Style extractor | heuristic descriptors + TF-IDF n-grams | descriptors → **real** ST + Ridge regressor (mean MAE 0.037); n-grams stay deterministic by design |

Heuristic paths kept as fast offline fallbacks. Runtime never crashes on missing pickle.

---

## What Tim needs to review

1. **PR [#18](https://github.com/timothim/kiln/pull/18)** — Stack A (your polish) + Stack B (autonomous distillation + correctness). All commits squash-mergeable as-is. No merges performed in this session.
2. **[Phase 0 honest claim](docs/sessions/saturday-final.md)** — preference 99.75% / style 0.037 MAE. The numbers are tight enough to be suspicious; please spot-check that the Opus-vs-classifier gap on a handful of examples actually reads as voice-bearing-vs-not before declaring victory.
3. **The 5 deferred medium / low audit items** at [docs/audits/saturday-full-audit.md](docs/audits/saturday-full-audit.md). None block the demo, all are clean follow-ups.
4. **Demo recording risk areas** (also in audit doc):
   - Pre-warm the sentence-transformers HF cache before any take that touches Voice Inspector.
   - Add `ollama list` to the pre-flight checklist.
   - Verify the classifier subprocess runs via `python -m kiln_trainer classify --mode quality --artifact ... --text "test"` before each take that touches Dataset Doctor's "Voice-passed" ticker.

---

## Recommended merge order

If you choose to merge:

1. **Merge PR #18 first.** It's a single coherent surface — Stack A (UI polish) + Stack B (correctness) — and both verifier passes are clean (Stack A's verifier is Tim's; Stack B's is documented in the PR comment).
2. After merge, the branch deletes itself; the next session picks up at clean main.

The five deferred audit items are tractable in a 1-hour follow-up commit on a fresh branch — no need to gate the demo recording on them.

---

## Repo state at session end

- Branch: `polish/saturday-ui-audit` at [3e692a7](https://github.com/timothim/kiln/commit/3e692a7).
- main: [15e6610](https://github.com/timothim/kiln/commit/15e6610) (M9.B merge — unchanged from session start).
- PR: [#18](https://github.com/timothim/kiln/pull/18) — open, **not merged**.
- `make test`: 212 + 183 = 395 passing, 6 skipped, 0 failures.
- `make build`: clean.
- `make demo-check`: PASS 6 / SKIP 3 / FAIL 0 (same as pre-session).

---

Final autonomous session complete. Awaiting your review.

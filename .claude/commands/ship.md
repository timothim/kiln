---
description: Final pre-submission audit for the hackathon. Tests, warnings, LICENSE, README demo GIF, writeup length, video length, CLAUDE_USAGE.md completeness. Fails loud if anything is missing.
---

# /ship

Final ship gate before submitting to the hackathon.

## Inputs

- (none)

## Behavior

1. Run `make test`. Must pass with zero failures.
2. Run `make build`. Must produce a Release build with zero warnings. Parse build log for any `warning:` lines.
3. Verify repo hygiene:
   - `LICENSE` exists and contains "MIT".
   - `README.md` exists and references `docs/demo/hero.gif`.
   - `docs/demo/hero.gif` exists and is < 20 MB.
   - `CLAUDE.md`, `SPEC.md`, `CLAUDE_USAGE.md` all exist.
4. Verify `CLAUDE_USAGE.md`:
   - All 7 sections present.
   - Zero remaining `<!-- FILL DURING SPRINT -->` markers.
   - Evidence (screenshots, stats, numbers) in every section.
5. Verify video:
   - `docs/demo/final.mp4` exists.
   - Duration <= 180 seconds (3:00), measured via `ffprobe`.
   - Resolution >= 1920x1080.
   - Audio present, not clipped.
6. Verify writeup:
   - `docs/submission/writeup.md` exists.
   - Word count 100–200.
7. Verify runtime-purity claim:
   - Grep `apps/Kiln` and `packages/KilnCore` for `api.anthropic.com`, `ANTHROPIC_API_KEY`, `openai.com`, `OPENAI_API_KEY`. Zero hits required.
   - Grep `Info.plist` entitlements for any outbound-network request to Anthropic/OpenAI. Zero.
8. Verify git state:
   - On `main`. Clean working tree. Tagged `v1.0-submission`.

## Output structure

```
SHIP AUDIT — <date>
===================

Tests:              [pass|FAIL]  (<N> passed)
Build:              [pass|FAIL]  (<N> warnings)
Repo hygiene:       [ok|FAIL]
CLAUDE_USAGE.md:    [ok|FAIL]    (<N> TODO markers remaining)
Video:              [ok|FAIL]    (<H:MM:SS>, <WxH>, <MB>)
Writeup:            [ok|FAIL]    (<N> words)
Runtime purity:     [ok|FAIL]    (<N> suspicious hits)
Git state:          [ok|FAIL]

READY TO SHIP: [YES|NO]
```

## Refuses nothing — this is read-only. A `NO` verdict is the refusal.

---
description: Audit the current product state against the North Star Demo sequence in SPEC.md. Returns a checklist of what's missing before the demo can be recorded.
---

# /demo-check

Audit against `SPEC.md §2 — North Star Demo` and the `.claude/skills/kiln-demo-recording/` pre-flight checklist.

## Inputs

- (none) — this command is argument-free. It reads the current repo state.

## Behavior

1. Load `SPEC.md §2` (the 7-step sequence) and `.claude/skills/kiln-demo-recording/SKILL.md §5 Pre-flight` into context.
2. For each of the 7 demo steps, determine the product-state evidence:
   - Step 1 (Drop) — does `apps/Kiln/Sources/IngestView.swift` exist with a drop zone?
   - Step 2 (Dataset Doctor) — does the view render file counts / dedup stats?
   - Step 3 (Style profile) — is the distilled `style-extractor` shipped and wired?
   - Step 4 (Training) — does pressing *Teach* start an SFT run end-to-end?
   - Step 5 (Growing Model) — are the three fixed prompts streamed during training?
   - Step 6 (Before/After) — is the split-pane compare view present?
   - Step 7 (Ollama export) — does the export flow end with `ollama run kiln-*`?
3. For each pre-flight item from the demo skill, verify its precondition (base model cached, Ollama running, corpus pre-staged, distilled artifacts present).
4. Emit a checklist.

## Output structure

```
Demo readiness: <N/7 steps OK> / <M/10 pre-flight OK>

North Star Demo
  [x] 1. Drop                -> IngestView.swift:42
  [x] 2. Dataset Doctor      -> DatasetDoctorView.swift:18
  [ ] 3. Style profile       -> MISSING: style-extractor artifact not shipped
  [x] 4. Training            -> TrainView.swift:71 + sidecar cmd=sft
  [ ] 5. Growing Model       -> PARTIAL: only 2 prompts wired (need 3)
  [ ] 6. Before/After        -> MISSING
  [ ] 7. Ollama export       -> MISSING: Modelfile template not wired

Pre-flight
  [x] Base model cached
  [ ] Ollama running (fix: `ollama serve`)
  ...

Blocking items: 4
Estimated time to ready: <N> hours
```

## Refuses nothing — this is read-only.

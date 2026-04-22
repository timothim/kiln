# kiln_trainer — Local Decisions

Local, sidecar-internal decisions. Project-wide choices live in the root
`DECISIONS.md`. One entry per decision, append-only.

---

## L1. `mlx_lm.lora` hyperparameter surface: YAML config, not CLI flags

- **Date:** 2026-04-22
- **Context:** The `mlx-lora-finetuning` skill (SKILL.md §5) shows a sample
  invocation including `--rank`, `--alpha`, and `--lora-layers`. In MLX-LM
  0.21.5 (pinned per root `DECISIONS.md §1`), only `--num-layers` exists on
  the CLI. `rank`, `alpha`, `dropout`, `scale`, and the target-module list
  are **YAML-only**, consumed through `--config`
  (`mlx_lm.lora.CONFIG_DEFAULTS` in the source).
- **Options considered:**
  - Call `mlx_lm.lora` directly in-process and bypass the CLI — tight
    coupling to MLX internals; harder to test with subprocess fixtures;
    contradicts the "wrap, do not re-implement" rule in root `CLAUDE.md`.
  - Upgrade/downgrade mlx-lm to a version whose CLI matches the skill —
    not a thing: the skill was written against a mix of older docs and
    wishful thinking. No shipped version exposes `--rank`/`--alpha`.
  - Render a YAML config at runtime and pass `--config <path>` alongside
    the CLI flags MLX-LM actually accepts.
- **Choice:** Render a throwaway `<run_dir>/lora_config.yaml` on every
  `train` invocation and pass it via `--config`. CLI-only knobs
  (`--num-layers`, `--batch-size`, `--learning-rate`, `--iters`,
  `--save-every`, `--val-batches`, `--max-seq-length`, `--grad-checkpoint`)
  stay on the argv.
- **Reason:** Only way to set `rank`/`alpha`/target-modules against
  mlx-lm 0.21.5. YAML also gives us a readable audit trail of the exact
  LoRA config a run used.
- **Reversible?** Yes — if mlx-lm later promotes these to CLI flags we
  replace the YAML render with an argv append.

---

## L2. Target modules are qualified paths, not short names

- **Date:** 2026-04-22
- **Context:** SPEC.md §6.2 lists target modules as `q_proj`, `k_proj`,
  `v_proj`, `o_proj`, etc. — the short names. MLX-LM's
  `linear_to_lora_layers` (in `mlx_lm/tuner/utils.py`) matches
  `lora_parameters.keys` against the **fully qualified** module path (e.g.
  `self_attn.q_proj`, `mlp.gate_proj`) produced by `model.named_modules()`.
  Short names never match a Qwen2.5 module and LoRA would be applied to zero
  layers — silent failure: training proceeds but nothing is learned.
- **Choice:** `hyperparams.Hyperparams` carries **two** fields:
  - `target_modules`: the SPEC.md-facing short names (public API).
  - `lora_keys`: the qualified MLX paths written into the YAML config.
- **Reason:** Keeps SPEC.md human-readable while handing MLX-LM the exact
  strings it expects. The mapping is stable for Qwen2.5 (all attention
  blocks live under `self_attn.*`, MLP blocks under `mlp.*`).
- **Reversible?** Yes; would need updating if a non-Qwen base family were
  supported, but root `CLAUDE.md` forbids that ("do not expand the
  supported base-model list beyond the three in `SPEC.md`").

---

## L3. No `--dpo` / `--beta` flags on `mlx_lm.lora`

- **Date:** 2026-04-22
- **Context:** The skill hints at DPO support via `--dpo --beta 0.1` on
  `mlx_lm.lora`. These flags do not exist in mlx-lm 0.21.5. SPEC.md §6.1
  keeps DPO as a stretch goal for M3; M2's scope is SFT only.
- **Choice:** `train` subcommand is SFT-only. DPO plumbing is not built
  in M2; when we add it in M3 we will evaluate `mlx_lm.dpo` (the
  sibling module) rather than extending `mlx_lm.lora`.
- **Reason:** Avoids building surface against a flag that isn't there.
- **Reversible?** Yes — `train.py` gains a `--loss dpo` branch in M3.

---

## L4. `generation` event distinct from training-time `sample`

- **Date:** 2026-04-22
- **Context:** SPEC.md §11.1 defines a `sample` event carrying `iter`,
  `prompt_id`, `completion`, `tokens_per_s` — emitted during training
  (Growing Model view, SPEC §6.3). The `sample` CLI (one-off inference)
  produces a semantically different payload: no `iter`, full `prompt` text,
  explicit `tokens`.
- **Options considered:**
  - Reuse `sample` with optional `iter` / required `prompt` — inconsistent
    field semantics across the same event type; Swift parser would need a
    discriminator. Sacrifices the event-type = shape invariant.
  - Add a new `generation` event type dedicated to the `sample` CLI.
- **Choice:** New `generation` event type in `events.EVENT_TYPES`, with a
  new `generation` stage in `events.STAGES`.
- **Reason:** Preserves the one-type-one-shape invariant the Swift parser
  relies on.
- **Reversible?** Yes; collapsing back into `sample` later would be a Swift
  parser change only.

---

## L5. Fake binaries (fixtures) as test seam instead of mocking

- **Date:** 2026-04-22
- **Context:** Each subcommand spawns a real subprocess. Mocking
  `subprocess.Popen` would let us test the wrapper in isolation but
  wouldn't exercise the line-buffered stdout, SIGTERM forwarding, or
  pipe-drain logic — the things most likely to break in practice.
- **Choice:** Ship fake binaries under `tests/fixtures/` (`fake_trainer.py`,
  `fake_generator.py`, `fake_fuser.py`, `llama.cpp/convert_hf_to_gguf.py`,
  `fake_ollama.py`) that speak the same stdout format as the real tools
  and honour SIGTERM. Hidden `--*-entry` / `--*-bin` argparse flags
  (`argparse.SUPPRESS`) let tests point at them without touching
  production code paths.
- **Reason:** Tests exercise the full IPC pipeline — the very thing the
  Swift parent will see at runtime. No MLX installation required in CI.
- **Reversible?** Yes — mocks can be reintroduced per test if needed.

---

## L6. SIGTERM handler installed in `cli.main()`, not inside subcommands

- **Date:** 2026-04-22
- **Context:** First pass installed the SIGTERM handler inside
  `train.run()`. A SIGTERM arriving between `events.emit(ready)` and the
  `install_sigterm_handler()` call hit Python's default disposition and
  killed the process without emitting a `done` event — observed
  reproducibly by `tests/test_sigterm.py::test_sigterm_before_any_iter_*`.
- **Choice:** `cli.main()` installs the handler first thing, even before
  argparse. `runtime.install_sigterm_handler()` is now idempotent (caches
  the `threading.Event` in a module global) so subcommands can still call
  it on entry without clobbering the flag.
- **Reason:** Closes the race window. The `ready` event still fires well
  under the 500 ms budget (`signal.signal` is microseconds).
- **Reversible?** Yes — if `signal.signal` were too expensive to call
  pre-ready (it isn't) we could move to a lazy installer.

---

## L7. `mlx` pinned to `>=0.22,<0.23`, not `mlx==0.16.*`

- **Date:** 2026-04-22
- **Context:** `packages/kiln_trainer/CLAUDE.md` originally listed
  `mlx==0.16.*`. `mlx-lm==0.21.5`'s own `requirements.txt` declares
  `mlx>=0.22.0`, so `uv sync` refuses the combination
  (`mlx-lm==0.21.* depends on mlx>=0.22.0`, not satisfiable with
  `mlx==0.16.*`).
- **Choice:** Pin `mlx>=0.22,<0.23` in `pyproject.toml` and update the
  sidecar's CLAUDE.md §Dependencies to match.
- **Reason:** The stated `mlx-lm==0.21.*` pin is the one the skill content
  and stdout-parsing regexes are written against — keep that fixed and
  move the `mlx` pin to what mlx-lm actually accepts.
- **Reversible?** Yes; if we later upgrade mlx-lm to a 0.22+ line we
  re-evaluate both pins together.

<!-- Append new decisions below. Number sequentially with the `L` prefix to
distinguish sidecar-local entries from root DECISIONS.md. -->

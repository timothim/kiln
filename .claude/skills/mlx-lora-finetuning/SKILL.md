---
name: mlx-lora-finetuning
description: Operational recipe for running LoRA fine-tunes with MLX-LM on Apple Silicon — exact CLI invocations, ChatML schema, hyperparameters by model size, OOM diagnosis, fuse and GGUF conversion, Ollama Modelfile template. Load this skill whenever Claude Code is writing code that calls mlx_lm, formatting training data, diagnosing training failures, converting adapters to GGUF, or authoring Ollama Modelfiles.
---

# MLX LoRA fine-tuning — the Kiln recipe

This is the operational runbook the Python sidecar and any Claude Code session must follow when producing, running, or debugging an MLX-LM LoRA run for Kiln. Supersedes ad-hoc habits. When upstream changes, update this file and bump the version in `packages/kiln_trainer/pyproject.toml`.

Reference: MLX-LM docs <https://github.com/ml-explore/mlx-lm>. If a flag in those docs contradicts this file, this file is wrong — open a PR before deviating.

## 1. Environment

```
uv venv --python 3.11 .venv
source .venv/bin/activate
uv pip install "mlx-lm==0.21.*" "mlx==0.16.*" safetensors sentencepiece
```

MLX-LM versions before 0.19 lack the `--dpo` flag. Pin exactly.

## 2. Data layout

Every example is a single JSON line with a `messages` array in ChatML format. Write to `<run_dir>/data/{train,valid,test}.jsonl`.

```json
{"messages":[{"role":"system","content":"You are Timothée, responding in their voice."},{"role":"user","content":"Quick take on the deploy?"},{"role":"assistant","content":"Ship it. Monitor the p95 overnight; we can still roll back before standup."}]}
```

Rules:

- Exactly one user turn and one assistant turn per SFT example (multi-turn supported but not used in v1 — see SPEC §1.2).
- System prompt is constant across a run; set from the OS account full name.
- DPO pairs use the same shape but paired:

```json
{"prompt":{"messages":[{"role":"system","content":"..."},{"role":"user","content":"..."}]},
 "chosen":"<user's own text>",
 "rejected":"<low-quality or generic paraphrase>"}
```

Validation set: 5% of rows, stratified by source file. Test: 2%. Never more than 1,000 rows in test — it wastes fuse time.

## 3. SFT — exact invocation

```
python -m mlx_lm.lora \
  --model mlx-community/Qwen2.5-3B-Instruct-4bit \
  --train \
  --data <run_dir>/data \
  --adapter-path <run_dir>/adapters \
  --iters 900 \
  --batch-size 2 \
  --learning-rate 1e-4 \
  --lora-layers 16 \
  --num-layers 16 \
  --save-every 50 \
  --val-batches 25 \
  --max-seq-length 2048 \
  --grad-checkpoint \
  --seed 42
```

Emits training metrics every 10 iters to stdout. The Kiln sidecar wraps this and transforms each line into the IPC event schema (`SPEC.md §11`).

## 4. DPO — exact invocation

```
python -m mlx_lm.lora \
  --model mlx-community/Qwen2.5-3B-Instruct-4bit \
  --train --dpo \
  --data <run_dir>/data_dpo \
  --adapter-path <run_dir>/adapters_dpo \
  --resume-adapter-file <run_dir>/adapters/adapters.safetensors \
  --iters 300 \
  --batch-size 1 \
  --learning-rate 5e-6 \
  --beta 0.1 \
  --save-every 25
```

`--resume-adapter-file` continues from the SFT adapters — do not start DPO from scratch. `--beta 0.1` keeps the DPO update from overpowering SFT gains. `--learning-rate 5e-6` is lower than SFT deliberately.

## 5. Hyperparameters by base size

Defaults. Override in code only with a DECISIONS.md entry.

| Size | Rank | Alpha | LoRA layers | Epochs | Batch | LR | Target modules |
|---|---|---|---|---|---|---|---|
| **1.5B** | 16 | 32 | 28 | 3 | 4 | 2e-4 | q_proj, k_proj, v_proj, o_proj |
| **3B (default)** | 16 | 32 | 16 | 2 | 2 | 1e-4 | q_proj, k_proj, v_proj, o_proj, gate_proj, up_proj, down_proj |
| **7B** | 8 | 16 | 8 | 1 | 1 | 5e-5 | q_proj, v_proj |

Rationale: fewer LoRA layers and modules on larger bases keeps adapter size small and shortens fuse time; the 3B model gets full module coverage because it is the shipped default and the quality signal matters most here.

## 6. Generate (for Growing Model samples)

```
python -m mlx_lm.generate \
  --model mlx-community/Qwen2.5-3B-Instruct-4bit \
  --adapter-path <run_dir>/adapters \
  --prompt "$(cat prompt.txt)" \
  --max-tokens 200 \
  --temp 0.7 \
  --top-p 0.9 \
  --seed 42
```

The sidecar runs this for each of the three fixed prompts at every `save-every` boundary.

## 7. Fuse

```
python -m mlx_lm.fuse \
  --model mlx-community/Qwen2.5-3B-Instruct-4bit \
  --adapter-path <run_dir>/adapters_dpo \
  --save-path <run_dir>/fused \
  --de-quantize
```

`--de-quantize` is required before GGUF conversion (llama.cpp expects fp16 weights). Skip it if exporting to a non-GGUF target.

## 8. GGUF via llama.cpp

```
git clone --depth=1 https://github.com/ggerganov/llama.cpp vendor/llama.cpp
python vendor/llama.cpp/convert_hf_to_gguf.py \
  <run_dir>/fused \
  --outfile <run_dir>/kiln.gguf \
  --outtype f16
./vendor/llama.cpp/llama-quantize <run_dir>/kiln.gguf <run_dir>/kiln.Q4_K_M.gguf Q4_K_M
```

Quantization target:

- 1.5B → `Q5_K_M` (the smaller model tolerates less quantization damage)
- 3B, 7B → `Q4_K_M`

Pin the llama.cpp commit in `Makefile` so the GGUF reader version matches Ollama's expected version.

## 9. Ollama Modelfile template

Write `<run_dir>/Modelfile`:

```
FROM ./kiln.Q4_K_M.gguf

PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER repeat_penalty 1.1
PARAMETER num_ctx 4096

SYSTEM "You are {USER_NAME}, responding in their voice."

TEMPLATE """{{ if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{ end }}{{ if .Prompt }}<|im_start|>user
{{ .Prompt }}<|im_end|>
{{ end }}<|im_start|>assistant
"""

STOP "<|im_end|>"
STOP "<|im_start|>"
```

Then:

```
ollama create kiln-{username} -f <run_dir>/Modelfile
ollama run kiln-{username}
```

## 10. Known gotchas

- **Tokenizer.** Qwen2.5 uses `<|im_start|>` / `<|im_end|>` — do NOT use OpenAI `<|endoftext|>`. MLX-LM reads the tokenizer from the model repo; do not override.
- **Chat template.** `mlx_lm.lora` applies the model's `chat_template` from `tokenizer_config.json`. If you hand-assemble prompts, you will double-template. Emit `messages`; trust the CLI.
- **OOM on 16 GB Macs.** Symptoms: process killed without error, or `MPS backend out of memory`. Mitigations in order: drop `--max-seq-length` to 1024, drop `--batch-size` to 1, add `--grad-checkpoint`, drop LoRA layers, fall back to the 1.5B base. If all fail, surface the OOM error IPC event and refuse to continue.
- **Loss NaN.** Almost always a broken data row. Validate JSONL upstream: every row has `messages`, every turn has non-empty `content`.
- **Slow first step.** MLX compiles kernels lazily. First 10 iters are always slow; do not show throughput before iter 20.
- **Adapter file naming.** `adapters.safetensors` by default. The Swift side looks for exactly that name — do not rename.

## 11. Checkpointing contract

- Save every 50 iters (`--save-every 50`).
- Kiln retains only the last 3 checkpoints plus best-val. The sidecar emits a `checkpoint` IPC event on every save; the app deletes older ones from disk via its own state machine — not the sidecar's job.

## 12. Eval quick-check after a run

```
python -m mlx_lm.generate \
  --model <run_dir>/fused \
  --prompt "What did you do this morning?" \
  --max-tokens 80 \
  --temp 0.3
```

A sanity prompt in the user's typical voice. If the output is obviously generic, the run failed even if loss looked fine — usually a data issue (generic system prompt, wrong role ordering).

## 13. When to deviate

Never silently. If you are tempted to deviate from any of the above:

1. Add a row to `DECISIONS.md` with the context, options considered, choice, reason.
2. Update this skill file in the same PR.
3. Run the eval matrix before merging.

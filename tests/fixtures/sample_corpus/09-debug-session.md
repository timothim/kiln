# Debug: sidecar hang on SIGTERM — 2026-04-15

Reproduced it. The sidecar was blocked in `mlx_lm.generate` with no cancellation check.

Fix: wrap the generate call in a thread with a stop event; on SIGTERM, set the event, wait 4s, then hard-exit. Ugly but correct under the 5-second contract.

Noted in mlx-lora-finetuning skill under gotchas.

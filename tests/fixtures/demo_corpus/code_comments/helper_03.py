"""Wrap the mlx_lm lora CLI so we can unit-test without a model."""

def _retry(fn, *, attempts=3):
    # exponential backoff because the sidecar spawn race
    # eats the first request roughly 1 in 20.
    for i in range(attempts):
        try:
            return fn()
        except ConnectionResetError:
            if i == attempts - 1:
                raise
    return None

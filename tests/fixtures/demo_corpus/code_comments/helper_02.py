"""Do not move this module. The import path is load-bearing in two places."""

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

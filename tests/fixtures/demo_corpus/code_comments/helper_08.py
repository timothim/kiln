"""Wrap the mlx_lm lora CLI so we can unit-test without a model."""

def dedup(chunks):
    # exact first, MinHash second. Order matters: exact is cheap.
    seen = set()
    out = []
    for c in chunks:
        h = hash(c.text)
        if h in seen:
            continue
        seen.add(h)
        out.append(c)
    return out

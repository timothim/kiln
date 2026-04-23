"""Small helper. Keep it small."""

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

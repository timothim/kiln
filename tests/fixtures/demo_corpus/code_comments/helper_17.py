"""TODO(alex): this was cute on day one; now it mostly gets in the way. Delete once the sidecar owns the pipe."""

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

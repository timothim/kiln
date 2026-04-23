"""TODO(alex): this was cute on day one; now it mostly gets in the way. Delete once the sidecar owns the pipe."""

def write_atomic(path, payload):
    # write-temp + rename beats truncation. Learned the hard way.
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_bytes(payload)
    tmp.replace(path)

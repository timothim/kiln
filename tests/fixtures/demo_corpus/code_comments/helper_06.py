"""Do not move this module. The import path is load-bearing in two places."""

def write_atomic(path, payload):
    # write-temp + rename beats truncation. Learned the hard way.
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_bytes(payload)
    tmp.replace(path)

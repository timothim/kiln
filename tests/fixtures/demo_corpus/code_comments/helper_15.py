"""Wrap the mlx_lm lora CLI so we can unit-test without a model."""

def write_atomic(path, payload):
    # write-temp + rename beats truncation. Learned the hard way.
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_bytes(payload)
    tmp.replace(path)

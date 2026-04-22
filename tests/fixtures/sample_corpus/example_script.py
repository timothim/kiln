"""Tiny sample: walk a directory and compute a SHA-256 over the sorted file list.

Used as a fixture for the code-file parser. The docstring and comments are the
signal we keep; the code body is kept as context but down-weighted.
"""

import hashlib
from pathlib import Path


def directory_fingerprint(root: Path) -> str:
    """Return a stable hash of all regular files under `root`.

    Sorted to keep the output stable across filesystems. Symlinks are skipped
    because following them leaks out of the intended folder.
    """
    h = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        if path.is_file() and not path.is_symlink():
            h.update(str(path.relative_to(root)).encode("utf-8"))
            h.update(b"\0")
    return h.hexdigest()


if __name__ == "__main__":
    import sys

    print(directory_fingerprint(Path(sys.argv[1])))

#!/usr/bin/env python3

import os
import sys
from pathlib import Path


def contains_pattern(path: Path, patterns: list[bytes]) -> bool:
    overlap = max(map(len, patterns), default=1) - 1
    previous = b""
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            data = previous + chunk
            if any(pattern in data for pattern in patterns):
                return True
            previous = data[-overlap:] if overlap else b""
    return False


def main() -> int:
    if len(sys.argv) < 3:
        return 64
    root = Path(sys.argv[1])
    patterns = [value.encode() for value in sys.argv[2:]]
    if root.is_file():
        return 1 if contains_pattern(root, patterns) else 0
    for directory, _, filenames in os.walk(root):
        for filename in filenames:
            path = Path(directory, filename)
            try:
                if contains_pattern(path, patterns):
                    print(path)
                    return 1
            except OSError:
                print(f"Unable to inspect {path}", file=sys.stderr)
                return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

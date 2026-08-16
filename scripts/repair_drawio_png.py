#!/usr/bin/env python3
"""Repair the truncated IEND chunk in a draw.io `-e` PNG export.

draw.io desktop writes the 4-byte IEND length field but omits the chunk type
and its CRC (8 bytes) when embedding diagram XML with `-e`. Lenient decoders
(most browsers) render the file anyway; strict ones reject it outright, which
is a nasty way to discover your architecture diagram is corrupt.

Idempotent: a no-op once the file already ends with a well-formed IEND, so it
is safe to run unconditionally and safe to keep after draw.io fixes this
upstream.

    python scripts/repair_drawio_png.py docs/diagrams/architecture.drawio.png
"""

from __future__ import annotations

import sys
from pathlib import Path

IEND_CHUNK = b"\x00\x00\x00\x00IEND\xaeB\x60\x82"
IEND_TAIL = b"IEND\xaeB\x60\x82"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def repair(path: Path) -> str:
    data = path.read_bytes()

    if not data.startswith(PNG_MAGIC):
        return f"not a PNG, skipped: {path}"
    if data.endswith(IEND_CHUNK):
        return f"already well formed: {path}"

    if data.endswith(b"\x00\x00\x00\x00"):
        path.write_bytes(data + IEND_TAIL)          # length present, tail missing
    else:
        path.write_bytes(data + IEND_CHUNK)         # whole chunk missing
    return f"repaired IEND: {path}"


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    for arg in argv[1:]:
        p = Path(arg)
        if not p.is_file():
            print(f"no such file: {p}", file=sys.stderr)
            return 1
        print(repair(p))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

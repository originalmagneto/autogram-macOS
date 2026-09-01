#!/usr/bin/env python3
"""Generate a synthetic Create ML dataset for smoke testing the pipeline.

Creates A4 pages (1240x1754 px) with random text lines plus stamped-in security
elements (ellipse stamp, squiggle signature, small initial, barcode block), and
writes annotations.json in the exact Create ML format. Use it to validate the
whole toolchain (split -> convert -> Create ML import -> provider mapping)
BEFORE investing hours into real annotation. Not a replacement for real scans.

Usage:
  python3 tools/ml-dataset/make_synth_pages.py --out synth_dataset --pages 40 --seed 7
"""
from __future__ import annotations

import argparse
import json
import math
import random
import shutil
from pathlib import Path

W, H = 1240, 1754  # A4 at 150 dpi


def blank_page() -> list[list[tuple[int, int, int]]]:
    return [[(255, 255, 255)] * W for _ in range(H)]


def draw_text_lines(px, rnd: random.Random) -> None:
    color = (70, 70, 70)
    y = 140
    while y < H - 320:
        x = 110
        while x < W - 110:
            if rnd.random() < 0.82:
                seg = rnd.randint(40, 140)
                for xx in range(x, min(x + seg, W - 110)):
                    px[y][xx] = color
                    if y + 1 < H:
                        px[y + 1][xx] = color
                x += seg + rnd.randint(8, 22)
            else:
                x += rnd.randint(20, 60)
        y += rnd.randint(16, 24)


def draw_ellipse(px, cx: int, cy: int, rx: int, ry: int, color) -> None:
    for y in range(max(0, cy - ry - 2), min(H, cy + ry + 3)):
        for x in range(max(0, cx - rx - 2), min(W, cx + rx + 3)):
            dx = (x - cx) / rx
            dy = (y - cy) / ry
            d = dx * dx + dy * dy
            if 0.72 <= d <= 1.0:
                px[y][x] = color


def draw_squiggle(px, x0: int, y0: int, length: int, amp: int, color) -> None:
    for i in range(length):
        x = x0 + i
        if not (0 <= x < W):
            continue
        y = int(y0 + amp * math.sin(i / 7.0) + 0.5 * amp * math.sin(i / 3.1))
        for dy in (-1, 0, 1):
            yy = y + dy
            if 0 <= yy < H:
                px[yy][x] = color


def draw_barcode(px, x0: int, y0: int, w: int, h: int, color) -> None:
    rnd = random.Random(x0 * 31 + y0)
    x = x0
    while x < min(x0 + w, W - 1):
        bar = rnd.choice((1, 1, 2, 3))
        for dx in range(bar):
            if 0 <= x + dx < W:
                for yy in range(max(0, y0), min(H, y0 + h)):
                    px[yy][x + dx] = color
        x += bar + rnd.choice((1, 2))


def draw_initial(px, x0: int, y0: int, w: int, h: int, color) -> None:
    rnd = random.Random(x0 * 17 + y0)
    x, y = x0, y0
    for _ in range(40):
        nx = x0 + rnd.randint(0, w)
        ny = y0 + rnd.randint(0, h)
        seg = abs(nx - x) or 1
        seg_y = abs(ny - y) or 1
        draw_squiggle(px, min(x, nx), min(y, ny), seg, max(2, seg_y // 6), color)
        x, y = nx, ny


def render_page(px, rnd: random.Random) -> list[dict]:
    """Draw text lines and place elements; return Create ML annotations."""
    draw_text_lines(px, rnd)
    annotations = []

    def emit(label: str, cx: float, cy: float, bw: float, bh: float) -> None:
        annotations.append({
            "label": label,
            "coordinates": {"x": round(cx, 2), "y": round(cy, 2),
                            "width": round(bw, 2), "height": round(bh, 2)},
        })

    # stamp: blue-ish ellipse
    if rnd.random() < 0.8:
        size = rnd.randint(220, 340)
        cx = rnd.uniform(200 + size / 2, W - 160 - size / 2)
        cy = rnd.uniform(140 + size / 2, H - 160 - size / 2)
        rx, ry = size // 2, int(size * 0.46)
        draw_ellipse(px, int(cx), int(cy), rx, ry, (40, 60, 160))
        emit("official_stamp", cx, cy, float(size), float(ry * 2))

    # signature: dark squiggle
    if rnd.random() < 0.8:
        length = rnd.randint(260, 420)
        cx = rnd.uniform(160 + length / 2, W - 160 - length / 2)
        cy = rnd.uniform(280, H - 220)
        draw_squiggle(px, int(cx - length / 2), int(cy), length,
                      rnd.randint(10, 22), (25, 25, 60))
        emit("handwritten_signature", cx, cy, float(length), 60.0)

    # initial: small scribble
    if rnd.random() < 0.55:
        w0 = rnd.randint(70, 110)
        cx = rnd.uniform(140 + w0 / 2, W - 140 - w0 / 2)
        cy = rnd.uniform(240, H - 200)
        draw_initial(px, int(cx - w0 / 2), int(cy - 14), w0, 28, (35, 35, 80))
        emit("initial", cx, cy, float(w0), 34.0)

    # barcode block
    if rnd.random() < 0.4:
        bw, bh = rnd.randint(180, 300), 70
        cx = rnd.uniform(150 + bw / 2, W - 150 - bw / 2)
        cy = rnd.uniform(200, H - 180)
        draw_barcode(px, int(cx - bw / 2), int(cy - bh / 2), bw, bh, (20, 20, 20))
        emit("other_security_element", cx, cy, float(bw), float(bh))

    return annotations


def write_png(path: Path, px: list[list[tuple[int, int, int]]]) -> None:
    """Write a minimal 8-bit RGB PNG (stdlib zlib only)."""
    import struct
    import zlib

    height = len(px)
    width = len(px[0])
    raw = bytearray()
    for row in px:
        raw.append(0)  # filter type 0
        for (r, g, b) in row:
            raw.extend((r, g, b))

    def chunk(tag: bytes, data: bytes) -> bytes:
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit RGB
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b""))
    path.write_bytes(png)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, help="Output dataset folder")
    parser.add_argument("--pages", type=int, default=40)
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()

    out_dir = Path(args.out).expanduser()
    if out_dir.exists():
        shutil.rmtree(out_dir)
    (out_dir / "images").mkdir(parents=True)

    rnd = random.Random(args.seed)
    entries = []
    n_docs = max(2, args.pages // 4)
    for doc in range(n_docs):
        doc_pages = rnd.randint(2, 5)
        for page in range(doc_pages):
            px = blank_page()
            anns = render_page(px, rnd)
            name = f"synthdoc{doc:02d}__page{page:02d}.png"
            write_png(out_dir / "images" / name, px)
            entries.append({"image": name, "annotations": anns})
            print(f"  {name}: {len(anns)} elements")

    (out_dir / "annotations.json").write_text(
        json.dumps(entries, ensure_ascii=False, indent=2), encoding="utf-8")
    n_boxes = sum(len(e["annotations"]) for e in entries)
    print(f"Done: {len(entries)} pages, {n_boxes} boxes -> {out_dir}")


if __name__ == "__main__":
    main()

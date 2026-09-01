#!/usr/bin/env python3
"""Export PDF pages to PNG renders for the Create ML training dataset.

Standard library only (no PyMuPDF required). Requires poppler-utils pdftoppm
on macOS: brew install poppler.

Usage:
    python3 tools/ml-dataset/prepare_dataset.py pdf2png --src scans/ --dst renders/ --width 1240
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

SUPPORTED = {".pdf"}


def check_poppler() -> str:
    pdftoppm = shutil.which("pdftoppm")
    if not pdftoppm:
        sys.exit(
            "pdftoppm not found. Install poppler: macOS 'brew install poppler', "
            "Debian/Ubuntu 'apt install poppler-utils'."
        )
    return pdftoppm


def cmd_pdf2png(args: argparse.Namespace) -> None:
    pdftoppm = check_poppler()
    src_dir = Path(args.src).expanduser()
    dst_dir = Path(args.dst).expanduser()
    if not src_dir.is_dir():
        sys.exit(f"Source directory not found: {src_dir}")
    dst_dir.mkdir(parents=True, exist_ok=True)

    pdfs = sorted(p for p in src_dir.rglob("*") if p.suffix.lower() in SUPPORTED)
    if not pdfs:
        sys.exit(f"No PDFs found under {src_dir}")
    print(f"Found {len(pdfs)} PDFs, rendering at width {args.width}px ...")

    total = 0
    for pdf in pdfs:
        stem = pdf.stem.replace(" ", "_")
        # -singlefile keeps output name as <stem>.png for single page docs.
        # For multi-page docs pdftoppm appends -1, -2, ... so prefix with doc stem.
        cmd = [
            pdftoppm,
            "-png",
            "-scale-to-x", str(args.width),
            "-scale-to-y", "-1",
            "-r", "150",
            str(pdf),
            str(dst_dir / f"{stem}__page"),
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"  FAILED {pdf.name}: {result.stderr.strip()}", file=sys.stderr)
            continue
        produced = sorted(dst_dir.glob(f"{stem}__page*.png"))
        total += len(produced)
        print(f"  {pdf.name}: {len(produced)} pages -> {len(produced)} PNGs")

    print(f"Done. {total} PNGs in {dst_dir}")
    print("Next: annotate with RectLabel (direct Create ML export) or VIA, then convert if needed.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("pdf2png", help="Render all PDFs in a folder to PNG pages")
    p.add_argument("--src", required=True, help="Folder with source PDFs")
    p.add_argument("--dst", required=True, help="Output folder for PNG renders")
    p.add_argument("--width", type=int, default=1240, help="Render width in px (default 1240)")
    p.set_defaults(func=cmd_pdf2png)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

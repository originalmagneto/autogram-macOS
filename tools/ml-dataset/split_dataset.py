#!/usr/bin/env python3
"""Split an annotated Create ML dataset into train/val/test folders.

The split is DOCUMENT-LEVEL: all pages of one document land in the same
partition. Random page-level splits leak near-duplicate pages between train
and test and produce inflated metrics.

Folder layout produced:
  out/
    train/  images + annotations.json
    val/    images + annotations.json
    test/   images + annotations.json

Usage:
  python3 tools/ml-dataset/split_dataset.py --src dataset/ --out splits/ \
      --train 0.7 --val 0.15 --seed 42

Source layout: a folder with PNGs (optionally in subfolders) plus an
annotations.json in Create ML format. Document prefix is the part of the file
name before the "__page" separator (prepare_dataset.py convention); files
without the separator are treated as their own document.
"""
from __future__ import annotations

import argparse
import json
import random
import shutil
import sys
from collections import defaultdict
from pathlib import Path


def doc_prefix(image_name: str) -> str:
    stem = Path(image_name).stem
    return stem.split("__page")[0] if "__page" in stem else stem


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--src", required=True, help="Folder with images + annotations.json")
    parser.add_argument("--out", required=True, help="Output folder for train/val/test")
    parser.add_argument("--train", type=float, default=0.7)
    parser.add_argument("--val", type=float, default=0.15)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    src = Path(args.src).expanduser()
    ann_path = src / "annotations.json"
    if not ann_path.exists():
        sys.exit(f"annotations.json not found in {src}")
    if args.train < 0 or args.val < 0 or args.train + args.val > 1.0 + 1e-9:
        sys.exit("train and val must be non-negative and train + val <= 1.0 (test gets the remainder)")

    entries = json.loads(ann_path.read_text(encoding="utf-8"))

    # Group entries by document, then shuffle documents (deterministic seed).
    by_doc: dict[str, list[dict]] = defaultdict(list)
    for entry in entries:
        by_doc[doc_prefix(entry["image"])].append(entry)

    docs = sorted(by_doc)
    rng = random.Random(args.seed)
    rng.shuffle(docs)

    n = len(docs)
    n_train = round(n * args.train)
    n_val = round(n * args.val)
    # guard: each non-empty split keeps at least one document when possible
    splits = {
        "train": docs[:n_train],
        "val": docs[n_train:n_train + n_val],
        "test": docs[n_train + n_val:],
    }

    out_root = Path(args.out).expanduser()
    if out_root.exists():
        sys.exit(f"Output folder already exists, remove it first: {out_root}")

    summary = []
    for split_name, split_docs in splits.items():
        split_dir = out_root / split_name
        split_dir.mkdir(parents=True, exist_ok=True)
        anns_out = []
        n_boxes = 0
        for doc in split_docs:
            for entry in by_doc[doc]:
                image_name = entry["image"]
                matches = list(src.rglob(image_name))
                if not matches:
                    print(f"  WARN: image not found, skipped: {image_name}", file=sys.stderr)
                    continue
                shutil.copy2(matches[0], split_dir / image_name)
                anns_out.append(entry)
                n_boxes += len(entry.get("annotations", []))
        (split_dir / "annotations.json").write_text(
            json.dumps(anns_out, ensure_ascii=False, indent=2), encoding="utf-8")
        summary.append((split_name, len(split_docs), len(anns_out), n_boxes))

    print(f"Documents total: {n}")
    for split_name, n_docs, n_images, n_boxes in summary:
        print(f"  {split_name:5}: {n_docs:4} docs, {n_images:4} images, {n_boxes:4} boxes")
    print(f"Done: {out_root}")


if __name__ == "__main__":
    main()

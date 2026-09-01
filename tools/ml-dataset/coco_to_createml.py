#!/usr/bin/env python3
"""Convert annotation exports to the Create ML annotations.json format.

Supported inputs:
  - COCO JSON (CVAT, Label Studio, Roboflow export)
  - VIA (VGG Image Annotator) project JSON (via_image_annotator.html)
  - RectLabel Create ML export passes through unchanged (validation only)

Create ML object detection annotation format (one JSON array, coordinates in
pixels; x,y is the CENTER of the box measured from the top left corner):
  [
    {
      "image": "page-0001.png",
      "annotations": [
        {"label": "official_stamp",
         "coordinates": {"x": 1520, "y": 2140, "width": 420, "height": 390}}
      ]
    },
    ...
  ]

Images with zero boxes may be omitted (they act as negatives), but including
them explicitly is recommended; this script includes every image it knows.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import NoReturn

LABEL_ALIASES = {
    # normalize messy label spellings to the four v1 classes
    "stamp": "official_stamp",
    "pečiatka": "official_stamp",
    "peciatka": "official_stamp",
    "signature": "handwritten_signature",
    "podpis": "handwritten_signature",
    "podpis_vlastnorucny": "handwritten_signature",
    "initial": "initial",
    "parafa": "initial",
    "other": "other_security_element",
    "other_security_element": "other_security_element",
    "qr": "other_security_element",
    "notárska pripojka": "other_security_element",
}


def normalize_label(raw: str) -> str:
    key = (raw or "").strip().lower()
    return LABEL_ALIASES.get(key, key)


def die(msg: str) -> NoReturn:
    sys.exit(f"ERROR: {msg}")


def coco_createml(coco: dict, images_dir: Path | None) -> list[dict]:
    images = {img["id"]: img for img in coco.get("images", [])}
    size_by_id = {
        img_id: (img.get("width"), img.get("height")) for img_id, img in images.items()
    }
    boxes: dict[int, list[dict]] = {}
    for ann in coco.get("annotations", []):
        img_id = ann.get("image_id")
        img = images.get(img_id)
        if img is None:
            continue
        cat = next(
            (c for c in coco.get("categories", []) if c.get("id") == ann.get("category_id")),
            None,
        )
        if cat is None:
            continue
        label = normalize_label(str(cat.get("name", "")))
        if not label:
            continue
        x, y, w, h = ann.get("bbox", [0, 0, 0, 0])  # COCO: top-left x,y + w,h
        cx = x + w / 2.0
        cy = y + h / 2.0
        boxes.setdefault(img_id, []).append(
            {"label": label, "coordinates": {"x": round(cx, 2), "y": round(cy, 2),
                                             "width": round(w, 2), "height": round(h, 2)}}
        )

    out: list[dict] = []
    for img_id, img in images.items():
        file_name = img.get("file_name")
        if not file_name:
            continue
        if images_dir is not None and not (images_dir / file_name).exists():
            print(f"  WARN: image file missing, skipping: {file_name}", file=sys.stderr)
            continue
        out.append({"image": file_name, "annotations": boxes.get(img_id, [])})
    return out


def via_createml(via: dict) -> list[dict]:
    meta = via.get("_via_img_metadata", via)
    out: list[dict] = []
    for _, info in meta.items():
        file_name = info.get("filename")
        if not file_name:
            continue
        anns = []
        for region in info.get("regions", []):
            shape = region.get("shape_attributes", {})
            if shape.get("name") != "rect":
                continue
            label = ""
            attrs = region.get("region_attributes", {})
            if isinstance(attrs, dict):
                label = attrs.get("label") or attrs.get("class") or attrs.get("type") or ""
                if isinstance(label, dict):
                    label = next(iter(label.values()), "")
            label = normalize_label(str(label))
            if not label:
                print("  WARN: rect region without label attribute, skipped", file=sys.stderr)
                continue
            x = shape.get("x", 0)
            y = shape.get("y", 0)
            w = shape.get("width", 0)
            h = shape.get("height", 0)
            anns.append(
                {"label": label, "coordinates": {"x": round(x + w / 2.0, 2), "y": round(y + h / 2.0, 2),
                                                 "width": round(w, 2), "height": round(h, 2)}}
            )
        out.append({"image": file_name, "annotations": anns})
    return out


def validate_createml(data: list, images_dir: Path | None) -> list[dict]:
    if not isinstance(data, list):
        die("Create ML annotations.json must be a JSON array")
    fixed: list[dict] = []
    for entry in data:
        if not isinstance(entry, dict) or "image" not in entry:
            die(f"Bad Create ML entry (missing 'image'): {entry!r}")
        file_name = entry["image"]
        if images_dir is not None and not (images_dir / file_name).exists():
            print(f"  WARN: image file missing, skipping: {file_name}", file=sys.stderr)
            continue
        anns = []
        for ann in entry.get("annotations", []):
            c = ann.get("coordinates", {})
            label = normalize_label(str(ann.get("label", "")))
            anns.append({"label": label, "coordinates": {
                "x": float(c.get("x", 0)), "y": float(c.get("y", 0)),
                "width": float(c.get("width", 0)), "height": float(c.get("height", 0))}})
        fixed.append({"image": file_name, "annotations": anns})
    return fixed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True,
                        help="COCO json / VIA project json / Create ML annotations.json")
    parser.add_argument("--format", choices=["coco", "via", "createml"], required=True)
    parser.add_argument("--images-dir", default=None,
                        help="Folder with the images (checks that every annotated image exists)")
    parser.add_argument("--output", required=True, help="Path of the resulting annotations.json")
    args = parser.parse_args()

    src = Path(args.input).expanduser()
    try:
        data = json.loads(src.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        die(f"cannot read {src}: {exc}")

    images_dir = Path(args.images_dir).expanduser() if args.images_dir else None

    if args.format == "coco":
        converted = coco_createml(data, images_dir)
    elif args.format == "via":
        converted = via_createml(data)
    else:
        if not isinstance(data, list):
            die("Create ML annotations.json must be a JSON array")
        converted = validate_createml(data, images_dir)

    out_path = Path(args.output).expanduser()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(converted, ensure_ascii=False, indent=2), encoding="utf-8")

    n_boxes = sum(len(e["annotations"]) for e in converted)
    n_empty = sum(1 for e in converted if not e["annotations"])
    labels = sorted({a["label"] for e in converted for a in e["annotations"]})
    print(f"Wrote {out_path}: {len(converted)} images, {n_boxes} boxes, {n_empty} negatives")
    print(f"Labels: {', '.join(labels) if labels else '(none)'}")
    if labels:
        unknown = [l for l in labels if l not in
                   {"official_stamp", "handwritten_signature", "initial", "other_security_element"}]
        if unknown:
            print(f"WARNING: unknown labels not in v1 class list: {', '.join(unknown)}")


if __name__ == "__main__":
    main()

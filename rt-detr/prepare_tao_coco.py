#!/usr/bin/env python3
"""
Prepare SDG COCO outputs for TAO RT-DETR.

Why this script exists:
- SDG COCO files are emitted with random file names (coco_annotations_<id>.json).
- Some datasets can contain sparse category IDs (for example only id 201/"other"),
  but TAO expects contiguous class IDs with max_id <= num_classes.

This script:
1) Finds one source COCO file per split: train/val/test.
2) Remaps category IDs to contiguous 0..N-1 (what TAO RT-DETR training expects).
3) Writes stable files: <split>/coco_annotations.json.
4) Writes classmap.txt from classes_unique.txt when present, otherwise from COCO.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict, List, Tuple


def _read_lines(path: Path) -> List[str]:
    if not path.exists():
        return []
    return [line.strip() for line in path.read_text().splitlines() if line.strip()]


def _find_source_json(split_dir: Path) -> Path:
    candidates = sorted(
        p
        for p in split_dir.glob("coco_*.json")
        if p.name != "coco_annotations.json"
    )
    if not candidates:
        raise FileNotFoundError(f"No source COCO JSON found in {split_dir}")
    return candidates[0]


def _build_name_list(
    old_ids_sorted: List[int],
    old_cat_by_id: Dict[int, dict],
    class_names_hint: List[str],
) -> List[str]:
    if class_names_hint and len(class_names_hint) == len(old_ids_sorted):
        return class_names_hint
    if class_names_hint and len(class_names_hint) == 1 and len(old_ids_sorted) == 1:
        return class_names_hint
    names = []
    for old_id in old_ids_sorted:
        cat = old_cat_by_id.get(old_id, {})
        names.append(str(cat.get("name", f"class_{old_id}")))
    return names


def _remap_one_json(src: Path, dst: Path, class_names_hint: List[str]) -> Tuple[int, List[str]]:
    data = json.loads(src.read_text())
    categories = data.get("categories", [])
    annotations = data.get("annotations", [])

    old_cat_by_id = {int(c["id"]): c for c in categories}
    old_ids_sorted = sorted(old_cat_by_id.keys())
    if not old_ids_sorted:
        raise ValueError(f"No categories found in {src}")

    new_names = _build_name_list(old_ids_sorted, old_cat_by_id, class_names_hint)
    id_map = {old_id: i for i, old_id in enumerate(old_ids_sorted)}

    new_categories = []
    for i, old_id in enumerate(old_ids_sorted):
        name = new_names[i] if i < len(new_names) else f"class_{i}"
        new_categories.append({"id": i, "name": name})

    new_annotations = []
    for ann in annotations:
        old_id = int(ann.get("category_id", -1))
        if old_id not in id_map:
            continue
        ann2 = dict(ann)
        ann2["category_id"] = id_map[old_id]
        new_annotations.append(ann2)

    data["categories"] = new_categories
    data["annotations"] = new_annotations

    dst.write_text(json.dumps(data, indent=2))
    return len(new_categories), [c["name"] for c in new_categories]


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare TAO-friendly COCO files from SDG output.")
    parser.add_argument(
        "--out-root",
        type=Path,
        default=Path.home() / "synthetic_out",
        help="SDG output root (default: ~/synthetic_out)",
    )
    args = parser.parse_args()

    out_root = args.out_root.expanduser().resolve()
    if not out_root.exists():
        raise FileNotFoundError(f"Output root not found: {out_root}")

    hint_classes = _read_lines(out_root / "classes_unique.txt")
    merged_class_names: List[str] = []
    max_classes = 0

    for split in ("train", "val", "test"):
        split_dir = out_root / split
        if not split_dir.exists():
            raise FileNotFoundError(f"Split directory missing: {split_dir}")
        src = _find_source_json(split_dir)
        dst = split_dir / "coco_annotations.json"
        n_classes, names = _remap_one_json(src, dst, hint_classes)
        max_classes = max(max_classes, n_classes)
        if len(names) > len(merged_class_names):
            merged_class_names = names
        print(f"[{split}] wrote {dst} from {src.name} ({n_classes} classes)")

    if hint_classes and len(hint_classes) >= max_classes:
        class_names = hint_classes[:max_classes]
    elif merged_class_names:
        class_names = merged_class_names
    else:
        class_names = ["custom"]

    classmap_path = out_root / "classmap.txt"
    classmap_path.write_text("\n".join(class_names) + "\n")
    print(f"[classmap] wrote {classmap_path} ({len(class_names)} classes)")


if __name__ == "__main__":
    main()

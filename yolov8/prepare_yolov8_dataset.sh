#!/usr/bin/env bash
# Usage example:
# OUT_ROOT=$HOME/synthetic_out ./prepare_yolov8_dataset.sh
set -euo pipefail
set -o errtrace
IFS=$'\n\t'

# Optional verbose tracing: DEBUG=1 ./prepare_yolov8_dataset.sh
if [[ "${DEBUG:-0}" == "1" ]]; then
  set -x
fi

# Ensure correct conda environment is active for the conversion step
if [[ "${CONDA_DEFAULT_ENV:-}" != "yolov8" ]]; then
  echo "Error: Please activate the 'yolov8' conda environment before running this script." >&2
  echo "Hint: conda activate yolov8" >&2
  echo "Refer to /yolov8/yolov8_setup.md for all requirements" >&2
  exit 1
fi

# Helpful error message on unexpected failures
trap 'rc=$?; echo "Error: script failed at line $LINENO: $BASH_COMMAND (exit=$rc)" >&2; exit $rc' ERR

OUT_ROOT=${OUT_ROOT:-"$HOME/synthetic_out"}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
COCO2YOLO_PY="$SCRIPT_DIR/coco2yolo.py"

echo "prepare_yolov8_dataset.sh: starting"
echo " - OUT_ROOT: $OUT_ROOT"

if [[ ! -d "$OUT_ROOT/train" ]] || [[ ! -d "$OUT_ROOT/val" ]] || [[ ! -d "$OUT_ROOT/test" ]]; then
  echo "Error: Missing train/val/test split directories under $OUT_ROOT" >&2
  echo "Run custom_sdg/generate_sdg_splits.sh first." >&2
  exit 1
fi

mkdir -p "$OUT_ROOT/images/train" "$OUT_ROOT/images/val" "$OUT_ROOT/images/test"
mkdir -p "$OUT_ROOT/labels/train" "$OUT_ROOT/labels/val" "$OUT_ROOT/labels/test"

link_images() {
  local split=$1
  local src="$OUT_ROOT/$split/Replicator"
  local dst="$OUT_ROOT/images/$split"
  [[ -d "$src" ]] || return 0
  echo "Linking images for $split from $src -> $dst"
  find "$src" -type f \( -iname '*.png' -o -iname '*.jpg' \) -print0 | while IFS= read -r -d '' f; do
    ln -sf "$f" "$dst/"
  done
}

link_images train
link_images val
link_images test

if [[ -f "$COCO2YOLO_PY" ]]; then
  echo "Converting COCO -> YOLO at $OUT_ROOT"
  python "$COCO2YOLO_PY" "$OUT_ROOT"
else
  echo "Warning: $COCO2YOLO_PY not found; skipping COCO->YOLO conversion" >&2
fi

read_classes_from_meta() {
  local meta="$OUT_ROOT/classes_unique.txt"
  if [[ -f "$meta" ]]; then
    sed '/^[[:space:]]*$/d' "$meta"
    return 0
  fi
  return 1
}

read_classes_from_coco() {
  local json_file
  json_file=$(find "$OUT_ROOT/train" -maxdepth 1 -type f -name 'coco_*.json' | head -n1 || true)
  if [[ -z "$json_file" ]]; then
    return 1
  fi
  python - "$json_file" <<'PY'
import json
import sys
from pathlib import Path

p = Path(sys.argv[1])
data = json.loads(p.read_text())
cats = sorted(data.get("categories", []), key=lambda c: int(c.get("id", 0)))
for cat in cats:
    name = str(cat.get("name", "")).strip()
    if name:
        print(name)
PY
}

mapfile -t UNIQUE_CLASSES < <(read_classes_from_meta || read_classes_from_coco || printf '%s\n' custom)
if [[ ${#UNIQUE_CLASSES[@]} -eq 0 ]]; then
  mapfile -t UNIQUE_CLASSES < <(read_classes_from_coco || printf '%s\n' custom)
fi

DATA_YAML_OUT="$OUT_ROOT/my_dataset.yaml"
echo "Writing dataset YAML to $DATA_YAML_OUT"
{
  echo "path: $OUT_ROOT"
  echo "train: images/train"
  echo "val: images/val"
  echo "test: images/test"
  echo "names:"
  for c in "${UNIQUE_CLASSES[@]}"; do
    echo "  - $c"
  done
} > "$DATA_YAML_OUT"

echo "Done. YOLO dataset prepared at $OUT_ROOT"

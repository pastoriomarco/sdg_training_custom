#!/usr/bin/env bash
# Usage example:
# OUT_ROOT=$HOME/synthetic_out RUN_NAME=yolov8s_custom ./custom_train_yolov8.sh
set -euo pipefail
IFS=$'\n\t'

# Train YOLOv8 using the dataset produced by custom_datagen_convert_yolov8.sh
# Requires the 'yolov8' conda environment as described in yolov8_setup.md

# Defaults (override via env vars)
OUT_ROOT=${OUT_ROOT:-"$HOME/synthetic_out"}
MODEL=${MODEL:-"yolov8s.pt"}
EPOCHS=${EPOCHS:-100}
BATCH=${BATCH:-16}
IMG_SIZE=${IMG_SIZE:-640}
DEVICE=${DEVICE:-0}
WORKERS=${WORKERS:-8}
PROJECT_NAME=${PROJECT_NAME:-"yolo_runs"}
RUN_NAME=${RUN_NAME:-"yolov8s_custom"}

# Resolve repo-relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
DATA_YAML="$SCRIPT_DIR/my_dataset.yaml"

# 1) Ensure we're in the correct conda environment
if [[ "${CONDA_DEFAULT_ENV:-}" != "yolov8" ]]; then
  echo "Error: Please activate the 'yolov8' conda environment first." >&2
  echo "Hint: conda activate yolov8" >&2
  exit 1
fi

# 2) Ensure 'yolo' CLI is available
if ! command -v yolo >/dev/null 2>&1; then
  echo "Error: 'yolo' CLI not found in PATH. Install ultralytics in the 'yolov8' env." >&2
  exit 1
fi

# 3) Validate dataset location
if [[ ! -d "$OUT_ROOT/images/train" ]] || [[ ! -d "$OUT_ROOT/labels/train" ]]; then
  echo "Warning: Expected dataset folders not found under $OUT_ROOT (images/ and labels/)." >&2
  echo "Run custom_datagen_convert_yolov8.sh first or set OUT_ROOT to your dataset root." >&2
fi

# 4) Build a temporary data YAML if the existing one points elsewhere
TMP_DATA_YAML=""
if [[ -f "$DATA_YAML" ]]; then
  # Extract current path value (if any)
  CURRENT_PATH=$(grep -E '^path:' "$DATA_YAML" | awk '{print $2}' || true)
  if [[ "$CURRENT_PATH" != "$OUT_ROOT" ]]; then
    TMP_DATA_YAML=$(mktemp /tmp/custom_yolo_data.XXXXXX.yaml)
    echo "Creating temp data YAML at $TMP_DATA_YAML with path: $OUT_ROOT"
    {
      echo "path: $OUT_ROOT"
      # Preserve the rest of the YAML minus an existing 'path:' line
      grep -v -E '^path:' "$DATA_YAML"
    } > "$TMP_DATA_YAML"
  fi
else
  echo "Error: $DATA_YAML not found." >&2
  exit 1
fi

USE_DATA_YAML=${TMP_DATA_YAML:-$DATA_YAML}

# 5) Define YOLO output project folder inside OUT_ROOT
PROJECT_DIR="$OUT_ROOT/$PROJECT_NAME"
mkdir -p "$PROJECT_DIR"

echo "Training YOLOv8..."
echo " - data:    $USE_DATA_YAML"
echo " - model:   $MODEL"
echo " - epochs:  $EPOCHS"
echo " - batch:   $BATCH"
echo " - imgsz:   $IMG_SIZE"
echo " - device:  $DEVICE"
echo " - workers: $WORKERS"
echo " - project: $PROJECT_DIR"
echo " - name:    $RUN_NAME"

yolo detect train \
  model="$MODEL" \
  data="$USE_DATA_YAML" \
  imgsz="$IMG_SIZE" \
  epochs="$EPOCHS" \
  batch="$BATCH" \
  device="$DEVICE" \
  workers="$WORKERS" \
  project="$PROJECT_DIR" \
  name="$RUN_NAME"

echo "Training complete. See runs under: $PROJECT_DIR/$RUN_NAME*"

# Cleanup temp file if used
if [[ -n "${TMP_DATA_YAML}" && -f "${TMP_DATA_YAML}" ]]; then
  rm -f "${TMP_DATA_YAML}"
fi

# 6) Export best.pt to ONNX (relative to synthetic_out)
if [[ "${EXPORT_ONNX:-1}" != "0" ]]; then
  WEIGHTS_DIR="$PROJECT_DIR/$RUN_NAME/weights"
  BEST_PT="$WEIGHTS_DIR/best.pt"
  if [[ -f "$BEST_PT" ]]; then
    echo "Exporting ONNX from: ${BEST_PT#$OUT_ROOT/} (relative to $OUT_ROOT)"
    BEST_PT="$BEST_PT" python - <<'PY'
import os
from ultralytics import YOLO

best = os.environ['BEST_PT']
model = YOLO(best)
onnx_path = model.export(format='onnx')  # creates best.onnx in same folder
print(f"ONNX exported to: {onnx_path}")
PY
  else
    echo "Warning: best.pt not found at $BEST_PT; skipping ONNX export" >&2
  fi
fi

#!/usr/bin/env bash
# Usage example (single-class):
# CUSTOM_ASSET_PATHS=/home/tndlux/Downloads/source/your_object.usd WAREHOUSE_ROBOT_CONFIG=./custom_sdg/warehouse_robots.default.yaml ./yolov8/generate_and_prepare_yolov8.sh
set -euo pipefail
set -o errtrace
IFS=$'\n\t'

# Optional verbose tracing: DEBUG=1 ./generate_and_prepare_yolov8.sh
if [[ "${DEBUG:-0}" == "1" ]]; then
  set -x
fi

# Helpful error message on unexpected failures
trap 'rc=$?; echo "Error: script failed at line $LINENO: $BASH_COMMAND (exit=$rc)" >&2; exit $rc' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
GEN_SCRIPT="$REPO_ROOT/custom_sdg/generate_sdg_splits.sh"
PREP_SCRIPT="$SCRIPT_DIR/prepare_yolov8_dataset.sh"

SKIP_YOLO_POST=${SKIP_YOLO_POST:-0}

echo "generate_and_prepare_yolov8.sh: starting"

# Keep legacy behavior: require yolov8 env before any heavy generation
# unless user explicitly asks for COCO-only output.
if [[ "${SKIP_YOLO_POST,,}" != "1" && "${SKIP_YOLO_POST,,}" != "true" ]]; then
  if [[ "${CONDA_DEFAULT_ENV:-}" != "yolov8" ]]; then
    echo "Error: Please activate the 'yolov8' conda environment before running this script." >&2
    echo "Hint: conda activate yolov8" >&2
    echo "Refer to /yolov8/yolov8_setup.md for all requirements" >&2
    echo "If you only need COCO output (e.g., TAO RT-DETR), run with SKIP_YOLO_POST=1." >&2
    exit 1
  fi
else
  echo "SKIP_YOLO_POST enabled: generating COCO splits only (skipping YOLO conversion artifacts)."
fi

if [[ ! -x "$GEN_SCRIPT" ]]; then
  echo "Error: generator script not found or not executable: $GEN_SCRIPT" >&2
  exit 1
fi

bash "$GEN_SCRIPT"

if [[ "${SKIP_YOLO_POST,,}" == "1" || "${SKIP_YOLO_POST,,}" == "true" ]]; then
  echo "SKIP_YOLO_POST enabled: skipping YOLO conversion artifacts."
  echo "Done. COCO split outputs in ${OUT_ROOT:-$HOME/synthetic_out}"
  exit 0
fi

if [[ ! -x "$PREP_SCRIPT" ]]; then
  echo "Error: YOLO prepare script not found or not executable: $PREP_SCRIPT" >&2
  exit 1
fi

bash "$PREP_SCRIPT"

echo "Done. Outputs in ${OUT_ROOT:-$HOME/synthetic_out}"

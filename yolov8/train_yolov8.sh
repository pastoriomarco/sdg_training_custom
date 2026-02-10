#!/usr/bin/env bash
# Usage example:
# OUT_ROOT=$HOME/synthetic_out RUN_NAME=yolov8s_custom ./yolov8/train_yolov8.sh
set -euo pipefail
set -o errtrace
IFS=$'\n\t'

# Optional verbose tracing: DEBUG=1 ./yolov8/train_yolov8.sh
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

# Train YOLOv8 using the dataset produced by generate_and_prepare_yolov8.sh
# Requires the 'yolov8' conda environment as described in yolov8_setup.md

# Defaults (override via env vars)
OUT_ROOT=${OUT_ROOT:-"$HOME/synthetic_out"}
# Optional override of dataset yaml; if not set, auto-use $OUT_ROOT/my_dataset.yaml when present
DATA_YAML_OVERRIDE=${DATA_YAML:-""}
MODEL=${MODEL:-"yolov8s.pt"}
EPOCHS=${EPOCHS:-50}
BATCH=${BATCH:-16}
IMG_SIZE=${IMG_SIZE:-640}
DEVICE=${DEVICE:-0}
WORKERS=${WORKERS:-8}
PROJECT_NAME=${PROJECT_NAME:-"yolo_runs"}
RUN_NAME=${RUN_NAME:-"yolov8s_custom"}

# Resolve repo-relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
DEFAULT_DATA_YAML="$SCRIPT_DIR/my_dataset.yaml"

# Announce start and key params early
echo "train_yolov8.sh: starting"
echo " - OUT_ROOT: ${OUT_ROOT:-}"
echo " - DATA_YAML override: ${DATA_YAML_OVERRIDE:-}"
echo " - MODEL: ${MODEL:-} | EPOCHS: ${EPOCHS:-} | BATCH: ${BATCH:-} | IMG_SIZE: ${IMG_SIZE:-} | DEVICE: ${DEVICE:-} | WORKERS: ${WORKERS:-}"

# 1) Validate required Python packages (env-agnostic). See yolov8_setup.md for installs.
REQ_DOC="$SCRIPT_DIR/yolov8_setup.md"
PY_BIN=${PYTHON_BIN:-python}
if ! command -v "$PY_BIN" >/dev/null 2>&1; then
  if command -v python3 >/dev/null 2>&1; then
    PY_BIN=python3
  else
    echo "Error: Python interpreter not found (looked for 'python' or 'python3'). See $REQ_DOC." >&2
    exit 1
  fi
fi
PYCHK=""
if ! PYCHK=$("$PY_BIN" - <<'PY'
import importlib, sys, json
mods = ['torch','ultralytics','onnx','onnxruntime','cv2','pycocotools','matplotlib','tqdm']
missing=[]; info={}
for m in mods:
    try:
        mod=importlib.import_module(m)
        v=getattr(mod,'__version__', None)
        info[m]=str(v) if v is not None else 'unknown'
    except Exception:
        missing.append(m)
ok = not missing
cuda_info = {}
try:
    import torch
    cuda_info = {
        'cuda_available': bool(torch.cuda.is_available()),
        'cuda_runtime': getattr(torch.version, 'cuda', None),
        'torch_version': getattr(torch, '__version__', 'unknown'),
    }
except Exception:
    pass
print(json.dumps({'ok': ok, 'missing': missing, 'info': info, 'cuda': cuda_info}))
sys.exit(0 if ok else 2)
PY
); then
  # Try to extract missing list from the JSON (best-effort)
  echo "Error: Required Python packages are missing: $(echo "$PYCHK" | sed -n 's/.*\"missing\":\s*\[\([^]]*\)\].*/\1/p')" >&2
  echo "See $REQ_DOC to install the expected versions." >&2
  exit 1
fi



# 2) Resolve YOLO entrypoint from the same Python we validated above.
# This avoids PATH mismatches (e.g., ~/.local/bin/yolo bound to another Python)
# and works with Ultralytics versions that do not expose ultralytics.__main__.
YOLO_CMD=("$PY_BIN" -c "from ultralytics.cfg import entrypoint; entrypoint()")

# 3) Validate dataset location
if [[ ! -d "$OUT_ROOT/images/train" ]] || [[ ! -d "$OUT_ROOT/labels/train" ]]; then
  echo "Warning: Expected dataset folders not found under $OUT_ROOT (images/ and labels/)." >&2
  echo "Run yolov8/prepare_yolov8_dataset.sh first or set OUT_ROOT to your dataset root." >&2
fi

# 4) Choose dataset YAML and normalize its path: prefer override > OUT_ROOT/my_dataset.yaml > default
if [[ -n "$DATA_YAML_OVERRIDE" ]]; then
  USE_DATA_YAML="$DATA_YAML_OVERRIDE"
elif [[ -f "$OUT_ROOT/my_dataset.yaml" ]]; then
  USE_DATA_YAML="$OUT_ROOT/my_dataset.yaml"
else
  USE_DATA_YAML="$DEFAULT_DATA_YAML"
fi

if [[ ! -f "$USE_DATA_YAML" ]]; then
  echo "Error: dataset YAML not found at $USE_DATA_YAML" >&2
  exit 1
fi

# If the chosen YAML doesn't point at OUT_ROOT, make a temp copy with path patched
TMP_DATA_YAML=""
CURRENT_PATH=$(grep -E '^path:' "$USE_DATA_YAML" | awk '{print $2}' || true)
if [[ "$CURRENT_PATH" != "$OUT_ROOT" ]]; then
  TMP_DATA_YAML=$(mktemp /tmp/custom_yolo_data.XXXXXX.yaml) || { echo "Error: failed to create temporary YAML in /tmp" >&2; exit 1; }
  echo "Creating temp data YAML at $TMP_DATA_YAML with path: $OUT_ROOT"
  {
    echo "path: $OUT_ROOT"
    grep -v -E '^path:' "$USE_DATA_YAML"
  } > "$TMP_DATA_YAML"
  USE_DATA_YAML="$TMP_DATA_YAML"
fi

# 4b) Validate classes: if convert script provided meta, enforce counts
CLASSES_META="$OUT_ROOT/classes_unique.txt"
ASSETS_META="$OUT_ROOT/assets_used.txt"
CLASSES_PER_ASSET_META="$OUT_ROOT/classes_per_asset.txt"
if [[ -f "$CLASSES_META" ]]; then
  EXPECTED_N=$(wc -l < "$CLASSES_META" | tr -d ' \t')
  if [[ -f "$ASSETS_META" && -f "$CLASSES_PER_ASSET_META" ]]; then
    NA=$(wc -l < "$ASSETS_META" | tr -d ' \t')
    NC=$(wc -l < "$CLASSES_PER_ASSET_META" | tr -d ' \t')
    if [[ "$NA" != "$NC" ]]; then
      echo "Error: Assets/classes mismatch from conversion meta: assets=$NA, classes=$NC (must be equal)." >&2
      exit 1
    fi
  fi
  # Count names in YAML (list style under 'names:')
  YAML_N=$(awk '
    $1=="names:" {inlist=1; next}
    inlist && $1 ~ /^-$/ {n++; next}
    inlist && $1 ~ /^-/ {n++; next}
    inlist && $1 ~ /^[^#-]/ {inlist=0}
    END{print n+0}
  ' "$USE_DATA_YAML")
  if [[ "$YAML_N" != "$EXPECTED_N" ]]; then
    echo "Error: Class count mismatch. YAML has $YAML_N names, expected $EXPECTED_N (from $CLASSES_META)." >&2
    exit 1
  fi
fi

# 4c) Optional: verify label indices are within range
if [[ "${ENFORCE_LABELS:-1}" != "0" ]]; then
  if [[ -n "${EXPECTED_N:-}" ]]; then
    MAX_ID=-1
    while IFS= read -r -d '' f; do
      # Skip empty files
      if [[ ! -s "$f" ]]; then continue; fi
      m=$(awk '{if(NF>0){cid=$1+0; if(cid>m)m=cid}} END{print (m=="")? -1 : m}' "$f")
      if (( m > MAX_ID )); then MAX_ID=$m; fi
    done < <(find "$OUT_ROOT/labels" -type f -name '*.txt' -print0 2>/dev/null)
    if (( MAX_ID >= EXPECTED_N )); then
      echo "Error: Found label class id $MAX_ID but expected < $EXPECTED_N based on classes meta." >&2
      exit 1
    fi
  fi
fi

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

"${YOLO_CMD[@]}" detect train \
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

#!/usr/bin/env bash
# Usage example (single-class):
# CUSTOM_ASSET_PATHS=/home/tndlux/Downloads/source/your_object.usd WAREHOUSE_ROBOT_CONFIG=./warehouse_robots.default.yaml ./generate_sdg_splits.sh
set -euo pipefail
set -o errtrace
IFS=$'\n\t'

# Optional verbose tracing: DEBUG=1 ./generate_sdg_splits.sh
if [[ "${DEBUG:-0}" == "1" ]]; then
  set -x
fi

# Helpful error message on unexpected failures
trap 'rc=$?; echo "Error: script failed at line $LINENO: $BASH_COMMAND (exit=$rc)" >&2; exit $rc' ERR

echo "generate_sdg_splits.sh: starting"

# This script launches dataset generation for train/val/test splits
# and stores COCO outputs under OUT_ROOT/<split>/.

# Allow overriding via env vars
SIM_PY=${SIM_PY:-"$HOME/isaacsim/_build/linux-x86_64/release/python.sh"}
WIDTH=${WIDTH:-640}
HEIGHT=${HEIGHT:-640}
HEADLESS=${HEADLESS:-True}
FRAMES_TRAIN=${FRAMES_TRAIN:-2500}
FRAMES_VAL=${FRAMES_VAL:-500}
FRAMES_TEST=${FRAMES_TEST:-500}
OUT_ROOT=${OUT_ROOT:-"$HOME/synthetic_out"}
# Accepting Single-value inputs, and also multi-asset/multi-class (colon-separated lists).
CUSTOM_ASSET_PATHS=${CUSTOM_ASSET_PATHS:-"$HOME/Downloads/source/TDNS06.usd"}
CUSTOM_OBJECT_CLASSES=${CUSTOM_OBJECT_CLASSES:-"custom"}
CUSTOM_PRIM_PREFIX=${CUSTOM_PRIM_PREFIX:-"custom"}
FALLBACK_COUNT=${FALLBACK_COUNT:-2}
CUSTOM_MATERIALS_DIRS=${CUSTOM_MATERIALS_DIRS:-"$HOME/Downloads/source/Materials"}
DISTRACTORS=${DISTRACTORS:-"warehouse"}
DISTRACTORS_TRAIN=${DISTRACTORS_TRAIN:-"$DISTRACTORS"}
DISTRACTORS_VAL=${DISTRACTORS_VAL:-"$DISTRACTORS"}
DISTRACTORS_TEST=${DISTRACTORS_TEST:-"$DISTRACTORS"}
WAREHOUSE_ROBOT_PATHS=${WAREHOUSE_ROBOT_PATHS:-""}
WAREHOUSE_ROBOT_CONFIG=${WAREHOUSE_ROBOT_CONFIG:-""}
WAREHOUSE_ROBOT_REPEAT=${WAREHOUSE_ROBOT_REPEAT:-""}
OBJECT_SCALE=${OBJECT_SCALE:-""}
CAM_POS=${CAM_POS:-""}
OBJ_POS=${OBJ_POS:-""}
OBJ_ROT=${OBJ_ROT:-""}
DIST_POS=${DIST_POS:-""}
DIST_ROT=${DIST_ROT:-""}
DIST_SCALE=${DIST_SCALE:-""}

# Resolve paths relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
GEN_PY="$SCRIPT_DIR/standalone_custom_sdg.py"
if [[ -z "$WAREHOUSE_ROBOT_CONFIG" ]]; then
  default_robots_cfg="$SCRIPT_DIR/warehouse_robots.default.yaml"
  [[ -f "$default_robots_cfg" ]] && WAREHOUSE_ROBOT_CONFIG="$default_robots_cfg"
fi

if [[ ! -x "$SIM_PY" ]]; then
  echo "Isaac Sim python not found or not executable at: $SIM_PY" >&2
  echo "Set SIM_PY=/path/to/isaacsim/_build/.../python.sh" >&2
  exit 1
fi

if [[ ! -f "$GEN_PY" ]]; then
  echo "Generator script not found: $GEN_PY" >&2
  exit 1
fi

echo "Output root: $OUT_ROOT"

# Collect assets and classes
ASSETS=()
CLASSES=()

if [[ -n "$CUSTOM_ASSET_PATHS" ]]; then
  IFS=':' read -r -a ASSETS <<< "$CUSTOM_ASSET_PATHS"
else
  echo "Error: CUSTOM_ASSET_PATHS is required (colon-separated; single value allowed)." >&2
  exit 1
fi

if [[ -n "$CUSTOM_OBJECT_CLASSES" ]]; then
  IFS=':' read -r -a CLASSES <<< "$CUSTOM_OBJECT_CLASSES"
else
  # Default single-class for single-asset only
  if [[ ${#ASSETS[@]} -eq 1 ]]; then
    CLASSES=("custom")
  else
    echo "Error: Multiple assets provided but CUSTOM_OBJECT_CLASSES not set." >&2
    echo "Provide colon-separated classes, one per asset (order must match)." >&2
    exit 1
  fi
fi

# Enforce equal counts when multi-asset
if [[ ${#ASSETS[@]} -ne ${#CLASSES[@]} ]]; then
  echo "Error: Mismatch between assets (${#ASSETS[@]}) and classes (${#CLASSES[@]})." >&2
  echo "Provide exactly one class per asset using CUSTOM_OBJECT_CLASSES (colon-separated)." >&2
  exit 1
fi

# Build ordered-unique classes (stable id mapping across splits)
UNIQUE_CLASSES=()
declare -A _seen
for c in "${CLASSES[@]}"; do
  if [[ -z "${_seen[$c]:-}" ]]; then
    UNIQUE_CLASSES+=("$c")
    _seen[$c]=1
  fi
done

# Handle existing output root: prompt to delete for a clean reset
if [[ -d "$OUT_ROOT" ]]; then
  if [[ "${AUTO_CLEAN:-}" == "1" || "${AUTO_CLEAN:-}" == "true" ]]; then
    echo "AUTO_CLEAN enabled. Removing existing $OUT_ROOT ..."
    rm -rf "$OUT_ROOT"
  else
    echo "Output folder already exists: $OUT_ROOT"
    if [[ -t 0 ]]; then
      resp=""
      # Read from tty to support piping this script
      read -r -p "Delete it and ALL contents? [y/N] " resp </dev/tty || true
      case "$resp" in
        y|Y|yes|YES)
          echo "Deleting $OUT_ROOT ..."
          rm -rf "$OUT_ROOT"
          ;;
        *)
          echo "Keeping existing $OUT_ROOT (data may be appended)."
          ;;
      esac
    else
      echo "Non-interactive shell detected; not deleting. Set AUTO_CLEAN=1 to force deletion."
    fi
  fi
fi

mkdir -p "$OUT_ROOT"

run_split() {
  local split=$1
  local frames=$2
  local dist=${3:-"$DISTRACTORS"}
  local material_args=()
  local scale_args=()
  local pos_rot_args=()
  local warehouse_robot_args=()
  local asset_args=(--asset_paths)
  local class_args=(--object_classes)
  if [[ -n "$CUSTOM_MATERIALS_DIRS" ]]; then
    IFS=':' read -r -a mats <<< "$CUSTOM_MATERIALS_DIRS"
    for dir in "${mats[@]}"; do
      [[ -n "$dir" ]] && material_args+=(--materials_dir "$dir")
    done
  fi
  if [[ -n "$OBJECT_SCALE" ]]; then
    scale_args+=(--object_scale "$OBJECT_SCALE")
  fi
  # Pos/rot/scale ranges
  [[ -n "$CAM_POS"   ]] && pos_rot_args+=(--cam_pos  "$CAM_POS")
  [[ -n "$OBJ_POS"   ]] && pos_rot_args+=(--obj_pos  "$OBJ_POS")
  [[ -n "$OBJ_ROT"   ]] && pos_rot_args+=(--obj_rot  "$OBJ_ROT")
  [[ -n "$DIST_POS"  ]] && pos_rot_args+=(--dist_pos "$DIST_POS")
  [[ -n "$DIST_ROT"  ]] && pos_rot_args+=(--dist_rot "$DIST_ROT")
  [[ -n "$DIST_SCALE" ]] && pos_rot_args+=(--dist_scale "$DIST_SCALE")
  [[ -n "$WAREHOUSE_ROBOT_CONFIG" ]] && warehouse_robot_args+=(--warehouse_robot_config "$WAREHOUSE_ROBOT_CONFIG")
  [[ -n "$WAREHOUSE_ROBOT_REPEAT" ]] && warehouse_robot_args+=(--warehouse_robot_repeat "$WAREHOUSE_ROBOT_REPEAT")
  if [[ -n "$WAREHOUSE_ROBOT_PATHS" ]]; then
    IFS=':' read -r -a robot_paths <<< "$WAREHOUSE_ROBOT_PATHS"
    if [[ ${#robot_paths[@]} -gt 0 ]]; then
      warehouse_robot_args+=(--warehouse_robot_paths "${robot_paths[@]}")
    fi
  fi
  for a in "${ASSETS[@]}"; do asset_args+=("$a"); done
  for c in "${CLASSES[@]}"; do class_args+=("$c"); done
  echo "Generating $split with $frames frames..."
  env -u CONDA_DEFAULT_ENV -u CONDA_PREFIX -u CONDA_PYTHON_EXE -u CONDA_SHLVL -u _CE_CONDA -u _CE_M \
    bash "$SIM_PY" "$GEN_PY" \
    --headless "$HEADLESS" \
    --num_frames "$frames" \
    --width "$WIDTH" --height "$HEIGHT" \
    --distractors "$dist" \
    "${warehouse_robot_args[@]}" \
    --data_dir "$OUT_ROOT/$split" \
    "${asset_args[@]}" \
    "${class_args[@]}" \
    --prim_prefix "$CUSTOM_PRIM_PREFIX" \
    --fallback_count "$FALLBACK_COUNT" \
    "${material_args[@]}" \
    "${scale_args[@]}" \
    "${pos_rot_args[@]}"
}

run_split train "$FRAMES_TRAIN" "$DISTRACTORS_TRAIN"
run_split val   "$FRAMES_VAL"   "$DISTRACTORS_VAL"
run_split test  "$FRAMES_TEST"  "$DISTRACTORS_TEST"

# Persist meta for training-time validation
printf "%s\n" "${ASSETS[@]}" > "$OUT_ROOT/assets_used.txt"
printf "%s\n" "${CLASSES[@]}" > "$OUT_ROOT/classes_per_asset.txt"
printf "%s\n" "${UNIQUE_CLASSES[@]}" > "$OUT_ROOT/classes_unique.txt"

echo "Done. COCO split outputs in $OUT_ROOT"

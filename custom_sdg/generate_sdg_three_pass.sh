#!/usr/bin/env bash
# Usage example (single-class):
# CUSTOM_ASSET_PATHS=/home/tndlux/Downloads/source/your_object.usd WAREHOUSE_ROBOT_CONFIG=/isaac-sim/custom_sdg/warehouse_robots.default.yaml ./generate_sdg_three_pass.sh
set -euo pipefail

# Path where Isaac Sim is installed (contains python.sh)
ISAAC_SIM_PATH=${ISAAC_SIM_PATH:-'/isaac-sim'}
SCRIPT_PATH="${ISAAC_SIM_PATH}/custom_sdg/standalone_custom_sdg.py"

# Multi-asset multi-class support (colon-separated). Single-value works too.
CUSTOM_ASSET_PATHS=${CUSTOM_ASSET_PATHS:-"$HOME/Downloads/source/TDNS06.usd"}
CUSTOM_OBJECT_CLASSES=${CUSTOM_OBJECT_CLASSES:-"custom"}
CUSTOM_PRIM_PREFIX=${CUSTOM_PRIM_PREFIX:-"custom"}
FALLBACK_COUNT=${FALLBACK_COUNT:-2}
DATA_ROOT=${DATA_ROOT:-"${ISAAC_SIM_PATH}/custom_sdg/custom_data"}
CAM_POS=${CAM_POS:-""}
OBJ_POS=${OBJ_POS:-""}
OBJ_ROT=${OBJ_ROT:-""}
DIST_POS=${DIST_POS:-""}
DIST_ROT=${DIST_ROT:-""}
DIST_SCALE=${DIST_SCALE:-""}
OBJECT_SCALE=${OBJECT_SCALE:-""}
WAREHOUSE_ROBOT_PATHS=${WAREHOUSE_ROBOT_PATHS:-""}
WAREHOUSE_ROBOT_CONFIG=${WAREHOUSE_ROBOT_CONFIG:-""}
WAREHOUSE_ROBOT_REPEAT=${WAREHOUSE_ROBOT_REPEAT:-""}
if [[ -z "$WAREHOUSE_ROBOT_CONFIG" ]]; then
  default_robots_cfg="${ISAAC_SIM_PATH}/custom_sdg/warehouse_robots.default.yaml"
  [[ -f "$default_robots_cfg" ]] && WAREHOUSE_ROBOT_CONFIG="$default_robots_cfg"
fi

mkdir -p "${DATA_ROOT}"

echo "Starting three-pass SDG generation"
echo " - Isaac Sim path: ${ISAAC_SIM_PATH}"

# Collect assets/classes
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
  if [[ ${#ASSETS[@]} -eq 1 ]]; then
    CLASSES=("custom")
  else
    echo "Error: Multiple assets provided but CUSTOM_OBJECT_CLASSES not set." >&2
    exit 1
  fi
fi

if [[ ${#ASSETS[@]} -ne ${#CLASSES[@]} ]]; then
  echo "Error: Mismatch between assets (${#ASSETS[@]}) and classes (${#CLASSES[@]})." >&2
  exit 1
fi

echo " - Asset file(s):  ${ASSETS[*]}"
echo " - Object class(es): ${CLASSES[*]}"

echo "Changing directory to Isaac Sim..."
cd "${ISAAC_SIM_PATH}"
pwd

run_generation() {
  local name=$1
  local frames=$2
  local distractors=$3
  local asset_args=(--asset_paths)
  local class_args=(--object_classes)
  local pos_rot_args=()
  local scale_args=()
  local warehouse_robot_args=()
  for a in "${ASSETS[@]}"; do asset_args+=("$a"); done
  for c in "${CLASSES[@]}"; do class_args+=("$c"); done

  # Build optional args
  [[ -n "$CAM_POS"    ]] && pos_rot_args+=(--cam_pos  "$CAM_POS")
  [[ -n "$OBJ_POS"    ]] && pos_rot_args+=(--obj_pos  "$OBJ_POS")
  [[ -n "$OBJ_ROT"    ]] && pos_rot_args+=(--obj_rot  "$OBJ_ROT")
  [[ -n "$DIST_POS"   ]] && pos_rot_args+=(--dist_pos "$DIST_POS")
  [[ -n "$DIST_ROT"   ]] && pos_rot_args+=(--dist_rot "$DIST_ROT")
  [[ -n "$DIST_SCALE" ]] && pos_rot_args+=(--dist_scale "$DIST_SCALE")
  [[ -n "$OBJECT_SCALE" ]] && scale_args+=(--object_scale "$OBJECT_SCALE")
  [[ -n "$WAREHOUSE_ROBOT_CONFIG" ]] && warehouse_robot_args+=(--warehouse_robot_config "$WAREHOUSE_ROBOT_CONFIG")
  [[ -n "$WAREHOUSE_ROBOT_REPEAT" ]] && warehouse_robot_args+=(--warehouse_robot_repeat "$WAREHOUSE_ROBOT_REPEAT")
  if [[ -n "$WAREHOUSE_ROBOT_PATHS" ]]; then
    IFS=':' read -r -a robot_paths <<< "$WAREHOUSE_ROBOT_PATHS"
    if [[ ${#robot_paths[@]} -gt 0 ]]; then
      warehouse_robot_args+=(--warehouse_robot_paths "${robot_paths[@]}")
    fi
  fi

  echo "Launching generation for ${name} (${frames} frames, distractors=${distractors})"
  env -u CONDA_DEFAULT_ENV -u CONDA_PREFIX -u CONDA_PYTHON_EXE -u CONDA_SHLVL -u _CE_CONDA -u _CE_M \
    ./python.sh "${SCRIPT_PATH}" \
    --headless True \
    --height 544 \
    --width 960 \
    --num_frames "${frames}" \
    --distractors "${distractors}" \
    "${warehouse_robot_args[@]}" \
    --data_dir "${DATA_ROOT}/${name}" \
    "${asset_args[@]}" \
    "${class_args[@]}" \
    --prim_prefix "${CUSTOM_PRIM_PREFIX}" \
    --fallback_count "${FALLBACK_COUNT}" \
    "${scale_args[@]}" \
    "${pos_rot_args[@]}"
}

run_generation "distractors_warehouse" 2000 "warehouse"
run_generation "distractors_additional" 2000 "additional"
run_generation "no_distractors" 1000 "None"

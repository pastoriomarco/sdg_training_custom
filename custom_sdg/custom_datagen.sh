#!/bin/bash
# Usage example (single-class):
# CUSTOM_ASSET_PATH=/home/tndlux/Downloads/source/your_object.usd ./custom_datagen.sh
set -euo pipefail

# Path where Isaac Sim is installed (contains python.sh)
ISAAC_SIM_PATH=${ISAAC_SIM_PATH:-'/isaac-sim'}
SCRIPT_PATH="${ISAAC_SIM_PATH}/custom_sdg/standalone_custom_sdg.py"

CUSTOM_ASSET_PATH=${CUSTOM_ASSET_PATH:-"$HOME/Downloads/source/your_object.usd"}
CUSTOM_OBJECT_CLASS=${CUSTOM_OBJECT_CLASS:-"custom"}
CUSTOM_PRIM_PREFIX=${CUSTOM_PRIM_PREFIX:-"custom"}
FALLBACK_COUNT=${FALLBACK_COUNT:-2}
DATA_ROOT=${DATA_ROOT:-"${ISAAC_SIM_PATH}/custom_sdg/custom_data"}

mkdir -p "${DATA_ROOT}"

echo "Starting data generation"
echo " - Isaac Sim path: ${ISAAC_SIM_PATH}"
echo " - Asset file:     ${CUSTOM_ASSET_PATH}"
echo " - Object class:   ${CUSTOM_OBJECT_CLASS}"

echo "Changing directory to Isaac Sim..."
cd "${ISAAC_SIM_PATH}"
pwd

run_generation() {
  local name=$1
  local frames=$2
  local distractors=$3

  echo "Launching generation for ${name} (${frames} frames, distractors=${distractors})"
  ./python.sh "${SCRIPT_PATH}" \
    --headless True \
    --height 544 \
    --width 960 \
    --num_frames "${frames}" \
    --distractors "${distractors}" \
    --data_dir "${DATA_ROOT}/${name}" \
    --asset_paths "${CUSTOM_ASSET_PATH}" \
    --object_class "${CUSTOM_OBJECT_CLASS}" \
    --prim_prefix "${CUSTOM_PRIM_PREFIX}" \
    --fallback_count "${FALLBACK_COUNT}"
}

run_generation "distractors_warehouse" 2000 "warehouse"
run_generation "distractors_additional" 2000 "additional"
run_generation "no_distractors" 1000 "None"

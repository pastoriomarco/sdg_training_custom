#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
TARGET="$SCRIPT_DIR/generate_sdg_three_pass.sh"

if [[ ! -x "$TARGET" ]]; then
  echo "Error: target script not found or not executable: $TARGET" >&2
  exit 1
fi

echo "custom_datagen.sh is deprecated; forwarding to custom_sdg/generate_sdg_three_pass.sh"
exec bash "$TARGET" "$@"

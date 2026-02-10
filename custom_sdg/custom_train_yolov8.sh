#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
TARGET="$REPO_ROOT/yolov8/train_yolov8.sh"

if [[ ! -x "$TARGET" ]]; then
  echo "Error: target script not found or not executable: $TARGET" >&2
  exit 1
fi

echo "custom_train_yolov8.sh is deprecated; forwarding to yolov8/train_yolov8.sh"
exec bash "$TARGET" "$@"

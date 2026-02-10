yolov8
======

YOLOv8-specific workflow for this repository.
Use this folder after generic SDG COCO data has been generated.

Prerequisites
-------------
Complete generic SDG generation first:
- Follow `../README.md`.
- Run `custom_sdg/generate_sdg_splits.sh` to produce `${OUT_ROOT}/train|val|test` COCO outputs.

Set up YOLO environment:
- Follow `yolov8_setup.md`.
- Activate env before conversion/training:
```bash
conda activate yolov8
```

Recommended paths
-----------------
```bash
export SDG_WS=/home/tndlux/workspaces/sdg
export OUT_ROOT=/home/tndlux/synthetic_out
```

1) Prepare YOLO dataset from SDG COCO outputs
---------------------------------------------
```bash
OUT_ROOT="${OUT_ROOT}" \
"${SDG_WS}/src/sdg_training_custom/yolov8/prepare_yolov8_dataset.sh"
```

This creates/updates:
- `${OUT_ROOT}/images/train`, `${OUT_ROOT}/images/val`, `${OUT_ROOT}/images/test`
- `${OUT_ROOT}/labels/train`, `${OUT_ROOT}/labels/val`, `${OUT_ROOT}/labels/test`
- `${OUT_ROOT}/my_dataset.yaml`

2) Train YOLOv8
---------------
```bash
OUT_ROOT="${OUT_ROOT}" \
RUN_NAME=yolov8s_custom \
"${SDG_WS}/src/sdg_training_custom/yolov8/train_yolov8.sh"
```

3) Optional one-shot command (generate + prepare)
--------------------------------------------------
If you want the old one-command behavior, use:
```bash
cd "${SDG_WS}" && \
  CUSTOM_ASSET_PATHS=/path/to/object.usd \
  CUSTOM_MATERIALS_DIRS=/path/to/materials \
  WAREHOUSE_ROBOT_CONFIG=${SDG_WS}/src/sdg_training_custom/custom_sdg/warehouse_robots.default.yaml \
  ${SDG_WS}/src/sdg_training_custom/yolov8/generate_and_prepare_yolov8.sh
```

- Set `SKIP_YOLO_POST=1` to generate only COCO outputs (skip YOLO conversion).

Common Parameters
-----------------
`prepare_yolov8_dataset.sh`:
- `OUT_ROOT` dataset root (default: `~/synthetic_out`)
- `DEBUG`

`train_yolov8.sh`:
- `OUT_ROOT`, `DATA_YAML`
- `MODEL` (default `yolov8s.pt`)
- `EPOCHS` (default `50`)
- `BATCH` (default `16`)
- `IMG_SIZE` (default `640`)
- `DEVICE` (default `0`)
- `WORKERS` (default `8`)
- `PROJECT_NAME` (default `yolo_runs`)
- `RUN_NAME` (default `yolov8s_custom`)
- `PYTHON_BIN`, `ENFORCE_LABELS`, `EXPORT_ONNX`, `DEBUG`

Outputs
-------
Training results are written under:
- `${OUT_ROOT}/${PROJECT_NAME}/${RUN_NAME}`

Default example:
- `${OUT_ROOT}/yolo_runs/yolov8s_custom`

Legacy Compatibility Commands
-----------------------------
These still work and forward to the new commands:
- `custom_sdg/custom_datagen_convert_yolov8.sh` -> `yolov8/generate_and_prepare_yolov8.sh`
- `custom_sdg/custom_train_yolov8.sh` -> `yolov8/train_yolov8.sh`

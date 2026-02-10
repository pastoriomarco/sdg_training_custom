sdg_training_custom
===================

Pipeline to generate synthetic object-detection data with NVIDIA Isaac Sim.
The main workflow in this README is model-agnostic and produces COCO split outputs.
Model-specific conversion/training/export steps live in dedicated folders.

Repository Layout
-----------------
- `custom_sdg/` — generic SDG generation tools and robot distractor configs.
- `yolov8/` — YOLOv8-specific conversion, training, and setup docs.
- `rt-detr/` — TAO RT-DETR-specific preparation, training, and export docs.

Model-Specific Workflows
------------------------
After generating SDG data, continue with one model README:
- YOLOv8: `yolov8/README.md`
- RT-DETR (TAO): `rt-detr/README.md`

Requirements (Generic)
----------------------
- Isaac Sim 5.0 with Replicator.
- Access to Isaac assets server (Nucleus) for environments.
- NVIDIA GPU + drivers suitable for Isaac Sim.

Quick Start (Generic SDG)
-------------------------
1. Create workspace and clone:
```bash
export SDG_WS=~/workspaces/sdg
mkdir -p "${SDG_WS}/src"
cd "${SDG_WS}/src"
git clone https://github.com/pastoriomarco/sdg_training_custom.git
```

2. Run SDG split generation (`train` / `val` / `test`) to COCO outputs:
```bash
cd "${SDG_WS}" && \
  CUSTOM_ASSET_PATHS=/EDIT/THIS/path/to/your/object.usd \
  CUSTOM_MATERIALS_DIRS=/EDIT/THIS/path/to/materials_dir/ \
  WAREHOUSE_ROBOT_CONFIG=${SDG_WS}/src/sdg_training_custom/custom_sdg/warehouse_robots.default.yaml \
  ${SDG_WS}/src/sdg_training_custom/custom_sdg/generate_sdg_splits.sh
```

Example using `isaac_sim_custom_examples`:
```bash
cd "${SDG_WS}" && \
  CUSTOM_ASSET_PATHS=${SDG_WS}/src/isaac_sim_custom_examples/trocar_short.usdz \
  CUSTOM_MATERIALS_DIRS=${SDG_WS}/src/isaac_sim_custom_examples/Materials/ \
  WAREHOUSE_ROBOT_CONFIG=${SDG_WS}/src/sdg_training_custom/custom_sdg/warehouse_robots.expanded.yaml \
  OBJECT_SCALE=0.001 \
  ${SDG_WS}/src/sdg_training_custom/custom_sdg/generate_sdg_splits.sh
```

3. Continue with model-specific steps:
- `yolov8/README.md` for YOLOv8 conversion/training/export.
- `rt-detr/README.md` for TAO RT-DETR preparation/training/export.

Generated Output Structure
--------------------------
Default output root is `~/synthetic_out` (override with `OUT_ROOT`).

Expected artifacts:
- `${OUT_ROOT}/train/Replicator`, `${OUT_ROOT}/val/Replicator`, `${OUT_ROOT}/test/Replicator`
- one `coco_*.json` per split directory
- `${OUT_ROOT}/assets_used.txt`
- `${OUT_ROOT}/classes_per_asset.txt`
- `${OUT_ROOT}/classes_unique.txt`

`classes_unique.txt` preserves class order used for stable class-id mapping.

Generic Scripts
---------------
- `custom_sdg/generate_sdg_splits.sh`
  - Main model-agnostic generator for `train/val/test` COCO splits.
- `custom_sdg/generate_sdg_three_pass.sh`
  - Legacy-style inside-Isaac-Sim 3-pass flow (`warehouse`, `additional`, `None`).
- `custom_sdg/standalone_custom_sdg.py`
  - Direct Python entry point (advanced/custom use).

Backward-compatible aliases:
- `custom_sdg/custom_datagen.sh` forwards to `custom_sdg/generate_sdg_three_pass.sh`.
- Model-specific legacy aliases are documented in each model folder README.

Custom Objects
--------------
`generate_sdg_splits.sh` supports one or multiple assets via colon-separated env vars.

Examples:
- Single asset/class:
```bash
CUSTOM_ASSET_PATHS=/a.usd \
CUSTOM_OBJECT_CLASSES=custom \
WAREHOUSE_ROBOT_CONFIG=./custom_sdg/warehouse_robots.default.yaml \
./custom_sdg/generate_sdg_splits.sh
```

- Multi asset/class (strict 1:1 mapping):
```bash
CUSTOM_ASSET_PATHS=/a.usd:/b.usd \
CUSTOM_OBJECT_CLASSES=cup:bottle \
WAREHOUSE_ROBOT_CONFIG=./custom_sdg/warehouse_robots.default.yaml \
./custom_sdg/generate_sdg_splits.sh
```

Rules:
- Multi-asset requires equal number of classes.
- The order defines class ids and is preserved across splits.

Materials
---------
Materials can come from:
- local USD material directories via `CUSTOM_MATERIALS_DIRS` (colon-separated),
- online MDL material URLs used by the generator when reachable.

Example:
```bash
CUSTOM_MATERIALS_DIRS=/dir/A:/dir/B \
WAREHOUSE_ROBOT_CONFIG=./custom_sdg/warehouse_robots.default.yaml \
./custom_sdg/generate_sdg_splits.sh
```

Generic Parameter Reference
---------------------------
`custom_sdg/generate_sdg_splits.sh` env vars:
- `SIM_PY` Isaac Sim `python.sh` path.
- `OUT_ROOT` output root.
- `WIDTH`, `HEIGHT`, `HEADLESS`.
- `FRAMES_TRAIN`, `FRAMES_VAL`, `FRAMES_TEST`.
- `CUSTOM_ASSET_PATHS`, `CUSTOM_OBJECT_CLASSES`, `CUSTOM_PRIM_PREFIX`, `FALLBACK_COUNT`.
- `CUSTOM_MATERIALS_DIRS`.
- `DISTRACTORS`, `DISTRACTORS_TRAIN`, `DISTRACTORS_VAL`, `DISTRACTORS_TEST`.
- `WAREHOUSE_ROBOT_CONFIG`, `WAREHOUSE_ROBOT_PATHS`, `WAREHOUSE_ROBOT_REPEAT`.
- `OBJECT_SCALE`, `CAM_POS`, `OBJ_POS`, `OBJ_ROT`, `DIST_POS`, `DIST_ROT`, `DIST_SCALE`.
- `AUTO_CLEAN`, `DEBUG`.

`custom_sdg/generate_sdg_three_pass.sh` env vars:
- `ISAAC_SIM_PATH`, `DATA_ROOT`.
- `CUSTOM_ASSET_PATHS`, `CUSTOM_OBJECT_CLASSES`, `CUSTOM_PRIM_PREFIX`, `FALLBACK_COUNT`.
- `WAREHOUSE_ROBOT_CONFIG`, `WAREHOUSE_ROBOT_PATHS`, `WAREHOUSE_ROBOT_REPEAT`.
- `OBJECT_SCALE`, `CAM_POS`, `OBJ_POS`, `OBJ_ROT`, `DIST_POS`, `DIST_ROT`, `DIST_SCALE`.

`custom_sdg/standalone_custom_sdg.py` key CLI flags:
- `--headless`, `--width`, `--height`, `--num_frames`, `--data_dir`, `--distractors`
- `--asset_paths`, `--asset_dir`, `--asset_glob`
- `--materials_dir` (repeatable)
- `--object_class`, `--object_classes`
- `--prim_prefix`, `--fallback_count`
- `--object_scale`, `--cam_pos`, `--obj_pos`, `--obj_rot`, `--dist_pos`, `--dist_rot`, `--dist_scale`
- `--warehouse_robot_config`, `--warehouse_robot_paths`, `--warehouse_robot_repeat`

Object Scale and Pose Ranges
----------------------------
Range vars/flags accept comma or colon separators.

Formats:
- Single value: `s` -> fixed `(s, s, s)`.
- Two values: `min,max` -> scalar range for all axes.
- Three values: `x,y,z` -> fixed per-axis values.
- Six values: `x_min,y_min,z_min,x_max,y_max,z_max` -> per-axis ranges.

Applies to:
- `OBJECT_SCALE` / `--object_scale`
- `CAM_POS` / `--cam_pos`
- `OBJ_POS` / `--obj_pos`
- `OBJ_ROT` / `--obj_rot`
- `DIST_POS` / `--dist_pos`
- `DIST_ROT` / `--dist_rot`
- `DIST_SCALE` / `--dist_scale`

Warehouse Robot YAML Format
---------------------------
Example:
```yaml
repeat: 2
robots:
  - /Isaac/Robots/UniversalRobots/ur3e/ur3e.usd
  - /Isaac/Robots/Ufactory/lite6/lite6.usd
  - /Isaac/Robots/Ufactory/uf850/uf850.usd
  - /Isaac/Robots/Ufactory/xarm6/xarm6.usd
  - path: /Isaac/Robots/RethinkRobotics/Sawyer/sawyer_instanceable.usd
    repeat: 1
```

Notes:
- Top-level `repeat` is optional.
- Per-robot `repeat` is optional.
- `WAREHOUSE_ROBOT_PATHS` / `--warehouse_robot_paths` overrides YAML robot entries.
- Missing robot paths are skipped with a warning.

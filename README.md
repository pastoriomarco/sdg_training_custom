sdg_training_custom
====================

Lightweight pipeline to generate synthetic data in NVIDIA Isaac Sim for any custom object USD, and train a YOLOv8 detector on the output. This repo generalizes an internal workflow to configurable "custom" objects.  
This pipeline is mainly thought for bin picking applications to use in isaac_ros_foundation pipeline, thus having various robots as distractors. Customize it to your needs for other applications. 

What It Does
------------
- Spawns one or more custom USD assets, randomizes pose, lighting, and environment textures, and optionally adds distractors.
- Writes COCO-format annotations (2D bboxes, semantic and instance masks optional).
- Organizes images/labels for YOLO and starts a YOLOv8 training run.

Requirements
------------
- Isaac Sim 5.0 (with Replicator) and access to the Isaac assets server (Nucleus) for environments. I prefer building Isaac SIM 5.0 from source with the instructions provided in the [IsaacSim official GitHub repo](https://github.com/isaac-sim/IsaacSim).
- For `custom_datagen_convert_yolov8.sh` and training: follow [yolov8_setup.md](https://github.com/pastoriomarco/sdg_training_custom/blob/main/custom_sdg/yolov8_setup.md) to set up `yolov8` Python environment with Conda.

Quick Start
-----------
1. Create the SDG workspace folder and download the repo. Edit the SDG workspace folder as you want:
    ```bash
    export SDG_WS=~/workspaces/sdg/
    mkdir -p ${SDG_WS}/src
    cd ${SDG_WS}/src && \
      git clone https://github.com/pastoriomarco/sdg_training_custom.git
    ```
2. Run `custom_datagen_convert_yolov8.sh` from SDG workspace: the scripts will download the required models there. You should at least provide the path to the custom object `usd` and to the materials' folder. E.g.:
    ```bash
    cd ${SDG_WS} && \
      CUSTOM_ASSET_PATHS=/EDIT/THIS/path/to/your/object.usd \
      CUSTOM_MATERIALS_DIRS=/EDIT/THIS/path/to/materials_dir/ \
      WAREHOUSE_ROBOT_CONFIG=${SDG_WS}/src/sdg_training_custom/custom_sdg/warehouse_robots.default.yaml \
      ${SDG_WS}/src/sdg_training_custom/custom_sdg/custom_datagen_convert_yolov8.sh
    ```
    Other folders you may want to set before running datagen:  
    *SIM_PY* is where the Isaac SIM's python.sh script is located. If you didn't install in the recommended location, edit this variable accordingly.  
    *OUT_ROOT* is the output folder for the SDG. If you edit it for `custom_datagen_convert_yolov8.sh`, remember to provide the same for `custom_train_yolov8.sh`. 

    For example, if you download the data from [my isaac_sim_custom_examples repo](https://github.com/pastoriomarco/isaac_sim_custom_examples.git) in ${SDG_WS}/src folder, you can run:

    ```bash
    cd ${SDG_WS} && \
      CUSTOM_ASSET_PATHS=${SDG_WS}/src/isaac_sim_custom_examples/trocar_short.usdz \
      CUSTOM_MATERIALS_DIRS=${SDG_WS}/src/isaac_sim_custom_examples/Materials/ \
      WAREHOUSE_ROBOT_CONFIG=${SDG_WS}/src/sdg_training_custom/custom_sdg/warehouse_robots.expanded.yaml \
      OBJECT_SCALE=0.001 \
      ${SDG_WS}/src/sdg_training_custom/custom_sdg/custom_datagen_convert_yolov8.sh
    ```

3. Edit `src/sdg_training_custom/custom_sdg/my_dataset.yaml` according to your needs, and check the env vars you can set for `custom_train_yolov8.sh`.  

4. Once completed, proceed to model training and conversion:
    ```bash
    cd ${SDG_WS} && \
      ${SDG_WS}/src/sdg_training_custom/custom_sdg/custom_train_yolov8.sh  
    ```

Layout
------
- `custom_sdg/standalone_custom_sdg.py` — Isaac Sim dataset generator (Replicator-based, configurable).
- `custom_sdg/custom_datagen_convert_yolov8.sh` — Runs 3 generation passes for train/val/test splits with selectable distractors and converts COCO → YOLO.
- `custom_sdg/custom_datagen.sh` — Runs 3 generation passes (warehouse, additional, none). Assumes script is available inside the Isaac Sim install; see below.
- `custom_sdg/custom_train_yolov8.sh` — Trains YOLOv8 on the generated dataset.
- `custom_sdg/coco2yolo.py` — COCO → YOLO labels converter.
- `custom_sdg/my_dataset.yaml` — YOLO dataset config (default class name `custom`).
- `custom_sdg/warehouse_robots.default.yaml` — Default articulated warehouse robot distractor set.
- `custom_sdg/warehouse_robots.with_grippers.yaml` — Variant including gripper-focused robot assets.
- `custom_sdg/warehouse_robots.expanded.yaml` — Expanded articulated candidate set (missing paths auto-skipped).

Custom Objects
--------------
You can provide assets in two ways:
- Convert script (recommended): use colon-separated env vars. Single-value works too.
  - `CUSTOM_ASSET_PATHS=/a.usd:/b.usd CUSTOM_OBJECT_CLASSES=cup:bottle WAREHOUSE_ROBOT_CONFIG=./custom_sdg/warehouse_robots.default.yaml ./custom_sdg/custom_datagen_convert_yolov8.sh`
  - For one asset/class: `CUSTOM_ASSET_PATHS=/a.usd CUSTOM_OBJECT_CLASSES=custom WAREHOUSE_ROBOT_CONFIG=./custom_sdg/warehouse_robots.default.yaml ./custom_sdg/custom_datagen_convert_yolov8.sh`
- Direct Python: pass repeated args; single or multiple values work the same way:
  - `--asset_paths /a.usd /b.usd --object_classes cup bottle`
  - `--asset_paths /a.usd --object_classes custom`
- Objects must be in `.usd` format: check the scale of your objects! You can control the in-sim object scale via `OBJECT_SCALE` (see Notes).

Important: When more than one asset is provided, the number of classes must equal the number of assets (strict 1:1). The generator enforces this and will exit with an error if they mismatch. The order defines class ids (stable across splits) and is used to build COCO categories and the dataset YAML.
Note: since I use this for isaac_ros_foundationpose pipeline, I tested it mainly on single-class version. Let me know if you find some issue on multi-class version!

Fallback prim paths also use a prefix you can change via `--prim_prefix` (default `custom`).

Materials
---------
The generator can assign materials in two ways:
- Local USD materials: Provide one or more directories of USD material files via repeated `--materials_dir` flags. The generator now scans all `.usd` files (recursively) in each directory and imports every `UsdShade.Material` prim it finds. Material prim names are sanitized (invalid characters replaced, prefixed if starting with a digit) to produce valid stage paths.
- Online MDL materials: A small set of MDL URLs are created and imported if reachable (requires network access). Both sources are combined, then one material is randomly bound to each model target once (constant during the run).

Tip: with `custom_datagen_convert_yolov8.sh` you can pass multiple material directories as a colon-separated env var:
`CUSTOM_MATERIALS_DIRS=/dir/A:/dir/B WAREHOUSE_ROBOT_CONFIG=./custom_sdg/warehouse_robots.default.yaml ./custom_sdg/custom_datagen_convert_yolov8.sh`

Material discovery and current behavior
--------------------------------------
- Discovery: The generator collects local material directories from any `--materials_dir` you provide. In `custom_datagen_convert_yolov8.sh`, `CUSTOM_MATERIALS_DIRS` defaults to `$HOME/Downloads/source/Materials`, so that folder is used unless you override it. If you want per-asset automatic discovery (`<asset_dir>` and `<asset_dir>/Materials`), set `CUSTOM_MATERIALS_DIRS=""` (or run `standalone_custom_sdg.py` directly without `--materials_dir`).
- Import: All `.usd` files found in discovered directories are scanned, and every `UsdShade.Material` prim found is imported. Online MDL materials are also added if reachable.
- Assignment: One material from the imported set is randomly assigned to each object target and remains fixed during the run.

Example using your Materials folder
----------------------------------
If your materials are under `/home/tndlux/Downloads/source/Materials/`, you can set:

- Convert + splits flow:
  `CUSTOM_ASSET_PATHS=$HOME/Downloads/source/your_object.usd CUSTOM_MATERIALS_DIRS=$HOME/Downloads/source/Materials WAREHOUSE_ROBOT_CONFIG=./custom_sdg/warehouse_robots.default.yaml ./custom_sdg/custom_datagen_convert_yolov8.sh`

- Three-pass flow (from inside Isaac Sim):
  `ISAAC_SIM_PATH=/isaac-sim CUSTOM_ASSET_PATHS=$HOME/Downloads/source/your_object.usd WAREHOUSE_ROBOT_CONFIG=/isaac-sim/custom_sdg/warehouse_robots.default.yaml ./custom_sdg/custom_datagen.sh`

If you want to restrict discovery to explicit material directories, pass them via `CUSTOM_MATERIALS_DIRS` (colon-separated) or `--materials_dir` (one per dir). Only those directories will be searched:
`CUSTOM_MATERIALS_DIRS=/extra/mats1:/extra/mats2 CUSTOM_ASSET_PATHS=$HOME/Downloads/source/your_object.usd WAREHOUSE_ROBOT_CONFIG=./custom_sdg/warehouse_robots.default.yaml ./custom_sdg/custom_datagen_convert_yolov8.sh`

Running Generation
------------------
Option A — Train/Val/Test + COCO→YOLO (recommended):
- `cd custom_sdg`
- Activate `conda activate yolov8` (required by the convert script). This env should satisfy `yolov8_setup.md`.
- Single or multi asset & classes (strict 1:1):
  `CUSTOM_ASSET_PATHS=/a.usd[:/b.usd:...] CUSTOM_OBJECT_CLASSES=classA[:classB:...] WAREHOUSE_ROBOT_CONFIG=./custom_sdg/warehouse_robots.default.yaml ./custom_sdg/custom_datagen_convert_yolov8.sh`
  - Important env vars: `SIM_PY` (Isaac `python.sh`), `OUT_ROOT` (dataset root), `WIDTH/HEIGHT/HEADLESS`, `CUSTOM_*` (assets, class, prefix, materials).
  - Optional range env vars:
    - `OBJECT_SCALE` — object scale range
    - `CAM_POS` — camera position range
    - `OBJ_POS` / `OBJ_ROT` — custom object group position/rotation ranges
    - `DIST_POS` / `DIST_ROT` / `DIST_SCALE` — distractor position/rotation/scale ranges

Option B — Three passes (warehouse/additional/none) from inside Isaac Sim:
- Copy or mount this folder to `${ISAAC_SIM_PATH}/custom_sdg` so that `standalone_custom_sdg.py` is on disk there.
- Run: `CUSTOM_ASSET_PATHS=$HOME/Downloads/source/your_object.usd WAREHOUSE_ROBOT_CONFIG=${ISAAC_SIM_PATH}/custom_sdg/warehouse_robots.default.yaml ./custom_datagen.sh`
- The same optional range env vars (`OBJECT_SCALE`, `CAM_POS`, `OBJ_POS`, `OBJ_ROT`, `DIST_POS`, `DIST_ROT`, `DIST_SCALE`) are supported and forwarded to the generator.

Direct Python launch (advanced):
- `bash "$SIM_PY" custom_sdg/standalone_custom_sdg.py --asset_paths /a.usd [/b.usd ...] --object_classes classA [classB ...] --warehouse_robot_config custom_sdg/warehouse_robots.default.yaml --data_dir /tmp/out --distractors None --prim_prefix custom`

Complete Parameter Reference
----------------------------
This section summarizes all available parameters/env vars for every entry point.

`custom_sdg/custom_datagen_convert_yolov8.sh` (env vars)
- `SIM_PY`: Isaac Sim `python.sh` path (default: `$HOME/isaacsim/_build/linux-x86_64/release/python.sh`)
- `WIDTH`, `HEIGHT`, `HEADLESS`
- `FRAMES_TRAIN`, `FRAMES_VAL`, `FRAMES_TEST`
- `OUT_ROOT`
- `CUSTOM_ASSET_PATHS`, `CUSTOM_OBJECT_CLASSES`, `CUSTOM_PRIM_PREFIX`, `FALLBACK_COUNT`
- `CUSTOM_MATERIALS_DIRS`
- `DISTRACTORS`, `DISTRACTORS_TRAIN`, `DISTRACTORS_VAL`, `DISTRACTORS_TEST`
- `WAREHOUSE_ROBOT_CONFIG` (YAML file; default: `custom_sdg/warehouse_robots.default.yaml`)
- `WAREHOUSE_ROBOT_PATHS` (colon-separated explicit robot USD paths; overrides config list)
- `WAREHOUSE_ROBOT_REPEAT` (default repeat for robot list density; overrides config `repeat`)
- `OBJECT_SCALE`, `CAM_POS`, `OBJ_POS`, `OBJ_ROT`, `DIST_POS`, `DIST_ROT`, `DIST_SCALE`
- `AUTO_CLEAN`, `DEBUG`
- `SKIP_YOLO_POST` (`1/true` skips YOLO env check and YOLO post-processing artifacts)

`custom_sdg/standalone_custom_sdg.py` (CLI flags)
- `--headless`, `--width`, `--height`, `--num_frames`, `--data_dir`, `--distractors`
- `--asset_paths`, `--asset_dir`, `--asset_glob`
- `--materials_dir` (repeatable)
- `--object_class`, `--object_classes`
- `--prim_prefix`, `--fallback_count`
- `--object_scale`, `--cam_pos`, `--obj_pos`, `--obj_rot`, `--dist_pos`, `--dist_rot`, `--dist_scale`
- `--warehouse_robot_config` (YAML file)
- `--warehouse_robot_paths` (space-separated explicit robot USD paths)
- `--warehouse_robot_repeat`
- Legacy (backward compatibility): `--allow_unstable_warehouse_robots`, `--franka_distractor_variant`, `--extra_warehouse_robot_paths`

`custom_sdg/custom_datagen.sh` (env vars, 3-pass flow inside Isaac Sim)
- `ISAAC_SIM_PATH`
- `CUSTOM_ASSET_PATHS`, `CUSTOM_OBJECT_CLASSES`, `CUSTOM_PRIM_PREFIX`, `FALLBACK_COUNT`
- `DATA_ROOT`
- `WAREHOUSE_ROBOT_CONFIG`, `WAREHOUSE_ROBOT_PATHS`, `WAREHOUSE_ROBOT_REPEAT`
- `OBJECT_SCALE`, `CAM_POS`, `OBJ_POS`, `OBJ_ROT`, `DIST_POS`, `DIST_ROT`, `DIST_SCALE`

`custom_sdg/custom_train_yolov8.sh` (env vars)
- `OUT_ROOT`, `DATA_YAML`
- `MODEL`, `EPOCHS`, `BATCH`, `IMG_SIZE`, `DEVICE`, `WORKERS`
- `PROJECT_NAME`, `RUN_NAME`
- `PYTHON_BIN`, `ENFORCE_LABELS`, `EXPORT_ONNX`, `DEBUG`

Training YOLOv8
---------------
- Activate a Python env that satisfies `yolov8_setup.md` (a Conda env like `yolov8` is recommended). Scripts validate required packages.
- After generation/conversion: `OUT_ROOT=$HOME/synthetic_out RUN_NAME=yolov8s_custom ./custom_sdg/custom_train_yolov8.sh`
- The convert script writes `$OUT_ROOT/my_dataset.yaml` with a `names:` list in the same order as the classes you provided (stable across splits). The train script auto-uses this YAML when present and patches only the `path:` if needed.
- Enforcement: If `$OUT_ROOT/classes_unique.txt` is present, the train script validates that the dataset YAML has the same number of class names and that label files contain only indices within range. Use `DATA_YAML=/path/to/your.yaml` to override the dataset file explicitly.

Notes & Customization
---------------------
- Distractors: `--distractors` accepts `warehouse`, `additional`, or `None`.
- Warehouse robot selection: set an explicit list via `WAREHOUSE_ROBOT_PATHS` (or `--warehouse_robot_paths`) or provide a YAML file via `WAREHOUSE_ROBOT_CONFIG` (or `--warehouse_robot_config`).
- Default working setup uses `custom_sdg/warehouse_robots.default.yaml` (conservative articulated manipulators only).
- Use `WAREHOUSE_ROBOT_REPEAT` / `--warehouse_robot_repeat` to set default robot repeat density.
- If needed, override repeat per robot in YAML with `- path: ...` plus `repeat: N`.
- Pose & scale ranges are in `standalone_custom_sdg.py` (search for `rep.modify.pose` for both camera and objects). Object scale is configurable via `OBJECT_SCALE` env var (convert script) or `--object_scale` (Python); defaults to fixed `0.01` if not provided.

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
- `repeat` is optional (defaults to `2` when unset).
- Per-entry `repeat` is optional; if set for any robot, that robot uses its own repeat while others use default `repeat`.
- `WAREHOUSE_ROBOT_PATHS` / `--warehouse_robot_paths` overrides YAML robot entries.
- Missing robot paths are skipped with a warning.

Object Scale
------------
- Convert script (env var): set `OBJECT_SCALE` before running `custom_datagen_convert_yolov8.sh`.
- Direct Python: pass `--object_scale` with the same formats.

Accepted formats (commas or colons as separators):
- Single value: `s`
  - Example: `0.01`
  - Meaning: fixed uniform scale `(s, s, s)`.
- Two values: `min,max`
  - Example: `0.008,0.015`
  - Meaning: scalar range applied to all axes (a single factor in `[min,max]`).
- Three values: `x,y,z`
  - Example: `0.01,0.01,0.01`
  - Meaning: fixed per-axis scale `(x, y, z)`.
- Six values: `(x_min, y_min, z_min, x_max, y_max, z_max)`
  - Example: `0.008,0.008,0.008,0.015,0.015,0.015`
  - Meaning: independent per-axis ranges.

Notes:
- Separators: `,` or `:` both work; spaces are ignored.
- Defaults to `0.01` if not provided.

Position/Rotation/Scale Ranges
------------------------------
All vector ranges accept the same formats as `OBJECT_SCALE` (commas or colons):
- Single value: `s` → fixed `(s, s, s)`
- Two values: `min,max` → scalar range applied to all axes
- Three values: `x,y,z` → fixed per-axis
- Six values: `(x_min, y_min, z_min, x_max, y_max, z_max)` → per-axis ranges

Variables and CLI flags:
- Camera: `CAM_POS` or `--cam_pos`
- Custom objects: `OBJ_POS`/`--obj_pos`, `OBJ_ROT`/`--obj_rot`
- Distractors: `DIST_POS`/`--dist_pos`, `DIST_ROT`/`--dist_rot`, `DIST_SCALE`/`--dist_scale`

Defaults (if not set):
- Camera position: `(-0.75, -0.75, 0.75)` to `(0.75, 0.75, 1.0)`
- Object position: `(-0.3, -0.2, 0.35)` to `(0.3, 0.2, 0.5)`
- Object rotation (deg): `(0, -45, 0)` to `(0, 45, 360)`
- Distractor position: `(-2, -2, 0)` to `(2, 2, 0)`
- Distractor rotation (deg): `(0, 0, 0)` to `(0, 30, 360)`
- Distractor scale: with `--distractors warehouse`, fixed `1` (articulated robots; avoids PhysX joint snapping); otherwise `1` to `1.5`
- Fallback behavior: If Replicator instances don’t appear, the script references your asset(s) under `/World/<prim_prefix>_##` and applies the chosen semantics. `--fallback_count` controls how many fallback references per asset.
- COCO writer toggles are defined in `standalone_custom_sdg.py` (RGB, tight 2D boxes, semantic and instance masks on by default).

 Datagen + Convert Parameters (env vars)
 ---------------------------------------
 `custom_sdg/custom_datagen_convert_yolov8.sh` drives 3 generation passes (train/val/test) via Isaac Sim, then converts COCO → YOLO and writes `my_dataset.yaml`. Configure it via environment variables:
 - SIM_PY: path to Isaac Sim `python.sh`. Default: `$HOME/isaacsim/_build/linux-x86_64/release/python.sh`.
 - WIDTH, HEIGHT: output image resolution. Default: `640`, `640`.
 - HEADLESS: run generator headless (`1/true/yes` or `0/false/no`). Default: `True`.
 - FRAMES_TRAIN, FRAMES_VAL, FRAMES_TEST: frames per split. Default: `2500`, `500`, `500`.
 - OUT_ROOT: dataset root folder. Default: `$HOME/synthetic_out`.
 - CUSTOM_ASSET_PATHS: colon-separated list of USD files. Required for your assets. Example: `/a.usd:/b.usd`.
 - CUSTOM_OBJECT_CLASSES: colon-separated class names, 1:1 with assets, order defines class ids. Default: `custom` (single-asset only).
 - CUSTOM_PRIM_PREFIX: prefix for fallback prim names under `/World`. Default: `custom`.
 - FALLBACK_COUNT: number of fallback references per asset if Replicator instances are missing. Default: `2`.
- CUSTOM_MATERIALS_DIRS: colon-separated directories with local USD materials. Default: `$HOME/Downloads/source/Materials` in this wrapper. Set `CUSTOM_MATERIALS_DIRS=""` to use per-asset automatic discovery.
- DISTRACTORS: choose `warehouse`, `additional`, or `None`. Default: `warehouse`.
- DISTRACTORS_TRAIN, DISTRACTORS_VAL, DISTRACTORS_TEST: per-split overrides; default to `DISTRACTORS` when unset.
- WAREHOUSE_ROBOT_CONFIG: YAML file defining warehouse robot distractors. Default: `custom_sdg/warehouse_robots.default.yaml`.
- WAREHOUSE_ROBOT_PATHS: colon-separated explicit articulated robot USD paths under `/Isaac/Robots/...`; overrides robot list from config.
- WAREHOUSE_ROBOT_REPEAT: default repeat factor for configured robot list density; overrides config `repeat` when set.
- OBJECT_SCALE: object scale range/values. See “Object Scale” below. Default: fixed `0.01` when unset.
 - CAM_POS, OBJ_POS, OBJ_ROT, DIST_POS, DIST_ROT, DIST_SCALE: ranges for camera, object group, and distractors. See “Position/Rotation/Scale Ranges” below for accepted formats and defaults.
 - AUTO_CLEAN: when `1` or `true`, delete existing `OUT_ROOT` without prompting. Default: disabled (prompts when interactive).
 - DEBUG: enable verbose bash tracing when `1`. Default: `0`.
 - SKIP_YOLO_POST: when `1` or `true`, generate only COCO split outputs and skip YOLO conversion artifacts (`images/`, `labels/`, `my_dataset.yaml`) and the `yolov8` env check.

 Notes
 - Multi-asset requires `CUSTOM_OBJECT_CLASSES` with the same count; order is preserved and used to build `names:` in `my_dataset.yaml` (stable across splits).
 - Materials: set `CUSTOM_MATERIALS_DIRS` to explicit directories. For per-asset automatic discovery, set `CUSTOM_MATERIALS_DIRS=""`.
 - The script requires the `yolov8` Conda env only when `SKIP_YOLO_POST` is not enabled; follow `yolov8_setup.md` for setup when using YOLO conversion/training flow.

 Examples
- Single asset with local materials and fixed scale:
  `CUSTOM_ASSET_PATHS=/data/thing.usd CUSTOM_MATERIALS_DIRS=/data/Materials WAREHOUSE_ROBOT_CONFIG=./custom_sdg/warehouse_robots.default.yaml OBJECT_SCALE=0.01 ./custom_sdg/custom_datagen_convert_yolov8.sh`
 - Working articulated-robot setup (uses default conservative YAML list):
   `DISTRACTORS=warehouse WAREHOUSE_ROBOT_CONFIG=./custom_sdg/warehouse_robots.default.yaml DIST_SCALE=1 ./custom_sdg/custom_datagen_convert_yolov8.sh`
- Two assets, two classes, per-split distractors and custom frames:
  `CUSTOM_ASSET_PATHS=/a.usd:/b.usd CUSTOM_OBJECT_CLASSES=cup:bottle WAREHOUSE_ROBOT_CONFIG=./custom_sdg/warehouse_robots.default.yaml FRAMES_TRAIN=3000 FRAMES_VAL=600 FRAMES_TEST=600 DISTRACTORS_TRAIN=warehouse DISTRACTORS_VAL=None DISTRACTORS_TEST=additional ./custom_sdg/custom_datagen_convert_yolov8.sh`
- Non-headless, custom resolution, auto-clean:
  `HEADLESS=0 WIDTH=960 HEIGHT=544 WAREHOUSE_ROBOT_CONFIG=./custom_sdg/warehouse_robots.default.yaml AUTO_CLEAN=1 ./custom_sdg/custom_datagen_convert_yolov8.sh`

 Train Script Parameters (env vars)
 ----------------------------------
 `custom_sdg/custom_train_yolov8.sh` is configured via environment variables (no positional flags). Common knobs and defaults:
 - OUT_ROOT: dataset root produced by convert step. Default: `$HOME/synthetic_out`.
 - DATA_YAML: path to dataset yaml to use. Default: auto-pick `$OUT_ROOT/my_dataset.yaml`, else falls back to `custom_sdg/my_dataset.yaml`.
 - MODEL: YOLOv8 model or weights to start from (e.g., `yolov8s.pt`, `yolov8n.pt`, `/path/to/best.pt`). Default: `yolov8s.pt`.
 - EPOCHS: number of training epochs. Default: `50`.
 - BATCH: batch size. Default: `16`.
 - IMG_SIZE: image size (imgsz). Default: `640`.
 - DEVICE: GPU id or `cpu`. Default: `0`.
 - WORKERS: dataloader workers. Default: `8`.
 - PROJECT_NAME: parent runs directory under `OUT_ROOT`. Default: `yolo_runs`.
 - RUN_NAME: name of this training run. Default: `yolov8s_custom`.
 - PYTHON_BIN: interpreter to use for checks/exports. Default: `python` (falls back to `python3`).
 - EXPORT_ONNX: export `best.pt` to ONNX after training (`1` enable, `0` disable). Default: `1`.
 - ENFORCE_LABELS: validate label class ids are within range when class meta is present (`1` enable, `0` disable). Default: `1`.
 - DEBUG: enable verbose bash tracing (`1` enable). Default: `0`.

 Notes
 - The script requires the `yolov8` Conda env to be active and will exit if `CONDA_DEFAULT_ENV` is not `yolov8`.
 - If `DATA_YAML` is unset, the script auto-selects `$OUT_ROOT/my_dataset.yaml` when present; otherwise it uses `custom_sdg/my_dataset.yaml` and patches its `path:` to the chosen `OUT_ROOT` at runtime.
 - The underlying `ultralytics` CLI invocation maps to: `yolo detect train model=$MODEL data=$DATA_YAML imgsz=$IMG_SIZE epochs=$EPOCHS batch=$BATCH device=$DEVICE workers=$WORKERS project=$OUT_ROOT/$PROJECT_NAME name=$RUN_NAME`.

Examples
- Train with a different base model and larger image size:
  `MODEL=yolov8m.pt IMG_SIZE=896 RUN_NAME=y8m_896 ./custom_sdg/custom_train_yolov8.sh`
- Resume/fine-tune from previous weights and skip ONNX export:
  `MODEL=$OUT_ROOT/yolo_runs/prev_run/weights/best.pt EXPORT_ONNX=0 ./custom_sdg/custom_train_yolov8.sh`
- Use a custom dataset YAML and CPU training:
  `DATA_YAML=/data/my_dataset.yaml DEVICE=cpu ./custom_sdg/custom_train_yolov8.sh`
  
---

DISCLAIMER
==========

This package builds upon and integrates components from:

* [NVIDIA Isaac Sim](https://docs.isaacsim.omniverse.nvidia.com/latest/index.html)
* [NVIDIA synthetic\_data\_generation\_training\_workflow](https://github.com/NVIDIA-AI-IOT/synthetic_data_generation_training_workflow)
* [Ultralytics YOLOv8](https://github.com/ultralytics/ultralytics)

All copyrights, trademarks, and ownership of the original software remain with their respective owners, including **NVIDIA Corporation** and **Ultralytics**.

This tutorial and the associated launch files are **community-created** and are **not officially maintained, endorsed, or supported by NVIDIA**.

It is intended to serve as a **reference and example** for custom training a YOLOV8 model with synthetic generated data created with Isaac SIM in a practical pipeline.  
While care has been taken to test the setup, **there are no guarantees of correctness, completeness, or compatibility** with future Isaac SIM releases.

Use this material **at your own discretion and risk**. For official documentation, support, and best practices, refer to the official NVIDIA documentation.

---

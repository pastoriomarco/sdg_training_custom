sdg_training_custom
====================

Lightweight pipeline to generate synthetic data in NVIDIA Isaac Sim for any custom object USD, and train a YOLOv8 detector on the output. This repo generalizes an internal td06 workflow to configurable "custom" objects.

What It Does
------------
- Spawns one or more custom USD assets, randomizes pose, lighting, and environment textures, and optionally adds distractors.
- Writes COCO-format annotations (2D bboxes, semantic and instance masks optional).
- Optionally organizes images/labels for YOLO and starts a YOLOv8 training run.

Layout
------
- `custom_sdg/standalone_custom_sdg.py` — Isaac Sim dataset generator (Replicator-based, configurable).
- `custom_sdg/custom_datagen.sh` — Runs 3 generation passes (warehouse, additional, none). Assumes script is available inside the Isaac Sim install; see below.
- `custom_sdg/custom_datagen_convert_yolov8.sh` — Same as custom_datagen.sh but also generates train/val/test splits and converts COCO → YOLO.
- `custom_sdg/custom_train_yolov8.sh` — Trains YOLOv8 on the generated dataset.
- `custom_sdg/coco2yolo.py` — COCO → YOLO labels converter.
- `custom_sdg/my_dataset.yaml` — YOLO dataset config (class name `custom`).

Requirements
------------
- Isaac Sim 5.0 (with Replicator) and access to the Isaac assets server (Nucleus) for environments.
- For `custom_datagen_convert_yolov8.sh` and training: a Conda env named `yolov8` with `ultralytics` installed.
  - Both scripts check `CONDA_DEFAULT_ENV == yolov8` and exit if not active.
  - Follow the setup guide: `src/sdg_training_custom/custom_sdg/yolov8_setup.md` (this repo).

Custom Objects
--------------
You can provide assets in two ways (both support multiple USDs at once):
- Directory + glob: `--asset_dir /path/to/usds --asset_glob "*.usd"`
- Explicit list: `--asset_paths /path/a.usd /path/b.usd ...`

Defaults in the provided shell scripts use `CUSTOM_ASSET_DIR=$HOME/Downloads/source` and `CUSTOM_ASSET_GLOB=*.usd`. Drop your USD(s) there, or override via env vars.

All provided assets are labeled with the same semantic class (default `custom`). You can change the class with `--object_class` (e.g., `--object_class td06` to mirror the old pipeline). Fallback prim paths also use a prefix you can change via `--prim_prefix` (default `custom`).

Materials
---------
The generator can assign materials in two ways:
- Local USD materials: Provide one or more directories of USD material files via repeated `--materials_dir` flags. The generator now scans all `.usd` files (recursively) in each directory and imports every `UsdShade.Material` prim it finds. Material prim names are sanitized (invalid characters replaced, prefixed if starting with a digit) to produce valid stage paths.
- Online MDL materials: A small set of MDL URLs are created and imported if reachable (requires network access). Both sources are combined, then one material is randomly bound to each model target once (constant during the run).

Tip: with `custom_datagen_convert_yolov8.sh` you can pass multiple material directories as a colon-separated env var:
`CUSTOM_MATERIALS_DIRS=/dir/A:/dir/B ./custom_sdg/custom_datagen_convert_yolov8.sh`

Material discovery and current behavior
--------------------------------------
- Discovery: The generator collects local material directories from any `--materials_dir` you provide. If you set only `CUSTOM_ASSET_DIR` (and not `CUSTOM_MATERIALS_DIRS`), the generator still searches `CUSTOM_ASSET_DIR` and `CUSTOM_ASSET_DIR/Materials` automatically. Otherwise, if `CUSTOM_MATERIALS_DIRS` and/or `--materials_dir` is provided, the generator only searches these provided dirs.
- Import: All `.usd` files found in discovered directories are scanned, and every `UsdShade.Material` prim found is imported. Online MDL materials are also added if reachable.
- Assignment: One material from the imported set is randomly assigned to each object target and remains fixed during the run.

Example using your Materials folder
----------------------------------
If your materials are under `/home/tndlux/Downloads/source/Materials/`, you can just set `CUSTOM_ASSET_DIR` and the generator will discover and import them automatically:

- Convert + splits flow:
  `CUSTOM_ASSET_DIR=$HOME/Downloads/source ./custom_sdg/custom_datagen_convert_yolov8.sh`

- Three-pass flow (from inside Isaac Sim):
  `ISAAC_SIM_PATH=/isaac-sim CUSTOM_ASSET_DIR=$HOME/Downloads/source ./custom_sdg/custom_datagen.sh`

If you have additional material directories outside the assets root, pass them via `CUSTOM_MATERIALS_DIRS` (colon-separated):
`CUSTOM_MATERIALS_DIRS=/extra/mats1:/extra/mats2 CUSTOM_ASSET_DIR=$HOME/Downloads/source ./custom_sdg/custom_datagen_convert_yolov8.sh`

Running Generation
------------------
Option A — Train/Val/Test + COCO→YOLO (recommended):
- `cd custom_sdg`
- Activate env: `conda activate yolov8` (required; script checks and exits otherwise)
- `CUSTOM_ASSET_DIR=$HOME/Downloads/source ./custom_datagen_convert_yolov8.sh`
  - Important env vars: `SIM_PY` (Isaac `python.sh`), `OUT_ROOT` (dataset root), `WIDTH/HEIGHT/HEADLESS`, `CUSTOM_*` (assets, class, prefix, materials).

Option B — Three passes (warehouse/additional/none) from inside Isaac Sim:
- Copy or mount this folder to `${ISAAC_SIM_PATH}/custom_sdg` so that `standalone_custom_sdg.py` is on disk there.
- Run: `CUSTOM_ASSET_DIR=$HOME/Downloads/source ./custom_datagen.sh`

Direct Python launch (advanced):
- `bash "$SIM_PY" custom_sdg/standalone_custom_sdg.py --asset_dir "$HOME/Downloads/source" --data_dir /tmp/out --distractors None --object_class custom --prim_prefix custom`

Training YOLOv8
---------------
- Activate env: `conda activate yolov8` (required; script checks and exits otherwise)
- After generation/conversion: `OUT_ROOT=$HOME/synthetic_out RUN_NAME=yolov8s_custom ./custom_sdg/custom_train_yolov8.sh`
- The script auto-patches `my_dataset.yaml` to point at `OUT_ROOT` using a temporary file if needed.

Notes & Customization
---------------------
- Distractors: `--distractors` accepts `warehouse`, `additional`, or `None`.
- Pose & scale ranges are in `standalone_custom_sdg.py` (search for `rep.modify.pose` for both camera and objects). Scale is fixed to 0.01 by default; adjust as needed.
- Fallback behavior: If Replicator instances don’t appear, the script references your asset(s) under `/World/<prim_prefix>_##` and applies the chosen semantics. `--fallback_count` controls how many fallback references per asset.
- COCO writer toggles are defined in `standalone_custom_sdg.py` (RGB, tight 2D boxes, semantic and instance masks on by default).

Troubleshooting
---------------
- Ensure Isaac Sim’s Nucleus asset server is reachable; the environment USD (`/Isaac/Environments/Simple_Warehouse/warehouse.usd`) loads from there.
- If MDL URLs are blocked (no network), only local USD materials will be used.
- If `custom_datagen.sh` can’t find the script, make sure `custom_sdg` is physically present under `${ISAAC_SIM_PATH}` or use the convert script that resolves paths locally.

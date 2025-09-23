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
- `custom_sdg/custom_datagen_convert_yolov8.sh` — Runs 3 generation passes for train/val/test splits with selectable distractors and converts COCO → YOLO.
- `custom_sdg/custom_train_yolov8.sh` — Trains YOLOv8 on the generated dataset.
- `custom_sdg/coco2yolo.py` — COCO → YOLO labels converter.
- `custom_sdg/my_dataset.yaml` — YOLO dataset config (class name `custom`).

Requirements
------------
- Isaac Sim 5.0 (with Replicator) and access to the Isaac assets server (Nucleus) for environments.
- For `custom_datagen_convert_yolov8.sh` and training: a Python environment with the packages from `src/sdg_training_custom/custom_sdg/yolov8_setup.md`.
  - Scripts validate required packages at runtime (env name is not enforced). If something is missing, they point you to the setup guide.
  - Recommended: use a Conda env (e.g., `yolov8`) and follow the setup guide: `src/sdg_training_custom/custom_sdg/yolov8_setup.md` (this repo).

Custom Objects
--------------
You can provide assets in two ways:
- Convert script (recommended): use colon-separated env vars. Single-value works too.
  - `CUSTOM_ASSET_PATHS=/a.usd:/b.usd CUSTOM_OBJECT_CLASSES=cup:bottle ./custom_sdg/custom_datagen_convert_yolov8.sh`
  - For one asset/class: `CUSTOM_ASSET_PATHS=/a.usd CUSTOM_OBJECT_CLASSES=custom ./custom_sdg/custom_datagen_convert_yolov8.sh`
- Direct Python: pass repeated args; single or multiple values work the same way:
  - `--asset_paths /a.usd /b.usd --object_classes cup bottle`
  - `--asset_paths /a.usd --object_classes custom`

Important: When more than one asset is provided, the number of classes must equal the number of assets (strict 1:1). The generator enforces this and will exit with an error if they mismatch. The order defines class ids (stable across splits) and is used to build COCO categories and the dataset YAML.

Fallback prim paths also use a prefix you can change via `--prim_prefix` (default `custom`).

Materials
---------
The generator can assign materials in two ways:
- Local USD materials: Provide one or more directories of USD material files via repeated `--materials_dir` flags. The generator now scans all `.usd` files (recursively) in each directory and imports every `UsdShade.Material` prim it finds. Material prim names are sanitized (invalid characters replaced, prefixed if starting with a digit) to produce valid stage paths.
- Online MDL materials: A small set of MDL URLs are created and imported if reachable (requires network access). Both sources are combined, then one material is randomly bound to each model target once (constant during the run).

Tip: with `custom_datagen_convert_yolov8.sh` you can pass multiple material directories as a colon-separated env var:
`CUSTOM_MATERIALS_DIRS=/dir/A:/dir/B ./custom_sdg/custom_datagen_convert_yolov8.sh`

Material discovery and current behavior
--------------------------------------
- Discovery: The generator collects local material directories from any `--materials_dir` you provide. If you set only `CUSTOM_ASSET_PATH` (and not `CUSTOM_MATERIALS_DIRS`), the generator searches the directory of that asset and its `Materials/` subfolder automatically. Otherwise, if `CUSTOM_MATERIALS_DIRS` and/or `--materials_dir` is provided, the generator only searches these provided dirs.
- Import: All `.usd` files found in discovered directories are scanned, and every `UsdShade.Material` prim found is imported. Online MDL materials are also added if reachable.
- Assignment: One material from the imported set is randomly assigned to each object target and remains fixed during the run.

Example using your Materials folder
----------------------------------
If your materials are under `/home/tndlux/Downloads/source/Materials/`, you can just set `CUSTOM_ASSET_PATH=/home/tndlux/Downloads/source/your_object.usd` and the generator will discover and import materials from next to the asset automatically (when no custom materials dirs are provided):

- Convert + splits flow:
  `CUSTOM_ASSET_PATH=$HOME/Downloads/source/your_object.usd ./custom_sdg/custom_datagen_convert_yolov8.sh`

- Three-pass flow (from inside Isaac Sim):
  `ISAAC_SIM_PATH=/isaac-sim CUSTOM_ASSET_PATH=$HOME/Downloads/source/your_object.usd ./custom_sdg/custom_datagen.sh`

If you want to restrict discovery to explicit material directories, pass them via `CUSTOM_MATERIALS_DIRS` (colon-separated) or `--materials_dir` (one per dir). Only those directories will be searched:
`CUSTOM_MATERIALS_DIRS=/extra/mats1:/extra/mats2 CUSTOM_ASSET_PATH=$HOME/Downloads/source/your_object.usd ./custom_sdg/custom_datagen_convert_yolov8.sh`

Running Generation
------------------
Option A — Train/Val/Test + COCO→YOLO (recommended):
- `cd custom_sdg`
- Activate `conda activate yolov8` (required by the convert script). This env should satisfy `yolov8_setup.md`.
- Single or multi asset & classes (strict 1:1):
  `CUSTOM_ASSET_PATHS=/a.usd[:/b.usd:...] CUSTOM_OBJECT_CLASSES=classA[:classB:...] ./custom_sdg/custom_datagen_convert_yolov8.sh`
  - Important env vars: `SIM_PY` (Isaac `python.sh`), `OUT_ROOT` (dataset root), `WIDTH/HEIGHT/HEADLESS`, `CUSTOM_*` (assets, class, prefix, materials).

Option B — Three passes (warehouse/additional/none) from inside Isaac Sim:
- Copy or mount this folder to `${ISAAC_SIM_PATH}/custom_sdg` so that `standalone_custom_sdg.py` is on disk there.
- Run: `CUSTOM_ASSET_PATH=$HOME/Downloads/source/your_object.usd ./custom_datagen.sh`

Direct Python launch (advanced):
- `bash "$SIM_PY" custom_sdg/standalone_custom_sdg.py --asset_paths /a.usd [/b.usd ...] --object_classes classA [classB ...] --data_dir /tmp/out --distractors None --prim_prefix custom`

Training YOLOv8
---------------
- Activate a Python env that satisfies `yolov8_setup.md` (a Conda env like `yolov8` is recommended). Scripts validate required packages.
- After generation/conversion: `OUT_ROOT=$HOME/synthetic_out RUN_NAME=yolov8s_custom ./custom_sdg/custom_train_yolov8.sh`
- The convert script writes `$OUT_ROOT/my_dataset.yaml` with a `names:` list in the same order as the classes you provided (stable across splits). The train script auto-uses this YAML when present and patches only the `path:` if needed.
- Enforcement: If `$OUT_ROOT/classes_unique.txt` is present, the train script validates that the dataset YAML has the same number of class names and that label files contain only indices within range. Use `DATA_YAML=/path/to/your.yaml` to override the dataset file explicitly.

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

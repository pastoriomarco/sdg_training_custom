sdg_training_custom
====================

Lightweight pipeline to generate synthetic data in NVIDIA Isaac Sim for any custom object USD, and train a YOLOv8 detector on the output. This repo generalizes an internal workflow to configurable "custom" objects.  
This pipeline is mainly thought for bin picking applications, thus having various robots as distractors. Customize it to your needs for other applications. 

What It Does
------------
- Spawns one or more custom USD assets, randomizes pose, lighting, and environment textures, and optionally adds distractors.
- Writes COCO-format annotations (2D bboxes, semantic and instance masks optional).
- Organizes images/labels for YOLO and starts a YOLOv8 training run.

Layout
------
- `custom_sdg/standalone_custom_sdg.py` — Isaac Sim dataset generator (Replicator-based, configurable).
- `custom_sdg/custom_datagen_convert_yolov8.sh` — Runs 3 generation passes for train/val/test splits with selectable distractors and converts COCO → YOLO.
- `custom_sdg/custom_datagen.sh` — Runs 3 generation passes (warehouse, additional, none). Assumes script is available inside the Isaac Sim install; see below.
- `custom_sdg/custom_train_yolov8.sh` — Trains YOLOv8 on the generated dataset.
- `custom_sdg/coco2yolo.py` — COCO → YOLO labels converter.
- `custom_sdg/my_dataset.yaml` — YOLO dataset config (default class name `custom`).

Requirements
------------
- Isaac Sim 5.0 (with Replicator) and access to the Isaac assets server (Nucleus) for environments. I prefer building Isaac SIM 5.0 from source with the instructions provided in the [IsaacSim official GitHub repo](https://github.com/isaac-sim/IsaacSim).
- For `custom_datagen_convert_yolov8.sh` and training: follow [yolov8_setup.md](https://github.com/pastoriomarco/sdg_training_custom/blob/main/custom_sdg/yolov8_setup.md) to set up `yolov8` Python environment with Conda.

Custom Objects
--------------
You can provide assets in two ways:
- Convert script (recommended): use colon-separated env vars. Single-value works too.
  - `CUSTOM_ASSET_PATHS=/a.usd:/b.usd CUSTOM_OBJECT_CLASSES=cup:bottle ./custom_sdg/custom_datagen_convert_yolov8.sh`
  - For one asset/class: `CUSTOM_ASSET_PATHS=/a.usd CUSTOM_OBJECT_CLASSES=custom ./custom_sdg/custom_datagen_convert_yolov8.sh`
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
  - Optional range env vars:
    - `OBJECT_SCALE` — object scale range
    - `CAM_POS` — camera position range
    - `OBJ_POS` / `OBJ_ROT` — custom object group position/rotation ranges
    - `DIST_POS` / `DIST_ROT` / `DIST_SCALE` — distractor position/rotation/scale ranges

Option B — Three passes (warehouse/additional/none) from inside Isaac Sim:
- Copy or mount this folder to `${ISAAC_SIM_PATH}/custom_sdg` so that `standalone_custom_sdg.py` is on disk there.
- Run: `CUSTOM_ASSET_PATH=$HOME/Downloads/source/your_object.usd ./custom_datagen.sh`
- The same optional range env vars (`OBJECT_SCALE`, `CAM_POS`, `OBJ_POS`, `OBJ_ROT`, `DIST_POS`, `DIST_ROT`, `DIST_SCALE`) are supported and forwarded to the generator.

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
- Pose & scale ranges are in `standalone_custom_sdg.py` (search for `rep.modify.pose` for both camera and objects). Object scale is configurable via `OBJECT_SCALE` env var (convert script) or `--object_scale` (Python); defaults to fixed `0.01` if not provided.

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
- Distractor scale: `1` to `1.5`
- Fallback behavior: If Replicator instances don’t appear, the script references your asset(s) under `/World/<prim_prefix>_##` and applies the chosen semantics. `--fallback_count` controls how many fallback references per asset.
- COCO writer toggles are defined in `standalone_custom_sdg.py` (RGB, tight 2D boxes, semantic and instance masks on by default).

Troubleshooting
---------------
- Ensure Isaac Sim’s Nucleus asset server is reachable; the environment USD (`/Isaac/Environments/Simple_Warehouse/warehouse.usd`) loads from there.
- If MDL URLs are blocked (no network), only local USD materials will be used.
- If `custom_datagen.sh` can’t find the script, make sure `custom_sdg` is physically present under `${ISAAC_SIM_PATH}` or use the convert script that resolves paths locally.

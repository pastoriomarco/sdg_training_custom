# Copyright (c) 2022, NVIDIA CORPORATION.  All rights reserved.
#
#  SPDX-FileCopyrightText: Copyright (c) 2022 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: MIT

# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER

from omni.isaac.kit import SimulationApp
import os
import argparse
import random
import glob
from typing import List


def _str_to_bool(value):
    if isinstance(value, bool):
        return value
    value = str(value).strip().lower()
    if value in {"1", "true", "t", "yes", "y"}:
        return True
    if value in {"0", "false", "f", "no", "n"}:
        return False
    raise argparse.ArgumentTypeError(f"Cannot interpret '{value}' as boolean.")


def _expand_path(path: str) -> str:
    return os.path.abspath(os.path.expanduser(path))


parser = argparse.ArgumentParser("Dataset generator")
parser.add_argument("--headless", type=_str_to_bool, default=False, help="Launch script headless, default is False")
parser.add_argument("--height", type=int, default=544, help="Height of image")
parser.add_argument("--width", type=int, default=960, help="Width of image")
parser.add_argument("--num_frames", type=int, default=1000, help="Number of frames to record")
parser.add_argument(
    "--distractors",
    type=str,
    default="warehouse",
    help="Options are 'warehouse' (default), 'additional' or None",
)
parser.add_argument(
    "--data_dir",
    type=str,
    default=os.getcwd() + "/_custom_data",
    help="Location where data will be output",
)
parser.add_argument(
    "--asset_paths",
    type=str,
    nargs="+",
    default=None,
    help="One or more USD asset files for the custom object.",
)
parser.add_argument(
    "--asset_dir",
    type=str,
    default=None,
    help="Directory containing USD assets to instantiate (used with --asset_glob).",
)
parser.add_argument(
    "--asset_glob",
    type=str,
    default="*.usd",
    help="Glob used with --asset_dir to collect USD assets.",
)
parser.add_argument(
    "--materials_dir",
    type=str,
    action="append",
    default=None,
    help="Additional directories containing USD material files. Can be provided multiple times.",
)
parser.add_argument(
    "--object_class",
    type=str,
    default="custom",
    help="Semantic class label for the custom object.",
)
parser.add_argument(
    "--prim_prefix",
    type=str,
    default="custom",
    help="Prefix used for fallback /World prim paths when Replicator fails.",
)
parser.add_argument(
    "--fallback_count",
    type=int,
    default=2,
    help="Number of fallback USD references per asset when Replicator instances are missing.",
)

args, _ = parser.parse_known_args()


def _gather_asset_paths() -> List[str]:
    candidate_paths: List[str] = []
    seen = set()

    if args.asset_paths:
        for path in args.asset_paths:
            expanded = _expand_path(path)
            if expanded not in seen:
                candidate_paths.append(expanded)
                seen.add(expanded)

    if args.asset_dir:
        base_dir = _expand_path(args.asset_dir)
        pattern = os.path.join(base_dir, args.asset_glob)
        for match in sorted(glob.glob(pattern)):
            expanded = _expand_path(match)
            if os.path.isfile(expanded) and expanded not in seen:
                candidate_paths.append(expanded)
                seen.add(expanded)

    if not candidate_paths:
        raise SystemExit(
            "No asset files resolved. Provide --asset_paths or --asset_dir with matching assets."
        )

    allowed_prefixes = ("omniverse://", "http://", "https://")
    missing = [
        p
        for p in candidate_paths
        if not p.startswith(allowed_prefixes) and not os.path.isfile(p)
    ]
    if missing:
        missing_str = "\n  ".join(missing)
        raise SystemExit(f"The following asset files were not found on disk:\n  {missing_str}")

    return candidate_paths


def _gather_material_dirs(asset_paths: List[str]) -> List[str]:
    dirs: List[str] = []
    seen = set()
    candidates: List[str] = []

    if args.materials_dir:
        candidates.extend(args.materials_dir)

    for asset_path in asset_paths:
        base_dir = os.path.dirname(asset_path)
        candidates.append(base_dir)
        candidates.append(os.path.join(base_dir, "Materials"))

    for candidate in candidates:
        expanded = _expand_path(candidate)
        if os.path.isdir(expanded) and expanded not in seen:
            dirs.append(expanded)
            seen.add(expanded)

    return dirs


CUSTOM_ASSET_PATHS = _gather_asset_paths()
LOCAL_MATERIAL_DIRS = _gather_material_dirs(CUSTOM_ASSET_PATHS)
OBJECT_CLASS = args.object_class
OBJECT_PRIM_PREFIX = args.prim_prefix
FALLBACK_COUNT = max(1, args.fallback_count)

# App config
CONFIG = {
    "renderer": "RayTracedLighting",
    "headless": args.headless,
    "width": args.width,
    "height": args.height,
    "num_frames": args.num_frames,
}

simulation_app = SimulationApp(launch_config=CONFIG)

# Scene (environment)
ENV_URL = "/Isaac/Environments/Simple_Warehouse/warehouse.usd"

import carb
import omni
import omni.usd
from omni.isaac.core.utils.nucleus import get_assets_root_path
from omni.isaac.core.utils.stage import get_current_stage, open_stage
from pxr import Semantics, Usd, UsdGeom, Sdf, UsdShade, Gf
import omni.replicator.core as rep
from omni.isaac.core.utils.semantics import get_semantics  # noqa

# Replicator settings
rep.settings.carb_settings("/omni/replicator/RTSubframes", 4)


# Your object(s) (resolved at runtime)
def get_custom_asset_paths():
    return CUSTOM_ASSET_PATHS

# Distractors (unchanged)
DISTRACTORS_WAREHOUSE = 2 * [
    "/Isaac/Environments/Simple_Warehouse/Props/S_TrafficCone.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/S_WetFloorSign.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_BarelPlastic_A_01.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_BarelPlastic_A_02.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_BarelPlastic_A_03.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_BarelPlastic_B_01.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_BarelPlastic_B_01.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_BarelPlastic_B_03.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_BarelPlastic_C_02.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_BottlePlasticA_02.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_BottlePlasticB_01.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_BottlePlasticA_02.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_BottlePlasticA_02.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_BottlePlasticD_01.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_BottlePlasticE_01.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_BucketPlastic_B.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_CardBoxB_01_1262.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_CardBoxB_01_1268.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_CardBoxB_01_1482.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_CardBoxB_01_1683.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_CardBoxB_01_291.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_CardBoxD_01_1454.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_CardBoxD_01_1513.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_CratePlastic_A_04.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_CratePlastic_B_03.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_CratePlastic_B_05.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_CratePlastic_C_02.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_CratePlastic_E_02.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_PushcartA_02.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_RackPile_04.usd",
    "/Isaac/Environments/Simple_Warehouse/Props/SM_RackPile_03.usd",
]

DISTRACTORS_ADDITIONAL = [
    "/Isaac/Environments/Hospital/Props/Pharmacy_Low.usd",
    "/Isaac/Environments/Hospital/Props/SM_BedSideTable_01b.usd",
    "/Isaac/Environments/Hospital/Props/SM_BooksSet_26.usd",
    "/Isaac/Environments/Hospital/Props/SM_BottleB.usd",
    "/Isaac/Environments/Hospital/Props/SM_BottleA.usd",
    "/Isaac/Environments/Hospital/Props/SM_BottleC.usd",
    "/Isaac/Environments/Hospital/Props/SM_Cart_01a.usd",
    "/Isaac/Environments/Hospital/Props/SM_Chair_02a.usd",
    "/Isaac/Environments/Hospital/Props/SM_Chair_01a.usd",
    "/Isaac/Environments/Hospital/Props/SM_Computer_02b.usd",
    "/Isaac/Environments/Hospital/Props/SM_Desk_04a.usd",
    "/Isaac/Environments/Hospital/Props/SM_DisposalStand_02.usd",
    "/Isaac/Environments/Hospital/Props/SM_FirstAidKit_01a.usd",
    "/Isaac/Environments/Hospital/Props/SM_GasCart_01c.usd",
    "/Isaac/Environments/Hospital/Props/SM_Gurney_01b.usd",
    "/Isaac/Environments/Hospital/Props/SM_HospitalBed_01b.usd",
    "/Isaac/Environments/Hospital/Props/SM_MedicalBag_01a.usd",
    "/Isaac/Environments/Hospital/Props/SM_Mirror.usd",
    "/Isaac/Environments/Hospital/Props/SM_MopSet_01b.usd",
    "/Isaac/Environments/Hospital/Props/SM_SideTable_02a.usd",
    "/Isaac/Environments/Hospital/Props/SM_SupplyCabinet_01c.usd",
    "/Isaac/Environments/Hospital/Props/SM_SupplyCart_01e.usd",
    "/Isaac/Environments/Hospital/Props/SM_TrashCan.usd",
    "/Isaac/Environments/Hospital/Props/SM_Washbasin.usd",
    "/Isaac/Environments/Hospital/Props/SM_WheelChair_01a.usd",
    "/Isaac/Environments/Office/Props/SM_WaterCooler.usd",
    "/Isaac/Environments/Office/Props/SM_TV.usd",
    "/Isaac/Environments/Office/Props/SM_TableC.usd",
    "/Isaac/Environments/Office/Props/SM_Recliner.usd",
    "/Isaac/Environments/Office/Props/SM_Personenleitsystem_Red1m.usd",
    "/Isaac/Environments/Office/Props/SM_Lamp02_162.usd",
    "/Isaac/Environments/Office/Props/SM_Lamp02.usd",
    "/Isaac/Environments/Office/Props/SM_HandDryer.usd",
    "/Isaac/Environments/Office/Props/SM_Extinguisher.usd",
]

# Random floor/wall textures (unchanged)
TEXTURES = [
    "/Isaac/Materials/Textures/Patterns/nv_asphalt_yellow_weathered.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_tile_hexagonal_green_white.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_rubber_woven_charcoal.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_granite_tile.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_tile_square_green.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_marble.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_brick_reclaimed.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_concrete_aged_with_lines.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_wooden_wall.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_stone_painted_grey.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_wood_shingles_brown.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_tile_hexagonal_various.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_carpet_abstract_pattern.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_wood_siding_weathered_green.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_animalfur_pattern_greys.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_artificialgrass_green.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_bamboo_desktop.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_brick_reclaimed.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_brick_red_stacked.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_fireplace_wall.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_fabric_square_grid.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_granite_tile.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_marble.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_gravel_grey_leaves.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_plastic_blue.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_stone_red_hatch.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_stucco_red_painted.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_rubber_woven_charcoal.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_stucco_smooth_blue.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_wood_shingles_brown.jpg",
    "/Isaac/Materials/Textures/Patterns/nv_wooden_wall.jpg",
]

def get_local_material_files():
    """Return list of local USD material file paths that exist, if any."""
    names = [
        "Aluminum_Brushed.Material.usd",
        "Stainless_Steel_Shiny_Smudged.Material.usd",
        "Steel_Carbon.Material.usd",
        "Stainless_Steel_Cast_Shiny.Material.usd",
    ]
    paths = []
    seen = set()
    for mat_dir in LOCAL_MATERIAL_DIRS:
        if not os.path.isdir(mat_dir):
            continue
        for n in names:
            p = os.path.join(mat_dir, n)
            if os.path.isfile(p) and p not in seen:
                paths.append(p)
                seen.add(p)
            else:
                # Defer logging until carb is available in main(); keep track of missing
                pass
    return paths

# === Online MDL materials to include as well ===
ONLINE_MDL_URLS = [
    "https://omniverse-content-production.s3.us-west-2.amazonaws.com/Materials/2023_1/Base/Metals/Cast_Metal_Silver_Vein.mdl",
    "http://omniverse-content-production.s3.us-west-2.amazonaws.com/Materials/2023_1/Base/Metals/Aluminum_Polished.mdl",
    "http://omniverse-content-production.s3.us-west-2.amazonaws.com/Materials/2023_1/Base/Metals/Steel_Stainless.mdl",
    "http://omniverse-content-production.s3.us-west-2.amazonaws.com/Materials/2023_1/Base/Metals/Copper.mdl",
]

# ---------- helpers ----------

def normalize_asset_path(p: str) -> str:
    """Return a path usable by USD regardless of current stage root."""
    p = os.path.expanduser(p)
    if p.startswith(("file://", "omniverse://", "http://", "https://")):
        return p
    if os.path.isabs(p):
        return "file://" + p
    return p


def update_semantics(stage, keep_semantics=[]):
    """Remove semantics from the stage except for keep_semantic classes."""
    for prim in stage.Traverse():
        if prim.HasAPI(Semantics.SemanticsAPI):
            processed_instances = set()
            for prop in prim.GetProperties():
                if not Semantics.SemanticsAPI.IsSemanticsAPIPath(prop.GetPath()):
                    continue
                instance_name = prop.SplitName()[1]
                if instance_name in processed_instances:
                    continue
                processed_instances.add(instance_name)
                sem = Semantics.SemanticsAPI.Get(prim, instance_name)
                type_attr = sem.GetSemanticTypeAttr()
                data_attr = sem.GetSemanticDataAttr()
                keep = False
                for semantic_class in keep_semantics:
                    if data_attr.Get() == semantic_class:
                        keep = True
                        break
                if not keep:
                    prim.RemoveProperty(type_attr.GetName())
                    prim.RemoveProperty(data_attr.GetName())
                    prim.RemoveAPI(Semantics.SemanticsAPI, instance_name)


def prefix_with_isaac_asset_server(relative_path: str) -> str:
    assets_root_path = get_assets_root_path()
    if assets_root_path is None:
        raise Exception("Nucleus server not found, could not access Isaac Sim assets folder")
    return assets_root_path + relative_path


def full_distractors_list(distractor_type="warehouse"):
    full_dist_list = []
    if distractor_type == "warehouse":
        for d in DISTRACTORS_WAREHOUSE:
            full_dist_list.append(prefix_with_isaac_asset_server(d))
    elif distractor_type == "additional":
        for d in DISTRACTORS_ADDITIONAL:
            full_dist_list.append(prefix_with_isaac_asset_server(d))
    else:
        print("No Distractors being added to the current scene for SDG")
    return full_dist_list


def full_textures_list():
    return [prefix_with_isaac_asset_server(t) for t in TEXTURES]


def add_custom_objects():
    """Spawn via Replicator first; if nothing appears, fall back to USD references under /World."""
    stage = get_current_stage()
    asset_paths = [normalize_asset_path(p) for p in get_custom_asset_paths()]

    # Warn early if the asset file is missing
    for ap in asset_paths:
        ap_fs = ap.replace("file://", "") if ap.startswith("file://") else ap
        if ap.startswith("http") or ap.startswith("omniverse://"):
            continue
        if not os.path.isfile(ap_fs):
            carb.log_warn(f"[SDG] Model USD not found at {ap_fs}. The object may fail to spawn.")

    rep_obj_list = [
        rep.create.from_usd(p, semantics=[("class", OBJECT_CLASS)], count=100) for p in asset_paths
    ]
    rep_custom_group = rep.create.group(rep_obj_list)

    for _ in range(10):
        simulation_app.update()

    found_replicator_instances = False
    for prim in stage.Traverse():
        if str(prim.GetPath()).startswith("/Replicator/Ref_Xform"):
            found_replicator_instances = True
            break

    if found_replicator_instances:
        carb.log_info("[SDG] Spawned via Replicator (Ref_Xform found).")
        return rep_custom_group

    carb.log_warn("[SDG] Replicator instances not found; falling back to USD references under /World.")
    total = max(1, FALLBACK_COUNT * len(asset_paths))
    src = asset_paths[0]
    for i in range(total):
        path = f"/World/{OBJECT_PRIM_PREFIX}_{i:02d}"
        xform = UsdGeom.Xform.Define(stage, Sdf.Path(path))
        prim = xform.GetPrim()
        prim.GetReferences().ClearReferences()
        prim.GetReferences().AddReference(src)
        sem = Semantics.SemanticsAPI.Apply(prim, f"{OBJECT_CLASS}_sem")
        sem.GetSemanticTypeAttr().Set("class")
        sem.GetSemanticDataAttr().Set(OBJECT_CLASS)

    for _ in range(10):
        simulation_app.update()

    return rep.get.prims(path_pattern=f"/World/{OBJECT_PRIM_PREFIX}_*")


def add_distractors(distractor_type="warehouse"):
    full_distractors = full_distractors_list(distractor_type)
    distractors = [rep.create.from_usd(path, count=1) for path in full_distractors]
    return rep.create.group(distractors)


def run_orchestrator():
    rep.orchestrator.run()
    while not rep.orchestrator.get_is_started():
        simulation_app.update()
    while rep.orchestrator.get_is_started():
        simulation_app.update()
    rep.BackendDispatch.wait_until_done()
    rep.orchestrator.stop()


# ---------- material helpers ----------

def ensure_looks_scope(scope_path: str = "/World/Looks"):
    stage = get_current_stage()
    if not stage.GetPrimAtPath(scope_path):
        UsdGeom.Scope.Define(stage, Sdf.Path(scope_path))


def make_mdl_material(mdl_url: str, material_name: str, looks_scope: str = "/World/Looks") -> str:
    """
    Create a USD MDL Material prim and return its path (string).
    Uses CreateMdlMaterialPrimCommand (Kit/Isaac Sim 5.0).
    """
    ensure_looks_scope(looks_scope)
    mat_path = f"{looks_scope}/{material_name}"
    stage = get_current_stage()
    if stage.GetPrimAtPath(mat_path):
        carb.log_info(f"[SDG] Reusing existing MDL material at {mat_path}")
        return mat_path

    try:
        import omni.kit.commands
        omni.kit.commands.execute(
            "CreateMdlMaterialPrimCommand",
            mtl_url=mdl_url,
            mtl_name=material_name,
            mtl_path=mat_path,
        )
        carb.log_info(f"[SDG] Created MDL material: {material_name} from {mdl_url}")
    except Exception as exc:
        carb.log_error(f"[SDG] Failed to create MDL material {material_name}: {exc}")
        return ""
    return mat_path


def import_usd_material(material_usd_path: str, looks_scope: str = "/World/Looks", prim_hint: str = None) -> str:
    """
    Import a UsdShade.Material from a local USD file into the stage under looks_scope.
    Returns the new material prim path (e.g. /World/Looks/Aluminum_Brushed).
    If prim_hint is provided, it is used as the path INSIDE the source file.
    """
    stage = get_current_stage()
    ensure_looks_scope(looks_scope)
    file_url = normalize_asset_path(material_usd_path)

    # open source stage to find a UsdShade.Material prim if no hint
    internal_mat_path = prim_hint
    if internal_mat_path is None:
        src = Usd.Stage.Open(file_url)
        if not src:
            carb.log_error(f"[SDG] Cannot open material file: {file_url}")
            return ""
        dp = src.GetDefaultPrim()
        if dp and dp.IsA(UsdShade.Material):
            internal_mat_path = dp.GetPath().pathString
        else:
            for p in src.Traverse():
                if p.IsA(UsdShade.Material):
                    internal_mat_path = p.GetPath().pathString
                    break
        if internal_mat_path is None:
            carb.log_error(f"[SDG] No UsdShade.Material found in {file_url}")
            return ""

    base = os.path.splitext(os.path.basename(material_usd_path))[0]
    if base.endswith(".Material"):
        base = base[:-9]
    mat_path = f"{looks_scope}/{base}"

    if get_current_stage().GetPrimAtPath(mat_path):
        carb.log_info(f"[SDG] Material {mat_path} already exists, reusing.")
        return mat_path

    # Create a Material prim that references the source material prim inside the .usd
    material = UsdShade.Material.Define(get_current_stage(), Sdf.Path(mat_path))
    mprim = get_current_stage().GetPrimAtPath(mat_path)
    mprim.GetReferences().ClearReferences()
    mprim.GetReferences().AddReference(file_url, internal_mat_path)
    carb.log_info(f"[SDG] Imported USD material {base} from {file_url} (prim {internal_mat_path}) to {mat_path}")
    return mat_path


def _find_model_bind_targets():
    """
    Find prims to bind the material to.
    Prefer binding on '/Replicator/Ref_Xform_*/Ref' so it cascades to children.
    Fall back to '/World/<prefix>_*' if we used the manual USD reference path.
    """
    stage = get_current_stage()
    targets = []

    for prim in stage.Traverse():
        p = str(prim.GetPath())
        # prefer the 'Ref' prim placed by Replicator (it holds the reference to the asset)
        if p.startswith("/Replicator/Ref_Xform") and p.endswith("/Ref"):
            targets.append(p)

    if not targets:
        world_prefix = f"/World/{OBJECT_PRIM_PREFIX}_"
        for prim in stage.Traverse():
            p = str(prim.GetPath())
            if p.startswith(world_prefix):
                targets.append(p)

    return targets


def assign_random_materials_to_targets(material_paths):
    """
    Given a list of material prim paths (in-stage, e.g. '/World/Looks/Aluminum_Brushed'),
    assign randomly one to each model target prim (once). This keeps materials constant during a run.
    """
    if not material_paths:
        carb.log_warn("[SDG] No material paths supplied for assignment.")
        return

    stage = get_current_stage()
    targets = _find_model_bind_targets()
    if not targets:
        carb.log_warn("[SDG] No targets found to bind materials.")
        return

    # For each target, pick a random material and bind using UsdShade
    for t in targets:
        chosen = random.choice(material_paths)
        mat = UsdShade.Material.Get(stage, Sdf.Path(chosen))
        if not mat:
            carb.log_warn(f"[SDG] Material not found in stage: {chosen}; skipping target {t}")
            continue
        UsdShade.MaterialBindingAPI(stage.GetPrimAtPath(t)).Bind(mat, UsdShade.Tokens.strongerThanDescendants)
    carb.log_info(f"[SDG] Assigned {len(material_paths)} materials randomly to {len(targets)} targets.")


# ---------- main ----------

def main():
    print(f"Loading Stage {ENV_URL}")
    open_stage(prefix_with_isaac_asset_server(ENV_URL))
    stage = get_current_stage()

    # Allow environment to finish loading
    for i in range(100):
        if i % 10 == 0:
            print(f"App update {i}..")
        simulation_app.update()

    textures = full_textures_list()
    rep_custom_group = add_custom_objects()
    rep_distractor_group = add_distractors(distractor_type=args.distractors)

    # Keep only the requested object semantics
    update_semantics(stage=stage, keep_semantics=[OBJECT_CLASS])

    # Camera
    cam = rep.create.camera(clipping_range=(0.1, 1_000_000))

    # ---- Import & create materials (once) ----
    material_prim_paths = []

    # Import local USD materials (if present) and add them to the list
    local_material_files = get_local_material_files()

    if LOCAL_MATERIAL_DIRS and not local_material_files:
        locations = ", ".join(LOCAL_MATERIAL_DIRS)
        carb.log_warn(
            f"[SDG] No expected local material USD files found under {locations}. Skipping local materials."
        )

    for local_file in local_material_files:
        try:
            mp = import_usd_material(local_file)
            if mp:
                material_prim_paths.append(mp)
        except Exception as e:
            carb.log_error(f"[SDG] Error importing local material {local_file}: {e}")

    # Create MDL materials from online MDL URLs and add them
    for mdlu in ONLINE_MDL_URLS:
        mdl_name = os.path.splitext(os.path.basename(mdlu))[0]
        try:
            mdl_prim_path = make_mdl_material(mdlu, mdl_name)
            if mdl_prim_path:
                material_prim_paths.append(mdl_prim_path)
        except Exception as e:
            carb.log_warn(f"[SDG] Could not create MDL material for {mdlu}: {e}")

    # wait a little for USD composition to settle
    for _ in range(10):
        simulation_app.update()

    # assign one random material from the combined set to each instance (keeps constant during run)
    if material_prim_paths:
        assign_random_materials_to_targets(material_prim_paths)
    else:
        carb.log_warn("[SDG] No materials were successfully created/imported; continuing without material binding.")

    # ---- Replicator trigger ----
    # use max_execs (num_frames)
    with rep.trigger.on_frame(max_execs=CONFIG["num_frames"]):

        # Camera motion
        with cam:
            rep.modify.pose(
                position=rep.distribution.uniform((-0.75, -0.75, 0.5), (0.75, 0.75, 1.0)),
                look_at=(0, 0, 0),
            )

        # Object pose randomization (fixed scale 0.01)
        with rep_custom_group:
            rep.modify.pose(
                position=rep.distribution.uniform((-0.3, -0.2, 0.02), (0.3, 0.2, 0.35)),
                rotation=rep.distribution.uniform((0, -45, 0), (0, 45, 360)),
                scale=rep.distribution.uniform((0.01, 0.01, 0.01), (0.01, 0.01, 0.01)),
            )

        # Distractors (if any)
        if args.distractors != "None":
            with rep_distractor_group:
                rep.modify.pose(
                    position=rep.distribution.uniform((-6, -6, 0), (6, 12, 0)),
                    rotation=rep.distribution.uniform((0, 0, 0), (0, 0, 360)),
                    scale=rep.distribution.uniform(1, 1.5),
                )

        # Lighting randomization
        with rep.get.prims(path_pattern="RectLight"):
            rep.modify.attribute("color", rep.distribution.uniform((0, 0, 0), (1, 1, 1)))
            rep.modify.attribute("intensity", rep.distribution.normal(300_000.0, 700_000.0))
            rep.modify.visibility(rep.distribution.choice([True, False, False, False, False, False, False]))

        # Floor & wall materials (OmniPBR)
        random_mat_floor = rep.create.material_omnipbr(
            diffuse_texture=rep.distribution.choice(textures),
            roughness=rep.distribution.uniform(0, 1),
            metallic=rep.distribution.choice([0, 1]),
            emissive_texture=rep.distribution.choice(textures),
            emissive_intensity=rep.distribution.uniform(0, 1000),
        )
        with rep.get.prims(path_pattern="SM_Floor"):
            rep.randomizer.materials(random_mat_floor)

        random_mat_wall = rep.create.material_omnipbr(
            diffuse_texture=rep.distribution.choice(textures),
            roughness=rep.distribution.uniform(0, 1),
            metallic=rep.distribution.choice([0, 1]),
            emissive_texture=rep.distribution.choice(textures),
            emissive_intensity=rep.distribution.uniform(0, 1000),
        )
        with rep.get.prims(path_pattern="SM_Wall"):
            rep.randomizer.materials(random_mat_wall)

    # Writer (COCO for YOLOv8)
    writer = rep.WriterRegistry.get("CocoWriter")
    output_directory = args.data_dir
    print("Outputting data to ", output_directory)

    # COCO category mapping — ids should be unique & positive
    coco_categories = {
        OBJECT_CLASS: {"id": 1, "name": OBJECT_CLASS, "color": [255, 0, 0]}
    }

    writer.initialize(
        output_dir=output_directory,
        categories=coco_categories,
        # turn on what you need:
        write_rgb=True,
        write_bbox_2d_tight=True,
        # optional toggles:
        # write_bbox_2d_loose=False,
        write_semantic=True,   # set True if you also want per-pixel semantic masks
        write_instance=True,   # set True if you also want instance masks (for instance/seg models)
    )

    RESOLUTION = (CONFIG["width"], CONFIG["height"])
    render_product = rep.create.render_product(cam, RESOLUTION)
    writer.attach(render_product)

    # Run
    run_orchestrator()
    simulation_app.update()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        carb.log_error(f"Exception: {e}")
        import traceback
        traceback.print_exc()
    finally:
        simulation_app.close()

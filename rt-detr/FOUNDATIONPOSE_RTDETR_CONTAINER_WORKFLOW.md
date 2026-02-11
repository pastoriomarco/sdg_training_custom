# TAO RT-DETR to FoundationPose-Compatible RT-DETR (Container-Only Workflow)

This guide converts a TAO-trained RT-DETR `.pth` checkpoint into an Isaac/FoundationPose-compatible TensorRT engine.

Target tensor interface required by Isaac Manipulator RT-DETR pipeline:
- inputs: `images`, `orig_target_sizes`
- outputs: `labels`, `boxes`, `scores`

Your checkpoints are expected in:
- `$ISAAC_ROS_WS/isaac_ros_assets/models/rt_detr_custom`

---

## 1) Host Shell (outside containers): set paths

```bash
export ISAAC_ROS_WS=/home/tndlux/workspaces/isaac_ros-dev
export SDG_WS=/home/tndlux/workspaces/sdg
export RTDETR_ASSETS=$ISAAC_ROS_WS/isaac_ros_assets/models/rt_detr_custom
```

Optional: avoid confusion with previous incompatible artifacts.

```bash
mv -n $RTDETR_ASSETS/model.onnx $RTDETR_ASSETS/model_raw_pred.onnx
mv -n $RTDETR_ASSETS/model.plan $RTDETR_ASSETS/model_raw_pred.plan
```

---

## 2) TAO Container: checkpoint conversion + ONNX export

Pull image (host shell, once):

```bash
docker pull nvcr.io/nvidia/tao/tao-toolkit:6.25.11-pyt
```

Start TAO container (host shell):

```bash
docker run --rm -it --gpus all \
  --shm-size=16g --ulimit memlock=-1 --ulimit stack=67108864 \
  -v "$ISAAC_ROS_WS:/workspace/isaac_ros_ws" \
  -v "$SDG_WS:/workspace/sdg_ws" \
  nvcr.io/nvidia/tao/tao-toolkit:6.25.11-pyt bash
```

Inside TAO container: install export deps + clone RT-DETR exporter code.

```bash
python3 -m pip install --no-cache-dir onnx onnxsim
mkdir -p /workspace/isaac_ros_ws/third_party
[ -d /workspace/isaac_ros_ws/third_party/RT-DETR ] || \
  git clone https://github.com/lyuwenyu/RT-DETR.git /workspace/isaac_ros_ws/third_party/RT-DETR
```

Inside TAO container: choose TAO checkpoint and convert key format for upstream exporter.

```bash
export RTDETR_ASSETS=/workspace/isaac_ros_ws/isaac_ros_assets/models/rt_detr_custom
export TAO_PTH=$RTDETR_ASSETS/rtdetr_model_latest.pth
# Alternative:
# export TAO_PTH=$RTDETR_ASSETS/model_epoch_079.pth
```

```bash
python3 - <<'PY'
import os, torch
in_ckpt = os.environ["TAO_PTH"]
out_ckpt = os.path.join(os.environ["RTDETR_ASSETS"], "rtdetr_for_export.pth")

ckpt = torch.load(in_ckpt, map_location="cpu")
src = ckpt.get("state_dict") or ckpt.get("model") or ((ckpt.get("ema") or {}).get("module"))
if src is None:
    raise RuntimeError(f"Unsupported checkpoint keys: {list(ckpt.keys())}")

converted = {}
for k, v in src.items():
    if k.startswith("model.model."):
        nk = k[len("model.model."):]
    elif k.startswith("model."):
        nk = k[len("model."):]
    else:
        nk = k
    converted[nk] = v

torch.save({"model": converted}, out_ckpt)
print("Saved:", out_ckpt, "params:", len(converted))
PY
```

Inside TAO container: generate export config matching TAO architecture.

```bash
export NUM_CLASSES=$(awk '/^  num_classes:/{print $2; exit}' \
  /workspace/sdg_ws/src/sdg_training_custom/rt-detr/rtdetr_train.yaml)
```

```bash
cat > /workspace/isaac_ros_ws/third_party/RT-DETR/rtdetr_pytorch/configs/rtdetr/rtdetr_r50vd_6x_tao_custom.yml <<EOF
__include__: [
  '../dataset/coco_detection.yml',
  '../runtime.yml',
  './include/dataloader.yml',
  './include/optimizer.yml',
  './include/rtdetr_r50vd.yml',
]
num_classes: ${NUM_CLASSES}
remap_mscoco_category: False
use_focal_loss: True
output_dir: ./output/rtdetr_r50vd_6x_tao_custom
EOF
```

Inside TAO container: export ONNX in Isaac-compatible format.

```bash
cd /workspace/isaac_ros_ws/third_party/RT-DETR/rtdetr_pytorch
python3 tools/export_onnx.py \
  -c configs/rtdetr/rtdetr_r50vd_6x_tao_custom.yml \
  -r /workspace/isaac_ros_ws/isaac_ros_assets/models/rt_detr_custom/rtdetr_for_export.pth \
  -f /workspace/isaac_ros_ws/isaac_ros_assets/models/rt_detr_custom/model_isaac.onnx \
  --check
```

Inside TAO container: verify tensor names.

```bash
python3 - <<'PY'
import onnx
m = onnx.load("/workspace/isaac_ros_ws/isaac_ros_assets/models/rt_detr_custom/model_isaac.onnx")
print("inputs :", [i.name for i in m.graph.input])
print("outputs:", [o.name for o in m.graph.output])
PY
```

Expected:
- inputs: `['images', 'orig_target_sizes']`
- outputs: `['labels', 'boxes', 'scores']`

Exit TAO container when done.

---

## 3) Isaac ROS Container: build TensorRT engine

Run this where `trtexec` is available (typically your Isaac ROS dev container):

```bash
export ISAAC_ROS_WS=/home/tndlux/workspaces/isaac_ros-dev

trtexec \
  --onnx=$ISAAC_ROS_WS/isaac_ros_assets/models/rt_detr_custom/model_isaac.onnx \
  --saveEngine=$ISAAC_ROS_WS/isaac_ros_assets/models/rt_detr_custom/model_isaac.plan \
  --fp16 \
  --minShapes=images:1x3x640x640,orig_target_sizes:1x2 \
  --optShapes=images:1x3x640x640,orig_target_sizes:1x2 \
  --maxShapes=images:1x3x640x640,orig_target_sizes:1x2
```

---

## 4) Isaac ROS Container: launch with FoundationPose pipeline

```bash
source /opt/ros/jazzy/setup.bash
source $ISAAC_ROS_WS/install/setup.bash

ros2 launch isaac_manipulator_pose_server perception_scan_server.launch.py \
  object_detection_model:=RT_DETR \
  rtdetr_engine_file_path:=$ISAAC_ROS_WS/isaac_ros_assets/models/rt_detr_custom/model_isaac.plan
```

---

## Notes

- Use `model_isaac.onnx` and `model_isaac.plan` for RT-DETR + FoundationPose.
- Older artifacts like `model.onnx`/`model.plan` in this folder may be raw-output format (`inputs -> pred_logits,pred_boxes`) and are not compatible with the default RT-DETR launch in Isaac Manipulator.

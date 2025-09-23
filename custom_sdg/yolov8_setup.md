# YOLOv8 Environment Setup and Installation

These are the steps that worked successfully to set up YOLOv8 training and export on a system with NVIDIA drivers, CUDA 12.8, Isaac Sim, ROS 2 Humble, and Conda.

---

## 1. Create and Activate Conda Environment

```bash
conda create -n yolov8 python=3.10 -y
conda activate yolov8
```

---

## 2. Install GPU PyTorch with CUDA 12.1

```bash
conda install -y -c pytorch -c nvidia pytorch torchvision pytorch-cuda=12.1
```

---

## 3. Upgrade pip

```bash
pip3 install --upgrade pip
```

---

## 4. Install Ultralytics and Supporting Packages

```bash
pip3 install ultralytics
python -m pip install --upgrade pip
python -m pip install ultralytics onnx onnxruntime-gpu netron opencv-python pycocotools matplotlib tqdm
```

---

## 5. Quick Check

```bash
python - << 'PY'
import torch, ultralytics
print("PyTorch:", torch.__version__)
print("CUDA available:", torch.cuda.is_available())
print("CUDA runtime:", torch.version.cuda)
print("Ultralytics:", ultralytics.__version__)
PY
```

If this shows CUDA available = True, the setup is complete.

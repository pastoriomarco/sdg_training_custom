# coco2yolo.py
import json, os, sys
from pathlib import Path
from collections import defaultdict

root = Path(sys.argv[1])  # /home/tndlux/synthetic_out
splits = ["train","val","test"]

def load_json(split):
    js = next((root/split).glob("coco_*.json"), None)
    if js is None:
        print(f"[WARN] No COCO json in {split}, skipping.")
        return None
    return json.load(open(js))

def write_label(txt_path, W, H, anns, cat2yolo):
    lines=[]
    for a in anns:
        if a.get("iscrowd",0): continue
        x,y,w,h = a["bbox"]
        cx,cy,nw,nh = (x+w/2)/W, (y+h/2)/H, w/W, h/H
        cid = cat2yolo[a["category_id"]]
        cx=max(0,min(1,cx)); cy=max(0,min(1,cy)); nw=max(0,min(1,nw)); nh=max(0,min(1,nh))
        lines.append(f"{cid} {cx:.6f} {cy:.6f} {nw:.6f} {nh:.6f}")
    txt_path.write_text("\n".join(lines))

for split in splits:
    data = load_json(split)
    if not data: continue
    images = {im["id"]:im for im in data["images"]}
    by_img = defaultdict(list)
    for a in data["annotations"]:
        by_img[a["image_id"]].append(a)

    # map COCO category ids to 0..N-1 (YOLO ids)
    cats = sorted([c["id"] for c in data["categories"]])
    cat2yolo = {cid:i for i,cid in enumerate(cats)}

    img_dir  = root/"images"/split
    lab_dir  = root/"labels"/split
    lab_dir.mkdir(parents=True, exist_ok=True)

    # index by basename for match
    name2img = {os.path.basename(im.get("file_name", im.get("coco_url",""))):im for im in data["images"]}

    for img_path in img_dir.iterdir():
        if not img_path.is_file(): continue
        im = name2img.get(img_path.name)
        txt = lab_dir/(img_path.stem + ".txt")
        if im is None:
            txt.write_text("")  # no annotations
            continue
        anns = by_img.get(im["id"], [])
        write_label(txt, im["width"], im["height"], anns, cat2yolo)

print("Done. Check labels/ for .txt files.")

import sys, json
from PIL import Image
import numpy as np
src=sys.argv[1]
meta=json.load(open(f"{src}/sprites.json"))
piv=tuple(meta["legs_turn"]["pivot"]); print("pivot", piv, meta["legs_turn"]["size"])
last=np.array(Image.open(f"{src}/legs_turn_15.png").convert("RGBA"))[...,3]>40
first=np.array(Image.open(f"{src}/legs_turn_00.png").convert("RGBA"))[...,3]>40
idle=Image.open(f"{src}/legs_idle_00.png").convert("RGBA")
def iou(a,b): return (a&b).sum()/max(1,(a|b).sum())
best=[]
for th in range(0,121,2):
    r=idle.rotate(-th, center=piv, resample=Image.BICUBIC)
    m=np.array(r)[...,3]>40
    best.append((iou(last,m),th,iou(first,m)))
b=max(best); print("last matches idle rotated cw by", b[1], "iou", round(b[0],2))
print("first frame vs unrotated idle iou", round(max(x[2] for x in best if x[1]==0),2))

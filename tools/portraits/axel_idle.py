import sys
import numpy as np
from PIL import Image, ImageFilter, ImageEnhance
import cv2
D, model = sys.argv[1], sys.argv[2]
src = Image.open(D + "/axel_idle_raw.png").convert("RGB")
W, H = src.size
a = np.asarray(src).astype(np.float32)
B = 12
# the AXEL lettering: saturated red strokes in the lower left (not the frame)
red = a[..., 0] - np.maximum(a[..., 1], a[..., 2])
txt = np.clip((red - 70.0) / 70.0, 0, 1)
txt[:int(H * 0.72)] = 0; txt[:, :B + 2] = 0; txt[:, -B - 2:] = 0; txt[-B - 2:] = 0
txt[:, int(W * 0.72):] = 0
# closer on him: head to below the belt, the same panel shape
cw = int(W * 0.54); ch = int(cw * H / W)
cx = W // 2; y0 = 140
box = (cx - cw // 2, y0, cx + cw // 2, y0 + ch)
crop = cv2.cvtColor(np.asarray(src.crop(box)), cv2.COLOR_RGB2BGR)
sr = cv2.dnn_superres.DnnSuperResImpl_create(); sr.readModel(model); sr.setModel("edsr", 4)
big = Image.fromarray(cv2.cvtColor(sr.upsample(crop), cv2.COLOR_BGR2RGB)).resize((W, H), Image.LANCZOS)
big = ImageEnhance.Brightness(big).enhance(1.12)
big = ImageEnhance.Contrast(big).enhance(1.06)
out = np.asarray(big).astype(np.float32)
# lettering back on top with a dark shadow under it
m = txt[..., None]
sh = np.asarray(Image.fromarray((txt * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(4)), np.float32)[..., None] / 255.0
out = out * (1 - sh * 0.75)
out = out * (1 - m) + a * m
# the original red frame
out[:B] = a[:B]; out[-B:] = a[-B:]; out[:, :B] = a[:, :B]; out[:, -B:] = a[:, -B:]
Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(D + "/axel_idle_fixed.png")
print("saved", box)

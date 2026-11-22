"""Take the red name lettering off a portrait panel and paint the picture back in under it with LaMa
(big-lama, ONNX with dynamic size: github.com/CloudyTabzy/LaMa-OxiONNX release model-lama-fp32-v1).
   unletter.py <work> <car> <lama.onnx> x0 y0 x1 y1 [keep_x0]
Reads <work>/<car>_idle_raw.png, writes <work>/<car>_idle_clean.png and <car>_idle_letters.png (the red fill that
was there: the source of the owner's own letters)."""
import sys
import numpy as np
import cv2
import onnxruntime as ort
from PIL import Image

W, car, model = sys.argv[1], sys.argv[2], sys.argv[3]
x0, y0, x1, y1 = map(int, sys.argv[4:8])
src = Image.open("%s/%s_idle_raw.png" % (W, car)).convert("RGB")
a = np.asarray(src).astype(np.float32)
H, Wd = a.shape[:2]
red = a[..., 0] - np.maximum(a[..., 1], a[..., 2])
fill = ((red > 26) & (a[..., 0] > 48)).astype(np.uint8)
box = np.zeros_like(fill); box[y0:y1, x0:x1] = 1
fill &= box
fill = cv2.morphologyEx(fill, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
n, lab, st, _ = cv2.connectedComponentsWithStats(fill, 8)
for i in range(1, n):  # specks are art, not lettering
    if st[i, 4] < 60:
        fill[lab == i] = 0
Image.fromarray(fill * 255).save("%s/%s_idle_letters.png" % (W, car))
hole = cv2.dilate(fill, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (19, 19)))  # the black outline + its soft edge
# LaMa on a padded crop around the lettering, sides a multiple of 8
ys, xs = np.nonzero(hole)
cx0 = max(0, xs.min() - 48); cy0 = max(0, ys.min() - 48); cx1 = min(Wd, xs.max() + 48); cy1 = min(H, ys.max() + 48)
img = a[cy0:cy1, cx0:cx1] / 255.0
m = hole[cy0:cy1, cx0:cx1].astype(np.float32)
ch, cw = m.shape
ph = -ch % 64; pw = -cw % 64  # the FFT blocks want sides in multiples of 64: mirror-pad, crop after
img_p = np.pad(img, ((0, ph), (0, pw), (0, 0)), mode="reflect")
m_p = np.pad(m, ((0, ph), (0, pw)), mode="reflect")
sess = ort.InferenceSession(model, providers=["CPUExecutionProvider"])
ins = sess.get_inputs()
feed = {ins[0].name: img_p.transpose(2, 0, 1)[None].astype(np.float32), ins[1].name: m_p[None, None]}
out = sess.run(None, feed)[0][0].transpose(1, 2, 0)[:ch, :cw]
if out.max() <= 1.5:
    out = out * 255.0
res = a.copy()
mm = cv2.GaussianBlur(m, (0, 0), 1.5)[..., None]
res[cy0:cy1, cx0:cx1] = a[cy0:cy1, cx0:cx1] * (1 - mm) + out * mm
Image.fromarray(np.clip(res, 0, 255).astype(np.uint8)).save("%s/%s_idle_clean.png" % (W, car))
print(car, "lettering out", (cx0, cy0, cx1, cy1), "hole px", int(hole.sum()))

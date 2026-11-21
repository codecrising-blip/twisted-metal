import sys
import numpy as np
from PIL import Image, ImageFilter
D = sys.argv[1]
idle = np.asarray(Image.open(D + "/roadkill_idle_raw.png").convert("RGB")).astype(np.float32)
im = np.asarray(Image.open(D + "/" + "roadkill_idle_mask.png").convert("L")).astype(np.float32) / 255.0
sel = Image.open(D + "/roadkill_select_raw.png").convert("RGB")
sm = Image.open(D + "/roadkill_select_mask_anime.png").convert("L")
W, H = sel.size
B = 12  # the red frame is kept from the original
# background-only pixels of the idle: far from the figure, inside the frame, above the name lettering
fig = np.asarray(Image.fromarray((im * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(41))) > 20
ok = ~fig
ok[:B + 4, :] = False; ok[-int(H * 0.22):, :] = False; ok[:, :B + 4] = False; ok[:, -B - 4:] = False
rng = np.random.default_rng(5)
P = 120
cand = [(y, x) for y in range(0, idle.shape[0] - P, 6) for x in range(0, idle.shape[1] - P, 6) if ok[y:y + P, x:x + P].mean() > 0.97]
print("patches", len(cand))
out = np.zeros((H, W, 3), np.float32); wsum = np.zeros((H, W, 1), np.float32)
ramp = np.minimum(np.linspace(0, 1, P), np.linspace(1, 0, P)) * 2
win = np.clip(np.outer(ramp, ramp), 0.02, 1)[..., None]
step = int(P * 0.62)
for y in range(-step, H, step):
    for x in range(-step, W, step):
        cy, cx = cand[rng.integers(len(cand))]
        patch = idle[cy:cy + P, cx:cx + P]
        if rng.random() < 0.5: patch = patch[:, ::-1]
        if rng.random() < 0.5: patch = patch[::-1]
        y0, x0 = max(y, 0), max(x, 0); y1, x1 = min(y + P, H), min(x + P, W)
        out[y0:y1, x0:x1] += patch[y0 - y:y1 - y, x0 - x:x1 - x] * win[y0 - y:y1 - y, x0 - x:x1 - x]
        wsum[y0:y1, x0:x1] += win[y0 - y:y1 - y, x0 - x:x1 - x]
bg = out / np.maximum(wsum, 1e-4)
# keep the patches' crispness: put back the fine detail the blending averaged out
lum = bg.mean(axis=2)
fine = lum - np.asarray(Image.fromarray(lum.astype(np.uint8)).filter(ImageFilter.GaussianBlur(3)), np.float32)
bg += fine[..., None] * 0.8
# the before-picture's light: brighter lavender high in the middle, darker toward the frame
yy, xx = np.mgrid[0:H, 0:W]
light = 1.18 - 0.55 * np.sqrt(((xx / W) - 0.5) ** 2 * 1.4 + ((yy / H) - 0.3) ** 2)
bg *= np.clip(light, 0.55, 1.15)[..., None]
bg += rng.normal(0, 4.0, (H, W, 1))
# dark smoke clouds drifting through it, like the before-picture's
cl = rng.random((H // 16, W // 16)).astype(np.float32)
cl = np.asarray(Image.fromarray((cl * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(22)), np.float32) / 255.0
cl = (cl - cl.mean()) / (cl.std() + 1e-4)
bg *= np.clip(1.0 + cl * 0.16, 0.6, 1.3)[..., None]
# a little darker when selected (owner), and a soft vignette so the eye goes to him
yy, xx = np.mgrid[0:H, 0:W]
d = np.sqrt(((xx / W) - 0.5) ** 2 + ((yy / H) - 0.42) ** 2)
bg *= (0.86 * (1.0 - np.clip((d - 0.35) * 0.8, 0, 0.25)))[..., None]
s = np.asarray(sel).astype(np.float32)
m = np.asarray(sm).astype(np.float32)[..., None] / 255.0
comp = s * m + bg * (1 - m)
comp[:B, :] = s[:B, :]; comp[-B:, :] = s[-B:, :]; comp[:, :B] = s[:, :B]; comp[:, -B:] = s[:, -B:]
Image.fromarray(np.clip(comp, 0, 255).astype(np.uint8)).save(D + "/roadkill_select_fixed.png")
print("saved")

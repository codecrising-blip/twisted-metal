"""Mr. Ash (Darkside's driver), round 26. The owner's sheet (docs/reference/portraits/owner_darkside.webp: before |
after, a shared red frame between) had the body the owner wanted, with three things the image tool could not fix:
  - no hair: the long hair under the hat goes, the face stays a black shadow, the coat rises to it;
  - light on him: a red rim light on the coat's edges and folds like the owner's other sheet (owner_darkside_alt.webp,
    whose body was wrong);
  - after the pick he only moves his arm toward the camera, "without moving a muscle" elsewhere: the after picture is
    the before body (hair off, name off) in the truck's light, with only the reaching arm and the coat side under it
    taken from the sheet's after panel.
   mr_ash.py <work> <lama.onnx>   ->  <work>/darkside_idle_fixed.png, <work>/darkside_select_fixed.png"""
import sys
import os
import numpy as np
import cv2
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paint import lama, poly, matte, clean_mask, rim_light  # noqa: E402

W_DIR, MODEL = sys.argv[1], sys.argv[2]
sheet = Image.open("docs/reference/portraits/owner_darkside.webp").convert("RGB")
bef_raw = np.asarray(sheet.crop((0, 0, 632, 832))).astype(np.float32)
aft = np.asarray(sheet.crop((616, 0, 1248, 832))).astype(np.float32)
H, W = bef_raw.shape[:2]
P = lambda ps, blur=0.0: poly((H, W), ps, blur)  # noqa: E731
DARK = np.array([4, 3, 4], np.float32)  # the black of his face column (measured)

# ---- 1. no hair ---------------------------------------------------------------------------------------------------
a = bef_raw.copy()
col = P([(250, 226), (390, 226), (390, 404), (250, 404)]) > 0.5
# the column below the eyes is one black shadow first, so LaMa never sees the strands that lay over its edges
sel = col & (np.arange(H)[:, None] > 226) & (a.mean(2) > 4)
a[sel] = DARK + 0.1 * (a[sel] - DARK)
hair = (P([(184, 202), (262, 202), (262, 410), (232, 410), (206, 384), (190, 354), (180, 318), (180, 262)]) +
        P([(378, 202), (456, 202), (462, 262), (462, 340), (446, 374), (412, 398), (378, 410)])) > 0.5
hole = (hair & ~col).astype(np.uint8)
# pass 1 at half size: LaMa sees shapes, not strands, so it fills with coat and haze instead of more hair
h2 = cv2.resize(a, (W // 2, H // 2), interpolation=cv2.INTER_AREA)
m2 = (cv2.resize(hole.astype(np.float32), (W // 2, H // 2), interpolation=cv2.INTER_AREA) > 0.01).astype(np.uint8)
up = cv2.resize(lama(h2, cv2.dilate(m2, np.ones((3, 3), np.uint8)), MODEL), (W, H), interpolation=cv2.INTER_CUBIC)
b = np.where(hole[..., None] > 0, up, a)
# pass 2 at full size on the inside of the hole: the grain back, with hair-free context now
b = lama(b, cv2.erode(hole, np.ones((5, 5), np.uint8)), MODEL)
# next to the column LaMa still draws strokes (they read as hair): the head's shadow fades over them instead
dist = cv2.distanceTransform((~col).astype(np.uint8), cv2.DIST_L2, 5)
w = cv2.GaussianBlur((np.clip(1.0 - dist / 20.0, 0, 1) ** 0.8 * (hole > 0)).astype(np.float32), (0, 0), 1.5)[..., None]
nohair = b * (1 - w) + DARK * w

# ---- 2. the before picture: red rim light, the MR. ASH lettering back on top as drawn ---------------------------
mb = matte(nohair)
mb[:305, :172] = 0  # a smoke curl over his left shoulder, not the coat
mb = clean_mask(mb)
head = cv2.GaussianBlur(P([(256, 205), (384, 205), (384, 840), (256, 840)]), (0, 0), 4.0)
idle = rim_light(nohair, mb, (1.0, 0.16, 0.12), strength=0.62, width=2.6, reach=30.0, detail=0.85, sides=1.0, top=0.6,
                 keep_out=head)
red = bef_raw[..., 0] - np.maximum(bef_raw[..., 1], bef_raw[..., 2])
letters = ((red > 40) & (bef_raw[..., 0] > 90)).astype(np.uint8)
letters[:540] = 0
letters = cv2.dilate(letters, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11)))
lw = cv2.GaussianBlur(letters.astype(np.float32), (0, 0), 1.5)[..., None]
idle = idle * (1 - lw) + bef_raw * lw
Image.fromarray(np.clip(idle, 0, 255).astype(np.uint8)).save(W_DIR + "/darkside_idle_fixed.png")

# ---- 3. the after picture: the same body, only the arm moved ------------------------------------------------------
# the name off the body (LaMa over the coat)
red = nohair[..., 0] - np.maximum(nohair[..., 1], nohair[..., 2])
fill = ((red > 26) & (nohair[..., 0] > 48)).astype(np.uint8)
fill[:560] = 0; fill[:, :30] = 0; fill[:, 600:] = 0; fill[805:] = 0
n, lab, st, _ = cv2.connectedComponentsWithStats(fill, 8)
for i in range(1, n):
    if st[i, 4] < 40:
        fill[lab == i] = 0
nh = cv2.dilate(fill, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (19, 19)))
nh[805:] = 0
bef = lama(nohair, nh, MODEL)
ma = matte(aft)
# R: the side that moved (the reaching arm from the shoulder, and the coat side the hanging arm no longer covers):
# the sheet's after panel there; everywhere else the before body, untouched
R = P([(452, 290), (490, 272), (540, 286), (590, 326), (604, 400), (604, 812), (440, 812), (436, 560), (432, 420),
       (438, 334)], 4.0)
# a clean outline round head and shoulders: against the bright truck the matte's ragged edge there read as hair
zone = np.zeros((H, W), np.float32); zone[198:342, 140:470] = 1.0
shape = P([(256, 150), (384, 150), (384, 268), (410, 281), (438, 297), (470, 310), (470, 342), (140, 342), (140, 330),
           (162, 324), (184, 310), (208, 295), (234, 280), (256, 268)])
zone = cv2.GaussianBlur(zone, (0, 0), 3.0)
mb = mb * (1 - zone) + np.minimum(np.maximum(mb, shape), shape) * zone
mb = np.maximum(mb, shape * zone * (np.arange(H)[:, None] > 270))
mb = cv2.GaussianBlur(mb, (0, 0), 0.7)
# where the after panel's own figure shows past the before body (its narrower shoulders): truck and fog by LaMa
mbd = cv2.dilate((mb > 0.5).astype(np.uint8), np.ones((5, 5), np.uint8))
hairzone = (P([(200, 200), (262, 200), (262, 334), (200, 334)]) + P([(378, 200), (432, 200), (432, 334), (378, 334)])) > 0.5
hole = ((ma > 0.4) & (R < 0.5) & ~hairzone & (mbd == 0)).astype(np.uint8)
hole = cv2.dilate(hole, np.ones((7, 7), np.uint8)) & (mbd == 0) & (~hairzone).astype(np.uint8)
hole[:, :14] = 0; hole[:, -14:] = 0; hole[:14] = 0; hole[-14:] = 0
scene = lama(aft, hole, MODEL) if hole.any() else aft.copy()
# beside the head LaMa paints long hair under the hat whatever it is given; the truck's cab is symmetric and its
# windshield shows clean on both sides, so the glass is mirrored in from just outside the hair instead
mirror = scene.copy()
for y in range(196, 336):
    for x in range(200, 258):  # left: about x 204 (clean glass at 150-204)
        mirror[y, x] = scene[y, max(150, 408 - x)]
    for x in range(380, 432):  # right: about x 432 (clean glass at 432-480)
        mirror[y, x] = scene[y, min(486, 864 - x)]
fz = cv2.GaussianBlur((hairzone & (mbd == 0)).astype(np.float32), (0, 0), 1.5)[..., None]
scene = scene * (1 - fz) + mirror * fz
# the before body in the truck's light: the after panel's cool grey, matched on a patch of coat both show
Y = (bef * np.array([0.3, 0.59, 0.11])).sum(2, keepdims=True)
body = bef * 0.25 + Y * np.array([0.94, 0.98, 1.06]) * 0.75
gain = (aft[420:620, 150:260].reshape(-1, 3).mean(0) + 1) / (body[420:620, 150:260].reshape(-1, 3).mean(0) + 1)
body = np.clip(body * np.clip(gain, 0.8, 2.2), 0, 255)
# the headlights behind him: a cold rim on his edges
body = rim_light(body, mb, (0.92, 0.95, 1.0), strength=0.3, width=2.0, reach=34.0, detail=1.0, sides=1.0, top=0.25,
                 seed=4, keep_out=head)
eyes = P([(262, 188), (380, 188), (380, 222), (262, 222)], 3.0)[..., None]  # the eyes keep their red glow
body = body * (1 - eyes) + bef * eyes
w = (cv2.GaussianBlur(mb, (0, 0), 0.8) * (1 - R))[..., None]
sel_img = scene * (1 - w) + body * w
Image.fromarray(np.clip(sel_img, 0, 255).astype(np.uint8)).save(W_DIR + "/darkside_select_fixed.png")
print("mr ash: idle + select")

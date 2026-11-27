"""Driver names on the portraits, lettered with the owner's own brush letters (round 26).
The owner's sheets carry red brush names (MR. GRIMM, NEEDLES KANE, MARCUS KANE, AXEL, BRUCE COCHRANE). New names are
put together from those letters: each glyph is cut out of a sheet (red fill inside a polygon), scaled to one cap
height and set on a rising baseline; the black outline and shadow are drawn fresh around the whole name, so letters
from different sheets read as one lettering. There is no J or T among the owner's names: T comes from the OUTLAW
title the owner's Outlaw sheet had, J is BRUCE's U with its left stem cut off above the bowl.
   names.py <work> [debug]
Writes <work>/outlaw_idle_named.png (JAMIE ROBERTS over outlaw_idle_fixed.png) and <work>/thumper_idle_named.png
(BRUCE over thumper_idle_clean.png: COCHRANE taken off, the swoosh shortened to the one word)."""
import sys
import math
import numpy as np
import cv2
from PIL import Image, ImageDraw, ImageFilter

W = sys.argv[1]
DEBUG = len(sys.argv) > 2

# glyph: sheet, polygon (panel pixels)
G = {
    "B": ("thumper", [(52, 688), (91, 688), (91, 797), (52, 800)]),
    "R": ("thumper", [(91, 678), (131, 678), (131, 787), (91, 797)]),
    "J": ("thumper", [(142, 668), (162, 668), (162, 790), (127, 790), (127, 750), (142, 750)]),
    "E": ("thumper", [(193, 660), (232, 660), (232, 764), (193, 768)]),
    "O": ("thumper", [(276, 648), (309, 648), (309, 758), (276, 758)]),
    "R2": ("thumper", [(377, 628), (419, 628), (415, 742), (377, 742)]),
    "A": ("thumper", [(416, 742), (420, 628), (444, 628), (444, 742)]),
    "E2": ("thumper", [(479, 620), (526, 620), (526, 748), (479, 748)]),
    "I": ("mr_grimm", [(346, 618), (367, 618), (367, 752), (352, 752), (346, 728)]),
    "M": ("mr_grimm", [(430, 595), (495, 595), (495, 721), (446, 721), (442, 742), (424, 742)]),
    "S": ("roadkill", [(273, 640), (322, 640), (322, 744), (262, 762), (262, 748), (273, 738)]),
    "T": ("outlaw", [(198, 610), (272, 610), (272, 668), (270, 780), (226, 780), (226, 668), (198, 668)]),
    "SW": ("thumper", [(84, 787), (352, 741), (352, 775), (84, 818)]),  # the swoosh under BRUCE COCHRANE
}
_raw = {}


def raw(car):
    if car not in _raw:
        src = "thumper_v1" if car == "thumper" else car  # round 29: the old BRUCE COCHRANE sheet keeps the glyphs
        _raw[car] = np.asarray(Image.open("%s/%s_idle_raw.png" % (W, src)).convert("RGB")).astype(np.float32)
    return _raw[car]


def glyph(key):
    """RGBA crop of one glyph: the sheet's own colours, alpha = how red the pixel is inside the polygon."""
    car, poly = G[key]
    a = raw(car)
    xs = [p[0] for p in poly]; ys = [p[1] for p in poly]
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    pm = Image.new("L", (a.shape[1], a.shape[0]), 0)
    ImageDraw.Draw(pm).polygon(poly, fill=255)
    pm = np.asarray(pm, np.float32)[y0:y1, x0:x1] / 255.0
    c = a[y0:y1, x0:x1]
    red = c[..., 0] - np.maximum(c[..., 1], c[..., 2])
    al = np.clip((red - 28.0) / 30.0, 0, 1) * np.clip((c[..., 0] - 50.0) / 30.0, 0, 1) * pm
    # keep only the glyph's own body: drop specks cut off at the polygon edge
    m = (al > 0.35).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(m, 8)
    if n > 2:
        big = 1 + int(np.argmax(st[1:, 4]))
        keep = np.zeros_like(m)
        for i in range(1, n):
            if i == big or st[i, 4] > 0.08 * st[big, 4]:
                keep[lab == i] = 1
        keep = cv2.dilate(keep, np.ones((3, 3), np.uint8))
        al = al * keep
    ys_, xs_ = np.nonzero(al > 0.3)
    al = al[ys_.min():ys_.max() + 1, xs_.min():xs_.max() + 1]
    c = c[ys_.min():ys_.max() + 1, xs_.min():xs_.max() + 1]
    rgba = np.dstack([c, al * 255.0]).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def swoosh(length, slope, thick=1.0):
    """The BRUCE COCHRANE swoosh resampled along its own axis to a new length; slope = rise per run (negative = up)."""
    g = glyph("SW")
    ang = math.degrees(math.atan2(741 - 787, 352 - 84))  # its own direction (about -10 deg)
    flat = g.rotate(ang, resample=Image.BICUBIC, expand=True)  # PIL turns counter-clockwise: level it
    bb = flat.getbbox(); flat = flat.crop(bb)
    flat = flat.resize((max(8, int(length)), max(4, int(flat.height * thick))), Image.LANCZOS)
    return flat.rotate(-math.degrees(math.atan(slope)), resample=Image.BICUBIC, expand=True)


def letter_layer(size, items):
    """items: (RGBA image, x, y top-left). One transparent layer the size of the panel."""
    lay = Image.new("RGBA", size, (0, 0, 0, 0))
    for im, x, y in items:
        lay.alpha_composite(im, (int(round(x)), int(round(y))))
    return lay


def ink(base, lay, outline=6, shadow=12):
    """The name over the picture: soft shadow, black brush outline round every stroke, then the red letters."""
    a = np.asarray(lay, np.float32)
    al = a[..., 3] / 255.0
    A = Image.fromarray((al * 255).astype(np.uint8))
    ol = np.asarray(A.filter(ImageFilter.MaxFilter(outline * 2 + 1)).filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255.0
    sh = np.asarray(A.filter(ImageFilter.MaxFilter(outline * 2 + 1)).filter(ImageFilter.GaussianBlur(shadow)), np.float32) / 255.0
    b = np.asarray(base.convert("RGB"), np.float32)
    b = b * (1 - 0.55 * sh[..., None])
    b = b * (1 - 0.93 * ol[..., None]) + np.array([14, 6, 6]) * 0.93 * ol[..., None]
    b = b * (1 - al[..., None]) + a[..., :3] * al[..., None]
    return Image.fromarray(np.clip(b, 0, 255).astype(np.uint8))


def set_word(letters, x, base_y, slope, cap, gap=-1.0, jitter=None, scale=None):
    """Lay glyphs along a rising baseline. Returns items and the x after the last one."""
    items = []
    for i, key in enumerate(letters):
        g = glyph(key)
        k = cap / g.height * (scale.get(key, 1.0) if scale else 1.0)
        g = g.resize((max(1, int(g.width * k)), max(1, int(g.height * k))), Image.LANCZOS)
        g = g.rotate(-math.degrees(math.atan(slope)) * 0.35, resample=Image.BICUBIC, expand=True)  # a little lean along the line
        dy = jitter[i] if jitter else 0.0
        by = base_y + slope * (x - 0) + dy
        items.append((g, x, by - g.height))
        x += g.width + gap
    return items, x


def outlaw():
    base = Image.open(W + "/outlaw_idle_fixed.png").convert("RGB")
    cap = 100.0; slope = -0.105; y0 = 798.0
    jit1 = [3, -2, 1, -3, 2]
    jit2 = [1, -2, 2, -1, 3, -2, 1]
    a, x = set_word(["J", "A", "M", "I", "E"], 42.0, y0, slope, cap, -2.0, jit1, {"J": 0.97, "I": 1.02, "M": 1.04})
    b, x2 = set_word(["R", "O", "B", "E2", "R2", "T", "S"], x + 20.0, y0, slope, cap, -2.0, jit2, {"T": 1.04, "S": 1.03})
    items = a + b
    sw = swoosh((x2 - 42.0) * 0.62, -0.19, 1.05)  # under the first name and on, like the owner's
    items.insert(0, (sw, 70.0, y0 + slope * 70.0 - 32.0))
    lay = letter_layer(base.size, items)
    ink(base, lay).save(W + "/outlaw_idle_named.png")
    print("outlaw: JAMIE ROBERTS from x 42 to", int(x2))


if DEBUG:
    keys = [k for k in G]
    ims = [glyph(k) for k in keys]
    sheet = Image.new("RGB", (sum(i.width for i in ims) + 10 * len(ims) + 300, 200), (90, 90, 90))
    x = 5
    for i in ims:
        sheet.paste(i, (x, 10), i); x += i.width + 10
    sheet.save(W + "/glyphs.png")
else:
    outlaw()

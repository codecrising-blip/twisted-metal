"""Outlaw: army clothes -> a clean police uniform (owner, round 25). Recolour the shirt police navy, the brown
harness black leather (a Sam Browne strap), add a gold badge and a POLICE shoulder patch, close the torn sleeve."""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import cv2

D = sys.argv[1]
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def hsl(a):
    mx = a.max(2); mn = a.min(2); d = np.maximum(mx - mn, 1e-4)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-4), 0)
    return h, s, (mx + mn) / 2


def poly_mask(shape, polys):
    m = Image.new("L", (shape[1], shape[0]), 0)
    d = ImageDraw.Draw(m)
    for p in polys:
        d.polygon(p, fill=255)
    return np.asarray(m, np.float32) / 255.0


def badge(size):
    """A gold police shield with a star, inked like the art, drawn big and scaled down."""
    k = 4; w = size * k; h = int(size * 1.2) * k
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    shield = [(w * 0.5, 0), (w * 0.95, h * 0.12), (w, h * 0.45), (w * 0.78, h * 0.8), (w * 0.5, h), (w * 0.22, h * 0.8), (0, h * 0.45), (w * 0.05, h * 0.12)]
    d.polygon(shield, fill=(20, 14, 6, 255))
    inner = [((x - w / 2) * 0.82 + w / 2, (y - h / 2) * 0.82 + h / 2) for x, y in shield]
    d.polygon(inner, fill=(214, 168, 62, 255))
    inner2 = [((x - w / 2) * 0.6 + w / 2, (y - h / 2) * 0.6 + h / 2) for x, y in shield]
    d.polygon(inner2, fill=(240, 205, 105, 255))
    import math
    cx, cy, R = w / 2, h * 0.47, w * 0.2
    star = []
    for i in range(10):
        r = R if i % 2 == 0 else R * 0.45
        a = -math.pi / 2 + i * math.pi / 5
        star.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    d.polygon(star, fill=(150, 105, 30, 255), outline=(20, 14, 6, 255))
    d.line([(w * 0.3, h * 0.2), (w * 0.42, h * 0.16)], fill=(255, 245, 200, 255), width=k * 2)  # glint
    return im.resize((size, int(size * 1.2)), Image.LANCZOS)


def patch(size):
    """Shoulder patch: arched-top navy patch, gold border, POLICE."""
    k = 4; w = size * k; h = int(size * 1.15) * k
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, h * 0.18, w, h], radius=w * 0.18, fill=(15, 12, 10, 255))
    d.pieslice([0, 0, w, h * 0.5], 180, 360, fill=(15, 12, 10, 255))
    b = int(w * 0.07)
    d.rounded_rectangle([b, h * 0.18 + b, w - b, h - b], radius=w * 0.14, fill=(205, 160, 55, 255))
    d.pieslice([b, b, w - b, h * 0.5 - b], 180, 360, fill=(205, 160, 55, 255))
    b2 = int(w * 0.13)
    d.rounded_rectangle([b2, h * 0.2 + b2, w - b2, h - b2], radius=w * 0.11, fill=(24, 36, 78, 255))
    d.pieslice([b2, b2, w - b2, h * 0.5 - b2 * 0.6], 180, 360, fill=(24, 36, 78, 255))
    f = ImageFont.truetype(FONT, int(w * 0.2))
    t = "POLICE"
    tw = d.textlength(t, font=f)
    d.text(((w - tw) / 2, h * 0.36), t, font=f, fill=(235, 195, 90, 255))
    d.ellipse([w * 0.38, h * 0.6, w * 0.62, h * 0.84], fill=(205, 160, 55, 255))
    return im.resize((size, int(size * 1.15)), Image.LANCZOS)


def paste(img, sprite, center, angle):
    sp = sprite.rotate(angle, resample=Image.BICUBIC, expand=True)
    x = int(center[0] - sp.width / 2); y = int(center[1] - sp.height / 2)
    img.alpha_composite(sp, (x, y))


def dress(name, keep_polys, strap_polys, tear_polys, badge_at, patch_at, src_name="raw"):
    src = Image.open(D + "/outlaw_%s_%s.png" % (name, src_name)).convert("RGB")
    a = np.asarray(src).astype(np.float32) / 255.0
    fig = np.asarray(Image.open(D + "/outlaw_%s_mask.png" % name).convert("L"), np.float32) / 255.0
    h, s, l = hsl(a)
    red = (a[..., 0] - np.maximum(a[..., 1], a[..., 2])) > 0.25
    hair = (h > 195) & (h < 250) & (s > 0.18)
    keep = poly_mask(a.shape, keep_polys) > 0.5  # guns, hands
    strap = poly_mask(a.shape, strap_polys)
    cloth = (fig > 0.5) & (l < 0.45) & (s < 0.36) & ~red & ~hair & ~keep
    leather = (strap > 0.5) & (fig > 0.5) & ~red & ~keep & (s < 0.5) & (l < 0.62)
    cm = np.asarray(Image.fromarray((cloth * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), np.float32)[..., None] / 255.0
    lm = np.asarray(Image.fromarray((leather * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), np.float32)[..., None] / 255.0
    Y = (a * np.array([0.3, 0.59, 0.11])).sum(2, keepdims=True)
    # clean cloth: smooth the grime out of it, keep the ink lines (edge-preserving)
    smooth = cv2.bilateralFilter((a * 255).astype(np.uint8), 9, 30, 9).astype(np.float32) / 255.0
    Ys = (smooth * np.array([0.3, 0.59, 0.11])).sum(2, keepdims=True)
    Y = Y * 0.35 + Ys * 0.65
    navy = np.clip(Y * np.array([0.66, 0.86, 1.6]) * 0.92, 0, 1)
    black = np.clip(Y * np.array([0.62, 0.64, 0.7]) * 0.9, 0, 1)
    out = a * (1 - cm) + navy * cm
    out = out * (1 - lm) + black * lm
    img = Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))
    if tear_polys:  # the torn sleeve: the skin showing through becomes sleeve (shading and ink kept)
        tm = poly_mask(a.shape, tear_polys) > 0.5
        skin = tm & (l > 0.18) & ~keep
        km = np.asarray(Image.fromarray((skin * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0)), np.float32)[..., None] / 255.0
        cur = np.asarray(img).astype(np.float32) / 255.0
        Yt = (cur * np.array([0.3, 0.59, 0.11])).sum(2, keepdims=True)
        sleeve = np.clip(Yt * 0.42 * np.array([0.66, 0.86, 1.6]), 0, 1)
        cur = cur * (1 - km) + sleeve * km
        img = Image.fromarray((np.clip(cur, 0, 1) * 255).astype(np.uint8))
    img = img.convert("RGBA")
    if patch_at:
        paste(img, patch(patch_at[2]), patch_at[:2], patch_at[3])
    if badge_at:
        paste(img, badge(badge_at[2]), badge_at[:2], badge_at[3])
    img.convert("RGB").save(D + "/outlaw_%s_fixed.png" % name)


# idle: gun + gloved hand kept; the brown harness becomes a black leather strap; patch on her shoulder,
# badge on her chest beside the gun hand
dress("idle",
      keep_polys=[[(318, 300), (500, 285), (590, 330), (585, 420), (520, 470), (515, 620), (395, 620), (330, 560)]],
      strap_polys=[[(60, 395), (165, 375), (240, 470), (310, 660), (300, 780), (230, 780), (200, 640), (130, 470), (60, 450)]],
      tear_polys=None,
      badge_at=(345, 470, 46, 12),
      patch_at=(85, 505, 66, 18),
      src_name="clean")  # the OUTLAW title taken off first (unletter.py): JAMIE ROBERTS goes on after (names.py)
# select: both guns and hands kept; the sleeve tear closed; badge on her left breast, patch on her right arm
dress("select",
      keep_polys=[[(295, 285), (560, 290), (600, 330), (600, 520), (380, 540), (270, 470)],
                  [(450, 640), (631, 640), (631, 848), (440, 848)]],
      strap_polys=[[(140, 660), (470, 660), (470, 800), (140, 800)], [(40, 760), (140, 760), (140, 848), (40, 848)]],
      tear_polys=[[(196, 396), (266, 388), (272, 474), (200, 474)]],
      badge_at=(430, 572, 44, -8),
      patch_at=(150, 360, 58, -20))
print("ok")

"""Paris (round 27): the Haussmann facade kit. One atlas for every piece.
    /tmp/bpy3.13/bin/python tools/blender/build_haussmann.py [--nobake]
Writes assets/models/haussmann.glb (+ _albedo/_normal/_orm, and haussmann_rail.png for the iron railings).

Every piece is one 3.0 m bay of a facade (piers: 1.0 m fillers), origin at the bottom centre of the
facade plane, the street side facing -Y (in Godot: +Z). Heights are whole stone courses (0.52 m) so the
joints run on from piece to piece:
    ground floor + entresol 4.68 | floors 3.12 | cornice 0.52 | mansard 1.56 (low, roofs you drive on at
    13.0 m) or 2.72 (tall blocks, 20.4 m)
Pieces: g_shop_red/green/navy/black, g_door, g_shutter, g_burnt, g_pier | f_balcony (2nd and top floor:
continuous balcony), f_window, f_pier | cornice | mans_low, mans_low_dormer, mans_tall, mans_tall_dormer |
chimney | awning_red, awning_green.
Palette: docs/design/32-paris-design.md section 5."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T  # first: it loads bpy, which puts mathutils on the path
import bmesh
import bpy
import numpy as np
from mathutils import Matrix
from PIL import Image, ImageDraw

T.reset()
GH = 4.68
FH = 3.12
CH = 0.52
ML = 1.56
MT = 2.72
SERIF = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"


ASHLAR = T.M("ashlar", T.lin("D8C9AC"), 0.3, 0.0, 0.3)
RUSTIC = T.M("rustic", T.lin("D3C3A5"), 0.35, 0.0, 0.5)
MOULD = T.M("stone", T.lin("DDD0B5"), 0.3, 0.0, 0.4)
PLINTH = T.M("stone", T.lin("8F8A80"), 0.45, 0.0, 0.8)
ZINC = T.M("stone", T.lin("6F7C86"), 0.15, 0.0, 0.45)
SEAM = T.M("stone", T.lin("A7B0B5"), 0.15, 0.0, 0.35)
IRON = T.M("paint", T.lin("1E2420"), 0.35, 0.25, 0.4)
FRAME = T.M("paint", T.lin("E2DCCD"), 0.3, 0.05, 0.45)
DOOR = T.M("paint", T.lin("1F3A2E"), 0.3, 0.05, 0.45)
INTERIOR = T.M("paint", T.lin("231E1B"), 0.05, 0.0, 0.1)
BRASS = T.M("steel", T.lin("B08D3C"), 0.2, 0.0, 0.2)
SHUTTER = T.M("steel", T.lin("6C7073"), 0.45, 0.35, 0.55)
BURNT = T.M("burnt", T.lin("2B2A29"), 0.8, 0.5, 0.8)
POT = T.M("concrete", T.lin("B0643E"), 0.35, 0.0, 0.55)
CANVAS = {"red": T.M("cloth", T.lin("8E1F1F"), 0.3, 0.0, 0.5), "green": T.M("cloth", T.lin("1E4A32"), 0.3, 0.0, 0.5)}
SHOPS = {"red": (T.lin("6E1F1F"), "BOULANGERIE"), "green": (T.lin("1F4A35"), "PHARMACIE"),
         "navy": (T.lin("1E2A44"), "LIBRAIRIE"), "black": (T.lin("161616"), "CAFE  TABAC")}
GOLD = T.lin("C9A24A")
GLASS = T.glass((0.025, 0.035, 0.045))
RAIL = bpy.data.materials.new("rail")

items = {}  # name -> (object, offset)
decals = []
regions = []
soot = []
rails = []  # rail faces are re-mapped to the railing texture after the unwrap


def B(size, at, mat, bevel=0.0):
    # Small bevels are left to the baked bevel normal (round 27 budget: ~1000 triangles a low bay).
    return T.box(size, at, mat=mat, bevel=bevel if bevel >= 0.02 else 0.0)


def quad(x0, x1, y, z0, z1, mat, name="rail"):
    """A flat vertical picture (railings): one face, both sides drawn by its material."""
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in ((x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1))]
    bm.faces.new(vs)
    ob = T._new_obj(name, bm, mat)
    rails.append(ob.name)
    return ob


def finish(name, parts, base_z):
    ob = T.join(parts, name)
    off = (len(items) * 4.0, 0.0, base_z)
    ob.data.transform(Matrix.Translation(off))
    items[name] = (ob, off)
    return off


def rail_image():
    """Haussmann cast-iron railing, one bay wide: rails, bars, rings and a scroll band."""
    w, h = 768, 256
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    ink = (30, 36, 32, 255)
    d.rectangle([0, 0, w, 14], fill=ink)
    d.rectangle([0, h - 12, w, h], fill=ink)
    d.rectangle([0, 34, w, 40], fill=ink)
    d.rectangle([0, h - 44, w, h - 38], fill=ink)
    step = 32
    for x in range(0, w, step):
        d.rectangle([x + 13, 14, x + 18, h - 12], fill=ink)
    for x in range(0, w, step * 2):
        cx = x + step
        d.ellipse([cx - 22, 70, cx + 22, 150], outline=ink, width=5)
        d.ellipse([cx - 9, 98, cx + 9, 122], outline=ink, width=4)
        d.arc([cx - 30, 150, cx + 2, 196], 180, 360, fill=ink, width=4)
        d.arc([cx - 2, 150, cx + 30, 196], 180, 360, fill=ink, width=4)
    for x in range(0, w, step * 2):
        d.ellipse([x + 12, 48, x + 20, 58], fill=ink)
    im.save(os.path.join(T.OUT, "haussmann_rail.png"))


# ---------------------------------------------------------------- ground floor + entresol (4.68 m)

def ground_walls(open_w, open_h):
    side = (3.0 - open_w) * 0.5
    p = [B((side, 0.3, GH), (-1.5 + side * 0.5, 0.15, GH * 0.5), RUSTIC),
         B((side, 0.3, GH), (1.5 - side * 0.5, 0.15, GH * 0.5), RUSTIC),
         B((open_w, 0.3, GH - open_h), (0, 0.15, (GH + open_h) * 0.5), RUSTIC),
         B((3.0, 0.38, 0.42), (0, 0.11, 0.21), PLINTH),
         B((3.0, 0.44, 0.16), (0, 0.08, GH - 0.08), MOULD, 0.02),
         B((3.0, 0.36, 0.06), (0, 0.12, GH - 0.2), MOULD),
         B((0.3, 0.08, 0.5), (0, -0.02, open_h + 0.24), MOULD)]  # keystone
    # entresol: a low window in the band above the opening
    p.append(B((1.2, 0.05, 0.5), (0, 0.22, open_h + 0.62), INTERIOR))
    p.append(B((1.3, 0.06, 0.62), (0, 0.18, open_h + 0.62), FRAME))
    p.append(B((1.16, 0.01, 0.48), (0, 0.14, open_h + 0.62), GLASS))
    return p


def g_shop(color):
    paint = T.M("paint", SHOPS[color][0], 0.35, 0.1, 0.5)
    oh = 3.64
    p = ground_walls(2.0, oh)[:-3]  # no entresol window: the shop sign takes the band
    p += [B((2.0, 0.04, oh), (0, 0.31, oh * 0.5), INTERIOR),
          B((0.14, 0.2, 3.0), (-0.93, 0.04, 1.5), paint, 0.01), B((0.14, 0.2, 3.0), (0.93, 0.04, 1.5), paint, 0.01),
          B((1.72, 0.18, 0.55), (0, 0.06, 0.275), paint, 0.01), B((1.4, 0.04, 0.3), (0, -0.04, 0.28), paint, 0.01),
          B((1.72, 0.08, 0.06), (0, 0.06, 0.58), paint), B((0.06, 0.08, 2.4), (0, 0.06, 1.8), paint),
          B((1.72, 0.08, 0.06), (0, 0.06, 2.55), paint), B((1.72, 0.08, 0.06), (0, 0.06, 3.0), paint),
          B((1.72, 0.01, 2.4), (0, 0.1, 1.8), GLASS),
          B((2.3, 0.22, 0.58), (0, -0.05, 3.33), paint, 0.015), B((2.42, 0.3, 0.07), (0, -0.07, 3.655), paint, 0.01)]
    off = finish("g_shop_" + color, p, 0.0)
    img = T.stencil(SHOPS[color][1], GOLD, 160, SERIF, False, 0.08)
    decals.append(T.Decal(img, (off[0], -0.17, 3.33), (0, -1, 0), (0, 0, 1), (2.0, 0.34), 0.1, kinds=("paint",)))


def g_door():
    oh = 3.64
    p = ground_walls(1.7, oh)
    p += [B((0.84, 0.1, 3.02), (-0.43, 0.24, 1.51), DOOR, 0.01), B((0.84, 0.1, 3.02), (0.43, 0.24, 1.51), DOOR, 0.01)]
    for sx in (-0.43, 0.43):
        for z in (0.75, 2.15):
            p.append(B((0.56, 0.05, 1.0), (sx, 0.18, z), DOOR, 0.02))
    p += [B((1.7, 0.08, 0.08), (0, 0.22, 3.06), DOOR), B((1.7, 0.01, 0.56), (0, 0.27, 3.36), GLASS),
          B((1.7, 0.04, 0.6), (0, 0.3, 3.36), INTERIOR),
          B((0.12, 0.08, oh), (-0.9, -0.02, oh * 0.5), MOULD, 0.01), B((0.12, 0.08, oh), (0.9, -0.02, oh * 0.5), MOULD, 0.01),
          B((0.07, 0.06, 0.07), (0, 0.17, 1.45), BRASS)]
    for k in range(7):  # iron bars across the fanlight
        p.append(B((0.025, 0.03, 0.56), (-0.75 + k * 0.25, 0.24, 3.36), IRON))
    off = finish("g_door", p, 0.0)
    plate = Image.new("RGBA", (120, 90), (28, 52, 120, 255))
    dd = ImageDraw.Draw(plate)
    dd.rectangle([4, 4, 115, 85], outline=(235, 235, 230, 255), width=4)
    from PIL import ImageFont
    dd.text((60, 45), str(12 + len(items)), font=ImageFont.truetype(T.FONT_BOLD, 52), fill=(240, 240, 235, 255), anchor="mm")
    decals.append(T.Decal(plate, (off[0] + 1.2, -0.01, 2.7), (0, -1, 0), (0, 0, 1), (0.26, 0.2), 0.1, kinds=("rustic",)))


def g_shutter():
    oh = 3.64
    p = ground_walls(2.0, oh)[:-3]
    p += [B((0.14, 0.2, 3.3), (-0.93, 0.04, 1.65), IRON, 0.01), B((0.14, 0.2, 3.3), (0.93, 0.04, 1.65), IRON, 0.01),
          B((1.72, 0.06, 3.0), (0, 0.08, 1.5), SHUTTER), B((2.0, 0.34, 0.42), (0, 0.0, 3.3), SHUTTER, 0.02)]
    for k in range(12):
        p.append(B((1.72, 0.04, 0.05), (0, 0.04, 0.12 + k * 0.25), SHUTTER))
    p.append(B((0.12, 0.06, 0.16), (0.3, 0.02, 0.3), BRASS, 0.01))  # padlock
    finish("g_shutter", p, 0.0)


def g_burnt():
    oh = 3.64
    p = ground_walls(2.0, oh)[:-3]
    p += [B((2.0, 0.04, oh), (0, 0.31, oh * 0.5), BURNT),
          B((0.14, 0.2, 3.0), (-0.93, 0.04, 1.5), BURNT, 0.01), B((0.14, 0.2, 2.2), (0.93, 0.04, 1.1), BURNT, 0.01),
          B((1.72, 0.18, 0.5), (0, 0.06, 0.25), BURNT, 0.01), B((2.3, 0.22, 0.5), (0, -0.05, 3.3), BURNT, 0.015),
          B((0.5, 0.01, 0.6), (-0.6, 0.1, 0.85), GLASS), B((0.3, 0.01, 0.4), (0.7, 0.1, 2.7), GLASS)]
    off = finish("g_burnt", p, 0.0)
    soot.append(((off[0], -0.1, 3.9), 1.7))
    soot.append(((off[0] + 0.4, -0.1, 5.4), 1.2))


def g_pier():
    p = [B((1.0, 0.3, GH), (0, 0.15, GH * 0.5), RUSTIC), B((1.0, 0.38, 0.42), (0, 0.11, 0.21), PLINTH),
         B((1.0, 0.44, 0.16), (0, 0.08, GH - 0.08), MOULD, 0.02), B((1.0, 0.36, 0.06), (0, 0.12, GH - 0.2), MOULD)]
    finish("g_pier", p, 0.0)


# ---------------------------------------------------------------- floors (3.12 m)

def window(p, z0, z1, w=1.24):
    """A tall French window in a stone surround: cream frames, glazing bars, dark room behind."""
    zm = (z0 + z1) * 0.5
    h = z1 - z0
    p += [B((w, 0.02, h), (0, 0.3, zm), INTERIOR), B((w - 0.14, 0.01, h - 0.1), (0, 0.22, zm), GLASS),
          B((0.07, 0.08, h), (-w * 0.5 + 0.035, 0.2, zm), FRAME), B((0.07, 0.08, h), (w * 0.5 - 0.035, 0.2, zm), FRAME),
          B((w, 0.08, 0.07), (0, 0.2, z1 - 0.035), FRAME), B((0.06, 0.08, h - 0.1), (0, 0.2, zm), FRAME),
          B((w - 0.1, 0.08, 0.06), (0, 0.2, z0 + h * 0.8), FRAME)]
    for zz in (z0 + h * 0.28, z0 + h * 0.54):
        p.append(B((w - 0.1, 0.04, 0.03), (0, 0.21, zz), FRAME))
    p += [B((0.1, 0.07, h + 0.1), (-w * 0.5 - 0.05, -0.03, zm + 0.05), MOULD, 0.01),
          B((0.1, 0.07, h + 0.1), (w * 0.5 + 0.05, -0.03, zm + 0.05), MOULD, 0.01),
          B((w + 0.2, 0.07, 0.1), (0, -0.03, z1 + 0.05), MOULD, 0.01)]


def floor_walls(z0, z1, w=1.24):
    side = (3.0 - w) * 0.5
    return [B((side, 0.3, FH), (-1.5 + side * 0.5, 0.15, FH * 0.5), ASHLAR),
            B((side, 0.3, FH), (1.5 - side * 0.5, 0.15, FH * 0.5), ASHLAR),
            B((w, 0.3, z0), (0, 0.15, z0 * 0.5), ASHLAR),
            B((w, 0.3, FH - z1), (0, 0.15, (FH + z1) * 0.5), ASHLAR)]


def f_balcony():
    z0, z1 = 0.14, 2.62
    p = floor_walls(z0, z1)
    window(p, z0, z1)
    p += [B((1.74, 0.2, 0.1), (0, -0.1, 2.86), MOULD), B((0.1, 0.18, 0.26), (-0.8, -0.09, 2.7), MOULD, 0.01),
          B((0.1, 0.18, 0.26), (0.8, -0.09, 2.7), MOULD, 0.01),
          B((3.0, 0.64, 0.14), (0, -0.32, 0.07), MOULD, 0.02), B((3.0, 0.5, 0.08), (0, -0.25, -0.04), MOULD, 0.01)]
    for x in (-0.95, 0.95):
        p.append(T.box((0.16, 0.24, 0.36), (x, -0.13, -0.22), mat=MOULD, taper=(1.0, 2.2)))
    p.append(quad(-1.5, 1.5, -0.6, 0.14, 1.12, RAIL))
    finish("f_balcony", p, GH)


def f_window():
    z0, z1 = 0.14, 2.62
    p = floor_walls(z0, z1)
    window(p, z0, z1)
    p += [B((1.56, 0.2, 0.08), (0, -0.06, 0.1), MOULD, 0.02), B((1.5, 0.12, 0.08), (0, -0.05, 2.8), MOULD, 0.01),
          B((0.02, 0.24, 0.02), (-0.7, -0.12, 0.86), IRON), B((0.02, 0.24, 0.02), (0.7, -0.12, 0.86), IRON)]
    p.append(quad(-0.7, 0.7, -0.22, 0.16, 0.86, RAIL))
    finish("f_window", p, GH + FH)


def f_pier():
    finish("f_pier", [B((1.0, 0.3, FH), (0, 0.15, FH * 0.5), ASHLAR)], GH + FH)


# ---------------------------------------------------------------- cornice, mansards, chimney

def cornice():
    prof = [(0.3, 0.0), (0.3, CH), (-0.56, CH), (-0.56, 0.44), (-0.5, 0.38), (-0.22, 0.32), (-0.18, 0.22),
            (-0.07, 0.15), (-0.07, 0.06), (0.0, 0.0)]
    p = [T.prism(prof, 3.0, (0, 0, 0), mat=MOULD, plane="YZ")]
    for k in range(10):
        p.append(B((0.11, 0.1, 0.09), (-1.35 + k * 0.3, -0.15, 0.17), MOULD))
    finish("cornice", p, GH + 2 * FH)


def mansard(name, h, run, dormer):
    t = 0.12
    prof = [(-0.02, 0.0), (-0.02 + t, 0.0), (run + t, h), (run, h)]
    p = [T.prism(prof, 3.02, (0, 0, 0), mat=ZINC, plane="YZ"), B((3.02, 0.16, 0.1), (0, -0.04, 0.06), ZINC, 0.01)]
    ang = math.atan2(run, h)
    length = math.hypot(run, h)
    for k in range(6):
        x = -1.25 + k * 0.5
        if dormer and abs(x) < 0.7:
            continue
        rib = T.box((0.03, 0.04, length), (x, run * 0.5 - 0.03, h * 0.5), mat=SEAM)
        rib.rotation_euler = (-ang, 0, 0)
        T.apply(rib)
        p.append(rib)
    if dormer:
        dz0 = 0.18
        dz1 = h * 0.8
        fy = run * dz0 / h - 0.06
        dw = 0.6 if h < 2 else 0.7
        p += [B((dw * 2, 0.12, dz1 - dz0), (0, fy, (dz0 + dz1) * 0.5), MOULD),
              B((0.1, run * 0.7, dz1 - dz0), (-dw, fy + run * 0.35, (dz0 + dz1) * 0.5), ZINC),
              B((0.1, run * 0.7, dz1 - dz0), (dw, fy + run * 0.35, (dz0 + dz1) * 0.5), ZINC)]
        p[-3:-2] = []  # the stone front gives way to a window
        ww = dw * 2 - 0.3
        p += [B((ww, 0.02, dz1 - dz0 - 0.2), (0, fy + 0.12, (dz0 + dz1) * 0.5 - 0.02), GLASS),
              B((ww + 0.04, 0.02, dz1 - dz0 - 0.16), (0, fy + 0.18, (dz0 + dz1) * 0.5 - 0.02), INTERIOR),
              B((0.14, 0.14, dz1 - dz0), (-dw + 0.07, fy, (dz0 + dz1) * 0.5), MOULD, 0.01),
              B((0.14, 0.14, dz1 - dz0), (dw - 0.07, fy, (dz0 + dz1) * 0.5), MOULD, 0.01),
              B((dw * 2, 0.16, 0.12), (0, fy, dz0 + 0.06), MOULD, 0.01),
              B((0.05, 0.06, dz1 - dz0 - 0.2), (0, fy + 0.1, (dz0 + dz1) * 0.5), FRAME)]
        ped = [(-dw - 0.12, 0.0), (dw + 0.12, 0.0), (0.0, 0.34)]
        pd = T.prism(ped, run * 0.75, (0, fy + run * 0.3, dz1), mat=MOULD, plane="XZ")
        p.append(pd)
    finish(name, p, GH + 2 * FH + CH)


def chimney():
    p = [B((1.4, 0.6, 1.8), (0, 0, 0.9), MOULD, 0.02), B((1.52, 0.72, 0.12), (0, 0, 1.86), MOULD, 0.02),
         B((1.46, 0.66, 0.08), (0, 0, 1.0), MOULD, 0.01)]
    for x in (-0.48, -0.16, 0.16, 0.48):
        p.append(T.cyl(0.09, 0.42, (x, 0, 2.13), mat=POT, n=8, r2=0.075))
    finish("chimney", p, 14.0)


def awning(color):
    mat = CANVAS[color]
    canopy = T.box((2.24, 0.03, 1.55), (0, -0.78, 2.78), mat=mat)
    canopy.rotation_euler = (math.radians(-58), 0, 0)
    T.apply(canopy)
    p = [canopy, B((2.24, 0.02, 0.24), (0, -1.43, 2.3), mat), B((2.3, 0.08, 0.08), (0, -0.04, 3.2), IRON)]
    for x in (-1.06, 1.06):
        arm = T.box((0.03, 1.5, 0.03), (x, -0.72, 2.75), mat=IRON)
        arm.rotation_euler = (math.radians(22), 0, 0)
        T.apply(arm)
        p.append(arm)
    off = finish("awning_" + color, p, 0.0)

    def stripes(P, N, ox=off[0]):
        return (np.mod(P[:, 0] - ox + 1.12, 0.32) < 0.16).astype(np.float32)
    if color == "red":
        regions.append((stripes, T.lin("D9D2C2"), ("cloth",)))


for c in ("red", "green", "navy", "black"):
    g_shop(c)
g_door()
g_shutter()
g_burnt()
g_pier()
f_balcony()
f_window()
f_pier()
cornice()
mansard("mans_low", ML, 1.3, False)
mansard("mans_low_dormer", ML, 1.3, True)
mansard("mans_tall", MT, 0.95, False)
mansard("mans_tall_dormer", MT, 0.95, True)
chimney()
awning("red")
awning("green")

objs = [o for (o, _) in items.values()]
print("triangles:", {n: T.tri_count([o]) for n, (o, _) in items.items()})
os.makedirs(T.OUT, exist_ok=True)
rail_image()
T.unwrap(objs, margin=0.003)
if "--nobake" not in sys.argv:
    g = T.gbuffer(objs, size=2048, ao_dist=0.5, bevel_r=0.01)
    al, nm, orm = T.weather(g, decals, seed=27, dust_from=0.0, dust_to=1.0, soot=soot, regions=regions, ao_strength=0.75)
    T.save_maps("haussmann", al, nm, orm)
# Railings read their own picture: u across the bay (3 m = one picture), v up the rail. Only after
# the bake: faces covering the whole 0..1 square would be baked over every other island.
for o in objs:
    me = o.data
    slot = [i for i, m in enumerate(me.materials) if m == RAIL]
    if not slot:
        continue
    uv = me.uv_layers.active.data
    for poly in me.polygons:
        if poly.material_index != slot[0]:
            continue
        xs = [me.vertices[me.loops[li].vertex_index].co.x for li in poly.loop_indices]
        zs = [me.vertices[me.loops[li].vertex_index].co.z for li in poly.loop_indices]
        x0, z0, z1 = min(xs), min(zs), max(zs)
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv[li].uv = ((co.x - x0) / 3.0, (co.z - z0) / max(z1 - z0, 1e-4))
for n, (o, off) in items.items():
    o.data.transform(Matrix.Translation((-off[0], -off[1], -off[2])))
# Faces nobody can see (round 27 budget): backs facing into the building, the sides where one bay meets
# the next, the tops and bottoms where one storey sits on the next. UVs stay as baked.
HEIGHTS = {"g": GH, "f": FH}
for n, (o, off) in items.items():
    if n[0] not in "gf":
        continue
    bm = bmesh.new()
    bm.from_mesh(o.data)
    half = 0.5 if n.endswith("pier") else 1.5
    top = HEIGHTS[n[0]]
    kill = []
    for f in bm.faces:
        if o.data.materials[f.material_index] == RAIL:
            continue
        c = f.calc_center_median()
        nm = f.normal
        inside = c.y > 0.0
        if nm.y > 0.9:
            kill.append(f)
        elif abs(nm.x) > 0.9 and abs(abs(c.x) - half) < 0.03:
            kill.append(f)
        elif inside and ((nm.z < -0.9 and abs(c.z) < 0.03) or (nm.z > 0.9 and abs(c.z - top) < 0.03)):
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(o.data)
    bm.free()
print("triangles after culling:", {n: T.tri_count([o]) for n, (o, _) in items.items()})
T.export_glb("haussmann", objs)
print("ok")

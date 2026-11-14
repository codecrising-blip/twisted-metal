"""Pickups (round 10): real ordnance and supply cases instead of toy icons. One atlas for all of them.
    /tmp/bpy/bin/python tools/blender/build_pickups.py [preview.png]
Writes assets/models/pickups.glb (+ _albedo/_normal/_orm). Node names = pickup kinds, plus "pad".
Blender space: +Y is the nose of a missile, +Z up. Every item is centred on the origin."""
import math
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T  # first: it loads bpy, which puts mathutils on the path
import numpy as np
from mathutils import Matrix, Vector

T.reset()
OLIVE = (0.085, 0.10, 0.05)
GREY = (0.30, 0.31, 0.31)
DARK = (0.05, 0.05, 0.055)
STEEL = (0.10, 0.10, 0.105)
WHITE = (0.62, 0.62, 0.58)
STENCIL = (0.8, 0.78, 0.68)
YELLOW = (0.62, 0.42, 0.04)

items = {}   # name -> object
decals = []
regions = []
SPACING = 5.0


def finish(name, parts):
    ob = T.join(parts, name)
    off = Vector((len(items) * SPACING, 0, 0))
    ob.data.transform(Matrix.Translation(off))
    items[name] = (ob, off)
    return off


def band(off, y0, y1, color, kinds=("paint",)):
    """Paint everything between two stations along the missile's axis."""
    def fn(P, N, off=off, y0=y0, y1=y1):
        d = P - np.array(off, dtype=np.float32)
        return ((d[:, 1] > y0) & (d[:, 1] < y1) & (np.abs(d[:, 0]) < 1.0) & (np.abs(d[:, 2]) < 1.0)).astype(np.float32)
    regions.append((fn, color, kinds))


def side_text(off, s, y, z_r, color=STENCIL, h=0.07, px=96):
    """Stencil lettering on both sides of a body whose axis is Y."""
    img = T.stencil(s, color, px)
    w = h * img.size[0] / img.size[1]
    for sx in (-1, 1):
        decals.append(T.Decal(img, (off[0] + sx * z_r, off[1] + y, off[2]), (sx, 0, 0), (0, 0, 1), (w, h), depth=0.12))


def missile(L, r, nose_len, body, nose, fin_mat, fin_span, fin_chord, canards=False, seeker=None):
    """A missile along +Y, centred. Returns parts."""
    z0, z1 = -L / 2, L / 2
    body_prof = [(r * 0.5, z0), (r * 0.62, z0 + 0.015), (r * 0.9, z0 + 0.05), (r, z0 + 0.09), (r, z1 - nose_len)]
    parts = [T.lathe(body_prof, rot=(-90, 0, 0), mat=body, n=18)]
    tip = z1 - (0.06 if seeker else 0.0)
    nose_prof = [(r, z1 - nose_len), (r * 0.96, z1 - nose_len * 0.72), (r * 0.82, z1 - nose_len * 0.45), (r * 0.58, z1 - nose_len * 0.22)]
    if seeker:
        nose_prof += [(r * 0.5, tip)]
        parts.append(T.lathe([(r * 0.5, tip), (r * 0.42, tip + 0.035), (r * 0.22, tip + 0.055), (0.0, tip + 0.06)], rot=(-90, 0, 0), mat=seeker, n=18))
    else:
        nose_prof += [(r * 0.3, z1 - nose_len * 0.07), (0.0, z1)]
    parts.append(T.lathe(nose_prof, rot=(-90, 0, 0), mat=nose, n=18))
    # exhaust nozzle
    parts.append(T.lathe([(r * 0.3, z0 - 0.05), (r * 0.5, z0 - 0.045), (r * 0.42, z0 + 0.02), (r * 0.2, z0 + 0.03)], rot=(-90, 0, 0), mat=T.M("steel", DARK, 0.6, 0.5), n=14))
    for k in range(4):
        a = 45 + 90 * k
        y = z0 + 0.03
        outline = [(y, r * 0.85), (y + fin_chord, r * 0.85), (y + fin_chord * 0.5, r + fin_span), (y + 0.02, r + fin_span)]
        parts.append(T.prism(outline, 0.016, rot=(0, a, 0), mat=fin_mat, plane="YZ"))
        if canards:
            yc = z1 - nose_len - 0.16
            o2 = [(yc, r * 0.85), (yc + 0.14, r * 0.85), (yc + 0.05, r + fin_span * 0.55), (yc, r + fin_span * 0.55)]
            parts.append(T.prism(o2, 0.012, rot=(0, a + 45, 0), mat=fin_mat, plane="YZ"))
    # band clamps and a cable raceway: small details the bake picks up
    for yy in (z0 + 0.14, z1 - nose_len - 0.02):
        parts.append(T.cyl(r * 1.03, 0.022, (0, yy, 0), rot=(-90, 0, 0), mat=T.M("steel", STEEL, 0.6, 0.4), n=18))
    parts.append(T.box((0.03, L * 0.5, 0.018), (0, 0, r * 0.99), mat=body, bevel=0.004))
    return parts


# ---------------------------------------------------------------- fire: stubby unguided rocket
body = T.M("paint", OLIVE, 0.75, 0.45, 0.5)
orange = T.M("paint", (0.55, 0.16, 0.02), 0.7, 0.4, 0.4)
off = finish("fire", missile(1.2, 0.115, 0.3, body, orange, T.M("paint", OLIVE, 0.8, 0.5, 0.5), 0.15, 0.24))
band(off, -0.08, -0.02, (0.55, 0.16, 0.02))
side_text(off, "FIRE  M1", 0.08, 0.115)

# ---------------------------------------------------------------- homing: slim guided missile
hbody = T.M("paint", GREY, 0.65, 0.3, 0.45)
purple = T.M("paint", (0.2, 0.05, 0.36), 0.6, 0.3, 0.4)
off = finish("homing", missile(1.5, 0.085, 0.3, hbody, purple, T.M("paint", GREY, 0.7, 0.35, 0.5), 0.13, 0.2, canards=True, seeker=T.glass()))
band(off, 0.26, 0.31, (0.2, 0.05, 0.36))
band(off, -0.5, -0.47, (0.2, 0.05, 0.36))
side_text(off, "HMG-2 SEEKER", -0.1, 0.085, h=0.055)

# ---------------------------------------------------------------- power: heavy warhead
pbody = T.M("paint", (0.045, 0.05, 0.045), 0.7, 0.45, 0.5)
red = T.M("paint", (0.36, 0.035, 0.025), 0.7, 0.45, 0.45)
off = finish("power", missile(1.5, 0.185, 0.46, pbody, red, T.M("paint", (0.045, 0.05, 0.045), 0.8, 0.5, 0.5), 0.2, 0.34))
band(off, 0.0, 0.29, (0.36, 0.035, 0.025))
band(off, -0.1, -0.03, YELLOW)
side_text(off, "POWER  HE", -0.36, 0.185, h=0.085)

# ---------------------------------------------------------------- zoomy: seven-tube rocket pod
pod = T.M("paint", OLIVE, 0.7, 0.4, 0.55)
parts = [T.cyl(0.3, 1.05, rot=(-90, 0, 0), mat=pod, n=20, bevel=0.012)]
parts.append(T.cyl(0.31, 0.05, (0, 0.5, 0), rot=(-90, 0, 0), mat=T.M("steel", STEEL, 0.6, 0.4), n=20))
parts.append(T.cyl(0.31, 0.05, (0, -0.47, 0), rot=(-90, 0, 0), mat=T.M("steel", STEEL, 0.6, 0.4), n=20))
tube_d = T.M("steel", (0.02, 0.02, 0.02), 0.3, 0.2)
tipm = T.M("paint", WHITE, 0.6, 0.3, 0.3)
spots = [(0, 0)] + [(0.185 * math.cos(math.radians(60 * k)), 0.185 * math.sin(math.radians(60 * k))) for k in range(6)]
for (x, z) in spots:
    parts.append(T.cyl(0.078, 0.02, (x, 0.527, z), rot=(-90, 0, 0), mat=tube_d, n=10))
    parts.append(T.lathe([(0.06, 0.0), (0.06, 0.05), (0.035, 0.1), (0.0, 0.13)], loc=(x, 0.5, z), rot=(-90, 0, 0), mat=tipm, n=10))
for yy in (-0.2, 0.2):  # mounting lugs
    parts.append(T.box((0.07, 0.1, 0.07), (0, yy, 0.32), mat=T.M("steel", STEEL, 0.6, 0.4), bevel=0.01))
parts.append(T.cyl(0.12, 0.08, (0, -0.56, 0), rot=(-90, 0, 0), mat=T.M("steel", DARK, 0.5, 0.4), n=12))
off = finish("zoomy", parts)
band(off, 0.3, 0.38, (0.5, 0.52, 0.06))
side_text(off, "ZOOMY x10", -0.05, 0.3, h=0.09)

# ---------------------------------------------------------------- napalm: jerry can
can = T.M("paint", (0.36, 0.04, 0.03), 0.7, 0.5, 0.5)
parts = [T.box((0.34, 0.7, 0.86), (0, 0, 0), mat=can, bevel=0.05, segs=2)]
for sx in (-1, 1):  # the pressed X on both big faces
    for ang in (38, -38):
        parts.append(T.box((0.03, 0.62, 0.05), (sx * 0.165, 0, -0.04), rot=(ang, 0, 0), mat=can, bevel=0.012))
parts.append(T.box((0.2, 0.42, 0.1), (0, -0.05, 0.47), mat=can, bevel=0.03))
for xx in (-0.07, 0.0, 0.07):  # three-bar handle
    parts.append(T.tube([(xx, -0.22, 0.5), (xx, -0.2, 0.56), (xx, 0.08, 0.56), (xx, 0.1, 0.5)], 0.016, mat=T.M("steel", STEEL, 0.6, 0.5), n=6))
parts.append(T.cyl(0.07, 0.1, (0, 0.24, 0.5), rot=(20, 0, 0), mat=T.M("steel", STEEL, 0.6, 0.5), n=12))
parts.append(T.cyl(0.085, 0.035, (0, 0.257, 0.55), rot=(20, 0, 0), mat=T.M("steel", DARK, 0.6, 0.5), n=12))
off = finish("napalm", parts)
for sx in (-1, 1):
    decals.append(T.Decal(T.stencil("NAPALM", (0.75, 0.6, 0.1), 110), (off[0] + sx * 0.17, 0, 0.27), (sx, 0, 0), (0, 0, 1), (0.5, 0.12), depth=0.1))
    decals.append(T.Decal(T.hazard_image(), (off[0] + sx * 0.17, 0, -0.33), (sx, 0, 0), (0, 0, 1), (0.6, 0.09), depth=0.06))

# ---------------------------------------------------------------- remote: the electronic mine
mbody = T.M("paint", (0.035, 0.04, 0.035), 0.6, 0.35, 0.5)
parts = [T.cyl(0.52, 0.2, (0, 0, 0), mat=mbody, n=8, bevel=0.025)]
parts.append(T.cyl(0.56, 0.05, (0, 0, -0.09), mat=T.M("steel", STEEL, 0.7, 0.5), n=8))
parts.append(T.cyl(0.39, 0.03, (0, 0, 0.11), mat=T.M("plastic", (0.02, 0.13, 0.05), 0.5, 0, 0.4), n=16))
chip = T.M("plastic", (0.012, 0.012, 0.012), 0.3, 0, 0.3)
parts.append(T.box((0.2, 0.14, 0.04), (-0.08, 0.04, 0.14), mat=chip, bevel=0.004))
parts.append(T.box((0.09, 0.09, 0.04), (0.16, -0.1, 0.14), mat=chip, bevel=0.004))
copper = T.M("chrome", (0.5, 0.25, 0.08), 0.4, 0.2, 0.2)
parts.append(T.box((0.26, 0.022, 0.012), (0.04, -0.17, 0.128), mat=copper))
parts.append(T.box((0.022, 0.24, 0.012), (0.21, 0.09, 0.128), mat=copper))
parts.append(T.cyl(0.06, 0.1, (-0.17, -0.13, 0.17), mat=T.M("steel", STEEL, 0.6, 0.3), n=10, bevel=0.008))
parts.append(T.cyl(0.011, 0.62, (0.25, 0.17, 0.44), mat=T.M("steel", DARK, 0.4, 0.2), n=5))
parts.append(T.sphere(0.04, (0.25, 0.17, 0.76), mat=T.glow((1.0, 0.1, 0.05)), n=8))
for k in range(8):
    a = math.radians(45 * k + 22.5)
    parts.append(T.sphere(0.035, (0.47 * math.cos(a), 0.47 * math.sin(a), 0.1), mat=T.glow((1.0, 0.1, 0.05)), n=6))
off = finish("remote", parts)

# ---------------------------------------------------------------- sat: uplink beacon with a dish
sbody = T.M("paint", (0.11, 0.12, 0.11), 0.6, 0.3, 0.5)
parts = [T.box((0.62, 0.5, 0.3), (0, 0, -0.2), mat=sbody, bevel=0.03, segs=2)]
for sx in (-1, 1):
    parts.append(T.tube([(sx * 0.33, -0.15, -0.14), (sx * 0.37, -0.15, -0.14), (sx * 0.37, 0.15, -0.14), (sx * 0.33, 0.15, -0.14)], 0.014, mat=T.M("steel", STEEL, 0.6, 0.4), n=6))
parts.append(T.box((0.5, 0.38, 0.03), (0, 0, -0.04), mat=T.M("steel", DARK, 0.5, 0.3), bevel=0.006))
parts.append(T.cyl(0.035, 0.26, (0, -0.05, 0.08), mat=T.M("steel", STEEL, 0.6, 0.3), n=8))
dish_m = T.M("paint", (0.42, 0.43, 0.42), 0.6, 0.3, 0.4)
dish = T.lathe([(0.03, 0.0), (0.16, 0.022), (0.28, 0.07), (0.36, 0.125), (0.375, 0.125), (0.29, 0.06), (0.16, 0.008), (0.03, -0.015)], loc=(0, -0.05, 0.22), rot=(-38, 0, 0), mat=dish_m, n=20)
parts.append(dish)
feed = T.cyl(0.012, 0.3, (0, 0.05, 0.35), rot=(-38, 0, 0), mat=T.M("steel", DARK, 0.5, 0.2), n=5)
parts.append(feed)
parts.append(T.sphere(0.035, (0, 0.145, 0.47), mat=T.glow((0.2, 0.95, 0.8)), n=8))
parts.append(T.cyl(0.009, 0.5, (0.24, -0.18, 0.2), mat=T.M("steel", DARK, 0.4, 0.2), n=5))
for xx in (-0.18, -0.06, 0.06):
    parts.append(T.sphere(0.028, (xx, 0.252, -0.12), mat=T.glow((0.2, 0.95, 0.8)), n=6))
off = finish("sat", parts)
decals.append(T.Decal(T.stencil("SAT UPLINK", STENCIL, 96), (off[0], 0.25, -0.26), (0, 1, 0), (0, 0, 1), (0.44, 0.07), depth=0.08))
decals.append(T.Decal(T.stencil("SAT UPLINK", STENCIL, 96), (off[0], -0.25, -0.2), (0, -1, 0), (0, 0, 1), (0.44, 0.07), depth=0.08))

# ---------------------------------------------------------------- turbo: nitrous bottle
blue = T.M("paint", (0.02, 0.1, 0.4), 0.65, 0.35, 0.45)
prof = [(0.0, -0.52), (0.1, -0.515), (0.185, -0.48), (0.21, -0.42), (0.21, 0.22), (0.19, 0.31), (0.12, 0.4), (0.07, 0.43), (0.07, 0.47)]
parts = [T.lathe(prof, rot=(-90, 0, 0), mat=blue, n=20)]
valve = T.M("chrome", (0.42, 0.33, 0.14), 0.5, 0.3, 0.3)
parts.append(T.cyl(0.06, 0.12, (0, 0.52, 0), rot=(-90, 0, 0), mat=valve, n=8, bevel=0.008))
parts.append(T.cyl(0.03, 0.1, (0, 0.52, 0.07), mat=valve, n=8))
parts.append(T.cyl(0.085, 0.022, (0, 0.52, 0.13), mat=T.M("paint", (0.4, 0.03, 0.02), 0.6, 0.3, 0.3), n=6, bevel=0.006))
parts.append(T.cyl(0.055, 0.03, (0.075, 0.52, 0), rot=(0, 90, 0), mat=T.M("steel", STEEL, 0.5, 0.3), n=12))
parts.append(T.cyl(0.045, 0.006, (0.092, 0.52, 0), rot=(0, 90, 0), mat=T.M("plastic", WHITE, 0.3, 0, 0.2), n=12))
for yy in (-0.3, 0.1):  # mounting straps
    parts.append(T.cyl(0.218, 0.04, (0, yy, 0), rot=(-90, 0, 0), mat=T.M("steel", STEEL, 0.6, 0.4), n=20))
off = finish("turbo", parts)
band(off, -0.16, -0.06, (0.6, 0.22, 0.03))
side_text(off, "N2O  TURBO", -0.02 + 0.2, 0.21, color=STENCIL, h=0.085)

# ---------------------------------------------------------------- health cases (owner: white cross on blue / yellow / red)
def med_case(name, s, bg):
    paint = T.M("paint", bg, 0.6, 0.3, 0.45)
    w, d, h = 0.92 * s, 0.4 * s, 0.7 * s
    parts = [T.box((w, d, h), (0, 0, 0), mat=paint, bevel=0.035 * s, segs=2)]
    stl = T.M("steel", STEEL, 0.6, 0.4)
    parts.append(T.box((w + 0.012, d + 0.012, 0.03 * s), (0, 0, h * 0.22), mat=stl, bevel=0.005))  # lid seam band
    for sx in (-1, 1):
        parts.append(T.box((0.08 * s, 0.03, 0.14 * s), (sx * w * 0.28, -d * 0.5 - 0.012, h * 0.2), mat=stl, bevel=0.006))  # latches
        parts.append(T.box((0.08 * s, 0.03, 0.14 * s), (sx * w * 0.28, d * 0.5 + 0.012, h * 0.2), mat=stl, bevel=0.006))
        for sy in (-1, 1):  # rubber corner guards
            parts.append(T.box((0.07 * s, 0.07 * s, h * 0.96), (sx * (w * 0.5 - 0.02 * s), sy * (d * 0.5 - 0.02 * s), 0), mat=T.M("rubber", (0.02, 0.02, 0.02), 0.5, 0, 0.5), bevel=0.012))
    hw = 0.17 * s
    parts.append(T.tube([(-hw, 0, h * 0.5), (-hw, 0, h * 0.5 + 0.07 * s), (hw, 0, h * 0.5 + 0.07 * s), (hw, 0, h * 0.5)], 0.018 * s, mat=T.M("rubber", (0.02, 0.02, 0.02), 0.5, 0, 0.4), n=6))
    off = finish(name, parts)
    for sy in (-1, 1):
        decals.append(T.Decal(T.cross_image(bg), (off[0], sy * d * 0.5, -h * 0.1), (0, sy, 0), (0, 0, 1), (0.5 * s, 0.5 * s), depth=0.06, kinds=("paint",)))

med_case("health", 1.0, (0.03, 0.11, 0.45))
med_case("mega", 1.3, (0.66, 0.42, 0.03))
med_case("full", 1.6, (0.45, 0.025, 0.02))

# ---------------------------------------------------------------- pad: steel drop plate with marker lamps
plate = T.M("steel", (0.07, 0.07, 0.075), 0.7, 0.55, 0.8)
parts = [T.cyl(1.05, 0.06, (0, 0, 0.03), mat=plate, n=8, bevel=0.012)]
parts.append(T.cyl(0.8, 0.03, (0, 0, 0.07), mat=T.M("steel", (0.05, 0.05, 0.055), 0.7, 0.5, 0.8), n=24, bevel=0.008))
parts.append(T.cyl(0.62, 0.012, (0, 0, 0.09), mat=T.M("rubber", (0.02, 0.02, 0.02), 0.6, 0, 0.8), n=24))
for k in range(8):
    a = math.radians(45 * k + 22.5)
    parts.append(T.cyl(0.035, 0.03, (0.93 * math.cos(a), 0.93 * math.sin(a), 0.065), mat=T.M("steel", STEEL, 0.6, 0.5), n=6))
    a2 = math.radians(45 * k)
    parts.append(T.box((0.2, 0.05, 0.022), (0.88 * math.cos(a2), 0.88 * math.sin(a2), 0.072), rot=(0, 0, 45 * k + 90), mat=T.glow((1, 1, 1))))
off = finish("pad", parts)

# ---------------------------------------------------------------- bake, weather, export
objs = [o for (o, _) in items.values()]
print("triangles:", {n: T.tri_count([o]) for n, (o, _) in items.items()})
T.unwrap(objs, margin=0.003)
if "--nobake" not in sys.argv:  # the UV layout is the same every run, so geometry can be re-exported alone
    g = T.gbuffer(objs, size=2048, ao_dist=0.35, bevel_r=0.008)
    al, nm, orm = T.weather(g, decals, seed=7, dust_from=-9, dust_to=-8, regions=regions, detail=1.0)
    T.save_maps("pickups", al, nm, orm)
for n, (o, off) in items.items():
    o.data.transform(Matrix.Translation(-off))
T.export_glb("pickups", objs)
print("ok")

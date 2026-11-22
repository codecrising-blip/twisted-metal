"""Brimstone (round 28): Jedediah's car, TM Black (owner's roster table: vehicle from Black).
  Shape: the TMB mesh (docs/reference/3d_models/twisted-metal-black.zip) measured at 5.5 m long (177 px/m on the
  scratch sheet): a '70s coupe utility (El Camino): long hood, short cab with a raked windshield and a near-upright
  back window, an open bed behind it, quad round headlamps, a thin bumper. On it: a big wooden cross lying on the
  hood whose foot is a sharpened, blood-soaked stake running a metre past the nose, chains over the hood and
  fenders, a cross hanging on each door with a sharpened foot, a twin gun with a ring sight on the bed's left rail.
  Colours from the TMB render (docs/reference/TMBBrimstoneRender.webp) and its select screen
  (docs/reference/brimestone.jpeg): dirty cream paint eaten by rust, stained-glass windows (lead lines, deep
  blue / purple / red / green / amber), dark wood. TMB's own wear is kept.
  Round 28 gameplay: a Sinner chained kneeling in the bed (node bed_sinner: shown while a Sinner Bomber is
  loaded), the throw starts at marker m_meta_sinner, the Hellfire Sermon's crown of fire sits on the roof at
  m_meta_bell (no bell is modelled: nothing invented on the car itself).
    /tmp/bpy3.13/bin/python tools/blender/build_brimstone.py
    /tmp/bpy3.13/bin/python tools/blender/build_brimstone.py --shape a.png
Blender space: +Y forward, +Z up. Nodes: body, wheel_f, wheel_r, bed_sinner; markers m_wheel_*, m_gun_l/r,
m_launcher, m_top, m_head, m_exh_l/r, m_meta_sinner, m_meta_bell."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
import carkit as K
import numpy as np
from mathutils import Matrix, Vector
from PIL import Image

T.reset()
V = Vector
random.seed(11)
paint = T.M("paint", (0.36, 0.33, 0.25), wear=0.55, rust=0.75, dirt=0.55, rough=0.6, name="br_paint")
stake_w = T.M("wood", (0.12, 0.025, 0.02), dirt=0.3)
wood = T.M("wood", (0.15, 0.085, 0.045), dirt=0.45)
chrome = T.M("chrome", (0.4, 0.39, 0.37), wear=0.0, rust=0.5, dirt=0.4)
dark = T.M("steel", (0.015, 0.015, 0.014), wear=0.3, rust=0.4, dirt=0.4)
gun = T.M("steel", (0.06, 0.06, 0.06), wear=0.3, rust=0.3, dirt=0.3, rough=0.4)
chain_m = T.M("steel", (0.12, 0.11, 0.1), wear=0.2, rust=0.6, dirt=0.3)
glassy = T.M("glassy", (0.03, 0.03, 0.035), wear=0.0, rust=0.0, dirt=0.4)
stained = T.M("glassy", (0.2, 0.2, 0.2), wear=0.0, rust=0.0, dirt=0.25, name="br_stained")
rubber = T.M("rubber", (0.016, 0.016, 0.016), dirt=0.4)
rim = T.M("steel", (0.035, 0.035, 0.035), wear=0.3, rust=0.4, dirt=0.4)
lamp = T.glow((0.95, 0.9, 0.7))
red = T.glow((0.8, 0.05, 0.03))
skin = T.M("plastic", (0.42, 0.36, 0.31), wear=0.0, dirt=0.5, rough=0.65)
burlap = T.M("cloth", (0.28, 0.22, 0.13), dirt=0.5)
rags = T.M("cloth", (0.06, 0.055, 0.05), dirt=0.5)
tnt = T.M("plastic", (0.45, 0.05, 0.035), wear=0.2, dirt=0.4, rough=0.6)
markers = []
decals = []

L = 5.5
TAIL, NOSE = -L / 2, L / 2
R = 0.4
RA, FA = -1.41, 1.9
TW = 0.82
HW = 1.08
BED_Z = 0.76
body = []


def y_(d):
    return TAIL + d


# ---------------------------------------------------------------- body: one loft tail -> nose, the bed cut out
rows = [(0.0, 1.03, 0.5, 1.06), (0.08, 1.07, 0.44, 1.1), (1.0, HW, 0.42, 1.11), (2.4, HW, 0.42, 1.11), (3.6, HW, 0.42, 1.12),
        (4.6, 1.07, 0.44, 1.08), (5.3, 1.05, 0.48, 1.03), (5.5, 1.0, 0.52, 0.98)]
lb = T.loft([K.section(y_(d), hw, zb, zt, c=0.06, tuck=0.06, crease=0.68, lip=0.025) for (d, hw, zb, zt) in rows], mat=paint, angle=32.0)
for sx in (1, -1):
    for ay in (RA, FA):
        T.cut(lb, T.cyl(R + 0.08, 0.6, loc=(sx * (TW + 0.25), ay, R - 0.02), rot=(0, 90, 0), n=28))
T.cut(lb, T.box((1.86, 2.18, 0.6), loc=(0, y_(1.2), BED_Z + 0.3)))   # the open bed
body.append(lb)
body.append(T.box((1.86, 2.18, 0.03), loc=(0, y_(1.2), BED_Z + 0.015), mat=dark))   # bed floor (ribbed below)
for k in range(6):
    body.append(T.box((0.04, 2.1, 0.02), loc=((k - 2.5) * 0.3, y_(1.2), BED_Z + 0.04), mat=paint))
body.append(T.box((1.95, 0.05, 0.02), loc=(0, y_(0.09), 1.1), mat=chrome))   # tailgate top trim
# the cab: short, raked windshield, near-upright back window
cab_rows = [(2.28, 1.0, 0.98, 1.11), (2.45, 1.0, 0.84, 1.48), (2.95, 1.0, 0.82, 1.49), (3.6, 1.02, 1.0, 1.11)]
body.append(T.loft([[(hb, y_(d), 1.08), (ht, y_(d), zt), (-ht, y_(d), zt), (-hb, y_(d), 1.08)] for (d, hb, ht, zt) in cab_rows], mat=paint, angle=30.0))


def stained_glass(w, h, cells, seed):
    """Stained glass as a picture: coloured cells (deep blue, purple, red, green, amber) in black leading."""
    rng = np.random.default_rng(seed)
    pts = rng.random((cells, 2)) * (w, h)
    pal = np.array([(40, 50, 170), (95, 40, 150), (170, 25, 30), (35, 120, 60), (210, 140, 30), (60, 110, 190), (130, 30, 90)], dtype=np.float32)
    cols = pal[rng.integers(0, len(pal), cells)] * rng.uniform(0.75, 1.1, (cells, 1))
    yy, xx = np.mgrid[0:h, 0:w]
    d = (xx[..., None] - pts[:, 0]) ** 2 + (yy[..., None] - pts[:, 1]) ** 2
    lab = d.argmin(-1)
    img = cols[lab]
    edge = np.zeros((h, w), bool)
    edge[:, 1:] |= lab[:, 1:] != lab[:, :-1]
    edge[1:, :] |= lab[1:, :] != lab[:-1, :]
    for _ in range(2):  # thicken the leading
        e = edge.copy()
        e[1:] |= edge[:-1]
        e[:-1] |= edge[1:]
        e[:, 1:] |= edge[:, :-1]
        e[:, :-1] |= edge[:, 1:]
        edge = e
    img[edge] = (12, 12, 12)
    img[:5], img[-5:], img[:, :5], img[:, -5:] = 12, 12, 12, 12
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).convert("RGBA")


# windshield (stained), side windows (stained), back window (plain dark glass)
wb, wt = V((0.0, y_(3.6), 1.11)), V((0.0, y_(2.95), 1.49))
up_ws = (wt - wb).normalized()
n_ws = up_ws.cross(V((1, 0, 0))).normalized()
if n_ws.y < 0:
    n_ws = -n_ws
p0, p1 = wb.lerp(wt, 0.06) + n_ws * 0.006, wb.lerp(wt, 0.94) + n_ws * 0.006
ws = [tuple(p0 + V((0.92, 0, 0))), tuple(p0 + V((-0.92, 0, 0))), tuple(p1 + V((-0.78, 0, 0))), tuple(p1 + V((0.78, 0, 0)))]
body.append(K.quad(ws, stained))
mid = (p0 + p1) / 2
decals.append(T.Decal(stained_glass(420, 170, 34, 3), tuple(mid), tuple(n_ws), tuple(up_ws), (1.9, (p1 - p0).length + 0.02), depth=0.08, kinds=("glassy",)))
bb, bt = V((0.0, y_(2.28), 1.11)), V((0.0, y_(2.45), 1.48))
p0, p1 = bb.lerp(bt, 0.1) - V((0, 0.006, 0)), bb.lerp(bt, 0.9) - V((0, 0.006, 0))
body.append(K.quad([tuple(p0 + V((-0.8, 0, 0))), tuple(p0 + V((0.8, 0, 0))), tuple(p1 + V((0.7, 0, 0))), tuple(p1 + V((-0.7, 0, 0)))], glassy))


def side_x(z):
    return 1.0 - (1.0 - 0.83) * (z - 1.08) / (1.485 - 1.08) + 0.006


for sx in (1, -1):
    pts = [(sx * side_x(1.15), y_(2.4), 1.15), (sx * side_x(1.15), y_(3.45), 1.15), (sx * side_x(1.43), y_(3.0), 1.43), (sx * side_x(1.43), y_(2.5), 1.43)]
    body.append(K.quad(pts if sx > 0 else list(reversed(pts)), stained))
    decals.append(T.Decal(stained_glass(300, 90, 14, 7 + sx), (sx * side_x(1.29), y_(2.92), 1.29), (sx, 0, 0.3), (0, 0, 1), (1.15, 0.33), depth=0.08, kinds=("glassy",)))
    for d in (2.3, 3.62):  # door seams
        body.append(T.box((0.008, 0.008, 0.6), loc=(sx * (HW + 0.002), y_(d), 0.78), mat=dark))
    body.append(T.box((0.02, 0.14, 0.03), loc=(sx * (HW + 0.01), y_(2.5), 0.98), mat=chrome, bevel=0.005))

# ---------------------------------------------------------------- front: quad lamps, dark grille, emblem, bumper
body.append(T.box((1.6, 0.06, 0.32), loc=(0, NOSE - 0.01, 0.78), mat=dark, bevel=0.01))
for k in range(4):
    body.append(T.box((0.7, 0.02, 0.025), loc=(0, NOSE + 0.02, 0.68 + k * 0.065), mat=chrome))
for sx in (1, -1):
    for lx in (0.58, 0.8):
        body.append(T.cyl(0.085, 0.05, loc=(sx * lx, NOSE + 0.005, 0.8), rot=(-90, 0, 0), mat=chrome, n=16))
        body.append(T.sphere(0.07, loc=(sx * lx, NOSE + 0.025, 0.8), mat=lamp, n=12, scale=(1, 0.4, 1)))
body.append(T.prism([(-0.09, 0.0), (0.09, 0.0), (0.09, 0.08), (0.0, 0.14), (-0.09, 0.08)], 0.03, loc=(0, NOSE - 0.12, 1.0), rot=(0, 0, 0), mat=chrome))   # hood emblem (chevron shield)
body.append(T.box((2.0, 0.1, 0.1), loc=(0, NOSE + 0.04, 0.5), mat=chrome, bevel=0.03))
body.append(T.box((2.0, 0.1, 0.1), loc=(0, TAIL - 0.03, 0.55), mat=chrome, bevel=0.03))
for sx in (1, -1):
    body.append(T.box((0.3, 0.03, 0.12), loc=(sx * 0.75, TAIL - 0.005, 0.72), mat=red, bevel=0.006))
body.append(T.box((0.06, 2.0, 0.03), loc=(0, y_(4.6), 1.1), rot=(-3.0, 0, 0), mat=paint, bevel=0.01))   # hood ridge

# ---------------------------------------------------------------- the cross on the hood: a stake through the nose
foot_a, foot_b = V((0.0, y_(3.75), 1.2)), V((0.0, NOSE + 0.98, 0.96))
sd = (foot_b - foot_a)
body.append(T.box((0.2, sd.length - 0.42, 0.17), loc=tuple(foot_a + sd.normalized() * ((sd.length - 0.42) / 2)), rot=(math.degrees(math.atan2(sd.z, sd.y)), 0, 0), mat=stake_w, bevel=0.01))
tip_from = foot_a + sd.normalized() * (sd.length - 0.42)
body.append(T.cyl(0.13, 0.42, loc=tuple(tip_from + sd.normalized() * 0.21), rot=K.aim(sd), mat=stake_w, n=4, r2=0.004))   # the sharpened point
body.append(T.box((1.4, 0.2, 0.17), loc=(-0.08, y_(3.95), 1.24), rot=(0, 0, 4), mat=wood, bevel=0.01))                          # its arms across the hood
body.append(T.box((0.2, 0.55, 0.17), loc=(0.0, y_(3.45), 1.27), rot=(-4, 0, 0), mat=wood, bevel=0.01))                           # the head against the glass
for sx in (1, -1):  # chains from the cross's arms over the fenders' edge and down their sides
    arm = -0.08 + sx * 0.66
    K.chain(body, (arm, y_(3.92), 1.3), (sx * 1.06, y_(4.15), 1.15), chain_m, sag=0.0, link=0.03)
    K.chain(body, (sx * 1.06, y_(4.15), 1.15), (sx * 1.12, y_(4.25), 0.8), chain_m, sag=0.0, link=0.03)
    K.chain(body, (sx * 0.12, y_(4.5), 1.27), (sx * 1.05, y_(5.0), 1.1), chain_m, sag=0.0, link=0.03)
    K.chain(body, (sx * 1.05, y_(5.0), 1.1), (sx * 1.1, y_(5.05), 0.78), chain_m, sag=0.0, link=0.03)
# a cross hanging on each door, its foot sharpened, on a chain from the window frame
for sx in (1, -1):
    x = sx * (HW + 0.06)
    body.append(T.box((0.08, 0.12, 0.62), loc=(x, y_(3.1), 0.72), mat=wood, bevel=0.008))
    body.append(T.box((0.07, 0.44, 0.11), loc=(x + sx * 0.012, y_(3.1), 0.86), mat=wood, bevel=0.008))
    body.append(T.cyl(0.075, 0.2, loc=(x, y_(3.1), 0.32), rot=(180, 0, 45), mat=wood, n=4, r2=0.003))
    K.chain(body, (sx * (HW + 0.02), y_(2.95), 1.12), (x, y_(3.05), 0.96), chain_m, sag=0.0, link=0.025)
    K.chain(body, (sx * (HW + 0.02), y_(3.25), 1.12), (x, y_(3.15), 0.96), chain_m, sag=0.0, link=0.025)

# ---------------------------------------------------------------- twin gun with a ring sight on the bed's left rail
gx, gz = -1.04, 1.42
body.append(T.box((0.1, 0.12, 0.3), loc=(gx + 0.06, y_(1.75), 1.25), mat=gun, bevel=0.01))
body.append(T.box((0.18, 0.85, 0.16), loc=(gx, y_(1.75), gz), mat=gun, bevel=0.015))
for bx in (-0.045, 0.045):
    body.append(K.rod(V((gx + bx, y_(2.15), gz + 0.02)), V((gx + bx, y_(2.72), gz + 0.02)), 0.022, gun, n=8))
    markers.append(T.marker("m_gun_" + ("l" if bx < 0 else "r"), (gx + bx, y_(2.76), gz + 0.02)))
ring = K.ring_solid([(0.13, -0.008), (0.13, 0.008), (0.11, 0.008), (0.11, -0.008)], gun, 20, "ring")
ring.rotation_euler = (0, 0, math.radians(90))
ring.location = (gx, y_(2.3), gz + 0.2)
body.append(ring)
body.append(K.rod(V((gx, y_(2.3), gz + 0.07)), V((gx, y_(2.3), gz + 0.09)), 0.012, gun, n=6))

# ---------------------------------------------------------------- the Sinner chained in the bed (shown while loaded)
import grimm_rider as GR
S = V((0.0, y_(1.2), BED_Z + 0.02))
sc = GR.Sculpt("sinner_body", res=0.02)
sc.ball(S + V((0, -0.12, 0.12)), 0.15, size=(1.2, 1.0, 0.8))       # hips, sitting back on his heels
for sx in (1, -1):
    sc.chain(S + V((sx * 0.1, -0.1, 0.1)), S + V((sx * 0.12, 0.28, 0.08)), 0.08, 0.065)   # thighs forward
    sc.chain(S + V((sx * 0.12, 0.28, 0.07)), S + V((sx * 0.12, -0.2, 0.05)), 0.06, 0.045)  # shins folded under
sc.ball(S + V((0, -0.04, 0.34)), 0.15, size=(1.2, 0.9, 1.0))       # belly
sc.ball(S + V((0, 0.04, 0.52)), 0.17, size=(1.35, 0.85, 0.9))      # chest, hunched forward
sh = [S + V((sx * 0.2, 0.06, 0.6)) for sx in (1, -1)]
for k, sx in enumerate((1, -1)):
    sc.ball(sh[k], 0.085)
    sc.chain(sh[k], S + V((sx * 0.2, 0.22, 0.42)), 0.065, 0.055)
    sc.chain(S + V((sx * 0.2, 0.22, 0.42)), S + V((sx * 0.06, 0.32, 0.36)), 0.055, 0.045)  # wrists together, chained
bed_sinner = [sc.mesh(skin, ratio=0.15)]
hood = GR.Sculpt("sinner_hood", res=0.016)
hood.ball(S + V((0, 0.1, 0.78)), 0.12, size=(0.95, 1.0, 1.15))
hood.ball(S + V((0, 0.06, 0.66)), 0.11, size=(1.3, 1.0, 0.6))      # the sack's neck, gathered and tied
bed_sinner.append(hood.mesh(burlap, ratio=0.2))
for sx in (1, -1):  # eye holes in the sack
    bed_sinner.append(T.sphere(0.022, loc=tuple(S + V((sx * 0.04, 0.215, 0.8))), mat=dark, n=8, scale=(1, 0.4, 0.7)))
bed_sinner.append(T.box((0.34, 0.26, 0.2), loc=tuple(S + V((0, -0.1, 0.14))), mat=rags, bevel=0.05))   # rags round his hips
for k in range(5):  # dynamite strapped across his chest
    bed_sinner.append(T.cyl(0.03, 0.22, loc=tuple(S + V(((k - 2) * 0.065, 0.17, 0.5))), mat=tnt, n=8))
bed_sinner.append(T.box((0.36, 0.03, 0.04), loc=tuple(S + V((0, 0.2, 0.5))), mat=rags))
for sx in (1, -1):  # chains from his wrists to the bed's sides
    K.chain(bed_sinner, S + V((sx * 0.06, 0.34, 0.36)), (sx * 0.9, y_(1.75), 1.02), chain_m, sag=0.12, link=0.025)
bed_sinner_ob = T.join(bed_sinner, "bed_sinner")

markers.append(T.marker("m_meta_sinner", (0.0, y_(1.3), 1.4)))
markers.append(T.marker("m_meta_bell", (0.0, y_(2.7), 1.5)))
markers.append(T.marker("m_launcher", (0.0, y_(4.3), 1.25)))
markers.append(T.marker("m_top", (0.0, y_(2.7), 1.5)))
markers.append(T.marker("m_head", (0.0, NOSE + 0.03, 0.8)))
for sx in (1, -1):
    markers.append(T.marker("m_exh_" + ("r" if sx > 0 else "l"), (sx * 0.6, TAIL - 0.02, 0.38)))
    body.append(K.rod(V((sx * 0.6, TAIL + 0.15, 0.38)), V((sx * 0.6, TAIL - 0.03, 0.38)), 0.035, dark, n=10))

# ---------------------------------------------------------------- wheels: steel wheels with small hubcaps


def wheel(name):
    parts = K.tyre(R, 0.3, rubber, 30)
    parts.append(K.ring_solid([(R * 0.69, -0.13), (R * 0.69, 0.14), (R * 0.6, 0.12), (R * 0.6, -0.12)], rim, 28))
    parts.append(T.cyl(R * 0.6, 0.02, loc=(0.08, 0, 0), rot=(0, 90, 0), mat=rim, n=24))
    for k in range(6):
        a = 2 * math.pi * k / 6
        parts.append(T.cyl(R * 0.08, 0.025, loc=(0.085, math.cos(a) * R * 0.4, math.sin(a) * R * 0.4), rot=(0, 90, 0), mat=dark, n=8))
    parts.append(T.cyl(R * 0.22, 0.05, loc=(0.11, 0, 0), rot=(0, 90, 0), mat=chrome, n=16, bevel=0.015))
    return T.join(parts, name)


wheel_f = wheel("wheel_f")
wheel_r = wheel("wheel_r")
markers += [T.marker("m_wheel_fr", (TW, FA, R)), T.marker("m_wheel_fl", (-TW, FA, R)),
            T.marker("m_wheel_rr", (TW, RA, R)), T.marker("m_wheel_rl", (-TW, RA, R))]
body_ob = T.join(body, "body")
print("triangles: body %d, wheel %d, sinner %d" % (T.tri_count([body_ob]), T.tri_count([wheel_f]), T.tri_count([bed_sinner_ob])))

if "--shape" in sys.argv:
    out = sys.argv[sys.argv.index("--shape") + 1]
    wf = [T.dup(wheel_f, (TW, FA, R)), T.dup(wheel_f, (-TW, FA, R), rot=(0, 0, 180)), T.dup(wheel_r, (TW, RA, R)), T.dup(wheel_r, (-TW, RA, R), rot=(0, 0, 180))]
    for o in (wheel_f, wheel_r):
        o.location = (0, 0, -50)
    T.preview(out, size=(1100, 600), eye=(-10.0, 0.0, 1.0), look=(0, 0.3, 0.8), fov=40, samples=12)
    T.preview(out.replace(".png", "_f.png"), size=(1100, 600), eye=(0.0, 9.0, 1.4), look=(0, 0, 0.85), fov=34, samples=12)
    T.preview(out.replace(".png", "_b.png"), size=(1100, 600), eye=(0.0, -8.0, 3.0), look=(0, 0, 0.9), fov=34, samples=12)
    T.preview(out.replace(".png", "_q.png"), size=(1100, 600), eye=(-5.0, 6.0, 3.4), look=(0, 0.3, 0.7), fov=40, samples=12)
    sys.exit(0)

import bpy
wheel_f.location = (3.5, 0.9, R)
wheel_r.location = (3.5, -0.9, R)
bpy.context.view_layer.update()
for o in (wheel_f, wheel_r):
    T.apply(o)
objs = [body_ob, wheel_f, wheel_r, bed_sinner_ob]
T.unwrap(objs, margin=0.002)
if "--nobake" not in sys.argv:
    g = T.gbuffer(objs, size=2048, ao_dist=0.5, bevel_r=0.008, ao_samples=20)
    al, nm, orm = T.weather(g, decals, seed=41, dust_from=0.0, dust_to=0.7, regions=[], ao_strength=0.75)
    T.save_maps("brimstone", al, nm, orm)
wheel_f.data.transform(Matrix.Translation((-3.5, -0.9, -R)))
wheel_r.data.transform(Matrix.Translation((-3.5, 0.9, -R)))
T.export_glb("brimstone", objs, markers=markers)
print("ok", T.tri_count(objs))

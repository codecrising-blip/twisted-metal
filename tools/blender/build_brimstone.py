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
Round 29 (owner's two design sheets, docs/reference/owner_sheets/brimstone_*.webp): iron cross and door crosses,
chain-wrapped spiked ram bar, two rotary guns on the bed firing over the cab plus one on the left side,
cross-spoked wheels, painted scripture and crosses, lit stained glass (its own
picture, ModelLib slot "stained"), and the sinner huddled in a caged well on a launch plate (node bed_plate).
Blender space: +Y forward, +Z up. Nodes: body, wheel_f, wheel_r, bed_sinner, bed_plate; markers m_wheel_*, m_gun_l/r,
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
from PIL import Image, ImageDraw

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
rubber = T.M("rubber", (0.016, 0.016, 0.016), dirt=0.4)
rim = T.M("steel", (0.035, 0.035, 0.035), wear=0.3, rust=0.4, dirt=0.4)
lamp = T.glow((0.95, 0.9, 0.7))
red = T.glow((0.8, 0.05, 0.03))
skin = T.M("plastic", (0.42, 0.36, 0.31), wear=0.0, dirt=0.5, rough=0.65)
burlap = T.M("cloth", (0.28, 0.22, 0.13), dirt=0.5)
rags = T.M("cloth", (0.06, 0.055, 0.05), dirt=0.5)
tnt = T.M("plastic", (0.45, 0.05, 0.035), wear=0.2, dirt=0.4, rough=0.6)
iron = T.M("steel", (0.08, 0.055, 0.045), wear=0.5, rust=0.85, dirt=0.5, rough=0.7, name="br_iron")
import bpy
STAINED = bpy.data.materials.new("stained") # round 29: lit stained glass, its own picture (brimstone_stained.png)
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
body.append(K.quad(ws, STAINED))
bb, bt = V((0.0, y_(2.28), 1.11)), V((0.0, y_(2.45), 1.48))
p0, p1 = bb.lerp(bt, 0.1) - V((0, 0.006, 0)), bb.lerp(bt, 0.9) - V((0, 0.006, 0))
body.append(K.quad([tuple(p0 + V((-0.8, 0, 0))), tuple(p0 + V((0.8, 0, 0))), tuple(p1 + V((0.7, 0, 0))), tuple(p1 + V((-0.7, 0, 0)))], glassy))


def side_x(z):
    return 1.0 - (1.0 - 0.83) * (z - 1.08) / (1.485 - 1.08) + 0.006


for sx in (1, -1):
    pts = [(sx * side_x(1.15), y_(2.4), 1.15), (sx * side_x(1.15), y_(3.45), 1.15), (sx * side_x(1.43), y_(3.0), 1.43), (sx * side_x(1.43), y_(2.5), 1.43)]
    body.append(K.quad(pts if sx > 0 else list(reversed(pts)), STAINED))
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
body.append(T.box((2.1, 0.12, 0.16), loc=(0, NOSE + 0.2, 0.44), mat=iron, bevel=0.02))      # iron ram bar over the bumper
for x in (-0.95, -0.45, 0.0, 0.45, 0.95):                                                       # its spikes
    body.append(T.cyl(0.045, 0.22, loc=(x, NOSE + 0.36, 0.44), rot=(-90, 0, 0), mat=iron, n=6, r2=0.004))
for sx in (1, -1):
    body.append(T.box((0.1, 0.1, 0.42), loc=(sx * 0.8, NOSE + 0.19, 0.48), mat=iron, bevel=0.01))  # guards up the corners
    K.chain(body, (sx * 0.95, NOSE + 0.27, 0.53), (sx * 0.1, NOSE + 0.27, 0.53), chain_m, sag=0.1, link=0.028)
body.append(T.box((2.0, 0.1, 0.1), loc=(0, TAIL - 0.03, 0.55), mat=chrome, bevel=0.03))
for sx in (1, -1):
    body.append(T.box((0.3, 0.03, 0.12), loc=(sx * 0.75, TAIL - 0.005, 0.72), mat=red, bevel=0.006))
body.append(T.box((0.06, 2.0, 0.03), loc=(0, y_(4.6), 1.1), rot=(-3.0, 0, 0), mat=paint, bevel=0.01))   # hood ridge

# ---------------------------------------------------------------- the cross on the hood: a stake through the nose
foot_a, foot_b = V((0.0, y_(3.75), 1.2)), V((0.0, NOSE + 0.98, 0.96))
sd = (foot_b - foot_a)
body.append(T.box((0.2, sd.length - 0.42, 0.17), loc=tuple(foot_a + sd.normalized() * ((sd.length - 0.42) / 2)), rot=(math.degrees(math.atan2(sd.z, sd.y)), 0, 0), mat=iron, bevel=0.01))
tip_from = foot_a + sd.normalized() * (sd.length - 0.42)
body.append(T.cyl(0.13, 0.42, loc=tuple(tip_from + sd.normalized() * 0.21), rot=T.aim(sd), mat=stake_w, n=4, r2=0.004))   # the sharpened point
body.append(T.box((1.4, 0.2, 0.17), loc=(-0.08, y_(3.95), 1.24), rot=(0, 0, 4), mat=iron, bevel=0.01))                          # its iron arms across the hood
body.append(T.box((0.2, 0.55, 0.17), loc=(0.0, y_(3.45), 1.27), rot=(-4, 0, 0), mat=iron, bevel=0.01))                           # the head against the glass
for (cx, cy) in ((-0.68, 3.97), (0.52, 3.93), (0.0, 3.5), (0.0, 4.4)):                                                            # rivets where it is welded
    body.append(T.sphere(0.03, loc=(cx, y_(cy), 1.33), mat=iron, n=8, scale=(1, 1, 0.6)))
for sx in (1, -1):  # chains from the cross's arms over the fenders' edge and down their sides
    arm = -0.08 + sx * 0.66
    K.chain(body, (arm, y_(3.92), 1.3), (sx * 1.06, y_(4.15), 1.15), chain_m, sag=0.0, link=0.03)
    K.chain(body, (sx * 1.06, y_(4.15), 1.15), (sx * 1.12, y_(4.25), 0.8), chain_m, sag=0.0, link=0.03)
    K.chain(body, (sx * 0.12, y_(4.5), 1.27), (sx * 1.05, y_(5.0), 1.1), chain_m, sag=0.0, link=0.03)
    K.chain(body, (sx * 1.05, y_(5.0), 1.1), (sx * 1.1, y_(5.05), 0.78), chain_m, sag=0.0, link=0.03)
# a welded iron cross on each door (owner's sheet), its foot a spike past the sill
for sx in (1, -1):
    x = sx * (HW + 0.03)
    body.append(T.box((0.05, 0.15, 0.82), loc=(x, y_(3.05), 0.66), mat=iron, bevel=0.01))
    body.append(T.box((0.045, 0.52, 0.13), loc=(x + sx * 0.012, y_(3.05), 0.88), mat=iron, bevel=0.01))
    body.append(T.cyl(0.075, 0.24, loc=(x, y_(3.05), 0.15), rot=(180, 0, 45), mat=iron, n=4, r2=0.003))
    for (dy, dz) in ((0, 1.0), (0, 0.33), (-0.2, 0.88), (0.2, 0.88)):
        body.append(T.sphere(0.022, loc=(x + sx * 0.03, y_(3.05) + dy, dz), mat=iron, n=6, scale=(0.5, 1, 1)))

# ---------------------------------------------------------------- "holy fire": rotary guns on the bed, firing over the cab


def gatling(at, length, mat, parts, n=6, r=0.055):
    at = V(at)
    parts.append(T.box((0.2, 0.36, 0.2), loc=tuple(at), mat=mat, bevel=0.02))
    for k in range(n):
        a = 2 * math.pi * k / n
        o = V((math.cos(a) * r, 0, math.sin(a) * r))
        parts.append(K.rod(at + o + V((0, 0.15, 0)), at + o + V((0, length, 0)), 0.016, mat, n=6))
    for d in (0.4, length - 0.05):
        parts.append(T.cyl(r + 0.03, 0.04, loc=tuple(at + V((0, d, 0))), rot=(-90, 0, 0), mat=mat, n=12))


for sx in (1, -1):
    x, y0 = sx * 0.62, y_(2.0)
    body.append(T.cyl(0.05, 0.62, loc=(x, y0, BED_Z + 0.31), mat=iron, n=10))
    body.append(T.cyl(0.11, 0.06, loc=(x, y0, BED_Z + 0.64), mat=iron, n=12))
    gatling((x, y0, 1.66), 1.15, gun, body)
    body.append(T.box((0.18, 0.2, 0.16), loc=(x - sx * 0.16, y0 - 0.05, 1.6), mat=iron, bevel=0.01))   # ammo drum box
    markers.append(T.marker("m_gun_" + ("r" if sx > 0 else "l"), (x, y0 + 1.2, 1.66)))
gatling((-HW - 0.12, y_(1.2), 1.0), 0.95, gun, body)                    # the one bolted to the bed's left side
body.append(T.box((0.12, 0.3, 0.24), loc=(-HW - 0.03, y_(1.2), 0.96), mat=iron, bevel=0.01))
# Round 30 (owner): no incense stacks and no brazier on the bed, only the chained sinner. The exhaust is
# a pair of plain tailpipes under the rear bumper.
for sx in (1, -1):
    body.append(T.cyl(0.05, 0.3, loc=(sx * 0.58, y_(0.12), 0.32), rot=(90, 0, 0), mat=iron, n=10))
    markers.append(T.marker("m_exh_" + ("r" if sx > 0 else "l"), (sx * 0.58, y_(0.0), 0.32)))

# ---------------------------------------------------------------- the sinner's well (owner's second sheet)
# A pit sunk into the bed behind a ring of spiked iron bars; the sinner huddles in it, chained, on the floor plate
# that throws him out (node bed_plate: the game kicks it up at the throw). He is shown while one is loaded.
import grimm_rider as GR
PY0, PIT, DEPTH = y_(0.98), 0.92, 0.32
T.cut(lb, T.box((PIT, PIT, DEPTH + 0.1), loc=(0, PY0, BED_Z - DEPTH / 2 + 0.05)))
for sx in (1, -1):  # the well's iron walls
    body.append(T.box((0.03, PIT, DEPTH), loc=(sx * PIT / 2, PY0, BED_Z - DEPTH / 2), mat=iron))
    body.append(T.box((PIT, 0.03, DEPTH), loc=(0, PY0 + sx * PIT / 2, BED_Z - DEPTH / 2), mat=iron))
nb = 7
for k in range(nb):  # spiked bars round the rim
    t = (k + 0.5) / nb - 0.5
    for (bx, by) in ((t * PIT, PIT / 2), (t * PIT, -PIT / 2), (PIT / 2, t * PIT), (-PIT / 2, t * PIT)):
        body.append(T.cyl(0.014, 0.5, loc=(bx, PY0 + by, BED_Z + 0.25), mat=iron, n=6))
        body.append(T.cyl(0.024, 0.08, loc=(bx, PY0 + by, BED_Z + 0.54), mat=iron, n=5, r2=0.002))
for sx in (1, -1):
    body.append(T.box((PIT + 0.04, 0.035, 0.035), loc=(0, PY0 + sx * PIT / 2, BED_Z + 0.4), mat=iron))
    body.append(T.box((0.035, PIT + 0.04, 0.035), loc=(sx * PIT / 2, PY0, BED_Z + 0.4), mat=iron))
plate_z = BED_Z - DEPTH + 0.02
bed_plate_ob = T.join([T.box((PIT - 0.06, PIT - 0.06, 0.04), loc=(0, PY0, plate_z), mat=iron, bevel=0.005)] +
                      [T.box((PIT - 0.1, 0.02, 0.012), loc=(0, PY0 + (k - 2) * 0.16, plate_z + 0.025), mat=dark) for k in range(5)], "bed_plate")
markers.append(T.marker("m_bed_plate", (0, PY0, plate_z)))
S = V((0.0, PY0 - 0.12, plate_z + 0.02))
sc = GR.Sculpt("sinner_body", res=0.02)
sc.ball(S + V((0, -0.04, 0.13)), 0.15, size=(1.25, 1.0, 0.8))         # sitting on the plate
for sx in (1, -1):
    knee = S + V((sx * 0.1, 0.26, 0.48))
    sc.chain(S + V((sx * 0.1, 0.0, 0.12)), knee, 0.08, 0.06)            # thighs drawn up to the chest
    sc.chain(knee, S + V((sx * 0.1, 0.34, 0.05)), 0.058, 0.045)         # shins down to the plate
sc.ball(S + V((0, 0.0, 0.32)), 0.14, size=(1.2, 0.9, 1.0))
sc.ball(S + V((0, 0.07, 0.5)), 0.16, size=(1.3, 0.85, 0.9))            # chest bent over the knees
for sx in (1, -1):
    shoulder = S + V((sx * 0.19, 0.06, 0.6))
    elbow = S + V((sx * 0.22, 0.3, 0.5))
    sc.ball(shoulder, 0.08)
    sc.chain(shoulder, elbow, 0.06, 0.05)                               # arms round the knees
    sc.chain(elbow, S + V((-sx * 0.05, 0.4, 0.44)), 0.05, 0.04)         # hands locked in front of the shins
bed_sinner = [sc.mesh(skin, ratio=0.15)]
hood = GR.Sculpt("sinner_hood", res=0.016)
hood.ball(S + V((0, 0.22, 0.7)), 0.12, size=(0.95, 1.05, 1.1))         # the sacked head, bowed onto the knees
hood.ball(S + V((0, 0.14, 0.64)), 0.1, size=(1.3, 1.0, 0.6))
bed_sinner.append(hood.mesh(burlap, ratio=0.2))
bed_sinner.append(T.box((0.36, 0.3, 0.18), loc=tuple(S + V((0, -0.02, 0.12))), mat=rags, bevel=0.05))
for k in range(5):  # dynamite strapped across his back
    bed_sinner.append(T.cyl(0.03, 0.22, loc=tuple(S + V(((k - 2) * 0.065, -0.12, 0.5))), rot=(0, 90, 0), mat=tnt, n=8))
for sx in (1, -1):  # chains from his wrists to the bars
    K.chain(bed_sinner, S + V((sx * 0.05, 0.42, 0.44)), (sx * PIT / 2, PY0 + PIT * 0.3, BED_Z + 0.3), chain_m, sag=0.1, link=0.022)
bed_sinner_ob = T.join(bed_sinner, "bed_sinner")



def scripture(w=900, h=200, seed=5):
    """Hand-painted scripture (owner's sheet): lines of rough brush script, not readable words."""
    rng = np.random.default_rng(seed)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for line in range(4):
        y = 22 + line * 44
        x = 14
        while x < w - 30:
            ww = int(rng.integers(6, 22))
            pts = [(x + i * 4, y + int(rng.integers(-9, 9))) for i in range(max(2, ww // 4))]
            d.line(pts, fill=(22, 14, 10, 235), width=int(rng.integers(3, 6)))
            if rng.random() < 0.3:
                d.line([(x, y - 12), (x, y + 10)], fill=(22, 14, 10, 235), width=3)
            x += ww + int(rng.integers(3, 9))
            if rng.random() < 0.12:
                x += 18
    return im


def painted_cross(px=96):
    im = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((px * 0.42, px * 0.08, px * 0.58, px * 0.92), fill=(35, 18, 12, 230))
    d.rectangle((px * 0.18, px * 0.3, px * 0.82, px * 0.44), fill=(35, 18, 12, 230))
    return im


for sx in (1, -1):
    decals.append(T.Decal(scripture(seed=5 + sx), (sx * HW, y_(1.15), 0.86), (sx, 0, 0), (0, 0, 1), (1.9, 0.38), depth=0.06, kinds=("paint",), opacity=0.85))
    for cy in (4.85, 0.45):
        decals.append(T.Decal(painted_cross(), (sx * HW, y_(cy), 0.78), (sx, 0, 0), (0, 0, 1), (0.22, 0.22), depth=0.06, kinds=("paint",)))

markers.append(T.marker("m_meta_sinner", (0.0, y_(1.3), 1.4)))
markers.append(T.marker("m_meta_bell", (0.0, y_(2.7), 1.5)))
markers.append(T.marker("m_launcher", (0.0, y_(4.3), 1.25)))
markers.append(T.marker("m_top", (0.0, y_(2.7), 1.5)))
markers.append(T.marker("m_head", (0.0, NOSE + 0.03, 0.8)))


# ---------------------------------------------------------------- wheels: steel wheels with small hubcaps


def wheel(name):
    parts = K.tyre(R, 0.3, rubber, 30)
    parts.append(K.ring_solid([(R * 0.69, -0.13), (R * 0.69, 0.14), (R * 0.6, 0.12), (R * 0.6, -0.12)], rim, 28))
    parts.append(T.cyl(R * 0.6, 0.02, loc=(0.08, 0, 0), rot=(0, 90, 0), mat=rim, n=24))
    parts.append(T.cyl(R * 0.55, 0.015, loc=(0.092, 0, 0), rot=(0, 90, 0), mat=dark, n=24))  # dark between the spokes
    for k in range(4):  # the cross of spokes (owner's sheet: cross-spoked wheels)
        a = math.pi / 2 * k
        parts.append(T.box((0.03, R * 0.13, R * 0.55), loc=(0.1, math.cos(a) * R * 0.3, math.sin(a) * R * 0.3), rot=(math.degrees(a) - 90, 0, 0), mat=rim, bevel=0.006))
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
objs = [body_ob, wheel_f, wheel_r, bed_sinner_ob, bed_plate_ob]
T.unwrap(objs, margin=0.002)
if "--nobake" not in sys.argv:
    g = T.gbuffer(objs, size=2048, ao_dist=0.5, bevel_r=0.008, ao_samples=20)
    al, nm, orm = T.weather(g, decals, seed=41, dust_from=0.0, dust_to=0.7, regions=[], ao_strength=0.75)
    T.save_maps("brimstone", al, nm, orm)
    stained_glass(640, 320, 42, 3).convert("RGB").save(os.path.join(T.OUT, "brimstone_stained.png"))
# The stained panes read their own picture, mapped flat across each face (only after the bake: faces covering
# the whole 0..1 square would be baked over every other island).
me = body_ob.data
slot = [i for i, m in enumerate(me.materials) if m == STAINED]
if slot:
    uv = me.uv_layers.active.data
    for poly in me.polygons:
        if poly.material_index != slot[0]:
            continue
        nrm = poly.normal
        ax = V((1, 0, 0)) if abs(nrm.x) < 0.7 else V((0, 1, 0))
        ay = nrm.cross(ax).normalized()
        ax = ay.cross(nrm).normalized()
        cs = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
        us = [c.dot(ax) for c in cs]
        vs = [c.dot(ay) for c in cs]
        for li, u_, v_ in zip(poly.loop_indices, us, vs):
            uv[li].uv = ((u_ - min(us)) / max(max(us) - min(us), 1e-4), (v_ - min(vs)) / max(max(vs) - min(vs), 1e-4))
wheel_f.data.transform(Matrix.Translation((-3.5, -0.9, -R)))
wheel_r.data.transform(Matrix.Translation((-3.5, 0.9, -R)))
T.export_glb("brimstone", objs, markers=markers)
print("ok", T.tri_count(objs))

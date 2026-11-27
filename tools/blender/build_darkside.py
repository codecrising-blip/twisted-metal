"""Darkside (round 28; round 30 from the owner's design sheet: welded POLICE plow with teeth and an anchor
chain, tubular grille guard, twin quad rocket pods and marker lamps on the roof, armoured louvres over the
glass, a roll-cage hoop, rotary guns on the front fenders, more rust). Mr. Ash's semi tractor, TM Black (owner's roster table: vehicle from Black).
  Shape: the TMB mesh in docs/reference/3d_models/twisted-metal-black.zip, ortho views measured at 7.6 m long
  (127 px/m on the scratch sheet): a long-nosed conventional tractor with a flat-topped sleeper cab (roof 2.26 m),
  two tall stacks with perforated heat shields at the cab's back corners, fuel tanks / steps under the cab, a long
  hood with sloped sides and flared front fenders, a dull chrome grille, a crushed POLICE cruiser front chained to
  the nose as his ram plate (2.9 m wide), a gatling on each side beside the hood, a flat rear deck with the fifth
  wheel and the air lines behind the sleeper, tandem rear axles on dual wheels, mud flaps.
  Colours from the TMB render (docs/reference/TMBDarksideRender2.webp): dark gunmetal with rust spots, black
  ram plate, dull chrome. TMB's own wear is kept (the original is weathered).
  The red slit (round 28 gameplay: it flares during the Darkside Slam) is a thin glow under the visor plates
  (node "slit", scaled about marker m_slit).
    /tmp/bpy3.13/bin/python tools/blender/build_darkside.py
    /tmp/bpy3.13/bin/python tools/blender/build_darkside.py --shape a.png
Blender space: +Y forward, +Z up. Nodes: body, wheel_f, wheel_r, slit; markers m_wheel_fr/fl/rr/rl/rr2/rl2,
m_gun_l/r, m_launcher, m_top, m_head, m_exh_l/r (stack tops), m_slit."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
import carkit as K
from mathutils import Matrix, Vector

T.reset()
V = Vector
random.seed(7)
paint = T.M("paint", (0.034, 0.037, 0.047), wear=0.18, rust=0.22, dirt=0.3, rough=0.5, name="ds_paint")
plow = T.M("steel", (0.05, 0.048, 0.045), wear=0.35, rust=0.45, dirt=0.4, rough=0.55, name="ds_plow")
chrome = T.M("chrome", (0.42, 0.43, 0.44), wear=0.0, rust=0.3, dirt=0.3)
shield = T.M("steel", (0.3, 0.3, 0.3), wear=0.2, rust=0.25, dirt=0.3, rough=0.45)
dark = T.M("steel", (0.025, 0.025, 0.027), wear=0.4, rust=0.45, dirt=0.4)
gun = T.M("steel", (0.06, 0.06, 0.062), wear=0.3, rust=0.2, dirt=0.2, rough=0.35)
chain_m = T.M("steel", (0.12, 0.11, 0.1), wear=0.2, rust=0.6, dirt=0.3)
glassy = T.M("glassy", (0.02, 0.02, 0.022), wear=0.0, rust=0.0, dirt=0.3)
rubber = T.M("rubber", (0.016, 0.016, 0.016), dirt=0.3)
rim = T.M("steel", (0.03, 0.03, 0.032), wear=0.3, rust=0.3, dirt=0.4)
lamp = T.glow((0.95, 0.92, 0.8))
red = T.glow((0.85, 0.05, 0.03))
amber = T.glow((0.95, 0.55, 0.1))
markers = []
decals = []

L = 7.6
TAIL, NOSE = -L / 2, L / 2
RF, RR = 0.47, 0.5
FA, RA1, RA2 = 2.51, -1.95, -3.05     # front axle, rear axles
TF, TR = 1.02, 1.1                    # wheel centres across (rear: the middle of the dual pair)
HW = 1.2                              # the cab's half width
body = []


def y_(d):
    return TAIL + d


def rect(y, hw, zb, zt, c=0.06):
    return [(hw - c, y, zb), (hw, y, zb + c), (hw, y, zt - c), (hw - c, y, zt), (-hw + c, y, zt), (-hw, y, zt - c), (-hw, y, zb + c), (-hw + c, y, zb)]


# ---------------------------------------------------------------- chassis: rails, rear deck, fifth wheel, bumper, flaps
for sx in (1, -1):
    body.append(T.box((0.22, 6.9, 0.32), loc=(sx * 0.5, y_(3.6), 0.72), mat=dark, bevel=0.01))
body.append(T.box((1.5, 2.5, 0.1), loc=(0, y_(1.45), 1.08), mat=dark, bevel=0.01))
body.append(T.cyl(0.62, 0.08, loc=(0, y_(1.75), 1.17), mat=dark, n=24, bevel=0.01))
body.append(T.box(((0.2, 0.62, 0.03)), loc=(0, y_(1.42), 1.215), mat=rubber))   # the coupler's throat
body.append(T.box((2.3, 0.2, 0.42), loc=(0, TAIL + 0.1, 0.62), mat=dark, bevel=0.02))
for sx in (1, -1):
    for k, c in enumerate((red, red, amber)):
        body.append(T.box((0.12, 0.03, 0.08), loc=(sx * (0.95 - k * 0.15), TAIL - 0.005, 0.7), mat=c, bevel=0.005))
    body.append(T.box((0.62, 0.025, 0.55), loc=(sx * TR, TAIL + 0.15, 0.5), mat=rubber))                      # mud flaps
    body.append(T.box((0.66, 1.75, 0.04), loc=(sx * TR, y_(1.35), 1.13), mat=dark, bevel=0.008))            # flat fenders over the duals
# air lines and the deck plate's rack behind the sleeper
body.append(T.box((1.3, 0.35, 0.5), loc=(0, y_(2.45), 1.38), mat=dark, bevel=0.02))
body.append(T.box((1.7, 0.08, 0.95), loc=(0, y_(2.62), 1.6), mat=dark, bevel=0.01))
for sx, c in ((0.25, red), (-0.25, T.M("plastic", (0.25, 0.2, 0.03), wear=0.2, dirt=0.4))):
    p = [V((sx, y_(2.66), 1.9)), V((sx * 1.4, y_(2.45), 1.75)), V((sx * 1.2, y_(2.1), 1.3)), V((sx * 0.6, y_(1.9), 1.22))]
    for a, b in zip(p, p[1:]):
        body.append(K.rod(a, b, 0.022, c if c is not red else T.M("plastic", (0.3, 0.02, 0.02), wear=0.2, dirt=0.4), n=8))

# ---------------------------------------------------------------- sleeper cab: one block, raked windshield
cab = [rect(y_(2.68), HW, 0.95, 2.22), rect(y_(4.9), HW, 0.95, 2.26), rect(y_(5.08), HW, 0.95, 2.24), rect(y_(5.36), HW, 0.95, 1.74)]
body.append(T.loft(cab, mat=paint, angle=35.0))
for sx in (1, -1):  # door seam, sleeper seam, rivet rows, door handle, step plate
    body.append(T.box((0.01, 0.01, 1.1), loc=(sx * (HW + 0.002), y_(3.95), 1.5), mat=dark))
    body.append(T.box((0.01, 0.01, 1.1), loc=(sx * (HW + 0.002), y_(5.12), 1.45), mat=dark))
    for k in range(10):
        body.append(T.sphere(0.022, loc=(sx * (HW + 0.005), y_(2.78 + k * 0.12), 2.12), mat=dark, n=6, scale=(0.5, 1, 1)))
        body.append(T.sphere(0.022, loc=(sx * (HW + 0.005), y_(2.78 + k * 0.12), 1.05), mat=dark, n=6, scale=(0.5, 1, 1)))
    body.append(T.box((0.03, 0.18, 0.04), loc=(sx * (HW + 0.015), y_(4.2), 1.5), mat=chrome, bevel=0.008))
    # side window: dark glass inset on the door
    pts = [(sx * (HW + 0.004), y_(4.15), 1.78), (sx * (HW + 0.004), y_(4.95), 1.78), (sx * (HW + 0.004), y_(4.95), 2.12), (sx * (HW + 0.004), y_(4.15), 2.12)]
    body.append(K.quad(pts if sx > 0 else list(reversed(pts)), glassy))
    # mirror on its arms at the cab's front corner
    body.append(K.rod(V((sx * HW, y_(5.2), 1.95)), V((sx * 1.52, y_(5.3), 1.95)), 0.018, chrome, n=6))
    body.append(K.rod(V((sx * HW, y_(5.2), 1.6)), V((sx * 1.52, y_(5.3), 1.7)), 0.018, chrome, n=6))
    body.append(T.box((0.08, 0.06, 0.42), loc=(sx * 1.55, y_(5.3), 1.82), mat=dark, bevel=0.015))
# the windshield, split by a post, under two angled visor plates (the "brows"), the red slit between them
ws_b, ws_t = V((0.0, y_(5.36), 1.76)), V((0.0, y_(5.08), 2.2))
nrm = (ws_t - ws_b).cross(V((1, 0, 0))).normalized()
if nrm.y < 0:
    nrm = -nrm
for sx in (1, -1):
    a, b = ws_b + V((sx * 0.06, 0, 0)), ws_b + V((sx * 1.06, 0, 0))
    c, d = ws_t + V((sx * 1.02, 0, 0)) - (ws_t - ws_b) * 0.05, ws_t + V((sx * 0.06, 0, 0)) - (ws_t - ws_b) * 0.05
    pts = [tuple(p + nrm * 0.006) for p in (a, b, c, d)]
    body.append(K.quad(pts if sx > 0 else list(reversed(pts)), glassy))
    # visor plate: hangs off the roof edge, angled down toward the middle
    vz = 2.08
    body.append(T.box((1.0, 0.36, 0.045), loc=(sx * 0.56, y_(5.24), vz), rot=(28, sx * 9, 0), mat=paint, bevel=0.01))
body.append(T.box((0.1, 0.06, 0.48), loc=(0, y_(5.22), 1.98), rot=(-32, 0, 0), mat=paint, bevel=0.01))   # centre post
slit_at = (0.0, y_(5.33), 1.93)
slit = T.box((1.5, 0.02, 0.025), loc=slit_at, rot=(-32, 0, 0), mat=red, name="slit")
markers.append(T.marker("m_slit", slit_at))

# ---------------------------------------------------------------- stacks with perforated heat shields
for sx in (1, -1):
    x, y = sx * (HW + 0.15), y_(3.92)
    body.append(T.cyl(0.085, 1.75, loc=(x, y, 1.75), mat=dark, n=14))
    body.append(T.cyl(0.09, 0.06, loc=(x, y, 2.6), mat=dark, n=14))
    body.append(T.cyl(0.135, 0.9, loc=(x, y, 1.5), mat=shield, n=16, bevel=0.01))
    for row in range(6):
        for k in range(7):
            a = 2 * math.pi * (k + 0.5 * (row % 2)) / 7
            body.append(T.cyl(0.02, 0.01, loc=(x + math.cos(a) * 0.136, y + math.sin(a) * 0.136, 1.17 + row * 0.12), rot=T.aim((math.cos(a), math.sin(a), 0)), mat=dark, n=5))
    for z in (1.0, 2.0):
        body.append(T.cyl(0.1, 0.05, loc=(x, y, z), mat=chrome, n=14))
    body.append(T.box((0.2, 0.06, 0.06), loc=(x - sx * 0.1, y, 2.0), mat=dark))
    markers.append(T.marker("m_exh_" + ("r" if sx > 0 else "l"), (x, y, 2.66)))

# ---------------------------------------------------------------- fuel tanks / steps under the cab
for sx in (1, -1):
    body.append(T.box((0.42, 2.95, 0.46), loc=(sx * 1.42, y_(4.2), 0.72), mat=paint, bevel=0.04))
    for k in range(3):
        body.append(T.box((0.44, 0.03, 0.47), loc=(sx * 1.42, y_(3.2 + k * 1.0), 0.72), mat=chrome, bevel=0.008))   # straps
    body.append(T.box((0.46, 0.5, 0.03), loc=(sx * 1.43, y_(5.3), 0.97), mat=dark, bevel=0.005))                     # step plate

# ---------------------------------------------------------------- hood, fenders, grille, lamps
hood = [[(0.98, y, 1.0), (0.72, y, zt), (-0.72, y, zt), (-0.98, y, 1.0)] for (y, zt) in ((y_(5.3), 1.72), (y_(7.08), 1.47))]
body.append(T.loft(hood, mat=paint, angle=30.0))
body.append(T.box((0.06, 1.75, 0.03), loc=(0, y_(6.2), 1.6), rot=(-8.1, 0, 0), mat=paint, bevel=0.01))   # its centre ridge
for sx in (1, -1):
    fender = [[(sx * 0.9, y, 0.72), (sx * 1.3, y, 0.78), (sx * 1.3, y, zt - 0.05), (sx * 1.22, y, zt), (sx * 0.9, y, zt)] for (y, zt) in
              ((y_(5.35), 1.16), (y_(6.2), 1.15), (y_(7.04), 1.06))]
    fb = T.loft(fender if sx > 0 else [list(reversed(f)) for f in fender], mat=paint, angle=30.0)
    T.cut(fb, T.cyl(RF + 0.1, 0.8, loc=(sx * 1.1, FA, RF + 0.04), rot=(0, 90, 0), n=28))
    body.append(fb)
    body.append(T.box((0.3, 0.05, 0.16), loc=(sx * 1.08, y_(7.06), 1.1), mat=chrome, bevel=0.01))      # rectangular lamp housing
    body.append(T.box((0.24, 0.03, 0.11), loc=(sx * 1.08, y_(7.085), 1.1), mat=lamp, bevel=0.008))
    body.append(T.cyl(0.11, 0.06, loc=(sx * 1.02, y_(6.98), 0.88), rot=(-90, 0, 0), mat=chrome, n=18))   # round lamp below it
    body.append(T.sphere(0.09, loc=(sx * 1.02, y_(7.01), 0.88), mat=lamp, n=14, scale=(1, 0.4, 1)))
body.append(T.box((1.42, 0.1, 0.66), loc=(0, y_(7.08), 1.18), mat=chrome, bevel=0.03))
for k in range(13):  # the grille's vertical bars on a dark back
    body.append(T.box((0.035, 0.03, 0.52), loc=((k - 6) * 0.095, y_(7.135), 1.17), mat=chrome, bevel=0.004))
body.append(T.box((1.28, 0.02, 0.54), loc=(0, y_(7.125), 1.17), mat=dark))
body.append(T.box((0.18, 0.02, 0.1), loc=(0, y_(7.14), 1.52), mat=T.M("paint", (0.4, 0.3, 0.12), wear=0.4, rust=0.3, dirt=0.4)))   # badge

# ---------------------------------------------------------------- the ram plow (round 30, owner's sheet)
# A massive welded steel plow with POLICE on both halves, a row of teeth along its foot, an anchor chain
# slung across it, and a tubular grille guard rising from it in front of the grille and the lamps.
PY = y_(7.46)
body.append(T.box((2.9, 0.22, 0.86), loc=(0, PY, 0.66), rot=(-10, 0, 0), mat=plow, bevel=0.03))
body.append(T.box((2.96, 0.3, 0.1), loc=(0, PY - 0.04, 1.1), mat=plow, bevel=0.02))          # its top lip
body.append(T.box((2.9, 0.12, 0.14), loc=(0, PY + 0.06, 0.26), mat=plow, bevel=0.02))        # its foot
for sx in (1, -1):  # side wings angled back
    body.append(T.box((0.12, 0.5, 0.8), loc=(sx * 1.5, PY - 0.18, 0.66), rot=(-10, 0, sx * 28), mat=plow, bevel=0.02))
    decals.append(T.Decal(T.stencil("POLICE", color=(0.82, 0.8, 0.76), bridges=False), (sx * 0.78, PY + 0.14, 0.72), (0, 1, 0), (0, 0, 1), (0.62, 0.15)))
for k in range(9):  # teeth along the foot, pointing forward and down
    x = (k - 4) * 0.34
    body.append(T.cyl(0.07, 0.36, loc=(x, PY + 0.26, 0.2), rot=(-110, 0, 0), mat=plow, n=6, r2=0.005))
for k in range(12):  # weld beads / rivets across the blade
    body.append(T.sphere(0.025, loc=((k - 5.5) * 0.24, PY + 0.12, 1.0), mat=dark, n=6))
# anchor chain slung across the plow's face, hooked at the corners
K.chain(body, (-1.2, PY + 0.14, 1.0), (1.2, PY + 0.14, 1.0), chain_m, sag=0.38)
# the grille guard: posts, rails and the lamp cages
for x in (-0.9, -0.3, 0.3, 0.9):
    body.append(K.rod(V((x, PY - 0.06, 1.1)), V((x, y_(7.24), 1.68)), 0.045, dark, n=8))
for z in (1.3, 1.62):
    body.append(K.rod(V((-0.95, y_(7.27), z)), V((0.95, y_(7.27), z)), 0.042, dark, n=8))
for sx in (1, -1):
    body.append(K.rod(V((sx * 1.3, PY - 0.06, 1.1)), V((sx * 1.3, y_(7.2), 1.28)), 0.04, dark, n=8))
    body.append(K.rod(V((sx * 0.95, y_(7.24), 1.28)), V((sx * 1.3, y_(7.2), 1.28)), 0.04, dark, n=8))
    body.append(T.box((0.18, 0.06, 0.12), loc=(sx * 1.32, PY + 0.02, 0.98), mat=red, bevel=0.01))      # red lamps on the plow's top
    body.append(T.box((0.12, 0.05, 0.1), loc=(sx * 1.12, PY + 0.04, 0.98), mat=amber, bevel=0.01))
for sx in (1, -1):  # the plow's brackets back to the frame
    body.append(T.box((0.18, 0.5, 0.2), loc=(sx * 0.5, y_(7.15), 0.62), mat=dark, bevel=0.01))
# chains from the grille's top corners down to the plow
for sx in (1, -1):
    K.chain(body, (sx * 0.68, y_(7.12), 1.5), (sx * 1.0, PY - 0.02, 1.12), chain_m, sag=0.12)

# ---------------------------------------------------------------- the roof: twin quad rocket pods, marker lamps, air horns
for sx in (1, -1):
    x, y, z = sx * 0.55, y_(4.55), 2.5
    body.append(T.box((0.62, 0.8, 0.46), loc=(x, y, z), mat=dark, bevel=0.03))
    body.append(T.box((0.2, 0.3, 0.12), loc=(x, y - 0.1, 2.24), mat=dark, bevel=0.01))           # its pedestal
    for i in range(2):
        for j in range(2):
            px, pz = x + (i - 0.5) * 0.28, z + (j - 0.5) * 0.22
            body.append(T.cyl(0.085, 0.04, loc=(px, y + 0.41, pz), rot=(-90, 0, 0), mat=chain_m, n=12))
            body.append(T.sphere(0.065, loc=(px, y + 0.42, pz), mat=red, n=10, scale=(1, 0.5, 1)))
    body.append(T.box((0.66, 0.06, 0.5), loc=(x, y - 0.41, z), mat=paint, bevel=0.01))           # back plate
for k in range(5):
    body.append(T.box((0.1, 0.06, 0.06), loc=((k - 2) * 0.34, y_(5.06), 2.3), mat=amber, bevel=0.01))
for sx in (1, -1):
    body.append(T.cyl(0.05, 0.5, loc=(sx * 0.95, y_(4.95), 2.34), rot=(-90, 0, 0), mat=chrome, n=10, r2=0.09))

# ---------------------------------------------------------------- armoured louvres over the glass, a roll cage
for k in range(6):  # windshield slats (they leave the red slit under the visor)
    t = 0.12 + k * 0.13
    p = ws_b.lerp(ws_t, t)
    body.append(T.box((2.0, 0.09, 0.018), loc=(0, p.y + 0.02, p.z), rot=(-58, 0, 0), mat=dark, bevel=0.004))
for sx in (1, -1):
    for k in range(4):  # side window slats
        body.append(T.box((0.02, 0.8, 0.05), loc=(sx * (HW + 0.03), y_(4.55), 1.84 + k * 0.08), mat=dark, bevel=0.004))
    body.append(K.rod(V((sx * (HW + 0.06), y_(5.15), 1.0)), V((sx * (HW + 0.06), y_(5.15), 2.2)), 0.03, dark, n=8))
    body.append(K.rod(V((sx * (HW + 0.06), y_(5.15), 2.2)), V((sx * (HW + 0.06), y_(3.0), 2.24)), 0.03, dark, n=8))
    body.append(T.cyl(0.13, 0.5, loc=(sx * (HW + 0.12), y_(3.3), 1.35), mat=chrome, n=14))           # a canister on the sleeper side

# ---------------------------------------------------------------- side gatlings beside the hood
for sx in (1, -1):  # round 30 (sheet): rotary guns on the front fenders, an ammo drum and belt beside each
    x, z = sx * 1.12, 1.38
    body.append(T.box((0.24, 0.42, 0.24), loc=(x, y_(5.55), z), mat=gun, bevel=0.02))
    body.append(T.box((0.2, 0.3, 0.12), loc=(x, y_(5.55), z - 0.17), mat=dark, bevel=0.01))   # its mount on the fender
    body.append(T.cyl(0.13, 0.22, loc=(x + sx * 0.2, y_(5.45), z - 0.05), rot=(0, 90, 0), mat=chain_m, n=14))
    K.chain(body, (x + sx * 0.2, y_(5.45), z - 0.18), (x, y_(5.6), z - 0.1), chain_m, sag=0.08)
    for k in range(6):
        a = 2 * math.pi * k / 6
        body.append(K.rod(V((x + math.cos(a) * 0.055, y_(5.75), z + math.sin(a) * 0.055)), V((x + math.cos(a) * 0.055, y_(6.72), z + math.sin(a) * 0.055)), 0.017, gun, n=6))
    for d in (5.9, 6.4, 6.68):
        body.append(T.cyl(0.085, 0.04, loc=(x, y_(d), z), rot=(-90, 0, 0), mat=gun, n=12))
    markers.append(T.marker("m_gun_" + ("r" if sx > 0 else "l"), (x, y_(6.78), z)))

markers.append(T.marker("m_launcher", (0.0, y_(4.0), 2.3)))
markers.append(T.marker("m_top", (0.0, y_(3.8), 2.3)))
markers.append(T.marker("m_head", (0.0, y_(7.1), 1.1)))

# ---------------------------------------------------------------- wheels: truck tyres on dark steel disc wheels


def truck_wheel(name, R, w, duals):
    parts = []
    for k in range(duals):
        off = (k - (duals - 1) / 2) * (w + 0.03)
        for p in K.tyre(R, w, rubber, 28):
            p.location.x += off
            parts.append(p)
        parts.append(K.ring_solid([(R * 0.7, off - w / 2 + 0.02), (R * 0.7, off + w / 2 - 0.02), (R * 0.6, off + w / 2 - 0.04), (R * 0.6, off - w / 2 + 0.03)], rim, 28))
    face = (duals - 1) / 2 * (w + 0.03) + w / 2 - 0.06
    parts.append(T.cyl(R * 0.6, 0.02, loc=(face, 0, 0), rot=(0, 90, 0), mat=rim, n=24))
    for k in range(10):  # hand holes and lug nuts
        a = 2 * math.pi * k / 10
        parts.append(T.cyl(R * 0.07, 0.025, loc=(face + 0.005, math.cos(a) * R * 0.42, math.sin(a) * R * 0.42), rot=(0, 90, 0), mat=dark, n=8))
        parts.append(T.cyl(0.018, 0.04, loc=(face + 0.02, math.cos(a + 0.3) * R * 0.25, math.sin(a + 0.3) * R * 0.25), rot=(0, 90, 0), mat=chrome, n=6))
    parts.append(T.cyl(R * 0.16, 0.12, loc=(face + 0.04, 0, 0), rot=(0, 90, 0), mat=chrome, n=16, bevel=0.012, r2=R * 0.11))
    return T.join(parts, name)


wheel_f = truck_wheel("wheel_f", RF, 0.36, 1)
wheel_r = truck_wheel("wheel_r", RR, 0.3, 2)
markers += [T.marker("m_wheel_fr", (TF, FA, RF)), T.marker("m_wheel_fl", (-TF, FA, RF)),
            T.marker("m_wheel_rr", (TR, RA1, RR)), T.marker("m_wheel_rl", (-TR, RA1, RR)),
            T.marker("m_wheel_rr2", (TR, RA2, RR)), T.marker("m_wheel_rl2", (-TR, RA2, RR))]
body_ob = T.join(body, "body")
print("triangles: body %d, wheel_f %d, wheel_r %d" % (T.tri_count([body_ob]), T.tri_count([wheel_f]), T.tri_count([wheel_r])))

if "--shape" in sys.argv:
    out = sys.argv[sys.argv.index("--shape") + 1]
    wf = [T.dup(wheel_f, (TF, FA, RF)), T.dup(wheel_f, (-TF, FA, RF), rot=(0, 0, 180))]
    for y in (RA1, RA2):
        wf += [T.dup(wheel_r, (TR, y, RR)), T.dup(wheel_r, (-TR, y, RR), rot=(0, 0, 180))]
    for o in (wheel_f, wheel_r):
        o.location = (0, 0, -50)
    T.preview(out, size=(1100, 600), eye=(-13.0, 0.0, 1.4), look=(0, 0.0, 1.2), fov=40, samples=12)
    T.preview(out.replace(".png", "_f.png"), size=(1100, 600), eye=(0.0, 12.0, 1.8), look=(0, 0, 1.2), fov=34, samples=12)
    T.preview(out.replace(".png", "_b.png"), size=(1100, 600), eye=(0.0, -12.0, 2.2), look=(0, 0, 1.2), fov=34, samples=12)
    T.preview(out.replace(".png", "_q.png"), size=(1100, 600), eye=(-7.5, 8.5, 4.6), look=(0, 0.6, 1.1), fov=40, samples=12)
    sys.exit(0)

import bpy
wheel_f.location = (4.5, 0.9, RF)
wheel_r.location = (4.5, -1.2, RR)
bpy.context.view_layer.update()
for o in (wheel_f, wheel_r, slit):
    T.apply(o)
objs = [body_ob, wheel_f, wheel_r, slit]
T.unwrap(objs, margin=0.002)
if "--nobake" not in sys.argv:
    g = T.gbuffer(objs, size=2048, ao_dist=0.6, bevel_r=0.01, ao_samples=20)
    al, nm, orm = T.weather(g, decals, seed=37, dust_from=0.0, dust_to=0.6, regions=[], ao_strength=0.75)
    T.save_maps("darkside", al, nm, orm)
wheel_f.data.transform(Matrix.Translation((-4.5, -0.9, -RF)))
wheel_r.data.transform(Matrix.Translation((-4.5, 1.2, -RR)))
T.export_glb("darkside", objs, markers=markers)
print("ok", T.tri_count(objs))

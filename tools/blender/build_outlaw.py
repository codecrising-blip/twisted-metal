"""Outlaw (round 10): Jamie Roberts' armoured police interceptor.
    /tmp/bpy3.13/bin/python tools/blender/build_outlaw.py            # build, bake, export
    /tmp/bpy3.13/bin/python tools/blender/build_outlaw.py --shape a.png
Our own design: a big boxy 90s patrol sedan lifted on steel wheels, black with white doors and roof
gone grey with dust, a welded push bar, steel louvres over the windshield and mesh on the side glass,
twin guns in an armoured box on the hood, a low light bar, and a caged taser coil on the trunk.
Blender space: +Y forward, +Z up. Nodes: body, wheel_f, wheel_r and m_* markers."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
import numpy as np
from mathutils import Matrix, Vector

T.reset()
R = 0.43
FA, RA = 1.48, -1.45
TRACK = 0.93
SILL = 0.36
BELT = 1.02
ROOF = 1.47
W = 0.99   # half width at the doors
Y_DECK, Y_ROOF_R, Y_ROOF_F, Y_COWL = -1.72, -1.1, 0.24, 1.0   # trunk lid, roof and cowl stations

BLACK = (0.02, 0.02, 0.022)
WHITE = (0.44, 0.44, 0.41)
paint = T.M("paint", BLACK, wear=0.7, rust=0.5, dirt=0.75)
armor = T.M("steel", (0.035, 0.035, 0.038), wear=0.7, rust=0.55, dirt=0.6)
bare = T.M("steel", (0.10, 0.10, 0.10), wear=0.7, rust=0.5, dirt=0.5)
dark = T.M("steel", (0.012, 0.012, 0.013), wear=0.3, rust=0.3, dirt=0.7)
rubber = T.M("rubber", (0.016, 0.016, 0.016), dirt=0.7)
window = T.M("glassy", (0.012, 0.016, 0.018), dirt=0.7)
copper = T.M("chrome", (0.42, 0.2, 0.07), wear=0.5, rust=0.3, dirt=0.4)
body = []
decals = []
regions = []
markers = []


def section(y, w, z_top, wg, deck):
    """Half cross-section at station y (x >= 0), from the bottom centre up and over to the top centre.
    deck = True for hood and trunk (flat top at z_top), False for the cabin (greenhouse wg wide)."""
    zf = SILL
    if deck:
        return [(0.0, y, zf), (w * 0.9, y, zf), (w, y, zf + 0.1), (w, y, BELT * 0.74), (w * 0.985, y, min(BELT, z_top) - 0.05),
                (w * 0.9, y, z_top - 0.015), (w * 0.55, y, z_top + 0.012), (0.0, y, z_top + 0.022)]
    return [(0.0, y, zf), (w * 0.9, y, zf), (w, y, zf + 0.1), (w, y, BELT * 0.74), (w * 0.985, y, BELT),
            (wg, y, z_top - 0.07), (wg * 0.84, y, z_top), (0.0, y, z_top + 0.02)]


# stations from the tail to the nose: (y, half width, top height, greenhouse half width, deck?)
stations = [
    (-2.42, 0.86, 0.94, 0, True), (-2.32, 0.93, 1.0, 0, True), (Y_DECK, 0.975, 1.03, 0, True),
    (Y_ROOF_R, W, ROOF - 0.01, 0.75, False), (Y_ROOF_F, W, ROOF, 0.77, False),
    (Y_COWL, 0.985, 1.03, 0, True), (1.8, 0.96, 0.99, 0, True), (2.3, 0.92, 0.93, 0, True), (2.42, 0.86, 0.88, 0, True),
]
secs = []
for (y, w, zt, wg, deck) in stations:
    half = section(y, w, zt, wg, deck)
    full = half + [(-x, yy, z) for (x, yy, z) in reversed(half[1:-1])]
    secs.append(full)
shell = T.loft(secs, mat=paint, name="shell", closed=True, caps=True, angle=30)
T.bevel(shell, 0.045, 2, 18)
for ay in (FA, RA):
    for sx in (1, -1):
        T.cut(shell, T.cyl(0.555, 0.5, (sx * (W - 0.12), ay, R + 0.02), rot=(0, 90, 0), n=20))
body.append(shell)

# ---------------------------------------------------------------- sides
PANES = ((-1.02, -0.42), (-0.34, 0.6))   # rear and front side glass (y from, y to)


def side(sx):
    x = sx * W
    # fender flares
    for ay in (FA, RA):
        n = 8
        for k in range(n + 1):
            a = math.radians(6 + 168.0 * k / n)
            py, pz = ay + math.cos(a) * 0.58, R + 0.02 + math.sin(a) * 0.58
            body.append(T.box((0.13, 0.235, 0.03), (x + sx * 0.025, py, pz), rot=(math.degrees(a) - 90, 0, 0), mat=armor))
    # rocker armour and a door bar
    body.append(T.box((0.05, 1.9, 0.2), (x + sx * 0.012, 0.02, SILL + 0.12), mat=armor, bevel=0.01))
    body.append(T.box((0.03, 1.7, 0.045), (x + sx * 0.01, -0.05, 0.86), mat=bare))
    # door handles
    for y in (0.22, -0.72):
        body.append(T.box((0.03, 0.16, 0.035), (x + sx * 0.012, y, 0.95), mat=bare))
    # side glass frames (the mesh over the glass is painted on)
    for (y0, y1) in PANES:
        yc, ln = (y0 + y1) / 2, (y1 - y0)
        for z in (BELT + 0.045, ROOF - 0.13):
            xx = sx * (0.985 - (z - BELT) / (ROOF - 0.07 - BELT) * (0.985 - 0.76))
            body.append(T.box((0.03, ln, 0.03), (xx + sx * 0.012, yc, z), mat=armor))
    # mirror
    body.append(T.box((0.16, 0.07, 0.11), (sx * 1.06, 0.8, 1.1), mat=paint, bevel=0.015))
    # spotlight on the A pillar
    body.append(T.cyl(0.075, 0.12, (sx * 0.93, 0.93, 1.2), rot=(-80, 0, sx * -12), mat=dark, n=10))
    body.append(T.cyl(0.062, 0.02, (sx * 0.945, 0.995, 1.212), rot=(-80, 0, sx * -12), mat=T.glow((1.0, 0.92, 0.75)), n=10))
    # headlight, marker and tail lamps
    body.append(T.box((0.3, 0.04, 0.14), (sx * 0.62, 2.435, 0.74), mat=dark))
    body.append(T.box((0.25, 0.03, 0.1), (sx * 0.62, 2.455, 0.74), mat=T.glow((1.0, 0.88, 0.62))))
    body.append(T.box((0.1, 0.03, 0.07), (sx * 0.83, 2.43, 0.74), mat=T.glow((1.0, 0.45, 0.05))))
    body.append(T.box((0.34, 0.03, 0.12), (sx * 0.6, -2.435, 0.78), mat=T.glow((0.85, 0.04, 0.03))))
    body.append(T.box((0.38, 0.04, 0.16), (sx * 0.6, -2.43, 0.78), mat=dark))
    # exhaust
    body.append(T.cyl(0.045, 0.3, (sx * 0.55, -2.45, 0.33), rot=(-90, 0, 0), mat=dark, n=8))
    markers.append(T.marker("m_exh_" + ("r" if sx > 0 else "l"), (sx * 0.55, -2.62, 0.33)))
    # mud flap
    body.append(T.box((0.34, 0.02, 0.3), (sx * TRACK, RA - 0.6, 0.3), mat=rubber))
    # light bar lenses: red on the driver's side, blue on the other
    body.append(T.box((0.46, 0.2, 0.09), (sx * 0.3, -0.4, ROOF + 0.115), mat=T.glow((0.95, 0.06, 0.04) if sx < 0 else (0.1, 0.25, 1.0))))

for sx in (1, -1):
    side(sx)

# ---------------------------------------------------------------- light bar, antennas
body.append(T.box((1.2, 0.26, 0.05), (0, -0.4, ROOF + 0.05), mat=dark, bevel=0.01))
body.append(T.box((0.12, 0.22, 0.1), (0, -0.4, ROOF + 0.115), mat=dark))
for sx in (1, -1):
    body.append(T.box((0.05, 0.24, 0.1), (sx * 0.56, -0.4, ROOF + 0.115), mat=dark))
body.append(T.cyl(0.008, 0.9, (0.6, -2.2, 1.48), rot=(8, 0, 0), mat=dark, n=4))
body.append(T.cyl(0.008, 0.6, (-0.45, -0.9, ROOF + 0.3), mat=dark, n=4))

# ---------------------------------------------------------------- windshield louvres, rear window plate
WS0 = Vector((0, Y_COWL - 0.02, 1.05))    # windshield base
WS1 = Vector((0, Y_ROOF_F + 0.04, ROOF - 0.04))
n_l = 7
for k in range(n_l):
    t = (k + 0.5) / n_l
    c = WS0.lerp(WS1, t) + Vector((0, 0.045, 0.045))
    wdt = 1.84 - 0.34 * t
    body.append(T.box((wdt, 0.115, 0.016), tuple(c), rot=(12, 0, 0), mat=armor))
for sx in (1, -1):
    a = WS0 + Vector((sx * 0.9, 0.03, 0.03))
    b = WS1 + Vector((sx * 0.73, 0.04, 0.04))
    body.append(T.tube([tuple(a), tuple(b)], 0.022, mat=armor, n=5))
body.append(T.tube([tuple(WS0 + Vector((0, 0.03, 0.03))), tuple(WS1 + Vector((0, 0.04, 0.04)))], 0.02, mat=armor, n=5))
RW0 = Vector((0, Y_DECK + 0.02, 1.06))
RW1 = Vector((0, Y_ROOF_R - 0.04, ROOF - 0.05))
rc = RW0.lerp(RW1, 0.5) + Vector((0, -0.035, 0.035))
rt = math.degrees(math.atan2(RW1.y - RW0.y, RW1.z - RW0.z))
body.append(T.box((1.52, 0.035, 0.6), tuple(rc), rot=(-rt, 0, 0), mat=armor, bevel=0.01))
for sx in (1, -1):
    body.append(T.box((0.46, 0.04, 0.06), tuple(rc + Vector((sx * 0.4, -0.004, 0.02))), rot=(-rt, 0, 0), mat=window))

# ---------------------------------------------------------------- hood gun box
GB = Vector((0, 1.62, 1.0))
body.append(T.box((0.74, 0.86, 0.2), tuple(GB + Vector((0, 0, 0.09))), mat=armor, bevel=0.025, taper=(0.9, 0.92)))
body.append(T.box((0.5, 0.3, 0.05), tuple(GB + Vector((0, -0.2, 0.215))), mat=bare, bevel=0.008))
for sx in (1, -1):
    body.append(T.cyl(0.05, 0.3, tuple(GB + Vector((sx * 0.2, 0.52, 0.1))), rot=(-90, 0, 0), mat=bare, n=10))
    body.append(T.cyl(0.028, 0.6, tuple(GB + Vector((sx * 0.2, 0.72, 0.1))), rot=(-90, 0, 0), mat=dark, n=8))
    body.append(T.cyl(0.04, 0.12, tuple(GB + Vector((sx * 0.2, 1.0, 0.1))), rot=(-90, 0, 0), mat=dark, n=8))
    markers.append(T.marker("m_gun_" + ("r" if sx > 0 else "l"), tuple(GB + Vector((sx * 0.2, 1.1, 0.1)))))
    for k in range(4):
        body.append(T.cyl(0.018, 0.02, tuple(GB + Vector((sx * 0.33, -0.3 + k * 0.2, 0.2))), mat=bare, n=6))

# ---------------------------------------------------------------- push bar, bumpers
PB = 2.62
for sx in (1, -1):
    body.append(T.box((0.07, 0.07, 0.72), (sx * 0.38, PB, 0.72), mat=armor, bevel=0.012))
    body.append(T.box((0.07, 0.3, 0.07), (sx * 0.38, PB - 0.14, 0.5), mat=armor))
    body.append(T.tube([(sx * 0.38, PB, 0.95), (sx * 0.8, PB - 0.06, 0.93), (sx * 1.0, PB - 0.28, 0.9)], 0.028, mat=armor, n=6))
    body.append(T.tube([(sx * 0.38, PB, 0.6), (sx * 0.8, PB - 0.06, 0.6), (sx * 1.0, PB - 0.28, 0.6)], 0.028, mat=armor, n=6))
for z in (0.45, 0.72, 1.0):
    body.append(T.box((0.84, 0.06, 0.075), (0, PB + 0.005, z), mat=armor, bevel=0.012))
body.append(T.box((1.98, 0.14, 0.2), (0, 2.46, 0.5), mat=armor, bevel=0.02))
body.append(T.box((1.98, 0.14, 0.2), (0, -2.46, 0.5), mat=armor, bevel=0.02))
body.append(T.box((1.3, 0.03, 0.22), (0, 2.435, 0.74), mat=dark))  # grille
for k in range(4):
    body.append(T.box((0.9, 0.03, 0.02), (0, 2.45, 0.67 + k * 0.05), mat=bare))
body.append(T.box((0.36, 0.02, 0.17), (0, -2.44, 0.6), mat=T.M("paint", (0.4, 0.4, 0.34), 0.8, 0.6, 0.7)))  # plate

# ---------------------------------------------------------------- taser coil on the trunk
TC = Vector((0, -2.02, 1.04))
body.append(T.box((0.62, 0.62, 0.1), tuple(TC + Vector((0, 0, 0.05))), mat=armor, bevel=0.02))
body.append(T.cyl(0.17, 0.42, tuple(TC + Vector((0, 0, 0.31))), mat=copper, n=14))
for k in range(3):
    body.append(T.cyl(0.19, 0.03, tuple(TC + Vector((0, 0, 0.14 + k * 0.17))), mat=dark, n=14))
body.append(T.lathe([(0.1, 0.0), (0.2, 0.03), (0.24, 0.09), (0.2, 0.15), (0.1, 0.18)], loc=tuple(TC + Vector((0, 0, 0.52))), mat=bare, n=14))
for sx in (1, -1):
    for sy in (1, -1):
        body.append(T.tube([tuple(TC + Vector((sx * 0.27, sy * 0.27, 0.1))), tuple(TC + Vector((sx * 0.27, sy * 0.27, 0.74))), tuple(TC + Vector((sx * 0.1, sy * 0.1, 0.8)))], 0.016, mat=armor, n=5))
body.append(T.lathe([(0.26, -0.016), (0.3, -0.016), (0.3, 0.016), (0.26, 0.016)], loc=tuple(TC + Vector((0, 0, 0.44))), mat=armor, n=12))
body.append(T.tube([tuple(TC + Vector((0.3, 0.1, 0.06))), tuple(TC + Vector((0.4, 0.5, 0.02))), (0.5, -1.74, 1.06)], 0.02, mat=rubber, n=5))
body.append(T.sphere(0.035, tuple(TC + Vector((0, 0, 0.72))), mat=T.glow((0.5, 0.75, 1.0)), n=6))
markers.append(T.marker("m_launcher", tuple(TC + Vector((0, 0, 0.82)))))
markers.append(T.marker("m_top", (0.0, 1.2, 1.2)))
markers.append(T.marker("m_head", (0.0, 2.6, 0.74)))

# ---------------------------------------------------------------- underbody
body.append(T.box((1.5, 4.3, 0.1), (0, 0, SILL - 0.03), mat=dark))
body.append(T.cyl(0.05, 1.8, (0, FA, R), rot=(0, 90, 0), mat=dark, n=6))
body.append(T.cyl(0.06, 1.8, (0, RA, R), rot=(0, 90, 0), mat=dark, n=6))
body.append(T.sphere(0.15, (0, RA, R), mat=dark, n=8))


# ---------------------------------------------------------------- wheels: black steel patrol wheels
def wheel(name, w):
    tyre = [(R * 0.6, -w / 2), (R * 0.9, -w / 2), (R * 0.985, -w / 2 + 0.04), (R, -w * 0.22), (R - 0.02, -w * 0.18), (R - 0.02, -w * 0.06),
            (R, -w * 0.03), (R, w * 0.03), (R - 0.02, w * 0.06), (R - 0.02, w * 0.18), (R, w * 0.22), (R * 0.985, w / 2 - 0.04), (R * 0.9, w / 2), (R * 0.6, w / 2)]
    parts = [T.lathe(tyre, rot=(0, 90, 0), mat=rubber, n=22, angle=50)]
    rim = [(R * 0.6, -w / 2 + 0.02), (R * 0.6, w / 2 - 0.015), (R * 0.56, w / 2 - 0.03), (R * 0.52, w / 2 - 0.07), (R * 0.3, w / 2 - 0.05), (R * 0.26, w / 2 - 0.01), (0.0, w / 2 - 0.01)]
    parts.append(T.lathe(rim, rot=(0, 90, 0), mat=T.M("steel", (0.02, 0.02, 0.021), 0.6, 0.6, 0.8), n=22))
    for k in range(5):
        a = math.radians(72 * k)
        parts.append(T.cyl(0.02, 0.03, (w / 2 - 0.02, math.cos(a) * R * 0.2, math.sin(a) * R * 0.2), rot=(0, 90, 0), mat=bare, n=6))
    for k in range(8):  # slots
        a = math.radians(45 * k + 22)
        parts.append(T.box((0.015, 0.03, 0.075), (w / 2 - 0.058, math.cos(a) * R * 0.44, math.sin(a) * R * 0.44), rot=(math.degrees(a) + 90, 0, 0), mat=dark))
    parts.append(T.cyl(R * 0.13, 0.05, (w / 2 + 0.0, 0, 0), rot=(0, 90, 0), mat=bare, n=10))
    return T.join(parts, name)

wheel_f = wheel("wheel_f", 0.3)
wheel_r = wheel("wheel_r", 0.33)
markers += [T.marker("m_wheel_fr", (TRACK, FA, R)), T.marker("m_wheel_fl", (-TRACK, FA, R)),
            T.marker("m_wheel_rr", (TRACK, RA, R)), T.marker("m_wheel_rl", (-TRACK, RA, R))]
body_ob = T.join(body, "body")
print("triangles: body %d, wheel_f %d, wheel_r %d" % (T.tri_count([body_ob]), T.tri_count([wheel_f]), T.tri_count([wheel_r])))

if "--shape" in sys.argv:
    out = sys.argv[sys.argv.index("--shape") + 1]
    wf = [T.dup(wheel_f, (TRACK, FA, R)), T.dup(wheel_f, (-TRACK, FA, R), rot=(0, 0, 180)), T.dup(wheel_r, (TRACK, RA, R)), T.dup(wheel_r, (-TRACK, RA, R), rot=(0, 0, 180))]
    wheel_f.location = (0, 0, -50)
    wheel_r.location = (0, 0, -50)
    T.preview(out, size=(1000, 620), eye=(4.8, 5.6, 2.5), look=(0, 0.1, 0.8), fov=40, samples=12)
    T.preview(out.replace(".png", "_b.png"), size=(1000, 620), eye=(-5.2, -5.0, 2.9), look=(0, 0, 0.8), fov=40, samples=12)
    sys.exit(0)

def doors(P, N):  # white doors
    return ((np.abs(N[:, 0]) > 0.5) & (P[:, 1] > -1.12) & (P[:, 1] < 1.0) & (P[:, 2] > SILL + 0.02) & (P[:, 2] < BELT + 0.03)).astype(np.float32)
regions.append((doors, WHITE, ("paint",)))
def roof(P, N):  # white roof
    return ((N[:, 2] > 0.75) & (P[:, 2] > ROOF - 0.12) & (P[:, 1] > Y_ROOF_R - 0.1) & (P[:, 1] < Y_ROOF_F + 0.08)).astype(np.float32)
regions.append((roof, WHITE, ("paint",)))
def side_glass(P, N):  # the windows, between the pillars
    z = P[:, 2]
    y = P[:, 1]
    band = (z > BELT + 0.07) & (z < ROOF - 0.15) & (np.abs(N[:, 0]) > 0.35)
    panes = ((y > PANES[0][0]) & (y < PANES[0][1])) | ((y > PANES[1][0]) & (y < PANES[1][1]))
    return (band & panes).astype(np.float32)
regions.append((side_glass, None, ("paint",), window))
def windshield(P, N):
    z = P[:, 2]
    y = P[:, 1]
    return ((N[:, 1] > 0.3) & (N[:, 2] > 0.2) & (z > 1.1) & (z < ROOF - 0.07) & (y > Y_ROOF_F) & (y < Y_COWL) & (np.abs(P[:, 0]) < 0.9 - (z - 1.1) * 0.42)).astype(np.float32)
regions.append((windshield, None, ("paint",), window))

for sx in (1, -1):
    decals.append(T.Decal(T.stencil("POLICE", (0.015, 0.015, 0.017), 140, bridges=False, pad=0.06), (sx * W, -0.05, 0.66), (sx, 0, 0), (0, 0, 1), (1.25, 0.28), depth=0.08, kinds=("paint",)))
    decals.append(T.Decal(T.stencil("911", (0.015, 0.015, 0.017), 110, bridges=False, pad=0.06), (sx * 0.98, -1.75, 0.84), (sx, 0, 0), (0, 0, 1), (0.34, 0.17), depth=0.08, kinds=("paint",)))
    # welded mesh over the side glass
    grid = T.lines_image([(k / 12.0, 0, k / 12.0, 1) for k in range(13)] + [(0, k / 4.0, 1, k / 4.0) for k in range(5)], size=(512, 128), width=5, color=(0.03, 0.03, 0.032), alpha=0.95)
    decals.append(T.Decal(grid, (sx * 0.88, (PANES[0][0] + PANES[1][1]) / 2, (BELT + ROOF) / 2 - 0.03), (sx, 0, 0.35), (0, 0, 1), (PANES[1][1] - PANES[0][0] + 0.06, 0.36), depth=0.16, kinds=("glassy",)))
    # door gaps
    gaps = T.lines_image([(0.02, 0.02, 0.02, 0.98), (0.5, 0.02, 0.5, 0.98), (0.98, 0.02, 0.98, 0.98), (0.02, 0.98, 0.98, 0.98)], size=(512, 256), width=4)
    decals.append(T.Decal(gaps, (sx * W, -0.06, 0.72), (sx, 0, 0), (0, 0, 1), (2.06, 0.74), depth=0.06, kinds=("paint",)))
    decals.append(T.Decal(T.holes_image(9, 14 + sx, size=(512, 200), r=(3, 7)), (sx * W, -0.3, 0.75), (sx, 0, 0), (0, 0, 1), (3.4, 0.7), depth=0.07, kinds=("paint",)))
decals.append(T.Decal(T.stencil("07", (0.015, 0.015, 0.017), 150, bridges=False, pad=0.06), (0, -0.8, ROOF), (0, 0, 1), (0, 1, 0), (0.5, 0.34), depth=0.1, kinds=("paint",)))
decals.append(T.Decal(T.splatter_image((0.07, 0.065, 0.06), n=50, seed=4), (0.5, 2.4, 0.7), (0, 1, 0), (0, 0, 1), (1.4, 0.7), depth=0.3, kinds=("paint", "steel"), opacity=0.5))
decals.append(T.Decal(T.splatter_image(seed=15), (-0.3, PB, 0.7), (0, 1, 0), (0, 0, 1), (0.9, 0.7), depth=0.25, kinds=("steel",), opacity=0.85))
def coil(P, N):  # copper windings on the coil
    d = P - np.array(TC, dtype=np.float32)
    near = (np.abs(d[:, 0]) < 0.2) & (np.abs(d[:, 1]) < 0.2) & (d[:, 2] > 0.1) & (d[:, 2] < 0.52)
    return (near & ((d[:, 2] * 60.0) % 1.0 < 0.35)).astype(np.float32) * 0.8
regions.append((coil, (0.05, 0.025, 0.012), ("chrome",)))

# ---------------------------------------------------------------- bake and export
import bpy
wheel_f.location = (3.5, 0.8, R)
wheel_r.location = (3.5, -0.8, R)
bpy.context.view_layer.update()
for o in (wheel_f, wheel_r):
    T.apply(o)
objs = [body_ob, wheel_f, wheel_r]
T.unwrap(objs, margin=0.002)
if "--nobake" not in sys.argv:
    g = T.gbuffer(objs, size=2048, ao_dist=0.6, bevel_r=0.012, ao_samples=24)
    al, nm, orm = T.weather(g, decals, seed=33, dust_from=0.2, dust_to=1.15, regions=regions,
        soot=[(tuple(GB + Vector((0, 1.05, 0.1))), 0.35)])
    T.save_maps("outlaw", al, nm, orm)
wheel_f.data.transform(Matrix.Translation((-3.5, -0.8, -R)))
wheel_r.data.transform(Matrix.Translation((-3.5, 0.8, -R)))
T.export_glb("outlaw", objs, markers=markers)
print("ok")

"""Sweet Tooth (round 10): an armoured ice cream step van that has been through a war.
    /tmp/bpy3.13/bin/python tools/blender/build_sweet_tooth.py            # build, bake, export
    /tmp/bpy3.13/bin/python tools/blender/build_sweet_tooth.py --shape a.png   # quick look, no bake
Our own design (owner: serious, real proportions, no cartoon face): a long-nosed step van, cream
paint gone to rust, a faded crimson band and polka dots, welded V plow with spikes, mesh over the
windshield, slit plates on the cab windows, a roll-up shutter on the serving hatch, twin gatlings on
the nose, a napalm mortar and fuel cans on the roof, horn speakers, and a burnt-out fibreglass soft
serve sign that still burns inside.
Blender space: +Y forward, +Z up. Nodes: body, wheel_f, wheel_r, spinner, and m_* markers."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
import numpy as np
from mathutils import Matrix, Vector

T.reset()
HW = 1.15           # half width of the body
FLOOR, ROOF = 0.62, 2.68
REAR, NOSE = -2.95, 2.85
FA, RA = 1.95, -1.75  # axles
R = 0.52
TRACK_F, TRACK_R = 1.08, 1.03

CREAM = (0.43, 0.40, 0.33)
CRIMSON = (0.28, 0.03, 0.04)
paint = T.M("paint", CREAM, wear=0.72, rust=0.66, dirt=0.75)
armor = T.M("steel", (0.035, 0.035, 0.038), wear=0.7, rust=0.6, dirt=0.6)
bare = T.M("steel", (0.10, 0.10, 0.10), wear=0.7, rust=0.5, dirt=0.5)
dark = T.M("steel", (0.012, 0.012, 0.013), wear=0.3, rust=0.3, dirt=0.7)
soot = T.M("burnt", (0.05, 0.04, 0.03), rust=0.5)
rubber = T.M("rubber", (0.016, 0.016, 0.016), dirt=0.7)
olive = T.M("paint", (0.075, 0.09, 0.045), wear=0.7, rust=0.5, dirt=0.6)
canred = T.M("paint", (0.32, 0.035, 0.03), wear=0.7, rust=0.5, dirt=0.6)
wafer = T.M("plastic", (0.27, 0.17, 0.075), wear=0.8, dirt=0.7)
swirl = T.M("plastic", (0.40, 0.31, 0.28), wear=0.85, dirt=0.8)
glass = T.glass()
body = []     # parts of the body mesh
door_parts = []  # the tailgate (round 19): its own node, it folds down into a ramp for Sweet Bot
DOOR_W, DOOR_Z0, DOOR_Z1 = 1.78, 0.74, 2.56
decals = []
regions = []
markers = []


def both(fn):
    """Call fn(sx) for the right (+1) and the left (-1) side."""
    for sx in (1, -1):
        fn(sx)


# ---------------------------------------------------------------- shell
profile = [(REAR, FLOOR), (NOSE - 0.02, FLOOR), (NOSE, FLOOR + 0.13), (NOSE, 1.22), (NOSE - 0.1, 1.34),
           (1.98, 1.58), (1.72, 2.58), (1.6, ROOF), (REAR, ROOF)]
shell = T.prism(profile, HW * 2, mat=paint, plane="YZ", name="shell")
T.bevel(shell, 0.07, 2, 20)
for (ay, track) in ((FA, TRACK_F), (RA, TRACK_R)):
    for sx in (1, -1):
        T.cut(shell, T.cyl(0.69, 0.62, (sx * (HW - 0.16), ay, R), rot=(0, 90, 0), n=20))
# the box's back opens (round 19): a hollow behind the tailgate, lined dark
T.cut(shell, T.box((DOOR_W, 1.42, DOOR_Z1 - DOOR_Z0), (0, REAR + 0.69, (DOOR_Z0 + DOOR_Z1) / 2)))
DM = (DOOR_Z0 + DOOR_Z1) / 2
for size, loc in (((DOOR_W, 1.4, 0.03), (0, REAR + 0.7, DOOR_Z0 + 0.015)), ((DOOR_W, 1.4, 0.03), (0, REAR + 0.7, DOOR_Z1 - 0.015)),
                  ((DOOR_W, 0.03, DOOR_Z1 - DOOR_Z0), (0, REAR + 1.395, DM)),
                  ((0.03, 1.4, DOOR_Z1 - DOOR_Z0), (DOOR_W / 2 - 0.015, REAR + 0.7, DM)), ((0.03, 1.4, DOOR_Z1 - DOOR_Z0), (-DOOR_W / 2 + 0.015, REAR + 0.7, DM))):
    body.append(T.box(size, loc, mat=dark))
for k in range(4):  # floor slats, worn bright where the robot slides out
    body.append(T.box((0.06, 1.36, 0.025), ((k - 1.5) * 0.4, REAR + 0.7, DOOR_Z0 + 0.04), mat=bare))
door_parts.append(T.box((DOOR_W - 0.02, 0.06, DOOR_Z1 - DOOR_Z0 - 0.02), (0, REAR - 0.03, DM), mat=paint, bevel=0.012))
for k in range(6):  # treads on its inside face: a ramp once it is down
    door_parts.append(T.box((DOOR_W - 0.24, 0.03, 0.045), (0, REAR + 0.012, DOOR_Z0 + 0.2 + k * 0.28), mat=bare))
markers.append(T.marker("m_door_hinge", (0, REAR - 0.03, DOOR_Z0)))
# windshield pocket
WS_T = math.degrees(math.atan2(0.26, 1.0))
ws_n = Vector((0, math.cos(math.radians(WS_T)), math.sin(math.radians(WS_T))))
ws_c = Vector((0, 1.85, 2.08))
T.cut(shell, T.box((2.0, 0.12, 0.8), tuple(ws_c + ws_n * 0.0), rot=(WS_T, 0, 0)))
body.append(shell)
body.append(T.box((1.98, 0.012, 0.78), tuple(ws_c - ws_n * 0.045), rot=(WS_T, 0, 0), mat=glass))
body.append(T.box((0.07, 0.1, 0.82), tuple(ws_c + ws_n * 0.0), rot=(WS_T, 0, 0), mat=paint))  # centre pillar
# welded bars over the windshield
for k in range(9):
    x = -0.92 + k * 0.23
    body.append(T.box((0.028, 0.028, 0.86), tuple(ws_c + ws_n * 0.075 + Vector((x, 0, 0))), rot=(WS_T, 0, 0), mat=armor))
for k in range(4):
    up = Vector((0, -math.sin(math.radians(WS_T)), math.cos(math.radians(WS_T)))) * (-0.33 + k * 0.22)
    body.append(T.box((2.06, 0.026, 0.026), tuple(ws_c + ws_n * 0.1 + up), rot=(WS_T, 0, 0), mat=armor))
body.append(T.box((2.14, 0.05, 0.05), tuple(ws_c + ws_n * 0.07 + Vector((0, -0.115, 0.44))), rot=(WS_T, 0, 0), mat=armor))
body.append(T.box((2.14, 0.05, 0.05), tuple(ws_c + ws_n * 0.07 + Vector((0, 0.115, -0.44))), rot=(WS_T, 0, 0), mat=armor))


# ---------------------------------------------------------------- sides
def side(sx):
    x = sx * HW
    # cab window: an armour plate with a vision slit, bolted on
    body.append(T.box((0.05, 0.92, 0.82), (x + sx * 0.02, 1.2, 2.06), mat=armor, bevel=0.012))
    body.append(T.box((0.056, 0.55, 0.075), (x + sx * 0.022, 1.25, 2.12), mat=glass))
    for (dy, dz) in ((-0.4, -0.35), (0.4, -0.35), (-0.4, 0.35), (0.4, 0.35), (0, 0.35), (0, -0.35)):
        body.append(T.cyl(0.022, 0.03, (x + sx * 0.05, 1.2 + dy, 2.06 + dz), rot=(0, 90, 0), mat=bare, n=6))
    # mirror on a tube arm
    body.append(T.tube([(x, 1.75, 1.75), (x + sx * 0.3, 1.9, 1.78), (x + sx * 0.3, 1.9, 2.25), (x, 1.75, 2.3)], 0.018, mat=dark, n=5))
    body.append(T.box((0.05, 0.16, 0.36), (x + sx * 0.32, 1.9, 2.02), mat=dark, bevel=0.012))
    # step under the cab door and a grab handle
    body.append(T.box((0.26, 0.7, 0.05), (x + sx * 0.1, 1.3 - 0.75 * 0 , 0.5), mat=armor, bevel=0.01))
    body.append(T.tube([(x, 0.78, 1.5), (x + sx * 0.06, 0.78, 1.5), (x + sx * 0.06, 0.78, 2.1), (x, 0.78, 2.1)], 0.014, mat=bare, n=5))
    # belt line trim and a rub rail along the box
    body.append(T.box((0.03, 3.35, 0.05), (x + sx * 0.012, -1.22, 1.42), mat=bare))
    body.append(T.box((0.035, 2.15, 0.07), (x + sx * 0.014, -0.2 - 0.02, 0.72), mat=armor))
    # fender flares welded from strip
    for (ay, tr) in ((FA, TRACK_F), (RA, TRACK_R)):
        n = 8
        for k in range(n + 1):
            a = math.radians(8 + (164.0 * k / n))
            py, pz = ay + math.cos(a) * 0.72, R + math.sin(a) * 0.72
            body.append(T.box((0.16, 0.285, 0.035), (x + sx * 0.05, py, pz), rot=(math.degrees(a) - 90, 0, 0), mat=armor))
    # exhaust stack behind the cab with a heat shield
    body.append(T.cyl(0.065, 2.35, (x + sx * 0.1, 0.62, 1.95), mat=soot, n=10))
    body.append(T.cyl(0.095, 0.95, (x + sx * 0.1, 0.62, 2.0), mat=armor, n=10))
    for z in (1.2, 2.55):
        body.append(T.box((0.12, 0.05, 0.04), (x + sx * 0.05, 0.62, z), mat=bare))
    markers.append(T.marker("m_exh_" + ("r" if sx > 0 else "l"), (x + sx * 0.1, 0.62, 3.15)))
    # gatling pod on the nose: armoured box, feed chute into the body
    body.append(T.box((0.3, 0.95, 0.3), (sx * 1.3, 2.3, 1.12), mat=armor, bevel=0.03))
    body.append(T.box((0.2, 0.3, 0.14), (sx * 1.2, 1.95, 1.3), rot=(0, 0, 0), mat=armor, bevel=0.02))
    body.append(T.cyl(0.11, 0.12, (sx * 1.3, 2.82, 1.12), rot=(-90, 0, 0), mat=bare, n=12))
    markers.append(T.marker("m_spin_" + ("r" if sx > 0 else "l"), (sx * 1.3, 2.88, 1.12)))
    markers.append(T.marker("m_gun_" + ("r" if sx > 0 else "l"), (sx * 1.3, 3.62, 1.12)))
    # headlight in a steel cage, marker lamp
    body.append(T.cyl(0.15, 0.08, (sx * 0.82, NOSE + 0.02, 1.0), rot=(-90, 0, 0), mat=dark, n=12))
    body.append(T.cyl(0.115, 0.03, (sx * 0.82, NOSE + 0.06, 1.0), rot=(-90, 0, 0), mat=T.glow((1.0, 0.86, 0.6)), n=12))
    for k in (-1, 0, 1):
        body.append(T.box((0.3, 0.02, 0.02), (sx * 0.82, NOSE + 0.09, 1.0 + k * 0.08), mat=armor))
    body.append(T.box((0.1, 0.03, 0.06), (sx * 1.02, NOSE + 0.02, 1.24), mat=T.glow((1.0, 0.45, 0.05))))
    # tail lamps
    body.append(T.box((0.12, 0.03, 0.2), (sx * 0.98, REAR - 0.015, 1.05), mat=T.glow((0.9, 0.05, 0.03))))
    body.append(T.box((0.16, 0.05, 0.26), (sx * 0.98, REAR - 0.01, 1.05), mat=dark))
    # the tailgate's hinges at its foot; its locking bars and handles ride on the door
    body.append(T.cyl(0.035, 0.18, (sx * 0.55, REAR - 0.05, DOOR_Z0), rot=(0, 90, 0), mat=bare, n=8))
    door_parts.append(T.cyl(0.02, 1.7, (sx * 0.3, REAR - 0.075, DM), mat=bare, n=6))
    door_parts.append(T.box((0.22, 0.03, 0.05), (sx * 0.36, REAR - 0.09, 1.5), mat=bare))
    # roof rail
    body.append(T.tube([(sx * 0.98, -2.7, ROOF + 0.02), (sx * 0.98, -2.7, ROOF + 0.14), (sx * 0.98, 1.2, ROOF + 0.14), (sx * 0.98, 1.2, ROOF + 0.02)], 0.022, mat=armor, n=5))
    for y in (-1.4, -0.1):
        body.append(T.cyl(0.02, 0.12, (sx * 0.98, y, ROOF + 0.08), mat=armor, n=5))
    # horn speaker on the roof (every ice cream truck has them)
    body.append(T.lathe([(0.05, 0.0), (0.06, 0.16), (0.11, 0.3), (0.2, 0.4), (0.21, 0.4), (0.12, 0.28), (0.04, 0.02)], loc=(sx * 0.55, 1.05, ROOF + 0.2), rot=(-82, 0, 0), mat=bare, n=14))
    body.append(T.box((0.06, 0.06, 0.2), (sx * 0.55, 1.12, ROOF + 0.1), mat=armor))
    # mud flap
    body.append(T.box((0.5, 0.02, 0.42), (sx * TRACK_R, RA - 0.72, 0.38), mat=rubber))

both(side)

# serving hatch on the right: frame, roll-up steel shutter, fold-down counter
HY0, HY1, HZ0, HZ1 = -1.95, -0.25, 1.5, 2.36
xr = HW + 0.012
for (yy, zz, sy, sz) in (((HY0 + HY1) / 2, HZ1 + 0.03, HY1 - HY0 + 0.16, 0.07), ((HY0 + HY1) / 2, HZ0 - 0.03, HY1 - HY0 + 0.16, 0.07),
                         (HY0 - 0.045, (HZ0 + HZ1) / 2, 0.07, HZ1 - HZ0), (HY1 + 0.045, (HZ0 + HZ1) / 2, 0.07, HZ1 - HZ0)):
    body.append(T.box((0.06, sy, sz), (xr + 0.01, yy, zz), mat=bare, bevel=0.008))
n_slat = 10
for k in range(n_slat):
    z = HZ0 + (k + 0.5) * (HZ1 - HZ0) / n_slat
    body.append(T.box((0.03 if k % 2 else 0.045, HY1 - HY0, (HZ1 - HZ0) / n_slat * 0.92), (xr, (HY0 + HY1) / 2, z), mat=armor))
body.append(T.box((0.3, HY1 - HY0 + 0.1, 0.04), (xr + 0.16, (HY0 + HY1) / 2, HZ0 - 0.09), mat=bare, bevel=0.008))
for y in (HY0 + 0.15, HY1 - 0.15):
    body.append(T.tube([(xr, y, HZ0 - 0.42), (xr + 0.28, y, HZ0 - 0.11)], 0.014, mat=bare, n=5))
body.append(T.box((0.05, 0.1, 0.14), (xr + 0.03, HY1 - 0.4, HZ0 + 0.06), mat=bare, bevel=0.01))  # padlock hasp
# awning bar above the hatch
body.append(T.tube([(xr, HY0, HZ1 + 0.16), (xr + 0.1, HY0, HZ1 + 0.16), (xr + 0.1, HY1, HZ1 + 0.16), (xr, HY1, HZ1 + 0.16)], 0.02, mat=armor, n=5))

# ---------------------------------------------------------------- nose, grille, bumper, plow
body.append(T.box((1.2, 0.06, 0.44), (0, NOSE - 0.0, 0.98), mat=dark))
for k in range(5):
    body.append(T.box((1.24, 0.05, 0.035), (0, NOSE + 0.035, 0.82 + k * 0.08), mat=bare))
for k in range(6):  # hood louvres
    body.append(T.box((0.42, 0.03, 0.025), (0, 2.2 + k * 0.1, 1.535 - k * 0.0285), rot=(-16, 0, 0), mat=armor))
body.append(T.box((2.5, 0.2, 0.24), (0, NOSE + 0.14, 0.62), mat=armor, bevel=0.03))
for sx in (1, -1):  # frame horns to the plow
    body.append(T.box((0.12, 0.5, 0.14), (sx * 0.55, NOSE + 0.3, 0.52), mat=armor))
PY = NOSE + 0.56   # the plow's point
ang = 21.0
for sx in (1, -1):
    c = Vector((sx * 0.66, PY - 0.66 * math.tan(math.radians(ang)), 0.52))
    rz = -sx * ang
    rot = Matrix.Rotation(math.radians(rz), 4, "Z")
    body.append(T.box((1.42, 0.07, 0.78), tuple(c), rot=(-9, 0, rz), mat=armor, bevel=0.012))
    body.append(T.box((1.42, 0.17, 0.05), tuple(c + Vector((0, -0.02, 0.4))), rot=(0, 0, rz), mat=bare))
    for lx in (-0.5, 0.0, 0.5):
        p = c + rot @ Vector((lx, -0.14, 0.02))
        body.append(T.prism([(0, -0.36), (0.22, -0.36), (0, 0.36)], 0.035, loc=tuple(p), rot=(0, 0, rz + 180), mat=bare, plane="YZ"))
    for lx in (-0.52, -0.2, 0.12, 0.44):
        p = c + rot @ Vector((lx, 0.16, -0.2))
        body.append(T.cyl(0.055, 0.3, tuple(p), rot=(-90, 0, rz), mat=bare, n=8, r2=0.004))
body.append(T.box((0.13, 0.16, 0.86), (0, PY - 0.02, 0.52), rot=(-9, 0, 0), mat=bare, bevel=0.02))
body.append(T.box((0.09, 0.012, 0.6), (0.6, NOSE + 0.01, 2.0 - 0.38), rot=(WS_T, 0, 0), mat=dark))  # wipers (parked)

# ---------------------------------------------------------------- rear
body.append(T.box((2.3, 0.34, 0.1), (0, REAR - 0.2, 0.52), mat=armor, bevel=0.015))
door_parts.append(T.box((0.42, 0.02, 0.2), (0, REAR - 0.07, 0.95), mat=T.M("paint", (0.5, 0.48, 0.3), 0.8, 0.6, 0.7)))  # plate, on the tailgate
for sx in (1, -1):
    body.append(T.box((0.12, 0.3, 0.2), (sx * 0.7, REAR - 0.18, 0.4), mat=armor))

# ---------------------------------------------------------------- roof: vent, mortar, fuel cans
body.append(T.sphere(0.24, (0.6, -2.5, ROOF + 0.02), mat=bare, n=12, scale=(1, 1, 0.45)))
MB = Vector((0.0, -1.75, ROOF))   # on the centre line: the missile leaves along the car's axis (the HOLLYWOOD shot)
tilt = 34.0
mdir = Vector((0, math.sin(math.radians(tilt)), math.cos(math.radians(tilt))))
body.append(T.cyl(0.34, 0.07, tuple(MB + Vector((0, 0, 0.035))), mat=armor, n=14, bevel=0.01))
for sx in (1, -1):
    body.append(T.prism([(-0.22, 0.0), (0.22, 0.0), (0.1, 0.42), (-0.06, 0.42)], 0.035, loc=tuple(MB + Vector((sx * 0.21, 0, 0.07))), mat=armor, plane="YZ"))
body.append(T.cyl(0.16, 1.05, tuple(MB + Vector((0, 0, 0.3)) + mdir * 0.42), rot=(-tilt, 0, 0), mat=soot, n=14))
body.append(T.cyl(0.185, 0.1, tuple(MB + Vector((0, 0, 0.3)) + mdir * 0.92), rot=(-tilt, 0, 0), mat=armor, n=14))
body.append(T.cyl(0.185, 0.07, tuple(MB + Vector((0, 0, 0.3)) + mdir * 0.1), rot=(-tilt, 0, 0), mat=armor, n=14))
launcher = MB + Vector((0, 0, 0.3)) + mdir * 1.0
markers.append(T.marker("m_launcher", tuple(launcher)))
for k, mcan in enumerate((canred, olive)):
    cy = -2.66 + k * 0.4
    body.append(T.box((0.62, 0.3, 0.52), (-0.5, cy, ROOF + 0.3), mat=mcan, bevel=0.035))
    body.append(T.cyl(0.05, 0.08, (-0.28, cy, ROOF + 0.59), mat=bare, n=8))
    body.append(T.box((0.3, 0.04, 0.04), (-0.58, cy, ROOF + 0.6), mat=bare))
body.append(T.box((0.72, 0.03, 0.03), (-0.5, -2.46, ROOF + 0.42), mat=bare))  # strap bar
body.append(T.box((0.03, 0.8, 0.03), (-0.84, -2.46, ROOF + 0.42), mat=bare))
body.append(T.tube([(-0.28, -2.26, ROOF + 0.63), (-0.2, -2.1, ROOF + 0.5), (-0.1, -1.98, ROOF + 0.2), (-0.05, -1.9, ROOF + 0.3)], 0.025, mat=rubber, n=6))

# ---------------------------------------------------------------- roof sign: burnt-out soft serve cone on a frame
SC = Vector((0, 0.1, ROOF))   # centre of the sign's footprint
ring_z = 0.52
for sx in (1, -1):
    for sy in (1, -1):
        body.append(T.tube([tuple(SC + Vector((sx * 0.4, sy * 0.36, 0.0))), tuple(SC + Vector((sx * 0.25, sy * 0.22, ring_z)))], 0.028, mat=armor, n=6))
        body.append(T.box((0.16, 0.16, 0.03), tuple(SC + Vector((sx * 0.4, sy * 0.36, 0.015))), mat=armor))
body.append(T.lathe([(0.3, -0.035), (0.34, -0.035), (0.34, 0.035), (0.3, 0.035)], loc=tuple(SC + Vector((0, 0, ring_z))), mat=armor, n=16))
cone_tip = SC + Vector((0, 0, 0.12))
CH = 0.78
cone = T.lathe([(0.0, 0.0), (0.05, 0.05), (0.36, CH), (0.38, CH + 0.06), (0.3, CH + 0.06)], loc=tuple(cone_tip), mat=wafer, n=18)
body.append(cone)
sw_base = cone_tip + Vector((0, 0, CH + 0.04))
sw = T.lathe([(0.3, 0.0), (0.4, 0.05), (0.42, 0.13), (0.34, 0.2), (0.3, 0.22), (0.34, 0.28), (0.32, 0.36), (0.24, 0.42),
              (0.21, 0.44), (0.23, 0.5), (0.19, 0.58), (0.11, 0.63), (0.08, 0.72), (0.03, 0.8), (0.0, 0.84)], loc=tuple(sw_base), mat=swirl, n=18)
# blown open at the back
T.apply(sw)
T.cut(sw, T.sphere(0.24, tuple(sw_base + Vector((-0.2, -0.3, 0.3))), n=10))
body.append(sw)
body.append(T.sphere(0.2, tuple(sw_base + Vector((-0.06, -0.1, 0.22))), mat=soot, n=8))
body.append(T.sphere(0.07, tuple(sw_base + Vector((-0.15, -0.2, 0.28))), mat=T.glow((1.0, 0.4, 0.06)), n=6))
markers.append(T.marker("m_cone", tuple(sw_base + Vector((-0.12, -0.18, 0.4)))))
markers.append(T.marker("m_top", (0.0, -1.0, ROOF + 0.3)))
markers.append(T.marker("m_head", (0.0, NOSE + 0.2, 1.0)))

# ---------------------------------------------------------------- underbody (dark, simple)
for sx in (1, -1):
    body.append(T.box((0.14, 5.3, 0.2), (sx * 0.5, -0.05, 0.5), mat=dark))
body.append(T.cyl(0.07, 2.0, (0, FA, R), rot=(0, 90, 0), mat=dark, n=6))
body.append(T.cyl(0.08, 1.9, (0, RA, R), rot=(0, 90, 0), mat=dark, n=6))
body.append(T.sphere(0.2, (0, RA, R), mat=dark, n=8))
body.append(T.cyl(0.04, 3.0, (0, RA + 1.5, R + 0.02), rot=(-90, 0, 0), mat=dark, n=5))
body.append(T.box((0.5, 1.1, 0.3), (-0.82, -0.2, 0.42), mat=armor, bevel=0.03))

# ---------------------------------------------------------------- wheels (axle along X, outer face at +X) and the gatling spinner
def wheel(name, width):
    w = width
    tyre = [(R * 0.6, -w / 2), (R * 0.9, -w / 2), (R * 0.985, -w / 2 + 0.045), (R, -w * 0.2), (R - 0.022, -w * 0.17), (R - 0.022, -w * 0.07),
            (R, -w * 0.04), (R, w * 0.04), (R - 0.022, w * 0.07), (R - 0.022, w * 0.17), (R, w * 0.2), (R * 0.985, w / 2 - 0.045), (R * 0.9, w / 2), (R * 0.6, w / 2)]
    parts = [T.lathe(tyre, rot=(0, 90, 0), mat=rubber, n=22, angle=50)]
    rim = [(R * 0.6, -w / 2 + 0.02), (R * 0.6, w / 2 - 0.02), (R * 0.56, w / 2 - 0.035), (R * 0.5, w / 2 - 0.1), (R * 0.3, w / 2 - 0.13), (R * 0.27, w / 2 - 0.05), (0.0, w / 2 - 0.05)]
    parts.append(T.lathe(rim, rot=(0, 90, 0), mat=T.M("steel", (0.06, 0.055, 0.05), 0.6, 0.7, 0.8), n=22))
    for k in range(8):
        a = math.radians(45 * k)
        parts.append(T.cyl(0.022, 0.035, (w / 2 - 0.04, math.cos(a) * R * 0.2, math.sin(a) * R * 0.2), rot=(0, 90, 0), mat=bare, n=6))
    for k in range(4):  # hand holes in the dish
        a = math.radians(90 * k + 22)
        parts.append(T.cyl(0.04, 0.02, (w / 2 - 0.105, math.cos(a) * R * 0.4, math.sin(a) * R * 0.4), rot=(0, 90, 0), mat=dark, n=8))
    parts.append(T.cyl(R * 0.12, 0.07, (w / 2 - 0.03, 0, 0), rot=(0, 90, 0), mat=bare, n=10))
    return T.join(parts, name)

wheel_f = wheel("wheel_f", 0.36)
wheel_r = wheel("wheel_r", 0.52)
sp = [T.cyl(0.085, 0.05, (0, 0.06, 0), rot=(-90, 0, 0), mat=bare, n=12), T.cyl(0.085, 0.04, (0, 0.5, 0), rot=(-90, 0, 0), mat=bare, n=12)]
for k in range(6):
    a = math.radians(60 * k)
    sp.append(T.cyl(0.021, 0.74, (math.cos(a) * 0.058, 0.37, math.sin(a) * 0.058), rot=(-90, 0, 0), mat=dark, n=6))
sp.append(T.cyl(0.03, 0.72, (0, 0.36, 0), rot=(-90, 0, 0), mat=dark, n=6))
spinner = T.join(sp, "spinner")
markers += [T.marker("m_wheel_fr", (TRACK_F, FA, R)), T.marker("m_wheel_fl", (-TRACK_F, FA, R)),
            T.marker("m_wheel_rr", (TRACK_R, RA, R)), T.marker("m_wheel_rl", (-TRACK_R, RA, R))]

body_ob = T.join(body, "body")
door_ob = T.join(door_parts, "door")
print("triangles: body %d, wheel_f %d, wheel_r %d, spinner %d" % (T.tri_count([body_ob]), T.tri_count([wheel_f]), T.tri_count([wheel_r]), T.tri_count([spinner])))

if "--shape" in sys.argv:
    out = sys.argv[sys.argv.index("--shape") + 1]
    wf = [T.dup(wheel_f, (TRACK_F, FA, R)), T.dup(wheel_f, (-TRACK_F, FA, R), rot=(0, 0, 180)), T.dup(wheel_r, (TRACK_R, RA, R)), T.dup(wheel_r, (-TRACK_R, RA, R), rot=(0, 0, 180))]
    wheel_f.location = (0, 0, -50)
    wheel_r.location = (0, 0, -50)
    spinner.location = (1.3, 2.88, 1.12)
    T.preview(out, size=(1000, 620), eye=(6.5, 7.5, 3.6), look=(0, 0.2, 1.5), fov=42, samples=12)
    T.preview(out.replace(".png", "_b.png"), size=(1000, 620), eye=(-7.0, -6.5, 4.2), look=(0, 0, 1.6), fov=42, samples=12)
    sys.exit(0)

# ---------------------------------------------------------------- paint job: band, lettering, dots, seams, damage
def band_fn(P, N):
    return ((np.abs(N[:, 0]) > 0.7) & (P[:, 2] > 0.86) & (P[:, 2] < 1.38) & (P[:, 1] > REAR - 0.02) & (P[:, 1] < 0.72)).astype(np.float32)
regions.append((band_fn, CRIMSON, ("paint",)))
def rear_band(P, N):
    return ((N[:, 1] < -0.7) & (P[:, 2] > 0.86) & (P[:, 2] < 1.38) & (np.abs(P[:, 0]) < HW)).astype(np.float32)
regions.append((rear_band, CRIMSON, ("paint",)))
def waffle(P, N):  # diamond grid pressed into the cone
    d = P - np.array(cone_tip, dtype=np.float32)
    a = np.arctan2(d[:, 0], d[:, 1])
    u = a * 3.0 + d[:, 2] * 9.0
    v = a * 3.0 - d[:, 2] * 9.0
    line = (np.abs((u % 1.0) - 0.5) > 0.42) | (np.abs((v % 1.0) - 0.5) > 0.42)
    near = (np.abs(d[:, 0]) < 0.5) & (np.abs(d[:, 1]) < 0.5) & (d[:, 2] > -0.05) & (d[:, 2] < CH + 0.1)
    return (line & near).astype(np.float32) * 0.75
regions.append((waffle, (0.09, 0.045, 0.015), ("plastic",)))

letter = T.stencil("ICE CREAM", (0.3, 0.035, 0.045), 150, font=T.FONT_BOLD, bridges=False, pad=0.08)
decals.append(T.Decal(letter, (-HW, -1.1, 2.0), (-1, 0, 0), (0, 0, 1), (3.0, 0.5), depth=0.08, kinds=("paint",), opacity=0.85))
small = T.stencil("ICE CREAM", (0.3, 0.035, 0.045), 120, bridges=False, pad=0.08)
decals.append(T.Decal(small, (HW, -1.1, HZ1 + 0.2 - 0.02), (1, 0, 0), (0, 0, 1), (1.5, 0.2), depth=0.06, kinds=("paint",), opacity=0.85))
dots = T.dots_image((0.36, 0.09, 0.16), n=16, seed=4)
decals.append(T.Decal(dots, (-HW, -1.2, 1.9), (-1, 0, 0), (0, 0, 1), (3.3, 1.5), depth=0.06, kinds=("paint",), opacity=0.5))
decals.append(T.Decal(T.dots_image((0.36, 0.09, 0.16), n=9, seed=9, size=(256, 256)), (0, REAR, 2.0), (0, -1, 0), (0, 0, 1), (2.0, 1.2), depth=0.06, kinds=("paint",), opacity=0.5))
decals.append(T.Decal(T.dots_image((0.36, 0.09, 0.16), n=5, seed=12, size=(256, 128)), (HW, 0.1, 1.95), (1, 0, 0), (0, 0, 1), (0.6, 1.0), depth=0.06, kinds=("paint",), opacity=0.5))
# door gaps: cab doors on both sides, the pair of rear doors
door = T.lines_image([(0.03, 0.02, 0.03, 0.98), (0.97, 0.02, 0.97, 0.98), (0.03, 0.02, 0.97, 0.02), (0.03, 0.98, 0.97, 0.98)], size=(256, 512), width=5)
for sx in (1, -1):
    decals.append(T.Decal(door, (sx * HW, 1.22, 1.5), (sx, 0, 0), (0, 0, 1), (1.05, 1.9), depth=0.05, kinds=("paint",)))
rear_doors = T.lines_image([(0.5, 0.02, 0.5, 0.98), (0.03, 0.02, 0.03, 0.98), (0.97, 0.02, 0.97, 0.98), (0.03, 0.02, 0.97, 0.02), (0.03, 0.98, 0.97, 0.98)], size=(512, 512), width=5)
decals.append(T.Decal(rear_doors, (0, REAR - 0.04, DM), (0, -1, 0), (0, 0, 1), (DOOR_W - 0.02, DOOR_Z1 - DOOR_Z0 - 0.02), depth=0.05, kinds=("paint",)))
# panel seams along the box sides
seams = T.lines_image([(0.33, 0.0, 0.33, 1.0), (0.66, 0.0, 0.66, 1.0)], size=(512, 64), width=3, alpha=0.7)
for sx in (1, -1):
    decals.append(T.Decal(seams, (sx * HW, -1.2, 1.7), (sx, 0, 0), (0, 0, 1), (3.3, 1.9), depth=0.05, kinds=("paint",)))
# battle damage: bullet strikes, dried blood on the plow and the bumper
decals.append(T.Decal(T.holes_image(15, 3), (-HW, -0.9, 1.75), (-1, 0, 0), (0, 0, 1), (3.4, 1.5), depth=0.06, kinds=("paint",)))
decals.append(T.Decal(T.holes_image(8, 5), (HW, 0.9, 1.3), (1, 0, 0), (0, 0, 1), (1.6, 1.0), depth=0.06, kinds=("paint", "steel")))
decals.append(T.Decal(T.holes_image(7, 8, size=(256, 256)), (0, REAR, 1.9), (0, -1, 0), (0, 0, 1), (1.8, 1.4), depth=0.06, kinds=("paint",)))
for (cx, cz, sd, op) in ((0.5, 0.55, 2, 0.9), (-0.6, 0.45, 6, 0.8)):
    decals.append(T.Decal(T.splatter_image(seed=sd), (cx, PY - 0.2, cz), (0, 1, 0), (0, 0, 1), (1.1, 0.9), depth=0.7, kinds=("steel",), opacity=op))
decals.append(T.Decal(T.splatter_image(seed=11), (0.2, NOSE, 1.1), (0, 1, 0), (0, 0, 1), (1.3, 0.8), depth=0.2, kinds=("paint", "steel"), opacity=0.6))

# ---------------------------------------------------------------- bake and export
# wheels and the spinner are baked beside the truck (not in the arches: they turn) but share its atlas
wheel_f.location = (4.5, 1.0, R)
wheel_r.location = (4.5, -1.0, R)
spinner.location = (4.5, 2.0, 1.0)
import bpy
bpy.context.view_layer.update()
for o in (wheel_f, wheel_r, spinner):
    T.apply(o)
objs = [body_ob, wheel_f, wheel_r, spinner, door_ob]
T.unwrap(objs, margin=0.002)
if "--nobake" not in sys.argv:
    g = T.gbuffer(objs, size=2048, ao_dist=0.7, bevel_r=0.014, ao_samples=24)
    al, nm, orm = T.weather(g, decals, seed=21, dust_from=0.25, dust_to=1.5, regions=regions,
        soot=[(tuple(launcher), 0.75), ((HW + 0.1, 0.62, 3.0), 0.45), ((-HW - 0.1, 0.62, 3.0), 0.45), (tuple(sw_base + Vector((-0.1, -0.15, 0.4))), 0.95)])
    T.save_maps("sweet_tooth", al, nm, orm)
wheel_f.data.transform(Matrix.Translation((-4.5, -1.0, -R)))
wheel_r.data.transform(Matrix.Translation((-4.5, 1.0, -R)))
spinner.data.transform(Matrix.Translation((-4.5, -2.0, -1.0)))
door_ob.data.transform(Matrix.Translation((0, -(REAR - 0.03), -DOOR_Z0)))  # its origin is the hinge
T.export_glb("sweet_tooth", objs, markers=markers)
print("ok")

"""Sweet Bot, third pass (owner: "a mini Sweet Bot from TM Black, no guessing"). Every part is placed from
measurements of the TMB robot (docs/reference/3d_models/twisted-metal-black.zip, mesh Mesh_1348.002, scaled to
1.8 m, front turned to +Y; parts listed with their centres and sizes by a loose-part scan), then built as our own
detailed model: a low chassis on four wheels (narrow front pair under slanted fenders with a stubby gun on each,
wide rear pair on an axle housing), the truck's lower box standing up as hips, a wide waist ledge, the cab front
as the chest (rounded hood bulge, a split windshield, the roof as an overhanging visor), shoulder blocks, a
missile pod tipped up and out on each shoulder, TMB's black beam behind the head on two struts, the right fist
raised beside the head, the left forearm forward along a long hex cannon. The head is Sweet Tooth's TM 2012
clown head (owner, round 19), sized and placed like TMB's. Cream paint with faded rust dots, dark steel arms.
    /tmp/bpy3.13/bin/python tools/blender/build_sweet_bot.py              # build, bake, export
    /tmp/bpy3.13/bin/python tools/blender/build_sweet_bot.py --shape a.png  # quick look, no bake
Blender space: +Y forward, +Z up. Writes assets/models/sweet_bot.glb: legs (chassis, wheels, guns, hips),
upper (its origin is the waist; it turns toward its target), markers m_waist, m_head, m_tube_l0..9 and
m_tube_r0..9 (tube mouths, bottom row first, in firing order)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
import clown_head
import numpy as np
from mathutils import Matrix, Vector

T.reset()
V = Vector
CREAM = (0.43, 0.40, 0.33)
paint = T.M("paint", CREAM, wear=0.72, rust=0.66, dirt=0.75)
armor = T.M("steel", (0.035, 0.035, 0.038), wear=0.7, rust=0.6, dirt=0.6)
bare = T.M("steel", (0.10, 0.10, 0.10), wear=0.7, rust=0.5, dirt=0.5)
dark = T.M("steel", (0.012, 0.012, 0.013), wear=0.3, rust=0.3, dirt=0.7)
rubber = T.M("rubber", (0.016, 0.016, 0.016), dirt=0.7)
soot = T.M("burnt", (0.05, 0.04, 0.03), rust=0.5)
warhead = T.M("paint", (0.32, 0.045, 0.03), wear=0.65, rust=0.45, dirt=0.5)
chrome = T.M("steel", (0.3, 0.3, 0.28), wear=0.25, rust=0.25, dirt=0.45)
bronze = T.M("steel", (0.2, 0.1, 0.035), wear=0.5, rust=0.75, dirt=0.5)
decals = []
regions = []
markers = []


def aim(d):
    q = Vector(d).normalized().to_track_quat("Z", "Y").to_euler()
    return (math.degrees(q.x), math.degrees(q.y), math.degrees(q.z))


def spike(base, d, length, r, mat=bronze, n=8):
    d = Vector(d).normalized()
    return T.cyl(r, length, loc=tuple(Vector(base) + d * length / 2), rot=aim(d), mat=mat, n=n, r2=r * 0.06)


def limb(a, b, w, d, mat, bevel=0.03):
    """A box from a to b (any direction), w across (x), d thick."""
    a, b = Vector(a), Vector(b)
    v = b - a
    return T.box((w, d, v.length), loc=tuple((a + b) / 2), rot=aim(v), mat=mat, bevel=bevel)


def rod(a, b, r, mat, n=10):
    a, b = Vector(a), Vector(b)
    v = b - a
    return T.cyl(r, v.length, loc=tuple((a + b) / 2), rot=aim(v), mat=mat, n=n)


def wheel(c, r, w, parts):
    """A knobbly off-road tyre (tread blocks round it), a steel rim with lug nuts, a dark hub cap."""
    c = Vector(c)
    parts.append(T.cyl(r * 0.9, w, loc=tuple(c), rot=(0, 90, 0), mat=rubber, n=16, bevel=0.03))
    n = 10
    for k in range(n):
        a = 2 * math.pi * (k + 0.5 * (k % 2)) / n
        parts.append(T.box((w * (0.92 if k % 2 else 0.7), r * 0.2, r * 0.15), loc=tuple(c + V((0, math.cos(a), math.sin(a))) * r * 0.93),
            rot=(math.degrees(a) - 90, 0, 0), mat=rubber))
    for side in (1, -1):
        parts.append(T.cyl(r * 0.56, 0.03, loc=tuple(c + V((side * w / 2, 0, 0))), rot=(0, 90, 0), mat=bare, n=16, bevel=0.008))
        for k in range(6):
            a = 2 * math.pi * k / 6
            parts.append(T.cyl(r * 0.055, 0.05, loc=tuple(c + V((side * (w / 2 + 0.02), math.cos(a) * r * 0.34, math.sin(a) * r * 0.34))), rot=(0, 90, 0), mat=dark, n=6))
        parts.append(T.cyl(r * 0.17, 0.07, loc=tuple(c + V((side * (w / 2 + 0.025), 0, 0))), rot=(0, 90, 0), mat=dark, n=10, r2=r * 0.12))


def piston(a, b, parts, r=0.045):
    """A hydraulic ram: dark cylinder, a bright rod sliding out of it, ball joints at both ends."""
    a, b = Vector(a), Vector(b)
    m = a.lerp(b, 0.55)
    parts.append(rod(a, m, r, dark))
    parts.append(rod(m - (b - a).normalized() * 0.06, b, r * 0.5, chrome, 8))
    parts.append(T.cyl(r * 1.15, 0.04, loc=tuple(m), rot=aim(b - a), mat=bare, n=10))
    for e in (a, b):
        parts.append(T.sphere(r * 1.15, loc=tuple(e), mat=bare, n=8))


def rivets(a, b, n, parts, r=0.016):
    for k in range(n):
        parts.append(T.sphere(r, loc=tuple(Vector(a).lerp(Vector(b), k / max(1, n - 1))), mat=bare, n=6))


def trim(c, w, h, axis, parts, t=0.035, studs=True):
    """A riveted steel frame round a panel face centred at c; axis = the face's normal, +-Y or +-X."""
    c = Vector(c)
    if abs(axis[1]) > 0.5:
        u, v = V((1, 0, 0)), V((0, 0, 1))
        sz_u, sz_v = (w + t, t, t), (t, t, h)
    else:
        u, v = V((0, 1, 0)), V((0, 0, 1))
        sz_u, sz_v = (t, w + t, t), (t, t, h)
    for e in (1, -1):
        parts.append(T.box(sz_u, loc=tuple(c + v * e * h / 2), mat=armor, bevel=0.006))
        parts.append(T.box(sz_v, loc=tuple(c + u * e * w / 2), mat=armor, bevel=0.006))
        if studs:
            out = Vector(axis).normalized() * t * 0.5
            rivets(c + v * e * h / 2 - u * w * 0.45 + out, c + v * e * h / 2 + u * w * 0.45 + out, max(3, int(w / 0.12)), parts)


def stacks(c, h, parts, gap=0.36):
    """Two blackened exhaust stacks with clamps, Sweet Tooth's truck's."""
    for sx in (1, -1):
        b = Vector(c) + V((sx * gap / 2, 0, 0))
        parts.append(rod(b, b + V((0, 0, h)), 0.055, bare, 12))
        parts.append(T.cyl(0.072, 0.14, loc=tuple(b + V((0, 0, h - 0.02))), mat=soot, n=12, r2=0.085))
        for z in (0.18, 0.55):
            parts.append(T.cyl(0.068, 0.035, loc=tuple(b + V((0, 0, h * z))), mat=dark, n=10))


def hose(points, parts, r=0.028):
    parts.append(T.tube([tuple(p) for p in points], r, mat=rubber, n=7))


def fist(c, sx, parts, s=1.0, down=(0, 0.25, -1)):
    """A clawed steel hand: palm, knuckle guard, three two-jointed fingers with hooked claws, a thumb."""
    c = Vector(c)
    parts.append(T.box((0.27 * s, 0.3 * s, 0.24 * s), loc=tuple(c), mat=armor, bevel=0.03 * s))
    parts.append(T.box((0.3 * s, 0.09 * s, 0.1 * s), loc=tuple(c + V((0, 0.13, 0.08)) * s), mat=bare, bevel=0.012))
    rivets(c + V((-0.11, 0.18, 0.08)) * s, c + V((0.11, 0.18, 0.08)) * s, 4, parts, 0.014)
    for f in range(3):
        x = (f - 1) * 0.085
        k1 = c + V((x, 0.13, -0.08)) * s
        k2 = k1 + V((0, 0.09, -0.07)) * s
        tip = k2 + V((0, 0.0, -0.12)) * s
        parts.append(limb(k1, k2, 0.07 * s, 0.075 * s, armor, 0.01))
        parts.append(limb(k2, tip, 0.064 * s, 0.068 * s, armor, 0.01))
        parts.append(T.sphere(0.04 * s, loc=tuple(k2), mat=bare, n=8))
        parts.append(spike(tip, (0, -0.35, -1), 0.13 * s, 0.03 * s, bare, 6))
    t1 = c + V((-sx * 0.14, 0.06, -0.02)) * s
    t2 = t1 + V((-sx * 0.04, 0.12, -0.1)) * s
    parts.append(limb(t1, t2, 0.07 * s, 0.07 * s, armor, 0.01))
    parts.append(spike(t2, (sx * 0.3, 0.4, -1), 0.1 * s, 0.026 * s, bare, 6))


def elbow(c, parts, r=0.11):
    parts.append(T.sphere(r, loc=tuple(c), mat=bare, n=12))
    parts.append(T.cyl(r * 1.05, r * 0.9, loc=tuple(c), rot=(0, 90, 0), mat=dark, n=12))


def stencil(text, c, n, size, seed=0, opacity=0.55):
    decals.append(T.Decal(T.stencil(text, color=(0.32, 0.05, 0.04)), tuple(c), tuple(n), (0, 0, 1), size, depth=0.1, kinds=("paint",), opacity=opacity))


def tubes(c, cols, rows, pitch, facing, parts, tag):
    """A grid of launch tubes on a face centred at c looking along `facing` (+Y or up)."""
    f = Vector(facing).normalized()
    side = V((1, 0, 0))
    up = f.cross(side).normalized() if abs(f.x) < 0.9 else V((0, 0, 1))
    if up.z < 0:
        up = -up
    k = 0
    for row in range(rows):
        for col in range(cols):
            p = Vector(c) + side * (col - (cols - 1) / 2) * pitch + up * (row - (rows - 1) / 2) * pitch
            parts.append(T.cyl(pitch * 0.42, 0.1, loc=tuple(p), rot=aim(f), mat=dark, n=8))
            parts.append(T.cyl(pitch * 0.3, 0.09, loc=tuple(p + f * 0.06), rot=aim(f), mat=warhead, n=8, r2=pitch * 0.05))
            k += 1
    fw, fh = cols * pitch + 0.05, rows * pitch + 0.05
    for e in (1, -1):  # a steel frame round the pod's face
        parts.append(T.box((fw + 0.05, 0.05, 0.05), loc=tuple(Vector(c) + up * e * fh / 2 - f * 0.01), mat=armor, bevel=0.008))
        parts.append(rod(Vector(c) + side * e * fw / 2 + up * fh / 2 - f * 0.01, Vector(c) + side * e * fw / 2 - up * fh / 2 - f * 0.01, 0.025, armor, 6))
    return k


def dots(c, n, size, seed, opacity=0.55):
    """TMB's faded rust-red polka dots on the cream paint: few, soft, never black."""
    decals.append(T.Decal(T.dots_image((0.34, 0.12, 0.06), n=7, seed=seed, size=(256, 256), r=(14, 22)), tuple(c), tuple(n), (0, 0, 1) if abs(n[2]) < 0.9 else (0, 1, 0), size, depth=0.12, kinds=("paint",), opacity=opacity))



H = 1.8                     # TMB's robot measured at 1.8 m; the whole model is scaled by S at the end
S = 1.75 / H                # about 1.75 m tall: it still rides out of the truck's box
WAIST = V((0, 0, 0.72))
legs, upper = [], []


def gun(c, parts):
    """TMB's stubby fender gun: a round body, a hex muzzle, a sight block on top, a bracket under it."""
    c = Vector(c)
    parts.append(T.cyl(0.052, 0.17, loc=tuple(c), rot=(-90, 0, 0), mat=dark, n=12, bevel=0.008))
    parts.append(T.cyl(0.041, 0.13, loc=tuple(c + V((0, 0.14, 0))), rot=(-90, 0, 0), mat=bare, n=6))
    parts.append(T.cyl(0.026, 0.03, loc=tuple(c + V((0, 0.215, 0))), rot=(-90, 0, 0), mat=soot, n=8))
    parts.append(T.box((0.05, 0.07, 0.035), loc=tuple(c + V((0, -0.02, 0.06))), mat=armor, bevel=0.006))
    parts.append(T.box((0.06, 0.1, 0.06), loc=tuple(c + V((0, -0.03, -0.06))), mat=armor, bevel=0.008))


# ---------------------------------------------------------------- legs: chassis, wheels, fenders, guns, the hips
legs.append(T.box((0.3, 0.64, 0.11), loc=(0, -0.11, 0.2), mat=dark, bevel=0.015))           # spine frame
legs.append(T.box((0.44, 0.38, 0.03), loc=(0, -0.13, 0.285), mat=armor, bevel=0.006))        # deck plate
legs.append(rod(V((-0.32, 0.15, 0.155)), V((0.32, 0.15, 0.155)), 0.025, bare))               # front axle
legs.append(T.box((0.34, 0.2, 0.14), loc=(0, -0.4, 0.165), mat=dark, bevel=0.02))             # rear axle housing
legs.append(T.cyl(0.07, 0.1, loc=(0, -0.4, 0.165), rot=(0, 90, 0), mat=bare, n=10))          # its differential
for sx in (1, -1):
    wheel((sx * 0.36, 0.15, 0.155), 0.155, 0.15, legs)                                        # narrow front pair
    wheel((sx * 0.27, -0.4, 0.165), 0.165, 0.22, legs)                                        # wide rear pair
    legs.append(T.cyl(0.03, 0.06, loc=(sx * 0.36 - sx * 0.1, 0.15, 0.155), rot=(0, 90, 0), mat=dark, n=6))  # hex hub nut
    # slanted fender over the front wheel, rising toward the hips (TMB: 24 deg), braced to the axle
    legs.append(T.box((0.13, 0.56, 0.035), loc=(sx * 0.35, 0.19, 0.31), rot=(-24, 0, 0), mat=armor, bevel=0.008))
    legs.append(T.box((0.035, 0.42, 0.16), loc=(sx * 0.29, 0.13, 0.27), rot=(-24, 0, 0), mat=armor, bevel=0.006))
    legs.append(limb(V((sx * 0.3, 0.15, 0.17)), V((sx * 0.3, 0.02, 0.36)), 0.04, 0.04, bare, 0.008))
    rivets(V((sx * 0.35, 0.42, 0.21)), V((sx * 0.35, -0.03, 0.41)), 5, legs, 0.012)
    gun((sx * 0.38, 0.22, 0.4), legs)                                                          # one on each fender
    legs.append(T.box((0.045, 0.1, 0.1), loc=(sx * 0.29, -0.6, 0.27), mat=rubber))             # mud flaps
# the hips: the truck's box stood up (TMB 0.58 x 0.62), tail lights and a framed door on its back
legs.append(T.box((0.58, 0.62, 0.42), loc=(0, -0.09, 0.5), mat=paint, bevel=0.035))
trim(V((0, 0.225, 0.5)), 0.46, 0.32, (0, 1, 0), legs)
legs.append(limb(V((-0.25, 0.235, 0.66)), V((0.25, 0.235, 0.34)), 0.07, 0.02, armor, 0.006))  # diagonal strap
trim(V((0, -0.405, 0.5)), 0.46, 0.32, (0, -1, 0), legs)
for sx in (1, -1):
    trim(V((sx * 0.295, -0.09, 0.5)), 0.5, 0.32, (sx, 0, 0), legs, studs=False)
    legs.append(limb(V((sx * 0.296, -0.32, 0.36)), V((sx * 0.296, 0.14, 0.64)), 0.025, 0.04, armor, 0.005))  # side brace
    legs.append(T.box((0.1, 0.03, 0.06), loc=(sx * 0.2, -0.41, 0.62), mat=T.glow((0.9, 0.06, 0.03))))  # tail lights
    legs.append(T.box((0.13, 0.035, 0.09), loc=(sx * 0.2, -0.405, 0.62), mat=dark, bevel=0.008))
for k in range(8):                                                                              # vent slats under the chest
    legs.append(T.box((0.02, 0.16, 0.03), loc=(-0.12 + k * 0.037, 0.13, 0.72), mat=dark))
legs.append(T.cyl(0.25, 0.04, loc=(0, -0.08, 0.72), mat=dark, n=20))                          # the turret ring
dots(V((0, 0.24, 0.5)), (0, 1, 0), (0.5, 0.38), 3)
dots(V((0.3, -0.09, 0.5)), (1, 0, 0), (0.55, 0.38), 4)
dots(V((-0.3, -0.09, 0.5)), (-1, 0, 0), (0.55, 0.38), 5)

# ---------------------------------------------------------------- upper: turns at the waist
up = upper
# the waist ledge: TMB's wide bar in front (0.82) and the rails back along the sides, little brackets on it
up.append(T.box((0.6, 0.54, 0.05), loc=(0, -0.08, 0.745), mat=dark, bevel=0.01))
up.append(T.box((0.82, 0.06, 0.09), loc=(0, 0.17, 0.725), mat=armor, bevel=0.012))
for sx in (1, -1):
    up.append(T.box((0.045, 0.5, 0.09), loc=(sx * 0.24, -0.05, 0.725), mat=armor, bevel=0.01))
    up.append(T.box((0.05, 0.08, 0.13), loc=(sx * 0.36, 0.17, 0.75), mat=bare, bevel=0.008))
    rivets(V((sx * 0.2, 0.205, 0.725)), V((sx * 0.4, 0.205, 0.725)), 3, up, 0.012)
# the chest: the cab front. A rounded hood bulge growing forward to the windshield, which leans back (TMB)
SECS = [(0.76, 0.58, 0.16, 0.22), (0.86, 0.68, 0.22, 0.28), (0.96, 0.72, 0.24, 0.31), (1.05, 0.74, 0.25, 0.32),
        (1.065, 0.74, 0.25, 0.32), (1.22, 0.72, 0.2, 0.25)]  # z, width, y at the side edges, y at the ridge


def prow(z, w, ys, yf, yb=-0.09, c=0.04):
    """One section of the chest: flat back with chamfered corners, two flat faces meeting at a ridge in front."""
    return [(w / 2 - c, yb, z), (w / 2, yb + c, z), (w / 2, ys, z), (0, yf, z), (-w / 2, ys, z), (-w / 2, yb + c, z), (-w / 2 + c, yb, z)]


def front_y(x, z):
    """The chest's front face at (x, z): between the sections, on the facet."""
    for (z0, w0, s0, f0), (z1, w1, s1, f1) in zip(SECS[:-1], SECS[1:]):
        if z0 <= z <= z1:
            t = (z - z0) / max(1e-6, z1 - z0)
            w, ys, yf = w0 + (w1 - w0) * t, s0 + (s1 - s0) * t, f0 + (f1 - f0) * t
            return yf - (yf - ys) * min(1.0, abs(x) / (w / 2))
    return 0.0


# the chest: the cab front as TMB's prow, two flat faces on a centre ridge growing forward to the windshield,
# which leans back; the roof above it is an overhanging visor
up.append(T.loft([prow(*sec) for sec in SECS], mat=paint, angle=18.0))
up.append(T.box((0.56, 0.36, 0.46), loc=(0, -0.24, 0.99), mat=paint, bevel=0.05))              # the back of it
up.append(T.tube([(0, front_y(0, z) + 0.004, z) for z in (0.77, 0.86, 0.96, 1.05)], 0.012, mat=bare, n=6))  # ridge seam
FACET = math.degrees(math.atan2(0.065, 0.366))
for sx in (1, -1):                                                                              # split windshield
    up.append(T.box((0.3, 0.012, 0.125), loc=(sx * 0.17, front_y(0.17, 1.135) + 0.006, 1.135), rot=(23.6, 0, -sx * FACET), mat=dark))
    for k in range(3):                                                                          # welded bars over it
        x = sx * (0.08 + k * 0.09)
        up.append(T.box((0.016, 0.02, 0.14), loc=(x, front_y(x, 1.135) + 0.014, 1.135), rot=(23.6, 0, -sx * FACET), mat=armor))
    up.append(T.box((0.37, 0.035, 0.035), loc=(sx * 0.18, front_y(0.18, 1.06) + 0.01, 1.06), rot=(0, 0, -sx * FACET), mat=armor, bevel=0.006))  # sill
up.append(T.box((0.05, 0.03, 0.17), loc=(0, front_y(0, 1.135) + 0.006, 1.135), rot=(23.6, 0, 0), mat=armor, bevel=0.006))   # pillar
up.append(T.box((0.82, 0.48, 0.05), loc=(0, 0.05, 1.245), rot=(-4, 0, 0), mat=paint, bevel=0.012))    # the roof: a visor
rivets(V((-0.36, 0.29, 1.27)), V((0.36, 0.29, 1.27)), 7, up, 0.013)
up.append(T.box((0.41, 0.22, 0.16), loc=(0, -0.2, 1.29), mat=paint, bevel=0.03))                      # upper back
up.append(T.cyl(0.11, 0.1, loc=(0, -0.08, 1.33), mat=dark, n=12))                                     # neck
dots(V((0, 0.33, 0.9)), (0, 1, 0), (0.6, 0.3), 12)
dots(V((0, -0.43, 1.0)), (0, -1, 0), (0.5, 0.42), 13)
# TMB's black beam behind the head on two struts, work lamps on its ends
up.append(T.box((0.8, 0.14, 0.12), loc=(0, -0.53, 1.36), mat=dark, bevel=0.02))
rivets(V((-0.36, -0.455, 1.4)), V((0.36, -0.455, 1.4)), 6, up, 0.014)
for sx in (1, -1):
    up.append(limb(V((sx * 0.105, -0.1, 1.08)), V((sx * 0.105, -0.56, 1.38)), 0.047, 0.117, armor, 0.008))
    decals.append(T.Decal(T.hazard_image(stripes=4), (sx * 0.3, -0.6, 1.36), (0, -1, 0), (0, 0, 1), (0.18, 0.1), depth=0.04, kinds=("steel",), opacity=0.8))
    lamp = V((sx * 0.36, -0.6, 1.45))
    up.append(T.cyl(0.045, 0.08, loc=tuple(lamp), rot=(90, 0, 0), mat=dark, n=12))
    up.append(T.cyl(0.035, 0.015, loc=tuple(lamp + V((0, -0.042, 0))), rot=(90, 0, 0), mat=T.glow((0.75, 0.55, 0.3)), n=12))
    up.append(T.box((0.03, 0.04, 0.06), loc=tuple(lamp + V((0, 0, -0.06))), mat=dark))
tube_marks = {}
for sx in (1, -1):
    side = "r" if sx > 0 else "l"
    up.append(T.box((0.18, 0.31, 0.4), loc=(sx * 0.31, -0.13, 1.19), mat=paint, bevel=0.06))       # shoulder block
    up.append(T.box((0.26, 0.24, 0.26), loc=(sx * 0.53, -0.2, 1.19), mat=armor, bevel=0.05))       # shoulder joint
    up.append(T.sphere(0.1, loc=(sx * 0.6, -0.17, 1.17), mat=bare, n=12))
    # the missile pod: TMB's shoulder piece, tipped up and out 25 deg, ten tubes in its front face
    tilt = math.radians(25.5)
    a = V((sx * math.cos(tilt), 0, math.sin(tilt)))
    b = V((-sx * math.sin(tilt), 0, math.cos(tilt)))
    pc = V((sx * 0.47, -0.22, 1.22))
    rot = (0, -sx * 25.5, 0)
    up.append(T.box((0.6, 0.34, 0.3), loc=tuple(pc), rot=rot, mat=paint, bevel=0.03))
    up.append(T.box((0.62, 0.36, 0.03), loc=tuple(pc + b * 0.16), rot=rot, mat=armor, bevel=0.008))        # top plate
    up.append(T.box((0.04, 0.37, 0.32), loc=tuple(pc + a * 0.31), rot=rot, mat=armor, bevel=0.008))        # outer cap
    face = pc + V((0, 0.17, 0))
    for e in (1, -1):                                                                                     # frame on the face
        up.append(T.box((0.58, 0.03, 0.03), loc=tuple(face + b * e * 0.125), rot=rot, mat=armor, bevel=0.005))
        up.append(T.box((0.03, 0.03, 0.26), loc=tuple(face + a * e * 0.27), rot=rot, mat=armor, bevel=0.005))
    for row in range(2):
        for col in range(5):
            p = face + a * (col - 2) * 0.1 + b * (row - 0.5) * 0.11
            up.append(T.cyl(0.043, 0.06, loc=tuple(p), rot=(-90, 0, 0), mat=dark, n=8))
            up.append(T.cyl(0.03, 0.05, loc=tuple(p + V((0, 0.012, 0))), rot=(-90, 0, 0), mat=warhead, n=8, r2=0.006))
            tube_marks["m_tube_%s%d" % (side, row * 5 + col)] = p + V((0, 0.05, 0))
    decals.append(T.Decal(T.dots_image((0.02, 0.02, 0.02), n=10, seed=40 + sx, size=(256, 256), r=(22, 34)), tuple(face), (0, 1, 0), (0, 0, 1),
        (0.62, 0.34), depth=0.06, kinds=("paint", "steel"), opacity=0.55))  # soot round the mouths
    dots(pc - V((0, 0.17, 0)), (0, -1, 0), (0.5, 0.3), 20 + sx)
    hose([V((sx * 0.22, -0.3, 1.05)), V((sx * 0.3, -0.42, 1.12)), pc + V((0, -0.17, -0.05))], up)
    piston(V((sx * 0.3, -0.25, 0.98)), pc + V((-sx * 0.05, -0.12, -0.12)), up, 0.03)
# right arm: the fist raised beside the head (TMB). Upper arm down, forearm forward and up.
sh, el, wr = V((0.6, -0.17, 1.16)), V((0.65, -0.12, 0.9)), V((0.56, 0.2, 1.15))
up.append(limb(sh, el, 0.22, 0.24, armor))
elbow(el, up, 0.11)
up.append(limb(el, wr, 0.24, 0.22, armor))
up.append(T.box((0.27, 0.06, 0.2), loc=tuple(el.lerp(wr, 0.55) + V((0.0, 0.0, -0.1))), rot=(-30, 0, 0), mat=bare, bevel=0.01))  # guard
up.append(T.box((0.2, 0.2, 0.25), loc=(0.53, 0.27, 1.28), mat=armor, bevel=0.03))                  # the fist
for k in range(4):                                                                                    # its knuckles
    up.append(T.box((0.045, 0.06, 0.05), loc=(0.46 + k * 0.047, 0.38, 1.31), mat=bare, bevel=0.01))
    up.append(T.box((0.04, 0.05, 0.13), loc=(0.46 + k * 0.047, 0.355, 1.23), mat=armor, bevel=0.008))
up.append(T.box((0.07, 0.15, 0.07), loc=(0.42, 0.27, 1.35), rot=(-20, 0, 0), mat=armor, bevel=0.01))   # thumb
piston(V((0.42, -0.2, 1.0)), V((0.62, 0.05, 0.98)), up, 0.03)
# left arm: forearm straight forward, the hand gripping a long hex cannon pointed 12 deg up (TMB)
sh, el, wr = V((-0.6, -0.17, 1.16)), V((-0.54, -0.13, 0.95)), V((-0.56, 0.28, 0.99))
up.append(limb(sh, el, 0.2, 0.24, armor))
elbow(el, up, 0.1)
up.append(limb(el, wr, 0.18, 0.19, armor))
up.append(T.box((0.17, 0.2, 0.15), loc=(-0.66, 0.16, 0.99), mat=armor, bevel=0.025))                  # the hand
cdir = V((0, 0.98, 0.21)).normalized()
cb = V((-0.51, 0.2, 1.0))
up.append(T.cyl(0.05, 0.42, loc=tuple(cb + cdir * 0.21), rot=aim(cdir), mat=dark, n=6, bevel=0.006))     # hex barrel
up.append(T.cyl(0.058, 0.08, loc=tuple(cb + cdir * 0.4), rot=aim(cdir), mat=bare, n=6))                   # muzzle collar
up.append(T.cyl(0.03, 0.02, loc=tuple(cb + cdir * 0.44), rot=aim(cdir), mat=soot, n=8))
up.append(T.box((0.12, 0.16, 0.12), loc=tuple(cb + cdir * 0.02), mat=armor, bevel=0.015))               # breech
up.append(T.box((0.03, 0.07, 0.05), loc=tuple(cb + cdir * 0.12 + V((0, 0, 0.07))), mat=bare))           # sight
for k in range(3):
    up.append(T.cyl(0.056, 0.02, loc=tuple(cb + cdir * (0.12 + k * 0.09)), rot=aim(cdir), mat=bare, n=6))  # barrel bands
piston(V((-0.42, -0.2, 1.0)), V((-0.6, 0.05, 0.96)), up, 0.03)
for name, pos in tube_marks.items():
    markers.append(T.marker(name, tuple(pos)))
# Sweet Tooth's own head, the TM 2012 fireball (owner), at TMB's head size and place. Its paint is laid at the
# bake, after the robot was scaled: unbake maps those points back to where the head was built.
HEAD_C, HEAD_S = V((0, -0.1, 1.5)), 0.55
clown_head.build(HEAD_C, HEAD_S, up, decals, regions, unbake=lambda P: P / S)
markers.append(T.marker("m_head", tuple(HEAD_C + V((0, 0, 0.3)))))
decals.append(T.Decal(T.holes_image(n=9, seed=7, size=(512, 256), r=(5, 9)), (0.37, 0.0, 0.95), (1, 0, 0), (0, 0, 1), (0.4, 0.2), depth=0.08, kinds=("paint",)))
decals.append(T.Decal(T.holes_image(n=6, seed=8, size=(512, 256), r=(5, 9)), (-0.15, 0.3, 0.92), (0, 1, 0), (0, 0, 1), (0.35, 0.18), depth=0.08, kinds=("paint", "steel")))
markers.append(T.marker("m_waist", tuple(WAIST)))

legs_ob = T.join(legs, "legs")
upper_ob = T.join(upper, "upper")
objs = [legs_ob, upper_ob]
for m in markers:
    m.location = m.location * S
for d in decals:
    d.center = d.center * S
    d.size = (d.size[0] * S, d.size[1] * S)
    d.depth *= S
scale = Matrix.Scale(S, 4)
for ob in objs:
    ob.data.transform(scale)

if "--shape" in sys.argv:
    out = sys.argv[sys.argv.index("--shape") + 1]
    T.preview(out, size=(800, 800), eye=(2.0, 3.0, 1.5), look=(0, 0, 0.85), fov=40, samples=12)
    T.preview(out.replace(".png", "_back.png"), size=(800, 800), eye=(-2.0, -3.0, 1.7), look=(0, 0, 0.9), fov=40, samples=12)
    sys.exit(0)
T.unwrap(objs, margin=0.003)
if "--nobake" not in sys.argv:
    g = T.gbuffer(objs, size=2048, ao_dist=0.3, bevel_r=0.008, ao_samples=20)
    al, nm, orm = T.weather(g, decals, seed=61, dust_from=0.0, dust_to=0.8, regions=regions)
    T.save_maps("sweet_bot", al, nm, orm)
upper_ob.data.transform(Matrix.Translation(-WAIST * S))  # the upper body turns about the waist
T.export_glb("sweet_bot", objs, markers=markers)
print("ok", T.tri_count(objs))

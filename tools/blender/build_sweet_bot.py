"""Sweet Bot (round 19): the owner's pick of four (look A, from the TMB clip
docs/reference/videos/special_sweet_bot_missiles.mp4) with a design pass. Sweet Tooth's truck box stood up on a
short spiked chassis with four knobbly wheels; the torso is the van's body with the serving shutter on its
chest, TMB's black beam across the shoulders, the shoulders are angled side panels with armoured wings and a
pod of ten loaded missile tubes in each, dark clawed arms on hydraulic rams, two blackened stacks, and the
clown head sunk in a full sunflower of bronze spikes. Serious, never cartoonish: worn cream paint, rust spots,
soot round the tubes, bullet holes. Scaled to fit in the truck's box (it slides out of the back door).
    /tmp/bpy3.13/bin/python tools/blender/build_sweet_bot.py              # build, bake, export
    /tmp/bpy3.13/bin/python tools/blender/build_sweet_bot.py --shape a.png  # quick look, no bake
Blender space: +Y forward, +Z up. Writes assets/models/sweet_bot.glb: legs (chassis, wheels, the lower box),
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
bronze = T.M("steel", (0.2, 0.1, 0.035), wear=0.5, rust=0.75, dirt=0.5)
face = T.M("paint", (0.6, 0.58, 0.53), wear=0.75, rust=0.45, dirt=0.7)
red = T.M("paint", (0.3, 0.02, 0.02), wear=0.7, rust=0.4, dirt=0.6)
bone = T.M("plastic", (0.55, 0.52, 0.44), wear=0.8, dirt=0.8)
soot = T.M("burnt", (0.05, 0.04, 0.03), rust=0.5)
ember = T.glow((1.0, 0.42, 0.06))
warhead = T.M("paint", (0.32, 0.045, 0.03), wear=0.65, rust=0.45, dirt=0.5)
chrome = T.M("steel", (0.3, 0.3, 0.28), wear=0.25, rust=0.25, dirt=0.45)
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


def dots(c, n, size, seed, opacity=0.85):
    decals.append(T.Decal(T.dots_image((0.16, 0.07, 0.03), n=12, seed=seed, size=(256, 256), r=(16, 26)), tuple(c), tuple(n), (0, 0, 1) if abs(n[2]) < 0.9 else (0, 1, 0), size, depth=0.12, kinds=("paint",), opacity=opacity))



S = 0.82  # the whole robot: about 1.75 m tall, it rides out of the truck's box easily
WAIST = V((0, 0, 1.46))
legs, upper = [], []


def ribs_y(c, w, h, n, y, parts, mat):
    for k in range(n):
        parts.append(T.box((w, 0.05, 0.05), loc=tuple(c + V((0, y, -h / 2 + h * (k + 0.5) / n))), mat=mat, bevel=0.012))


# ---------------------------------------------------------------- legs: the truck's chassis (owner: no box, the top half rides on it)
o = V((0, 0, 0))
legs.append(T.box((1.1, 1.1, 0.18), loc=(0, 0, 0.42), mat=dark, bevel=0.02))
for sx in (1, -1):
    for sy in (1, -1):
        wheel((sx * 0.64, sy * 0.42, 0.34), 0.34, 0.24, legs)
    legs.append(T.box((0.24, 0.025, 0.26), loc=(sx * 0.64, -0.8, 0.3), mat=rubber))  # mud flaps
    legs.append(T.box((0.3, 0.9, 0.06), loc=(sx * 0.64, 0, 0.72), mat=armor, bevel=0.012))  # fenders over the wheels
# a short welded plow, Sweet Tooth's, with spikes
legs.append(T.prism([(-0.68, 0.0), (0.0, 0.22), (0.68, 0.0), (0.68, -0.08), (0.0, 0.14), (-0.68, -0.08)], 0.3,
    loc=(0, 0.66, 0.36), mat=armor, plane="XY"))
for k in range(5):
    x = (k - 2) * 0.27
    legs.append(spike((x, 0.68 + (0.22 - abs(x) * 0.32), 0.36), (0, 1, -0.1), 0.2, 0.04, bare, 6))
legs.append(T.box((1.16, 0.12, 0.12), loc=(0, -0.66, 0.42), mat=bare, bevel=0.02))  # rear bumper
for sx in (1, -1):
    legs.append(T.box((0.16, 0.04, 0.09), loc=(sx * 0.42, -0.73, 0.52), mat=T.glow((0.9, 0.06, 0.03))))  # tail lights
    legs.append(T.box((0.2, 0.05, 0.13), loc=(sx * 0.42, -0.71, 0.52), mat=dark, bevel=0.01))
legs.append(T.cyl(0.33, 0.1, loc=(0, 0, 0.56), mat=dark, n=16))  # the turret ring's base, bolted to the chassis
for k in range(6):
    a = math.radians(k * 60)
    legs.append(T.cyl(0.022, 0.03, loc=(math.cos(a) * 0.29, math.sin(a) * 0.29, 0.62), mat=bare, n=6))

# ---------------------------------------------------------------- upper: turns at the waist
up = upper
up.append(T.cyl(0.3, 0.1, loc=(0, 0, 1.5), mat=dark, n=20))  # turret ring
up.append(T.cyl(0.24, 0.12, loc=(0, 0, 1.58), mat=bare, n=16))
up.append(T.box((1.25, 0.8, 0.64), loc=(0, 0, 1.84), mat=paint, bevel=0.08, taper=(1.1, 1.02)))  # the van's body: the chest
# the serving shutter on the chest: a steel frame, roll-up slats, a drip ledge
trim(V((0, 0.41, 1.82)), 0.92, 0.42, (0, 1, 0), up)
for k in range(7):
    up.append(T.box((0.88, 0.03, 0.045), loc=(0, 0.415, 1.635 + k * 0.058), mat=bare, bevel=0.006))
up.append(T.box((1.0, 0.12, 0.04), loc=(0, 0.47, 2.05), mat=armor, bevel=0.01))
for sx in (1, -1):  # side vents
    for k in range(4):
        up.append(T.box((0.03, 0.4, 0.035), loc=(sx * 0.66, 0.0, 1.72 + k * 0.07), rot=(0, sx * 6, 0), mat=dark))
# TMB's black beam across the shoulders, behind the head, with two work lamps
up.append(T.box((2.05, 0.28, 0.2), loc=(0, -0.06, 2.2), mat=dark, bevel=0.03))
rivets((-0.92, 0.09, 2.31), (0.92, 0.09, 2.31), 6, up, 0.02)
for sx in (1, -1):
    hz = V((sx * 0.85, 0.085, 2.2))
    decals.append(T.Decal(T.hazard_image(stripes=4), tuple(hz), (0, 1, 0), (0, 0, 1), (0.3, 0.18), depth=0.05, kinds=("steel",), opacity=0.8))
    lamp = V((sx * 0.86, 0.12, 2.36))
    up.append(T.cyl(0.07, 0.12, loc=tuple(lamp), rot=(-90, 0, 0), mat=dark, n=12))
    up.append(T.cyl(0.055, 0.02, loc=tuple(lamp + V((0, 0.065, 0))), rot=(-90, 0, 0), mat=T.glow((0.75, 0.55, 0.3)), n=12))
    up.append(T.box((0.04, 0.06, 0.1), loc=tuple(lamp + V((0, 0, -0.1))), mat=dark))
up.append(T.cyl(0.16, 0.12, loc=(0, 0.04, 2.3), mat=dark, n=14))  # neck collar on the beam
tube_marks = {}
for sx in (1, -1):
    sh = V((sx * 0.98, 0.0, 1.99))
    up.append(T.sphere(0.17, loc=tuple(sh + V((-sx * 0.3, 0, -0.08))), mat=bare, n=12))  # shoulder joint
    up.append(T.box((0.52, 0.74, 0.58), loc=tuple(sh), rot=(0, sx * 18, 0), mat=paint, bevel=0.05))  # the side panel
    # armoured wing on the outside, tipped out like TMB's, and a plate over the top
    up.append(T.box((0.07, 0.86, 0.74), loc=tuple(sh + V((sx * 0.31, -0.02, 0.06))), rot=(0, sx * 32, 0), mat=armor, bevel=0.015))
    up.append(T.box((0.62, 0.84, 0.06), loc=tuple(sh + V((sx * 0.04, -0.02, 0.33))), rot=(0, sx * 18, 0), mat=armor, bevel=0.012))
    pod = sh + V((0, 0.38, 0.0))
    tubes(pod, 2, 5, 0.095, (0, 1, 0), up, "a")
    for row in range(5):
        for col in range(2):
            tube_marks["m_tube_%s%d" % ("r" if sx > 0 else "l", row * 2 + col)] = pod + V(((col - 0.5) * 0.095, 0.1, (row - 2) * 0.095))
    decals.append(T.Decal(T.dots_image((0.02, 0.02, 0.02), n=10, seed=40 + sx, size=(256, 256), r=(22, 34)), tuple(pod + V((0, 0.02, 0))), (0, 1, 0), (0, 0, 1),
        (0.42, 0.66), depth=0.08, kinds=("paint", "steel"), opacity=0.55))  # soot round the mouths
    up.append(limb(sh + V((sx * 0.2, -0.12, 0.3)), sh + V((sx * 0.62, -0.28, 0.95)), 0.05, 0.08, bare, 0.01))  # blade
    up.append(limb(sh + V((sx * 0.05, 0.0, -0.25)), sh + V((sx * 0.1, 0.04, -0.52)), 0.26, 0.3, armor))  # upper arm
    elbow(sh + V((sx * 0.1, 0.04, -0.56)), up, 0.12)
    up.append(limb(sh + V((sx * 0.1, 0.06, -0.6)), sh + V((sx * 0.13, 0.12, -0.72)), 0.3, 0.34, armor))  # forearm
    up.append(T.box((0.34, 0.06, 0.2), loc=tuple(sh + V((sx * 0.12, 0.27, -0.65))), rot=(-15, 0, 0), mat=bare, bevel=0.012))  # guard
    fist(sh + V((sx * 0.13, 0.1, -0.87)), sx, up, 1.05)
    piston(V((sx * 0.5, -0.12, 1.64)), sh + V((-sx * 0.12, -0.15, -0.24)), up)  # shoulder ram
    hose([V((sx * 0.45, -0.38, 1.95)), V((sx * 0.62, -0.52, 2.1)), sh + V((0, -0.4, 0.05))], up)
    dots(sh + V((sx * 0.27, 0, 0.05)), (sx, 0, 0), (0.6, 0.5), 5 + sx)
for name, pos in tube_marks.items():
    markers.append(T.marker(name, tuple(pos)))
# Sweet Tooth's own head, the TM 2012 fireball (owner). Its paint is laid at the bake, after the upper body has
# come down DZ and the robot was scaled: unbake maps those points back to where the head was built.
clown_head.build(V((0, 0.14, 2.55)), 0.68, up, decals, regions, unbake=lambda P: P / S + np.array((0, 0, DZ), dtype=np.float32))
markers.append(T.marker("m_head", (0, 0.1, 2.95)))
stacks(V((0, -0.42, 1.64)), 0.72, up, gap=0.95)  # out to the sides: the head's flames stream back between them
decals.append(T.Decal(T.holes_image(n=9, seed=7, size=(512, 256), r=(5, 9)), (0.66, 0.15, 1.95), (1, 0, 0), (0, 0, 1), (0.6, 0.3), depth=0.1, kinds=("paint",)))
decals.append(T.Decal(T.holes_image(n=6, seed=8, size=(512, 256), r=(5, 9)), (-0.2, 0.42, 1.95), (0, 1, 0), (0, 0, 1), (0.5, 0.25), depth=0.1, kinds=("paint", "steel")))
dots(V((0, -0.41, 1.85)), (0, -1, 0), (1.1, 0.55), 12)
markers.append(T.marker("m_waist", tuple(WAIST)))  # (moved down with the rest below)

legs_ob = T.join(legs, "legs")
upper_ob = T.join(upper, "upper")
objs = [legs_ob, upper_ob]
# owner (round 19): no box between: the upper body sits straight on the chassis (DZ lower). Everything
# drawn for the upper body (its decals, the markers) comes down with it, then the whole robot is scaled.
DZ = 0.88
upper_ob.data.transform(Matrix.Translation((0, 0, -DZ)))
WAIST = WAIST - V((0, 0, DZ))
for m in markers:
    m.location = (m.location - V((0, 0, DZ))) * S
for d in decals:
    d.center = (d.center - np.array((0, 0, DZ), dtype=np.float32)) * S
    d.size = (d.size[0] * S, d.size[1] * S)
    d.depth *= S
scale = Matrix.Scale(S, 4)
for ob in objs:
    ob.data.transform(scale)

if "--shape" in sys.argv:
    out = sys.argv[sys.argv.index("--shape") + 1]
    T.preview(out, size=(800, 800), eye=(2.2, 3.2, 1.6), look=(0, 0, 0.85), fov=40, samples=12)
    T.preview(out.replace(".png", "_back.png"), size=(800, 800), eye=(-2.0, -3.2, 1.8), look=(0, 0, 0.9), fov=40, samples=12)
    sys.exit(0)
T.unwrap(objs, margin=0.003)
if "--nobake" not in sys.argv:
    g = T.gbuffer(objs, size=2048, ao_dist=0.35, bevel_r=0.01, ao_samples=20)
    al, nm, orm = T.weather(g, decals, seed=61, dust_from=0.0, dust_to=0.9, regions=regions)
    T.save_maps("sweet_bot", al, nm, orm)
upper_ob.data.transform(Matrix.Translation(-WAIST * S))  # the upper body turns about the waist
T.export_glb("sweet_bot", objs, markers=markers)
print("ok", T.tri_count(objs))

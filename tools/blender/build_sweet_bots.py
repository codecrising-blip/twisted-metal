"""Sweet Bot, four looks for the owner to pick from (round 19). From the owner's TMB clip
(docs/reference/videos/special_sweet_bot_missiles.mp4): the truck stands up into a robot. Its rear box
(cream paint, brown spots, ribbed) is the body on the truck's chassis and wheels, a black beam runs across
the shoulders, the shoulders are the truck's side panels with blades sticking out, dark arms with claws,
and on top Sweet Tooth's clown head: white, with a ruff of bronze spikes and a tall cone on the crown.
The owner: smaller than TMB's (it is dropped out of the truck's back door), the clown head on every one,
twenty missiles from the shoulders. Serious, never cartoonish: cracked fibreglass, rust, soot, dark
sunken eyes with embers in them, a grin of steel teeth.
    /tmp/bpy3.13/bin/python tools/blender/build_sweet_bots.py              # build, bake, export
    /tmp/bpy3.13/bin/python tools/blender/build_sweet_bots.py --shape a.png  # quick looks, no bake
  A  TMB: the truck box stands on its chassis and four wheels, panel shoulders with blades, claw arms
  B  WALKER: on two legs of truck panels with hub-cap knees, the arms are the missile pods
  C  WHEELIE: on two big wheels behind the truck's spiked plow, a rocket box on its back
  D  BRUTE: hunched, huge panel shoulders with the tubes on top, long arms down to knuckle wheels
Writes assets/models/sweet_bots.glb: nodes bot_a..bot_d (each stands on its own origin) and m_head_a..d."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
import numpy as np
from mathutils import Vector

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
    parts.append(T.cyl(r * 0.9, w, loc=tuple(c), rot=(0, 90, 0), mat=rubber, n=22, bevel=0.03))
    n = 16
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
            parts.append(T.cyl(pitch * 0.42, 0.1, loc=tuple(p), rot=aim(f), mat=dark, n=12))
            parts.append(T.cyl(pitch * 0.3, 0.09, loc=tuple(p + f * 0.06), rot=aim(f), mat=warhead, n=10, r2=pitch * 0.05))
            k += 1
    fw, fh = cols * pitch + 0.05, rows * pitch + 0.05
    for e in (1, -1):  # a steel frame round the pod's face
        parts.append(T.box((fw + 0.05, 0.05, 0.05), loc=tuple(Vector(c) + up * e * fh / 2 - f * 0.01), mat=armor, bevel=0.008))
        parts.append(rod(Vector(c) + side * e * fw / 2 + up * fh / 2 - f * 0.01, Vector(c) + side * e * fw / 2 - up * fh / 2 - f * 0.01, 0.025, armor, 6))
    return k


def clown_head(c, s, parts, tag):
    """Sweet Tooth's head, facing +Y: a white fibreglass egg gone grey and cracked, dark sunken eyes with
    embers deep inside, slanted brows, a faded red nose, a grin of steel teeth, and the ruff of bronze
    spikes fanned out behind it with a tall cone on the crown."""
    c = Vector(c)
    parts.append(T.sphere(0.27 * s, loc=tuple(c), mat=face, n=22, scale=(0.95, 0.9, 1.1)))
    parts.append(T.sphere(0.21 * s, loc=tuple(c + V((0, 0.06, -0.13)) * s), mat=face, n=18, scale=(1.1, 0.95, 0.8)))
    for sx in (1, -1):
        # deep narrow sockets, a dim ember far inside, brows cut down hard toward the nose: it glares
        parts.append(T.sphere(0.068 * s, loc=tuple(c + V((sx * 0.1, 0.205, 0.045)) * s), mat=dark, n=12, scale=(1.35, 0.62, 0.62)))
        parts.append(T.sphere(0.013 * s, loc=tuple(c + V((sx * 0.1, 0.228, 0.042)) * s), mat=ember, n=8))
        parts.append(T.box((0.14 * s, 0.05 * s, 0.032 * s), loc=tuple(c + V((sx * 0.1, 0.222, 0.098)) * s), rot=(0, -sx * 26, 0), mat=dark))
        parts.append(T.box((0.07 * s, 0.03 * s, 0.025 * s), loc=tuple(c + V((sx * 0.17, 0.215, -0.11)) * s), rot=(0, -sx * 35, 0), mat=red))
    parts.append(T.sphere(0.055 * s, loc=tuple(c + V((0, 0.27, -0.01)) * s), mat=red, n=12))
    parts.append(T.box((0.27 * s, 0.07 * s, 0.075 * s), loc=tuple(c + V((0, 0.2, -0.15)) * s), mat=dark, bevel=0.01 * s))
    for lz in (0.045, -0.045):
        parts.append(T.box((0.29 * s, 0.035 * s, 0.022 * s), loc=tuple(c + V((0, 0.225, -0.15 + lz)) * s), mat=red, bevel=0.005))
    for k in range(7):
        x = (k - 3) * 0.034
        parts.append(T.box((0.026 * s, 0.03 * s, 0.05 * s), loc=tuple(c + V((x, 0.235, -0.15)) * s), mat=bone))
    parts.append(T.cyl(0.1 * s, 0.22 * s, loc=tuple(c + V((0, -0.02, -0.33)) * s), mat=dark, n=12))  # neck
    # the ruff: spikes fanned out behind the head in a disc, missing at the bottom
    n = 15
    for k in range(n):
        a = math.radians(-60 + 300 * k / (n - 1)) if False else math.radians(-55 + 290 * k / (n - 1))
        d = V((math.cos(a), -0.32, math.sin(a)))
        base = c + V((math.cos(a) * 0.16, -0.12, math.sin(a) * 0.16)) * s
        parts.append(spike(base, d, (0.36 + 0.06 * math.sin(k * 2.1)) * s, 0.055 * s))
    parts.append(spike(c + V((0, -0.04, 0.24)) * s, (0, -0.15, 1), 0.48 * s, 0.075 * s))  # the crown cone
    markers.append(T.marker("m_head_" + tag, tuple(c + V((0, -0.05, 0.3)) * s)))


def dots(c, n, size, seed, opacity=0.85):
    decals.append(T.Decal(T.dots_image((0.16, 0.07, 0.03), n=12, seed=seed, size=(256, 256), r=(16, 26)), tuple(c), tuple(n), (0, 0, 1) if abs(n[2]) < 0.9 else (0, 1, 0), size, depth=0.12, kinds=("paint",), opacity=opacity))


# ---------------------------------------------------------------- A: TMB (the truck box on its chassis)
def bot_a(o):
    p = []
    o = Vector(o)
    p.append(T.box((1.1, 1.05, 0.18), loc=tuple(o + V((0, 0, 0.42))), mat=dark, bevel=0.02))
    for sx in (1, -1):
        for sy in (1, -1):
            wheel(tuple(o + V((sx * 0.64, sy * 0.4, 0.34))), 0.34, 0.24, p)
    p.append(T.box((0.98, 0.66, 0.86), loc=tuple(o + V((0, 0, 0.94))), mat=paint, bevel=0.04))  # the box stood up
    for k in range(5):
        for sy in (1, -1):
            p.append(T.box((1.02, 0.05, 0.05), loc=tuple(o + V((0, sy * 0.34, 0.6 + k * 0.17))), mat=paint, bevel=0.012))
    p.append(T.cyl(0.3, 0.16, loc=tuple(o + V((0, 0, 1.44))), mat=dark, n=16))  # waist
    p.append(T.box((1.25, 0.78, 0.62), loc=tuple(o + V((0, 0, 1.82))), mat=paint, bevel=0.07, taper=(1.08, 1.0)))  # torso
    p.append(T.box((0.9, 0.06, 0.28), loc=tuple(o + V((0, 0.4, 1.74))), mat=armor, bevel=0.02))
    p.append(T.box((2.0, 0.26, 0.18), loc=tuple(o + V((0, -0.05, 2.17))), mat=dark, bevel=0.03))  # shoulder beam
    for sx in (1, -1):
        sh = o + V((sx * 0.98, 0.0, 1.98))
        p.append(T.box((0.52, 0.74, 0.58), loc=tuple(sh), rot=(0, sx * 18, 0), mat=paint, bevel=0.05))  # panel shoulder
        tubes(sh + V((0, 0.38, 0.0)), 2, 5, 0.095, (0, 1, 0), p, "a")
        p.append(limb(sh + V((sx * 0.2, -0.1, 0.25)), sh + V((sx * 0.62, -0.25, 0.9)), 0.05, 0.08, bare, 0.01))  # blade
        p.append(limb(sh + V((sx * 0.05, 0.0, -0.25)), sh + V((sx * 0.1, 0.04, -0.52)), 0.24, 0.28, armor))  # upper arm
        elbow(sh + V((sx * 0.1, 0.04, -0.56)), p)
        p.append(limb(sh + V((sx * 0.1, 0.06, -0.6)), sh + V((sx * 0.13, 0.12, -0.8)), 0.26, 0.3, armor))  # forearm
        p.append(T.box((0.3, 0.06, 0.2), loc=tuple(sh + V((sx * 0.12, 0.25, -0.68))), rot=(-15, 0, 0), mat=bare, bevel=0.012))  # guard
        fist(sh + V((sx * 0.13, 0.1, -0.95)), sx, p)
        piston(o + V((sx * 0.5, -0.12, 1.62)), sh + V((-sx * 0.12, -0.15, -0.24)), p)  # shoulder ram
        hose([o + V((sx * 0.45, -0.36, 1.95)), o + V((sx * 0.62, -0.5, 2.1)), sh + V((sx * 0.0, -0.4, 0.05))], p)
        rivets(sh + V((-sx * 0.2, 0.38, 0.3)), sh + V((sx * 0.2, 0.38, 0.3)), 4, p)
        dots(sh + V((sx * 0.27, 0, 0.05)), (sx, 0, 0), (0.6, 0.5), 5 + sx)
    clown_head(o + V((0, 0.06, 2.55)), 1.0, p, "a")
    trim(o + V((0, 0.4, 1.82)), 1.12, 0.5, (0, 1, 0), p)
    trim(o + V((0, 0.34, 0.94)), 0.86, 0.72, (0, 1, 0), p, studs=False)
    rivets(o + V((-0.9, 0.09, 2.27)), o + V((0.9, 0.09, 2.27)), 9, p, 0.02)
    stacks(o + V((0, -0.44, 1.6)), 1.0, p)
    for sx in (1, -1):
        piston(o + V((sx * 0.45, 0.2, 0.55)), o + V((sx * 0.5, 0.12, 1.4)), p, 0.04)
    stencil("ICE CREAM", o + V((0, 0.42, 1.0)), (0, 1, 0), (0.8, 0.22))
    dots(o + V((0, 0.4, 1.95)), (0, 1, 0), (1.1, 0.45), 11)
    dots(o + V((0, -0.4, 1.85)), (0, -1, 0), (1.1, 0.55), 12)
    dots(o + V((0, 0.34, 1.0)), (0, 1, 0), (0.9, 0.8), 13)
    return T.join(p, "bot_a")


# ---------------------------------------------------------------- B: WALKER (legs, pod arms)
def bot_b(o):
    p = []
    o = Vector(o)
    for sx in (1, -1):
        hip = o + V((sx * 0.3, 0, 1.15))
        knee = o + V((sx * 0.34, 0.14, 0.62))
        ankle = o + V((sx * 0.34, -0.02, 0.16))
        p.append(limb(hip, knee, 0.3, 0.34, paint, 0.04))   # thigh: a truck panel
        p.append(limb(knee, ankle, 0.22, 0.26, armor))       # shin
        p.append(T.cyl(0.17, 0.12, loc=tuple(knee + V((sx * 0.16, 0, 0))), rot=(0, 90, 0), mat=bare, n=18, bevel=0.02))  # hub cap knee
        p.append(T.box((0.34, 0.56, 0.16), loc=tuple(ankle + V((0, 0.1, -0.08))), mat=armor, bevel=0.03))  # boot
        for t in (-0.1, 0.0, 0.1):
            p.append(spike(ankle + V((t, 0.36, -0.1)), (0, 1, -0.2), 0.14, 0.035, bare, 6))
        piston(hip + V((0, -0.22, -0.05)), knee + V((0, -0.2, 0.08)), p, 0.04)  # hamstring ram
        piston(knee + V((0, -0.16, -0.05)), ankle + V((0, -0.18, 0.12)), p, 0.035)  # calf ram
        elbow(ankle, p, 0.09)
        dots(hip.lerp(knee, 0.5) + V((sx * 0.16, 0, 0)), (sx, 0, 0), (0.3, 0.45), 20 + sx)
    p.append(T.box((0.85, 0.5, 0.28), loc=tuple(o + V((0, 0, 1.2))), mat=armor, bevel=0.04))  # pelvis
    p.append(T.box((1.1, 0.74, 0.8), loc=tuple(o + V((0, 0, 1.75))), mat=paint, bevel=0.08, taper=(1.12, 1.0)))  # torso
    p.append(T.box((0.7, 0.06, 0.45), loc=tuple(o + V((0, 0.38, 1.72))), mat=bare, bevel=0.015))  # serving shutter
    for k in range(7):
        p.append(T.box((0.68, 0.02, 0.014), loc=tuple(o + V((0, 0.415, 1.53 + k * 0.06))), mat=dark))
    p.append(T.box((1.5, 0.24, 0.16), loc=tuple(o + V((0, -0.06, 2.16))), mat=dark, bevel=0.03))  # shoulder beam
    for sx in (1, -1):
        sh = o + V((sx * 0.82, 0.05, 1.85))
        p.append(T.cyl(0.14, 0.24, loc=tuple(sh + V((-sx * 0.12, 0, 0.12))), rot=(0, 90, 0), mat=bare, n=14))
        p.append(T.box((0.44, 0.8, 0.52), loc=tuple(sh), mat=paint, bevel=0.05))  # the pod is the arm
        p.append(T.box((0.46, 0.06, 0.54), loc=tuple(sh + V((0, 0.4, 0))), mat=armor, bevel=0.015))
        tubes(sh + V((0, 0.44, 0)), 2, 5, 0.09, (0, 1, 0), p, "b")
        dots(sh + V((sx * 0.22, 0, 0)), (sx, 0, 0), (0.75, 0.48), 30 + sx)
    clown_head(o + V((0, 0.06, 2.52)), 1.0, p, "b")
    trim(o + V((0, 0.38, 1.72)), 0.74, 0.5, (0, 1, 0), p)
    rivets(o + V((-0.7, 0.07, 2.25)), o + V((0.7, 0.07, 2.25)), 7, p, 0.02)
    stacks(o + V((0, -0.42, 1.55)), 1.05, p)
    for sx in (1, -1):
        hose([o + V((sx * 0.4, 0.3, 1.45)), o + V((sx * 0.62, 0.42, 1.5)), o + V((sx * 0.82, 0.3, 1.62))], p)
        rivets(o + V((sx * 1.05, -0.36, 2.08)), o + V((sx * 1.05, 0.36, 2.08)), 6, p)
    stencil("ICE CREAM", o + V((0, -0.38, 1.95)), (0, -1, 0), (0.8, 0.22))
    dots(o + V((0, -0.37, 1.8)), (0, -1, 0), (1.0, 0.7), 33)
    return T.join(p, "bot_b")


# ---------------------------------------------------------------- C: WHEELIE (two big wheels, plow, rocket box)
def bot_c(o):
    p = []
    o = Vector(o)
    for sx in (1, -1):
        wheel(tuple(o + V((sx * 0.62, 0, 0.5))), 0.5, 0.3, p)
    p.append(T.cyl(0.08, 1.3, loc=tuple(o + V((0, 0, 0.5))), rot=(0, 90, 0), mat=dark, n=10))  # axle
    p.append(T.box((0.9, 0.6, 0.7), loc=tuple(o + V((0, -0.05, 0.95))), mat=paint, bevel=0.05))  # hips box
    # the truck's V plow as a skirt, with spikes
    p.append(T.prism([(-0.75, 0.0), (0.0, 0.45), (0.75, 0.0), (0.75, -0.12), (0.0, 0.33), (-0.75, -0.12)], 0.55,
        loc=tuple(o + V((0, 0.42, 0.62))), mat=armor, plane="XY"))
    for k in range(5):
        x = (k - 2) * 0.3
        p.append(spike(o + V((x, 0.45 + (0.45 - abs(x) * 0.6) * 0.9, 0.62)), (0, 1, -0.15), 0.28, 0.05, bare, 6))
    p.append(T.box((1.2, 0.8, 0.75), loc=tuple(o + V((0, 0.05, 1.68))), rot=(10, 0, 0), mat=paint, bevel=0.07))  # torso, leaning in
    p.append(T.box((1.7, 0.26, 0.16), loc=tuple(o + V((0, -0.05, 2.07))), mat=dark, bevel=0.03))
    # the rocket box on its back, twenty tubes looking forward over the shoulders
    rb = o + V((0, -0.55, 2.2))
    p.append(T.box((1.3, 0.6, 0.62), loc=tuple(rb), rot=(-12, 0, 0), mat=paint, bevel=0.05))
    p.append(T.box((1.32, 0.06, 0.64), loc=tuple(rb + V((0, 0.31, 0.06))), rot=(-12, 0, 0), mat=armor, bevel=0.015))
    tubes(rb + V((0, 0.36, 0.07)), 5, 4, 0.12, (0, 1, 0.21), p, "c")
    for sx in (1, -1):  # short dark arms with fists
        sh = o + V((sx * 0.72, 0.1, 1.95))
        p.append(limb(sh, sh + V((sx * 0.1, 0.18, -0.36)), 0.22, 0.26, armor))
        elbow(sh + V((sx * 0.1, 0.18, -0.4)), p, 0.1)
        p.append(limb(sh + V((sx * 0.1, 0.2, -0.42)), sh + V((sx * 0.13, 0.36, -0.55)), 0.24, 0.28, armor))
        fist(sh + V((sx * 0.14, 0.4, -0.72)), sx, p, 0.95)
        piston(o + V((sx * 0.4, -0.2, 1.05)), o + V((sx * 0.5, -0.25, 1.45)), p, 0.045)  # torso rams
        hose([rb + V((sx * 0.55, -0.1, -0.3)), o + V((sx * 0.7, -0.35, 1.75)), o + V((sx * 0.62, -0.2, 1.5))], p)
        p.append(limb(sh + V((sx * 0.1, -0.2, 0.25)), sh + V((sx * 0.55, -0.4, 0.95)), 0.05, 0.08, bare, 0.01))  # blade
        dots(o + V((sx * 0.6, 0.05, 1.7)), (sx, 0, 0), (0.7, 0.6), 40 + sx)
    clown_head(o + V((0, 0.22, 2.5)), 1.0, p, "c")
    trim(o + V((0, 0.47, 1.72)), 1.0, 0.5, (0, 1, 0), p)
    rivets(o + V((-0.8, 0.1, 2.17)), o + V((0.8, 0.1, 2.17)), 8, p, 0.02)
    for sx in (1, -1):
        stacks(rb + V((sx * 0.5, -0.2, 0.25)), 0.55, p, gap=0.14)
    dots(rb + V((0, -0.31, 0)), (0, -1, 0), (1.1, 0.5), 44)
    return T.join(p, "bot_c")


# ---------------------------------------------------------------- D: BRUTE (hunched, knuckle wheels)
def bot_d(o):
    p = []
    o = Vector(o)
    for sx in (1, -1):  # short splayed legs
        hip = o + V((sx * 0.32, -0.15, 0.95))
        ft = o + V((sx * 0.5, -0.25, 0.12))
        p.append(limb(hip, ft, 0.26, 0.3, armor))
        p.append(T.box((0.36, 0.52, 0.16), loc=tuple(ft + V((0, 0.12, -0.04))), mat=armor, bevel=0.03))
    p.append(T.box((0.9, 0.6, 0.32), loc=tuple(o + V((0, -0.15, 1.0))), mat=armor, bevel=0.04))
    p.append(T.box((1.15, 0.85, 0.8), loc=tuple(o + V((0, 0.0, 1.55))), rot=(18, 0, 0), mat=paint, bevel=0.08))  # hunched torso
    for sx in (1, -1):
        hump = o + V((sx * 0.72, -0.1, 2.0))
        p.append(T.box((0.62, 0.9, 0.62), loc=tuple(hump), rot=(10, 0, sx * 6), mat=paint, bevel=0.07))  # huge panel shoulder
        tubes(hump + V((0, 0.15, 0.33)), 2, 5, 0.1, (0, 0.55, 1), p, "d")  # tubes on top, looking forward and up
        sh = hump + V((sx * 0.2, 0.2, -0.2))
        el = o + V((sx * 1.0, 0.45, 1.0))
        p.append(limb(sh, el, 0.3, 0.34, armor))   # long arms down
        p.append(limb(el, o + V((sx * 0.98, 0.62, 0.36)), 0.28, 0.3, armor))
        wheel(tuple(o + V((sx * 0.98, 0.66, 0.24))), 0.24, 0.22, p)  # knuckle wheels
        elbow(el, p, 0.15)
        piston(sh + V((sx * 0.1, 0.25, 0.0)), el + V((0, 0.2, 0.1)), p, 0.05)
        rivets(hump + V((-sx * 0.25, 0.46, 0.25)), hump + V((sx * 0.25, 0.46, 0.25)), 4, p)
        dots(hump + V((sx * 0.31, 0, 0)), (sx, 0, 0), (0.75, 0.5), 50 + sx)
    p.append(T.box((1.7, 0.24, 0.16), loc=tuple(o + V((0, -0.3, 2.2))), mat=dark, bevel=0.03))
    clown_head(o + V((0, 0.42, 2.02)), 1.05, p, "d")  # low between the shoulders
    stacks(o + V((0, -0.5, 1.9)), 0.75, p, gap=0.3)
    trim(o + V((0, -0.44, 1.5)), 0.95, 0.5, (0, -1, 0), p)
    for sx in (1, -1):
        hose([o + V((sx * 0.3, 0.35, 1.3)), o + V((sx * 0.55, 0.45, 1.55)), o + V((sx * 0.72, 0.3, 1.75))], p)
    dots(o + V((0, -0.42, 1.7)), (0, -1, 0.3), (1.0, 0.7), 55)
    return T.join(p, "bot_d")


SPACING = 4.0
objs = [bot_a(((-1.5) * SPACING, 0, 0)), bot_b(((-0.5) * SPACING, 0, 0)), bot_c((0.5 * SPACING, 0, 0)), bot_d((1.5 * SPACING, 0, 0))]

if "--shape" in sys.argv:
    out = sys.argv[sys.argv.index("--shape") + 1]
    for k, ob in enumerate(objs):
        x = (k - 1.5) * SPACING
        T.preview(out.replace(".png", "_%s.png" % "abcd"[k]), size=(700, 800), eye=(x + 2.6, 4.4, 2.6), look=(x, 0, 1.45), fov=40, samples=10)
        T.preview(out.replace(".png", "_%s_back.png" % "abcd"[k]), size=(700, 800), eye=(x - 2.4, -4.4, 2.8), look=(x, 0, 1.5), fov=40, samples=10)
    sys.exit(0)
T.unwrap(objs, margin=0.003)
if "--nobake" not in sys.argv:
    g = T.gbuffer(objs, size=2048, ao_dist=0.4, bevel_r=0.012, ao_samples=20)
    al, nm, orm = T.weather(g, decals, seed=61, dust_from=0.0, dust_to=1.0, regions=regions)
    T.save_maps("sweet_bots", al, nm, orm)
for k, ob in enumerate(objs):  # each stands on its own origin
    from mathutils import Matrix
    ob.data.transform(Matrix.Translation((-(k - 1.5) * SPACING, 0, 0)))
for m in markers:
    tag = m.name[-1]
    m.location.x -= ("abcd".index(tag) - 1.5) * SPACING
T.export_glb("sweet_bots", objs, markers=markers)
print("ok", T.tri_count(objs))

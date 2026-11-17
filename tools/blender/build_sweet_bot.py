"""Sweet Bot (round 18): Sweet Tooth's secondary weapon, a small walker the truck drops and leaves standing.
    /tmp/bpy3.13/bin/python tools/blender/build_sweet_bot.py              # build, bake, export
    /tmp/bpy3.13/bin/python tools/blender/build_sweet_bot.py --shape a.png  # quick look, no bake
Our own design (owner: smaller than TMB's, serious, never cartoonish, no face): built from the truck's
own scrap. Two reverse-jointed steel legs on hydraulic rams, an armoured torso in the van's dirty cream
paint with the crimson band and polka dots, a roll-up shutter on the chest like the serving hatch, two
olive missile pods on the shoulders with ten tubes each (twenty missiles), a squat armoured head with
an orange sensor slit, blackened stacks, and a little burnt soft serve cone on top that still burns.
About 2.1 m tall. Blender space: +Y forward, +Z up. Nodes: legs, upper (its origin is the waist, it
turns toward its target) and markers m_waist, m_pod_l / m_pod_r (muzzle centres), m_cone (the flame),
m_tube_l0..9 / m_tube_r0..9 (every tube mouth, for the launch flashes)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
import numpy as np
from mathutils import Matrix, Vector

T.reset()
CREAM = (0.43, 0.40, 0.33)
CRIMSON = (0.28, 0.03, 0.04)
paint = T.M("paint", CREAM, wear=0.72, rust=0.66, dirt=0.75)
armor = T.M("steel", (0.035, 0.035, 0.038), wear=0.7, rust=0.6, dirt=0.6)
bare = T.M("steel", (0.10, 0.10, 0.10), wear=0.7, rust=0.5, dirt=0.5)
dark = T.M("steel", (0.012, 0.012, 0.013), wear=0.3, rust=0.3, dirt=0.7)
soot = T.M("burnt", (0.05, 0.04, 0.03), rust=0.5)
olive = T.M("paint", (0.075, 0.09, 0.045), wear=0.7, rust=0.5, dirt=0.6)
chrome = T.M("chrome", (0.35, 0.35, 0.36), wear=0.5, rust=0.3, dirt=0.5)
wafer = T.M("plastic", (0.27, 0.17, 0.075), wear=0.8, dirt=0.7)
swirl = T.M("plastic", (0.40, 0.31, 0.28), wear=0.85, dirt=0.8)
slit = T.glow((1.0, 0.45, 0.1))

WAIST = Vector((0.0, 0.0, 1.12))
legs = []
upper = []
decals = []
regions = []
markers = []


def limb(a, b, w, d, mat, bevel=0.03):
    """A box from point a to point b (both in the YZ plane at the same x), w across, d thick."""
    a, b = Vector(a), Vector(b)
    v = b - a
    L = v.length
    theta = math.degrees(math.atan2(-v.y, v.z))
    return T.box((w, d, L), loc=tuple((a + b) / 2), rot=(theta, 0, 0), mat=mat, bevel=bevel)


def rod(a, b, r, mat, n=10):
    a, b = Vector(a), Vector(b)
    v = b - a
    theta = math.degrees(math.atan2(-v.y, v.z))
    return T.cyl(r, v.length, loc=tuple((a + b) / 2), rot=(theta, 0, 0), mat=mat, n=n)


# ---------------------------------------------------------------- legs (stay put)
legs.append(T.box((0.78, 0.52, 0.26), loc=(0, 0, 1.0), mat=armor, bevel=0.05))              # pelvis
legs.append(T.box((0.6, 0.36, 0.1), loc=(0, -0.05, 0.84), mat=dark, bevel=0.02))
for sx in (1, -1):
    x = sx * 0.36
    hip = (x, 0.0, 0.98)
    knee = (x, 0.26, 0.58)
    ankle = (x, -0.1, 0.2)
    legs.append(T.cyl(0.13, 0.16, loc=(sx * 0.44, 0.0, 0.98), rot=(0, 90, 0), mat=bare, n=14))     # hip joint
    legs.append(limb(hip, knee, 0.2, 0.24, paint))                                                     # thigh
    legs.append(limb((x + sx * 0.11, 0.0, 0.96), (x + sx * 0.11, 0.24, 0.6), 0.04, 0.2, armor, 0.01))  # thigh plate
    legs.append(T.cyl(0.11, 0.3, loc=knee, rot=(0, 90, 0), mat=bare, n=14))                           # knee
    legs.append(limb(knee, ankle, 0.16, 0.18, armor))                                                 # shin
    legs.append(T.cyl(0.09, 0.26, loc=ankle, rot=(0, 90, 0), mat=bare, n=12))                          # ankle
    # hydraulic rams: chrome rod in a dark sleeve, hip to shin and knee to foot
    legs.append(rod((x - sx * 0.12, -0.12, 0.92), (x - sx * 0.12, 0.05, 0.42), 0.035, dark))
    legs.append(rod((x - sx * 0.12, -0.02, 0.7), (x - sx * 0.12, 0.08, 0.3), 0.022, chrome))
    legs.append(rod((x + sx * 0.12, 0.24, 0.52), (x + sx * 0.12, 0.1, 0.16), 0.022, chrome))
    # foot: a heavy splayed plate with two toes forward and a spur back
    legs.append(T.box((0.26, 0.42, 0.1), loc=(x, 0.02, 0.07), mat=armor, bevel=0.03))
    for tx in (-0.07, 0.07):
        legs.append(T.box((0.09, 0.26, 0.08), loc=(x + tx, 0.32, 0.05), rot=(-8, 0, 0), mat=armor, bevel=0.02))
    legs.append(T.box((0.1, 0.2, 0.07), loc=(x, -0.27, 0.05), rot=(10, 0, 0), mat=armor, bevel=0.02))
legs_ob = T.join(legs, "legs")

# ---------------------------------------------------------------- upper body (turns at the waist)
upper.append(T.cyl(0.24, 0.14, loc=(0, 0, 1.17), mat=dark, n=18))                                # waist ring
upper.append(T.box((0.92, 0.68, 0.72), loc=(0, 0, 1.6), mat=paint, bevel=0.06, taper=(0.86, 0.9)))  # torso shell
upper.append(T.box((0.62, 0.06, 0.4), loc=(0, 0.35, 1.58), mat=bare, bevel=0.015))                   # chest shutter
for k in range(7):
    upper.append(T.box((0.6, 0.02, 0.012), loc=(0, 0.385, 1.42 + k * 0.053), mat=dark))
upper.append(T.box((0.84, 0.08, 0.16), loc=(0, 0.36, 1.92), mat=armor, bevel=0.02))                  # brow plate
upper.append(T.box((0.84, 0.08, 0.14), loc=(0, 0.35, 1.27), mat=armor, bevel=0.02))                  # belly plate
upper.append(T.box((0.94, 0.5, 0.06), loc=(0, -0.05, 1.98), mat=armor, bevel=0.02))                  # roof plate
upper.append(T.box((0.6, 0.12, 0.5), loc=(0, -0.38, 1.6), mat=armor, bevel=0.03))                    # back pack
for sx in (1, -1):  # blackened stacks out of the back pack
    upper.append(T.cyl(0.05, 0.62, loc=(sx * 0.2, -0.46, 1.92), mat=soot, n=10))
    upper.append(T.cyl(0.065, 0.06, loc=(sx * 0.2, -0.46, 2.22), mat=soot, n=10))
# shoulder arms and missile pods
pod_center = {}
for sx in (1, -1):
    upper.append(T.cyl(0.11, 0.2, loc=(sx * 0.53, 0, 1.78), rot=(0, 90, 0), mat=bare, n=14))       # shoulder joint
    upper.append(T.box((0.08, 0.22, 0.36), loc=(sx * 0.63, 0, 1.72), mat=armor, bevel=0.015))     # bracket
    c = Vector((sx * 0.86, 0.06, 1.78))
    pod_center[sx] = c
    upper.append(T.box((0.36, 0.62, 0.46), loc=tuple(c), mat=olive, bevel=0.04))                   # pod
    upper.append(T.box((0.38, 0.05, 0.48), loc=tuple(c + Vector((0, 0.3, 0))), mat=armor, bevel=0.015))  # front frame
    for row in range(5):
        for col in range(2):
            tx = c.x + (col - 0.5) * 0.15
            tz = c.z - 0.17 + row * 0.085
            upper.append(T.cyl(0.035, 0.06, loc=(tx, c.y + 0.32, tz), rot=(90, 0, 0), mat=dark, n=10))
            markers.append(T.marker("m_tube_%s%d" % ("r" if sx > 0 else "l", row * 2 + col), (tx, c.y + 0.36, tz)))
    markers.append(T.marker("m_pod_" + ("r" if sx > 0 else "l"), tuple(c + Vector((0, 0.36, 0)))))
# head: squat armoured box with a sensor slit, no face
upper.append(T.cyl(0.09, 0.14, loc=(0, 0.08, 2.05), mat=dark, n=12))                              # neck
upper.append(T.box((0.36, 0.34, 0.24), loc=(0, 0.1, 2.2), mat=armor, bevel=0.04, taper=(0.9, 0.85)))
upper.append(T.box((0.26, 0.02, 0.035), loc=(0, 0.275, 2.22), mat=slit))                          # sensor slit
upper.append(T.box((0.3, 0.06, 0.05), loc=(0, 0.27, 2.27), mat=bare, bevel=0.01))                   # visor brow
# the burnt soft serve cone on a little frame on top (it still burns, like the truck's)
cone_tip = Vector((0.0, -0.02, 2.33))
upper.append(T.lathe([(0.0, 0.0), (0.02, 0.02), (0.12, 0.2), (0.13, 0.22), (0.1, 0.22)], loc=tuple(cone_tip), mat=wafer, n=14))
upper.append(T.lathe([(0.1, 0.0), (0.11, 0.04), (0.07, 0.1), (0.02, 0.15), (0.0, 0.16)], loc=tuple(cone_tip + Vector((0, 0, 0.22))), mat=swirl, n=12))
for a in range(3):
    ang = a * 2.0 * math.pi / 3.0
    upper.append(rod((math.cos(ang) * 0.13, -0.02 + math.sin(ang) * 0.13, 2.31), (math.cos(ang) * 0.05, -0.02 + math.sin(ang) * 0.05, 2.4), 0.012, dark, 6))
markers.append(T.marker("m_cone", tuple(cone_tip + Vector((0, 0, 0.36)))))
markers.append(T.marker("m_waist", tuple(WAIST)))
upper_ob = T.join(upper, "upper")


# ---------------------------------------------------------------- paint
def band(P, N):  # the crimson band round the torso, like the van's
    return ((P[:, 2] > 1.5) & (P[:, 2] < 1.62) & (np.abs(P[:, 0]) < 0.5) & (P[:, 2] < 1.9)).astype(np.float32)
regions.append((band, CRIMSON, ("paint",)))
for sx in (1, -1):
    decals.append(T.Decal(T.dots_image((0.28, 0.03, 0.04), n=9, seed=3 + sx, size=(256, 256), r=(14, 22)), (sx * 0.47, 0.0, 1.72), (sx, 0, 0), (0, 0, 1), (0.6, 0.36), depth=0.1, kinds=("paint",), opacity=0.8))
    decals.append(T.Decal(T.stencil("%d" % (10 if sx > 0 else 20), (0.75, 0.72, 0.6), 96, pad=0.1), (sx * 1.045, 0.06, 1.86), (sx, 0, 0), (0, 0, 1), (0.16, 0.1), depth=0.06, kinds=("paint",)))
    decals.append(T.Decal(T.hazard_image(stripes=5, size=(256, 48)), (pod_center[sx].x, pod_center[sx].y + 0.33, pod_center[sx].z + 0.27), (0, 1, 0), (0, 0, 1), (0.36, 0.06), depth=0.06, kinds=("steel",)))
decals.append(T.Decal(T.holes_image(7, 5, size=(512, 256), r=(3, 7)), (0, 0.36, 1.6), (0, 1, 0), (0, 0, 1), (0.9, 0.6), depth=0.08, kinds=("paint", "steel")))
decals.append(T.Decal(T.stencil("ICE", (0.28, 0.03, 0.04), 110, pad=0.1), (0, -0.445, 1.62), (0, -1, 0), (0, 0, 1), (0.34, 0.14), depth=0.06, kinds=("steel",), opacity=0.7))


# ---------------------------------------------------------------- bake and export
objs = [legs_ob, upper_ob]
if "--shape" in sys.argv:
    out = sys.argv[sys.argv.index("--shape") + 1]
    T.preview(out, size=(900, 900), eye=(2.6, 3.4, 2.0), look=(0, 0, 1.15), fov=40, samples=12)
    T.preview(out.replace(".png", "_b.png"), size=(900, 900), eye=(-2.8, -3.0, 2.4), look=(0, 0, 1.15), fov=40, samples=12)
    sys.exit(0)
T.unwrap(objs, margin=0.003)
if "--nobake" not in sys.argv:
    g = T.gbuffer(objs, size=1024, ao_dist=0.35, bevel_r=0.01, ao_samples=24)
    al, nm, orm = T.weather(g, decals, seed=41, dust_from=0.0, dust_to=0.9, regions=regions,
        soot=[((0.2, -0.46, 2.22), 0.25), ((-0.2, -0.46, 2.22), 0.25), (tuple(cone_tip + Vector((0, 0, 0.3))), 0.22)])
    T.save_maps("sweet_bot", al, nm, orm)
upper_ob.data.transform(Matrix.Translation(-WAIST))  # the upper body turns about the waist
T.export_glb("sweet_bot", objs, markers=markers)
print("ok", T.tri_count(objs))

"""Sweet Tooth's special (round 23, owner: "make the specials look like special weapons, not plain fireballs"):
the Napalm Cone as a real thing, not a ball of light. A big waffle cone flying point first: the raised waffle
lattice wound round it both ways, the tip scorched black, a rolled rim, and on top a scoop of molten napalm
(glowing, lumpy, dripping over the rim). The fire round it is the game's own (FoamFire) in Godot.
    /tmp/bpy3.13/bin/python tools/blender/build_napalm_cone.py              # build, bake, export
    /tmp/bpy3.13/bin/python tools/blender/build_napalm_cone.py --shape a.png  # quick look, no bake
Blender space: +Y = where it flies (the tip), +Z up. In Godot (x the shot's size) the tip is at -Z 0.7 and the
scoop's top at +Z 0.75, the same span as the old primitive cone. Writes assets/models/napalm_cone.glb: "cone"."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
from grimm_rider import Sculpt
import bpy
from mathutils import Matrix, Vector

T.reset()
V = Vector
L = 1.0   # tip to mouth
R = 0.36  # mouth radius
waffle = T.M("plastic", (0.52, 0.27, 0.08), wear=0.0, rust=0.0, dirt=0.5, rough=0.75)
ridge = T.M("plastic", (0.66, 0.37, 0.12), wear=0.0, rust=0.0, dirt=0.45, rough=0.65)
burnt = T.M("plastic", (0.07, 0.035, 0.02), wear=0.0, rust=0.0, dirt=0.2, rough=0.95)
molten = T.glow((1.0, 0.42, 0.07))

# Built along +Z (tip at z = 0, mouth at z = L), turned at the end so the tip points along +Y.
parts = []
tip_end = 0.24
prof = [(0.0, 0.0)] + [(R * t, L * t) for t in [i / 20.0 for i in range(1, int(tip_end * 20) + 1)]]
parts.append(T.lathe(prof, mat=burnt, n=40, name="tip"))
prof = [(R * t, L * t) for t in [tip_end + (1.0 - tip_end) * i / 16.0 for i in range(17)]]
parts.append(T.lathe(prof, mat=waffle, n=40, name="shell"))
# The waffle lattice: raised ridges wound round the cone both ways.
LINES = 14
for sgn in (1, -1):
    for k in range(LINES):
        a0 = 2 * math.pi * k / LINES
        pts = []
        for i in range(17):
            t = tip_end + (1.0 - tip_end) * i / 16.0
            a = a0 + sgn * 1.7 * t
            r = R * t + 0.002
            pts.append((r * math.cos(a), r * math.sin(a), L * t))
        parts.append(T.tube(pts, 0.011, mat=ridge, n=3, name="ridge"))
# The rolled rim round the mouth.
rim = [((R + 0.012) * math.cos(2 * math.pi * i / 40), (R + 0.012) * math.sin(2 * math.pi * i / 40), L) for i in range(41)]
parts.append(T.tube(rim, 0.04, mat=ridge, n=6, name="rim"))
# The scoop of molten napalm: one melted surface, lumpy, with drips running over the rim.
random.seed(5)
S = Sculpt("scoop", 0.02)
S.ball(V((0, 0, L + 0.13)), 0.37, (1.0, 1.0, 0.82))
for k in range(7):
    a = 2 * math.pi * k / 7 + random.uniform(-0.3, 0.3)
    S.ball(V((0.22 * math.cos(a), 0.22 * math.sin(a), L + 0.2 + random.uniform(-0.05, 0.08))), 0.15)
S.ball(V((0.02, -0.03, L + 0.33)), 0.17)
for k in range(5):  # drips down the outside of the cone, of different lengths
    a = 2 * math.pi * k / 5 + 0.4
    length = random.uniform(0.12, 0.3)
    top = V(((R + 0.015) * math.cos(a), (R + 0.015) * math.sin(a), L + 0.02))
    bot = V(((R * (1 - length) + 0.02) * math.cos(a), (R * (1 - length) + 0.02) * math.sin(a), L * (1 - length)))
    S.chain(top, bot, 0.04, 0.02, step=0.03)
    S.ball(bot, 0.03)
scoop = S.mesh(molten, 0.22)
scoop.name = "scoop"
parts.append(scoop)
cone = T.join(parts, "cone")
# Turn: +Z (tip to mouth) -> -Y, so the tip leads along +Y; then the tip to y = +0.7 (as before in Godot).
cone.data.transform(Matrix.Translation((0, 0.7, 0)) @ Matrix.Rotation(math.radians(90), 4, "X"))
print("triangles", T.tri_count([cone]))

if "--shape" in sys.argv:
    out = sys.argv[sys.argv.index("--shape") + 1]
    cone.data.transform(Matrix.Translation((0, 0, 0.8)))
    T.preview(out, size=(900, 700), eye=(1.6, 1.4, 1.5), look=(0, 0, 0.8), fov=40, samples=16, ground=False)
    sys.exit(0)
T.unwrap([cone], margin=0.004)
if "--nobake" not in sys.argv:
    g = T.gbuffer([cone], size=1024, ao_dist=0.12, bevel_r=0.004, ao_samples=24)
    al, nm, orm = T.weather(g, [], seed=11, dust_from=-1.0, dust_to=1.0, ao_strength=0.95)
    T.save_maps("napalm_cone", al, nm, orm)
T.export_glb("napalm_cone", [cone])
print("ok", T.tri_count([cone]))

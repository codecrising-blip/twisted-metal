"""Mr. Grimm's special (round 21, owner: "it looks like a fireball, not a skull attack"): the skull itself, a
real one, so it reads as a skull at a glance with the flames streaming back behind it (the fire is the
game's FoamFire, added in Godot by Projectile._skull_visual).
Sculpted like the drivers and the clown head: the cranium, brow, cheekbones and upper jaw melted into one
surface, the eye sockets and the nose hole cut deep into it (their walls dark), a row of upper teeth, the
jaw hanging open beneath with its own teeth, a glowing ember deep in each socket. Old bone: ivory, darker
and dirtier in every crevice (baked AO + grime). About 1.15 m across.
    /tmp/bpy3.13/bin/python tools/blender/build_skull.py              # build, bake, export
    /tmp/bpy3.13/bin/python tools/blender/build_skull.py --shape a.png  # quick look, no bake
Blender space: +Y = where it flies (its face), +Z up, centred on the middle of the cranium.
Writes assets/models/skull.glb: node "skull"."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
from grimm_rider import Sculpt
import bpy
from mathutils import Matrix, Vector

T.reset()
V = Vector
bone = T.M("plastic", (0.66, 0.6, 0.47), wear=0.0, rust=0.0, dirt=0.55, rough=0.6)
socket = T.M("plastic", (0.006, 0.005, 0.004), wear=0.0, rust=0.0, dirt=0.0, rough=0.95)
tooth = T.M("plastic", (0.55, 0.47, 0.3), wear=0.0, rust=0.0, dirt=0.6, rough=0.5)
ember = T.glow((1.0, 0.14, 0.02))
# Hairline cracks across the dome and down one temple (old bone, not a toy).
import random as _r
_r.seed(7)


def crack(x0, y0, steps, dx, dy):
    seg, x, y = [], x0, y0
    for k in range(steps):
        nx, ny = x + dx + _r.uniform(-0.05, 0.05), y + dy + _r.uniform(-0.04, 0.04)
        seg.append((x, y, nx, ny))
        if _r.random() < 0.3:
            seg.append((nx, ny, nx + _r.uniform(-0.08, 0.08), ny + _r.uniform(0.03, 0.08)))
        x, y = nx, ny
    return seg


cracks = T.lines_image(crack(0.3, 0.1, 9, 0.05, 0.085) + crack(0.62, 0.15, 6, -0.03, 0.09), size=(512, 512), width=3, color=(0.05, 0.035, 0.02), alpha=0.95)
decals = [T.Decal(cracks, (0.08, 0.12, 0.55), (0.1, 0.5, 1.0), (0, 1, 0), (0.7, 0.7), depth=0.35, kinds=("plastic",), opacity=0.9),
          T.Decal(cracks, (0.4, -0.05, 0.15), (1, 0, 0.2), (0, 0, 1), (0.5, 0.5), depth=0.3, kinds=("plastic",), opacity=0.8)]


def cut(ob, cutter):
    """ob minus cutter; the cut walls take the cutter's material (dark socket walls)."""
    m = ob.modifiers.new("cut", "BOOLEAN")
    m.operation = "DIFFERENCE"
    m.object = cutter
    m.solver = "EXACT"
    m.material_mode = "TRANSFER"
    bpy.context.view_layer.update()
    T.apply(ob)
    bpy.data.objects.remove(cutter)
    return ob


# ---------------------------------------------------------------- the cranium and face, one surface
S = Sculpt("skull_bone", 0.014)
S.ball(V((0, -0.06, 0.14)), 0.47, (0.9, 1.06, 0.95))       # the dome, longer front to back
S.ball(V((0, 0.2, 0.2)), 0.31, (1.05, 0.9, 0.9))           # the forehead, rounded forward
S.ball(V((0, -0.36, 0.0)), 0.3, (1.0, 0.9, 0.9))           # the back of the head
S.ball(V((0, 0.41, 0.06)), 0.09, (3.3, 1.0, 0.7))          # the brow ridge, overhanging the sockets
for sx in (1, -1):
    S.ball(V((sx * 0.26, 0.31, -0.13)), 0.12, (1.4, 0.9, 0.7))   # cheekbones, jutting
    S.ball(V((sx * 0.3, 0.1, -0.09)), 0.065, (0.7, 1.8, 0.55))  # the arch back to the ear, flat
    S.ball(V((sx * 0.31, -0.05, 0.12)), 0.2, (0.6, 1.0, 1.1))    # the temples, flatter
S.ball(V((0, 0.33, -0.25)), 0.17, (1.25, 0.95, 0.8))       # the upper jaw
S.ball(V((0, 0.12, -0.2)), 0.22, (1.2, 1.0, 0.7))          # the skull's base behind it
head = S.mesh(bone, 0.3)
head.name = "skull_head"
# sockets, the nose hole and the hollow between the jaws, cut deep; their walls dark
for sx in (1, -1):  # the orbits: rounded squares, deep, the outer corner a little lower
    c = T.box((0.23, 0.42, 0.19), loc=(sx * 0.145, 0.46, -0.035), rot=(0, sx * 8, 0), mat=socket, bevel=0.06, segs=3)
    head = cut(head, c)
nose = [(0.0, 0.05), (0.028, 0.012), (0.05, -0.05), (0.048, -0.095), (0.02, -0.112), (0.0, -0.09),
        (-0.02, -0.112), (-0.048, -0.095), (-0.05, -0.05), (-0.028, 0.012)]
head = cut(head, T.prism(nose, 0.5, loc=(0, 0.45, -0.12), mat=socket, plane="XZ"))  # the nose hole: an upside-down heart
parts = [head]
# embers glowing deep in the sockets
for sx in (1, -1):
    parts.append(T.sphere(0.02, loc=(sx * 0.145, 0.3, -0.045), mat=ember, n=10))
# the upper teeth along the jaw's curve
_r.seed(3)
for k in range(8):  # uneven, yellowed, one missing
    if k == 5:
        continue
    a = (k - 3.5) / 3.5
    h = 0.075 + _r.uniform(-0.012, 0.01)
    parts.append(T.box((0.038, 0.04, h), loc=(a * 0.16, 0.43 - (a * a) * 0.09, -0.355 - h * 0.5 + 0.035), rot=(0, _r.uniform(-6, 6), -a * 28), mat=tooth, bevel=0.01))
# ---------------------------------------------------------------- the jaw, hanging open under it
J = Sculpt("skull_jaw", 0.014)
J.ball(V((0, 0.36, -0.52)), 0.11, (1.5, 1.0, 0.8))          # the chin, square and heavy
for sx in (1, -1):
    J.chain(V((sx * 0.07, 0.35, -0.5)), V((sx * 0.25, 0.1, -0.44)), 0.06, 0.055)   # the jaw's body
    J.chain(V((sx * 0.26, 0.1, -0.44)), V((sx * 0.29, 0.02, -0.22)), 0.05, 0.045)  # up to the hinge
jaw = J.mesh(bone, 0.35)
jaw_parts = [jaw]
for k in range(8):
    a = (k - 3.5) / 3.5
    h = 0.065 + _r.uniform(-0.012, 0.008)
    jaw_parts.append(T.box((0.034, 0.036, h), loc=(a * 0.145, 0.4 - (a * a) * 0.09, -0.44 + h * 0.5 - 0.03), rot=(0, _r.uniform(-6, 6), -a * 28), mat=tooth, bevel=0.01))
jaw = T.join(jaw_parts, "skull_jaw")
# open: turned down about the hinge
hinge = V((0, 0.02, -0.22))
jaw.data.transform(Matrix.Translation(hinge) @ Matrix.Rotation(math.radians(-16), 4, "X") @ Matrix.Translation(-hinge))
skull = T.join(parts + [jaw], "skull")
print("triangles", T.tri_count([skull]))

if "--shape" in sys.argv:
    out = sys.argv[sys.argv.index("--shape") + 1]
    skull.data.transform(Matrix.Translation((0, 0, 0.75)))
    T.preview(out, size=(900, 900), eye=(1.1, 2.4, 1.2), look=(0, 0, 0.75), fov=34, samples=16, ground=False)
    T.preview(out.replace(".png", "_f.png"), size=(900, 900), eye=(0.0, 2.6, 0.85), look=(0, 0, 0.75), fov=34, samples=16, ground=False)
    sys.exit(0)
T.unwrap([skull], margin=0.004)
if "--nobake" not in sys.argv:
    g = T.gbuffer([skull], size=1024, ao_dist=0.25, bevel_r=0.006, ao_samples=24)
    al, nm, orm = T.weather(g, decals, seed=31, dust_from=-0.6, dust_to=0.6, ao_strength=0.9)
    T.save_maps("skull", al, nm, orm)
T.export_glb("skull", [skull])
print("ok", T.tri_count([skull]))

"""Mr. Grimm, second pass (round 20, owner): TM2's vehicle IDENTICAL in shape and colours, nothing invented;
only the rider's clothes change (Death's coat and the scythe instead of the motorbike suit).
  Shape: the owner's 7 views of the HD TM2 roster (docs/reference/Mr Grimm F/B/L/R/T/IL/IR.jpeg), placed at the
  sizes of the original TM2 car (the textured rip in docs/reference/3d_models/tm2_roster_textured_obj.zip, scaled
  x25: 3.17 m long, 1.86 m wide, wheels r 0.45 on a 2.24 m base, the sidecar on the right).
  Colours: transferred spot by spot from the original car's texture (T.ps1_reference + T.transfer_colors), drawn
  smoother than the PS1 pixels. Clean: no wear, rust or dirt.
    /tmp/bpy3.13/bin/python tools/blender/build_mr_grimm.py              # build, bake, export
    /tmp/bpy3.13/bin/python tools/blender/build_mr_grimm.py --shape a.png  # quick look, no bake
Blender space: +Y forward, +Z up. Nodes: body, wheel_f, wheel_r, spinner; markers m_wheel_fl (bike front),
m_wheel_rl (bike rear), m_gun_l/r, m_spin_0, m_launcher, m_top, m_head, m_exh_l."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
import numpy as np
from mathutils import Matrix, Vector
from PIL import Image

T.reset()
V = Vector
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
RIP = os.path.join(REPO, "docs", "reference", "3d_models", "tm2_roster_textured_obj.zip")
SCALE = 25.0
# the car's own paint comes from the original: these two only say how it shines
tm2 = T.M("paint", (0.5, 0.05, 0.04), wear=0.0, rust=0.0, dirt=0.0, rough=0.4, name="tm2_paint")
tm2_metal = T.M("steel", (0.5, 0.5, 0.5), wear=0.0, rust=0.0, dirt=0.0, rough=0.3, name="tm2_metal")
gun_steel = T.M("steel", (0.42, 0.42, 0.42), wear=0.0, rust=0.0, dirt=0.0, rough=0.3)
rubber = T.M("rubber", (0.018, 0.018, 0.018), dirt=0.0)
hub = T.M("plastic", (0.6, 0.58, 0.52), wear=0.0, dirt=0.0, rough=0.35)
# the rider (not from the original: the owner's clothes)
helmet = T.M("plastic", (0.02, 0.02, 0.023), wear=0.0, dirt=0.0, rough=0.18)
visor = T.M("glassy", (0.03, 0.04, 0.055), wear=0.0, rust=0.0, dirt=0.0)
coat = T.M("cloth", (0.065, 0.07, 0.09), dirt=0.0)
lining = T.M("cloth", (0.16, 0.02, 0.025), dirt=0.0)
leather = T.M("plastic", (0.03, 0.027, 0.025), wear=0.0, dirt=0.0, rough=0.4)
wood = T.M("wood", (0.16, 0.09, 0.045), dirt=0.0)
blade = T.M("steel", (0.32, 0.32, 0.31), wear=0.0, rust=0.0, dirt=0.0)
decals = []
regions = []
markers = []

R = 0.45            # wheel radius (original: 0.45)
BX = -0.51          # the bike's centre line; the sidecar rides on the right
SX = 0.30           # the sidecar's centre line
FA, RA = 1.12, -1.12  # axles
body = []


def aim(d):
    q = Vector(d).normalized().to_track_quat("Z", "Y").to_euler()
    return (math.degrees(q.x), math.degrees(q.y), math.degrees(q.z))


def rod(a, b, r, mat, n=10, r2=None):
    a, b = Vector(a), Vector(b)
    v = b - a
    return T.cyl(r, v.length, loc=tuple((a + b) / 2), rot=aim(v), mat=mat, n=n, r2=r2)


def limb(a, b, w, d, mat, bevel=0.02):
    a, b = Vector(a), Vector(b)
    v = b - a
    return T.box((w, d, v.length), loc=tuple((a + b) / 2), rot=aim(v), mat=mat, bevel=bevel)


def side_prism(outline, x, width, mat, bevel=0.015):
    """A part drawn as its side outline (y, z) and given its width across X."""
    return T.prism(outline, width, loc=(x, 0, 0), mat=mat, plane="YZ", bevel=bevel)


def strip(path, width, thick, mat, up=V((0, 0, 1)), taper=1.0):
    secs = []
    n = len(path)
    for k, p in enumerate(path):
        p = Vector(p)
        t = (Vector(path[min(k + 1, n - 1)]) - Vector(path[max(k - 1, 0)])).normalized()
        side = t.cross(up).normalized()
        nrm = side.cross(t).normalized()
        w = width * (1.0 + (taper - 1.0) * k / (n - 1)) / 2
        secs.append([tuple(p + side * w + nrm * thick / 2), tuple(p - side * w + nrm * thick / 2),
                     tuple(p - side * w - nrm * thick / 2), tuple(p + side * w - nrm * thick / 2)])
    return T.loft(secs, mat=mat, angle=35.0)


# ---------------------------------------------------------------- the bike (side view L: front to the left)
# lower body between the wheels, its back edge raked clear of the rear wheel
body.append(side_prism([(0.51, 0.66), (0.40, 0.33), (0.10, 0.20), (-0.62, 0.20), (-0.86, 0.62), (-0.92, 0.97),
                        (-0.62, 1.0), (-0.18, 1.0), (0.0, 1.1), (0.30, 1.02), (0.47, 0.82)], BX, 0.35, tm2))
body.append(side_prism([(-0.62, 0.97), (-0.95, 0.84), (-1.25, 0.95), (-1.25, 1.23), (-0.81, 1.14)], BX, 0.30, tm2))  # the tail
body.append(T.box((0.22, 0.48, 0.07), loc=(BX, -0.42, 1.04), mat=tm2, bevel=0.03))                   # seat
# the fairing: a long box on top of the front, its front a V-shaped plate (front view)
body.append(side_prism([(0.0, 1.12), (0.0, 1.27), (0.92, 1.34), (0.87, 1.12)], BX, 0.32, tm2, 0.02))
body.append(T.prism([(-0.27, 0.0), (0.27, 0.0), (0.0, -0.38)], 0.05, loc=(BX, 0.9, 1.35), rot=(-10, 0, 0), mat=tm2, plane="XZ"))
body.append(limb(V((BX, 0.92, 1.33)), V((BX, 0.25, 1.66)), 0.34, 0.03, tm2, 0.01))                  # the windscreen blade
for sx in (1, -1):  # bar risers up to the high grips
    g = V((BX + sx * 0.24, -0.02, 1.66))
    body.append(limb(V((BX + sx * 0.12, 0.48, 1.34)), g, 0.07, 0.07, tm2, 0.015))
    body.append(T.cyl(0.035, 0.16, loc=tuple(g + V((sx * 0.06, 0, 0))), rot=(0, 90, 0), mat=tm2, n=10))
body.append(limb(V((BX, FA, R)), V((BX, 0.6, 1.04)), 0.2, 0.16, tm2, 0.03))                          # the fork
for k in range(4):  # the stacked fins under the fairing
    body.append(T.box((0.44, 0.42, 0.045), loc=(BX, 0.34, 0.76 + k * 0.062), mat=tm2_metal, bevel=0.02))
for k in range(3):  # three pipes low on the left
    body.append(T.cyl(0.035, 0.6 - k * 0.08, loc=(BX - 0.2, -0.44 - k * 0.04, 0.3 + k * 0.1), rot=(-90, 0, 0), mat=tm2_metal, n=10))
markers.append(T.marker("m_exh_l", (BX - 0.2, -0.76, 0.3)))
body.append(rod(V((BX - 0.13, RA, R)), V((BX - 0.13, -0.62, 0.42)), 0.04, tm2_metal))                 # swingarm, both sides
body.append(rod(V((BX + 0.13, RA, R)), V((BX + 0.13, -0.62, 0.42)), 0.04, tm2_metal))

# ---------------------------------------------------------------- the sidecar (side view R: front to the right)
SC = [(-1.58, 0.25), (-1.07, 0.63), (-0.03, 0.63), (0.17, 0.36), (0.17, 0.19), (-1.45, 0.19)]
body.append(side_prism(SC, SX, 0.7, tm2))
body.append(T.box((0.3, 0.7, 0.035), loc=(-0.19, -0.71, 0.5), rot=(0, -40, 0), mat=tm2, bevel=0.01))   # to the bike
# the slot panel on its outer side: two rows of six
body.append(T.box((0.05, 0.73, 0.4), loc=(SX + 0.37, -0.8, 0.41), mat=tm2, bevel=0.01))
for row in range(2):
    for k in range(6):
        body.append(T.box((0.03, 0.04, 0.12), loc=(SX + 0.4, -1.08 + k * 0.11, 0.33 + row * 0.16), mat=tm2_metal, bevel=0.008))
# the ramp at its back carries the skull, riveted strips beside it and a row of slots under it
ra, rb = V((0, -1.58, 0.25)), V((0, -1.07, 0.63))
up_r = (rb - ra).normalized()
n_r = V((0, -up_r.z, up_r.y))
mid = (ra + rb) / 2
for sx in (1, -1):
    c = V((SX + sx * 0.3, 0, 0)) + mid + n_r * 0.012
    body.append(T.box((0.07, 0.03, 0.6), loc=tuple(c), rot=aim(up_r), mat=tm2_metal, bevel=0.006))
    for k in range(5):
        body.append(T.sphere(0.012, loc=tuple(c + up_r * (-0.24 + k * 0.12) + n_r * 0.016), mat=tm2_metal, n=6))
for k in range(6):
    body.append(T.box((0.035, 0.03, 0.06), loc=tuple(V((SX + (k - 2.5) * 0.08, 0, 0)) + ra + up_r * 0.08 + n_r * 0.01), rot=aim(up_r), mat=tm2_metal, bevel=0.006))
sk = V((SX, 0, 0)) + mid + up_r * 0.05 + n_r * 0.03
right = V((1, 0, 0))
body.append(T.sphere(0.19, loc=tuple(sk + up_r * 0.04), mat=tm2, n=18, scale=(1.0, 0.42, 0.82)))    # cranium (relief)
body.append(T.box((0.22, 0.06, 0.1), loc=tuple(sk - up_r * 0.15 + n_r * 0.01), rot=aim(up_r), mat=tm2, bevel=0.025))  # jaw
for k in range(6):  # teeth
    body.append(T.box((0.026, 0.03, 0.05), loc=tuple(sk + right * (k - 2.5) * 0.034 - up_r * 0.11 + n_r * 0.05), rot=aim(up_r), mat=tm2, bevel=0.006))
for sx in (1, -1):
    body.append(T.sphere(0.052, loc=tuple(sk + right * sx * 0.075 + up_r * 0.03 + n_r * 0.06), mat=tm2, n=10, scale=(1.1, 0.6, 1.0)))  # sockets
    body.append(T.box((0.05, 0.04, 0.09), loc=tuple(sk + right * sx * 0.15 - up_r * 0.05 + n_r * 0.03), rot=aim(up_r), mat=tm2, bevel=0.015))  # cheek bones
# the front: three round ports low down
for k in range(3):
    body.append(T.cyl(0.055, 0.04, loc=(SX + (k - 1) * 0.2, 0.17, 0.27), rot=(-90, 0, 0), mat=tm2, n=14))
    body.append(T.cyl(0.04, 0.03, loc=(SX + (k - 1) * 0.2, 0.185, 0.27), rot=(-90, 0, 0), mat=rubber, n=12))
# the magazine on top: ten rounded plates standing in a row
for k in range(10):
    body.append(T.box((0.46, 0.045, 0.33), loc=(SX + 0.04, -1.04 + k * 0.069, 0.79), mat=tm2_metal, bevel=0.018))
body.append(T.cyl(0.14, 0.08, loc=(SX, -0.34, 0.77), rot=(-90, 0, 0), mat=gun_steel, n=16))             # gatling housing
body.append(T.cyl(0.12, 0.04, loc=(SX, 0.18, 0.77), rot=(-90, 0, 0), mat=gun_steel, n=16))              # barrel clamp (fixed)
body.append(T.cyl(0.25, 0.12, loc=(SX + 0.17, -0.71, 0.25), rot=(0, 90, 0), mat=rubber, n=16))          # its own little wheel, under it
markers.append(T.marker("m_spin_0", (SX, -0.3, 0.77)))
for sx in (1, -1):
    markers.append(T.marker("m_gun_" + ("r" if sx > 0 else "l"), (SX + sx * 0.03, 0.5, 0.77)))
markers.append(T.marker("m_launcher", (0.0, 0.3, 1.0)))
markers.append(T.marker("m_top", (BX, 0.3, 1.2)))
markers.append(T.marker("m_head", (BX, 0.95, 1.2)))

# ---------------------------------------------------------------- the rider: TM2's pose and helmet, Death's coat
import grimm_rider  # a sculpt, not parts (owner: "not a Lego driver")
body += grimm_rider.build(BX, dict(coat=coat, leather=leather, helmet=helmet, visor=visor, wood=wood, blade=blade, lining=lining, metal=gun_steel), regions)

# ---------------------------------------------------------------- wheels (axle along X, outer face at +X) and the spinner


def ring_solid(profile, mat, n=28, name="ring"):
    """A closed profile [(radius, x), ...] swept round the X axis, with no caps: an open ring (tyre, rim)."""
    import bmesh
    bm = bmesh.new()
    rings = [[bm.verts.new((x, r * math.cos(2 * math.pi * k / n), r * math.sin(2 * math.pi * k / n))) for k in range(n)] for r, x in profile]
    for i in range(len(rings)):
        a, b = rings[i], rings[(i + 1) % len(rings)]
        for k in range(n):
            bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return T._new_obj(name, bm, mat, (0, 0, 0), (0, 0, 0), 50.0)


def wheel(name, w, spokes=10):
    """TM2's HD wheel: a chevron-treaded tyre, ten straight spokes, a big hub cap."""
    tyre = [(R * 0.7, -w / 2), (R * 0.92, -w / 2), (R * 0.99, -w / 2 + 0.035), (R, -w * 0.2), (R, w * 0.2), (R * 0.99, w / 2 - 0.035),
            (R * 0.92, w / 2), (R * 0.7, w / 2), (R * 0.69, 0.0)]
    parts = [ring_solid(tyre, rubber, 32)]
    for k in range(32):  # shallow chevron ribs in the tread (not blocks)
        a = 2 * math.pi * k / 32
        for sx in (1, -1):
            parts.append(T.box((w * 0.4, 0.045, 0.01), loc=(sx * w * 0.2, math.cos(a) * (R + 0.002), math.sin(a) * (R + 0.002)),
                               rot=(math.degrees(a) + 90, 0, sx * 30), mat=rubber))
    parts.append(ring_solid([(R * 0.7, -w / 2 + 0.01), (R * 0.7, w / 2 - 0.01), (R * 0.63, w / 2 - 0.02), (R * 0.63, -w / 2 + 0.02)], hub, 32))
    for k in range(spokes):
        a = 2 * math.pi * k / spokes
        parts.append(T.box((0.05, 0.035, R * 0.5), loc=(0, math.cos(a) * R * 0.42, math.sin(a) * R * 0.42), rot=(math.degrees(a) - 90, 0, 0), mat=hub, bevel=0.008))
    parts.append(T.cyl(R * 0.2, w * 0.9, rot=(0, 90, 0), mat=hub, n=18, bevel=0.012))               # the hub cap
    parts.append(T.cyl(R * 0.08, w * 1.05, rot=(0, 90, 0), mat=gun_steel, n=10))
    return T.join(parts, name)


wheel_f = wheel("wheel_f", 0.24)
wheel_r = wheel("wheel_r", 0.24)
markers += [T.marker("m_wheel_fl", (BX, FA, R)), T.marker("m_wheel_rl", (BX, RA, R))]
sp = [T.cyl(0.11, 0.05, (0, 0.06, 0), rot=(-90, 0, 0), mat=gun_steel, n=14), T.cyl(0.11, 0.04, (0, 0.6, 0), rot=(-90, 0, 0), mat=gun_steel, n=14)]
for k in range(6):
    a = math.radians(60 * k)
    sp.append(T.cyl(0.032, 0.8, (math.cos(a) * 0.072, 0.4, math.sin(a) * 0.072), rot=(-90, 0, 0), mat=gun_steel, n=8))
sp.append(T.cyl(0.03, 0.78, (0, 0.39, 0), rot=(-90, 0, 0), mat=gun_steel, n=8))
spinner = T.join(sp, "spinner")
body_ob = T.join(body, "body")
print("triangles: body %d, wheel_f %d, wheel_r %d, spinner %d" % (T.tri_count([body_ob]), T.tri_count([wheel_f]), T.tri_count([wheel_r]), T.tri_count([spinner])))

if "--shape" in sys.argv:
    out = sys.argv[sys.argv.index("--shape") + 1]
    wf = [T.dup(wheel_f, (BX, FA, R)), T.dup(wheel_r, (BX, RA, R)), T.dup(spinner, (SX, -0.3, 0.77))]
    for o in (wheel_f, wheel_r, spinner):
        o.location = (0, 0, -50)
    T.preview(out, size=(1000, 700), eye=(-5.0, 0.0, 1.0), look=(0, 0.0, 0.9), fov=40, samples=12)      # left side
    T.preview(out.replace(".png", "_r.png"), size=(1000, 700), eye=(5.0, 0.1, 1.0), look=(0, 0.0, 0.9), fov=40, samples=12)
    T.preview(out.replace(".png", "_f.png"), size=(1000, 700), eye=(-0.1, 5.5, 1.3), look=(0, 0, 0.9), fov=40, samples=12)
    T.preview(out.replace(".png", "_b.png"), size=(1000, 700), eye=(1.8, -4.6, 2.6), look=(0, 0, 0.7), fov=40, samples=12)
    if "--rider" in sys.argv:  # close-ups of the rider
        T.preview(out.replace(".png", "_rh.png"), size=(900, 900), eye=(-0.9, 0.2, 2.0), look=(BX, -0.86, 1.85), fov=30, samples=16)
        T.preview(out.replace(".png", "_rf.png"), size=(900, 900), eye=(-2.2, 1.6, 2.2), look=(BX, -0.5, 1.45), fov=36, samples=16)
        T.preview(out.replace(".png", "_rb.png"), size=(900, 900), eye=(-1.6, -2.6, 2.4), look=(BX, -0.6, 1.4), fov=36, samples=16)
        T.preview(out.replace(".png", "_rs.png"), size=(900, 900), eye=(-3.0, -0.4, 1.6), look=(BX, -0.4, 1.35), fov=36, samples=16)
    sys.exit(0)

# ---------------------------------------------------------------- bake: the shape here, the paint from the original
import bpy
wheel_f.location = (3.0, 0.8, R)
wheel_r.location = (3.0, -0.8, R)
spinner.location = (3.0, 1.8, 0.5)
bpy.context.view_layer.update()
for o in (wheel_f, wheel_r, spinner):
    T.apply(o)
objs = [body_ob, wheel_f, wheel_r, spinner]
T.unwrap(objs, margin=0.002)
if "--nobake" not in sys.argv:
    g = T.gbuffer(objs, size=2048, ao_dist=0.35, bevel_r=0.006, ao_samples=20)
    tris, uvs, tex = T.ps1_reference(RIP, "mg", SCALE)
    print("original: %d triangles" % len(tris))
    print("painted texels:", T.transfer_colors(g, tris, uvs, tex, [tm2, tm2_metal]))
    al, nm, orm = T.weather(g, decals, seed=47, dust_from=0.0, dust_to=0.01, regions=regions, ao_strength=0.6)
    T.save_maps("mr_grimm", al, nm, orm)
wheel_f.data.transform(Matrix.Translation((-3.0, -0.8, -R)))
wheel_r.data.transform(Matrix.Translation((-3.0, 0.8, -R)))
spinner.data.transform(Matrix.Translation((-3.0, -1.8, -0.5)))
T.export_glb("mr_grimm", objs, markers=markers)
print("ok", T.tri_count(objs))

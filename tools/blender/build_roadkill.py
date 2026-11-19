"""Roadkill (round 20, owner): TM2's car IDENTICAL in shape and colours, nothing invented.
  Shape: the owner's HD TM2 views (docs/reference/roadkill S/T/F/B/IL/IR.jpeg), measured on a 0.25 m grid with the
  original's length (5.39 m: the textured rip in docs/reference/3d_models/tm2_roster_textured_obj.zip, x25): a long
  low muscle car, wedge nose behind a riveted armour plate with a row of slots over it and small square lamps, a hood
  scoop with two round intakes and a slotted box ahead of it, a fastback cabin, a big rear wing on end plates, a
  riveted rear plate, side pipes, two slots in each front fender, and a gun on each front fender: a row of eight
  shell canisters behind a long barrel, on two brackets. Deep-dish slotted wheels, bigger at the back.
  Colours: transferred spot by spot from the original car's texture ("rk"), smoothed. Clean, no wear.
    /tmp/bpy3.13/bin/python tools/blender/build_roadkill.py              # build, bake, export
    /tmp/bpy3.13/bin/python tools/blender/build_roadkill.py --shape a.png  # quick look, no bake
Blender space: +Y forward, +Z up. Nodes: body, wheel_f, wheel_r; markers m_wheel_fr/fl/rr/rl, m_gun_l/r,
m_launcher, m_top, m_head, m_exh_l/r."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
from mathutils import Matrix, Vector

T.reset()
V = Vector
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
RIP = os.path.join(REPO, "docs", "reference", "3d_models", "tm2_roster_textured_obj.zip")
SCALE = 25.0
tm2 = T.M("paint", (0.6, 0.25, 0.05), wear=0.0, rust=0.0, dirt=0.0, rough=0.35, name="tm2_paint")
tm2_metal = T.M("steel", (0.5, 0.5, 0.5), wear=0.0, rust=0.0, dirt=0.0, rough=0.3, name="tm2_metal")
tm2_glass = T.M("glassy", (0.05, 0.05, 0.06), wear=0.0, rust=0.0, dirt=0.0, name="tm2_glass")
gun_steel = T.M("steel", (0.32, 0.32, 0.33), wear=0.0, rust=0.0, dirt=0.0, rough=0.3)
rubber = T.M("rubber", (0.018, 0.018, 0.018), dirt=0.0)
rim_m = T.M("steel", (0.55, 0.55, 0.56), wear=0.0, rust=0.0, dirt=0.0, rough=0.25)
dark = T.M("steel", (0.03, 0.03, 0.032), wear=0.0, rust=0.0, dirt=0.0)
decals = []
regions = []
markers = []

L = 5.39
TAIL, NOSE = -L / 2, L / 2
RR, RF = 0.44, 0.37            # rear / front wheel radius (HD side view)
RA, FA = -1.3, 1.86            # axles
TR, TF = 0.98, 0.9             # wheel centres across
HW = 1.0                       # the body's half width
body = []


def y_(d):
    """Distance from the tail in the side view (metres) -> our y."""
    return TAIL + d


def aim(d):
    q = Vector(d).normalized().to_track_quat("Z", "Y").to_euler()
    return (math.degrees(q.x), math.degrees(q.y), math.degrees(q.z))


def rod(a, b, r, mat, n=12, r2=None):
    a, b = Vector(a), Vector(b)
    v = b - a
    return T.cyl(r, v.length, loc=tuple((a + b) / 2), rot=aim(v), mat=mat, n=n, r2=r2)


def section(y, hw, zb, zt, c=0.07, tuck=0.06):
    """A cross-section of the lower body at y: flat bottom, sides tucked a little under, the top edge rounded."""
    return [(hw - tuck, y, zb), (hw, y, zb + 0.12), (hw, y, zt - c), (hw - c, y, zt), (-hw + c, y, zt), (-hw, y, zt - c), (-hw, y, zb + 0.12), (-hw + tuck, y, zb)]


# ---------------------------------------------------------------- lower body: tail to nose (side view grid)
lower = [section(y_(0.0), 0.95, 0.47, 0.93), section(y_(0.25), 1.0, 0.42, 1.0), section(y_(0.9), HW, 0.4, 1.0),
         section(y_(1.6), HW, 0.38, 1.0), section(y_(3.2), HW, 0.38, 1.0), section(y_(4.0), HW, 0.39, 0.93),
         section(y_(4.7), 0.99, 0.42, 0.86), section(y_(5.12), 0.97, 0.47, 0.8), section(y_(5.39), 0.94, 0.55, 0.66, 0.04)]
lb = T.loft(lower, mat=tm2, angle=35.0)
for (yc, r, xc) in ((RA, RR, TR), (FA, RF, TF)):  # wheel arches cut through each side
    for sx in (1, -1):
        cutter = T.cyl(r + 0.06, 0.62, loc=(sx * (xc + 0.12), yc, r), rot=(0, 90, 0), n=28)
        T.cut(lb, cutter)
body.append(lb)
# the cabin: a fastback greenhouse, narrower than the body
cab = []
for y, hb, ht, zt in ((y_(1.05), 0.88, 0.8, 1.02), (y_(1.55), 0.86, 0.72, 1.3), (y_(1.75), 0.86, 0.7, 1.32), (y_(2.75), 0.86, 0.7, 1.32),
                      (y_(3.25), 0.88, 0.8, 1.02)):
    cab.append([(hb, y, 0.99), (ht, y, zt), (-ht, y, zt), (-hb, y, 0.99)])
body.append(T.loft(cab, mat=tm2, angle=30.0))
# its glass, laid on the cabin 5 mm proud: windshield, rear window, side windows
def quad(p, mat, th=0.012):
    a, b, c, d = [V(x) for x in p]
    n = (b - a).cross(d - a).normalized()
    return T.loft([[tuple(a + n * th), tuple(b + n * th), tuple(c + n * th), tuple(d + n * th)], [tuple(a), tuple(b), tuple(c), tuple(d)]], mat=mat, angle=10.0)
body.append(quad([(0.82, y_(3.2), 1.03), (-0.82, y_(3.2), 1.03), (-0.66, y_(2.8), 1.29), (0.66, y_(2.8), 1.29)], tm2_glass))
body.append(quad([(-0.8, y_(1.12), 1.04), (0.8, y_(1.12), 1.04), (0.66, y_(1.5), 1.28), (-0.66, y_(1.5), 1.28)], tm2_glass))
for sx in (1, -1):
    pts = [(sx * 0.875, y_(1.7), 1.05), (sx * 0.875, y_(3.05), 1.05), (sx * 0.73, y_(2.72), 1.27), (sx * 0.73, y_(1.78), 1.27)]
    body.append(quad(pts if sx > 0 else list(reversed(pts)), tm2_glass))
# the rear wing on its end plates, the riveted rear plate, tail lamps
body.append(T.box((1.96, 0.62, 0.035), loc=(0, y_(0.38), 1.27), rot=(-9, 0, 0), mat=tm2, bevel=0.01))
for sx in (1, -1):
    body.append(T.box((0.04, 0.66, 0.2), loc=(sx * 0.97, y_(0.38), 1.2), rot=(-9, 0, 0), mat=tm2, bevel=0.008))
    body.append(T.box((0.06, 0.12, 0.28), loc=(sx * 0.62, y_(0.62), 1.1), mat=tm2_metal, bevel=0.01))
    body.append(T.box((0.26, 0.03, 0.09), loc=(sx * 0.7, TAIL - 0.005, 0.86), mat=T.glow((0.85, 0.06, 0.04))))
body.append(T.box((1.98, 0.36, 0.33), loc=(0, TAIL + 0.13, 0.615), mat=tm2, bevel=0.02))
for row in range(2):
    for k in range(7):
        body.append(T.sphere(0.022, loc=((k - 3) * 0.3, TAIL - 0.055, 0.53 + row * 0.16), mat=tm2_metal, n=8))
# the nose: a riveted armour plate, the slots over it, two pairs of small square lamps
body.append(T.box((1.9, 0.07, 0.3), loc=(0, NOSE - 0.015, 0.6), rot=(12, 0, 0), mat=tm2, bevel=0.012))
for row in range(2):
    for k in range(8):
        body.append(T.sphere(0.02, loc=((k - 3.5) * 0.24, NOSE + 0.02, 0.53 + row * 0.13), mat=tm2_metal, n=8))
body.append(T.box((1.86, 0.16, 0.05), loc=(0, NOSE - 0.12, 0.775), rot=(-14, 0, 0), mat=tm2, bevel=0.01))   # the slotted strip on the nose
for k in range(11):  # its slots, cut in (dark, flush with the strip)
    body.append(T.box((0.05, 0.11, 0.012), loc=((k - 5) * 0.16, NOSE - 0.12, 0.802), rot=(-14, 0, 0), mat=dark))
for sx in (1, -1):  # two small square lamps at each top corner of the plate
    for k in range(2):
        body.append(T.box((0.1, 0.03, 0.065), loc=(sx * (0.62 + k * 0.13), NOSE + 0.035, 0.7), rot=(12, 0, 0), mat=T.glow((0.9, 0.85, 0.65))))
        body.append(T.box((0.12, 0.03, 0.085), loc=(sx * (0.62 + k * 0.13), NOSE + 0.025, 0.7), rot=(12, 0, 0), mat=dark, bevel=0.006))
# hood scoop with two round intakes, a slotted box ahead of it
body.append(T.box((0.46, 0.85, 0.16), loc=(0, y_(4.15), 1.03), mat=tm2, bevel=0.03))
for sx in (1, -1):
    body.append(T.cyl(0.075, 0.12, loc=(sx * 0.11, y_(4.55), 1.06), rot=(-90, 0, 0), mat=tm2_metal, n=16))
    body.append(T.cyl(0.055, 0.125, loc=(sx * 0.11, y_(4.555), 1.06), rot=(-90, 0, 0), mat=dark, n=16))
body.append(T.box((0.34, 0.22, 0.07), loc=(0, y_(4.85), 0.88), mat=tm2, bevel=0.01))
for k in range(5):
    body.append(T.box((0.03, 0.18, 0.02), loc=((k - 2) * 0.06, y_(4.85), 0.92), mat=dark))
# side pipes along the sills, two slots in each front fender
for sx in (1, -1):
    body.append(rod(V((sx * 1.04, y_(2.2), 0.47)), V((sx * 1.04, y_(3.95), 0.47)), 0.055, tm2_metal))
    body.append(T.cyl(0.07, 0.1, loc=(sx * 1.04, y_(2.15), 0.47), rot=(-90, 0, 0), mat=tm2_metal, n=14))
    body.append(T.cyl(0.05, 0.11, loc=(sx * 1.04, y_(2.14), 0.47), rot=(-90, 0, 0), mat=dark, n=12))
    for k in range(2):
        body.append(T.box((0.03, 0.05, 0.22), loc=(sx * (HW + 0.005), y_(3.62 + k * 0.25), 0.66), mat=dark))
    markers.append(T.marker("m_exh_" + ("r" if sx > 0 else "l"), (sx * 1.04, y_(2.08), 0.47)))
# a gun on each front fender: two brackets, a row of eight shell canisters, a long barrel
for sx in (1, -1):
    x = sx * 0.9
    for d in (3.45, 3.7):
        body.append(T.box((0.08, 0.07, 0.2), loc=(x, y_(d), 1.07), mat=dark, bevel=0.01))
    for k in range(8):
        body.append(T.cyl(0.055, 0.28, loc=(x, y_(3.28 + k * 0.105), 1.27), mat=tm2_metal, n=12))
    body.append(T.box((0.1, 0.86, 0.06), loc=(x, y_(3.65), 1.14), mat=dark, bevel=0.01))
    body.append(rod(V((x, y_(4.08), 1.29)), V((x, y_(4.9), 1.29)), 0.055, gun_steel))
    body.append(T.cyl(0.075, 0.1, loc=(x, y_(4.88), 1.29), rot=(-90, 0, 0), mat=gun_steel, n=14))
    body.append(T.cyl(0.07, 0.12, loc=(x, y_(4.12), 1.29), rot=(-90, 0, 0), mat=gun_steel, n=14))
    markers.append(T.marker("m_gun_" + ("r" if sx > 0 else "l"), (x, y_(4.97), 1.29)))
markers.append(T.marker("m_launcher", (0.0, y_(4.6), 1.15)))
markers.append(T.marker("m_top", (0.0, y_(4.2), 1.05)))
markers.append(T.marker("m_head", (0.0, NOSE + 0.02, 0.7)))

# ---------------------------------------------------------------- wheels: deep-dish slotted rims, tyres with a block tread


def ring_solid(profile, mat, n=28, name="ring"):
    import bmesh
    bm = bmesh.new()
    rings = [[bm.verts.new((x, r * math.cos(2 * math.pi * k / n), r * math.sin(2 * math.pi * k / n))) for k in range(n)] for r, x in profile]
    for i in range(len(rings)):
        a, b = rings[i], rings[(i + 1) % len(rings)]
        for k in range(n):
            bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return T._new_obj(name, bm, mat, (0, 0, 0), (0, 0, 0), 50.0)


def wheel(name, R, w):
    tyre = [(R * 0.68, -w / 2), (R * 0.92, -w / 2), (R * 0.99, -w / 2 + 0.04), (R, -w * 0.25), (R, w * 0.25), (R * 0.99, w / 2 - 0.04),
            (R * 0.92, w / 2), (R * 0.68, w / 2), (R * 0.67, 0.0)]
    parts = [ring_solid(tyre, rubber, 32)]
    for k in range(32):
        a = 2 * math.pi * k / 32
        parts.append(T.box((w * 0.8, 0.05, 0.012), loc=(0, math.cos(a) * (R + 0.002), math.sin(a) * (R + 0.002)), rot=(math.degrees(a) + 90, 0, 0), mat=rubber))
    parts.append(ring_solid([(R * 0.68, -w / 2 + 0.01), (R * 0.68, w / 2 - 0.005), (R * 0.62, w / 2 - 0.012), (R * 0.62, -w / 2 + 0.02)], rim_m, 32))
    parts.append(T.cyl(R * 0.62, 0.02, loc=(w / 2 - 0.09, 0, 0), rot=(0, 90, 0), mat=rim_m, n=28))       # the dish's face, set deep
    for k in range(8):  # its eight slots
        a = 2 * math.pi * k / 8
        parts.append(T.box((0.022, R * 0.22, R * 0.1), loc=(w / 2 - 0.078, math.cos(a) * R * 0.38, math.sin(a) * R * 0.38), rot=(math.degrees(a) + 90, 0, 0), mat=dark))
    parts.append(T.cyl(R * 0.17, 0.06, loc=(w / 2 - 0.06, 0, 0), rot=(0, 90, 0), mat=rim_m, n=16, bevel=0.01))  # centre cap
    return T.join(parts, name)


wheel_f = wheel("wheel_f", RF, 0.28)
wheel_r = wheel("wheel_r", RR, 0.36)
markers += [T.marker("m_wheel_fr", (TF, FA, RF)), T.marker("m_wheel_fl", (-TF, FA, RF)),
            T.marker("m_wheel_rr", (TR, RA, RR)), T.marker("m_wheel_rl", (-TR, RA, RR))]
body_ob = T.join(body, "body")
print("triangles: body %d, wheel_f %d, wheel_r %d" % (T.tri_count([body_ob]), T.tri_count([wheel_f]), T.tri_count([wheel_r])))

if "--shape" in sys.argv:
    out = sys.argv[sys.argv.index("--shape") + 1]
    wf = [T.dup(wheel_f, (TF, FA, RF)), T.dup(wheel_f, (-TF, FA, RF), rot=(0, 0, 180)), T.dup(wheel_r, (TR, RA, RR)), T.dup(wheel_r, (-TR, RA, RR), rot=(0, 0, 180))]
    for o in (wheel_f, wheel_r):
        o.location = (0, 0, -50)
    T.preview(out, size=(1100, 600), eye=(-7.5, 0.0, 1.0), look=(0, 0.0, 0.75), fov=40, samples=12)           # side (left)
    T.preview(out.replace(".png", "_f.png"), size=(1100, 600), eye=(0.0, 8.0, 1.2), look=(0, 0, 0.8), fov=36, samples=12)
    T.preview(out.replace(".png", "_b.png"), size=(1100, 600), eye=(0.0, -8.0, 1.6), look=(0, 0, 0.8), fov=36, samples=12)
    T.preview(out.replace(".png", "_q.png"), size=(1100, 600), eye=(-5.0, 5.5, 3.2), look=(0, 0.2, 0.6), fov=40, samples=12)
    sys.exit(0)

# ---------------------------------------------------------------- bake: the shape here, the paint from the original
import bpy
wheel_f.location = (3.5, 0.9, RF)
wheel_r.location = (3.5, -0.9, RR)
bpy.context.view_layer.update()
for o in (wheel_f, wheel_r):
    T.apply(o)
objs = [body_ob, wheel_f, wheel_r]
T.unwrap(objs, margin=0.002)
if "--nobake" not in sys.argv:
    g = T.gbuffer(objs, size=2048, ao_dist=0.5, bevel_r=0.008, ao_samples=20)
    tris, uvs, tex = T.ps1_reference(RIP, "rk", SCALE)
    print("original: %d triangles" % len(tris))
    print("painted texels:", T.transfer_colors(g, tris, uvs, tex, [tm2, tm2_metal, tm2_glass]))
    al, nm, orm = T.weather(g, decals, seed=29, dust_from=0.0, dust_to=0.01, regions=regions, ao_strength=0.6)
    T.save_maps("roadkill", al, nm, orm)
wheel_f.data.transform(Matrix.Translation((-3.5, -0.9, -RF)))
wheel_r.data.transform(Matrix.Translation((-3.5, 0.9, -RR)))
T.export_glb("roadkill", objs, markers=markers)
print("ok", T.tri_count(objs))

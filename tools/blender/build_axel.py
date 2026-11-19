"""Axel (round 20, owner): TM2's vehicle and TM2's driver, identical, nothing invented.
  Shape: the owner's HD TM2 views (docs/reference/axel F/B/L/R/T/IL/IR.jpeg), measured on a grid from the front
  view at 1.8 m for the man (0.00837 m a pixel): two giant chevron-treaded tyres (r 1.39, 1.18 m wide, centres
  1.31 m out), each hugged on its inside by a tall frame plate carrying the axle; between the plates a platform the
  man stands on, a step at its front, ribs behind; his hands locked in blocks beside his head at the plates' tops.
  The wheel faces: a plain sidewall, a recessed rim with eight lug bolts, a hub with four bolts and a cap.
  Colours (the original TM2 textures in docs/reference/3d_models/tm2_roster_textured_obj.zip, AX-1..6, read by
  eye: the PS1 man is a flat card, so his colours are given per part): black tyres, bronze-silver hubs, black frame,
  red lights on the hand blocks and the plates (AX-3), silver rings at the plates' feet (AX-4); the man bald and
  tanned, red goggles, bare muscled chest and arms with dark straps round the arms, blue jeans, brown boots.
    /tmp/bpy3.13/bin/python tools/blender/build_axel.py              # build, bake, export
    /tmp/bpy3.13/bin/python tools/blender/build_axel.py --shape a.png  # quick look, no bake
Blender space: +Y forward, +Z up. Nodes: body, wheel_r; markers m_wheel_rr/rl, m_gun_l/r, m_launcher, m_top, m_head."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
from grimm_rider import Sculpt, cloth
from mathutils import Matrix, Vector

T.reset()
V = Vector
frame_m = T.M("steel", (0.035, 0.035, 0.038), wear=0.0, rust=0.0, dirt=0.0, rough=0.4)
plate_m = T.M("steel", (0.12, 0.12, 0.125), wear=0.0, rust=0.0, dirt=0.0, rough=0.35)
rubber = T.M("rubber", (0.02, 0.018, 0.02), dirt=0.0)
hub_m = T.M("steel", (0.42, 0.37, 0.3), wear=0.0, rust=0.0, dirt=0.0, rough=0.3)
ring_m = T.M("steel", (0.62, 0.62, 0.6), wear=0.0, rust=0.0, dirt=0.0, rough=0.25)
dark = T.M("steel", (0.012, 0.012, 0.014), wear=0.0, rust=0.0, dirt=0.0)
red = T.glow((0.95, 0.05, 0.03))
skin = T.M("plastic", (0.2, 0.105, 0.05), wear=0.0, dirt=0.0, rough=0.45)
jeans = T.M("cloth", (0.04, 0.085, 0.26), dirt=0.0)
boots = T.M("plastic", (0.2, 0.11, 0.05), wear=0.0, dirt=0.0, rough=0.45)
strap = T.M("plastic", (0.06, 0.04, 0.03), wear=0.0, dirt=0.0, rough=0.5)
goggle = T.glow((0.9, 0.06, 0.04))
decals = []
regions = []
markers = []

R = 1.39            # tyre radius
TW = 1.18           # tyre width
WX = 1.31           # wheel centres across
PX0, PX1 = 0.46, 0.63  # the frame plates' inner and outer faces
PD = 0.36           # their half depth
FEET = 0.4          # platform top: where he stands
body = []


def aim(d):
    q = Vector(d).normalized().to_track_quat("Z", "Y").to_euler()
    return (math.degrees(q.x), math.degrees(q.y), math.degrees(q.z))


def rod(a, b, r, mat, n=12, r2=None):
    a, b = Vector(a), Vector(b)
    v = b - a
    return T.cyl(r, v.length, loc=tuple((a + b) / 2), rot=aim(v), mat=mat, n=n, r2=r2)


# ---------------------------------------------------------------- the frame: two plates, the platform, the hand blocks
for sx in (1, -1):
    xc = sx * (PX0 + PX1) / 2
    # the plate: tall, its front and back edges stepped in at the top (front view: a slim rail)
    body.append(T.prism([(-PD, 0.15), (PD, 0.15), (PD, 1.7), (PD * 0.55, 2.14), (-PD * 0.55, 2.14), (-PD, 1.7)], PX1 - PX0,
                        loc=(xc, 0, 0), mat=frame_m, plane="YZ", bevel=0.02))
    for face in (1, -1):  # ladder slots down its front and back edges
        for k in range(10):
            body.append(T.box((0.1, 0.02, 0.07), loc=(xc, face * (PD + 0.005), 0.38 + k * 0.13), mat=dark))
    for k in range(3):  # the red bar lights low on its front (AX-3)
        body.append(T.box((0.03, 0.02, 0.16), loc=(xc + (k - 1) * 0.045, PD + 0.012, 0.62), mat=red))
    # the axle boss, through to the wheel
    body.append(T.cyl(0.24, 0.14, loc=(sx * (PX1 + 0.05), 0, R), rot=(0, 90, 0), mat=plate_m, n=20, bevel=0.015))
    body.append(T.cyl(0.13, 0.2, loc=(sx * (PX1 + 0.14), 0, R), rot=(0, 90, 0), mat=dark, n=16))
    # the silver ring at the plate's front foot (AX-4): a disc ringed with holes
    rc = V((xc, PD + 0.03, 0.27))
    body.append(T.cyl(0.13, 0.05, loc=tuple(rc), rot=(-90, 0, 0), mat=ring_m, n=20, bevel=0.01))
    for k in range(8):
        a = 2 * math.pi * k / 8
        body.append(T.cyl(0.022, 0.06, loc=tuple(rc + V((math.cos(a) * 0.085, 0.005, math.sin(a) * 0.085))), rot=(-90, 0, 0), mat=dark, n=8))
    body.append(T.cyl(0.04, 0.06, loc=tuple(rc + V((0, 0.005, 0))), rot=(-90, 0, 0), mat=dark, n=10))
    # the hand block beside his head, on an arm from the plate's top; red lights on its face (AX-3)
    hb = V((sx * 0.26, 0.0, 2.0))
    body.append(T.box((0.17, 0.2, 0.17), loc=tuple(hb), mat=plate_m, bevel=0.015))
    body.append(T.box((PX0 - 0.26 + 0.02, 0.1, 0.08), loc=(sx * (0.26 + (PX0 - 0.26) / 2), 0, 2.05), mat=frame_m, bevel=0.01))
    for kz in (0.04, -0.04):
        body.append(T.cyl(0.022, 0.015, loc=tuple(hb + V((sx * 0.0 + 0.0, 0.105, kz))), rot=(-90, 0, 0), mat=red, n=12))
    markers.append(T.marker("m_gun_" + ("r" if sx > 0 else "l"), tuple(hb + V((0, 0.14, 0)))))
# the platform between the plates, a step in front, ribs behind
body.append(T.box((PX0 * 2, PD * 2, FEET - 0.18), loc=(0, 0, (FEET + 0.18) / 2), mat=frame_m, bevel=0.02))
body.append(T.box((PX0 * 2 - 0.1, 0.22, 0.13), loc=(0, PD + 0.1, 0.2), mat=plate_m, bevel=0.015))
for k in range(5):
    body.append(T.box((PX0 * 2 - 0.08, 0.03, 0.03), loc=(0, -PD - 0.015, 0.22 + k * 0.035), mat=plate_m))
body.append(T.box((0.34, 0.24, 0.05), loc=(0, 0.05, FEET + 0.025), mat=plate_m, bevel=0.01))  # the plate under his feet
markers.append(T.marker("m_launcher", (0.0, PD + 0.2, 1.2)))
markers.append(T.marker("m_top", (0.0, 0.0, 1.5)))
markers.append(T.marker("m_head", (0.0, PD + 0.1, 1.0)))

# ---------------------------------------------------------------- the man: one sculpt in TM2's colours
HIP = V((0, 0.0, FEET + 0.95))
CH = V((0, 0.02, FEET + 1.3))
NECK = V((0, 0.0, FEET + 1.52))
skin_s = Sculpt("axel_skin", 0.02)
skin_s.ball(CH, 0.22, (1.15, 0.65, 0.9))                         # the chest, broad
skin_s.ball(CH + V((0, -0.02, -0.18)), 0.18, (1.0, 0.6, 0.9))      # the belly
for sx in (1, -1):
    skin_s.ball(CH + V((sx * 0.1, 0.07, 0.03)), 0.09, (1.1, 0.6, 0.8))  # pectorals
    skin_s.ball(NECK + V((sx * 0.13, -0.02, -0.06)), 0.1)            # trapezius
    sh = NECK + V((sx * 0.25, 0.0, -0.1))
    skin_s.ball(sh, 0.12)                                          # deltoid
    el = V((sx * 0.4, 0.0, FEET + 1.52))
    hand = V((sx * 0.27, 0.0, 2.0))
    skin_s.chain(sh, el, 0.1, 0.085)                               # upper arm out to the elbow
    skin_s.ball(sh.lerp(el, 0.45) + V((0, 0.03, 0)), 0.08)          # biceps
    skin_s.chain(el, hand + V((sx * 0.02, 0, -0.08)), 0.08, 0.06)   # forearm up into the block
skin_s.chain(NECK - V((0, 0, 0.05)), NECK + V((0, 0, 0.1)), 0.085, 0.08)  # neck
HD = NECK + V((0, 0.02, 0.2))
skin_s.ball(HD, 0.12, (0.85, 1.0, 1.1))                          # the bald head
skin_s.ball(HD + V((0, 0.06, -0.08)), 0.07, (1.0, 0.9, 0.8))       # jaw
skin_s.ball(HD + V((0, 0.105, 0.035)), 0.035, (2.4, 0.8, 0.7))     # the brow ridge
skin_s.ball(HD + V((0, 0.125, -0.01)), 0.025, (0.7, 1.0, 1.2))     # nose
for sx in (1, -1):
    skin_s.ball(HD + V((sx * 0.105, -0.0, 0.0)), 0.025, (0.5, 1.0, 1.3))  # ears
body.append(skin_s.mesh(skin, 0.18))
jean = Sculpt("axel_jeans", 0.022)
jean.ball(HIP, 0.19, (1.05, 0.75, 0.75))
for sx in (1, -1):
    hp = HIP + V((sx * 0.1, 0, -0.05))
    kn = V((sx * 0.14, 0.03, FEET + 0.48))
    an = V((sx * 0.16, 0.0, FEET + 0.12))
    jean.chain(hp, kn, 0.11, 0.08)
    jean.chain(kn, an, 0.08, 0.065)
body.append(jean.mesh(jeans, 0.18))
bt = Sculpt("axel_boots", 0.018)
for sx in (1, -1):
    an = V((sx * 0.16, 0.0, FEET + 0.12))
    bt.chain(an + V((0, 0, 0.06)), an + V((0, 0.02, -0.06)), 0.07, 0.072)
    bt.ball(an + V((0, 0.09, -0.07)), 0.07, (0.85, 1.5, 0.6))
body.append(bt.mesh(boots, 0.25))
for sx in (1, -1):  # the dark straps round his upper arms and wrists
    sh = NECK + V((sx * 0.25, 0.0, -0.1))
    el = V((sx * 0.4, 0.0, FEET + 1.52))
    for p, r in ((sh.lerp(el, 0.6), 0.1), (el.lerp(V((sx * 0.27, 0, 2.0)), 0.75), 0.075)):
        d = (el - sh).normalized() if r > 0.09 else (V((sx * 0.27, 0, 2.0)) - el).normalized()
        body.append(T.cyl(r, 0.05, loc=tuple(p), rot=aim(d), mat=strap, n=14))
    body.append(T.cyl(0.026, 0.02, loc=(sx * 0.048, HD.y + 0.135, HD.z + 0.015), rot=(-90, 0, 0), mat=goggle, n=14))     # red goggle lenses
    body.append(T.cyl(0.035, 0.05, loc=(sx * 0.048, HD.y + 0.115, HD.z + 0.015), rot=(-90, 0, 0), mat=dark, n=14))  # their cups
body.append(T.cyl(0.118, 0.03, loc=tuple(HD + V((0, 0.0, 0.015))), mat=strap, n=20))               # the goggle strap round his head
body.append(T.cyl(0.2, 0.05, loc=(0, 0.0, HIP.z + 0.13), mat=strap, n=20))                       # his belt

# ---------------------------------------------------------------- the wheel: a fat chevron tyre, a recessed rim (outer face +X)


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


def wheel(name):
    w = TW
    tyre = [(R * 0.52, -w / 2), (R * 0.8, -w / 2), (R * 0.95, -w / 2 + 0.07), (R, -w / 2 + 0.2), (R, w / 2 - 0.2), (R * 0.95, w / 2 - 0.07),
            (R * 0.8, w / 2), (R * 0.52, w / 2), (R * 0.51, 0.0)]
    parts = [ring_solid(tyre, rubber, 48)]
    # the tread: one row of three chevron grooves built at the top of the tyre, then copied round the axle
    row = []
    for col in (-0.24, 0.0, 0.24):  # kept on the flat of the tread, inside the shoulders
        for half in (1, -1):
            row.append(T.box((w * 0.15, 0.03, 0.008), loc=(col * w + half * w * 0.062, 0.0, R + 0.002), rot=(0, 0, half * 32), mat=dark))
    stripe = T.join(row, "stripe")
    import bpy as _bpy
    copies = [T.dup(stripe, (0, 0, 0), rot=(360.0 * k / 34, 0, 0)) for k in range(34)]
    _bpy.context.view_layer.update()
    for o in copies:
        parts.append(T.apply(o))
    _bpy.data.objects.remove(stripe)
    # the outer face: the rim set in, eight lug bolts round it, a hub with four bolts and a cap
    parts.append(ring_solid([(R * 0.52, w / 2 - 0.02), (R * 0.52, w / 2 - 0.12), (R * 0.47, w / 2 - 0.14), (R * 0.47, w / 2 - 0.03)], hub_m, 40))
    parts.append(T.cyl(R * 0.48, 0.03, loc=(w / 2 - 0.13, 0, 0), rot=(0, 90, 0), mat=hub_m, n=40))
    parts.append(T.cyl(R * 0.36, 0.03, loc=(w / 2 - 0.11, 0, 0), rot=(0, 90, 0), mat=dark, n=36))
    for k in range(8):
        a = 2 * math.pi * k / 8 + 0.2
        parts.append(T.cyl(0.035, 0.05, loc=(w / 2 - 0.11, math.cos(a) * R * 0.41, math.sin(a) * R * 0.41), rot=(0, 90, 0), mat=dark, n=8))
    parts.append(T.cyl(R * 0.2, 0.1, loc=(w / 2 - 0.08, 0, 0), rot=(0, 90, 0), mat=hub_m, n=24, bevel=0.02))
    for k in range(4):
        a = 2 * math.pi * k / 4 + 0.78
        parts.append(T.cyl(0.03, 0.04, loc=(w / 2 - 0.02, math.cos(a) * R * 0.12, math.sin(a) * R * 0.12), rot=(0, 90, 0), mat=dark, n=8))
    parts.append(T.cyl(R * 0.07, 0.06, loc=(w / 2 - 0.01, 0, 0), rot=(0, 90, 0), mat=hub_m, n=14))
    # the inner face: the rim plain, closed by the axle's flange
    parts.append(T.cyl(R * 0.5, 0.03, loc=(-w / 2 + 0.06, 0, 0), rot=(0, 90, 0), mat=dark, n=36))
    return T.join(parts, name)


wheel_r = wheel("wheel_r")
markers += [T.marker("m_wheel_rr", (WX, 0.0, R)), T.marker("m_wheel_rl", (-WX, 0.0, R))]
body_ob = T.join(body, "body")
print("triangles: body %d, wheel %d" % (T.tri_count([body_ob]), T.tri_count([wheel_r])))

if "--shape" in sys.argv:
    out = sys.argv[sys.argv.index("--shape") + 1]
    wf = [T.dup(wheel_r, (WX, 0, R)), T.dup(wheel_r, (-WX, 0, R), rot=(0, 0, 180))]
    wheel_r.location = (0, 0, -50)
    T.preview(out, size=(1000, 800), eye=(0.0, 8.0, 1.6), look=(0, 0, 1.3), fov=38, samples=12)            # front
    T.preview(out.replace(".png", "_q.png"), size=(1000, 800), eye=(4.5, 6.0, 3.5), look=(0, 0, 1.2), fov=38, samples=12)
    T.preview(out.replace(".png", "_b.png"), size=(1000, 800), eye=(-3.0, -7.0, 2.8), look=(0, 0, 1.2), fov=38, samples=12)
    T.preview(out.replace(".png", "_m.png"), size=(900, 900), eye=(0.8, 2.6, 1.9), look=(0, 0, 1.5), fov=36, samples=16)  # the man
    sys.exit(0)

import bpy
wheel_r.location = (4.0, 0.0, R)
bpy.context.view_layer.update()
T.apply(wheel_r)
objs = [body_ob, wheel_r]
T.unwrap(objs, margin=0.002)
if "--nobake" not in sys.argv:
    g = T.gbuffer(objs, size=2048, ao_dist=0.5, bevel_r=0.008, ao_samples=20)
    al, nm, orm = T.weather(g, decals, seed=17, dust_from=0.0, dust_to=0.01, regions=regions, ao_strength=0.6)
    T.save_maps("axel", al, nm, orm)
wheel_r.data.transform(Matrix.Translation((-4.0, 0.0, -R)))
T.export_glb("axel", objs, markers=markers)
print("ok", T.tri_count(objs))

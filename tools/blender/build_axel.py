"""Axel (round 20, owner): TM2's vehicle and TM2's driver, identical, nothing invented.
  Shape: the owner's HD TM2 views (docs/reference/axel F/B/L/R/T/IL/IR.jpeg), measured on a grid from the front
  view at 1.8 m for the man (0.0083 m a pixel) and the top view: two giant chevron-treaded tyres (r 1.39, 1.18 m wide,
  centres 1.31 m out); on each tyre's inside an A-frame of channel bars with ladder rungs (two legs from an apex
  beside his hands down to a front and a back foot, a round bottom member between the feet, a cross member at the hub
  carrying the axle bearing); between the A-frames a platform he stands on with struts to the front feet, an X-braced
  back frame behind him, a black beam over his shoulders carrying the two hand blocks his hands are locked in.
  The wheel faces: a plain sidewall, a recessed rim with eight lug bolts, a hub with four bolts and a cap.
  Colours from the original TM2 textures (docs/reference/3d_models/tm2_roster_textured_obj.zip, measured): black
  tyres (AX-1/2), reddish bronze-grey rims (AX-1), light brass-silver frame bars with dark ladders (hs-0), black
  beam and back frame, two red oval lights on each hand block and three red tail bars at each back foot (AX-3),
  silver six-barrel gatling faces at the front feet (AX-4); the man (AX-5/6): bald, dark brown skin with an oily
  gold sheen, red goggles, dark straps round the upper arms, blue jeans with a dark waistband, brown boots.
    /tmp/bpy3.13/bin/python tools/blender/build_axel.py              # build, bake, export
    /tmp/bpy3.13/bin/python tools/blender/build_axel.py --shape a.png  # quick look, no bake
Blender space: +Y forward, +Z up. Nodes: body, wheel_r; markers m_wheel_rr/rl, m_gun_l/r, m_launcher, m_top, m_head."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
import carkit as K
from grimm_rider import Sculpt
from mathutils import Matrix, Vector

T.reset()
V = Vector
rail_m = T.M("steel", (0.32, 0.28, 0.2), wear=0.0, rust=0.0, dirt=0.0, rough=0.35)    # hs-0's light brass-silver
groove_m = T.M("steel", (0.035, 0.027, 0.014), wear=0.0, rust=0.0, dirt=0.0, rough=0.5)  # hs-0's dark bronze
mech_m = T.M("steel", (0.07, 0.052, 0.026), wear=0.0, rust=0.0, dirt=0.0, rough=0.45)
black = T.M("steel", (0.018, 0.018, 0.02), wear=0.0, rust=0.0, dirt=0.0, rough=0.4)
rubber = T.M("rubber", (0.02, 0.018, 0.02), dirt=0.0)
hub_m = T.M("steel", (0.12, 0.075, 0.06), wear=0.0, rust=0.0, dirt=0.0, rough=0.35)     # AX-1's rim
ring_m = T.M("steel", (0.45, 0.44, 0.42), wear=0.0, rust=0.0, dirt=0.0, rough=0.25)     # AX-4's gatling face
dark = T.M("steel", (0.012, 0.012, 0.014), wear=0.0, rust=0.0, dirt=0.0)
red = T.glow((0.95, 0.05, 0.03))
skin = T.M("plastic", (0.05, 0.022, 0.011), wear=0.0, dirt=0.0, rough=0.3)
jeans = T.M("cloth", (0.044, 0.082, 0.246), dirt=0.0)
boots = T.M("plastic", (0.035, 0.017, 0.008), wear=0.0, dirt=0.0, rough=0.45)
strap = T.M("plastic", (0.02, 0.012, 0.008), wear=0.0, dirt=0.0, rough=0.5)
goggle = T.glow((0.9, 0.06, 0.04))
decals = []
regions = []
markers = []

R = 1.39            # tyre radius
TW = 1.18           # tyre width
WX = 1.31           # wheel centres across
XF = 0.55           # the A-frames' centre planes
FW = 0.2            # their bars' width across
LD = 0.12           # their bars' depth in the frame's plane
APEX = 2.08         # where each frame's legs meet, beside his hands
FOOT_Y, FOOT_Z = 0.86, 0.18  # the front and back feet
FEET = 0.4          # platform top: where he stands
body = []


def channel(xc, a, b, rungs=True):
    """One frame bar in the frame's plane (x = xc) from a = (y, z) to b: two brass flanges, a dark web set in
    between them on both faces, ladder rungs across the web (hs-0's ladders)."""
    a, b = V((xc, a[0], a[1])), V((xc, b[0], b[1]))
    t = b - a
    L = t.length
    th = math.degrees(math.atan2(-t.y, t.z))
    c = (a + b) / 2
    for side in (1, -1):
        body.append(T.box((0.035, LD, L + LD), loc=(xc + side * (FW / 2 - 0.0175), c.y, c.z), rot=(th, 0, 0), mat=rail_m, bevel=0.006))
    body.append(T.box((FW - 0.06, LD * 0.55, L + LD * 0.6), loc=tuple(c), rot=(th, 0, 0), mat=groove_m))
    if rungs:
        n = int(L / 0.1)
        tn = t.normalized()
        for k in range(n):
            p = a + tn * (L * (k + 0.5) / n)
            body.append(T.box((FW - 0.07, LD * 0.62, 0.028), loc=tuple(p), rot=(th, 0, 0), mat=rail_m))


# ---------------------------------------------------------------- the A-frames, the platform, the beam with the hand blocks
for sx in (1, -1):
    xc = sx * XF
    top, front, back = (0.0, APEX), (FOOT_Y, FOOT_Z), (-FOOT_Y, FOOT_Z)
    channel(xc, front, top)
    channel(xc, back, top)
    # the round bottom member between the feet, and the feet
    body.append(T.cyl(0.075, FOOT_Y * 2, loc=(xc, 0, FOOT_Z), rot=(90, 0, 0), mat=rail_m, n=16))
    body.append(T.box((FW + 0.05, 0.22, 0.3), loc=(xc, FOOT_Y + 0.03, FOOT_Z + 0.02), mat=mech_m, bevel=0.015))
    body.append(T.box((FW + 0.05, 0.22, 0.3), loc=(xc, -FOOT_Y - 0.03, FOOT_Z + 0.02), mat=mech_m, bevel=0.015))
    # the gatling face on each front foot (AX-4): six barrels round a hub
    rc = V((xc, FOOT_Y + 0.15, FOOT_Z + 0.03))
    body.append(T.cyl(0.12, 0.06, loc=tuple(rc), rot=(-90, 0, 0), mat=ring_m, n=24, bevel=0.01))
    for k in range(8):
        q = 2 * math.pi * k / 8
        body.append(T.cyl(0.024, 0.07, loc=tuple(rc + V((math.cos(q) * 0.08, 0.005, math.sin(q) * 0.08))), rot=(-90, 0, 0), mat=dark, n=8))
    body.append(T.cyl(0.04, 0.07, loc=tuple(rc + V((0, 0.005, 0))), rot=(-90, 0, 0), mat=dark, n=10))
    markers.append(T.marker("m_gun_" + ("r" if sx > 0 else "l"), tuple(rc + V((0, 0.08, 0)))))
    # three red tail bars on each back foot (AX-3)
    for k in range(3):
        body.append(T.box((0.045, 0.02, 0.17), loc=(xc + (k - 1) * 0.07, -FOOT_Y - 0.15, FOOT_Z + 0.03), mat=red))
    # the cross member at the hub carrying the axle bearing into the wheel
    yl = FOOT_Y * (APEX - R) / (APEX - FOOT_Z)
    body.append(T.box((FW * 0.75, yl * 2, 0.12), loc=(xc, 0, R), mat=rail_m, bevel=0.01))
    body.append(T.cyl(0.16, 0.16, loc=(sx * (XF + FW / 2 + 0.06), 0, R), rot=(0, 90, 0), mat=mech_m, n=20, bevel=0.015))
    body.append(T.cyl(0.08, WX - TW / 2 - XF + 0.05, loc=(sx * (XF + (WX - TW / 2 - XF) / 2 + 0.08), 0, R), rot=(0, 90, 0), mat=dark, n=14))
    # the strut from the platform's front corner down to the front foot
    body.append(T.box((0.06, 0.06, 0.42), loc=(sx * 0.43, 0.7, 0.32), rot=(-62, 0, 0), mat=rail_m, bevel=0.008))
# the black beam over his shoulders between the apexes, the two hand blocks on it (two red oval lights each, AX-3)
body.append(T.box((XF * 2, 0.1, 0.1), loc=(0, -0.17, 2.0), mat=black, bevel=0.01))
for sx in (1, -1):
    hb = V((sx * 0.26, 0.0, 2.0))
    body.append(T.box((0.17, 0.2, 0.17), loc=tuple(hb), mat=black, bevel=0.015))
    body.append(T.box((0.08, 0.1, 0.08), loc=tuple(hb + V((0, -0.12, 0))), mat=black))
    for kz in (0.04, -0.04):
        ov = T.cyl(0.026, 0.012, loc=tuple(hb + V((0, 0.104, kz))), rot=(-90, 0, 0), mat=red, n=14)
        ov.scale = (1.6, 1.0, 1.0)
        body.append(ov)
# the X-braced back frame behind him (the PS1's black board)
BY = -0.3
for sx in (1, -1):
    body.append(T.box((0.06, 0.06, 1.5), loc=(sx * 0.42, BY, FEET + 0.75), mat=black, bevel=0.006))
body.append(T.box((0.9, 0.06, 0.06), loc=(0, BY, FEET + 1.48), mat=black, bevel=0.006))
body.append(T.box((0.9, 0.06, 0.06), loc=(0, BY, FEET + 0.05), mat=black, bevel=0.006))
for sx in (1, -1):
    body.append(K.rod((sx * 0.42, BY, FEET + 0.05), (-sx * 0.42, BY, FEET + 1.48), 0.025, black, n=8))
# the platform between the frames
body.append(T.box(((XF - FW / 2) * 2, 1.1, FEET - 0.16), loc=(0, 0, (FEET + 0.16) / 2), mat=mech_m, bevel=0.02))
body.append(T.box(((XF - FW / 2) * 2 - 0.06, 1.04, 0.03), loc=(0, 0, FEET + 0.0), mat=rail_m, bevel=0.008))
for k in range(9):  # grip ribs on its deck
    body.append(T.box(((XF - FW / 2) * 2 - 0.12, 0.025, 0.02), loc=(0, -0.48 + k * 0.12, FEET + 0.02), mat=groove_m))
body.append(T.box((0.3, 0.18, 0.12), loc=(0, 0.42, FEET + 0.06), mat=mech_m, bevel=0.012))  # the step block before his feet
markers.append(T.marker("m_launcher", (0.0, 0.62, 1.2)))
markers.append(T.marker("m_top", (0.0, 0.0, 1.5)))
markers.append(T.marker("m_head", (0.0, 0.55, 1.0)))

# ---------------------------------------------------------------- the man: sculpted anatomy in TM2's colours
# Heights from his soles (1.8 m): eyes 1.68, chin 1.56, shoulders 1.46, nipples 1.30, navel 1.08, crotch 0.83,
# knees 0.5. A bodybuilder's V: broad lats and deltoids, a narrow waist, six abs; the double-biceps pose of the HD
# views (upper arms out to the frames, forearms up, his fists locked in the blocks beside his head).
def at(x, y, z):
    return V((x, y, FEET + z))


def lean(e, axis):
    """Turn a metaball ellipsoid so its local X runs along `axis`."""
    e.rotation = V((1, 0, 0)).rotation_difference(V(axis).normalized())


skin_s = Sculpt("axel_skin", 0.011)
skin_s.ball(at(0, -0.01, 1.3), 0.16, (1.0, 0.75, 1.05))           # the rib cage
skin_s.ball(at(0, 0.02, 1.13), 0.12, (1.0, 0.62, 1.0))            # the belly, narrower, flat at the back
for sx in (1, -1):
    skin_s.ball(at(sx * 0.075, 0.075, 1.335), 0.085, (1.0, 0.45, 0.7))    # pectorals
    skin_s.ball(at(sx * 0.13, -0.035, 1.25), 0.075, (0.8, 0.95, 1.7))     # lats: the V
    skin_s.ball(at(sx * 0.1, 0.0, 1.06), 0.065, (0.9, 0.9, 0.9))          # obliques over the hips
    skin_s.ball(at(sx * 0.085, -0.03, 1.48), 0.07, (1.0, 0.75, 0.6))      # trapezius, neck to shoulder
    for k, z in enumerate((1.2, 1.135, 1.07)):                          # abs, three pairs
        skin_s.ball(at(sx * 0.036, 0.083, z), 0.03, (1.0, 0.6, 0.85))
    sh = at(sx * 0.19, 0.0, 1.445)                                      # shoulder joint
    el = at(sx * 0.425, -0.015, 1.42)                                   # elbow, against the frame
    wr = at(sx * 0.29, 0.0, 1.58)                                       # wrist, at the block
    skin_s.ball(at(sx * 0.215, 0.0, 1.455), 0.08, (0.9, 0.95, 0.85))     # deltoid cap
    skin_s.chain(sh, el, 0.07, 0.05)                                    # upper arm
    d = el - sh
    lean(skin_s.ball(sh.lerp(el, 0.5) + V((0, 0.02, 0.03)), 0.055, (1.6, 0.9, 1.0)), d)   # biceps, peaked
    lean(skin_s.ball(sh.lerp(el, 0.45) + V((0, -0.03, -0.02)), 0.05, (1.7, 0.9, 0.9)), d)  # triceps
    skin_s.chain(el, wr, 0.05, 0.034)                                   # forearm
    lean(skin_s.ball(el.lerp(wr, 0.3), 0.048, (1.5, 0.9, 0.9)), wr - el)  # its muscle near the elbow
    skin_s.ball(wr + V((sx * -0.01, 0, 0.05)), 0.042, (1.0, 1.0, 1.1))    # the fist, in the block
skin_s.chain(at(0, -0.005, 1.46), at(0, 0.01, 1.58), 0.058, 0.052)     # neck
HD = at(0, 0.0, 1.69)
skin_s.ball(HD, 0.095, (0.82, 1.0, 1.05))                        # the bald cranium
skin_s.ball(at(0, 0.035, 1.615), 0.06, (1.0, 1.0, 0.85))         # face and jaw
skin_s.ball(at(0, 0.07, 1.585), 0.026)                            # chin
skin_s.ball(at(0, 0.075, 1.705), 0.02, (3.0, 1.0, 0.9))           # brow ridge
skin_s.ball(at(0, 0.095, 1.655), 0.016, (1.0, 1.2, 1.6))          # nose
for sx in (1, -1):
    skin_s.ball(at(sx * 0.045, 0.06, 1.655), 0.024)               # cheekbones
    skin_s.ball(at(sx * 0.078, 0.0, 1.665), 0.014, (0.6, 1.4, 2.0))   # ears
body.append(skin_s.mesh(skin, 0.07))
jean = Sculpt("axel_jeans", 0.014)
jean.ball(at(0, -0.01, 0.95), 0.15, (1.05, 0.75, 0.75))           # pelvis
for sx in (1, -1):
    jean.ball(at(sx * 0.07, -0.06, 0.9), 0.075)                   # seat
    hp = at(sx * 0.09, 0.0, 0.9)
    kn = at(sx * 0.125, 0.02, 0.5)
    an = at(sx * 0.135, -0.005, 0.11)
    jean.chain(hp, kn, 0.1, 0.066)                                # thigh
    jean.ball(hp.lerp(kn, 0.4) + V((0, 0.03, 0)), 0.08, (0.9, 0.85, 1.5))   # quadriceps
    jean.chain(kn, an, 0.062, 0.05)                               # shin
    jean.ball(kn.lerp(an, 0.3) + V((0, -0.03, 0)), 0.058, (0.9, 0.9, 1.5))  # calf
    jean.ball(an + V((0, 0.0, 0.03)), 0.055, (1.0, 1.0, 0.6))     # the hem over the boot
body.append(jean.mesh(jeans, 0.09))
bt = Sculpt("axel_boots", 0.012)
for sx in (1, -1):
    an = at(sx * 0.135, -0.005, 0.11)
    bt.chain(an + V((0, 0, 0.02)), an + V((0, 0.0, -0.07)), 0.05, 0.055)
    bt.ball(at(sx * 0.14, 0.07, 0.04), 0.05, (0.9, 1.7, 0.75))   # the foot, toe forward
body.append(bt.mesh(boots, 0.2))
for sx in (1, -1):  # dark straps round his upper arms (AX-5/6) and cuffs where his fists go into the blocks
    sh = at(sx * 0.19, 0.0, 1.445)
    el = at(sx * 0.425, -0.015, 1.42)
    wr = at(sx * 0.29, 0.0, 1.58)
    body.append(T.cyl(0.066, 0.045, loc=tuple(sh.lerp(el, 0.42)), rot=T.aim(el - sh), mat=strap, n=16))
    body.append(T.cyl(0.042, 0.05, loc=tuple(wr), rot=T.aim(wr - el), mat=black, n=14))
    # the goggles: a dark cup round each eye with a red lens inside it
    body.append(T.cyl(0.022, 0.032, loc=tuple(at(sx * 0.034, 0.083, 1.678)), rot=(-90, 0, 0), mat=dark, n=14))
    body.append(T.cyl(0.016, 0.01, loc=tuple(at(sx * 0.034, 0.1, 1.678)), rot=(-90, 0, 0), mat=goggle, n=14))
band = T.cyl(0.083, 0.02, loc=tuple(at(0, 0.0, 1.685)), mat=strap, n=24)   # the goggle strap round his head
band.scale = (0.88, 1.0, 1.0)
body.append(band)
wb = T.cyl(0.155, 0.045, loc=tuple(at(0, -0.005, 1.0)), mat=strap, n=24)  # the jeans' dark waistband
wb.scale = (1.0, 0.76, 1.0)
body.append(wb)

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
    for col in (-0.27, 0.0, 0.27):  # a chevron in each of the three ribs
        for half in (1, -1):
            row.append(T.box((w * 0.14, 0.03, 0.008), loc=(col * w + half * w * 0.058, 0.0, R + 0.002), rot=(0, 0, half * 32), mat=dark))
    stripe = T.join(row, "stripe")
    import bpy as _bpy
    copies = [T.dup(stripe, (0, 0, 0), rot=(360.0 * k / 34, 0, 0)) for k in range(34)]
    _bpy.context.view_layer.update()
    for o in copies:
        parts.append(T.apply(o))
    _bpy.data.objects.remove(stripe)
    for gx in (-0.135, 0.135):  # the two grooves round the tyre between the ribs
        parts.append(ring_solid([(R + 0.003, gx * w - 0.012), (R + 0.003, gx * w + 0.012), (R - 0.01, gx * w + 0.012), (R - 0.01, gx * w - 0.012)], dark, 64))
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
    parts.append(T.cyl(R * 0.1, 0.22, loc=(w / 2 + 0.06, 0, 0), rot=(0, 90, 0), mat=hub_m, n=18, bevel=0.015))  # the cap sticks out (IL view)
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
    if "--man" in sys.argv:  # close-ups of the man alone (front, three-quarter, back)
        T.preview(out.replace(".png", "_mf.png"), size=(900, 1100), eye=(0.0, 3.2, 1.7), look=(0, 0, 1.45), fov=34, samples=20)
        T.preview(out.replace(".png", "_mq.png"), size=(900, 1100), eye=(1.0, 2.2, 2.3), look=(0, 0, 1.6), fov=36, samples=20)
        T.preview(out.replace(".png", "_mb.png"), size=(900, 1100), eye=(0.3, -3.0, 1.9), look=(0, 0, 1.5), fov=34, samples=20)
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

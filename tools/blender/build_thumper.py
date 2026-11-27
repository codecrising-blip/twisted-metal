"""Thumper (round 29): Bruce's lowrider, remade from the owner's design sheet
(docs/reference/owner_sheets/thumper_sheet.webp, "Thumper reimagined": a heavily weaponised '64 lowrider coupe).
  The '64 Impala hardtop shape of round 28 (the owner's HD views, 6.0 m), now dressed as the sheet: deep candy
  purple with a pearl sheen, faded pinstripes and lilac flames on the flanks, road grime and rust low down;
  riveted grey steel plates over the rockers; steel louvres over the back window and the rear side glass; tall
  tail fins with an exhaust pipe in each (the turbo flames come out of them); four chrome side pipes ahead of each
  rear wheel; twin hood scoops; a .50-cal autocannon on each front fender with its ammo belt; quad headlamps (the
  inner pair burning purple); a tubular ram bar over the chrome bumper; the Megafire's two nozzles under the
  bumper (marker m_meta_nozzle between them); chrome wire wheels on thin white walls; three round tail lamps a side.
    /tmp/bpy3.13/bin/python tools/blender/build_thumper.py              # build, bake, export
    /tmp/bpy3.13/bin/python tools/blender/build_thumper.py --shape a.png  # quick look, no bake
Blender space: +Y forward, +Z up. Nodes: body, wheel_f, wheel_r; markers m_wheel_*, m_gun_l/r, m_launcher, m_top,
m_head, m_exh_l/r (the fin pipes), m_meta_nozzle."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
import carkit as K
import numpy as np
from mathutils import Matrix, Vector
from PIL import Image, ImageDraw, ImageFilter

T.reset()
V = Vector
paint = T.M("paint", (0.2, 0.065, 0.4), wear=0.22, rust=0.2, dirt=0.35, rough=0.25, name="th_paint")
chrome = T.M("chrome", (0.75, 0.76, 0.79), wear=0.0, rust=0.15, dirt=0.25)
glassy = T.M("glassy", (0.025, 0.025, 0.03), wear=0.0, rust=0.0, dirt=0.35)
dark = T.M("steel", (0.02, 0.02, 0.022), wear=0.3, rust=0.3, dirt=0.4)
armor = T.M("steel", (0.12, 0.115, 0.11), wear=0.45, rust=0.5, dirt=0.5, rough=0.55, name="th_armor")
gun = T.M("steel", (0.05, 0.05, 0.052), wear=0.3, rust=0.2, dirt=0.3, rough=0.35)
brass = T.M("steel", (0.55, 0.38, 0.12), wear=0.2, rust=0.1, dirt=0.3, rough=0.35)
rubber = T.M("rubber", (0.018, 0.018, 0.018), dirt=0.35)
white = T.M("plastic", (0.62, 0.62, 0.6), wear=0.1, dirt=0.4, rough=0.5)
red_lens = T.glow((0.85, 0.05, 0.04))
lamp = T.glow((0.95, 0.9, 0.72))
purple_lamp = T.glow((0.65, 0.25, 1.0))
markers = []
decals = []

L = 6.0
TAIL, NOSE = -L / 2, L / 2
R = 0.34
RA, FA = -1.39, 2.16
TW = 0.9
HW = 1.13
CR = 0.45
body = []


def y_(d):
    return TAIL + d


# ---------------------------------------------------------------- lower body (side view, tail -> nose)
rows = [(0.0, 1.07, 0.34, 0.9), (0.06, 1.12, 0.24, 0.93), (0.5, HW, 0.18, 0.945), (1.6, HW, 0.17, 0.94), (4.3, HW, 0.17, 0.93),
        (5.0, HW, 0.19, 0.9), (5.6, 1.12, 0.24, 0.86), (5.94, 1.1, 0.3, 0.82), (6.0, 1.06, 0.36, 0.79)]
lb = T.loft([K.section(y_(d), hw, zb, zt, crease=CR, lip=0.03) for (d, hw, zb, zt) in rows], mat=paint, angle=32.0)
for sx in (1, -1):
    T.cut(lb, T.cyl(R + 0.03, 0.7, loc=(sx * (TW + 0.2), FA, 0.24), rot=(0, 90, 0), n=28))
    T.cut(lb, T.cyl(R + 0.03, 0.7, loc=(sx * (TW + 0.2), RA, 0.11), rot=(0, 90, 0), n=28))
body.append(lb)

# ---------------------------------------------------------------- the cabin
cab_rows = [(1.6, 1.07, 1.0, 0.95), (2.33, 1.07, 0.92, 1.47), (2.45, 1.07, 0.91, 1.49), (3.86, 1.07, 0.91, 1.49), (3.98, 1.07, 0.92, 1.47),
            (4.42, 1.07, 1.0, 0.95)]
body.append(T.loft([[(hb, y_(d), 0.92), (ht, y_(d), zt), (-ht, y_(d), zt), (-hb, y_(d), 0.92)] for (d, hb, ht, zt) in cab_rows], mat=paint, angle=30.0))


def on(a, b, t):
    return V(a).lerp(V(b), t)


wb, wt = V((0.0, y_(4.42), 0.95)), V((0.0, y_(3.98), 1.47))
n_ws = V((0.0, 0.52, 0.44)).normalized() * 0.006
p0, p1 = on(wb, wt, 0.05), on(wb, wt, 0.93)
body.append(K.quad([tuple(p0 + V((0.9, 0, 0)) + n_ws), tuple(p0 + V((-0.9, 0, 0)) + n_ws), tuple(p1 + V((-0.83, 0, 0)) + n_ws), tuple(p1 + V((0.83, 0, 0)) + n_ws)], glassy))
# the back window under steel louvres
rb, rt = V((0.0, y_(1.6), 0.95)), V((0.0, y_(2.33), 1.47))
n_rw = V((0.0, -0.52, 0.73)).normalized()
p0, p1 = on(rb, rt, 0.1), on(rb, rt, 0.92)
body.append(K.quad([tuple(p0 + V((-0.84, 0, 0)) + n_rw * 0.006), tuple(p0 + V((0.84, 0, 0)) + n_rw * 0.006), tuple(p1 + V((0.76, 0, 0)) + n_rw * 0.006), tuple(p1 + V((-0.76, 0, 0)) + n_rw * 0.006)], glassy))
slope = math.degrees(math.atan2((rt - rb).z, (rt - rb).y))
for k in range(8):
    p = on(rb, rt, 0.12 + k * 0.105) + n_rw * 0.05
    body.append(T.box((1.72 - k * 0.02, 0.1, 0.012), loc=tuple(p), rot=(slope - 25, 0, 0), mat=armor, bevel=0.004))
for sx in (1, -1):
    body.append(T.box((0.05, 0.9, 0.03), loc=(sx * 0.86, (rb.y + rt.y) / 2, (rb.z + rt.z) / 2 + 0.05), rot=(slope, 0, 0), mat=armor, bevel=0.006))


def side_x(z):
    return 1.07 - (1.07 - 0.91) * (z - 0.92) / (1.49 - 0.92) + 0.006


for sx in (1, -1):
    pts = [(sx * side_x(0.98), y_(2.2), 0.98), (sx * side_x(0.98), y_(4.2), 0.98), (sx * side_x(1.43), y_(3.9), 1.43), (sx * side_x(1.43), y_(2.52), 1.43)]
    body.append(K.quad(pts if sx > 0 else list(reversed(pts)), glassy))
    for k in range(5): # louvres over the rear part of the side glass
        z = 1.02 + k * 0.085
        body.append(T.box((0.03, 0.82, 0.018), loc=(sx * (side_x(z) + 0.03), y_(2.82), z), rot=(0, sx * 20, 0), mat=armor, bevel=0.004))
    body.append(T.box((0.03, 0.03, 0.46), loc=(sx * (side_x(1.2) + 0.03), y_(3.25), 1.2), mat=armor)) # the louvre frame's front post
    body.append(T.box((0.012, 2.3, 0.022), loc=(sx * (side_x(0.95) + 0.004), y_(3.25), 0.955), mat=chrome, bevel=0.004))
    body.append(T.box((0.016, 5.5, 0.03), loc=(sx * (HW + 0.006), y_(3.05), 0.66), mat=chrome, bevel=0.006))
    for d in (2.62, 4.18):
        body.append(T.box((0.008, 0.008, 0.68), loc=(sx * (HW + 0.002), y_(d), 0.58), mat=dark))
    body.append(T.box((0.02, 0.16, 0.025), loc=(sx * (HW + 0.012), y_(3.95), 0.8), mat=chrome, bevel=0.006))
    # side mirror
    body.append(K.rod(V((sx * 1.06, y_(4.25), 1.0)), V((sx * 1.2, y_(4.3), 1.08)), 0.012, chrome, n=6))
    body.append(T.sphere(0.07, loc=(sx * 1.22, y_(4.3), 1.1), mat=chrome, n=12, scale=(0.6, 1.0, 0.8)))
    # riveted grey steel plates over the rocker between the wheels
    body.append(T.box((0.03, 2.9, 0.26), loc=(sx * (HW + 0.012), y_(3.15), 0.32), mat=armor, bevel=0.01))
    for k in range(14):
        body.append(T.sphere(0.018, loc=(sx * (HW + 0.03), y_(1.85 + k * 0.2), 0.42), mat=dark, n=6, scale=(0.5, 1, 1)))
        body.append(T.sphere(0.018, loc=(sx * (HW + 0.03), y_(1.85 + k * 0.2), 0.22), mat=dark, n=6, scale=(0.5, 1, 1)))
    # four chrome side pipes ahead of the rear wheel
    for k in range(4):
        body.append(K.rod(V((sx * (HW - 0.05), y_(2.35), 0.14 + k * 0.0)), V((sx * (HW + 0.08), y_(1.98 - k * 0.11), 0.13)), 0.035, chrome, n=10))
        body.append(T.cyl(0.03, 0.03, loc=(sx * (HW + 0.09), y_(1.96 - k * 0.11), 0.13), rot=(0, 90, 0), mat=dark, n=10))
    # the tail fin: a canted blade along the rear quarter, rising to the tail, a pipe out of its end
    fin_pts = [V((sx * 1.0, y_(1.5), 0.93)), V((sx * 0.98, y_(0.15), 1.16)), V((sx * 0.98, y_(0.0), 1.15)), V((sx * 1.0, y_(0.0), 0.93))]
    body.append(T.loft([[tuple(p + V((sx * -0.035, 0, 0))) for p in fin_pts], [tuple(p + V((sx * 0.035, 0, 0))) for p in fin_pts]], mat=paint, angle=20.0))
    body.append(K.rod(V((sx * 0.99, y_(0.6), 1.02)), V((sx * 0.99, TAIL - 0.12, 1.04)), 0.045, chrome, n=12))
    body.append(T.cyl(0.04, 0.03, loc=(sx * 0.99, TAIL - 0.13, 1.04), rot=(90, 0, 0), mat=dark, n=12))
    markers.append(T.marker("m_exh_" + ("r" if sx > 0 else "l"), (sx * 0.99, TAIL - 0.16, 1.04)))
body.append(T.box((1.75, 0.025, 0.012), loc=(0, y_(2.42), 1.497), mat=chrome))
for sx in (1, -1):  # two sensor pods at the roof's front corners
    body.append(T.cyl(0.05, 0.1, loc=(sx * 0.7, y_(3.78), 1.53), mat=dark, n=10))
    body.append(T.sphere(0.055, loc=(sx * 0.7, y_(3.78), 1.59), mat=T.glow((0.9, 0.2, 0.15)), n=10, scale=(1, 1, 0.6)))

# ---------------------------------------------------------------- front: grille, quad lamps (inner purple), bumper, ram bar
body.append(T.box((2.04, 0.1, 0.34), loc=(0, NOSE - 0.02, 0.6), mat=chrome, bevel=0.02))
for k in range(6):
    body.append(T.box((1.92, 0.012, 0.012), loc=(0, NOSE + 0.032, 0.47 + k * 0.052), mat=dark))
body.append(T.box((0.16, 0.03, 0.1), loc=(0, NOSE + 0.045, 0.62), mat=chrome, bevel=0.01)) # emblem
for sx in (1, -1):
    for lx, lm in ((0.62, purple_lamp), (0.88, lamp)):
        x = sx * lx
        body.append(T.cyl(0.1, 0.05, loc=(x, NOSE + 0.02, 0.62), rot=(-90, 0, 0), mat=chrome, n=20, bevel=0.01))
        body.append(T.cyl(0.082, 0.05, loc=(x, NOSE + 0.025, 0.62), rot=(-90, 0, 0), mat=dark, n=20))
        body.append(T.sphere(0.078, loc=(x, NOSE + 0.04, 0.62), mat=lm, n=16, scale=(1, 0.35, 1)))
    body.append(T.box((0.2, 0.02, 0.05), loc=(sx * 0.73, NOSE + 0.035, 0.47), mat=T.glow((0.95, 0.6, 0.15)), bevel=0.006))
body.append(T.box((2.18, 0.17, 0.16), loc=(0, NOSE + 0.05, 0.34), mat=chrome, bevel=0.05))
for sx in (1, -1):
    body.append(T.box((0.3, 0.14, 0.15), loc=(sx * 1.02, NOSE - 0.1, 0.34), rot=(0, 0, sx * 28), mat=chrome, bevel=0.045))
body.append(T.box((0.5, 0.02, 0.1), loc=(0, NOSE + 0.14, 0.33), mat=dark, bevel=0.005))
# the ram bar: a tube across, two uprights, two guards over the plate, all on brackets to the frame
bar_y = NOSE + 0.3
body.append(K.rod(V((-0.95, bar_y, 0.42)), V((0.95, bar_y, 0.42)), 0.045, armor, n=12))
body.append(K.rod(V((-0.95, bar_y - 0.02, 0.22)), V((0.95, bar_y - 0.02, 0.22)), 0.04, armor, n=12))
for x in (-0.95, -0.28, 0.28, 0.95):
    body.append(K.rod(V((x, bar_y, 0.15)), V((x, bar_y - 0.04, 0.72 if abs(x) < 0.5 else 0.5)), 0.04, armor, n=10))
for x in (-0.6, 0.6):
    body.append(K.rod(V((x, bar_y - 0.02, 0.3)), V((x, NOSE + 0.12, 0.3)), 0.035, armor, n=8))
# the Megafire: two nozzles under the bumper
for sx in (1, -1):
    body.append(T.cyl(0.07, 0.22, loc=(sx * 0.5, NOSE + 0.05, 0.2), rot=(-90, 0, 0), mat=gun, n=14, r2=0.09))
    body.append(T.cyl(0.065, 0.02, loc=(sx * 0.5, NOSE + 0.165, 0.2), rot=(-90, 0, 0), mat=dark, n=14))
markers.append(T.marker("m_meta_nozzle", (0.0, NOSE + 0.32, 0.32)))
# hood: twin scoops
for sx in (1, -1):
    body.append(T.box((0.42, 0.85, 0.12), loc=(sx * 0.36, y_(5.0), 0.94), rot=(-4.5, 0, 0), mat=paint, bevel=0.03, taper=(0.82, 1.0)))
    body.append(T.box((0.34, 0.03, 0.07), loc=(sx * 0.36, y_(5.43), 0.95), rot=(-4.5, 0, 0), mat=dark, bevel=0.008))
body.append(T.box((1.7, 0.05, 0.012), loc=(0, y_(4.48), 0.935), mat=dark))

# ---------------------------------------------------------------- .50-cal autocannons on the front fenders
for sx in (1, -1):
    x = sx * 0.92
    body.append(T.box((0.16, 0.24, 0.12), loc=(x, y_(4.55), 0.98), mat=armor, bevel=0.01))  # pintle base
    body.append(T.box((0.2, 0.62, 0.2), loc=(x, y_(4.75), 1.12), mat=gun, bevel=0.015))    # receiver
    body.append(T.box((0.06, 0.2, 0.12), loc=(x, y_(4.42), 1.14), mat=gun, bevel=0.01))     # grips at the back
    body.append(K.rod(V((x, y_(5.04), 1.15)), V((x, y_(5.6), 1.15)), 0.055, gun, n=12))     # perforated jacket
    for k in range(5):
        a = k * 72
        body.append(T.cyl(0.012, 0.02, loc=(x + math.cos(math.radians(a)) * 0.056, y_(5.15 + k * 0.08), 1.15 + math.sin(math.radians(a)) * 0.056), rot=T.aim((math.cos(math.radians(a)), 0, math.sin(math.radians(a)))), mat=dark, n=6))
    body.append(K.rod(V((x, y_(5.6), 1.15)), V((x, NOSE + 0.25, 1.15)), 0.028, gun, n=10))  # barrel past the nose
    body.append(T.cyl(0.045, 0.1, loc=(x, NOSE + 0.2, 1.15), rot=(-90, 0, 0), mat=gun, n=12))  # muzzle brake
    body.append(T.box((0.14, 0.2, 0.14), loc=(x - sx * 0.17, y_(4.72), 1.06), mat=armor, bevel=0.01))  # ammo can
    for k in range(6):  # the belt from the can into the receiver
        body.append(T.box((0.06, 0.03, 0.05), loc=(x - sx * (0.12 - k * 0.012), y_(4.82 + k * 0.012), 1.12 + k * 0.012), rot=(0, 0, sx * 20), mat=brass))
    markers.append(T.marker("m_gun_" + ("r" if sx > 0 else "l"), (x, NOSE + 0.3, 1.15)))

# ---------------------------------------------------------------- rear: three round tail lamps a side, bumper, plate
for sx in (1, -1):
    for k in range(3):
        cx = sx * (0.42 + k * 0.2)
        body.append(T.cyl(0.075, 0.04, loc=(cx, TAIL - 0.005, 0.72), rot=(90, 0, 0), mat=chrome, n=16, bevel=0.008))
        body.append(T.sphere(0.06, loc=(cx, TAIL - 0.03, 0.72), mat=red_lens, n=12, scale=(1, 0.4, 1)))
body.append(T.box((2.18, 0.17, 0.17), loc=(0, TAIL - 0.05, 0.34), mat=chrome, bevel=0.05))
body.append(T.box((0.56, 0.02, 0.12), loc=(0, TAIL - 0.14, 0.34), mat=dark, bevel=0.005))
body.append(T.box((1.4, 0.012, 0.012), loc=(0, TAIL - 0.005, 0.86), mat=chrome))

markers.append(T.marker("m_launcher", (0.0, y_(4.0), 1.0)))
markers.append(T.marker("m_top", (0.0, y_(3.1), 1.5)))
markers.append(T.marker("m_head", (0.0, NOSE + 0.05, 0.62)))


# ---------------------------------------------------------------- paintwork: faded pinstripes and lilac flames
def flames_image(w=1200, h=300, seed=3):
    """Flame tongues licking back from the front, outlined thin in magenta (sheet: faded flame decals)."""
    rng = np.random.default_rng(seed)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for k in range(7):
        y0 = int(h * (0.18 + 0.1 * k))
        length = int(w * rng.uniform(0.45, 0.95))
        pts = [(w, y0 - 18), (w - 40, y0 - 22)]
        steps = 14
        for i in range(steps + 1):
            t = i / steps
            x = w - 40 - t * length
            wob = math.sin(t * 7.0 + k) * 14 * t
            pts.append((x, y0 + wob - 16 * (1 - t)))
        for i in range(steps, -1, -1):
            t = i / steps
            x = w - 40 - t * length
            wob = math.sin(t * 7.0 + k) * 14 * t
            pts.append((x, y0 + wob + 16 * (1 - t) + 4))
        pts.append((w, y0 + 22))
        d.polygon(pts, fill=(168, 110, 214, 215), outline=(235, 80, 205, 255))
    im = im.filter(ImageFilter.GaussianBlur(1.2))
    return im


for sx in (1, -1):
    decals.append(T.Decal(flames_image(seed=3 + sx), (sx * HW, y_(4.3), 0.66), (sx, 0, 0), (0, 0, 1), (3.0, 0.62), depth=0.06, kinds=("paint",), opacity=0.75))
    decals.append(T.Decal(T.flat_image((0.75, 0.65, 0.85), 0.8, (64, 4)), (sx * HW, y_(3.0), 0.88), (sx, 0, 0), (0, 0, 1), (5.6, 0.012), depth=0.05, kinds=("paint",)))

# ---------------------------------------------------------------- wheels
wheel_f = K.wire_wheel("wheel_f", R, 0.24, rubber, white, chrome, dark)
wheel_r = K.wire_wheel("wheel_r", R, 0.24, rubber, white, chrome, dark)
markers += [T.marker("m_wheel_fr", (TW, FA, R)), T.marker("m_wheel_fl", (-TW, FA, R)),
            T.marker("m_wheel_rr", (TW, RA, R)), T.marker("m_wheel_rl", (-TW, RA, R))]
body_ob = T.join(body, "body")
print("triangles: body %d, wheel %d" % (T.tri_count([body_ob]), T.tri_count([wheel_f])))

if "--shape" in sys.argv:
    out = sys.argv[sys.argv.index("--shape") + 1]
    wf = [T.dup(wheel_f, (TW, FA, R)), T.dup(wheel_f, (-TW, FA, R), rot=(0, 0, 180)), T.dup(wheel_r, (TW, RA, R)), T.dup(wheel_r, (-TW, RA, R), rot=(0, 0, 180))]
    for o in (wheel_f, wheel_r):
        o.location = (0, 0, -50)
    T.preview(out, size=(1100, 600), eye=(-10.5, 0.0, 0.9), look=(0, 0.0, 0.7), fov=40, samples=12)
    T.preview(out.replace(".png", "_f.png"), size=(1100, 600), eye=(0.0, 9.0, 1.3), look=(0, 0, 0.75), fov=34, samples=12)
    T.preview(out.replace(".png", "_b.png"), size=(1100, 600), eye=(-4.0, -8.0, 2.4), look=(0, 0, 0.75), fov=36, samples=12)
    T.preview(out.replace(".png", "_q.png"), size=(1100, 600), eye=(-5.5, 6.0, 3.0), look=(0, 0.3, 0.6), fov=40, samples=12)
    sys.exit(0)

import bpy
wheel_f.location = (3.5, 0.9, R)
wheel_r.location = (3.5, -0.9, R)
bpy.context.view_layer.update()
for o in (wheel_f, wheel_r):
    T.apply(o)
objs = [body_ob, wheel_f, wheel_r]
T.unwrap(objs, margin=0.002)
if "--nobake" not in sys.argv:
    g = T.gbuffer(objs, size=2048, ao_dist=0.5, bevel_r=0.008, ao_samples=20)
    al, nm, orm = T.weather(g, decals, seed=31, dust_from=0.0, dust_to=0.55, regions=[], ao_strength=0.65)
    T.save_maps("thumper", al, nm, orm)
wheel_f.data.transform(Matrix.Translation((-3.5, -0.9, -R)))
wheel_r.data.transform(Matrix.Translation((-3.5, 0.9, -R)))
T.export_glb("thumper", objs, markers=markers)
print("ok", T.tri_count(objs))

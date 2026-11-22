"""Thumper (round 28): Bruce's lowrider, TM3 (owner's roster table: vehicle from TM3).
  Shape: the owner's HD views (docs/reference/thumper S/F/B/T/IL/IR.jpeg, a '64 Impala hardtop) measured on the
  side view at 6.0 m long (rip x25): long low body with a crease above the rocker, rear wheels half under skirts,
  front wheels in shallow arches, a formal roof with a broad sloping C-pillar, long flat deck, louvred tail lamps,
  chrome bumpers. TM3's own look over it (docs/reference/ThumperTM3Render.webp): deep purple paint, a dark navy
  vinyl top, a full-width chrome grille with quad round headlamps, a raised panel on the hood, a chrome strip
  along each side, wire wheels with white walls, and TM3's two gun boxes on the hood with long barrels.
  Clean, no wear (owner: TM cars identical, "our touch" later).
  The Megafire flame comes out of the grille (marker m_meta_nozzle), no part invented for it.
  Drive-By crew (round 28 secondary): two sculpted crewmen (nodes gunman_l / gunman_r, hidden in the game until
  the Drive-By, pivot markers m_gunman_l / m_gunman_r on the door sills).
    /tmp/bpy3.13/bin/python tools/blender/build_thumper.py              # build, bake, export
    /tmp/bpy3.13/bin/python tools/blender/build_thumper.py --shape a.png  # quick look, no bake
Blender space: +Y forward, +Z up. Nodes: body, wheel_f, wheel_r, gunman_l, gunman_r; markers m_wheel_*, m_gun_l/r,
m_launcher, m_top, m_head, m_exh_l/r, m_meta_nozzle, m_gunman_l/r."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
import carkit as K
from mathutils import Matrix, Vector

T.reset()
V = Vector
paint = T.M("paint", (0.2, 0.016, 0.19), wear=0.0, rust=0.0, dirt=0.0, rough=0.32, name="th_paint")
vinyl = T.M("plastic", (0.008, 0.009, 0.03), wear=0.0, dirt=0.0, rough=0.8, name="th_vinyl")
chrome = T.M("chrome", (0.78, 0.79, 0.82), wear=0.0, rust=0.0, dirt=0.0)
glassy = T.M("glassy", (0.03, 0.032, 0.036), wear=0.0, rust=0.0, dirt=0.0)
dark = T.M("steel", (0.02, 0.02, 0.022), wear=0.0, rust=0.0, dirt=0.0)
gunbox = T.M("steel", (0.15, 0.148, 0.15), wear=0.0, rust=0.0, dirt=0.0, rough=0.45)
barrel = T.M("steel", (0.05, 0.05, 0.052), wear=0.0, rust=0.0, dirt=0.0, rough=0.35)
rubber = T.M("rubber", (0.018, 0.018, 0.018), dirt=0.0)
white = T.M("plastic", (0.72, 0.72, 0.69), wear=0.0, dirt=0.0, rough=0.5)
red_lens = T.glow((0.85, 0.05, 0.04))
lamp = T.glow((0.95, 0.9, 0.72))
crew_mats = (T.M("cloth", (0.045, 0.045, 0.05), dirt=0.0), T.M("plastic", (0.26, 0.14, 0.08), wear=0.0, dirt=0.0, rough=0.6),
             T.M("cloth", (0.012, 0.012, 0.012), dirt=0.0), T.M("cloth", (0.28, 0.02, 0.02), dirt=0.0), barrel)
markers = []

L = 6.0
TAIL, NOSE = -L / 2, L / 2
R = 0.34                       # wheel radius (HD side view)
RA, FA = -1.39, 2.16           # axles
TW = 0.9                       # wheel centres across
HW = 1.13                      # body half width
CR = 0.45                      # the crease over the rocker
body = []


def y_(d):
    return TAIL + d


# ---------------------------------------------------------------- lower body (side view, tail -> nose)
rows = [(0.0, 1.07, 0.34, 0.9), (0.06, 1.12, 0.24, 0.93), (0.5, HW, 0.18, 0.945), (1.6, HW, 0.17, 0.94), (4.3, HW, 0.17, 0.93),
        (5.0, HW, 0.19, 0.9), (5.6, 1.12, 0.24, 0.86), (5.94, 1.1, 0.3, 0.82), (6.0, 1.06, 0.36, 0.79)]
lb = T.loft([K.section(y_(d), hw, zb, zt, crease=CR, lip=0.03) for (d, hw, zb, zt) in rows], mat=paint, angle=32.0)
for sx in (1, -1):  # front arches shallow, the rear ones mostly skirted (a lowrider sits on its wheels)
    T.cut(lb, T.cyl(R + 0.03, 0.7, loc=(sx * (TW + 0.2), FA, 0.24), rot=(0, 90, 0), n=28))
    T.cut(lb, T.cyl(R + 0.03, 0.7, loc=(sx * (TW + 0.2), RA, 0.11), rot=(0, 90, 0), n=28))
body.append(lb)

# ---------------------------------------------------------------- the cabin: formal hardtop roof, broad C-pillar
cab_rows = [(1.6, 1.07, 1.0, 0.95), (2.33, 1.07, 0.92, 1.47), (2.45, 1.07, 0.91, 1.49), (3.86, 1.07, 0.91, 1.49), (3.98, 1.07, 0.92, 1.47),
            (4.42, 1.07, 1.0, 0.95)]
cab = [[(hb, y_(d), 0.92), (ht, y_(d), zt), (-ht, y_(d), zt), (-hb, y_(d), 0.92)] for (d, hb, ht, zt) in cab_rows]
body.append(T.loft(cab, mat=paint, angle=30.0))


def on(a, b, t):
    return V(a).lerp(V(b), t)


# windshield on the face between (d 3.98, top) and (d 4.42, base); rear window on (1.6 base) .. (2.33 top)
wb, wt = V((0.0, y_(4.42), 0.95)), V((0.0, y_(3.98), 1.47))
n_ws = V((0.0, 0.52, 0.44)).normalized() * 0.006
p0, p1 = on(wb, wt, 0.05), on(wb, wt, 0.93)
body.append(K.quad([tuple(p0 + V((0.9, 0, 0)) + n_ws), tuple(p0 + V((-0.9, 0, 0)) + n_ws), tuple(p1 + V((-0.83, 0, 0)) + n_ws), tuple(p1 + V((0.83, 0, 0)) + n_ws)], glassy))
rb, rt = V((0.0, y_(1.6), 0.95)), V((0.0, y_(2.33), 1.47))
n_rw = V((0.0, -0.52, 0.73)).normalized() * 0.006
p0, p1 = on(rb, rt, 0.1), on(rb, rt, 0.92)
body.append(K.quad([tuple(p0 + V((-0.84, 0, 0)) + n_rw), tuple(p0 + V((0.84, 0, 0)) + n_rw), tuple(p1 + V((0.76, 0, 0)) + n_rw), tuple(p1 + V((-0.76, 0, 0)) + n_rw)], glassy))


def side_x(z):
    return 1.07 - (1.07 - 0.91) * (z - 0.92) / (1.49 - 0.92) + 0.006


for sx in (1, -1):
    pts = [(sx * side_x(0.98), y_(2.2), 0.98), (sx * side_x(0.98), y_(4.2), 0.98), (sx * side_x(1.43), y_(3.9), 1.43), (sx * side_x(1.43), y_(2.52), 1.43)]
    body.append(K.quad(pts if sx > 0 else list(reversed(pts)), glassy))
    body.append(T.box((0.012, 2.3, 0.022), loc=(sx * (side_x(0.95) + 0.004), y_(3.25), 0.955), mat=chrome, bevel=0.004))   # window sill trim
    body.append(T.box((0.016, 5.5, 0.03), loc=(sx * (HW + 0.006), y_(3.05), 0.66), mat=chrome, bevel=0.006))               # the side strip
    for d in (2.62, 4.18):  # door seams
        body.append(T.box((0.008, 0.008, 0.68), loc=(sx * (HW + 0.002), y_(d), 0.58), mat=dark))
    body.append(T.box((0.02, 0.16, 0.025), loc=(sx * (HW + 0.012), y_(3.95), 0.8), mat=chrome, bevel=0.006))   # door handle
# the vinyl top over the roof
body.append(K.quad([(-0.89, y_(2.42), 1.496), (0.89, y_(2.42), 1.496), (0.89, y_(3.9), 1.496), (-0.89, y_(3.9), 1.496)], vinyl, th=0.01))
body.append(T.box((1.75, 0.025, 0.012), loc=(0, y_(2.42), 1.497), mat=chrome))

# ---------------------------------------------------------------- front: full-width chrome grille, quad lamps, bumper
body.append(T.box((2.04, 0.1, 0.34), loc=(0, NOSE - 0.02, 0.6), mat=chrome, bevel=0.02))
for k in range(6):  # the grille's horizontal ribs run the full width, behind the lamps
    body.append(T.box((1.92, 0.012, 0.012), loc=(0, NOSE + 0.032, 0.47 + k * 0.052), mat=dark))
for sx in (1, -1):
    for lx in (0.6, 0.86):
        x = sx * lx
        body.append(T.cyl(0.1, 0.05, loc=(x, NOSE + 0.02, 0.62), rot=(-90, 0, 0), mat=chrome, n=20, bevel=0.01))   # bezel
        body.append(T.cyl(0.082, 0.05, loc=(x, NOSE + 0.025, 0.62), rot=(-90, 0, 0), mat=dark, n=20))
        body.append(T.sphere(0.078, loc=(x, NOSE + 0.04, 0.62), mat=lamp, n=16, scale=(1, 0.35, 1)))
    body.append(T.box((0.2, 0.02, 0.05), loc=(sx * 0.73, NOSE + 0.035, 0.47), mat=T.glow((0.95, 0.6, 0.15)), bevel=0.006))  # park lamps
body.append(T.box((2.18, 0.17, 0.16), loc=(0, NOSE + 0.05, 0.34), mat=chrome, bevel=0.05))
for sx in (1, -1):
    body.append(T.box((0.3, 0.14, 0.15), loc=(sx * 1.02, NOSE - 0.1, 0.34), rot=(0, 0, sx * 28), mat=chrome, bevel=0.045))
body.append(T.box((0.5, 0.02, 0.1), loc=(0, NOSE + 0.14, 0.33), mat=dark, bevel=0.005))
# the raised panel on the hood
body.append(T.box((0.78, 1.15, 0.04), loc=(0, y_(5.15), 0.91), rot=(-4.5, 0, 0), mat=paint, bevel=0.015, taper=(0.86, 1.0)))
body.append(T.box((1.7, 0.05, 0.012), loc=(0, y_(4.48), 0.935), mat=dark))   # cowl vent at the windshield's foot

# ---------------------------------------------------------------- TM3's guns: a box each side of the hood, long barrels
for sx in (1, -1):
    x = sx * 0.6
    body.append(T.box((0.36, 0.56, 0.26), loc=(x, y_(4.72), 1.05), mat=gunbox, bevel=0.025))
    body.append(T.box((0.3, 0.3, 0.06), loc=(x, y_(4.66), 1.2), mat=gunbox, bevel=0.015))
    for k in range(3):  # its panel lines and vents
        body.append(T.box((0.006, 0.08, 0.06), loc=(x + sx * 0.181, y_(4.55 + k * 0.12), 1.06), mat=dark))
        body.append(T.box((0.006, 0.08, 0.06), loc=(x - sx * 0.181, y_(4.55 + k * 0.12), 1.06), mat=dark))
    body.append(T.box((0.24, 0.012, 0.14), loc=(x, y_(5.003), 1.06), mat=dark))
    body.append(K.rod(V((x, y_(4.98), 1.09)), V((x, y_(6.02), 1.09)), 0.04, barrel, n=12))
    body.append(T.cyl(0.055, 0.12, loc=(x, y_(5.04), 1.09), rot=(-90, 0, 0), mat=barrel, n=12))
    body.append(T.cyl(0.05, 0.06, loc=(x, y_(5.99), 1.09), rot=(-90, 0, 0), mat=barrel, n=12))
    markers.append(T.marker("m_gun_" + ("r" if sx > 0 else "l"), (x, y_(6.05), 1.09)))

# ---------------------------------------------------------------- rear: louvred tail lamps, bumper, plate
for sx in (1, -1):
    for cx, w, n in ((0.8, 0.42, 6), (0.47, 0.16, 3)):
        body.append(T.box((w + 0.04, 0.03, 0.2), loc=(sx * cx, TAIL - 0.01, 0.72), mat=chrome, bevel=0.01))
        body.append(T.box((w, 0.03, 0.16), loc=(sx * cx, TAIL - 0.02, 0.72), mat=red_lens))
        for k in range(n):
            body.append(T.box((0.014, 0.04, 0.16), loc=(sx * (cx - w / 2 + (k + 0.5) * w / n), TAIL - 0.035, 0.72), mat=chrome))
body.append(T.box((2.18, 0.17, 0.17), loc=(0, TAIL - 0.05, 0.34), mat=chrome, bevel=0.05))
body.append(T.box((0.56, 0.02, 0.12), loc=(0, TAIL - 0.14, 0.34), mat=dark, bevel=0.005))
body.append(T.box((1.4, 0.012, 0.012), loc=(0, TAIL - 0.005, 0.86), mat=chrome))   # deck lid edge trim

markers.append(T.marker("m_meta_nozzle", (0.0, NOSE + 0.12, 0.6)))
markers.append(T.marker("m_launcher", (0.0, y_(4.0), 1.0)))
markers.append(T.marker("m_top", (0.0, y_(3.1), 1.5)))
markers.append(T.marker("m_head", (0.0, NOSE + 0.05, 0.62)))
for sx in (1, -1):
    markers.append(T.marker("m_exh_" + ("r" if sx > 0 else "l"), (sx * 0.55, TAIL - 0.05, 0.18)))
    body.append(K.rod(V((sx * 0.55, TAIL + 0.1, 0.18)), V((sx * 0.55, TAIL - 0.06, 0.18)), 0.04, chrome, n=12))

# ---------------------------------------------------------------- wheels and crew
wheel_f = K.wire_wheel("wheel_f", R, 0.24, rubber, white, chrome, dark)
wheel_r = K.wire_wheel("wheel_r", R, 0.24, rubber, white, chrome, dark)
markers += [T.marker("m_wheel_fr", (TW, FA, R)), T.marker("m_wheel_fl", (-TW, FA, R)),
            T.marker("m_wheel_rr", (TW, RA, R)), T.marker("m_wheel_rl", (-TW, RA, R))]
crew = []
for sx in (1, -1):
    nm = "gunman_" + ("r" if sx > 0 else "l")
    at = (sx * 0.86, y_(3.2), 0.93)
    crew.append(K.crewman(nm, at, sx, crew_mats))
    markers.append(T.marker("m_" + nm, at))
body_ob = T.join(body, "body")
print("triangles: body %d, wheel %d, crew %d" % (T.tri_count([body_ob]), T.tri_count([wheel_f]), T.tri_count(crew)))

if "--shape" in sys.argv:
    out = sys.argv[sys.argv.index("--shape") + 1]
    wf = [T.dup(wheel_f, (TW, FA, R)), T.dup(wheel_f, (-TW, FA, R), rot=(0, 0, 180)), T.dup(wheel_r, (TW, RA, R)), T.dup(wheel_r, (-TW, RA, R), rot=(0, 0, 180))]
    for o in (wheel_f, wheel_r):
        o.location = (0, 0, -50)
    if "--crew" not in sys.argv:
        for o in crew:
            o.location = (0, 0, -50)
    else:
        for o in crew:
            o.location = (o.location.x + (0.35 if o.name.endswith("r") else -0.35), 0, 0)
    T.preview(out, size=(1100, 600), eye=(-10.5, 0.0, 0.9), look=(0, 0.0, 0.7), fov=40, samples=12)
    T.preview(out.replace(".png", "_f.png"), size=(1100, 600), eye=(0.0, 9.0, 1.3), look=(0, 0, 0.75), fov=34, samples=12)
    T.preview(out.replace(".png", "_b.png"), size=(1100, 600), eye=(0.0, -9.0, 1.7), look=(0, 0, 0.75), fov=34, samples=12)
    T.preview(out.replace(".png", "_q.png"), size=(1100, 600), eye=(-5.5, 6.0, 3.4), look=(0, 0.3, 0.6), fov=40, samples=12)
    sys.exit(0)

# ---------------------------------------------------------------- bake and export
import bpy
wheel_f.location = (3.5, 0.9, R)
wheel_r.location = (3.5, -0.9, R)
bpy.context.view_layer.update()
for o in (wheel_f, wheel_r):
    T.apply(o)
objs = [body_ob, wheel_f, wheel_r] + crew
T.unwrap(objs, margin=0.002)
if "--nobake" not in sys.argv:
    g = T.gbuffer(objs, size=2048, ao_dist=0.5, bevel_r=0.008, ao_samples=20)
    al, nm, orm = T.weather(g, [], seed=31, dust_from=0.0, dust_to=0.01, regions=[], ao_strength=0.6)
    T.save_maps("thumper", al, nm, orm)
wheel_f.data.transform(Matrix.Translation((-3.5, -0.9, -R)))
wheel_r.data.transform(Matrix.Translation((-3.5, 0.9, -R)))
T.export_glb("thumper", objs, markers=markers)
print("ok", T.tri_count(objs))

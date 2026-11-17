"""Outlaw's wheel clamp, four looks for the owner to pick from (round 19: "bigger, brighter, more
noticeable"). Each one is built round a wheel of radius 0.5 m and 0.38 m wide, centred on the wheel's
centre: axle along X, the clamp's face on +X (the outside of a right-hand wheel), +Y forward, +Z up.
Godot scales it to the car's wheel and mirrors it for a left wheel (WheelClamp.attach).
    /tmp/bpy3.13/bin/python tools/blender/build_wheel_clamps.py              # build, bake, export
    /tmp/bpy3.13/bin/python tools/blender/build_wheel_clamps.py --shape a.png  # quick looks, no bake
  A  DENVER BOOT: the classic safety-yellow boot, a ring of red and white reflectors, two arms over the
     tyre, a padlock, a red lamp on top
  B  BEAR TRAP: hazard-striped steel jaws bitten into the tread, springs, a chain dragging a spiked weight
  C  POLICE LOCK: Outlaw's own: white plate, black rim, gold star, IMPOUND, red and blue lamps
  D  SPIKED RING: a heavy yellow ring with spikes driven into the tyre, hooks over the tread, an amber
     beacon in a cage
Writes assets/models/wheel_clamps.glb: nodes clamp_a..d (baked) and their lamps (glow, separate so the
game can blink them): lamp_a, lamp_b, lamp_c_red, lamp_c_blue, lamp_d."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
from mathutils import Matrix, Vector

T.reset()
V = Vector
R = 0.5   # the wheel
FACE = 0.25  # x of the clamp's plate: just outside the tyre's sidewall
yellow = T.M("paint", (0.8, 0.52, 0.012), wear=0.35, rust=0.25, dirt=0.35)
white = T.M("paint", (0.62, 0.62, 0.59), wear=0.35, rust=0.2, dirt=0.4)
black = T.M("paint", (0.02, 0.02, 0.022), wear=0.4, rust=0.2, dirt=0.4)
dark = T.M("steel", (0.03, 0.03, 0.033), wear=0.5, rust=0.4, dirt=0.5)
bare = T.M("steel", (0.2, 0.2, 0.2), wear=0.4, rust=0.35, dirt=0.4)
gold = T.M("steel", (0.55, 0.38, 0.08), wear=0.3, rust=0.1, dirt=0.3)
g_red = T.glow((1.0, 0.06, 0.03))
g_white = T.glow((1.0, 0.95, 0.85))
g_blue = T.glow((0.1, 0.3, 1.0))
g_amber = T.glow((1.0, 0.5, 0.02))
decals = []


def aim(d):
    q = Vector(d).normalized().to_track_quat("Z", "Y").to_euler()
    return (math.degrees(q.x), math.degrees(q.y), math.degrees(q.z))


def rod(a, b, r, mat, n=10):
    a, b = Vector(a), Vector(b)
    v = b - a
    return T.cyl(r, v.length, loc=tuple((a + b) / 2), rot=aim(v), mat=mat, n=n)


def bar(a, b, w, d, mat, bevel=0.008):
    a, b = Vector(a), Vector(b)
    v = b - a
    return T.box((w, d, v.length), loc=tuple((a + b) / 2), rot=aim(v), mat=mat, bevel=bevel)


def spike(base, d, length, r, mat=bare, n=8):
    d = Vector(d).normalized()
    return T.cyl(r, length, loc=tuple(Vector(base) + d * length / 2), rot=aim(d), mat=mat, n=n, r2=r * 0.08)


def ring(x, radius, r, mat, n=28, a0=0.0, a1=360.0):
    """A pipe bent round the axle (in the YZ plane at x), from angle a0 to a1 (0 = forward, 90 = up)."""
    pts = []
    steps = max(3, int(n * (a1 - a0) / 360.0))
    for k in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * k / steps)
        pts.append((x, math.cos(a) * radius, math.sin(a) * radius))
    return T.tube(pts, r, mat=mat, n=10)


def at(x, radius, deg):
    a = math.radians(deg)
    return V((x, math.cos(a) * radius, math.sin(a) * radius))


def disc(x, radius, h, mat, n=28):
    return T.cyl(radius, h, loc=(x, 0, 0), rot=(0, 90, 0), mat=mat, n=n, bevel=0.012)


def bolts(x, radius, k, parts, r=0.022):
    for i in range(k):
        parts.append(T.cyl(r, 0.04, loc=tuple(at(x, radius, 360 * i / k + 15)), rot=(0, 90, 0), mat=bare, n=6))


def arm(deg, parts, mat, inner_plate=True):
    """A bar from the plate over the tread to the inside of the tyre at angle deg, with a claw plate."""
    o = at(FACE, R + 0.07, deg)
    i = at(-0.24, R + 0.07, deg)
    parts.append(bar(at(FACE, 0.34, deg), o, 0.09, 0.07, mat))   # up the plate's face to the rim
    parts.append(bar(o, i, 0.1, 0.08, mat))                        # over the tread
    if inner_plate:
        parts.append(bar(i, at(-0.24, R - 0.12, deg), 0.12, 0.05, mat))  # down the inside: the claw


def hazard(c, n, up, size):
    decals.append(T.Decal(T.hazard_image(stripes=7), tuple(c), tuple(n), tuple(up), size, depth=0.05, kinds=("paint",)))


def words(s, c, n, up, size, color=(0.02, 0.02, 0.02)):
    decals.append(T.Decal(T.stencil(s, color=color), tuple(c), tuple(n), tuple(up), size, depth=0.04, kinds=("paint",), opacity=0.95))


# ---------------------------------------------------------------- A: DENVER BOOT
def clamp_a():
    p, lamp = [], []
    p.append(disc(FACE, 0.45, 0.06, yellow))
    p.append(ring(FACE + 0.035, 0.42, 0.028, yellow))
    for k in range(12):  # reflectors: red and white blocks round the face
        p.append(T.box((0.012, 0.15, 0.06), loc=tuple(at(FACE + 0.035, 0.33, k * 30)), rot=(k * 30 - 90, 0, 0), mat=g_red if k % 2 else g_white))
    p.append(disc(FACE + 0.06, 0.15, 0.1, dark, 18))
    p.append(T.cyl(0.06, 0.08, loc=(FACE + 0.14, 0, 0), rot=(0, 90, 0), mat=bare, n=8))
    bolts(FACE + 0.06, 0.21, 6, p)
    for deg in (40, 140):
        arm(deg, p, yellow)
    p.append(T.box((0.09, 0.15, 0.17), loc=(FACE + 0.08, 0, -0.27), mat=dark, bevel=0.012))  # padlock
    p.append(T.tube([(FACE + 0.08, -0.05, -0.18), (FACE + 0.08, -0.05, -0.12), (FACE + 0.08, 0.0, -0.09), (FACE + 0.08, 0.05, -0.12), (FACE + 0.08, 0.05, -0.18)], 0.014, mat=bare, n=6))
    p.append(T.cyl(0.05, 0.05, loc=(FACE, 0, R - 0.02), mat=dark, n=12))
    lamp.append(T.sphere(0.07, loc=(FACE, 0, R + 0.04), mat=g_red, n=12, scale=(1, 1, 0.8)))
    words("IMPOUNDED", (FACE + 0.03, 0, 0.21), (1, 0, 0), (0, 0, 1), (0.36, 0.08))
    return T.join(p, "clamp_a"), T.join(lamp, "lamp_a")


# ---------------------------------------------------------------- B: BEAR TRAP
def clamp_b():
    p, lamp = [], []
    for a0, a1 in ((15, 92), (88, 165)):  # two jaws closed over the top of the tyre
        for k in range(8):
            d0 = a0 + (a1 - a0) * k / 8
            d1 = a0 + (a1 - a0) * (k + 1) / 8
            p.append(bar(at(0, R + 0.06, d0), at(0, R + 0.06, d1), 0.5, 0.06, yellow, 0.004))
        for k in range(7):  # teeth along both edges, biting in
            d = a0 + (a1 - a0) * (k + 0.5) / 7
            for x in (0.22, -0.22):
                p.append(spike(at(x, R + 0.04, d), -at(0, 1, d), 0.12, 0.022))
        for x in (0.26, -0.26):  # hinge springs at the jaw ends
            p.append(rod(at(x, R + 0.06, a0) - V((0.03 * (1 if x > 0 else -1), 0, 0)), at(x, R + 0.06, a0) + V((0.03 * (1 if x > 0 else -1), 0, 0)), 0.06, dark))
            p.append(rod(at(x, R + 0.06, a1) - V((0.03 * (1 if x > 0 else -1), 0, 0)), at(x, R + 0.06, a1) + V((0.03 * (1 if x > 0 else -1), 0, 0)), 0.06, dark))
        hazard(at(0, R + 0.09, (a0 + a1) / 2), at(0, 1, (a0 + a1) / 2), (1, 0, 0), (0.5, 0.42))
    for deg in (15, 165, 92):  # struts on the face down to the hub
        p.append(bar(at(FACE + 0.03, R + 0.06, deg), (FACE + 0.03, 0, 0), 0.08, 0.05, yellow))
    for z in range(5):  # the spring coil round the hub
        p.append(ring(FACE + 0.04 + z * 0.025, 0.13, 0.014, bare, 16))
    p.append(disc(FACE + 0.03, 0.1, 0.12, dark, 16))
    # a chain hangs back from the hub to a spiked weight dragging on the road
    a = V((FACE + 0.1, 0, 0))
    b = V((FACE + 0.14, -0.62, -R + 0.1))
    n = 9
    for k in range(n):
        c = a.lerp(b, (k + 0.5) / n) + V((0, 0, -0.06 * math.sin(math.pi * (k + 0.5) / n)))
        rot = aim(b - a)
        p.append(T.box((0.03 if k % 2 else 0.07, 0.07 if k % 2 else 0.03, 0.09), loc=tuple(c), rot=rot, mat=bare, bevel=0.01))
    p.append(T.sphere(0.1, loc=tuple(b + V((0, -0.06, 0))), mat=dark, n=12))
    for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0.6, -0.6, 0.5), (-0.6, -0.6, 0.5)):
        p.append(spike(b + V((0, -0.06, 0)) + V(d) * 0.08, d, 0.09, 0.025, bare, 6))
    lamp.append(T.sphere(0.055, loc=(FACE + 0.1, 0, 0), mat=g_red, n=12))
    return T.join(p, "clamp_b"), T.join(lamp, "lamp_b")


# ---------------------------------------------------------------- C: POLICE LOCK (Outlaw's own)
def clamp_c():
    p, lamp = [], []
    p.append(disc(FACE, 0.45, 0.06, white))
    p.append(ring(FACE + 0.035, 0.43, 0.035, black))
    p.append(disc(FACE + 0.035, 0.2, 0.04, black, 22))
    star = []
    for k in range(10):  # a gold star badge on the black middle
        a = math.radians(90 + k * 36)
        rr = 0.15 if k % 2 == 0 else 0.065
        star.append((math.cos(a) * rr, math.sin(a) * rr))
    p.append(T.prism(star, 0.03, loc=(FACE + 0.07, 0, 0), mat=gold, plane="YZ"))
    bolts(FACE + 0.04, 0.3, 8, p)
    for deg in (40, 140):
        arm(deg, p, black)
    for deg in (220, 320):  # short black claws low on the face, round the sidewall
        p.append(bar(at(FACE, 0.36, deg), at(FACE, 0.45, deg), 0.1, 0.07, black))
    p.append(T.box((0.12, 0.42, 0.09), loc=(FACE, 0, R + 0.03), mat=black, bevel=0.015))  # light bar
    lamp_r = [T.box((0.13, 0.17, 0.08), loc=(FACE, 0.1, R + 0.1), mat=g_red, bevel=0.02)]
    lamp_b = [T.box((0.13, 0.17, 0.08), loc=(FACE, -0.1, R + 0.1), mat=g_blue, bevel=0.02)]
    words("IMPOUND", (FACE + 0.03, 0, -0.3), (1, 0, 0), (0, 0, 1), (0.42, 0.1))
    words("POLICE", (FACE + 0.03, 0, 0.3), (1, 0, 0), (0, 0, 1), (0.36, 0.09))
    return T.join(p, "clamp_c"), T.join(lamp_r, "lamp_c_red"), T.join(lamp_b, "lamp_c_blue")


# ---------------------------------------------------------------- D: SPIKED RING
def clamp_d():
    p, lamp = [], []
    p.append(ring(FACE, 0.37, 0.07, yellow, 32))
    for deg in (45, 135):  # cross braces through the hub
        p.append(bar(at(FACE + 0.02, 0.36, deg), at(FACE + 0.02, 0.36, deg + 180), 0.1, 0.05, yellow))
        hazard(at(FACE + 0.05, 0.18, deg), (1, 0, 0), at(0, 1, deg), (0.06, 0.3))
    p.append(disc(FACE + 0.04, 0.12, 0.1, dark, 18))
    p.append(T.cyl(0.05, 0.09, loc=(FACE + 0.11, 0, 0), rot=(0, 90, 0), mat=bare, n=8))
    for k in range(10):  # spikes driven into the sidewall
        p.append(spike(at(FACE - 0.02, 0.37, k * 36 + 18), (-1, 0, 0), 0.16, 0.035))
    for deg in (60, 120, 240, 300):  # hooks over the tread
        o = at(FACE, R + 0.08, deg)
        i = at(-0.22, R + 0.08, deg)
        p.append(bar(at(FACE, 0.42, deg), o, 0.09, 0.08, yellow))
        p.append(bar(o, i, 0.09, 0.08, yellow))
        p.append(spike(i, -at(0, 1, deg), 0.12, 0.035))
    p.append(T.cyl(0.08, 0.06, loc=(FACE, 0, R + 0.08), mat=dark, n=14))  # beacon base
    for k in range(4):  # the cage
        a = math.radians(45 + k * 90)
        p.append(rod((FACE + math.cos(a) * 0.075, math.sin(a) * 0.075, R + 0.1), (FACE + math.cos(a) * 0.075, math.sin(a) * 0.075, R + 0.25), 0.008, dark, 5))
    p.append(T.cyl(0.085, 0.015, loc=(FACE, 0, R + 0.25), mat=dark, n=14))
    lamp.append(T.cyl(0.06, 0.14, loc=(FACE, 0, R + 0.17), mat=g_amber, n=14, r2=0.05))
    return T.join(p, "clamp_d"), T.join(lamp, "lamp_d")


SPACING = 1.8
built = [clamp_a(), clamp_b(), clamp_c(), clamp_d()]
bodies = [b[0] for b in built]
lamps = [l for b in built for l in b[1:]]
for k, group in enumerate(built):  # spread out for building and previews, back to their own origin at export
    for ob in group:
        ob.data.transform(Matrix.Translation(((k - 1.5) * SPACING, 0, 0)))

if "--shape" in sys.argv:
    out = sys.argv[sys.argv.index("--shape") + 1]
    T.preview(out, size=(1400, 600), eye=(3.4, 5.2, 1.9), look=(0, 0, 0.1), fov=55, samples=12)
    T.preview(out.replace(".png", "_face.png"), size=(1400, 500), eye=(7.5, 0.0, 0.6), look=(0, 0, 0.05), fov=42, samples=12)
    sys.exit(0)
T.unwrap(bodies, margin=0.004)
if "--nobake" not in sys.argv:
    g = T.gbuffer(bodies, size=1024, ao_dist=0.25, bevel_r=0.008, ao_samples=20)
    al, nm, orm = T.weather(g, decals, seed=19, dust_from=-0.6, dust_to=0.7)
    T.save_maps("wheel_clamps", al, nm, orm)
for k, group in enumerate(built):
    for ob in group:
        ob.data.transform(Matrix.Translation((-(k - 1.5) * SPACING, 0, 0)))
T.export_glb("wheel_clamps", bodies + lamps)
print("ok", T.tri_count(bodies + lamps))

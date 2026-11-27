"""Outlaw's wheel clamp (round 19: the owner picked look C of four, "bigger, like a weight on the tyre").
Built round a wheel of radius 0.5 m and 0.38 m wide, centred on the wheel's centre: axle along X, the clamp's
face on +X (the outside of a right-hand wheel), +Y forward, +Z up. Godot scales it to 1.3 x the car's wheel
and mirrors it for a left wheel (WheelClamp.attach).
A police impound lock as heavy as a weight plate: a thick white steel disc with a black rim lip, a raised
black centre with a gold star, a big hub boss, heavy black arms over the tread, a lock box hanging under the
hub, POLICE / IMPOUND, blue reflector studs round the rim, and a red-blue light bar on top that blinks.
    /tmp/bpy3.13/bin/python tools/blender/build_wheel_clamp.py              # build, bake, export
    /tmp/bpy3.13/bin/python tools/blender/build_wheel_clamp.py --shape a.png  # quick look, no bake
Writes assets/models/wheel_clamp.glb: clamp (baked), lamp_red and lamp_blue (glow, separate so they blink)."""
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
white = T.M("paint", (0.62, 0.62, 0.59), wear=0.35, rust=0.2, dirt=0.4)
black = T.M("paint", (0.02, 0.02, 0.022), wear=0.4, rust=0.2, dirt=0.4)
dark = T.M("steel", (0.03, 0.03, 0.033), wear=0.5, rust=0.4, dirt=0.5)
bare = T.M("steel", (0.2, 0.2, 0.2), wear=0.4, rust=0.35, dirt=0.4)
gold = T.M("steel", (0.55, 0.38, 0.08), wear=0.3, rust=0.1, dirt=0.3)
g_red = T.glow((1.0, 0.06, 0.03))
g_blue = T.glow((0.1, 0.3, 1.0))
decals = []


def rod(a, b, r, mat, n=10):
    a, b = Vector(a), Vector(b)
    v = b - a
    return T.cyl(r, v.length, loc=tuple((a + b) / 2), rot=T.aim(v), mat=mat, n=n)


def bar(a, b, w, d, mat, bevel=0.008):
    a, b = Vector(a), Vector(b)
    v = b - a
    return T.box((w, d, v.length), loc=tuple((a + b) / 2), rot=T.aim(v), mat=mat, bevel=bevel)


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


def words(s, c, n, up, size, color=(0.02, 0.02, 0.02)):
    decals.append(T.Decal(T.stencil(s, color=color), tuple(c), tuple(n), tuple(up), size, depth=0.04, kinds=("paint",), opacity=0.95))


# ---------------------------------------------------------------- the clamp
def build():
    p = []
    W = 0.16  # the plate's thickness: a weight, not a sheet
    X0 = FACE + 0.04  # the plate's middle; its back sits against the sidewall
    XF = X0 + W / 2   # its face
    p.append(disc(X0, 0.47, W, white, 32))
    p.append(ring(XF - 0.01, 0.45, 0.055, black, 36))  # the heavy rim lip
    p.append(ring(X0 - W / 2 + 0.01, 0.45, 0.045, black, 36))
    p.append(disc(XF + 0.02, 0.23, 0.05, black, 24))  # raised centre
    star = []
    for k in range(10):  # the gold star badge
        a = math.radians(90 + k * 36)
        rr = 0.17 if k % 2 == 0 else 0.075
        star.append((math.cos(a) * rr, math.sin(a) * rr))
    p.append(T.prism(star, 0.035, loc=(XF + 0.06, 0, 0), mat=gold, plane="YZ"))
    p.append(T.cyl(0.075, 0.12, loc=(XF + 0.1, 0, 0), rot=(0, 90, 0), mat=dark, n=16, bevel=0.01))  # hub boss
    p.append(T.cyl(0.05, 0.05, loc=(XF + 0.18, 0, 0), rot=(0, 90, 0), mat=bare, n=6))  # the big hex bolt
    bolts(XF + 0.005, 0.33, 10, p, 0.03)
    for deg in (40, 140):  # heavy arms over the tread, claws down the inside
        o = at(XF, R + 0.09, deg)
        i = at(-0.25, R + 0.09, deg)
        p.append(bar(at(XF, 0.36, deg), o, 0.15, 0.1, black))
        p.append(bar(o, i, 0.15, 0.12, black))
        p.append(bar(i, at(-0.25, R - 0.14, deg), 0.16, 0.07, black))
        p.append(T.cyl(0.04, 0.17, loc=tuple(o), rot=(0, 90, 0), mat=bare, n=10))  # hinge pin
    for deg in (215, 325):  # short claws low on the face round the sidewall
        p.append(bar(at(XF, 0.38, deg), at(XF, 0.5, deg), 0.13, 0.09, black))
    p.append(T.box((0.13, 0.2, 0.22), loc=(XF + 0.07, 0, -0.33), mat=dark, bevel=0.015))  # lock box under the hub
    p.append(T.tube([(XF + 0.07, -0.06, -0.21), (XF + 0.07, -0.06, -0.14), (XF + 0.07, 0.0, -0.1), (XF + 0.07, 0.06, -0.14), (XF + 0.07, 0.06, -0.21)], 0.02, mat=bare, n=6))
    p.append(T.box((0.03, 0.06, 0.06), loc=(XF + 0.14, 0, -0.35), mat=bare))  # keyhole plate
    studs = []
    for k in range(12):  # blue reflector studs round the rim: seen from far, day or dusk
        studs.append(T.cyl(0.03, 0.03, loc=tuple(at(XF + 0.04, 0.45, k * 30 + 15)), rot=(0, 90, 0), mat=g_blue, n=8))
    # the light bar, high on top of the tyre so the chase camera sees it over the bodywork
    p.append(T.box((0.18, 0.56, 0.1), loc=(X0, 0, R + 0.1), mat=black, bevel=0.02))
    p.append(bar((X0, 0, R - 0.04), (X0, 0, R + 0.06), 0.08, 0.08, black))
    lamp_r = [T.box((0.19, 0.24, 0.12), loc=(X0, 0.14, R + 0.2), mat=g_red, bevel=0.03)]
    lamp_b = [T.box((0.19, 0.24, 0.12), loc=(X0, -0.14, R + 0.2), mat=g_blue, bevel=0.03)]
    words("POLICE", (XF + 0.005, 0, 0.33), (1, 0, 0), (0, 0, 1), (0.42, 0.11))
    words("IMPOUND", (X0 + 0.09, 0, R + 0.1), (1, 0, 0), (0, 0, 1), (0.46, 0.075), color=(0.9, 0.9, 0.86))  # on the light bar
    body = T.join(p + studs, "clamp")
    return body, T.join(lamp_r, "lamp_red"), T.join(lamp_b, "lamp_blue")


body, lamp_red, lamp_blue = build()
objs = [body, lamp_red, lamp_blue]
if "--shape" in sys.argv:
    out = sys.argv[sys.argv.index("--shape") + 1]
    for o in objs:
        o.data.transform(Matrix.Translation((0, 0, R)))  # stand it on the preview's ground
    T.preview(out, size=(1000, 700), eye=(2.4, 1.6, 1.1), look=(0.2, 0, 0.5), fov=40, samples=12)
    sys.exit(0)
T.unwrap([body], margin=0.004)
if "--nobake" not in sys.argv:
    g = T.gbuffer([body], size=1024, ao_dist=0.25, bevel_r=0.008, ao_samples=20)
    al, nm, orm = T.weather(g, decals, seed=19, dust_from=-0.6, dust_to=0.7)
    T.save_maps("wheel_clamp", al, nm, orm)
T.export_glb("wheel_clamp", objs)
print("ok", T.tri_count(objs))

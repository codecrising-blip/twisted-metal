"""Shared pieces for the car builds of round 28 (Thumper, Brimstone, Darkside): rods, glass quads, body
sections, open tyre rings, a wire wheel and a sculpted crewman. Import after tmlib (bpy first).
Blender space: +Y forward, +Z up, metres; wheels are built along X (their axle) and placed by markers."""
import math

import bpy  # first
import bmesh
from mathutils import Vector

import tmlib as T

V = Vector


def aim(d):
    q = Vector(d).normalized().to_track_quat("Z", "Y").to_euler()
    return (math.degrees(q.x), math.degrees(q.y), math.degrees(q.z))


def rod(a, b, r, mat, n=12, r2=None):
    a, b = Vector(a), Vector(b)
    v = b - a
    return T.cyl(r, v.length, loc=tuple((a + b) / 2), rot=aim(v), mat=mat, n=n, r2=r2)


def quad(p, mat, th=0.012):
    """A thin plate on four corners (glass, panels), `th` thick toward the inside."""
    a, b, c, d = [V(x) for x in p]
    n = (b - a).cross(d - a).normalized()
    return T.loft([[tuple(a + n * th), tuple(b + n * th), tuple(c + n * th), tuple(d + n * th)], [tuple(a), tuple(b), tuple(c), tuple(d)]], mat=mat, angle=10.0)


def section(y, hw, zb, zt, c=0.08, tuck=0.07, crease=None, lip=0.0):
    """A body cross-section at y: flat bottom, the sides tucked under, an optional crease (z) where the
    upper body stands `lip` further out than the rocker, the top edge rounded by c."""
    pts = [(hw - tuck, y, zb), (hw - lip - 0.02, y, zb + 0.08)]
    if crease is not None:
        pts += [(hw - lip, y, crease - 0.03), (hw, y, crease + 0.02)]
    pts += [(hw, y, zt - c), (hw - c * 0.7, y, zt)]
    return pts + [(-x, y, z) for (x, y, z) in reversed(pts)]


def ring_solid(profile, mat, n=28, name="ring"):
    """A closed ring swept round the X axis from (radius, x) points: an open tyre, a rim lip (no end caps)."""
    bm = bmesh.new()
    rings = [[bm.verts.new((x, r * math.cos(2 * math.pi * k / n), r * math.sin(2 * math.pi * k / n))) for k in range(n)] for r, x in profile]
    for i in range(len(rings)):
        a, b = rings[i], rings[(i + 1) % len(rings)]
        for k in range(n):
            bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return T._new_obj(name, bm, mat, (0, 0, 0), (0, 0, 0), 50.0)


def tyre(R, w, rubber, n=32, tread=True):
    prof = [(R * 0.7, -w / 2), (R * 0.93, -w / 2), (R * 0.99, -w / 2 + 0.035), (R, -w * 0.25), (R, w * 0.25), (R * 0.99, w / 2 - 0.035),
            (R * 0.93, w / 2), (R * 0.7, w / 2), (R * 0.69, 0.0)]
    parts = [ring_solid(prof, rubber, n)]
    if tread:
        for k in range(n):
            a = 2 * math.pi * k / n
            parts.append(T.box((w * 0.8, 0.045, 0.01), loc=(0, math.cos(a) * (R + 0.002), math.sin(a) * (R + 0.002)), rot=(math.degrees(a) + 90, 0, 0), mat=rubber))
    return parts


def wire_wheel(name, R, w, rubber, white, chrome, dark, spokes=36):
    """A lowrider wheel: a thin tyre with a broad white wall, a chrome dish rim, a fan of crossed wire
    spokes from the rim to a domed hub, a two-eared knock-off cap. Outer face toward +X."""
    parts = tyre(R, w, rubber, 32, tread=False)
    o = w / 2 + 0.002
    parts.append(ring_solid([(R * 0.93, o - 0.01), (R * 0.93, o + 0.002), (R * 0.72, o + 0.002), (R * 0.72, o - 0.01)], white, 32))  # white wall
    parts.append(ring_solid([(R * 0.71, -w / 2 + 0.02), (R * 0.71, o + 0.012), (R * 0.64, o + 0.008), (R * 0.62, o - 0.03), (R * 0.62, -w / 2 + 0.03)], chrome, 32))
    parts.append(T.cyl(R * 0.62, 0.012, loc=(-0.02, 0, 0), rot=(0, 90, 0), mat=dark, n=24))  # the dark well behind the spokes
    hub_x = o - 0.02
    for k in range(spokes):
        a = 2 * math.pi * k / spokes
        lace = 0.22 if k % 2 else -0.22  # crossed lacing: every other spoke leans the other way
        out = V((0.0, math.cos(a) * R * 0.6, math.sin(a) * R * 0.6))
        b = a + lace
        inn = V((hub_x - 0.03 * (k % 3), math.cos(b) * R * 0.13, math.sin(b) * R * 0.13))
        parts.append(rod(out, inn, 0.0045, chrome, n=4))
    parts.append(T.cyl(R * 0.15, 0.06, loc=(hub_x, 0, 0), rot=(0, 90, 0), mat=chrome, n=16, bevel=0.012))
    parts.append(T.sphere(R * 0.1, loc=(hub_x + 0.035, 0, 0), mat=chrome, n=12, scale=(0.6, 1, 1)))
    for e in (-1, 1):  # knock-off ears
        parts.append(T.box((0.018, R * 0.36, 0.03), loc=(hub_x + 0.04, 0, e * 0.0), rot=(e * 30, 0, 0), mat=chrome, bevel=0.006))
    return T.join(parts, name)


# ------------------------------------------------------------------ a crewman (Thumper's Drive-By), sculpted

def crewman(name, at, side, mats):
    """One of Bruce's crew from the waist up, sitting on the door sill facing +Y with a compact machine gun
    held at the shoulder: one melted surface for the body in its hooded jacket (chest, shoulders and arms
    flow together), the head and hands in skin, a black knit cap and a dark bandana over the face.
    `at` = the sill point (the node's pivot), `side` = +1 right, -1 left (the gun arm is on the outer side)."""
    import grimm_rider as GR
    jacket, skin, cap, bandana, gun = mats
    P = V(at)
    s = side
    body = GR.Sculpt(name + "_body", res=0.02)
    body.ball(P + V((0, -0.02, 0.02)), 0.17, size=(1.25, 0.95, 0.8))         # hips on the sill
    body.ball(P + V((0, 0.0, 0.2)), 0.16, size=(1.2, 0.85, 1.0))             # belly
    body.ball(P + V((0, 0.01, 0.4)), 0.19, size=(1.3, 0.85, 1.0))            # chest
    body.ball(P + V((0, -0.08, 0.5)), 0.12, size=(1.4, 1.0, 0.8))            # the hood bunched behind the neck
    sh_o, sh_i = P + V((s * 0.22, 0.0, 0.5)), P + V((-s * 0.22, 0.0, 0.5))
    el_o, el_i = P + V((s * 0.24, 0.2, 0.33)), P + V((-s * 0.12, 0.26, 0.3))
    ha_o, ha_i = P + V((s * 0.06, 0.4, 0.42)), P + V((0.0, 0.58, 0.4))
    body.ball(sh_o, 0.1)
    body.ball(sh_i, 0.1)
    body.chain(sh_o, el_o, 0.075, 0.065)
    body.chain(el_o, ha_o + V((0, -0.05, 0)), 0.065, 0.05)
    body.chain(sh_i, el_i, 0.075, 0.065)
    body.chain(el_i, ha_i + V((0, -0.05, 0)), 0.065, 0.05)
    parts = [body.mesh(jacket, ratio=0.12)]
    head = GR.Sculpt(name + "_head", res=0.014)
    head.ball(P + V((0, 0.02, 0.6)), 0.05)                                     # neck
    head.ball(P + V((0, 0.03, 0.74)), 0.105, size=(0.9, 1.0, 1.15))          # skull
    head.ball(P + V((0, 0.09, 0.7)), 0.06, size=(1.0, 0.8, 0.9))             # jaw
    head.ball(ha_o, 0.045)
    head.ball(ha_i, 0.045)
    parts.append(head.mesh(skin, ratio=0.18))
    parts.append(T.sphere(0.112, loc=tuple(P + V((0, 0.02, 0.785))), mat=cap, n=14, scale=(0.95, 1.05, 0.8)))   # knit cap
    parts.append(T.cyl(0.028, 0.2, loc=tuple(P + V((0, 0.02, 0.73))), rot=(0, 90, 0), mat=cap, n=10))           # its turned-up brim, side to side
    parts.append(T.sphere(0.098, loc=tuple(P + V((0, 0.07, 0.69))), mat=bandana, n=14, scale=(1.02, 0.9, 0.62)))  # bandana over nose and mouth
    # the gun: receiver, barrel shroud, magazine, folded stock against the outer shoulder
    g = P + V((s * 0.03, 0.5, 0.45))
    parts.append(T.box((0.06, 0.32, 0.09), loc=tuple(g), mat=gun, bevel=0.008))
    parts.append(rod(g + V((0, 0.16, 0.01)), g + V((0, 0.34, 0.01)), 0.018, gun, n=8))
    parts.append(T.box((0.045, 0.05, 0.16), loc=tuple(g + V((0, 0.05, -0.11))), rot=(-12, 0, 0), mat=gun, bevel=0.005))
    parts.append(T.box((0.03, 0.2, 0.03), loc=tuple(g + V((0, -0.2, -0.01))), mat=gun, bevel=0.004))
    return T.join(parts, name)


def chain(parts, a, b, mat, sag=0.12, link=0.035):
    """A hanging chain a -> b: round links alternately flat and on edge along a sagging line."""
    a, b = V(a), V(b)
    n = max(4, int((b - a).length / (link * 2.0)))
    pts = [a.lerp(b, i / n) - V((0, 0, sag * 4 * (i / n) * (1 - i / n))) for i in range(n + 1)]
    for i in range(n):
        p, q = pts[i], pts[i + 1]
        d = (q - p).normalized()
        axis = d.cross(V((0, 0, 1))) if i % 2 else V((0, 0, 1)).cross(d).cross(d)
        if axis.length < 1e-4:
            axis = V((1, 0, 0))
        parts.append(T.cyl(link, link * 0.4, loc=tuple((p + q) / 2), rot=aim(axis), mat=mat, n=8))

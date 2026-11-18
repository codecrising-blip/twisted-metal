"""Sweet Tooth's clown head (round 19), from the owner's reference: the TM 2012 truck's mascot. One head for
the truck's roof (on a spring) and for Sweet Bot. Facing +Y, +Z up, centred on the middle of the skull.

Built like a sculpt, not from parts: the skull, the cheeks, the jaw, the mass of fire behind and the tongues
of flame are metaballs melted into ONE surface (no seams, no separate cones), then cut down to a game mesh.
The features sit ON that surface (projected onto it with ray casts): a raised riveted seam where the white
face ends and the fire begins, long eyes outlined in thick red with no pupils, the big glossy ball nose,
and the grin: a band of joined white teeth inside thick red lips that curl up into the cheeks. The colour
of the fire is painted by distance from the seam: pale gold, yellow-orange, orange, red at the tips. Worn
fibreglass: grime, specks, chips (the bake).
    import clown_head
    clown_head.build(centre, scale, parts, decals, regions, unbake=None)
`unbake(P)` maps bake-space points back to where the head was built (when the caller moves the meshes
after building, like Sweet Bot's upper body). Size at scale 1: the skull about 0.85 m across, about 1.6 m
from the nose to the furthest flame tip."""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import tmlib as T

V = Vector
FS = V((0, 0.88, -0.47)).normalized()  # the face side: the seam is a plane across it, SEAM behind the centre
SEAM = 0.0  # owner: the fire's hairline comes forward over the forehead (the forehead keeps its curve)
PITCH = -8.0  # the whole head leans nose-down like the reference: the face looks ahead and down, the fire rises
_m = {}

# tongues of flame: root, tip, metaball radius at the root. Each rises off the skull, bends back, and its
# tip curls up again (a cubic path), thinning to a point.
TONGUES = [
    ((0.0, -0.04, 0.37), (0.0, -0.46, 1.02), 0.3),
    ((0.0, -0.38, 0.24), (0.0, -0.84, 0.88), 0.29),
    ((0.0, -0.42, 0.1), (0.0, -1.0, 0.68), 0.27),
    ((0.0, -0.46, -0.06), (0.0, -1.08, 0.42), 0.25),
    ((0.0, -0.42, -0.2), (0.0, -1.0, 0.14), 0.22),
    ((0.25, -0.26, 0.22), (0.38, -0.8, 0.82), 0.24),
    ((-0.25, -0.26, 0.22), (-0.38, -0.8, 0.82), 0.24),
    ((0.26, -0.42, 0.0), (0.42, -0.96, 0.54), 0.22),
    ((-0.26, -0.42, 0.0), (-0.42, -0.96, 0.54), 0.22),
    ((0.26, -0.12, 0.28), (0.34, -0.36, 0.78), 0.17),
    ((-0.26, -0.12, 0.28), (-0.34, -0.36, 0.78), 0.17),
]


def _mats():
    if not _m:
        _m["skin"] = T.M("paint", (0.5, 0.47, 0.38), wear=0.3, rust=0.25, dirt=0.45, rough=0.35)  # the truck's cream (owner)
        _m["seam"] = T.M("paint", (0.8, 0.5, 0.12), wear=0.25, rust=0.25, dirt=0.45, rough=0.35)
        _m["red"] = T.M("paint", (0.62, 0.035, 0.03), wear=0.2, rust=0.08, dirt=0.25, rough=0.25)
        _m["nose"] = T.M("plastic", (0.62, 0.04, 0.025), wear=0.2, dirt=0.25, rough=0.2)
        _m["teeth"] = T.M("plastic", (0.82, 0.81, 0.77), wear=0.25, dirt=0.4, rough=0.28)
        _m["rivet"] = T.M("steel", (0.32, 0.26, 0.16), wear=0.4, rust=0.6, dirt=0.6)
    return _m


def _skull():
    """The sculpt: metaballs melted into one surface, converted and cut down to a game mesh."""
    mb = bpy.data.metaballs.new("clown_skull")
    mb.resolution = 0.022
    mb.render_resolution = 0.022
    ob = bpy.data.objects.new("clown_skull", mb)
    bpy.context.scene.collection.objects.link(ob)

    def ball(co, r, kind="BALL", size=(1, 1, 1)):
        e = mb.elements.new(type=kind)
        e.co = co
        e.radius = r
        if kind == "ELLIPSOID":
            e.size_x, e.size_y, e.size_z = size

    ball((0, 0, 0), 0.74, "ELLIPSOID", (1.0, 1.06, 0.97))     # the skull, a little long front to back
    for sx in (1, -1):
        ball((sx * 0.2, 0.27, -0.13), 0.26)                    # cheeks pushed up by the grin
    ball((0, 0.2, -0.24), 0.32)                                # jaw and chin
    ball((0, -0.1, 0.13), 0.62, "ELLIPSOID", (0.92, 1.0, 0.96))  # the mass of fire, up to the hairline
    # the smooth head without the tongues: the seam (the fire's hairline) is laid on this, one clean arc
    dg = bpy.context.evaluated_depsgraph_get()
    me0 = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    smooth = bpy.data.objects.new("clown_smooth", me0)
    T._link(smooth)
    bvh0 = _surface(smooth)
    bpy.data.objects.remove(smooth)
    for root, tip, r0 in TONGUES:
        p0, p3 = V(root), V(tip)
        length = (p3 - p0).length
        p1 = p0 + V((0, 0.04, 0.42 * length))               # rises off the skull...
        p2 = p3 + V((0, 0.3 * length, -0.3 * length))      # ...bends back, and the tip curls up again
        n = max(10, int(length / 0.025))
        for i in range(n + 1):
            t = i / n
            p = p0 * (1 - t) ** 3 + p1 * 3 * t * (1 - t) ** 2 + p2 * 3 * t * t * (1 - t) + p3 * t ** 3
            ball(tuple(p), r0 * (1.0 - t) ** 0.95 + 0.014)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob)
    bpy.data.metaballs.remove(mb)
    sk = bpy.data.objects.new("clown_skin", me)
    T._link(sk)
    me.materials.append(_mats()["skin"])
    bvh = _surface(sk)  # the features are laid on the full-detail sculpt, before it is cut down
    T.decimate(sk, 0.06)
    me = sk.data
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    return sk, bvh, bvh0


def _surface(sk):
    bm = bmesh.new()
    bm.from_mesh(sk.data)
    bm.transform(sk.matrix_world)
    return BVHTree.FromBMesh(bm)


def _on_face(bvh, u, v, out=0.0):
    """The point of the face at (u right, v up) seen from the front, lifted `out` off the surface."""
    hit = bvh.ray_cast(V((u, 2.0, v)), V((0, -1, 0)), 5.0)
    if hit[0] is None:
        return V((u, 0.3, v)), V((0, 1, 0))
    return hit[0] + hit[1] * out, hit[1]


def _spline(pts, n, closed=False):
    """(u, v) points along a Catmull-Rom line through pts (a loop if closed)."""
    P = [np.array(p, dtype=np.float64) for p in pts]
    L = len(P)
    out = []
    for i in range(n + 1):
        if closed:
            f = i / n * L
            k = int(f) % L
            t = f - int(f)
            p0, p1, p2, p3 = P[(k - 1) % L], P[k], P[(k + 1) % L], P[(k + 2) % L]
        else:
            f = i / n * (L - 1)
            k = min(int(f), L - 2)
            t = f - k
            p0, p1, p2, p3 = P[max(k - 1, 0)], P[k], P[k + 1], P[min(k + 2, L - 1)]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    return np.array(out, dtype=np.float32)


def _eye_lids(sx):
    up = [(sx * x, y) for x, y in ((0.07, 0.06), (0.13, 0.118), (0.2, 0.155), (0.27, 0.172), (0.335, 0.165))]
    dn = [(sx * x, y) for x, y in ((0.07, 0.06), (0.13, 0.05), (0.2, 0.06), (0.27, 0.088), (0.335, 0.165))]
    return up, dn


def _dist(pts, line):
    """Distance from each point to the nearest sample of a dense line (3D, on the surface: even widths)."""
    d = np.full(len(pts), 9.0, dtype=np.float32)
    for q in line:
        np.minimum(d, np.sqrt(((pts - q) ** 2).sum(axis=1)), out=d)
    return d


def _paint_face(local, bvh):
    """The face is painted like the reference: thick even red outlines round each eye and round the grin,
    the grin's corners running up into the cheeks, a band of white teeth with grey gaps, the eye whites a
    shade brighter than the face. Regions in the head's frame, seen from the front (u = x, v = z)."""
    def front(P):
        L, inside = local(P)
        on = inside & (L[:, 1] > -0.05) & (np.abs(L[:, 0]) < 0.5) & (L[:, 2] > -0.45) & (L[:, 2] < 0.32)
        return L, on

    def smooth_edge(d, half, soft=0.004):
        return np.clip((half + soft - d) / (2 * soft), 0, 1)

    us = np.linspace(-MOUTH_W, MOUTH_W, 64)
    up_u = np.array([_lip_up(u) for u in us])
    dn_u = np.array([_lip_dn(u) for u in us])

    def teeth(P, N):
        L, on = front(P)
        u, v = L[:, 0], L[:, 2]
        top = np.interp(u, us, up_u)
        bot = np.interp(u, us, dn_u)
        return ((v < top) & (v > bot) & (np.abs(u) < MOUTH_W)).astype(np.float32) * on

    def gaps(P, N):
        L, on = front(P)
        u = L[:, 0]
        frac = np.abs(((u + MOUTH_W) / 0.09) % 1.0 - 0.5)
        return teeth(P, N) * (frac > 0.455)

    def whites(P, N):
        L, on = front(P)
        u, v = L[:, 0], L[:, 2]
        w = np.zeros(len(u), dtype=np.float32)
        for sx in (1, -1):
            up, dn = _eye_lids(sx)
            ux = np.array([p[0] for p in up])[::sx]
            uy = np.array([p[1] for p in up])[::sx]
            dx = np.array([p[0] for p in dn])[::sx]
            dy = np.array([p[1] for p in dn])[::sx]
            inside = (u * sx > 0.06) & (u * sx < 0.4) & (v < np.interp(u, ux, uy)) & (v > np.interp(u, dx, dy))
            w = np.maximum(w, inside.astype(np.float32))
        return w * on

    def on_skin(uv_line):  # the face points under a (u, v) line, in 3D on the sculpt
        return np.array([tuple(_on_face(bvh, float(q[0]), float(q[1]), 0.0)[0]) for q in uv_line], dtype=np.float32)

    lines = []
    for sx in (1, -1):
        up, dn = _eye_lids(sx)
        lines.append((on_skin(_spline(up + list(reversed(dn[1:-1])), 240, True)), 0.03))
        lines.append((on_skin(_spline([(p[0], p[1] + 0.012) for p in up[1:-1]], 80)), 0.034))  # the heavy upper lid
    us_l = [-MOUTH_W, -0.33, -0.26, -0.18, -0.09, 0.0, 0.09, 0.18, 0.26, 0.33, MOUTH_W]
    lu = [(u, _lip_up(u)) for u in us_l]
    ld = [(u, _lip_dn(u)) for u in us_l]
    lines.append((on_skin(_spline(lu + list(reversed(ld[1:-1])), 400, True)), 0.04))  # one crescent, pointed corners

    def red(P, N):
        L, on = front(P)
        idx = np.nonzero(on)[0]
        out = np.zeros(len(P), dtype=np.float32)
        if len(idx) == 0:
            return out
        pts = L[idx].astype(np.float32)
        w = np.zeros(len(idx), dtype=np.float32)
        for line, half in lines:
            w = np.maximum(w, smooth_edge(_dist(pts, line), half))
        out[idx] = w
        return out

    return [(whites, (0.58, 0.55, 0.46), ("paint",)), (teeth, (0.66, 0.64, 0.56), ("paint",)),
            (gaps, (0.5, 0.47, 0.42), ("paint",)), (red, (0.62, 0.03, 0.025), ("paint",))]


MOUTH_W = 0.38  # the grin's half width: a crescent across nearly the whole face, its corners high on the cheeks


def _lip_up(u):
    a = min(abs(u) / MOUTH_W, 1.0)
    return -0.17 + 0.2 * a ** 2


def _lip_dn(u):
    a = min(abs(u) / MOUTH_W, 1.0)
    return -0.37 + 0.4 * a ** 1.7


def build(c, s, parts, decals=None, regions=None, unbake=None):
    m = _mats()
    c = V(c)
    head = []
    sk, bvh, bvh0 = _skull()
    head.append(sk)
    # the seam: a raised riveted band in the plane across the face side, laid on the surface from inside
    A = V((1, 0, 0))
    B = FS.cross(A).normalized()
    seam = []
    for k in range(48):
        a = 2 * math.pi * k / 48
        d = (A * math.cos(a) + B * math.sin(a)).normalized()
        hit = bvh0.ray_cast(FS * SEAM + d * 0.02, d, 3.0)
        if hit[0] is not None:
            seam.append(hit[0] + hit[1] * 0.006)
    if len(seam) > 8:
        head.append(T.tube([tuple(p) for p in seam + seam[:1]], 0.015, mat=m["seam"], n=6))
        for k in range(0, len(seam), 2):
            head.append(T.sphere(0.008, loc=tuple(seam[k] + (seam[k] - FS * SEAM).normalized() * 0.01), mat=m["rivet"], n=5))
    # the nose: a big glossy ball low between the eyes and the grin (the eyes, the lips and the teeth are
    # PAINTED on the fibreglass, like the reference: see _paint_face, applied as regions at the bake)
    np_, nn = _on_face(bvh, 0.0, -0.05, 0.075)
    head.append(T.sphere(0.118, loc=tuple(np_ + nn * 0.01), mat=m["nose"], n=20))
    # into place
    rot = Matrix.Rotation(math.radians(PITCH), 4, "X")
    xf = Matrix.Translation(c) @ rot @ Matrix.Scale(s, 4)
    r3 = rot.to_3x3()
    for o in head:
        T.apply(o)
        o.data.transform(xf)
    parts.extend(head)
    unb = unbake if unbake else (lambda P: P)
    if decals is not None:
        # grime specks all over
        for k, (dn, size) in enumerate((((0, 1, 0), 0.9), ((1, 0, 0), 0.9), ((-1, 0, 0), 0.9), ((0, 0, 1), 0.9), ((0, -1, 0), 1.2))):
            dv = r3 @ V(dn)
            upv = r3 @ (V((0, 0, 1)) if abs(dn[2]) < 0.9 else V((0, 1, 0)))
            decals.append(T.Decal(T.dots_image((0.2, 0.13, 0.06), n=22, seed=70 + k, size=(512, 512), r=(1, 3), alpha=0.6), tuple(c + dv * 0.3 * s), tuple(dv),
                                  tuple(upv), (size * s, size * s), depth=0.6 * s, kinds=("paint",), opacity=0.4))
    if regions is not None:
        cc = np.array(c, dtype=np.float32)
        fs = np.array(FS, dtype=np.float32)
        rm = np.array(r3, dtype=np.float32)

        def local(P):
            L = ((unb(P) - cc) / s) @ rm  # back into the head's own frame (undo the pitch)
            inside = (np.abs(L[:, 0]) < 0.62) & (L[:, 1] > -1.3) & (L[:, 1] < 0.62) & (L[:, 2] > -0.55) & (L[:, 2] < 1.3)
            return L, inside

        def band(lo, hi):
            def fn(P, N):
                L, inside = local(P)
                depth = -(L @ fs) + SEAM
                return np.clip((depth - lo) / (hi - lo), 0, 1) * inside
            return fn
        regions.append((band(-0.006, 0.0), (0.85, 0.48, 0.06), ("paint",)))   # behind the seam: gold
        regions.append((band(0.01, 0.1), (0.92, 0.34, 0.01), ("paint",)))     # yellow-orange
        regions.append((band(0.1, 0.3), (0.9, 0.17, 0.0), ("paint",)))        # orange
        regions.append((band(0.38, 0.66), (0.8, 0.09, 0.0), ("paint",)))      # orange-red at the tips
        regions.extend(_paint_face(local, bvh))

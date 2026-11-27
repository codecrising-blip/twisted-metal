"""Paris (round 29, owner: "add the rest of the map like the tower and the other things"): the landmarks.
Three files, each with its own atlas:
    /tmp/bpy3.13/bin/python tools/blender/build_paris_landmarks.py tower|monuments|buildings [--nobake] [--shape out.png]
  tower     -> paris_tower.glb      eiffel: 140 m, feet 50 m apart, decks at 30 / 70 / 112 m
  monuments -> paris_monuments.glb  arc (Arc de Triomphe, the main arch runs through along Y), obelisk,
                                    fountain + fountain_water, pyramid (Louvre: glass + steel lattice),
                                    moulin (Moulin Rouge) + moulin_sails (hub at its origin, turns about Y)
  buildings -> paris_buildings.glb  notre_dame (front -Y), sacre_coeur, invalides, opera, chaillot (one wing),
                                    louvre_wing (30 m of the palace), louvre_pavilion
Every piece: origin in the middle of its footprint on the ground, the front faces -Y (Godot +Z, south).
Palette: docs/design/32-paris-design.md section 5. Sizes are the game's (the map is smaller than Paris)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T  # first: it loads bpy
import bmesh
import bpy
from mathutils import Matrix, Vector

T.reset()
PART = next((a for a in sys.argv[1:] if a in ("tower", "monuments", "buildings")), "tower")


STONE = T.M("ashlar", T.lin("D8C9AC"), 0.3, 0.0, 0.35)
STONE_DK = T.M("stone", T.lin("A3967F"), 0.35, 0.0, 0.5)
CATHEDRAL = T.M("ashlar", T.lin("CBC2AE"), 0.35, 0.0, 0.55)
WHITE = T.M("stone", T.lin("EEEAE0"), 0.15, 0.0, 0.3)
GRANITE = T.M("stone", T.lin("B39684"), 0.25, 0.0, 0.3)
EIFFEL = T.M("paint", T.lin("6B4E3A"), 0.25, 0.2, 0.35)
STEEL = T.M("steel", T.lin("4C5155"), 0.25, 0.2, 0.4)
GOLD = T.M("steel", T.lin("C9A54A"), 0.08, 0.0, 0.2)
SLATE = T.M("stone", T.lin("50575D"), 0.15, 0.0, 0.4)
ZINC = T.M("stone", T.lin("6F7C86"), 0.15, 0.0, 0.45)
COPPER = T.M("paint", T.lin("5E8C78"), 0.2, 0.0, 0.35)
RED = T.M("paint", T.lin("9E1B1B"), 0.25, 0.05, 0.4)
WOOD = T.M("paint", T.lin("5A3B26"), 0.3, 0.1, 0.5)
DARK = T.M("paint", T.lin("1E1A18"), 0.05, 0.0, 0.1)  # deep openings, window voids
BRONZE = T.M("steel", T.lin("3F5A4C"), 0.2, 0.1, 0.4)
GLASS = T.glass((0.03, 0.045, 0.06))
LIGHTS = T.glow((1.0, 0.82, 0.45))


# ------------------------------------------------------------------ helpers

def beams(name, segs, mat):
    """Square-section beams in one mesh: segs = [(a, b, width), ...] (the Eiffel lattice, glass ribs)."""
    bm = bmesh.new()
    for a, b, w in segs:
        a = Vector(a)
        b = Vector(b)
        d = b - a
        if d.length < 1e-4:
            continue
        d.normalize()
        up = Vector((0, 0, 1)) if abs(d.z) < 0.95 else Vector((1, 0, 0))
        u = d.cross(up).normalized() * w * 0.5
        v = d.cross(u).normalized() * w * 0.5
        vs = [bm.verts.new(p) for p in (a + u + v, a - u + v, a - u - v, a + u - v, b + u + v, b - u + v, b - u - v, b + u - v)]
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((vs[i], vs[j], vs[4 + j], vs[4 + i]))
        bm.faces.new((vs[3], vs[2], vs[1], vs[0]))
        bm.faces.new((vs[4], vs[5], vs[6], vs[7]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return T._new_obj(name, bm, mat)


def arch_cutter(w, h, depth, axis="Y", loc=(0, 0, 0), n=16):
    """A round-headed opening w wide, h tall (to the crown), through `depth` along Y or X."""
    r = w * 0.5
    pts = [(-r, -1.0), (r, -1.0)]
    for k in range(n + 1):
        a = math.pi * k / n
        pts.append((r * math.cos(a), h - r + r * math.sin(a)))
    pts = [pts[0], pts[1]] + pts[2:]
    if axis == "Y":
        return T.prism(pts, depth, loc=loc, plane="XZ")
    return T.prism(pts, depth, loc=loc, plane="YZ")


def window_grid(objs, x0, x1, z0, rows, y, w=1.4, h=2.6, step=4.0, floor_h=4.0, face=-1, mat=DARK, frame=None, axis="X"):
    """Recessed dark windows (thin boxes standing just proud of the wall) along X (or Y) at depth y."""
    n = max(1, int((x1 - x0) / step))
    for r in range(rows):
        z = z0 + r * floor_h + h * 0.5
        for k in range(n):
            x = x0 + (k + 0.5) * (x1 - x0) / n
            loc = (x, y + face * 0.03, z) if axis == "X" else (y + face * 0.03, x, z)
            size = (w, 0.08, h) if axis == "X" else (0.08, w, h)
            objs.append(T.box(size, loc, mat=mat))
            if frame:
                fl = (x, y + face * 0.08, z - h * 0.5 - 0.15) if axis == "X" else (y + face * 0.08, x, z - h * 0.5 - 0.15)
                objs.append(T.box((w + 0.5, 0.25, 0.2) if axis == "X" else (0.25, w + 0.5, 0.2), fl, mat=frame))


def mansard_roof(objs, sx, sy, z, h, mat, inset=1.4, name="roof"):
    """A hipped mansard: footprint sx x sy at height z, rising h with the top inset all round."""
    bm = bmesh.new()
    lo = [bm.verts.new(p) for p in ((-sx / 2, -sy / 2, z), (sx / 2, -sy / 2, z), (sx / 2, sy / 2, z), (-sx / 2, sy / 2, z))]
    hi = [bm.verts.new(p) for p in ((-sx / 2 + inset, -sy / 2 + inset, z + h), (sx / 2 - inset, -sy / 2 + inset, z + h),
                                    (sx / 2 - inset, sy / 2 - inset, z + h), (-sx / 2 + inset, sy / 2 - inset, z + h))]
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bm.faces.new(hi)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    objs.append(T._new_obj(name, bm, mat))


def dome(objs, r, z, h, mat, n=24, onion=0.0, lantern=None, at=(0.0, 0.0)):
    """A dome of radius r springing at z, h tall, centred on `at`; onion > 0 swells it (Sacre-Coeur)."""
    prof = []
    for k in range(9):
        t = k / 8.0
        rr = r * math.cos(t * math.pi * 0.5) * (1.0 + onion * math.sin(t * math.pi))
        prof.append((rr if k < 8 else 0.0, z + h * math.sin(t * math.pi * 0.5)))
    cx, cy = at
    objs.append(T.lathe(prof, (cx, cy, 0), mat=mat, n=n))
    if lantern:
        lr, lh = lantern
        objs.append(T.cyl(lr, lh, (cx, cy, z + h + lh * 0.5 - 0.2), mat=mat, n=12))
        objs.append(T.lathe([(lr * 1.2, z + h + lh - 0.2), (lr * 0.9, z + h + lh + 0.4), (0.0, z + h + lh + lr * 2.2)], (cx, cy, 0), mat=GOLD, n=12))


items = {}  # name -> object


def finish(name, objs):
    ob = T.join(objs, name)
    items[name] = ob
    return ob


# ------------------------------------------------------------------ the Eiffel tower

def eiffel():
    segs = []
    W = 0.55  # corner girders
    B = 0.28  # bracing

    def leg_frame(z):
        """Centre offset and half size of each leg at height z (z <= 70)."""
        if z <= 30.0:
            t = z / 30.0
            return 21.0 - 9.0 * t ** 0.85, 4.0 - 1.0 * t
        t = (z - 30.0) / 40.0
        return 12.0 - 7.0 * t ** 0.9, 3.0 - 1.0 * t

    def shaft(z):
        t = (z - 70.0) / 42.0
        return 7.0 - 4.4 * t ** 0.8

    zs = [0.0]
    while zs[-1] < 70.0:
        zs.append(min(70.0, zs[-1] + (2.5 if zs[-1] < 30 else 3.4)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            rings = []
            for z in zs:
                c, h = leg_frame(z)
                cx, cy = sx * c, sy * c
                rings.append([(cx - h, cy - h, z), (cx + h, cy - h, z), (cx + h, cy + h, z), (cx - h, cy + h, z)])
            for i in range(len(rings) - 1):
                a, b = rings[i], rings[i + 1]
                for k in range(4):
                    k2 = (k + 1) % 4
                    segs.append((a[k], b[k], W))
                    segs.append((a[k], b[k2], B))
                    segs.append((a[k2], b[k], B))
                if i % 3 == 0:
                    for k in range(4):
                        segs.append((a[k], a[(k + 1) % 4], B))
    # the shaft above the second deck
    z = 70.0
    prev = None
    while z <= 112.01:
        s = shaft(z)
        ring = [(-s, -s, z), (s, -s, z), (s, s, z), (-s, s, z)]
        if prev:
            for k in range(4):
                k2 = (k + 1) % 4
                segs.append((prev[k], ring[k], W * 0.8))
                segs.append((prev[k], ring[k2], B * 0.8))
                segs.append((prev[k2], ring[k], B * 0.8))
                segs.append((ring[k], ring[k2], B * 0.8))
        prev = ring
        z += 3.5
    # the great arches under the first deck, one on each face
    for face in range(4):
        pts = []
        for k in range(17):
            t = k / 16.0
            x = -13.5 + 27.0 * t
            zz = 14.0 + 13.0 * math.sin(t * math.pi) ** 0.7
            pts.append((x, zz))
        for k in range(16):
            ax, az = pts[k]
            bx, bz = pts[k + 1]
            p0 = Vector((ax, -14.5, az))
            p1 = Vector((bx, -14.5, bz))
            rot = Matrix.Rotation(face * math.pi * 0.5, 3, "Z")
            segs.append((tuple(rot @ p0), tuple(rot @ p1), 0.9))
            # spandrel ribs up to the deck
            if k % 2 == 0:
                segs.append((tuple(rot @ p0), tuple(rot @ Vector((ax, -14.5, 29.0))), 0.25))
    objs = [beams("lattice", segs, EIFFEL)]
    # decks: slabs, galleries (a fascia all round), railings
    for z, s, depth in ((30.0, 16.5, 4.0), (70.0, 8.8, 3.0), (112.0, 4.6, 2.2)):
        objs.append(T.box((s * 2, s * 2, 0.8), (0, 0, z), mat=EIFFEL))
        for sx, sy, w, d in ((0, -s, s * 2, 0.4), (0, s, s * 2, 0.4), (-s, 0, 0.4, s * 2), (s, 0, 0.4, s * 2)):
            objs.append(T.box((w, d, depth), (sx, sy, z - depth * 0.5 + 0.4), mat=EIFFEL))
            objs.append(T.box((w if w > 1 else 0.12, d if d > 1 else 0.12, 0.1), (sx, sy, z + 1.5), mat=STEEL))
        if z < 100:
            for k in range(int(s * 2 / 2.0)):
                t = -s + 1.0 + k * 2.0
                for sx, sy in ((t, -s), (t, s), (-s, t), (s, t)):
                    objs.append(T.box((0.08, 0.08, 1.5), (sx, sy, z + 0.75), mat=STEEL))
    # summit: cabin, lantern, mast
    objs.append(T.box((6.0, 6.0, 3.6), (0, 0, 114.2), mat=EIFFEL))
    window_grid(objs, -2.4, 2.4, 112.9, 1, -3.0, w=0.9, h=1.6, step=1.6, floor_h=2.0)
    objs.append(T.cyl(2.2, 3.0, (0, 0, 117.5), mat=EIFFEL, n=12, r2=1.6))
    objs.append(T.cyl(1.4, 2.0, (0, 0, 120.0), mat=STEEL, n=10))
    objs.append(T.cyl(0.35, 19.0, (0, 0, 130.5), mat=STEEL, n=6, r2=0.12))
    objs.append(T.box((1.2, 1.2, 0.6), (0, 0, 126.0), mat=STEEL))
    # feet: stone piers each leg stands on
    for sx in (-1, 1):
        for sy in (-1, 1):
            objs.append(T.box((10.0, 10.0, 1.6), (sx * 21.0, sy * 21.0, 0.8), mat=STONE_DK, bevel=0.2))
    finish("eiffel", objs)


# ------------------------------------------------------------------ monuments

def arc():
    W, D = 36.0, 18.0
    body = T.box((W, D, 28.0), (0, 0, 14.0), mat=STONE)
    T.cut(body, arch_cutter(12.0, 24.0, D + 2.0, "Y"))
    T.cut(body, arch_cutter(7.0, 15.0, W + 2.0, "X"))
    objs = [body]
    # entablature, frieze, attic, top cornice
    objs.append(T.box((W + 1.2, D + 1.2, 1.4), (0, 0, 28.7), mat=STONE, bevel=0.15))
    objs.append(T.box((W + 0.4, D + 0.4, 3.2), (0, 0, 31.0), mat=STONE_DK))
    objs.append(T.box((W + 1.6, D + 1.6, 1.0), (0, 0, 33.1), mat=STONE, bevel=0.15))
    objs.append(T.box((W, D, 5.6), (0, 0, 36.4), mat=STONE))
    objs.append(T.box((W + 0.9, D + 0.9, 0.8), (0, 0, 39.6), mat=STONE, bevel=0.12))
    # shields along the attic
    for k in range(9):
        x = -W / 2 + 2.0 + k * (W - 4.0) / 8
        for y in (-D / 2 - 0.15, D / 2 + 0.15):
            objs.append(T.cyl(0.9, 0.3, (x, y, 36.4), rot=(90, 0, 0), mat=STONE_DK, n=12))
    # sculpture groups on the four piers of the long faces, cornice bands at the impost
    for sx in (-1, 1):
        for y in (-D / 2, D / 2):
            fy = -0.6 if y < 0 else 0.6
            objs.append(T.box((7.0, 1.2, 10.0), (sx * 12.0, y + fy * 0.6, 9.0), mat=STONE_DK, bevel=0.3))
            objs.append(T.box((7.6, 1.4, 0.9), (sx * 12.0, y + fy * 0.7, 3.6), mat=STONE, bevel=0.1))
            objs.append(T.box((6.0, 1.0, 4.2), (sx * 12.0, y + fy * 0.5, 21.0), mat=STONE_DK, bevel=0.15))
    objs.append(T.box((W + 0.8, D + 0.8, 0.7), (0, 0, 17.0), mat=STONE, bevel=0.1))
    # base plinth all round, keystone, coffered soffit of the main arch
    objs.append(T.box((W + 2.0, D + 2.0, 0.9), (0, 0, 0.45), mat=STONE_DK, bevel=0.1))
    for y in (-D / 2 - 0.3, D / 2 + 0.3):
        objs.append(T.box((1.6, 0.8, 2.6), (0, y, 23.2), mat=STONE, bevel=0.1))
    for k in range(6):
        objs.append(T.box((11.4, 1.6, 0.4), (0, -D / 2 + 2.0 + k * (D - 4.0) / 5, 23.6), mat=STONE_DK))
    finish("arc", objs)


def obelisk():
    objs = [T.box((4.6, 4.6, 1.2), (0, 0, 0.6), mat=GRANITE, bevel=0.1),
            T.box((3.4, 3.4, 4.0), (0, 0, 3.2), mat=GRANITE, bevel=0.08),
            T.box((3.8, 3.8, 0.5), (0, 0, 5.45), mat=GRANITE, bevel=0.08)]
    objs.append(T.box((1.8, 1.8, 20.0), (0, 0, 15.7), mat=GRANITE, taper=(0.62, 0.62)))
    objs.append(T.lathe([(0.8, 25.7), (0.0, 27.3)], mat=GOLD, n=4))
    for k in range(4):  # hieroglyph bands: shallow darker panels
        a = k * math.pi * 0.5
        objs.append(T.box((0.9, 0.06, 16.0), (math.sin(a) * 0.82, -math.cos(a) * 0.82, 15.0), rot=(0, 0, math.degrees(a)), mat=STONE_DK, taper=(0.65, 1.0)))
    finish("obelisk", objs)


def fountain():
    objs = [T.lathe([(9.0, 0.0), (9.0, 0.55), (8.4, 0.55), (8.4, 0.1), (0.0, 0.1)], mat=STONE, n=40)]
    objs.append(T.lathe([(1.6, 0.0), (1.2, 1.2), (0.9, 3.0), (3.6, 3.2), (3.8, 3.6), (0.8, 3.6), (0.6, 5.4),
                         (2.2, 5.6), (2.3, 5.9), (0.5, 5.9), (0.4, 7.6), (0.0, 8.4)], mat=BRONZE, n=24))
    for k in range(6):  # tritons round the bowl
        a = k * math.tau / 6
        objs.append(T.sphere(0.5, (math.cos(a) * 2.4, math.sin(a) * 2.4, 1.9), mat=BRONZE, n=8, scale=(1, 1, 1.6)))
    finish("fountain", objs)
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, segments=40, radius=8.4)
    w = T._new_obj("fountain_water", bm, GLASS, loc=(0, 0, 0.42))
    items["fountain_water"] = w


def pyramid():
    B, H = 22.0, 14.0
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in ((-B / 2, -B / 2, 0), (B / 2, -B / 2, 0), (B / 2, B / 2, 0), (-B / 2, B / 2, 0), (0, 0, H))]
    for i in range(4):
        bm.faces.new((vs[i], vs[(i + 1) % 4], vs[4]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    glass = T._new_obj("pyr_glass", bm, GLASS)
    segs = []
    top = Vector((0, 0, H))
    corners = [Vector(p) for p in ((-B / 2, -B / 2, 0), (B / 2, -B / 2, 0), (B / 2, B / 2, 0), (-B / 2, B / 2, 0))]
    n = 9
    for i in range(4):
        a, b = corners[i], corners[(i + 1) % 4]
        nrm = ((a + b) * 0.5 - Vector((0, 0, 0))).normalized() * 0.08
        for k in range(1, n):  # horizontal rails
            t = k / n
            segs.append((tuple(a.lerp(top, t) + nrm), tuple(b.lerp(top, t) + nrm), 0.16))
        for k in range(n + 1):  # diagonals both ways: the lozenge grid
            p = a.lerp(b, k / n)
            segs.append((tuple(p + nrm), tuple(p.lerp(top, 1.0) + nrm), 0.12))
        segs.append((tuple(a + nrm * 1.5), tuple(top), 0.35))
    for i in range(4):
        segs.append((tuple(corners[i] + Vector((0, 0, 0.3))), tuple(corners[(i + 1) % 4] + Vector((0, 0, 0.3))), 0.6))
    lattice = beams("pyr_lattice", segs, STEEL)
    objs = [glass, lattice, T.box((B + 1.2, B + 1.2, 0.3), (0, 0, 0.15), mat=STONE_DK)]
    finish("pyramid", objs)


def moulin():
    objs = [T.box((18.0, 10.0, 9.0), (0, 0, 4.5), mat=RED)]
    objs.append(T.box((18.6, 10.6, 0.6), (0, 0, 9.3), mat=WOOD))
    window_grid(objs, -8.0, 8.0, 4.8, 1, -5.0, w=1.6, h=2.4, step=3.2, mat=DARK, frame=WOOD)
    objs.append(T.box((7.0, 0.3, 3.4), (0, -5.15, 1.7), mat=DARK))
    objs.append(T.box((9.0, 1.6, 0.4), (0, -5.6, 3.7), mat=RED))
    sign = T.text("MOULIN ROUGE", 1.15, (0, -5.32, 8.0), mat=LIGHTS, depth=0.08)
    objs.append(sign)
    # the windmill on the roof, front left
    mx, my = -5.0, -1.0
    objs.append(T.cyl(2.6, 7.5, (mx, my, 13.35), mat=RED, n=16, r2=2.1))
    objs.append(T.lathe([(2.5, 17.1), (2.7, 17.4), (0.0, 20.0)], (mx, my, 0), mat=WOOD, n=16))
    for k in range(3):
        objs.append(T.box((1.0, 0.1, 1.3), (mx, my - 2.45, 11.5 + k * 2.0), mat=DARK))
    objs.append(T.cyl(0.35, 1.4, (mx, my - 2.6, 17.2), rot=(90, 0, 0), mat=WOOD, n=8))
    finish("moulin", objs)
    # the sails: four lattice blades round the hub at the origin, in the X/Z plane
    segs = []
    for k in range(4):
        a = k * math.pi * 0.5 + 0.4
        d = Vector((math.cos(a), 0, math.sin(a)))
        s = Vector((-math.sin(a), 0, math.cos(a)))
        segs.append(((0, 0, 0), tuple(d * 8.0), 0.3))
        for e in (0.0, 1.3):
            segs.append((tuple(d * 1.6 + s * e), tuple(d * 8.0 + s * e), 0.12))
        for j in range(8):
            r = 1.6 + j * 0.9
            segs.append((tuple(d * r), tuple(d * r + s * 1.3), 0.1))
    sails = beams("moulin_sails", segs, WOOD)
    hub = T.cyl(0.6, 0.6, (0, 0, 0), rot=(90, 0, 0), mat=WOOD, n=10)
    items["moulin_sails"] = T.join([sails, hub], "moulin_sails")


# ------------------------------------------------------------------ buildings

def notre_dame():
    objs = []
    L, NW, NH = 40.0, 11.0, 21.0  # nave (Y from -20 to +20), nave width and wall height
    objs.append(T.box((NW, L - 8.0, NH), (0, 1.0, NH / 2), mat=CATHEDRAL))
    objs.append(T.prism([(-NW / 2 - 0.4, NH), (NW / 2 + 0.4, NH), (0, NH + 8.5)], L - 8.5, (0, 1.0, 0), mat=SLATE, plane="XZ"))
    for sx in (-1, 1):  # aisles, buttresses, flying buttresses
        objs.append(T.box((5.0, L - 10.0, 11.0), (sx * (NW / 2 + 2.5), 1.0, 5.5), mat=CATHEDRAL))
        objs.append(T.prism([(0, 11.0), (5.4 * sx, 11.0), (0, 13.2)] if sx > 0 else [(-5.4, 11.0), (0, 11.0), (0, 13.2)],
                            L - 10.0, (sx * NW / 2, 1.0, 0), mat=SLATE, plane="XZ"))
        for k in range(7):
            y = -12.0 + k * 4.4
            objs.append(T.box((1.2, 1.4, 16.0), (sx * (NW / 2 + 6.0), y, 8.0), mat=CATHEDRAL))
            objs.append(T.cyl(0.55, 2.4, (sx * (NW / 2 + 6.0), y, 17.2), mat=CATHEDRAL, n=6, r2=0.05))
            fb = T.box((5.8, 0.7, 0.8), (sx * (NW / 2 + 3.0), y, 16.0), rot=(0, sx * 28, 0), mat=CATHEDRAL)
            objs.append(fb)
        window_grid(objs, -14.0, 16.0, 13.0, 1, sx * (NW / 2), w=1.6, h=5.0, step=4.4, face=sx, axis="Y")
        window_grid(objs, -14.0, 16.0, 3.5, 1, sx * (NW / 2 + 5.0), w=1.4, h=4.4, step=4.4, face=sx, axis="Y")
    # transept with its rose windows, apse
    objs.append(T.box((NW + 14.0, 7.0, NH), (0, 6.0, NH / 2), mat=CATHEDRAL))
    tr = T.prism([(-3.9, NH), (3.9, NH), (0, NH + 6.0)], NW + 14.6, (0, 6.0, 0), mat=SLATE, plane="YZ")
    objs.append(tr)
    for sx in (-1, 1):
        objs.append(T.cyl(2.6, 0.3, (sx * (NW / 2 + 7.05), 6.0, 14.0), rot=(0, 90, 0), mat=GLASS, n=20))
        objs.append(T.cyl(2.9, 0.2, (sx * (NW / 2 + 7.0), 6.0, 14.0), rot=(0, 90, 0), mat=CATHEDRAL, n=20))
    objs.append(T.cyl(NW / 2, NH, (0, L / 2 - 3.0, NH / 2), mat=CATHEDRAL, n=16))
    objs.append(T.lathe([(NW / 2 + 0.4, NH), (0.0, NH + 7.5)], (0, L / 2 - 3.0, 0), mat=SLATE, n=16))
    # the spire at the crossing
    objs.append(T.cyl(1.6, 6.0, (0, 6.0, NH + 9.0), mat=SLATE, n=8))
    objs.append(T.cyl(1.5, 18.0, (0, 6.0, NH + 21.0), mat=SLATE, n=8, r2=0.05))
    # the west front: two towers, the gallery between, the rose, three portals
    fy = -L / 2 + 3.0
    for sx in (-1, 1):
        t = T.box((8.5, 8.0, 34.0), (sx * 6.75, fy, 17.0), mat=CATHEDRAL)
        objs.append(t)
        objs.append(T.box((9.1, 8.6, 0.8), (sx * 6.75, fy, 34.2), mat=CATHEDRAL))
        for k in range(2):
            objs.append(T.box((2.0, 0.2, 9.0), (sx * 6.75 + (k - 0.5) * 3.2, fy - 4.05, 27.5), mat=DARK))
        for cx in (-1, 1):
            for cy in (-1, 1):
                objs.append(T.cyl(0.4, 1.6, (sx * 6.75 + cx * 3.9, fy + cy * 3.6, 35.2), mat=CATHEDRAL, n=6, r2=0.08))
    objs.append(T.box((5.0, 8.0, 30.0), (0, fy, 15.0), mat=CATHEDRAL))
    objs.append(T.box((22.0, 1.0, 1.0), (0, fy - 4.3, 22.5), mat=CATHEDRAL))
    objs.append(T.cyl(4.0, 0.3, (0, fy - 4.15, 17.0), rot=(90, 0, 0), mat=GLASS, n=24))
    objs.append(T.cyl(4.4, 0.2, (0, fy - 4.05, 17.0), rot=(90, 0, 0), mat=CATHEDRAL, n=24))
    objs.append(T.box((22.0, 0.8, 2.0), (0, fy - 4.2, 10.5), mat=STONE_DK))  # gallery of kings
    for x in (-6.75, 0.0, 6.75):
        objs.append(arch_door(x, fy - 4.05, 4.0 if x == 0 else 3.4, 8.0 if x == 0 else 7.0))
    finish("notre_dame", objs)


def arch_door(x, y, w, h):
    pts = [(-w / 2, 0.0), (w / 2, 0.0)]
    for k in range(9):
        a = math.pi * k / 8
        pts.append((w / 2 * math.cos(a), h - w / 2 + w / 2 * 1.25 * math.sin(a)))
    return T.prism(pts, 0.2, (x, y, 0), mat=DARK, plane="XZ")


def sacre_coeur():
    objs = []
    objs.append(T.box((26.0, 18.0, 14.0), (0, 0, 7.0), mat=WHITE))
    objs.append(T.box((27.0, 19.0, 1.0), (0, 0, 14.4), mat=WHITE, bevel=0.1))
    objs.append(T.box((10.0, 6.0, 12.0), (0, -11.5, 6.0), mat=WHITE))  # porch
    for x in (-3.2, 0.0, 3.2):
        objs.append(arch_door(x, -14.55, 2.6, 7.0))
    for sx in (-1, 1):  # the two small domes over the porch, the corner domes
        objs.append(T.cyl(1.6, 3.0, (sx * 4.0, -11.5, 13.5), mat=WHITE, n=12))
        dome(objs, 1.8, 15.0, 2.6, WHITE, n=12, onion=0.15, lantern=(0.3, 0.8), at=(sx * 4.0, -11.5))
        for sy in (-1, 1):
            objs.append(T.cyl(2.2, 4.0, (sx * 9.5, sy * 6.0, 16.9), mat=WHITE, n=14))
            dome(objs, 2.4, 18.9, 3.8, WHITE, n=14, onion=0.2, lantern=(0.35, 1.0), at=(sx * 9.5, sy * 6.0))
    # the great dome on its drum with arched windows
    objs.append(T.cyl(6.2, 9.0, (0, 1.0, 19.4), mat=WHITE, n=24))
    for k in range(12):
        a = k * math.tau / 12
        objs.append(T.box((1.0, 0.2, 3.6), (math.cos(a) * 6.25, 1.0 + math.sin(a) * 6.25, 19.6), rot=(0, 0, math.degrees(a) + 90), mat=DARK))
        objs.append(T.box((0.6, 0.6, 9.0), (math.cos(a + 0.26) * 6.4, 1.0 + math.sin(a + 0.26) * 6.4, 19.4), mat=WHITE))
    dome(objs, 6.4, 23.9, 10.0, WHITE, n=28, onion=0.18, lantern=(0.9, 3.2), at=(0.0, 1.0))
    # the campanile at the back
    objs.append(T.box((5.0, 5.0, 26.0), (0, 11.0, 13.0), mat=WHITE))
    for k in range(4):
        a = k * math.pi * 0.5
        objs.append(T.box((2.4, 0.2, 5.0), (math.sin(a) * 2.55, 11.0 - math.cos(a) * 2.55, 22.0), rot=(0, 0, math.degrees(a)), mat=DARK))
    dome(objs, 2.8, 26.0, 4.0, WHITE, n=14, onion=0.15, lantern=(0.4, 1.2), at=(0.0, 11.0))
    window_grid(objs, -12.0, 12.0, 4.0, 2, -9.0, w=1.2, h=3.2, step=3.0, floor_h=5.0, mat=DARK)
    finish("sacre_coeur", objs)


def invalides():
    objs = [T.box((34.0, 34.0, 15.0), (0, 0, 7.5), mat=STONE)]
    objs.append(T.box((35.0, 35.0, 1.0), (0, 0, 15.3), mat=STONE, bevel=0.1))
    window_grid(objs, -15.0, 15.0, 3.0, 2, -17.0, w=1.6, h=3.4, step=3.8, floor_h=6.0, mat=DARK, frame=STONE_DK)
    # portico: two storeys of columns, pediment
    for k in range(8):
        x = -7.0 + k * 2.0
        objs.append(T.cyl(0.5, 7.0, (x, -17.6, 3.5), mat=STONE, n=10))
        objs.append(T.cyl(0.42, 6.0, (x, -17.6, 10.0), mat=STONE, n=10))
    objs.append(T.box((17.0, 1.6, 1.0), (0, -17.6, 7.4), mat=STONE))
    objs.append(T.prism([(-8.8, 13.4), (8.8, 13.4), (0, 17.0)], 1.6, (0, -17.6, 0), mat=STONE, plane="XZ"))
    # drum with columns, the gold dome, lantern and spire
    objs.append(T.cyl(10.0, 4.0, (0, 0, 17.8), mat=STONE, n=32))
    objs.append(T.cyl(8.6, 10.0, (0, 0, 24.8), mat=STONE, n=32))
    for k in range(16):
        a = k * math.tau / 16
        objs.append(T.cyl(0.45, 9.0, (math.cos(a) * 9.2, math.sin(a) * 9.2, 24.8), mat=STONE, n=8))
        objs.append(T.box((1.3, 0.2, 4.0), (math.cos(a + 0.2) * 8.65, math.sin(a + 0.2) * 8.65, 24.5), rot=(0, 0, math.degrees(a + 0.2) + 90), mat=DARK))
    objs.append(T.cyl(9.6, 1.0, (0, 0, 30.3), mat=STONE, n=32))
    dome(objs, 9.0, 30.8, 12.0, GOLD, n=32, lantern=(1.3, 4.0))
    segs = []
    for k in range(16):
        a = k * math.tau / 16
        pts = []
        for j in range(9):
            t = j / 8.0
            r = 9.05 * math.cos(t * math.pi * 0.5)
            pts.append(Vector((math.cos(a) * r, math.sin(a) * r, 30.8 + 12.0 * math.sin(t * math.pi * 0.5) + 0.05)))
        for j in range(8):
            segs.append((tuple(pts[j]), tuple(pts[j + 1]), 0.35))
    objs.append(beams("ribs", segs, STONE_DK))
    objs.append(T.cyl(0.25, 9.0, (0, 0, 52.5), mat=GOLD, n=6, r2=0.05))
    finish("invalides", objs)


def opera():
    objs = [T.box((48.0, 34.0, 20.0), (0, 2.0, 10.0), mat=STONE)]
    # loggia of paired columns over an arcade, attic with gilded groups
    objs.append(T.box((44.0, 2.0, 7.0), (0, -15.5, 3.5), mat=STONE))
    for k in range(7):
        objs.append(arch_door(-15.0 + k * 5.0, -16.55, 3.2, 6.0))
    for k in range(8):
        x = -17.5 + k * 5.0
        for dx in (-0.6, 0.6):
            objs.append(T.cyl(0.45, 9.0, (x + dx, -16.3, 11.5), mat=STONE_DK, n=10))
        if k < 7:
            objs.append(T.box((3.2, 0.2, 6.0), (x + 2.5, -15.6, 11.5), mat=DARK))
    objs.append(T.box((46.0, 2.6, 1.6), (0, -15.8, 16.8), mat=STONE, bevel=0.1))
    objs.append(T.box((44.0, 2.0, 3.6), (0, -15.6, 19.4), mat=STONE_DK))
    for sx in (-1, 1):
        objs.append(T.box((6.0, 6.0, 24.0), (sx * 21.0, -14.0, 12.0), mat=STONE))
        objs.append(T.sphere(1.6, (sx * 21.0, -14.0, 25.6), mat=GOLD, n=10, scale=(1.0, 1.0, 1.6)))
        objs.append(T.box((0.6, 0.6, 3.0), (sx * 21.0, -14.0, 28.8), mat=GOLD))
    # the low green dome over the auditorium, the stage house roof behind
    dome(objs, 12.0, 20.0, 7.0, COPPER, n=32, lantern=(1.2, 2.5), at=(0.0, 2.0))
    objs.append(T.box((30.0, 12.0, 8.0), (0, 13.0, 24.0), mat=STONE))
    objs.append(T.prism([(-15.5, 28.0), (15.5, 28.0), (0, 35.0)], 12.6, (0, 13.0, 0), mat=COPPER, plane="XZ"))
    objs.append(T.sphere(1.2, (0, 7.0, 35.5), mat=GOLD, n=10, scale=(1.0, 1.0, 1.8)))
    window_grid(objs, -22.0, 22.0, 4.0, 2, 19.0, w=1.6, h=3.0, step=4.0, floor_h=6.0, face=1, mat=DARK)
    finish("opera", objs)


def chaillot():
    objs = [T.box((26.0, 8.0, 15.0), (0, 0, 7.5), mat=STONE)]
    for k in range(12):
        x = -11.9 + k * 2.16
        objs.append(T.box((0.9, 0.9, 10.0), (x, -4.6, 8.0), mat=STONE))
        objs.append(T.box((1.4, 0.2, 7.0), (x + 1.08, -4.05, 7.5), mat=DARK) if k < 11 else None)
    objs.append(T.box((26.6, 2.2, 1.2), (0, -4.0, 13.6), mat=STONE, bevel=0.1))
    objs.append(T.box((26.6, 9.2, 0.6), (0, 0, 15.3), mat=STONE, bevel=0.05))
    objs.append(T.box((27.0, 9.6, 2.4), (0, 0, 1.2), mat=STONE_DK))
    objs.append(T.text("LA VIE EST BREVE", 0.8, (0, -4.62, 12.0), mat=GOLD, depth=0.06))
    finish("chaillot", objs)


def louvre_wing():
    objs = [T.box((30.0, 16.0, 17.0), (0, 0, 8.5), mat=STONE)]
    for k in range(10):  # ground arcade
        objs.append(arch_door(-13.5 + k * 3.0, -8.05, 2.0, 4.8))
    for k in range(11):
        objs.append(T.box((0.7, 0.4, 11.0), (-15.0 + k * 3.0, -8.1, 11.0), mat=STONE))
    window_grid(objs, -15.0, 15.0, 7.0, 2, -8.0, w=1.4, h=3.0, step=3.0, floor_h=4.8, mat=DARK, frame=STONE_DK)
    objs.append(T.box((30.0, 16.8, 1.0), (0, 0, 17.3), mat=STONE, bevel=0.1))
    mansard_roof(objs, 30.0, 16.0, 17.8, 5.0, SLATE, inset=2.2)
    for k in range(5):  # dormers
        x = -12.0 + k * 6.0
        objs.append(T.box((1.8, 2.0, 2.4), (x, -6.6, 19.6), mat=STONE))
        objs.append(T.box((1.0, 0.1, 1.5), (x, -7.65, 19.5), mat=DARK))
    finish("louvre_wing", objs)


def louvre_pavilion():
    objs = [T.box((18.0, 18.0, 19.0), (0, 0, 9.5), mat=STONE)]
    for k in range(4):
        x = -6.0 + k * 4.0
        objs.append(T.cyl(0.5, 12.0, (x, -9.3, 9.0), mat=STONE, n=10))
    window_grid(objs, -8.0, 8.0, 5.0, 2, -9.0, w=1.4, h=3.0, step=4.0, floor_h=5.5, mat=DARK, frame=STONE_DK)
    objs.append(T.prism([(-8.0, 15.5), (8.0, 15.5), (0, 18.4)], 1.2, (0, -9.2, 0), mat=STONE, plane="XZ"))
    objs.append(T.box((18.8, 18.8, 1.0), (0, 0, 19.4), mat=STONE, bevel=0.1))
    mansard_roof(objs, 17.0, 17.0, 19.9, 8.0, SLATE, inset=4.0)
    objs.append(T.box((9.4, 9.4, 1.5), (0, 0, 28.6), mat=SLATE))
    finish("louvre_pavilion", objs)


# ------------------------------------------------------------------ build, bake, export

if PART == "tower":
    eiffel()
    size = 2048
elif PART == "monuments":
    arc()
    obelisk()
    fountain()
    pyramid()
    moulin()
    size = 2048
else:
    notre_dame()
    sacre_coeur()
    invalides()
    opera()
    chaillot()
    louvre_wing()
    louvre_pavilion()
    size = 4096

objs = list(items.values())
print("triangles:", {n: T.tri_count([o]) for n, o in items.items()})
shape = next((sys.argv[i + 1] for i, a in enumerate(sys.argv) if a == "--shape"), None)
if shape:
    T.preview(shape, objs, eye=(120, -160, 90) if PART == "tower" else (70, -90, 50), look=(0, 0, 40 if PART == "tower" else 10), fov=40)
    sys.exit(0)
T.unwrap(objs, margin=0.002)
if "--nobake" not in sys.argv:
    g = T.gbuffer(objs, size=size, ao_dist=1.2, bevel_r=0.03)
    al, nm, orm = T.weather(g, (), seed=29, dust_from=0.0, dust_to=2.0, ao_strength=0.7)
    T.save_maps("paris_" + PART, al, nm, orm)
T.export_glb("paris_" + PART, objs)
print("ok")

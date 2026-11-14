"""Twisted Metal project: Blender asset pipeline (round 10).

Models are built by scripts with this library, baked to a texture atlas and exported as .glb for
Godot. Run with Blender as a Python module (no window needed):

    python3.13 -m venv /tmp/bpy && /tmp/bpy/bin/pip install bpy==5.3.0 pillow
    /tmp/bpy/bin/python tools/blender/build_pickups.py

Conventions (Blender space): +X right, +Y forward (the nose of a car), +Z up, metres. The glTF
export turns that into the game's space (cars face -Z, Y up).

How an asset is made:
  1. Geometry from the helpers below (box, cyl, lathe, loft, ...). Every part gets a material from
     M(kind, colour): the kind ("paint", "steel", "rubber", "concrete", ...) says how it weathers.
  2. bake(...) unwraps everything into one atlas and bakes a small G-buffer with Cycles (base colour,
     position, normal, ambient occlusion, edge mask, a bevelled tangent normal).
  3. The weathering is composited from that in numpy (weather()): paint chipped along the edges,
     rust in the cavities, streaks, dust low down and on top, baked occlusion; stencils and stripes
     are projected on as decals first, so they wear too. No hand-painted or downloaded textures.
  4. Albedo, normal and ORM (occlusion, roughness, metallic) are saved next to the .glb.
Glass and lights are not baked: they keep the material names "glass" and "glow" (vertex colours).
"""

import math
import os

import bpy  # first: it puts bmesh and mathutils on the path
import bmesh
import numpy as np
from mathutils import Euler, Matrix, Vector
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "models")
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_COND = "/usr/share/fonts/truetype/liberation/LiberationSansNarrow-Bold.ttf"

_mats = {}
_kinds = []  # index -> dict(kind=..., params)


# ------------------------------------------------------------------ scene

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()
    _kinds.clear()
    s = bpy.context.scene
    s.unit_settings.system = "METRIC"
    s.render.engine = "CYCLES"
    s.cycles.device = "CPU"
    s.cycles.use_denoising = False
    return s


def _link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _activate(ob, others=()):
    bpy.context.view_layer.update()
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in others:
        o.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


# ------------------------------------------------------------------ materials

def M(kind, color=(0.5, 0.5, 0.5), wear=0.5, rust=0.3, dirt=0.5, rough=None, name=None):
    """A weathering material: `kind` picks the recipe in weather(), colour is the clean base colour
    (linear RGB), wear/rust/dirt (0..1) say how far gone it is."""
    key = (kind, tuple(round(c, 4) for c in color), round(wear, 3), round(rust, 3), round(dirt, 3), rough)
    if key in _mats:
        return _mats[key]
    idx = len(_kinds)
    m = bpy.data.materials.new(name or "%s_%02d" % (kind, idx))
    m.use_nodes = True
    m["tm_idx"] = idx
    m.diffuse_color = (*color, 1.0)
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.6
        if kind in ("steel", "chrome"):
            bsdf.inputs["Metallic"].default_value = 0.9
    _kinds.append(dict(kind=kind, color=color, wear=wear, rust=rust, dirt=dirt, rough=rough))
    _mats[key] = m
    return m


def glass(tint=(0.03, 0.04, 0.05)):
    """Not baked: exported with the material name 'glass'."""
    if "glass" not in _mats:
        m = bpy.data.materials.new("glass")
        m.use_nodes = True
        m.diffuse_color = (*tint, 1.0)
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = (*tint, 1.0)
        b.inputs["Roughness"].default_value = 0.08
        m["tm_special"] = "glass"
        _mats["glass"] = m
    return _mats["glass"]


def glow(color=(1.0, 0.8, 0.5), name="glow"):
    """Not baked: lights. The colour is written to vertex colours; material name 'glow'."""
    key = ("glow", tuple(round(c, 3) for c in color))
    if key not in _mats:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        m.diffuse_color = (*color, 1.0)
        nt = m.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs[0].default_value = (*color, 1.0)
        em.inputs[1].default_value = 3.0
        nt.links.new(em.outputs[0], out.inputs[0])
        m["tm_special"] = "glow"
        m["tm_color"] = color
        _mats[key] = m
    return _mats[key]


def _is_baked(mat):
    return mat is not None and "tm_idx" in mat.keys()


# ------------------------------------------------------------------ geometry

def _new_obj(name, bm, mat=None, loc=(0, 0, 0), rot=(0, 0, 0), smooth=None):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    ob.rotation_euler = Euler([math.radians(a) for a in rot], "XYZ")
    _link(ob)
    if mat is not None:
        me.materials.append(mat)
    if smooth is not None:
        shade(ob, smooth)
    return ob


def shade(ob, angle=40.0):
    """Smooth shading with hard edges where faces meet at more than `angle` degrees."""
    me = ob.data
    for p in me.polygons:
        p.use_smooth = True
    me.set_sharp_from_angle(angle=math.radians(angle))
    return ob


def box(size, loc=(0, 0, 0), rot=(0, 0, 0), mat=None, bevel=0.0, segs=1, name="box", taper=None):
    """Box of full size (x, y, z) centred on loc. bevel = real rounded edges (metres).
    taper = (sx, sy): scale of the top face (wedges, tapered housings)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
        if taper and v.co.z > 0:
            v.co.x *= taper[0]
            v.co.y *= taper[1]
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=segs, profile=0.5, affect="EDGES")
    return _new_obj(name, bm, mat, loc, rot, 35.0 if bevel > 0 else None)


def cyl(r, h, loc=(0, 0, 0), rot=(0, 0, 0), mat=None, n=16, r2=None, bevel=0.0, name="cyl", caps=True):
    """Cylinder along local Z, centred on loc. r2 = top radius (cones, tapers)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=n, radius1=r, radius2=r if r2 is None else r2, depth=h)
    if bevel > 0.0:
        rim = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-5]
        bmesh.ops.bevel(bm, geom=rim, offset=bevel, segments=2, profile=0.5, affect="EDGES")
    return _new_obj(name, bm, mat, loc, rot, 40.0)


def sphere(r, loc=(0, 0, 0), mat=None, n=16, scale=(1, 1, 1), name="sphere"):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=n, v_segments=max(6, n // 2), radius=r)
    for v in bm.verts:
        v.co.x *= scale[0]
        v.co.y *= scale[1]
        v.co.z *= scale[2]
    return _new_obj(name, bm, mat, loc, (0, 0, 0), 60.0)


def lathe(profile, loc=(0, 0, 0), rot=(0, 0, 0), mat=None, n=20, name="lathe", angle=40.0):
    """Surface of revolution about local Z. profile = [(radius, z), ...] from bottom to top;
    ends at radius 0 are closed to a point, others are capped."""
    bm = bmesh.new()
    rings = []
    for (r, z) in profile:
        if r <= 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((r * math.cos(2 * math.pi * k / n), r * math.sin(2 * math.pi * k / n), z)) for k in range(n)])
    for a, b in zip(rings[:-1], rings[1:]):
        for k in range(n):
            k2 = (k + 1) % n
            if len(a) == 1 and len(b) == 1:
                continue
            if len(a) == 1:
                bm.faces.new((a[0], b[k], b[k2]))
            elif len(b) == 1:
                bm.faces.new((a[k], a[k2], b[0]))
            else:
                bm.faces.new((a[k], a[k2], b[k2], b[k]))
    if len(rings[0]) > 1:
        bm.faces.new(list(reversed(rings[0])))
    if len(rings[-1]) > 1:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return _new_obj(name, bm, mat, loc, rot, angle)


def prism(points, depth, loc=(0, 0, 0), rot=(0, 0, 0), mat=None, bevel=0.0, name="prism", plane="XZ"):
    """A 2D outline (counter-clockwise list of (a, b)) extruded by `depth`, centred on its depth.
    plane "XZ": outline in X/Z, extruded along Y. "YZ": outline in Y/Z, extruded along X.
    "XY": outline in X/Y, extruded along Z."""
    bm = bmesh.new()
    def P(a, b, d):
        return {"XZ": (a, d, b), "YZ": (d, a, b), "XY": (a, b, d)}[plane]
    front = [bm.verts.new(P(a, b, -depth * 0.5)) for a, b in points]
    back = [bm.verts.new(P(a, b, depth * 0.5)) for a, b in points]
    n = len(points)
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for k in range(n):
        k2 = (k + 1) % n
        bm.faces.new((front[k], back[k], back[k2], front[k2]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=1, profile=0.5, affect="EDGES")
    return _new_obj(name, bm, mat, loc, rot, 35.0)


def loft(sections, mat=None, name="loft", closed=True, caps=True, angle=45.0):
    """Skin through sections (each a list of (x, y, z), same count). closed = each section is a loop."""
    bm = bmesh.new()
    rings = [[bm.verts.new(p) for p in sec] for sec in sections]
    n = len(rings[0])
    for a, b in zip(rings[:-1], rings[1:]):
        for k in range(n if closed else n - 1):
            k2 = (k + 1) % n
            bm.faces.new((a[k], a[k2], b[k2], b[k]))
    if caps and closed:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return _new_obj(name, bm, mat, (0, 0, 0), (0, 0, 0), angle)


def tube(points, r, mat=None, n=8, name="tube"):
    """A pipe of radius r through the points (bends are mitred)."""
    pts = [Vector(p) for p in points]
    secs = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        up = Vector((0, 0, 1)) if abs(d.z) < 0.95 else Vector((1, 0, 0))
        a = d.cross(up).normalized()
        b = d.cross(a).normalized()
        secs.append([tuple(p + (a * math.cos(2 * math.pi * k / n) + b * math.sin(2 * math.pi * k / n)) * r) for k in range(n)])
    return loft(secs, mat, name, True, True, 50.0)


def text(s, size, loc=(0, 0, 0), rot=(90, 0, 0), mat=None, depth=0.01, name="text", align="CENTER"):
    """Text as geometry (use decals for painted lettering; this is for raised letters and signs)."""
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = s
    cu.size = size
    cu.extrude = depth * 0.5
    cu.align_x = align
    cu.align_y = "CENTER"
    cu.resolution_u = 2
    ob = bpy.data.objects.new(name, cu)
    _link(ob)
    ob.location = loc
    ob.rotation_euler = Euler([math.radians(a) for a in rot], "XYZ")
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob)
    mo = bpy.data.objects.new(name, me)
    mo.location = loc
    mo.rotation_euler = Euler([math.radians(a) for a in rot], "XYZ")
    _link(mo)
    if mat is not None:
        me.materials.append(mat)
    return mo


def apply(ob):
    """Bake the object's transform and modifiers into its mesh."""
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    me.transform(ob.matrix_world)
    ob.modifiers.clear()
    ob.data = me
    ob.matrix_world = Matrix.Identity(4)
    return ob


def cut(ob, cutter, keep=False, solver="EXACT"):
    """Boolean difference: ob minus cutter."""
    m = ob.modifiers.new("cut", "BOOLEAN")
    m.operation = "DIFFERENCE"
    m.object = cutter
    m.solver = solver
    bpy.context.view_layer.update()
    apply(ob)
    if not keep:
        bpy.data.objects.remove(cutter)
    return ob


def bevel(ob, width=0.02, segments=2, angle=30.0):
    m = ob.modifiers.new("bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    m.harden_normals = False
    bpy.context.view_layer.update()
    apply(ob)
    return shade(ob, 35.0)


def subsurf(ob, levels=1):
    m = ob.modifiers.new("sub", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    bpy.context.view_layer.update()
    apply(ob)
    return shade(ob, 50.0)


def decimate(ob, ratio):
    m = ob.modifiers.new("dec", "DECIMATE")
    m.ratio = ratio
    bpy.context.view_layer.update()
    return apply(ob)


def dup(ob, loc=None, rot=None, scale=None, name=None):
    o = ob.copy()
    o.data = ob.data.copy()
    _link(o)
    if loc is not None:
        o.location = loc
    if rot is not None:
        o.rotation_euler = Euler([math.radians(a) for a in rot], "XYZ")
    if scale is not None:
        o.scale = scale
    if name:
        o.name = name
    return o


def mirror(ob, axis="X"):
    """A mirrored copy across the world plane (X: left/right)."""
    o = dup(ob)
    bpy.context.view_layer.update()
    apply(o)
    i = "XYZ".index(axis)
    for v in o.data.vertices:
        v.co[i] = -v.co[i]
    o.data.flip_normals()
    o.data.update()
    return o


def join(objs, name="joined"):
    objs = [o for o in objs if o is not None]
    bpy.context.view_layer.update()
    for o in objs:
        apply(o)
    bm = bmesh.new()
    mats = []
    for o in objs:
        remap = []
        for m in o.data.materials:
            if m not in mats:
                mats.append(m)
            remap.append(mats.index(m))
        tmp = bmesh.new()
        tmp.from_mesh(o.data)
        off = len(bm.verts)
        vs = [bm.verts.new(v.co) for v in tmp.verts]
        for f in tmp.faces:
            try:
                nf = bm.faces.new([vs[v.index] for v in f.verts])
            except ValueError:
                continue
            nf.material_index = remap[f.material_index] if remap else 0
            nf.smooth = f.smooth
        # keep sharp edges
        bm.edges.ensure_lookup_table()
        for e in tmp.edges:
            if not e.smooth:
                ne = bm.edges.get((vs[e.verts[0].index], vs[e.verts[1].index]))
                if ne:
                    ne.smooth = False
        tmp.free()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    for o in objs:
        bpy.data.objects.remove(o)
    ob = bpy.data.objects.new(name, me)
    _link(ob)
    return ob


def tri_count(objs):
    n = 0
    for o in objs:
        n += sum(len(p.vertices) - 2 for p in o.data.polygons)
    return n


# ------------------------------------------------------------------ decals

class Decal:
    """A picture projected onto the model before weathering (stencils, stripes, numbers).
    centre: where it sits; normal: the way the painted face looks; up: the picture's up;
    size (w, h) in metres; depth: how far through the surface it reaches."""

    def __init__(self, image, center, normal, up, size, depth=0.25, kinds=("paint", "steel", "concrete", "plastic", "wood"), opacity=1.0):
        self.image = np.asarray(image.convert("RGBA"), dtype=np.float32) / 255.0
        self.center = np.array(center, dtype=np.float32)
        n = Vector(normal).normalized()
        u = Vector(up).normalized()
        r = u.cross(n).normalized()
        self.n = np.array(n, dtype=np.float32)
        self.u = np.array(u, dtype=np.float32)
        self.r = np.array(r, dtype=np.float32)
        self.size = size
        self.depth = depth
        self.kinds = kinds
        self.opacity = opacity


def stencil(s, color=(0.9, 0.9, 0.85), px=128, font=FONT_BOLD, bridges=True, pad=0.15):
    """Sprayed stencil lettering as an RGBA picture (sRGB colour given linear)."""
    f = ImageFont.truetype(font, px)
    box = f.getbbox(s)
    w, h = box[2] - box[0], box[3] - box[1]
    padx = int(px * pad)
    im = Image.new("L", (w + padx * 2, h + padx * 2), 0)
    d = ImageDraw.Draw(im)
    d.text((padx - box[0], padx - box[1]), s, font=f, fill=255)
    if bridges:  # the little gaps a cut stencil leaves
        a = np.asarray(im).copy()
        step = max(8, px // 2)
        for x in range(step // 2, a.shape[1], step):
            a[:, x:x + max(2, px // 22)] = 0
        im = Image.fromarray(a)
    im = im.filter(ImageFilter.GaussianBlur(px / 90.0))  # soft sprayed edge
    rgb = _to_srgb(np.array(color, dtype=np.float32))
    out = np.zeros((im.size[1], im.size[0], 4), dtype=np.uint8)
    out[..., :3] = (rgb * 255).astype(np.uint8)
    out[..., 3] = np.asarray(im)
    return Image.fromarray(out, "RGBA")


def flat_image(color, alpha=1.0, size=(8, 8)):
    rgb = _to_srgb(np.array(color, dtype=np.float32))
    out = np.zeros((size[1], size[0], 4), dtype=np.uint8)
    out[..., :3] = (rgb * 255).astype(np.uint8)
    out[..., 3] = int(alpha * 255)
    return Image.fromarray(out, "RGBA")


def hazard_image(a=(0.75, 0.6, 0.08), b=(0.04, 0.04, 0.04), stripes=6, size=(256, 64)):
    """Diagonal warning stripes."""
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w]
    k = ((xx + yy) * stripes / w).astype(int) % 2
    ca = (_to_srgb(np.array(a, dtype=np.float32)) * 255).astype(np.uint8)
    cb = (_to_srgb(np.array(b, dtype=np.float32)) * 255).astype(np.uint8)
    out = np.zeros((h, w, 4), dtype=np.uint8)
    out[..., :3] = np.where(k[..., None] == 0, ca, cb)
    out[..., 3] = 255
    return Image.fromarray(out, "RGBA")


def cross_image(bg, fg=(0.9, 0.9, 0.86), px=256, arm=0.2, reach=0.34):
    """A plain cross on a coloured field (medical cases)."""
    im = Image.new("RGBA", (px, px), tuple(int(c * 255) for c in _to_srgb(np.array(bg, dtype=np.float32))) + (255,))
    d = ImageDraw.Draw(im)
    c = px / 2
    col = tuple(int(v * 255) for v in _to_srgb(np.array(fg, dtype=np.float32))) + (255,)
    d.rectangle([c - px * reach, c - px * arm / 2, c + px * reach, c + px * arm / 2], fill=col)
    d.rectangle([c - px * arm / 2, c - px * reach, c + px * arm / 2, c + px * reach], fill=col)
    return im


def holes_image(n=14, seed=1, size=(512, 256), r=(4, 9)):
    """Bullet strikes: a dark hole, a ring of bare metal, a few paint flakes round it."""
    rng = np.random.default_rng(seed)
    im = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for _ in range(n):
        x, y = rng.uniform(20, size[0] - 20), rng.uniform(20, size[1] - 20)
        rr = rng.uniform(*r)
        for k in range(6):
            a = rng.uniform(0, 6.283)
            q = rr * rng.uniform(1.3, 2.4)
            fr = rr * rng.uniform(0.25, 0.6)
            d.ellipse([x + math.cos(a) * q - fr, y + math.sin(a) * q - fr, x + math.cos(a) * q + fr, y + math.sin(a) * q + fr], fill=(118, 112, 106, 230))
        d.ellipse([x - rr * 1.5, y - rr * 1.5, x + rr * 1.5, y + rr * 1.5], fill=(128, 122, 116, 255))
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(8, 7, 7, 255))
    return im


def splatter_image(color=(0.11, 0.012, 0.01), n=60, seed=1, size=(256, 256)):
    """Dried spatter (blood, oil): one heavy patch thrown out into drops and runs."""
    rng = np.random.default_rng(seed)
    a = np.zeros((size[1], size[0]), dtype=np.float32)
    im = Image.new("L", size, 0)
    d = ImageDraw.Draw(im)
    cx, cy = size[0] * 0.5, size[1] * 0.42
    for _ in range(n):
        ang = rng.uniform(0, 6.283)
        dist = abs(rng.normal(0, size[0] * 0.2))
        x, y = cx + math.cos(ang) * dist, cy + math.sin(ang) * dist * 0.8
        rr = max(1.5, rng.uniform(2, 16) * (1.0 - dist / size[0] * 1.6))
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=int(rng.uniform(150, 255)))
        if rng.uniform() < 0.25:  # a run down
            d.line([x, y, x + rng.uniform(-2, 2), y + rng.uniform(15, 70)], fill=200, width=max(1, int(rr * 0.5)))
    im = im.filter(ImageFilter.GaussianBlur(1.2))
    rgb = _to_srgb(np.array(color, dtype=np.float32))
    out = np.zeros((size[1], size[0], 4), dtype=np.uint8)
    out[..., :3] = (rgb * 255).astype(np.uint8)
    out[..., 3] = np.asarray(im)
    return Image.fromarray(out, "RGBA")


def dots_image(color, n=18, seed=1, size=(512, 256), r=(14, 24), alpha=0.8):
    """Scattered painted dots (Sweet Tooth's polka dots, faded)."""
    rng = np.random.default_rng(seed)
    im = Image.new("L", size, 0)
    d = ImageDraw.Draw(im)
    placed = []
    tries = 0
    while len(placed) < n and tries < 2000:
        tries += 1
        x, y, rr = rng.uniform(30, size[0] - 30), rng.uniform(30, size[1] - 30), rng.uniform(*r)
        if all((x - px) ** 2 + (y - py) ** 2 > (rr + pr + 14) ** 2 for px, py, pr in placed):
            placed.append((x, y, rr))
            d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=int(255 * alpha))
    rgb = _to_srgb(np.array(color, dtype=np.float32))
    out = np.zeros((size[1], size[0], 4), dtype=np.uint8)
    out[..., :3] = (rgb * 255).astype(np.uint8)
    out[..., 3] = np.asarray(im)
    return Image.fromarray(out, "RGBA")


def lines_image(segments, size=(512, 512), width=3, color=(0.015, 0.015, 0.015), alpha=0.9):
    """Panel seams and door gaps: segments = [(x0, y0, x1, y1)] in 0..1 picture space."""
    im = Image.new("L", size, 0)
    d = ImageDraw.Draw(im)
    for (x0, y0, x1, y1) in segments:
        d.line([x0 * size[0], y0 * size[1], x1 * size[0], y1 * size[1]], fill=int(255 * alpha), width=width)
    rgb = _to_srgb(np.array(color, dtype=np.float32))
    out = np.zeros((size[1], size[0], 4), dtype=np.uint8)
    out[..., :3] = (rgb * 255).astype(np.uint8)
    out[..., 3] = np.asarray(im)
    return Image.fromarray(out, "RGBA")


def marker(name, loc):
    """An empty: exported as a named node, read by the game (wheel positions, muzzles, ...)."""
    ob = bpy.data.objects.new(name, None)
    ob.location = loc
    _link(ob)
    return ob


# ------------------------------------------------------------------ noise (numpy)

def _hash3(ix, iy, iz, seed):
    h = (ix.astype(np.uint32) * np.uint32(374761393) + iy.astype(np.uint32) * np.uint32(668265263)
         + iz.astype(np.uint32) * np.uint32(2147483647) + np.uint32(seed * 1013904223 & 0xFFFFFFFF))
    h = (h ^ (h >> np.uint32(13))) * np.uint32(1274126177)
    h = h ^ (h >> np.uint32(16))
    return (h & np.uint32(0xFFFFFF)).astype(np.float32) / np.float32(0xFFFFFF)


def vnoise(p, seed=0):
    """Value noise at points p (N, 3) -> (N,) in 0..1."""
    f = np.floor(p)
    t = (p - f).astype(np.float32)
    t = t * t * (3.0 - 2.0 * t)
    i = f.astype(np.int64)
    ix, iy, iz = i[:, 0], i[:, 1], i[:, 2]
    out = np.zeros(len(p), dtype=np.float32)
    for dx in (0, 1):
        wx = t[:, 0] if dx else 1.0 - t[:, 0]
        for dy in (0, 1):
            wy = t[:, 1] if dy else 1.0 - t[:, 1]
            for dz in (0, 1):
                wz = t[:, 2] if dz else 1.0 - t[:, 2]
                out += wx * wy * wz * _hash3(ix + dx, iy + dy, iz + dz, seed)
    return out


def fbm(p, scale=1.0, octaves=4, seed=0, stretch=(1, 1, 1)):
    """Fractal noise 0..1 at points p (N, 3). scale = features per metre."""
    q = p * (np.array(stretch, dtype=np.float32) * scale)
    out = np.zeros(len(p), dtype=np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += amp * vnoise(q, seed + o * 17)
        tot += amp
        amp *= 0.5
        q = q * 2.03 + 11.7
    return out / tot


def sstep(a, b, x):
    t = np.clip((x - a) / np.maximum(b - a, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _to_srgb(x):
    x = np.clip(x, 0.0, 1.0)
    return np.where(x < 0.0031308, x * 12.92, 1.055 * np.power(x, 1.0 / 2.4) - 0.055)


def _lerp(a, b, t):
    return a + (b - a) * t


# ------------------------------------------------------------------ bake

def _set_emit(mat, build):
    """Replace the material's nodes with: build(nodetree) -> output socket, fed to an emission."""
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(build(nt), em.inputs[0])
    nt.links.new(em.outputs[0], out.inputs[0])


def _target(mat, img):
    nt = mat.node_tree
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = img
    for x in nt.nodes:
        x.select = False
    n.select = True
    nt.nodes.active = n


def _pixels(img):
    w, h = img.size
    a = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(h, w, 4)[::-1].copy()  # row 0 = top (glTF / image convention)


def unwrap(objs, margin=0.004, angle=66.0):
    """One UV atlas over all the objects (islands packed together)."""
    for o in objs:
        if not o.data.uv_layers:
            o.data.uv_layers.new(name="UVMap")
    _activate(objs[0], objs)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin, area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.select_all(action="SELECT")
    try:
        bpy.ops.uv.pack_islands(margin=margin, rotate=True)
    except TypeError:
        bpy.ops.uv.pack_islands(margin=margin)
    bpy.ops.object.mode_set(mode="OBJECT")


def gbuffer(objs, size=1024, ao_samples=24, ao_dist=0.6, bevel_r=0.02, margin=6, height=None):
    """Bake the passes weather() needs for these objects (they share one atlas).
    Returns dict of (H, W, C) arrays: base, pos, nrm, ao, edge, idx, tnrm, cover."""
    scene = bpy.context.scene
    w = size
    h = height or size
    mats = []
    for o in objs:
        for m in o.data.materials:
            if _is_baked(m) and m not in mats:
                mats.append(m)
    others = []
    for o in objs:
        for m in o.data.materials:
            if m is not None and not _is_baked(m) and m not in others:
                if not m.use_nodes:
                    m.use_nodes = True
                others.append(m)
    # world bounds, to pack positions into 0..1
    lo = np.array([1e9] * 3)
    hi = np.array([-1e9] * 3)
    for o in objs:
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            lo = np.minimum(lo, p)
            hi = np.maximum(hi, p)
    lo -= 0.05
    span = (hi + 0.05) - lo
    saved = {m: None for m in mats}

    def run(kind, samples, build, bake_type="EMIT"):
        img = bpy.data.images.new("bake_" + kind, w, h, alpha=True, float_buffer=True, is_data=True)
        img.colorspace_settings.name = "Non-Color"
        for m in mats:
            if build is not None:
                _set_emit(m, lambda nt, mm=m: build(nt, mm))
            _target(m, img)
        for m in others:  # glow and glass slots need a target too, or Blender refuses to bake
            _target(m, img)
        scene.cycles.samples = samples
        first = True
        for o in objs:
            if not any(_is_baked(m) for m in o.data.materials):
                continue
            _activate(o)
            bpy.ops.object.bake(type=bake_type, margin=margin, use_clear=first, margin_type="EXTEND")
            first = False
        a = _pixels(img)
        bpy.data.images.remove(img)
        return a

    def b_base(nt, m):
        n = nt.nodes.new("ShaderNodeRGB")
        n.outputs[0].default_value = (*_kinds[m["tm_idx"]]["color"], 1.0)
        return n.outputs[0]

    def b_pos(nt, m):
        g = nt.nodes.new("ShaderNodeNewGeometry")
        vm = nt.nodes.new("ShaderNodeVectorMath")
        vm.operation = "MULTIPLY_ADD"
        nt.links.new(g.outputs["Position"], vm.inputs[0])
        vm.inputs[1].default_value = tuple(1.0 / span)
        vm.inputs[2].default_value = tuple(-lo / span)
        return vm.outputs[0]

    def b_nrm(nt, m):
        g = nt.nodes.new("ShaderNodeNewGeometry")
        vm = nt.nodes.new("ShaderNodeVectorMath")
        vm.operation = "MULTIPLY_ADD"
        nt.links.new(g.outputs["Normal"], vm.inputs[0])
        vm.inputs[1].default_value = (0.5, 0.5, 0.5)
        vm.inputs[2].default_value = (0.5, 0.5, 0.5)
        return vm.outputs[0]

    def b_mask(nt, m):
        g = nt.nodes.new("ShaderNodeNewGeometry")
        bv = nt.nodes.new("ShaderNodeBevel")
        bv.samples = 6
        bv.inputs["Radius"].default_value = bevel_r * 1.6
        dot = nt.nodes.new("ShaderNodeVectorMath")
        dot.operation = "DOT_PRODUCT"
        nt.links.new(bv.outputs[0], dot.inputs[0])
        nt.links.new(g.outputs["Normal"], dot.inputs[1])
        one = nt.nodes.new("ShaderNodeMath")
        one.operation = "SUBTRACT"
        one.inputs[0].default_value = 1.0
        nt.links.new(dot.outputs["Value"], one.inputs[1])
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        mul.use_clamp = True
        nt.links.new(one.outputs[0], mul.inputs[0])
        mul.inputs[1].default_value = 3.0
        ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.samples = 8
        ao.inputs["Distance"].default_value = ao_dist
        # the same edge test with a much wider radius: the zone near an edge where wear spreads
        bw = nt.nodes.new("ShaderNodeBevel")
        bw.samples = 6
        bw.inputs["Radius"].default_value = bevel_r * 7.0
        dw = nt.nodes.new("ShaderNodeVectorMath")
        dw.operation = "DOT_PRODUCT"
        nt.links.new(bw.outputs[0], dw.inputs[0])
        nt.links.new(g.outputs["Normal"], dw.inputs[1])
        ow = nt.nodes.new("ShaderNodeMath")
        ow.operation = "SUBTRACT"
        ow.inputs[0].default_value = 1.0
        nt.links.new(dw.outputs["Value"], ow.inputs[1])
        mw = nt.nodes.new("ShaderNodeMath")
        mw.operation = "MULTIPLY"
        mw.use_clamp = True
        nt.links.new(ow.outputs[0], mw.inputs[0])
        mw.inputs[1].default_value = 3.0
        comb = nt.nodes.new("ShaderNodeCombineColor")
        nt.links.new(mul.outputs[0], comb.inputs[0])
        nt.links.new(ao.outputs["AO"], comb.inputs[1])
        nt.links.new(mw.outputs[0], comb.inputs[2])
        return comb.outputs[0]

    def b_idx(nt, m):
        n = nt.nodes.new("ShaderNodeRGB")
        n.outputs[0].default_value = ((m["tm_idx"] + 0.5) / 64.0, 0.0, 0.0, 1.0)
        return n.outputs[0]

    base = run("base", 1, b_base)
    pos = run("pos", 1, b_pos)
    nrm = run("nrm", 1, b_nrm)
    mask = run("mask", ao_samples, b_mask)
    idxp = run("idx", 1, b_idx)
    # tangent-space normal with rounded edges (the Bevel node), from a plain BSDF
    for m in mats:
        nt = m.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        bs = nt.nodes.new("ShaderNodeBsdfDiffuse")
        bv = nt.nodes.new("ShaderNodeBevel")
        bv.samples = 8
        bv.inputs["Radius"].default_value = bevel_r
        nt.links.new(bv.outputs[0], bs.inputs["Normal"])
        nt.links.new(bs.outputs[0], out.inputs[0])
    tn = run("tnrm", 12, None, "NORMAL")
    cover = base[..., 3] > 0.5
    return dict(
        base=base[..., :3], pos=pos[..., :3] * span.astype(np.float32) + lo.astype(np.float32),
        nrm=nrm[..., :3] * 2.0 - 1.0, edge=mask[..., 0], ao=mask[..., 1], wide=mask[..., 2],
        idx=np.clip(np.round(idxp[..., 0] * 64.0 - 0.5), 0, 63).astype(np.int32), tnrm=tn[..., :3], cover=cover,
        lo=lo, span=span)


def _blur(a, r):
    if r <= 0:
        return a
    im = Image.fromarray(np.clip(a * 255.0, 0, 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r)), dtype=np.float32) / 255.0


# ------------------------------------------------------------------ weathering

RUST_A = np.array([0.20, 0.075, 0.03], dtype=np.float32)
RUST_B = np.array([0.36, 0.16, 0.06], dtype=np.float32)
RUST_DARK = np.array([0.07, 0.035, 0.02], dtype=np.float32)
BARE = np.array([0.22, 0.21, 0.20], dtype=np.float32)
PRIMER = np.array([0.32, 0.12, 0.08], dtype=np.float32)
DUST = np.array([0.27, 0.23, 0.18], dtype=np.float32)
SOOT = np.array([0.02, 0.018, 0.016], dtype=np.float32)


def weather(g, decals=(), seed=1, dust_from=0.0, dust_to=1.2, soot=None, ao_strength=0.85, detail=1.0, regions=()):
    """Composite albedo (sRGB), tangent normal and ORM from a G-buffer. dust_from/dust_to: heights (m)
    between which road dust fades out. soot: list of (centre, radius) scorch marks."""
    H, W = g["cover"].shape
    P = g["pos"].reshape(-1, 3).astype(np.float32)
    N = g["nrm"].reshape(-1, 3).astype(np.float32)
    base = g["base"].reshape(-1, 3).astype(np.float32).copy()
    idx = g["idx"].reshape(-1)
    ao = _blur(g["ao"], 0.8).reshape(-1)
    edge = _blur(g["edge"], 0.6).reshape(-1)
    nk = len(_kinds)
    idx = np.clip(idx, 0, max(nk - 1, 0)).copy()
    kind_names = [k["kind"] for k in _kinds]
    # painted regions: (fn(P, N) -> mask 0..1, linear colour, kinds[, material]). Bands round a
    # missile, colour blocks; with a material the surface there changes kind too (glass on a body).
    for reg in regions:
        fn, rcolor, rkinds = reg[0], reg[1], reg[2]
        ids = [i for i, n in enumerate(kind_names) if n in rkinds]
        mk = np.clip(fn(P, N), 0, 1) * np.isin(np.array([kind_names.index(k["kind"]) for k in _kinds])[idx], ids)
        if not mk.any():
            continue
        if len(reg) > 3 and reg[3] is not None:
            hit = mk > 0.5
            idx[hit] = reg[3]["tm_idx"]
            base[hit] = np.array(_kinds[reg[3]["tm_idx"]]["color"], dtype=np.float32)
        else:
            base = base * (1 - mk[:, None]) + np.array(rcolor, dtype=np.float32)[None, :] * mk[:, None]
    kind_of = np.array([kind_names.index(k["kind"]) for k in _kinds])[idx] if nk else idx
    def per(key, default=0.5):
        return np.array([(k[key] if k[key] is not None else default) for k in _kinds], dtype=np.float32)[idx]
    wear = per("wear")
    rust = per("rust")
    dirt = per("dirt")
    def is_kind(*names):
        ids = [i for i, n in enumerate(kind_names) if n in names]
        return np.isin(kind_of, ids)

    # decals go on the clean paint, so they chip and stain with it
    for d in decals:
        rel = P - d.center
        dn = rel @ d.n
        u = (rel @ d.r) / d.size[0] + 0.5
        v = 0.5 - (rel @ d.u) / d.size[1]
        ok = (np.abs(dn) < d.depth) & (u > 0) & (u < 1) & (v > 0) & (v < 1) & ((N @ d.n) > 0.35) & is_kind(*d.kinds)
        if not ok.any():
            continue
        ih, iw = d.image.shape[:2]
        px = np.clip((u[ok] * iw).astype(int), 0, iw - 1)
        py = np.clip((v[ok] * ih).astype(int), 0, ih - 1)
        tex = d.image[py, px]
        col = np.where(tex[:, :3] <= 0.04045, tex[:, :3] / 12.92, ((tex[:, :3] + 0.055) / 1.055) ** 2.4)
        a = (tex[:, 3:4] * d.opacity)
        base[ok] = base[ok] * (1 - a) + col * a

    n_big = fbm(P, 1.1, 4, seed)
    n_big2 = fbm(P, 0.6, 3, seed + 40)
    n_mid = fbm(P, 7.0, 4, seed + 80)
    n_fine = fbm(P, 45.0, 3, seed + 120)
    streak = fbm(P, 1.0, 4, seed + 160, stretch=(14, 14, 0.9))
    up = np.clip(N[:, 2], 0, 1)
    side = 1.0 - np.abs(N[:, 2])
    cav = np.clip(1.0 - ao, 0, 1)
    convex = edge * sstep(0.45, 0.85, ao)
    near = _blur(g["wide"], 1.2).reshape(-1) * sstep(0.4, 0.8, ao)  # the zone around a convex edge
    rain = sstep(0.46, 0.7, fbm(P, 1.0, 4, seed + 320, stretch=(19, 19, 0.7))) * side
    low = 1.0 - sstep(dust_from, dust_to, P[:, 2])

    col = base.copy()
    rough = np.full(len(P), 0.6, dtype=np.float32)
    metal = np.zeros(len(P), dtype=np.float32)
    height = np.zeros(len(P), dtype=np.float32)

    # ---- paint: faded, chipped to primer and bare steel on and near the edges, rust blooming out
    # of the chips and the corners, rust and rain streaks down the sides
    m = is_kind("paint")
    if m.any():
        fade = 0.84 + 0.28 * n_big
        c = base * fade[:, None]
        grey = c.mean(axis=1, keepdims=True)
        c = _lerp(c, grey * 1.05, (0.25 * n_big2)[:, None])  # sun-bleached patches
        field = convex * 1.25 + near * (0.35 + 1.1 * n_mid) + n_mid * 0.3 + n_fine * 0.22
        th = 1.12 - 0.62 * wear
        chip = sstep(th, th + 0.09, field)
        speck = sstep(0.78, 0.84, n_fine * 0.62 + n_mid * 0.48 + (n_big - 0.5) * 0.5) * sstep(0.25, 0.75, wear)
        chip = np.clip(chip + speck * 0.9, 0, 1)
        halo = sstep(th - 0.14, th + 0.02, field)
        c = _lerp(c, PRIMER * (0.7 + 0.5 * n_fine)[:, None], ((halo - chip).clip(0, 1) * 0.5)[:, None])
        c = _lerp(c, BARE * (0.7 + 0.6 * n_fine)[:, None], chip[:, None])
        rfield = cav * 1.0 + chip * 0.45 + near * 0.35 + n_big * 0.8 + n_mid * 0.25
        tr = 1.42 - 0.9 * rust
        rmask = sstep(tr, tr + 0.22, rfield)
        rcol = _lerp(RUST_A, RUST_B, n_fine[:, None]) * (0.65 + 0.6 * n_mid)[:, None]
        c = _lerp(c, rcol, (rmask * 0.93)[:, None])
        smask = sstep(0.5, 0.7, streak) * side * sstep(0.1, 0.6, rust) * (0.35 + 0.65 * sstep(0.35, 0.7, n_big + near * 0.4))
        c = _lerp(c, RUST_A * 0.9, (smask * 0.55)[:, None])
        col[m] = c[m]
        rough[m] = (_lerp(0.42 + 0.14 * n_mid, 0.5, chip) * (1 - rmask) + 0.92 * rmask)[m]
        metal[m] = (chip * (1 - rmask) * 0.85)[m]
        height[m] = (-chip * 0.6 + rmask * (n_fine - 0.3) * 0.9)[m]

    # ---- steel: dark plate, edges rubbed bright, scratches, rust in the corners
    m = is_kind("steel")
    if m.any():
        c = base * (0.8 + 0.4 * n_big)[:, None]
        scratch = sstep(0.62, 0.7, fbm(P, 3.0, 3, seed + 200, stretch=(30, 2, 2)) * 0.6 + n_fine * 0.4)
        rub = np.clip(convex * 1.5 * (0.5 + n_mid) + near * 0.5 * n_mid * wear + scratch * 0.35 * wear, 0, 1)
        c = _lerp(c, np.clip(base * 2.4 + 0.12, 0, 0.62), (rub * (0.35 + 0.65 * wear))[:, None])
        tr = 1.5 - 0.95 * rust
        rmask = sstep(tr, tr + 0.25, cav * 1.2 + n_big * 0.85 + n_mid * 0.3 + near * 0.2)
        rcol = _lerp(RUST_A, RUST_B, n_fine[:, None]) * (0.6 + 0.5 * n_mid)[:, None]
        c = _lerp(c, rcol, (rmask * 0.9)[:, None])
        smask = sstep(0.5, 0.72, streak) * side * sstep(0.1, 0.6, rust) * (0.3 + 0.7 * sstep(0.35, 0.7, n_big))
        c = _lerp(c, RUST_A * 0.9, (smask * 0.5)[:, None])
        col[m] = c[m]
        rough[m] = (_lerp(0.5 + 0.2 * n_mid - rub * 0.2, 0.92, rmask))[m]
        metal[m] = ((1 - rmask) * 0.85)[m]
        height[m] = (rmask * (n_fine - 0.3) * 0.9 - scratch * 0.15)[m]

    # ---- chrome / bright metal that has dulled
    m = is_kind("chrome")
    if m.any():
        c = base * (0.85 + 0.3 * n_mid)[:, None]
        rmask = sstep(0.6, 0.85, cav + n_big * 0.6 - (1.0 - rust) * 0.9)
        c = _lerp(c, RUST_A[None, :] * 1.2, (rmask * 0.8)[:, None])
        col[m] = c[m]
        rough[m] = (0.3 + 0.25 * n_mid + rmask * 0.4)[m]
        metal[m] = (1 - rmask)[m]

    # ---- glass painted onto a body (car windows): dark, a film of dust, wiped streaks
    m = is_kind("glassy")
    if m.any():
        c = base * (0.8 + 0.5 * n_big)[:, None]
        film = sstep(0.35, 0.8, n_big2 * 0.7 + cav * 0.9 + rain * 0.5) * (0.3 + 0.7 * dirt)
        c = _lerp(c, DUST * 0.55, (film * 0.5)[:, None])
        col[m] = c[m]
        rough[m] = (0.12 + film * 0.55)[m]
        metal[m] = 0.35
        height[m] = 0.0

    # ---- rubber: black, dusty and scuffed
    m = is_kind("rubber")
    if m.any():
        c = base * (0.8 + 0.5 * n_mid)[:, None]
        scuff = sstep(0.55, 0.8, n_fine * 0.5 + n_big * 0.6)
        c = _lerp(c, base * 2.2 + 0.015, (scuff * 0.5)[:, None])
        col[m] = c[m]
        rough[m] = 0.9
        height[m] = ((n_fine - 0.5) * 0.3)[m]

    # ---- plastic / composite: dull, scratched pale
    m = is_kind("plastic")
    if m.any():
        c = base * (0.88 + 0.24 * n_big)[:, None]
        scr = sstep(0.66, 0.74, convex * 1.2 + n_fine * 0.5 + n_mid * 0.3 - (1.0 - wear) * 0.6)
        c = _lerp(c, np.clip(base * 1.7 + 0.1, 0, 0.8), (scr * 0.7)[:, None])
        col[m] = c[m]
        rough[m] = (0.55 + 0.25 * n_mid)[m]
        height[m] = (-scr * 0.3)[m]

    # ---- concrete: stained, cracked, broken edges showing the aggregate
    m = is_kind("concrete")
    if m.any():
        c = base * (0.78 + 0.4 * n_big)[:, None]
        stain = sstep(0.5, 0.8, n_big2 * 0.8 + streak * 0.5 * side)
        c = c * (1.0 - 0.38 * stain)[:, None]
        agg = sstep(0.5, 0.75, convex * 1.6 + n_mid * 0.4 - (1.0 - wear) * 0.7)
        c = _lerp(c, np.clip(base * 1.35 + 0.05, 0, 0.8) * (0.7 + 0.6 * n_fine)[:, None], (agg * 0.8)[:, None])
        crack = 1.0 - sstep(0.0, 0.012 + 0.02 * wear, np.abs(fbm(P, 1.7, 3, seed + 240) - 0.5))
        crack *= sstep(0.35, 0.6, n_big2 + wear * 0.3)
        c = c * (1.0 - 0.7 * crack)[:, None]
        pit = sstep(0.72, 0.8, n_fine)
        c = c * (1.0 - 0.25 * pit)[:, None]
        col[m] = c[m]
        rough[m] = 0.92
        height[m] = (-crack * 1.0 - pit * 0.4 - agg * 0.4 + (n_mid - 0.5) * 0.25)[m]

    # ---- wood: grain along the longest axis is not known here, so grain runs with z-stretched noise
    m = is_kind("wood")
    if m.any():
        grain = fbm(P, 2.0, 4, seed + 280, stretch=(22, 22, 1.2))
        c = base * (0.7 + 0.6 * grain)[:, None]
        grey = c.mean(axis=1, keepdims=True)
        c = _lerp(c, grey * 1.1, (0.35 * wear * n_big)[:, None])
        col[m] = c[m]
        rough[m] = 0.88
        height[m] = ((grain - 0.5) * 0.7)[m]

    # ---- burnt metal (wrecks): soot black, ash-grey edges, fresh orange rust in patches
    m = is_kind("burnt")
    if m.any():
        c = np.broadcast_to(SOOT, col.shape) * (0.8 + 0.8 * n_mid)[:, None]
        ash = sstep(0.45, 0.8, convex * 1.2 + n_big * 0.7 + n_fine * 0.2 - 0.35)
        c = _lerp(c, np.array([0.3, 0.29, 0.28], dtype=np.float32) * (0.6 + 0.6 * n_fine)[:, None], (ash * 0.6)[:, None])
        rmask = sstep(0.5, 0.75, n_big2 * 0.9 + n_mid * 0.4 + cav * 0.3 - (1.0 - rust) * 0.7)
        c = _lerp(c, _lerp(RUST_A, RUST_B * 1.2, n_fine[:, None]), (rmask * 0.85)[:, None])
        keep = sstep(0.62, 0.8, n_big * 0.8 + n_mid * 0.3) * 0.5  # scraps of the old paint
        c = _lerp(c, base * 0.5, keep[:, None])
        col[m] = c[m]
        rough[m] = 0.95
        height[m] = (rmask * (n_fine - 0.3) + (n_mid - 0.5) * 0.4)[m]

    # ---- cloth / canvas
    m = is_kind("cloth")
    if m.any():
        weave = (np.sin(P[:, 0] * 260.0) * np.sin(P[:, 2] * 260.0 + P[:, 1] * 260.0)) * 0.5 + 0.5
        c = base * (0.75 + 0.3 * n_big + 0.12 * weave)[:, None]
        col[m] = c[m]
        rough[m] = 0.95
        height[m] = ((weave - 0.5) * 0.4)[m]

    # ---- everything: road dust low down and on what faces up, grime in the corners, scorch marks
    dustm = np.clip(low * 0.75 + up * 0.35 + cav * 0.6 + (n_big - 0.5) * 0.5, 0, 1) * dirt
    dustm = sstep(0.25, 0.9, dustm) * np.where(is_kind("glassy"), 0.35, 1.0)
    dcol = DUST * (0.75 + 0.5 * n_mid)[:, None]
    col = _lerp(col, dcol, (dustm * 0.7)[:, None])
    rough = _lerp(rough, 0.95, dustm * 0.8)
    metal = metal * (1.0 - dustm * 0.8)
    grime = sstep(0.15, 0.75, cav) * (0.35 + 0.4 * dirt)
    col = col * (1.0 - grime * 0.55)[:, None]
    col = col * (1.0 - rain * dirt * 0.32)[:, None]  # dirty rain runs down the sides
    if soot:
        for (c0, r0) in soot:
            d = np.linalg.norm(P - np.array(c0, dtype=np.float32), axis=1)
            sm = (1.0 - sstep(r0 * 0.25, r0, d)) * (0.6 + 0.6 * n_mid)
            sm = np.clip(sm, 0, 1)
            col = _lerp(col, SOOT[None, :] * (0.8 + n_fine[:, None]), (sm * 0.9)[:, None])
            rough = _lerp(rough, 0.95, sm)
            metal = metal * (1 - sm)
    col = col * _lerp(1.0, ao, ao_strength)[:, None]

    albedo = _to_srgb(col).reshape(H, W, 3)
    # fine surface detail folded into the baked normal (texture-space gradient of the height)
    hmap = _blur(np.clip(height.reshape(H, W) * 0.5 + 0.5, 0, 1), 0.7)
    gx = (np.roll(hmap, -1, axis=1) - np.roll(hmap, 1, axis=1)) * detail * 2.2
    gy = (np.roll(hmap, 1, axis=0) - np.roll(hmap, -1, axis=0)) * detail * 2.2
    tn = g["tnrm"] * 2.0 - 1.0
    tn[..., 0] -= gx
    tn[..., 1] -= gy
    tn /= np.maximum(np.linalg.norm(tn, axis=2, keepdims=True), 1e-5)
    tn[~g["cover"]] = (0, 0, 1)
    normal = tn * 0.5 + 0.5
    orm = np.stack([ao.reshape(H, W), rough.reshape(H, W), metal.reshape(H, W)], axis=2)
    return albedo, normal, orm


def save_maps(name, albedo, normal, orm, quality=90):
    os.makedirs(OUT, exist_ok=True)
    def u8(a):
        return (np.clip(a, 0, 1) * 255.0 + 0.5).astype(np.uint8)
    Image.fromarray(u8(albedo)).save(os.path.join(OUT, name + "_albedo.webp"), quality=quality, method=6)
    Image.fromarray(u8(normal)).save(os.path.join(OUT, name + "_normal.webp"), lossless=True, method=4)
    Image.fromarray(u8(orm)).save(os.path.join(OUT, name + "_orm.webp"), quality=quality, method=6)
    for suffix, normal_map in (("_albedo", 0), ("_normal", 1), ("_orm", 0)):
        _write_import(os.path.join(OUT, name + suffix + ".webp"), normal_map)


def _write_import(path, normal_map=0):
    """Godot import settings beside the texture: VRAM compressed with mipmaps (a few MB on the GPU
    instead of tens), unless one is already there (Godot adds its own ids to it)."""
    imp = path + ".import"
    if os.path.exists(imp):
        return
    rel = "res://" + os.path.relpath(path, ROOT).replace(os.sep, "/")
    with open(imp, "w") as f:
        f.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[deps]\n\nsource_file="%s"\n\n[params]\n\n' % rel)
        f.write("compress/mode=2\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/hdr_compression=1\n")
        f.write("compress/normal_map=%d\ncompress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\n" % normal_map)
        f.write('roughness/mode=0\nroughness/src_normal=""\nprocess/fix_alpha_border=true\nprocess/premult_alpha=false\n')
        f.write("process/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\nprocess/hdr_clamp_exposure=false\nprocess/size_limit=0\ndetect_3d/compress_to=0\n")


# ------------------------------------------------------------------ export

def _finish_materials(objs, atlas_name="atlas"):
    """After baking: every baked slot becomes the one 'atlas' material; glass and glow stay, and
    glow colours go to vertex colours."""
    atlas = bpy.data.materials.get(atlas_name) or bpy.data.materials.new(atlas_name)
    glowm = bpy.data.materials.get("glow_out") or bpy.data.materials.new("glow_out")
    glowm.name = "glow"
    for o in objs:
        me = o.data
        if not me.color_attributes:
            me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        ca = me.color_attributes[0]
        cols = np.ones((len(me.loops), 4), dtype=np.float32)
        slots = list(me.materials)
        for p in me.polygons:
            m = slots[p.material_index] if slots else None
            if m is not None and m.get("tm_special") == "glow":
                c = m["tm_color"]
                for li in p.loop_indices:
                    cols[li] = (c[0], c[1], c[2], 1.0)
        ca.data.foreach_set("color", cols.reshape(-1))
        new_slots = []
        remap = []
        for m in slots:
            if _is_baked(m):
                t = atlas
            elif m is not None and m.get("tm_special") == "glow":
                t = glowm
            else:
                t = m
            if t not in new_slots:
                new_slots.append(t)
            remap.append(new_slots.index(t))
        idxs = [remap[p.material_index] for p in me.polygons]
        me.materials.clear()
        for t in new_slots:
            me.materials.append(t)
        for p, i in zip(me.polygons, idxs):
            p.material_index = i
        me.update()


def export_glb(name, objs, atlas_name="atlas", markers=()):
    """Write assets/models/<name>.glb with these objects (their names become node names)."""
    os.makedirs(OUT, exist_ok=True)
    _finish_materials(objs, atlas_name)
    _activate(objs[0], list(objs) + list(markers))
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
        export_materials="EXPORT", export_normals=True, export_texcoords=True, export_tangents=False,
        export_yup=True, export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_animations=False, export_cameras=False, export_lights=False,
        export_extras=True)
    return path


# ------------------------------------------------------------------ preview render

def preview(path, objs=None, size=(960, 540), eye=(4.5, -6.0, 3.2), look=(0, 0, 0.8), fov=38.0, samples=24, sun=(55, 0, 35), ground=True, tex=None):
    """A quick Cycles render to check a model. tex = (albedo, normal, orm) arrays to show the baked
    result on the 'atlas' material."""
    scene = bpy.context.scene
    made = []
    cam_d = bpy.data.cameras.new("pv_cam")
    cam_d.lens_unit = "FOV"
    cam_d.angle = math.radians(fov)
    cam = bpy.data.objects.new("pv_cam", cam_d)
    _link(cam)
    made.append(cam)
    cam.location = eye
    d = Vector(look) - Vector(eye)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    sd = bpy.data.lights.new("pv_sun", "SUN")
    sd.energy = 3.2
    sd.angle = math.radians(4)
    so = bpy.data.objects.new("pv_sun", sd)
    so.rotation_euler = Euler([math.radians(a) for a in sun], "XYZ")
    _link(so)
    made.append(so)
    world = bpy.data.worlds.new("pv_world")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.42, 0.44, 0.5, 1.0)
    bg.inputs[1].default_value = 0.9
    scene.world = world
    if ground:
        gm = bpy.data.materials.new("pv_ground")
        gm.use_nodes = True
        gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.16, 0.15, 0.14, 1)
        gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
        bm = bmesh.new()
        bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=40.0)
        gr = _new_obj("pv_ground", bm, gm)
        made.append(gr)
    imgs = []
    if tex is not None:
        at = bpy.data.materials.get("atlas")
        if at is not None:
            at.use_nodes = True
            nt = at.node_tree
            nt.nodes.clear()
            out = nt.nodes.new("ShaderNodeOutputMaterial")
            bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
            nt.links.new(bs.outputs[0], out.inputs[0])
            def img_node(arr, data):
                h, w = arr.shape[:2]
                im = bpy.data.images.new("pv_tex", w, h, alpha=False, float_buffer=False, is_data=data)
                rgba = np.ones((h, w, 4), dtype=np.float32)
                rgba[..., :3] = arr[::-1]
                if not data:
                    im.colorspace_settings.name = "sRGB"
                im.pixels.foreach_set(rgba.reshape(-1))
                im.update()
                im.pack()
                imgs.append(im)
                n = nt.nodes.new("ShaderNodeTexImage")
                n.image = im
                return n
            a = img_node(tex[0], False)
            nt.links.new(a.outputs[0], bs.inputs["Base Color"])
            nm = img_node(tex[1], True)
            nmap = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(nm.outputs[0], nmap.inputs["Color"])
            nt.links.new(nmap.outputs[0], bs.inputs["Normal"])
            o = img_node(tex[2], True)
            sep = nt.nodes.new("ShaderNodeSeparateColor")
            nt.links.new(o.outputs[0], sep.inputs[0])
            nt.links.new(sep.outputs[1], bs.inputs["Roughness"])
            nt.links.new(sep.outputs[2], bs.inputs["Metallic"])
    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.filepath = path
    scene.view_settings.view_transform = "Standard"
    try:
        bpy.ops.render.render(write_still=True)
    except RuntimeError as e:
        scene.cycles.use_denoising = False
        bpy.ops.render.render(write_still=True)
    scene.cycles.use_denoising = False
    for o in made:
        bpy.data.objects.remove(o)
    return path

"""Paris backdrop: the city beyond the edge walls as one equirectangular panorama, shown as the sky (costs no frames).
    /tmp/bpy3.13/bin/python tools/blender/build_paris_backdrop.py [width] [samples]   (8192 32 = the game's; 2048 8 = a test)
Writes assets/backdrops/paris_city.jpg (u = 0 looks north, growing east, as Godot reads it); a width under 8192 writes
assets/backdrops/_paris_test.jpg instead.

Round 32 (owner: "the BG still looks empty ... thousands of houses along the horizon; far houses are dots anyway, so
make it good for the far observer"). What the eye gets from far away decides the detail of every ring:
  - Paris lies in a basin. Here the basin is steeper than the real one, so the city climbs away from the map in rows of
    roofs that stand one above the other up to the skyline (on flat ground everything past a kilometre collapses onto
    the horizon line, which the stage's own edge buildings hide).
  - 300 m - 1.8 km: Haussmann blocks: cream stone walls with rows of windows (a pattern in metre UVs: at 400 m a window
    is 3-4 pixels), zinc mansards with dormers, chimney stacks. 1.8 - 4 km: the suburbs: small houses with red tile
    roofs, apartment slabs and towers on the hills (they make the skyline). Past 4 km: boxes only, then the ground's
    own mottled "carpet" of roofs: at that distance a house is a dot of colour.
  - Haze by distance (aerial perspective): each farther row is lighter and greyer, so the layers read as depth.
  - Overcast day (the owner's light, round 32): soft sky light, a weak sun in the south-west, no hard shadows.
  - Landmarks outside the map: La Defense and the Grande Arche (WNW), Tour Montparnasse (S), the Pantheon dome, church
    spires, factory chimneys and gasometers north, a TV mast on the eastern hills; war smoke columns over the city.
Only the band the stage can show (-15 to +40 degrees) is rendered at full size; the sky above and the ground below are
a small render scaled up. Blender space: +Y north, +X east, +Z up (Godot z = -Blender y)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
import bpy
import numpy as np
from mathutils import Euler
from PIL import Image

W = int(sys.argv[1]) if len(sys.argv) > 1 else 8192
SAMPLES = int(sys.argv[2]) if len(sys.argv) > 2 else 32
FINAL = W >= 8192
scene = T.reset()
rng = np.random.default_rng(32)
CAM_Z = 10.0
HX, HZ = 275.0 + 45.0, 225.0 + 45.0   # the map, its edge walls and the ring of block shells round it (ParisArena._outer_ring)
SKY_TOP = (0.50, 0.53, 0.58)      # overcast: bright grey-blue overhead...
SKY_LOW = (0.60, 0.61, 0.63)      # ...a paler grey at the horizon
HAZE = (0.58, 0.59, 0.61)         # what far things fade into
REACH = 4200.0                    # haze distance: 1 - exp(-d / REACH) of a thing is haze


# ---------------------------------------------------------------- the land: a basin round the map
def river_y(x):
    """The Seine's line in Blender y (Godot's river_z, negated), carried on past the map, winding a little."""
    return -(62.0 + 40.0 * math.sin(x / 1400.0) * min(1.0, abs(x) / 900.0))


HILLS = [  # (azimuth deg from north, distance m, height m, width deg): the rim's high points
    (20, 2600, 170, 30), (65, 2900, 230, 35), (110, 3400, 120, 40), (165, 2700, 140, 30), (215, 3100, 260, 35),
    (260, 3600, 210, 30), (300, 4200, 180, 40), (340, 3000, 150, 30)]


def height(x, y):
    """Ground height: flat round the map and along the river, rising to the rim with its hills."""
    d = math.hypot(x, y)
    az = math.degrees(math.atan2(x, y)) % 360.0
    rim = 200.0
    for (ha, hd, hh, hw) in HILLS:
        da = (az - ha + 180.0) % 360.0 - 180.0
        rim += hh * math.exp(-(da / hw) ** 2) * math.exp(-((d - hd) / 1600.0) ** 2) * 1.6
    t = max(0.0, (d - 450.0) / 3000.0)
    h = rim * min(t, 1.5) ** 1.15
    if abs(x) > HX:  # the river valley stays low
        k = min(1.0, max(0.0, (abs(y - river_y(x)) - 60.0) / 1400.0))
        h *= k * k * (3.0 - 2.0 * k)
    return h


def build_terrain():
    """Polar grid from the map out to 14 km (dense near, coarse far)."""
    rings = np.concatenate([np.linspace(0, 3000, 90), np.geomspace(3050, 14000, 40)])
    segs = 360
    verts, faces = [], []
    for r in rings:
        for k in range(segs):
            a = 2 * math.pi * k / segs
            x, y = math.sin(a) * r, math.cos(a) * r
            verts.append((x, y, height(x, y)))
    for i in range(len(rings) - 1):
        for k in range(segs):
            a, b = i * segs + k, i * segs + (k + 1) % segs
            faces.append((a, b, b + segs, a + segs))
    me = bpy.data.meshes.new("ground")
    me.from_pydata(verts, [], faces)
    me.materials.append(mat_ground)
    T.link(bpy.data.objects.new("ground", me))


# ---------------------------------------------------------------- materials (all fade into the haze)
def hazed(name, build):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    mix = nt.nodes.new("ShaderNodeMixShader")
    cam = nt.nodes.new("ShaderNodeCameraData")
    k = nt.nodes.new("ShaderNodeMath")
    k.operation = "MULTIPLY"
    k.inputs[1].default_value = -1.0 / REACH
    nt.links.new(cam.outputs["View Distance"], k.inputs[0])
    e = nt.nodes.new("ShaderNodeMath")
    e.operation = "EXPONENT"
    nt.links.new(k.outputs[0], e.inputs[0])
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(e.outputs[0], inv.inputs[1])
    hz = nt.nodes.new("ShaderNodeEmission")
    hz.inputs[0].default_value = (*HAZE, 1.0)
    nt.links.new(inv.outputs[0], mix.inputs[0])
    nt.links.new(build(nt), mix.inputs[1])
    nt.links.new(hz.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    return m


def node(nt, kind, **inputs):
    n = nt.nodes.new(kind)
    for k, v in inputs.items():
        if k == "op":
            n.operation = v
        elif k == "dt":
            n.data_type = v
        else:
            n.inputs[k].default_value = v
    return n


def math_op(nt, op, a, b=None, c=None):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    for i, v in enumerate((a, b, c)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = v
        else:
            nt.links.new(v, n.inputs[i])
    return n.outputs[0]


def band(nt, value, period, lo, hi, offset=0.0):
    """1 where fract((value + offset) / period) is inside [lo, hi]."""
    f = math_op(nt, "FRACT", math_op(nt, "DIVIDE", math_op(nt, "ADD", value, offset), period))
    return math_op(nt, "MULTIPLY", math_op(nt, "GREATER_THAN", f, lo), math_op(nt, "LESS_THAN", f, hi))


def tinted(nt, base_out):
    """base colour x the per-building tint (colour attribute "tint")."""
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = "tint"
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    nt.links.new(base_out, mul.inputs[6])
    nt.links.new(at.outputs["Color"], mul.inputs[7])
    return mul.outputs[2]


def facade(nt):
    """Walls: UV = metres (u along the wall, v up). Windows in bays of 3 m and floors of 3.1 m, a dark shop band at
    the street, balcony lines on the 2nd and the top floor, a lighter cornice under the roof."""
    b = node(nt, "ShaderNodeBsdfPrincipled", Roughness=0.85)
    uv = nt.nodes.new("ShaderNodeUVMap")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(uv.outputs[0], sep.inputs[0])
    u, v = sep.outputs[0], sep.outputs[1]
    upper = math_op(nt, "GREATER_THAN", v, 4.4)
    win = math_op(nt, "MULTIPLY", math_op(nt, "MULTIPLY", band(nt, u, 3.0, 0.3, 0.7), band(nt, v, 3.1, 0.2, 0.78, -1.3)), upper)
    shop = math_op(nt, "MULTIPLY", math_op(nt, "LESS_THAN", v, 3.6), math_op(nt, "MULTIPLY", math_op(nt, "GREATER_THAN", v, 0.4), band(nt, u, 6.0, 0.06, 0.94)))
    rail = math_op(nt, "MULTIPLY", band(nt, v, 3.1, 0.05, 0.13, -1.3), math_op(nt, "GREATER_THAN", v, 7.0))
    dark = math_op(nt, "MAXIMUM", math_op(nt, "MAXIMUM", win, shop), math_op(nt, "MULTIPLY", rail, 0.6))
    stone = nt.nodes.new("ShaderNodeRGB")
    stone.outputs[0].default_value = (1, 1, 1, 1)
    col = tinted(nt, stone.outputs[0])
    glass = nt.nodes.new("ShaderNodeRGB")
    glass.outputs[0].default_value = (*T.lin("2A2E33"), 1)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    nt.links.new(dark, mix.inputs[0])
    nt.links.new(col, mix.inputs[6])
    nt.links.new(glass.outputs[0], mix.inputs[7])
    nt.links.new(mix.outputs[2], b.inputs["Base Color"])
    return b.outputs[0]


def roof(nt):
    """Roofs: the tint is the roof's colour (zinc grey-blue, slate, red tile); dormer windows in bays of 3 m on
    the slopes (v = metres up the slope)."""
    b = node(nt, "ShaderNodeBsdfPrincipled", Roughness=0.55)
    uv = nt.nodes.new("ShaderNodeUVMap")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(uv.outputs[0], sep.inputs[0])
    dormer = math_op(nt, "MULTIPLY", band(nt, sep.outputs[0], 3.0, 0.36, 0.64), band(nt, sep.outputs[1], 100.0, 0.009, 0.022))
    white = nt.nodes.new("ShaderNodeRGB")
    white.outputs[0].default_value = (1, 1, 1, 1)
    col = tinted(nt, white.outputs[0])
    dark = nt.nodes.new("ShaderNodeRGB")
    dark.outputs[0].default_value = (*T.lin("33373C"), 1)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    nt.links.new(dormer, mix.inputs[0])
    nt.links.new(col, mix.inputs[6])
    nt.links.new(dark.outputs[0], mix.inputs[7])
    nt.links.new(mix.outputs[2], b.inputs["Base Color"])
    return b.outputs[0]


def plain(color, rough=0.8, metal=0.0):
    def build(nt):
        return node(nt, "ShaderNodeBsdfPrincipled", **{"Base Color": (*color, 1.0), "Roughness": rough, "Metallic": metal}).outputs[0]
    return build


def ground_carpet(nt):
    """From far away a city is a carpet of roof colours: zinc, slate, red tile, stone and trees, in patches the
    size of houses and of quarters, with the darker streets between."""
    b = node(nt, "ShaderNodeBsdfPrincipled", Roughness=0.9)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    vor = node(nt, "ShaderNodeTexVoronoi", Scale=0.06)
    nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
    big = node(nt, "ShaderNodeTexNoise", Scale=0.0012, Detail=3.0)
    nt.links.new(tc.outputs["Object"], big.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    stops = [(0.0, "6E7680"), (0.25, "8A8478"), (0.45, "9A5A45"), (0.62, "7F8790"), (0.8, "4F5E3C"), (1.0, "A39C8E")]
    cr.elements[0].position, cr.elements[0].color = stops[0][0], (*T.lin(stops[0][1]), 1)
    cr.elements[1].position, cr.elements[1].color = stops[-1][0], (*T.lin(stops[-1][1]), 1)
    for p, c in stops[1:-1]:
        el = cr.elements.new(p)
        el.color = (*T.lin(c), 1)
    # house-sized cells pick a colour; the quarter-sized noise shifts the mix (green parks, red-roof suburbs)
    cell = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(vor.outputs["Color"], cell.inputs[0])
    v = math_op(nt, "ADD", math_op(nt, "MULTIPLY", cell.outputs[0], 0.6), math_op(nt, "MULTIPLY", big.outputs[0], 0.5))
    nt.links.new(v, ramp.inputs[0])
    street = math_op(nt, "LESS_THAN", vor.outputs["Distance"], 0.12)
    dark = node(nt, "ShaderNodeMix", dt="RGBA")
    nt.links.new(street, dark.inputs[0])
    nt.links.new(ramp.outputs[0], dark.inputs[6])
    dark.inputs[7].default_value = (*T.lin("3A3B3D"), 1)
    cam = nt.nodes.new("ShaderNodeCameraData")
    far = math_op(nt, "MINIMUM", math_op(nt, "MAXIMUM", math_op(nt, "DIVIDE", math_op(nt, "SUBTRACT", cam.outputs["View Distance"], 1600.0), 1200.0), 0.0), 1.0)
    near = node(nt, "ShaderNodeMix", dt="RGBA")
    nt.links.new(far, near.inputs[0])
    near.inputs[6].default_value = (*T.lin("57595B"), 1)
    nt.links.new(dark.outputs[2], near.inputs[7])
    nt.links.new(near.outputs[2], b.inputs["Base Color"])
    return b.outputs[0]


mat_wall = hazed("wall", facade)
mat_roof = hazed("roof", roof)
mat_brick = hazed("brick", plain(T.lin("8C5A44")))
mat_ground = hazed("ground", ground_carpet)
mat_glass = hazed("glass", plain(T.lin("5D6D7A"), 0.15, 0.6))
mat_stone = hazed("stone", plain(T.lin("CBC3B2"), 0.8))
mat_lead = hazed("lead", plain(T.lin("5A6068"), 0.4, 0.5))
mat_tree = hazed("tree", plain(T.lin("3F4D2C"), 0.95))
mat_water = hazed("water", plain(T.lin("4F5D62"), 0.08))
mat_dark = hazed("dark", plain(T.lin("2E3133"), 0.6))
mat_red = hazed("redwhite", plain(T.lin("A33A2C"), 0.6))
MATS = [mat_wall, mat_roof, mat_brick, mat_glass, mat_stone, mat_lead, mat_tree, mat_dark, mat_red]
WALL, ROOF, BRICK, GLASS, STONE, LEAD, TREE, DARK, RED = range(9)


# ---------------------------------------------------------------- one big mesh, built from lists (fast enough)
class Geo:
    def __init__(self):
        self.v, self.f, self.uv, self.col, self.mat = [], [], [], [], []

    def face(self, pts, mat, uvs=None, col=(1, 1, 1)):
        base = len(self.v)
        self.v.extend(pts)
        self.f.append(tuple(range(base, base + len(pts))))
        self.uv.extend(uvs if uvs else [(0.0, 0.0)] * len(pts))
        self.col.extend([(*col, 1.0)] * len(pts))
        self.mat.append(mat)

    def commit(self, name):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.v, [], self.f)
        for m in MATS:
            me.materials.append(m)
        me.polygons.foreach_set("material_index", np.array(self.mat, dtype=np.int32))
        uv = me.uv_layers.new(name="UVMap")
        uv.data.foreach_set("uv", np.array(self.uv, dtype=np.float32).ravel())
        ca = me.color_attributes.new("tint", "FLOAT_COLOR", "CORNER")
        ca.data.foreach_set("color", np.array(self.col, dtype=np.float32).ravel())
        me.update()
        T.link(bpy.data.objects.new(name, me))
        print(name, len(self.f), "faces")


geo = Geo()


def rot(cx, cy, yaw, lx, ly):
    c, s = math.cos(yaw), math.sin(yaw)
    return (cx + lx * c - ly * s, cy + lx * s + ly * c)


def walls(g, cx, cy, z0, w, d, h, yaw, tint):
    """Four walls of a box (no floor), UVs in metres."""
    corners = [rot(cx, cy, yaw, sx * w / 2, sy * d / 2) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    lens = [w, d, w, d]
    off = rng.uniform(0, 3)
    for i in range(4):
        a, b = corners[i], corners[(i + 1) % 4]
        L = lens[i]
        g.face([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z0 + h), (a[0], a[1], z0 + h)], WALL,
               [(off, 0), (off + L, 0), (off + L, h), (off, h)], tint)
    return corners


def mansard(g, cx, cy, z, w, d, h, yaw, inset, tint):
    lo = [rot(cx, cy, yaw, sx * w / 2, sy * d / 2) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    hi = [rot(cx, cy, yaw, sx * (w / 2 - inset), sy * (d / 2 - inset)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    lens = [w, d, w, d]
    slope = math.hypot(inset, h)
    for i in range(4):
        j = (i + 1) % 4
        L = lens[i]
        g.face([(lo[i][0], lo[i][1], z), (lo[j][0], lo[j][1], z), (hi[j][0], hi[j][1], z + h), (hi[i][0], hi[i][1], z + h)], ROOF,
               [(0, 0), (L, 0), (L - inset, slope), (inset, slope)], tint)
    g.face([(p[0], p[1], z + h) for p in hi], ROOF, None, tint)


def gable(g, cx, cy, z, w, d, h, yaw, tint):
    """A pitched roof, ridge along the long side (hipped: four slopes)."""
    if w < d:
        w, d, yaw = d, w, yaw + math.pi / 2
    r = min(d / 2, w / 2) * 0.9
    lo = [rot(cx, cy, yaw, sx * w / 2, sy * d / 2) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    ra = rot(cx, cy, yaw, -(w / 2 - r), 0)
    rb = rot(cx, cy, yaw, (w / 2 - r), 0)
    A, B = (ra[0], ra[1], z + h), (rb[0], rb[1], z + h)
    P = [(p[0], p[1], z) for p in lo]
    g.face([P[0], P[1], B, A], ROOF, None, tint)
    g.face([P[2], P[3], A, B], ROOF, None, tint)
    g.face([P[1], P[2], B], ROOF, None, tint)
    g.face([P[3], P[0], A], ROOF, None, tint)


def box(g, cx, cy, z0, w, d, h, yaw, mat, tint=(1, 1, 1), top=True):
    corners = [rot(cx, cy, yaw, sx * w / 2, sy * d / 2) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    for i in range(4):
        a, b = corners[i], corners[(i + 1) % 4]
        g.face([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z0 + h), (a[0], a[1], z0 + h)], mat, None, tint)
    if top:
        g.face([(p[0], p[1], z0 + h) for p in corners], mat, None, tint)


def cylinder(g, cx, cy, z0, r, h, mat, n=12, r2=None, tint=(1, 1, 1)):
    r2 = r if r2 is None else r2
    for k in range(n):
        a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        g.face([(cx + math.cos(a0) * r, cy + math.sin(a0) * r, z0), (cx + math.cos(a1) * r, cy + math.sin(a1) * r, z0),
                (cx + math.cos(a1) * r2, cy + math.sin(a1) * r2, z0 + h), (cx + math.cos(a0) * r2, cy + math.sin(a0) * r2, z0 + h)], mat, None, tint)
    if r2 > 0.01:
        g.face([(cx + math.cos(2 * math.pi * k / n) * r2, cy + math.sin(2 * math.pi * k / n) * r2, z0 + h) for k in range(n)], mat, None, tint)


def dome(g, cx, cy, z0, r, mat, rings=6, n=16, tint=(1, 1, 1)):
    for i in range(rings):
        t0, t1 = i / rings * math.pi / 2, (i + 1) / rings * math.pi / 2
        r0, r1 = math.cos(t0) * r, math.cos(t1) * r
        z_0, z_1 = z0 + math.sin(t0) * r * 1.15, z0 + math.sin(t1) * r * 1.15
        for k in range(n):
            a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
            pts = [(cx + math.cos(a0) * r0, cy + math.sin(a0) * r0, z_0), (cx + math.cos(a1) * r0, cy + math.sin(a1) * r0, z_0),
                   (cx + math.cos(a1) * r1, cy + math.sin(a1) * r1, z_1), (cx + math.cos(a0) * r1, cy + math.sin(a0) * r1, z_1)]
            if r1 < 0.01:
                pts = pts[:3]
            g.face(pts, mat, None, tint)


STONES = [T.lin(c) for c in ("D6CBB4", "CFC4AE", "C9C0AF", "DDD3BF", "BFB6A4", "D2C2A2", "B9AE9A")]
ZINC = [T.lin(c) for c in ("6E7882", "66707A", "7A838C", "5E676F", "737C84")]
TILE = [T.lin(c) for c in ("9C5440", "A8624A", "8E4A38", "B06E52", "7F4A3C")]
SUBURB_WALL = [T.lin(c) for c in ("B8AE9C", "A89A86", "C2B8A6", "988C7A", "B09A7C", "8E8A82", "7C746A")]


def free(x, y):
    """Outside the stage and its ring, off the Seine and the avenues that cross the basin."""
    if abs(x) < HX and abs(y) < HZ:
        return False
    if abs(x) > HX - 60 and abs(y - river_y(x)) < 70.0:
        return False
    az = math.degrees(math.atan2(x, y)) % 360.0
    for a in (12, 47, 98, 143, 196, 238, 283, 327):  # long boulevards radiating out: gaps between the blocks
        if abs((az - a + 180) % 360 - 180) * math.pi / 180 * math.hypot(x, y) < 9.0:
            return False
    return True


def park(x, y):
    """Parks and woods (Bois de Boulogne to the west-south-west, Vincennes to the east-south-east, small squares)."""
    for (pa, pd, pr) in ((250, 2600, 900), (115, 3300, 1000), (40, 1900, 260), (180, 1500, 220), (330, 1300, 200)):
        px, py = math.sin(math.radians(pa)) * pd, math.cos(math.radians(pa)) * pd
        if math.hypot(x - px, y - py) < pr:
            return True
    return False


def city():
    """Haussmann blocks near, then the suburbs, then boxes. One jittered grid per ring, the step growing with distance."""
    n = [0, 0, 0, 0]
    # Haussmann Paris: 300 m - 1.8 km
    step = 58.0
    for gx in np.arange(-1800, 1800, step):
        for gy in np.arange(-1800, 1800, step):
            x, y = gx + rng.uniform(-5, 5), gy + rng.uniform(-5, 5)
            d = math.hypot(x, y)
            if d > 1800 or not free(x, y):
                continue
            if park(x, y):
                trees(x, y, 46)
                continue
            z = height(x, y)
            yaw = math.radians(rng.uniform(-8, 8)) + (math.pi / 4 if rng.random() < 0.15 else 0.0)
            w, dd = rng.uniform(40, 52), rng.uniform(38, 50)
            h = 3.1 * rng.integers(5, 8) + 1.4
            tint = STONES[rng.integers(len(STONES))]
            if rng.random() < 0.06:
                tint = tuple(c * 0.45 for c in tint)  # burnt out
            walls(geo, x, y, z - 2.0, w, dd, h + 2.0, yaw, tint)
            mh = rng.uniform(2.6, 4.2)
            mansard(geo, x, y, z + h, w, dd, mh, yaw, 2.4, ZINC[rng.integers(len(ZINC))])
            for k in range(rng.integers(3, 8)):  # chimney stacks along the roof
                lx, ly = rng.uniform(-w / 2 + 3, w / 2 - 3), (dd / 2 - 3.0) * (1 if rng.random() < 0.5 else -1)
                cx, cy = rot(x, y, yaw, lx, ly)
                box(geo, cx, cy, z + h, 2.2, 0.8, mh + 1.6, yaw, BRICK)
            n[0] += 1
    # the suburbs: 1.8 - 4 km (houses, slabs, towers), on the slopes
    step = 26.0
    for gx in np.arange(-4000, 4000, step):
        for gy in np.arange(-4000, 4000, step):
            x, y = gx + rng.uniform(-7, 7), gy + rng.uniform(-7, 7)
            d = math.hypot(x, y)
            if d < 1800 or d > 4000 or not free(x, y):
                continue
            if park(x, y):
                if rng.random() < 0.35:
                    trees(x, y, 20)
                continue
            z = height(x, y)
            yaw = math.radians(rng.uniform(-30, 30))
            r = rng.random()
            if r < 0.035 and d < 3700:  # a tower block: the skyline
                w, dd, h = rng.uniform(18, 26), rng.uniform(14, 20), 2.9 * rng.integers(12, 22)
                walls(geo, x, y, z - 2, w, dd, h + 2, yaw, SUBURB_WALL[rng.integers(len(SUBURB_WALL))])
                box(geo, x, y, z + h, w, dd, 1.2, yaw, DARK)
                n[2] += 1
            elif r < 0.12:  # an apartment slab
                w, dd, h = rng.uniform(40, 70), rng.uniform(11, 14), 2.9 * rng.integers(4, 10)
                walls(geo, x, y, z - 2, w, dd, h + 2, yaw, SUBURB_WALL[rng.integers(len(SUBURB_WALL))])
                box(geo, x, y, z + h, w, dd, 0.8, yaw, DARK)
                n[2] += 1
            elif r < 0.75:  # a house or a small block with a red tile roof
                w, dd, h = rng.uniform(9, 16), rng.uniform(8, 12), 3.0 * rng.integers(2, 5)
                walls(geo, x, y, z - 2, w, dd, h + 2, yaw, SUBURB_WALL[rng.integers(len(SUBURB_WALL))])
                gable(geo, x, y, z + h, w, dd, rng.uniform(2.5, 4.0), yaw, TILE[rng.integers(len(TILE))] if rng.random() < 0.75 else ZINC[rng.integers(len(ZINC))])
                n[1] += 1
            elif r < 0.85:
                trees(x, y, 12)
    # past 4 km: boxes with roof-coloured tops (a few pixels each), towers here and there
    step = 60.0
    for gx in np.arange(-7000, 7000, step):
        for gy in np.arange(-7000, 7000, step):
            x, y = gx + rng.uniform(-20, 20), gy + rng.uniform(-20, 20)
            d = math.hypot(x, y)
            if d < 4000 or d > 7000 or not free(x, y) or park(x, y) or rng.random() < 0.25:
                continue
            z = height(x, y)
            tall = rng.random() < 0.04
            w, dd, h = (rng.uniform(20, 30), rng.uniform(16, 22), rng.uniform(35, 70)) if tall else (rng.uniform(25, 50), rng.uniform(20, 40), rng.uniform(8, 18))
            box(geo, x, y, z - 2, w, dd, h + 2, math.radians(rng.uniform(0, 90)), WALL if tall else ROOF,
                SUBURB_WALL[rng.integers(len(SUBURB_WALL))] if tall else (TILE + ZINC)[rng.integers(10)])
            n[3] += 1
    print("blocks", n[0], "houses", n[1], "towers/slabs", n[2], "far boxes", n[3])


def trees(x, y, spread):
    for k in range(int(spread / 6) + 1):
        tx, ty = x + rng.uniform(-spread / 2, spread / 2), y + rng.uniform(-spread / 2, spread / 2)
        z = height(tx, ty)
        r = rng.uniform(3.5, 6.0)
        cylinder(geo, tx, ty, z + r * 0.9, r, r * 1.5, TREE, n=6, r2=r * 0.35, tint=(1, 1, 1))


def landmarks():
    # La Defense on the west-north-west rim: glass towers and the Grande Arche
    DA = math.radians(292.0)
    for k in range(22):
        dist = rng.uniform(3300, 4200)
        a = DA + math.radians(rng.uniform(-5, 5))
        x, y = math.sin(a) * dist, math.cos(a) * dist
        z = height(x, y)
        w, dd, h = rng.uniform(28, 55), rng.uniform(26, 45), rng.uniform(80, 230)
        box(geo, x, y, z - 2, w, dd, h + 2, math.radians(rng.uniform(0, 90)), GLASS)
    ax, ay = math.sin(DA) * 3150, math.cos(DA) * 3150
    az = height(ax, ay)
    S = 108.0
    for (lx, lz, sx, sz) in ((0, S - 6, S, 12), (0, 6, S, 12), (-S / 2 + 6, S / 2, 12, S), (S / 2 - 6, S / 2, 12, S)):
        cx, cy = rot(ax, ay, -DA, lx, 0)
        box(geo, cx, cy, az + lz - sz / 2, sx, 20, sz, -DA, STONE)
    # Tour Montparnasse to the south
    ma = math.radians(192.0)
    mx, my = math.sin(ma) * 1700, math.cos(ma) * 1700
    box(geo, mx, my, height(mx, my) - 2, 52, 34, 212, math.radians(25), DARK)
    # the Pantheon to the south-east: drum, colonnade, dome, lantern
    pa = math.radians(150.0)
    px, py = math.sin(pa) * 1300, math.cos(pa) * 1300
    pz = height(px, py) + 30
    box(geo, px, py, pz - 32, 84, 110, 32, math.radians(10), STONE)
    cylinder(geo, px, py, pz, 19, 22, STONE, n=24)
    dome(geo, px, py, pz + 22, 19, LEAD, n=24)
    cylinder(geo, px, py, pz + 43, 4, 9, STONE, n=12, r2=1.0)
    # Val-de-Grace dome, Saint-Sulpice's two towers, the Tour Saint-Jacques, Gare de Lyon's clock tower
    for (aa, dist, kind) in ((170, 1550, "dome"), (205, 1000, "twin"), (95, 900, "tower"), (118, 1500, "clock"), (35, 1350, "spire"),
                             (75, 1700, "spire"), (240, 1450, "spire"), (320, 1600, "spire"), (140, 2300, "spire")):
        a = math.radians(aa)
        x, y = math.sin(a) * dist, math.cos(a) * dist
        z = height(x, y)
        if kind == "dome":
            box(geo, x, y, z, 40, 40, 28, a, STONE)
            cylinder(geo, x, y, z + 28, 12, 10, STONE, n=20)
            dome(geo, x, y, z + 38, 12, LEAD, n=20)
        elif kind == "twin":
            box(geo, x, y, z, 50, 30, 30, a, STONE)
            for s in (-1, 1):
                tx, ty = rot(x, y, a, s * 20, 0)
                box(geo, tx, ty, z + 30, 12, 12, 40, a, STONE)
        elif kind == "tower":
            box(geo, x, y, z, 10, 10, 54, a, STONE)
            box(geo, x, y, z + 54, 12, 12, 4, a, STONE)
        elif kind == "clock":
            box(geo, x, y, z, 12, 12, 64, a, STONE)
            cylinder(geo, x, y, z + 64, 7, 10, LEAD, n=8, r2=0.5)
        else:  # a church: nave, tower and spire
            box(geo, x, y, z, 18, 50, 22, a, STONE)
            tx, ty = rot(x, y, a, 0, -26)
            box(geo, tx, ty, z, 11, 11, 38, a, STONE)
            cylinder(geo, tx, ty, z + 38, 5.5, 28, LEAD, n=8, r2=0.2)
    # the industrial north: chimneys and gasometers; a TV mast on the eastern hills
    for k in range(9):
        a = math.radians(rng.uniform(345, 385))
        dist = rng.uniform(2600, 4800)
        x, y = math.sin(a) * dist, math.cos(a) * dist
        z = height(x, y)
        if k % 3 == 0:
            cylinder(geo, x, y, z, 26, 40, DARK, n=18)
        else:
            cylinder(geo, x, y, z, 3.5, rng.uniform(60, 95), BRICK, n=10, r2=2.2)
    ta = math.radians(70.0)
    tx, ty = math.sin(ta) * 3000, math.cos(ta) * 3000
    tz = height(tx, ty)
    for k in range(8):
        cylinder(geo, tx, ty, tz + k * 22, 3.0 - k * 0.25, 22, RED if k % 2 else STONE, n=8, r2=2.75 - k * 0.25)
    # the Seine on past the map, with its quays' trees and a few bridges
    water = Geo()
    for sx in (-1, 1):
        xs = np.linspace(sx * (HX - 40), sx * 9000.0, 120)
        for i in range(len(xs) - 1):
            x0, x1 = xs[i], xs[i + 1]
            w0 = 28.0 + abs(x0) * 0.004
            w1 = 28.0 + abs(x1) * 0.004
            water.face([(x0, river_y(x0) - w0, 0.3), (x1, river_y(x1) - w1, 0.3), (x1, river_y(x1) + w1, 0.3), (x0, river_y(x0) + w0, 0.3)][::sx], 0)
        for k in range(10):
            bx = sx * (HX + 250 + k * 420)
            box(geo, bx, river_y(bx), 3.0, 14, 90, 3.0, 0.0, STONE)
        for xq in np.arange(sx * (HX + 20), sx * 3000.0, sx * 16.0):
            for side in (-1, 1):
                if rng.random() < 0.8:
                    yq = river_y(xq) + side * (40.0 + rng.uniform(-2, 2))
                    r = rng.uniform(4, 6)
                    cylinder(geo, xq, yq, 4.0 + r * 0.6, r, r * 1.5, TREE, n=6, r2=r * 0.35)
    me = bpy.data.meshes.new("seine")
    me.from_pydata(water.v, [], water.f)
    me.materials.append(mat_water)
    T.link(bpy.data.objects.new("seine", me))


# ---------------------------------------------------------------- war: smoke columns, fires at their feet
def smoke_card_mat():
    """A soft dark column on a camera-facing sheet (no volume: a few cards cost almost nothing)."""
    m = bpy.data.materials.new("smoke")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["UV"], sep.inputs[0])
    nz = node(nt, "ShaderNodeTexNoise", Scale=4.0, Detail=6.0, Roughness=0.6)
    nt.links.new(tc.outputs["UV"], nz.inputs["Vector"])
    # across: soft edges that widen with height; along: fade out at the top
    cx = math_op(nt, "ABSOLUTE", math_op(nt, "SUBTRACT", sep.outputs[0], 0.5))
    width = math_op(nt, "ADD", 0.12, math_op(nt, "MULTIPLY", sep.outputs[1], 0.3))
    edge = math_op(nt, "SUBTRACT", 1.0, math_op(nt, "DIVIDE", cx, width))
    top = math_op(nt, "SUBTRACT", 1.0, math_op(nt, "POWER", sep.outputs[1], 3.0))
    shape = math_op(nt, "MULTIPLY", math_op(nt, "MAXIMUM", edge, 0.0), top)
    dens = math_op(nt, "MULTIPLY", shape, math_op(nt, "MULTIPLY", nz.outputs[0], 1.6))
    alpha = math_op(nt, "MINIMUM", math_op(nt, "MULTIPLY", dens, 1.3), 0.92)
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    em = node(nt, "ShaderNodeBsdfDiffuse", Color=(*T.lin("3B3A39"), 1))
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(alpha, mix.inputs[0])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    return m


def smoke_columns():
    sm = smoke_card_mat()
    fire = bpy.data.materials.new("fire")
    fire.use_nodes = True
    fn = fire.node_tree
    fn.nodes.clear()
    fo = fn.nodes.new("ShaderNodeOutputMaterial")
    fe = node(fn, "ShaderNodeEmission", Color=(1.0, 0.36, 0.06, 1.0), Strength=3.0)
    fn.links.new(fe.outputs[0], fo.inputs[0])
    for k in range(11):
        a = math.radians(k * 33.0 + rng.uniform(-10, 10))
        dist = rng.uniform(700, 3200)
        x, y = math.sin(a) * dist, math.cos(a) * dist
        z = height(x, y) + 20.0
        hgt = rng.uniform(300, 650) * (0.6 + dist / 4000)
        wid = hgt * rng.uniform(0.5, 0.7)
        # the sheet faces the camera, leans with the wind (east)
        nx, ny = -math.cos(a), math.sin(a)  # across the line of sight
        lean = rng.uniform(0.15, 0.3) * hgt
        v = [(x - nx * wid / 2, y - ny * wid / 2, z), (x + nx * wid / 2, y + ny * wid / 2, z),
             (x + nx * wid / 2 + lean, y + ny * wid / 2, z + hgt), (x - nx * wid / 2 + lean, y - ny * wid / 2, z + hgt)]
        me = bpy.data.meshes.new("smoke")
        me.from_pydata(v, [], [(0, 1, 2, 3)])
        uv = me.uv_layers.new(name="UVMap")
        uv.data.foreach_set("uv", [0, 0, 1, 0, 1, 1, 0, 1])
        me.materials.append(sm)
        ob = T.link(bpy.data.objects.new("smoke", me))
        ob.visible_shadow = False
        fg = Geo()
        for j in range(3):
            fx, fy = x + rng.uniform(-15, 15), y + rng.uniform(-15, 15)
            r = rng.uniform(5, 10)
            cylinder(fg, fx, fy, z - 22, r, r * 2.2, 0, n=7, r2=r * 0.3)
        fme = bpy.data.meshes.new("fire")
        fme.from_pydata(fg.v, [], fg.f)
        fme.materials.append(fire)
        T.link(bpy.data.objects.new("fire", fme))


# ---------------------------------------------------------------- sky and light: an overcast day
world = bpy.data.worlds.new("sky")
world.use_nodes = True
scene.world = world
wn = world.node_tree
wn.nodes.clear()
wout = wn.nodes.new("ShaderNodeOutputWorld")
bg = wn.nodes.new("ShaderNodeBackground")
geom = wn.nodes.new("ShaderNodeNewGeometry")
sepw = wn.nodes.new("ShaderNodeSeparateXYZ")
wn.links.new(geom.outputs["Incoming"], sepw.inputs[0])
up = math_op(wn, "POWER", math_op(wn, "MAXIMUM", sepw.outputs["Z"], 0.0), 0.6)
grad = node(wn, "ShaderNodeMix", dt="RGBA")
wn.links.new(up, grad.inputs[0])
grad.inputs[6].default_value = (*SKY_LOW, 1)
grad.inputs[7].default_value = (*SKY_TOP, 1)
clouds = node(wn, "ShaderNodeTexNoise", Scale=2.2, Detail=8.0, Roughness=0.62)
wn.links.new(geom.outputs["Incoming"], clouds.inputs["Vector"])
cl = node(wn, "ShaderNodeMix", dt="RGBA")
wn.links.new(math_op(wn, "MULTIPLY", math_op(wn, "SUBTRACT", clouds.outputs[0], 0.45), 0.7), cl.inputs[0])
wn.links.new(grad.outputs[2], cl.inputs[6])
cl.inputs[7].default_value = (*T.lin("8E9196"), 1)  # darker cloud bases
wn.links.new(cl.outputs[2], bg.inputs[0])
bg.inputs[1].default_value = 1.0
wn.links.new(bg.outputs[0], wout.inputs[0])
sun_d = bpy.data.lights.new("sun", "SUN")
sun_d.energy = 1.2
sun_d.color = (0.95, 0.96, 1.0)
sun_d.angle = math.radians(25.0)   # through the clouds: soft shadows
sun = T.link(bpy.data.objects.new("sun", sun_d))
sun.rotation_euler = Euler((math.radians(50), 0, math.radians(225 - 180)))

build_terrain()
city()
landmarks()
geo.commit("city")
smoke_columns()

# ---------------------------------------------------------------- camera and render
cd = bpy.data.cameras.new("cam")
cd.type = "PANO"
try:
    cd.panorama_type = "EQUIRECTANGULAR"
except AttributeError:
    cd.cycles.panorama_type = "EQUIRECTANGULAR"
cd.clip_end = 30000.0
cam = T.link(bpy.data.objects.new("cam", cd))
cam.location = (0, 0, CAM_Z)
cam.rotation_euler = Euler((math.radians(90), 0, 0))   # looking north
scene.camera = cam
scene.cycles.use_denoising = True
scene.cycles.max_bounces = 3
scene.cycles.transparent_max_bounces = 8
scene.view_settings.view_transform = "Standard"
scene.render.image_settings.file_format = "PNG"
LO, HI = -15.0, 40.0   # the band the stage can show, in degrees above the horizon


def render(width, samples, band, path):
    scene.render.resolution_x, scene.render.resolution_y = width, width // 2
    scene.render.resolution_percentage = 100
    scene.cycles.samples = samples
    scene.render.use_border = band
    scene.render.use_crop_to_border = False
    if band:
        scene.render.border_min_x, scene.render.border_max_x = 0.0, 1.0
        scene.render.border_min_y, scene.render.border_max_y = (90 + LO) / 180.0, (90 + HI) / 180.0
    scene.render.filepath = path
    try:
        bpy.ops.render.render(write_still=True)
    except RuntimeError:
        scene.cycles.use_denoising = False
        bpy.ops.render.render(write_still=True)
    return np.asarray(Image.open(path).convert("RGB")).astype(np.float32)


tmp = os.path.join(T.ROOT, "assets", "backdrops", "_paris_render.png")
full = render(max(512, W // 8), max(8, SAMPLES // 2), False, tmp)          # sky above and ground below
bandimg = render(W, SAMPLES, True, tmp)                                    # the city, full size
os.remove(tmp)
H = W // 2
up_img = np.asarray(Image.fromarray(full.astype(np.uint8)).resize((W, H), Image.BICUBIC)).astype(np.float32)
rows = np.arange(H)
lat = 90.0 - (rows + 0.5) / H * 180.0       # image row -> degrees above the horizon
blend = np.clip(np.minimum(lat - LO, HI - lat) / 2.0, 0.0, 1.0)[:, None, None]  # 2 degrees of cross-fade at the band's edges
img = up_img * (1 - blend) + bandimg * blend
img = np.roll(img, W // 2, axis=1)   # Cycles puts the view direction (north) in the middle; Godot wants it at u = 0
out = os.path.join(T.ROOT, "assets", "backdrops", "paris_city.jpg" if FINAL else "_paris_test.jpg")
Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(out, quality=90)
print("saved", out)

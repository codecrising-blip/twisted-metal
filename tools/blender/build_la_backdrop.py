"""Los Angeles backdrop (round 10): the city beyond the walls, burning. Rendered with Cycles as one
equirectangular panorama and shown as the sky in the game (nothing here costs frames).
    /tmp/bpy3.13/bin/python tools/blender/build_la_backdrop.py [width] [samples]
Writes assets/backdrops/los_angeles_city.jpg (u = 0 looks north, growing east, as Godot reads it).
Owner: "a real battleground, fires in the city: Calypso has made the whole planet his arena".
What is in it: the Hollywood hills to the north with a brush fire along the ridge, blocks of dark
mid-rises all round (power is out; the only lit windows are burning rooms), a broken downtown
skyline, a dozen tall smoke columns leaning with the wind, a low red sun behind the smoke, and
Calypso's blimp hanging over it all. Blender space: +Y north, +X east, +Z up."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
import bmesh
import bpy
import numpy as np
from mathutils import Euler, Vector
from PIL import Image

W = int(sys.argv[1]) if len(sys.argv) > 1 else 4096
SAMPLES = int(sys.argv[2]) if len(sys.argv) > 2 else 96
scene = T.reset()
rng = np.random.default_rng(11)
SUN_EL, SUN_AZ = 17.0, 242.0   # low in the west-south-west (matches the game's sun)
HAZE = (0.34, 0.2, 0.12)


def link(ob):
    scene.collection.objects.link(ob)
    return ob


def hazed(name, build):
    """A material that fades into the smoke haze with distance: build(nt) -> a BSDF output socket."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    mix = nt.nodes.new("ShaderNodeMixShader")
    cam = nt.nodes.new("ShaderNodeCameraData")
    k = nt.nodes.new("ShaderNodeMath")
    k.operation = "MULTIPLY"
    k.inputs[1].default_value = -1.0 / 1500.0
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
    hz.inputs[1].default_value = 1.0
    nt.links.new(inv.outputs[0], mix.inputs[0])
    nt.links.new(build(nt), mix.inputs[1])
    nt.links.new(hz.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    return m


# ---------------------------------------------------------------- sky: smoke over a low sun
world = bpy.data.worlds.new("sky")
world.use_nodes = True
scene.world = world
wn = world.node_tree
wn.nodes.clear()
wout = wn.nodes.new("ShaderNodeOutputWorld")
bg = wn.nodes.new("ShaderNodeBackground")
sky = wn.nodes.new("ShaderNodeTexSky")
for t in ("MULTIPLE_SCATTERING", "NISHITA", "HOSEK_WILKIE"):
    try:
        sky.sky_type = t
        break
    except TypeError:
        continue
for attr, val in (("sun_elevation", math.radians(SUN_EL)), ("sun_rotation", math.radians(SUN_AZ)), ("air_density", 2.2),
                  ("dust_density", 7.0), ("aerosol_density", 7.0), ("ozone_density", 1.0), ("sun_intensity", 0.25), ("sun_size", math.radians(2.2)), ("altitude", 100.0)):
    try:
        setattr(sky, attr, val)
    except (AttributeError, TypeError):
        pass
# a deck of smoke: noise seen as a flat layer overhead (direction projected on a plane)
geo = wn.nodes.new("ShaderNodeNewGeometry")
sep = wn.nodes.new("ShaderNodeSeparateXYZ")
wn.links.new(geo.outputs["Incoming"], sep.inputs[0])
zc = wn.nodes.new("ShaderNodeMath")
zc.operation = "ADD"
zc.inputs[1].default_value = 0.16
wn.links.new(sep.outputs["Z"], zc.inputs[0])
zabs = wn.nodes.new("ShaderNodeMath")
zabs.operation = "ABSOLUTE"
wn.links.new(zc.outputs[0], zabs.inputs[0])
dx = wn.nodes.new("ShaderNodeMath")
dx.operation = "DIVIDE"
wn.links.new(sep.outputs["X"], dx.inputs[0])
wn.links.new(zabs.outputs[0], dx.inputs[1])
dy = wn.nodes.new("ShaderNodeMath")
dy.operation = "DIVIDE"
wn.links.new(sep.outputs["Y"], dy.inputs[0])
wn.links.new(zabs.outputs[0], dy.inputs[1])
comb = wn.nodes.new("ShaderNodeCombineXYZ")
wn.links.new(dx.outputs[0], comb.inputs[0])
wn.links.new(dy.outputs[0], comb.inputs[1])
noise = wn.nodes.new("ShaderNodeTexNoise")
noise.inputs["Scale"].default_value = 0.55
noise.inputs["Detail"].default_value = 7.0
noise.inputs["Roughness"].default_value = 0.6
wn.links.new(comb.outputs[0], noise.inputs["Vector"])
ramp = wn.nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position = 0.42
ramp.color_ramp.elements[0].color = (0, 0, 0, 1)
ramp.color_ramp.elements[1].position = 0.7
ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
wn.links.new(noise.outputs[0], ramp.inputs[0])
smoke_col = wn.nodes.new("ShaderNodeRGB")
smoke_col.outputs[0].default_value = (0.11, 0.085, 0.07, 1.0)
mixc = wn.nodes.new("ShaderNodeMix")
mixc.data_type = "RGBA"
wn.links.new(ramp.outputs[0], mixc.inputs[0])
warm = wn.nodes.new("ShaderNodeMix")
warm.data_type = "RGBA"
warm.blend_type = "MULTIPLY"
warm.inputs[0].default_value = 1.0
wn.links.new(sky.outputs[0], warm.inputs[6])
warm.inputs[7].default_value = (1.0, 0.8, 0.62, 1.0)
wn.links.new(warm.outputs[2], mixc.inputs[6])
wn.links.new(smoke_col.outputs[0], mixc.inputs[7])
# everything sinks into a brown-orange murk toward the horizon
hz_f = wn.nodes.new("ShaderNodeMath")
hz_f.operation = "SMOOTHSTEP" if False else "MULTIPLY"
low = wn.nodes.new("ShaderNodeMapRange")
low.inputs["From Min"].default_value = -0.02
low.inputs["From Max"].default_value = 0.22
low.inputs["To Min"].default_value = 0.92
low.inputs["To Max"].default_value = 0.0
wn.links.new(sep.outputs["Z"], low.inputs["Value"])
murk = wn.nodes.new("ShaderNodeRGB")
murk.outputs[0].default_value = (HAZE[0] * 1.5, HAZE[1] * 1.4, HAZE[2] * 1.2, 1.0)
mixh = wn.nodes.new("ShaderNodeMix")
mixh.data_type = "RGBA"
wn.links.new(low.outputs[0], mixh.inputs[0])
wn.links.new(mixc.outputs[2], mixh.inputs[6])
wn.links.new(murk.outputs[0], mixh.inputs[7])
wn.links.new(mixh.outputs[2], bg.inputs[0])
bg.inputs[1].default_value = 0.85
wn.links.new(bg.outputs[0], wout.inputs[0])

sun_d = bpy.data.lights.new("sun", "SUN")
sun_d.energy = 3.4
sun_d.color = (1.0, 0.45, 0.22)
sun_d.angle = math.radians(3.0)
sun = link(bpy.data.objects.new("sun", sun_d))
az, el = math.radians(SUN_AZ), math.radians(SUN_EL)
to_sun = Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)))
sun.rotation_euler = to_sun.to_track_quat("Z", "Y").to_euler()

# ---------------------------------------------------------------- ground and hills
def ground_mat(nt):
    b = nt.nodes.new("ShaderNodeBsdfDiffuse")
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = 0.01
    r = nt.nodes.new("ShaderNodeValToRGB")
    r.color_ramp.elements[0].color = (0.03, 0.026, 0.022, 1)
    r.color_ramp.elements[1].color = (0.085, 0.07, 0.05, 1)
    nt.links.new(n.outputs[0], r.inputs[0])
    nt.links.new(r.outputs[0], b.inputs[0])
    return b.outputs[0]

bm = bmesh.new()
bmesh.ops.create_grid(bm, x_segments=2, y_segments=2, size=9000.0)
me = bpy.data.meshes.new("ground")
bm.to_mesh(me)
bm.free()
g = link(bpy.data.objects.new("ground", me))
g.location = (0, 0, -6.0)
me.materials.append(hazed("ground", ground_mat))


def hill_h(x, y):
    """Height of the hills north of the arena (0 elsewhere)."""
    d = y - 250.0
    ridge = np.clip(d / 260.0, 0, 1) * np.clip((1500.0 - y) / 500.0, 0, 1)
    wide = np.exp(-(x / 1150.0) ** 2)
    P = np.stack([x * 0.004, y * 0.004, np.zeros_like(x)], axis=1)
    n = T.fbm(P, 1.0, 5, 3)
    n2 = T.fbm(P, 3.1, 4, 9)
    return ridge * wide * (170.0 + 300.0 * n + 60.0 * n2) * (0.55 + 0.45 * np.clip(d / 600.0, 0, 1))

NX, NY = 150, 80
xs = np.linspace(-2600, 2600, NX)
ys = np.linspace(230, 1750, NY)
gx, gy = np.meshgrid(xs, ys)
hz = hill_h(gx.reshape(-1), gy.reshape(-1)).reshape(NY, NX)
bm = bmesh.new()
vs = [[bm.verts.new((gx[j, i], gy[j, i], hz[j, i] - 6.0)) for i in range(NX)] for j in range(NY)]
for j in range(NY - 1):
    for i in range(NX - 1):
        bm.faces.new((vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i]))
me = bpy.data.meshes.new("hills")
bm.to_mesh(me)
bm.free()
for p in me.polygons:
    p.use_smooth = True
hills = link(bpy.data.objects.new("hills", me))


def hill_mat(nt):
    b = nt.nodes.new("ShaderNodeBsdfDiffuse")
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = 0.035
    n.inputs["Detail"].default_value = 8.0
    r = nt.nodes.new("ShaderNodeValToRGB")
    r.color_ramp.elements[0].position = 0.35
    r.color_ramp.elements[0].color = (0.018, 0.014, 0.011, 1)   # burnt scrub
    r.color_ramp.elements[1].position = 0.7
    r.color_ramp.elements[1].color = (0.12, 0.085, 0.045, 1)    # dry chaparral
    nt.links.new(n.outputs[0], r.inputs[0])
    nt.links.new(r.outputs[0], b.inputs[0])
    return b.outputs[0]

me.materials.append(hazed("hills", hill_mat))

# ---------------------------------------------------------------- fire and smoke
fire_mat = bpy.data.materials.new("fire")
fire_mat.use_nodes = True
fn = fire_mat.node_tree
fn.nodes.clear()
fo = fn.nodes.new("ShaderNodeOutputMaterial")
fe = fn.nodes.new("ShaderNodeEmission")
fnz = fn.nodes.new("ShaderNodeTexNoise")
fnz.inputs["Scale"].default_value = 0.2
fr = fn.nodes.new("ShaderNodeValToRGB")
fr.color_ramp.elements[0].color = (0.9, 0.1, 0.01, 1)
fr.color_ramp.elements[1].color = (1.0, 0.42, 0.06, 1)
fn.links.new(fnz.outputs[0], fr.inputs[0])
fn.links.new(fr.outputs[0], fe.inputs[0])
fe.inputs[1].default_value = 1.4   # stays orange: anything brighter clips to yellow-white in the panorama
fn.links.new(fe.outputs[0], fo.inputs[0])


def smoke_mat(density, glow):
    m = bpy.data.materials.new("smoke")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = (0.045, 0.04, 0.036, 1)
    vol.inputs["Anisotropy"].default_value = 0.35
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 3.2
    nz.inputs["Detail"].default_value = 5.0
    nt.links.new(tc.outputs["Generated"], nz.inputs["Vector"])
    sp = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sp.inputs[0])
    r = nt.nodes.new("ShaderNodeMapRange")
    r.inputs["From Min"].default_value = 0.36
    r.inputs["From Max"].default_value = 0.66
    r.inputs["To Min"].default_value = 0.0
    r.inputs["To Max"].default_value = density
    nt.links.new(nz.outputs[0], r.inputs["Value"])
    thin = nt.nodes.new("ShaderNodeMapRange")   # thinner with height
    thin.inputs["From Min"].default_value = 0.0
    thin.inputs["From Max"].default_value = 1.0
    thin.inputs["To Min"].default_value = 1.6
    thin.inputs["To Max"].default_value = 0.25
    nt.links.new(sp.outputs["Z"], thin.inputs["Value"])
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    nt.links.new(r.outputs["Result"], mul.inputs[0])
    nt.links.new(thin.outputs["Result"], mul.inputs[1])
    nt.links.new(mul.outputs[0], vol.inputs["Density"])
    hot = nt.nodes.new("ShaderNodeMapRange")    # lit by the fire at its foot
    hot.inputs["From Min"].default_value = 0.0
    hot.inputs["From Max"].default_value = 0.1
    hot.inputs["To Min"].default_value = glow
    hot.inputs["To Max"].default_value = 0.0
    nt.links.new(sp.outputs["Z"], hot.inputs["Value"])
    nt.links.new(hot.outputs["Result"], vol.inputs["Emission Strength"])
    vol.inputs["Emission Color"].default_value = (1.0, 0.3, 0.06, 1)
    nt.links.new(vol.outputs[0], out.inputs["Volume"])
    return m


def plume(x, y, z0, height, r0, r1, lean, density=0.012, glow=0.5):
    """A column of smoke: a tube widening with height, pushed east by the wind."""
    bm = bmesh.new()
    rings = []
    n, levels = 10, 9
    for k in range(levels + 1):
        t = k / levels
        r = r0 + (r1 - r0) * t ** 0.8
        ox = lean * height * t ** 1.6
        oy = lean * height * 0.25 * t ** 1.6
        rings.append([bm.verts.new((x + ox + r * math.cos(2 * math.pi * i / n), y + oy + r * math.sin(2 * math.pi * i / n), z0 + height * t)) for i in range(n)])
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    me = bpy.data.meshes.new("plume")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(smoke_mat(density, glow))
    return link(bpy.data.objects.new("plume", me))


def fire(x, y, z, size):
    bm = bmesh.new()
    for k in range(5):
        m = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=size * rng.uniform(0.35, 0.8))
        off = Vector((rng.uniform(-1, 1) * size, rng.uniform(-1, 1) * size, rng.uniform(0, 1.3) * size))
        for v in m["verts"]:
            v.co += off
            v.co.z *= 1.5
    me = bpy.data.meshes.new("fire")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(fire_mat)
    ob = link(bpy.data.objects.new("fire", me))
    ob.location = (x, y, z)
    return ob


# ---------------------------------------------------------------- the city
def building_mat(nt):
    b = nt.nodes.new("ShaderNodeBsdfDiffuse")
    info = nt.nodes.new("ShaderNodeObjectInfo")
    wall = nt.nodes.new("ShaderNodeValToRGB")
    wall.color_ramp.elements[0].color = (0.03, 0.028, 0.026, 1)
    wall.color_ramp.elements[1].color = (0.16, 0.13, 0.1, 1)
    nt.links.new(info.outputs["Random"], wall.inputs[0])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.offset = 0.0
    brick.inputs["Scale"].default_value = 0.16
    brick.inputs["Mortar Size"].default_value = 0.035
    brick.inputs["Color1"].default_value = (0, 0, 0, 1)
    brick.inputs["Color2"].default_value = (0.02, 0.02, 0.02, 1)
    brick.inputs["Mortar"].default_value = (1, 1, 1, 1)
    brick.inputs["Brick Width"].default_value = 0.42
    brick.inputs["Row Height"].default_value = 0.5
    mapn = nt.nodes.new("ShaderNodeMapping")
    mapn.inputs["Rotation"].default_value = (math.radians(90), 0, 0)
    nt.links.new(tc.outputs["Object"], mapn.inputs[0])
    nt.links.new(mapn.outputs[0], brick.inputs["Vector"])
    mixw = nt.nodes.new("ShaderNodeMix")
    mixw.data_type = "RGBA"
    nt.links.new(brick.outputs["Color"], mixw.inputs[0])
    mixw.inputs[6].default_value = (0.006, 0.006, 0.007, 1)   # dead windows
    nt.links.new(wall.outputs[0], mixw.inputs[7])
    soot = nt.nodes.new("ShaderNodeTexNoise")
    soot.inputs["Scale"].default_value = 0.03
    dark = nt.nodes.new("ShaderNodeMix")
    dark.data_type = "RGBA"
    dark.blend_type = "MULTIPLY"
    dark.inputs[0].default_value = 0.85
    nt.links.new(mixw.outputs[2], dark.inputs[6])
    nt.links.new(soot.outputs[0], dark.inputs[7])
    nt.links.new(dark.outputs[2], b.inputs[0])
    return b.outputs[0]

bmat = hazed("building", building_mat)
fires = []


def building(x, y, w, d, h, yaw, broken):
    bm = bmesh.new()
    def add(sx, sy, sz, ox, oy, oz, tilt=0.0):
        m = bmesh.ops.create_cube(bm, size=1.0)
        for v in m["verts"]:
            v.co = Vector((v.co.x * sx + ox + v.co.z * sz * tilt, v.co.y * sy + oy, v.co.z * sz + oz))
    if broken:   # the top is gone: a stump, jagged leftovers, a lean
        cut = h * rng.uniform(0.35, 0.75)
        tilt = rng.uniform(-0.08, 0.08)
        add(w, d, cut, 0, 0, cut / 2, tilt)
        for k in range(int(rng.integers(3, 7))):
            sw, sd = w * rng.uniform(0.15, 0.45), d * rng.uniform(0.15, 0.45)
            sh = h * rng.uniform(0.05, 0.3)
            add(sw, sd, sh, rng.uniform(-0.5, 0.5) * (w - sw), rng.uniform(-0.5, 0.5) * (d - sd), cut + sh / 2 - 1.0, tilt)
    else:
        add(w, d, h, 0, 0, h / 2)
        if h > 60:   # setback on the towers
            add(w * 0.6, d * 0.6, h * 0.18, 0, 0, h + h * 0.09)
    me = bpy.data.meshes.new("b")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(bmat)
    ob = link(bpy.data.objects.new("b", me))
    ob.location = (x, y, -6.0)
    ob.rotation_euler = Euler((0, 0, yaw))
    return ob

n_b = 0
for k in range(1500):
    a = rng.uniform(0, 2 * math.pi)
    r = 215.0 + 1900.0 * rng.uniform(0, 1) ** 2.0
    x, y = math.sin(a) * r, math.cos(a) * r
    if y > 300 and abs(x) < 1500 and hill_h(np.array([x]), np.array([y]))[0] > 12.0:
        continue   # that is hillside
    near = 1.0 - min(r / 1500.0, 1.0)
    h = float(np.clip(rng.lognormal(3.1, 0.5), 9, 95)) * (0.6 + 0.8 * near)
    w, d = rng.uniform(16, 44), rng.uniform(16, 44)
    broken = rng.uniform() < 0.3
    building(x, y, w, d, h, rng.uniform(0, math.pi), broken)
    n_b += 1
    if rng.uniform() < 0.03 and r > 260:
        fires.append((x, y, h * (0.5 if broken else 0.9), rng.uniform(7, 15)))
# downtown: a cluster of towers to the south-east, some of them broken
DT = (math.sin(math.radians(138)) * 1250.0, math.cos(math.radians(138)) * 1250.0)
for k in range(26):
    x = DT[0] + rng.normal(0, 190)
    y = DT[1] + rng.normal(0, 150)
    h = rng.uniform(90, 270) * (1.0 - min(1.0, math.hypot(x - DT[0], y - DT[1]) / 600.0) * 0.5)
    broken = rng.uniform() < 0.38
    building(x, y, rng.uniform(34, 60), rng.uniform(34, 60), h, rng.uniform(0, 0.5), broken)
    if rng.uniform() < 0.3:
        fires.append((x, y, h * (0.45 if broken else 0.7), rng.uniform(14, 24)))
# brush fire along the ridge behind the sign
for k in range(16):
    x = rng.uniform(-1500, 1500)
    y = rng.uniform(430, 900)
    z = hill_h(np.array([x]), np.array([y]))[0]
    if z > 25:
        fires.append((x, y, z - 4.0, rng.uniform(9, 20)))

fires = fires[:46]
for i, (x, y, z, s) in enumerate(fires):
    fire(x, y, z - 6.0, s)
big = sorted(range(len(fires)), key=lambda i: -fires[i][3])[:13]
for i in big:
    x, y, z, s = fires[i]
    hgt = rng.uniform(380, 900)
    plume(x, y, z - 6.0, hgt, s * 0.9, s * rng.uniform(8, 14), rng.uniform(0.35, 0.6), density=rng.uniform(0.012, 0.022), glow=rng.uniform(0.04, 0.1))
print("buildings", n_b, "fires", len(fires), "plumes", len(big))

# ---------------------------------------------------------------- Calypso's blimp, far off in the east
def blimp_mat(nt):
    b = nt.nodes.new("ShaderNodeBsdfDiffuse")
    b.inputs[0].default_value = (0.02, 0.02, 0.022, 1)
    return b.outputs[0]

bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=10, radius=1.0)
for v in bm.verts:
    v.co = Vector((v.co.x * 95.0, v.co.y * 24.0, v.co.z * 24.0))
gond = bmesh.ops.create_cube(bm, size=1.0)
for v in gond["verts"]:
    v.co = Vector((v.co.x * 28.0, v.co.y * 8.0, v.co.z * 6.0 - 27.0))
for sgn in (1, -1):
    fin = bmesh.ops.create_cube(bm, size=1.0)
    for v in fin["verts"]:
        v.co = Vector((v.co.x * 26.0 - 78.0, v.co.y * 2.0, v.co.z * 20.0 + sgn * 19.0))
me = bpy.data.meshes.new("blimp")
bm.to_mesh(me)
bm.free()
for p in me.polygons:
    p.use_smooth = True
me.materials.append(hazed("blimp", blimp_mat))
bl = link(bpy.data.objects.new("blimp", me))
bl.location = (math.sin(math.radians(74)) * 1000.0, math.cos(math.radians(74)) * 1000.0, 430.0)
bl.rotation_euler = Euler((0, 0, math.radians(35)))
for k in range(3):   # its red running lights
    f = fire(bl.location.x + (k - 1) * 40.0 * math.cos(math.radians(35)), bl.location.y + (k - 1) * 40.0 * math.sin(math.radians(35)), bl.location.z - 31.0, 2.6)

# ---------------------------------------------------------------- camera and render
cd = bpy.data.cameras.new("cam")
cd.type = "PANO"
try:
    cd.panorama_type = "EQUIRECTANGULAR"
except AttributeError:
    cd.cycles.panorama_type = "EQUIRECTANGULAR"
cd.clip_end = 30000.0
cam = link(bpy.data.objects.new("cam", cd))
cam.location = (0, 0, 9.0)
cam.rotation_euler = Euler((math.radians(90), 0, 0))   # looking north
scene.camera = cam
scene.render.resolution_x, scene.render.resolution_y = W, W // 2
scene.render.resolution_percentage = 100
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.cycles.max_bounces = 3
scene.cycles.volume_bounces = 0
scene.cycles.volume_step_rate = 4.0
scene.cycles.volume_max_steps = 96
scene.view_settings.view_transform = "Standard"
scene.view_settings.exposure = 0.0
tmp = os.path.join(T.ROOT, "assets", "backdrops", "_la_render.png")
scene.render.filepath = tmp
scene.render.image_settings.file_format = "PNG"
try:
    bpy.ops.render.render(write_still=True)
except RuntimeError:
    scene.cycles.use_denoising = False
    bpy.ops.render.render(write_still=True)
im = Image.open(tmp).convert("RGB")
a = np.asarray(im)
a = np.roll(a, a.shape[1] // 2, axis=1)   # Cycles puts the view direction (north) in the middle; Godot wants it at u = 0
out = os.path.join(T.ROOT, "assets", "backdrops", "los_angeles_city.jpg" if W >= 2048 else "_la_test.jpg")
Image.fromarray(a).save(out, quality=90)
os.remove(tmp)
print("saved", out)

"""Paris backdrop (round 30, owner: "the map has no background from there"): the city beyond the edge walls,
rendered with Cycles as one equirectangular panorama and shown as the sky in the game (costs no frames).
    /tmp/bpy3.13/bin/python tools/blender/build_paris_backdrop.py [width] [samples]
Writes assets/backdrops/paris_city.jpg (u = 0 looks north, growing east, as Godot reads it).
What is in it: 4 pm under a clear sky with warm haze low down (the stage's own light, design 32 section 5);
Haussmann blocks to the horizon (cream stone, blue-grey zinc mansards, chimneys); the Seine running on west and
east; La Defense's towers and the Grande Arche to the west-north-west; columns of war smoke over the city with
fires at their feet. Blender space: +Y north, +X east, +Z up (Godot z = -Blender y)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector
from PIL import Image

W = int(sys.argv[1]) if len(sys.argv) > 1 else 4096
SAMPLES = int(sys.argv[2]) if len(sys.argv) > 2 else 64
scene = T.reset()
rng = np.random.default_rng(30)
SUN_EL, SUN_AZ = 35.0, 225.0  # the game's sun: 35 degrees up in the south-west
HAZE = (0.78, 0.72, 0.62)
HX, HZ = 290.0, 240.0  # just past the map (275 x 225) and its edge wall


def link(ob):
    scene.collection.objects.link(ob)
    return ob


def lin(h):
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def river_y(x):
    """The Seine's line in Blender y (Godot's river_z, negated), carried on past the map."""
    return -(62.0 + 6.0 * max(-1.0, min(1.0, x / 600.0)))


def hazed(name, build, reach=2600.0):
    """A material that fades into the warm haze with distance: build(nt) -> a shader output socket."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    mix = nt.nodes.new("ShaderNodeMixShader")
    cam = nt.nodes.new("ShaderNodeCameraData")
    k = nt.nodes.new("ShaderNodeMath")
    k.operation = "MULTIPLY"
    k.inputs[1].default_value = -1.0 / reach
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


def principled(color, rough=0.8, metal=0.0, bands=None):
    def build(nt):
        b = nt.nodes.new("ShaderNodeBsdfPrincipled")
        b.inputs["Base Color"].default_value = (*color, 1.0)
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = metal
        if bands: # rows of dark windows: bands up the walls (floors) broken by columns (bays)
            tc = nt.nodes.new("ShaderNodeTexCoord")
            sep = nt.nodes.new("ShaderNodeSeparateXYZ")
            nt.links.new(tc.outputs["Object"], sep.inputs[0])
            rows = nt.nodes.new("ShaderNodeMath")
            rows.operation = "PINGPONG"
            rows.inputs[1].default_value = 1.56
            nt.links.new(sep.outputs["Z"], rows.inputs[0])
            step = nt.nodes.new("ShaderNodeMath")
            step.operation = "GREATER_THAN"
            step.inputs[1].default_value = 0.85
            nt.links.new(rows.outputs[0], step.inputs[0])
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.inputs[6].default_value = (*color, 1.0)
            mix.inputs[7].default_value = (*bands, 1.0)
            nt.links.new(step.outputs[0], mix.inputs[0])
            nt.links.new(mix.outputs[2], b.inputs["Base Color"])
        return b.outputs[0]
    return build


# ---------------------------------------------------------------- sky: clear afternoon, warm haze low down
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
for attr, val in (("sun_elevation", math.radians(SUN_EL)), ("sun_rotation", math.radians(SUN_AZ)), ("air_density", 1.0),
                  ("dust_density", 2.5), ("aerosol_density", 2.5), ("ozone_density", 1.0), ("sun_intensity", 0.2), ("sun_size", math.radians(1.5)), ("altitude", 100.0)):
    try:
        setattr(sky, attr, val)
    except (AttributeError, TypeError):
        pass
geo = wn.nodes.new("ShaderNodeNewGeometry")
sep = wn.nodes.new("ShaderNodeSeparateXYZ")
wn.links.new(geo.outputs["Incoming"], sep.inputs[0])
low = wn.nodes.new("ShaderNodeMapRange")
low.inputs["From Min"].default_value = -0.02
low.inputs["From Max"].default_value = 0.18
low.inputs["To Min"].default_value = 0.85
low.inputs["To Max"].default_value = 0.0
wn.links.new(sep.outputs["Z"], low.inputs["Value"])
murk = wn.nodes.new("ShaderNodeRGB")
murk.outputs[0].default_value = (*HAZE, 1.0)
mixh = wn.nodes.new("ShaderNodeMix")
mixh.data_type = "RGBA"
wn.links.new(low.outputs[0], mixh.inputs[0])
wn.links.new(sky.outputs[0], mixh.inputs[6])
wn.links.new(murk.outputs[0], mixh.inputs[7])
wn.links.new(mixh.outputs[2], bg.inputs[0])
bg.inputs[1].default_value = 0.3 # the Nishita sky is physically bright: down to the stage's blue
wn.links.new(bg.outputs[0], wout.inputs[0])

sun_d = bpy.data.lights.new("sun", "SUN")
sun_d.energy = 4.0
sun_d.color = (1.0, 0.94, 0.86)
sun_d.angle = math.radians(2.0)
sun = link(bpy.data.objects.new("sun", sun_d))
az, el = math.radians(SUN_AZ), math.radians(SUN_EL)
to_sun = Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)))
sun.rotation_euler = to_sun.to_track_quat("Z", "Y").to_euler()

# ---------------------------------------------------------------- ground and the Seine
def disc(name, r, z, mat):
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, segments=64, radius=r)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = link(bpy.data.objects.new(name, me))
    ob.location.z = z
    return ob


disc("ground", 9000.0, -0.2, hazed("ground", principled(lin("8F877A"), 0.95)))
water = hazed("water", principled(lin("3E5856"), 0.12, 0.0))
for sx in (-1, 1):
    bm = bmesh.new()
    xs = np.linspace(sx * HX, sx * 4200.0, 60)
    a = [bm.verts.new((x, river_y(x) - 20.0, 0.0)) for x in xs]
    b = [bm.verts.new((x, river_y(x) + 20.0, 0.0)) for x in xs]
    for i in range(len(xs) - 1):
        bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]) if sx > 0 else (a[i], b[i], b[i + 1], a[i + 1]))
    me = bpy.data.meshes.new("seine")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(water)
    link(bpy.data.objects.new("seine", me))

# ---------------------------------------------------------------- the city: Haussmann blocks to the horizon
walls = bmesh.new()
roofs = bmesh.new()
chim = bmesh.new()


def block(bm, x, y, w, d, h, yaw):
    m = Matrix.Translation((x, y, h / 2)) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Diagonal((w, d, h, 1.0))
    bmesh.ops.create_cube(bm, size=1.0, matrix=m)


def mansard(bm, x, y, w, d, z, h, yaw, inset=2.5):
    rot = Matrix.Rotation(yaw, 4, "Z")
    lo = [Vector((sx * w / 2, sy * d / 2, 0)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    hi = [Vector((sx * (w / 2 - inset), sy * (d / 2 - inset), h)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    vl = [bm.verts.new((rot @ v.to_4d()).to_3d() + Vector((x, y, z))) for v in lo]
    vh = [bm.verts.new((rot @ v.to_4d()).to_3d() + Vector((x, y, z))) for v in hi]
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((vl[i], vl[j], vh[j], vh[i]))
    bm.faces.new(vh)


n_blocks = 0
step = 62.0
R = 2600.0
for gx in np.arange(-R, R, step):
    for gy in np.arange(-R, R, step):
        x = gx + rng.uniform(-6, 6)
        y = gy + rng.uniform(-6, 6)
        if abs(x) < HX + 30 and abs(y) < HZ + 30:
            continue
        if math.hypot(x, y) > R:
            continue
        if abs(y - river_y(x)) < 48.0 and abs(x) > HX: # the Seine and its quays
            continue
        if rng.random() < 0.08: # a square or a park now and then
            continue
        w, d = rng.uniform(40, 54), rng.uniform(40, 54)
        near = math.hypot(x, y) < 900.0
        h = rng.uniform(24.0, 34.0) if near else rng.uniform(18.0, 26.0) # the first rows stand up over the edge wall
        yaw = math.radians(rng.uniform(-6, 6))
        block(walls, x, y, w, d, h, yaw)
        mansard(roofs, x, y, w, d, h, rng.uniform(2.6, 4.2), yaw)
        for k in range(rng.integers(1, 4)):
            cx = x + rng.uniform(-w / 3, w / 3)
            cy = y + rng.uniform(-d / 3, d / 3)
            m = Matrix.Translation((cx, cy, h + 4.5)) @ Matrix.Diagonal((1.6, 0.7, 2.6, 1.0))
            bmesh.ops.create_cube(chim, size=1.0, matrix=m)
        n_blocks += 1
for name, bm, mat in (("walls", walls, hazed("walls", principled(lin("CDBFA3"), 0.85, bands=lin("4A4238")))),
                      ("roofs", roofs, hazed("roofs", principled(lin("67737D"), 0.45, 0.3))),
                      ("chimneys", chim, hazed("chimneys", principled(lin("A0603E"), 0.8)))):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    link(bpy.data.objects.new(name, me))
print("blocks", n_blocks)

# ---------------------------------------------------------------- La Defense to the west-north-west, the Grande Arche
glass = hazed("glass", principled(lin("5C6E7E"), 0.12, 0.7), reach=3400.0)
towers = bmesh.new()
DA = math.radians(292.0)
for k in range(16):
    dist = rng.uniform(2200, 2900)
    a = DA + math.radians(rng.uniform(-6, 6))
    x, y = math.sin(a) * dist, math.cos(a) * dist
    w, d, h = rng.uniform(30, 55), rng.uniform(30, 50), rng.uniform(90, 210)
    block(towers, x, y, w, d, h, math.radians(rng.uniform(0, 90)))
me = bpy.data.meshes.new("defense")
towers.to_mesh(me)
towers.free()
me.materials.append(glass)
link(bpy.data.objects.new("defense", me))
arche = bmesh.new()
ax, ay = math.sin(DA) * 2050, math.cos(DA) * 2050
S = 105.0
for (cx, cy, cz, sx, sy, sz) in ((0, 0, S - 6, S, 18, 12), (0, 0, 6, S, 18, 12), (-S / 2 + 6, 0, S / 2, 12, 18, S), (S / 2 - 6, 0, S / 2, 12, 18, S)):
    m = Matrix.Translation((ax, ay, 0)) @ Matrix.Rotation(DA, 4, "Z") @ Matrix.Translation((cx, cy, cz)) @ Matrix.Diagonal((sx, sy, sz, 1.0))
    bmesh.ops.create_cube(arche, size=1.0, matrix=m)
me = bpy.data.meshes.new("arche")
arche.to_mesh(me)
arche.free()
me.materials.append(hazed("arche", principled(lin("E4E2DC"), 0.5), reach=3400.0))
link(bpy.data.objects.new("arche", me))

# Tour Montparnasse to the south: one dark slab over the rooftops
mt = bmesh.new()
ma = math.radians(195.0)
block(mt, math.sin(ma) * 1500.0, math.cos(ma) * 1500.0, 50.0, 32.0, 210.0, math.radians(20.0))
me = bpy.data.meshes.new("montparnasse")
mt.to_mesh(me)
mt.free()
me.materials.append(hazed("montparnasse", principled(lin("2E3236"), 0.3, 0.4), reach=3400.0))
link(bpy.data.objects.new("montparnasse", me))

# ---------------------------------------------------------------- war: smoke columns over the city, fires at their feet
fire_mat = bpy.data.materials.new("fire")
fire_mat.use_nodes = True
fn = fire_mat.node_tree
fn.nodes.clear()
fo = fn.nodes.new("ShaderNodeOutputMaterial")
fe = fn.nodes.new("ShaderNodeEmission")
fe.inputs[0].default_value = (1.0, 0.38, 0.06, 1.0)
fe.inputs[1].default_value = 2.0
fn.links.new(fe.outputs[0], fo.inputs[0])


def smoke_mat(density):
    m = bpy.data.materials.new("smoke")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = (0.035, 0.032, 0.03, 1)
    vol.inputs["Anisotropy"].default_value = 0.3
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 3.0
    nz.inputs["Detail"].default_value = 5.0
    nt.links.new(tc.outputs["Generated"], nz.inputs["Vector"])
    r = nt.nodes.new("ShaderNodeMapRange")
    r.inputs["From Min"].default_value = 0.38
    r.inputs["From Max"].default_value = 0.66
    r.inputs["To Min"].default_value = 0.0
    r.inputs["To Max"].default_value = density
    nt.links.new(nz.outputs[0], r.inputs["Value"])
    nt.links.new(r.outputs["Result"], vol.inputs["Density"])
    nt.links.new(vol.outputs[0], out.inputs["Volume"])
    return m


def plume(x, y, height, r0, r1, lean):
    bm = bmesh.new()
    rings = []
    n, levels = 10, 9
    for k in range(levels + 1):
        t = k / levels
        r = r0 + (r1 - r0) * t ** 0.8
        ox, oy = lean * height * t ** 1.6, lean * height * 0.3 * t ** 1.6
        rings.append([bm.verts.new((x + ox + r * math.cos(2 * math.pi * i / n), y + oy + r * math.sin(2 * math.pi * i / n), 15.0 + height * t)) for i in range(n)])
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    me = bpy.data.meshes.new("plume")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(smoke_mat(0.035))
    link(bpy.data.objects.new("plume", me))
    fb = bmesh.new()
    for k in range(4):
        mm = bmesh.ops.create_icosphere(fb, subdivisions=1, radius=r0 * rng.uniform(0.4, 0.8))
        off = Vector((rng.uniform(-1, 1) * r0, rng.uniform(-1, 1) * r0, 18.0 + rng.uniform(0, 1) * r0))
        for v in mm["verts"]:
            v.co += off + Vector((x, y, 0))
            v.co.z = 18.0 + (v.co.z - 18.0) * 1.5
    me = bpy.data.meshes.new("fire")
    fb.to_mesh(me)
    fb.free()
    me.materials.append(fire_mat)
    link(bpy.data.objects.new("fire", me))


for k in range(9):
    a = math.radians(k * 40.0 + rng.uniform(-12, 12))
    dist = rng.uniform(600, 1900)
    plume(math.sin(a) * dist, math.cos(a) * dist, rng.uniform(260, 480), rng.uniform(16, 26), rng.uniform(60, 110), rng.uniform(0.1, 0.22))

# ---------------------------------------------------------------- camera and render
cd = bpy.data.cameras.new("cam")
cd.type = "PANO"
try:
    cd.panorama_type = "EQUIRECTANGULAR"
except AttributeError:
    cd.cycles.panorama_type = "EQUIRECTANGULAR"
cd.clip_end = 30000.0
cam = link(bpy.data.objects.new("cam", cd))
cam.location = (0, 0, 14.0)
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
tmp = os.path.join(T.ROOT, "assets", "backdrops", "_paris_render.png")
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
out = os.path.join(T.ROOT, "assets", "backdrops", "paris_city.jpg" if W >= 2048 else "_paris_test.jpg")
Image.fromarray(a).save(out, quality=90)
os.remove(tmp)
print("saved", out)

"""Paris (round 27): the far-away look of a Haussmann facade, rendered from the kit itself.
    /tmp/bpy3.13/bin/python tools/blender/render_haussmann_far.py
Reads assets/models/haussmann.glb + its baked maps, stacks three bays of the low (13 m roofs) and the
tall block (ground floor up to the cornice), renders them straight on with a narrow lens (nearly
orthographic) and writes assets/models/haussmann_far_low.png / haussmann_far_tall.png. ParisBlocks
paints them on a block's plain shell past NEAR metres, so far blocks look like the near ones."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
import bpy
import numpy as np
from PIL import Image

GH, FH = 4.68, 3.12
PX = 64  # per metre
T.reset()
bpy.ops.import_scene.gltf(filepath=os.path.join(T.OUT, "haussmann.glb"))
src = {o.name: o for o in bpy.context.scene.objects if o.type == "MESH"}
for o in src.values():
    o.hide_render = True
    o.location = (0, 0, 0)


rail = bpy.data.materials.get("rail")
if rail is not None:
    rail.use_nodes = True
    nt = rail.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    im = nt.nodes.new("ShaderNodeTexImage")
    im.image = bpy.data.images.load(os.path.join(T.OUT, "haussmann_rail.png"))
    nt.links.new(im.outputs["Color"], bs.inputs["Base Color"])
    nt.links.new(im.outputs["Alpha"], bs.inputs["Alpha"])
    nt.links.new(bs.outputs[0], out.inputs[0])


def load(name):
    a = np.asarray(Image.open(os.path.join(T.OUT, name)).convert("RGB")).astype(np.float32) / 255.0
    return a


tex = (load("haussmann_albedo.webp"), load("haussmann_normal.webp"), load("haussmann_orm.webp"))


def column(name, grounds, floors):
    made = []
    h = GH + FH * len(floors)
    for b, g in enumerate(grounds):
        x = (b - 1) * 3.0
        stack = [(g, 0.0)] + [(f, GH + FH * k) for k, f in enumerate(floors)]
        if g.startswith("g_shop"):
            stack.append(("awning_red" if b != 1 else "awning_green", 0.0))
        for node, z in stack:
            d = src[node].copy()
            bpy.context.scene.collection.objects.link(d)
            d.hide_render = False
            d.location = (x, 0, z)
            made.append(d)
    dist = 400.0
    fov = math.degrees(2 * math.atan(h * 0.5 / dist))
    path = os.path.join(T.OUT, "haussmann_far_%s.png" % name)
    T.preview(path, made, size=(int(9 * PX), int(h * PX)), eye=(0, -dist, h * 0.5), look=(0, 0, h * 0.5), fov=fov,
              samples=16, sun=(62, 0, 18), ground=False, tex=tex)
    for d in made:
        bpy.data.objects.remove(d)
    print("wrote", path)


column("low", ["g_shop_red", "g_door", "g_shop_navy"], ["f_balcony", "f_balcony"])
column("tall", ["g_shop_green", "g_door", "g_shutter"], ["f_balcony", "f_window", "f_window", "f_balcony"])

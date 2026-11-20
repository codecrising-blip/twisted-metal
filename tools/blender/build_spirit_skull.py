"""Mr. Grimm's special, Head-On style (round 23, owner's video `docs/reference/videos/mr grimm video.mp4`): not a
bone skull but a SPIRIT FACE. In Head-On three big see-through skull faces in pinkish red burst out round the bike
(the rider flashes red, the ground glows pink), rush ahead together and burst on the target in a fireball with gold
sparks. Those faces are flat pictures that always look at the viewer, so this renders our own sculpted skull
(assets/models/skull.glb, from build_skull.py) straight from the front into a picture:
- lit by its own ambient occlusion: the dome, cheekbones and teeth glow pink-white, the sockets, the nose hole and
  the mouth sink to a deep, see-through blood red (a spirit has no inside);
- a soft red aura round it (blurred alpha), so it reads as glowing light, not paint.
    /tmp/bpy3.13/bin/python tools/blender/build_spirit_skull.py
Writes assets/fx/spirit_skull.png (512 x 512, RGBA, straight alpha)."""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "fx", "spirit_skull.png")
SIZE = 512

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "assets", "models", "skull.glb"))
skull = [o for o in bpy.context.scene.objects if o.type == "MESH"]
# Centre it and find its size.
pts = [o.matrix_world @ Vector(c) for o in skull for c in o.bound_box]
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
mid = (lo + hi) * 0.5
span = max(hi.x - lo.x, hi.z - lo.z)
print("skull bounds", lo, hi)

# The baked bone texture: its dark socket walls, nose hole and cracks darken the spirit too.
bone_img = None
for o in skull:
    for m in o.data.materials:
        if m and m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image and "albedo" in n.image.name.lower():
                    bone_img = n.image
if bone_img is None:  # the glb keeps its baked set beside it (ModelLib loads it): skull_albedo.webp
    bone_img = bpy.data.images.load(os.path.join(ROOT, "assets", "models", "skull_albedo.webp"))
    bone_img.colorspace_settings.name = "sRGB"
print("bone texture", bone_img.name if bone_img else None)

# One material for every part: emission from AO and facing, see-through where it is dark.
mat = bpy.data.materials.new("spirit")
mat.use_nodes = True
nt = mat.node_tree
for n in list(nt.nodes):
    nt.nodes.remove(n)
out = nt.nodes.new("ShaderNodeOutputMaterial")
ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
ao.samples = 32
ao.inputs["Distance"].default_value = 0.6
lw = nt.nodes.new("ShaderNodeLayerWeight")
lw.inputs["Blend"].default_value = 0.35
# light = ao^1.6 * (1 - 0.45 * facing-edge): bright where open and facing us
pw = nt.nodes.new("ShaderNodeMath"); pw.operation = "POWER"; pw.inputs[1].default_value = 3.2
nt.links.new(ao.outputs["AO"], pw.inputs[0])
if bone_img is not None:  # x smoothstep(bone brightness): the sockets' dark walls go dark
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bone_img
    bw = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(tex.outputs["Color"], bw.inputs[0])
    st = nt.nodes.new("ShaderNodeMapRange")
    st.interpolation_type = "SMOOTHSTEP"
    st.inputs["From Min"].default_value = 0.03
    st.inputs["From Max"].default_value = 0.3
    nt.links.new(bw.outputs[0], st.inputs["Value"])
    pw2 = nt.nodes.new("ShaderNodeMath"); pw2.operation = "MULTIPLY"
    nt.links.new(pw.outputs[0], pw2.inputs[0])
    nt.links.new(st.outputs["Result"], pw2.inputs[1])
    pw = pw2
edge = nt.nodes.new("ShaderNodeMath"); edge.operation = "MULTIPLY_ADD"
edge.inputs[1].default_value = -0.45; edge.inputs[2].default_value = 1.0
nt.links.new(lw.outputs["Facing"], edge.inputs[0])
light = nt.nodes.new("ShaderNodeMath"); light.operation = "MULTIPLY"; light.use_clamp = True
nt.links.new(pw.outputs[0], light.inputs[0])
nt.links.new(edge.outputs[0], light.inputs[1])
ramp = nt.nodes.new("ShaderNodeValToRGB")
cr = ramp.color_ramp
cr.elements[0].position = 0.0
cr.elements[0].color = (0.08, 0.0, 0.01, 1.0)   # near black blood red in the hollows
cr.elements[1].position = 1.0
cr.elements[1].color = (1.0, 0.58, 0.54, 1.0)   # hot pink only on the very top of the dome
e = cr.elements.new(0.3); e.color = (0.62, 0.02, 0.05, 1.0)
e = cr.elements.new(0.62); e.color = (0.92, 0.1, 0.12, 1.0)
e = cr.elements.new(0.86); e.color = (1.0, 0.3, 0.3, 1.0)
nt.links.new(light.outputs[0], ramp.inputs["Fac"])
emit = nt.nodes.new("ShaderNodeEmission")
emit.inputs["Strength"].default_value = 1.0
nt.links.new(ramp.outputs["Color"], emit.inputs["Color"])
# alpha: hollows half see-through, the face itself mostly solid light
amap = nt.nodes.new("ShaderNodeMapRange")
amap.inputs["From Min"].default_value = 0.0
amap.inputs["From Max"].default_value = 0.75
amap.inputs["To Min"].default_value = 0.12
amap.inputs["To Max"].default_value = 0.8
nt.links.new(light.outputs[0], amap.inputs["Value"])
transp = nt.nodes.new("ShaderNodeBsdfTransparent")
mix = nt.nodes.new("ShaderNodeMixShader")
nt.links.new(amap.outputs["Result"], mix.inputs["Fac"])
nt.links.new(transp.outputs[0], mix.inputs[1])
nt.links.new(emit.outputs[0], mix.inputs[2])
nt.links.new(mix.outputs[0], out.inputs["Surface"])
for o in skull:
    o.data.materials.clear()
    o.data.materials.append(mat)

# Front camera (the face looks along +Y in Blender space), orthographic, a little from below like the game camera.
cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = span * 1.22
cam = bpy.data.objects.new("cam", cam_data)
bpy.context.scene.collection.objects.link(cam)
cam.location = mid + Vector((0.0, 6.0, 0.35))
d = (mid - cam.location).normalized()
cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
sc = bpy.context.scene
sc.camera = cam
sc.render.engine = "CYCLES"
sc.cycles.samples = 48
sc.cycles.device = "CPU"
sc.render.film_transparent = True
sc.render.resolution_x = SIZE
sc.render.resolution_y = SIZE
sc.view_settings.view_transform = "Standard"
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
tmp = OUT.replace(".png", "_raw.png")
os.makedirs(os.path.dirname(OUT), exist_ok=True)
sc.render.filepath = tmp
bpy.ops.render.render(write_still=True)

# The aura: the face's alpha, blurred wide, in red, laid under it.
from PIL import Image, ImageFilter
im = Image.open(tmp).convert("RGBA")
a = im.getchannel("A")
glow = a.filter(ImageFilter.GaussianBlur(SIZE * 0.035))
g = np.asarray(glow, dtype=np.float32) / 255.0 * 0.7
rgba = np.asarray(im, dtype=np.float32) / 255.0
fa = rgba[..., 3:4]
red = np.array([0.95, 0.1, 0.12], dtype=np.float32)
out_a = fa + g[..., None] * (1.0 - fa)
out_rgb = (rgba[..., :3] * fa + red * g[..., None] * (1.0 - fa)) / np.maximum(out_a, 1e-4)
res = np.concatenate([out_rgb, out_a], axis=-1)
Image.fromarray((np.clip(res, 0, 1) * 255).astype(np.uint8), "RGBA").save(OUT)
os.remove(tmp)
print("wrote", OUT)

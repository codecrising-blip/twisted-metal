"""Burning drivers (round 17, owner): what climbs out of a destroyed car. Two plain dummies, a man and
a woman (on fire, every man looks the same and every woman looks the same, so no faces or clothes),
each a low-poly body skinned to a small skeleton, with the clips the game blends between:

    run_burn  loop: a panicked run, one hand beating at the fire on the head, the other at the chest
    kneel     loop: dropped to the knees, slumped, swaying (a moving hold)
    crawl     loop: on hands and knees, dragging forward
    prone     loop: face down, dead (a faint last twitch)
    limp      loop: a loose straight body for the thrown / run-over corpse (physics turns it)

The game (BurningDriver) crossfades: run -> kneel -> crawl -> prone, or straight to prone when shot.
The charred look and the embers are a Godot shader on the "body" material, not baked here.

Run:  /tmp/bpy3.13/bin/python tools/blender/build_drivers.py [--shape out.png]
Out:  assets/models/driver_m.glb, driver_f.glb
Blender space: +X = the body's left, +Y forward (the way it faces), +Z up, metres, feet on z = 0.
"""

import math
import os
import sys

import bpy  # first: it puts bmesh and mathutils on the path
import bmesh
from mathutils import Euler, Matrix, Quaternion, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "models")
FPS = 30


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.fps = FPS
    s.unit_settings.system = "METRIC"
    return s


# ------------------------------------------------------------------ skeleton

def joints(female):
    """Bone (head, tail, parent) in metres for a ~1.80 m man / ~1.69 m woman."""
    k = 0.94 if female else 1.0
    sh = 0.175 if female else 0.205  # shoulder half width
    hp = 0.1 if female else 0.092  # hip joint half width
    j = {
        "hips": ((0, 0, 0.95), (0, 0, 1.08), None),
        "spine": ((0, 0, 1.08), (0, 0, 1.28), "hips"),
        "chest": ((0, 0, 1.28), (0, 0, 1.47), "spine"),
        "neck": ((0, 0, 1.47), (0, 0, 1.57), "chest"),
        "head": ((0, 0, 1.57), (0, 0.01, 1.8), "neck"),
    }
    for side, sx in (("L", 1.0), ("R", -1.0)):
        j["upper_arm." + side] = ((sx * sh, 0, 1.43), (sx * (sh + 0.05), 0, 1.15), "chest")
        j["forearm." + side] = ((sx * (sh + 0.05), 0, 1.15), (sx * (sh + 0.075), 0.02, 0.9), "upper_arm." + side)
        j["hand." + side] = ((sx * (sh + 0.075), 0.02, 0.9), (sx * (sh + 0.085), 0.03, 0.79), "forearm." + side)
        j["thigh." + side] = ((sx * hp, 0, 0.93), (sx * (hp + 0.008), 0.01, 0.5), "hips")
        j["shin." + side] = ((sx * (hp + 0.008), 0.01, 0.5), (sx * (hp + 0.008), -0.01, 0.09), "thigh." + side)
        j["foot." + side] = ((sx * (hp + 0.008), -0.01, 0.09), (sx * (hp + 0.012), 0.17, 0.03), "shin." + side)
    return {n: (Vector(h) * k, Vector(t) * k, p) for n, (h, t, p) in j.items()}


def make_armature(J):
    arm = bpy.data.armatures.new("rig")
    ob = bpy.data.objects.new("rig", arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (h, t, p) in J.items():
        eb = arm.edit_bones.new(name)
        eb.head, eb.tail = h, t
        # Every bone's local X is the body's side axis, so a turn about X swings the limb in the
        # body's own plane (forward = +angle for limbs hanging down, back for the spine).
        d = (t - h).normalized()
        z = Vector((1, 0, 0)).cross(d)
        eb.align_roll(z.normalized() if z.length > 1e-4 else Vector((0, 0, 1)))
    for name, (h, t, p) in J.items():
        if p:
            eb = arm.edit_bones[name]
            eb.parent = arm.edit_bones[p]
            eb.use_connect = (arm.edit_bones[p].tail - eb.head).length < 1e-4 and name.split(".")[0] not in ("upper_arm", "thigh")
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in ob.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return ob


# ------------------------------------------------------------------ body

class Body:
    """One mesh built from simple parts; every part is rigidly skinned to one bone. The weights live in
    a bmesh deform layer (vertex indices shift while bmesh ops run, so they can't be listed)."""

    def __init__(self):
        self.bm = bmesh.new()
        self.deform = self.bm.verts.layers.deform.verify()
        self.groups = []  # bone names in vertex-group order

    def _take(self, bone, verts):
        if bone not in self.groups:
            self.groups.append(bone)
        gi = self.groups.index(bone)
        for v in verts:
            v[self.deform][gi] = 1.0

    def seg(self, bone, a, b, r1, r2, depth=1.0, n=10):
        """A tapered limb from a (radius r1) to b (r2); `depth` squashes it front to back."""
        a, b = Vector(a), Vector(b)
        d = b - a
        ret = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=n, radius1=r1, radius2=r2, depth=d.length)
        z = d.normalized()
        x = Vector((1, 0, 0)) - z * z.x
        x = x.normalized() if x.length > 1e-4 else Vector((0, 1, 0))
        y = z.cross(x)
        for v in ret["verts"]:
            lx, ly, lz = v.co.x, v.co.y * depth, v.co.z
            v.co = (a + b) * 0.5 + x * lx + y * ly + z * lz
        self._take(bone, ret["verts"])

    def ell(self, bone, c, r, n=10):
        """An ellipsoid at c with radii r = (x, y, z)."""
        ret = bmesh.ops.create_uvsphere(self.bm, u_segments=n, v_segments=max(6, n * 2 // 3), radius=1.0)
        for v in ret["verts"]:
            v.co = Vector((v.co.x * r[0] + c[0], v.co.y * r[1] + c[1], v.co.z * r[2] + c[2]))
        self._take(bone, ret["verts"])

    def finish(self, rig, mat):
        me = bpy.data.meshes.new("body")
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        for p in me.polygons:
            p.use_smooth = True
        me.materials.append(mat)
        ob = bpy.data.objects.new("body", me)
        bpy.context.scene.collection.objects.link(ob)
        for bone in self.groups:
            ob.vertex_groups.new(name=bone)
        ob.parent = rig
        mod = ob.modifiers.new("rig", "ARMATURE")
        mod.object = rig
        return ob


def build_body(J, female, rig):
    b = Body()
    k = 0.94 if female else 1.0
    P = lambda *v: Vector(v) * k  # noqa: E731
    hipw = 0.17 if female else 0.155
    # torso
    b.ell("hips", P(0, -0.005, 0.99), (hipw * k, 0.115 * k, 0.12 * k), 12)
    b.seg("spine", P(0, 0, 1.04), P(0, 0, 1.3), (0.125 if female else 0.135) * k, (0.13 if female else 0.15) * k, 0.72, 12)
    b.ell("chest", P(0, 0.0, 1.37), ((0.165 if female else 0.19) * k, 0.115 * k, 0.15 * k), 12)
    if female:
        for sx in (1, -1):
            b.ell("chest", P(sx * 0.07, 0.085, 1.33), (0.062 * k, 0.05 * k, 0.055 * k), 8)
    b.seg("neck", P(0, 0, 1.45), P(0, 0.005, 1.6), 0.052 * k, 0.047 * k, 1.0, 8)
    b.ell("head", P(0, 0.012, 1.685), (0.088 * k, 0.103 * k, 0.118 * k), 12)
    if female:
        b.ell("head", P(0, -0.085, 1.72), (0.05 * k, 0.045 * k, 0.05 * k), 8)  # what is left of tied-up hair
    # limbs (+ joint balls so the bends do not open gaps)
    for side in ("L", "R"):
        ua, fa, hd = J["upper_arm." + side], J["forearm." + side], J["hand." + side]
        th, sn, ft = J["thigh." + side], J["shin." + side], J["foot." + side]
        b.ell("chest", ua[0], (0.066 * k,) * 3, 8)
        b.seg("upper_arm." + side, ua[0], ua[1], 0.058 * k, 0.045 * k, 1.0, 8)
        b.ell("forearm." + side, fa[0], (0.045 * k,) * 3, 8)
        b.seg("forearm." + side, fa[0], fa[1], 0.044 * k, 0.034 * k, 1.0, 8)
        b.seg("hand." + side, hd[0], hd[1], 0.04 * k, 0.03 * k, 0.55, 6)
        b.ell("hips", th[0], (0.088 * k,) * 3, 8)
        b.seg("thigh." + side, th[0], th[1], (0.092 if female else 0.088) * k, 0.06 * k, 1.0, 10)
        b.ell("shin." + side, sn[0], (0.062 * k,) * 3, 8)
        b.seg("shin." + side, sn[0], sn[1], 0.06 * k, 0.042 * k, 1.0, 8)
        fh = ft[0]
        b.seg("foot." + side, fh + Vector((0, -0.04, -0.02)) * k, ft[1] + Vector((0, 0.02, 0)) * k, 0.045 * k, 0.04 * k, 0.75, 6)
    mat = bpy.data.materials.new("body")
    mat.diffuse_color = (0.05, 0.035, 0.03, 1.0)
    return b.finish(rig, mat)


# ------------------------------------------------------------------ clips

BONES = ["hips", "spine", "chest", "neck", "head"] + [p + s for p in ("upper_arm.", "forearm.", "hand.", "thigh.", "shin.", "foot.") for s in ("L", "R")]


def _q(rx=0.0, ry=0.0, rz=0.0):
    return Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ").to_quaternion()


def mirror(pose):
    """The same pose for the other side (left <-> right; side swings and twists flip)."""
    out = {}
    for name, v in pose.items():
        if name == "loc":
            out[name] = (-v[0], v[1], v[2])
            continue
        rx, ry, rz = (list(v) + [0, 0])[:3]
        if name.endswith(".L"):
            name = name[:-2] + ".R"
        elif name.endswith(".R"):
            name = name[:-2] + ".L"
        out[name] = (rx, -ry, -rz)
    return out


def key(rig, frame, pose):
    """Key every bone at `frame`: the given Euler turns (degrees, bone space), the rest at rest.
    pose["loc"] moves the hips (bone space: x side, y up, z back)."""
    for name in BONES:
        pb = rig.pose.bones[name]
        r = pose.get(name, (0, 0, 0))
        pb.rotation_quaternion = _q(*r)
        pb.keyframe_insert("rotation_quaternion", frame=frame)
    hips = rig.pose.bones["hips"]
    hips.location = Vector(pose.get("loc", (0, 0, 0)))
    hips.keyframe_insert("location", frame=frame)


def clip(rig, name, frames):
    """frames = [(frame, pose), ...]; the last key should repeat the first for loops."""
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = act
    for f, pose in frames:
        key(rig, f, pose)
    return act


def run_poses():
    lean = {"spine": (-12, 0, 0), "chest": (-6, 0, 0)}
    # a: right foot planted in front, left arm up beating at the burning head, right hand at the chest
    a = dict(lean, **{
        "loc": (0, -0.035, 0), "hips": (0, 8, 0), "chest": (-6, -10, 0), "head": (14, 18, 6),
        "thigh.R": (38, 0, 0), "shin.R": (-12, 0, 0), "foot.R": (8, 0, 0),
        "thigh.L": (-28, 0, 0), "shin.L": (-62, 0, 0), "foot.L": (-20, 0, 0),
        "upper_arm.L": (150, 0, -25), "forearm.L": (95, 0, 0), "hand.L": (20, 0, 0),
        "upper_arm.R": (55, 0, 25), "forearm.R": (115, 0, 0), "hand.R": (10, 0, 0),
    })
    # b: passing, the right foot under the body, the left knee coming through; arms swapping over
    b = dict(lean, **{
        "loc": (0, 0.03, 0), "hips": (0, 2, 0), "chest": (-8, -2, 0), "head": (6, -10, -8),
        "thigh.R": (-2, 0, 0), "shin.R": (-18, 0, 0),
        "thigh.L": (22, 0, 0), "shin.L": (-95, 0, 0), "foot.L": (-15, 0, 0),
        "upper_arm.L": (95, 0, -40), "forearm.L": (120, 0, 0),
        "upper_arm.R": (110, 0, 35), "forearm.R": (100, 0, 0),
    })
    return a, b


def build_clips(rig):
    a, b = run_poses()
    clip(rig, "run_burn", [(1, a), (6, b), (11, mirror(a)), (16, mirror(b)), (21, a)])
    kneel = {
        "loc": (0, -0.45, 0.04), "spine": (-24, 0, 0), "chest": (-16, 0, 0), "neck": (-10, 0, 0), "head": (-12, 0, 8),
        "thigh.L": (8, 0, -6), "shin.L": (-92, 0, 0), "foot.L": (-40, 0, 0),
        "thigh.R": (12, 0, 6), "shin.R": (-95, 0, 0), "foot.R": (-40, 0, 0),
        "upper_arm.L": (40, 0, -12), "forearm.L": (55, 0, 0),
        "upper_arm.R": (85, 0, 10), "forearm.R": (70, 0, 0),
    }
    kneel2 = dict(kneel, **{"spine": (-30, 4, 0), "head": (-18, -6, -6), "upper_arm.R": (75, 0, 14)})
    clip(rig, "kneel", [(1, kneel), (16, kneel2), (31, kneel)])
    # crawl: the body pitched forward almost flat on hands and knees, dragging along
    c0 = {
        "loc": (0, -0.43, 0.0), "hips": (-78, 0, 4), "spine": (-6, 0, 0), "chest": (-2, 0, 0), "neck": (20, 0, 0), "head": (28, 0, 0),
        "thigh.L": (92, 0, -4), "shin.L": (-92, 0, 0), "foot.L": (-30, 0, 0),
        "thigh.R": (68, 0, 4), "shin.R": (-80, 0, 0), "foot.R": (-30, 0, 0),
        "upper_arm.L": (62, 0, -6), "forearm.L": (10, 0, 0), "hand.L": (-40, 0, 0),
        "upper_arm.R": (98, 0, 6), "forearm.R": (18, 0, 0), "hand.R": (-50, 0, 0),
    }
    c1 = dict(c0, **{"hips": (-80, 0, 0), "loc": (0, -0.46, 0.0), "thigh.L": (80, 0, -4), "thigh.R": (80, 0, 4),
                     "upper_arm.L": (80, 0, -6), "upper_arm.R": (80, 0, 6), "head": (22, 0, 0)})
    clip(rig, "crawl", [(1, c0), (8, c1), (16, mirror(c0)), (23, mirror(c1)), (31, c0)])
    prone = {
        "loc": (0, -0.84, -0.05), "hips": (-90, 0, 0), "spine": (-2, 0, 0), "neck": (0, 0, 0), "head": (6, 70, 0),
        "thigh.L": (-4, 0, -10), "shin.L": (-28, 0, 0), "foot.L": (-50, 0, 0),
        "thigh.R": (2, 0, 6), "shin.R": (-6, 0, 0), "foot.R": (-60, 0, 0),
        "upper_arm.L": (165, 0, -25), "forearm.L": (25, 0, 0),
        "upper_arm.R": (15, 0, 30), "forearm.R": (35, 0, 0), "hand.R": (-30, 0, 0),
    }
    prone2 = dict(prone, **{"forearm.L": (32, 0, 0), "hand.R": (-20, 0, 0)})
    clip(rig, "prone", [(1, prone), (20, prone2), (40, prone)])
    limp = {
        "head": (10, 25, 10), "neck": (8, 0, 0), "spine": (4, 0, 0),
        "upper_arm.L": (10, 0, -38), "forearm.L": (25, 0, 0), "upper_arm.R": (-5, 0, 32), "forearm.R": (35, 0, 0),
        "thigh.L": (6, 0, -10), "shin.L": (-18, 0, 0), "thigh.R": (-4, 0, 8), "shin.R": (-8, 0, 0),
        "foot.L": (-30, 0, 0), "foot.R": (-35, 0, 0),
    }
    clip(rig, "limp", [(1, limp), (30, dict(limp, **{"head": (12, 22, 12)})), (60, limp)])
    rig.animation_data.action = bpy.data.actions["run_burn"]


# ------------------------------------------------------------------ export / preview

def export(name):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=False, export_yup=True, export_apply=False,
        export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True,
        export_skins=True, export_materials="EXPORT", export_cameras=False, export_lights=False,
    )
    return path


def shape_sheet(rig, path):
    """Quick look: every clip at a few frames, side and front-three-quarter views (Workbench)."""
    s = bpy.context.scene
    s.render.engine = "CYCLES"  # Workbench/EEVEE need a GPU; this container has none
    s.cycles.device = "CPU"
    s.cycles.samples = 6
    s.cycles.use_denoising = False
    s.render.resolution_x, s.render.resolution_y = 320, 320
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    s.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = Euler((math.radians(50), 0, math.radians(30)))
    s.collection.objects.link(sun)
    for m in bpy.data.materials:
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.55, 0.42, 0.35, 1.0)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    s.collection.objects.link(cam)
    s.camera = cam
    floor = bpy.data.meshes.new("floor")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=3.0)
    bm.to_mesh(floor)
    s.collection.objects.link(bpy.data.objects.new("floor", floor))
    shots = []
    tiles = []
    for act, frames in (("run_burn", (1, 6, 11, 16)), ("kneel", (1, 16)), ("crawl", (1, 8, 16)), ("prone", (1,)), ("limp", (1,))):
        rig.animation_data.action = bpy.data.actions[act]
        for f in frames:
            for view in ("side", "34"):
                s.frame_set(f)
                if view == "side":
                    cam.location = (3.6, 0.0, 1.0)
                else:
                    cam.location = (2.4, 2.6, 1.6)
                d = Vector((0, 0, 0.75)) - cam.location
                cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
                out = path + "_%s_%d_%s.png" % (act, f, view)
                s.render.filepath = out
                bpy.ops.render.render(write_still=True)
                tiles.append(out)
    from PIL import Image
    ims = [Image.open(t) for t in tiles]
    cols = 8
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 320, rows * 320), (40, 40, 40))
    for i, im in enumerate(ims):
        sheet.paste(im, ((i % cols) * 320, (i // cols) * 320))
    sheet.save(path)
    for t in tiles:
        os.remove(t)


def main():
    shape = sys.argv[sys.argv.index("--shape") + 1] if "--shape" in sys.argv else None
    for female, name in ((False, "driver_m"), (True, "driver_f")):
        reset()
        J = joints(female)
        rig = make_armature(J)
        body = build_body(J, female, rig)
        build_clips(rig)
        tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
        if shape:
            shape_sheet(rig, shape.replace(".png", "_%s.png" % name))
            print(name, "sheet", tris, "triangles")
        else:
            print(name, "->", export(name), tris, "triangles")


if __name__ == "__main__":
    main()

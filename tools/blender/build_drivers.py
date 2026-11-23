"""Burning drivers (round 17, owner): what climbs out of a destroyed car. Two plain dummies, a man and
a woman (on fire, every man looks the same and every woman looks the same, so no faces or clothes),
each a low-poly body skinned to a small skeleton, with the clips the game blends between:

    run_burn  loop: a panicked run, one hand beating at the fire on the head, the other at the chest
    kneel     loop: dropped to the knees, slumped, swaying (a moving hold)
    crawl     loop: on hands and knees, dragging forward
    prone     loop: face down, dead (a faint last twitch)
    limp      loop: a loose straight body for the thrown / run-over corpse (physics turns it)
    sprint    loop: a hard, clean sprint, leaning in, arms pumping (round 29: Brimstone's sinner, not burning)

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
    """Bone (head, tail, parent) in metres. Owner, round 17: men taller with broad shoulders and a long
    reach (chest about as wide as the hips); women shorter, narrow shoulders (a small reach)."""
    h = 1.68 if female else 1.82  # standing height
    k = h / 1.8
    sh = 0.158 if female else 0.215  # shoulder joint half width
    hp = 0.09 if female else 0.092  # hip joint half width
    ua = (0.27 if female else 0.305) * k  # upper arm, forearm, hand lengths
    fa = (0.245 if female else 0.27) * k
    hd = 0.1 * k
    z = lambda v: v * k  # noqa: E731
    j = {
        "hips": ((0, 0, z(0.95)), (0, 0, z(1.08)), None),
        "spine": ((0, 0, z(1.08)), (0, 0, z(1.28)), "hips"),
        "chest": ((0, 0, z(1.28)), (0, 0, z(1.47)), "spine"),
        "neck": ((0, 0, z(1.47)), (0, 0, z(1.57)), "chest"),
        "head": ((0, 0, z(1.57)), (0, 0.01, z(1.8)), "neck"),
    }
    for side, sx in (("L", 1.0), ("R", -1.0)):
        s0 = Vector((sx * sh, 0, z(1.43)))
        e = s0 + Vector((sx * 0.045, 0, -ua))
        w = e + Vector((sx * 0.025, 0.02, -fa))
        j["upper_arm." + side] = (tuple(s0), tuple(e), "chest")
        j["forearm." + side] = (tuple(e), tuple(w), "upper_arm." + side)
        j["hand." + side] = (tuple(w), tuple(w + Vector((sx * 0.01, 0.01, -hd))), "forearm." + side)
        j["thigh." + side] = ((sx * hp, 0, z(0.93)), (sx * (hp + 0.008), 0.01, z(0.5)), "hips")
        j["shin." + side] = ((sx * (hp + 0.008), 0.01, z(0.5)), (sx * (hp + 0.008), -0.01, z(0.09)), "thigh." + side)
        j["foot." + side] = ((sx * (hp + 0.008), -0.01, z(0.09)), (sx * (hp + 0.012), 0.17 * k, z(0.03)), "shin." + side)
    return {n: (Vector(hh), Vector(t), p) for n, (hh, t, p) in j.items()}


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
    """Plain bodies told apart by build, not by hair or clothes (owner, round 17): the woman (Jamie
    Roberts's build: skinny) has narrow shoulders, a thin waist, slightly wider hips and backside and
    a small chest; the man is broad in the shoulders with a chest about as wide as his hips."""
    b = Body()
    k = (1.68 if female else 1.82) / 1.8
    z = lambda v: v * k  # noqa: E731
    P = lambda x, y, zz: Vector((x, y, z(zz)))  # noqa: E731
    if female:
        b.ell("hips", P(0, -0.012, 0.975), (0.165, 0.112, 0.118), 12)
        for sx in (1, -1): # backside, merging into the hips (not two balls)
            b.ell("hips", P(sx * 0.055, -0.05, 0.925), (0.088, 0.072, 0.092), 10)
        b.seg("spine", P(0, 0, 1.05), P(0, 0, 1.3), 0.112, 0.118, 0.7, 12) # thin waist
        b.ell("chest", P(0, 0.0, 1.37), (0.148, 0.102, 0.14), 12)
        for sx in (1, -1): # small chest (B)
            b.ell("chest", P(sx * 0.062, 0.08, 1.335), (0.056, 0.048, 0.05), 8)
        b.seg("neck", P(0, 0, 1.45), P(0, 0.005, 1.6), 0.045, 0.041, 1.0, 8)
        b.ell("head", P(0, 0.012, 1.685), (0.084, 0.098, 0.112), 12)
        arm_r, thigh_r, shin_r, ball = (0.05, 0.039, 0.039, 0.03), (0.093, 0.058), (0.056, 0.04), 0.056
    else:
        b.ell("hips", P(0, -0.005, 0.98), (0.158, 0.112, 0.12), 12)
        b.seg("spine", P(0, 0, 1.04), P(0, 0, 1.3), 0.142, 0.158, 0.74, 12)
        b.ell("chest", P(0, 0.005, 1.37), (0.19, 0.125, 0.158), 12) # broad, about as wide as the hips
        b.seg("neck", P(0, 0, 1.45), P(0, 0.005, 1.6), 0.058, 0.052, 1.0, 8)
        b.ell("head", P(0, 0.012, 1.69), (0.09, 0.104, 0.12), 12)
        arm_r, thigh_r, shin_r, ball = (0.062, 0.049, 0.049, 0.037), (0.094, 0.064), (0.064, 0.045), 0.07
    for side in ("L", "R"):
        ua, fa, hd = J["upper_arm." + side], J["forearm." + side], J["hand." + side]
        th, sn, ft = J["thigh." + side], J["shin." + side], J["foot." + side]
        b.ell("chest", ua[0], (ball,) * 3, 8)
        b.seg("upper_arm." + side, ua[0], ua[1], arm_r[0], arm_r[1], 1.0, 8)
        b.ell("forearm." + side, fa[0], (arm_r[1] * 0.95,) * 3, 8)
        b.seg("forearm." + side, fa[0], fa[1], arm_r[2], arm_r[3], 1.0, 8)
        b.seg("hand." + side, hd[0], hd[1], arm_r[3] * 1.1, arm_r[3] * 0.8, 0.55, 6)
        b.ell("hips", th[0], (thigh_r[0] * 0.98,) * 3, 8)
        b.seg("thigh." + side, th[0], th[1], thigh_r[0], thigh_r[1], 1.0, 10)
        b.ell("shin." + side, sn[0], (thigh_r[1],) * 3, 8)
        b.seg("shin." + side, sn[0], sn[1], shin_r[0], shin_r[1], 1.0, 8)
        b.seg("foot." + side, ft[0] + Vector((0, -0.04, -0.02)), ft[1] + Vector((0, 0.02, 0)), 0.045 * k, 0.04 * k, 0.75, 6)
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
    """The burning run (owner, round 17, after Twisted Metal: Black): no clean jog. Hunched over,
    stumbling on bent knees, the head thrown back and jerking, the arms flailing and beating at the
    flames, never the same twice in the two strides of the loop."""
    hunch = {"spine": (-20, 0, 0), "chest": (-10, 0, 0)}
    k1 = dict(hunch, **{ # right foot down, left arm thrashing over the head, right fist at the chest
        "loc": (0, -0.07, 0), "hips": (0, 10, 4), "spine": (-22, 0, -5), "chest": (-10, -16, 0), "neck": (8, 0, 0), "head": (22, 25, 8),
        "thigh.R": (30, 0, 0), "shin.R": (-14, 0, 0), "foot.R": (6, 0, 0),
        "thigh.L": (-24, 0, 0), "shin.L": (-58, 0, 0), "foot.L": (-25, 0, 0),
        "upper_arm.L": (160, 0, -38), "forearm.L": (40, 0, 0), "hand.L": (25, 0, 0),
        "upper_arm.R": (70, 0, 18), "forearm.R": (112, 0, 0)})
    k2 = dict(hunch, **{ # passing: the arm comes down sweeping, the other beats at the face
        "loc": (0, 0.0, 0), "hips": (0, 4, -2), "chest": (-14, -4, 4), "head": (8, -8, -6),
        "thigh.R": (-6, 0, 0), "shin.R": (-24, 0, 0),
        "thigh.L": (22, 0, 0), "shin.L": (-84, 0, 0), "foot.L": (-20, 0, 0),
        "upper_arm.L": (95, 0, -62), "forearm.L": (25, 0, 0),
        "upper_arm.R": (132, 0, 14), "forearm.R": (122, 0, 0), "hand.R": (30, 0, 0)})
    k3 = dict(hunch, **{ # left foot down: arms swap, one flung out wide, one waving high
        "loc": (0, -0.08, 0), "hips": (0, -12, -5), "spine": (-24, 0, 6), "chest": (-8, 18, 0), "neck": (10, 0, 0), "head": (14, -30, -12),
        "thigh.L": (28, 0, 0), "shin.L": (-16, 0, 0), "foot.L": (6, 0, 0),
        "thigh.R": (-22, 0, 0), "shin.R": (-60, 0, 0), "foot.R": (-25, 0, 0),
        "upper_arm.L": (42, 0, -72), "forearm.L": (38, 0, 0),
        "upper_arm.R": (172, 0, 34), "forearm.R": (28, 0, 0), "hand.R": (-20, 0, 0)})
    k4 = dict(hunch, **{ # a stumble: a short, deep step, both hands clawing at the head
        "loc": (0, -0.12, 0.03), "hips": (0, 2, 6), "spine": (-30, 0, -8), "chest": (-14, 6, 0), "neck": (-6, 0, 0), "head": (-14, 10, 10),
        "thigh.L": (-4, 0, 0), "shin.L": (-34, 0, 0),
        "thigh.R": (38, 0, 0), "shin.R": (-102, 0, 0), "foot.R": (-15, 0, 0),
        "upper_arm.L": (150, 0, -10), "forearm.L": (112, 0, 0),
        "upper_arm.R": (146, 0, 12), "forearm.R": (106, 0, 0)})
    k5 = dict(hunch, **{ # right foot down again, off balance, the head thrown back screaming
        "loc": (0, -0.06, 0), "hips": (0, 8, 2), "spine": (-18, 0, -3), "chest": (-6, -12, 0), "neck": (14, 0, 0), "head": (32, 12, 4),
        "thigh.R": (34, 0, 0), "shin.R": (-12, 0, 0), "foot.R": (8, 0, 0),
        "thigh.L": (-26, 0, 0), "shin.L": (-62, 0, 0), "foot.L": (-25, 0, 0),
        "upper_arm.L": (22, 0, -48), "forearm.L": (50, 0, 0), "hand.L": (-25, 0, 0),
        "upper_arm.R": (82, 0, -18), "forearm.R": (96, 0, 0)})
    k6 = dict(hunch, **{ # passing: one arm across the body, the other swinging back
        "loc": (0, -0.01, 0), "hips": (0, 0, -3), "chest": (-12, 10, -4), "head": (6, 20, 0),
        "thigh.R": (-4, 0, 0), "shin.R": (-22, 0, 0),
        "thigh.L": (24, 0, 0), "shin.L": (-88, 0, 0), "foot.L": (-18, 0, 0),
        "upper_arm.L": (165, 0, -22), "forearm.L": (60, 0, 0),
        "upper_arm.R": (12, 0, 40), "forearm.R": (35, 0, 0)})
    k7 = dict(hunch, **{ # left foot down, beating at the chest with both fists
        "loc": (0, -0.07, 0), "hips": (0, -8, -3), "spine": (-20, 0, 4), "chest": (-10, 12, 0), "neck": (6, 0, 0), "head": (18, -14, -8),
        "thigh.L": (30, 0, 0), "shin.L": (-12, 0, 0), "foot.L": (6, 0, 0),
        "thigh.R": (-24, 0, 0), "shin.R": (-58, 0, 0), "foot.R": (-24, 0, 0),
        "upper_arm.L": (75, 0, -12), "forearm.L": (118, 0, 0),
        "upper_arm.R": (150, 0, 30), "forearm.R": (60, 0, 0)})
    k8 = dict(hunch, **{ # passing, the arms flung up and out
        "loc": (0, 0.0, 0), "hips": (0, -2, 2), "chest": (-12, -6, 0), "head": (24, -6, 6),
        "thigh.L": (-6, 0, 0), "shin.L": (-24, 0, 0),
        "thigh.R": (22, 0, 0), "shin.R": (-86, 0, 0), "foot.R": (-20, 0, 0),
        "upper_arm.L": (128, 0, -55), "forearm.L": (30, 0, 0),
        "upper_arm.R": (118, 0, 50), "forearm.R": (45, 0, 0)})
    return [k1, k2, k3, k4, k5, k6, k7, k8]


def sprint_poses():
    """Round 29 (owner: the sinner's run was chaos, "arms 12 times a second"): a plain, driven sprint. Leaning
    in, knees high, the arms bent and pumping against the legs; one stride each way."""
    lean = {"spine": (-14, 0, 0), "chest": (-6, 0, 0), "neck": (4, 0, 0), "head": (10, 0, 0)}
    k1 = dict(lean, **{ # right foot reaching down, left arm forward
        "loc": (0, -0.04, 0), "hips": (0, 6, 0), "chest": (-6, -6, 0),
        "thigh.R": (34, 0, 0), "shin.R": (-10, 0, 0), "foot.R": (4, 0, 0),
        "thigh.L": (-26, 0, 0), "shin.L": (-72, 0, 0), "foot.L": (-22, 0, 0),
        "upper_arm.L": (48, 0, -8), "forearm.L": (95, 0, 0),
        "upper_arm.R": (-38, 0, 8), "forearm.R": (80, 0, 0)})
    k2 = dict(lean, **{ # passing: the left knee drives up, the arms come through
        "loc": (0, 0.03, 0), "hips": (0, 0, 0),
        "thigh.R": (2, 0, 0), "shin.R": (-16, 0, 0),
        "thigh.L": (42, 0, 0), "shin.L": (-104, 0, 0), "foot.L": (-14, 0, 0),
        "upper_arm.L": (12, 0, -8), "forearm.L": (92, 0, 0),
        "upper_arm.R": (6, 0, 8), "forearm.R": (92, 0, 0)})
    return [k1, k2, mirror(k1), mirror(k2)]


def build_clips(rig):
    ks = run_poses()
    clip(rig, "run_burn", [(1 + i * 5, k) for i, k in enumerate(ks)] + [(41, ks[0])])
    sp = sprint_poses()
    clip(rig, "sprint", [(1 + i * 6, k) for i, k in enumerate(sp)] + [(25, sp[0])])
    # On the knees, rocking in agony, clawing at the head.
    kneel = {
        "loc": (0, -0.47, 0.04), "spine": (-30, 0, 0), "chest": (-18, 0, 0), "neck": (-8, 0, 0), "head": (24, 0, 6),
        "thigh.L": (6, 0, -6), "shin.L": (-94, 0, 0), "foot.L": (-40, 0, 0),
        "thigh.R": (10, 0, 6), "shin.R": (-96, 0, 0), "foot.R": (-40, 0, 0),
        "upper_arm.L": (150, 0, -12), "forearm.L": (115, 0, 0),
        "upper_arm.R": (60, 0, 20), "forearm.R": (100, 0, 0)}
    kneel2 = dict(kneel, **{"spine": (-42, 6, 0), "chest": (-22, 0, 0), "head": (-20, -10, -8),
                            "upper_arm.L": (95, 0, -30), "forearm.L": (90, 0, 0), "upper_arm.R": (150, 0, 15), "forearm.R": (118, 0, 0)})
    clip(rig, "kneel", [(1, kneel), (12, kneel2), (24, kneel), (36, kneel2), (45, kneel)])
    # A last desperate crawl: low, one arm reaching and dragging, the legs barely helping.
    c0 = {
        "loc": (0, -0.5, 0.0), "hips": (-80, 0, 5), "spine": (-8, 0, 0), "chest": (-6, 0, 0), "neck": (14, 0, 0), "head": (14, 0, 6),
        "thigh.L": (86, 0, -6), "shin.L": (-98, 0, 0), "foot.L": (-30, 0, 0),
        "thigh.R": (62, 0, 6), "shin.R": (-84, 0, 0), "foot.R": (-30, 0, 0),
        "upper_arm.L": (128, 0, -8), "forearm.L": (8, 0, 0), "hand.L": (-30, 0, 0),
        "upper_arm.R": (64, 0, 10), "forearm.R": (30, 0, 0), "hand.R": (-50, 0, 0)}
    c1 = dict(c0, **{"loc": (0, -0.56, -0.05), "hips": (-84, 0, 0), "head": (4, 0, 0),
                     "thigh.L": (76, 0, -6), "thigh.R": (70, 0, 6),
                     "upper_arm.L": (96, 0, -8), "forearm.L": (40, 0, 0), "upper_arm.R": (88, 0, 10)})
    clip(rig, "crawl", [(1, c0), (12, c1), (24, mirror(c0)), (36, mirror(c1)), (47, c0)])
    # Dead: crumpled on its side, curled up as burnt bodies do: knees drawn up, fists to the face.
    curl = {
        "loc": (0.0, -0.8, 0.12), "hips": (-20, 0, 82), "spine": (-24, 0, 0), "chest": (-18, 0, 0), "neck": (-14, 0, 0), "head": (-20, 0, 10),
        "thigh.L": (78, 0, 0), "shin.L": (-112, 0, 0), "foot.L": (-30, 0, 0),
        "thigh.R": (62, 0, 8), "shin.R": (-98, 0, 0), "foot.R": (-35, 0, 0),
        "upper_arm.L": (70, 0, -10), "forearm.L": (125, 0, 0), "hand.L": (-40, 0, 0),
        "upper_arm.R": (95, 0, 14), "forearm.R": (118, 0, 0), "hand.R": (-40, 0, 0)}
    clip(rig, "prone", [(1, curl), (30, dict(curl, **{"forearm.L": (128, 0, 0)})), (60, curl)])
    # Thrown: stiff and burnt, bent the same way (the physics turns the body).
    limp = {
        "head": (-12, 20, 8), "neck": (-8, 0, 0), "spine": (-12, 0, 0),
        "upper_arm.L": (55, 0, -25), "forearm.L": (110, 0, 0), "upper_arm.R": (75, 0, 25), "forearm.R": (100, 0, 0),
        "thigh.L": (45, 0, -10), "shin.L": (-80, 0, 0), "thigh.R": (25, 0, 8), "shin.R": (-60, 0, 0),
        "foot.L": (-30, 0, 0), "foot.R": (-35, 0, 0)}
    clip(rig, "limp", [(1, limp), (30, dict(limp, **{"head": (-14, 22, 10)})), (60, limp)])
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
    for act, frames in (("run_burn", (1, 6, 11, 16, 21, 26, 31, 36)), ("kneel", (1, 12)), ("crawl", (1, 12, 24)), ("prone", (1,)), ("limp", (1,))):
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

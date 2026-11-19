"""Mr. Grimm's rider (round 20, owner: "not a Lego driver"): built like a sculpt, not from parts. The body in
Death's coat is ONE surface of metaballs melted together (chest, belly, hips, shoulders, the arms in their bell
sleeves, the legs), so shoulders flow into arms and the chest into the hips; gloves and boots are their own
sculpts. The coat's skirt and tails are cloth: thick curved panels with soft folds and a ragged hem; the hood
lies folded round the neck (a draped cowl, not a lump); a high collar; TM2's round helmet with a wrap-round
visor; the scythe strapped across his back. Pose: TM2's (owner's HD views): sitting up, leaning back a little,
arms straight out to the high grips, knees up by the fairing, feet forward on the pegs.

    import grimm_rider; parts += grimm_rider.build(BX, mats)
"""
import math

import bpy  # first
import bmesh
from mathutils import Matrix, Vector

import tmlib as T

V = Vector
F = 0.6  # a metaball's surface sits at about this share of its radius (dense chains run a little fatter)


class Sculpt:
    """One metaball family = one melted surface."""

    def __init__(self, name, res=0.018):
        self.mb = bpy.data.metaballs.new(name)
        self.mb.resolution = res
        self.mb.render_resolution = res
        self.ob = bpy.data.objects.new(name, self.mb)
        bpy.context.scene.collection.objects.link(self.ob)

    def ball(self, c, r, size=None):
        e = self.mb.elements.new(type="ELLIPSOID" if size else "BALL")
        e.co = tuple(c)
        e.radius = r / F
        if size:
            e.size_x, e.size_y, e.size_z = size
        return e

    def chain(self, a, b, ra, rb, step=0.022):
        """A limb: balls along a -> b, radius ra -> rb (the surface radius, roughly)."""
        a, b = V(a), V(b)
        n = max(2, int((b - a).length / step))
        for i in range(n + 1):
            t = i / n
            self.ball(a.lerp(b, t), (ra + (rb - ra) * t) * 0.82)

    def mesh(self, mat, ratio=0.35):
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(self.ob.evaluated_get(dg))
        bpy.data.objects.remove(self.ob)
        bpy.data.metaballs.remove(self.mb)
        ob = bpy.data.objects.new(self.mb.name if False else "sculpt", me)
        T._link(ob)
        me.materials.append(mat)
        if ratio < 1.0:
            T.decimate(ob, ratio)
        ob.data.polygons.foreach_set("use_smooth", [True] * len(ob.data.polygons))
        return ob


def cloth(path, width, thick, mat, up, folds=3, fold_depth=0.018, taper=1.0, ragged=0.0, sub=5, seed=0, m=10):
    """A panel of heavy cloth along `path` (top to hem): `width` across, soft folds running down it, the hem
    ragged by `ragged` metres. Sections are dense so it shades smoothly."""
    pts = [V(p) for p in path]
    # resample the path densely
    dense = []
    for i in range(len(pts) - 1):
        for k in range(sub):
            dense.append(pts[i].lerp(pts[i + 1], k / sub))
    dense.append(pts[-1])
    n = len(dense)
    secs = []
    for i, p in enumerate(dense):
        t = (dense[min(i + 1, n - 1)] - dense[max(i - 1, 0)]).normalized()
        side = t.cross(up).normalized()
        nrm = side.cross(t).normalized()
        s = i / (n - 1)
        w = width * (1.0 + (taper - 1.0) * s) / 2
        front, back = [], []
        for j in range(m):
            u = j / (m - 1) * 2 - 1
            fold = math.sin((u * folds + 0.25) * math.pi) * fold_depth * (0.4 + 0.6 * s)
            q = p + side * u * w + nrm * fold
            if i == n - 1 and ragged > 0:  # the hem: uneven, torn
                q = q - t * ragged * (0.5 + 0.5 * math.sin(u * 9.0 + seed * 1.7)) * (0.6 + 0.4 * math.cos(u * 23.0 + seed))
            front.append(q + nrm * thick / 2)
            back.append(q - nrm * thick / 2)
        secs.append([tuple(v) for v in front] + [tuple(v) for v in reversed(back)])
    ob = T.loft(secs, mat=mat, angle=60.0)
    ob.data.polygons.foreach_set("use_smooth", [True] * len(ob.data.polygons))
    return ob


def build(BX, mats):
    """The rider on a bike whose centre line is x = BX. mats: coat, leather, helmet, visor, wood, blade."""
    coat, leather, helmet, visor, wood, blade, lining, metal = (mats[k] for k in ("coat", "leather", "helmet", "visor", "wood", "blade", "lining", "metal"))
    parts = []
    HIP = V((BX, -0.52, 1.17))
    CHEST = V((BX, -0.66, 1.46))
    NECK = V((BX, -0.79, 1.69))
    back_n = (V((0, -0.28, 0.96)).cross(V((1, 0, 0)))).normalized()   # torso leans back a little
    up_t = (NECK - HIP).normalized()
    back_n = V((0, -up_t.z, up_t.y))
    S = Sculpt("grimm_body", 0.026)
    # the trunk: pelvis, belly, chest, the back of the ribcage, the shoulder girdle
    S.ball(HIP, 0.2, (1.0, 0.75, 0.7))
    S.ball(HIP.lerp(CHEST, 0.5), 0.2, (1.0, 0.72, 0.85))
    S.ball(CHEST, 0.23, (1.0, 0.68, 0.9))
    S.ball(CHEST + back_n * 0.05 + up_t * 0.08, 0.2, (1.05, 0.6, 0.8))
    for sx in (1, -1):
        S.ball(CHEST + V((sx * 0.15, 0.0, 0.1)), 0.13)               # the chest's sides under the coat
        S.ball(NECK + V((sx * 0.13, 0.02, -0.07)), 0.09)              # trapezius, sloping to the shoulder
    SH = {}
    for sx in (1, -1):
        sh = NECK + V((sx * 0.24, 0.04, -0.12))
        SH[sx] = sh
        S.ball(sh, 0.115)                                            # deltoid, under the coat's shoulder
    S.chain(NECK - up_t * 0.04, NECK + up_t * 0.08, 0.075, 0.065)    # neck
    # arms: straight out to the high grips; the coat sleeve bells out at the wrist
    for sx in (1, -1):
        sh = SH[sx]
        el = V((BX + sx * 0.27, -0.42, 1.6))
        wr = V((BX + sx * 0.25, -0.1, 1.65))
        S.chain(sh, el, 0.092, 0.08)
        S.ball(el, 0.082)
        S.chain(el, wr, 0.08, 0.1)
        S.ball(wr - (wr - el).normalized() * 0.01, 0.105, (0.9, 0.7, 1.0))  # the sleeve's open bell
    # legs: thighs up to the knees by the fairing, shins down to the pegs
    for sx in (1, -1):
        th = HIP + V((sx * 0.11, 0.04, -0.04))
        kn = V((BX + sx * 0.2, -0.06, 1.25))
        an = V((BX + sx * 0.21, 0.12, 0.74))
        S.chain(th, kn, 0.12, 0.085)
        S.ball(kn, 0.085)
        S.chain(kn, an, 0.08, 0.06)
    body = S.mesh(coat, 0.12)
    parts.append(body)
    # gloves gripping the bars, boots on the pegs
    G = Sculpt("grimm_gloves", 0.016)
    for sx in (1, -1):
        g = V((BX + sx * 0.25, -0.03, 1.66))
        G.ball(g, 0.06, (1.0, 1.25, 0.85))                            # the fist round the grip
        G.chain(g + V((0, -0.06, 0.0)), g + V((0, -0.11, -0.005)), 0.055, 0.06)  # cuff into the sleeve
        G.ball(g + V((-sx * 0.04, 0.03, 0.03)), 0.028)                 # thumb over the bar
    parts.append(G.mesh(leather, 0.22))
    B = Sculpt("grimm_boots", 0.018)
    for sx in (1, -1):
        an = V((BX + sx * 0.21, 0.12, 0.74))
        B.chain(an + V((0, 0, 0.08)), an + V((0, 0.01, -0.06)), 0.065, 0.07)  # boot shaft
        B.ball(an + V((0, 0.08, -0.08)), 0.07, (0.85, 1.6, 0.7))       # the foot, forward on the peg
        B.ball(an + V((0, -0.03, -0.09)), 0.05)                         # heel
    parts.append(B.mesh(leather, 0.22))
    # the coat: a skirt from the waist, split at the front and the back: two panels down the sides over the
    # thighs, the back panel draped over the seat and down the tail, all with soft folds and a torn hem
    for sx in (1, -1):
        top = HIP + V((sx * 0.2, -0.02, 0.02))
        parts.append(cloth([top, top + V((sx * 0.06, 0.08, -0.22)), top + V((sx * 0.09, 0.1, -0.45)), top + V((sx * 0.1, 0.06, -0.62))],
                           0.34, 0.014, coat, V((sx, 0, 0)), folds=2, fold_depth=0.02, taper=1.35, ragged=0.07, seed=sx))
        parts.append(cloth([top + V((-sx * 0.012, 0.18, 0)), top + V((sx * 0.05, 0.27, -0.22)), top + V((sx * 0.08, 0.32, -0.45))],
                           0.03, 0.016, lining, V((sx, 0, 0)), folds=0, fold_depth=0.0, sub=3, m=3))
    w0 = HIP + back_n * 0.12 + V((0, 0, 0.0))
    parts.append(cloth([w0, w0 + V((0, -0.18, -0.06)), w0 + V((0, -0.36, -0.12)), w0 + V((0, -0.5, -0.3)), w0 + V((0, -0.56, -0.55))],
                       0.44, 0.014, coat, V((0, -0.3, 1)), folds=3, fold_depth=0.025, taper=1.5, ragged=0.09, seed=3))
    # the coat's front: two lapels down the chest from the collar, the dark red lining showing at their edges
    front_n = -back_n
    for sx in (1, -1):
        a = NECK + V((sx * 0.07, 0.0, -0.02)) + front_n * 0.1
        b = HIP.lerp(CHEST, 0.45) + V((sx * 0.05, 0, 0)) + front_n * 0.13
        parts.append(cloth([a, a.lerp(b, 0.5) + front_n * 0.02, b], 0.08, 0.016, coat, front_n, folds=0, fold_depth=0.0, sub=3, m=4, taper=0.5))
        parts.append(cloth([a + V((sx * 0.04, 0, 0)), b + V((sx * 0.025, 0, 0))], 0.02, 0.018, lining, front_n, folds=0, fold_depth=0.0, sub=3, m=3))
    # the belt round the waist, a square buckle in front
    belt = []
    for k in range(13):
        a = 2 * math.pi * k / 12
        belt.append(HIP + up_t * 0.12 + V((math.sin(a) * 0.215, 0, 0)) + front_n * math.cos(a) * 0.165)
    parts.append(cloth(belt, 0.055, 0.016, leather, up_t, folds=0, fold_depth=0.0, sub=2, m=3))
    parts.append(T.box((0.07, 0.02, 0.06), loc=tuple(HIP + up_t * 0.12 + front_n * 0.172), mat=metal, bevel=0.008))
    # the inside of the skirt panels shows the lining
    # the hood, down: a heavy fold of cloth lying round the back of the neck and over the shoulders
    arc = []
    for k in range(9):
        a = math.radians(-100 + k * 25)                               # from the left collarbone round the back
        arc.append(NECK + V((math.sin(a) * 0.17, -math.cos(a) * 0.15, -0.06 - 0.03 * math.cos(a))))
    parts.append(cloth(arc, 0.17, 0.05, coat, up_t, folds=2, fold_depth=0.015, taper=0.8, sub=2, m=8))
    # a high collar standing round the neck, open at the throat
    col = []
    for k in range(7):
        a = math.radians(-120 + k * 40)
        col.append(NECK + V((math.sin(a) * 0.1, -math.cos(a) * 0.09, 0.03)))
    parts.append(cloth(col, 0.13, 0.012, coat, up_t, folds=1, fold_depth=0.004, sub=2, m=6))
    # TM2's helmet: one round shell; the visor is painted into its own surface (a band of faces across the front
    # at eye level take the visor material), so nothing floats in front of it
    HC = NECK + up_t * 0.2 + V((0, -0.02, 0.0))
    hs = T.sphere(0.165, loc=tuple(HC), mat=helmet, n=24, scale=(0.94, 1.1, 1.0))
    hs.data.materials.append(visor)
    mw = hs.matrix_world
    for p in hs.data.polygons:
        c = mw @ p.center - HC
        ang = math.degrees(math.atan2(c.x, c.y))      # 0 = straight ahead
        if abs(ang) < 68 and -0.035 < c.z < 0.05 and c.y > 0:
            p.material_index = 1
    hs.data.polygons.foreach_set("use_smooth", [True] * len(hs.data.polygons))
    parts.append(hs)
    # the scythe across his back: snath from the left hip up past the right shoulder, the blade out to the right
    A = HIP + up_t * (-0.08) + V((-0.28, 0, 0)) + back_n * 0.2
    Bt = HIP + up_t * 1.15 + V((0.3, 0, 0)) + back_n * 0.2
    d = (Bt - A).normalized()

    def aim(v):
        q = V(v).normalized().to_track_quat("Z", "Y").to_euler()
        return (math.degrees(q.x), math.degrees(q.y), math.degrees(q.z))

    parts.append(T.cyl(0.022, (Bt - A).length, loc=tuple((A + Bt) / 2), rot=aim(d), mat=wood, n=10))
    for t in (0.22, 0.52):
        parts.append(T.cyl(0.028, 0.06, loc=tuple(A.lerp(Bt, t)), rot=aim(d), mat=leather, n=10))
    parts.append(T.cyl(0.03, 0.07, loc=tuple(Bt), rot=aim(d), mat=blade, n=10))
    e = (V((1, 0, 0)) - d * d.x).normalized()
    nb = e.cross(d).normalized()
    secs = []
    for k in range(13):
        s = k / 12
        c = Bt + e * (0.72 * s) - d * (0.24 * s * s) + d * 0.03
        tg = (e * 0.72 - d * (0.48 * s)).normalized()
        wv = nb.cross(tg).normalized()
        if wv.dot(-d) < 0:
            wv = -wv
        w = 0.13 * (1 - s) ** 0.8 + 0.004
        th = 0.012 * (1 - s) + 0.003
        secs.append([tuple(c + nb * th), tuple(c - wv * w * 0.15 + nb * th * 0.3), tuple(c - nb * th), tuple(c + wv * w - nb * 0.001)])
    parts.append(T.loft(secs, mat=blade, angle=40.0))
    for sx in (1, -1):  # the strap: over a shoulder and round the chest
        a = NECK + V((sx * 0.15, -0.02, -0.06)) + back_n * 0.1
        b = HIP.lerp(CHEST, 0.6) + V((-sx * 0.2, 0, 0)) + back_n * 0.15
        parts.append(cloth([a, a.lerp(b, 0.5) + back_n * 0.03, b], 0.045, 0.012, leather, back_n, folds=0, fold_depth=0.0, sub=3, m=3))
    print("rider triangles: %d" % T.tri_count(parts))
    return parts

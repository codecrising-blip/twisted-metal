"""Sweet Tooth's clown head (round 19, the owner's reference: the TM 2012 truck's mascot). One head for the
truck's roof (on a spring) and for Sweet Bot. Facing +Y, +Z up, centred on the middle of the head.
A fireball: the white fibreglass face in front, a riveted seam over the brow, and behind it the skull turns
into fire, yellow then orange, streaming back in broad tongues that curl up at their red tips. Narrow
red-rimmed eyes slanting up at the outside, a big red ball nose, a huge red-lipped grin of white teeth up
into the cheeks. Worn: chipped paint, grime in the creases (the bake does that).
    import clown_head; clown_head.build(centre, scale, parts)   # appends the meshes to `parts`
Size at scale 1: the face about 0.8 m across, about 1.5 m from the nose to the flame tips."""
import math

import tmlib as T
from mathutils import Vector

V = Vector
R = 0.4  # the skull
_m = {}


def _mats():
    if not _m:
        _m["face"] = T.M("paint", (0.64, 0.62, 0.56), wear=0.4, rust=0.15, dirt=0.5)
        _m["red"] = T.M("paint", (0.45, 0.02, 0.02), wear=0.4, rust=0.15, dirt=0.35)
        _m["nose"] = T.M("plastic", (0.55, 0.03, 0.02), wear=0.3, dirt=0.3)
        _m["dark"] = T.M("plastic", (0.02, 0.015, 0.015), wear=0.2, dirt=0.5)
        _m["teeth"] = T.M("plastic", (0.66, 0.64, 0.58), wear=0.4, dirt=0.5)
        _m["rivet"] = T.M("steel", (0.25, 0.22, 0.18), wear=0.4, rust=0.5, dirt=0.5)
        _m["f_yellow"] = T.M("paint", (0.85, 0.6, 0.12), wear=0.35, rust=0.12, dirt=0.4)
        _m["f_orange"] = T.M("paint", (0.85, 0.32, 0.03), wear=0.35, rust=0.12, dirt=0.4)
        _m["f_red"] = T.M("paint", (0.62, 0.08, 0.02), wear=0.35, rust=0.12, dirt=0.45)
    return _m


def _face_y(x, z):
    """How far forward the face is at (x, z) (head space): on the skull's surface."""
    return 0.95 * math.sqrt(max(R * R - x * x - z * z, 0.0))


def _tongue(c, s, az, el, length, width, parts, m, segs=8, n=8):
    """A broad tongue of flame rooted on the back of the skull at azimuth `az` (0 = straight back, +
    to the right) and elevation `el` (degrees), streaming back and up, its tip curling up. Yellow at the
    root, orange, red at the tip."""
    a, e = math.radians(az), math.radians(el)
    normal = V((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    base = V((0, -0.2, 0.06)) + normal * R * 0.78  # rooted in the fire mass behind the skull
    d0 = (normal * 0.45 + V((0, -1.0, 0.3))).normalized()
    side = V((math.cos(a), math.sin(a), 0.0))
    pts, rads = [], []
    for i in range(segs + 1):
        t = i / segs
        p = base + d0 * length * t + V((0, 0, 1)) * length * 0.8 * t ** 2.0 + side * length * 0.08 * math.sin(t * math.pi * 1.6)
        pts.append(p)
        rads.append(max(0.006, width * (1.0 - t) ** 0.8 * (0.9 + 0.25 * math.sin(t * math.pi))))
    secs = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, segs)] - pts[max(i - 1, 0)]).normalized()
        ax = side - d * side.dot(d)
        ax.normalize()
        bx = d.cross(ax).normalized()
        r = rads[i]
        secs.append([tuple(c + (p + ax * math.cos(2 * math.pi * k / n) * r + bx * math.sin(2 * math.pi * k / n) * r * 0.45) * s) for k in range(n)])
    c1, c2 = int(segs * 0.3), int(segs * 0.75)
    parts.append(T.loft(secs[:c1 + 1], m["f_yellow"], "flame", True, True, 50.0))
    parts.append(T.loft(secs[c1:c2 + 1], m["f_orange"], "flame", True, True, 50.0))
    parts.append(T.loft(secs[c2:], m["f_red"], "flame", True, True, 50.0))


def build(c, s, parts):
    """The head at centre c (Vector or tuple), scale s; meshes appended to parts."""
    m = _mats()
    c = V(c)

    def P(x, y, z):
        return tuple(c + V((x, y, z)) * s)

    # the skull, one egg: the white face in front and below, the top and back painted fire (yellow), a
    # riveted seam over the brow and behind the cheeks between the two
    parts.append(T.sphere(R * s, loc=P(0, 0, 0), mat=m["face"], n=20, scale=(1.0, 0.98, 1.0)))
    f = V((0, 0.6, -0.8))  # the face side looks forward and down; the seam plane is across it
    SEAM = -0.12
    cap = T.sphere((R + 0.006) * s, loc=P(0, 0, 0), mat=m["f_yellow"], n=20, scale=(1.0, 0.98, 1.0))
    T.cut(cap, T.box((3 * s, 3 * s, 3 * s), loc=tuple(c + f * (1.5 + SEAM) * s), rot=(-53.13, 0, 0)))
    parts.append(cap)
    a_ax = V((1, 0, 0))
    b_ax = f.cross(a_ax).normalized()
    rr = math.sqrt(R * R - SEAM * SEAM) + 0.006
    seam = [f * SEAM + (a_ax * math.cos(2 * math.pi * k / 32) + b_ax * math.sin(2 * math.pi * k / 32)) * rr for k in range(33)]
    parts.append(T.tube([tuple(c + p * s) for p in seam], 0.013 * s, mat=m["rivet"], n=6))
    for k in range(0, 32, 4):
        parts.append(T.sphere(0.012 * s, loc=tuple(c + seam[k] * 1.025 * s), mat=m["rivet"], n=5))
    # eyes: narrow almonds rimmed in red, slanting up at the outside, white inside, a small dark pupil
    for sx in (1, -1):
        x, z = sx * 0.15, 0.08
        y = _face_y(x, z)
        parts.append(T.sphere(0.1 * s, loc=P(x, y - 0.025, z), mat=m["red"], n=14, scale=(1.55, 0.4, 0.55)))
        parts[-1].rotation_euler = (0, math.radians(-sx * 16), math.radians(-sx * 12))
        parts.append(T.sphere(0.085 * s, loc=P(x, y - 0.012, z - 0.004), mat=m["teeth"], n=12, scale=(1.45, 0.36, 0.3)))
        parts[-1].rotation_euler = (0, math.radians(-sx * 16), math.radians(-sx * 12))
        parts.append(T.sphere(0.024 * s, loc=P(x - sx * 0.02, y + 0.012, z - 0.006), mat=m["dark"], n=8))
        parts.append(T.box((0.24 * s, 0.05 * s, 0.032 * s), loc=P(x + sx * 0.01, _face_y(x, z + 0.07) - 0.01, z + 0.07), rot=(0, -sx * 20, 0), mat=m["red"], bevel=0.008 * s))
    parts.append(T.sphere(0.11 * s, loc=P(0, _face_y(0, -0.02) + 0.04, -0.02), mat=m["nose"], n=16))  # the ball nose
    # the grin: wide, its corners high in the cheeks; a block of white teeth with a dark line between the
    # rows, framed by thick red lips
    def lip_up(u):
        return -0.1 + 0.11 * u * u
    def lip_dn(u):
        return -0.27 + 0.2 * u ** 4 + 0.05 * u * u
    W = 0.29
    for k in range(12):
        u = (k - 5.5) / 6.0
        x = u * W
        z_top, z_bot = lip_up(u) - 0.012, lip_dn(u) + 0.012
        if z_top - z_bot < 0.02:
            continue
        z_mid = (z_top + z_bot) / 2
        y = _face_y(x, z_mid) - 0.004
        parts.append(T.box((0.044 * s, 0.03 * s, (z_top - z_mid) * s - 0.006 * s), loc=P(x, y, (z_top + z_mid) / 2), rot=(0, 0, -u * 35), mat=m["teeth"]))
        parts.append(T.box((0.044 * s, 0.03 * s, (z_mid - z_bot) * s - 0.006 * s), loc=P(x, y - 0.006, (z_mid + z_bot) / 2), rot=(0, 0, -u * 35), mat=m["teeth"]))
    gap = [V((u * W * 0.98, _face_y(u * W, (lip_up(u) + lip_dn(u)) / 2) - 0.012, (lip_up(u) + lip_dn(u)) / 2)) for u in [(k - 8) / 8.0 for k in range(17)]]
    parts.append(T.tube([tuple(c + p * s) for p in gap], 0.008 * s, mat=m["dark"], n=5))
    for fn in (lip_up, lip_dn):
        pts = []
        for k in range(13):
            u = (k - 6) / 6.0 * 1.02
            z = fn(u)
            pts.append(c + V((u * W, _face_y(u * W, z) + 0.006, z)) * s)
        parts.append(T.tube([tuple(p) for p in pts], 0.026 * s, mat=m["red"], n=6))
    # the fire: the back of the skull runs out into a teardrop of fire (a fireball flying face first)...
    secs = []
    for i in range(8):
        t = i / 7
        ctr = V((0, -0.5 * t, 0.1 * t + 0.12 * t * t))
        r = max(0.01, R * 0.97 * (1.0 - 0.62 * t ** 1.3))
        secs.append([tuple(c + (ctr + V((math.cos(2 * math.pi * k / 16) * r, 0, math.sin(2 * math.pi * k / 16) * r * 0.95))) * s) for k in range(16)])
    parts.append(T.loft(secs[:5], m["f_yellow"], "fire_mass", True, True, 50.0))
    parts.append(T.loft(secs[4:], m["f_orange"], "fire_mass", True, True, 50.0))
    # ...and broad tongues stream back and up out of it, their tips curling up
    for az, el, length, width in ((0, 55, 0.8, 0.3), (-42, 36, 0.7, 0.27), (42, 36, 0.7, 0.27), (-75, 12, 0.55, 0.24), (75, 12, 0.55, 0.24),
                                  (0, 12, 0.85, 0.3)):
        _tongue(c, s, az, el, length, width, parts, m)


def _aim(d):
    q = V(d).normalized().to_track_quat("Z", "Y").to_euler()
    return (math.degrees(q.x), math.degrees(q.y), math.degrees(q.z))

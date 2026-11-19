"""Mr. Grimm (round 20, owner): the TM2 vehicle and helmet, the Head-On rider's clothes. A red sport bike
with a full fairing (a pointed shield round the headlight, a smoked screen), a weapon sidecar bolted on its
right: an armoured box with a wedge nose, three lamps low in front, a bone skull on its back, a six-barrel
gatling on top and a rack of brass rounds beside it, a belt of rounds over its back. The rider crouches over
the tank in TM2's round black helmet, dressed as Death: a long black coat, tattered tails streaming back over
the seat, a hood bunched at the neck, wide sleeves, black gloves and boots, the scythe strapped across his back.
References: docs/reference/3d_models/tm2_cars_4views/mr_grimm_*.jpg (shape), the textured TM2 roster in
tm2_roster_textured_obj.zip (colours), docs/reference TM2MrGrimmRender (bike).
    /tmp/bpy3.13/bin/python tools/blender/build_mr_grimm.py              # build, bake, export
    /tmp/bpy3.13/bin/python tools/blender/build_mr_grimm.py --shape a.png  # quick look, no bake
Blender space: +Y forward, +Z up. Nodes: body, wheel_f, wheel_r, spinner; markers m_wheel_fl (bike front),
m_wheel_rl (bike rear), m_wheel_rr (sidecar), m_gun_l/r, m_spin_0, m_launcher, m_top, m_head, m_exh_l."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmlib as T
import numpy as np
from mathutils import Matrix, Vector

T.reset()
V = Vector
RED = (0.36, 0.03, 0.025)
red = T.M("paint", RED, wear=0.55, rust=0.35, dirt=0.55)
black_paint = T.M("paint", (0.02, 0.02, 0.022), wear=0.5, rust=0.3, dirt=0.55)
armor = T.M("steel", (0.045, 0.047, 0.045), wear=0.65, rust=0.55, dirt=0.6)
bare = T.M("steel", (0.12, 0.12, 0.12), wear=0.6, rust=0.4, dirt=0.5)
dark = T.M("steel", (0.015, 0.015, 0.016), wear=0.35, rust=0.3, dirt=0.6)
gun_steel = T.M("steel", (0.2, 0.2, 0.19), wear=0.3, rust=0.3, dirt=0.45)
brass = T.M("steel", (0.36, 0.24, 0.07), wear=0.25, rust=0.2, dirt=0.4)
copper = T.M("steel", (0.32, 0.12, 0.05), wear=0.3, rust=0.3, dirt=0.4)
rubber = T.M("rubber", (0.016, 0.016, 0.016), dirt=0.65)
leather = T.M("plastic", (0.02, 0.018, 0.017), wear=0.4, dirt=0.6)
helmet = T.M("plastic", (0.012, 0.012, 0.014), wear=0.35, dirt=0.4, rough=0.3)
coat = T.M("cloth", (0.022, 0.023, 0.03), dirt=0.55)
lining = T.M("cloth", (0.06, 0.012, 0.012), dirt=0.5)
bone = T.M("plastic", (0.55, 0.5, 0.4), wear=0.75, dirt=0.75)
wood = T.M("wood", (0.16, 0.09, 0.045), dirt=0.6)
blade = T.M("steel", (0.28, 0.28, 0.27), wear=0.3, rust=0.45, dirt=0.4)
soot = T.M("burnt", (0.05, 0.04, 0.03), rust=0.5)
glass = T.glass((0.02, 0.025, 0.03))
decals = []
regions = []
markers = []

R = 0.36            # every wheel (the sidecar's too): one spin rate for all
BX = -0.42          # the bike's centre line; the sidecar rides on the right
SX = 0.53           # the sidecar's centre line
FA, RA = 1.12, -0.78  # bike axles
body = []


def aim(d):
    q = Vector(d).normalized().to_track_quat("Z", "Y").to_euler()
    return (math.degrees(q.x), math.degrees(q.y), math.degrees(q.z))


def rod(a, b, r, mat, n=10, r2=None):
    a, b = Vector(a), Vector(b)
    v = b - a
    return T.cyl(r, v.length, loc=tuple((a + b) / 2), rot=aim(v), mat=mat, n=n, r2=r2)


def limb(a, b, w, d, mat, bevel=0.02):
    a, b = Vector(a), Vector(b)
    v = b - a
    return T.box((w, d, v.length), loc=tuple((a + b) / 2), rot=aim(v), mat=mat, bevel=bevel)


def rivets(a, b, n, parts, r=0.014, mat=bare):
    for k in range(n):
        parts.append(T.sphere(r, loc=tuple(Vector(a).lerp(Vector(b), k / max(1, n - 1))), mat=mat, n=6))


def strip(path, width, thick, mat, up=V((0, 0, 1)), taper=1.0):
    """A strip of cloth or plate along `path` (list of points): `width` across, `thick` through, its flat side
    facing `up` as far as the path allows; the width runs down to `taper` x at the end."""
    secs = []
    n = len(path)
    for k, p in enumerate(path):
        p = Vector(p)
        t = (Vector(path[min(k + 1, n - 1)]) - Vector(path[max(k - 1, 0)])).normalized()
        side = t.cross(up).normalized()
        nrm = side.cross(t).normalized()
        w = width * (1.0 + (taper - 1.0) * k / (n - 1)) / 2
        secs.append([tuple(p + side * w + nrm * thick / 2), tuple(p - side * w + nrm * thick / 2),
                     tuple(p - side * w - nrm * thick / 2), tuple(p + side * w - nrm * thick / 2)])
    return T.loft(secs, mat=mat, angle=35.0)


# ---------------------------------------------------------------- the bike
for sx in (1, -1):  # front fork: raked 24 deg, fat lowers, a brace over the tyre
    top = V((BX + sx * 0.1, FA - 0.36, 1.06))
    bot = V((BX + sx * 0.1, FA, R))
    body.append(rod(top, top.lerp(bot, 0.5), 0.028, gun_steel))
    body.append(rod(top.lerp(bot, 0.45), bot, 0.04, dark))
    body.append(T.cyl(0.05, 0.05, loc=tuple(bot + V((sx * 0.01, 0, 0))), rot=(0, 90, 0), mat=bare, n=10))
body.append(T.box((0.26, 0.06, 0.05), loc=(BX, FA - 0.36, 1.06), mat=dark, bevel=0.01))         # top yoke
body.append(T.box((0.26, 0.07, 0.05), loc=(BX, FA - 0.26, 0.85), rot=(24, 0, 0), mat=dark, bevel=0.01))  # lower yoke
for k in range(4):  # front fender: a short arc over the tyre
    a = math.radians(50 + k * 22)
    c = V((BX, FA + math.cos(a) * (R + 0.06), R + math.sin(a) * (R + 0.06)))
    body.append(T.box((0.15, 0.17, 0.025), loc=tuple(c), rot=(math.degrees(a) - 90, 0, 0), mat=red, bevel=0.006))
# the fairing: a pointed shield round the headlight, wider and taller going back (TM2's front view)


def shield(y, w, zb, zt):
    return [(BX, y, zb), (BX + w * 0.5, y, zb + (zt - zb) * 0.38), (BX + w * 0.46, y, zt), (BX - w * 0.46, y, zt), (BX - w * 0.5, y, zb + (zt - zb) * 0.38)]


body.append(T.loft([shield(1.02, 0.3, 0.84, 1.08), shield(0.92, 0.5, 0.72, 1.17), shield(0.78, 0.62, 0.66, 1.2), shield(0.6, 0.6, 0.66, 1.16)],
                   mat=red, angle=25.0))
body.append(T.cyl(0.075, 0.04, loc=(BX, 1.035, 0.96), rot=(-90, 0, 0), mat=dark, n=14))
body.append(T.cyl(0.06, 0.02, loc=(BX, 1.055, 0.96), rot=(-90, 0, 0), mat=T.glow((0.9, 0.82, 0.6)), n=14))  # headlight
for sx in (1, -1):  # little turn lamps on the fairing's flanks
    body.append(T.box((0.05, 0.03, 0.03), loc=(BX + sx * 0.27, 0.85, 1.0), mat=T.glow((0.9, 0.45, 0.05))))
body.append(T.prism([(-0.21, 0.0), (0.21, 0.0), (0.13, 0.17), (0.0, 0.24), (-0.13, 0.17)], 0.01, loc=(BX, 0.86, 1.17), rot=(38, 0, 0), mat=glass))  # smoked screen, leaning back
body.append(T.box((0.43, 0.03, 0.025), loc=(BX, 0.86, 1.17), mat=dark))
body.append(T.box((0.38, 0.52, 0.22), loc=(BX, 0.3, 1.01), mat=red, bevel=0.08))                 # tank
body.append(T.cyl(0.04, 0.02, loc=(BX, 0.38, 1.125), mat=bare, n=10))                              # filler cap
body.append(T.box((0.3, 0.46, 0.07), loc=(BX, -0.2, 0.95), mat=leather, bevel=0.025))             # seat
body.append(T.loft([[(BX - 0.17, -0.42, 0.9), (BX + 0.17, -0.42, 0.9), (BX + 0.16, -0.42, 1.04), (BX - 0.16, -0.42, 1.04)],
                    [(BX - 0.12, -1.0, 0.92), (BX + 0.12, -1.0, 0.92), (BX + 0.09, -1.0, 1.08), (BX - 0.09, -1.0, 1.08)],
                    [(BX - 0.05, -1.22, 0.96), (BX + 0.05, -1.22, 0.96), (BX + 0.03, -1.22, 1.02), (BX - 0.03, -1.22, 1.02)]],
                   mat=red, angle=30.0))                                                             # tail
body.append(T.box((0.12, 0.03, 0.04), loc=(BX, -1.13, 0.98), rot=(-15, 0, 0), mat=T.glow((0.85, 0.05, 0.03))))
# TM2's skull plate on a backrest behind the rider
body.append(T.box((0.3, 0.04, 0.24), loc=(BX, -0.64, 1.1), rot=(-14, 0, 0), mat=red, bevel=0.02))
for sx in (1, -1):
    body.append(rod(V((BX + sx * 0.12, -0.58, 0.95)), V((BX + sx * 0.12, -0.62, 1.2)), 0.018, gun_steel))
# engine: an inline four, finned, with covers either side
body.append(T.box((0.34, 0.42, 0.3), loc=(BX, 0.24, 0.5), mat=dark, bevel=0.03))
for k in range(5):
    body.append(T.box((0.4, 0.3, 0.018), loc=(BX, 0.4, 0.62 + k * 0.045), rot=(-20, 0, 0), mat=bare))
for sx in (1, -1):
    body.append(T.cyl(0.13, 0.05, loc=(BX + sx * 0.19, 0.18, 0.46), rot=(0, 90, 0), mat=gun_steel, n=14, bevel=0.01))
    body.append(rod(V((BX + sx * 0.13, 0.75, 1.02)), V((BX + sx * 0.13, -0.24, 0.62)), 0.03, dark))  # frame spars
    body.append(limb(V((BX + sx * 0.12, -0.24, 0.55)), V((BX + sx * 0.12, RA, R)), 0.04, 0.07, dark))  # swingarm
    body.append(rod(V((BX + sx * 0.16, 0.05, 0.42)), V((BX + sx * 0.2, -0.05, 0.4)), 0.02, bare))       # footpegs
body.append(rod(V((BX, -0.3, 0.92)), V((BX, -0.45, 0.55)), 0.035, gun_steel))                     # rear shock
body.append(T.cyl(0.05, 0.12, loc=(BX, -0.36, 0.78), rot=(-22, 0, 0), mat=copper, n=10))           # its spring
for k in range(4):  # headers into one pipe and a muffler on the left (the sidecar is on the right)
    x = BX - 0.12 + k * 0.08
    body.append(T.tube([(x, 0.42, 0.55), (x, 0.5, 0.36), (BX - 0.16, 0.3, 0.24), (BX - 0.22, -0.2, 0.3)], 0.02, mat=bare, n=6))
body.append(rod(V((BX - 0.22, -0.2, 0.3)), V((BX - 0.24, -0.62, 0.52)), 0.035, bare))
body.append(rod(V((BX - 0.24, -0.6, 0.51)), V((BX - 0.26, -1.08, 0.66)), 0.07, dark, 12, 0.06))
body.append(T.cyl(0.045, 0.03, loc=(BX - 0.26, -1.09, 0.665), rot=aim(V((-0.02, -0.48, 0.15))), mat=soot, n=10))
markers.append(T.marker("m_exh_l", (BX - 0.26, -1.12, 0.67)))
for sx in (1, -1):  # clip-on bars low on the fork, levers, grips
    g = V((BX + sx * 0.33, 0.66, 1.06))
    body.append(rod(V((BX + sx * 0.1, 0.76, 1.03)), g, 0.016, dark))
    body.append(T.cyl(0.024, 0.11, loc=tuple(g + V((sx * 0.04, 0, 0))), rot=(0, 90, 0), mat=rubber, n=8))
    body.append(limb(g - V((sx * 0.02, -0.04, 0)), g + V((sx * 0.06, 0.08, -0.02)), 0.012, 0.02, bare, 0.003))

# ---------------------------------------------------------------- the weapon sidecar
body.append(T.box((0.64, 1.72, 0.48), loc=(SX, -0.16, 0.5), mat=red, bevel=0.035))                # the box
body.append(T.prism([(0.7, 0.26), (1.12, 0.38), (1.12, 0.46), (0.7, 0.74)], 0.64, loc=(SX, 0, 0), mat=armor, plane="YZ"))  # wedge nose
for k in range(3):  # three lamps low in the nose (TM2)
    x = SX + (k - 1) * 0.17
    body.append(T.cyl(0.05, 0.05, loc=(x, 1.1, 0.4), rot=(-90, 0, 0), mat=dark, n=12))
    body.append(T.cyl(0.036, 0.02, loc=(x, 1.13, 0.4), rot=(-90, 0, 0), mat=T.glow((0.85, 0.7, 0.4)), n=12))
for sx in (1, -1):  # riveted armour plates down both flanks
    x = SX + sx * 0.33
    body.append(T.box((0.03, 1.5, 0.36), loc=(x, -0.18, 0.47), mat=armor, bevel=0.008))
    rivets(V((x + sx * 0.017, -0.88, 0.62)), V((x + sx * 0.017, 0.52, 0.62)), 9, body)
    rivets(V((x + sx * 0.017, -0.88, 0.32)), V((x + sx * 0.017, 0.52, 0.32)), 9, body)
body.append(T.box((0.66, 0.04, 0.05), loc=(SX, -1.02, 0.28), mat=bare, bevel=0.01))               # rear bumper bar
for y in (0.32, -0.52):  # struts to the bike's frame
    body.append(rod(V((SX - 0.3, y, 0.42)), V((BX + 0.16, y, 0.48)), 0.03, gun_steel))
    body.append(T.sphere(0.04, loc=(BX + 0.16, y, 0.48), mat=bare, n=8))
# a bone skull bolted to its back (TM2), on a dark plate
body.append(T.box((0.46, 0.03, 0.34), loc=(SX, -1.025, 0.52), mat=armor, bevel=0.01))
sk = V((SX, -1.06, 0.55))
body.append(T.sphere(0.13, loc=tuple(sk + V((0, 0, 0.04))), mat=bone, n=14, scale=(1.0, 0.55, 0.9)))
body.append(T.box((0.15, 0.06, 0.08), loc=tuple(sk + V((0, -0.01, -0.1))), mat=bone, bevel=0.02))  # jaw
for sx in (1, -1):
    body.append(T.sphere(0.035, loc=tuple(sk + V((sx * 0.05, -0.06, 0.04))), mat=dark, n=8, scale=(1.1, 0.6, 1.0)))  # sockets
    body.append(T.box((0.028, 0.03, 0.12), loc=tuple(sk + V((sx * 0.13, -0.02, -0.02))), mat=bone, bevel=0.008))   # cheek bones
body.append(T.sphere(0.018, loc=tuple(sk + V((0, -0.07, -0.02))), mat=dark, n=6, scale=(0.9, 0.6, 1.2)))  # nose
for k in range(5):  # teeth
    body.append(T.box((0.022, 0.02, 0.03), loc=tuple(sk + V(((k - 2) * 0.026, -0.04, -0.07))), mat=bone))
# the gatling: a mount block on a ring, the spinner turns in a shroud; a rack of rounds on its outer side
body.append(T.cyl(0.16, 0.05, loc=(SX, 0.2, 0.765), mat=dark, n=16))
body.append(T.box((0.24, 0.4, 0.2), loc=(SX, 0.22, 0.88), mat=armor, bevel=0.025))
body.append(T.cyl(0.1, 0.12, loc=(SX, 0.48, 0.9), rot=(-90, 0, 0), mat=gun_steel, n=14))          # front of the drive
body.append(T.box((0.03, 0.34, 0.06), loc=(SX - 0.12, 0.22, 1.0), mat=dark))                       # sight rail
rack = V((SX + 0.21, 0.2, 0.86))
body.append(T.box((0.16, 0.5, 0.2), loc=tuple(rack), mat=armor, bevel=0.01))
for k in range(9):  # the rounds stand in the rack, tips up
    p = rack + V((0, -0.21 + k * 0.052, 0.1))
    body.append(T.cyl(0.02, 0.1, loc=tuple(p + V((0.04, 0, 0.0))), mat=brass, n=8))
    body.append(T.cyl(0.02, 0.04, loc=tuple(p + V((0.04, 0, 0.07))), mat=copper, n=8, r2=0.004))
    body.append(T.cyl(0.02, 0.1, loc=tuple(p + V((-0.03, 0, 0.0))), mat=brass, n=8))
    body.append(T.cyl(0.02, 0.04, loc=tuple(p + V((-0.03, 0, 0.07))), mat=copper, n=8, r2=0.004))
for k in range(10):  # a belt of rounds laid across its back, feeding forward
    p = V((SX, -0.5 + k * 0.06, 0.755))
    body.append(T.cyl(0.02, 0.36, loc=tuple(p), rot=(0, 90, 0), mat=brass, n=8))
    body.append(T.box((0.4, 0.03, 0.012), loc=tuple(p + V((0, 0, 0.02))), mat=dark))
markers.append(T.marker("m_spin_0", (SX, 0.54, 0.9)))
for sx in (1, -1):
    markers.append(T.marker("m_gun_" + ("r" if sx > 0 else "l"), (SX + sx * 0.03, 1.4, 0.9)))
markers.append(T.marker("m_launcher", (0.2, 0.62, 0.92)))
markers.append(T.marker("m_top", (BX, 0.3, 0.95)))
markers.append(T.marker("m_head", (BX, 1.06, 0.96)))

# ---------------------------------------------------------------- the rider: TM2's helmet, Death's clothes
HIP = V((BX, -0.2, 1.02))
SHO = V((BX, 0.2, 1.42))
ax = (SHO - HIP).normalized()
back_n = V((0, -ax.z, ax.y))  # the back faces up and behind


def torso_ring(t, w, d, k=8):
    c = HIP.lerp(SHO, t)
    pts = []
    for i in range(k):
        a = 2 * math.pi * i / k
        pts.append(tuple(c + V((1, 0, 0)) * math.cos(a) * w / 2 + back_n * math.sin(a) * d / 2))
    return pts


body.append(T.loft([torso_ring(-0.05, 0.36, 0.24), torso_ring(0.35, 0.38, 0.26), torso_ring(0.75, 0.46, 0.28), torso_ring(1.0, 0.44, 0.24)],
                   mat=coat, angle=50.0))
body.append(T.cyl(0.07, 0.12, loc=tuple(SHO + ax * 0.06), rot=aim(ax), mat=coat, n=10))           # neck
body.append(T.cyl(0.13, 0.13, loc=tuple(SHO + ax * 0.04), rot=aim(ax), mat=coat, n=12, r2=0.15))  # high collar
body.append(T.sphere(0.15, loc=tuple(SHO + back_n * 0.12 + ax * 0.0), mat=coat, n=12, scale=(1.3, 0.7, 0.8)))  # the hood, down
H = SHO + ax * 0.2 + V((0, 0.05, 0.03))
body.append(T.sphere(0.155, loc=tuple(H), mat=helmet, n=18, scale=(0.95, 1.08, 1.0)))             # TM2's round helmet
body.append(T.sphere(0.13, loc=tuple(H + V((0, 0.06, -0.005))), mat=glass, n=16, scale=(1.0, 1.0, 0.5)))  # smoked visor
body.append(T.box((0.24, 0.05, 0.02), loc=tuple(H + V((0, 0.13, -0.075))), mat=helmet, bevel=0.008))  # chin bar edge
for sx in (1, -1):
    s = SHO + V((sx * 0.22, -0.02, -0.03))
    e = V((BX + sx * 0.28, 0.42, 1.2))
    w = V((BX + sx * 0.32, 0.62, 1.08))
    body.append(T.sphere(0.085, loc=tuple(s), mat=coat, n=10))
    body.append(rod(s, e, 0.075, coat, 10, 0.08))                                                   # upper sleeve
    body.append(rod(e, w + (e - w).normalized() * 0.05, 0.08, coat, 10, 0.11))                      # the reaper's bell sleeve
    body.append(T.sphere(0.05, loc=tuple(w), mat=leather, n=10, scale=(1.0, 1.3, 0.9)))             # gloved hand on the grip
    for k in range(3):  # the sleeve's ragged hem
        a = 2 * math.pi * k / 3 + sx
        d = (e - w).normalized()
        hem = w + d * 0.04 + V((math.cos(a) * 0.09, 0, math.sin(a) * 0.09))
        body.append(rod(hem, hem - d * 0.02 + V((0, 0, -0.07)), 0.03, coat, 5, 0.008))
    # legs: thighs down the tank, knees in, shins back to the pegs, boots
    th = HIP + V((sx * 0.12, 0.05, -0.03))
    kn = V((BX + sx * 0.19, 0.3, 0.86))
    ft = V((BX + sx * 0.21, 0.02, 0.45))
    body.append(rod(th, kn, 0.085, coat, 10, 0.07))
    body.append(T.sphere(0.075, loc=tuple(kn), mat=coat, n=10))
    body.append(rod(kn, ft + V((0, 0, 0.06)), 0.065, coat, 10, 0.055))
    body.append(T.box((0.1, 0.24, 0.1), loc=tuple(ft + V((0, 0.05, 0.02))), mat=leather, bevel=0.03))  # boot
    # the coat hangs open down his sides in tatters, over the thigh to below the knee
    for k in range(4):
        y = -0.12 + k * 0.1
        top = V((BX + sx * 0.2, y, 1.0))
        L = 0.42 + 0.08 * ((k * 7 + (sx > 0) * 3) % 3)
        body.append(strip([top, top + V((sx * 0.05, 0.02, -L * 0.5)), top + V((sx * 0.06, 0.06 - k * 0.02, -L))], 0.11, 0.012, coat, up=V((sx, 0, 0)), taper=0.55))
# the coat's tails stream back over the seat and the tail, ragged at the hem
for k in range(5):  # overlapping, so it reads as one torn sheet; it droops over the tail as it goes
    x = BX + (k - 2) * 0.075
    L = 0.72 + 0.1 * ((k * 7) % 3)
    sp = (k - 2) * 0.03
    p0 = V((x, -0.3, 1.12))
    pts = [p0, p0 + V((sp * 0.3, -0.25, 0.0)), p0 + V((sp, -0.5, -0.06)), p0 + V((sp * 1.6, -L * 0.85, -0.2)), p0 + V((sp * 2.0, -L, -0.34))]
    body.append(strip(pts, 0.13, 0.012, coat, up=V((0, 0.2, 1)), taper=0.6))
body.append(strip([HIP + V((0, -0.06, 0.12)), HIP + V((0, -0.2, 0.1)), HIP + V((0, -0.33, 0.1))], 0.5, 0.016, coat, up=V((0, 0, 1))))  # where the tails join the back
# the scythe across his back: a dark wooden snath from his left hip up past his right shoulder, the blade sweeping out
A = HIP + ax * (-0.2) + V((-0.3, 0, 0)) + back_n * 0.17
B = HIP + ax * 0.95 + V((0.34, 0, 0)) + back_n * 0.17
body.append(rod(A, B, 0.022, wood, 8))
for t in (0.25, 0.55):  # two grips on the snath
    body.append(T.cyl(0.03, 0.05, loc=tuple(A.lerp(B, t)), rot=aim(B - A), mat=leather, n=8))
body.append(T.cyl(0.032, 0.07, loc=tuple(B), rot=aim(B - A), mat=bare, n=8))                       # the blade's collar
d = (B - A).normalized()
e = (V((1, 0, 0)) - d * d.x).normalized()
nb = e.cross(d).normalized()
secs = []
for k in range(9):
    s = k / 8
    c = B + e * (0.7 * s) - d * (0.22 * s * s) + d * 0.03
    tg = (e * 0.7 - d * (0.44 * s)).normalized()
    wv = nb.cross(tg).normalized()
    if wv.dot(-d) < 0:
        wv = -wv
    w = 0.13 * (1 - s) ** 0.8 + 0.004
    th = 0.012 * (1 - s) + 0.003
    secs.append([tuple(c + nb * th), tuple(c - wv * w * 0.15 + nb * th * 0.3), tuple(c - nb * th), tuple(c + wv * w - nb * 0.001)])
body.append(T.loft(secs, mat=blade, angle=40.0))
for sx in (1, -1):  # the strap holding it, over the shoulder and round the chest
    body.append(strip([SHO + V((sx * 0.16, 0.02, 0.04)) + back_n * 0.13, HIP.lerp(SHO, 0.4) + V((-sx * 0.19, 0, 0)) + back_n * 0.14], 0.045, 0.012, leather, up=back_n))

# ---------------------------------------------------------------- wheels (axle along X, outer face at +X) and the spinner


def wheel(name, w, spokes):
    tyre = [(R * 0.66, -w / 2), (R * 0.9, -w / 2), (R * 0.985, -w / 2 + 0.03), (R, -w * 0.2), (R, w * 0.2), (R * 0.985, w / 2 - 0.03), (R * 0.9, w / 2), (R * 0.66, w / 2)]
    parts = [T.lathe(tyre, rot=(0, 90, 0), mat=rubber, n=22, angle=50)]
    parts.append(T.lathe([(R * 0.66, -w / 2 + 0.01), (R * 0.66, w / 2 - 0.01), (R * 0.6, w / 2 - 0.02), (R * 0.6, -w / 2 + 0.02)], rot=(0, 90, 0), mat=bare, n=22))
    for k in range(spokes):  # TM2's spoked wheels: crossed spokes to the hub
        a = math.radians(360 * k / spokes)
        tip = V((0, math.cos(a) * R * 0.62, math.sin(a) * R * 0.62))
        hub = V(((-1 if k % 2 else 1) * w * 0.25, math.cos(a + 0.3) * 0.05, math.sin(a + 0.3) * 0.05))
        parts.append(rod(hub, tip, 0.012, gun_steel, 5))
    parts.append(T.cyl(0.075, w * 0.75, rot=(0, 90, 0), mat=bare, n=12))
    parts.append(T.cyl(R * 0.4, 0.008, loc=(w * 0.32, 0, 0), rot=(0, 90, 0), mat=bare, n=16))  # brake disc
    return T.join(parts, name)


wheel_f = wheel("wheel_f", 0.13, 16)
wheel_r = wheel("wheel_r", 0.17, 16)
markers += [T.marker("m_wheel_fl", (BX, FA, R)), T.marker("m_wheel_rl", (BX, RA, R)), T.marker("m_wheel_rr", (SX + 0.08, -0.3, R))]
sp = [T.cyl(0.075, 0.05, (0, 0.06, 0), rot=(-90, 0, 0), mat=bare, n=12), T.cyl(0.075, 0.04, (0, 0.62, 0), rot=(-90, 0, 0), mat=bare, n=12)]
for k in range(6):
    a = math.radians(60 * k)
    sp.append(T.cyl(0.018, 0.86, (math.cos(a) * 0.05, 0.43, math.sin(a) * 0.05), rot=(-90, 0, 0), mat=gun_steel, n=6))
sp.append(T.cyl(0.026, 0.84, (0, 0.42, 0), rot=(-90, 0, 0), mat=dark, n=6))
spinner = T.join(sp, "spinner")
body_ob = T.join(body, "body")
print("triangles: body %d, wheel_f %d, wheel_r %d, spinner %d" % (T.tri_count([body_ob]), T.tri_count([wheel_f]), T.tri_count([wheel_r]), T.tri_count([spinner])))

# ---------------------------------------------------------------- paint
def flames(P, N):  # dark flame licks along the tank and the fairing's flanks (TM2's bike has them)
    x = np.abs(P[:, 0] - BX)
    y, z = P[:, 1], P[:, 2]
    side = (x > 0.12) & (z > 0.75) & (z < 1.2) & (y > 0.05) & (y < 1.0)
    lick = np.sin(y * 26.0 + np.sin(y * 7.0) * 2.0) * 0.05 + 0.92 - (y - 0.05) * 0.12
    return (side & (z < lick)).astype(np.float32) * 0.85
regions.append((flames, (0.02, 0.02, 0.022), ("paint",)))
decals.append(T.Decal(T.stencil("GRIMM", (0.6, 0.56, 0.48), 120, bridges=False, pad=0.06), (SX + 0.35, -0.3, 0.6), (1, 0, 0), (0, 0, 1), (0.7, 0.16), depth=0.06, kinds=("steel",), opacity=0.7))
decals.append(T.Decal(T.holes_image(n=10, seed=21, size=(512, 200), r=(3, 7)), (SX + 0.33, 0.1, 0.45), (1, 0, 0), (0, 0, 1), (0.9, 0.3), depth=0.06, kinds=("steel", "paint")))
decals.append(T.Decal(T.holes_image(n=6, seed=22, size=(512, 200), r=(3, 7)), (BX - 0.2, 0.75, 0.95), (-1, 0, 0), (0, 0, 1), (0.4, 0.2), depth=0.08, kinds=("paint",)))
decals.append(T.Decal(T.dots_image((0.02, 0.02, 0.02), n=10, seed=5, size=(256, 256), r=(18, 30)), (SX, 1.12, 0.9), (0, 1, 0), (0, 0, 1), (0.4, 0.3), depth=0.3, kinds=("steel", "paint"), opacity=0.5))  # gun soot

if "--shape" in sys.argv:
    out = sys.argv[sys.argv.index("--shape") + 1]
    wf = [T.dup(wheel_f, (BX, FA, R)), T.dup(wheel_r, (BX, RA, R)), T.dup(wheel_r, (SX + 0.08, -0.3, R)), T.dup(spinner, (SX, 0.54, 0.9))]
    for o in (wheel_f, wheel_r, spinner):
        o.location = (0, 0, -50)
    T.preview(out, size=(1000, 700), eye=(3.6, 3.8, 1.9), look=(0.05, 0.0, 0.75), fov=38, samples=12)
    T.preview(out.replace(".png", "_b.png"), size=(1000, 700), eye=(-3.4, -3.8, 2.2), look=(0, 0, 0.8), fov=38, samples=12)
    T.preview(out.replace(".png", "_s.png"), size=(1000, 700), eye=(5.0, 0.1, 1.0), look=(0, 0.0, 0.8), fov=38, samples=12)
    sys.exit(0)

# ---------------------------------------------------------------- bake and export
import bpy
wheel_f.location = (3.0, 0.8, R)
wheel_r.location = (3.0, -0.8, R)
spinner.location = (3.0, 1.8, 0.5)
bpy.context.view_layer.update()
for o in (wheel_f, wheel_r, spinner):
    T.apply(o)
objs = [body_ob, wheel_f, wheel_r, spinner]
T.unwrap(objs, margin=0.002)
if "--nobake" not in sys.argv:
    g = T.gbuffer(objs, size=2048, ao_dist=0.45, bevel_r=0.008, ao_samples=22)
    al, nm, orm = T.weather(g, decals, seed=47, dust_from=0.1, dust_to=1.0, regions=regions)
    T.save_maps("mr_grimm", al, nm, orm)
wheel_f.data.transform(Matrix.Translation((-3.0, -0.8, -R)))
wheel_r.data.transform(Matrix.Translation((-3.0, 0.8, -R)))
spinner.data.transform(Matrix.Translation((-3.0, -1.8, -0.5)))
T.export_glb("mr_grimm", objs, markers=markers)
print("ok", T.tri_count(objs))

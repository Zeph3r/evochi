"""The stage of Bram's forge minigame (forge_minigame.dart): the forge corner seen straight on, as one
picture the game paints its live work over (the bar's heat, the hammer, the sparks, the sweep). The brick
hearth with its coals and iron hood on the left, the anvil on its stump in the middle, the quench barrel
on the right, Bram's tools and lanterns on the wall behind.

    python3 forge_stage.py OUT_DIR [--quick]

Writes forge_stage.png and forge_stage.json (where the hearth, the anvil face, the barrel's water and the
hammer's pivot fall in the picture, as fractions of its width and height: the painter's anchors).
"""
import json
import math
import os
import sys

import numpy as np

from home_scenes import hashmask
from village_scenes import (BRASS, BRICK, COBBLE, COPPER, CPainter, GLASS_AMBER, GLASS_MINT, IRON, OAK, STONE, STONE_LT, VScene, WALNUT,
                            WATERC, ball, barrel, box, crate, cyl_y, lantern)
from voxel import Model

W, H = 1080, 840
CAM = {'pos': (0.6, 6.8, 30.0), 'target': (0.6, 3.3, 0.0), 'fov': 22.0}
EMBER = ['#FF9A3C', '#FFC561', '#FF6A2A']
ORE_COPPER = ['#C9874E', '#8E5A33', '#D9985E']
ORE_IRON = ['#7A8088', '#5E666E', '#9099A2']
HEARTH = (-4.4, -2.6)     # x, z of the coals' middle
ANVIL = (0.9, 0.6)        # the anvil's waist
FACE_Y = 3.4              # the anvil's working face
BARREL = (5.5, 0.9)
PIVOT = (4.1, 6.6, 0.6)   # where the hammer swings from


def project(p):
    """world point -> (u, v) fractions of the picture (Blender's camera, vertical fov)"""
    cp, tg = np.array(CAM['pos'], float), np.array(CAM['target'], float)
    f = tg - cp
    f /= np.linalg.norm(f)
    r = np.cross(f, [0.0, 1.0, 0.0])
    r /= np.linalg.norm(r)
    u = np.cross(r, f)
    d = np.array(p, float) - cp
    x, y, z = d @ r, d @ u, d @ f
    t = math.tan(math.radians(CAM['fov']) / 2)
    return 0.5 + (x / z) / (2 * t * W / H), 0.5 - (y / z) / (2 * t)


def scene():
    S = VScene('forge_stage', W, H, CAM, world=((0.95, 0.8, 0.66), 0.1), samples=128)
    M = Model((-11, -1, -6), (11, 15, 9), [], res=4)
    P = CPainter(M, 23)
    X, Y, Z = M.X, M.Y, M.Z
    rng = np.random.default_rng(23)
    # the floor: worn flags, sooty by the hearth
    floor = box(M, (-11, -1, -5), (11, 0, 9))
    P.fill(floor, ['#6E5D50', '#62534A', '#7A675A'], cell=(1.2, 1, 1.2))
    P.fill(floor & hashmask(M, 0.1, seed=4, cell=1.2), ['#54473E'], cell=9)
    P.fill(floor & ((X - HEARTH[0]) ** 2 / 9 + (Z - HEARTH[1] - 1.5) ** 2 / 4 < 1) & hashmask(M, 0.5, seed=6, cell=0.5), ['#4A4040', '#55493F'], cell=9)
    # the back wall: brick with mortar, a timber post and plate
    wall = box(M, (-11, 0, -5.6), (11, 15, -4.6))
    P.fill(wall, BRICK, cell=(2.0, 1.0, 2.0))
    P.fill(wall & ((Y % 1.0) < 0.14), ['#D8C6A8'], cell=9)
    P.fill(wall & (((X + 7 * (np.floor(Y) % 2)) % 2.0) < 0.14), ['#D8C6A8'], cell=9)
    P.fill(wall & (Y < 1.0), STONE, cell=(1.0, 0.6, 1.0))
    for px in (-9.6, 8.6):
        P.fill(box(M, (px, 0, -4.6), (px + 0.7, 15, -4.0)), WALNUT, cell=9)
    P.fill(box(M, (-11, 11.4, -4.6), (11, 12.1, -4.0)), WALNUT, cell=9)
    # ---- the hearth: a brick block out from the wall, an arched mouth, the coals, the hood
    hx, hz = HEARTH
    block = box(M, (hx - 3.0, 0, -4.6), (hx + 3.0, 5.2, -1.4))
    P.fill(block, BRICK, cell=(1.0, 0.5, 1.0))
    P.fill(block & ((Y % 0.8) < 0.12), ['#D8C6A8'], cell=9)
    P.fill(box(M, (hx - 3.2, 4.9, -4.6), (hx + 3.2, 5.4, -1.2)), STONE_LT, cell=(1.0, 1, 1.0))       # the lintel shelf
    arch = (np.abs(X - hx) < 2.0) & (Y >= 1.3) & (Y < 3.0 + np.sqrt(np.clip(4.0 - (X - hx) ** 2, 0, None)) * 0.55) & (Z >= -3.8) & (Z < -1.3)
    M.m[arch] = 0
    P.fill(box(M, (hx - 2.0, 1.3, -4.0), (hx + 2.0, 4.2, -3.8)), ['#231B18', '#2B211D'], cell=9)    # the soot at the back
    P.fill(box(M, (hx - 2.0, 1.0, -3.8), (hx + 2.0, 1.3, -1.3)), ['#2B211D'], cell=9)               # the grate
    coals = ball(M, (hx, 1.3, hz), 1.8, 0.4) & (Y >= 1.3) & (Z < -1.4)
    P.fill(coals, EMBER, glow=0.55, cell=0.4)
    P.fill(coals & hashmask(M, 0.3, seed=5, cell=0.4), ['#3A2A22', '#2B211D'], cell=9)
    P.fill(ball(M, (hx, 1.4, hz), 0.8, 0.5) & (Y >= 1.3), ['#FFD27A'], glow=0.6, cell=9)
    S.lights.append({'type': 'point', 'pos': (hx, 2.2, hz + 0.6), 'power': 30.0, 'color': 1900, 'radius': 1.0})
    S.lights.append({'type': 'point', 'pos': (hx, 1.8, -0.4), 'power': 14.0, 'color': 2100, 'radius': 1.4})
    hood = (np.abs(X - hx) < 3.3 - (Y - 5.4) * 0.42) & (Y >= 5.4) & (Y < 10.4) & (Z >= -4.6) & (Z < -1.0 - (Y - 5.4) * 0.5)
    P.fill(hood, IRON, cell=(1.0, 0.5, 1.0))
    P.fill(hood & (np.abs(Y - 5.7) < 0.3), ['#3F3531'], cell=9)
    for rx in (-2.4, 0, 2.4):                                                                    # rivets
        P.fill(ball(M, (hx + rx, 5.9, -0.9), 0.18), BRASS, cell=9)
    # the bellows, leaning on the hearth's left
    bx = hx - 4.4
    P.fill(box(M, (bx - 1.0, 0, -2.6), (bx + 1.0, 0.4, -0.6)), WALNUT, cell=9)
    P.fill(box(M, (bx - 0.9, 0.4, -2.4), (bx + 0.9, 1.5, -0.8)), ['#8D5D3B', '#7E5133'], cell=(9, 0.3, 9))
    P.fill(box(M, (bx - 1.0, 1.5, -2.6), (bx + 1.0, 1.8, -0.6)), WALNUT, cell=9)
    P.fill(box(M, (bx - 0.2, 1.8, -1.8), (bx + 0.2, 3.4, -1.4)), WALNUT, cell=9)
    P.fill(box(M, (bx + 1.0, 0.8, -1.8), (bx + 1.4, 1.2, -1.4)), IRON, cell=9)
    # ---- the anvil on its stump
    ax, az = ANVIL
    stump = cyl_y(M, (ax, az), 1.35, 0, 2.0)
    P.fill(stump, WALNUT, cell=(9, 0.4, 9))
    P.fill(stump & (Y >= 1.8), ['#B48A5E', '#A47A50'], cell=9)
    P.fill(stump & (np.abs(Y - 0.6) < 0.18), IRON, cell=9)
    P.fill(box(M, (ax - 1.1, 2.0, az - 0.75), (ax + 1.4, 2.4, az + 0.75)), IRON, cell=9)            # foot
    P.fill(box(M, (ax - 0.55, 2.4, az - 0.45), (ax + 0.85, 2.85, az + 0.45)), IRON, cell=9)         # waist
    P.fill(box(M, (ax - 1.9, 2.85, az - 0.75), (ax + 2.1, FACE_Y - 0.15, az + 0.75)), IRON, cell=9)  # body
    P.fill(box(M, (ax - 1.9, FACE_Y - 0.15, az - 0.75), (ax + 2.1, FACE_Y, az + 0.75)), ['#9AA3AC', '#8A939C'], cell=9)   # the bright face
    horn = ((Z - az) ** 2 + (Y - (FACE_Y - 0.35)) ** 2 <= np.clip(0.45 - (X - ax - 2.1) * 0.26, 0, None) ** 2) & (X >= ax + 2.1) & (X < ax + 3.8)
    P.fill(horn, IRON, cell=9)
    P.fill(box(M, (ax - 2.4, FACE_Y - 0.6, az - 0.5), (ax - 1.9, FACE_Y - 0.1, az + 0.5)), IRON, cell=9)   # heel
    # tongs leaning on the stump
    P.fill(box(M, (ax - 1.6, 0, az + 1.0), (ax - 1.4, 2.4, az + 1.15)), IRON, cell=9)
    P.fill(box(M, (ax - 1.3, 0, az + 1.0), (ax - 1.1, 2.3, az + 1.15)), IRON, cell=9)
    # ---- the quench barrel, its water, a dipper on the rim
    qx, qz = BARREL
    barrel(P, M, qx, qz, 1.25, 2.6)
    P.fill(cyl_y(M, (qx, qz), 1.05, 2.25, 2.55), WATERC, cell=9)
    P.fill(box(M, (qx + 0.6, 2.5, qz - 0.1), (qx + 1.9, 2.7, qz + 0.1)), WALNUT, cell=9)
    # ---- the tool wall: hammers and tongs on hooks above the anvil, a rack of bars, lanterns
    P.fill(box(M, (-1.2, 7.6, -4.6), (7.8, 7.9, -4.2)), WALNUT, cell=9)
    for k, tx in enumerate(np.arange(-0.6, 7.6, 1.15)):
        P.fill(box(M, (tx - 0.06, 7.2, -4.4), (tx + 0.06, 7.6, -4.2)), IRON, cell=9)
        if k % 3 == 0:     # a hammer, head down
            P.fill(box(M, (tx - 0.12, 4.9, -4.5), (tx + 0.12, 7.2, -4.3)), WALNUT, cell=9)
            P.fill(box(M, (tx - 0.45, 4.6, -4.55), (tx + 0.45, 5.2, -4.2)), IRON, cell=9)
        elif k % 3 == 1:   # tongs
            P.fill(box(M, (tx - 0.25, 5.0, -4.5), (tx - 0.12, 7.2, -4.35)), IRON, cell=9)
            P.fill(box(M, (tx + 0.12, 5.0, -4.5), (tx + 0.25, 7.2, -4.35)), IRON, cell=9)
        else:              # a file / chisel
            P.fill(box(M, (tx - 0.1, 5.6, -4.5), (tx + 0.1, 7.2, -4.35)), ['#6E7680'], cell=9)
            P.fill(box(M, (tx - 0.14, 6.6, -4.52), (tx + 0.14, 7.2, -4.33)), WALNUT, cell=9)
    # a shelf of bars and ingots, a finished lantern or two
    P.fill(box(M, (-1.0, 9.6, -4.6), (7.6, 9.9, -3.6)), WALNUT, cell=9)
    for k, ix in enumerate(np.arange(-0.4, 3.4, 0.9)):
        P.fill(box(M, (ix, 9.9, -4.3), (ix + 0.7, 10.25, -3.8)), (ORE_COPPER, ORE_IRON, COPPER)[k % 3], cell=9)
    lantern(S, P, M, (5.0, 10.7, -4.0), s=0.42, lit=True, glass=GLASS_AMBER, power=4.0)
    lantern(S, P, M, (6.6, 10.7, -4.0), s=0.42, lit=False, glass=GLASS_MINT)
    lantern(S, P, M, (-8.0, 8.4, -3.9), s=0.5, lit=True, glass=GLASS_AMBER, power=6.0)
    P.fill(box(M, (-8.15, 9.4, -4.6), (-7.85, 10.6, -3.9)), IRON, cell=9)
    # ---- the floor's clutter: ore crates and a coal sack at the sides, out of the play
    crate(P, M, 8.6, -2.6, 0.9)
    for k in range(3):
        P.fill(ball(M, (8.6 + (rng.random() - 0.5) * 0.8, 2.1, -2.6 + (rng.random() - 0.5) * 0.8), 0.42), ORE_COPPER if k % 2 else ORE_IRON, cell=9)
    P.fill(ball(M, (-9.4, 0.8, 0.8), 1.1, 0.75) & (Y >= 0), ['#4A4040', '#3F3535'], cell=9)
    P.fill(ball(M, (-9.4, 1.5, 0.8), 0.5, 0.5) & (Y >= 1.2), ['#2B211D'], cell=9)
    # light: warm fill from the front (the camera side), a cool window wash from the right
    S.lights.append({'type': 'point', 'pos': (1.0, 9.0, 12.0), 'power': 26.0, 'color': 3200, 'radius': 3.0})
    S.lights.append({'type': 'sun', 'dir': (-0.5, -0.6, -0.6), 'power': 0.45, 'color': 5600, 'angle': 8.0})
    S.models.append((M, (), {'water': WATERC}))
    S.grade = {'bloom': 0.22, 'vignette': 0.2, 'warm': 0.03}
    return S


if __name__ == '__main__':
    out = sys.argv[1]
    quick = '--quick' in sys.argv
    os.makedirs(out, exist_ok=True)
    anchors = {
        'hearth': project((HEARTH[0], 1.6, HEARTH[1] + 1.0)),
        'mouth_top': project((HEARTH[0], 4.0, -1.4)),
        'anvil': project((ANVIL[0], FACE_Y, ANVIL[1])),
        'anvil_l': project((ANVIL[0] - 1.9, FACE_Y, ANVIL[1] + 0.75)),
        'anvil_r': project((ANVIL[0] + 2.1, FACE_Y, ANVIL[1] + 0.75)),
        'water': project((BARREL[0], 2.55, BARREL[1])),
        'water_r': project((BARREL[0] + 1.05, 2.55, BARREL[1])),
        'pivot': project(PIVOT),
        'floor_front': project((0.0, 0.0, 6.0)),
    }
    json.dump({k: [round(a, 4), round(b, 4)] for k, (a, b) in anchors.items()}, open(os.path.join(out, 'forge_stage.json'), 'w'), indent=1)
    print(json.dumps(anchors))
    if '--anchors' in sys.argv:
        sys.exit(0)
    import village_blender as VB
    import village_scenes as VSC
    if quick:
        VB.QUICK = 0.5
    vs = scene()
    raw = os.path.join(out, 'forge_stage_raw.png')
    VB.render(vs, raw, preview=quick)
    VSC.finish(vs, raw, os.path.join(out, 'forge_stage.png'), quick)

"""The nest hub, lit in Blender like the Home Map and the Square: the nest in the meadow, the path
forking behind it, the Cottage up the left branch and the stone arch to Sunlit Village up the right,
two sign posts at the fork with blank boards (the game letters them, and lights the one you tap).

    python3 hub_blender.py OUT_DIR [--ruined] [--quick | --preview] [--light day|golden] [--no-nest]

Camera: close and a little high, so the Evochi stands as big as it does in the meadow today and the
fork reads behind it. Writes hub_<state>.png (graded), hub_<state>_raw.png and hub_<state>.json
(anchors in image px: the nest, the sign boards, both walks, both destinations).
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from voxel import Model
from village_scenes import (VScene, CPainter, box, cyl_y, ball, gable, fence_line, outdoor_lantern, flower_patch, tree2,
                            far_terrain, STATE_LIGHT, GRASS, PATHC, ROOF, PLASTER, WATERC, CLEAR_GLASS, HONEY, WALNUT, OAK,
                            STONE, STONE_LT, FLOWERS, TREE_LEAVES)
from home_scenes import cottage, noise2, STRAW


def seg(M, a, b, w):
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    t = np.clip(((M.X - ax) * dx + (M.Z - az) * dz) / (dx * dx + dz * dz), 0, 1)
    return (M.X - ax - t * dx) ** 2 + (M.Z - az - t * dz) ** 2 <= w * w


NEST_R = 3.9
COTTAGE = (-18.0, -5.0, -27.0, -17.0)                  # x0, x1, z0, z1: the door faces the nest
GATE = (11.5, -21.0)
SIGNS = {'home': (-10.5, -5.0), 'village': (10.5, -5.0)}
BOARD = dict(w=8.4, h=3.3, y=3.9, d=0.6)               # the sign boards (world units)
LEFT_WALK = [(0.0, 0.0), (-3.0, -3.4), (-7.0, -8.0), (-10.0, -12.5), (-11.5, -17.0)]
RIGHT_WALK = [(0.0, 0.0), (3.0, -3.4), (7.0, -8.0), (10.0, -13.0), (11.5, -19.0), (11.5, -26.0)]


def board(P, M, x, z, left):
    """A blank arrow plank on its post, pointing out along its path."""
    w, h, y, d = BOARD['w'], BOARD['h'], BOARD['y'], BOARD['d']
    P.fill(box(M, (x - 0.4, 0, z - 0.4), (x + 0.4, y + 0.4, z + 0.4)), WALNUT, cell=(9, 1, 9))
    P.fill(box(M, (x - 0.8, 0, z - 0.8), (x + 0.8, 0.5, z + 0.8)), STONE, cell=0.5)
    s = -1 if left else 1                                  # the tip's side
    u = (M.X - x) * s                                      # along the board, toward the tip
    tl = 1.8                                               # the arrow tip's length
    tip = w / 2 - tl
    shape = (u >= -w / 2) & (u < w / 2) & (np.abs(M.Y - y) <= h / 2 - np.clip(u - tip, 0, None) * (h / 2) / tl) & \
            (M.Z >= z + 0.45) & (M.Z < z + 0.45 + d)
    rim = shape & ~((u >= -w / 2 + 0.3) & (np.abs(M.Y - y) <= h / 2 - 0.3 - np.clip(u - tip + 0.3, 0, None) * (h / 2) / tl))
    P.fill(shape, ['#E2B57A', '#D9AA6E', '#E8BE86'], cell=(2.0, 0.7, 1.0))
    P.fill(shape & (np.abs(np.abs(M.Y - y) - h / 6) < 0.12), ['#C4925E'], cell=9)
    P.fill(rim, ['#8A5A34', '#7A4E2E'], cell=0.5)


def scene_hub_b(restored=True, light='day', nest=True, w=1170, h=2532):
    st = STATE_LIGHT[light]
    # close and a little high: the nest just below the middle, the fork and both doors above it
    cam = {'pos': (0.0, 20.0, 40.0), 'target': (0.0, 3.0, -8.0), 'fov': 70.0}
    S = VScene('hub_' + ('restored' if restored else 'ruined'), w, h, cam, world=st['world'], samples=160,
               transparent=True, sky=st['sky'])
    S.lights.append({'type': 'sun', **st['sun']})
    rng = np.random.default_rng(91)
    M = Model((-40, -4, -44), (40, 26, 30), [], res=2)
    P = CPainter(M, 91)
    ground = (M.Y >= -1) & (M.Y < 0)
    P.fill((M.Y >= -4) & (M.Y < -1), ['#B98955', '#A97C4B'], cell=1)
    P.fill(ground, GRASS, cell=1.0)
    P.fill(ground & (noise2(M) > 0.75), ['#79A85A', '#73A255'], cell=1.0)
    P.fill(ground & (noise2(M, 0.21, 0.17, 2.0) > 1.05), ['#96C473', '#9BC979'], cell=1.0)
    # the paths: up from the bottom to the nest, then forking to the Cottage door and the gate
    path = seg(M, (0.6, 30.0), (0.0, 4.0), 2.3)
    for pts in (LEFT_WALK, RIGHT_WALK):
        for a, b in zip(pts[1:-1], pts[2:]):
            path |= seg(M, a, b, 1.9)
        path |= seg(M, pts[0], pts[1], 1.9)
    clearing = (M.X ** 2 + M.Z ** 2) <= (NEST_R + 2.2) ** 2
    P.fill(ground & (path | clearing), PATHC, cell=(1.0, 1, 1.0))
    P.fill(ground & (path | clearing) & (noise2(M, 0.9, 0.8, 1.3) > 0.9), ['#CDBB94'], cell=1.0)
    # the nest (the game draws the one you've placed; this one is for the picture)
    if nest:
        # a woven straw bowl: a fat ring with darker weave bands, a blanket and a pillow inside
        r = np.sqrt(M.X ** 2 + M.Z ** 2)
        ang = np.degrees(np.arctan2(M.Z, M.X))
        ring = (np.sqrt((r - NEST_R) ** 2 + ((M.Y - 1.2) / 1.15) ** 2) <= 1.4) & (M.Y >= 0)
        P.fill(ring, STRAW, cell=0.5)
        weave = ring & (((np.floor(ang / 10) + np.floor(M.Y / 0.5)) % 2) == 0)
        P.fill(weave, ['#C9A24A', '#BF9640', '#D4AE4E'], cell=0.5)
        P.fill(ring & (M.Y >= 2.3), ['#F0D27A', '#F6DE8E'], cell=0.5)          # the sunlit rim
        for k_ in range(14):                                                  # stray straws
            aa = k_ * 2 * math.pi / 14 + 0.2
            sx_, sz_ = (NEST_R + 1.3) * math.cos(aa), (NEST_R + 1.3) * math.sin(aa)
            st_ = (np.abs(M.Y - 0.3) < 0.2) & (np.abs((M.X - sx_) * math.sin(aa) - (M.Z - sz_) * math.cos(aa)) < 0.18) & \
                  (np.abs((M.X - sx_) * math.cos(aa) + (M.Z - sz_) * math.sin(aa)) < 0.9)
            P.fill(st_, ['#E8C766', '#D4AE4E'], cell=9)
        P.fill((r < NEST_R - 1.0) & (M.Y >= 0) & (M.Y < 0.7), ['#FBF5E8', '#F1E6CF'], cell=0.5)
        P.fill((r < NEST_R - 1.0) & (M.Y >= 0.5) & (M.Y < 0.7) & ((np.floor(M.X) + np.floor(M.Z)) % 2 == 0), ['#F5C4CF'], cell=9)
    # the Cottage and the gate
    x0, x1, z0, z1 = COTTAGE
    cottage(S, P, M, rng, x0, x1, z0, z1, restored)
    gcx, gcz = GATE
    for px in (gcx - 4.0, gcx + 4.0):
        P.fill(box(M, (px - 0.9, 0, gcz - 0.9), (px + 0.9, 6.4, gcz + 0.9)), STONE, cell=(1.0, 1.0, 1.0))
        P.fill(box(M, (px - 1.1, 6.4, gcz - 1.1), (px + 1.1, 7.0, gcz + 1.1)), STONE_LT, cell=9)
        vine = (np.abs(M.X - px - 0.7 * np.sin(M.Y * 1.1 + px)) < 0.5) & (M.Z >= gcz + 0.8) & (M.Z < gcz + 1.3) & (M.Y < 5.0) & (M.Y >= 0)
        P.fill(vine, ['#5EA046', '#4F9C3E', '#6FB24E'], cell=0.5)
    arch = (np.abs(M.Z - gcz) <= 0.9) & (np.abs(M.Y - 7.4 - 1.2 * np.cos((M.X - gcx) / 4.6 * 1.45)) <= 0.7) & (np.abs(M.X - gcx) <= 4.9)
    P.fill(arch, STONE_LT, cell=(1.0, 1.0, 1.0))
    P.fill(box(M, (gcx - 2.0, 5.2, gcz + 0.9), (gcx + 2.0, 6.6, gcz + 1.3)), HONEY, cell=9)
    for (bx, bz) in ((gcx - 4.0, gcz + 1.0), (gcx + 4.0, gcz + 1.0)):
        P.fill(ball(M, (bx, 7.6, bz), 0.5), ['#F5A3B5', '#FFFDF6'], cell=9)
    outdoor_lantern(S, P, M, gcx - 5.8, gcz + 1.8, 4.2, lit=True, s=0.6, power=10.0)
    fence_line(P, M, (gcx + 5.0, gcz - 0.5), (40.0, gcz - 2.5))
    fence_line(P, M, (gcx - 6.6, gcz - 0.5), (x1 + 1.5, gcz - 1.0))
    fence_line(P, M, (x0 - 1.5, z0 + 2.0), (-40.0, z0 + 0.5))
    # Sunlit Village beyond the gate: roofs along the road, the road running on
    road = seg(M, (gcx, gcz - 1.0), (gcx + 2.0, -44.0), 2.0)
    P.fill(ground & road, PATHC, cell=(1.0, 1, 1.0))
    for (hx, hz, hw, hh, roof) in ((gcx - 3.5, -33.0, 6.0, 4.0, ROOF), (gcx + 9.0, -31.0, 7.0, 4.6, ROOF),
                                   (gcx + 4.0, -41.0, 5.0, 3.6, ['#3E5F7E', '#36546F', '#4A6C8C']), (gcx + 17.0, -38.0, 6.0, 4.0, ROOF)):
        gable(P, M, hx - hw / 2, hx + hw / 2, hz - 2.2, hz + 2.2, hh, 2.8, PLASTER, roof, oh=0.6, ridge='x', wall_cell=(3, 3, 3))
        for wx in (hx - hw / 4, hx + hw / 4):
            P.fill(box(M, (wx - 0.5, hh * 0.45, hz + 2.2), (wx + 0.5, hh * 0.45 + 1.1, hz + 2.6)),
                   ['#FFD46A'] if restored else ['#9BB4C4'], glow=0.8 if restored else None, cell=9)
    # the sign posts, and a lit lantern beside each
    for key, (sx, sz) in SIGNS.items():
        board(P, M, sx, sz, key == 'home')
        lx = sx + (-4.0 if key == 'home' else 4.0)
        outdoor_lantern(S, P, M, lx, sz + 1.0, 3.4, lit=True, s=0.5, power=8.0)
    # trees: between the buildings, behind the Cottage, at the edges
    for (tx, tz, th, tr) in ((-1.5, -30.0, 7.0, 4.6), (-26.0, -24.0, 8.0, 5.2), (27.0, -18.0, 7.5, 5.0), (-27.0, 4.0, 6.0, 4.4),
                             (26.0, 6.0, 6.0, 4.2), (6.0, -36.0, 6.0, 3.8)):
        tree2(P, M, tx, tz, th, tr, fruit=['#D85F51'] if tx > 20 else None)
    # flowers and a few stones, off the paths and clear of the buildings
    keep_off = path | clearing | seg(M, (x0 - 1, z1 + 1), (x1 + 1, z1 + 1), 2.5)
    edge = np.zeros(M.m.shape[::2], bool)
    for pts in (LEFT_WALK, RIGHT_WALK):
        for a, b in zip(pts[1:-1], pts[2:]):
            edge |= (seg(M, a, b, 3.4) & ~seg(M, a, b, 2.2))[:, 0, :]
    ex, ez = np.nonzero(edge)
    for j in rng.choice(len(ex), size=min(60, len(ex)), replace=False):
        fx, fz = ex[j] / 2.0 - 40, ez[j] / 2.0 - 44
        if fz < -15 or fz > -2 or any(math.hypot(fx - sx, fz - sz) < 2.2 for (sx, sz) in SIGNS.values()):
            continue
        flower_patch(P, M, fx, fz, 0.6, 0.5, rng, n=1)
    for _ in range(26):                                    # leafy clumps in the near grass
        gx_, gz_ = rng.uniform(-22, 22), rng.uniform(5, 24)
        i, k = min(int((gx_ + 40) * 2), M.m.shape[0] - 1), min(int((gz_ + 44) * 2), M.m.shape[2] - 1)
        if not (path | clearing)[i, 0, k] and abs(gx_) > 3.5:
            P.fill(ball(M, (gx_, 0.0, gz_), rng.uniform(0.9, 1.4), 0.7) & (M.Y >= 0), ['#6FA552', '#5E9646', '#7FB35F'], cell=0.5)
    for _ in range(70):
        fx, fz = rng.uniform(-36, 36), rng.uniform(-30, 2)
        i, k = min(int((fx + 40) * 2), M.m.shape[0] - 1), min(int((fz + 44) * 2), M.m.shape[2] - 1)
        if keep_off[i, 0, k] or (x0 - 2 < fx < x1 + 2 and z0 - 2 < fz < z1 + 2) or (abs(fx - gcx) < 6 and abs(fz - gcz) < 3):
            continue
        if any(math.hypot(fx - sx, fz - sz) < 2.0 for (sx, sz) in SIGNS.values()):
            continue
        flower_patch(P, M, fx, fz, 1.2, 0.9, rng, n=3)
    for (rx, rz, rr) in ((-9.5, 4.5, 1.3), (-11.0, 2.0, 0.9), (10.5, 5.0, 1.0)):
        P.fill(ball(M, (rx, 0.2, rz), rr, 0.7) & (M.Y >= 0), STONE, cell=0.5)
    S.models.append((M, CLEAR_GLASS, {'water': WATERC}))
    S.models.append((far_terrain(seed=43), (), {'water': WATERC}))
    S.grade = {'bloom': 0.16 if restored else 0.1, 'vignette': 0.1, 'warm': 0.04}
    # anchors (world points; the renderer projects them)
    S.anchors = {'nest': (0.0, 0.0, 0.0), 'nest_r': (5.0, 0.0, 0.0)}       # nest_r: px per unit at the nest
    for key, (sx, sz) in SIGNS.items():
        bz = sz + 0.45 + BOARD['d']
        S.anchors[f'sign_{key}'] = (sx, BOARD['y'], bz)
        S.anchors[f'sign_{key}_l'] = (sx - BOARD['w'] / 2, BOARD['y'], bz)
        S.anchors[f'sign_{key}_r'] = (sx + BOARD['w'] / 2, BOARD['y'], bz)
        S.anchors[f'sign_{key}_t'] = (sx, BOARD['y'] + BOARD['h'] / 2, bz)
        S.anchors[f'sign_{key}_b'] = (sx, BOARD['y'] - BOARD['h'] / 2, bz)
    for key, pts in (('home', LEFT_WALK), ('village', RIGHT_WALK)):
        for i, (x, z) in enumerate(pts[:4]):
            S.anchors[f'walk_{key}_{i}'] = (x, 0.0, z)
            S.anchors[f'walk_{key}_{i}_u'] = (x + 1.0, 0.0, z)       # one unit along: px per unit there
    S.anchors['goal_home'] = ((x0 + x1) / 2, 2.5, z1)
    S.anchors['goal_village'] = (gcx, 4.0, gcz)
    return S


if __name__ == '__main__':
    import village_blender as VB
    import village_scenes as VSC
    args = sys.argv[1:]
    out = args[0]
    restored = '--ruined' not in args
    light = args[args.index('--light') + 1] if '--light' in args else 'day'
    preview = '--preview' in args or '--quick' in args
    if '--quick' in args:
        VB.QUICK = 0.3
    vs = scene_hub_b(restored, light, nest='--no-nest' not in args)
    os.makedirs(out, exist_ok=True)
    raw = os.path.join(out, f'{vs.name}_raw.png')
    anchors = VB.render(vs, raw, preview)
    VSC.finish(vs, raw, os.path.join(out, f'{vs.name}.png'), preview)
    json.dump({'w': vs.w, 'h': vs.h, 'nest_r5': True, 'anchors': anchors}, open(os.path.join(out, f'{vs.name}.json'), 'w'), indent=1)

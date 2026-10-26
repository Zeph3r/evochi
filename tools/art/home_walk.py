"""The Home, laid out to walk through (docs: the Hatching Nook & Companion Collection bible: Nest, Cottage
and Farm kept as the three big places, the Hatching Nook a small expansion against the cottage, the
Grove a quiet glade where two or three companions rest). The same ground as the Home Map
(home_scenes.scene_home_map, restored), seen from the walking camera: orthographic, 35 degrees above
the horizon, looking north. Cosier than the map: a bench and a lantern under the big tree, a woodpile
and a water butt by the cottage, a washing line, a birdbath, stepping stones to the pond, mushrooms,
and the farm grown to eight beds behind one fence, ready to be cleared one by one.

    python3 home_walk.py OUT [--quick] [--depth] [--view home|home_nook]

World: x east, z toward you, y up. The cottage's door faces +z (you).
"""
import math
import os
import sys

import numpy as np

import village_walk as VW
from home_scenes import GRAVEL, SOIL, SPROUT, STRAW, cottage, noise2, seg, soil_plot, sprouts
from village_scenes import (BRASS, COPPER, CPainter, FLOWERS, GRASS, HONEY, IRON, OAK, PATHC, PLASTER, ROOF, STONE, STONE_LT, STATE_LIGHT,
                            VScene, WALNUT, WATERC, ball, box, cyl_y, far_terrain, fence_line, flower_patch, gable, outdoor_lantern, tree2,
                            win_front)
from voxel import Model

X0, X1, Z0, Z1 = -44.0, 44.0, -46.0, 38.0
NEST = (-11.0, 13.0)
COTTAGE = (-24.0, -8.0, -31.0, -19.5)      # x0, x1, z0, z1 (the door on z1)
NOOK = (-8.0, 0.5, -28.5, -21.5)          # the Hatching Nook, against the cottage's east wall
GATE = (16.0, -33.0)
POND = (-30.0, -3.0)
GROVE = (-31.0, 25.0)                     # the glade's middle
FARM = (2.0, 36.0, -10.0, 20.0)           # one fence round eight beds
BEDS = [(4.0, 12.0, -8.0, -1.6), (14.0, 22.0, -8.0, -1.6), (4.0, 12.0, 1.4, 7.6), (14.0, 22.0, 1.4, 7.6),
        (26.0, 34.0, -8.0, -1.6), (26.0, 34.0, 1.4, 7.6), (4.0, 12.0, 11.4, 17.6), (14.0, 22.0, 11.4, 17.6)]
BED_CROPS = ['berry', 'leafy', 'wheat', 'weeds', 'weeds', 'weeds', 'weeds', 'weeds']   # the first four are tilled and sown
LUMEN = ['#9FF0DA', '#C8FFF0', '#7FD8C0']
MOSS = ['#5E9646', '#6FA552', '#4F8A3C', '#7FB35F']


def _path(M):
    hub = (-1.0, 2.0)
    return (seg(M, (NEST[0], NEST[1] - 5.0), hub, 2.0) | seg(M, hub, (2.5, 0.0), 2.0) | seg(M, hub, (-16.0, -18.0), 2.0) |
            seg(M, (-16.0, -18.0), (-4.0, -20.5), 1.6) | seg(M, hub, (9.0, -22.0), 2.0) | seg(M, (9.0, -22.0), (16.0, -33.0), 2.0) |
            seg(M, (16.0, -33.0), (17.0, -46.0), 2.2) | seg(M, (NEST[0] - 4.0, NEST[1] + 2.0), (GROVE[0] + 6.0, GROVE[1] - 4.0), 1.6) |
            seg(M, hub, (-22.0, -2.0), 1.4))


def scene_home_walk():
    st = STATE_LIGHT['day']
    S = VScene('home_walk', 1800, 1400, {}, world=st['world'], samples=96, transparent=True, sky=st['sky'])
    S.lights.append({'type': 'sun', **st['sun']})
    rng = np.random.default_rng(71)
    M = Model((X0, -4, Z0), (X1, 30, Z1), [], res=2)
    P = CPainter(M, 71)
    X, Y, Z = M.X, M.Y, M.Z
    ground = (Y >= -1) & (Y < 0)
    P.fill((Y >= -4) & (Y < -1), ['#B98955', '#A97C4B'], cell=1)
    P.fill(ground, GRASS, cell=1.0)
    P.fill(ground & (noise2(M) > 0.75), ['#79A85A', '#73A255'], cell=1.0)
    path = _path(M)
    P.fill(ground & path, PATHC, cell=(1.0, 1, 1.0))
    P.fill(ground & path & (noise2(M, 0.9, 0.8, 1.3) > 0.9), ['#CDBB94'], cell=1.0)
    # ---- the pond, with stepping stones out to it and a birdbath on its bank
    px_, pz_ = POND
    pr = ((X - px_) ** 2 / 36.0 + (Z - pz_) ** 2 / 16.0)
    M.m[(pr <= 1.0) & (Y >= -1.0) & (Y < 0)] = 0
    P.fill((pr <= 1.0) & (Y >= -1.6) & (Y < -0.6), WATERC, cell=1.0)
    P.fill((pr > 1.0) & (pr <= 1.35) & (Y >= -1.0) & (Y < 0.2), STONE_LT, cell=1.0)
    for (lx, lz) in ((px_ - 2.0, pz_ - 1.0), (px_ + 1.5, pz_ + 1.5), (px_ - 0.5, pz_ - 2.2)):
        P.fill(cyl_y(M, (lx, lz), 0.9, -0.7, -0.4), ['#5EA046', '#6FB24E'], cell=9)
    P.fill(ball(M, (px_ + 1.7, -0.3, pz_ + 1.7), 0.35), ['#F5A3B5'], cell=9)
    for k in range(4):
        P.fill(cyl_y(M, (-22.5 - k * 1.6, -2.0 + 0.4 * math.sin(k)), 0.8, -0.1, 0.25), STONE_LT, cell=9)
    P.fill(cyl_y(M, (px_ + 8.0, pz_ + 5.5), 0.5, 0, 1.6) | cyl_y(M, (px_ + 8.0, pz_ + 5.5), 1.4, 1.6, 2.0), STONE, cell=9)   # the birdbath
    P.fill(cyl_y(M, (px_ + 8.0, pz_ + 5.5), 1.1, 1.75, 2.0), WATERC, cell=9)

    # ---- the Nest: a woven straw ring with a blanket, a pillow and its little sign; a lantern on a post
    ncx, ncz = NEST
    r = np.sqrt((X - ncx) ** 2 + (Z - ncz) ** 2)
    ring = (np.sqrt((r - 4.4) ** 2 + (Y - 0.9) ** 2) <= 1.4) & (Y >= 0)
    P.fill(ring, STRAW, cell=0.5)
    P.fill(ring & ((np.floor(np.degrees(np.arctan2(Z - ncz, X - ncx)) / 12) % 2) == 0) & (Y > 1.4), ['#C9A24A', '#D4AE4E'], cell=0.5)
    P.fill((r < 3.3) & (Y >= 0) & (Y < 0.6), ['#FBF5E8', '#F1E6CF'], cell=0.5)
    P.fill((r < 3.3) & (Y >= 0.4) & (Y < 0.6) & ((np.floor((X - ncx) / 1.0) + np.floor((Z - ncz) / 1.0)) % 2 == 0), ['#F5C4CF'], cell=9)
    P.fill(ball(M, (ncx - 1.4, 0.9, ncz - 1.6), 1.0, 0.55) & (Y >= 0.4), ['#FFFDF6', '#F7F1E4'], cell=0.5)
    P.fill(box(M, (ncx + 5.4, 0, ncz - 3.4), (ncx + 5.8, 3.6, ncz - 3.0)), WALNUT, cell=9)
    P.fill(box(M, (ncx + 4.4, 2.6, ncz - 3.4), (ncx + 7.4, 4.2, ncz - 3.0)), HONEY, cell=9)
    for a in np.linspace(0.3, 2 * math.pi, 9):
        flower_patch(P, M, ncx + 7.2 * math.cos(a), ncz + 6.4 * math.sin(a), 0.9, 0.8, rng, n=2)
    outdoor_lantern(S, P, M, ncx + 7.0, ncz + 3.5, 4.4, lit=True, power=7.0, s=0.6)

    # ---- the Farm: one fence round eight beds, the first four tilled and sown, the rest waiting under
    # weeds (cleared one by one in the game); a shed, a scarecrow, a water butt, baskets at the gate
    gx0, gx1, gz0, gz1 = FARM
    fence_line(P, M, (gx0, gz0), (gx1, gz0))
    fence_line(P, M, (gx1, gz0), (gx1, gz1))
    fence_line(P, M, (gx0, gz1), (gx1, gz1))
    fence_line(P, M, (gx0, gz0), (gx0, -2.6))
    fence_line(P, M, (gx0, 2.6), (gx0, gz1))
    P.fill(ground & box(M, (gx0, -1, gz0), (gx1, 0, gz1)), GRAVEL, cell=(1.0, 1, 1.0))
    for (bx0, bx1, bz0, bz1), kind in zip(BEDS, BED_CROPS):
        soil_plot(P, M, bx0, bx1, bz0, bz1, top=0.7)
        sprouts(P, M, bx0 + 0.6, bx1 - 0.6, bz0 + 0.6, bz1 - 0.6, 0.7, rng, kind)
    P.fill(box(M, (12.8, 0, -0.1), (13.2, 5.4, 0.3)), WALNUT, cell=9)
    P.fill(box(M, (11.1, 3.6, -0.1), (14.9, 4.0, 0.3)), WALNUT, cell=9)
    P.fill(box(M, (11.9, 2.2, -0.4), (14.1, 4.4, 0.6)), ['#7F9871', '#76906A'], cell=9)
    P.fill(ball(M, (13.0, 5.4, 0.1), 0.9), ['#F0D27A', '#E8C766'], cell=9)
    P.fill(cyl_y(M, (13.0, 0.1), 1.4, 6.0, 6.3) | cyl_y(M, (13.0, 0.1), 0.8, 6.3, 7.1), ['#D9B36A', '#C9A24A'], cell=9)
    gable(P, M, 26.0, 34.0, -17.5, -12.5, 4.5, 3.0, ['#B98955', '#AD7E4C'], ['#7F9871', '#76906A', '#8AA37C'], oh=0.6, ridge='x', wall_cell=(1.0, 9, 9))
    P.fill(box(M, (29.0, 0, -12.6), (31.0, 3.6, -12.2)), ['#6E4529'], cell=9)
    P.fill(cyl_y(M, (24.5, -12.0), 1.3, 0, 2.6), WALNUT, cell=(9, 0.5, 9))                   # the water butt
    P.fill(cyl_y(M, (24.5, -12.0), 1.0, 2.4, 2.7), WATERC, cell=9)
    P.fill(cyl_y(M, (0.4, 4.6), 0.8, 0, 1.4), COPPER, cell=9)
    P.fill(box(M, (1.1, 0.9, 4.4), (2.2, 1.2, 4.8)), COPPER)
    P.fill(cyl_y(M, (0.4, -4.4), 1.0, 0, 1.0), ['#C69469', '#B9875C'], cell=9)
    for k in range(4):
        P.fill(ball(M, (0.1 + 0.5 * (k % 2), 1.2, -4.6 + 0.5 * (k // 2)), 0.35), [['#E8513F'], ['#F08A3A'], ['#E8513F'], ['#F4C04E']][k], cell=9)

    # ---- the Cottage, restored, with its flowers and fence; a woodpile and a washing line beside it
    cx0, cx1, cz0, cz1 = COTTAGE
    cottage(S, P, M, rng, cx0, cx1, cz0, cz1, True)
    flower_patch(P, M, -23.0, -16.6, 2.4, 1.2, rng, n=8)
    fence_line(P, M, (-26.0, -15.5), (-18.6, -15.5))
    for i in range(6):                                                                   # the woodpile
        for j in range(3 - i // 3):
            P.fill(cyl_y(M, (cx0 - 2.2 + (i % 3) * 1.2 + (j % 2) * 0.6, cz0 + 3.0 + (i // 3) * 1.2), 0.55, j * 1.0, j * 1.0 + 1.0),
                   ['#A8703F', '#8E5A33'], cell=9)
    for px in (cx0 - 7.0, cx0 - 1.5):                                                   # the washing line
        P.fill(box(M, (px - 0.2, 0, -12.2), (px + 0.2, 4.2, -11.8)), WALNUT, cell=9)
    P.fill((np.abs(Z + 12.0) < 0.15) & (np.abs(Y - 3.9 + 0.3 * np.sin((X - cx0 + 4.2) / 5.5 * math.pi)) < 0.15) & (X > cx0 - 7.0) & (X < cx0 - 1.5), IRON, cell=9)
    for k, col in enumerate((['#F5C4CF'], ['#C9E6F5'], ['#FBF5E8'])):
        wx = cx0 - 6.2 + k * 1.7
        P.fill(box(M, (wx, 2.4, -12.1), (wx + 1.2, 3.8, -11.9)), col, cell=9)

    # ---- the Hatching Nook: a small round-roofed room against the cottage's east wall, a warm round
    # window, an egg lantern on a post by its door (the landmark), moss on its roof
    nx0, nx1, nz0, nz1 = NOOK
    gable(P, M, nx0, nx1, nz0, nz1, 4.4, 2.8, ['#E9D7B8', '#E2CEAC', '#EADBC0'], ['#8AA37C', '#7F9871', '#9AB08A'], oh=0.8, ridge='x', wall_cell=(1, 1, 1))
    P.fill(box(M, (nx0 - 0.3, 0, nz0 - 0.3), (nx1 + 0.3, 1.0, nz1 + 0.3)) & ~box(M, (nx0, 0, nz0), (nx1, 1.2, nz1)), STONE_LT, cell=9)
    dz0, dz1 = nz1 + 0.3, nz1 + 0.8                                                   # proud of the wall, so they read
    P.fill(box(M, ((nx0 + nx1) / 2 - 1.0, 0, dz0), ((nx0 + nx1) / 2 + 1.0, 3.4, dz1)), ['#5E3A24'], cell=9)        # the door
    P.fill(box(M, ((nx0 + nx1) / 2 - 0.3, 2.6, dz1 - 0.1), ((nx0 + nx1) / 2 + 0.3, 3.2, dz1 + 0.2)), ['#9FF0DA'], glow=0.3, cell=9)
    win = ((X - (nx1 - 1.9)) ** 2 + (Y - 2.6) ** 2 < 0.9 ** 2) & (Z >= dz0) & (Z < dz1)
    P.fill(win, ['#FFD98A', '#FFE9B0'], glow=0.4, cell=9)
    P.fill(win & (((X - (nx1 - 1.9)) ** 2 + (Y - 2.6) ** 2 >= 0.6 ** 2) | (np.abs(X - (nx1 - 1.9)) < 0.12) | (np.abs(Y - 2.6) < 0.12)), WALNUT, cell=9)
    S.lights.append({'type': 'point', 'pos': (nx1 - 1.9, 2.6, nz1 + 0.8), 'power': 1.6, 'color': 2300, 'radius': 0.5})
    ex, ez = (nx0 + nx1) / 2 + 3.0, nz1 + 2.2                                            # the egg lantern
    P.fill(box(M, (ex - 0.25, 0, ez - 0.25), (ex + 0.25, 4.0, ez + 0.25)), WALNUT, cell=9)
    P.fill(box(M, (ex - 0.25, 3.8, ez - 0.25), (ex + 1.3, 4.2, ez + 0.25)), WALNUT, cell=9)
    egg = ((X - (ex + 1.1)) ** 2 / 0.7 ** 2 + (Y - 2.7) ** 2 / 1.0 ** 2 + (Z - ez) ** 2 / 0.7 ** 2 <= 1.0)
    P.fill(egg, ['#FFE2A0', '#FFEFC6'], glow=0.45, cell=9)
    P.fill(egg & (rng.random(M.m.shape) < 0.12), ['#F2B35A'], cell=9)
    P.fill(box(M, (ex + 0.9, 3.7, ez - 0.2), (ex + 1.3, 3.9, ez + 0.2)), IRON, cell=9)
    S.lights.append({'type': 'point', 'pos': (ex + 1.1, 2.7, ez + 0.4), 'power': 2.2, 'color': 2500, 'radius': 0.5})
    P.fill(box(M, (nx0, 7.0, nz0 + 0.5), (nx1, 7.5, nz0 + 2.5)) & (rng.random(M.m.shape) < 0.3), MOSS, cell=0.5)

    # ---- the Village Gate: a stone arch, a sign, a lantern and a mailbox; the hedge and the far roofs
    gcx, gcz = GATE
    for px in (gcx - 4.0, gcx + 4.0):
        P.fill(box(M, (px - 0.9, 0, gcz - 0.9), (px + 0.9, 6.4, gcz + 0.9)), STONE, cell=(1.0, 1.0, 1.0))
        P.fill(box(M, (px - 1.1, 6.4, gcz - 1.1), (px + 1.1, 7.0, gcz + 1.1)), STONE_LT, cell=9)
    arch = (np.abs(Z - gcz) <= 0.9) & (np.abs(Y - 7.4 - 1.2 * np.cos((X - gcx) / 4.6 * 1.45)) <= 0.7) & (np.abs(X - gcx) <= 4.9)
    P.fill(arch, STONE_LT, cell=(1.0, 1.0, 1.0))
    P.fill(box(M, (gcx - 2.0, 5.2, gcz + 0.9), (gcx + 2.0, 6.6, gcz + 1.3)), HONEY, cell=9)
    P.fill(box(M, (gcx - 1.4, 5.7, gcz + 1.2), (gcx + 1.4, 6.1, gcz + 1.4)), ['#8D5D3B'], cell=9)
    outdoor_lantern(S, P, M, gcx + 6.0, gcz + 1.6, 4.4, lit=True, power=8.0, s=0.6)
    P.fill(box(M, (gcx - 7.0, 0, gcz + 2.0), (gcx - 6.6, 2.6, gcz + 2.4)), WALNUT, cell=9)                   # the mailbox
    P.fill(box(M, (gcx - 7.6, 2.6, gcz + 1.6), (gcx - 6.0, 3.6, gcz + 2.8)), ['#C9552E', '#B8482A'], cell=9)
    fence_line(P, M, (X0, -38.0), (gcx - 5.0, gcz - 0.5))
    fence_line(P, M, (gcx + 5.0, gcz - 0.5), (X1, -36.0))
    for (vx, vz, w_) in ((6.0, -43.0, 6.0), (24.0, -44.0, 7.0), (34.0, -42.0, 5.0), (-14.0, -44.0, 6.0)):
        gable(P, M, vx - w_ / 2, vx + w_ / 2, vz - 2.0, vz + 2.0, 3.0, 2.6, PLASTER, ROOF, oh=0.5, ridge='x', wall_cell=(3, 3, 3))

    # ---- the Grove: a glade west of the nest under the big trees, a lumen tree in its middle, a ring of
    # mossy stones and two moss beds where companions rest, a flowering arch at its mouth, toadstools
    gvx, gvz = GROVE
    gr = ((X - gvx) ** 2 / 9.0 ** 2 + (Z - gvz) ** 2 / 7.0 ** 2)
    P.fill(ground & (gr <= 1.0), ['#6FA552', '#5E9646', '#7FB35F'], cell=1.0)
    P.fill(ground & (gr <= 1.0) & (noise2(M, 0.7, 0.6, 2.0) > 0.7), ['#8DBD6C'], cell=1.0)
    tree2(P, M, gvx, gvz - 3.0, 7.0, 4.6, leaves=['#7FD8C0', '#9FF0DA', '#6CC7AE', '#B8FFE8'])
    P.fill(ball(M, (gvx, 8.0, gvz - 3.0), 4.8, 0.8) & ball(M, (gvx, 8.0, gvz - 3.0), 5.0, 0.8) & (rng.random(M.m.shape) < 0.08), ['#E8FFF6'], glow=0.5, cell=9)
    S.lights.append({'type': 'point', 'pos': (gvx, 6.0, gvz - 3.0), 'power': 5.0, 'color': (0.62, 0.94, 0.85), 'radius': 1.0})
    for i in range(7):
        a = i * 2 * math.pi / 7 + 0.4
        sx_, sz_ = gvx + 7.2 * math.cos(a), gvz + 5.6 * math.sin(a)
        if a < 0.9 or a > 5.9:
            continue                                                                     # the way in stays open
        P.fill(ball(M, (sx_, 0.2, sz_), 0.9 + 0.3 * (i % 2), 0.7) & (Y >= 0), STONE, cell=0.5)
        P.fill(ball(M, (sx_, 0.7, sz_), 0.9 + 0.3 * (i % 2), 0.7) & (Y >= 0.5) & (rng.random(M.m.shape) < 0.5), MOSS, cell=0.5)
    for (bx_, bz_) in ((gvx - 4.2, gvz + 1.6), (gvx + 4.4, gvz + 1.2)):                  # the moss beds
        P.fill(ball(M, (bx_, 0.1, bz_), 2.3, 0.3) & (Y >= 0), MOSS, cell=0.5)
        P.fill(ball(M, (bx_, 0.1, bz_), 1.6, 0.35) & (Y >= 0.2), ['#8DBD6C', '#9FD47E'], cell=0.5)
    ax_, az_ = gvx + 9.5, gvz - 1.0                                                      # the arch at its mouth
    for pz in (az_ - 2.4, az_ + 2.4):
        P.fill(box(M, (ax_ - 0.3, 0, pz - 0.3), (ax_ + 0.3, 4.6, pz + 0.3)), WALNUT, cell=9)
    P.fill((np.abs(X - ax_) < 0.3) & (np.abs(Y - 4.6 - 1.4 * np.cos((Z - az_) / 2.4 * 1.5)) < 0.35) & (np.abs(Z - az_) <= 2.6), WALNUT, cell=9)
    P.fill((np.abs(X - ax_) < 0.6) & (np.abs(Y - 4.6 - 1.4 * np.cos((Z - az_) / 2.4 * 1.5)) < 0.9) & (np.abs(Z - az_) <= 2.6) & (rng.random(M.m.shape) < 0.5),
           ['#5E9646', '#6FA552', '#F5A3B5', '#FFFDF6'], cell=9)
    for (mx_, mz_) in ((gvx - 6.5, gvz - 4.5), (gvx + 5.5, gvz - 5.5), (gvx - 7.5, gvz + 4.5)):
        P.fill(cyl_y(M, (mx_, mz_), 0.25, 0, 0.9), ['#F1E6CF'], cell=9)
        P.fill(ball(M, (mx_, 1.0, mz_), 0.7, 0.5), ['#E85D4A', '#D85F51'], cell=9)
        P.fill(ball(M, (mx_, 1.0, mz_), 0.7, 0.5) & (rng.random(M.m.shape) < 0.2), ['#FFFDF6'], cell=9)

    # ---- the big tree with a bench and a lantern under it, more trees, flowers, rocks
    trees = [(-36.0, -40.0, 8, 5.0), (-37.0, 10.0, 6, 4.4), (-22.0, 32.0, 5, 3.8), (2.0, 30.0, 5, 3.4),
             (40.0, 24.0, 6, 4.6), (40.0, -24.0, 7, 4.4), (-6.0, -38.0, 7, 4.6), (-40.0, -18.0, 6, 4.2),
             (30.0, 32.0, 5, 3.6), (38.0, 8.0, 6, 4.2), (-40.0, 34.0, 6, 4.0), (14.0, 26.0, 5, 3.6), (-30.0, -34.0, 6, 4.2)]
    for (tx, tz, th_, tr) in trees:
        tree2(P, M, tx, tz, th_, tr, fruit=['#D85F51'] if tx > 30 else None)
    bx_, bz_ = 3.5, -9.0
    P.fill(box(M, (bx_ - 1.8, 1.0, bz_ - 0.6), (bx_ + 1.8, 1.5, bz_ + 0.6)), HONEY, cell=(1.5, 1, 9))
    for lx in (bx_ - 1.4, bx_ + 1.0):
        P.fill(box(M, (lx, 0, bz_ - 0.5), (lx + 0.5, 1.0, bz_ + 0.5)), WALNUT)
    P.fill(box(M, (bx_ - 1.8, 1.5, bz_ + 0.3), (bx_ + 1.8, 2.8, bz_ + 0.6)), HONEY, cell=(1.5, 9, 9))
    outdoor_lantern(S, P, M, bx_ + 3.2, bz_ - 0.5, 4.2, lit=True, power=7.0, s=0.6)
    for _ in range(36):
        fx, fz = rng.uniform(X0 + 2, X1 - 2), rng.uniform(-30, 34)
        if (gx0 - 2 < fx < gx1 + 2 and gz0 - 2 < fz < gz1 + 2) or (-27 < fx < 2 and -34 < fz < -13) or math.hypot(fx - ncx, fz - ncz) < 8.5 \
                or ((fx - gvx) ** 2 / 100 + (fz - gvz) ** 2 / 64 < 1.3) or (pr[min(int((fx - X0) * 2), M.m.shape[0] - 1), 0, min(int((fz - Z0) * 2), M.m.shape[2] - 1)] < 1.4) \
                or path[min(int((fx - X0) * 2), M.m.shape[0] - 1), 0, min(int((fz - Z0) * 2), M.m.shape[2] - 1)]:
            continue
        flower_patch(P, M, fx, fz, 1.3, 1.0, rng, n=4)
    for (rx, rz, rr) in ((-24.0, 6.0, 1.3), (38.0, 14.0, 1.1), (0.0, 22.0, 0.9), (-40.0, 4.0, 1.2), (24.0, 24.0, 1.0)):
        P.fill(ball(M, (rx, 0.2, rz), rr, 0.7) & (Y >= 0), STONE, cell=0.5)
    S.models.append((M, (), {'water': WATERC}))
    S.models.append((far_terrain(seed=43), (), {'water': WATERC}))
    S.grade = {'bloom': 0.18, 'vignette': 0.1}
    return S


# the walking camera's view of the whole home (2x: 45.8 px a unit), and a close look at the nook
VW.VIEWS['home'] = ((0.0, -2.2), 88.0, (4030, 2300))
VW.VIEWS['home_nook'] = ((-10.0, -14.0), 40.0, (1832, 1500))

if __name__ == '__main__':
    import json

    import village_scenes as VSC
    args = sys.argv[1:]
    out = args[0]
    quick = '--quick' in args
    os.makedirs(out, exist_ok=True)
    vs = scene_home_walk()
    if '--depth' in args:
        VW.render_ortho(vs, 'home', os.path.join(out, 'village_walk_home_depth.exr'), quick, depth=True)
        sys.exit(0)
    view = args[args.index('--view') + 1] if '--view' in args else 'home'
    raw = os.path.join(out, f'village_walk_{view}_raw.png')
    proj = VW.render_ortho(vs, view, raw, quick)
    VSC.finish(vs, raw, os.path.join(out, f'village_walk_{view}.png'), quick)
    json.dump(proj, open(os.path.join(out, 'village_walk_home.json'), 'w'), indent=1)

"""Sunlit Village, laid out to walk through: the Square's buildings (village_scenes.scene_square, built
by the same code) moved apart round a bigger plaza, with paths between them, the stream and bridge on
the way to the Trail Guild, the village gate south (the road home) and the Old Trail east (to the
Crossing: the mines and the Sunlit Thicket). Seen from the Lumen Wilds' map camera: orthographic,
35 degrees above the horizon, looking north, so the Evochi walks it with the same walk cycles.

    python3 village_walk.py OUT_DIR [--quick] [--view all|plaza|workshop|road] [--state day_dim|lamp_lit|waystone_restored]

Writes village_walk_<view>.png and village_walk_<view>.json (projection: px per unit, origin).
Each building is its own voxel model, built where scene_square builds it, then moved (its origin
shifted) to its place here; its lights move with it.
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from voxel import Model
from village_scenes import *          # noqa: F401,F403  (the village kit: palettes, props, builders)
from village_scenes import VScene, CPainter, box, cyl_y, ball, gable, win_front, outdoor_lantern, lantern, fence_line, \
    flower_patch, tree2, crate, barrel, bunting, fireflies2, waystone_model, far_terrain, STATE_LIGHT

PITCH = 35.0
RES = 2


# ------------------------------------------------------------------ the buildings (scene_square's code)
def glasshouse(S, P, M, rng, lamp):
    gx0, gx1, gz0, gz1 = -24.0, -11.0, -10.0, 2.0
    P.fill(box(M, (gx0, 0, gz0), (gx1, 2.0, gz1)), STONE_LT, cell=(1.5, 0.75, 1.5))
    walls = box(M, (gx0, 2.0, gz0), (gx1, 8.0, gz1)) & ~box(M, (gx0 + 0.5, 2.0, gz0 + 0.5), (gx1 - 0.5, 8.0, gz1 - 0.5))
    P.fill(walls, CLEAR_GLASS, cell=50)
    P.fill(walls & (((((M.X - gx0) % 2.5) < 0.5) & ((M.Z >= gz1 - 0.5) | (M.Z < gz0 + 0.5))) | (((M.Z - gz0) % 2.5) < 0.5) & ((M.X >= gx1 - 0.5) | (M.X < gx0 + 0.5)) | (np.abs(M.Y - 5.0) < 0.3)), SAGE, cell=9)
    zc, half = (gz0 + gz1) / 2, (gz1 - gz0) / 2 + 0.6
    topy = 8.0 + 4.0 * (1 - np.abs(M.Z - zc) / half)
    groof = (M.X >= gx0 - 0.6) & (M.X < gx1 + 0.6) & (np.abs(M.Z - zc) <= half) & (M.Y >= topy - 0.6) & (M.Y < topy) & (M.Y >= 8.0)
    P.fill(groof, CLEAR_GLASS, cell=50)
    P.fill(groof & ((((M.X - gx0) % 2.6) < 0.6) | (np.abs(M.Z - zc) < 0.6)), SAGE, cell=9)
    P.fill(box(M, (gx0 - 0.6, 7.6, gz0 - 0.6), (gx1 + 0.6, 8.2, gz1 + 0.6)) & ~box(M, (gx0 + 0.5, 7.0, gz0 + 0.5), (gx1 - 0.5, 9.0, gz1 - 0.5)), ['#43523D'], cell=9)
    for px in np.arange(gx0 + 1.6, gx1 - 1.0, 2.2):
        for pz in (gz0 + 1.6, gz1 - 1.8):
            P.fill(cyl_y(M, (px, pz), 0.6, 2.0, 3.0), TERRACOTTA, cell=9)
            P.fill(ball(M, (px, 4.0, pz), 1.1, 0.9) & (M.m == 0), LEAF, cell=0.5)
            P.fill(ball(M, (px + 0.4, 4.8, pz + 0.4), 0.4), [FLOWERS[int(px * 3) % 5]])
    P.fill(box(M, (gx1 - 0.2, 0, -5.4), (gx1 + 0.4, 5.0, -2.6)), ['#7F9871', '#6E8762'], cell=9)
    for (px, pz) in ((gx1 + 1.6, 0.6), (gx1 + 1.6, -8.0), (gx0 + 2.0, gz1 + 1.6), (gx0 + 6.0, gz1 + 1.6), (gx0 + 10.0, gz1 + 1.6)):
        P.fill(cyl_y(M, (px, pz), 0.8, 0, 1.2), TERRACOTTA, cell=9)
        P.fill(ball(M, (px, 2.0, pz), 1.2, 0.85) & (M.m == 0), LEAF, cell=0.5)
        P.fill(ball(M, (px + 0.4, 2.8, pz + 0.4), 0.45), [FLOWERS[int(abs(px * pz)) % 5]])
    flower_patch(P, M, gx0 + 6.0, gz1 + 5.0, 5.0, 1.6, rng, n=18)
    P.fill(box(M, (-17.6, 12.0, zc - 0.2), (-17.2, 14.6, zc + 0.2)), IRON, cell=9)
    P.fill(ball(M, (-17.4, 15.0, zc), 0.8), ['#FFFDF6'])
    P.fill(ball(M, (-17.4, 15.0, zc + 0.4), 0.35), ['#F4C04E'])
    outdoor_lantern(S, P, M, gx1 + 1.2, -1.4, 4.4, lit=lamp, power=8.0, s=0.6)


def workshop(S, P, M, rng, lamp):
    wx0, wx1, wz0, wz1 = 11.0, 24.0, -11.0, 1.0
    body = gable(P, M, wx0, wx1, wz0, wz1, 7.0, 5.0, BRICK, ROOF, oh=1.0, ridge='z', wall_cell=(2.0, 1.0, 2.0))
    P.fill(body & ((((M.Y) % 1.0) < 0.5) & ((M.X < wx0 + 0.5) | (M.Z >= wz1 - 0.5))) & ((np.floor(M.Y) % 2) == 0), ['#9E5A40'], cell=9)
    for (px, pz) in ((wx0, wz0), (wx0, wz1 - 0.6), (wx1 - 0.6, wz1 - 0.6)):
        P.fill(box(M, (px, 0, pz), (px + 0.6, 7.0, pz + 0.6)), WALNUT, cell=9)
    P.fill(box(M, (wx0, 6.4, wz0), (wx1, 7.0, wz1)) & ((M.X < wx0 + 0.6) | (M.Z >= wz1 - 0.6)), WALNUT, cell=9)
    win_front(P, M, wx0, 3.6, -7.6, 2.4, 2.2, lit=True, face='-x', glow=0.7)
    win_front(P, M, 19.6, 3.8, wz1, 2.4, 2.2, lit=True, glow=0.7)
    S.lights.append({'type': 'point', 'pos': (wx0 + 1.6, 3.6, -7.6), 'power': 10.0, 'color': 1900, 'radius': 1.0})
    P.fill(box(M, (wx0 - 0.5, 0, -3.8), (wx0 + 0.2, 5.0, -1.0)), WALNUT, cell=9)
    P.fill(box(M, (19.0, 7.0, -8.6), (21.4, 15.6, -6.2)), STONE, cell=(1.0, 1.0, 1.0))
    P.fill(box(M, (19.4, 15.4, -8.2), (21.0, 15.8, -6.6)), ['#FF9A4A', '#FFB65C'], glow=1.0, cell=9)
    for k in range(4):
        P.fill(ball(M, (20.2 + k * 0.6, 17.2 + k * 1.6, -7.4 - k * 0.3), 0.8 + 0.25 * k) & (M.m == 0), ['#F2F2EE', '#E6E6E2'], cell=0.5)
    awn = (M.X >= wx0 - 3.0) & (M.X < wx0) & (M.Z >= -10.0) & (M.Z < -5.0) & (np.abs(M.Y - (5.6 + (M.X - wx0) * 0.35)) < 0.3)
    P.fill(awn, ['#B76B4D'], cell=9)
    P.fill(awn & (((M.Z + 10.0) % 2.0) < 1.0), ['#F3E5C9'], cell=9)
    for (cx_, cz_, s_) in ((wx0 - 1.8, 3.4, 0.9), (wx0 - 1.6, 5.2, 0.7), (wx1 + 1.6, -2.0, 1.0)):
        crate(P, M, cx_, cz_, s_)
    barrel(P, M, wx1 + 1.8, 1.6, 1.1, 2.4)
    P.fill(box(M, (wx0 - 2.2, 5.2, 0.2), (wx0 - 1.8, 6.8, 2.2)), HONEY, cell=9)
    P.fill(box(M, (wx0 - 2.0, 6.8, 1.0), (wx0 - 0.4, 7.2, 1.4)), IRON)
    outdoor_lantern(S, P, M, wx0 - 1.4, -1.0, 4.4, lit=lamp, power=8.0, s=0.6)


def lodge(S, P, M, rng, lamp, restored=False):
    lx0, lx1, lz0, lz1 = -10.0, 10.0, -34.0, -24.0
    body = gable(P, M, lx0, lx1, lz0, lz1, 10.0, 6.0, PLASTER, ROOF, oh=1.2, ridge='x', wall_cell=(3, 3, 3))
    fr = body & (M.Z >= lz1 - 0.5) & ((((M.X - lx0) % 5.0) < 0.6) | (np.abs(M.Y - 5.0) < 0.35) | (M.Y < 0.6) | (M.Y >= 9.4))
    P.fill(fr, WALNUT, cell=9)
    P.fill(body & (M.X < lx0 + 0.6) & ((((M.Z - lz0) % 5.0) < 0.6) | (np.abs(M.Y - 5.0) < 0.35)), WALNUT, cell=9)
    P.fill(box(M, (-1.8, 0, lz1 - 0.4), (1.8, 4.4, lz1 + 0.3)), ['#5E3A24', '#6E4529'], cell=9)
    for wx in (-6.5, 6.5):
        win_front(P, M, wx, 2.6, lz1, 2.4, 2.0, lit=lamp)
        win_front(P, M, wx, 7.4, lz1, 2.4, 2.0, lit=lamp or restored)
    win_front(P, M, 0.0, 7.4, lz1, 2.0, 2.0, lit=restored)
    comp = (np.sqrt(M.X ** 2 + (M.Y - 12.4) ** 2) <= 1.1) & (M.Z >= lz1 - 1.0) & (M.Z < lz1 + 0.6)
    P.fill(comp, COPPER, cell=9)
    P.fill(comp & ((np.abs(M.X) < 0.25) | (np.abs(M.Y - 12.4) < 0.25)), BRASS)
    for bx in (-9.2, 9.2):
        ban = (np.abs(M.X - bx) <= 1.1) & (M.Y >= 3.4) & (M.Y < 9.0) & (M.Z >= lz1 + 0.1) & (M.Z < lz1 + 0.6)
        ban &= ~((M.Y < 4.4) & (np.abs(M.X - bx) < 0.5))
        P.fill(ban, NAVY, cell=9)
        P.fill(ban & (np.abs(M.Y - 7.0) < 0.5) & (np.abs(M.X - bx) < 0.6), CREAM)
    P.fill(box(M, (-3.6, 4.6, lz1), (3.6, 5.0, lz1 + 2.6)), WALNUT, cell=9)
    for px in (-3.2, 3.0):
        P.fill(box(M, (px, 0, lz1 + 2.0), (px + 0.5, 4.6, lz1 + 2.5)), WALNUT, cell=9)
    for wx in (-2.6, 2.6):
        lantern(S, P, M, (wx, 3.6, lz1 + 2.3), s=0.55, lit=lamp, power=5.0)
    P.fill(box(M, (8.6, 16.0, -29.2), (9.0, 21.0, -28.8)), IRON, cell=9)
    P.fill(box(M, (9.0, 18.8, -29.0), (12.6, 20.8, -28.8)), NAVY, cell=9)
    P.fill(box(M, (9.0, 19.6, -29.0), (12.6, 20.0, -28.8)), CREAM, cell=9)


def cottage_home(cx0, cx1, cz0, cz1, rf, wl, lit):
    def build(S, P, M, rng, lamp):
        gable(P, M, cx0, cx1, cz0, cz1, 6.0, 4.5, wl, rf, ridge='x', wall_cell=(3, 3, 3))
        P.fill(box(M, (cx0, 0, cz1 - 0.5), (cx1, 0.6, cz1)), WALNUT, cell=9)
        mid = (cx0 + cx1) / 2
        P.fill(box(M, (mid - 1.0, 0, cz1 - 0.3), (mid + 1.0, 3.6, cz1 + 0.3)), ['#6E4529'], cell=9)
        win_front(P, M, mid - 3.0, 3.0, cz1, 1.6, 1.6, lit=lit)
        win_front(P, M, mid + 3.0, 3.0, cz1, 1.6, 1.6, lit=lit)
        P.fill(box(M, (cx1 - 2.6, 6.0, cz0 + 2.0), (cx1 - 1.2, 11.0, cz0 + 3.4)), STONE, cell=9)
        flower_patch(P, M, mid, cz1 + 2.4, 3.0, 0.8, rng, n=6)
    return build


def market(S, P, M, rng, lamp):
    mx_, mz_ = -21.0, 12.0
    P.fill(box(M, (mx_ - 3.6, 2.4, mz_ - 1.6), (mx_ + 3.6, 3.0, mz_ + 1.6)), HONEY, cell=(1.5, 1, 9))
    for (px, pz) in ((mx_ - 3.4, mz_ - 1.4), (mx_ + 3.0, mz_ - 1.4), (mx_ - 3.4, mz_ + 1.0), (mx_ + 3.0, mz_ + 1.0)):
        P.fill(box(M, (px, 0, pz), (px + 0.5, 6.4, pz + 0.5)), WALNUT, cell=9)
    canopy = (np.abs(M.X - mx_) <= 4.2) & (np.abs(M.Z - mz_) <= 2.6) & (np.abs(M.Y - (6.8 - (M.Z - mz_) * 0.35)) < 0.35)
    P.fill(canopy, ['#D85F51'], cell=9)
    P.fill(canopy & ((((M.X - mx_) % 2.0) + 2.0) % 2.0 < 1.0), CREAM, cell=9)
    for k, (fx_, col) in enumerate(((-2.4, ['#D85F51', '#C94C40']), (-0.6, ['#F4C04E', '#E8B04A']), (1.2, ['#86C56A', '#6FB24E']), (2.8, ['#FF9E5A']))):
        P.fill(ball(M, (mx_ + fx_, 3.4, mz_), 0.9, 0.6) & (M.Y >= 3.0), col, cell=0.5)
    barrel(P, M, mx_ + 5.4, mz_ + 1.0, 1.1, 2.4)
    crate(P, M, mx_ - 5.0, mz_ + 1.6, 0.9)


def give_way(models):
    """Empty each model's voxels wherever a later one in the list is filled. Models may differ in res
    (the far hills are res 1, the waystone res 4): a coarse voxel gives way if any part of it is taken."""
    for a, A in enumerate(models):
        ra, sa = A.res, np.array(A.m.shape)
        for B in models[a + 1:]:
            rb, sb = B.res, np.array(B.m.shape)
            w0 = np.maximum(A.lo / ra, B.lo / rb)                    # the overlap, in world units
            w1 = np.minimum((A.lo + sa) / ra, (B.lo + sb) / rb)
            if np.any(w1 <= w0):
                continue
            i0 = np.clip(np.floor(w0 * ra).astype(int) - A.lo, 0, sa)
            i1 = np.clip(np.ceil(w1 * ra).astype(int) - A.lo, 0, sa)
            s = max(1, rb // ra)                                      # samples per axis inside one of A's voxels
            hit = np.zeros(tuple(i1 - i0), bool)
            for off in np.ndindex(s, s, s):
                ax, ok = [], []
                for d in range(3):
                    c = (A.lo[d] + np.arange(i0[d], i1[d]) + (off[d] + 0.5) / s) / ra
                    bi = np.floor(c * rb).astype(int) - B.lo[d]
                    ok.append((bi >= 0) & (bi < sb[d]))
                    ax.append(np.clip(bi, 0, sb[d] - 1))
                hit |= (B.m[np.ix_(*ax)] > 0) & ok[0][:, None, None] & ok[1][None, :, None] & ok[2][None, None, :]
            A.m[i0[0]:i1[0], i0[1]:i1[1], i0[2]:i1[2]][hit] = 0


def piece(S, lo, hi, fn, dx, dz, seed, *a):
    """Build [fn] in its own model over [lo, hi] (scene_square's coordinates), then move it by (dx, dz)."""
    M = Model(lo, hi, [], res=RES)
    P = CPainter(M, seed)
    n0 = len(S.lights)
    fn(S, P, M, np.random.default_rng(seed), *a)
    M.lo = M.lo + np.array([int(round(dx * RES)), 0, int(round(dz * RES))], np.int32)
    for L in S.lights[n0:]:
        if 'pos' in L:
            x, y, z = L['pos']
            L['pos'] = (x + dx, y, z + dz)
    S.models.append((M, CLEAR_GLASS, {'water': WATERC}))


# ------------------------------------------------------------------ the plan
# where each building goes: (scene_square's centre) -> (the walkable village's centre)
MOVE = {
    'glasshouse': (-16.0, 0.0),      # west of the plaza
    'workshop': (16.0, 0.0),         # east of the plaza
    'lodge': (0.0, -10.0),           # north, over the stream
    'market': (5.0, 12.0),           # south-west, by the road home
}
COTTAGES = [  # (scene_square's box, move) -> spread round the edges
    ((-34.0, -26.0, -36.0, -26.0, 'SLATE', 'PLASTER'), (-14.0, -10.0)),
    ((22.0, 34.0, -38.0, -28.0, 'MOSSROOF', 'CREAMWALL'), (14.0, -8.0)),
    ((26.0, 36.0, 10.0, 20.0, 'ROOF', 'PLASTER'), (12.0, 18.0)),
    ((-38.0, -30.0, -8.0, 2.0, 'SLATE', 'SANDWALL'), (-18.0, 26.0)),
]
STREAM_Z = -26.0
FORD_X = -15.0                                     # stepping stones over the stream, up to the waterfall
FALLS_DZ = -14.0                                   # the cliffs and their waterfall, brought close
CREEK = [(-24.0, -60.0), (-25.0, -52.0), (-21.5, -42.0), (-23.0, -33.0), (-21.0, -26.0)]
GATE_Z = 50.0
ROAD_EAST = [(10.0, -1.5), (26.0, -2.2)]          # plaza -> Bram's door
TRAIL_EAST = [(18.0, 6.0), (40.0, 8.0), (66.0, 4.0)]   # the Old Trail, east to the Crossing
BOUNDS = (-66.0, 66.0, -58.0, 62.0)
TREES = [(-52.0, -52.0, 8, 5.0), (-36.0, -50.0, 7, 4.6), (28.0, -52.0, 7, 4.4), (52.0, -50.0, 8, 5.0), (-58.0, -20.0, 7, 4.6),
         (58.0, -24.0, 7, 4.8), (-60.0, 6.0, 6, 4.2), (60.0, 26.0, 6, 4.4), (-56.0, 40.0, 6, 4.4), (56.0, 44.0, 6, 4.0),
         (-26.0, 40.0, 5, 3.8), (24.0, 40.0, 5, 3.6), (-20.0, -40.0, 6, 4.0), (20.0, -42.0, 6, 4.0), (-44.0, -2.0, 5, 3.6),
         (40.0, -14.0, 5, 3.6), (14.0, 24.0, 5, 3.4)]
TRAIL_LANTERNS = ((30.0, 10.5), (44.0, 9.5), (58.0, 6.5))
WELL = (15.0, 15.0)


def seg(X, Z, a, b, w):
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    t = np.clip(((X - ax) * dx + (Z - az) * dz) / (dx * dx + dz * dz), 0, 1)
    return (X - ax - t * dx) ** 2 + (Z - az - t * dz) ** 2 <= w * w


def polyline(X, Z, pts, w):
    m = np.zeros(X.shape, bool)
    for a, b in zip(pts, pts[1:]):
        m |= seg(X, Z, a, b, w)
    return m


def scene_village_walk(state='day_dim'):
    lamp = state in ('lamp_lit', 'waystone_restored')
    restored = state == 'waystone_restored'
    st = STATE_LIGHT[{'day_dim': 'day', 'lamp_lit': 'golden', 'waystone_restored': 'dusk'}[state]]
    S = VScene('village_walk_' + state, 1800, 1400, {}, world=st['world'], samples=96, transparent=True, sky=st['sky'])
    S.lights.append({'type': 'sun', **st['sun']})
    rng = np.random.default_rng(57)
    x0, x1, z0, z1 = BOUNDS
    # ---- the ground: grass, the plaza, the paths, the stream and its bridge
    G = Model((x0, -4, z0), (x1, 4, z1), [], res=RES)
    P = CPainter(G, 57)
    X2, Z2 = G.X[:, 0, :], G.Z[:, 0, :]
    R = np.sqrt(G.X ** 2 + G.Z ** 2)
    ground = (G.Y >= -1) & (G.Y < 0)
    P.fill((G.Y >= -4) & (G.Y < -1), ['#B98955', '#A97C4B'], cell=1)
    P.fill(ground, GRASS, cell=1.0)
    P.fill(ground & (np.sin(G.X * 0.37) * np.cos(G.Z * 0.29) > 0.55), ['#79A85A', '#73A255'], cell=1.0)
    sz = STREAM_Z + 1.6 * np.sin(G.X * 0.18)
    G.m[(np.abs(G.Z - sz) < 2.0) & (G.Y >= -1.0) & (G.Y < 0)] = 0
    P.fill((np.abs(G.Z - sz) >= 2.0) & (np.abs(G.Z - sz) < 2.8) & (G.Y >= -1.0) & (G.Y < 0), ['#C9C2AE', '#BDB5A0', '#B0A993'], cell=1.0)
    P.fill((np.abs(G.Z - sz) < 2.0) & (G.Y >= -1.4) & (G.Y < -0.4), WATERC, cell=1.0)
    # the creek: from the waterfall's pool (north-west, under the cliffs) down into the stream
    creek = polyline(X2, Z2, CREEK, 1.5)
    banks = polyline(X2, Z2, CREEK, 2.3) & ~creek
    G.m[creek[:, None, :] & (G.Y >= -1.0) & (G.Y < 0)] = 0
    P.fill(banks[:, None, :] & (G.Y >= -1.0) & (G.Y < 0), ['#C9C2AE', '#BDB5A0', '#B0A993'], cell=1.0)
    P.fill(creek[:, None, :] & (G.Y >= -1.4) & (G.Y < -0.4), WATERC, cell=1.0)
    for (rx_, rz_) in ((-26.5, -52.0), (-21.0, -44.0), (-23.5, -36.0)):
        P.fill(ball(G, (rx_, -0.2, rz_), 0.9, 0.6) & (G.Y >= -0.6), STONE, cell=0.5)
    # a stone ford across the stream west of the Guild: the way up to the creek and the waterfall
    fsz = STREAM_Z + 1.6 * np.sin(FORD_X * 0.18)
    ford = (np.abs(G.X - FORD_X + 0.35 * np.sin(G.Z * 1.3)) < 2.7) & (np.abs(G.Z - fsz) < 3.0) & (G.Y >= -1.4) & (G.Y < 0)
    G.m[ford] = 0
    P.fill(ford, ['#B7B1A3', '#A8A193', '#C4BEB0', '#9E978A'], cell=(1.0, 1.4, 1.0))
    P.fill(ford & (G.Y >= -0.5) & ((np.floor(G.X * 0.9) + np.floor(G.Z * 0.8)) % 3 == 0), ['#8F887C'], cell=9)
    bz = STREAM_Z
    bridge = (np.abs(G.X) < 3.0) & (np.abs(G.Z - bz) < 3.6) & (G.Y >= 0) & (G.Y < 0.6 + 0.6 * np.cos((G.Z - bz) / 3.6 * 1.4))
    P.fill(bridge & (G.Y >= 0.2 * np.cos((G.Z - bz) / 3.6 * 1.4)), HONEY, cell=(9, 1, 1.0))
    for bx in (-3.0, 2.6):
        P.fill((np.abs(G.X - bx - 0.2) < 0.3) & (np.abs(G.Z - bz) < 3.6) & (np.abs(G.Y - 1.8 - 0.6 * np.cos((G.Z - bz) / 3.6 * 1.4)) < 0.3), WALNUT, cell=9)
        for pz in (bz - 3.2, bz, bz + 3.2):
            P.fill(box(G, (bx, 0, pz - 0.3), (bx + 0.6, 2.4, pz + 0.3)), WALNUT, cell=9)
    lz1 = -24.0 + MOVE['lodge'][1]
    paths = polyline(X2, Z2, [(0.0, 9.0), (0.6, 20.0), (-0.8, 32.0), (0.4, GATE_Z + 4.0)], 2.4)          # south, home
    paths |= polyline(X2, Z2, [(0.0, -9.0), (0.0, bz - 3.0)], 2.4) | polyline(X2, Z2, [(0.0, bz + 3.0), (0.0, lz1 + 2.0)], 2.4)
    paths |= polyline(X2, Z2, [(-9.0, -1.5), (-26.0, -4.0)], 2.2)                                       # west, Mira
    paths |= polyline(X2, Z2, ROAD_EAST, 2.2)                                                           # east, Bram
    paths |= polyline(X2, Z2, [(6.0, 8.0)] + TRAIL_EAST, 2.4)                                           # the Old Trail
    paths |= polyline(X2, Z2, [(0.4, 26.0), (-13.0, 24.5)], 2.0)                                        # to the market
    paths |= polyline(X2, Z2, [(-12.5, -2.0), (-14.0, -14.0), (FORD_X, -22.5)], 1.8)                     # down to the ford
    paths |= polyline(X2, Z2, [(FORD_X, -30.0), (-15.5, -40.0), (-16.5, -50.0), (-17.5, -57.0)], 1.8)   # up to the falls
    pathm = ground & paths[:, None, :]
    P.fill(pathm, PATHC, cell=(1.0, 1, 1.0))
    plaza = ground & (R < 11.0)
    P.fill(plaza, COBBLE, cell=(1.5, 1, 1.0))
    P.fill(plaza & ((np.abs((R % 2.5) - 1.25) > 1.0)), ['#B1A893'], cell=9)
    P.fill(ground & (R >= 10.4) & (R < 11.4), ['#A89F8C', '#B4AB97'], cell=9)
    # flower beds and lamp posts round the plaza, benches, the signpost east, hay by the trail
    for a in (0.785, 2.356, 3.927, 5.498):
        bx_, bz_ = 14.0 * math.cos(a), 14.0 * math.sin(a)
        bed = ((G.X - bx_) ** 2 + (G.Z - bz_) ** 2 <= 4.0) & (G.Y >= 0) & (G.Y < 0.7)
        P.fill(bed, STONE_LT, cell=9)
        P.fill(bed & (((G.X - bx_) ** 2 + (G.Z - bz_) ** 2) < 2.6) & (G.Y >= 0.4), ['#5B4334'], cell=0.5)
        flower_patch(P, G, bx_, bz_, 1.2, 1.2, rng, n=6)
    for (bx_, bz_) in ((-7.0, 8.6), (7.2, -8.8)):
        P.fill(box(G, (bx_ - 1.8, 1.0, bz_ - 0.6), (bx_ + 1.8, 1.5, bz_ + 0.6)), HONEY, cell=(1.5, 1, 9))
        for lx in (bx_ - 1.4, bx_ + 1.0):
            P.fill(box(G, (lx, 0, bz_ - 0.5), (lx + 0.5, 1.0, bz_ + 0.5)), WALNUT)
    sx_, sz_ = 50.0, 4.0
    P.fill(box(G, (sx_ - 0.2, 0, sz_ - 0.2), (sx_ + 0.2, 3.9, sz_ + 0.2)), WALNUT, cell=9)
    for (lx0_, lx1_, y_) in ((sx_, sx_ + 3.0, 3.3), (sx_ - 2.6, sx_, 2.5)):
        P.fill(box(G, (lx0_, y_ - 0.35, sz_ - 0.2), (lx1_, y_ + 0.35, sz_ + 0.2)), HONEY, cell=9)
    for (hx, hz) in ((44.0, 13.0), (46.0, 14.4)):
        P.fill(cyl_y(G, (hx, hz), 1.2, 0, 1.6), ['#E8C766', '#DDBA58'], cell=0.5)
    # the gate south, fences either side of it
    for gx in (-3.6, 3.4):
        P.fill(box(G, (gx - 0.4 + 0.4, 0, GATE_Z - 0.4), (gx + 0.4 + 0.4, 4.6, GATE_Z + 0.4)), HONEY, cell=9)
    arch = (np.abs(G.Z - GATE_Z) <= 0.4) & (np.abs(G.Y - 4.4 - 0.6 * np.cos((G.X - 0.3) / 3.8 * 1.4)) <= 0.35) & (np.abs(G.X - 0.3) <= 4.2)
    P.fill(arch, HONEY, cell=9)
    fence_line(P, G, (x0 + 2.0, GATE_Z + 1.0), (-4.2, GATE_Z))
    fence_line(P, G, (5.0, GATE_Z), (x1 - 2.0, GATE_Z + 1.0))
    # lamp posts and the nursery lamp
    for (lx, lz) in ((10.5, 7.5), (-10.5, 7.5), (-10.5, -8.0), (10.5, -8.0)):
        outdoor_lantern(S, P, G, lx, lz, 6.0, lit=lamp, power=14.0, s=0.75)
    outdoor_lantern(S, P, G, 9.0, 14.0, 6.0, lit=lamp, power=30.0 if lamp else 0.0, s=0.95, kelvin=2400)
    keep_off = paths | (np.sqrt(X2 ** 2 + Z2 ** 2) < 13.0) | (np.abs(Z2 - STREAM_Z) < 4.0) | polyline(X2, Z2, CREEK, 3.5)
    for _ in range(70):
        fx, fz = rng.uniform(x0 + 4, x1 - 4), rng.uniform(z0 + 6, z1 - 6)
        i, k = int((fx - x0) * RES), int((fz - z0) * RES)
        if keep_off[i, k]:
            continue
        flower_patch(P, G, fx, fz, 1.4, 1.0, rng, n=4)
    # a well south-east of the plaza
    wx_, wz_ = 15.0, 15.0
    ring = ((G.X - wx_) ** 2 + (G.Z - wz_) ** 2 <= 2.2 ** 2) & ((G.X - wx_) ** 2 + (G.Z - wz_) ** 2 > 1.3 ** 2) & (G.Y >= 0) & (G.Y < 1.6)
    P.fill(ring, STONE, cell=0.5)
    P.fill(((G.X - wx_) ** 2 + (G.Z - wz_) ** 2 <= 1.3 ** 2) & (G.Y >= 0.6) & (G.Y < 1.0), WATERC, cell=9)
    for px in (wx_ - 1.9, wx_ + 1.6):
        P.fill(box(G, (px, 1.6, wz_ - 0.2), (px + 0.3, 3.9, wz_ + 0.2)), WALNUT, cell=9)
    S.models.append((G, CLEAR_GLASS, {'water': WATERC}))
    # ---- bushes along the paths, gardens by two cottages, lanterns on the Old Trail
    B = Model((x0, -1, z0), (x1, 5, z1), [], res=RES)
    PB = CPainter(B, 59)
    edge = polyline(X2, Z2, [(0.0, 12.0), (0.6, 20.0), (-0.8, 32.0), (0.4, GATE_Z - 2.0)], 4.2) & ~paths
    edge |= polyline(X2, Z2, TRAIL_EAST, 4.4) & ~paths
    ex, ez = np.nonzero(edge)
    for j in rng.choice(len(ex), size=min(34, len(ex)), replace=False):
        bx_, bz_ = ex[j] / RES + x0, ez[j] / RES + z0
        PB.fill(ball(B, (bx_, 0.4, bz_), rng.uniform(1.0, 1.6), 0.8) & (B.Y >= 0), ['#5E9646', '#6FA552', '#4F8A3C'], cell=0.5)
        if rng.random() < 0.4:
            PB.fill(ball(B, (bx_ + 0.3, 1.5, bz_ + 0.3), 0.35), [FLOWERS[int(rng.integers(5))]], cell=9)
    for (gx_, gz_) in ((-14.0 - 30.0, -36.0 + 10.0 - 10.0), (26.0 + 12.0 + 2.0, 10.0 + 18.0 - 6.0)):
        bed = box(B, (gx_ - 3.0, 0, gz_ - 2.0), (gx_ + 3.0, 0.5, gz_ + 2.0))
        PB.fill(bed, ['#6B4A34', '#5E412E'], cell=9)
        for k in range(3):
            PB.fill(box(B, (gx_ - 2.4 + k * 2.0, 0.5, gz_ - 1.4), (gx_ - 1.6 + k * 2.0, 1.2, gz_ + 1.4)), ['#7FC45E', '#6FB24E'], cell=0.5)
    S.models.append((B, ()))
    for (lx, lz) in TRAIL_LANTERNS:
        L_ = Model((int(lx) - 2, -1, int(lz) - 2), (int(lx) + 2, 9, int(lz) + 2), [], res=RES)
        outdoor_lantern(S, CPainter(L_, 60), L_, lx, lz, 4.6, lit=lamp, power=8.0, s=0.6)
        S.models.append((L_, ()))
    # ---- the buildings, moved apart
    piece(S, (-28, -1, -14), (-6, 18, 12), glasshouse, *MOVE['glasshouse'], 41, lamp)
    piece(S, (6, -1, -14), (29, 26, 8), workshop, *MOVE['workshop'], 42, lamp)
    piece(S, (-13, -1, -37), (15, 23, -19), lodge, *MOVE['lodge'], 43, lamp, restored)
    piece(S, (-28, -1, 8), (-13, 9, 16), market, *MOVE['market'], 44, lamp)
    walls = {'PLASTER': PLASTER, 'CREAMWALL': ['#E9D7B8', '#E2CEAC'], 'SANDWALL': ['#D9C8A8', '#E2D2B4']}
    roofs = {'SLATE': SLATE, 'MOSSROOF': MOSSROOF, 'ROOF': ROOF}
    for i, ((cx0, cx1, cz0, cz1, rf, wl), (dx, dz)) in enumerate(COTTAGES):
        fn = cottage_home(cx0, cx1, cz0, cz1, roofs[rf], walls[wl], restored or (lamp and cx0 > 0))
        piece(S, (int(cx0) - 2, -1, int(cz0) - 2), (int(cx1) + 2, 12, int(cz1) + 4), fn, dx, dz, 50 + i, lamp)
    S.models.append((waystone_model(S, restored, glimmer=False, power=14.0), ()))
    # ---- trees round the edges and between the buildings
    T = Model((x0, -1, z0), (x1, 21, z1), [], res=RES)
    PT = CPainter(T, 58)
    for (tx, tz, th, tr) in TREES:
        tree2(PT, T, tx, tz, th, tr, fruit=['#D85F51'] if (tx > 0 and tz > 20) else None)
    S.models.append((T, ()))
    if lamp:
        fireflies2(S, P, G, np.random.default_rng(3), 8, (7.0, 11.0), (6.0, 10.0), (12.0, 16.0), light_every=99)
    S.models.append((falls_cliff(rng), (), {'water': WATERC}))
    F = far_terrain(seed=41)
    # the creek leaves the pool through a notch in the lowest step (far_terrain's coordinates)
    ch_ = (np.abs(F.X - (-24.0 + 0.12 * (F.Z + 50.0))) < 1.6) & (F.Z > -53.0)
    F.m[ch_ & (F.Y >= 1.0)] = 0
    F.m[ch_ & (F.Y >= 0.0) & (F.Y < 1.0)] = F.mid(WATERC[0])
    # foam where the falls land, on the pool (far_terrain's coordinates: z is ours less FALLS_DZ)
    fz_ = FALLS_FACE + 2.0 - FALLS_DZ
    foam = ((F.X - FALLS_X) ** 2 / 20.0 + (F.Z - fz_) ** 2 / 5.0 <= 1.0) & (F.Y >= 1.0) & (F.Y < 3.0) & (F.Z > FALLS_FACE - FALLS_DZ)
    F.m[foam] = F.mid('#F4FBFF')
    F.m[foam & (F.Y >= 2.0) & ((np.floor(F.X) + np.floor(F.Z)) % 2 == 0)] = F.mid('#FFFFFF')
    F.lo = F.lo + np.array([0, 0, int(FALLS_DZ)], np.int32) * F.res
    S.models.append((F, (), {'water': WATERC}))
    # where two models fill the same voxel they draw coplanar faces that shade each other black: the
    # far hills give way to everything, then the ground, the bushes and the trees; the cliff wins
    rank = {id(F): 0, id(G): 1, id(B): 2, id(T): 3}
    give_way([it[0] for it in sorted(S.models, key=lambda it: rank.get(id(it[0]), 4))])
    S.grade ={'bloom': {'day_dim': 0.12, 'lamp_lit': 0.3, 'waystone_restored': 0.4}[state], 'vignette': 0.08}
    return S


FALLS_X = -24.0                     # the waterfall's middle; it drops down the cliff's face into the pool
FALLS_FACE = -78.6                  # the cliff face (z); far_terrain's falling sheet hangs just in front
CLIFF_TOP = 23.0
CLIFF_TREES = ((-36.0, -88.0), (-14.0, -90.0), (-42.0, -100.0), (-8.0, -102.0), (-30.0, -104.0))


def cliff_height(x):
    """The cliff's ledge height at x (without its small bumps)."""
    dx = abs(x - FALLS_X)
    return math.floor((CLIFF_TOP - 0.035 * max(dx - 7.0, 0.0) ** 1.7) / 2.0) * 2.0 + 1.0


def falls_cliff(rng):
    """A rock cliff behind the waterfall: stepped strata, wet dark rock round the falls, grass and trees on
    top, the stream running across the top to a notch at the lip and down the face; foam where it lands."""
    C = Model((-52, -2, -112), (4, 30, -75), [], res=RES)
    P = CPainter(C, 61)
    xs, zs = C.X[:, 0, 0], C.Z[0, 0, :]
    X2, Z2 = np.meshgrid(xs, zs, indexing='ij')
    dx = np.abs(X2 - FALLS_X)
    # height: tallest round the falls, stepping down to the sides in 2-unit ledges
    hc = CLIFF_TOP - 0.035 * np.clip(dx - 7.0, 0, None) ** 1.7
    hc = np.floor(hc / 2.0) * 2.0 + 1.0
    rough = np.floor((np.sin(X2 * 0.9) * np.cos(Z2 * 0.7) + np.sin(X2 * 0.37 + Z2 * 0.21)) * 0.8)
    face = FALLS_FACE - 0.6 - 0.9 * (np.sin(X2 * 0.8) * 0.5 + 0.5) - 0.12 * dx       # a ragged face, set back at the sides
    H = np.where(Z2 <= face, np.clip(hc + rough * 0.5, 0, None), -10)
    solid = (C.Y < H[:, None, :]) & (C.Y >= -1.0)
    top = solid & (C.Y >= H[:, None, :] - 1.0)
    strata = (np.floor(C.Y / 1.5).astype(int) % 3)
    rock = solid & ~top
    P.fill(rock & (strata == 0), ['#B9A889', '#A99877'], cell=(1.5, 1.0, 1.5))
    P.fill(rock & (strata == 1), ['#C4B597', '#B5A585'], cell=(1.5, 1.0, 1.5))
    P.fill(rock & (strata == 2), ['#9E8E70', '#A99877'], cell=(1.5, 1.0, 1.5))
    P.fill(top, ['#7FAE5F', '#86B566', '#8DBD6C'], cell=1.0)
    wet = rock & (np.abs(C.X - FALLS_X) < 5.0)
    P.fill(wet, ['#7E847C', '#6F766F', '#8A8F85'], cell=(1.0, 1.0, 1.0))           # spray-darkened rock
    moss = rock & (np.abs(C.X - FALLS_X) < 6.5) & (np.abs(C.X - FALLS_X) >= 3.4) & (np.random.default_rng(3).random(C.m.shape) < 0.25)
    P.fill(moss, ['#5E9646', '#6FA552'], cell=0.5)
    # the stream across the top, through a notch in the lip
    run = (np.abs(C.X - (FALLS_X + 1.2 * np.sin((C.Z + 80.0) * 0.18))) < 2.6) & (C.Z <= FALLS_FACE + 0.2)
    lip = H[:, None, :]
    C.m[run & (C.Y >= lip - 1.0)] = 0
    P.fill(run & (C.Y >= lip - 2.0) & (C.Y < lip - 1.0), WATERC, cell=1.0)
    # the falling water, flush with the face from the lip to the pool
    sheet = (np.abs(C.X - FALLS_X) <= 2.8) & (C.Z > FALLS_FACE - 0.4) & (C.Z <= FALLS_FACE + 0.8) & (C.Y < CLIFF_TOP - 1.5) & (C.Y >= 0)
    P.fill(sheet, ['#DFF4FC', '#BFE8FA', '#FFFFFF', '#A9DDF5'], cell=(1.0, 1.5, 1.0))
    # trees along the top, clear of the stream
    for (tx, tz) in CLIFF_TREES:
        i, k = int((tx + 52) * RES), int((tz + 112) * RES)
        ty = float(H[i, k])
        if ty > 2:
            tree2(P, C, tx, tz, 6.0, 3.8, y=ty)
    return C


VIEWS = {   # centre (x, z) and width in world units; the image height follows from the aspect
    'all': ((0.0, -28.0), 132.0, (1500, 1200)),
    'falls': ((-20.0, -72.0), 36.0, (824, 1100)),
    'plaza': ((-2.0, -4.0), 36.0, (824, 1100)),
    'workshop': ((24.0, -2.0), 36.0, (824, 1100)),
    'road': ((46.0, 2.0), 36.0, (824, 1100)),
    # the zoom study (village_mock/zoom_concept.py): the path north of the plaza at twice the detail, so
    # it can be cropped to 1x, 1.5x and 2x; and a close-up by the Guild's door for a conversation
    'zoom_hd': ((0.8, -21.7), 36.0, (1648, 2200)),
    'zoom_talk': ((-3.35, -33.2), 14.4, (824, 1100)),
    # the first playable piece (flutter/lib/features/village/village_walk.dart): the plaza, the bridge and
    # the Guild at the walking camera's detail (2x: 45.8 px a unit)
    'slice': ((0.0, -25.8), 40.0, (1832, 2200)),
    # the whole village to walk through (village_walk_full.py cuts it into tiles for the game)
    'full': ((0.0, -13.1), 132.0, (6046, 4992)),
}
DEPTH_RANGE = (-70.0, 30.0)   # world z the depth pass spans (0 -> 65535)


def render_ortho(vs, view, out_path, quick=False, depth=False):
    """[depth]: instead of the picture, each pixel's world z and height (the visible surface's), for the
    game to tell what stands in front of a character: saved as a float .npy (z, alpha, height) beside
    [out_path]."""
    import bpy
    import village_blender as VB
    from mathutils import Vector
    (cx, cz), width, (w, h) = VIEWS[view]
    VB.reset()
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    k = 0.35 if quick else 1.0
    sc.render.resolution_x, sc.render.resolution_y = int(w * k), int(h * k)
    sc.render.resolution_percentage = 100
    sc.cycles.samples = 12 if quick else int(os.environ.get('VW_SAMPLES', vs.samples))
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.02
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    sc.cycles.max_bounces = 6
    sc.cycles.diffuse_bounces = 4
    sc.cycles.sample_clamp_indirect = 6.0
    sc.render.film_transparent = vs.transparent
    sc.view_settings.view_transform = vs.view
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    if depth:
        sc.cycles.samples = 1
        sc.cycles.use_adaptive_sampling = False
        sc.cycles.use_denoising = False
        sc.cycles.filter_width = 0.01
        sc.render.film_transparent = True
        sc.view_settings.view_transform = 'Standard'
        sc.render.image_settings.file_format = 'OPEN_EXR'
        sc.render.image_settings.color_depth = '32'
    nf = 0
    for i, item in enumerate(vs.models):
        M, glass = item[0], item[1]
        opts = item[2] if len(item) > 2 else {}
        ob, n = VB.model_mesh(M, f'{vs.name}_{i}', glass, water=tuple(opts.get('water', ())))
        nf += n
    if depth:
        m = bpy.data.materials.new('world_z')
        m.use_nodes = True
        nt = m.node_tree
        for n in list(nt.nodes):
            if n.type != 'OUTPUT_MATERIAL':
                nt.nodes.remove(n)
        geo = nt.nodes.new('ShaderNodeNewGeometry')
        sep = nt.nodes.new('ShaderNodeSeparateXYZ')
        mul = nt.nodes.new('ShaderNodeMath')
        mul.operation = 'MULTIPLY'
        mul.inputs[1].default_value = -1.0 / VB.SCALE          # Blender y is -z (voxel units / SCALE)
        up = nt.nodes.new('ShaderNodeMath')
        up.operation = 'MULTIPLY'
        up.inputs[1].default_value = 1.0 / VB.SCALE           # Blender z is height
        comb = nt.nodes.new('ShaderNodeCombineXYZ')
        em = nt.nodes.new('ShaderNodeEmission')
        nt.links.new(geo.outputs['Position'], sep.inputs[0])
        nt.links.new(sep.outputs['Y'], mul.inputs[0])
        nt.links.new(sep.outputs['Z'], up.inputs[0])
        nt.links.new(mul.outputs[0], comb.inputs['X'])        # R: world z
        nt.links.new(up.outputs[0], comb.inputs['Y'])         # G: height
        nt.links.new(comb.outputs[0], em.inputs['Color'])
        em.inputs['Strength'].default_value = 1.0
        nt.links.new(em.outputs[0], nt.nodes['Material Output'].inputs['Surface'])
        bpy.context.view_layer.material_override = m
        VB.setup_world((0.0, 0.0, 0.0), 0.0)
    else:
        for L in vs.lights:
            VB.add_light(L)
        VB.setup_world(vs.world[0], vs.world[1])
    d = bpy.data.cameras.new('cam')
    d.type = 'ORTHO'
    d.ortho_scale = width * VB.SCALE
    d.sensor_fit = 'HORIZONTAL'
    d.clip_start = 0.05
    d.clip_end = 400
    ob = bpy.data.objects.new('cam', d)
    sc.collection.objects.link(ob)
    p = math.radians(PITCH)
    look = Vector((0.0, -math.sin(p), -math.cos(p)))          # voxel space: down and north
    target = Vector((cx, 0.0, cz))
    pos = target - look * 150.0
    ob.location = VB.to_blender(tuple(pos))
    v = (VB.to_blender(tuple(target)) - ob.location).normalized()
    ob.rotation_euler = v.to_track_quat('-Z', 'Y').to_euler()
    sc.camera = ob
    print(f'{vs.name}/{view}: {nf} faces, {len(vs.lights)} lights', flush=True)
    sc.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    if depth:
        import numpy as _np
        im = bpy.data.images.load(out_path)
        buf = _np.empty(im.size[0] * im.size[1] * 4, _np.float32)     # foreach_get: a Python list of a
        im.pixels.foreach_get(buf)                                    # big picture's floats runs out of memory
        px = buf.reshape(im.size[1], im.size[0], 4)[::-1]
        _np.save(out_path.rsplit('.', 1)[0] + '.npy', _np.dstack([px[..., 0], px[..., 3], px[..., 1]]))   # z, alpha, height
    # the projection: world (x, y, z) -> image px
    ppu = w / width
    return {'w': w, 'h': h, 'ppu': ppu, 'centre': [cx, cz], 'pitch': PITCH,
            'note': 'px = w/2 + (x-cx)*ppu ; py = h/2 + ((z-cz)*sin(pitch) - y*cos(pitch))*ppu'}


if __name__ == '__main__':
    import village_scenes as VSC
    args = sys.argv[1:]
    out = args[0]
    quick = '--quick' in args
    view = args[args.index('--view') + 1] if '--view' in args else 'all'
    state = args[args.index('--state') + 1] if '--state' in args else 'day_dim'
    os.makedirs(out, exist_ok=True)
    vs = scene_village_walk(state)
    if '--depth' in args:
        render_ortho(vs, view, os.path.join(out, f'village_walk_{view}_depth.exr'), quick, depth=True)
        sys.exit(0)
    raw = os.path.join(out, f'village_walk_{view}_raw.png')
    proj = render_ortho(vs, view, raw, quick)
    VSC.finish(vs, raw, os.path.join(out, f'village_walk_{view}.png'), quick)
    json.dump(proj, open(os.path.join(out, f'village_walk_{view}.json'), 'w'), indent=1)

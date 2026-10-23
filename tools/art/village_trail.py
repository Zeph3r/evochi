"""The Old Trail: out of Sunlit Village's east side along a ledge under autumn cliffs, over a stream that
falls away south in a waterfall, to the Crossing: Flint's dwelling against the rock, the mine with its
rails and cart, and the gate into the Sunlit Thicket. Built from the village's voxel kit (village_scenes
and village_walk: trees, lanterns, fences, crates, barrels, gables, water), lit and rendered the same
way, and walked with the same camera (village_walk_pack.py packs it).

    python3 village_trail.py OUT [--quick] [--depth]      # OUT/village_walk_trail[_depth].png/.npy

World: x east (0 at the village's east gate) to 128, z toward you, y up; the ledge you walk on is at 0.
"""
import math
import os
import sys

import numpy as np

import village_walk as VW
from village_scenes import (BRASS, HONEY, IRON, OAK, OAK_DARK, STATE_LIGHT, WALNUT, CPainter, VScene, ball, barrel, box,
                            crate, flower_patch, gable, lantern, tree2, win_front)
from voxel import Model

RES = 2
X0, X1, Z0, Z1 = -4.0, 130.0, -48.0, 32.0

ROCK = ['#6F6A7C', '#7C778A', '#625E70', '#86819A']        # purple-grey cliff stone
ROCK_DARK = ['#57536A', '#4D4960', '#615C72']
ROCK_LT = ['#8E8AA0', '#9A96AB']
GRASS = ['#86B566', '#7FAE5F', '#8DBD6C', '#94C26F']
GRASS_DRY = ['#A9BF5E', '#B5C565', '#9DB457']
DIRT = ['#C98B4F', '#BF8148', '#D39858', '#B97A42']
SOIL = ['#8A5A3A', '#7A4E30']
AUTUMN = (['#E08A2E', '#EB9B39', '#D3742A', '#F2B04A'],     # orange
          ['#E9B83C', '#F2CB52', '#D9A631', '#F7D96A'],     # gold
          ['#C9552E', '#D96A35', '#B8482A', '#E58040'])     # red
PINE = ['#3F7A3A', '#4A8742', '#356B33', '#53944A']
CANVAS = ['#E2B44A', '#D9A43C', '#EBC25C']
BANNER_RED = ['#B8402F', '#A9382A']
LEAF_GREEN = ['#5E9646', '#6FA552']
WATER = VW.WATERC
FALLS = ['#DFF4FC', '#BFE8FA', '#FFFFFF', '#A9DDF5']
POOL = ['#2F6FB3', '#3A7EC2', '#2A649F', '#4A8DD0']           # deep water in the basin

PATH = [(-4.0, 3.0), (12.0, 1.0), (28.0, -2.0), (44.0, 0.0), (58.0, 2.0), (72.0, -1.0), (86.0, 1.0),
        (100.0, -2.5), (114.0, -4.0), (130.0, -3.0)]
TER_H, TER_D = 6.0, 4.5   # the cliffs' terraces: each this high and this deep
STREAM_X = 44.0          # the stream comes down the cliffs here, crosses under the bridge, falls south
CROSSING = 88.0          # from here east the ledge opens into the Crossing's yard
FLINT = (103.0, -13.5)
MINE = (116.5, -26.0)    # the mine's mouth (centre of its opening, at the cliff's foot)
GATE_X = 126.0           # the Sunlit Thicket's gate
LANTERNS = ((9.0, -2.8), (31.0, 1.6), (52.0, -2.6), (70.0, 2.6), (90.0, -4.6), (110.0, -9.0))
SIGNS = ((3.0, -1.6, 'village'), (84.0, -3.8, 'crossing'))


def yard(x):
    return float(np.clip((x - CROSSING + 6) / 10, 0, 1))


def zn(x):
    """Where the north cliffs start (their foot), by x."""
    x = np.asarray(x, float)
    y = np.clip((x - CROSSING + 6) / 10, 0, 1)
    return -15.0 + 2.6 * np.sin(x * 0.07) + 1.3 * np.sin(x * 0.19 + 1.0) - 9.0 * y


def zs(x):
    """Where the ledge drops away south, by x."""
    x = np.asarray(x, float)
    y = np.clip((x - CROSSING + 6) / 10, 0, 1)
    return 9.0 + 2.6 * np.sin(x * 0.055 + 0.8) + 1.1 * np.sin(x * 0.21) + 5.0 * y


def seg(X, Z, a, b, w):
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    t = np.clip(((X - ax) * dx + (Z - az) * dz) / (dx * dx + dz * dz), 0, 1)
    return np.hypot(X - (ax + t * dx), Z - (az + t * dz)) < w


def polyline(X, Z, pts, w):
    m = np.zeros(np.broadcast(X, Z).shape, bool)
    for a, b in zip(pts, pts[1:]):
        m |= seg(X, Z, a, b, w)
    return m


def pine(P, M, x, z, h=9.0, r=3.2, y=0.0, rng=None):
    """A blocky pine: a short trunk and stacked tiers narrowing to a point."""
    rng = rng or np.random.default_rng(int(abs(x * 13 + z * 17)))
    P.fill(box(M, (x - 0.5, y, z - 0.5), (x + 0.5, y + 2.4, z + 0.5)), ['#6E4529', '#7A4E2E'], cell=(9, 1, 9))
    n = 4
    for i in range(n):
        t = i / n
        y0 = y + 1.6 + t * (h - 2.2)
        rr = r * (1 - t * 0.78)
        tier = (np.maximum(np.abs(M.X - x), np.abs(M.Z - z)) * 0.55 + np.hypot(M.X - x, M.Z - z) * 0.45 <= rr - (M.Y - y0) * 0.45) & \
               (M.Y >= y0) & (M.Y < y0 + (h - 1.6) / n + 0.8)
        P.fill(tier & (M.m == 0), PINE, cell=1.0)
    P.fill(box(M, (x - 0.5, y + h - 0.2, z - 0.5), (x + 0.5, y + h + 0.8, z + 0.5)), [PINE[1]], cell=9)


def boulder(P, M, x, z, r, y=0.0, seed=1):
    rng = np.random.default_rng(seed)
    b = np.zeros(M.m.shape, bool)
    for _ in range(3):
        c = np.array([x, y + r * 0.45, z]) + rng.uniform(-1, 1, 3) * np.array([r * 0.4, r * 0.15, r * 0.4])
        b |= (np.maximum(np.abs(M.X - c[0]), np.abs(M.Z - c[2])) <= r * rng.uniform(0.55, 0.8)) & (M.Y >= y) & (M.Y < c[1] + r * 0.4)
    P.fill(b & (M.m == 0), ROCK, cell=(1.0, 1.0, 1.0))
    top = b & ~np.roll(b, -1, 1)
    P.fill(top & (rng.random(M.m.shape) < 0.35), ['#7FAE5F', '#6FA552'], cell=0.5)


def lamp_post(S, P, M, x, z, side=1.0, h=6.0):
    """A wooden post with an arm reaching over the path and a lantern hanging from it."""
    P.fill(box(M, (x - 0.45, 0, z - 0.45), (x + 0.45, h, z + 0.45)), WALNUT, cell=(9, 1, 9))
    P.fill(box(M, (x - 0.8, 0, z - 0.8), (x + 0.8, 0.8, z + 0.8)), ROCK_DARK, cell=9)
    ax = x + side * 2.2
    P.fill(box(M, (min(x, ax) - 0.3, h - 0.7, z - 0.3), (max(x, ax) + 0.3, h - 0.1, z + 0.3)), WALNUT, cell=9)
    P.fill(box(M, (x + side * 0.4 - 0.25, h - 1.8, z - 0.25), (x + side * 1.2 + 0.25, h - 0.6, z + 0.25)), WALNUT, cell=9)    # the brace
    lantern(S, P, M, (ax, h - 2.6, z), s=0.6, lit=True, power=7.0, hang_to=h - 0.7)


def signpost(P, M, x, z, kind):
    """A post with arrow boards: west to the Village (a little house on it), east to the Crossing and the
    Mines (a pickaxe)."""
    P.fill(box(M, (x - 0.4, 0, z - 0.4), (x + 0.4, 5.6, z + 0.4)), WALNUT, cell=(9, 1, 9))
    boards = [(-1, 4.4, 'house')] if kind == 'village' else [(1, 4.6, 'pick'), (1, 3.0, 'tree')]
    for sg, y, icon in boards:
        bx0, bx1 = (x - 3.6, x + 0.6) if sg < 0 else (x - 0.6, x + 3.6)
        tip = bx0 if sg < 0 else bx1
        half = 0.75 - np.clip(sg * (M.X - tip) + 1.0, 0, 1) * 0.75     # the arrow's point
        body = (M.X >= bx0) & (M.X < bx1) & (np.abs(M.Y - y) <= half) & (M.Z >= z + 0.4) & (M.Z < z + 0.9)
        P.fill(body, HONEY, cell=(9, 1, 9))
        P.fill(body & ((np.abs(M.Y - y) > 0.45) | (np.abs(M.X - (bx0 if sg > 0 else bx1)) < 0.3)), OAK_DARK, cell=9)
        cx = (bx0 + bx1) / 2 - sg * 0.4
        mark = np.zeros(M.m.shape, bool)
        if icon == 'house':
            mark = ((np.abs(M.X - cx) < 0.5) & (M.Y >= y - 0.5) & (M.Y < y)) | ((np.abs(M.X - cx) < 0.75 - (M.Y - y)) & (M.Y >= y) & (M.Y < y + 0.6))
        elif icon == 'pick':
            mark = ((np.abs((M.X - cx) + (M.Y - y)) < 0.3) & (np.abs(M.X - cx) < 0.6)) | ((np.abs(M.Y - y - 0.45) < 0.2) & (np.abs(M.X - cx - 0.3) < 0.7))
        else:
            mark = (np.abs(M.X - cx) < 0.55 - (M.Y - y + 0.4) * 0.45) & (M.Y >= y - 0.4) & (M.Y < y + 0.6)
        P.fill(mark & (M.Z >= z + 0.85) & (M.Z < z + 1.25), ['#5A3714'], cell=9)


def fence(P, M, pts, h=2.2):
    for a, b in zip(pts, pts[1:]):
        a, b = np.array(a, float), np.array(b, float)
        L = np.linalg.norm(b - a)
        d = (b - a) / L
        rx, rz = M.X - a[0], M.Z - a[1]
        t = rx * d[0] + rz * d[1]
        perp = np.abs(-rx * d[1] + rz * d[0])
        on = (t >= 0) & (t <= L)
        for ry in (0.9, 1.8):
            P.fill(on & (perp <= 0.3) & (np.abs(M.Y - ry) <= 0.28), ['#9A6A44', '#8D5D3B'], cell=9)
        P.fill(on & (perp <= 0.45) & ((t % 2.8) < 0.9) & (M.Y >= 0) & (M.Y < h), ['#7A4E2E', '#6E4529'], cell=9)


def scene_trail(state='day_dim'):
    st = STATE_LIGHT['day']
    S = VScene('village_walk_trail', 1800, 1400, {}, world=st['world'], samples=96, transparent=True, sky=st['sky'])
    S.lights.append({'type': 'sun', **st['sun']})
    rng = np.random.default_rng(73)
    G = Model((X0, -12, Z0), (X1, 34, Z1), [], res=RES)
    P = CPainter(G, 74)
    X, Y, Z = G.X, G.Y, G.Z
    X2, Z2 = X[:, 0, :], Z[:, 0, :]
    north, south = zn(X2), zs(X2)
    # ---- the ledge: rock strata under a skin of grass, dropping away south to a lower meadow
    led = (Z2 >= north - 0.01) & (Z2 <= south)
    strata = (np.floor((Y + 12) / 1.5).astype(int) % 3)
    rock_col = (Y >= -10) & (Y < -1)
    for k, cols in enumerate((ROCK, ROCK_DARK, ROCK)):
        P.fill(led[:, None, :] & rock_col & (strata == k), cols, cell=(1.5, 1.0, 1.5))
    P.fill(led[:, None, :] & (Y >= -1) & (Y < 0), GRASS, cell=1.0)
    dry = led & (np.sin(X2 * 0.23) * np.cos(Z2 * 0.31) > 0.45)
    P.fill(dry[:, None, :] & (Y >= -1) & (Y < 0), GRASS_DRY, cell=1.0)
    low = Z2 > south
    P.fill(low[:, None, :] & (Y >= -12) & (Y < -9), GRASS, cell=1.0)
    P.fill(low[:, None, :] & (Y >= -12) & (Y < -10), SOIL, cell=1.0)
    # ---- the north cliffs: terraces stepping back and up, grass and trees on each
    back = np.clip(north - Z2, 0, None)
    hn = np.where(Z2 < north, TER_H + TER_H * np.floor(back / TER_D) + np.floor((np.sin(X2 * 0.5) + np.cos(Z2 * 0.7)) * 0.6), -99)
    hn = np.minimum(hn, 30.0)
    solid = (Y >= -10) & (Y < hn[:, None, :])
    tops = solid & (Y >= hn[:, None, :] - 1.0)
    for k, cols in enumerate((ROCK, ROCK_DARK, ROCK_LT)):
        P.fill(solid & ~tops & (strata == k), cols, cell=(1.5, 1.0, 1.5))
    P.fill(tops, GRASS, cell=1.0)
    P.fill(tops & (np.sin(X * 0.17 + Z * 0.11) > 0.6), GRASS_DRY, cell=1.0)
    moss = solid & ~tops & (rng.random(G.m.shape) < 0.06)
    P.fill(moss, ['#6FA552', '#5E9646'], cell=0.5)
    # ---- the stream: down the terraces, across the ledge under the bridge, over the edge in a waterfall
    sx = STREAM_X + 1.2 * np.sin(Z2 * 0.21)
    chan = np.abs(X2 - sx) < 2.2
    banks = (np.abs(X2 - sx) < 3.0) & ~chan
    # through the terraces: a notch with the water stepping down, sheets on each step's face
    notch = chan[:, None, :] & (Z2 < north)[:, None, :] & (Y >= hn[:, None, :] - 1.6) & (Y < hn[:, None, :])
    G.m[chan[:, None, :] & (Z2 < north)[:, None, :] & (Y >= hn[:, None, :] - 1.6)] = 0
    P.fill(notch & (Y < hn[:, None, :] - 1.0), WATER, cell=1.0)
    for k in range(6):
        zf = north - TER_D * k                   # terrace k's face (k = 0: the cliffs' foot)
        face = chan[:, None, :] & ((Z2 >= zf) & (Z2 < zf + 0.6))[:, None, :] & (Y >= TER_H * k - 1.4) & (Y < TER_H * k + TER_H - 1.0)
        P.fill(face, FALLS, cell=(1.0, 1.5, 1.0))
    # across the ledge, under the bridge, into a deep pool in a rocky basin beside the path
    bsz = float(zs(STREAM_X))
    bcz = (bsz + 3.2) / 2                                 # the basin: from the path's edge to the lip
    basin = ((X2 - STREAM_X) ** 2 / 8.0 ** 2 + (Z2 - bcz) ** 2 / ((bsz - 3.0) / 2 + 0.6) ** 2 < 1.0) & led
    onl = chan & led & ~basin
    G.m[onl[:, None, :] & (Y >= -1.0) & (Y < 0)] = 0
    P.fill(onl[:, None, :] & (Y >= -1.4) & (Y < -0.4), WATER, cell=1.0)
    P.fill((banks & led & ~basin)[:, None, :] & (Y >= -1.0) & (Y < 0), ['#C9C2AE', '#BDB5A0', '#B0A993'], cell=1.0)
    G.m[basin[:, None, :] & (Y >= -2.6)] = 0
    P.fill(basin[:, None, :] & (Y >= -3.4) & (Y < -2.0), POOL, cell=1.0)
    rim = (((X2 - STREAM_X) ** 2 / 9.2 ** 2 + (Z2 - bcz) ** 2 / ((bsz - 3.0) / 2 + 1.5) ** 2 < 1.0) & led & ~basin & ~chan)
    rh = 0.5 + 0.9 * (np.sin(X2 * 1.3) * np.cos(Z2 * 1.1) > 0.1)                      # rough, blocky stones round it
    P.fill(rim[:, None, :] & (Y >= -1.0) & (Y < rh[:, None, :]), ROCK + ROCK_DARK, cell=(1.0, 1.0, 1.0))
    P.fill(rim[:, None, :] & (Y >= rh[:, None, :] - 0.5) & (Y < rh[:, None, :]) & (rng.random(G.m.shape) < 0.3), ['#6FA552', '#7FB35F'], cell=0.5)
    # the basin's inner walls: wet dark stone down to the water
    wall = basin[:, None, :] & (Y >= -2.6) & (Y < -1.0) & ~(((X2 - STREAM_X) ** 2 / 7.2 ** 2 + (Z2 - bcz) ** 2 / ((bsz - 3.0) / 2 - 0.2) ** 2 < 1.0))[:, None, :]
    P.fill(wall & ~(chan[:, None, :] & (Z2 < bcz)[:, None, :]), ROCK_DARK, cell=1.0)
    # lily pads, a couple in flower
    for (lx, lz, fl) in ((STREAM_X - 4.0, bcz - 0.4, '#FFFDF6'), (STREAM_X - 1.6, bcz + 1.0, None), (STREAM_X + 3.4, bcz - 0.6, '#F5A3B5'),
                         (STREAM_X + 1.2, bcz - 1.4, '#FFFDF6'), (STREAM_X + 5.0, bcz + 0.8, None)):
        pad = ((X - lx) ** 2 + (Z - lz) ** 2 < 1.15 ** 2) & ~((X - lx - 0.6) ** 2 + (Z - lz - 0.3) ** 2 < 0.35 ** 2) & (Y >= -2.0) & (Y < -1.75)
        P.fill(pad, ['#4F8A3C', '#5E9646'], cell=9)
        if fl:
            P.fill(box(G, (lx - 0.25, -1.75, lz - 0.25), (lx + 0.25, -1.25, lz + 0.25)), [fl], cell=9)
    # over the lip: a wide waterfall down the ledge's face, into the pool below
    lip = south
    fall = (np.abs(X2 - STREAM_X) < 5.0)[:, None, :] & (Z2 > lip - 0.6)[:, None, :] & (Z2 <= lip + 0.5)[:, None, :] & (Y >= -9.5) & (Y < -2.0)
    G.m[fall] = 0
    P.fill(fall, FALLS, cell=(1.0, 1.5, 1.0))
    P.fill(fall & (Y >= -2.6), ['#E8F7FF', '#FFFFFF'], cell=0.5)
    pool = ((X2 - STREAM_X) ** 2 / 64 + (Z2 - (zs(STREAM_X) + 7.0)) ** 2 / 22 < 1.0) & low
    river = (np.abs(X2 - (STREAM_X + 2.0 + 0.18 * (Z2 - zs(STREAM_X) - 7))) < 2.6) & (Z2 > zs(STREAM_X) + 7) & low
    wet = pool | river
    G.m[wet[:, None, :] & (Y >= -10) & (Y < -9)] = 0
    P.fill(wet[:, None, :] & (Y >= -10.4) & (Y < -9.6), WATER, cell=1.0)
    foam = ((X2 - STREAM_X) ** 2 / 10 + (Z2 - (zs(STREAM_X) + 1.6)) ** 2 / 2.5 < 1.0) & low
    P.fill(foam[:, None, :] & (Y >= -9.6) & (Y < -9.0), ['#F4FBFF', '#FFFFFF'], cell=0.5)
    # ---- the path: warm dirt, a little worn into the grass
    pth = polyline(X2, Z2, PATH, 1.9) & led & ~chan
    P.fill(pth[:, None, :] & (Y >= -1) & (Y < 0), DIRT, cell=(1.0, 1, 1.0))
    edge = polyline(X2, Z2, PATH, 2.4) & ~polyline(X2, Z2, PATH, 1.9) & led & ~chan & (np.sin(X2 * 1.7 + Z2) > 0)
    P.fill(edge[:, None, :] & (Y >= -1) & (Y < 0), GRASS_DRY, cell=0.5)
    # the Crossing's yard: trodden dirt
    yd = led & (X2 > CROSSING) & ((X2 - 106) ** 2 / 400 + (Z2 + 10) ** 2 / 90 < 1.0)
    P.fill(yd[:, None, :] & (Y >= -1) & (Y < 0), DIRT, cell=(1.5, 1, 1.5))
    # ---- the bridge over the stream, where the path crosses
    bz = float(np.interp(STREAM_X, [p[0] for p in PATH], [p[1] for p in PATH]))
    span = (np.abs(Z - bz) < 2.6) & (np.abs(X - STREAM_X) < 3.8)
    deck = span & (Y >= 0) & (Y < 0.5 + 0.5 * np.cos((X - STREAM_X) / 3.8 * 1.3))
    P.fill(deck, HONEY, cell=(1.0, 1, 9))
    P.fill(deck & ((np.floor((X - STREAM_X + 10) / 1.0) % 2) == 0), OAK, cell=(1.0, 1, 9))
    for rz in (bz - 2.6, bz + 2.2):
        P.fill((np.abs(X - STREAM_X) < 3.8) & (np.abs(Z - rz - 0.2) < 0.25) & (np.abs(Y - 1.7 - 0.5 * np.cos((X - STREAM_X) / 3.8 * 1.3)) < 0.28),
               WALNUT, cell=9)
        for px_ in (STREAM_X - 3.6, STREAM_X, STREAM_X + 3.4):
            P.fill(box(G, (px_, 0, rz - 0.1), (px_ + 0.5, 2.3, rz + 0.5)), WALNUT, cell=9)
    S.models.append((G, (), {'water': WATER + POOL}))

    # ---- things on the ledge and the cliffs
    T = Model((X0, -12, Z0), (X1, 46, Z1), [], res=RES)
    PT = CPainter(T, 75)
    # trees on the terraces: autumn colour among pines
    for _ in range(90):
        x = rng.uniform(X0 + 2, X1 - 2)
        z = rng.uniform(Z0 + 3, float(zn(x)) - 1.5)
        if abs(x - STREAM_X) < 5 or (x > CROSSING - 4 and z > float(zn(x)) - 9):
            continue
        hb = TER_H + TER_H * math.floor((float(zn(x)) - z) / TER_D)
        hb = min(hb, 30.0)
        if (float(zn(x)) - z) % TER_D < 1.6:         # too near a terrace's edge
            continue
        if rng.random() < 0.45:
            pine(PT, T, x, z, h=rng.uniform(7, 10), r=rng.uniform(2.4, 3.2), y=hb, rng=rng)
        else:
            tree2(PT, T, x, z, h=rng.uniform(3.5, 5.0), r=rng.uniform(2.8, 3.8), y=hb, leaves=AUTUMN[rng.integers(3)], rng=rng)
    # on the lower meadow, south: a few, so the ledge has a forest below it
    for _ in range(26):
        x = rng.uniform(X0 + 2, X1 - 2)
        z = rng.uniform(float(zs(x)) + 4, Z1 - 1)
        if abs(x - STREAM_X - 2) < 8:
            continue
        if rng.random() < 0.5:
            pine(PT, T, x, z, h=rng.uniform(8, 11), r=rng.uniform(2.6, 3.4), y=-9.0, rng=rng)
        else:
            tree2(PT, T, x, z, h=rng.uniform(4.0, 5.5), r=rng.uniform(3.0, 4.2), y=-9.0, leaves=AUTUMN[rng.integers(3)], rng=rng)
    # by the path: a handful, clear of it
    for (x, z, kind) in ((6.0, -9.5, 0), (18.0, 6.5, 1), (24.0, -10.0, 2), (31.5, 7.0, 0), (36.0, -7.5, 2), (55.5, 7.4, 2), (62.0, -9.0, 1), (66.0, 7.5, 2),
                         (78.0, -8.5, 0), (82.0, 7.0, 1)):
        if kind == 2:
            pine(PT, T, x, z, h=8.5, r=2.8, rng=rng)
        else:
            tree2(PT, T, x, z, h=4.2, r=3.2, leaves=AUTUMN[kind], rng=rng)
    S.models.append((T, ()))

    D = Model((X0, -1, Z0), (X1, 14, Z1), [], res=RES)
    PD = CPainter(D, 76)
    for i, (x, z) in enumerate(LANTERNS):
        lamp_post(S, PD, D, x, z, side=1.0 if z < 0 else -1.0)
    for (x, z, kind) in SIGNS:
        signpost(PD, D, x, z, kind)
    # fences along the drop, with gaps; posts and rails like the village's
    for xa, xb in ((0.0, 20.0), (26.0, 39.0), (50.0, 68.0), (74.0, 90.0)):
        pts = [(x, float(zs(x)) - 1.3) for x in np.linspace(xa, xb, 6)]
        fence(PD, D, pts)
    for (x, z, r, sd) in ((14.0, -7.5, 1.6, 1), (33.0, 5.8, 1.3, 2), (47.5, -6.5, 1.8, 3), (59.0, 5.0, 1.2, 4), (76.0, -6.0, 1.5, 5),
                          (92.0, 8.0, 1.4, 6), (122.0, 6.0, 1.8, 7), (97.0, -18.5, 1.2, 8)):
        boulder(PD, D, x, z, r, seed=sd)
    # bushes and stones along the ledge, so the path runs through something
    for _ in range(46):
        x = rng.uniform(0, CROSSING + 30)
        z = rng.uniform(float(zn(x)) + 0.8, float(zs(x)) - 1.6)
        if abs(x - STREAM_X) < 5 or abs(z - float(np.interp(x, [p[0] for p in PATH], [p[1] for p in PATH]))) < 3.4:
            continue
        if x > CROSSING - 2 and (x - 106) ** 2 / 400 + (z + 10) ** 2 / 90 < 1.2:
            continue
        if rng.random() < 0.6:
            r = rng.uniform(0.9, 1.6)
            bush = ball(D, (x, r * 0.55, z), r, 0.75) & (D.Y >= 0)
            PD.fill(bush & (D.m == 0), ['#5E9646', '#6FA552', '#4F8A3C', '#7FB35F'] if rng.random() < 0.7 else AUTUMN[rng.integers(3)], cell=0.5)
        else:
            boulder(PD, D, x, z, rng.uniform(0.6, 1.1), seed=int(rng.integers(1000)))
    for (cx, cz) in ((12.0, 4.0), (40.0, -6.0), (64.0, 4.5), (86.0, -6.5), (112.0, 4.0)):
        flower_patch(PD, D, cx, cz, 2.6, 1.2, rng, n=7, cols=('#FFFDF6', '#F5A3B5', '#F4C04E', '#E85D4A'))
    S.models.append((D, ()))

    # ---- the Crossing: Flint's dwelling against the rock, the mine, the Thicket's gate
    C = Model((CROSSING - 4, -1, Z0 + 8), (X1, 20, 12), [], res=RES)
    PC = CPainter(C, 77)
    cz0, cz1 = float(zn(100.0)) - 6.5, float(zn(100.0)) + 0.6     # into the cliff's foot
    hx0, hx1 = 95.0, 109.0
    # clear the rock where it stands
    G.m[(np.abs(G.X - (hx0 + hx1) / 2) < (hx1 - hx0) / 2 + 0.5) & (G.Z > cz0 - 0.5) & (G.Z < cz1 + 1.0) & (G.Y >= 0)] = 0
    gable(PC, C, hx0, hx1, cz0, cz1, 6.5, 3.5, ['#B98955', '#AD7E4C', '#A47448'], ['#8E5A3C', '#7E4E33', '#9A6444'], ridge='x', wall_cell=(1, 7, 7))
    PC.fill(box(C, (hx0, 0, cz1 - 0.6), (hx1, 6.5, cz1)) & ((np.floor(C.X) % 4) == 0), WALNUT, cell=9)    # the planks' posts
    PC.fill(box(C, (hx0 - 0.4, 0, cz1 - 0.6), (hx1 + 0.4, 1.2, cz1 + 0.2)), ROCK_DARK, cell=9)            # a stone footing
    PC.fill(box(C, (101.0, 0, cz1 - 0.3), (103.4, 4.6, cz1 + 0.3)), ['#5E3A24'], cell=9)                     # the door
    win_front(PC, C, 98.0, 3.4, cz1, 1.8, 1.6, lit=True)
    win_front(PC, C, 107.0, 3.4, cz1, 1.6, 1.6, lit=True)
    # the awning: canvas from the eaves out over the workbench (the left half), on two poles
    aw = (C.X >= hx0 - 0.5) & (C.X < 100.6) & (C.Z >= cz1) & (C.Z < cz1 + 4.2)
    ay = 6.4 - (C.Z - cz1) * 0.36
    PC.fill(aw & (C.Y >= ay - 0.5) & (C.Y < ay), CANVAS, cell=(1.0, 9, 1.0))
    PC.fill(aw & (C.Y >= ay - 0.5) & (C.Y < ay) & ((np.floor(C.X / 1.5) % 2) == 0), ['#D99A33'], cell=9)
    for px_ in (hx0, 100.0):
        PC.fill(box(C, (px_, 0, cz1 + 3.6), (px_ + 0.6, 4.9, cz1 + 4.2)), WALNUT, cell=9)
    # a red banner with a pickaxe, beside the door
    bx = 104.6
    ban = (C.X >= bx) & (C.X < bx + 2.4) & (C.Y >= 2.6) & (C.Y < 6.4) & (C.Z >= cz1) & (C.Z < cz1 + 0.5)
    PC.fill(ban, BANNER_RED, cell=9)
    pick = ban & ((np.abs((C.X - bx - 1.2) + (C.Y - 4.3)) < 0.35) & (np.abs(C.X - bx - 1.2) < 0.9) |
                  (np.abs(C.Y - 5.0 - 0.25 * np.abs(C.X - bx - 1.5)) < 0.25) & (np.abs(C.X - bx - 1.5) < 0.95))
    C.set(pick & (C.Z >= cz1 + 0.25), '#F2E6C4')
    # the workbench, crates, barrels, ore set out
    PC.fill(box(C, (97.0, 2.2, cz1 + 1.2), (101.5, 2.8, cz1 + 3.2)), OAK, cell=9)
    for lx in (97.4, 101.0):
        PC.fill(box(C, (lx, 0, cz1 + 1.4), (lx + 0.5, 2.2, cz1 + 3.0)), WALNUT, cell=9)
    for (ox, oz, col) in ((98.0, cz1 + 2.0, ['#D9844A', '#B8622E']), (99.4, cz1 + 2.3, ['#C9CDD6', '#9EA4B0']), (100.6, cz1 + 1.9, ['#9FF0DA', '#6FD8C0'])):
        PC.fill(ball(C, (ox, 3.2, oz), 0.55), col, cell=0.5)
    crate(PC, C, 93.0, cz1 + 2.5, 1.0)
    crate(PC, C, 93.6, cz1 + 2.2, 0.8, y=2.0)
    crate(PC, C, 111.0, cz1 + 3.0, 1.0)
    barrel(PC, C, 91.4, cz1 + 5.0, r=1.0, h=2.4)
    barrel(PC, C, 112.8, cz1 + 5.2, r=1.0, h=2.4)
    lantern(S, PC, C, (hx0 + 0.3, 5.6, cz1 + 3.9), s=0.55, lit=True, power=6.0)
    lantern(S, PC, C, (hx1 - 0.8, 5.0, cz1 + 0.8), s=0.55, lit=True, power=6.0)
    # the mine: a mouth cut into the cliff, timbered, rails running out to a cart of ore
    mx, mz = MINE
    G.m[(np.abs(G.X - mx) < 3.2) & (G.Z < mz + 0.5) & (G.Z > mz - 14.0) & (G.Y >= 0) & (G.Y < 6.4)] = 0
    G.m[(np.abs(G.X - mx) < 4.6) & (G.Z < mz + 4.0) & (G.Z > mz - 0.5) & (G.Y >= 0) & (G.Y < 9.0)] = 0       # the cut in front
    for (fz, fh) in ((mz, 7.2), (mz - 4.0, 6.8), (mz - 8.0, 6.6)):
        for sx_ in (-1, 1):
            PC.fill(box(C, (mx + sx_ * 3.4 - 0.5, 0, fz - 0.5), (mx + sx_ * 3.4 + 0.5, fh, fz + 0.5)), ['#7A4E2E', '#6E4529'], cell=9)
        PC.fill(box(C, (mx - 4.2, fh, fz - 0.6), (mx + 4.2, fh + 1.0, fz + 0.6)), ['#7A4E2E', '#6E4529'], cell=9)
    PC.fill(box(C, (mx - 3.0, 0, mz - 13.5), (mx + 3.0, 6.4, mz - 13.0)), ['#1E1A22'], cell=9)              # the dark beyond
    lantern(S, PC, C, (mx + 2.2, 5.4, mz + 0.2), s=0.6, lit=True, power=8.0, hang_to=7.2)
    rail_z0, rail_z1 = mz - 12.0, float(zn(mx)) + 13.0
    for rx_ in (mx - 1.1, mx + 1.1):
        PC.fill(box(C, (rx_ - 0.25, 0, rail_z0), (rx_ + 0.25, 0.5, rail_z1)), IRON, cell=9)
    PC.fill((np.abs(C.X - mx) < 1.8) & (C.Z >= rail_z0) & (C.Z < rail_z1) & ((np.floor(C.Z / 1.2) % 2) == 0) & (C.Y >= 0) & (C.Y < 0.3),
            WALNUT, cell=9)
    cart_z = mz + 7.0
    PC.fill(box(C, (mx - 1.6, 0.9, cart_z - 1.8), (mx + 1.6, 3.0, cart_z + 1.8)) & ~box(C, (mx - 1.1, 1.4, cart_z - 1.3), (mx + 1.1, 3.1, cart_z + 1.3)),
            ['#5A5560', '#4C4752'], cell=9)
    for wz in (cart_z - 1.2, cart_z + 1.2):
        for wx in (mx - 1.6, mx + 1.4):
            PC.fill(box(C, (wx, 0.3, wz - 0.5), (wx + 0.3, 1.3, wz + 0.5)), IRON, cell=9)
    for (ox, oz, col) in ((mx - 0.5, cart_z - 0.6, ['#D9844A', '#B8622E']), (mx + 0.5, cart_z + 0.4, ['#D9844A', '#F0A56A']),
                          (mx, cart_z + 0.9, ['#8E8A86', '#7B7773']), (mx + 0.4, cart_z - 0.7, ['#8E8A86', '#A39E98'])):
        PC.fill(ball(C, (ox, 3.0, oz), 0.7), col, cell=0.5)
    crate(PC, C, mx + 5.6, mz + 3.0, 1.0)
    barrel(PC, C, mx - 5.6, mz + 2.4, r=1.0, h=2.4)
    # the Sunlit Thicket's gate: two posts and a beam, a green banner with a leaf
    gz = float(np.interp(GATE_X, [p[0] for p in PATH], [p[1] for p in PATH]))
    for pz in (gz - 3.6, gz + 3.0):
        PC.fill(box(C, (GATE_X - 0.6, 0, pz - 0.6), (GATE_X + 0.6, 8.6, pz + 0.6)), ['#7A4E2E', '#6E4529'], cell=9)
    PC.fill(box(C, (GATE_X - 0.7, 8.6, gz - 4.6), (GATE_X + 0.7, 9.6, gz + 4.0)), ['#7A4E2E', '#6E4529'], cell=9)
    gb = (np.abs(C.X - GATE_X + 0.9) < 0.25) & (np.abs(C.Z - gz + 0.3) < 1.6) & (C.Y >= 5.2) & (C.Y < 8.6)
    PC.fill(gb, LEAF_GREEN, cell=9)
    leaf = gb & ((C.Z - gz + 0.3) ** 2 / 0.8 + (C.Y - 6.9) ** 2 / 1.3 < 1.0)
    C.set(leaf, '#F2D35B')
    S.models.append((C, (), {'water': WATER}))
    VW.give_way([G, T, D, C])
    S.grade = {'bloom': 0.12, 'vignette': 0.06}
    return S


# the walking camera's view of the whole trail (2x: 45.8 px a unit)
VW.VIEWS['trail'] = ((63.0, -10.45), 130.0, (5954, 2748))
# a close look at the waterfall by the bridge, at the walking camera's zoom (a phone's picture)
VW.VIEWS['trail_falls'] = ((44.0, 0.0), 24.0, (824, 1100))

if __name__ == '__main__':
    import village_scenes as VSC
    args = sys.argv[1:]
    out = args[0]
    quick = '--quick' in args
    os.makedirs(out, exist_ok=True)
    vs = scene_trail()
    if '--depth' in args:
        VW.render_ortho(vs, 'trail', os.path.join(out, 'village_walk_trail_depth.exr'), quick, depth=True)
        sys.exit(0)
    view = args[args.index('--view') + 1] if '--view' in args else 'trail'
    raw = os.path.join(out, f'village_walk_{view}_raw.png')
    proj = VW.render_ortho(vs, view, raw, quick)
    VSC.finish(vs, raw, os.path.join(out, f'village_walk_{view}.png'), quick)
    import json
    json.dump(proj, open(os.path.join(out, 'village_walk_trail.json'), 'w'), indent=1)

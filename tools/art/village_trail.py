"""The Old Trail: out of Sunlit Village's east side along a ledge under autumn cliffs, over a stream that
falls away south in a waterfall, to the Crossing: Flint's camp (a tent, a fire, his tools), the mine's
stone portal dug into a hill with rails and a cart, and the gate into the Sunlit Thicket. Built from the village's voxel kit (village_scenes
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
FLINT = (101.5, -14.5)   # Flint, by his tent
MINE_X, MINE_FZ = 116.5, -16.5   # the mine's stone portal: its middle, and its front face
MINE = (MINE_X, MINE_FZ - 1.5)   # the mouth, behind the portal's arch
MINE_W = 7.5                     # the portal's half-width
ARCH_R, ARCH_JAMB = 3.5, 4.0     # the arch: its radius, and how high its sides stand before it turns
WING_FLARE, WING_L, WING_H0, WING_H1 = 0.6, 5.5, 9.0, 1.6   # the wing walls: flare, length, height at the portal and at the end
HILL = (MINE_X, -23.0, 13.0, 8.0, 13.0)   # the hill the mine is dug into: centre x, z, half-width, half-depth, height
GATE_X = 126.0           # the Sunlit Thicket's gate
LANTERNS = ((9.0, -2.8), (31.0, 1.6), (52.0, -2.6), (70.0, 2.6), (90.0, -4.6))
SIGNS = ((3.0, -1.6, 'village'), (84.0, -3.8, 'crossing'))
RAIL_END = float(np.interp(MINE_X, [p[0] for p in PATH], [p[1] for p in PATH])) - 1.5    # the rails run out to the path
CART_Z = (MINE_FZ + RAIL_END) / 2                                                       # the ore cart, halfway out
MINE_POSTS = ((MINE_X - 3.4, RAIL_END - 1.4, -1.0), (MINE_X + 3.4, RAIL_END - 1.4, 1.0))  # lamp posts either side of the rails
MINE_LAMPS = ((MINE_X - 5.25, 7.4, MINE_FZ + 0.8), (MINE_X + 5.25, 7.4, MINE_FZ + 0.8),  # on the portal, either side of the arch
              (MINE_X, 4.8, MINE_FZ - 3.0))                                              # and one hanging just inside
TENT = (95.5, -21.0, -16.0, 4.6, 3.2)      # Flint's tent: centre x, back, front, ridge height, half-width at the ground
TENT_LAMP = (TENT[0], TENT[3] - 1.3, TENT[2] + 0.55)
CAMPFIRE = (95.5, -12.6)
FLAG = (99.8, -16.4)
WHEELBARROW = (99.2, -11.0)
ORE_NODES = (('copper', 92.0, -9.5), ('copper', 89.4, -12.2), ('iron', 108.6, -12.4), ('lumen', 124.8, -12.2))   # the trail's ore
ORES = tuple((x, z) for _, x, z in ORE_NODES)


def hill_h(x, z):
    """The mine's hill, by (x, z): a broad grassy rise with a rounded top (before the portal's cut)."""
    hx, hz, rx, rz, H = HILL
    d = (np.abs((np.asarray(x, float) - hx) / rx) ** 3 + np.abs((np.asarray(z, float) - hz) / rz) ** 3) ** (1 / 3)
    base = np.clip(1 - d * d, 0, None) * 28.0
    return H * np.tanh(base / H) + 0.7 * np.sin(np.asarray(x) * 0.45) * np.cos(np.asarray(z) * 0.6) * (base > 1.0)


def _clear(x, z, r=4.5):
    """Nothing scattered within r of what you walk up to: ores, signs, lamps, Flint, the bridge, the rails."""
    pts = list(ORES) + [s[:2] for s in SIGNS] + [p[:2] for p in MINE_POSTS] + list(LANTERNS) + [FLINT, (STREAM_X, 0.0)]
    if any((x - a) ** 2 + (z - b) ** 2 < r * r for a, b in pts):
        return False
    if hill_h(x, z) > 0.2 or (abs(x - MINE_X) < 14 and MINE_FZ - 2 < z < MINE_FZ + WING_L + 1):
        return False
    if (x - 95.0) ** 2 / 100 + (z + 15.5) ** 2 / 36 < 1:     # Flint's camp
        return False
    return not (abs(x - MINE_X) < 5.5 and z < RAIL_END + 1.0)


def _trees():
    """Every tree: (kind, x, z, the ground it stands on, height, crown radius, autumn palette): on the
    cliffs' terraces autumn colour among pines, a forest on the meadow below, a handful by the path."""
    rng = np.random.default_rng(731)
    out = []
    for _ in range(90):
        x = rng.uniform(X0 + 2, X1 - 2)
        z = rng.uniform(Z0 + 3, float(zn(x)) - 1.5)
        pick, hp, rp, li = rng.random(), rng.random(), rng.random(), int(rng.integers(3))
        if abs(x - STREAM_X) < 5 or (x > CROSSING - 4 and z > float(zn(x)) - 9):
            continue
        if (float(zn(x)) - z) % TER_D < 1.6:         # too near a terrace's edge
            continue
        hb = min(TER_H + TER_H * math.floor((float(zn(x)) - z) / TER_D), 30.0)
        if pick < 0.45:
            out.append(('pine', x, z, hb, 7 + 3 * hp, 2.4 + 0.8 * rp, li))
        else:
            out.append(('tree', x, z, hb, 3.5 + 1.5 * hp, 2.8 + 1.0 * rp, li))
    for _ in range(26):
        x = rng.uniform(X0 + 2, X1 - 2)
        z = rng.uniform(float(zs(x)) + 4, Z1 - 1)
        pick, hp, rp, li = rng.random(), rng.random(), rng.random(), int(rng.integers(3))
        if abs(x - STREAM_X - 2) < 8:
            continue
        if pick < 0.5:
            out.append(('pine', x, z, -9.0, 8 + 3 * hp, 2.6 + 0.8 * rp, li))
        else:
            out.append(('tree', x, z, -9.0, 4.0 + 1.5 * hp, 3.0 + 1.2 * rp, li))
    for (x, z, kind) in ((6.0, -9.5, 0), (24.0, -10.0, 2), (36.0, -7.5, 2), (62.0, -9.0, 1), (78.0, -8.5, 0)):   # north side only: the path stays open
        out.append(('pine', x, z, 0.0, 8.5, 2.8, 0) if kind == 2 else ('tree', x, z, 0.0, 4.2, 3.2, kind))
    for (x, z, kind, h, r, li) in ((109.5, -24.5, 'tree', 3.4, 2.5, 0), (123.5, -24.0, 'tree', 3.6, 2.6, 2),
                                   (127.0, -21.0, 'pine', 6.5, 2.0, 0), (106.5, -21.5, 'pine', 6.0, 2.0, 0)):   # on the mine's hill
        out.append((kind, x, z, float(hill_h(x, z)) - 0.5, h, r, li))
    return out


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


TREES = _trees()


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
    for (kind, x, z, y, h, r, li) in TREES:
        if kind == 'pine':
            pine(PT, T, x, z, h=h, r=r, y=y, rng=rng)
        else:
            tree2(PT, T, x, z, h=h, r=r, y=y, leaves=AUTUMN[li], rng=rng)
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
    for (x, z, r, sd) in ((14.0, -7.5, 1.6, 1), (33.0, 5.8, 1.3, 2), (59.0, 5.0, 1.2, 4), (76.0, -6.0, 1.5, 5),
                          (92.0, 8.0, 1.4, 6), (122.0, 6.0, 1.8, 7), (97.0, -18.5, 1.2, 8)):
        boulder(PD, D, x, z, r, seed=sd)
    for (x, z, sd) in MINE_POSTS:                         # lamp posts where the rails meet the path
        lamp_post(S, PD, D, x, z, side=sd)
    # bushes and stones along the ledge, fewer and further from the path (room to read it on a phone)
    for _ in range(32):
        x = rng.uniform(0, CROSSING + 30)
        z = rng.uniform(float(zn(x)) + 0.8, float(zs(x)) - 1.6)
        if abs(x - STREAM_X) < 5 or abs(z - float(np.interp(x, [p[0] for p in PATH], [p[1] for p in PATH]))) < 4.4 or not _clear(x, z):
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

    # ---- the Crossing: Flint's camp (his tent, a fire, his tools out in the open) and the mine: a stone
    # portal cut into a grassy hill under the cliffs, old and overgrown, rails running out of it to the path
    C = Model((CROSSING - 4, -1, Z0 + 8), (X1, 20, 12), [], res=RES)
    PC = CPainter(C, 77)
    rngc = np.random.default_rng(78)
    mx, fz = MINE_X, MINE_FZ
    # the hill, in the ground model: rock under a skin of grass, the cut for the portal left open
    off2 = np.abs(X2 - mx)
    ww2 = MINE_W + (Z2 - fz) * WING_FLARE
    inw2 = (Z2 >= fz) & (Z2 < fz + WING_L)
    wall2 = WING_H0 - (Z2 - fz) / WING_L * (WING_H0 - WING_H1)
    hh = hill_h(X2, Z2)
    hh = np.where((Z2 >= fz - 1.5) & (Z2 < fz) & (off2 < MINE_W), 0, hh)          # where the portal stands
    hh = np.where((Z2 >= fz) & (off2 < ww2 + 1.2), 0, hh)                        # the cut and its walls
    berm = np.where(inw2 & (off2 >= ww2 + 1.2), (wall2 - 0.5) * np.clip(1 - (off2 - ww2 - 1.2) / 3.0, 0, 1), 0)
    hh = np.maximum(hh, berm)
    hs = (Y >= 0) & (Y < hh[:, None, :]) & (G.m == 0)
    htop = hs & (Y >= hh[:, None, :] - 1.0)
    for k, cols in enumerate((ROCK, ROCK_DARK, ROCK_LT)):
        P.fill(hs & ~htop & (strata == k), cols, cell=(1.5, 1.0, 1.5))
    P.fill(hs & ~htop & (rng.random(G.m.shape) < 0.14), ['#6FA552', '#5E9646', '#7FAE52'], cell=0.5)   # moss on the rock
    P.fill(htop, GRASS, cell=1.0)
    P.fill(htop & (np.sin(X * 0.31 + Z * 0.23) > 0.55), GRASS_DRY, cell=1.0)
    # the tunnel, through the hill and the cliff behind
    dxa = np.abs(X - mx)
    G.m[(dxa < ARCH_R + 0.5) & (Z < fz) & (Z > fz - 15.0) & (Y >= 0) &
        (Y < ARCH_JAMB + np.sqrt(np.clip((ARCH_R + 0.5) ** 2 - dxa ** 2, 0, None)))] = 0
    P.fill((dxa < ARCH_R + 0.5) & (Z < fz) & (Z > fz - 15.0) & (Y >= -1) & (Y < 0), ['#5A5048', '#4E463F', '#625850'], cell=0.5)   # its floor
    # gravel in the cut, and a trodden patch round Flint's camp
    cut2 = (Z2 >= fz) & (off2 < ww2) & (Z2 < fz + WING_L + 1.5) & led
    P.fill(cut2[:, None, :] & (Y >= -1) & (Y < 0), ['#A39C8E', '#ADA697', '#958E80', '#B5AE9F'], cell=0.5)
    camp2 = ((X2 - 95.0) ** 2 / 81 + (Z2 + 15.5) ** 2 / 25 < 1.0) & led
    P.fill(camp2[:, None, :] & (Y >= -1) & (Y < 0), DIRT, cell=(1.5, 1, 1.5))

    # the portal: dressed stone in courses, an arch of red voussoirs, a gable with the crossed hammer and
    # pick, a line of brass runes ("the mine") between them
    CX, CY, CZ = C.X, C.Y, C.Z
    cdx = np.abs(CX - mx)
    opening = (cdx < ARCH_R) & (CY < ARCH_JAMB + np.sqrt(np.clip(ARCH_R ** 2 - cdx ** 2, 0, None)))
    wallf = (cdx < MINE_W) & (CY >= 0) & (CY < 12.0) & (CZ >= fz - 1.5) & (CZ < fz)
    gablef = (cdx < 3.5) & (CY >= 12.5) & (CY < 17.5) & (CZ >= fz - 1.5) & (CZ < fz)
    face = (wallf | gablef) & ~opening
    course = np.floor(CY / 1.5)
    shift = (course % 2) * 1.25
    blk = np.floor((CX - shift) / 2.5)
    joint = ((CY % 1.5) < 0.5) | (((CX - shift) % 2.5) < 0.5)
    tint = ((course * 7 + blk * 13) % 4).astype(int)
    for k, col in enumerate(('#BCB5A5', '#C7C0B0', '#ADA698', '#B6AE9C')):
        PC.fill(face & ~joint & (tint == k), [col], cell=9)
    PC.fill(face & joint, ['#8C8578'], cell=9)
    PC.fill(face & (cdx >= ARCH_R) & (cdx < ARCH_R + 1.0) & (CY < ARCH_JAMB), ['#C9C2B2', '#D0C9B9'], cell=9)   # the jambs
    for (y0, half) in ((12.0, MINE_W + 0.5), (17.5, 4.0)):                                                     # cornices
        PC.fill(box(C, (mx - half, y0, fz - 2.0), (mx + half, y0 + 0.5, fz + 0.5)), ['#A8A192', '#B3AC9D'], cell=9)
    for (y0, half) in ((18.0, 2.5), (18.5, 1.5), (19.0, 0.5)):                                                 # the pediment
        PC.fill(box(C, (mx - half, y0, fz - 1.5), (mx + half, y0 + 0.5, fz)), ['#BCB5A5', '#ADA698'], cell=9)
    ry = CY - ARCH_JAMB
    rr = np.hypot(CX - mx, ry)
    ring = (rr >= ARCH_R) & (rr < ARCH_R + 1.25) & (ry >= 0) & (CZ >= fz - 1.5) & (CZ < fz + 0.5)
    seg_ = np.floor(np.arctan2(np.maximum(ry, 0), CX - mx) / (np.pi / 11)).astype(int)
    PC.fill(ring & (seg_ % 2 == 0), ['#B97A66', '#C48670'], cell=9)
    PC.fill(ring & (seg_ % 2 == 1), ['#A8685A', '#D19A84'], cell=9)
    PC.fill(ring & (seg_ == 5), ['#D8B49A'], cell=9)                                                            # the keystone
    # the tunnel's lining, and the dark far in, warm
    tun = (CZ < fz - 1.5) & (CZ >= fz - 15.0)
    lining = tun & (((cdx >= ARCH_R) & (cdx < ARCH_R + 0.5) & (CY >= 0) & (CY < ARCH_JAMB)) | ((rr >= ARCH_R) & (rr < ARCH_R + 0.5) & (ry >= 0)))
    PC.fill(lining, ['#6E675D', '#625B52', '#776F64'], cell=(1.0, 1.0, 2.0))
    PC.fill(opening & (CZ >= fz - 15.0) & (CZ < fz - 14.5) & (CY >= 0), ['#2B1F1A'], cell=9)
    v = 0.5                                                                                                     # a voxel
    RUNES = {'th': ('100', '110', '101', '110', '100'), 'e': ('101', '111', '101', '101', '101'), '.': ('0', '0', '1', '0', '0'),
             'm': ('101', '111', '111', '101', '101'), 'i': ('010',) * 5, 'n': ('010', '011', '110', '010', '010')}
    word = ('th', 'e', '.', 'm', 'i', 'n', 'e')
    wv = sum(len(RUNES[c][0]) for c in word) + len(word) - 1
    x0r, col = mx - math.floor(wv / 2) * v, 0
    for c in word:
        for j, row in enumerate(RUNES[c]):
            for i, b in enumerate(row):
                if b == '1':
                    xa, ya = x0r + (col + i) * v, 11.0 - j * v
                    PC.fill(box(C, (xa, ya, fz), (xa + v, ya + v, fz + v)), ['#D9A441', '#C8922F'], cell=9)
        col += len(RUNES[c][0]) + 1
    EMB = ('....X....', '...X.XX..', '..X...XX.', '.X.X.X.XX', 'X...X....', '...X.X...', '..X...X..', '.X.....X.')
    for j, row in enumerate(EMB):
        for i, b in enumerate(row):
            if b == 'X':
                xa, ya = mx - 2.5 + i * v, 16.5 - j * v
                PC.fill(box(C, (xa, ya, fz), (xa + v, ya + v, fz + v)), ['#3A3A42', '#46464F'], cell=9)
    # iron gates, swung open flat against the stone either side of the arch
    for sgn in (-1, 1):
        gx0, gx1 = (mx - 7.0, mx - ARCH_R) if sgn < 0 else (mx + ARCH_R, mx + 7.0)
        leaf = (CX >= gx0) & (CX < gx1) & (CZ >= fz) & (CZ < fz + 0.5) & (CY >= 0)
        colm = np.floor((CX - gx0) / 0.5)
        bars = leaf & ((colm % 2) == 0) & (CY < 6.5 + 0.5 * ((colm % 4) == 0))
        rails_ = leaf & (((CY >= 0.5) & (CY < 1.0)) | ((CY >= 3.5) & (CY < 4.0)) | ((CY >= 6.0) & (CY < 6.5)))
        PC.fill(bars | rails_, ['#33333A', '#3E3E46'], cell=9)
    # lanterns on brackets either side of the arch, one hanging inside, and a warm light deeper in
    for (lx, ly, lz) in MINE_LAMPS:
        if lz > fz:
            PC.fill(box(C, (lx - 0.25, ly + 1.4, fz), (lx + 0.25, ly + 1.9, lz + 0.25)), IRON, cell=9)
            lantern(S, PC, C, (lx, ly, lz), s=0.6, lit=True, power=11.0, hang_to=ly + 1.4)
        else:
            lantern(S, PC, C, (lx, ly, lz), s=0.6, lit=True, power=11.0, hang_to=ARCH_JAMB + ARCH_R)
    S.lights.append({'type': 'point', 'pos': (mx, 2.5, fz - 7.0), 'power': 4.0, 'color': 2200, 'radius': 0.3})
    # wing walls of rough stone, stepping down as they flare out toward you, moss on their caps
    cww = MINE_W + (CZ - fz) * WING_FLARE
    cwh = WING_H0 - (CZ - fz) / WING_L * (WING_H0 - WING_H1)
    wing = (CZ >= fz) & (CZ < fz + WING_L) & (cdx >= cww) & (cdx < cww + 1.2) & (CY >= 0) & (CY < cwh)
    PC.fill(wing, ['#8E877A', '#9A9385', '#7F786C', '#A39C8E', '#878074'], cell=(1.0, 0.5, 1.0))
    cap = wing & (CY >= cwh - 0.5)
    PC.fill(cap, ['#B5AE9F', '#A8A192'], cell=9)
    PC.fill(cap & (rngc.random(C.m.shape) < 0.45), ['#6FA552', '#5E9646', '#7FAE52'], cell=0.5)
    # age: moss creeping over the stone, cracks running down it, ivy hanging from the cornice, grass at its foot
    front = face & (CZ >= fz - 0.5)
    mossy = (np.sin(CX * 0.9 + CY * 0.5) * np.cos(CY * 1.3 - CX * 0.4) > 0.5) & ((CY < 2.5) | (CY > 10.5) | (cdx > 6.0))
    PC.fill(front & mossy & (rngc.random(C.m.shape) < 0.6), ['#6F8F4A', '#7A9A50', '#5E8A3C'], cell=0.5)
    PC.fill(wing & ((CY < 1.5) | (rngc.random(C.m.shape) < 0.08)) & (rngc.random(C.m.shape) < 0.5), ['#6F8F4A', '#5E8A3C'], cell=0.5)
    for _ in range(7):
        cx_, cy_ = rngc.uniform(mx - 7.0, mx + 7.0), rngc.uniform(3.0, 11.5)
        for _ in range(int(rngc.integers(6, 13))):
            C.set(box(C, (cx_, cy_, fz - 0.5), (cx_ + 0.5, cy_ + 0.5, fz)) & face, '#5A544B')
            cy_ -= 0.5
            cx_ += float(rngc.choice([-0.5, 0.0, 0.5]))
    for _ in range(16):
        ix, iy = mx + float(rngc.choice([-1, 1])) * rngc.uniform(5.9, 7.4), 12.0
        for _ in range(int(rngc.integers(4, 13))):
            iy -= 0.5
            ix += float(rngc.choice([-0.5, 0, 0, 0.5]))
            PC.fill(box(C, (ix, iy, fz), (ix + 0.5, iy + 0.5, fz + 0.5)) & (C.m == 0), ['#4F8A3C', '#5E9646', '#6FA552'], cell=0.5)
    for _ in range(10):                                   # ivy over the wing walls' caps
        z_ = rngc.uniform(fz, fz + WING_L - 0.5)
        sgn = float(rngc.choice([-1, 1]))
        ix = mx + sgn * (MINE_W + (z_ - fz) * WING_FLARE)
        iy = WING_H0 - (z_ - fz) / WING_L * (WING_H0 - WING_H1)
        for _ in range(int(rngc.integers(2, 7))):
            iy -= 0.5
            PC.fill(box(C, (ix - 0.5 * (sgn > 0), iy, z_), (ix + 0.5 * (sgn < 0), iy + 0.5, z_ + 0.5)) & (C.m == 0),
                    ['#4F8A3C', '#5E9646'], cell=0.5)
    near = (((CZ >= fz) & (CZ < fz + 1.0) & (cdx >= ARCH_R + 0.6) & (cdx < MINE_W)) |
            ((CZ >= fz) & (CZ < fz + WING_L) & (cdx >= cww - 0.8) & (cdx < cww)))
    PC.fill(near & (CY >= 0) & (CY < 0.5 + 0.5 * (rngc.random(C.m.shape) < 0.4)) & (C.m == 0) & (rngc.random(C.m.shape) < 0.4),
            ['#6FA552', '#7FB35F', '#5E9646'], cell=0.5)
    for (bx_, bz_, r) in ((mx - 9.6, fz + 0.9, 1.2), (mx + 9.7, fz + 1.3, 1.3), (mx - 11.8, fz + 4.2, 1.0), (mx + 12.0, fz + 3.9, 1.1),
                          (mx - 6.0, fz - 3.0, 1.4), (mx + 6.4, fz - 3.4, 1.3), (mx - 2.6, fz - 4.6, 1.1)):
        by = float(hh[int((bx_ - X0) * RES), int((bz_ - Z0) * RES)])
        PC.fill(ball(C, (bx_, by + r * 0.4, bz_), r, 0.75) & (CY >= by - 0.5) & (C.m == 0),
                ['#5E9646', '#6FA552', '#4F8A3C', '#7FB35F'] if bz_ > fz else AUTUMN[1], cell=0.5)
    for (sx_, sz_, r) in ((mx - 7.8, fz + 2.6, 0.5), (mx + 8.4, fz + 3.4, 0.75), (mx - 9.0, fz + 4.8, 0.5)):    # stones fallen from the walls
        PC.fill(box(C, (sx_ - r, 0, sz_ - r), (sx_ + r, 2 * r, sz_ + r)), ['#8E877A', '#9A9385'], cell=9)
    # rails out of the tunnel to the path, a cart of ore halfway
    rail_z0, rail_z1 = fz - 13.0, RAIL_END
    for rx_ in (mx - 1.1, mx + 1.1):
        PC.fill(box(C, (rx_ - 0.25, 0, rail_z0), (rx_ + 0.25, 0.5, rail_z1)), IRON, cell=9)
    PC.fill((np.abs(CX - mx) < 1.8) & (CZ >= rail_z0) & (CZ < rail_z1) & ((np.floor(CZ / 1.2) % 2) == 0) & (CY >= 0) & (CY < 0.3),
            WALNUT, cell=9)
    cart_z = CART_Z
    PC.fill(box(C, (mx - 1.6, 0.9, cart_z - 1.8), (mx + 1.6, 3.0, cart_z + 1.8)) & ~box(C, (mx - 1.1, 1.4, cart_z - 1.3), (mx + 1.1, 3.1, cart_z + 1.3)),
            ['#5A5560', '#4C4752'], cell=9)
    for wz in (cart_z - 1.2, cart_z + 1.2):
        for wx in (mx - 1.6, mx + 1.4):
            PC.fill(box(C, (wx, 0.3, wz - 0.5), (wx + 0.5, 1.3, wz + 0.5)), IRON, cell=9)
    for (ox, oz, col) in ((mx - 0.5, cart_z - 0.6, ['#D9844A', '#B8622E']), (mx + 0.5, cart_z + 0.4, ['#D9844A', '#F0A56A']),
                          (mx, cart_z + 0.9, ['#8E8A86', '#7B7773']), (mx + 0.4, cart_z - 0.7, ['#8E8A86', '#A39E98'])):
        PC.fill(ball(C, (ox, 3.0, oz), 0.7), col, cell=0.5)

    # Flint's camp: an A-frame tent with its flaps tied back, a lantern at the door, a fire ringed with stones
    tx, tz0, tz1, th, tw = TENT
    half = tw * (1 - CY / th)
    shell = (np.abs(CX - tx) <= half) & (np.abs(CX - tx) > half - 0.75) & (CY >= 0) & (CY < th) & (CZ >= tz0) & (CZ < tz1)
    PC.fill(shell, ['#D8CBA4', '#CDBF98', '#E2D6B2'], cell=(9, 1.0, 1.0))
    PC.fill(shell & (CZ >= tz1 - 1.0), ['#C2B289', '#B8A87F'], cell=9)                 # the door flaps, tied back
    PC.fill(shell & (CY < 0.6), ['#A9583A', '#B8643F'], cell=9)                        # a red hem
    PC.fill((np.abs(CX - tx) <= half) & (CY >= 0) & (CY < th) & (CZ >= tz0) & (CZ < tz0 + 0.5), ['#CDBF98'], cell=9)
    PC.fill((np.abs(CX - tx) <= half - 0.5) & (CY >= 0) & (CY < th - 0.6) & (CZ >= tz0 + 0.5) & (CZ < tz0 + 1.0), ['#4A3828'], cell=9)
    PC.fill(box(C, (tx - 1.5, 0, tz0 + 1.0), (tx + 1.0, 0.5, tz0 + 3.5)), ['#7A5A8C', '#6B4E7C'], cell=9)        # a bedroll
    PC.fill(box(C, (tx - 0.25, 0, tz1 - 0.5), (tx + 0.25, th + 0.5, tz1)), WALNUT, cell=9)                     # the door pole
    PC.fill(box(C, (tx - 0.25, th - 0.5, tz0), (tx + 0.25, th, tz1 + 1.0)), WALNUT, cell=9)                    # the ridge, out over the door
    lantern(S, PC, C, TENT_LAMP, s=0.5, lit=True, power=6.0, hang_to=th - 0.5)
    cfx, cfz = CAMPFIRE
    for k in range(8):
        a = k * np.pi / 4
        sx_, sz_ = cfx + 1.15 * np.cos(a), cfz + 1.15 * np.sin(a)
        PC.fill(box(C, (sx_ - 0.3, 0, sz_ - 0.3), (sx_ + 0.3, 0.5, sz_ + 0.3)), ROCK + ROCK_DARK, cell=9)
    PC.fill(box(C, (cfx - 0.75, 0, cfz - 0.25), (cfx + 0.75, 0.5, cfz + 0.25)), WALNUT, cell=9)
    PC.fill(box(C, (cfx - 0.25, 0.5, cfz - 0.75), (cfx + 0.25, 1.0, cfz + 0.75)), ['#6E4529'], cell=9)
    flame = (np.hypot(CX - cfx, CZ - cfz) < 0.75 * (1 - (CY - 0.5) / 1.5)) & (CY >= 0.5) & (CY < 2.0) & (C.m == 0)
    PC.fill(flame, ['#FFB03A', '#FF8A2A', '#FFD45A'], cell=0.5, glow=0.9)
    S.lights.append({'type': 'point', 'pos': (cfx, 1.4, cfz), 'power': 5.0, 'color': 1900, 'radius': 0.4})
    # his flag on a pole: red, with a pickaxe
    fgx, fgz = FLAG
    PC.fill(box(C, (fgx - 0.25, 0, fgz - 0.25), (fgx + 0.25, 6.8, fgz + 0.25)), WALNUT, cell=9)
    PC.fill(box(C, (fgx, 6.0, fgz - 0.25), (fgx + 2.9, 6.5, fgz + 0.25)), WALNUT, cell=9)
    bx = fgx + 0.3
    ban = (CX >= bx) & (CX < bx + 2.4) & (CY >= 2.6) & (CY < 6.0) & (CZ >= fgz - 0.25) & (CZ < fgz + 0.25)
    PC.fill(ban, BANNER_RED, cell=9)
    C.set(ban & ((np.abs((CX - bx - 1.2) + (CY - 4.1)) < 0.35) & (np.abs(CX - bx - 1.2) < 0.9) |
                 (np.abs(CY - 4.8 - 0.25 * np.abs(CX - bx - 1.5)) < 0.25) & (np.abs(CX - bx - 1.5) < 0.95)), '#F2E6C4')
    # his workbench with ore set out, a rack of picks and shovels, a grindstone, a wheelbarrow of copper
    PC.fill(box(C, (99.5, 2.2, -20.4), (103.0, 2.8, -18.6)), OAK, cell=9)
    for lx in (99.8, 102.4):
        PC.fill(box(C, (lx, 0, -20.2), (lx + 0.5, 2.2, -18.8)), WALNUT, cell=9)
    for (ox, oz, col) in ((100.3, -19.4, ['#D9844A', '#B8622E']), (101.4, -19.6, ['#C9CDD6', '#9EA4B0']), (102.4, -19.3, ['#9FF0DA', '#6FD8C0'])):
        PC.fill(ball(C, (ox, 3.2, oz), 0.55), col, cell=0.5)
    rz = -19.2
    for px_ in (86.6, 91.4):
        PC.fill(box(C, (px_, 0, rz - 0.25), (px_ + 0.5, 3.4, rz + 0.25)), WALNUT, cell=9)
    PC.fill(box(C, (86.6, 2.8, rz - 0.25), (91.9, 3.3, rz + 0.25)), WALNUT, cell=9)
    for hx_ in (87.6, 88.7):                              # picks, heads up
        PC.fill(box(C, (hx_, 0, rz + 0.25), (hx_ + 0.5, 3.4, rz + 0.75)), OAK, cell=9)
        PC.fill(box(C, (hx_ - 0.5, 3.4, rz + 0.25), (hx_ + 1.0, 3.9, rz + 0.75)), IRON, cell=9)
        PC.fill(box(C, (hx_ - 1.0, 3.0, rz + 0.25), (hx_ - 0.5, 3.5, rz + 0.75)), IRON, cell=9)
    for hx_ in (89.6, 90.6):                              # shovels, blades down
        PC.fill(box(C, (hx_, 1.0, rz + 0.25), (hx_ + 0.5, 3.8, rz + 0.75)), OAK, cell=9)
        PC.fill(box(C, (hx_ - 0.25, 0, rz + 0.25), (hx_ + 0.75, 1.2, rz + 0.75)), ['#8E949E', '#7C828C'], cell=9)
    gx_, gz_ = 90.0, -15.4
    wheel = ((CX - gx_) ** 2 + (CY - 1.7) ** 2 < 1.05 ** 2) & (CZ >= gz_ - 0.25) & (CZ < gz_ + 0.25)
    PC.fill(wheel, ['#A39D90', '#958F83'], cell=0.5)
    PC.fill(wheel & ((CX - gx_) ** 2 + (CY - 1.7) ** 2 < 0.3 ** 2), IRON, cell=9)
    for pz in (gz_ - 0.75, gz_ + 0.75):
        PC.fill(box(C, (gx_ - 0.25, 0, pz - 0.25), (gx_ + 0.25, 1.9, pz + 0.25)), WALNUT, cell=9)
    PC.fill(box(C, (gx_ - 0.25, 1.45, gz_ - 1.0), (gx_ + 0.25, 1.95, gz_ + 1.0)), IRON, cell=9)
    wbx, wbz = WHEELBARROW
    PC.fill(box(C, (wbx - 1.2, 0.9, wbz - 0.8), (wbx + 1.2, 1.9, wbz + 0.8)) & ~box(C, (wbx - 0.7, 1.4, wbz - 0.3), (wbx + 0.7, 2.0, wbz + 0.3)),
            ['#6B7A55', '#5F6E4B'], cell=9)
    PC.fill(((CX - (wbx - 1.6)) ** 2 + (CY - 0.6) ** 2 < 0.65 ** 2) & (CZ >= wbz - 0.25) & (CZ < wbz + 0.25), ['#4A3020'], cell=9)
    for hz in (wbz - 0.75, wbz + 0.25):
        PC.fill(box(C, (wbx + 1.2, 1.0, hz), (wbx + 2.8, 1.5, hz + 0.5)), WALNUT, cell=9)
        PC.fill(box(C, (wbx + 0.5, 0, hz), (wbx + 1.0, 0.9, hz + 0.5)), WALNUT, cell=9)
    for (ox, oz) in ((wbx - 0.3, wbz - 0.2), (wbx + 0.3, wbz + 0.15), (wbx, wbz)):
        PC.fill(ball(C, (ox, 2.0, oz), 0.5), ['#D9844A', '#B8622E'], cell=0.5)
    crate(PC, C, 86.8, -16.2, 1.0)
    crate(PC, C, 87.1, -16.3, 0.8, y=2.0)
    barrel(PC, C, 87.2, -13.4, r=0.9, h=2.2)
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
# a close look at the Crossing: Flint's camp and the mine's portal (for checking)
VW.VIEWS['trail_mine'] = ((106.0, -16.0), 44.0, (2016, 1600))

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

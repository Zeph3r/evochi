"""Fernlight Wood: the old forest between the Old Trail and the Sunlit Thicket, still untouched by the
Hollow. You come in over a wooden bridge across a brook at its south edge; a path winds north through tall
green trees, ferns and mossy stones, past a meadow of wildflowers and a pond with lily pads under a little
waterfall, to the Thicket's way in: two ancient trees grown together into an arch over the path, and past it
the dark of the Hollow's tangle, its violet light just showing. Butterflies, fireflies, pollen and calm
creatures are the game's (the living scene, and the critters the walk screen sets wandering).

Built from the village's voxel kit, lit and rendered the same way, walked with the same camera
(village_walk_pack.py packs it).

    python3 fern_wood.py OUT [--quick] [--depth]      # OUT/village_walk_wood[_depth].png/.npy

World: x east, z toward you, y up; the ground you walk on is at 0.
"""
import math
import os
import sys

import numpy as np

import village_walk as VW
from village_scenes import (HONEY, IRON, OAK, STATE_LIGHT, WALNUT, CPainter, VScene, ball, box, cyl_y, flower_patch, lantern,
                            tree2)
from village_trail import boulder, pine, polyline
from voxel import Model

RES = 2
X0, X1, Z0, Z1 = -4.0, 92.0, -64.0, 28.0

GRASS = ['#6FAF52', '#79B85A', '#66A64B', '#82C062']
GRASS_DEEP = ['#5C9A44', '#57923F', '#62A049']
MOSS = ['#5E9646', '#6FA552', '#4F8A3C']
DIRT = ['#B98552', '#AD7A48', '#C4915C', '#A77446']
SOIL = ['#7A4E30', '#6B4530']
BANK = ['#8A6A4A', '#7C5E40', '#94744F']
STONE = ['#9A9588', '#8B867A', '#A6A194', '#7F7A6F']
STONE_MOSS = ['#7E9A5E', '#6F8C52']
WATER = VW.WATERC
POOL = ['#3E86C0', '#4A93CC', '#357AB2', '#5AA2D6']
LILY = ['#5EA046', '#4F9140', '#6CB050']
LEAVES = (['#5E9646', '#6FA552', '#4F8A3C', '#7FB860'],     # oak green
          ['#4A8742', '#3F7A3A', '#53944A', '#62A050'],     # deep green
          ['#7FB35F', '#8CC06A', '#6FA552', '#9ACB74'])     # spring green
BIRCH_LEAF = ['#A4CF6C', '#B5DA7A', '#93C25F', '#C2E388']
BIRCH = ['#EDEAE0', '#E2DED2', '#F4F1E8']
FERN = ['#4F9A42', '#5DAA4B', '#448A39', '#6DB857']
HOLLOW = ['#B47CFF', '#9C5CF0', '#C9A0FF']
HOLLOW_LEAF = ['#2F4A33', '#3E5A3C', '#35404F', '#4E3A6E', '#2B3D30', '#36503A']
FLOWERS = ('#FFFDF6', '#F5A3B5', '#F4C04E', '#E8E0FF', '#FF9F7A', '#B8D8FF')

# the brook along the south edge, and the bridge you come in over
BROOK_W = 2.4


def brook_z(x):
    return 19.0 + 1.6 * np.sin(np.asarray(x, float) * 0.11 + 0.6) + 0.8 * np.sin(np.asarray(x, float) * 0.29)


BRIDGE_X = 14.0
BRIDGE = (BRIDGE_X, float(brook_z(BRIDGE_X)))
# the path north: from the bridge, round the meadow and the pond, to the arch
PATH = [(BRIDGE_X, Z1), (BRIDGE_X, 22.0), (15.0, 14.0), (21.0, 6.0), (30.0, 1.0), (38.0, -6.0), (41.0, -15.0),
        (36.0, -24.0), (36.5, -34.0), (43.0, -42.0), (48.0, -48.0), (48.0, -58.0)]
PATH_W = 1.9
POND = (66.0, -6.0, 11.0, 7.5)          # centre x, z, half-width, half-depth
FALLS = (68.0, -14.5)                   # the little falls into the pond, off the rocks behind it
MEADOW = (22.0, -27.0, 10.0, 7.0)
ARCH_X, ARCH_Z = 48.0, -53.0            # the Thicket's way in: the arch's middle, over the path
ARCH_HALF, ARCH_TOP = 5.2, 12.0         # its trunks stand this far either side; it closes this high
LANTERNS = ((17.5, 10.0), (34.0, -3.5), (44.0, -12.0), (39.5, -31.0), (44.5, -46.0))
SIGN = (11.0, 15.0)                     # "Fernlight Wood", by the bridge
BENCH = (58.0, 2.0)                     # a log bench by the pond


def _near_path(x, z, w):
    return bool(polyline(np.array([x]), np.array([z]), PATH, w)[0])


def _clear(x, z):
    """Nothing big stands on the path, in the pond, on the meadow, under the arch or by the lanterns."""
    if _near_path(x, z, PATH_W + 3.2):
        return False
    px, pz, rx, rz = POND
    if ((x - px) / (rx + 3.5)) ** 2 + ((z - pz) / (rz + 3.5)) ** 2 < 1:
        return False
    mx, mz, mrx, mrz = MEADOW
    if ((x - mx) / mrx) ** 2 + ((z - mz) / mrz) ** 2 < 1:
        return False
    if abs(x - ARCH_X) < ARCH_HALF + 6 and z < ARCH_Z + 7:
        return False
    if abs(z - float(brook_z(x))) < BROOK_W + 2.5:
        return False
    if any((x - a) ** 2 + (z - b) ** 2 < 16 for a, b in LANTERNS + (SIGN, BENCH)):
        return False
    return True


def _path_pts(step=1.0):
    pts = []
    for (ax, az), (bx, bz) in zip(PATH, PATH[1:]):
        n = max(1, int(math.hypot(bx - ax, bz - az) / step))
        pts += [(ax + (bx - ax) * i / n, az + (bz - az) * i / n) for i in range(n)]
    return pts + [PATH[-1]]


PATH_PTS = _path_pts()


def _hides(x, z, h, r):
    """would a tree here stand in front of the path or the pond (seen from the walking camera, it rises up
    the screen over what is behind it)?"""
    reach = (h + r * 1.6) * 1.43 + r
    for (px, pz) in PATH_PTS + [(POND[0] + dx, POND[1] - POND[3] * 0.6) for dx in (-6, -3, 0, 3, 6)]:
        if abs(px - x) < r + PATH_W + 0.8 and -r - PATH_W - 1.0 < z - pz < reach:
            return True
    return False


def _trees():
    """(kind, x, z, height, crown, palette): tall greens through the wood (none in front of the path, so it
    stays in view), birches by the meadow and the pond, a few pines at the back; past the arch, the Hollow's
    tangle."""
    rng = np.random.default_rng(1207)
    out = []
    tries = 0
    while len(out) < 52 and tries < 8000:
        tries += 1
        x = rng.uniform(X0 + 1, X1 - 1)
        z = rng.uniform(Z0 + 8, Z1 - 3)
        if z < ARCH_Z - 2 and abs(x - ARCH_X) < 22:
            continue
        if (x - ARCH_X) ** 2 + (z - ARCH_Z) ** 2 < 15 ** 2:
            continue                                   # the arch stands clear
        pick = rng.random()
        near_open = ((x - POND[0]) ** 2 + (z - POND[1]) ** 2 < 420) or ((x - MEADOW[0]) ** 2 + (z - MEADOW[1]) ** 2 < 330)
        if near_open and pick < 0.55:
            t = ('birch', x, z, 6.0 + 2.0 * rng.random(), 2.4 + 0.7 * rng.random(), 0)
        elif z < -30 and pick < 0.3:
            t = ('pine', x, z, 9.0 + 3.0 * rng.random(), 2.6 + 0.7 * rng.random(), 0)
        else:
            t = ('tree', x, z, 4.5 + 2.0 * rng.random(), 3.0 + 1.1 * rng.random(), int(rng.integers(3)))
        if not _clear(x, z) or _hides(x, z, t[3], t[4]) or any((x - o[1]) ** 2 + (z - o[2]) ** 2 < (t[4] + o[4] + 0.5) ** 2 for o in out):
            continue
        out.append(t)
    # the Hollow's tangle beyond the arch: dark trees closing in along the wood's north edge
    for (x, z, h, r) in ((ARCH_X - 11.0, ARCH_Z - 7.0, 5.4, 3.8), (ARCH_X - 4.0, ARCH_Z - 9.5, 6.0, 4.0), (ARCH_X + 4.5, ARCH_Z - 9.0, 5.6, 3.8),
                         (ARCH_X + 11.5, ARCH_Z - 6.5, 5.0, 3.6), (ARCH_X - 17.5, ARCH_Z - 4.5, 5.0, 3.4), (ARCH_X + 18.0, ARCH_Z - 4.0, 5.2, 3.5)):
        out.append(('hollow', x, z, h, r, 0))
    # and a wall of green along the rest of the north edge, two deep, so the wood goes on past the map
    for row, z in enumerate((-58.5, -62.0)):
        for x in np.arange(X0 + 3 + row * 4.0, X1, 8.5):
            if abs(x - ARCH_X) < 21:
                continue
            out.append(('tree', float(x), z + (row * 0.5 - 0.6) * math.sin(x), 5.2 + 0.9 * math.sin(x * 1.7), 3.9, int(x) % 3))
    for x in np.arange(ARCH_X - 18.0, ARCH_X + 19.0, 7.0):           # the tangle's back row, behind the arch
        out.append(('hollow', float(x), Z0 + 1.5, 5.8, 3.8, 0))
    return out


TREES = _trees()


def _ferns():
    rng = np.random.default_rng(77)
    out = []
    while len(out) < 120:
        x, z = rng.uniform(X0 + 1, X1 - 1), rng.uniform(ARCH_Z + 2, Z1 - 1)
        if _near_path(x, z, PATH_W + 0.6) or not (_clear(x, z) or _near_path(x, z, PATH_W + 3.0)):
            continue
        out.append((x, z, 1.2 + 0.9 * rng.random(), rng.uniform(0, math.pi)))
    return out


def _bits():
    """Mushrooms, mossy logs, stumps and stones: (kind, x, z, size)."""
    rng = np.random.default_rng(91)
    out = []
    while len(out) < 46:
        x, z = rng.uniform(X0 + 2, X1 - 2), rng.uniform(ARCH_Z + 3, Z1 - 2)
        if not _clear(x, z) and not _near_path(x, z, PATH_W + 3.0):
            continue
        if _near_path(x, z, PATH_W + 0.8):
            continue
        k = rng.random()
        kind = 'shroom' if k < 0.45 else ('stone' if k < 0.75 else ('stump' if k < 0.88 else 'log'))
        out.append((kind, x, z, 0.8 + 0.6 * rng.random()))
    return out


FERNS, BITS = _ferns(), _bits()


def birch(P, M, x, z, h=7.0, r=2.8, rng=None):
    rng = rng or np.random.default_rng(int(abs(x * 17 + z * 11)))
    trunk = cyl_y(M, (x, z), 0.55, 0, h)
    P.fill(trunk, BIRCH, cell=(9, 0.5, 9))
    P.fill(trunk & (np.sin(M.Y * 3.1 + x) > 0.86), ['#3E3A36', '#4A4540'], cell=(9, 0.5, 9))     # its dark marks
    can = np.zeros(M.m.shape, bool)
    for _ in range(5):
        c = np.array([x, h + r * 0.2, z]) + rng.uniform(-1, 1, 3) * np.array([r * 0.5, r * 0.45, r * 0.5])
        can |= ball(M, c, r * rng.uniform(0.55, 0.8), 1.1)
    can &= (M.m == 0)
    P.fill(can, BIRCH_LEAF, cell=1.0)


def _sl(M, lo, hi):
    """the index slices of the box lo..hi (world units) in M"""
    i0 = np.clip(np.floor(np.array(lo, float) * M.res).astype(int) - M.lo, 0, M.m.shape)
    i1 = np.clip(np.ceil(np.array(hi, float) * M.res).astype(int) - M.lo, 0, M.m.shape)
    return tuple(slice(int(a), int(b)) for a, b in zip(i0, i1))


def fern(acc, M, x, z, s, a0):
    """a fan of fronds arching out and drooping, added to the mask [acc] (worked out in its own corner of
    the grid: there are a lot of them)"""
    sl = _sl(M, (x - 2.6 * s, 0, z - 2.6 * s), (x + 2.6 * s, 0.6 + 1.2 * s + 0.6, z + 2.6 * s))
    Xs, Ys, Zs = M.X[sl], M.Y[sl], M.Z[sl]
    loc = np.zeros(Xs.shape, bool)
    for k in range(7):
        a = a0 + k * math.pi * 2 / 7
        L = s * (1.6 + 0.4 * math.sin(k * 2.3))
        for t in np.linspace(0.1, 1.0, 7):
            px, pz = x + math.cos(a) * L * t, z + math.sin(a) * L * t
            py = 0.1 + s * 1.1 * math.sin(math.pi * t * 0.85)
            w = 0.45 * (1 - t * 0.6)
            loc |= (np.abs(Xs - px) < w) & (np.abs(Zs - pz) < w) & (Ys >= py) & (Ys < py + 0.5)
    acc[sl] |= loc & (M.m[sl] == 0)


def shroom(P, M, x, z, s, rng):
    P.fill(cyl_y(M, (x, z), 0.3 * s, 0, 1.1 * s), ['#F4EEDF', '#E8E0CC'], cell=9)
    cap = ball(M, (x, 1.1 * s, z), 0.85 * s, 0.55) & (M.Y >= 1.0 * s)
    red = rng.random() < 0.6
    P.fill(cap, ['#D9453A', '#C93A30'] if red else ['#B57A48', '#A86E3E'], cell=0.5)
    P.fill(cap & (rng.random(M.m.shape) < 0.16), ['#FFF8EC'], cell=0.5)


def tube(M, pts, r0, r1):
    """a thick bent trunk: balls swept along a polyline, narrowing"""
    m = np.zeros(M.m.shape, bool)
    pts = [np.array(p, float) for p in pts]
    total = sum(np.linalg.norm(b - a) for a, b in zip(pts, pts[1:]))
    d = 0.0
    for a, b in zip(pts, pts[1:]):
        L = np.linalg.norm(b - a)
        for t in np.linspace(0, 1, max(2, int(L / 0.4))):
            c = a + (b - a) * t
            r = r0 + (r1 - r0) * (d + L * t) / total
            lo = c - r - 0.5
            hi = c + r + 0.5
            sub = (M.X >= lo[0]) & (M.X < hi[0]) & (M.Y >= lo[1]) & (M.Y < hi[1]) & (M.Z >= lo[2]) & (M.Z < hi[2])
            m |= sub & ((M.X - c[0]) ** 2 + (M.Y - c[1]) ** 2 + (M.Z - c[2]) ** 2 <= r * r)
        d += L
    return m


def scene_wood(state='golden'):
    st = STATE_LIGHT[state]
    S = VScene('village_walk_wood', 1800, 1400, {}, world=st['world'], samples=96, transparent=True, sky=st['sky'])
    S.lights.append({'type': 'sun', **st['sun']})
    rng = np.random.default_rng(29)
    G = Model((X0, -4, Z0), (X1, 8, Z1), [], res=RES)
    P = CPainter(G, 41)
    X, Y, Z = G.X, G.Y, G.Z
    X2, Z2 = X[:, 0, :], Z[:, 0, :]
    # ---- the forest floor: grass over soil, darker in the shade of the trees, moss here and there
    P.fill((Y >= -3) & (Y < -1), SOIL, cell=1.0)
    P.fill((Y >= -1) & (Y < 0), GRASS, cell=1.0)
    shade = np.zeros(X2.shape, bool)
    for (kind, x, z, h, r, _) in TREES:
        shade |= (X2 - x) ** 2 + (Z2 - z) ** 2 < (r * 1.3) ** 2
    P.fill(shade[:, None, :] & (Y >= -1) & (Y < 0), GRASS_DEEP, cell=1.0)
    P.fill((np.sin(X2 * 0.37 + Z2 * 0.21) * np.cos(Z2 * 0.33) > 0.62)[:, None, :] & (Y >= -1) & (Y < 0), MOSS, cell=0.5)
    # the path: trodden dirt, grass growing into its edges, a few flat stones
    path = polyline(X2, Z2, PATH, PATH_W)
    P.fill(path[:, None, :] & (Y >= -1) & (Y < 0), DIRT, cell=(1.0, 1, 1.0))
    edge = polyline(X2, Z2, PATH, PATH_W + 0.5) & ~path & (np.sin(X2 * 1.7 + Z2 * 1.3) > 0)
    P.fill(edge[:, None, :] & (Y >= -1) & (Y < 0), GRASS_DEEP, cell=0.5)
    flag = path & (rng.random(X2.shape) < 0.02)
    P.fill(flag[:, None, :] & (Y >= -1) & (Y < 0), STONE, cell=0.5)
    # ---- the brook across the south: banks of earth, the water a step down, stones in it
    bz = brook_z(X2)
    chan = np.abs(Z2 - bz) < BROOK_W
    bank = (np.abs(Z2 - bz) < BROOK_W + 0.8) & ~chan
    G.m[chan[:, None, :] & (Y >= -1.5)] = 0
    P.fill(chan[:, None, :] & (Y >= -2.5) & (Y < -1.5), SOIL, cell=1.0)
    P.fill(chan[:, None, :] & (Y >= -1.5) & (Y < -1.0), WATER, cell=1.0)
    P.fill(bank[:, None, :] & (Y >= -1) & (Y < 0), BANK, cell=0.5)
    for sx in (3.0, 27.0, 41.0, 58.0, 76.0, 88.0):
        sz = float(brook_z(sx)) + rng.uniform(-1, 1)
        P.fill(ball(G, (sx, -1.2, sz), 0.9, 0.6) & (Y >= -1.4), STONE + STONE_MOSS, cell=0.5)
    # ---- the pond: a still basin, lily pads and their flowers, reeds round its edge, stones at its back
    px, pz, rx, rz = POND
    d = ((X2 - px) / rx) ** 2 + ((Z2 - pz) / rz) ** 2
    basin = d < 1
    G.m[basin[:, None, :] & (Y >= -1.5)] = 0
    P.fill(basin[:, None, :] & (Y >= -2.5) & (Y < -1.5), SOIL, cell=1.0)
    P.fill(basin[:, None, :] & (Y >= -1.5) & (Y < -1.0), POOL, cell=1.0)
    rim = (d >= 1) & (d < 1.22)
    P.fill(rim[:, None, :] & (Y >= -1) & (Y < 0), BANK + MOSS, cell=0.5)
    for _ in range(26):
        a, rr = rng.uniform(0, 2 * math.pi), math.sqrt(rng.uniform(0.05, 0.75))
        lx, lz = px + rx * rr * math.cos(a), pz + rz * rr * math.sin(a)
        pad = ((X - lx) ** 2 + (Z - lz) ** 2 < rng.uniform(0.5, 0.9) ** 2) & (Y >= -1.0) & (Y < -0.5)
        P.fill(pad, LILY, cell=0.5)
        if rng.random() < 0.35:
            P.fill(box(G, (lx - 0.25, -0.5, lz - 0.25), (lx + 0.25, 0.0, lz + 0.25)), ['#F7A8C4', '#FFF2F6'], cell=9)
    for _ in range(40):
        a = rng.uniform(0, 2 * math.pi)
        rx_, rz_ = px + (rx + 0.4) * math.cos(a), pz + (rz + 0.4) * math.sin(a)
        if abs(a - math.pi / 2) < 0.7:
            continue                          # the near shore stays open to look over
        hh = rng.uniform(1.2, 2.6)
        P.fill(box(G, (rx_ - 0.2, -1.0, rz_ - 0.2), (rx_ + 0.2, hh, rz_ + 0.2)), ['#6E9A45', '#5E8A3C', '#7FAA52'], cell=9)
        if rng.random() < 0.4:
            P.fill(box(G, (rx_ - 0.3, hh, rz_ - 0.3), (rx_ + 0.3, hh + 0.6, rz_ + 0.3)), ['#7A5434'], cell=9)    # a bulrush
    # the falls: mossy rocks stepping up behind the pond, water spilling down them
    fx_, fz_ = FALLS
    rocks = np.zeros(G.m.shape, bool)
    for (ox, oz, r, hgt) in ((-3.0, -0.5, 2.6, 3.2), (0.0, -1.2, 3.0, 4.6), (3.2, -0.4, 2.4, 2.8), (1.4, -3.0, 2.8, 6.0), (-2.0, -2.8, 2.4, 5.0)):
        rocks |= ball(G, (fx_ + ox, hgt * 0.45, fz_ + oz), r, hgt / (2 * r) * 1.15) & (Y >= -1)
    sheet = (np.abs(X - fx_) < 1.2) & (Z >= fz_ - 1.0) & (Z < fz_ + 0.6) & (Y >= -1.0) & (Y < 5.6)
    P.fill(rocks & ~sheet, STONE + STONE_MOSS, cell=0.5)
    P.fill(rocks & ~sheet & (Y > 2) & (rng.random(G.m.shape) < 0.3), MOSS, cell=0.5)
    P.fill(sheet & rocks, ['#DFF4FC', '#BFE8FA', '#FFFFFF', '#A9DDF5'], cell=(0.5, 0.5, 9))
    P.fill(box(G, (fx_ - 1.6, -1.0, fz_ + 0.4), (fx_ + 1.6, -0.6, fz_ + 1.6)), ['#E9F7FD', '#FFFFFF'], cell=0.5)   # foam where it lands
    # ---- the bridge over the brook: a plank deck with rails, a little up, its posts in the banks
    bx_, bzc = BRIDGE
    span = (np.abs(X - bx_) < 2.6) & (np.abs(Z - bzc) < BROOK_W + 1.6)
    arc = 0.5 + 0.5 * np.cos((Z - bzc) / (BROOK_W + 1.6) * 1.3)
    deck = span & (Y >= -0.5) & (Y < arc)
    P.fill(deck, HONEY, cell=(9, 1, 1.0))
    P.fill(deck & ((np.floor((Z - bzc + 20) / 1.0) % 2) == 0), OAK, cell=(9, 1, 1.0))
    for rx_ in (bx_ - 2.6, bx_ + 2.2):
        P.fill((np.abs(Z - bzc) < BROOK_W + 1.6) & (np.abs(X - rx_ - 0.2) < 0.25) & (np.abs(Y - 1.7 - arc) < 0.28), WALNUT, cell=9)
        for pz_ in (bzc - BROOK_W - 1.4, bzc, bzc + BROOK_W + 1.2):
            P.fill(box(G, (rx_, -2.5, pz_ - 0.25), (rx_ + 0.5, 2.3 + 0.5, pz_ + 0.25)), WALNUT, cell=9)
    S.models.append((G, (), {'water': WATER + POOL + ['#DFF4FC', '#BFE8FA', '#FFFFFF', '#A9DDF5', '#E9F7FD']}))

    # ---- what grows and stands: trees, ferns, flowers, mushrooms, logs, stones
    T = Model((X0, -2, Z0), (X1, 30, Z1), [], res=RES)
    PT = CPainter(T, 53)
    for (kind, x, z, h, r, li) in TREES:
        if kind == 'pine':
            pine(PT, T, x, z, h=h, r=r, y=0.0, rng=rng)
        elif kind == 'birch':
            birch(PT, T, x, z, h=h, r=r)
        elif kind == 'hollow':
            tree2(PT, T, x, z, h=h, r=r, y=0.0, leaves=HOLLOW_LEAF, rng=rng)
        else:
            tree2(PT, T, x, z, h=h, r=r, y=0.0, leaves=LEAVES[li], rng=rng)
        # roots spreading at its foot
        if kind in ('tree', 'pine'):
            for k in range(4):
                a = k * math.pi / 2 + 0.6
                PT.fill(box(T, (x + math.cos(a) * 0.9 - 0.35, 0, z + math.sin(a) * 0.9 - 0.35), (x + math.cos(a) * 1.6 + 0.35, 0.5, z + math.sin(a) * 1.6 + 0.35))
                        & (T.m == 0), ['#6E4529', '#7A4E2E'], cell=9)
    ferns = np.zeros(T.m.shape, bool)
    for (x, z, s, a0) in FERNS:
        fern(ferns, T, x, z, s, a0)
    PT.fill(ferns & (T.m == 0), FERN, cell=0.5)
    mx, mz, mrx, mrz = MEADOW
    for _ in range(9):
        flower_patch(PT, T, mx + rng.uniform(-mrx, mrx) * 0.7, mz + rng.uniform(-mrz, mrz) * 0.7, 2.6, 2.0, rng, n=14, cols=FLOWERS)
    for (x, z) in ((10.0, 8.0), (26.0, 12.0), (50.0, 6.0), (54.0, -18.0), (28.0, -12.0), (60.0, -34.0), (24.0, -40.0), (80.0, 8.0), (82.0, -24.0), (6.0, -14.0)):
        flower_patch(PT, T, x, z, 2.0, 1.6, rng, n=7, cols=FLOWERS)
    for (kind, x, z, s) in BITS:
        if kind == 'shroom':
            for k in range(int(rng.integers(1, 4))):
                shroom(PT, T, x + rng.uniform(-0.8, 0.8), z + rng.uniform(-0.8, 0.8), s * rng.uniform(0.7, 1.1), rng)
        elif kind == 'stone':
            boulder(PT, T, x, z, 1.0 + 0.8 * s, y=-0.3, seed=int(abs(x * 7 + z * 3)))
            PT.fill(ball(T, (x, 1.0 * s, z), 1.4 * s, 0.6) & (T.m > 0) & (T.Y > 0.8 * s), MOSS, cell=0.5)
        elif kind == 'stump':
            PT.fill(cyl_y(T, (x, z), 0.9 * s, 0, 1.2 * s), ['#7A4E2E', '#6E4529'], cell=(9, 0.5, 9))
            PT.fill(cyl_y(T, (x, z), 0.75 * s, 1.2 * s - 0.5, 1.2 * s), ['#C9A06E', '#B88E5E'], cell=9)
        else:
            L = 3.0 + 2.0 * s
            lg = ((T.Y - 0.6 * s) ** 2 + (T.Z - z) ** 2 < (0.6 * s) ** 2) & (np.abs(T.X - x) < L / 2)
            PT.fill(lg, ['#7A4E2E', '#6E4529', '#8A5A34'], cell=(1.0, 9, 9))
            PT.fill(lg & (T.Y > 0.9 * s), MOSS, cell=0.5)
            shroom(PT, T, x + L / 2 - 0.6, z + 0.6, 0.6, rng)
    # the bench by the pond, the sign by the bridge
    bnx, bnz = BENCH
    PT.fill(((T.Y - 0.9) ** 2 + (T.Z - bnz) ** 2 < 0.55 ** 2) & (np.abs(T.X - bnx) < 2.4), ['#8A5A34', '#7A4E2E'], cell=(1.0, 9, 9))
    for lx in (bnx - 1.8, bnx + 1.8):
        PT.fill(box(T, (lx - 0.3, 0, bnz - 0.5), (lx + 0.3, 0.6, bnz + 0.5)), WALNUT, cell=9)
    sx_, sz_ = SIGN
    PT.fill(box(T, (sx_ - 0.25, 0, sz_ - 0.25), (sx_ + 0.25, 3.4, sz_ + 0.25)), WALNUT, cell=9)
    PT.fill(box(T, (sx_ - 2.0, 2.2, sz_ - 0.15), (sx_ + 1.4, 3.4, sz_ + 0.25)), HONEY, cell=(1.0, 9, 9))
    PT.fill(box(T, (sx_ - 1.6, 2.6, sz_ + 0.2), (sx_ + 1.0, 3.0, sz_ + 0.3)), ['#5E3A24'], cell=9)
    PT.fill(box(T, (sx_ - 1.4, 3.4, sz_ - 0.1), (sx_ - 0.6, 3.8, sz_ + 0.2)), MOSS, cell=0.5)
    # lanterns along the path, firefly jars on posts, warm
    for (lx, lz) in LANTERNS:
        PT.fill(box(T, (lx - 0.3, 0, lz - 0.3), (lx + 0.3, 3.0, lz + 0.3)), WALNUT, cell=9)
        PT.fill(box(T, (lx - 0.3, 3.0, lz - 0.3), (lx + 1.2, 3.3, lz + 0.3)), WALNUT, cell=9)
        lantern(S, PT, T, (lx + 1.0, 2.2, lz), s=0.55, lit=True, power=10.0, kelvin=2600, hang_to=3.0)
    S.models.append((T, ()))

    # ---- the Thicket's way in: two ancient trees leaning together into an arch over the path, roots heaving
    # out of the ground, vines and moss on them; past it the path runs on into the Hollow's dark
    A = Model((ARCH_X - 18, -2, ARCH_Z - 14), (ARCH_X + 18, 22, ARCH_Z + 8), [], res=RES)
    PA = CPainter(A, 67)
    trunks = np.zeros(A.m.shape, bool)
    for s in (-1, 1):
        bx = ARCH_X + s * ARCH_HALF
        trunks |= tube(A, [(bx + s * 1.0, -1.0, ARCH_Z), (bx, 4.0, ARCH_Z), (bx - s * 0.8, 7.5, ARCH_Z - 0.3), (ARCH_X + s * 0.8, ARCH_TOP, ARCH_Z - 0.4)], 2.0, 1.2)
        for k in range(5):                                            # roots
            a = (k - 2) * 0.55 + (0 if s < 0 else math.pi)
            tip = (bx + math.cos(a) * 4.0, -0.6, ARCH_Z + math.sin(a) * 3.0 + 1.0)
            trunks |= tube(A, [(bx, 1.4, ARCH_Z), tip], 0.9, 0.35)
    PA.fill(trunks, ['#6E4529', '#7A4E2E', '#5E3A24', '#8A5A34'], cell=(0.5, 1.0, 0.5))
    PA.fill(trunks & (np.sin(A.X * 2.1 + A.Y * 1.3) > 0.7), ['#4A3020', '#3E2718'], cell=0.5)        # deep bark
    PA.fill(trunks & (A.Y > 1.5) & (np.sin(A.Y * 0.9 + A.X * 0.7 + A.Z) > 0.55), MOSS, cell=0.5)   # moss
    # the canopy over it: green on the near side, the Hollow's dark creeping into the far side
    can = np.zeros(A.m.shape, bool)
    rng2 = np.random.default_rng(5)
    for _ in range(9):
        c = np.array([ARCH_X, ARCH_TOP + 1.8, ARCH_Z - 1.0]) + rng2.uniform(-1, 1, 3) * np.array([6.0, 1.8, 2.6])
        can |= ball(A, c, rng2.uniform(2.6, 3.6), 0.8)
    can &= A.m == 0
    PA.fill(can & (A.Z >= ARCH_Z - 1.5), LEAVES[1], cell=1.0)
    PA.fill(can & (A.Z < ARCH_Z - 1.5), HOLLOW_LEAF, cell=1.0)
    # vines hanging from the arch, with little glowing flowers (the last of the wood's light)
    for k in range(14):
        vx = ARCH_X + rng2.uniform(-ARCH_HALF + 0.8, ARCH_HALF - 0.8)
        top = ARCH_TOP - 1.2 - abs(vx - ARCH_X) * 0.9
        L = rng2.uniform(1.5, 4.0)
        vine = (np.abs(A.X - vx) < 0.3) & (np.abs(A.Z - (ARCH_Z + 0.6)) < 0.3) & (A.Y < top) & (A.Y >= top - L) & (A.m == 0)
        PA.fill(vine, ['#4F8A3C', '#5E9646', '#3F7A32'], cell=0.5)
        if k % 4 == 0:
            PA.fill(box(A, (vx - 0.3, top - L - 0.5, ARCH_Z + 0.3), (vx + 0.3, top - L, ARCH_Z + 0.9)), ['#FFF2B0', '#FFE58A'], cell=9, glow=0.3)
    # past it: the path into the dark, the Hollow's light low under the tangle, a few violet crystals
    PA.fill(box(A, (ARCH_X - 3.0, -1.0, ARCH_Z - 13.0), (ARCH_X + 3.0, -0.5, ARCH_Z - 1.0)), ['#2E2836', '#28222F', '#352E3E'], cell=(1.0, 9, 1.0))
    for (cx_, cz_) in ((ARCH_X - 3.6, ARCH_Z - 4.0), (ARCH_X + 3.4, ARCH_Z - 6.5), (ARCH_X - 2.0, ARCH_Z - 10.0)):
        for _ in range(4):
            px_, pz_ = cx_ + rng2.uniform(-0.7, 0.7), cz_ + rng2.uniform(-0.6, 0.6)
            hgt = rng2.uniform(0.8, 2.0)
            shard = (np.abs(A.X - px_) < 0.3 * (1 - A.Y / hgt)) & (np.abs(A.Z - pz_) < 0.3) & (A.Y >= -0.5) & (A.Y < hgt)
            PA.fill(shard & (A.m == 0), HOLLOW, cell=9, glow=0.45)
    for (lx, lz) in ((ARCH_X - 1.5, ARCH_Z - 7.0), (ARCH_X + 1.5, ARCH_Z - 10.5)):
        S.lights.append({'type': 'point', 'pos': (lx, 1.4, lz), 'power': 3.0, 'color': (0.62, 0.34, 1.0), 'radius': 0.5})
    S.lights.append({'type': 'point', 'pos': (ARCH_X, 3.0, ARCH_Z + 4.0), 'power': 1.6, 'color': 3600, 'radius': 1.5})   # a little warm light on its face
    S.models.append((A, ()))
    VW.give_way([G, T, A])
    S.grade = {'bloom': 0.14, 'vignette': 0.05}
    return S


# the walking camera's view of the whole wood (45.8 px a unit)
VW.VIEWS['wood'] = ((44.0, -28.0), 96.0, (4397, 2950))
VW.VIEWS['wood_arch'] = ((ARCH_X, ARCH_Z + 2.0), 30.0, (1374, 1300))     # the way in, for checking
VW.VIEWS['wood_pond'] = ((POND[0], POND[1]), 30.0, (1374, 1100))

if __name__ == '__main__':
    import village_scenes as VSC
    args = sys.argv[1:]
    out = args[0]
    quick = '--quick' in args
    os.makedirs(out, exist_ok=True)
    vs = scene_wood()
    if '--depth' in args:
        VW.render_ortho(vs, 'wood', os.path.join(out, 'village_walk_wood_depth.exr'), quick, depth=True)
        sys.exit(0)
    view = args[args.index('--view') + 1] if '--view' in args else 'wood'
    raw = os.path.join(out, f'village_walk_{view}_raw.png')
    proj = VW.render_ortho(vs, view, raw, quick)
    VSC.finish(vs, raw, os.path.join(out, f'village_walk_{view}.png'), quick)
    import json
    json.dump(proj, open(os.path.join(out, 'village_walk_wood.json'), 'w'), indent=1)

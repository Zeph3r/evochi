"""Stand-alone voxel models for inventory items, decorations and the voxel UI icon family.

Each builder returns (Model, camera). Materials are literal hex colours so the
models need no palette. Every model is authored in a small grid (res = voxels
per unit) and rendered with the same outline treatment as the characters.
"""
from __future__ import annotations

import math

import numpy as np

from voxel import Model, Camera
from characters import spike, tube, local_frame

# common colours
GOLD, GOLD_HI, GOLD_LO, GOLD_DK = '#F4C04E', '#FFE29A', '#D99A36', '#B87828'
RUBY, RUBY_HI = '#D8434A', '#FF8F8A'
WOOD, WOOD_HI, WOOD_LO = '#A86E42', '#C98C57', '#7A4A2C'
LEAF, LEAF_HI, LEAF_LO = '#6FB24E', '#9BD16B', '#3F7D35'
CREAM, CREAM_LO = '#FFF3E2', '#EAD7BF'
RED, RED_HI, RED_LO = '#D24A3F', '#EC6E62', '#962F29'
BLUE, BLUE_HI, BLUE_LO = '#4D8FD8', '#86B9EE', '#2F5FA3'
STRAW, STRAW_HI, STRAW_LO = '#E2B866', '#F6D894', '#B98A3E'
LEATHER, LEATHER_HI, LEATHER_LO = '#8A5634', '#B07444', '#5E3A24'
WHITE = '#FFFDF6'
GREY, GREY_HI, GREY_LO = '#8E8A86', '#B5B0AA', '#625E5B'
GLASS, GLASS_HI = '#BFE6F5', '#EAF8FF'
GLOW = '#FFD46A'


def M_(lo, hi, res=1):
    return Model(lo, hi, [], res=res)


def ell(M, c, r, p=2.0):
    return M.ellipsoid(c, r, p)


def cyl(M, c, r, h, axis=1, p=2.0):
    """Cylinder centred at c with radius r, length h along axis."""
    X = [M.X, M.Y, M.Z]
    a = [i for i in range(3) if i != axis]
    rad = np.abs((X[a[0]] - c[a[0]]) / r) ** p + np.abs((X[a[1]] - c[a[1]]) / r) ** p
    return (rad <= 1) & (np.abs(X[axis] - c[axis]) <= h / 2)


def flower(M, c, n=(0, 0, 1), size=1.0, petal=WHITE, centre=GOLD):
    u, v, nn = local_frame(n)
    P = np.stack([M.X - c[0], M.Y - c[1], M.Z - c[2]], -1)
    U, V, N = P @ u, P @ v, P @ nn
    r = np.sqrt(U ** 2 + V ** 2)
    th = np.arctan2(V, U)
    pet = (r <= size * (1.25 + 0.65 * np.cos(5 * th))) & (np.abs(N) <= 0.55 * size) & (r <= 1.95 * size)
    M.set(pet, petal)
    M.set((r <= 0.75 * size) & (N > -0.3) & (N <= 1.0 * size), centre)


# ----------------------------------------------------------------------------
# Items
# ----------------------------------------------------------------------------
def leaf_scarf():
    M = M_((-12, -6, -12), (12, 8, 12), res=2)
    th = np.degrees(np.arctan2(M.X, M.Z))
    r = np.sqrt(M.X ** 2 + M.Z ** 2)
    band = (r >= 6.5) & (r <= 9.0) & (M.Y >= -0.5) & (M.Y < 3.0)
    M.set(band, LEAF)
    M.set(band & (M.Y >= 2.3), LEAF_HI)
    phase = (th + 360) % 36
    tri = np.abs(phase - 18) / 18
    depth = (-0.5 - M.Y) / 3.6
    lobe = (r >= 6.8) & (r <= 9.2) & (M.Y < -0.5) & (M.Y > -4.1) & (tri <= (1 - depth))
    M.set(lobe, LEAF_LO)
    vein = band & (np.abs(phase - 18) < 2.0)
    M.set(vein, '#4D8E3B')
    flower(M, (5.2, 1.5, 7.6), n=(0.5, 0.25, 1), size=1.7)
    return M, Camera(yaw=-20, pitch=28)


def blue_scarf():
    M = M_((-12, -10, -12), (12, 8, 12), res=2)
    r = np.sqrt(M.X ** 2 + M.Z ** 2)
    band = (r >= 6.0) & (r <= 8.8) & (M.Y >= -1.0) & (M.Y < 3.0)
    k = np.floor(M.Y + 1).astype(int) % 2
    M.set(band & (k == 0), BLUE)
    M.set(band & (k == 1), BLUE_HI)
    tail = (M.X >= 1.5) & (M.X <= 5.0) & (M.Z >= 6.0) & (M.Z <= 8.5) & (M.Y < 1.0) & (M.Y > -8.0)
    M.set(tail & (M.Y > -6.5), BLUE)
    M.set(tail & (M.Y > -6.5) & (np.floor(M.Y).astype(int) % 3 == 0), BLUE_HI)
    fr = tail & (M.Y <= -6.5) & (np.floor((M.X - 1.5) / 0.75).astype(int) % 2 == 0)
    M.set(fr, WHITE)
    knot = ell(M, (3.0, 1.0, 8.2), (2.0, 1.8, 1.5))
    M.set(knot, BLUE_LO)
    return M, Camera(yaw=-15, pitch=26)


def crown(big=True):
    M = M_((-9, -2, -9), (9, 12, 9), res=2)
    r = np.sqrt(M.X ** 2 + M.Z ** 2)
    R = 7.0 if big else 6.0
    ring = (r <= R) & (r >= R - 1.6) & (M.Y >= 0) & (M.Y < 3.2)
    M.set(ring, GOLD)
    M.set(ring & (M.Y < 0.8), GOLD_LO)
    M.set(ring & (M.Y >= 2.6), GOLD_HI)
    n = 8 if big else 5
    for k in range(n):
        a = k / n * 2 * math.pi
        base = (math.sin(a) * (R - 0.8), 2.8, math.cos(a) * (R - 0.8))
        sp = spike(M, base, (math.sin(a) * 0.12, 1, math.cos(a) * 0.12), 5.0 if big else 4.2, 1.5, 0.3)
        M.set(sp, GOLD if k % 2 else GOLD_HI)
        if not big:
            M.set(ell(M, (base[0], base[1] + 4.6, base[2]), (0.7, 0.7, 0.7)), GOLD_HI)
    gem = (np.abs(M.X) + np.abs(M.Y - 1.6) <= 1.8) & (M.Z >= R - 1.2) & (M.Z <= R + 0.8)
    M.set(gem, RUBY)
    M.set(gem & (M.Y > 2.2) & (M.X < 0.5), RUBY_HI)
    if big:
        for a in (math.pi / 2, -math.pi / 2):
            g = (math.sin(a) * R, 1.6, math.cos(a) * R)
            M.set(ell(M, g, (0.9, 0.9, 0.9)) & (r >= R - 0.6), '#4EC3E0')
    return M, Camera(yaw=-18, pitch=22)


def explorer_hat():
    M = M_((-11, -1, -11), (11, 11, 11), res=2)
    brim = (M.X ** 2 / 9.5 ** 2 + M.Z ** 2 / 9.0 ** 2 <= 1) & (M.Y >= 0) & (M.Y < 1.2)
    crown_ = (M.X ** 2 / 5.8 ** 2 + M.Z ** 2 / 5.6 ** 2 + M.Y ** 2 / 7.2 ** 2 <= 1) & (M.Y >= 0)
    crown_ &= ~((np.abs(M.X) < 1.0) & (M.Y > 5.8))
    M.set(brim, LEATHER)
    M.set(brim & (M.Y >= 0.6), LEATHER_HI)
    M.set(crown_ & ~brim, LEATHER)
    M.set(crown_ & (M.Y > 4.5) & (M.X < -1), LEATHER_HI)
    band = crown_ & (M.Y >= 1.2) & (M.Y < 2.8)
    M.set(band, '#4F8C3C')
    for sx in (-1.7, 1.7):
        lens = ((M.X - sx) ** 2 + (M.Y - 2.0) ** 2 <= 1.35 ** 2) & (M.Z >= 4.6) & (M.Z <= 6.4)
        M.set(lens, '#2E3640')
        M.set(((M.X - sx) ** 2 + (M.Y - 2.0) ** 2 <= 0.8 ** 2) & (M.Z > 5.6) & (M.Z <= 6.6), '#7FA6C8')
    fe = spike(M, (4.4, 2.0, -0.8), (0.4, 1.0, -0.4), 7.0, 1.1, 0.3, square=False)
    M.set(fe & (M.m == 0), '#F2EBD9')
    return M, Camera(yaw=-22, pitch=22)


def butterfly_clip():
    M = M_((-7, -6, -3), (7, 6, 3), res=2)
    for s in (-1, 1):
        for (dy, rr, rx) in ((1.4, 3.0, 3.2), (-1.8, 2.2, 2.4)):
            cx = s * (rx * 0.85)
            e = ((M.X - cx) / rx) ** 2 + ((M.Y - dy) / rr) ** 2
            w = (e <= 1) & (np.abs(M.Z) <= 0.6)
            M.set(w, '#F6C24E')
            M.set(w & (e > 0.55), '#E39A2E')
            M.set(((M.X - cx) ** 2 + (M.Y - dy) ** 2 <= 0.45) & (np.abs(M.Z) <= 0.8), '#7A4A22')
    M.set((np.abs(M.X) <= 0.6) & (np.abs(M.Y) <= 3.4) & (np.abs(M.Z) <= 1.0), '#6B4226')
    for s in (-1, 1):
        ant = spike(M, (s * 0.3, 3.2, 0), (s * 0.5, 1, 0), 2.6, 0.4, 0.3, square=False)
        M.set(ant, '#6B4226')
    return M, Camera(yaw=-15, pitch=12)


def backpack(kind='red'):
    M = M_((-8, -1, -7), (8, 14, 7), res=2)
    body, hi, lo = (RED, RED_HI, RED_LO) if kind == 'red' else (LEATHER, LEATHER_HI, LEATHER_LO)
    b = ((np.abs(M.X) / 5.6) ** 6 + (np.abs(M.Y - 5.6) / 5.6) ** 6 + (np.abs(M.Z) / 3.8) ** 6) <= 1
    M.set(b, body)
    flap = b & (M.Y > 6.5) & (M.Z > 1.6)
    flap |= b & (M.Y > 9.2)
    M.set(flap, hi)
    pk = (np.abs(M.X) <= 3.2) & (M.Y > 1.0) & (M.Y < 5.4) & (M.Z > 3.0) & (M.Z <= 5.0)
    M.set(pk, lo)
    for bx in (-2.6, 2.6):
        M.set((np.abs(M.X - bx) <= 0.75) & (np.abs(M.Y - 7.2) <= 0.75) & (M.Z > 3.2) & (M.Z <= 4.6),
              '#E9C46A')
    handle = (np.abs(M.X) <= 2.2) & (M.Y >= 11.0) & (M.Y < 12.6) & (np.abs(M.Z) <= 0.8)
    handle &= ~((np.abs(M.X) <= 1.2) & (M.Y < 11.8))
    M.set(handle, lo)
    if kind == 'explorer':
        roll = ((M.Y - 12.4) ** 2 + (M.Z - 0.0) ** 2 <= 2.2 ** 2) & (np.abs(M.X) <= 6.4)
        M.set(roll & (M.m == 0) | roll & (M.Y > 11.0), '#4E8C4C')
        M.set(roll & (np.abs(np.abs(M.X) - 3.6) < 0.6), LEATHER_LO)
        M.set(roll & (np.abs(M.X) > 6.0), '#78B06A')
    return M, Camera(yaw=-25, pitch=16)


def berry_snack():
    M = M_((-8, -1, -8), (8, 12, 8), res=2)
    rng = np.random.default_rng(3)
    for (c, r) in (((-2.4, 2.6, 0.5), 2.7), ((2.4, 2.6, 0.0), 2.7), ((0.0, 2.6, 2.8), 2.6),
                   ((0.0, 5.8, 0.8), 2.6), ((-1.0, 2.4, -2.5), 2.4)):
        b = ell(M, c, (r, r, r), p=2.4)
        M.set(b, '#D93A48')
        M.set(b & (M.Y > c[1] + r * 0.45) & (M.X < c[0]), '#F06A70')
        M.set(b & (M.Y < c[1] - r * 0.4), '#A52532')
    for (c, d) in (((0.0, 8.6, 0.6), (0.6, 0.4, 0.8)), ((-0.4, 8.6, 0.6), (-0.8, 0.3, -0.4))):
        lf = spike(M, c, d, 4.0, 1.4, 0.3)
        M.set(lf & (M.m == 0), LEAF)
    M.set((np.abs(M.X) <= 0.4) & (M.Y > 7.6) & (M.Y < 9.6) & (np.abs(M.Z - 0.7) <= 0.4), '#6B4226')
    return M, Camera(yaw=-20, pitch=20)


def healing_herb():
    M = M_((-8, -1, -8), (8, 16, 8), res=2)
    rng = np.random.default_rng(5)
    leaves = [((0, 2, 0), (0.6, 1, 0.3)), ((0, 2, 0), (-0.7, 1, 0.2)), ((0, 2, 0), (0.1, 1, 0.8)),
              ((0, 2, 0), (0.2, 1, -0.8)), ((0, 2, 0), (-0.4, 1, -0.6)), ((0, 2, 0), (0.8, 0.7, -0.3))]
    for i, (b, d) in enumerate(leaves):
        lf = spike(M, b, d, 7.5 + (i % 3), 2.2, 0.4, twist=0.4 * i)
        M.set(lf, LEAF if i % 2 else LEAF_HI)
    M.set(ell(M, (0, 1.2, 0), (3.0, 1.6, 3.0)), LEAF_LO)
    flower(M, (0.6, 9.6, 2.0), n=(0.2, 0.6, 1), size=1.6)
    flower(M, (-3.6, 7.0, 1.6), n=(-0.4, 0.5, 1), size=1.0)
    return M, Camera(yaw=-15, pitch=20)


def sunlit_flower():
    M = M_((-8, -1, -8), (8, 14, 8), res=2)
    for i, d in enumerate([(0.7, 1, 0.2), (-0.8, 1, 0.1), (0.1, 1, -0.8), (0.0, 1, 0.9)]):
        lf = spike(M, (0, 1, 0), d, 5.5, 1.8, 0.3, twist=0.5 * i)
        M.set(lf, LEAF if i % 2 else LEAF_HI)
    M.set((np.abs(M.X) <= 0.5) & (np.abs(M.Z) <= 0.5) & (M.Y < 8.5), LEAF_LO)
    flower(M, (0, 9.0, 0.5), n=(0, 0.4, 1), size=2.6)
    flower(M, (3.6, 5.4, 1.4), n=(0.3, 0.4, 1), size=1.4)
    flower(M, (-3.4, 4.6, 1.0), n=(-0.3, 0.4, 1), size=1.3)
    return M, Camera(yaw=-15, pitch=18)


def nest(meadow=False):
    M = M_((-12, -1, -12), (12, 9, 12), res=2)
    rng = np.random.default_rng(9)
    r = np.sqrt(M.X ** 2 + M.Z ** 2)
    ring = (r <= 9.5) & (r >= 5.0) & (M.Y >= 0) & (M.Y < 3.6 - ((r - 7.25) / 2.25) ** 2 * 1.4)
    base = (r < 5.5) & (M.Y >= 0) & (M.Y < 1.0)
    noise = rng.random(M.m.shape)
    if meadow:
        M.set(ring, '#9C7A52')
        M.set(ring & (noise > 0.55), '#B9966A')
        M.set(base, '#7DAE54')
        moss = ring & (M.Y > 2.0) & (noise > 0.45)
        M.set(moss, '#7DB353')
        for k in range(5):
            a = k / 5 * 2 * math.pi + 0.3
            flower(M, (math.sin(a) * 7.4, 3.8, math.cos(a) * 7.4), n=(0, 1, 0.3), size=1.2)
    else:
        M.set(ring, STRAW)
        M.set(ring & (noise > 0.6), STRAW_HI)
        M.set(ring & (noise < 0.18), STRAW_LO)
        M.set(base, STRAW_LO)
        for k in range(3):
            a = k / 3 * 2 * math.pi + 0.9
            flower(M, (math.sin(a) * 7.6, 3.4, math.cos(a) * 7.6), n=(0, 1, 0.3), size=1.1)
    return M, Camera(yaw=-10, pitch=30)


def lantern(glow=True):
    M = M_((-6, -1, -6), (6, 16, 6), res=2)
    frame = (np.maximum(np.abs(M.X), np.abs(M.Z)) <= 3.2) & (M.Y >= 2.0) & (M.Y < 9.5)
    hollow = (np.maximum(np.abs(M.X), np.abs(M.Z)) <= 2.4) & (M.Y >= 2.8) & (M.Y < 8.8)
    M.set(frame & ~hollow, WOOD_LO)
    panes = frame & hollow
    # glass panes: carve windows in the frame
    win = frame & ~hollow & (np.minimum(np.abs(M.X), np.abs(M.Z)) <= 1.9) & (M.Y >= 3.0) & (M.Y < 8.4)
    M.set(win, GLOW)
    M.glow[win] = 0.8
    core = (np.maximum(np.abs(M.X), np.abs(M.Z)) <= 2.0) & (M.Y >= 3.0) & (M.Y < 8.4)
    M.set(core, '#FFE7A0')
    M.glow[core] = 1.0
    base = (np.maximum(np.abs(M.X), np.abs(M.Z)) <= 3.8) & (M.Y >= 0.6) & (M.Y < 2.0)
    M.set(base, WOOD)
    top = (np.maximum(np.abs(M.X), np.abs(M.Z)) <= 3.8 - (M.Y - 9.5) * 0.9) & (M.Y >= 9.5) & (M.Y < 12.0)
    M.set(top, WOOD)
    ring = ((M.X ** 2 + (M.Y - 13.2) ** 2) <= 1.6 ** 2) & ((M.X ** 2 + (M.Y - 13.2) ** 2) >= 0.8 ** 2) & \
        (np.abs(M.Z) <= 0.5)
    M.set(ring, GREY_LO)
    return M, Camera(yaw=-25, pitch=14)


ITEM_BUILDERS = {
    'leaf_scarf': leaf_scarf, 'blue_scarf': blue_scarf,
    'golden_crest_crown': lambda: crown(True), 'tiny_crown': lambda: crown(False),
    'explorer_hat': explorer_hat, 'butterfly_clip': butterfly_clip,
    'red_backpack': lambda: backpack('red'), 'explorer_pack': lambda: backpack('explorer'),
    'berry_snack': berry_snack, 'healing_herb': healing_herb, 'sunlit_flower': sunlit_flower,
    'nest_bed': lambda: nest(False), 'meadow_nest': lambda: nest(True),
    'explorer_lantern': lantern,
}


# ----------------------------------------------------------------------------
# UI icons (voxel family)
# ----------------------------------------------------------------------------
def ic_coin():
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    r = np.sqrt(M.X ** 2 + M.Y ** 2)
    disc = (r <= 8.0) & (np.abs(M.Z) <= 1.6)
    M.set(disc, '#F3B83A')
    M.set(disc & (r > 6.6), '#E09A28')
    inner = (np.maximum(np.abs(M.X), np.abs(M.Y)) <= 3.4) & (M.Z > 1.0) & (M.Z <= 2.0)
    M.set(inner, '#FFD970')
    M.set((np.maximum(np.abs(M.X), np.abs(M.Y)) <= 2.0) & (M.Z > 1.0) & (M.Z <= 2.0), '#F3B83A')
    M.set(disc & (M.Z > 1.0) & (r > 4.5) & (r < 5.6) & (M.X < 0) & (M.Y > 0), '#FFE9A8')
    return M, Camera(yaw=-14, pitch=8)


def ic_gem():
    M = M_((-8, -9, -8), (8, 9, 8), res=2)
    top = (np.maximum(np.abs(M.X), np.abs(M.Z)) * 0.0 + np.abs(M.X) * 0.9 + np.abs(M.Z) * 0.9 + np.abs(M.Y - 2) * 1.6 <= 7.5) & (M.Y >= 2)
    bot = (np.abs(M.X) + np.abs(M.Z) + (2 - M.Y) * 0.75 <= 7.5) & (M.Y < 2)
    M.set(top, '#57CCEA')
    M.set(bot, '#2E9FCC')
    M.set(top & (M.X < 0) & (M.Y > 3.5), '#B5EEFB')
    return M, Camera(yaw=-22, pitch=12)


def ic_heart(col='#E0524A', hi='#F58C82'):
    M = M_((-9, -8, -3), (9, 8, 3), res=2)
    x, y = M.X / 7.0, M.Y / 7.0 + 0.1
    h = (x ** 2 + y ** 2 - 1) ** 3 - x ** 2 * y ** 3 <= 0
    sh = h & (np.abs(M.Z) <= 1.8 * np.clip(1.2 - np.abs(x) * 0.4, 0.5, 1.2))
    M.set(sh, col)
    M.set(sh & (M.Z > 0.6) & (M.X < -2) & (M.Y > 1.5) & (M.Y < 4.5) & (M.X > -5.5), hi)
    return M, Camera(yaw=-10, pitch=8)


def ic_house():
    M = M_((-9, -1, -8), (9, 16, 8), res=2)
    walls = (np.abs(M.X) <= 6) & (M.Y >= 0) & (M.Y < 7.5) & (np.abs(M.Z) <= 5)
    M.set(walls, CREAM)
    M.set(walls & (M.Y < 1.2), CREAM_LO)
    roof = (np.abs(M.X) <= 8.2 - (M.Y - 7.0) * 1.05) & (M.Y >= 7.0) & (np.abs(M.Z) <= 6.2)
    M.set(roof, '#E06A45')
    M.set(roof & ((np.floor(M.Y - 7.0).astype(int)) % 2 == 0), '#C9553A')
    door = (np.abs(M.X - 1.2) <= 1.8) & (M.Y < 4.8) & (M.Z > 4.5) & (M.Z <= 5.6)
    M.set(door, WOOD)
    win = (np.abs(M.X + 3.4) <= 1.2) & (M.Y > 3.0) & (M.Y < 5.4) & (M.Z > 4.5) & (M.Z <= 5.6)
    M.set(win, '#8FD0F0')
    chim = (np.abs(M.X - 4.2) <= 1.0) & (M.Y >= 8) & (M.Y < 12.2) & (np.abs(M.Z) <= 1.0)
    M.set(chim, '#A65A3A')
    return M, Camera(yaw=-24, pitch=14)


def ic_map():
    M = M_((-10, -1, -8), (10, 3, 8), res=2)
    for i in range(4):
        x0 = -8 + i * 4
        panel = (M.X >= x0) & (M.X < x0 + 4) & (np.abs(M.Z) <= 6.5)
        h = 0.0 if i % 2 == 0 else 0.9
        y = h + (M.X - x0) / 4 * (0.9 if i % 2 == 0 else -0.9)
        sl = panel & (M.Y >= y) & (M.Y < y + 0.9)
        M.set(sl, '#EBD9B0' if i % 2 == 0 else '#D9C397')
    land = (M.m > 0) & (((M.X + 2) ** 2 + (M.Z - 1) ** 2) < 14)
    M.set(land, '#7DBA5A')
    land2 = (M.m > 0) & (((M.X - 5) ** 2 + (M.Z + 3) ** 2) < 6)
    M.set(land2, '#7DBA5A')
    path = (M.m > 0) & (np.abs(M.Z - (M.X * 0.35 - 0.5)) < 0.7) & (M.X > -6) & (M.X < 3)
    M.set(path, '#C9553A')
    xm = (M.m > 0) & ((np.abs((M.X - 4.5) - (M.Z - 2.5)) < 0.8) | (np.abs((M.X - 4.5) + (M.Z - 2.5)) < 0.8)) & \
        (np.abs(M.X - 4.5) < 1.8) & (np.abs(M.Z - 2.5) < 1.8)
    M.set(xm, '#D8434A')
    return M, Camera(yaw=-10, pitch=52)


def ic_backpack():
    M, _ = backpack('explorer')
    return M, Camera(yaw=-22, pitch=12)


def ic_stall():
    M = M_((-9, -1, -7), (9, 16, 7), res=2)
    counter = (np.abs(M.X) <= 7) & (M.Y >= 0) & (M.Y < 5) & (np.abs(M.Z) <= 4)
    M.set(counter, WOOD)
    M.set(counter & (M.Y >= 4.2), WOOD_HI)
    M.set(counter & (M.Y < 4.2) & (M.Z > 3.2) & ((np.floor(M.X + 7) % 4) < 0.9), WOOD_LO)
    for sx in (-6.4, 6.4):
        M.set((np.abs(M.X - sx) <= 0.7) & (M.Y >= 5) & (M.Y < 10) & (np.abs(M.Z - 2.8) <= 0.7), WOOD_LO)
    awn = (np.abs(M.X) <= 8.2) & (M.Y >= 9.5) & (M.Y < 13.5) & (M.Z <= 6.0) & (M.Z >= 6.0 - (13.5 - M.Y) * 2.8)
    awn |= (np.abs(M.X) <= 8.2) & (M.Y >= 12.8) & (M.Y < 13.6) & (np.abs(M.Z) <= 6.0)
    stripe = (np.floor((M.X + 8.2) / 2.05).astype(int) % 2 == 0)
    M.set(awn & stripe, '#E05A44')
    M.set(awn & ~stripe, WHITE)
    scal = (np.abs(M.X) <= 8.2) & (M.Y >= 8.4) & (M.Y < 9.6) & (M.Z > 5.0) & (M.Z <= 6.6)
    scal &= (((M.X + 8.2) % 2.05) < 1.6)
    M.set(scal & stripe, '#E05A44')
    M.set(scal & ~stripe, WHITE)
    M.set(ell(M, (-3, 5.8, 1.0), (1.4, 1.2, 1.4)), '#D93A48')
    M.set(ell(M, (2.5, 5.8, 1.0), (1.3, 1.1, 1.3)), '#F3B83A')
    return M, Camera(yaw=-22, pitch=12)


def ic_book():
    M = M_((-8, -1, -6), (8, 18, 6), res=2)
    cover = (np.abs(M.X) <= 6.2) & (M.Y >= 0) & (M.Y < 16) & (np.abs(M.Z) <= 2.6)
    M.set(cover, '#9C4F32')
    pages = (M.X > 5.0) & (M.X <= 6.0) & (M.Y >= 0.8) & (M.Y < 15.2) & (np.abs(M.Z) <= 2.0)
    M.set(pages, '#F7ECD8')
    spine = (M.X <= -5.0) & cover
    M.set(spine, '#7F3D27')
    emb = (np.abs(M.X - 0.5) <= 3.2) & (np.abs(M.Y - 9.5) <= 2.4) & (M.Z > 2.0) & (M.Z <= 3.2)
    M.set(emb, '#F3B83A')
    M.set((np.abs(M.X - 0.5) <= 1.8) & (np.abs(M.Y - 9.5) <= 1.1) & (M.Z > 2.6) & (M.Z <= 3.4), '#FFE29A')
    band = cover & (np.abs(M.Y - 3.4) <= 0.6)
    M.set(band, '#F3B83A')
    bm = (np.abs(M.X - 3.6) <= 0.8) & (M.Y >= -1) & (M.Y < 1) & (np.abs(M.Z - 2.0) <= 0.4)
    M.set(bm, '#D8434A')
    return M, Camera(yaw=-20, pitch=10)


def ic_ball():
    M = M_((-8, -8, -8), (8, 8, 8), res=2)
    s = ell(M, (0, 0, 0), (7, 7, 7))
    a = np.degrees(np.arctan2(M.X, M.Z))
    seg = (np.floor((a + 180) / 60).astype(int)) % 3
    M.set(s & (seg == 0), '#E2493D')
    M.set(s & (seg == 1), WHITE)
    M.set(s & (seg == 2), '#3E8FD6')
    M.set(s & (M.Y > 5.6), WHITE)
    return M, Camera(yaw=-15, pitch=20)


def ic_magnifier():
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    c = (-1.5, 1.5)
    r = np.sqrt((M.X - c[0]) ** 2 + (M.Y - c[1]) ** 2)
    rim = (r <= 6.0) & (r >= 4.4) & (np.abs(M.Z) <= 1.4)
    M.set(rim, '#6C4A35')
    lens = (r < 4.4) & (np.abs(M.Z) <= 0.6)
    M.set(lens, '#9FDCF3')
    M.set(lens & ((M.X - c[0]) < -0.5) & ((M.Y - c[1]) > 0.5) & (r > 1.8) & (r < 3.2), '#E8F8FF')
    d = np.array([1, -1, 0]) / math.sqrt(2)
    P = np.stack([M.X - 2.8, M.Y + 2.8, M.Z], -1)
    t = P @ d
    rad = np.linalg.norm(P - t[..., None] * d, axis=-1)
    handle = (t >= 0) & (t <= 6.5) & (rad <= 1.3)
    M.set(handle, '#8A5634')
    return M, Camera(yaw=-12, pitch=8)


def ic_gear():
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    r = np.sqrt(M.X ** 2 + M.Y ** 2)
    a = np.arctan2(M.Y, M.X)
    teeth = (np.cos(8 * a) > 0.3) & (r <= 8.0)
    g = ((r <= 6.0) | teeth) & (r >= 2.4) & (np.abs(M.Z) <= 1.8)
    M.set(g, '#6E6964')
    M.set(g & (r < 4.4) & (M.Z > 0.8), '#8E8A86')
    return M, Camera(yaw=-12, pitch=10)


def ic_mail():
    M = M_((-9, -7, -3), (9, 7, 3), res=2)
    env = (np.abs(M.X) <= 7.6) & (np.abs(M.Y) <= 5.2) & (np.abs(M.Z) <= 1.2)
    M.set(env, '#F1E3CB')
    flap = env & (M.Z > 0.6) & (M.Y > 5.2 - (7.6 - np.abs(M.X)) * 0.62) & (M.Y > -1)
    M.set(flap, '#DCC5A2')
    edge = env & (M.Z > 0.6) & (np.abs(M.Y - (5.2 - (7.6 - np.abs(M.X)) * 0.62)) < 0.55)
    M.set(edge, '#8B6A4C')
    return M, Camera(yaw=-10, pitch=8)


def ic_pin():
    M = M_((-7, -1, -4), (7, 17, 4), res=2)
    head = ell(M, (0, 10.5, 0), (5.5, 5.5, 2.6))
    tip = (np.abs(M.X) <= (M.Y - 0.5) * 0.55) & (M.Y >= 0.5) & (M.Y < 10.5) & (np.abs(M.Z) <= 2.2)
    M.set(head | tip, '#7A5440')
    hole = ((M.X) ** 2 + (M.Y - 10.8) ** 2 <= 2.2 ** 2) & (np.abs(M.Z) <= 3.0)
    M.set(hole & (M.m > 0), '#F4E6D2')
    return M, Camera(yaw=-10, pitch=8)


def ic_star(col='#F7C33F', hi='#FFE590'):
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    a = np.arctan2(M.X, M.Y)
    r = np.sqrt(M.X ** 2 + M.Y ** 2)
    k = np.cos(5 * a)
    rad = 4.0 + 3.8 * np.clip(k, 0, 1) ** 1.5
    s = (r <= rad) & (np.abs(M.Z) <= 1.8 - r * 0.1)
    M.set(s, col)
    M.set(s & (M.X < 0) & (M.Y > 0) & (M.Z > 0.3), hi)
    return M, Camera(yaw=-10, pitch=8)


def ic_flask():
    M = M_((-8, -1, -8), (8, 17, 8), res=2)
    bulb = ell(M, (0, 5.5, 0), (5.6, 5.4, 5.6))
    neck = cyl(M, (0, 12.0, 0), 1.9, 5.0)
    M.set(bulb | neck, '#CDEBF5')
    liquid = bulb & (M.Y < 6.5)
    M.set(liquid, '#8ED36A')
    M.set(liquid & (M.Y > 5.6), '#B6E694')
    cork = cyl(M, (0, 15.0, 0), 2.2, 2.0)
    M.set(cork, WOOD)
    return M, Camera(yaw=-15, pitch=14)


def ic_sprout():
    M = M_((-8, -1, -8), (8, 18, 8), res=2)
    pot = (np.sqrt(M.X ** 2 + M.Z ** 2) <= 4.2 + M.Y * 0.18) & (M.Y >= 0) & (M.Y < 6)
    M.set(pot, '#C9734A')
    M.set(pot & (M.Y >= 5.0), '#B05E3A')
    M.set((np.sqrt(M.X ** 2 + M.Z ** 2) <= 4.6) & (M.Y >= 5.4) & (M.Y < 6.2), '#6B4A33')
    stem = (np.abs(M.X) <= 0.6) & (np.abs(M.Z) <= 0.6) & (M.Y >= 6) & (M.Y < 11)
    M.set(stem, LEAF_LO)
    l1 = ell(M, (-3.0, 11.5, 0), (3.6, 1.8, 2.4)) & (M.m == 0)
    l2 = ell(M, (3.0, 12.8, 0), (3.6, 1.8, 2.4)) & (M.m == 0)
    M.set(l1, LEAF)
    M.set(l2, LEAF_HI)
    return M, Camera(yaw=-15, pitch=16)


def ic_leaf():
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    d = np.array([0.7, 0.7, 0]) / math.sqrt(0.98)
    P = np.stack([M.X, M.Y, M.Z], -1)
    t = P @ d
    perp = np.abs(M.X * -d[1] + M.Y * d[0])
    leaf = (perp <= 3.8 * np.sqrt(np.clip(1 - (t / 7.5) ** 2, 0, 1))) & (np.abs(M.Z) <= 1.0)
    M.set(leaf, '#5DAA45')
    M.set(leaf & (perp < 0.5), '#3F7D35')
    M.set(leaf & (M.X * -d[1] + M.Y * d[0] > 0.6) & (M.Z > 0.2), '#86C761')
    stem = (perp < 0.55) & (t < -6.5) & (t > -9) & (np.abs(M.Z) <= 0.6)
    M.set(stem, '#3F7D35')
    return M, Camera(yaw=-10, pitch=8)


def ic_chest():
    M = M_((-9, -1, -7), (9, 14, 7), res=2)
    box = (np.abs(M.X) <= 7.5) & (M.Y >= 0) & (M.Y < 6.5) & (np.abs(M.Z) <= 5)
    M.set(box, WOOD)
    lid = (np.abs(M.X) <= 7.5) & (M.Y >= 6.5) & ((M.Y - 6.5) ** 2 / 4.5 ** 2 + M.Z ** 2 / 5 ** 2 <= 1)
    M.set(lid, WOOD_HI)
    for sx in (-5.5, 0, 5.5):
        trim = (M.m > 0) & (np.abs(M.X - sx) <= 0.8)
        M.set(trim, GOLD)
    M.set((M.m > 0) & (np.abs(M.Y - 6.5) <= 0.5), GOLD_LO)
    lock = (np.abs(M.X) <= 1.4) & (np.abs(M.Y - 5.6) <= 1.6) & (M.Z > 4.5) & (M.Z <= 5.8)
    M.set(lock, GOLD_HI)
    return M, Camera(yaw=-22, pitch=14)


def ic_lock():
    M = M_((-7, -1, -4), (7, 16, 4), res=2)
    body = (np.abs(M.X) <= 5.4) & (M.Y >= 0) & (M.Y < 8) & (np.abs(M.Z) <= 2.4)
    M.set(body, '#E5B44C')
    r = np.sqrt(M.X ** 2 + (M.Y - 8) ** 2)
    shackle = (r <= 4.2) & (r >= 2.6) & (M.Y >= 8) & (np.abs(M.Z) <= 1.0)
    shackle |= ((np.abs(np.abs(M.X) - 3.4) <= 0.8) & (M.Y >= 6) & (M.Y < 8) & (np.abs(M.Z) <= 1.0))
    M.set(shackle, '#8E8A86')
    kh = (np.abs(M.X) <= 0.8) & (np.abs(M.Y - 4) <= 1.6) & (M.Z > 1.8)
    M.set(kh & (M.m > 0), '#6B4A1E')
    return M, Camera(yaw=-15, pitch=10)


def ic_paw():
    M = M_((-9, -9, -2), (9, 9, 2), res=2)
    pad = ell(M, (0, -2.5, 0), (4.6, 3.6, 1.4))
    toes = np.zeros(M.m.shape, bool)
    for (x, y) in ((-5.2, 2.0), (-1.9, 4.6), (1.9, 4.6), (5.2, 2.0)):
        toes |= ell(M, (x, y, 0), (1.9, 2.3, 1.4))
    M.set(pad | toes, '#7A5440')
    return M, Camera(yaw=-8, pitch=6)


def ic_steps():
    M = M_((-10, -10, -2), (10, 10, 2), res=2)
    def print_(cx, cy, ang):
        ca, sa = math.cos(ang), math.sin(ang)
        X = (M.X - cx) * ca + (M.Y - cy) * sa
        Y = -(M.X - cx) * sa + (M.Y - cy) * ca
        sole = ((X / 2.4) ** 2 + ((Y - 0.4) / 3.0) ** 2 <= 1) & (np.abs(M.Z) <= 1.0)
        heel = ((X / 1.9) ** 2 + ((Y + 4.2) / 1.7) ** 2 <= 1) & (np.abs(M.Z) <= 1.0)
        toes = np.zeros(M.m.shape, bool)
        for (tx, ty, tr) in ((-1.5, 4.2, 0.9), (0.1, 4.8, 0.95), (1.6, 4.3, 0.8)):
            toes |= ((X - tx) ** 2 + (Y - ty) ** 2 <= tr ** 2) & (np.abs(M.Z) <= 1.0)
        return sole | heel | toes
    M.set(print_(-3.4, -2.2, 0.22), '#4F9A45')
    M.set(print_(3.4, 2.6, -0.18), '#6CB25A')
    return M, Camera(yaw=-6, pitch=6)


def ic_potion():
    M = M_((-7, -1, -7), (7, 17, 7), res=2)
    bottle = ell(M, (0, 5.5, 0), (5.0, 5.4, 5.0))
    neck = cyl(M, (0, 11.5, 0), 1.8, 4.0)
    M.set(bottle | neck, '#F6D6DC')
    liq = bottle & (M.Y < 7.4)
    M.set(liq, '#E2525E')
    M.set(liq & (M.X < -1.5) & (M.Y > 4) & (M.Z > 1), '#F58C96')
    M.set(cyl(M, (0, 14.2, 0), 2.2, 2.0), WOOD)
    return M, Camera(yaw=-15, pitch=14)


def ic_trophy():
    M = M_((-9, -1, -6), (9, 17, 6), res=2)
    cup = (np.sqrt(M.X ** 2 + M.Z ** 2) <= 3.0 + (M.Y - 6) * 0.42) & (M.Y >= 6) & (M.Y < 14)
    M.set(cup, GOLD)
    M.set(cup & (M.X < -1.5), GOLD_HI)
    stem = cyl(M, (0, 4.5, 0), 1.2, 3.0)
    base = (np.abs(M.X) <= 4.2) & (np.abs(M.Z) <= 3.0) & (M.Y >= 0) & (M.Y < 3.2)
    M.set(stem | base, GOLD_LO)
    for s in (-1, 1):
        r = np.sqrt((M.X - s * 6.2) ** 2 + (M.Y - 11) ** 2)
        h = (r <= 2.6) & (r >= 1.4) & (np.abs(M.Z) <= 0.7) & (s * (M.X - s * 6.2) > -1.0)
        M.set(h & (M.m == 0), GOLD)
    return M, Camera(yaw=-15, pitch=12)


def ic_bell():
    M = M_((-8, -1, -8), (8, 16, 8), res=2)
    b = (np.sqrt(M.X ** 2 + M.Z ** 2) <= 2.5 + (12.5 - M.Y) * 0.42) & (M.Y >= 3) & (M.Y < 12.5)
    b |= ell(M, (0, 12.5, 0), (2.6, 1.8, 2.6))
    M.set(b, GOLD)
    M.set(b & (M.X < -1.5), GOLD_HI)
    rim = (np.sqrt(M.X ** 2 + M.Z ** 2) <= 7.0) & (M.Y >= 2) & (M.Y < 3.6)
    M.set(rim, GOLD_LO)
    M.set(ell(M, (0, 1.2, 0), (1.5, 1.5, 1.5)), GOLD_DK)
    return M, Camera(yaw=-15, pitch=12)


def ic_palette():
    M = M_((-10, -9, -2), (10, 9, 2), res=2)
    p = ((M.X / 8.6) ** 2 + (M.Y / 6.8) ** 2 <= 1) & (np.abs(M.Z) <= 0.9)
    p &= ~(((M.X - 4.6) ** 2 + (M.Y + 2.8) ** 2) < 2.4 ** 2)
    M.set(p, '#D7B48A')
    for (x, y, c) in ((-4.8, 1.6, '#E2493D'), (-1.6, 4.0, '#F3B83A'), (2.4, 4.0, '#6CB25A'),
                      (5.2, 1.2, '#3E8FD6'), (-4.4, -2.6, '#9975C9')):
        M.set(((M.X - x) ** 2 + (M.Y - y) ** 2 <= 1.6 ** 2) & (M.Z > 0.2) & (M.Z <= 1.6), c)
    return M, Camera(yaw=-8, pitch=6)


def ic_dna():
    """Evolution: two stacked chevrons / sparkle."""
    M = M_((-9, -9, -2), (9, 9, 2), res=2)
    a = np.arctan2(M.X, M.Y)
    r = np.sqrt(M.X ** 2 + M.Y ** 2)
    k = np.cos(4 * a)
    s = (r <= 3.0 + 5.4 * np.clip(k, 0, 1) ** 2.2) & (np.abs(M.Z) <= 1.6)
    M.set(s, '#F4B84E')
    M.set(s & (r < 3.2), '#FFE5A2')
    s2 = ((M.X - 6) ** 2 + (M.Y - 6) ** 2 <= 2.2) & (np.abs(M.Z) <= 1.2)
    M.set(s2, '#FFE5A2')
    return M, Camera(yaw=0, pitch=0)


def ic_hat():
    M, _ = explorer_hat()
    return M, Camera(yaw=-20, pitch=14)


def ic_crown():
    M, _ = crown(False)
    return M, Camera(yaw=-15, pitch=16)


def ic_house_habitat():
    M = M_((-9, -1, -9), (9, 14, 9), res=2)
    base = (np.abs(M.X) <= 8) & (np.abs(M.Z) <= 8) & (M.Y >= 0) & (M.Y < 2)
    M.set(base, '#7DBA5A')
    M.set(base & (M.Y < 1), '#8D6748')
    tree = ell(M, (-3.5, 8.5, -2), (4.0, 4.0, 4.0))
    M.set(tree, '#5DAA45')
    M.set(cyl(M, (-3.5, 3.5, -2), 0.9, 3.0), WOOD_LO)
    flower(M, (3.5, 3.0, 3.0), n=(0, 0.5, 1), size=1.6)
    return M, Camera(yaw=-20, pitch=18)


def ic_warning():
    M = M_((-9, -1, -2), (9, 16, 2), res=2)
    tri = (np.abs(M.X) <= (14.5 - M.Y) * 0.58) & (M.Y >= 0) & (M.Y < 14.5) & (np.abs(M.Z) <= 1.0)
    M.set(tri, '#F2B544')
    ex = (np.abs(M.X) <= 0.9) & (M.Y >= 4.8) & (M.Y < 10.5) & (M.Z > 0.2)
    ex |= (np.abs(M.X) <= 0.9) & (M.Y >= 1.8) & (M.Y < 3.6) & (M.Z > 0.2)
    M.set(ex & (M.m > 0), '#5B3A1E')
    return M, Camera(yaw=0, pitch=4)


def ic_xp():
    return ic_star('#F4B84E', '#FFE29A')


ICON_BUILDERS = {
    'coin': ic_coin, 'gem': ic_gem, 'heart': ic_heart, 'heart_empty': lambda: ic_heart('#EAD9C8', '#F6EADF'),
    'home': ic_house, 'journey': ic_map, 'bag': ic_backpack, 'shop': ic_stall, 'evodex': ic_book,
    'play': ic_ball, 'inspect': ic_magnifier, 'settings': ic_gear, 'mail': ic_mail, 'pin': ic_pin,
    'star': ic_star, 'wearables': ic_hat, 'consumables': ic_flask, 'decorations': ic_sprout,
    'care': ic_leaf, 'habitats': ic_house_habitat, 'chest': ic_chest, 'lock': ic_lock, 'paw': ic_paw,
    'steps': ic_steps, 'potion': ic_potion, 'trophy': ic_trophy, 'bell': ic_bell, 'palette': ic_palette,
    'evolve': ic_dna, 'crown': ic_crown, 'warning': ic_warning, 'xp': ic_xp,
}


def platform():
    """Round wooden dais used as the Bag / Create preview stand."""
    M = M_((-12, -1, -12), (12, 5, 12), res=2)
    r = np.sqrt(M.X ** 2 + M.Z ** 2)
    rng = np.random.default_rng(4)
    top = (r <= 9.5) & (M.Y >= 0) & (M.Y < 2.4)
    M.set(top, '#B58050')
    ring = top & (r > 8.2)
    M.set(ring, '#8E8A86')
    M.set(ring & (rng.random(M.m.shape) > 0.5), '#A39D94')
    planks = top & (r <= 8.2) & (M.Y >= 1.9)
    k = np.floor(M.X / 1.6).astype(int) % 3
    M.set(planks & (k == 0), '#C08A57')
    M.set(planks & (k == 1), '#B07A48')
    M.set(planks & (k == 2), '#CB9763')
    M.set(planks & (np.abs(M.X % 1.6) < 0.25), '#8A5A34')
    return M, Camera(yaw=0, pitch=20)


ITEM_BUILDERS['platform'] = platform

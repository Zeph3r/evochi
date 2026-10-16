"""Village Tales, Chapter 1 item art (Quest Bible §4): seven quest materials and three story rewards.

Same conventions as items.py: each builder returns (Model, Camera) with literal hex materials,
rendered by build_village.py with the shared item outline. The story-reward silhouettes are kept
distinct from shop items on purpose (the Hearth is not the Explorer Lantern, the Bloom is not the
Sunlit Flower).
"""
from __future__ import annotations

import numpy as np

from voxel import Model, Camera
from characters import tube

GLOW = '#FFE29A'
GOLD, GOLD_HI, GOLD_LO = '#E8B956', '#FFE5A2', '#C8832C'
CREAM, CREAM_LO = '#FBF5E8', '#E9DCC0'
WALNUT, WALNUT_LO = '#8D5D3B', '#6E4529'
NAVY = '#203B50'
COPPER, COPPER_HI = '#C69469', '#E2B488'
SAGE, SAGE_DK = '#7F9871', '#43523D'
MINT, MINT_HI = '#9FE3CF', '#D6F7EC'


def M_(lo, hi, res=2):
    return Model(lo, hi, [], res=res)


def put(M, mask, col, glow=None, empty=False):
    if empty:
        mask = mask & (M.m == 0)
    M.set(mask, col)
    if glow is not None:
        M.glow[mask] = glow
    return mask


# ------------------------------------------------------------------ materials
def dawn_dew_vial():
    M = M_((-7, -1, -7), (7, 17, 7))
    r = np.maximum(np.abs(M.X) * 0.92 + np.abs(M.Z) * 0.38, np.abs(M.Z) * 0.92 + np.abs(M.X) * 0.38)  # octagonal facets
    body = (r <= 4.4) & (M.Y >= 0.5) & (M.Y < 9.5)
    put(M, body, '#CFEFFB')
    put(M, body & (M.Y < 6.0), '#7FC4E8')
    put(M, body & (M.Y < 6.0) & (M.Y >= 5.0), '#A7DCF3')
    put(M, body & (M.X < -2.4) & (M.Y > 2.0), '#EAF8FF')
    glint = (np.abs(M.X - 1.0) < 1.0) & (np.abs(M.Y - 3.4) < 1.0) & (np.abs(M.Z) < 1.0)
    put(M, glint, GLOW, glow=1.0)
    shoulder = (r <= 4.4 - (M.Y - 9.5) * 1.4) & (M.Y >= 9.5) & (M.Y < 11.0)
    put(M, shoulder, '#CFEFFB')
    neck = (r <= 2.0) & (M.Y >= 11.0) & (M.Y < 13.0)
    put(M, neck, '#BFE6F5')
    put(M, (r <= 2.6) & (M.Y >= 11.3) & (M.Y < 12.2), GOLD)
    cork = (r <= 1.7) & (M.Y >= 13.0) & (M.Y < 15.0)
    put(M, cork, '#B07A48')
    loop = ((M.X - 3.2) ** 2 + (M.Y - 12.6) ** 2 <= 1.6 ** 2) & ((M.X - 3.2) ** 2 + (M.Y - 12.6) ** 2 >= 0.8 ** 2) & (np.abs(M.Z) <= 0.5)
    put(M, loop, GOLD, empty=True)
    return M, Camera(yaw=-25, pitch=16)


def lumenbud_sprig():
    M = M_((-8, -1, -6), (8, 17, 6))
    stem = tube(M, [(-2.0, 0.5, 0), (-1.0, 5.0, 0.3), (0.6, 9.5, 0.2), (1.2, 13.0, 0)], [0.75, 0.7, 0.6, 0.5], p=2.0)
    put(M, stem, '#4E6B45')
    for (c, s) in (((-1.0, 6.5, 0.6), 1.5), ((2.6, 10.2, 0.4), 1.6), ((0.9, 14.0, 0.2), 1.8)):
        b = (np.abs(M.X - c[0]) <= s) & (np.abs(M.Y - c[1]) <= s) & (np.abs(M.Z - c[2]) <= s)
        put(M, b, '#F4C04E', glow=0.85)
        put(M, b & (M.Y > c[1] + s * 0.4), GOLD_HI, glow=1.0)
    twig = tube(M, [(-1.0, 5.6, 0.2), (-0.2, 6.2, 0.4)], [0.5, 0.5]) | tube(M, [(0.9, 10.0, 0.2), (2.0, 10.2, 0.3)], [0.5, 0.5])
    put(M, twig, '#4E6B45', empty=True)
    leaf = (((M.X + 4.0) / 3.4) ** 2 + ((M.Y - 9.0) / 1.6) ** 2 <= 1) & (np.abs(M.Z - 0.2 - (M.X + 4.0) * 0.25) <= 0.6)
    curl = ((M.X + 7.0) ** 2 + (M.Y - 10.0) ** 2 <= 1.3 ** 2) & ((M.X + 7.0) ** 2 + (M.Y - 10.0) ** 2 >= 0.5 ** 2) & (np.abs(M.Z + 0.4) <= 0.6)
    put(M, leaf | curl, SAGE, empty=True)
    put(M, leaf & (np.abs(M.Y - 9.0) < 0.3), SAGE_DK)
    return M, Camera(yaw=-15, pitch=14)


def windprint_paper():
    M = M_((-9, -1, -7), (9, 9, 7))
    # two folded panels meeting at a ridge, like a half-open card lying flat
    t = np.abs(M.X)
    panel = (t <= 7.0) & (np.abs(M.Z) <= 5.4) & (np.abs(M.Y - (1.0 + (7.0 - t) * 0.32)) <= 0.45)
    put(M, panel, CREAM)
    put(M, panel & (M.X < 0), '#F4ECDB')
    put(M, panel & (t < 0.6), CREAM_LO)
    # mint wind spiral on the right panel
    u, v = M.X - 3.6, M.Z
    rr = np.sqrt(u ** 2 + v ** 2)
    th = np.arctan2(v, u)
    spiral = (np.abs(((rr - 0.55 * (th + np.pi)) % 2.0) - 1.0) < 0.38) & (rr < 3.6) & (rr > 0.5)
    put(M, panel & spiral & (M.X > 0.6), '#5FC4B6')
    put(M, panel & (np.abs(M.Z - 3.2) < 0.4) & (M.X < -1.5) & (M.X > -6) & ((np.floor(M.X) % 2) == 0), '#9AD9CF')
    pin = (np.abs(M.X + 6.0) <= 0.7) & (np.abs(M.Z + 4.4) <= 0.7) & (M.Y > 1.0) & (M.Y < 3.6)
    put(M, pin, COPPER)
    put(M, pin & (M.Y > 2.8), '#D85F51')
    return M, Camera(yaw=-20, pitch=38)


def sealed_trail_letter():
    M = M_((-9, -1, -7), (9, 5, 7))
    env = (np.abs(M.X) <= 7.4) & (np.abs(M.Z) <= 5.0) & (M.Y >= 0) & (M.Y < 1.2)
    put(M, env, CREAM)
    border = env & ((np.abs(M.X) > 6.6) | (np.abs(M.Z) > 4.2))
    put(M, border, WALNUT)
    flap = env & (M.Y >= 0.7) & (np.abs(M.Z + 0.5) < (7.4 - np.abs(M.X)) * 0.62) & (M.Z < 0.0)
    put(M, flap, '#F1E6CF')
    seal = ((M.X ** 2 + (M.Z - 0.3) ** 2) <= 2.6 ** 2) & (M.Y >= 0.8) & (M.Y < 2.2)
    put(M, seal, NAVY)
    put(M, seal & ((M.X ** 2 + (M.Z - 0.3) ** 2) > 2.0 ** 2), '#2F5571')
    wing = seal & (M.Y >= 1.6) & ((np.abs(M.X) < 1.6) & (np.abs(M.Z - 0.3 - np.abs(M.X) * 0.45) < 0.45))
    put(M, wing, CREAM)
    return M, Camera(yaw=-15, pitch=40)


def echo_rubbing():
    M = M_((-9, -1, -9), (9, 5, 9))
    sheet = (np.abs(M.X) <= 6.8) & (np.abs(M.Z) <= 6.8) & (M.Y >= 0) & (M.Y < 0.8)
    rng = np.random.default_rng(5)
    put(M, sheet, '#45444C')
    put(M, sheet & (rng.random(M.m.shape) > 0.6), '#3A3940')
    put(M, sheet & ((np.abs(M.X) > 6.0) | (np.abs(M.Z) > 6.0)), '#5A5862')
    top = sheet & (M.Y >= 0.3)
    rune = (np.abs(M.X) < 0.45) & (np.abs(M.Z) < 4.2)
    rune |= (np.abs(M.Z + 2.4 - M.X * 0.9) < 0.45) & (np.abs(M.X) < 2.8)
    rune |= (np.abs(M.Z - 2.2 + M.X * 0.9) < 0.45) & (np.abs(M.X) < 2.8)
    rune |= (np.abs(np.sqrt(M.X ** 2 + M.Z ** 2) - 4.6) < 0.4) & (M.Z < -1.0)
    put(M, top & rune, GOLD, glow=0.9)
    return M, Camera(yaw=-15, pitch=42)


def waystone_core():
    M = M_((-7, -1, -7), (7, 13, 7))
    rng = np.random.default_rng(12)
    cube = (np.abs(M.X) <= 4.6) & (np.abs(M.Z) <= 4.6) & (M.Y >= 0.5) & (M.Y < 9.7)
    # chamfered edges so it reads as carved stone, not a box
    e = 4.6 - 1.1
    bev = ((np.abs(M.X) > e) & (np.abs(M.Z) > e)) | ((np.abs(M.X) > e) & ((M.Y > 8.6) | (M.Y < 1.6))) | \
          ((np.abs(M.Z) > e) & ((M.Y > 8.6) | (M.Y < 1.6)))
    cube &= ~bev
    put(M, cube, '#F1E7D2')
    put(M, cube & (rng.random(M.m.shape) > 0.7), '#E6DAC0')
    put(M, cube & (M.Y < 2.0), '#DCCFB4')
    # three carved channels down the front, glowing gold, meeting a mint centre
    front = cube & (M.Z > 3.8)
    for cx in (-2.4, 0.0, 2.4):
        put(M, front & (np.abs(M.X - cx) < 0.45) & (M.Y > 1.8) & (M.Y < 8.6), GOLD, glow=0.9)
    put(M, cube & (M.Y > 9.0) & ((np.abs(M.X) < 0.45) | (np.abs(M.Z) < 0.45)), GOLD, glow=0.9)
    put(M, front & (np.abs(M.X) < 1.5) & (np.abs(M.Y - 5.0) < 1.5), MINT, glow=1.0)
    put(M, front & (np.abs(M.X) < 0.7) & (np.abs(M.Y - 5.0) < 0.7), MINT_HI, glow=1.0)
    side = cube & (M.X > 3.8)
    put(M, side & (np.abs(M.Z) < 0.45) & (M.Y > 1.8) & (M.Y < 8.6), GOLD, glow=0.9)
    return M, Camera(yaw=-30, pitch=20)


def glowbloom_essence():
    M = M_((-7, -1, -7), (7, 17, 7))
    r = np.sqrt(M.X ** 2 + M.Z ** 2)
    yy = M.Y - 5.0
    drop = (r <= np.where(yy < 0, np.sqrt(np.clip(25 - yy ** 2, 0, None)), 5.0 - yy * 0.62)) & (M.Y >= 0.2) & (M.Y < 12.0)
    put(M, drop, '#A9E5DA')
    put(M, drop & (M.X < -2.0) & (M.Y > 3.0), '#D9F6EF')
    put(M, drop & (M.Y < 2.4), '#86CFC2')
    M.m[drop & (M.Z > 3.2) & (np.abs(M.X) < 3.0) & (M.Y > 2.0) & (M.Y < 9.4)] = 0   # a window into the jar
    leaf = (((M.X - 0.2) / 2.2) ** 2 + ((M.Y - 5.6) / 3.4) ** 2 <= 1) & (np.abs(M.Z - 2.0) <= 0.8)
    put(M, leaf, '#F2FFD6', glow=1.0)
    put(M, leaf & (np.abs(M.X - 0.2) < 0.4), '#B7EA8C', glow=1.0)
    put(M, drop & (M.Z > 1.0) & (M.Z <= 3.2) & ~leaf & (M.m == 0), '#CFF3EA')
    cork = (r <= 1.5) & (M.Y >= 12.0) & (M.Y < 14.2)
    put(M, cork, '#B07A48')
    put(M, (r <= 2.0) & (M.Y >= 11.6) & (M.Y < 12.4), GOLD)
    return M, Camera(yaw=-25, pitch=16)


# ------------------------------------------------------------------ rewards
def firefly_hearth(scene=False):
    M = M_((-10, -1, -10), (10, 16, 10))
    r = np.sqrt(M.X ** 2 + M.Z ** 2)
    rng = np.random.default_rng(9)
    stump = (r <= 6.0 + 0.6 * np.sin(np.arctan2(M.Z, M.X) * 7)) & (M.Y >= 0) & (M.Y < 9.0)
    put(M, stump, WALNUT)
    put(M, stump & (rng.random(M.m.shape) > 0.55), '#7A4E2E')
    put(M, stump & (M.Y < 1.2), WALNUT_LO)
    rings = stump & (M.Y >= 8.2)
    put(M, rings, '#D9B07A')
    put(M, rings & (np.abs(((r + 0.3) % 1.8) - 0.9) < 0.3), '#B98955')
    moss = rings & (M.X < -1.0) & (M.Z < 1.5) & (rng.random(M.m.shape) > 0.25)
    put(M, moss | (stump & (M.Y > 7.5) & (M.X < -4.6)), '#6FB24E')
    # hollow doorway lit from inside
    door = (np.abs(M.X - 0.4) <= 2.4) & (M.Y < 5.8 - (np.abs(M.X - 0.4) / 2.4) ** 2 * 1.6) & (M.Y >= 0.5) & (M.Z > 0)
    inner = door & (r < 4.8)
    M.m[door & (r >= 4.8)] = 0
    put(M, inner & (r >= 3.6), '#FFC960', glow=0.95)
    put(M, (np.abs(M.X - 0.4) <= 2.9) & (M.Y < 6.4 - (np.abs(M.X - 0.4) / 2.9) ** 2 * 1.6) & (M.Y >= 0.5) & (M.Z > 0) & stump & ~door & (r > 5.2), '#5E3A24')
    roots = ((np.abs(M.X - 6.4) < 1.0) | (np.abs(M.X + 6.2) < 1.0) | (np.abs(M.Z + 6.2) < 1.0)) & (M.Y < 1.4) & (r < 7.6) & (r > 5.0)
    put(M, roots, WALNUT_LO, empty=True)
    # three golden cubic fireflies
    for (fx, fy, fz) in ((4.6, 11.0, 3.0), (-3.4, 13.4, 1.2), (1.2, 14.8, -3.0)):
        f = (np.abs(M.X - fx) <= 0.75) & (np.abs(M.Y - fy) <= 0.75) & (np.abs(M.Z - fz) <= 0.75)
        put(M, f, GLOW, glow=1.0)
        put(M, (np.abs(M.X - fx) <= 0.3) & (np.abs(M.Y - fy - 1.0) <= 0.3) & (np.abs(M.Z - fz) <= 0.3), '#FFF6D2', glow=1.0)
    return M, Camera(yaw=-20, pitch=18)


def windtrail_mantle():
    M = M_((-10, -1, -7), (10, 17, 7))
    # a short cape seen from the back, flaring out toward the hem, with a cream trail embroidery
    flare = 4.2 + (13.0 - M.Y) * 0.36
    cape = (np.abs(M.X) <= flare) & (M.Y >= 1.0) & (M.Y < 13.0) & (np.abs(M.Z + 0.08 * M.X ** 2 * 0.1) <= 0.8)
    hem = (M.Y < 1.0 + 0.8 * np.abs(np.sin(M.X * 0.9)))
    cape &= ~hem
    put(M, cape, '#7FB8DE')
    put(M, cape & (np.abs(M.X) > flare - 1.3), '#5E9CC8')
    put(M, cape & (M.X < -1.0) & (M.Y > 6.0) & (np.abs(M.X) < flare - 1.3), '#A8D2EE')
    path = cape & (np.abs(M.X - 2.4 * np.sin(M.Y * 0.55)) < 0.45) & (M.Y > 2.5) & (M.Y < 11.5)
    dots = cape & (np.abs(M.X + 3.5 - 1.2 * np.sin(M.Y * 0.8)) < 0.45) & ((np.floor(M.Y) % 2) == 0) & (M.Y > 3.0) & (M.Y < 9.0)
    put(M, path | dots, CREAM)
    collar = (np.abs(M.X) <= 5.0) & (M.Y >= 12.4) & (M.Y < 15.0) & (np.abs(M.Z) <= 1.2)
    put(M, collar, '#5E9CC8')
    put(M, collar & (M.Y >= 14.2), '#A8D2EE')
    for cx in (-3.6, 3.6):
        cl = ((M.X - cx) ** 2 + (M.Y - 13.4) ** 2 <= 1.3 ** 2) & (np.abs(M.Z - 1.0) <= 0.8)
        put(M, cl, COPPER)
        put(M, cl & (M.Y > 13.8), COPPER_HI)
    return M, Camera(yaw=-18, pitch=10)


def waystone_bloom():
    M = M_((-9, -1, -9), (9, 22, 9))
    r = np.sqrt(M.X ** 2 + M.Z ** 2)
    sq = np.maximum(np.abs(M.X), np.abs(M.Z))
    plinth = (sq <= 3.6 - (M.Y > 6.0) * 0.6) & (M.Y >= 0.8) & (M.Y < 7.4)
    base = (sq <= 4.8) & (M.Y >= 0) & (M.Y < 1.6)
    capst = (sq <= 4.4) & (M.Y >= 7.4) & (M.Y < 8.6)
    put(M, plinth, '#EDEAE2')
    put(M, base | capst, '#D8D3C8')
    put(M, plinth & (M.X < -2.4), '#F7F5F0')
    groove = plinth & (np.abs(M.Y - 4.0) < 0.35) & (sq > 3.0)
    put(M, groove, MINT, glow=0.8)
    # floating crystal blossom: five faceted mint petals around a gold heart
    from characters import spike
    c = np.array([0.0, 12.6, 0.0])
    for i in range(6):
        ang = i * 2 * np.pi / 6 + 0.25
        d = np.array([np.cos(ang), 0.9, np.sin(ang)])
        pet = spike(M, c + np.array([np.cos(ang), 0, np.sin(ang)]) * 0.8, d, 6.2, 1.9, 0.35, twist=0.4)
        put(M, pet, '#A8EBD4', glow=0.35)
        tipm = spike(M, c + d / np.linalg.norm(d) * 3.4, d, 3.0, 1.0, 0.3, twist=0.4) & pet
        put(M, tipm, MINT_HI, glow=0.5)
    heart = (np.abs(M.X) <= 1.6) & (np.abs(M.Y - 14.0) <= 1.6) & (np.abs(M.Z) <= 1.5)
    put(M, heart, GOLD, glow=1.0)
    put(M, heart & (M.Y > 14.9), GOLD_HI, glow=1.0)
    sp = ((M.Y > 9.6) & (M.Y < 10.4) & (r > 4.6) & (r < 5.4) & ((np.floor(np.degrees(np.arctan2(M.Z, M.X)) / 40) % 2) == 0))
    put(M, sp, '#FFF6D2', glow=1.0)
    return M, Camera(yaw=-25, pitch=16)


VILLAGE_ITEMS = {
    'q_dawn_dew_vial': dawn_dew_vial, 'q_lumenbud_sprig': lumenbud_sprig, 'q_windprint_paper': windprint_paper,
    'q_sealed_trail_letter': sealed_trail_letter, 'q_echo_rubbing': echo_rubbing, 'q_waystone_core': waystone_core,
    'q_glowbloom_essence': glowbloom_essence,
    'reward_firefly_hearth': firefly_hearth, 'reward_windtrail_mantle': windtrail_mantle,
    'reward_waystone_bloom': waystone_bloom,
}

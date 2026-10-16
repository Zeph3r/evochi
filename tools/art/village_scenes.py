"""Village Tales, Chapter 1 scenes (Quest Bible §2): Sunlit Village Square (day_dim / lamp_lit /
waystone_restored), Mira's Glasshouse, Bram's Lampwright Workshop, the Trail Guild Lodge and the
Waystone close-up. Same voxel language and layered renderer as the Sunlit Meadow.

Palette (Bible §2): grass #7F9871, sky #B8D5D6, path #F3E5C9, wood #C69469, shadow #8D5D3B,
gold #E8B956, roof #B76B4D.
"""
from __future__ import annotations

import json
import math
import os
import time

import numpy as np
from PIL import Image

from voxel import Model, Camera, project_px, save_rgba
import scenes as S
from scenes import Painter, Layer, Scene, tree, daisy, grass_tufts, heightmap_fill, terrace_cliffs, make_fit, \
    sky_image, render_layer, composite, GRASS, STONE, LEAVES, WATER

V_GRASS = ['#86B566', '#7FAE5F', '#8DBD6C', '#79A85A', '#93C271']
PATH = ['#F3E5C9', '#EADAB8', '#F7ECD6']
COBBLE = ['#D9D2C3', '#CBC3B2', '#E3DDCF', '#BDB4A2']
WOOD = ['#C69469', '#B9875C', '#D2A176']
WALNUT = ['#8D5D3B', '#7E5133', '#986642']
ROOF = ['#B76B4D', '#A95F43', '#C27658']
PLASTER = ['#F3E5C9', '#EEDDBD', '#F7ECD8']
GLASS = ['#D3EEF3', '#C3E6EE', '#E2F5F8']
SAGE = ['#7F9871', '#76906A']
NAVY = ['#203B50', '#284A63']
GOLD = '#E8B956'
LAMP_ON = ['#FFD46A', '#FFE08A']
LAMP_OFF = ['#8C8A78', '#7D7B6A']
MINT_GLOW = ['#9FE3CF', '#BDF2E2']


def box(M, lo, hi):
    return (M.X >= lo[0]) & (M.X < hi[0]) & (M.Y >= lo[1]) & (M.Y < hi[1]) & (M.Z >= lo[2]) & (M.Z < hi[2])


def gable_house(M, P, x0, x1, z0, z1, wall_h, roof_h, walls, roof, oh=1.0, ridge='x', y0=0.0):
    """Solid house with a gabled roof. ridge='x' means the ridge runs along x (front faces +z)."""
    body = box(M, (x0, y0, z0), (x1, y0 + wall_h, z1))
    P.fill(body, walls)
    if ridge == 'x':
        zc, half = (z0 + z1) / 2, (z1 - z0) / 2 + oh
        top = y0 + wall_h + roof_h * (1 - np.abs(M.Z - zc) / half)
        r = (M.X >= x0 - oh) & (M.X < x1 + oh) & (np.abs(M.Z - zc) <= half) & (M.Y >= y0 + wall_h - 0.5) & (M.Y < top)
        gable = (M.X >= x0) & (M.X < x1) & (np.abs(M.Z - zc) <= half - oh) & (M.Y >= y0 + wall_h) & (M.Y < top - 1.0)
    else:
        xc, half = (x0 + x1) / 2, (x1 - x0) / 2 + oh
        top = y0 + wall_h + roof_h * (1 - np.abs(M.X - xc) / half)
        r = (M.Z >= z0 - oh) & (M.Z < z1 + oh) & (np.abs(M.X - xc) <= half) & (M.Y >= y0 + wall_h - 0.5) & (M.Y < top)
        gable = (M.Z >= z0) & (M.Z < z1) & (np.abs(M.X - xc) <= half - oh) & (M.Y >= y0 + wall_h) & (M.Y < top - 1.0)
    P.fill(gable, walls)
    shell = r & ~gable & (M.Y >= top - 1.2)
    P.fill(shell, roof)
    # tile rows
    rows = shell & ((np.floor((M.Y - y0) / 0.8).astype(int) % 2) == 0)
    P.fill(rows, [roof[1]])
    return body


def window(M, P, x, y, z, w, h, face='z', lit=False, frame=WALNUT, glass=None, depth=0.6):
    """Window on the +z (or +x / -x) face of a wall at plane z (x)."""
    if face == 'z':
        fr = (np.abs(M.X - x) <= w / 2 + 0.5) & (np.abs(M.Y - y) <= h / 2 + 0.5) & (M.Z >= z - 0.3) & (M.Z < z + depth)
        pane = (np.abs(M.X - x) <= w / 2) & (np.abs(M.Y - y) <= h / 2) & (M.Z >= z - 0.3) & (M.Z < z + depth)
        bar = pane & ((np.abs(M.X - x) < 0.25) | (np.abs(M.Y - y) < 0.25))
    else:
        sgn = 1 if face == '+x' else -1
        fr = (np.abs(M.Z - z) <= w / 2 + 0.5) & (np.abs(M.Y - y) <= h / 2 + 0.5) & (sgn * (M.X - x) >= -0.3) & (sgn * (M.X - x) < depth)
        pane = (np.abs(M.Z - z) <= w / 2) & (np.abs(M.Y - y) <= h / 2) & (sgn * (M.X - x) >= -0.3) & (sgn * (M.X - x) < depth)
        bar = pane & ((np.abs(M.Z - z) < 0.25) | (np.abs(M.Y - y) < 0.25))
    P.fill(fr & ~pane, frame)
    P.fill(pane, glass or (LAMP_ON if lit else ['#A9C9D6', '#9DBFCD']), glow=0.9 if lit else None)
    P.fill(bar, frame)


def lantern_at(M, P, x, y, z, lit, s=1.0):
    lf = (np.maximum(np.abs(M.X - x), np.abs(M.Z - z)) <= 0.8 * s) & (M.Y >= y - 1.1 * s) & (M.Y < y + 1.1 * s)
    P.fill(lf, LAMP_ON if lit else LAMP_OFF, glow=1.0 if lit else None)
    P.fill(lf & ((M.Y >= y + 0.7 * s) | (M.Y < y - 0.7 * s)), ['#4A3328'])
    cap = (np.maximum(np.abs(M.X - x), np.abs(M.Z - z)) <= 1.1 * s - (M.Y - y - 1.1 * s)) & (M.Y >= y + 1.1 * s) & (M.Y < y + 1.8 * s)
    P.fill(cap, ['#5A3B2A'])


def fireflies(M, P, rng, n, x_range, y_range, z_range):
    for _ in range(n):
        fx, fy, fz = rng.uniform(*x_range), rng.uniform(*y_range), rng.uniform(*z_range)
        f = (np.abs(M.X - fx) <= 0.35) & (np.abs(M.Y - fy) <= 0.35) & (np.abs(M.Z - fz) <= 0.35)
        P.fill(f & (M.m == 0), ['#FFF3B0', '#FFE7A0'], glow=1.0)


# ----------------------------------------------------------------------------
# Sunlit Village Square
# ----------------------------------------------------------------------------
SQUARE_ANCHORS = {   # world points the map pins attach to
    'glasshouse': (-15.5, 9.5, -3.0), 'workshop': (15.5, 9.5, -3.0), 'lodge': (0.0, 13.5, -24.0),
    'waystone': (0.0, 7.5, 0.0), 'lamp': (8.0, 6.5, 11.0), 'market': (-21.0, 4.0, 12.0),
}


def scene_square(w=1170, h=1300, seed=41, state='day_dim'):
    lamp = state in ('lamp_lit', 'waystone_restored')
    restored = state == 'waystone_restored'
    rng = np.random.default_rng(seed)
    cam = Camera(yaw=0, pitch=40, target=(0, 0, -6), persp=96, fov=34)
    layers = []
    # far: terraces, a waterfall and canopy behind the village
    F = Model((-120, -2, -170), (120, 70, -40), [], res=1)
    PF = Painter(F, rng)
    PF.fill((F.Y >= -1) & (F.Y < 0) & (F.Z >= -60) & (F.Z < -40), WATER)
    terrace_cliffs(F, PF, rng, (-120, 120), (-150, -58), 4, 30, steps=4, falls=((-22, 7, -62), (30, 5, -66)), trees=40)
    layers.append(Layer('far', F, blur=5.0, haze=0.22, haze_col='#D6EAEC', inner_alpha=0.15))

    M = Model((-34, -4, -40), (34, 26, 32), [], res=2)
    P = Painter(M, rng)
    xs, zs = M.X[:, 0, 0], M.Z[0, 0, :]
    X2, Z2 = np.meshgrid(xs, zs, indexing='ij')
    H = np.zeros((len(xs), len(zs)))
    heightmap_fill(M, H, V_GRASS, ['#B98955', '#A97C4B'], P, top_th=0.5, base=-4)
    top = (M.Y >= -0.5) & (M.Y < 0)
    R = np.sqrt(X2 ** 2 + Z2 ** 2)
    # paths: down to the gate, up to the lodge, left and right to the two houses
    path2 = ((np.abs(X2 - 0.15 * Z2) < 2.4) & (Z2 > 5)) | ((np.abs(X2) < 2.4) & (Z2 < -5) & (Z2 > -20)) | \
            ((np.abs(Z2 + 1.0) < 2.2) & (np.abs(X2) > 6) & (np.abs(X2) < 12.5))
    P.fill(top & path2[:, None, :], PATH)
    plaza = R < 9.0
    P.fill(top & plaza[:, None, :], COBBLE)
    joints = plaza & ((np.floor(X2 / 1.5) + np.floor(Z2 / 1.0)) % 5 == 0)
    P.fill(top & joints[:, None, :], ['#B1A893'])
    ringm = (R > 8.0) & (R < 9.0)
    P.fill(top & ringm[:, None, :], ['#A89F8C', '#B4AB97'])
    grass_tufts(M, P, H, (~plaza) & (~path2) & (R > 10), 0.05, rng, max_h=0.8, cols=['#93C271', '#86B566', '#9CCB79'])

    # the Waystone: a plinth and a standing stone with three grooves and three brass notches
    plinth = (np.maximum(np.abs(M.X), np.abs(M.Z)) <= 2.6) & (M.Y >= 0) & (M.Y < 0.8)
    P.fill(plinth, ['#C9C2AE', '#BDB5A0'])
    stone = (np.abs(M.X) <= 2.0 - (M.Y > 7.0) * (M.Y - 7.0) * 0.55) & (np.abs(M.Z) <= 1.1) & (M.Y >= 0.8) & (M.Y < 9.0)
    P.fill(stone, ['#E0D6A6', '#D5CA96', '#E8DFB4'])
    P.fill(stone & (M.Y < 2.4) & (M.X < -0.6), SAGE)
    grooves = stone & (M.Z > 0.6) & ((np.abs(M.X + 0.9) < 0.25) | (np.abs(M.X) < 0.25) | (np.abs(M.X - 0.9) < 0.25)) & (M.Y > 2.2) & (M.Y < 7.4)
    P.fill(grooves, MINT_GLOW if restored else ['#6C6A55'], glow=1.0 if restored else None)
    for nx in (-0.75, 0.0, 0.75):
        P.fill((np.abs(M.X - nx * 1.2) < 0.3) & (np.abs(M.Y - 7.9) < 0.3) & (M.Z > 0.6) & (M.Z < 1.4), ['#C69469'])
    if restored:
        halo = (np.abs(np.sqrt(M.X ** 2 + M.Z ** 2) - 3.3) < 0.3) & (M.Y >= 0) & (M.Y < 0.5)
        P.fill(halo, MINT_GLOW, glow=0.9)
        fireflies(M, P, rng, 46, (-14, 14), (2.5, 12), (-16, 10))

    # Mira's Glasshouse (left): low stone base, glass walls and roof on sage frames, pots outside
    gx0, gx1, gz0, gz1 = -21.0, -10.0, -8.0, 2.0
    base = box(M, (gx0, 0, gz0), (gx1, 2.0, gz1))
    P.fill(base, ['#D9CFBE', '#CFC4B0'])
    gl = box(M, (gx0, 2.0, gz0), (gx1, 7.0, gz1))
    P.fill(gl, GLASS)
    zc, half = (gz0 + gz1) / 2, (gz1 - gz0) / 2 + 0.5
    topy = 7.0 + 3.5 * (1 - np.abs(M.Z - zc) / half)
    groof = (M.X >= gx0 - 0.5) & (M.X < gx1 + 0.5) & (np.abs(M.Z - zc) <= half) & (M.Y >= 7.0) & (M.Y < topy)
    P.fill(groof, GLASS)
    frames = (gl | groof) & ((np.abs(((M.X - gx0) % 2.2) - 1.1) > 0.9) | (gl & (np.abs(((M.Y) % 2.5) - 1.25) > 1.05)) |
                             (groof & (np.abs(((M.Z - gz0) % 2.6) - 1.3) > 1.05)))
    P.fill(frames, SAGE)
    P.fill(groof & (M.Y >= topy - 0.7) & (np.abs(M.Z - zc) < 0.5), ['#43523D'])
    P.fill((gl | groof) & ((np.abs(M.X - gx0) < 0.5) | (np.abs(M.X - gx1 + 0.5) < 0.5)), ['#43523D'])
    # plants seen through the panes
    for px in np.arange(gx0 + 1.5, gx1 - 0.5, 2.2):
        leaf = ((M.X - px) ** 2 + (M.Y - 4.2) ** 2 <= 1.0) & (M.Z >= gz1 - 0.2) & (M.Z < gz1 + 0.1)
        P.fill(leaf & gl, ['#6FB24E', '#5EA046'])
    door = (np.abs(M.Z + 3.0) <= 1.3) & (M.Y >= 0) & (M.Y < 4.6) & (M.X >= gx1 - 0.2) & (M.X < gx1 + 0.4)
    P.fill(door, ['#7F9871', '#6E8762'])
    for (px, pz) in ((gx1 + 1.4, 0.8), (gx1 + 1.4, -6.8), (gx0 + 2.0, gz1 + 1.4), (gx0 + 5.0, gz1 + 1.4)):
        pot = ((M.X - px) ** 2 + (M.Z - pz) ** 2 <= 0.8) & (M.Y >= 0) & (M.Y < 1.2)
        P.fill(pot, ['#B76B4D'])
        bush = ((M.X - px) ** 2 + (M.Y - 1.9) ** 2 + (M.Z - pz) ** 2) <= 1.2 ** 2
        P.fill(bush & (M.m == 0), LEAVES)
        daisy(M, P, (px + 0.2, 2.6, pz + 0.5), size=0.45, stem=False)
    # flower-headed weather vane
    vane = (np.abs(M.X + 15.5) < 0.2) & (np.abs(M.Z - zc) < 0.2) & (M.Y >= 10.0) & (M.Y < 13.0)
    P.fill(vane, ['#4A3328'])
    daisy(M, P, (-15.5, 13.6, zc), size=0.8, stem=False)
    lantern_at(M, P, gx1 + 0.9, 5.6, -0.8, lamp, 0.7)

    # Bram's Lampwright Workshop (right): timber walls, clay roof, chimney with a furnace glow
    wx0, wx1, wz0, wz1 = 10.0, 21.0, -8.0, 2.0
    body = gable_house(M, P, wx0, wx1, wz0, wz1, 6.0, 4.5, WALNUT, ROOF, oh=1.0, ridge='z')
    planks = body & ((np.floor(M.Y / 1.0).astype(int) % 3) == 0)
    P.fill(planks, ['#7A4E2E'])
    P.fill(box(M, (wx0, 0, wz0), (wx0 + 0.6, 6.0, wz0 + 0.6)) | box(M, (wx0, 0, wz1 - 0.6), (wx0 + 0.6, 6.0, wz1)), ['#5E3A24'])
    window(M, P, wx0, 3.4, -5.6, 2.2, 2.0, face='-x', lit=True)
    door = (np.abs(M.Z + 1.2) <= 1.3) & (M.Y >= 0) & (M.Y < 4.6) & (M.X >= wx0 - 0.4) & (M.X < wx0 + 0.2)
    P.fill(door, ['#5E3A24', '#6E4529'])
    chim = box(M, (17.0, 6.0, -6.6), (18.8, 13.5, -4.8))
    P.fill(chim, STONE)
    P.fill(box(M, (17.3, 13.0, -6.3), (18.5, 13.6, -5.1)), ['#FF9A4A', '#FFB65C'], glow=1.0)
    sign = box(M, (wx0 - 1.6, 5.2, 1.0), (wx0 - 1.2, 6.6, 2.6))
    P.fill(sign, ['#C69469'])
    lantern_at(M, P, wx0 - 0.9, 5.4, -3.2, lamp, 0.7)

    # Trail Guild Lodge (top): cream plaster with timber beams, clay roof, navy banners, compass
    lx0, lx1, lz0, lz1 = -8.0, 8.0, -30.0, -21.0
    body = gable_house(M, P, lx0, lx1, lz0, lz1, 7.5, 5.0, PLASTER, ROOF, oh=1.2, ridge='x')
    beams = body & ((np.abs(((M.X - lx0) % 4.0) - 2.0) > 1.6) | (np.abs(M.Y - 3.8) < 0.3) | (M.Y > 7.0))
    P.fill(beams & (M.Z > lz1 - 0.6), WALNUT)
    door = (np.abs(M.X) <= 1.6) & (M.Y >= 0) & (M.Y < 5.0) & (M.Z >= lz1 - 0.3) & (M.Z < lz1 + 0.3)
    P.fill(door, ['#5E3A24', '#6E4529'])
    for wx in (-5.0, 5.0):
        window(M, P, wx, 4.6, lz1, 1.8, 1.8, lit=lamp)
    comp = (np.sqrt(M.X ** 2 + (M.Y - 6.6) ** 2) <= 0.9) & (M.Z >= lz1 - 0.2) & (M.Z < lz1 + 0.5)
    P.fill(comp, ['#C69469'])
    P.fill(comp & (np.abs(M.X) < 0.2), [GOLD])
    for bx in (-7.0, 7.0):
        ban = (np.abs(M.X - bx) <= 1.0) & (M.Y >= 2.0) & (M.Y < 6.8) & (M.Z >= lz1 + 0.1) & (M.Z < lz1 + 0.5)
        ban &= ~((M.Y < 2.8) & (np.abs(M.X - bx) < 0.4))
        P.fill(ban, NAVY)
        P.fill(ban & (np.abs(M.Y - 4.8) < 0.5) & (np.abs(M.X - bx) < 0.6), ['#F3E5C9'])
    for wx in (-3.4, 3.4):
        lantern_at(M, P, wx, 5.4, lz1 + 0.8, lamp, 0.65)

    # the nursery lamp by the gate (lit once Quest 1 is done)
    px_, pz_ = 8.0, 11.0
    post = (np.abs(M.X - px_) <= 0.35) & (np.abs(M.Z - pz_) <= 0.35) & (M.Y >= 0) & (M.Y < 6.0)
    P.fill(post, ['#4A3328'])
    lantern_at(M, P, px_, 6.6, pz_, lamp, 0.9)
    if lamp:
        fireflies(M, P, np.random.default_rng(seed + 3), 6, (px_ - 2, px_ + 2), (5, 9), (pz_ - 2, pz_ + 2))
    # honey-wood gate and fences along the bottom
    for gx in (-3.6, 3.4):
        gp = (np.abs(M.X - gx - 0.15 * 14) <= 0.4) & (np.abs(M.Z - 14) <= 0.4) & (M.Y >= 0) & (M.Y < 4.4)
        P.fill(gp, WOOD)
    arch = (np.abs(M.Z - 14) <= 0.35) & (np.abs(M.Y - 4.2 - 0.6 * np.cos((M.X - 2.1) / 3.6 * 1.4)) <= 0.35) & (np.abs(M.X - 2.1) <= 4.0)
    P.fill(arch, WOOD)
    for (a, b) in (((-30, 0, 15.0), (-4.5, 0, 14.0)), ((7.0, 0, 14.0), (30, 0, 15.0))):
        a, b = np.array(a, float), np.array(b, float)
        d = (b - a) / np.linalg.norm(b - a)
        rx, rz = M.X - a[0], M.Z - a[2]
        t = rx * d[0] + rz * d[2]
        perp = np.abs(-rx * d[2] + rz * d[0])
        L = np.linalg.norm(b - a)
        for ry in (1.0, 2.0):
            P.fill((perp <= 0.25) & (t >= 0) & (t <= L) & (np.abs(M.Y - ry) <= 0.25), WOOD)
        posts = (perp <= 0.35) & (t >= 0) & (t <= L) & ((np.abs((t % 3.0) - 1.5) > 1.15)) & (M.Y >= 0) & (M.Y < 2.6)
        P.fill(posts, ['#B9875C'])
    # trees framing the village, flowers in the grass
    for (tx, tz, th_, tr) in ((-27, -14, 7, 4.5), (-25, 6, 5, 3.6), (26, -16, 8, 4.8), (27, 5, 5, 3.5),
                              (-14, -24, 6, 4.0), (15, -25, 6, 4.2), (-31, -30, 7, 5), (31, -30, 7, 5)):
        tree(M, P, (tx, 0, tz), trunk_h=th_, r=tr, rng=rng, leaves=['#6FA552', '#7FB35F', '#5E9646', '#88BC67'])
    for _ in range(70):
        fx, fz = rng.uniform(-32, 32), rng.uniform(-36, 20)
        rr = math.hypot(fx, fz)
        if rr < 10.5 or (abs(fx) > 9 and abs(fx) < 22 and -9 < fz < 3) or (abs(fx) < 9 and -31 < fz < -20) or abs(fx - 0.15 * fz) < 3 and fz > 4:
            continue
        daisy(M, P, (fx, rng.uniform(0.5, 0.9), fz), size=rng.uniform(0.32, 0.45), stem=False)
    # benches around the plaza
    for (bx, bz, rot) in ((-6.0, 6.0, 0), (6.4, -6.0, 0)):
        seat = box(M, (bx - 1.6, 0.9, bz - 0.5), (bx + 1.6, 1.3, bz + 0.5))
        P.fill(seat, WOOD)
        for lx in (bx - 1.2, bx + 1.2):
            P.fill(box(M, (lx - 0.25, 0, bz - 0.4), (lx + 0.25, 0.9, bz + 0.4)), ['#8D5D3B'])
    layers.append(Layer('mid', M, blur=0.0, inner_alpha=0.3))
    sc = Scene('square', cam, w, h, (0.5, 0.58), ('#9CCBD6', '#E2F1EE'), layers, seed=seed, clouds=4)
    sc.slots = SQUARE_ANCHORS
    return sc


# ----------------------------------------------------------------------------
# Interiors: one front-facing room plate each, floor left clear for the villager
# ----------------------------------------------------------------------------
RW, RH, RF = 25.0, 21.0, 18.0   # interior half-width, wall height, floor front edge


def room(M, P, rng, wall_cols, floor_cols, width=15.0, back=-7.0, h=13.0, side=True, beams=True):
    floor = box(M, (-width, -1.0, back), (width, 0.0, 8.0))
    P.fill(floor, floor_cols)
    wall = box(M, (-width, 0.0, back - 1.0), (width, h, back))
    P.fill(wall, wall_cols)
    if side:
        for sx in (-1, 1):
            sw = box(M, (sx * width - (1.0 if sx > 0 else 0), 0, back), (sx * width + (0 if sx > 0 else 1.0), h, 8.0)) if sx < 0 else \
                box(M, (width - 1.0, 0, back), (width, h, 8.0))
            P.fill(sw, wall_cols)
    if beams:
        for bx in np.arange(-width + 3.0, width, 6.0):
            P.fill(box(M, (bx - 0.4, 0.0, back - 0.2), (bx + 0.4, h, back + 0.4)), WALNUT)
        P.fill(box(M, (-width, h - 1.0, back - 0.2), (width, h - 0.2, back + 0.5)), WALNUT)
    return wall


def shelf(M, P, x0, x1, y, z, depth=1.4):
    P.fill(box(M, (x0, y - 0.3, z), (x1, y, z + depth)), WOOD)
    for bx in (x0 + 0.4, x1 - 0.4):
        P.fill(box(M, (bx - 0.2, y - 1.2, z), (bx + 0.2, y - 0.3, z + 0.4)), ['#8D5D3B'])


def pot_plant(M, P, x, y, z, s=1.0, rng=None, flower=None):
    pot = ((M.X - x) ** 2 + (M.Z - z) ** 2 <= (0.8 * s) ** 2) & (M.Y >= y) & (M.Y < y + 1.1 * s)
    P.fill(pot, ['#B76B4D', '#A95F43'])
    P.fill(pot & (M.Y >= y + 0.85 * s), ['#C9805F'])
    bush = ((M.X - x) ** 2 + ((M.Y - y - 1.9 * s) * 1.1) ** 2 + (M.Z - z) ** 2) <= (1.15 * s) ** 2
    P.fill(bush & (M.m == 0), ['#6FB24E', '#5EA046', '#86C56A'])
    if flower:
        daisy(M, P, (x + 0.3 * s, y + 2.6 * s, z + 0.6 * s), size=0.45 * s, petal=flower, stem=False)


def scene_glasshouse(w=1170, h=900, seed=51):
    rng = np.random.default_rng(seed)
    cam = Camera(yaw=0, pitch=9, target=(0, 5.6, -1.0), persp=33, fov=40)
    M = Model((-RW - 1, -2, -10), (RW + 1, RH + 1, RF + 1), [], res=2)
    P = Painter(M, rng)
    floor = box(M, (-RW, -1, -9), (RW, 0, RF))
    P.fill(floor, ['#D9B79A', '#CFA98A', '#E2C3A6'])
    P.fill(floor & ((np.floor(M.X / 1.5) + np.floor(M.Z / 1.5)) % 2 == 0), ['#C99B7A', '#D2A585'])
    # glass back wall on sage frames, low stone sill
    sill = box(M, (-RW, 0, -9), (RW, 2.0, -8))
    P.fill(sill, ['#D9CFBE', '#CFC4B0'])
    gw = box(M, (-RW, 2.0, -9), (RW, RH, -8))
    P.fill(gw, ['#DDF2F4', '#CDEBF0', '#E6F7F8'])
    fr = gw & ((np.abs(((M.X + RW) % 4.0) - 2.0) > 1.75) | (np.abs(((M.Y - 2) % 4.0) - 2.0) > 1.75))
    P.fill(fr, SAGE)
    # garden visible beyond the glass: soft green hills band
    P.fill(gw & ~fr & (M.Y < 5.0 + 1.2 * np.sin(M.X * 0.4)), ['#BFE0B0', '#B3D8A3'])
    for sx in (-1, 1):
        sw = box(M, (RW - 1 if sx > 0 else -RW, 0, -9), (RW if sx > 0 else -RW + 1, RH, RF))
        P.fill(sw, ['#DDF2F4', '#CDEBF0'])
        P.fill(sw & ((np.abs(((M.Z + 9) % 4.0) - 2.0) > 1.75) | (np.abs(((M.Y - 2) % 4.0) - 2.0) > 1.75)), SAGE)
    # sunbeams: pale stripes across the floor
    beam = floor & (np.abs(((M.X - M.Z * 0.6) % 7.0) - 3.5) < 0.9) & (M.Y >= -0.5)
    P.fill(beam, ['#F2D8BE', '#EDD0B4'])
    # curved bench of seedlings on the right, shelves of pots, hanging baskets
    bench = (np.sqrt((M.X - 10.5) ** 2 + ((M.Z + 2.0) * 1.3) ** 2) < 5.2) & (np.sqrt((M.X - 10.5) ** 2 + ((M.Z + 2.0) * 1.3) ** 2) > 3.2) & \
        (M.Y >= 2.4) & (M.Y < 3.0) & (M.X > 6.0)
    P.fill(bench, WOOD)
    for lx, lz in ((7.2, 0.6), (13.6, 0.4), (8.0, -5.2), (13.0, -5.4)):
        P.fill(box(M, (lx - 0.3, 0, lz - 0.3), (lx + 0.3, 2.4, lz + 0.3)), ['#8D5D3B'])
    for a in np.linspace(-1.2, 1.2, 7):
        sx_, sz_ = 10.5 - 4.2 * math.cos(a), -2.0 + 4.2 * math.sin(a) / 1.3
        sprout = ((M.X - sx_) ** 2 + (M.Z - sz_) ** 2 <= 0.35) & (M.Y >= 3.0) & (M.Y < 4.2)
        P.fill(sprout, ['#86C56A', '#6FB24E'])
    shelf(M, P, -14.5, -7.0, 7.0, -8.0)
    shelf(M, P, -14.5, -7.0, 10.5, -8.0)
    for (x, y) in ((-13.2, 7.0), (-10.8, 7.0), (-8.4, 7.0), (-12.4, 10.5), (-9.2, 10.5)):
        pot_plant(M, P, x, y, -7.3, 0.6, rng, flower='#FFFDF6' if x < -12 else None)
    for (x, z, s) in ((-12.8, 3.0, 1.0), (-14.2, -2.0, 1.2), (13.8, 5.6, 1.0)):
        pot_plant(M, P, x, 0, z, s, rng, flower='#F4C04E')
    for hx in (-3.5, 4.5):
        rope = (np.abs(M.X - hx) < 0.15) & (np.abs(M.Z + 4.0) < 0.15) & (M.Y >= 10.5) & (M.Y < RH)
        P.fill(rope, ['#B98A3E'])
        bowl = ((M.X - hx) ** 2 + ((M.Y - 10.2) * 1.4) ** 2 + (M.Z + 4.0) ** 2 <= 1.3 ** 2) & (M.Y < 10.6)
        P.fill(bowl, ['#C99B5A'])
        leaves = ((M.X - hx) ** 2 + (M.Y - 10.6) ** 2 + (M.Z + 4.0) ** 2 <= 1.4 ** 2) & (M.Y >= 10.6)
        P.fill(leaves, ['#6FB24E', '#86C56A'])
        trail = (np.abs(M.X - hx - 0.9) < 0.3) & (np.abs(M.Z + 3.4) < 0.3) & (M.Y >= 8.4) & (M.Y < 10.2)
        P.fill(trail, ['#5EA046'])
    for vx in (-RW + 2.0, -1.0, RW - 6.0):
        vine = (np.abs(M.X - vx - 0.8 * np.sin(M.Y * 0.9)) < 0.45) & (M.Z >= -8.2) & (M.Z < -7.6) & (M.Y > 2.0) & (M.Y < 14.0)
        P.fill(vine, ['#5EA046', '#6FB24E'])
        for ly in np.arange(3.0, 14.0, 1.8):
            lf = ((M.X - vx - 0.8 * np.sin(ly * 0.9) - 0.7) ** 2 + (M.Y - ly) ** 2 <= 0.5) & (M.Z >= -8.0) & (M.Z < -7.3)
            P.fill(lf, ['#86C56A'])
    for bx0 in (-RW + 1.0, -6.0, 6.0):
        fbox = box(M, (bx0, 2.0, -8.0), (bx0 + 5.0, 3.0, -6.8))
        P.fill(fbox, ['#B76B4D', '#A95F43'])
        for fx_ in np.arange(bx0 + 0.6, bx0 + 5.0, 1.1):
            daisy(M, P, (fx_, 3.6, -7.2), size=0.42, petal=['#FFFDF6', '#F5A3B5', '#F4C04E'][int(fx_ * 7) % 3], stem=False)
    stand = box(M, (-17.0, 0, -3.0), (-14.0, 3.0, 0.0))
    P.fill(stand, WOOD)
    big = ((M.X + 15.5) ** 2 + ((M.Y - 5.6) * 0.8) ** 2 + (M.Z + 1.5) ** 2) <= 3.0 ** 2
    P.fill(big & (M.Y >= 3.0) & (M.m == 0), ['#5EA046', '#6FB24E', '#4F9C3E'])
    for (x, z, s) in ((-19.0, 6.0, 1.3), (17.5, 9.0, 1.2), (-9.5, 12.0, 1.0), (21.0, 2.0, 1.4)):
        pot_plant(M, P, x, 0, z, s, rng, flower=['#FFFDF6', '#F5A3B5', '#F4C04E'][int(abs(x)) % 3])
    # copper watering can and a seed sack near the front
    can = ((M.X - 5.2) ** 2 + (M.Z - 5.2) ** 2 <= 0.9) & (M.Y >= 0) & (M.Y < 1.6)
    P.fill(can, ['#C9874E', '#D9985E'])
    sack = ((M.X - 2.6) ** 2 + ((M.Y - 1.0) * 1.2) ** 2 + (M.Z - 6.4) ** 2 <= 1.3 ** 2) & (M.Y >= 0)
    P.fill(sack, ['#D8C39A', '#CDB689'])
    layers = [Layer('mid', M, inner_alpha=0.28)]
    sc = Scene('glasshouse', cam, w, h, (0.5, 0.55), ('#BFE3EC', '#E9F6F4'), layers, seed=seed, clouds=0)
    sc.pet = (-4.0, 0, 4.0)
    sc.slots = {'npc': (-4.5, 0, 3.0)}
    return sc


def scene_workshop(w=1170, h=900, seed=61):
    rng = np.random.default_rng(seed)
    cam = Camera(yaw=0, pitch=9, target=(0, 5.6, -1.0), persp=33, fov=40)
    M = Model((-RW - 1, -2, -10), (RW + 1, RH + 1, RF + 1), [], res=2)
    P = Painter(M, rng)
    floor = box(M, (-RW, -1, -9), (RW, 0, RF))
    P.fill(floor, ['#9A6B47', '#8D6040', '#A5754F'])
    P.fill(floor & (np.abs((M.X % 2.0) - 1.0) > 0.88), ['#6E4529'])
    wall = box(M, (-RW, 0, -9), (RW, RH, -8))
    P.fill(wall, ['#B07A50', '#A56F47', '#BB855A'])
    P.fill(wall & (np.abs(((M.Y) % 2.0) - 1.0) > 0.85), ['#7E5133'])
    for sx in (-1, 1):
        sw = box(M, (RW - 1 if sx > 0 else -RW, 0, -9), (RW if sx > 0 else -RW + 1, RH, RF))
        P.fill(sw, ['#A56F47', '#B07A50'])
    for bx in (-20.0, -12.0, -4.0, 4.0, 12.0, 20.0):
        P.fill(box(M, (bx - 0.45, 0, -8.6), (bx + 0.45, RH, -7.6)), ['#5E3A24'])
    P.fill(box(M, (-RW, 12.6, -8.6), (RW, 13.4, -7.4)), ['#5E3A24'])
    # glow-cube furnace on the right
    fx = 10.5
    furn = box(M, (fx - 3.2, 0, -7.6), (fx + 3.2, 7.0, -3.6))
    P.fill(furn, STONE)
    mouth = box(M, (fx - 1.8, 1.0, -3.8), (fx + 1.8, 4.2, -3.4))
    P.fill(mouth, ['#FF9A4A', '#FFB65C', '#FF8A3A'], glow=1.0)
    P.fill(box(M, (fx - 1.0, 7.0, -6.6), (fx + 1.0, RH, -4.6)), ['#8E8A86', '#A39D94'])
    coals = box(M, (fx - 1.6, 1.0, -3.6), (fx + 1.6, 1.6, -3.0))
    P.fill(coals, ['#FFD46A'], glow=1.0)
    # shelves of glass lenses and hanging lantern frames
    shelf(M, P, -14.5, -6.0, 6.5, -8.0)
    shelf(M, P, -14.5, -6.0, 10.0, -8.0)
    for (x, y) in ((-13.4, 6.5), (-11.6, 6.5), (-9.8, 6.5), (-8.0, 6.5), (-12.6, 10.0), (-10.4, 10.0), (-8.2, 10.0)):
        lens = ((M.X - x) ** 2 + (M.Y - y - 0.8) ** 2 <= 0.7 ** 2) & (M.Z >= -7.6) & (M.Z < -7.0)
        P.fill(lens, ['#BFE6F5', '#D7F0FA'])
        P.fill(lens & ((M.X - x) ** 2 + (M.Y - y - 0.8) ** 2 > 0.4 ** 2), ['#C69469'])
    for (hx, hy, lit) in ((-2.0, 10.6, True), (2.6, 11.2, False), (6.2, 10.4, True)):
        chain = (np.abs(M.X - hx) < 0.15) & (np.abs(M.Z + 5.0) < 0.15) & (M.Y >= hy + 1.0) & (M.Y < RH)
        P.fill(chain, ['#4A3328'])
        lantern_at(M, P, hx, hy, -5.0, lit, 0.8)
    # parchment repair diagrams pinned to the wall
    for (x, y, ww, hh) in ((-3.0, 6.0, 3.0, 2.2), (1.6, 7.2, 2.4, 3.0)):
        sheet = box(M, (x - ww / 2, y - hh / 2, -8.0), (x + ww / 2, y + hh / 2, -7.7))
        P.fill(sheet, ['#F3E5C9', '#EADAB8'])
        P.fill(sheet & ((np.abs(M.Y - y) < 0.12) | (np.abs(M.X - x) < 0.12) | (np.abs(np.sqrt((M.X - x) ** 2 + (M.Y - y) ** 2) - 0.7) < 0.12)), ['#5A7C9A'])
    # stout oak workbench at the back right with tools
    wb = box(M, (1.0, 2.8, -6.6), (7.4, 3.4, -3.6))
    P.fill(wb, ['#9A6538', '#A8703F'])
    for lx in (1.4, 7.0):
        for lz in (-6.2, -4.0):
            P.fill(box(M, (lx - 0.3, 0, lz - 0.3), (lx + 0.3, 2.8, lz + 0.3)), ['#7A4E2E'])
    P.fill(box(M, (2.0, 3.4, -5.6), (3.4, 4.6, -4.4)), ['#C69469', '#E2B488'])
    P.fill(box(M, (4.6, 3.4, -5.4), (6.6, 3.8, -4.6)), ['#8E8A86'])
    # crates and a copper pipe
    for (cx, cz, s) in ((-13.0, 4.0, 1.6), (-11.0, 5.6, 1.2), (13.2, 5.0, 1.5)):
        crate = box(M, (cx - s, 0, cz - s), (cx + s, 2 * s, cz + s))
        P.fill(crate, ['#B07A48', '#A06C3E'])
        P.fill(crate & ((M.Y >= 2 * s - 0.3) | (np.abs(M.X - cx) < 0.2)), ['#7A4E2E'])
    rack = box(M, (-21.0, 4.0, -8.0), (-15.5, 9.5, -7.4))
    P.fill(rack, ['#7A4E2E'])
    for i, tx in enumerate(np.arange(-20.4, -15.8, 1.1)):
        tool = box(M, (tx - 0.2, 4.6, -7.4), (tx + 0.2, 8.6, -7.0))
        P.fill(tool, ['#8E8A86', '#C69469', '#A39D94'][i % 3])
        P.fill(box(M, (tx - 0.5, 7.8, -7.4), (tx + 0.5, 8.9, -6.9)), ['#5E5A56', '#C69469'][i % 2])
    for (bx_, bz_) in ((18.5, 1.0), (20.5, 4.0), (-19.5, 9.0)):
        barrel = ((M.X - bx_) ** 2 + (M.Z - bz_) ** 2 <= 1.6 ** 2) & (M.Y >= 0) & (M.Y < 3.2)
        P.fill(barrel, ['#9A6538', '#8A5A34'])
        P.fill(barrel & ((np.abs(M.Y - 0.6) < 0.25) | (np.abs(M.Y - 2.6) < 0.25)), ['#5E5A56'])
    for (hx, lit) in ((-13.0, True), (-8.6, False), (14.6, True), (18.8, False)):
        chain = (np.abs(M.X - hx) < 0.15) & (np.abs(M.Z + 4.0) < 0.15) & (M.Y >= 12.4) & (M.Y < RH)
        P.fill(chain, ['#4A3328'])
        lantern_at(M, P, hx, 11.4, -4.0, lit, 0.7)
    pipe = (np.abs(M.Y - 13.8) < 0.35) & (np.abs(M.Z + 7.3) < 0.35) & (M.X > -RW) & (M.X < 8)
    P.fill(pipe, ['#C69469', '#D9A57A'])
    layers = [Layer('mid', M, inner_alpha=0.28)]
    sc = Scene('workshop', cam, w, h, (0.5, 0.55), ('#3B2923', '#5E3A24'), layers, seed=seed, clouds=0)
    sc.slots = {'npc': (-4.5, 0, 3.0)}
    return sc


def scene_lodge(w=1170, h=900, seed=71):
    rng = np.random.default_rng(seed)
    cam = Camera(yaw=0, pitch=9, target=(0, 5.6, -1.0), persp=33, fov=40)
    M = Model((-RW - 1, -2, -10), (RW + 1, RH + 1, RF + 1), [], res=2)
    P = Painter(M, rng)
    floor = box(M, (-RW, -1, -9), (RW, 0, RF))
    P.fill(floor, ['#B98955', '#AD7E4C', '#C4925E'])
    P.fill(floor & (np.abs((M.Z % 2.2) - 1.1) > 0.95), ['#8D5D3B'])
    rug = (np.abs(M.X - 0.5) < 6.5) & (np.abs(M.Z - 2.5) < 3.5) & (M.Y >= -0.5) & (M.Y < 0.1)
    P.fill(rug, ['#203B50', '#284A63'])
    P.fill(rug & ((np.abs(M.X - 0.5) > 5.8) | (np.abs(M.Z - 2.5) > 2.8)), ['#E8B956'])
    wall = box(M, (-RW, 0, -9), (RW, RH, -8))
    P.fill(wall, PLASTER)
    for sx in (-1, 1):
        P.fill(box(M, (RW - 1 if sx > 0 else -RW, 0, -9), (RW if sx > 0 else -RW + 1, RH, RF)), ['#EEDDBD', '#F3E5C9'])
    for bx in (-18.4, -11.0, -3.6, 3.6, 11.0, 18.4):
        P.fill(box(M, (bx - 0.5, 0, -8.6), (bx + 0.5, RH, -7.5)), WALNUT)
    P.fill(box(M, (-RW, 11.8, -8.6), (RW, 12.6, -7.3)), WALNUT)
    P.fill(box(M, (-RW, 0, -8.6), (RW, 1.0, -7.5)), WALNUT)
    # navy heraldic flags with the Guild wing
    for fx in (-7.3, 7.3):
        flag = (np.abs(M.X - fx) <= 1.8) & (M.Y >= 5.0) & (M.Y < 11.2) & (M.Z >= -7.6) & (M.Z < -7.2)
        flag &= ~((M.Y < 6.2) & (np.abs(M.X - fx) < 0.8))
        P.fill(flag, NAVY)
        wing = flag & (np.abs(M.Y - 8.6 - np.abs(M.X - fx) * 0.5) < 0.4) & (np.abs(M.X - fx) < 1.2)
        P.fill(wing, ['#F3E5C9'])
        P.fill(flag & ((np.abs(M.X - fx) > 1.5)), ['#E8B956'])
        P.fill(box(M, (fx - 2.1, 11.2, -7.6), (fx + 2.1, 11.6, -7.0)), ['#5E3A24'])
    # courier pigeonholes on the left with letters, pinned trail sketches in the middle
    ph = box(M, (-14.6, 2.0, -7.8), (-9.0, 9.4, -6.2))
    P.fill(ph, WALNUT)
    holes = ph & (np.abs(((M.X + 14.6) % 1.4) - 0.7) < 0.5) & (np.abs(((M.Y - 2.0) % 1.48) - 0.74) < 0.55) & (M.Z > -7.2)
    M.m[holes] = 0
    for (x, y) in ((-13.9, 3.5), (-11.1, 5.0), (-12.5, 8.0), (-9.7, 3.5)):
        P.fill(box(M, (x - 0.4, y - 0.4, -7.2), (x + 0.4, y + 0.2, -6.6)), ['#F3E5C9'])
    for (x, y, ww, hh) in ((-1.6, 7.0, 2.8, 2.2), (1.8, 6.0, 2.2, 2.6), (0.2, 9.6, 2.4, 1.6)):
        sheet = box(M, (x - ww / 2, y - hh / 2, -7.6), (x + ww / 2, y + hh / 2, -7.3))
        P.fill(sheet, ['#FBF5E8', '#F1E6CF'])
        trail = sheet & (np.abs(M.Y - y - 0.5 * np.sin((M.X - x) * 2.0)) < 0.14)
        P.fill(trail, ['#B76B4D'])
        P.fill(box(M, (x - 0.15, y + hh / 2 - 0.3, -7.3), (x + 0.15, y + hh / 2, -7.0)), ['#D85F51'])
    # copper compass above the door gap, Alder's map desk on the right with scrolls
    comp = (np.sqrt(M.X ** 2 + (M.Y - 13.6) ** 2) <= 1.0) & (M.Z >= -7.6) & (M.Z < -7.0)
    P.fill(comp, ['#C69469'])
    P.fill(comp & (np.abs(M.X) < 0.18), ['#E8B956'])
    desk = box(M, (6.0, 2.8, -6.6), (13.6, 3.4, -2.0))
    P.fill(desk, ['#9A6538', '#A8703F'])
    for lx in (6.4, 13.2):
        for lz in (-6.2, -2.4):
            P.fill(box(M, (lx - 0.3, 0, lz - 0.3), (lx + 0.3, 2.8, lz + 0.3)), ['#7A4E2E'])
    mapm = box(M, (7.0, 3.4, -5.8), (12.4, 3.6, -2.6))
    P.fill(mapm, ['#FBF5E8', '#F1E6CF'])
    P.fill(mapm & (np.abs(M.Z + 4.2 - 0.8 * np.sin(M.X * 1.3)) < 0.18), ['#7F9871'])
    P.fill(mapm & (np.abs(M.X - 9.6) < 0.18), ['#203B50'])
    for (sx_, sz_) in ((12.8, -1.4), (13.6, -0.6)):
        sc_ = ((M.Y - 0.6) ** 2 + (M.Z - sz_) ** 2 <= 0.5 ** 2) & (np.abs(M.X - sx_) < 1.6)
        P.fill(sc_, ['#FBF5E8'])
    globe = ((M.X - 8.0) ** 2 + (M.Y - 4.6) ** 2 + (M.Z + 5.6) ** 2) <= 1.0
    P.fill(globe, ['#5FA0C8', '#82B75E'])
    bs = box(M, (16.0, 0, -8.0), (22.0, 10.0, -6.4))
    P.fill(bs, WALNUT)
    for sy in (2.6, 5.2, 7.8):
        books = box(M, (16.5, sy - 2.2, -7.2), (21.5, sy - 0.2, -6.5))
        P.fill(books, ['#B76B4D', '#203B50', '#7F9871', '#E8B956', '#8D5D3B'])
        P.fill(box(M, (16.0, sy - 0.2, -8.0), (22.0, sy, -6.4)), ['#5E3A24'])
    for (x, y, ww, hh) in ((-19.0, 7.0, 2.4, 3.0), (-21.4, 10.2, 2.0, 1.6)):
        sheet = box(M, (x - ww / 2, y - hh / 2, -7.6), (x + ww / 2, y + hh / 2, -7.3))
        P.fill(sheet, ['#FBF5E8', '#F1E6CF'])
        P.fill(sheet & (np.abs(M.X - x - 0.4 * np.sin((M.Y - y) * 2.5)) < 0.14), ['#7F9871'])
    bench = box(M, (-21.0, 1.6, 4.0), (-15.0, 2.2, 6.0))
    P.fill(bench, WOOD)
    for lx in (-20.4, -15.6):
        P.fill(box(M, (lx - 0.3, 0, 4.4), (lx + 0.3, 1.6, 5.6)), ['#8D5D3B'])
    for (hx, hy) in ((-10.0, 15.0), (10.0, 15.0)):
        chain = (np.abs(M.X - hx) < 0.15) & (np.abs(M.Z + 3.0) < 0.15) & (M.Y >= hy + 1.0) & (M.Y < RH)
        P.fill(chain, ['#4A3328'])
        lantern_at(M, P, hx, hy, -3.0, True, 0.8)
    # Pip's counter on the left front
    counter = box(M, (-14.0, 0, -4.4), (-8.4, 3.4, -2.6))
    P.fill(counter, ['#A8703F', '#9A6538'])
    P.fill(counter & (M.Y >= 3.0), ['#C98C57'])
    bell = ((M.X + 9.6) ** 2 + (M.Z + 3.4) ** 2 <= 0.36) & (M.Y >= 3.4) & (M.Y < 4.0)
    P.fill(bell, ['#E8B956'])
    layers = [Layer('mid', M, inner_alpha=0.28)]
    sc = Scene('lodge', cam, w, h, (0.5, 0.55), ('#3B2923', '#5E3A24'), layers, seed=seed, clouds=0)
    sc.slots = {'npc': (-4.5, 0, 3.0)}
    return sc


def scene_waystone(w=1000, h=1000, seed=81, restored=False):
    rng = np.random.default_rng(seed)
    cam = Camera(yaw=0, pitch=12, target=(0, 4.0, 0), persp=30, fov=40)
    M = Model((-16, -2, -20), (16, 14, 8), [], res=3)
    P = Painter(M, rng)
    xs, zs = M.X[:, 0, 0], M.Z[0, 0, :]
    H = np.zeros((len(xs), len(zs)))
    heightmap_fill(M, H, COBBLE, ['#A89F8C'], P, top_th=0.34, base=-2)
    X2, Z2 = np.meshgrid(xs, zs, indexing='ij')
    joints = ((np.floor(X2 / 1.5) + np.floor(Z2 / 1.0)) % 5 == 0)
    P.fill((M.Y >= -0.34) & (M.Y < 0) & joints[:, None, :], ['#B1A893'])
    plinth = (np.maximum(np.abs(M.X), np.abs(M.Z)) <= 3.2) & (M.Y >= 0) & (M.Y < 1.0)
    P.fill(plinth, ['#C9C2AE', '#BDB5A0'])
    stone = (np.abs(M.X) <= 2.2 - np.clip(M.Y - 7.0, 0, None) * 0.55) & (np.abs(M.Z) <= 1.2) & (M.Y >= 1.0) & (M.Y < 9.2)
    P.fill(stone, ['#E0D6A6', '#D5CA96', '#E8DFB4', '#DCD09C'])
    P.fill(stone & (M.Y < 3.2) & (M.X < -1.0) & (rng.random(M.m.shape) > 0.3), SAGE)
    P.fill(stone & (M.Y > 8.0) & (M.X > 0.6) & (rng.random(M.m.shape) > 0.5), SAGE)
    grooves = stone & (M.Z > 0.85) & ((np.abs(M.X + 1.0) < 0.22) | (np.abs(M.X) < 0.22) | (np.abs(M.X - 1.0) < 0.22)) & (M.Y > 2.6) & (M.Y < 7.6)
    if restored:
        P.fill(grooves, MINT_GLOW, glow=1.0)
    else:
        P.fill(grooves, ['#6C6A55', '#5F5D4B'])
        P.fill(grooves & (np.abs(M.X - 1.0) < 0.22) & (M.Y > 6.4), ['#E8D99A'], glow=0.6)   # the one groove that glimmers
    for nx in (-1.0, 0.0, 1.0):
        P.fill((np.abs(M.X - nx) < 0.36) & (np.abs(M.Y - 8.1) < 0.36) & (M.Z > 0.8) & (M.Z < 1.6), ['#C69469', '#E2B488'])
    if restored:
        halo = (np.abs(np.sqrt(M.X ** 2 + M.Z ** 2) - 4.0) < 0.35) & (M.Y >= 0) & (M.Y < 0.4)
        P.fill(halo, MINT_GLOW, glow=0.9)
        fireflies(M, P, rng, 30, (-12, 12), (2, 13), (-14, 6))
    # the old lantern Mira meets you under, and flower tubs
    lp = (np.abs(M.X - 6.5) <= 0.3) & (np.abs(M.Z + 3.0) <= 0.3) & (M.Y >= 0) & (M.Y < 9.0)
    P.fill(lp, ['#4A3328'])
    lantern_at(M, P, 6.5, 9.6, -3.0, True, 0.9)
    for (tx, tz) in ((-6.0, -2.0), (-9.0, 2.0)):
        tub = box(M, (tx - 1.2, 0, tz - 1.2), (tx + 1.2, 1.4, tz + 1.2))
        P.fill(tub, WOOD)
        bush = ((M.X - tx) ** 2 + ((M.Y - 2.2) * 1.2) ** 2 + (M.Z - tz) ** 2) <= 1.4 ** 2
        P.fill(bush & (M.m == 0), LEAVES)
        daisy(M, P, (tx + 0.3, 3.2, tz + 0.8), size=0.5, stem=False)
    layers = [Layer('mid', M, inner_alpha=0.25)]
    # blurred village backdrop
    B = Model((-60, -2, -70), (60, 30, -22), [], res=1)
    PB = Painter(B, rng)
    PB.fill((B.Y < 0) & (B.Y >= -1), V_GRASS)
    for (x0, x1, col, roof) in ((-34, -18, GLASS, SAGE), (-8, 8, PLASTER, ROOF), (18, 34, WALNUT, ROOF)):
        gable_house(B, PB, x0, x1, -50, -38, 8, 6, col, roof, ridge='x')
    for tx in (-44, -26, 0, 26, 46):
        tree(B, PB, (tx, 0, -58), trunk_h=8, r=6, rng=rng, leaves=['#6FA552', '#7FB35F'])
    layers.insert(0, Layer('far', B, blur=9.0, haze=0.2, haze_col='#E2F1EE', inner_alpha=0.1))
    sky = ('#7FA3C9', '#F2C9A0') if restored else ('#9CCBD6', '#E2F1EE')
    sc = Scene('waystone', cam, w, h, (0.5, 0.6), sky, layers, seed=seed, clouds=3)
    return sc


# ----------------------------------------------------------------------------
def render_scene(sc, out, name):
    t = time.time()
    fit = make_fit(sc)
    imgs = [sky_image(sc)]
    for L in sc.layers:
        img, _ = render_layer(sc, L, fit)
        imgs.append(img)
    comp = composite(imgs)
    Image.fromarray(comp[..., :3]).save(os.path.join(out, f'{name}.png'))
    meta = {'w': sc.w, 'h': sc.h,
            'anchors': {k: project_px(sc.cam, fit, [v])[0].round(1).tolist() for k, v in sc.slots.items()}}
    print(name, 'done in %.1fs' % (time.time() - t), flush=True)
    return meta


def build_all(out, scale=1.0):
    os.makedirs(out, exist_ok=True)
    meta = {}
    W = lambda v: int(v * scale)
    for st in ('day_dim', 'lamp_lit', 'waystone_restored'):
        meta[f'square_{st}'] = render_scene(scene_square(W(1170), W(1300), state=st), out, f'square_{st}')
    meta['glasshouse'] = render_scene(scene_glasshouse(W(1170), W(900)), out, 'glasshouse')
    meta['workshop'] = render_scene(scene_workshop(W(1170), W(900)), out, 'workshop')
    meta['lodge'] = render_scene(scene_lodge(W(1170), W(900)), out, 'lodge')
    meta['waystone_dormant'] = render_scene(scene_waystone(W(1000), W(1000), restored=False), out, 'waystone_dormant')
    meta['waystone_restored'] = render_scene(scene_waystone(W(1000), W(1000), restored=True), out, 'waystone_restored')
    json.dump(meta, open(os.path.join(out, 'scenes.json'), 'w'), indent=1)


if __name__ == '__main__':
    import sys
    out = sys.argv[1]
    which = sys.argv[2:]
    scale = 0.5
    if not which:
        build_all(out, 1.0)
    else:
        fns = {'square': lambda: scene_square(int(1170 * scale), int(1300 * scale), state='lamp_lit'),
               'restored': lambda: scene_square(int(1170 * scale), int(1300 * scale), state='waystone_restored'),
               'glasshouse': lambda: scene_glasshouse(int(1170 * scale), int(900 * scale)),
               'workshop': lambda: scene_workshop(int(1170 * scale), int(900 * scale)),
               'lodge': lambda: scene_lodge(int(1170 * scale), int(900 * scale)),
               'waystone': lambda: scene_waystone(int(1000 * scale), int(1000 * scale)),
               'waystone_r': lambda: scene_waystone(int(1000 * scale), int(1000 * scale), restored=True)}
        os.makedirs(out, exist_ok=True)
        for n in which:
            render_scene(fns[n](), out, 'preview_' + n)

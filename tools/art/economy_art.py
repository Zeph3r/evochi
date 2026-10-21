"""Economy art drawn with the flat item renderer: the rare items, Glimmer, the Season 1 cosmetics,
the Starlight Caravan / Plus / Season UI icons and the four daily-chest tiers (closed and open, for
the opening animation).

  python3 economy_art.py FLUTTER_ASSETS_ART_DIR [items|icons|chests ...]
    items/<id>.webp                     168px item icons            manifest['items'][id]
    icons/<k>.webp                      112px UI icons              manifest['icons'][k]
    economy/chest_<tier>_<state>.webp   384px chest sprites (closed/open share one camera and fit)

Writes the web-ready WebP files straight into the Flutter asset folder and adds their keys to
manifest.json (existing keys are kept).
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image

from voxel import Camera, render, fit_camera, model_extent_points
from items import M_, ell, cyl, flower, GOLD, GOLD_HI, GOLD_LO, WOOD, WOOD_HI, WOOD_LO, LEAF, LEAF_HI, LEAF_LO, WHITE
from characters import spike
from build_items import LIGHT, render_model
from home_items import put, box, ycyl, bottle

# ------------------------------------------------------------------ palette
SUN, SUN_HI, SUN_LO, SUN_CORE = '#FFB637', '#FFDB6E', '#E8892A', '#FFF4C2'
DEW, DEW_HI = '#4FB3EA', '#A8DCFA'
MOON = '#F6E9AE'
ROSE, ROSE_HI, ROSE_LO, ROSE_DK = '#F27AA0', '#FFB3CB', '#D9577F', '#C23D66'
BRASS, BRASS_HI, BRASS_LO = '#D9A441', '#F4CF7A', '#A8772A'
FACE = '#FFF3E2'
MINT_GLOW, MINT_GLOW_HI = '#6FE3C0', '#C9F8E8'
NEEDLE_RED = '#D8434A'
ACORN, ACORN_HI, ACORN_LO = '#FFC83E', '#FFF0B0', '#E5A22E'
CAP, CAP_HI = '#B07A2E', '#C99448'
VIOLET, VIOLET_HI, VIOLET_LO = '#7A58B8', '#A88BE0', '#5A3F8E'
RUNE = '#E2D2FF'
SEED, SEED_HI, SEED_LO = '#C98C57', '#E2B488', '#8D5D3B'
STAR, STAR_HI = '#FFE27A', '#FFF8D2'
PRISM = ['#F7A6B9', '#FFC98A', '#FFE98C', '#A9E6A2', '#8FD6F2', '#A9A0F2', '#D6A2EE']
CY, CY_HI, CY_LO = '#4FD8EE', '#BFF6FF', '#2BA9CC'
VI, VI_HI, VI_LO = '#A487F2', '#D9CCFF', '#7559CF'
CLOTH, CLOTH_HI, CLOTH_LO = '#E8CFA0', '#F6E3BE', '#C9AC78'
TWINE = '#8A5634'
NAVY, NAVY_HI, NAVY_LO = '#2E3D6B', '#41548C', '#1F2A4D'
FIREFLY = '#FFE680'
PEACH, PEACH_HI, PEACH_LO = '#F6A77C', '#FFC7A3', '#DA8458'
AMBERW, AMBERW_HI = '#FFCF6A', '#FFF0B8'
RIBBON, RIBBON_HI, RIBBON_LO = '#F3B1C8', '#FFD6E4', '#D98AA8'


def plane_dist(M, c):
    return np.sqrt((M.X - c[0]) ** 2 + (M.Y - c[1]) ** 2)


def star4(M, c, size, depth=0.8, col=STAR_HI, glow=1.0):
    """A flat four-point sparkle facing the camera (+Z)."""
    dx, dy = np.abs(M.X - c[0]), np.abs(M.Y - c[1])
    s = (np.sqrt(dx) + np.sqrt(dy) <= math.sqrt(size)) & (np.abs(M.Z - c[2]) <= depth)
    return put(M, s, col, glow=glow)


def star5(M, c, R, r, depth, col, hi=None, glow=None):
    a = np.arctan2(M.X - c[0], M.Y - c[1])
    rr = plane_dist(M, c)
    k = np.cos(5 * a)
    rad = r + (R - r) * np.clip(k, 0, 1) ** 1.5
    s = (rr <= rad) & (np.abs(M.Z - c[2]) <= depth)
    put(M, s, col, glow=glow)
    if hi:
        put(M, s & (M.X < c[0]) & (M.Y > c[1]) & (M.Z > c[2]), hi, glow=glow)
    return s


# ================================================================== rare items
def sunstone():
    M = M_((-9, -1, -9), (9, 18, 9), res=2)
    cy = 8.0
    # sun rays: a halo of short spikes in the plane facing the camera, behind the gem
    for k in range(10):
        a = k / 10 * 2 * math.pi
        d = (math.sin(a), math.cos(a), 0.0)
        base = (d[0] * 5.0, cy + d[1] * 5.0, -1.6)
        sp = spike(M, base, d, 3.0 if k % 2 == 0 else 2.0, 0.9, 0.2)
        put(M, sp, SUN_HI if k % 2 == 0 else SUN, glow=0.75)
    # the faceted gem: an octahedron, stretched tall
    q = np.abs(M.X) * 0.9 + np.abs(M.Z) * 0.9 + np.abs(M.Y - cy) * 0.78
    gem = q <= 5.6
    put(M, gem, SUN, glow=0.55)
    put(M, gem & (M.Y < cy), SUN_LO, glow=0.45)
    put(M, gem & (M.Y >= cy) & (M.X < 0), SUN_HI, glow=0.65)
    put(M, gem & (M.Y >= cy + 1.5) & (M.X < -0.5) & (M.Z > 0.5), SUN_CORE, glow=0.9)
    # facet lines
    put(M, gem & (np.abs(M.Y - cy) < 0.45), SUN_LO, glow=0.4)
    star4(M, (5.6, cy + 6.2, 2.0), 1.8)
    return M, Camera(yaw=-20, pitch=12)


def moonwell_dew():
    M = M_((-8, -1, -8), (8, 18, 8), res=2)
    cy = bottle(M, 'round', DEW, DEW_HI, glow=0.4)
    # a crescent-moon stopper on the cork
    c = (0.0, cy[1] + 2.2, 0.0)
    disc = (plane_dist(M, c) <= 2.3) & (np.abs(M.Z) <= 0.8)
    bite = plane_dist(M, (c[0] + 1.2, c[1] + 0.6, 0)) <= 1.9
    put(M, disc & ~bite, MOON, glow=0.6)
    for (x, y, z) in ((1.6, 3.0, 3.0), (-0.8, 2.0, 3.3), (0.6, 4.9, 3.2), (-1.8, 4.0, 2.4)):
        put(M, ell(M, (x, y, z), (0.45, 0.45, 0.45)), '#FFFFFF', glow=1.0)
    star4(M, (3.8, 10.5, 1.0), 1.6)
    return M, Camera(yaw=-20, pitch=16)


def _heart_mask(M, c, s, depth):
    x, y = (M.X - c[0]) / s, (M.Y - c[1]) / s + 0.1
    h = (x ** 2 + y ** 2 - 1) ** 3 - x ** 2 * y ** 3 <= 0
    return h & (np.abs(M.Z - c[2]) <= depth)


def heartbloom():
    M = M_((-9, -1, -9), (9, 19, 9), res=2)
    # stem and two leaves
    put(M, ycyl(M, (0, 0), 0.7, 0.0, 9.0), '#4E9A3A')
    for d, col in (((0.9, 0.5, 0.2), LEAF), ((-0.9, 0.6, 0.15), LEAF_HI)):
        lf = spike(M, (0, 3.0 if d[0] > 0 else 4.6, 0), d, 4.2, 1.5, 0.3)
        put(M, lf & (M.m == 0), col)
    # five heart-shaped petals (point to the centre), facing the camera, with gaps between them
    cy = 11.6
    for k in range(5):
        a = k / 5 * 2 * math.pi + math.pi / 2
        px, py = math.cos(a) * 3.6, cy + math.sin(a) * 3.6
        x, y = (M.X - px) / 2.15, (M.Y - py) / 2.15
        ang = -(a - math.pi / 2)  # turn each heart so its point aims at the centre
        xr = x * math.cos(ang) - y * math.sin(ang)
        yr = x * math.sin(ang) + y * math.cos(ang) + 0.15
        h = (xr ** 2 + yr ** 2 - 1) ** 3 - xr ** 2 * yr ** 3 <= 0
        h &= (np.abs(M.Z - 0.2) <= 1.0)
        put(M, h, ROSE if k % 2 else ROSE_LO, glow=0.35)
        put(M, h & (yr > 0.35) & (M.Z > 0.4), ROSE_HI, glow=0.5)
    # a glowing centre
    c = ell(M, (0, cy, 1.0), (1.7, 1.7, 1.2))
    put(M, c, '#FFE07A', glow=0.9)
    put(M, c & (M.X < -0.3) & (M.Y > cy + 0.3), '#FFF6CC', glow=1.0)
    for (x, y, z) in ((-5.6, 14.6, 1.0), (5.2, 15.4, 0.6), (4.6, 7.0, 1.4)):
        put(M, ell(M, (x, y, z), (0.45, 0.45, 0.45)), '#FFE0EA', glow=1.0)
    return M, Camera(yaw=-14, pitch=10)


def wayfinder_compass():
    M = M_((-9, -1, -4), (9, 19, 4), res=2)
    c = (0.0, 8.0, 0.0)
    r = plane_dist(M, c)
    body = (r <= 7.2) & (np.abs(M.Z) <= 1.8)
    put(M, body, BRASS)
    put(M, body & (M.Z < -0.6), BRASS_LO)
    put(M, body & (r >= 6.0) & (M.Z > 0.6) & (M.X < 0) & (M.Y > c[1]), BRASS_HI)
    face = (r <= 5.6) & (M.Z > 1.0) & (M.Z <= 2.2)
    put(M, face, FACE)
    # tick marks at N/E/S/W
    for (dx, dy) in ((0, 1), (1, 0), (0, -1), (-1, 0)):
        t = (np.abs(M.X - dx * 4.6) <= 0.5 + 0.35 * abs(dy)) & (np.abs(M.Y - c[1] - dy * 4.6) <= 0.5 + 0.35 * abs(dx)) & face
        put(M, t, '#7A5A44')
    # the needle: mint (glowing) half towards the upper right, red half the other way
    d = np.array([0.55, 0.83])
    d /= np.linalg.norm(d)
    u = (M.X - c[0]) * d[0] + (M.Y - c[1]) * d[1]
    v = -(M.X - c[0]) * d[1] + (M.Y - c[1]) * d[0]
    needle = (np.abs(v) <= 1.1 * (1 - np.abs(u) / 4.8)) & (np.abs(u) <= 4.8) & (M.Z > 1.8) & (M.Z <= 3.0)
    put(M, needle & (u >= 0), MINT_GLOW, glow=0.9)
    put(M, needle & (u >= 0) & (v < 0), MINT_GLOW_HI, glow=1.0)
    put(M, needle & (u < 0), NEEDLE_RED)
    put(M, (r <= 0.8) & (M.Z > 2.0) & (M.Z <= 3.2), BRASS_HI)
    # the loop on top
    rr = np.sqrt(M.X ** 2 + (M.Y - (c[1] + 8.4)) ** 2)
    put(M, (rr <= 1.8) & (rr >= 0.9) & (np.abs(M.Z) <= 0.6), BRASS_LO)
    return M, Camera(yaw=-16, pitch=8)


def golden_acorn():
    M = M_((-9, -1, -9), (9, 18, 9), res=2)
    nut = ell(M, (0, 5.6, 0), (4.6, 5.8, 4.6), p=2.1) & (M.Y < 8.5)
    nut |= ell(M, (0, 1.0, 0), (1.0, 1.3, 1.0))  # the little point
    put(M, nut, ACORN, glow=0.3)
    put(M, nut & (M.X < -1.2) & (M.Y > 3.2) & (M.Z > 0), ACORN_HI, glow=0.5)
    put(M, nut & (M.Y < 3.0) & (M.X > 0.5), ACORN_LO, glow=0.15)
    cap = ell(M, (0, 8.6, 0), (5.6, 3.2, 5.6), p=2.2) & (M.Y >= 7.6)
    put(M, cap, CAP)
    ch = (np.floor(M.X * 1.2).astype(int) + np.floor(M.Y * 1.2).astype(int) + np.floor(M.Z * 1.2).astype(int)) % 2 == 0
    put(M, cap & ch, CAP_HI)
    put(M, ycyl(M, (0, 0), 0.8, 11.0, 13.4), '#7A5A2C')
    lf = spike(M, (0.4, 12.4, 0), (0.85, 0.35, 0.35), 5.2, 1.7, 0.3)
    put(M, lf & (M.m == 0), LEAF)
    put(M, lf & (M.Y > 13.6), LEAF_HI)
    star4(M, (-4.6, 11.6, 2.6), 2.0)
    return M, Camera(yaw=-20, pitch=14)


def hollow_ward():
    M = M_((-9, -1, -4), (9, 20, 4), res=2)
    c = (0.0, 8.0, 0.0)
    r = plane_dist(M, c)
    disc = (r <= 7.2) & (np.abs(M.Z) <= 1.6)
    put(M, disc, WOOD)
    put(M, disc & (r >= 6.0), WOOD_LO)
    put(M, disc & (r >= 6.0) & (M.X < 0) & (M.Y > c[1]) & (M.Z > 0), WOOD_HI)
    inner = (r <= 5.4) & (M.Z > 0.8) & (M.Z <= 2.2)
    put(M, inner, VIOLET)
    put(M, inner & (M.X < -1.0) & (M.Y > c[1] + 1.0), VIOLET_HI)
    # a glowing rune: a ring and an eye-like diamond
    ring = (r <= 4.0) & (r >= 3.1) & (M.Z > 1.8) & (M.Z <= 2.6)
    put(M, ring, RUNE, glow=0.95)
    dia = (np.abs(M.X) * 1.6 + np.abs(M.Y - c[1]) <= 2.2) & (M.Z > 1.8) & (M.Z <= 2.6)
    put(M, dia, RUNE, glow=1.0)
    for k in range(4):
        a = k / 4 * 2 * math.pi + math.pi / 4
        put(M, ell(M, (math.cos(a) * 4.6, c[1] + math.sin(a) * 4.6, 2.2), (0.6, 0.6, 0.5)), RUNE, glow=0.9)
    # a cord loop on top
    rr = np.sqrt(M.X ** 2 + (M.Y - (c[1] + 8.6)) ** 2)
    put(M, (rr <= 2.0) & (rr >= 1.1) & (np.abs(M.Z) <= 0.6), '#8A5634')
    return M, Camera(yaw=-16, pitch=8)


def starseed():
    M = M_((-9, -1, -9), (9, 18, 9), res=2)
    # a teardrop seed, point up
    t = np.clip((M.Y - 0.6) / 10.5, 0, 1)
    rad = 4.8 * np.sqrt(np.clip(np.sin(np.pi * np.minimum(t * 1.35, 1.0)), 0, 1)) * (1 - 0.65 * t)
    rr = np.sqrt((M.X) ** 2 + (M.Z) ** 2)
    seed = (rr <= rad + 0.3) & (M.Y >= 0.6) & (M.Y < 11.1)
    put(M, seed, SEED)
    put(M, seed & (M.X < -0.8) & (M.Z > 0), SEED_HI)
    put(M, seed & (M.Y < 2.4), SEED_LO)
    # a stripe of golden speckles
    sp = seed & (((np.floor(M.Y * 2).astype(int) + np.floor(M.X * 2).astype(int)) % 5) == 0) & (M.Y > 3)
    put(M, sp, '#F2CF6A', glow=0.5)
    # the star it carries
    star5(M, (3.4, 14.2, 1.0), 3.2, 1.3, 0.9, STAR, STAR_HI, glow=1.0)
    star4(M, (-4.6, 12.6, 1.6), 1.4)
    return M, Camera(yaw=-16, pitch=12)


def prism_scale():
    M = M_((-9, -2, -4), (9, 18, 4), res=2)
    # a rounded scale: a circle-topped shield tapering to a point, slightly curved
    c = (0.0, 9.0)
    x, y = M.X, M.Y
    top = ((x / 6.2) ** 2 + ((y - c[1]) / 6.6) ** 2 <= 1) & (y >= c[1] - 1)
    bot = (np.abs(x) <= 6.2 * np.clip((y - 0.4) / (c[1] - 1 - 0.4), 0, 1) ** 0.7) & (y >= 0.4) & (y < c[1] - 1)
    curve = 0.06 * x ** 2
    shape = (top | bot) & (M.Z - curve <= 1.2) & (M.Z - curve >= -0.8)
    hue = ((y + x * 0.55) / 2.4).astype(int) % len(PRISM)
    for i, col in enumerate(PRISM):
        put(M, shape & (hue == i), col, glow=0.3)
    # a pearly rim and a shine stripe
    edge = shape & ~(((x / 5.2) ** 2 + ((y - c[1]) / 5.6) ** 2 <= 1) & (y >= c[1] - 1) |
                     ((np.abs(x) <= 5.2 * np.clip((y - 1.6) / (c[1] - 1 - 1.6), 0, 1) ** 0.7) & (y >= 1.6) & (y < c[1] - 1)))
    put(M, edge, '#FFFFFF', glow=0.35)
    put(M, shape & (np.abs(x + y * 0.35 - 0.6) < 0.7) & (y > c[1]) & (M.Z - curve > 0.4), '#FFFFFF', glow=0.7)
    star4(M, (4.4, 14.0, 1.6), 1.6)
    return M, Camera(yaw=-14, pitch=6)


def glimmer():
    M = M_((-9, -1, -8), (9, 18, 8), res=2)
    # three star crystals: a tall violet-to-cyan centre and two smaller ones
    for (cx, cz, h, r0, lean, cols) in (
            (0.0, 0.0, 12.5, 3.5, (0.0, 0.0), (VI_LO, VI, CY, CY_HI)),
            (4.0, 1.2, 8.0, 2.6, (0.35, 0.1), (CY_LO, CY, CY_HI, CY_HI)),
            (-3.8, 1.0, 7.0, 2.4, (-0.35, 0.1), (VI_LO, VI, VI_HI, VI_HI))):
        d = np.array([lean[0], 1.0, lean[1]])
        d /= np.linalg.norm(d)
        sp = spike(M, (cx, 0.4, cz), d, h, r0, 0.25)
        t = np.clip((M.Y - 0.4) / h, 0, 1)
        for i, col in enumerate(cols):
            put(M, sp & (t >= i / 4) & (t < (i + 1) / 4 + (1 if i == 3 else 0)), col, glow=0.45 + 0.15 * i)
        put(M, sp & (M.X < cx - 0.3) & (M.Z > cz), cols[3], glow=0.8)
    # a sparkle star above, the thing that makes it Glimmer and not a Lumen Shard
    star5(M, (0.0, 15.6, 1.2), 2.4, 1.0, 0.8, '#FFFFFF', None, glow=1.0)
    star4(M, (4.8, 11.8, 1.6), 1.5)
    star4(M, (-4.8, 9.6, 1.6), 1.1)
    return M, Camera(yaw=-18, pitch=12)


def starter_pack():
    M = M_((-9, -1, -9), (9, 18, 9), res=2)
    sack = ell(M, (0, 5.4, 0), (6.6, 5.6, 6.0), p=2.2) & (M.Y >= 0.2)
    put(M, sack, CLOTH)
    put(M, sack & (M.X < -2) & (M.Y > 5) & (M.Z > 0), CLOTH_HI)
    put(M, sack & (M.Y < 2.0), CLOTH_LO)
    # a stitched patch
    put(M, sack & (np.abs(M.X - 2.4) <= 1.8) & (np.abs(M.Y - 4.4) <= 1.6) & (M.Z > 3.0), '#C9874E')
    neck = ycyl(M, (0, 0), 2.2, 10.0, 11.8)
    put(M, neck, CLOTH)
    ruff = ell(M, (0, 12.6, 0), (3.6, 1.6, 3.4)) & ~ycyl(M, (0, 0), 1.0, 12.8, 20)
    put(M, ruff, CLOTH_HI)
    put(M, ycyl(M, (0, 0), 2.5, 10.6, 11.4), TWINE)
    # a string down to a gold star tag
    put(M, (np.abs(M.X - 2.6) <= 0.35) & (M.Y >= 7.6) & (M.Y < 11.0) & (np.abs(M.Z - 5.0) <= 0.35), TWINE)
    star5(M, (3.0, 6.0, 5.8), 2.6, 1.1, 0.6, GOLD, GOLD_HI)
    return M, Camera(yaw=-20, pitch=16)


# ================================================================== season 1 cosmetics
def season_dawn_circlet():
    M = M_((-9, -2, -9), (9, 12, 9), res=2)
    r = np.sqrt(M.X ** 2 + M.Z ** 2)
    R = 7.0
    ring = (r <= R) & (r >= R - 1.2) & (M.Y >= 0) & (M.Y < 1.8)
    put(M, ring, GOLD)
    put(M, ring & (M.Y >= 1.2), GOLD_HI)
    # a sunrise ornament at the front: a half sun with rays
    c = (0.0, 1.6, R - 0.4)
    pr = np.sqrt(M.X ** 2 + (M.Y - c[1]) ** 2)
    zf = np.abs(M.Z - c[2]) <= 0.9
    half = (pr <= 2.8) & (M.Y >= c[1]) & zf
    put(M, half, SUN, glow=0.6)
    put(M, half & (pr <= 1.6), SUN_CORE, glow=0.9)
    a = np.arctan2(M.X, M.Y - c[1])
    rays = (pr > 3.0) & (pr <= 5.4) & (M.Y >= c[1] + 0.3) & (np.cos(7 * a) > 0.55) & zf
    put(M, rays, GOLD_HI, glow=0.5)
    # small pink gems around the band
    for a in (math.pi / 2.6, -math.pi / 2.6):
        g = (math.sin(a) * R, 0.9, math.cos(a) * R)
        put(M, ell(M, g, (0.9, 0.9, 0.9)) & (r >= R - 0.6), ROSE_HI, glow=0.4)
    return M, Camera(yaw=-18, pitch=22)


def season_firefly_scarf():
    M = M_((-12, -10, -12), (12, 8, 12), res=2)
    r = np.sqrt(M.X ** 2 + M.Z ** 2)
    band = (r >= 6.0) & (r <= 8.8) & (M.Y >= -1.0) & (M.Y < 3.0)
    put(M, band, NAVY)
    put(M, band & (M.Y >= 2.2), NAVY_HI)
    tail = (M.X >= 1.5) & (M.X <= 5.0) & (M.Z >= 6.0) & (M.Z <= 8.5) & (M.Y < 1.0) & (M.Y > -8.0)
    put(M, tail, NAVY)
    put(M, tail & (M.Y <= -6.6), NAVY_LO)
    knot = ell(M, (3.0, 1.0, 8.2), (2.0, 1.8, 1.5))
    put(M, knot, NAVY_LO)
    # fireflies: glowing dots on the outside of the cloth
    rng = np.random.default_rng(3)
    surf = M.surface() & (M.m > 0)
    for _ in range(16):
        th = rng.uniform(-math.pi * 0.2, math.pi * 1.1)
        y = rng.uniform(-0.4, 2.4)
        p = (math.sin(th) * 8.6, y, math.cos(th) * 8.6)
        put(M, ell(M, p, (0.75, 0.75, 0.75)) & surf, FIREFLY, glow=1.0)
    for (x, y) in ((3.2, -2.5), (3.6, -5.0), (2.4, -4.0)):
        put(M, ell(M, (x, y, 8.6), (0.75, 0.75, 0.75)) & surf, FIREFLY, glow=1.0)
    return M, Camera(yaw=-15, pitch=26)


def season_lantern_wings():
    M = M_((-12, -2, -6), (12, 16, 6), res=2)
    # a small harness piece in the middle
    put(M, ell(M, (0, 7.0, 0), (1.8, 2.4, 1.6)), '#8A5634')
    put(M, ell(M, (0, 7.6, 1.2), (1.0, 1.0, 0.6)), AMBERW, glow=0.9)
    # two pairs of leaf-shaped wings, glowing amber
    for s in (-1, 1):
        for (ang, ln, w, y0) in ((0.55, 9.5, 3.6, 8.0), (-0.25, 7.0, 2.6, 6.2)):
            d = np.array([s * math.cos(ang), math.sin(ang), -0.15])
            d /= np.linalg.norm(d)
            P = np.stack([M.X - s * 1.4, M.Y - y0, M.Z], -1)
            t = P @ d
            perp = P - t[..., None] * d
            pn = np.linalg.norm(perp, axis=-1)
            prof = w * np.sin(np.pi * np.clip(t / ln, 0, 1)) ** 0.8
            wing = (t >= 0) & (t <= ln) & (pn <= prof) & (np.abs(M.Z + 0.15 * t) <= 0.6)
            put(M, wing, AMBERW, glow=0.7)
            put(M, wing & (pn <= prof * 0.45), AMBERW_HI, glow=0.9)
            vein = wing & (np.abs((perp[..., 1] * d[0] - perp[..., 0] * d[1])) <= 0.35)
            put(M, vein, '#E8A040', glow=0.5)
    return M, Camera(yaw=-12, pitch=14)


def season_glow_ribbon():
    M = M_((-10, -9, -4), (10, 8, 4), res=2)
    # a bow: two loops, a knot and two tails
    for s in (-1, 1):
        c = (s * 3.8, 2.4)
        lp = (((M.X - c[0]) / 4.0) ** 2 + ((M.Y - c[1]) / 2.8) ** 2 <= 1) & \
             ~(((M.X - c[0]) / 2.4) ** 2 + ((M.Y - c[1]) / 1.3) ** 2 <= 1) & (np.abs(M.Z) <= 1.0)
        put(M, lp, RIBBON, glow=0.35)
        put(M, lp & (M.Y > c[1] + 1.2), RIBBON_HI, glow=0.45)
        tl = (np.abs(M.X - s * (1.2 + (1.2 - M.Y) * 0.35)) <= 1.2) & (M.Y < 1.0) & (M.Y > -7.0) & (np.abs(M.Z) <= 0.7)
        notch = (M.Y < -5.6) & (np.abs(M.X - s * (1.2 + (1.2 - M.Y) * 0.35)) < (-5.6 - M.Y) * 0.9)
        put(M, tl & ~notch, RIBBON_LO, glow=0.3)
    put(M, ell(M, (0, 2.2, 0.3), (1.6, 1.8, 1.4)), RIBBON_LO, glow=0.4)
    star4(M, (0, 2.4, 1.8), 1.0)
    star4(M, (-6.8, 6.0, 1.0), 1.0)
    star4(M, (6.4, -2.6, 1.0), 0.9)
    return M, Camera(yaw=-10, pitch=8)


def season_first_light_banner():
    M = M_((-9, -1, -5), (9, 22, 5), res=2)
    # the pole, a crossbar and a base
    put(M, box(M, (-6.2, 0.0, -0.6), (-5.0, 20.0, 0.6)), WOOD_LO)
    put(M, box(M, (-7.2, 0.0, -1.6), (-4.0, 1.2, 1.6)), WOOD)
    put(M, box(M, (-6.2, 18.0, -0.5), (6.6, 19.0, 0.5)), WOOD)
    put(M, ell(M, (-5.6, 20.4, 0), (1.0, 1.0, 1.0)), GOLD_HI)
    # the cloth: night-blue with a pointed foot
    x0, x1 = -4.4, 5.8
    cx = (x0 + x1) / 2
    cloth = (M.X >= x0) & (M.X < x1) & (M.Y < 18.0) & (M.Y >= 5.0 + np.abs(M.X - cx) * 0.55) & (np.abs(M.Z) <= 0.5)
    put(M, cloth, NAVY)
    put(M, cloth & (M.Y > 16.6), NAVY_HI)
    put(M, cloth & ((M.X < x0 + 0.8) | (M.X > x1 - 0.8)), GOLD_LO)
    # a rising sun with rays
    c = (cx, 10.6)
    pr = np.sqrt((M.X - c[0]) ** 2 + (M.Y - c[1]) ** 2)
    zf = (M.Z > 0.3) & (M.Z <= 1.2)
    put(M, (pr <= 2.4) & (M.Y >= c[1]) & zf, SUN, glow=0.7)
    put(M, (pr <= 1.3) & (M.Y >= c[1]) & zf, SUN_CORE, glow=0.9)
    a = np.arctan2(M.X - c[0], M.Y - c[1])
    put(M, (pr > 2.8) & (pr <= 4.4) & (M.Y >= c[1] + 0.2) & (np.cos(7 * a) > 0.6) & zf, GOLD_HI, glow=0.5)
    put(M, (np.abs(M.Y - c[1] + 0.3) <= 0.3) & (np.abs(M.X - c[0]) <= 4.0) & zf, GOLD, glow=0.4)
    for (x, y) in ((cx - 3.0, 15.4), (cx + 3.2, 14.6), (cx + 0.4, 16.2)):
        put(M, ell(M, (x, y, 0.8), (0.5, 0.5, 0.4)), FIREFLY, glow=1.0)
    return M, Camera(yaw=-14, pitch=8)


def season_first_light_scarf():
    M = M_((-12, -10, -12), (12, 8, 12), res=2)
    r = np.sqrt(M.X ** 2 + M.Z ** 2)
    band = (r >= 6.0) & (r <= 8.8) & (M.Y >= -1.0) & (M.Y < 3.0)
    put(M, band, PEACH)
    put(M, band & (M.Y >= 2.2), PEACH_HI)
    put(M, band & (M.Y < -0.3), PEACH_LO)
    tail = (M.X >= 1.5) & (M.X <= 4.8) & (M.Z >= 6.0) & (M.Z <= 8.5) & (M.Y < 1.0) & (M.Y > -7.0)
    put(M, tail, PEACH)
    put(M, tail & (M.Y <= -5.8), PEACH_LO)
    # a little sun charm on the knot
    put(M, ell(M, (3.0, 1.0, 8.2), (2.0, 1.8, 1.5)), PEACH_LO)
    put(M, ell(M, (3.0, 0.8, 9.4), (1.2, 1.2, 0.7)), SUN, glow=0.7)
    return M, Camera(yaw=-15, pitch=26)


def season_dawn_shimmer():
    M = M_((-10, -10, -3), (10, 10, 3), res=2)
    # a spiral of sparkles from gold through pink to cyan
    cols = [SUN, '#FFC27A', ROSE_HI, '#D9B8FF', CY_HI]
    for i in range(26):
        t = i / 25
        a = t * 3.2 * math.pi
        rr = 1.0 + 7.2 * t
        p = (math.cos(a) * rr, math.sin(a) * rr, 0.0)
        s = 0.55 + 0.75 * (1 - t)
        put(M, ell(M, p, (s, s, s)), cols[min(len(cols) - 1, int(t * len(cols)))], glow=0.9)
    star5(M, (0, 0, 0.6), 2.6, 1.1, 0.9, STAR, STAR_HI, glow=1.0)
    star4(M, (6.4, 6.0, 1.0), 2.0)
    star4(M, (-6.6, -5.0, 1.0), 1.6)
    return M, Camera(yaw=-8, pitch=6)


def ember_draught():
    """A round flask of glowing ember-orange brew with a little flame dancing on the cork."""
    M = M_((-8, -1, -8), (8, 18, 8), res=2)
    cy = bottle(M, 'round', '#FF7A2E', '#FFC064', glow=0.75)
    flame = (plane_dist(M, (0, cy[1] + 2.6, 0)) <= 1.7 - 0.25 * (M.Y - cy[1] - 1.5)) & (M.Y > cy[1]) & (np.abs(M.Z) <= 1.0)
    put(M, flame & (M.m == 0), '#FFB13B', glow=1.0)
    put(M, (plane_dist(M, (0, cy[1] + 2.2, 0)) <= 0.8) & (np.abs(M.Z) <= 1.2), '#FFF2B0', glow=1.0)
    for (x, y, z) in ((1.4, 3.2, 2.9), (-0.8, 2.2, 3.1), (0.5, 4.8, 3.0)):
        put(M, ell(M, (x, y, z), (0.45, 0.45, 0.45)), '#FFE7A8', glow=1.0)
    return M, Camera(yaw=-20, pitch=16)


def thornskin_tonic():
    """A tall bottle of deep-green brew wrapped in a briar of little thorns, a heartwood chip on the cork."""
    M = M_((-8, -1, -8), (8, 18, 8), res=2)
    cy = bottle(M, 'tall', '#3E9A55', '#8FD07A', glow=0.4)
    for k in range(10):
        a = k * 1.9
        y = 1.5 + k * 0.85
        x, z = math.cos(a) * 3.1, math.sin(a) * 3.1
        put(M, ell(M, (x, y, z), (0.55, 0.55, 0.55)), '#6B4A31')
        tip = spike(M, (x, y, z), (math.cos(a), 0.25, math.sin(a)), 1.4, 0.5, 0.1)
        put(M, tip & (M.m == 0), '#E9D9B0')
    put(M, box(M, (-1.2, cy[1], -1.2), (1.2, cy[1] + 1.2, 1.2)) & (M.m == 0), '#7FE3C8', glow=0.6)
    return M, Camera(yaw=-20, pitch=16)


ITEMS = {
    'ember_draught': ember_draught, 'thornskin_tonic': thornskin_tonic,
    'sunstone': sunstone, 'moonwell_dew': moonwell_dew, 'heartbloom': heartbloom,
    'wayfinder_compass': wayfinder_compass, 'golden_acorn': golden_acorn, 'hollow_ward': hollow_ward,
    'starseed': starseed, 'prism_scale': prism_scale, 'glimmer': glimmer, 'starter_pack': starter_pack,
    'season_dawn_circlet': season_dawn_circlet, 'season_firefly_scarf': season_firefly_scarf,
    'season_lantern_wings': season_lantern_wings, 'season_glow_ribbon': season_glow_ribbon,
    'season_first_light_banner': season_first_light_banner, 'season_first_light_scarf': season_first_light_scarf,
    'season_dawn_shimmer': season_dawn_shimmer,
}


# ================================================================== chests
CHEST_TIERS = {
    #          body      body_hi    body_lo    band       band_hi    band_lo    glow_band light
    'wood': ('#A86E42', '#C98C57', '#7A4A2C', '#5E5550', '#857A74', '#433B37', None, '#FFE7A0'),
    'silver': ('#6F86A0', '#8FA6BF', '#4F6480', '#D7DEE6', '#FFFFFF', '#A3AFBD', None, '#FFF3C8'),
    'gold': ('#A8323A', '#C94C50', '#7A2228', '#F4C04E', '#FFE29A', '#D99A36', None, '#FFE08A'),
    'lumen': ('#2A3566', '#3B4A85', '#1D2550', '#7FE3D0', '#D2FBF2', '#4FB8A6', 0.85, '#BDF7E4'),
}
HINGE = (6.5, -5.0)  # (y, z) of the lid hinge at the back top edge


def chest(tier, open_=False, angle=108.0):
    body, body_hi, body_lo, band, band_hi, band_lo, bglow, light = CHEST_TIERS[tier]
    M = M_((-10, -1, -13), (10, 22, 9), res=2)
    X, Y, Z = M.X, M.Y, M.Z
    # ---- the box (hollow, so an open chest has an inside)
    outer = (np.abs(X) <= 7.5) & (Y >= 0) & (Y < 6.5) & (np.abs(Z) <= 5)
    inner = (np.abs(X) <= 6.3) & (Y >= 1.2) & (np.abs(Z) <= 3.8)
    shell_ = outer & ~inner
    put(M, shell_, body)
    put(M, shell_ & (Y < 1.0), body_lo)
    # planks
    put(M, shell_ & (np.abs(Y - 3.25) <= 0.25) & (np.abs(Z) > 4.5), body_lo)
    for sx in (-5.5, 0.0, 5.5):
        put(M, shell_ & (np.abs(X - sx) <= 0.8), band, glow=bglow)
    put(M, shell_ & (np.abs(X - 5.5) <= 0.8) & (Y > 4.5), band_hi, glow=bglow)
    put(M, shell_ & (Y >= 5.8), band_lo, glow=bglow)
    corner = shell_ & (np.abs(X) >= 6.8) & ((np.abs(Z) >= 4.3))
    put(M, corner, band_lo, glow=bglow)
    # lock plate on the front of the box
    lock = (np.abs(X) <= 1.6) & (Y >= 3.6) & (Y < 6.5) & (Z > 4.6) & (Z <= 5.8)
    put(M, lock, band_hi, glow=bglow)
    put(M, (np.abs(X) <= 0.45) & (Y >= 4.2) & (Y < 5.4) & (Z > 5.4) & (Z <= 6.0), '#2B2320')

    # ---- the lid, drawn in its own (hinged) frame
    if open_:
        th = math.radians(angle)
        dy, dz = Y - HINGE[0], Z - HINGE[1]
        LY = HINGE[0] + dy * math.cos(th) - dz * math.sin(th)
        LZ = HINGE[1] + dy * math.sin(th) + dz * math.cos(th)
    else:
        LY, LZ = Y, Z
    lid = (np.abs(X) <= 7.5) & (LY >= 6.5) & ((LY - 6.5) ** 2 / 4.5 ** 2 + LZ ** 2 / 5 ** 2 <= 1)
    lid_in = (np.abs(X) <= 6.5) & (LY >= 6.5) & ((LY - 6.5) ** 2 / 3.5 ** 2 + LZ ** 2 / 4.0 ** 2 <= 1)
    lid_shell = lid & ~(lid_in & (LY < 9.6))
    put(M, lid_shell, body_hi)
    put(M, lid_shell & (LY < 7.0), body_lo)
    for sx in (-5.5, 0.0, 5.5):
        put(M, lid_shell & (np.abs(X - sx) <= 0.8), band, glow=bglow)
    put(M, lid_shell & (np.abs(X - 5.5) <= 0.8) & (LZ > 0) & (LY > 8.5), band_hi, glow=bglow)
    put(M, lid_shell & (LY < 7.1) & (np.abs(X) >= 6.8), band_lo, glow=bglow)
    hasp = (np.abs(X) <= 1.1) & (LY >= 6.3) & (LY < 8.6) & (LZ > 4.2) & (LZ <= 5.6)
    put(M, hasp, band_hi, glow=bglow)

    if open_:
        # light pooled inside: a heap of glow, and a few sparkles rising out of it
        heap = ell(M, (0, 4.2, 0), (6.2, 2.4, 3.7)) & inner
        put(M, heap, light, glow=0.75)
        bumps = heap & (Y > 5.2) & (((np.floor(X * 1.5).astype(int) + np.floor(Z * 1.5).astype(int)) % 3) == 0)
        put(M, bumps, '#FFFFFF', glow=0.9)
        for (x, y, z, s) in ((-3.4, 9.6, 1.0, 0.7), (2.6, 11.2, 0.4, 0.6), (0.2, 13.4, 1.2, 0.5),
                             (4.6, 8.8, 2.0, 0.55), (-1.4, 15.0, 0.0, 0.45)):
            put(M, ell(M, (x, y, z), (s, s, s)), light, glow=1.0)
    return M


CHEST_CAM = Camera(yaw=-24, pitch=18)


# ================================================================== UI icons
def ic_glimmer():
    return glimmer()


def ic_caravan():
    M = M_((-11, -1, -7), (11, 16, 7), res=2)
    # the wagon bed
    bed = (np.abs(M.X) <= 7.5) & (M.Y >= 3.0) & (M.Y < 6.0) & (np.abs(M.Z) <= 4.2)
    put(M, bed, WOOD)
    put(M, bed & (M.Y < 3.8), WOOD_LO)
    # the canvas hood: a half cylinder along x, night blue with a gold star
    hood = (np.abs(M.X) <= 6.8) & (M.Y >= 6.0) & ((M.Y - 6.0) ** 2 / 6.2 ** 2 + M.Z ** 2 / 4.6 ** 2 <= 1)
    put(M, hood, NAVY)
    put(M, hood & (M.Y > 10.6), NAVY_HI)
    for sx in (-4.6, 0.0, 4.6):
        put(M, hood & (np.abs(M.X - sx) <= 0.45), '#E8CFA0')
    star5(M, (2.3, 9.0, 4.0), 2.0, 0.8, 0.7, GOLD, GOLD_HI, glow=0.6)
    # wheels
    for wx in (-4.8, 4.8):
        rr = np.sqrt((M.X - wx) ** 2 + (M.Y - 2.8) ** 2)
        wheel = (rr <= 2.8) & (np.abs(np.abs(M.Z) - 4.6) <= 0.6)
        put(M, wheel & (rr >= 2.0), WOOD_LO)
        put(M, wheel & (rr < 0.8), '#5E5550')
        put(M, wheel & ((np.abs(M.X - wx) <= 0.3) | (np.abs(M.Y - 2.8) <= 0.3)) & (rr < 2.0), WOOD_LO)
    # a lantern hanging at the front
    put(M, box(M, (7.0, 9.0, -0.4), (8.6, 9.6, 0.4)), WOOD_LO)
    put(M, ell(M, (8.4, 7.6, 0), (0.9, 1.2, 0.9)), '#FFE7A0', glow=1.0)
    return M, Camera(yaw=-22, pitch=12)


def ic_plus():
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    r = np.sqrt(M.X ** 2 + M.Y ** 2)
    disc = (r <= 8.2) & (np.abs(M.Z) <= 1.6)
    put(M, disc, GOLD)
    put(M, disc & (r > 7.0), GOLD_LO)
    put(M, disc & (r > 7.0) & (M.X < 0) & (M.Y > 0) & (M.Z > 0), GOLD_HI)
    face = (M.Z > 1.0) & (M.Z <= 2.2)
    # a paw, a little to the lower left
    pad = ell(M, (-1.2, -2.0, 1.6), (2.8, 2.2, 0.8))
    toes = np.zeros(M.m.shape, bool)
    for (x, y) in ((-4.2, 0.8), (-2.2, 2.5), (0.0, 2.5), (1.8, 0.8)):
        toes |= ell(M, (x, y, 1.6), (1.1, 1.4, 0.8))
    put(M, (pad | toes) & face, '#7A5440')
    # the plus, top right
    pl = ((np.abs(M.X - 4.2) <= 0.9) & (np.abs(M.Y - 3.8) <= 2.6)) | ((np.abs(M.X - 4.2) <= 2.6) & (np.abs(M.Y - 3.8) <= 0.9))
    put(M, pl & (M.Z > 1.0) & (M.Z <= 2.6), WHITE)
    return M, Camera(yaw=-10, pitch=8)


def ic_season():
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    r = np.sqrt(M.X ** 2 + M.Y ** 2)
    disc = (r <= 8.2) & (np.abs(M.Z) <= 1.4)
    put(M, disc, NAVY)
    put(M, disc & (r > 7.0), GOLD_LO)
    put(M, disc & (r > 7.0) & (M.X < 0) & (M.Y > 0), GOLD)
    face = (M.Z > 0.8) & (M.Z <= 2.4)
    # a lantern with a firefly glow
    put(M, (np.abs(M.X) <= 2.6) & (M.Y >= -4.2) & (M.Y < -3.2) & face, WOOD_LO)
    put(M, (np.abs(M.X) <= 2.0) & (M.Y >= -3.2) & (M.Y < 2.6) & face, '#FFE7A0', glow=1.0)
    put(M, (np.abs(M.X) <= 2.0) & (M.Y >= -3.2) & (M.Y < 2.6) & face & (np.abs(M.X) >= 1.4), WOOD_LO)
    put(M, (np.abs(M.X) <= 2.8 - (M.Y - 2.6) * 0.8) & (M.Y >= 2.6) & (M.Y < 4.6) & face, WOOD_LO)
    rr = np.sqrt(M.X ** 2 + (M.Y - 5.4) ** 2)
    put(M, (rr <= 1.2) & (rr >= 0.5) & face, GOLD_HI)
    for (x, y) in ((-5.0, 2.6), (4.8, 1.0), (-3.8, -4.6), (5.0, -4.2)):
        put(M, ell(M, (x, y, 1.6), (0.7, 0.7, 0.7)), FIREFLY, glow=1.0)
    return M, Camera(yaw=-10, pitch=8)


ICONS = {
    'glimmer': ic_glimmer, 'caravan': ic_caravan, 'plus': ic_plus, 'season': ic_season,
    'chest_wood': lambda: (chest('wood'), Camera(yaw=-22, pitch=14)),
    'chest_silver': lambda: (chest('silver'), Camera(yaw=-22, pitch=14)),
    'chest_gold': lambda: (chest('gold'), Camera(yaw=-22, pitch=14)),
    'chest_lumen': lambda: (chest('lumen'), Camera(yaw=-22, pitch=14)),
}


# ================================================================== output
def _webp(arr, path, size=None, q=90):
    im = Image.fromarray(arr, 'RGBA')
    if size and im.width != size:
        im = im.resize((size, size), Image.LANCZOS)
    im.save(path, 'WEBP', quality=q, method=6)


def _manifest(out):
    p = os.path.join(out, 'manifest.json')
    with open(p) as f:
        return p, json.load(f)


def items(out, only=None, man=None):
    os.makedirs(os.path.join(out, 'items'), exist_ok=True)
    for k, b in ITEMS.items():
        if only and k not in only:
            continue
        M, cam = b()
        _webp(render_model(M, cam, 256), os.path.join(out, 'items', f'{k}.webp'), 168)
        man['items'][k] = f'items/{k}.webp'
        print('item', k, flush=True)


def icons(out, only=None, man=None):
    os.makedirs(os.path.join(out, 'icons'), exist_ok=True)
    for k, b in ICONS.items():
        if only and k not in only:
            continue
        M, cam = b()
        _webp(render_model(M, cam, 192, outline=2.6), os.path.join(out, 'icons', f'{k}.webp'), 112)
        man['icons'][k] = f'icons/{k}.webp'
        print('icon', k, flush=True)


def chests(out, only=None, size=384):
    os.makedirs(os.path.join(out, 'economy'), exist_ok=True)
    for tier in CHEST_TIERS:
        if only and tier not in only:
            continue
        closed, opened = chest(tier, False), chest(tier, True)
        # one fit for both states so the sprites line up when swapped
        pts = np.concatenate([model_extent_points(closed), model_extent_points(opened)])
        fit = fit_camera(CHEST_CAM, pts, size, size, 0.06)
        for state, M in (('closed', closed), ('open', opened)):
            o = render(M, {}, CHEST_CAM, size, size, fit=fit, light=LIGHT, ss=3,
                       outline_px=size / 70, outline_col='#3B2923',
                       inner_thresh=2.0, inner_alpha=0.55, inner_px=0.8)
            _webp(o.rgba, os.path.join(out, 'economy', f'chest_{tier}_{state}.webp'))
            print('chest', tier, state, flush=True)


if __name__ == '__main__':
    out = sys.argv[1]
    parts = sys.argv[2:] or ['items', 'icons', 'chests']
    only = [p for p in parts if p not in ('items', 'icons', 'chests')] or None
    path, man = _manifest(out)
    if 'items' in parts:
        items(out, only, man)
    if 'icons' in parts:
        icons(out, only, man)
    if 'chests' in parts:
        chests(out, only)
    with open(path, 'w') as f:
        json.dump(man, f, indent=1)

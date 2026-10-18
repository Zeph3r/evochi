"""Home art drawn with the flat item renderer: seeds, harvests, Kitchen meals, Apothecary brews, the
Sturdy Timber quest material, three skill icons, and the crop sprites for the Garden beds.

  python3 home_items.py ASSETS_DIR
    ASSETS/items/item_<id>_icon.png          256px item icons (picked up by the web packer)
    ASSETS/ui_icons/icon_<k>.png             192px UI icons (skill_farming, skill_cooking, skill_alchemy, home_map)
    ASSETS/home/crop_<crop>_<stage>.png      bed sprites, all on one shared canvas + ASSETS/home/crops.json

Crop sprites share one camera and one fit, so every sprite lines up the same way on a bed: the
JSON gives the canvas size, the pixel of the bed's centre on the ground and the bed's width in
pixels; the game scales a sprite by (bed width on the Garden plate / bed width here).
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np

from voxel import Camera, render, save_rgba, fit_camera, project_px
from items import M_, ell, cyl, flower, LEAF, LEAF_HI, LEAF_LO, WHITE, GOLD
from characters import spike
from build_items import render_model, LIGHT

BERRY, BERRY_HI, BERRY_LO = '#F0613E', '#FFA05A', '#C8402E'
CARROT, CARROT_HI, CARROT_LO = '#F08A3A', '#FFB062', '#D06A24'
WHEAT, WHEAT_HI, WHEAT_LO = '#F0C95A', '#FFE08A', '#C9A040'
MINT, MINT_HI, MINT_LO = '#7FD9B8', '#C9F5E4', '#4FB894'
SHROOM, SHROOM_HI, SHROOM_LO = '#9975C9', '#C8B1E4', '#6E4FA3'
STEM = '#5EA046'
PAPER, PAPER_LO = '#FBF5E8', '#E9DCC0'
CRUST, CRUST_HI, CRUST_LO = '#E3B26A', '#F2CF8C', '#C48F48'
WOOD, WOOD_HI, WOOD_LO = '#C69469', '#E2B488', '#8D5D3B'
CREAM = '#FBF5E8'
COPPER, COPPER_HI = '#C9874E', '#E2B488'
IRON = '#4A3F3A'


def put(M, mask, col, glow=None, empty=False):
    if empty:
        mask = mask & (M.m == 0)
    M.set(mask, col)
    if glow is not None:
        M.glow[mask] = glow
    return mask


def box(M, lo, hi):
    return (M.X >= lo[0]) & (M.X < hi[0]) & (M.Y >= lo[1]) & (M.Y < hi[1]) & (M.Z >= lo[2]) & (M.Z < hi[2])


def ycyl(M, c, r, y0, y1):
    return ((M.X - c[0]) ** 2 + (M.Z - c[1]) ** 2 <= r * r) & (M.Y >= y0) & (M.Y < y1)


# ------------------------------------------------------------------ plants (shared by icons and beds)
def berry(M, c, r=1.0):
    b = ell(M, c, (r, r, r), p=2.2)
    put(M, b, BERRY)
    put(M, b & (M.Y > c[1] + r * 0.35) & (M.X < c[0] + r * 0.2), BERRY_HI)
    put(M, b & (M.Y < c[1] - r * 0.45), BERRY_LO)
    put(M, (np.abs(M.X - c[0]) < 0.35) & (np.abs(M.Z - c[2]) < 0.35) & (M.Y > c[1] + r * 0.8) & (M.Y < c[1] + r * 1.3), '#6B4226')
    return b


def carrot(M, base, length=6.0, r=1.4, tilt=(0.0, 0.0)):
    """Root pointing down from `base` (its shoulder), with a leafy top."""
    bx, by, bz = base
    t = np.clip((by - M.Y) / length, 0, 1)
    rr = r * (1 - t) ** 0.8
    root = ((M.X - bx - tilt[0] * (by - M.Y)) ** 2 + (M.Z - bz - tilt[1] * (by - M.Y)) ** 2 <= rr ** 2) & (M.Y <= by) & (M.Y > by - length)
    put(M, root, CARROT)
    put(M, root & ((np.floor((by - M.Y) / 0.9) % 3) == 0), CARROT_LO)
    put(M, root & (M.X < bx - rr * 0.3), CARROT_HI)
    for i, d in enumerate(((0.3, 1, 0.2), (-0.4, 1, 0.1), (0.0, 1, -0.4), (0.1, 1, 0.5))):
        lf = spike(M, (bx, by, bz), d, 4.0 + (i % 2), 1.0, 0.3, twist=0.6 * i)
        put(M, lf & (M.m == 0), LEAF if i % 2 else LEAF_HI)
    return root


def wheat_stalk(M, x, z, h, head=True, lean=(0.0, 0.0), ripe=True):
    stalk = (np.abs(M.X - x - lean[0] * M.Y / h) < 0.32) & (np.abs(M.Z - z - lean[1] * M.Y / h) < 0.32) & (M.Y >= 0) & (M.Y < h)
    put(M, stalk, '#C9B05A' if ripe else STEM)
    if head:
        hx, hz = x + lean[0], z + lean[1]
        hd = ell(M, (hx, h + 0.8, hz), (0.6, 1.1, 0.6), p=2.0)
        put(M, hd, WHEAT if ripe else LEAF_HI)
        put(M, hd & ((np.floor((M.Y - h) / 0.5) % 2) == 0), WHEAT_HI if ripe else LEAF)
        if ripe:
            for k in range(3):
                aw = (np.abs(M.X - hx - 0.4 * (k - 1)) < 0.18) & (np.abs(M.Z - hz) < 0.18) & (M.Y >= h + 2.2) & (M.Y < h + 3.0 + 0.3 * k)
                put(M, aw, WHEAT_LO)


def glowleaf(M, c, s=1.0, glow=0.6, n=5):
    for i in range(n):
        a = i * 2 * np.pi / n + 0.4
        d = (np.cos(a), 0.9, np.sin(a))
        lf = spike(M, c, d, 4.2 * s, 1.6 * s, 0.35, twist=0.3)
        put(M, lf & (M.m == 0), MINT if i % 2 else MINT_HI, glow=glow)
        vein = spike(M, c, d, 3.6 * s, 0.35 * s, 0.4, twist=0.3) & lf
        put(M, vein, MINT_LO, glow=glow * 0.6)
    put(M, ell(M, (c[0], c[1] + 3.2 * s, c[2]), (0.45 * s, 0.45 * s, 0.45 * s)), '#FFF3B0', glow=1.0)


def mushroom(M, c, s=1.0, glow=0.5):
    x, y, z = c
    stem = ycyl(M, (x, z), 0.7 * s, y, y + 2.6 * s)
    put(M, stem, CREAM)
    cap = ell(M, (x, y + 2.8 * s, z), (2.0 * s, 1.2 * s, 2.0 * s), p=2.0) & (M.Y >= y + 2.2 * s)
    put(M, cap, SHROOM)
    put(M, cap & (M.Y > y + 3.4 * s) & (M.X < x), SHROOM_HI)
    put(M, cap & (M.Y < y + 2.6 * s), SHROOM_LO)
    for (dx, dz) in ((0.8, 0.6), (-0.6, 1.0), (0.2, -1.0), (-1.1, -0.3)):
        sp = ell(M, (x + dx * s, y + 3.5 * s, z + dz * s), (0.4 * s, 0.4 * s, 0.4 * s)) & cap
        put(M, sp, '#F7F1FF', glow=glow)


def sprout(M, x, z, s=1.0, col=LEAF_HI, y=0.0):
    put(M, (np.abs(M.X - x) < 0.3 * s) & (np.abs(M.Z - z) < 0.3 * s) & (M.Y >= y) & (M.Y < y + 1.6 * s), STEM)
    for d in ((0.9, 0.6, 0.2), (-0.9, 0.6, -0.2)):
        lf = spike(M, (x, y + 1.4 * s, z), d, 1.8 * s, 0.9 * s, 0.3)
        put(M, lf & (M.m == 0), col)


# ------------------------------------------------------------------ item icons
def i_sunberry():
    M = M_((-8, -1, -8), (8, 12, 8), res=2)
    for c, r in (((-2.3, 2.6, 0.4), 2.5), ((2.2, 2.6, 0.0), 2.5), ((0.0, 2.5, 2.6), 2.4), ((0.0, 5.6, 0.6), 2.5)):
        berry(M, c, r)
    for d in ((0.7, 0.5, 0.6), (-0.8, 0.4, -0.3), (0.1, 0.5, -0.9)):
        lf = spike(M, (0.0, 7.8, 0.6), d, 4.0, 1.5, 0.3)
        put(M, lf & (M.m == 0), LEAF)
    return M, Camera(yaw=-20, pitch=20)


def i_meadow_carrot():
    M = M_((-8, -1, -8), (8, 16, 8), res=2)
    carrot(M, (0.0, 9.0, 0.0), length=9.0, r=2.4, tilt=(0.22, 0.05))
    return M, Camera(yaw=-25, pitch=14)


def i_golden_wheat():
    M = M_((-8, -1, -8), (8, 17, 8), res=2)
    for k, (x, z) in enumerate(((-1.2, 0.0), (0.0, 0.8), (1.2, 0.0), (-0.6, -0.9), (0.7, -0.8))):
        wheat_stalk(M, x, z, 10.0, lean=((x * 0.8), (z * 0.6)))
    put(M, ycyl(M, (0, 0), 1.9, 4.0, 5.2), '#C9874E')
    put(M, ycyl(M, (0, 0), 1.9, 4.4, 4.8), '#E8B956')
    return M, Camera(yaw=-20, pitch=12)


def i_glowleaf():
    M = M_((-8, -1, -8), (8, 12, 8), res=2)
    glowleaf(M, (0, 1.0, 0), s=1.5, glow=0.55, n=6)
    return M, Camera(yaw=-20, pitch=26)


def i_moonshroom():
    M = M_((-8, -1, -8), (8, 13, 8), res=2)
    mushroom(M, (0.6, 0, 0.4), s=1.9)
    mushroom(M, (-3.0, 0, 1.4), s=1.1)
    return M, Camera(yaw=-20, pitch=16)


def seed_packet(crop):
    """A paper seed packet with a little picture of the crop on its front and a few seeds spilled."""
    M = M_((-8, -1, -8), (8, 16, 8), res=2)
    pk = box(M, (-4.6, 0, -0.8), (4.6, 12.0, 0.8))
    band = {'sunberry': BERRY, 'meadow_carrot': CARROT, 'golden_wheat': WHEAT, 'glowleaf': MINT, 'moonshroom': SHROOM}[crop]
    put(M, pk, PAPER)
    put(M, pk & (M.Y >= 10.0), band)
    put(M, pk & (M.Y < 1.2), band)
    put(M, pk & (M.Y >= 11.2) & (((M.X + 4.6) % 1.2) < 0.6), PAPER_LO)      # crimped top
    put(M, box(M, (-3.4, 2.0, 0.8), (3.4, 9.0, 1.2)), '#F3E5C9')             # picture window
    if crop == 'sunberry':
        for c in ((-1.0, 4.4, 1.6), (1.1, 4.6, 1.6), (0.0, 6.3, 1.6)):
            berry(M, c, 1.3)
    elif crop == 'meadow_carrot':
        carrot(M, (0.0, 7.4, 1.8), length=5.0, r=1.3, tilt=(0.15, 0.0))
    elif crop == 'golden_wheat':
        for x in (-1.2, 0.0, 1.2):
            hd = ell(M, (x, 6.2, 1.6), (0.6, 1.6, 0.5), p=2.0)
            put(M, hd, WHEAT)
            put(M, (np.abs(M.X - x) < 0.25) & (M.Y >= 2.6) & (M.Y < 4.8) & (np.abs(M.Z - 1.6) < 0.3), '#C9B05A')
    elif crop == 'glowleaf':
        for i, d in enumerate(((0.8, 1, 0.3), (-0.8, 1, 0.3), (0, 1, 0.6))):
            lf = spike(M, (0, 3.0, 1.6), d, 4.0, 1.4, 0.3)
            put(M, lf & (M.m == 0), MINT if i % 2 else MINT_HI, glow=0.5)
    elif crop == 'moonshroom':
        mushroom(M, (0.0, 2.6, 1.8), s=1.2)
    for (x, z) in ((-3.0, 4.2), (-1.4, 5.0), (2.4, 4.6), (4.0, 3.8)):
        put(M, ell(M, (x, 0.4, z), (0.55, 0.4, 0.4)), '#B07A48' if crop != 'moonshroom' else '#C8B1E4')
    return M, Camera(yaw=-20, pitch=12)


def dish(M, r=6.0, y=0.0, col='#BFE4FA', rim='#9CCDEB'):
    plate = ycyl(M, (0, 0), r, y, y + 0.8) & ~ycyl(M, (0, 0), r - 1.0, y + 0.4, y + 0.8)
    put(M, plate, col)
    put(M, ycyl(M, (0, 0), r, y + 0.6, y + 0.8) & ~ycyl(M, (0, 0), r - 0.6, y, y + 0.8), rim)


def i_sunberry_tart():
    M = M_((-9, -1, -9), (9, 8, 9), res=2)
    dish(M, 7.4)
    crust = ycyl(M, (0, 0), 6.2, 0.6, 2.8)
    put(M, crust, CRUST)
    put(M, crust & (M.Y >= 2.2) & (np.sqrt(M.X ** 2 + M.Z ** 2) > 5.2), CRUST_HI)
    put(M, crust & ((np.floor(np.degrees(np.arctan2(M.Z, M.X)) / 15) % 2) == 0) & (np.sqrt(M.X ** 2 + M.Z ** 2) > 5.6), CRUST_LO)
    fill = ycyl(M, (0, 0), 5.0, 2.2, 2.8)
    put(M, fill, BERRY_LO)
    for k in range(9):
        a = k * 0.7
        rr = 3.2 if k < 7 else 0.0
        berry(M, (rr * np.cos(a) * (k < 7), 3.2, rr * np.sin(a) * (k < 7) + (k == 8) * 1.4), 1.05)
    lat = fill & ((np.abs((M.X + M.Z) % 2.6) < 0.5) | (np.abs((M.X - M.Z) % 2.6) < 0.5)) & (M.Y >= 2.6)
    put(M, lat, CRUST_HI)
    return M, Camera(yaw=-20, pitch=34)


def i_carrot_stew():
    M = M_((-9, -1, -9), (9, 10, 9), res=2)
    bowl = ell(M, (0, 4.6, 0), (6.4, 4.6, 6.4), p=2.0) & (M.Y < 4.8) & (M.Y >= 0)
    hollow = ell(M, (0, 4.6, 0), (5.6, 4.0, 5.6), p=2.0)
    put(M, bowl & ~hollow, '#E0A16A')
    put(M, bowl & ~hollow & (M.Y > 3.6), '#F0BE8C')
    put(M, ycyl(M, (0, 0), 2.6, 0, 0.6), '#C48F48')
    soup = ycyl(M, (0, 0), 5.5, 3.2, 3.8)
    put(M, soup, '#E8913C')
    for (x, z) in ((-2.4, 0.8), (1.6, 2.2), (2.6, -1.6), (-0.6, -2.6), (0.4, 0.4)):
        put(M, box(M, (x - 0.7, 3.6, z - 0.7), (x + 0.7, 4.4, z + 0.7)), CARROT_HI)
    for (x, z) in ((-1.0, 2.6), (2.8, 0.6)):
        put(M, ell(M, (x, 4.0, z), (0.7, 0.4, 0.7)), LEAF_HI)
    for k in range(3):
        put(M, ell(M, (-1.0 + k * 1.0, 6.4 + k * 1.3, 0.0), (0.6, 0.7, 0.6)) & (M.m == 0), '#F7F5F0')
    return M, Camera(yaw=-20, pitch=30)


def i_golden_bun():
    M = M_((-8, -1, -8), (8, 9, 8), res=2)
    bun = ell(M, (0, 2.8, 0), (5.6, 3.6, 4.6), p=2.3) & (M.Y >= 0)
    put(M, bun, CRUST)
    put(M, bun & (M.Y > 4.4), '#D9963E')
    put(M, bun & (M.Y > 5.0) & (M.X < 0), '#E9AE58')
    for x in (-2.0, 0.0, 2.0):
        put(M, bun & (np.abs(M.X - x - (M.Z * 0.25)) < 0.35) & (M.Y > 4.6), CRUST_HI)
    for (x, z) in ((-1.4, 1.0), (1.2, -0.6), (0.2, 1.8), (2.4, 1.2)):
        put(M, ell(M, (x, 6.4, z), (0.3, 0.25, 0.3)), CREAM)
    return M, Camera(yaw=-20, pitch=24)


def i_moonshroom_pie():
    M = M_((-9, -1, -9), (9, 9, 9), res=2)
    dish(M, 7.4, col='#E8E0FF', rim='#C8B1E4')
    crust = ycyl(M, (0, 0), 6.2, 0.6, 3.4)
    put(M, crust, CRUST)
    top = ell(M, (0, 3.2, 0), (6.0, 1.6, 6.0), p=2.0) & (M.Y >= 3.2)
    put(M, top, CRUST_HI)
    put(M, top & (np.abs(M.X) < 0.5) | top & (np.abs(M.Z) < 0.5), CRUST_LO)
    mushroom(M, (0.0, 3.6, 0.0), s=1.2, glow=0.6)
    for (x, z) in ((3.4, 2.2), (-3.0, -2.4), (2.6, -3.0)):
        put(M, ell(M, (x, 4.4, z), (0.5, 0.4, 0.5)) & (M.m == 0), SHROOM_HI, glow=0.5)
    return M, Camera(yaw=-20, pitch=30)


def bottle(M, kind, liquid, liquid_hi, glow=0.6):
    if kind == 'round':
        body = ell(M, (0, 4.4, 0), (4.0, 4.0, 4.0), p=2.0) & (M.Y >= 0.6)
        neck = ycyl(M, (0, 0), 1.3, 7.6, 10.6)
        cork_y = (10.6, 12.2)
    else:
        body = ycyl(M, (0, 0), 2.8, 0.6, 9.0) | (ell(M, (0, 9.0, 0), (2.8, 1.6, 2.8)) & (M.Y >= 9.0))
        neck = ycyl(M, (0, 0), 1.2, 9.8, 12.4)
        cork_y = (12.4, 14.0)
    put(M, body, '#E8F7F9')
    liq = body & (M.Y < (5.6 if kind == 'round' else 7.0))
    put(M, liq, liquid, glow=glow)
    put(M, liq & (M.X < -1.0) & (M.Y > 2.0), liquid_hi, glow=glow)
    put(M, body & ~liq & (M.X < -1.6), '#FFFFFF')
    put(M, neck, '#DDF3F6')
    put(M, ycyl(M, (0, 0), 1.0, cork_y[0], cork_y[1]), '#B07A48')
    put(M, ycyl(M, (0, 0), 1.6, neck_y_lo(kind), neck_y_lo(kind) + 0.6), '#E8B956')
    return cork_y


def neck_y_lo(kind):
    return 8.2 if kind == 'round' else 10.4


def i_glowleaf_tonic():
    M = M_((-8, -1, -8), (8, 15, 8), res=2)
    cy = bottle(M, 'round', '#7FD9B8', '#C9F5E4', glow=0.7)
    for i, d in enumerate(((0.7, 0.6, 0.2), (-0.6, 0.7, 0.1))):
        lf = spike(M, (0, cy[1], 0), d, 3.0, 1.1, 0.3)
        put(M, lf & (M.m == 0), MINT_HI if i else MINT, glow=0.4)
    for (x, y, z) in ((1.2, 3.4, 2.6), (-0.6, 2.4, 3.0), (0.4, 4.6, 3.2)):
        put(M, ell(M, (x, y, z), (0.45, 0.45, 0.45)), '#E8FBF4', glow=1.0)
    return M, Camera(yaw=-20, pitch=16)


def i_meadow_tea():
    M = M_((-8, -1, -8), (8, 12, 8), res=2)
    put(M, ycyl(M, (0, 0), 5.6, 0, 0.6) & ~ycyl(M, (0, 0), 4.6, 0.3, 0.6), '#FBF5E8')   # saucer
    cup = ycyl(M, (0, 0), 3.6, 0.6, 5.0) & ~ycyl(M, (0, 0), 3.0, 1.2, 5.0)
    put(M, cup, '#FBF5E8')
    put(M, cup & (np.abs(M.Y - 3.6) < 0.4), '#7FD9B8')
    handle = ((M.X - 4.2) ** 2 + (M.Y - 3.0) ** 2 <= 1.6 ** 2) & ((M.X - 4.2) ** 2 + (M.Y - 3.0) ** 2 >= 0.8 ** 2) & (np.abs(M.Z) <= 0.5) & (M.X > 3.4)
    put(M, handle, '#FBF5E8')
    put(M, ycyl(M, (0, 0), 3.0, 3.8, 4.4), '#C9B05A')
    put(M, ell(M, (0.6, 4.6, 0.6), (1.0, 0.3, 0.6)), LEAF_HI)
    for k in range(3):
        put(M, ell(M, (-0.8 + 0.7 * k, 6.4 + k * 1.4, 0.2 * k), (0.6, 0.8, 0.6)) & (M.m == 0), '#F7F5F0')
    return M, Camera(yaw=-20, pitch=26)


def i_sprout_tonic():
    M = M_((-8, -1, -8), (8, 17, 8), res=2)
    cy = bottle(M, 'tall', '#9CD47E', '#C9F0A8', glow=0.45)
    sprout(M, 0, 0, s=1.4, y=cy[1] - 0.2)
    return M, Camera(yaw=-20, pitch=14)


def i_moonlight_draught():
    M = M_((-8, -1, -8), (8, 17, 8), res=2)
    bottle(M, 'tall', '#3C4F9E', '#6F82D6', glow=0.5)
    for (x, y, z) in ((-0.6, 2.4, 2.8), (1.4, 4.4, 2.4), (0.0, 5.8, 2.9), (-1.6, 4.0, 2.2)):
        put(M, box(M, (x - 0.35, y - 0.35, z - 0.2), (x + 0.35, y + 0.35, z + 0.6)), '#FFE5A2', glow=1.0)
    put(M, ell(M, (2.4, 13.6, 0), (1.2, 1.2, 0.5)) & ~ell(M, (3.0, 14.0, 0), (1.0, 1.0, 0.7)), '#FFE5A2', glow=1.0)   # tiny moon charm
    return M, Camera(yaw=-20, pitch=14)


def i_sturdy_timber():
    M = M_((-9, -1, -8), (9, 9, 8), res=2)
    for k, (y, z) in enumerate(((1.0, -1.4), (1.0, 1.4), (3.4, 0.0), (3.4, -2.6), (3.4, 2.6), (5.8, -1.4), (5.8, 1.4))):
        pl = (np.abs(M.Y - y) <= 1.1) & (np.abs(M.Z - z) <= 1.2) & (np.abs(M.X) <= 7.6 - (k % 2) * 0.6)
        put(M, pl, [WOOD, WOOD_HI, '#B98955'][k % 3])
        put(M, pl & (np.abs(M.X) > 7.0 - (k % 2) * 0.6), '#E8C9A0')     # cut ends
        put(M, pl & ((np.floor((M.X + 8) / 2.3) % 3) == 0) & (np.abs(M.Y - y) < 0.3), WOOD_LO)
    for x in (-4.0, 4.0):
        put(M, (np.abs(M.X - x) <= 0.5) & (np.sqrt(M.Y ** 2 * 0 + (M.Y - 3.4) ** 2 + M.Z ** 2) > 3.8) & (np.sqrt((M.Y - 3.4) ** 2 + M.Z ** 2) <= 4.3), '#D8C39A')
    return M, Camera(yaw=-25, pitch=22)


ITEMS = {
    'sunberry': i_sunberry, 'meadow_carrot': i_meadow_carrot, 'golden_wheat': i_golden_wheat, 'glowleaf': i_glowleaf,
    'moonshroom': i_moonshroom,
    'seed_sunberry': lambda: seed_packet('sunberry'), 'seed_meadow_carrot': lambda: seed_packet('meadow_carrot'),
    'seed_golden_wheat': lambda: seed_packet('golden_wheat'), 'seed_glowleaf': lambda: seed_packet('glowleaf'),
    'seed_moonshroom': lambda: seed_packet('moonshroom'),
    'sunberry_tart': i_sunberry_tart, 'carrot_stew': i_carrot_stew, 'golden_bun': i_golden_bun, 'moonshroom_pie': i_moonshroom_pie,
    'glowleaf_tonic': i_glowleaf_tonic, 'meadow_tea': i_meadow_tea, 'sprout_tonic': i_sprout_tonic,
    'moonlight_draught': i_moonlight_draught, 'q_sturdy_timber': i_sturdy_timber,
}


# ------------------------------------------------------------------ UI icons
def ic_skill_farming():
    M = M_((-8, -1, -8), (8, 14, 8), res=2)
    put(M, ell(M, (0, 0.8, 0), (5.6, 1.6, 4.0)) & (M.Y >= 0), '#6B4A34')
    sprout(M, -1.0, 0.4, s=2.0, col=LEAF_HI)
    # a little trowel leaning on the soil
    blade = (np.abs(M.Z - 1.2) < 0.4) & (np.abs(M.X - 3.4 - (M.Y - 2.0) * 0.35) <= 1.4 - np.maximum(0, 2.0 - M.Y) * 0.5) & (M.Y >= 0.8) & (M.Y < 4.0)
    put(M, blade, '#BFC7CC')
    handle = (np.abs(M.Z - 1.2) < 0.5) & (np.abs(M.X - 3.4 - (M.Y - 2.0) * 0.35) <= 0.5) & (M.Y >= 4.0) & (M.Y < 8.0)
    put(M, handle, WOOD)
    return M, Camera(yaw=-20, pitch=18)


def ic_skill_cooking():
    M = M_((-8, -1, -8), (8, 14, 8), res=2)
    pot = ycyl(M, (0, 0), 5.0, 0.6, 6.0) & ~ycyl(M, (0, 0), 4.3, 1.6, 6.0)
    put(M, pot, COPPER)
    put(M, pot & (M.X < -2.6), COPPER_HI)
    put(M, ycyl(M, (0, 0), 5.4, 5.6, 6.2) & ~ycyl(M, (0, 0), 4.6, 5.6, 6.2), '#B8773F')
    for x in (-6.2, 6.2):
        put(M, box(M, (x - 0.8, 4.0, -0.5), (x + 0.8, 4.8, 0.5)), IRON)
    put(M, ycyl(M, (0, 0), 4.3, 4.6, 5.2), '#E8913C')
    for k in range(3):
        put(M, ell(M, (-1.6 + 1.6 * k, 7.6 + (k % 2) * 1.4, 0.0), (1.0, 1.2, 1.0)) & (M.m == 0), '#F7F5F0')
    return M, Camera(yaw=-20, pitch=22)


def ic_skill_alchemy():
    M = M_((-8, -1, -8), (8, 15, 8), res=2)
    bottle(M, 'round', '#AA8BCF', '#D8C7F5', glow=0.6)
    for (x, y, z) in ((1.0, 3.0, 2.8), (-0.8, 2.2, 3.0), (0.6, 4.6, 3.3)):
        put(M, ell(M, (x, y, z), (0.45, 0.45, 0.45)), '#F7F1FF', glow=1.0)
    return M, Camera(yaw=-20, pitch=16)


def ic_home_map():
    M = M_((-8, -1, -8), (8, 12, 8), res=2)
    sheet = (np.abs(M.Y - 0.5 - 0.35 * np.sin(M.X * 0.9)) < 0.4) & (np.abs(M.X) <= 6.8) & (np.abs(M.Z) <= 5.4)
    put(M, sheet, PAPER)
    put(M, sheet & (np.abs(M.Z - 0.4 * np.sin(M.X * 0.6)) < 0.6), '#7FC4E8')
    put(M, sheet & ((M.X - 2.6) ** 2 + (M.Z + 2.4) ** 2 < 2.0), '#86C56A')
    put(M, sheet & (((M.X + 3.6) ** 2 + (M.Z - 2.6) ** 2) < 1.4), '#E8C766')
    # a little red-roofed house standing on the map
    put(M, box(M, (-1.6, 0.8, -2.0), (1.6, 3.6, 0.6)), '#F3E5C9')
    roof = (M.Y >= 3.6) & (M.Y < 3.6 + 2.0 - np.abs(M.Z + 0.7) * 1.2) & (np.abs(M.X) <= 2.0) & (np.abs(M.Z + 0.7) <= 1.9)
    put(M, roof, '#B76B4D')
    put(M, box(M, (-0.5, 0.8, 0.5), (0.5, 2.6, 0.8)), '#7A4E2E')
    return M, Camera(yaw=-20, pitch=30)


ICONS = {'skill_farming': ic_skill_farming, 'skill_cooking': ic_skill_cooking, 'skill_alchemy': ic_skill_alchemy,
         'home_map': ic_home_map}


# ------------------------------------------------------------------ crop sprites for the beds
BED_W, BED_D = 13.0, 9.0
CROP_CAM = Camera(yaw=0.0, pitch=40.0)          # the Garden plate's camera looks down at about 40 degrees
CROP_CANVAS = (640, 520)
ROWS_X = (-4.8, -1.6, 1.6, 4.8)
ROWS_Z = (-2.7, 0.0, 2.7)


TALL = {'sunberry', 'golden_wheat', 'moonshroom'}


def crop_model(crop, stage):
    M = M_((-7, -1, -5), (7, 12, 5), res=3)
    rng = np.random.default_rng(sum(map(ord, crop + stage)))
    # tall crops grow in two staggered rows so the soil shows between them; low ones in three
    rows = (-2.1, 2.1) if (crop in TALL and stage != 'sprout') else ROWS_Z
    for zi, z in enumerate(rows):
        for xi, x in enumerate(ROWS_X):
            jx, jz = rng.uniform(-0.2, 0.2), rng.uniform(-0.15, 0.15)
            x_, z_ = x + jx + (0.8 if zi % 2 else -0.4), z + jz
            put(M, ell(M, (x_, 0.0, z_), (0.9, 0.35, 0.7)) & (M.Y >= 0), '#5B4334')      # a little mound
            if stage == 'sprout':
                if crop == 'moonshroom':
                    mushroom(M, (x_, 0.2, z_), s=0.35, glow=0.2)
                else:
                    sprout(M, x_, z_, s=0.75, col=MINT_HI if crop == 'glowleaf' else LEAF_HI, y=0.2)
                continue
            ripe = stage == 'ripe'
            if crop == 'sunberry':
                bush = ell(M, (x_, 1.0, z_), (1.35, 0.95, 1.1), p=2.2) & (M.Y >= 0.2)
                put(M, bush, LEAF_LO if not ripe else LEAF)
                put(M, bush & (M.Y > 1.6) & (M.X < x_), LEAF_HI)
                if ripe:
                    for (dx, dy, dz) in ((0.6, 1.3, 0.8), (-0.6, 0.9, 0.9), (0.1, 1.7, 0.6), (0.9, 0.7, 0.3), (-0.9, 1.4, 0.3)):
                        berry(M, (x_ + dx, dy, z_ + dz), 0.42)
                else:
                    for (dx, dy, dz) in ((0.5, 1.4, 0.8), (-0.5, 1.0, 0.8)):
                        put(M, ell(M, (x_ + dx, dy, z_ + dz), (0.28, 0.28, 0.28)), '#B9D98B')
            elif crop == 'meadow_carrot':
                n = 4 if ripe else 3
                for i in range(n):
                    a = i * 2 * np.pi / n + 0.4
                    lf = spike(M, (x_, 0.2, z_), (np.cos(a) * 0.5, 1, np.sin(a) * 0.5), 2.2 if ripe else 1.6, 0.7, 0.3, twist=0.5)
                    put(M, lf & (M.m == 0), LEAF if i % 2 else LEAF_HI)
                if ripe:
                    sh = ell(M, (x_, 0.3, z_ + 0.1), (0.55, 0.45, 0.55)) & (M.Y >= 0.1)
                    put(M, sh, CARROT)
            elif crop == 'golden_wheat':
                for k in range(3):
                    wx_ = x_ + (k - 1) * 0.45
                    wheat_stalk(M, wx_, z_ + 0.25 * (k % 2), 2.0 if ripe else 1.4, head=True, lean=(0.2 * (k - 1), 0.0), ripe=ripe)
            elif crop == 'glowleaf':
                glowleaf(M, (x_, 0.2, z_), s=0.42 if not ripe else 0.6, glow=0.15 if not ripe else 0.65, n=5)
            elif crop == 'moonshroom':
                mushroom(M, (x_, 0.1, z_), s=0.45 if not ripe else 0.62, glow=0.15 if not ripe else 0.7)
    return M


def crops(out):
    d = os.path.join(out, 'home')
    os.makedirs(d, exist_ok=True)
    W, Hh = CROP_CANVAS
    # one shared fit: the bed's footprint plus room for the tallest plants
    pts = np.array([[x, y, z] for x in (-BED_W / 2, BED_W / 2) for y in (0.0, 4.5) for z in (-BED_D / 2, BED_D / 2)], float)
    fit = fit_camera(CROP_CAM, pts, W, Hh, margin=0.06)
    ground = project_px(CROP_CAM, fit, [[0, 0, 0]])[0]
    left, right = project_px(CROP_CAM, fit, [[-BED_W / 2, 0, 0], [BED_W / 2, 0, 0]])
    meta = {'w': W, 'h': Hh, 'ground': [round(float(ground[0]), 1), round(float(ground[1]), 1)],
            'bedW': round(float(right[0] - left[0]), 1), 'stages': ['sprout', 'growing', 'ripe'], 'crops': []}
    for crop in ('sunberry', 'meadow_carrot', 'golden_wheat', 'glowleaf', 'moonshroom'):
        for stage in meta['stages']:
            M = crop_model(crop, stage)
            o = render(M, {}, CROP_CAM, W, Hh, fit=fit, light=LIGHT, ss=3, outline_px=2.6, outline_col='#3B2923',
                       inner_thresh=2.0, inner_alpha=0.45, inner_px=0.7)
            save_rgba(o.rgba, os.path.join(d, f'crop_{crop}_{stage}.png'))
            print('crop', crop, stage, flush=True)
        meta['crops'].append(crop)
    json.dump(meta, open(os.path.join(d, 'crops.json'), 'w'), indent=1)


def items(out):
    d = os.path.join(out, 'items')
    os.makedirs(d, exist_ok=True)
    for k, b in ITEMS.items():
        M, cam = b()
        save_rgba(render_model(M, cam, 256), os.path.join(d, f'item_{k}_icon.png'))
        print('item', k, flush=True)
    d = os.path.join(out, 'ui_icons')
    os.makedirs(d, exist_ok=True)
    for k, b in ICONS.items():
        M, cam = b()
        save_rgba(render_model(M, cam, 192, outline=2.6), os.path.join(d, f'icon_{k}.png'))
        print('icon', k, flush=True)


if __name__ == '__main__':
    out = sys.argv[1]
    parts = sys.argv[2:] or ['items', 'crops']
    if 'items' in parts:
        items(out)
    if 'crops' in parts:
        crops(out)

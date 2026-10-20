"""The Lumen Wilds' maps. F1, the Sunlit Thicket: a trail from the south entrance, through a flowered
meadow past Sher's camp, round a pond, over a plank bridge across a stream, through denser wood with a
hidden nook, to the old stone gate to Fernwood Trail (F2, locked for now) at the north end.

    python3 wilds_maps.py OUT_DIR [--quick] [--only=ground,props,data]     (a Python with bpy for ground/props)

The ground is one voxel slab (grass, the path, water channels, flowers, tufts, pebbles, the bridge, the
camp's fire ring), lit in Blender (Cycles) by a warm sun from the upper left, with every prop present but
hidden from the camera, so their shadows fall on it. Each prop kind is its own sprite, lit the same way,
placed and depth-sorted by the game against the walkers. Same map camera as the walk sheets (walk.py):
orthographic, MAP_PITCH above the horizon, looking north; world (x, 0, z) lands at ground pixel
origin + (x, z * sin(pitch)) * GROUND_SCALE.

Writes:
    <map>_ground_<i>.webp           the ground in tiles (rows of TILE px)
    <map>_prop_<kind>.webp          the props
    <map>_mini.webp                 the minimap (top-down)
    wilds_map_<map>.json            sizes, origin, bounds, the walk grid, props, spots, Sher, fx
"""
from __future__ import annotations

import base64
import json
import math
import os
import sys

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

from voxel import Model
from village_scenes import CPainter, box, ball
from walk import MAP_PITCH

HERE = os.path.dirname(os.path.abspath(__file__))
GROUND_SCALE = 5.0           # ground and props: px per world unit
TILE = 1024
X0, X1, Z0, Z1 = -200, 200, -600, 600      # the slab
BOUNDS = (-186, -498, 186, 592)            # where walkers may stand (up to the gate)
CELL = 4                                    # walk grid cell (world units)

GRASS = ['#5E9E43', '#69AB49', '#73B54F', '#7EBF57', '#8BC862']
PATH = ['#C9A877', '#BF9C6B', '#D3B587']
SOIL = ['#7A5638', '#6E4C31']
WATER = ['#5FAFCF', '#58A6C6', '#6BB9D6']
WOOD = ['#9A6B43', '#8A5D39', '#A87A4E']
STONE = ['#9C968C', '#8E887E', '#A8A297']
MOSS = ['#6FA34C', '#7DB357', '#5F9442']
LEAF_OAK = ['#4C8E3A', '#5A9C44', '#3F7E33', '#68AC4D']
LEAF_PINE = ['#2F6B3E', '#3A7A47', '#285C36']
LEAF_BIRCH = ['#86BE5A', '#96C966', '#78B04F']
BARK = ['#7B5435', '#6A462B', '#86603D']


def noise2(shape, scale, seed):
    rng = np.random.default_rng(seed)
    return ndimage.gaussian_filter(rng.random(shape), scale, mode='reflect')


def norm(a):
    return (a - a.min()) / max(a.max() - a.min(), 1e-6)


# ------------------------------------------------------------------ the plan (2D, 1 unit cells) ----
MAIN_PATH = [(0, 640), (6, 560), (30, 490), (58, 430), (46, 360), (8, 290), (-22, 215), (-34, 150), (-12, 70),
             (24, 0), (42, -70), (44, -135), (36, -200), (6, -270), (-28, -330), (-30, -410), (-6, -470), (0, -515),
             (0, -640)]
BRANCHES = [
    ([(58, 430), (78, 390), (96, 352)], 16),           # to Sher's camp
    ([(-34, 150), (-58, 150), (-72, 160)], 14),        # down to the pond shore
    ([(-28, -330), (-70, -352), (-112, -372), (-146, -390)], 11),   # the overgrown way to the nook
]
CAMP = (100, 340)
POND = (-118, 112, 62, 44)                             # centre x, z, radius x, z
NOOK = (-152, -392)
GATE = (0, -512)
SIGN = (34, 548)


def stream_z(x):
    return -135 + 10 * np.sin(x / 37.0) + 6 * np.sin(x / 13.0 + 1.0)


def plan():
    """2D layers over the slab, 1 cell per world unit: path, water, bridge, clearings, flowers."""
    W, D = X1 - X0, Z1 - Z0
    xs = np.arange(X0, X1) + 0.5
    zs = np.arange(Z0, Z1) + 0.5
    X, Z = np.meshgrid(xs, zs, indexing='ij')             # (W, D)
    jit = (noise2((W, D), 6, 3) - 0.5) * 9

    def stroke(pts, width):
        m = np.zeros((D, W), np.uint8)
        P = np.array([[x - X0, z - Z0] for x, z in pts], np.float64)
        # a smooth curve through the points (Catmull-Rom)
        out = []
        for i in range(len(P) - 1):
            p0, p1, p2, p3 = P[max(i - 1, 0)], P[i], P[i + 1], P[min(i + 2, len(P) - 1)]
            for t in np.linspace(0, 1, 24, endpoint=False):
                t2, t3 = t * t, t * t * t
                out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
        out.append(P[-1])
        cv2.polylines(m, [np.round(np.array(out)).astype(np.int32)], False, 1, thickness=int(width), lineType=cv2.LINE_8)
        return m.T.astype(bool)

    path = stroke(MAIN_PATH, 22)
    for pts, w in BRANCHES:
        path |= stroke(pts, w)
    # ragged edges
    dist = ndimage.distance_transform_edt(~path)
    path = dist < (1.0 + jit * 0.35).clip(0, 3)
    sz = stream_z(X)
    stream = np.abs(Z - sz) < 13 + jit * 0.4
    pcx, pcz, prx, prz = POND
    pond = ((X - pcx) / prx) ** 2 + ((Z - pcz) / prz) ** 2 < 1 + jit * 0.03
    water_art = stream | pond
    # the bridge: where the main path crosses the stream (the water runs on under its planks)
    bx = 44.0
    bridge = (np.abs(X - bx) < 15) & (np.abs(Z - stream_z(bx)) < 22)
    water = water_art & ~bridge                          # where nobody can walk
    path &= ~water
    clear = np.zeros_like(path)
    for (cx, cz, r) in ((CAMP[0], CAMP[1], 54), (0, 548, 58), (0, -500, 54), (NOOK[0], NOOK[1], 22)):
        clear |= (X - cx) ** 2 + (Z - cz) ** 2 < r * r
    return dict(X=X, Z=Z, path=path, water=water, water_art=water_art, stream=stream, pond=pond, bridge=bridge,
                clear=clear, jit=jit)


# ------------------------------------------------------------------ the ground ----
def ground(pl, rng):
    W, D = pl['X'].shape
    M = Model((X0, -6, Z0), (X1, 6, Z1), [], res=1)
    P = CPainter(M, seed=7)
    j0 = -M.lo[1]                                       # index of y = 0
    water = pl['water_art']
    # soil everywhere below; the channels dug 4 deep
    M.m[:, :j0 - 1, :] = M.mid(SOIL[0])
    M.m[:, :j0 - 4, :] = M.mid(SOIL[1])
    top = np.ones((W, D), bool)
    n1 = norm(noise2((W, D), 9, 1))
    n2 = norm(noise2((W, D), 2.2, 2))
    g = 0.65 * n1 + 0.35 * n2
    band = np.clip((g * len(GRASS)).astype(int), 0, len(GRASS) - 1)
    ids = np.array([M.mid(c) for c in GRASS], np.uint8)
    M.m[:, j0 - 1, :] = ids[band]
    pn = norm(noise2((W, D), 1.4, 4))
    pid = np.array([M.mid(c) for c in PATH], np.uint8)
    pk = np.clip((pn * 3).astype(int), 0, 2)
    M.m[:, j0 - 1, :] = np.where(pl['path'], pid[pk], M.m[:, j0 - 1, :])
    edge = ndimage.binary_dilation(pl['path'], iterations=2) & ~pl['path'] & (n2 > 0.4)
    M.m[:, j0 - 1, :] = np.where(edge, M.mid('#A8B866'), M.m[:, j0 - 1, :])
    # water channels: dig, line the banks with stones, fill to 2 below the grass
    for j in range(j0 - 4, j0):
        M.m[:, j, :] = np.where(water, 0, M.m[:, j, :])
    wid = np.array([M.mid(c) for c in WATER], np.uint8)
    wk = np.clip((norm(noise2((W, D), 3, 5)) * 3).astype(int), 0, 2)
    for j in (j0 - 4, j0 - 3):
        M.m[:, j, :] = np.where(water, wid[wk], M.m[:, j, :])
    bank = ndimage.binary_dilation(water, iterations=2) & ~water & ~pl['bridge']
    sk = (rng.random((W, D)) < 0.35) & bank
    sid = np.array([M.mid(c) for c in STONE], np.uint8)
    M.m[:, j0 - 1, :] = np.where(sk, sid[rng.integers(0, 3, (W, D))], M.m[:, j0 - 1, :])
    # the bridge: planks across, a rail post at each corner and midway
    br = pl['bridge']
    xs = np.arange(X0, X1) + 0.5
    plank = br & ((np.floor(pl['Z'] / 3) % 2) == 0)
    M.m[:, j0 - 1, :] = np.where(br, M.mid(WOOD[0]), M.m[:, j0 - 1, :])
    M.m[:, j0 - 1, :] = np.where(plank, M.mid(WOOD[1]), M.m[:, j0 - 1, :])
    M.m[:, j0 - 2, :] = np.where(br & water & (np.abs(pl['X'] - 44) > 12), M.mid(WOOD[2]), M.m[:, j0 - 2, :])
    bz = stream_z(44.0)
    for dx in (-14, 13):
        for dz in (-20, -10, 0, 10, 19):
            P.fill(box(M, (44 + dx, 0, bz + dz), (45 + dx, 4, bz + dz + 1)), WOOD)
        P.fill(box(M, (44 + dx, 3, bz - 20), (45 + dx, 4, bz + 20)), WOOD)
    # lily pads on the pond, reeds round it
    pond = pl['pond']
    for _ in range(26):
        cx = POND[0] + rng.uniform(-48, 48)
        cz = POND[1] + rng.uniform(-32, 32)
        r = rng.uniform(2.2, 4.0)
        pad = ((pl['X'] - cx) ** 2 + (pl['Z'] - cz) ** 2 < r * r) & pond
        notch = ((pl['X'] - cx) > 0) & (np.abs(pl['Z'] - cz) < 0.8)
        M.m[:, j0 - 3, :] = np.where(pad & ~notch, M.mid('#5C9C46'), M.m[:, j0 - 3, :])
        if rng.random() < 0.3:
            fl = (np.abs(pl['X'] - cx + 0.5) < 1) & (np.abs(pl['Z'] - cz + 0.5) < 1)
            M.m[:, j0 - 2, :] = np.where(fl, M.mid('#F2A9C4'), M.m[:, j0 - 2, :])
    reed_zone = ndimage.binary_dilation(water, iterations=4) & ~ndimage.binary_dilation(water, iterations=1) & ~ndimage.binary_dilation(br, iterations=4) & ~pl['path']
    pts = np.argwhere(reed_zone & (rng.random((W, D)) < 0.05))
    for (i, k) in pts:
        hgt = rng.integers(3, 6)
        M.m[i, j0:j0 + hgt, k] = M.mid(['#5E8F3E', '#6E9E48'][rng.integers(0, 2)])
        if rng.random() < 0.4:
            M.m[i, j0 + hgt - 1, k] = M.mid('#7A5638')            # a cattail head
    # tufts, flowers and pebbles (not on paths or water)
    grass_ok = ~pl['path'] & ~water & ~br
    for (i, k) in np.argwhere(grass_ok & (rng.random((W, D)) < 0.012)):
        hgt = rng.integers(1, 3)
        M.m[i, j0:j0 + hgt, k] = M.mid(['#4F8E38', '#5E9E43', '#86C25C'][rng.integers(0, 3)])
    flowers = grass_ok & (rng.random((W, D)) < 0.004)
    meadow = (pl['Z'] > 380) & grass_ok & (rng.random((W, D)) < 0.02)
    for (i, k) in np.argwhere(flowers | meadow):
        M.m[i, j0, k] = M.mid('#4F8E38')
        M.m[i, j0 + 1, k] = M.mid(['#F4E07A', '#F6F1E4', '#E99AC0', '#9FC6F2', '#F2A65A'][rng.integers(0, 5)])
    for (i, k) in np.argwhere(pl['path'] & (rng.random((W, D)) < 0.006)):
        M.m[i, j0, k] = M.mid(STONE[rng.integers(0, 3)])
    # mushrooms in the north wood
    for _ in range(40):
        x, z = rng.uniform(-170, 170), rng.uniform(-560, -180)
        i, k = int(x - X0), int(z - Z0)
        if not grass_ok[i, k]:
            continue
        M.m[i, j0, k] = M.mid('#EFE6D2')
        M.m[max(0, i - 1):i + 2, j0 + 1, max(0, k - 1):k + 2] = M.mid(['#D9573E', '#E2A23C', '#B8835A'][rng.integers(0, 3)])
    # the camp: a ring of stones, charred logs, embers (they glow)
    cx, cz = CAMP[0] - 10, CAMP[1] + 6
    ring = ((pl['X'] - cx) ** 2 + (pl['Z'] - cz) ** 2 < 6.5 ** 2) & ((pl['X'] - cx) ** 2 + (pl['Z'] - cz) ** 2 > 4.2 ** 2)
    for (i, k) in np.argwhere(ring):
        M.m[i, j0:j0 + 2, k] = M.mid(STONE[(i + k) % 3])
    pit = (pl['X'] - cx) ** 2 + (pl['Z'] - cz) ** 2 < 4.2 ** 2
    M.m[:, j0 - 1, :] = np.where(pit, M.mid('#3A2A22'), M.m[:, j0 - 1, :])
    emb = pit & (rng.random((W, D)) < 0.5)
    for (i, k) in np.argwhere(emb):
        M.m[i, j0, k] = M.mid(['#FF8A3A', '#FFB347', '#E9592C'][rng.integers(0, 3)])
        M.glow[i, j0, k] = 1.0
    for a in (0.4, 2.0, 3.5):
        for t in np.linspace(-3.4, 3.4, 9):
            i = int(cx + math.cos(a) * t - X0)
            k = int(cz + math.sin(a) * t - Z0)
            M.m[i, j0 + 1, k] = M.mid('#4A3226')
    return M


# ------------------------------------------------------------------ props ----
def _rng(seed):
    return np.random.default_rng(seed)


def blob(M, c, r, p=2.2):
    return (np.abs((M.X - c[0]) / r[0]) ** p + np.abs((M.Y - c[1]) / r[1]) ** p + np.abs((M.Z - c[2]) / r[2]) ** p) <= 1


def oak(seed):
    rng = _rng(seed)
    M = Model((-26, 0, -24), (26, 70, 24), [], res=1)
    P = CPainter(M, seed)
    r = np.hypot(M.X, M.Z)
    trunk = (r < 3.6 + np.maximum(0, 4 - M.Y) * 0.9) & (M.Y < 28)
    P.fill(trunk, BARK, cell=(1, 3, 1))
    for (dx, dz, ry) in ((5, 2, 20), (-5, -3, 23)):
        P.fill(blob(M, (dx * 0.6, ry, dz * 0.6), (5, 1.2, 1.2)) & (M.Y > ry - 1), BARK)
    can = np.zeros(M.m.shape, bool)
    h = 32 + rng.uniform(-3, 3)
    for _ in range(7):
        c = (rng.uniform(-11, 11), h + rng.uniform(-5, 6), rng.uniform(-9, 9))
        rr = rng.uniform(8, 12)
        can |= blob(M, c, (rr, rr * 0.75, rr * 0.9))
    can |= blob(M, (0, h, 0), (18, 11, 16))
    n = norm(noise2(M.m.shape, 1.6, seed))
    P.fill(can, LEAF_OAK, cell=(2, 2, 2))
    M.set(can & (n > 0.72) & (M.Y > h + 2), '#78BC5A')
    return M, 6.0


def pine(seed):
    rng = _rng(seed)
    M = Model((-20, 0, -20), (20, 82, 20), [], res=1)
    P = CPainter(M, seed)
    r = np.hypot(M.X, M.Z)
    P.fill((r < 2.8 + np.maximum(0, 3 - M.Y)) & (M.Y < 22), BARK, cell=(1, 3, 1))
    tiers = 4
    base = 10 + rng.uniform(-1.5, 1.5)
    for t in range(tiers):
        y0 = base + t * 9.5
        rad = 15 - t * 3.0
        cone = (M.Y >= y0) & (M.Y < y0 + 13) & (r < rad * (1 - (M.Y - y0) / 13.0) + 1.5 * np.sin(np.arctan2(M.Z, M.X) * 6))
        P.fill(cone, LEAF_PINE, cell=(2, 2, 2))
    P.fill((r < 1.5) & (M.Y >= base + tiers * 9.5) & (M.Y < base + tiers * 9.5 + 4), LEAF_PINE)
    return M, 5.0


def birch(seed):
    rng = _rng(seed)
    M = Model((-18, 0, -18), (18, 66, 18), [], res=1)
    P = CPainter(M, seed)
    r = np.hypot(M.X, M.Z - 0.0)
    trunk = (r < 2.4) & (M.Y < 32)
    P.fill(trunk, ['#F1ECE0', '#E6DFCF'], cell=(1, 1, 1))
    M.set(trunk & (np.floor(M.Y / 2.5) % 3 == 0) & (np.floor(np.arctan2(M.Z, M.X) * 2) % 2 == 0), '#3C3530')
    can = np.zeros(M.m.shape, bool)
    for _ in range(6):
        c = (rng.uniform(-7, 7), 34 + rng.uniform(-5, 8), rng.uniform(-6, 6))
        rr = rng.uniform(7, 9.5)
        can |= blob(M, c, (rr, rr * 1.1, rr))
    P.fill(can, LEAF_BIRCH, cell=(2, 2, 2))
    return M, 4.0


def bush(seed):
    M = Model((-12, 0, -11), (12, 16, 11), [], res=1)
    P = CPainter(M, seed)
    b = (blob(M, (0, 6.5, 0), (10, 7, 9)) | blob(M, (-5, 4.5, 3), (6, 4.5, 6)) | blob(M, (5.5, 5, -2), (6, 5, 6))) & (M.Y >= 0)
    P.fill(b, ['#4E8F3A', '#5FA046', '#447F33'], cell=(2, 2, 2))
    rng = _rng(seed)
    sh = b & ~ndimage.binary_erosion(b)
    pts = np.argwhere(sh & (M.Y > 4))
    for i in rng.choice(len(pts), min(26, len(pts)), replace=False):
        x, y, z = pts[i]
        M.m[x, y, z] = M.mid('#D9453B')
    return M, 9.0


def rock(seed, big=False):
    s = 1.5 if big else 1.0
    M = Model((-int(15 * s), 0, -int(13 * s)), (int(15 * s), int(17 * s), int(13 * s)), [], res=1)
    P = CPainter(M, seed)
    b = (blob(M, (0, 3.5 * s, 0), (11.5 * s, 9.0 * s, 9.5 * s), 2.4) | blob(M, (6 * s, 2.5 * s, 3 * s), (6 * s, 5.5 * s, 6 * s))) & (M.Y >= 0)
    P.fill(b, STONE, cell=(3, 2, 3))
    sh = b & ~ndimage.binary_erosion(b)
    top = sh & (M.Y > 6.5 * s) & (norm(noise2(M.m.shape, 1.2, seed)) > 0.35)
    P.fill(top, MOSS)
    return M, (15.0 if big else 10.5)


def stump(seed):
    M = Model((-10, 0, -10), (10, 10, 10), [], res=1)
    P = CPainter(M, seed)
    r = np.hypot(M.X, M.Z)
    trunk = (r < 6.5) & (M.Y < 7.0)
    P.fill(trunk, BARK)
    top = trunk & (M.Y > 6)
    M.set(top, '#D8B985')
    M.set(top & ((np.floor(r * 1.3) % 2) == 0), '#C29E6C')
    M.set(top & (r > 5.6), '#8C6440')
    return M, 7.0


def log(seed):
    M = Model((-26, 0, -8), (26, 12, 8), [], res=1)
    P = CPainter(M, seed)
    r = np.hypot(M.Y - 5, M.Z)
    lg = (r < 5) & (np.abs(M.X) < 23)
    P.fill(lg, BARK, cell=(3, 1, 1))
    ends = lg & (np.abs(M.X) > 22)
    M.set(ends, '#D2B07E')
    P.fill(lg & (M.Y > 8.5) & (norm(noise2(M.m.shape, 1.5, seed)) > 0.45), MOSS)
    return M, 0.0      # blocks as a row of circles (see LOG_BLOCKS)


def pillar(seed, h=26):
    M = Model((-8, 0, -8), (8, h + 4, 8), [], res=1)
    P = CPainter(M, seed)
    p = (np.maximum(np.abs(M.X), np.abs(M.Z)) < 5.5) & (M.Y < h - (np.abs(M.X) + 2 * M.Z) * 0.5)
    P.fill(p, ['#B9B2A2', '#A9A292', '#C5BFAF'], cell=(2, 3, 2))
    P.fill(box(M, (-6.5, 0, -6.5), (6.5, 3, 6.5)), ['#9E978A', '#8F897C'])
    P.fill(p & (M.Y > 4) & (norm(noise2(M.m.shape, 1.3, seed)) > 0.55), MOSS)
    return M, 6.5


def gate():
    """The old stone arch to Fernwood Trail, grown over, a carved stone between its feet"""
    M = Model((-34, 0, -9), (34, 64, 9), [], res=1)
    P = CPainter(M, 41)
    for s in (-1, 1):
        P.fill(box(M, (s * 22 - 6, 0, -6), (s * 22 + 6, 46, 6)), ['#B9B2A2', '#A9A292', '#C5BFAF'], cell=(3, 3, 3))
        P.fill(box(M, (s * 22 - 7.5, 0, -7.5), (s * 22 + 7.5, 4, 7.5)), ['#9E978A', '#8F897C'])
    th = np.arctan2(M.Y - 40, M.X)
    rr = np.hypot(M.X, M.Y - 40)
    arch = (rr > 17) & (rr < 26) & (M.Y >= 40) & (np.abs(M.Z) < 6)
    P.fill(arch, ['#B9B2A2', '#A9A292', '#C5BFAF'], cell=(3, 3, 3))
    key = (np.abs(M.X) < 3.5) & (M.Y > 56) & (M.Y < 66) & (np.abs(M.Z) < 6.8)
    P.fill(key, ['#C9C2AE'])
    M.set(key & (M.Z > 6) & (np.abs(M.X) < 1.5) & (np.abs(M.Y - 61) < 2.5), '#8FE3D0')
    M.glow[(M.m == M.mid('#8FE3D0'))] = 0.8
    vine = (arch | box(M, (-28, 0, -6), (28, 46, 6))) & (M.m > 0) & (norm(noise2(M.m.shape, 1.6, 9)) > 0.62) & (np.abs(M.Z) > 4.5)
    P.fill(vine, ['#4E8F3A', '#5FA046', '#3F7E33'])
    # bars of light across the opening: the way is sealed
    for y in (12, 22, 32):
        P.fill(box(M, (-16, y, -0.5), (16, y + 1, 0.5)), ['#9FE3CF'], glow=0.9)
    return M, 0.0


def sign():
    M = Model((-10, 0, -3), (10, 26, 3), [], res=1)
    P = CPainter(M, 5)
    P.fill(box(M, (-1.2, 0, -1.2), (1.2, 22, 1.2)), WOOD)
    P.fill(box(M, (-9, 13, -1), (9, 21, 1)), ['#B9875C', '#C69469'])
    P.fill(box(M, (-9, 13, 0.6), (9, 21, 1.2)) & ((M.Y > 20) | (M.Y < 14) | (np.abs(M.X) > 8)), ['#7A4E2E'])
    P.fill(box(M, (-6, 16, 0.6), (6, 17.4, 1.4)), ['#4A3226'])
    P.fill(box(M, (-4, 18, 0.6), (5, 19, 1.4)), ['#4A3226'])
    return M, 3.0


def tent():
    """Sher's tent: an A-frame of canvas, its open triangular entrance toward you (south), a maroon flap
    tied back, a ridge pole"""
    M = Model((-16, 0, -18), (16, 22, 18), [], res=1)
    P = CPainter(M, 13)
    a = (np.abs(M.Z) < 15) & (M.Y < 19 - np.abs(M.X) * 1.3) & (np.abs(M.X) < 14) & (M.Y >= 0)
    hollow = (np.abs(M.Z) < 13.5) & (M.Y < 17.6 - np.abs(M.X) * 1.3) & (np.abs(M.X) < 12.6)
    open_front = (M.Z > 12) & (M.Y < 13 - np.abs(M.X) * 1.3)
    P.fill(a & ~hollow, ['#D8C39A', '#CDB68B', '#E2CEA6'], cell=(2, 2, 2))
    M.m[a & open_front] = 0
    P.fill((M.Z > 13.5) & (M.Z < 15) & (M.Y < 13.5 - np.abs(M.X) * 1.3) & (M.Y >= 0), ['#4A3A2A'])
    flap = a & ~hollow & (M.Z > 13) & (M.X > 2) & (M.X < 7) & (M.Y < 12)
    P.fill(flap, ['#7A2B36', '#8C3440'])
    P.fill(box(M, (-1, 18.5, -17), (1, 20.5, 17)), WOOD)
    P.fill(box(M, (-1, 0, 15.5), (1, 20, 17)) | box(M, (-1, 0, -17), (1, 20, -15.5)), WOOD)
    return M, 14.0


def seat():
    M = Model((-12, 0, -4), (12, 7, 4), [], res=1)
    P = CPainter(M, 17)
    r = np.hypot(M.Y - 3, M.Z)
    P.fill((r < 3.2) & (np.abs(M.X) < 10), BARK, cell=(3, 1, 1))
    M.set((r < 3.2) & (np.abs(M.X) > 9.4), '#D2B07E')
    return M, 0.0


KINDS = {
    'oak_a': lambda: oak(11), 'oak_b': lambda: oak(12), 'pine_a': lambda: pine(21), 'pine_b': lambda: pine(22),
    'birch': lambda: birch(31), 'bush': lambda: bush(41), 'rock': lambda: rock(51), 'boulder': lambda: rock(52, True),
    'stump': lambda: stump(61), 'log': lambda: log(71), 'pillar': lambda: pillar(81), 'pillar_low': lambda: pillar(82, 14),
    'gate': gate, 'sign': sign, 'tent': tent, 'seat': seat,
}
# footprints that are not one circle: (dx, dz, r) relative to the prop's spot
SHAPES = {
    'log': [(-16, 0, 5.5), (-6, 0, 5.5), (5, 0, 5.5), (16, 0, 5.5)],
    'gate': [(-22, 0, 8), (22, 0, 8), (-13, 0, 3), (13, 0, 3), (-5, 0, 3), (5, 0, 3), (0, 0, 3)],
    'seat': [(-7, 0, 3.5), (0, 0, 3.5), (7, 0, 3.5)],
}


def place_props(pl, rng):
    """Trees as walls round the edge and in groves between the areas; rocks, bushes, stumps, logs and
    ruins; the camp, the sign and the gate. Nothing on the path, the water or the clearings."""
    W, D = pl['X'].shape
    keep_out = pl['path'] | pl['water'] | pl['bridge'] | pl['clear']
    free = ndimage.distance_transform_edt(~keep_out)        # distance to anything to keep clear
    # a tree's canopy rises up the screen over whatever is just north of it: keep tall things out of a
    # band south of the path and the clearings (z grows southward, toward the camera)
    shade = keep_out.copy()
    for k in range(4, 58, 3):
        shade[:, k:] |= (pl['path'] | pl['clear'])[:, :-k]
    props = []
    taken = []

    def ok(x, z, r, tall=False):
        i, k = int(x - X0), int(z - Z0)
        if not (0 <= i < W and 0 <= k < D):
            return False
        if free[i, k] < r + 6:
            return False
        if tall and shade[i, k]:
            return False
        return all((x - tx) ** 2 + (z - tz) ** 2 > (r + tr) ** 2 for tx, tz, tr in taken)

    def add(kind, x, z, r, flip=None):
        props.append({'kind': kind, 'x': round(float(x), 1), 'z': round(float(z), 1),
                      'flip': bool(rng.random() < 0.5) if flip is None else flip})
        taken.append((x, z, r))

    trees = ['oak_a', 'oak_b', 'pine_a', 'pine_b', 'birch']
    # the walls: dense along the edges
    for x in np.arange(X0 + 10, X1 - 4, 22):
        for z in (Z0 + 14, Z1 - 10):
            x2 = x + rng.uniform(-6, 6)
            if ok(x2, z, 8, tall=True):
                add(trees[rng.integers(0, 5)], x2, z + rng.uniform(-5, 5), 12)
    for z in np.arange(Z0 + 30, Z1 - 20, 24):
        for x in (X0 + 12, X1 - 12):
            z2 = z + rng.uniform(-8, 8)
            if ok(x, z2, 8, tall=True):
                add(trees[rng.integers(0, 5)], x + rng.uniform(-4, 4), z2, 12)
    # groves with glades between them: denser to the north (pines), lighter in the south (oaks, birches)
    dens = norm(noise2((W, D), 26, 77))
    for _ in range(6000):
        x, z = rng.uniform(X0 + 20, X1 - 20), rng.uniform(Z0 + 30, Z1 - 30)
        north = z < -150
        d = dens[int(x - X0), int(z - Z0)] + (0.18 if north else 0.0) - (0.12 if z > 380 else 0.0)
        if rng.random() > np.clip((d - 0.38) / 0.3, 0.0, 1.0):
            continue
        kind = (['pine_a', 'pine_b', 'pine_a', 'oak_a', 'birch'] if north else ['oak_a', 'oak_b', 'birch', 'birch', 'oak_a'])[rng.integers(0, 5)]
        if ok(x, z, 11, tall=True):
            add(kind, x, z, 11)
    for kind, n, r in (('bush', 26, 9), ('rock', 14, 10), ('boulder', 5, 15), ('stump', 8, 7), ('log', 4, 24)):
        for _ in range(4000):
            if n == 0:
                break
            x, z = rng.uniform(X0 + 24, X1 - 24), rng.uniform(Z0 + 40, Z1 - 30)
            if ok(x, z, r):
                add(kind, x, z, r)
                n -= 1
    # the camp (Sher's): his tent, a log seat by the fire
    add('tent', CAMP[0] + 24, CAMP[1] - 20, 0, flip=False)
    add('seat', CAMP[0] - 28, CAMP[1] + 4, 0, flip=False)
    # the entrance sign; the gate with ruins round it
    add('sign', SIGN[0], SIGN[1], 0, flip=False)
    add('gate', GATE[0], GATE[1], 0, flip=False)
    for (dx, dz, k) in ((-40, 22, 'pillar'), (44, 18, 'pillar_low'), (-52, -8, 'pillar_low'), (56, -12, 'pillar')):
        add(k, GATE[0] + dx, GATE[1] + dz, 0, flip=False)
    return props


# ------------------------------------------------------------------ data ----
def walk_grid(pl):
    """Blocked cells (CELL units): water (the bridge is open), outside the bounds."""
    W, D = pl['X'].shape
    cols, rows = W // CELL, D // CELL
    wat = pl['water'][:cols * CELL, :rows * CELL].reshape(cols, CELL, rows, CELL).mean((1, 3)) > 0.3
    bits = np.packbits(wat.T.astype(np.uint8).ravel())       # row-major: rows (z) of cols (x)
    return {'cell': CELL, 'x0': X0, 'z0': Z0, 'cols': cols, 'rows': rows,
            'blocked': base64.b64encode(bits.tobytes()).decode('ascii')}


def minimap(pl, props, out, name):
    """Top-down, 1 px per 2 units: grass, path, water, the trees as dark dots."""
    W, D = pl['X'].shape
    s = 2
    img = np.zeros((D // s, W // s, 3), np.uint8)
    grass = np.array([126, 176, 92], np.uint8)
    img[:] = grass
    sub = lambda a: a[::s, ::s].T[:D // s, :W // s]
    img[sub(pl['path'])] = (214, 190, 140)
    img[sub(pl['bridge'])] = (160, 112, 70)
    img[sub(pl['water'])] = (98, 172, 206)
    im = Image.fromarray(img)
    from PIL import ImageDraw
    d = ImageDraw.Draw(im)
    for p in props:
        x, z = (p['x'] - X0) / s, (p['z'] - Z0) / s
        if p['kind'].startswith(('oak', 'pine', 'birch')):
            r = 4
            d.ellipse((x - r, z - r, x + r, z + r), fill=(64, 112, 58))
        elif p['kind'] in ('rock', 'boulder', 'pillar', 'pillar_low'):
            d.ellipse((x - 2, z - 2, x + 2, z + 2), fill=(150, 146, 136))
    fn = f'{name}_mini.webp'
    im.save(os.path.join(out, fn), quality=88)
    return {'image': fn, 'w': im.width, 'h': im.height}


def data(out, name, pl, props, ground_meta, prop_meta):
    spots = [
        {'id': 'exit', 'kind': 'exit', 'x': 0, 'z': 600, 'r': 26, 'label': 'Leave', 'title': 'Back to the trail',
         'text': 'Head back down the trail to the village?'},
        {'id': 'sign', 'kind': 'read', 'x': SIGN[0], 'z': SIGN[1], 'r': 22, 'label': 'Read', 'title': 'Sunlit Thicket',
         'text': 'F1 · Sunlit Thicket. Mind the stream, keep to the trail. The old gate north leads to Fernwood.'},
        {'id': 'gate', 'kind': 'gate', 'x': GATE[0], 'z': GATE[1] + 14, 'r': 30, 'label': 'Inspect', 'title': 'Fernwood Trail',
         'text': 'Bars of old light seal the arch. The carving reads: F2 · Fernwood Trail. Come back stronger (Lv. 5).',
         'need': 5},
        {'id': 'nook', 'kind': 'glint', 'x': NOOK[0], 'z': NOOK[1], 'r': 20, 'label': 'Inspect', 'title': 'A glint in the moss',
         'text': 'Trail runes, faintly glowing under the moss. Someone passed this way not long ago.'},
        {'id': 'pond', 'kind': 'read', 'x': -70, 'z': 160, 'r': 18, 'label': 'Look', 'title': 'The pond',
         'text': 'Lily pads and a lazy frog. The water is clear and very cold.'},
    ]
    blocks = []
    for p in props:
        img = prop_meta[p['kind']]
        if p['kind'] in SHAPES:
            for dx, dz, r in SHAPES[p['kind']]:
                blocks.append([round(p['x'] + (-dx if p['flip'] else dx), 1), round(p['z'] + dz, 1), r])
        elif img['radius'] > 0:
            blocks.append([p['x'], p['z'], img['radius']])
    meta = {
        'id': name, 'name': 'Sunlit Thicket', 'floor': 'F1', 'level': 3, 'pitch': MAP_PITCH, 'scale': GROUND_SCALE,
        'ground': ground_meta, 'bounds': list(BOUNDS), 'grid': walk_grid(pl),
        'start': {'x': 2, 'z': 552, 'dir': 'N'},
        'images': prop_meta, 'props': props, 'blocks': blocks, 'spots': spots,
        'fx': [{'kind': 'fire', 'x': CAMP[0] - 10, 'z': CAMP[1] + 6}],
        'sher': {'x': CAMP[0] - 22, 'z': CAMP[1] + 4, 'route': [[CAMP[0] - 22, CAMP[1] + 4], [CAMP[0] + 2, CAMP[1] + 26],
                                                                [CAMP[0] + 14, CAMP[1] - 2]]},
        'objective': 'Explore the Thicket and find the way to Fernwood Trail',
        'minimap': minimap(pl, props, out, name),
    }
    json.dump(meta, open(os.path.join(out, f'wilds_map_{name}.json'), 'w'), indent=1)
    return meta


def main(out, quick=False, only=None):
    os.makedirs(out, exist_ok=True)
    rng = np.random.default_rng(2026)
    pl = plan()
    props = place_props(pl, rng)
    print('props', len(props), flush=True)
    name = 'thicket'
    work = os.path.join(out, 'work')
    os.makedirs(work, exist_ok=True)
    gm_path = os.path.join(work, 'ground_meta.json')
    pm_path = os.path.join(work, 'prop_meta.json')
    if only is None or 'ground' in only or 'ground_blend' in only:
        G = ground(pl, rng)
        import wilds_blender
        if only and 'ground_blend' in only:
            # the scene for a GPU machine; after it renders <out>/work/<name>_ground.png, run --only=tiles
            gm = wilds_blender.render_ground(G, props, KINDS, out, name, save_blend=os.path.join(work, f'{name}_ground.blend'),
                                             samples=96)
        else:
            gm = wilds_blender.render_ground(G, props, KINDS, out, name, quick=quick)
        json.dump(gm, open(gm_path, 'w'))
    if only and 'tiles' in only:
        import wilds_blender
        gm = json.load(open(gm_path))
        gm['tiles'] = wilds_blender.tile_ground(os.path.join(work, f'{name}_ground.png'), out, name)
        json.dump(gm, open(gm_path, 'w'))
    if only is None or 'props' in only:
        import wilds_blender
        pm = wilds_blender.render_props(KINDS, out, name, quick=quick)
        json.dump(pm, open(pm_path, 'w'))
    if only and 'props_blend' in only:
        # the props for a GPU machine (render_props_gpu.py writes props/<kind>.png); then --only=prop_images
        import wilds_blender
        pm = wilds_blender.save_props_blend(KINDS, os.path.join(work, f'{name}_props.blend'))
        open(os.path.join(work, 'render_props_gpu.py'), 'w').write(wilds_blender.RENDER_PROPS_GPU)
        json.dump(pm, open(pm_path, 'w'))
    if only and 'prop_images' in only:
        pm = json.load(open(pm_path))
        for k in pm:
            fn = f'{name}_prop_{k}.webp'
            Image.open(os.path.join(work, 'props', k + '.png')).save(os.path.join(out, fn), quality=90, method=6)
            pm[k]['image'] = fn
        json.dump(pm, open(pm_path, 'w'))
    if only is None or 'data' in only:
        gm = json.load(open(gm_path))
        pm = json.load(open(pm_path))
        data(out, name, pl, props, gm, pm)
        print('data written', flush=True)


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = {a.split('=', 1)[0]: a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--') and '=' in a}
    main(args[0], quick='--quick' in sys.argv, only=opts['--only'].split(',') if '--only' in opts else None)

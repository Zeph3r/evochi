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
X0, X1, Z0, Z1 = -200, 200, -740, 600      # the slab
BOUNDS = (-186, -626, 186, 592)            # where walkers may stand (up to the gate)
CELL = 4                                    # walk grid cell (world units)

GRASS = ['#3F6A2E', '#467334', '#4E7C39', '#57853F', '#618F45']     # a shaded wood: mossy, not lime
LITTER = ['#5B5631', '#625935', '#545A31', '#6A5E38']                # leaf litter under the groves
MOSS_FLOOR = ['#3B6230', '#42693A']
PATH = ['#A58A5E', '#9A7F55', '#B09366']
SOIL = ['#6A4B31', '#5E422B']
WATER = ['#4E95B0', '#4889A6', '#5AA0BA']
WOOD = ['#8E6440', '#7E5636', '#9A7048']
STONE = ['#8E897F', '#827D73', '#9A958A']
MOSS = ['#5E8C40', '#6A974A', '#517D38']
LEAF_OAK = ['#3B6B2D', '#447634', '#36632A', '#4E8039']
LEAF_OAK_LO, LEAF_OAK_HI = '#2D5524', '#62924A'
LEAF_PINE = ['#24513A', '#2C5E41', '#1F4733']
LEAF_PINE_HI = '#3B7050'
LEAF_BIRCH = ['#5A8A3A', '#669642', '#507E34']
LEAF_BIRCH_HI = '#84AC52'
BARK = ['#6B4A31', '#5C3F29', '#775337']


def noise2(shape, scale, seed):
    rng = np.random.default_rng(seed)
    return ndimage.gaussian_filter(rng.random(shape), scale, mode='reflect')


def norm(a):
    return (a - a.min()) / max(a.max() - a.min(), 1e-6)


# ------------------------------------------------------------------ the plan (2D, 1 unit cells) ----
MAIN_PATH = [(0, 640), (6, 560), (30, 490), (58, 430), (46, 360), (8, 290), (-22, 215), (-34, 150), (-12, 70),
             (24, 0), (42, -70), (44, -135), (36, -200), (6, -270), (-28, -330), (-34, -420), (-20, -500), (-6, -570),
             (0, -632), (0, -760)]
BRANCHES = [
    ([(58, 430), (78, 390), (96, 352)], 16),           # to Sher's camp
    ([(-34, 150), (-58, 150), (-72, 160)], 14),        # down to the pond shore
    ([(-9, -297), (-60, -312), (-114, -332), (-162, -352)], 11),    # the overgrown way to the nook
]
# where the fights are: clearings off the trail (the foes wait there), and the guardian's arena before the
# gate. Each zone: id, name, centre x, z, radius.
ZONES = [('fern', 'Fern Clearing', -8, 250, 64), ('ring', 'Mushroom Ring', 4, 26, 60), ('stand', 'Thorn Stand', 28, -218, 60)]
ARENA = (-14, -470, 135)                               # the Briarback's arena: centre x, z, radius
CAMP = (100, 340)
POND = (-118, 112, 62, 44)                             # centre x, z, radius x, z
NOOK = (-168, -352)
GATE = (0, -640)
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
    for (cx, cz, r) in ((CAMP[0], CAMP[1], 54), (0, 548, 58), (GATE[0], GATE[1] + 12, 54), (NOOK[0], NOOK[1], 22), ARENA[:3],
                        *[(z[2], z[3], z[4]) for z in ZONES]):
        clear |= (X - cx) ** 2 + (Z - cz) ** 2 < r * r
    return dict(X=X, Z=Z, path=path, water=water, water_art=water_art, stream=stream, pond=pond, bridge=bridge,
                clear=clear, jit=jit)


# ------------------------------------------------------------------ the ground ----
def canopy_map(pl, props):
    """0..1: how much tree overhead (from the trees' positions, blurred)"""
    W, D = pl['X'].shape
    c = np.zeros((W, D), np.float32)
    for p in props:
        if p['kind'].startswith(('oak', 'pine', 'birch')):
            i, k = int(p['x'] - X0), int(p['z'] - Z0)
            if 0 <= i < W and 0 <= k < D:
                c[i, k] += 1.0 * p.get('s', 1.0)
    c = ndimage.gaussian_filter(c, 16) * 900
    return np.clip(c, 0, 1)


def ground(pl, rng, props=()):
    W, D = pl['X'].shape
    can = canopy_map(pl, props)
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
    # under the trees: the grass gives way to leaf litter and moss, in soft-edged patches
    nl = norm(noise2((W, D), 5, 11))
    under = (can + (nl - 0.5) * 0.5) > 0.42
    lid = np.array([M.mid(c) for c in LITTER], np.uint8)
    mid_ = np.array([M.mid(c) for c in MOSS_FLOOR], np.uint8)
    lk = rng.integers(0, len(LITTER), (W, D))
    mossy = norm(noise2((W, D), 3, 12)) > 0.55
    M.m[:, j0 - 1, :] = np.where(under & ~mossy, lid[lk], np.where(under & mossy, mid_[lk % 2], M.m[:, j0 - 1, :]))
    pn = norm(noise2((W, D), 1.4, 4))
    pid = np.array([M.mid(c) for c in PATH], np.uint8)
    pk = np.clip((pn * 3).astype(int), 0, 2)
    M.m[:, j0 - 1, :] = np.where(pl['path'], pid[pk], M.m[:, j0 - 1, :])
    edge = ndimage.binary_dilation(pl['path'], iterations=2) & ~pl['path'] & (n2 > 0.4)
    M.m[:, j0 - 1, :] = np.where(edge, M.mid('#6F7E40'), M.m[:, j0 - 1, :])
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
    # tufts; fallen leaves under the trees; ferns round the trunks; flowers only where the sun gets in
    grass_ok = ~pl['path'] & ~water & ~br
    for (i, k) in np.argwhere(grass_ok & ~under & (rng.random((W, D)) < 0.014)):
        hgt = rng.integers(1, 3)
        M.m[i, j0:j0 + hgt, k] = M.mid(['#3F6E2C', '#4A7A33', '#5C8A3C'][rng.integers(0, 3)])
    for (i, k) in np.argwhere(grass_ok & under & (rng.random((W, D)) < 0.05)):
        M.m[i, j0, k] = M.mid(['#8A5A2C', '#A0682E', '#7A6A34', '#9C7A3A', '#6E4A2A'][rng.integers(0, 5)])
    fern_cols = ['#2F5E2A', '#3A6C30', '#457A36']
    for p in props:
        if not p['kind'].startswith(('oak', 'pine', 'birch', 'bush')):
            continue
        for _ in range(rng.integers(0, 3)):
            a = rng.uniform(0, 2 * math.pi)
            d = rng.uniform(8, 16) * p.get('s', 1.0)
            fx, fz = p['x'] + math.cos(a) * d, p['z'] + math.sin(a) * d
            fi, fk = int(fx - X0), int(fz - Z0)
            if not (7 <= fi < W - 7 and 7 <= fk < D - 7) or not grass_ok[fi, fk] or pl['clear'][fi, fk]:
                continue
            # a fern: fronds arching out from the middle, low at the tips
            for f in range(rng.integers(5, 8)):
                fa = f * 2 * math.pi / 7 + rng.uniform(-0.3, 0.3)
                ln = rng.uniform(3.5, 5.5)
                c = fern_cols[rng.integers(0, 3)]
                for t in np.linspace(0, 1, 7):
                    i2 = int(round(fi + math.cos(fa) * ln * t))
                    k2 = int(round(fk + math.sin(fa) * ln * t))
                    y = j0 + int(round(3.2 * math.sin(math.pi * (0.15 + 0.7 * t)) * (1 - 0.35 * t)))
                    M.m[i2, y, k2] = M.mid(c)
    sunny = grass_ok & ~under & (pl['clear'] | (pl['Z'] > 380) | (can < 0.12))
    fl = sunny & (rng.random((W, D)) < np.where(pl['Z'] > 380, 0.008, 0.003))
    for (i, k) in np.argwhere(fl):
        M.m[i, j0, k] = M.mid('#3F6E2C')
        M.m[i, j0 + 1, k] = M.mid(['#F0DC7A', '#EDE6D6', '#D998B8', '#9DB8E2'][rng.integers(0, 4)])
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


def tube(M, a, b, r0, r1=None):
    """a tapered capsule from a to b"""
    r1 = r0 if r1 is None else r1
    a, b = np.asarray(a, float), np.asarray(b, float)
    ab = b - a
    L2 = max(float(ab @ ab), 1e-9)
    px, py, pz = M.X - a[0], M.Y - a[1], M.Z - a[2]
    t = np.clip((px * ab[0] + py * ab[1] + pz * ab[2]) / L2, 0, 1)
    dx, dy, dz = px - t * ab[0], py - t * ab[1], pz - t * ab[2]
    r = r0 + (r1 - r0) * t
    return dx * dx + dy * dy + dz * dz <= r * r


def roots(M, P, rng, r0, n=5, reach=7.0):
    """flaring roots at the foot of a trunk"""
    a0 = rng.uniform(0, 2 * math.pi)
    for i in range(n):
        a = a0 + 2 * math.pi * i / n + rng.uniform(-0.3, 0.3)
        ln = reach * rng.uniform(0.7, 1.15)
        P.fill(tube(M, (0, 2.2, 0), (math.cos(a) * (r0 + ln), 0.3, math.sin(a) * (r0 + ln)), r0 * 0.55, 0.7) & (M.Y >= 0), BARK)


def leafy(M, P, can, cols, lo, hi, seed, rough=0.62):
    """a canopy: its outline roughened, darker underneath, catching the light on top"""
    n = norm(noise2(M.m.shape, 1.3, seed))
    # a lumpy outline: tufts grow out where the noise is high (carving holes would open pockets that
    # shade into a pattern), and bites come out only at the very rim
    grow = ndimage.binary_dilation(can, iterations=1) & ~can & (n > rough + 0.08)
    can = can | grow
    rim = can & ~ndimage.binary_erosion(can, iterations=1) & (n < 0.2)
    can = can & ~(rim & ~ndimage.binary_dilation(~can, iterations=1, border_value=1).__invert__())
    P.fill(can, cols, cell=(2, 2, 2))
    ys = M.Y[can]
    if len(ys):
        ymid = np.percentile(ys, 45)
        M.set(can & (M.Y < ymid - 3) & (n < 0.55), lo)
        top = can & ~np.roll(can, -1, axis=1)             # faces open to the sky
        M.set(top & (n > 0.5), hi)
    return can


def oak(seed, big=False):
    rng = _rng(seed)
    k = 1.25 if big else 1.0
    M = Model((-int(32 * k), 0, -int(30 * k)), (int(32 * k), int(76 * k), int(30 * k)), [], res=1)
    P = CPainter(M, seed)
    lean = (rng.uniform(-1.5, 1.5), rng.uniform(-1.0, 1.0))
    top = (lean[0] * k, 24 * k, lean[1] * k)
    P.fill(tube(M, (0, 0, 0), top, 3.6 * k, 2.4 * k), BARK, cell=(1, 3, 1))
    roots(M, P, rng, 3.2 * k, n=5, reach=6.5 * k)
    can = np.zeros(M.m.shape, bool)
    h = (31 + rng.uniform(-2, 2)) * k
    limbs = []
    for i in range(4):
        a = rng.uniform(0, 2 * math.pi)
        rr = rng.uniform(9, 14) * k
        end = (top[0] + math.cos(a) * rr, h + rng.uniform(-4, 3) * k, top[2] + math.sin(a) * rr * 0.85)
        start = (top[0] * 0.8, (17 + i * 2.5) * k, top[2] * 0.8)
        P.fill(tube(M, start, end, 1.6 * k, 0.9 * k), BARK)
        limbs.append(end)
    for c in limbs:
        for _ in range(3):
            rr = rng.uniform(5.5, 8.5) * k
            cc = (c[0] + rng.uniform(-4, 4) * k, c[1] + rng.uniform(-2, 4) * k, c[2] + rng.uniform(-4, 4) * k)
            can |= blob(M, cc, (rr, rr * 0.72, rr * 0.9))
    can |= blob(M, (top[0], h + 3 * k, top[2]), (13 * k, 8 * k, 12 * k))
    leafy(M, P, can, LEAF_OAK, LEAF_OAK_LO, LEAF_OAK_HI, seed)
    return M, 6.0 * k


def pine(seed):
    rng = _rng(seed)
    M = Model((-22, 0, -22), (22, 88, 22), [], res=1)
    P = CPainter(M, seed)
    r = np.hypot(M.X, M.Z)
    th = np.arctan2(M.Z, M.X)
    P.fill((r < 2.6 + np.maximum(0, 3 - M.Y) * 0.6) & (M.Y < 30), BARK, cell=(1, 3, 1))
    roots(M, P, rng, 2.4, n=4, reach=4.5)
    tiers = rng.integers(5, 7)
    base = 9 + rng.uniform(-1.5, 1.5)
    can = np.zeros(M.m.shape, bool)
    n = noise2(M.m.shape, 1.1, seed)
    for t in range(tiers):
        y0 = base + t * 8.0
        rad = 16 - t * (12.0 / tiers)
        k = (M.Y - y0) / 12.0
        ragged = 1.6 * np.sin(th * (5 + t % 3) + t) + 2.0 * (n - 0.5)
        cone = (M.Y >= y0 - 1.5 * (r / max(rad, 1)) ** 2) & (k < 1) & (r < rad * (1 - np.clip(k, 0, 1)) + ragged)
        can |= cone
    can |= (r < 1.6) & (M.Y >= base + tiers * 8.0) & (M.Y < base + tiers * 8.0 + 5)
    leafy(M, P, can, LEAF_PINE, '#1A3D2B', LEAF_PINE_HI, seed, rough=0.66)
    return M, 5.0


def birch(seed):
    rng = _rng(seed)
    M = Model((-20, 0, -20), (20, 70, 20), [], res=1)
    P = CPainter(M, seed)
    lean = (rng.uniform(-3, 3), rng.uniform(-2, 2))
    mid = (lean[0] * 0.4, 14, lean[1] * 0.4)
    top = (lean[0], 36, lean[1])
    trunk = tube(M, (0, 0, 0), mid, 2.3, 2.0) | tube(M, mid, top, 2.0, 1.4)
    P.fill(trunk, ['#EEE8DA', '#E2DBCA'], cell=(1, 1, 1))
    dark = trunk & (norm(noise2(M.m.shape, 0.8, seed)) > 0.66)
    M.set(dark | (trunk & (M.Y < 2.5)), '#3C3530')
    can = np.zeros(M.m.shape, bool)
    for _ in range(9):
        c = (top[0] + rng.uniform(-7, 7), rng.uniform(26, 44), top[2] + rng.uniform(-6, 6))
        rr = rng.uniform(5, 7.5)
        can |= blob(M, c, (rr, rr * 1.15, rr))
    for _ in range(3):
        a = rng.uniform(0, 2 * math.pi)
        P.fill(tube(M, (mid[0], 22 + rng.uniform(0, 8), mid[2]), (top[0] + math.cos(a) * 7, 34, top[2] + math.sin(a) * 6), 0.8, 0.5),
               ['#E2DBCA'])
    leafy(M, P, can, LEAF_BIRCH, '#456E2E', LEAF_BIRCH_HI, seed, rough=0.58)
    return M, 4.0


def bush(seed):
    rng = _rng(seed)
    M = Model((-13, 0, -12), (13, 16, 12), [], res=1)
    P = CPainter(M, seed)
    b = np.zeros(M.m.shape, bool)
    for _ in range(6):
        rr = rng.uniform(4.5, 7.5)
        b |= blob(M, (rng.uniform(-6, 6), rng.uniform(3, 7), rng.uniform(-4, 4)), (rr, rr * 0.85, rr))
    b &= M.Y >= 0
    b = leafy(M, P, b, ['#3E7232', '#4A803A', '#355F2A'], '#2C5024', '#5E9244', seed, rough=0.6)
    sh = b & ~ndimage.binary_erosion(b)
    pts = np.argwhere(sh & (M.Y > 4))
    if seed % 2 and len(pts):
        for i in rng.choice(len(pts), min(10, len(pts)), replace=False):
            M.m[tuple(pts[i])] = M.mid('#C2453B')
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


GATE_EMIT = 21.0                 # the seal's emitters: on the pillars' inner faces, this far either side of the gate's middle
GATE_BEAMS = (14.0, 26.0, 38.0)  # ...at these heights (world units); the game draws the beams between them


# Elder Futhark runes as strokes on a 4 x 7 grid (u right, v up, centred): the gate's carvings.
FUTHARK = {
    'fehu': [(-1.5, -3.5, -1.5, 3.5), (-1.5, 1.4, 1.5, 3.4), (-1.5, -0.6, 1.5, 1.4)],
    'raidho': [(-1.5, -3.5, -1.5, 3.5), (-1.5, 3.5, 1.3, 2.0), (1.3, 2.0, -1.5, 0.4), (-1.5, 0.4, 1.5, -3.5)],
    'algiz': [(0, -3.5, 0, 3.5), (0, 0.6, -2.0, 3.5), (0, 0.6, 2.0, 3.5)],
    'sowilo': [(1.3, 3.5, -1.3, 1.1), (-1.3, 1.1, 1.3, -1.1), (1.3, -1.1, -1.3, -3.5)],
    'othala': [(0, 3.5, 2.0, 1.0), (0, 3.5, -2.0, 1.0), (-2.0, 1.0, 1.7, -3.5), (2.0, 1.0, -1.7, -3.5)],
    'dagaz': [(-2.0, -3.5, -2.0, 3.5), (2.0, -3.5, 2.0, 3.5), (-2.0, 3.5, 2.0, -3.5), (-2.0, -3.5, 2.0, 3.5)],
    'ingwaz': [(0, 3.5, 2.0, 0), (2.0, 0, 0, -3.5), (0, -3.5, -2.0, 0), (-2.0, 0, 0, 3.5)],
}
RUNES_LEFT = ('raidho', 'algiz', 'fehu')        # journey, protection, wealth (top to bottom)
RUNES_RIGHT = ('sowilo', 'othala', 'dagaz')     # sun, ancestral home, dawn


def rune_mask(M, cx, cy, rune, scale=1.25, w=0.85):
    """The voxels within w of a rune's strokes, centred at (cx, cy) on the X-Y plane."""
    u, v = M.X - cx, M.Y - cy
    out = np.zeros(M.X.shape, bool)
    for (x0, y0, x1, y1) in FUTHARK[rune]:
        x0, y0, x1, y1 = x0 * scale, y0 * scale, x1 * scale, y1 * scale
        dx, dy = x1 - x0, y1 - y0
        L2 = max(dx * dx + dy * dy, 1e-6)
        t = np.clip(((u - x0) * dx + (v - y0) * dy) / L2, 0, 1)
        out |= np.hypot(u - (x0 + t * dx), v - (y0 + t * dy)) < w
    return out


def gate():
    """The ruined doorway to Fernwood Trail: two carved pillars on worn steps under a cracked lintel (its
    far corner broken off and lying in the moss), a stone arch in the opening with a keystone rune, runes
    that glow where the Lumen still runs, ivy hanging from the lintel, ferns at the feet. Gem sockets on
    the pillars' inner faces hold the seal: the game draws its beams of light between them (GATE_BEAMS)."""
    M = Model((-50, 0, -15), (50, 84, 15), [], res=1)
    P = CPainter(M, 41)
    ST = ['#A7A08F', '#9A9383', '#B3AC9B', '#8F897A']
    ST_DK = ['#7F796C', '#736E62', '#857F71']
    RUNE = '#8FF0DC'
    rn = norm(noise2(M.m.shape, 1.4, 41))
    # the steps: two broad slabs, worn and cracked
    steps = box(M, (-46, 0, -13), (46, 3, 14)) | box(M, (-40, 3, -11), (40, 5, 11))
    steps &= ~(box(M, (16, 3, 6), (24, 5, 11)) & (rn > 0.5))
    P.fill(steps, ST_DK, cell=(5, 1, 4))
    # the pillars: square, a little tapered, on plinths, under capitals, with carved bands
    cols = np.zeros_like(steps)
    for sgn in (-1, 1):
        cx = sgn * 30.0
        taper = 9.0 - (M.Y - 5) * 0.035
        col = (np.abs(M.X - cx) < taper) & (np.abs(M.Z) < taper - 1) & (M.Y >= 5) & (M.Y < 58)
        cols |= col
        P.fill(col, ST, cell=(3, 4, 3))
        P.fill(box(M, (cx - 11.5, 5, -11), (cx + 11.5, 10, 11)), ST_DK, cell=(4, 2, 4))
        P.fill(box(M, (cx - 11.5, 56, -11), (cx + 11.5, 61, 11)), ST_DK, cell=(4, 2, 4))
        for y in (22.0, 34.0, 46.0):
            M.set(col & (np.abs(M.Y - y) < 0.7) & ((np.abs(M.X - cx) > taper - 1.6) | (np.abs(M.Z) > taper - 2.6)), '#6E695E')
        # Elder Futhark runes carved down the front face, glowing where the Lumen still runs
        front = col & (M.Z > taper - 2.2)
        for (y, rune) in zip((40, 28, 16), RUNES_LEFT if sgn < 0 else RUNES_RIGHT):
            M.set(front & rune_mask(M, cx, y, rune), RUNE, glow=0.85)
        # the seal's emitters: a carved bracket jutting into the opening, a bright gem in its mouth
        for y in GATE_BEAMS:
            iy = 9.0 - (y - 5) * 0.035                      # the pillar's half-width at that height
            inner = cx - sgn * iy
            bracket = (np.abs(M.X - (inner - sgn * 2.2)) < 2.4) & (np.abs(M.Y - y) < 2.6) & (M.Z > -3) & (M.Z < 4)
            P.fill(bracket, ['#6E695E', '#7A7468'])
            gem = (np.abs(M.X - (inner - sgn * 4.0)) < 1.4) & (np.abs(M.Y - y) < 1.5) & (M.Z > -1.5) & (M.Z < 3.5)
            M.set(gem, '#C8FCFF', glow=1.0)
    # the arch in the opening, and its keystone with the gate's rune
    th_r = np.hypot(M.X, M.Y - 34)
    arch = (th_r > 17) & (th_r < 23.5) & (M.Y >= 34) & (np.abs(M.Z) < 6) & (np.abs(M.X) < 23)
    P.fill(arch, ST, cell=(3, 3, 3))
    P.fill(arch & ((np.floor(np.arctan2(M.Y - 34, M.X) * 5) % 2) == 0), ['#9C9585'])
    key = (np.abs(M.X) < 3.6) & (M.Y > 52) & (M.Y < 60) & (np.abs(M.Z) < 7.5)
    P.fill(key, ['#BDB6A3'])
    M.set(key & (M.Z > 6.6) & rune_mask(M, 0.0, 56.0, 'ingwaz', scale=0.75), RUNE, glow=0.95)
    # the lintel across the top, cracked, its right end broken off
    lin = box(M, (-42, 61, -10), (42, 70, 10))
    broken = (M.X > 27) & (M.Y > 61 + (M.X - 27) * 0.45 + 3 * (rn - 0.5))
    lin &= ~broken
    P.fill(lin, ST, cell=(6, 3, 4))
    M.set(lin & (np.abs(M.X + 6 + 2 * np.sin(M.Y)) < 0.6) & (M.Z > 9), '#5F5A50')   # the crack
    # the broken corner, fallen at the right pillar's foot
    fallen = box(M, (36, 0, 3), (48, 7, 14)) & (M.Y < 7 - (M.X - 36) * 0.18)
    P.fill(fallen, ST, cell=(4, 2, 3))
    solid = M.m > 0
    # moss on every top face, and creeping down the faces from above
    top = solid & ~np.roll(solid, -1, axis=1)
    top[:, -1, :] = solid[:, -1, :]
    # (patchy: stone should still read through it)
    P.fill(top & (rn > 0.5) & (M.Y > 6), ['#5E8C40', '#6A974A', '#517D38', '#4C7A35'])
    P.fill(top & (rn > 0.72) & (M.Y <= 6), ['#5E8C40', '#517D38'])
    shell = solid & ~ndimage.binary_erosion(solid)
    drip = shell & (norm(noise2(M.m.shape, 2.2, 47)) > 0.74) & (M.Y > 40)
    P.fill(drip, ['#5E8C40', '#517D38'])
    P.fill(shell & (M.Y < 12) & (norm(noise2(M.m.shape, 1.8, 48)) > 0.6), ['#5E8C40', '#4C7A35'])
    # ivy hanging from the lintel's front
    rng = np.random.default_rng(43)
    for x in (-39.0, -35.5, -24.0, -20.5, -6.0, 19.0, 22.5):
        ln = rng.uniform(7, 15) if abs(x) < 15 else rng.uniform(12, 24)
        for y in np.arange(61, 61 - ln, -1.0):
            wob = 1.2 * math.sin(y * 0.6 + x)
            leaf = (np.abs(M.X - (x + wob)) < 1.0 + 0.6 * ((61 - y) % 3 < 1)) & (np.abs(M.Y - y) < 0.6) & (np.abs(M.Z - 10.6) < 0.8)
            M.set(leaf & (M.m == 0), '#4E8F3A' if (int(y) % 2) else '#62A048')
    # ferns at the pillars' feet
    for (fx, fz) in ((-44, 9), (-17, 10), (17, 11), (44, -9), (-42, -8)):
        for k in range(7):
            a = k / 7 * math.pi * 2
            for t in np.linspace(0, 1, 7):
                x, y, z = fx + math.cos(a) * 6 * t, 4 + 5 * t * (1 - t) * 2, fz + math.sin(a) * 4 * t
                M.set((np.abs(M.X - x) < 0.8) & (np.abs(M.Y - y) < 0.7) & (np.abs(M.Z - z) < 0.8) & (M.m == 0), '#4E8F3A' if t < 0.6 else '#6FAA4E')
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


def bramble(seed):
    """A Hollow bramble: thick thorny canes arching out of the ground, violet buds glowing on them"""
    rng = _rng(seed)
    M = Model((-14, 0, -12), (14, 20, 12), [], res=1)
    P = CPainter(M, seed)
    cane = np.zeros(M.m.shape, bool)
    buds = []
    for k in range(9):
        a = rng.uniform(0, 2 * math.pi)
        r0 = rng.uniform(0, 4)
        x0, z0 = r0 * math.cos(a), r0 * math.sin(a)
        b = a + rng.uniform(-1.2, 1.2)
        span = rng.uniform(7, 12)
        h = rng.uniform(9, 16)
        for t in np.linspace(0, 1, 26):
            x = x0 + math.cos(b) * span * t
            z = z0 * 0.8 + math.sin(b) * span * t * 0.8
            y = h * math.sin(math.pi * t) * (1 - 0.25 * t)
            cane |= blob(M, (x, y, z), (1.6, 1.6, 1.6))
            if 0.25 < t < 0.8 and rng.random() < 0.18:
                d = rng.normal(size=3)
                d /= np.linalg.norm(d)
                cane |= blob(M, (x + d[0] * 1.8, y + d[1] * 1.8, z + d[2] * 1.8), (0.7, 0.7, 0.7))
            if abs(t - 0.5) < 0.02 and rng.random() < 0.6:
                buds.append((x, y + 1.4, z))
    P.fill(cane & (M.Y >= 0), ['#4A3550', '#3E2B46', '#57405F'], cell=(2, 2, 2))
    for (x, y, z) in buds:
        bud = blob(M, (x, y, z), (1.3, 1.3, 1.3))
        M.set(bud, '#C8B1E4')
        M.glow[bud] = 0.9
    return M, 9.5


def shrooms(seed):
    """A few Hollow toadstools: violet caps with glowing spots (they don't block the way)"""
    rng = _rng(seed)
    M = Model((-9, 0, -8), (9, 9, 8), [], res=1)
    P = CPainter(M, seed)
    for (x, z, s) in ((-3.5, 1.5, 1.0), (2.5, -1.5, 1.3), (4.5, 3.0, 0.8)):
        stem = (np.hypot(M.X - x, M.Z - z) < 1.1 * s) & (M.Y < 3.6 * s)
        P.fill(stem, ['#D8C9E6', '#C8B8D9'])
        capm = blob(M, (x, 4.0 * s, z), (2.8 * s, 1.6 * s, 2.8 * s)) & (M.Y >= 3.0 * s)
        P.fill(capm, ['#6B4C95', '#5E4286'])
        sh = capm & ~ndimage.binary_erosion(capm)
        pts = np.argwhere(sh & (M.Y > 3.8 * s))
        for i in rng.choice(len(pts), min(5, len(pts)), replace=False):
            M.m[tuple(pts[i])] = M.mid('#D9C2FF')
            M.glow[tuple(pts[i])] = 0.9
    return M, 0.0


KINDS = {
    'oak_a': lambda: oak(11), 'oak_b': lambda: oak(12), 'oak_c': lambda: oak(13), 'oak_old': lambda: oak(14, big=True),
    'pine_a': lambda: pine(21), 'pine_b': lambda: pine(22), 'pine_c': lambda: pine(23),
    'birch': lambda: birch(31), 'birch_b': lambda: birch(32), 'bush': lambda: bush(41), 'bush_b': lambda: bush(42), 'rock': lambda: rock(51), 'boulder': lambda: rock(52, True),
    'stump': lambda: stump(61), 'log': lambda: log(71), 'pillar': lambda: pillar(81), 'pillar_low': lambda: pillar(82, 14),
    'gate': gate, 'sign': sign, 'tent': tent, 'seat': seat, 'bramble': lambda: bramble(91), 'shrooms': lambda: shrooms(95),
}
# footprints that are not one circle: (dx, dz, r) relative to the prop's spot
SHAPES = {
    'log': [(-16, 0, 5.5), (-6, 0, 5.5), (5, 0, 5.5), (16, 0, 5.5)],
    # the pillars, the sealed opening between them (the seal's beams), and the fallen corner of the lintel
    'gate': [(-30, 0, 11), (30, 0, 11), (-16, 0, 3.5), (-8, 0, 3.5), (0, 0, 3.5), (8, 0, 3.5), (16, 0, 3.5), (42, 8, 6)],
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
        shade[:, k:] |= (pl['path'] | pl['clear'] | pl['water_art'])[:, :-k]
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

    def add(kind, x, z, r, flip=None, sc=1.0):
        props.append({'kind': kind, 'x': round(float(x), 1), 'z': round(float(z), 1),
                      'flip': bool(rng.random() < 0.5) if flip is None else flip, 's': round(float(sc), 2)})
        taken.append((x, z, r))

    # which trees grow where: species come in stands (a field picks them), not salt-and-pepper
    species = norm(noise2((W, D), 30, 91))
    north_f = lambda z: np.clip((-z - 60) / 260, 0, 1)

    def tree_at(x, z):
        f = species[int(x - X0), int(z - Z0)] + 0.45 * north_f(z) - 0.25 * (z > 380)
        if f > 0.78:
            pool = ['pine_a', 'pine_b', 'pine_c', 'pine_a']
        elif f > 0.6:
            pool = ['pine_a', 'oak_b', 'pine_c', 'oak_c']
        elif f > 0.36:
            pool = ['oak_a', 'oak_b', 'oak_c', 'oak_a', 'oak_b', 'birch']
        else:
            pool = ['birch', 'birch_b', 'oak_a', 'oak_c']
        k = pool[rng.integers(0, len(pool))]
        if k.startswith('oak') and rng.random() < 0.08:
            k = 'oak_old'
        return k

    # the walls: thick along the edges, two ragged rows
    for x in np.arange(X0 + 8, X1 - 4, 15):
        for z0 in (Z0 + 12, Z0 + 30, Z1 - 8, Z1 - 24):
            x2, z2 = x + rng.uniform(-8, 8), z0 + rng.uniform(-7, 7)
            sc = rng.uniform(0.85, 1.2)
            if rng.random() < 0.85 and ok(x2, z2, 8 * sc, tall=True):
                add(tree_at(x2, z2), x2, z2, 11 * sc, sc=sc)
    for z in np.arange(Z0 + 30, Z1 - 20, 16):
        for x0 in (X0 + 10, X0 + 28, X1 - 10, X1 - 28):
            x2, z2 = x0 + rng.uniform(-7, 7), z + rng.uniform(-8, 8)
            sc = rng.uniform(0.85, 1.2)
            if rng.random() < 0.85 and ok(x2, z2, 8 * sc, tall=True):
                add(tree_at(x2, z2), x2, z2, 11 * sc, sc=sc)
    # groves with glades between them: thicker to the north
    dens = norm(noise2((W, D), 26, 77))
    for _ in range(7000):
        x, z = rng.uniform(X0 + 20, X1 - 20), rng.uniform(Z0 + 30, Z1 - 30)
        d = dens[int(x - X0), int(z - Z0)] + 0.18 * north_f(z) - (0.12 if z > 380 else 0.0)
        if rng.random() > np.clip((d - 0.38) / 0.3, 0.0, 1.0):
            continue
        sc = rng.uniform(0.8, 1.2)
        if ok(x, z, 10 * sc, tall=True):
            add(tree_at(x, z), x, z, 10.5 * sc, sc=sc)
    # undergrowth at the groves' edges
    near_tree = np.zeros((W, D), bool)
    for pp in props:
        i, k = int(pp['x'] - X0), int(pp['z'] - Z0)
        near_tree[max(0, i - 24):i + 24, max(0, k - 24):k + 24] = True
    for _ in range(9000):
        if sum(1 for pp in props if pp['kind'].startswith('bush')) >= 46:
            break
        x, z = rng.uniform(X0 + 24, X1 - 24), rng.uniform(Z0 + 40, Z1 - 30)
        if not near_tree[int(x - X0), int(z - Z0)]:
            continue
        sc = rng.uniform(0.75, 1.15)
        if ok(x, z, 9 * sc):
            add(['bush', 'bush_b'][rng.integers(0, 2)], x, z, 9 * sc, sc=sc)
    for kind, n, r in (('rock', 14, 10), ('boulder', 5, 15), ('stump', 8, 7), ('log', 4, 24)):
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
    # the arena: ruined pillars and a boulder to bait the guardian's charge into, brambles round the rim
    ax, az, ar = ARENA
    for (dx, dz, k) in ARENA_ROCKS:
        add(k, ax + dx, az + dz, 0, flip=False)
    for k in range(32):
        a = 2 * math.pi * k / 32
        x, z = ax + math.cos(a) * (ar - 4), az + math.sin(a) * (ar - 4) * 0.92
        if z > az + ar * 0.55 and abs(x - arena_entry()[0]) < 40:
            continue                                   # the way in stays open (until the fight)
        if z < GATE[1] + 30 or (z < az - ar * 0.5 and abs(x + 8) < 30):
            continue                                   # not in front of the gate, nor across the way to it
        add('bramble', x, z, 0, flip=bool(k % 2))
    # the Hollow creeping in at the Thorn Stand
    zx, zz, zr = ZONES[2][2], ZONES[2][3], ZONES[2][4]
    for a in (2.3, 3.4, 5.6):
        add('bramble', zx + math.cos(a) * (zr + 4), zz + math.sin(a) * (zr + 4) * 0.9, 0, flip=a > 3)
    # toadstools round the Mushroom Ring
    zx, zz, zr = ZONES[1][2], ZONES[1][3], ZONES[1][4]
    for k in range(9):
        a = 2 * math.pi * k / 9 + 0.3
        add('shrooms', zx + math.cos(a) * (zr - 6), zz + math.sin(a) * (zr - 6) * 0.9, 0, flip=bool(k % 2))
    return props


ARENA_ROCKS = [(-88, -30, 'pillar'), (72, -56, 'pillar_low'), (-60, 62, 'boulder'), (62, 56, 'pillar'), (6, -76, 'pillar_low'),
               (98, 6, 'boulder'), (-100, -78, 'pillar_low'), (34, 104, 'pillar_low')]


def arena_entry():
    """where the trail comes into the arena (its south rim), and the trail's heading there"""
    ax, az, ar = ARENA
    pts = np.array(MAIN_PATH, float)
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        if math.hypot(a[0] - ax, a[1] - az) >= ar > math.hypot(b[0] - ax, b[1] - az):
            for t in np.linspace(0, 1, 200):
                p = a + (b - a) * t
                if math.hypot(p[0] - ax, p[1] - az) < ar:
                    d = (b - a) / np.linalg.norm(b - a)
                    return float(p[0]), float(p[1]), float(d[0]), float(d[1])
    raise ValueError('the trail misses the arena')


def arena_wall():
    """the brambles that close the way in while the guardian fights: across the trail at the rim"""
    x, z, dx, dz = arena_entry()
    px, pz = -dz, dx                                   # across the trail
    return [[round(x + px * k - dx * 4, 1), round(z + pz * k - dz * 4, 1)] for k in (-36, -18, 0, 18, 36)]


# ------------------------------------------------------------------ the masks ----
# For the living-scene shader (flutter/shaders/scene_fx.frag): what moves, and how.
def ground_mask(pl, gm, out, name):
    """Grass shimmers (G 64), water ripples (G 128); paths, banks and the bridge stay still. Cut in the
    ground's tiles, lossless."""
    from wilds_blender import tile_image
    w, h, s = gm['w'], gm['h'], gm['scale']
    ox, oy = gm['origin']
    sp, cp = math.sin(math.radians(MAP_PITCH)), math.cos(math.radians(MAP_PITCH))
    gx, gy = np.meshgrid(np.arange(w) + 0.5, np.arange(h) + 0.5)
    W, D = pl['X'].shape
    x = (gx - ox) / s
    i = np.clip((x - X0).astype(int), 0, W - 1)
    # the grass top (y = 0) and the water surface (y = -2) land at different rows
    kz = np.clip(((gy - oy) / s / sp - X0 * 0 - Z0).astype(int), 0, D - 1)
    kw = np.clip(((gy - oy) / s / sp - 2 * cp / sp - Z0).astype(int), 0, D - 1)
    m = np.zeros((h, w, 3), np.uint8)
    wat = pl['water_art'][i, kw] & ~pl['bridge'][i, kw]
    still = ~pl['path'][i, kz] & ~pl['bridge'][i, kz] & ~pl['water_art'][i, kz]
    m[..., 1] = np.where(wat, 128, np.where(still, 64, 0))
    return tile_image(Image.fromarray(m, 'RGB'), out, f'{name}_groundmask', lossless=True)


def prop_mask(png, kind):
    """Leaves sway, more toward the top (the trunk and roots hold still); cloth ripples; the rest is
    still. A few px past the leaves so the outline moves too."""
    im = np.asarray(Image.open(png).convert('RGBA')).astype(np.float32)
    h, w = im.shape[:2]
    r, g, b, a = im[..., 0], im[..., 1], im[..., 2], im[..., 3]
    m = np.zeros((h, w, 3), np.uint8)
    leafy_kind = kind.startswith(('oak', 'pine', 'birch', 'bush', 'bramble'))
    if leafy_kind:
        leaf = (a > 40) & (g > r * 1.08) & (g > b * 1.05)
        leaf = ndimage.binary_opening(leaf, iterations=1) | (leaf & ndimage.binary_erosion(leaf))
        ys = np.nonzero(a.max(1) > 40)[0]
        top, bot = (ys.min(), ys.max()) if len(ys) else (0, h - 1)
        ramp = np.clip((bot - np.arange(h)) / max(1, bot - top), 0, 1)[:, None] ** 0.8
        amt = {'bush': 0.45, 'bush_b': 0.45, 'bramble': 0.3}.get(kind, 1.0)
        sway = np.where(leaf, ramp * amt, 0).astype(np.float32)
        sway = ndimage.grey_dilation(sway, size=(5, 5))
        sway = ndimage.gaussian_filter(sway, 1.2)
        m[..., 0] = np.clip(sway * 255, 0, 255).astype(np.uint8)
    elif kind == 'tent':
        cloth = (a > 40) & (r > g * 1.1)
        ys = np.arange(h)[:, None]
        m[..., 0] = np.where(cloth, 70, 0).astype(np.uint8)
        m[..., 2] = np.where(cloth, 80, 0).astype(np.uint8)
    return Image.fromarray(m, 'RGB')


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
    grass = np.array([84, 124, 64], np.uint8)
    img[:] = grass
    sub = lambda a: a[::s, ::s].T[:D // s, :W // s]
    img[sub(pl['path'])] = (190, 166, 118)
    img[sub(pl['bridge'])] = (160, 112, 70)
    img[sub(pl['water'])] = (98, 172, 206)
    im = Image.fromarray(img)
    from PIL import ImageDraw
    d = ImageDraw.Draw(im)
    for p in props:
        x, z = (p['x'] - X0) / s, (p['z'] - Z0) / s
        if p['kind'].startswith(('oak', 'pine', 'birch')):
            r = 4
            d.ellipse((x - r, z - r, x + r, z + r), fill=(40, 78, 42))
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
         'text': 'Beams of old Lumen light seal the doorway, humming between gems in the carved pillars. The lintel reads: F2 · Fernwood Trail. Calm the Thicket\'s guardian, and come back stronger (Lv. 5).',
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
            blocks.append([p['x'], p['z'], round(img['radius'] * p.get('s', 1.0), 1)])
    zones = [{'id': i, 'name': n, 'x': x, 'z': z, 'r': r} for i, n, x, z, r in ZONES]
    ax, az, ar = ARENA
    foes = [
        {'id': 'fern_1', 'kind': 'thornling', 'zone': 'fern', 'x': -30, 'z': 230},
        {'id': 'fern_2', 'kind': 'thornling', 'zone': 'fern', 'x': 4, 'z': 242},
        {'id': 'ring_1', 'kind': 'sporecap', 'zone': 'ring', 'x': -16, 'z': 12},
        {'id': 'ring_2', 'kind': 'sporecap', 'zone': 'ring', 'x': 22, 'z': 40},
        {'id': 'stand_1', 'kind': 'thornling', 'zone': 'stand', 'x': 12, 'z': -206},
        {'id': 'stand_2', 'kind': 'thornling', 'zone': 'stand', 'x': 46, 'z': -230},
        {'id': 'stand_3', 'kind': 'sporecap', 'zone': 'stand', 'x': 30, 'z': -252},
    ]
    boss = {'id': 'briarback', 'kind': 'briarback', 'name': 'Briarback', 'title': 'Guardian of the Thicket',
            'x': ax + 4, 'z': az - 48, 'arena': {'x': ax, 'z': az, 'r': ar}, 'wall': arena_wall(),
            'summon': [[ax - 52, az + 8], [ax + ar - 40, az - 10], [ax - 36, az - ar + 48], [ax + 36, az - ar + 48]]}
    meta = {
        'id': name, 'name': 'Sunlit Thicket', 'floor': 'F1', 'level': 3, 'pitch': MAP_PITCH, 'scale': GROUND_SCALE,
        'ground': ground_meta, 'bounds': list(BOUNDS), 'grid': walk_grid(pl),
        'start': {'x': 2, 'z': 552, 'dir': 'N'},
        'images': prop_meta, 'props': props, 'blocks': blocks, 'spots': spots,
        'fx': [{'kind': 'fire', 'x': CAMP[0] - 10, 'z': CAMP[1] + 6}],
        'sher': {'x': CAMP[0] - 22, 'z': CAMP[1] + 4, 'route': [[CAMP[0] - 22, CAMP[1] + 4], [CAMP[0] + 2, CAMP[1] + 26],
                                                                [CAMP[0] + 14, CAMP[1] - 2]]},
        'objective': 'Explore the Thicket and find the way to Fernwood Trail',
        'zones': zones, 'foes': foes, 'boss': boss,
        # the gate's seal: beams of light between gem sockets on the pillars' inner faces (drawn by the game)
        'gate': {'x': GATE[0], 'z': GATE[1], 'emit': GATE_EMIT, 'beams': list(GATE_BEAMS)},
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
        G = ground(pl, rng, props)
        import wilds_blender
        if only and 'ground_blend' in only:
            # the scene for a GPU machine; after it renders <out>/work/<name>_ground.png, run --only=tiles
            gm = wilds_blender.render_ground(G, props, KINDS, out, name, save_blend=os.path.join(work, f'{name}_ground.blend'),
                                             samples=96, pl=pl)
        else:
            gm = wilds_blender.render_ground(G, props, KINDS, out, name, quick=quick, pl=pl)
        json.dump(gm, open(gm_path, 'w'))
    if only and 'tiles' in only:
        import wilds_blender
        gm = json.load(open(gm_path))
        gm['tiles'] = wilds_blender.tile_ground(os.path.join(work, f'{name}_ground.png'), out, name)
        for t, mt in zip(gm['tiles'], ground_mask(pl, gm, out, name)):
            t['mask'] = mt['image']
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
            src = os.path.join(work, 'props', k + '.png')
            Image.open(src).save(os.path.join(out, fn), quality=90, method=6)
            pm[k]['image'] = fn
            mk = prop_mask(src, k)
            if np.asarray(mk).any():
                mfn = f'{name}_propmask_{k}.webp'
                mk.save(os.path.join(out, mfn), lossless=True, quality=100, method=6)
                pm[k]['mask'] = mfn
            else:
                pm[k].pop('mask', None)
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

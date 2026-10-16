"""Wearable accessories, fitted to each Evochi stage, plus stand-alone item models."""
from __future__ import annotations

import math

import numpy as np
from scipy import ndimage

from voxel import Model
from characters import Character, shell_region, tube, spike, local_frame

ACC_MATS_PREFIX = 'acc_'

# Per-stage placement parameters
NECK = {  # y range, z range, thickness (voxels), flower anchor direction (azimuth deg)
    1: dict(y=(3.4, 7.3), z=(-30, 30), th=3, flower=(22, 5.6), lobes_y=3.4),
    2: dict(y=(6.2, 10.0), z=(1.0, 30), th=3, flower=(20, 7.6), lobes_y=6.2),
    3: dict(y=(7.0, 13.2), z=(4.0, 13.0), th=3, flower=(22, 9.5), lobes_y=7.0),
}
HEAD = {  # centre of crest base (x, y, z), ring radius, ring height
    1: dict(c=(0, 22.6, 0.4), r=5.6, h=3.4),
    2: dict(c=(0, 25.6, 7.0), r=6.0, h=3.4),
    3: dict(c=(0, 22.6, 18.2), r=5.0, h=3.2),
}
BACK = {  # anchor point on the back, outward normal, scale
    1: dict(p=(5.0, 16.5, -8.0), n=(0.55, 0.65, -1), s=1.0),
    2: dict(p=(2.5, 15.5, -11.0), n=(0.35, 1, -0.4), s=1.0),
    3: dict(p=(3.0, 18.5, -13.0), n=(0.4, 1, -0.3), s=1.1),
}


def core_mask(M: Model):
    ids = [M.ids[n] for n in ('shell', 'belly') if n in M.ids]
    return np.isin(M.m, ids)


def _set(M, mask, name, only_empty=True):
    if only_empty:
        mask = mask & (M.m == 0)
    M.set(mask, ACC_MATS_PREFIX + name)
    return mask


def _flower(M, center, normal, size=1.0, petal='flower', centre_mat='flower_c'):
    u, v, n = local_frame(normal)
    P = np.stack([M.X - center[0], M.Y - center[1], M.Z - center[2]], -1)
    U, V, N = P @ u, P @ v, P @ n
    r = np.sqrt(U ** 2 + V ** 2)
    th = np.arctan2(V, U)
    petals = r <= size * (1.25 + 0.65 * np.cos(5 * th))
    disc = (np.abs(N) <= 0.6 * size) & petals & (r <= size * 1.9)
    _set(M, disc, petal, only_empty=False)
    c = (r <= size * 0.75) & (N > -0.2) & (N <= 1.0 * size)
    _set(M, c, centre_mat, only_empty=False)


def neck_band(ch: Character, M: Model, colors=('leaf', 'leaf_hi', 'leaf_lo'), stripes=False):
    p = NECK[ch.stage]
    core = core_mask(M)
    band = shell_region(M, core, p['th'])
    band &= (M.Y >= p['y'][0]) & (M.Y < p['y'][1]) & (M.Z >= p['z'][0]) & (M.Z < p['z'][1])
    band &= (M.m == 0)
    if stripes:
        k = (np.floor((M.Y - p['y'][0]) / 1.0)).astype(int) % 2
        _set(M, band & (k == 0), colors[0])
        _set(M, band & (k == 1), colors[1])
    else:
        _set(M, band, colors[0])
        # lighter top edge
        top = band & (M.Y >= p['y'][1] - 0.6)
        M.set(top, ACC_MATS_PREFIX + colors[1])
    return band


def leaf_scarf(ch: Character, M: Model):
    p = NECK[ch.stage]
    band = neck_band(ch, M)
    core = core_mask(M)
    # pointed leaf lobes hanging below the band, every ~30 degrees
    cx, cz = 0.0, (0.0 if ch.stage == 1 else (7.0 if ch.stage == 2 else 8.0))
    ang = np.degrees(np.arctan2(M.X - cx, M.Z - cz))
    lobe_region = shell_region(M, core, 3) & (M.Y < p['y'][0]) & (M.Y > p['y'][0] - 2.6)
    phase = (ang + 360) % 30
    tri = np.abs(phase - 15) / 15.0     # 0 at lobe centre, 1 between lobes
    depth = (p['y'][0] - M.Y) / 2.6     # 0 at band, 1 at tip
    lobe = lobe_region & (tri <= (1 - depth) * 0.95) & (M.Z >= p['z'][0])
    _set(M, lobe, 'leaf_lo')
    # leaf veins: darker vertical lines on the band
    vein = band & (np.abs(phase - 15) < 1.6)
    M.set(vein & (M.m > 0), ACC_MATS_PREFIX + 'leaf_vein')
    # flower on the front-right
    az, fy = p['flower']
    d = np.array([math.sin(math.radians(az)), 0.0, math.cos(math.radians(az))])
    # find the outer surface of the band along that direction
    c = np.array([cx, fy, cz])
    pt = None
    for t in np.arange(0, 30, 0.1):
        q = c + d * t
        idx = np.floor(q * M.res - M.lo).astype(int)
        if np.any(idx < 0) or np.any(idx >= np.array(M.m.shape)):
            break
        if M.m[tuple(idx)] > 0:
            pt = q
    if pt is not None:
        _flower(M, pt + d * 0.6, d + np.array([0, 0.25, 0]), size=1.25 if ch.stage == 1 else 1.4)


def blue_scarf(ch: Character, M: Model):
    p = NECK[ch.stage]
    neck_band(ch, M, colors=('blue', 'blue_hi', 'blue_lo'), stripes=True)
    core = core_mask(M)
    # hanging end at the front-left
    az = -28
    d = np.array([math.sin(math.radians(az)), 0.0, math.cos(math.radians(az))])
    cz = 0.0 if ch.stage == 1 else (7.0 if ch.stage == 2 else 8.0)
    c = np.array([0, p['y'][0] + 0.5, cz])
    pt = None
    for t in np.arange(0, 30, 0.1):
        q = c + d * t
        idx = np.floor(q * M.res - M.lo).astype(int)
        if np.any(idx < 0) or np.any(idx >= np.array(M.m.shape)):
            break
        if M.m[tuple(idx)] > 0:
            pt = q
    if pt is None:
        return
    u, v, n = local_frame(d)
    P = np.stack([M.X - pt[0], M.Y - pt[1], M.Z - pt[2]], -1)
    U, V, N = P @ u, P @ v, P @ n
    tail = (np.abs(U) <= 1.5) & (V <= 0.5) & (V >= -4.2) & (N >= 0.0) & (N <= 1.4)
    _set(M, tail & (V > -3.4), 'blue')
    fringe = tail & (V <= -3.4) & ((np.floor((U + 1.5) / 0.75)).astype(int) % 2 == 0)
    _set(M, fringe, 'white')
    # knot
    knot = (U ** 2 + (V - 0.3) ** 2 <= 1.4 ** 2) & (N >= -0.2) & (N <= 1.8)
    _set(M, knot, 'blue_lo')


def _ring(M, c, r, h, inner=0.9, square=True):
    dx, dz = M.X - c[0], M.Z - c[2]
    if square:
        rad = np.maximum(np.abs(dx), np.abs(dz))
    else:
        rad = np.sqrt(dx ** 2 + dz ** 2)
    return (rad <= r) & (rad >= r - inner) & (M.Y >= c[1]) & (M.Y < c[1] + h)


def golden_crest_crown(ch: Character, M: Model):
    p = HEAD[ch.stage]
    c = np.array(p['c'], float)
    r, h = p['r'] + 0.6, p['h']
    ring = _ring(M, c, r, h, inner=1.2, square=False)
    M.set(ring, ACC_MATS_PREFIX + 'gold')
    M.set(ring & (M.Y < c[1] + 0.8), ACC_MATS_PREFIX + 'gold_lo')
    # spikes around the rim
    for k in range(8):
        a = k / 8 * 2 * math.pi + math.pi / 8
        base = c + np.array([math.sin(a) * (r - 0.5), h - 0.2, math.cos(a) * (r - 0.5)])
        sp = spike(M, base, (math.sin(a) * 0.15, 1, math.cos(a) * 0.15), 3.2, 1.0, 0.25)
        M.set(sp, ACC_MATS_PREFIX + ('gold_hi' if k % 2 == 0 else 'gold'))
    # ruby at the front
    g = np.array([c[0], c[1] + h * 0.5, c[2] + r + 0.1])
    gem = (np.abs(M.X - g[0]) + np.abs(M.Y - g[1]) <= 1.4) & (M.Z >= g[2] - 0.8) & (M.Z <= g[2] + 0.7)
    M.set(gem, ACC_MATS_PREFIX + 'ruby')
    M.set(gem & (M.Y > g[1] + 0.5), ACC_MATS_PREFIX + 'ruby_hi')


def tiny_crown(ch: Character, M: Model):
    p = HEAD[ch.stage]
    c = np.array(p['c'], float)
    # small crown sitting tilted on the right side of the crest
    off = np.array([p['r'] * 0.95, -0.4, 2.0])
    cc = c + off
    r, h = 3.0, 2.6
    ring = _ring(M, cc, r, h, inner=0.8, square=True)
    M.set(ring, ACC_MATS_PREFIX + 'gold')
    for (dx, dz) in ((-r + 0.4, 0), (r - 0.4, 0), (0, r - 0.4), (0, -r + 0.4)):
        sp = spike(M, cc + np.array([dx, h - 0.2, dz]), (0, 1, 0), 2.2, 0.75, 0.25)
        M.set(sp, ACC_MATS_PREFIX + 'gold_hi')
    g = cc + np.array([0, h * 0.5, r])
    gem = (np.abs(M.X - g[0]) + np.abs(M.Y - g[1]) <= 0.95) & (np.abs(M.Z - g[2]) <= 0.6)
    M.set(gem, ACC_MATS_PREFIX + 'ruby')


def explorer_hat(ch: Character, M: Model):
    p = HEAD[ch.stage]
    c = np.array(p['c'], float)
    s = {1: 1.0, 2: 1.05, 3: 0.95}[ch.stage]
    base_y = c[1] + 1.4
    # brim
    brim = ((M.X - c[0]) ** 2 / (9.5 * s) ** 2 + (M.Z - c[2]) ** 2 / (9.0 * s) ** 2 <= 1) & \
        (M.Y >= base_y) & (M.Y < base_y + 1.0)
    # crown (dome)
    crown = ((M.X - c[0]) ** 2 / (5.6 * s) ** 2 + (M.Z - c[2]) ** 2 / (5.4 * s) ** 2
             + (M.Y - base_y) ** 2 / (6.2 * s) ** 2 <= 1) & (M.Y >= base_y)
    crown &= ~((np.abs(M.X - c[0]) < 1.0) & (M.Y > base_y + 5.0 * s))   # pinch
    # clear the crest under the hat so it does not poke through
    crest_ids = [i for i, n in enumerate(M.mats) if n.startswith('crest')]
    under = ((M.Y >= base_y - 0.5) & np.isin(M.m, crest_ids) &
             ((M.X - c[0]) ** 2 + (M.Z - c[2]) ** 2 <= (7.0 * s) ** 2))
    M.m[under] = 0
    M.set(brim, ACC_MATS_PREFIX + 'leather')
    M.set(brim & (M.Y >= base_y + 0.5), ACC_MATS_PREFIX + 'leather_hi')
    M.set(crown & ~brim, ACC_MATS_PREFIX + 'leather')
    band = crown & (M.Y >= base_y + 1.0) & (M.Y < base_y + 2.4)
    M.set(band, ACC_MATS_PREFIX + 'band')
    # goggles on the front of the band
    for sx in (-1.6, 1.6):
        g = np.array([c[0] + sx * s, base_y + 1.8, c[2] + 5.2 * s])
        lens = ((M.X - g[0]) ** 2 + (M.Y - g[1]) ** 2 <= 1.25 ** 2) & (np.abs(M.Z - g[2]) <= 0.8)
        M.set(lens, ACC_MATS_PREFIX + 'goggle')
        inner = ((M.X - g[0]) ** 2 + (M.Y - g[1]) ** 2 <= 0.75 ** 2) & (M.Z > g[2] + 0.1) & (M.Z <= g[2] + 0.9)
        M.set(inner, ACC_MATS_PREFIX + 'goggle_lens')
    # feather on the right side
    f0 = np.array([c[0] + 4.6 * s, base_y + 2.0, c[2] - 1.0])
    fe = spike(M, f0, (0.35, 1.0, -0.45), 6.0 * s, 1.0, 0.3, square=False)
    M.set(fe & (M.m == 0), ACC_MATS_PREFIX + 'feather')


def _pack(ch: Character, M: Model, body_mat, hi, lo, flap_mat, roll=False):
    p = BACK[ch.stage]
    s = p['s']
    a = np.array(p['p'], float)
    n = np.array(p['n'], float)
    n /= np.linalg.norm(n)
    up = (0, 1, 0) if abs(n[1]) < 0.8 else (0, 0, -1)
    u, v, nn = local_frame(n, up)
    P = np.stack([M.X - a[0], M.Y - a[1], M.Z - a[2]], -1)
    U, V, N = P @ u, P @ v, P @ nn
    w, h, d = 4.4 * s, 5.0 * s, 3.8 * s
    box = (np.abs(U) <= w) & (np.abs(V) <= h) & (N >= -1.5) & (N <= d)
    # round the box edges
    box &= ((np.abs(U) / w) ** 6 + (np.abs(V) / h) ** 6 + (np.abs(N - d / 2) / (d / 2 + 1.5)) ** 6) <= 1.25
    box &= ~core_mask(M)
    _set(M, box, body_mat)
    flap = box & (V > h * 0.25) & (N > d - 1.0)
    M.set(flap, ACC_MATS_PREFIX + flap_mat)
    flap2 = box & (V > h * 0.55)
    M.set(flap2 & (M.m > 0), ACC_MATS_PREFIX + flap_mat)
    # buckles
    for bu in (-w * 0.45, w * 0.45):
        b = (np.abs(U - bu) <= 0.75) & (np.abs(V - h * 0.18) <= 0.7) & (N > d - 0.6) & (N <= d + 0.6)
        M.set(b, ACC_MATS_PREFIX + 'buckle')
    # front pocket
    pk = (np.abs(U) <= w * 0.55) & (V > -h * 0.85) & (V < -h * 0.1) & (N > d - 0.2) & (N <= d + 0.9)
    _set(M, pk, lo)
    if roll:
        # bed-roll on top
        r = 1.7 * s
        rl = ((V - (h + 1.0)) ** 2 + (N - d * 0.45) ** 2 <= r * r) & (np.abs(U) <= w + 0.8)
        _set(M, rl, 'bedroll')
        M.set(rl & (np.abs(np.abs(U) - w * 0.6) < 0.5), ACC_MATS_PREFIX + 'leather_lo')
    # straps going around to the chest (thin)
    core = core_mask(M)
    strap_region = shell_region(M, core, 1)
    for su in (-w * 0.55, w * 0.55):
        st = strap_region & (np.abs(U - su) <= 0.55) & (V > -h * 1.6) & (V < h * 1.6)
        if ch.stage == 1:
            st &= M.Z < -1.0
        _set(M, st, lo)


def red_backpack(ch, M):
    _pack(ch, M, 'red', 'red_hi', 'red_lo', 'red_hi')


def explorer_pack(ch, M):
    _pack(ch, M, 'leather', 'leather_hi', 'leather_lo', 'leather_hi', roll=True)


def butterfly_clip(ch: Character, M: Model):
    p = HEAD[ch.stage]
    base = np.array(p['c'], float)
    # find the head surface at the front-left of the crest and clip the butterfly there
    probe = base + np.array([-p['r'] * 1.15, -2.2, 0.0])
    pt = None
    for t in np.arange(0, 25, 0.1):
        q = probe + np.array([0, 0, 1.0]) * t
        idx = np.floor(q * M.res - M.lo).astype(int)
        if np.any(idx < 0) or np.any(idx >= np.array(M.m.shape)):
            break
        if M.m[tuple(idx)] > 0:
            pt = q
    if pt is None:
        pt = probe + np.array([0, 0, 6.0])
    c = pt + np.array([0, 0.4, 0.9])
    for side in (-1, 1):
        for (dy, rr) in ((0.9, 1.9), (-1.0, 1.4)):
            wc = c + np.array([side * 1.7, dy, 0])
            ell = ((M.X - wc[0]) / rr) ** 2 + ((M.Y - wc[1]) / (rr * 0.85)) ** 2
            wing = (ell <= 1) & (np.abs(M.Z - c[2]) <= 0.55)
            M.set(wing, ACC_MATS_PREFIX + 'butter')
            M.set(wing & (ell > 0.6), ACC_MATS_PREFIX + 'butter_lo')
            dot = ((M.X - wc[0]) ** 2 + (M.Y - wc[1]) ** 2 <= 0.3) & (np.abs(M.Z - c[2]) <= 0.75)
            M.set(dot, ACC_MATS_PREFIX + 'butter_dot')
    body = (np.abs(M.X - c[0]) <= 0.5) & (np.abs(M.Y - c[1]) <= 2.2) & (np.abs(M.Z - c[2]) <= 0.85)
    M.set(body, ACC_MATS_PREFIX + 'butter_dot')


# Village Tales story reward: a short sky-blue travel cape over the back, cream trail embroidery,
# a collar with two copper clasps. Hugs the body so it never changes the sprite frame.
CAPE = {
    1: dict(c=(0, 11.0, -3.0), r=16.5, ymin=3.5, ymax=18.5, zmin=-30.0, zmax=4.5, th=5),
    2: dict(c=(0, 12.0, -2.0), r=11.0, ymin=8.0, ymax=24.0, zmin=-9.5, zmax=5.0, th=7),
    3: dict(c=(0, 13.5, -3.0), r=13.0, ymin=9.5, ymax=27.0, zmin=-14.0, zmax=7.5, th=6),
}


def windtrail_mantle(ch: Character, M: Model):
    p = CAPE[ch.stage]
    core = core_mask(M)
    c = np.array(p['c'], float)
    d = np.sqrt((M.X - c[0]) ** 2 + (M.Y - c[1]) ** 2 + (M.Z - c[2]) ** 2)
    # draped over the shoulders and back, two units thick; spikes and fluff poke through it
    cape = shell_region(M, core, p['th']) & ~core & (d < p['r']) & (M.Y > p['ymin']) & (M.Y < p['ymax']) & \
        (M.Z < p['zmax']) & (M.Z > p['zmin'])
    # scalloped hem around the lower edge
    ang = np.arctan2(M.X, M.Z - c[2])
    cape &= ~((M.Y < p['ymin'] + 1.4 + 0.9 * np.abs(np.sin(ang * 5))) & (d > p['r'] * 0.55))
    M.set(cape, ACC_MATS_PREFIX + 'sky')
    M.set(cape & (M.Y < p['ymin'] + 2.6), ACC_MATS_PREFIX + 'sky_lo')
    M.set(cape & (M.Y > c[1] + p['r'] * 0.35), ACC_MATS_PREFIX + 'sky_hi')
    # cream trail embroidery: one winding path along each flank, plus stitched dots
    for sx in (-1, 1):
        y_mid = (p['ymin'] + min(p['ymax'], c[1] + p['r'])) / 2
        trail = cape & (sx * M.X > 0) & (np.abs(M.Y - y_mid - 1.6 * np.sin(M.Z * 0.55)) < 0.5)
        M.set(trail, ACC_MATS_PREFIX + 'cream')
        dots = cape & (sx * M.X > 0) & (np.abs(M.Y - y_mid + 2.4) < 0.5) & ((np.floor(M.Z / 1.5) % 2) == 0)
        M.set(dots, ACC_MATS_PREFIX + 'cream')
    # collar at the neck with two copper clasps
    n = NECK[ch.stage]
    collar = shell_region(M, core, 2) & (M.Y >= n['y'][1] - 1.6) & (M.Y < n['y'][1] + 0.4) & \
        (M.Z >= n['z'][0]) & (M.Z < n['z'][1]) & (M.m == 0)
    _set(M, collar, 'sky_lo')
    if collar.any():
        zf = M.Z[collar].max()
        for sx in (-1, 1):
            cl = collar & (np.abs(M.Z - zf) < 1.4) & (np.abs(M.X - sx * 2.2) < 1.0)
            M.set(cl, ACC_MATS_PREFIX + 'copper')


WEARABLES = {
    'leaf_scarf': ('neck', leaf_scarf),
    'blue_scarf': ('neck', blue_scarf),
    'tiny_crown': ('head', tiny_crown),
    'golden_crest_crown': ('head', golden_crest_crown),
    'explorer_hat': ('head', explorer_hat),
    'butterfly_clip': ('head', butterfly_clip),
    'red_backpack': ('back', red_backpack),
    'explorer_pack': ('back', explorer_pack),
    'reward_windtrail_mantle': ('back', windtrail_mantle),
}
# the shop wearables that define each stage's sprite frame (story wearables must fit inside it)
FRAME_WEARABLES = ['leaf_scarf', 'blue_scarf', 'tiny_crown', 'golden_crest_crown', 'explorer_hat', 'butterfly_clip',
                   'red_backpack', 'explorer_pack']


def wear(ch: Character, item_id: str) -> Model:
    M = ch.model.copy()
    WEARABLES[item_id][1](ch, M)
    return M

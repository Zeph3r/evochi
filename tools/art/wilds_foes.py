"""The Lumen Wilds' foes: creatures the Hollow has tangled, drawn like the rest of the walkers (voxels, the
flat renderer, the map camera, 8 directions) so they share the floor with your Evochi and Sher.

    python3 wilds_foes.py OUT_DIR [--only=thornling,sporecap,briarback] [--preview] [--jobs=2]

  Thornling   a hedgehog of brambles. It trots, crouches and bristles, tucks into a thorn ball (the ball is
              its roll-charge: the app spins the one sprite), nips, flinches.
  Sporecap    a toadstool that hops on two stubby feet. It swells its cap and puffs spores.
  Briarback   the Thicket's guardian, a hart with antlers of bramble. It walks, gallops head-down (the
              charge), lowers its antlers, sweeps them, rears and stomps, roars, staggers.
  Sentinel    the Forgotten Sentinel at its gate (F5): asleep, waking, fists up and slammed down (both,
              or one and then the other), a beam from its eyes, runes cast wide, a shield held out, and
              restored, bowing.

Every foe also has a calm walk: the same creature with the Hollow lifted (the vines gone, the colours
back), for the moment it is purified and trots off.

Writes, per foe:
    foe_<key>_walk_<variant>.webp   rows S, SE, E, NE, N, NW, W, SW; columns idle + 8 frames
    foe_<key>_<gait>_hollow.webp    other cycles (Briarback's charge)
    foe_<key>_act.webp              rows the 8 directions; columns the poses (named in the json)
    wilds_foes.json                 frame size, ground anchor, scale (px per unit), footprint, top (px
                                    above the ground point), per gait the roll, squash, lift and cycle,
                                    the act poses
"""
from __future__ import annotations

import json
import math
import os
import sys
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from voxel import Model, Fit, render                             # noqa: E402
from walk import DIRS, FRAMES, MAP_PITCH, PAD, cam_for, light_for, frame_box, swing, q   # noqa: E402

OUTLINE = '#3B2923'
INK, EYE_HI = '#282725', '#FFFFFF'
GLOW_V = '#D9C2FF'
VIOLET, VIOLET_HI, VIOLET_LO = '#9975C9', '#C8B1E4', '#6E4FA3'
VINE_H, VINE_H_HI = '#43306B', '#5A4388'
BLUSH = '#F2A58F'
GOLD, WHITE, PINK = '#F4C542', '#FFFFFF', '#F5A3B5'


# ------------------------------------------------------------------ shapes (cropped to their box: fast)
def _sl(M, lo, hi):
    s = []
    for k in range(3):
        a = int(math.floor(lo[k] * M.res - M.lo[k])) - 1
        b = int(math.ceil(hi[k] * M.res - M.lo[k])) + 2
        s.append(slice(max(a, 0), max(0, min(b, M.m.shape[k]))))
    return tuple(s)


def region(M, lo, hi, fn):
    out = np.zeros(M.m.shape, bool)
    sl = _sl(M, lo, hi)
    if any(s.stop <= s.start for s in sl):
        return out
    out[sl] = fn(M.X[sl], M.Y[sl], M.Z[sl])
    return out


def E(M, c, r, p=2.0):
    """an ellipsoid"""
    c, r = np.asarray(c, float), np.asarray(r, float)
    return region(M, c - r, c + r, lambda X, Y, Z: (np.abs((X - c[0]) / r[0]) ** p + np.abs((Y - c[1]) / r[1]) ** p
                                                     + np.abs((Z - c[2]) / r[2]) ** p) <= 1.0)


def cap(M, a, b, r0, r1=None):
    """a capsule from a to b, its radius tapering r0 -> r1"""
    r1 = r0 if r1 is None else r1
    a, b = np.asarray(a, float), np.asarray(b, float)
    rr = max(r0, r1)
    lo, hi = np.minimum(a, b) - rr, np.maximum(a, b) + rr
    ab = b - a
    L2 = max(float(ab @ ab), 1e-9)

    def f(X, Y, Z):
        px, py, pz = X - a[0], Y - a[1], Z - a[2]
        t = np.clip((px * ab[0] + py * ab[1] + pz * ab[2]) / L2, 0, 1)
        dx, dy, dz = px - t * ab[0], py - t * ab[1], pz - t * ab[2]
        r = r0 + (r1 - r0) * t
        return dx * dx + dy * dy + dz * dz <= r * r
    return region(M, lo, hi, f)


def chain(M, pts, r0, r1):
    """capsules along a polyline, the radius tapering along it"""
    out = np.zeros(M.m.shape, bool)
    n = len(pts) - 1
    for i in range(n):
        out |= cap(M, pts[i], pts[i + 1], r0 + (r1 - r0) * i / n, r0 + (r1 - r0) * (i + 1) / n)
    return out


def thorn(M, base, d, length, r0):
    """a little cone"""
    d = np.asarray(d, float)
    d = d / max(np.linalg.norm(d), 1e-9)
    tip = np.asarray(base, float) + d * length
    return cap(M, base, tip, r0, 0.15)


def put(M, mask, col, glow=None, empty=False):
    if empty:
        mask = mask & (M.m == 0)
    M.set(mask, col)
    if glow is not None:
        M.glow[mask] = glow
    return mask


def shell(M, body, depth=1):
    er = ndimage.binary_erosion(body, structure=ndimage.generate_binary_structure(3, 1), iterations=depth, border_value=0)
    return body & ~er


def facing(M, body, c, r, zmin=-99.0, depth=2):
    """the front (+z) skin of `body` inside an ellipse (in x, y) around c"""
    sh = shell(M, body, depth)
    e = region(M, (c[0] - r[0], c[1] - r[1], zmin), (c[0] + r[0], c[1] + r[1], 99),
               lambda X, Y, Z: ((X - c[0]) / r[0]) ** 2 + ((Y - c[1]) / r[1]) ** 2 <= 1.0)
    return sh & e


# ------------------------------------------------------------------ posing parts
def blank(M):
    return Model(tuple(M.lo // M.res), tuple(M.hi // M.res), [], res=M.res)


def rot(rx=0.0, ry=0.0, rz=0.0):
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])          # +rx: the front (+z) dips
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])          # +ry: the front turns toward +x
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])          # +rz: +x rises
    return Rz @ Ry @ Rx


def turn(P, pivot, R, shift=(0, 0, 0)):
    """move the voxels of part P: rotate R about pivot (world units), then shift"""
    if np.allclose(R, np.eye(3)) and not any(shift):
        return P
    c0 = np.asarray(pivot, float) * P.res - P.lo - 0.5          # the pivot in index space
    Rt = R.T
    off = c0 - Rt @ (c0 + np.asarray(shift, float) * P.res)
    m = ndimage.affine_transform(P.m, Rt, offset=off, order=0, mode='constant', cval=0)
    g = ndimage.affine_transform(P.glow, Rt, offset=off, order=0, mode='constant', cval=0)
    Q = P.copy()
    Q.m, Q.glow = m, g
    return Q


def merge(M, P, under=False):
    """copy part P's voxels into M (keeping M's where both are filled when under)"""
    for i, name in enumerate(P.mats):
        if i == 0:
            continue
        sel = P.m == i
        if under:
            sel &= M.m == 0
        if sel.any():
            M.set(sel, name)
            M.glow[sel] = P.glow[sel]


# ------------------------------------------------------------------ Thornling
TH = {
    'hollow': dict(fur='#5C4872', fur_lo='#45355A', belly='#A493B8', spike='#33243F', tip=VIOLET_HI, foot='#3A2D44',
                   eye='slit'),
    'calm': dict(fur='#A87C55', fur_lo='#8A6342', belly='#EBD6B4', spike='#5E8C3E', tip='#B6DC8E', foot='#6A4A33',
                 eye='calm'),
}


def thornling(pose=None, variant='hollow'):
    p = pose or {}
    C = TH[variant]
    hollow = variant == 'hollow'
    M = Model((-14, -4, -15), (14, 22, 16), [], res=2)
    ball = p.get('ball', 0.0)            # 0 rest .. 1 curled into a thorn ball
    low = p.get('low', 0.0)              # crouch: the body drops
    bristle = p.get('bristle', 1.0)
    feet = p.get('feet', {})
    if ball >= 1.0:
        c = (0, 7.0, 0)
        body = E(M, c, (6.8, 6.6, 6.8))
        put(M, body, C['fur'])
        put(M, shell(M, body) & (M.Y < 3.0), C['fur_lo'])
        rng = np.random.default_rng(7)
        for k in range(64):
            v = rng.normal(size=3)
            v /= np.linalg.norm(v)
            if v[1] < -0.75:
                continue
            base = np.asarray(c) + v * 5.6
            put(M, thorn(M, base, v + rng.normal(size=3) * 0.15, 4.2 * bristle, 1.05), C['spike'])
            put(M, thorn(M, base + v * 3.0 * bristle, v, 1.3 * bristle, 0.5), C['tip'], glow=0.6 if hollow else None)
        if hollow:
            for k in range(2):
                for t in np.linspace(0, 1, 36):
                    a = t * 2 * math.pi + k * 1.9
                    y = 7.0 + 5.0 * math.sin(a * 2 + k)
                    rr = math.sqrt(max(0.0, 6.9 ** 2 - (y - 7.0) ** 2)) + 0.5
                    put(M, E(M, (rr * math.cos(a), y, rr * math.sin(a)), (0.75, 0.6, 0.75)), VINE_H if k else VINE_H_HI)
        return M, {'ground': (0, 0, 0), 'top': (0, 15.0, 0)}
    dy = -low
    # the body: a round bun, the snout in front
    bc = (0, 7.4 + dy - ball * 0.8, -1.0)
    br = (6.4 + ball * 0.4, 4.9 + ball * 1.4, 7.0 - ball * 1.0)
    body = E(M, bc, br, p=2.2)
    head_tuck = ball * 0.9 + p.get('tuck', 0.0)
    nip = p.get('nip', 0.0)
    H = blank(M)
    sc = (0, 6.4 + dy, 6.2 + nip * 2.2)
    snout = E(H, sc, (3.5, 3.1, 3.6))
    put(H, snout, C['belly'])
    put(H, E(H, (0, 6.7 + dy, 9.8 + nip * 2.2), (1.05, 0.9, 0.8)), INK)
    face = snout
    ey = 7.7 + dy
    for s in (-1, 1):
        if C['eye'] == 'slit' and not p.get('hurt'):
            put(H, facing(H, face, (s * 1.8, ey), (1.6, 1.0)), '#2B1F33')
            put(H, facing(H, face, (s * 1.8, ey), (1.2, 0.55)), GLOW_V, glow=0.95)
        elif p.get('hurt'):
            put(H, facing(H, face, (s * 1.8, ey), (1.1, 0.3)), INK)
        else:
            put(H, facing(H, face, (s * 1.8, ey), (0.8, 1.0)), INK)
            put(H, facing(H, face, (s * 1.55, ey + 0.4), (0.32, 0.32)), EYE_HI)
            put(H, facing(H, face, (s * 2.7, ey - 1.3), (0.7, 0.45)), BLUSH)
    if nip > 0:
        put(H, facing(H, face, (0, 5.1 + dy), (1.3, 0.9)), '#4A2030')
    elif not hollow:
        put(H, facing(H, face, (0, 5.3 + dy), (0.9, 0.25)), INK)
    # little ears
    for s in (-1, 1):
        put(H, E(H, (s * 3.0, 10.0 + dy, 4.2), (1.1, 1.3, 0.8)), C['fur_lo'], empty=True)
    H = turn(H, (0, 5.8 + dy, 3.6), rot(rx=head_tuck))
    put(M, body, C['fur'])
    put(M, shell(M, body) & (M.Y < 4.0 + dy) & (M.Z > -3), C['belly'])
    # thorns over the back, flatter toward the tail; none across the face
    rng = np.random.default_rng(11)
    n = 0
    while n < 24:
        v = rng.normal(size=3)
        v /= np.linalg.norm(v)
        if v[1] < 0.1 or v[2] > 0.5:
            continue
        n += 1
        base = np.asarray(bc) + v * np.asarray(br) * 0.86
        d = v + np.array([0, 0.1, -0.6]) * (1 - bristle * 0.4)
        ln = (3.6 + rng.uniform(0, 1.4)) * bristle
        put(M, thorn(M, base, d, ln, 1.3), C['spike'])
        d = d / np.linalg.norm(d)
        if n % 3 == 0 or not hollow:
            put(M, thorn(M, base + d * ln * 0.72, d, ln * 0.3, 0.5), C['tip'], glow=0.6 if hollow else None)
    if not hollow:
        # leaves and a flower among the spines
        for (x, y, z) in ((-3.0, 11.4, -1.0), (2.6, 11.0, -3.0)):
            put(M, E(M, (x, y + dy, z), (1.4, 0.5, 1.0)), '#7DB357', empty=True)
        put(M, E(M, (0.6, 12.0 + dy, -0.4), (0.9, 0.6, 0.9)), PINK)
        put(M, E(M, (0.6, 12.5 + dy, -0.4), (0.35, 0.35, 0.35)), GOLD)
    else:
        # Hollow vines across the back, beads of glow
        for k in range(2):
            for t in np.linspace(0, 1, 30):
                a = math.pi * (0.15 + 0.7 * t)
                x = (6.9 + 0.3) * math.cos(a) * (1 if k == 0 else -1)
                y = bc[1] + 5.4 * math.sin(a)
                z = -3.5 + k * 3.5 + 2.0 * math.sin(t * 7)
                put(M, E(M, (x, y, z), (0.7, 0.6, 0.7)), VINE_H if k else VINE_H_HI)
                if int(t * 30) % 8 == 3:
                    put(M, E(M, (x, y + 0.6, z), (0.45, 0.45, 0.45)), GLOW_V, glow=0.9)
    # stubby legs (hidden when tucked)
    if ball < 0.6:
        for side in (-1, 1):
            for front in (True, False):
                fdy, fdz = feet.get((side, front), (0.0, 0.0))
                hz = 3.6 if front else -4.4
                hip = (side * 3.6, 4.4 + dy, hz)
                foot = (side * 3.9, 0.9 + fdy, hz + 0.5 + fdz)
                if ball > 0:
                    foot = (side * 3.6, 2.4 + dy + ball * 1.5, hz)
                put(M, cap(M, hip, foot, 1.5, 1.3), C['fur_lo'], empty=True)
                put(M, E(M, (foot[0], foot[1] - 0.2, foot[2] + 0.6), (1.6, 0.9, 1.9)), C['foot'], empty=True)
    tail = E(M, (0, 6.8 + dy, -7.9), (1.2, 1.2, 1.0))
    put(M, tail, C['fur_lo'], empty=True)
    merge(M, H)
    if p.get('roll'):
        M = turn(M, (0, 0, 0), rot(rx=p['roll']))
    return M, {'ground': (0, 0, 0), 'top': (0, 15.5, 0)}


# ------------------------------------------------------------------ Sporecap
SP = {
    'hollow': dict(stem='#D8C9E6', stem_lo='#B5A3C9', cap='#6B4C95', cap_lo='#523873', cap_hi='#8A68B5', spot=GLOW_V,
                   gill='#3E2B55', foot='#8D7AA6'),
    'calm': dict(stem='#F4EBDD', stem_lo='#DCCDB6', cap='#E05A4E', cap_lo='#B8443B', cap_hi='#F07A6C', spot=WHITE,
                 gill='#F2DCC8', foot='#CDB89B'),
}


def sporecap(pose=None, variant='hollow'):
    p = pose or {}
    C = SP[variant]
    hollow = variant == 'hollow'
    M = Model((-14, -4, -14), (14, 28, 14), [], res=2)
    sw = p.get('swell', 0.0)             # 0..1: the cap fills up with spores
    puff = p.get('puff', 0.0)            # the cap snaps down
    sq = 1.0 - 0.12 * sw + 0.1 * puff    # the body squashes while it swells, stretches as it puffs
    feet = p.get('feet', (0.0, 0.0))
    # a plump stem-body, the face on its front, the cap sitting on top
    stem_top = 9.4 * sq
    stem = E(M, (0, 4.6 * sq + 0.4, 0.3), (5.0 + sw * 0.4, 4.7 * sq, 4.8), p=2.2)
    put(M, stem, C['stem'])
    put(M, shell(M, stem) & (M.Y < 2.4), C['stem_lo'])
    fy = 5.0 * sq + 0.6
    for s in (-1, 1):
        if p.get('hurt'):
            put(M, facing(M, stem, (s * 1.9, fy + 0.4), (1.0, 0.3)), INK)
        elif hollow:
            put(M, facing(M, stem, (s * 1.9, fy + 0.4), (1.5, 1.0)), '#3E2B55')
            put(M, facing(M, stem, (s * 1.9, fy + 0.4), (1.1, 0.55)), GLOW_V, glow=0.95)
        else:
            put(M, facing(M, stem, (s * 1.9, fy + 0.4), (0.8, 1.05)), INK)
            put(M, facing(M, stem, (s * 1.65, fy + 0.8), (0.32, 0.32)), EYE_HI)
            put(M, facing(M, stem, (s * 3.1, fy - 0.9), (0.8, 0.45)), BLUSH)
    if puff > 0 or sw > 0.6:
        put(M, facing(M, stem, (0, fy - 1.6), (1.1, 0.9 if puff > 0 else 0.6)), '#3A2440')
    elif hollow:
        put(M, facing(M, stem, (0, fy - 1.5), (1.0, 0.25)), '#3E2B55')
    else:
        put(M, facing(M, stem, (0, fy - 1.4), (1.0, 0.35)) & ~facing(M, stem, (0, fy - 1.05), (0.85, 0.35)), INK)
    # the cap: a dome, swelling, snapped flatter on a puff
    cy = stem_top + 0.6 - puff * 0.6
    cr = (7.3 + sw * 1.3 - puff * 0.2, 4.2 + sw * 1.2 - puff * 1.1, 7.1 + sw * 1.3)
    dome = E(M, (0, cy, 0), cr, p=2.0) & (M.Y >= cy - 1.2)
    put(M, dome, C['cap'])
    put(M, shell(M, dome) & (M.Y < cy - 0.4), C['cap_lo'])
    put(M, shell(M, dome) & (M.Y > cy + cr[1] * 0.5) & (M.X < 0) & (M.Z > -2), C['cap_hi'])
    gill = E(M, (0, cy - 1.0, 0), (cr[0] - 1.0, 0.7, cr[2] - 1.0)) & (M.m == 0)
    put(M, gill, C['gill'])
    # spots: glowing in the Hollow, white when calm
    rng = np.random.default_rng(5)
    for k in range(11):
        a = rng.uniform(0, 2 * math.pi)
        el = rng.uniform(0.25, 1.15)
        v = np.array([math.cos(a) * math.cos(el), math.sin(el), math.sin(a) * math.cos(el)])
        c = np.array([0, cy, 0]) + v * np.asarray(cr) * 0.96
        put(M, E(M, c, (1.05, 0.7, 1.05)) & shell(M, dome, 2), C['spot'], glow=(0.6 + 0.4 * sw) if hollow else None)
    if hollow:
        # a Hollow vine round the stem and up over the cap's rim
        for t in np.linspace(0, 1, 40):
            a = t * 2 * math.pi * 1.3
            y = 1.0 + t * (stem_top - 1.0)
            if math.sin(a) > 0.3 and 2.0 < y < 8.5:
                continue
            rr = 5.0 * math.sqrt(max(0.0, 1 - ((y - 4.6 * sq - 0.4) / (4.7 * sq)) ** 2)) + 0.4
            put(M, E(M, (rr * math.cos(a), y, rr * math.sin(a)), (0.6, 0.55, 0.6)), VINE_H, empty=True)
    # stubby feet
    for s in (-1, 1):
        put(M, E(M, (s * 2.6, 0.8 + feet[0], 1.4 + feet[1] * s), (1.8, 1.0, 2.3)), C['foot'], empty=True)
    if p.get('tilt'):
        M = turn(M, (0, 0, 0), rot(rz=p['tilt']))
    return M, {'ground': (0, 0, 0), 'top': (0, cy + cr[1] + 1.0, 0)}


# ------------------------------------------------------------------ Briarback
BB = {
    'hollow': dict(coat='#6E4B3A', coat_lo='#523629', coat_hi='#86604A', belly='#9C8270', antler='#4A3550',
                   antler_hi='#5E4668', thorn='#2E2238', moss='#5E7D4A', hoof='#2F2420', crystal=(VIOLET, VIOLET_HI),
                   nose='#2B2026'),
    'calm': dict(coat='#B98556', coat_lo='#996A41', coat_hi='#CF9E6D', belly='#F0DDBD', antler='#7B5435',
                 antler_hi='#94683F', thorn='#5A3E26', moss='#6FA34C', hoof='#4A3528', crystal=('#8FE3D0', '#C9F5EA'),
                 nose='#3A2A22'),
}
ANTLER = [
    [(2.4, 43.0, 18.0), (6.0, 48.5, 15.5), (10.0, 54.5, 12.5), (12.5, 60.0, 8.5)],
    [(6.0, 48.5, 15.5), (6.5, 53.0, 20.5), (6.0, 56.5, 22.5)],
    [(10.0, 54.5, 12.5), (15.5, 57.0, 14.0), (18.0, 59.5, 13.0)],
    [(11.6, 58.0, 10.0), (10.4, 62.5, 13.0)],
]


def briarback(pose=None, variant='hollow'):
    p = pose or {}
    C = BB[variant]
    hollow = variant == 'hollow'
    M = Model((-24, -6, -30), (24, 68, 36), [], res=2)
    low = p.get('low', 0.0)
    feet = p.get('feet', {})
    splay = p.get('splay', 0.0)
    dy = -low
    # ---- the body
    torso = E(M, (0, 24 + dy, -2), (8.6, 8.4, 15.0), p=2.3)
    chest = E(M, (0, 25 + dy, 9), (8.0, 9.0, 7.0), p=2.2)
    haunch = E(M, (0, 24.5 + dy, -12), (8.8, 8.8, 7.5), p=2.2)
    body = torso | chest | haunch
    put(M, body, C['coat'])
    put(M, shell(M, body) & (M.Y < 19.5 + dy), C['belly'])
    put(M, shell(M, body) & (M.Y > 29 + dy) & (M.X < -2), C['coat_hi'])
    if hollow:
        put(M, shell(M, body) & (M.Y > 30 + dy) & (np.sin(M.Z * 0.7) + np.cos(M.X * 0.9) > 0.9), C['moss'])
    else:
        # fawn spots along the back, moss and blooms on the shoulders
        rng = np.random.default_rng(3)
        for k in range(16):
            z = rng.uniform(-18, 6)
            s = rng.choice([-1, 1])
            put(M, E(M, (s * rng.uniform(3, 6.5), 30.5 + dy + rng.uniform(-1.5, 1.0), z), (1.0, 0.8, 1.0)) & shell(M, body, 2), '#F6E7CC')
        put(M, shell(M, body) & (M.Y > 30.5 + dy) & (M.Z > 2) & (np.sin(M.X * 1.1 + M.Z) > 0.2), C['moss'])
    tail = E(M, (0, 28 + dy, -19.6), (2.0, 2.6, 2.2))
    put(M, tail, C['belly'] if not hollow else C['coat_lo'], empty=True)
    # ---- the legs: hip, knee (hock), hoof
    for side in (-1, 1):
        for front in (True, False):
            fdy, fdz = feet.get((side, front), (0.0, 0.0))
            sx = side * (4.9 + splay)
            if front:
                hip, rest = (side * 4.8, 19.5 + dy, 9.0), (sx, 1.2, 10.0)
            else:
                hip, rest = (side * 5.2, 20.0 + dy, -12.0), (sx, 1.2, -13.0)
            hoof = (rest[0], rest[1] + fdy, rest[2] + fdz)
            mid = ((hip[0] + hoof[0]) / 2, (hip[1] + hoof[1]) / 2, (hip[2] + hoof[2]) / 2 + (1.8 if front else -2.6))
            leg = cap(M, hip, mid, 2.6, 2.0) | cap(M, mid, hoof, 2.0, 1.5)
            put(M, leg, C['coat_lo'] if not front else C['coat'], empty=True)
            put(M, E(M, (hoof[0], hoof[1] - 0.3, hoof[2] + 0.4), (1.9, 1.3, 2.3)), C['hoof'])
            if hollow:
                for t in np.linspace(0, 1, 16):
                    a = t * 2 * math.pi * 2 + side
                    q_ = (hip[0] + (hoof[0] - hip[0]) * t + 2.1 * math.cos(a), hip[1] + (hoof[1] - hip[1]) * t,
                          hip[2] + (hoof[2] - hip[2]) * t + 2.1 * math.sin(a))
                    if t < 0.75:
                        put(M, E(M, q_, (0.6, 0.6, 0.6)), VINE_H, empty=True)
    # ---- the neck, head and antlers: one part, posed about the base of the neck
    H = blank(M)
    neck = cap(H, (0, 27 + dy, 8), (0, 37 + dy, 16), 4.8, 3.9)
    head = E(H, (0, 39.5 + dy, 19), (4.9, 5.0, 6.2), p=2.2)
    snout = E(H, (0, 37.4 + dy, 24.6), (3.5, 3.3, 4.0), p=2.2)
    put(H, neck | head | snout, C['coat'])
    # a ruff round the neck: bramble and moss in the Hollow, moss and blooms when calm
    ruff = cap(H, (0, 29 + dy, 9.5), (0, 33.5 + dy, 13.0), 6.4, 5.4) & ~cap(H, (0, 27 + dy, 8), (0, 37 + dy, 16), 4.0, 3.2)
    put(H, ruff & shell(H, ruff | neck, 2), C['moss'] if not hollow else '#3F3046')
    put(H, ruff & shell(H, ruff, 1) & (np.sin(H.X * 1.4 + H.Y * 0.9) > 0.3), C['coat_lo'] if hollow else '#7DB357')
    put(H, shell(H, neck) & (H.Z > 12) & (H.Y < 33 + dy), C['belly'])
    put(H, E(H, (0, 38.2 + dy, 28.4), (1.5, 1.2, 0.9)), C['nose'])
    put(H, shell(H, snout) & (H.Y < 35.6 + dy), C['belly'])
    hf = head | snout
    for s in (-1, 1):
        if p.get('daze'):
            put(H, facing(H, hf, (s * 3.3, 40.6 + dy), (0.9, 0.3), zmin=20), INK)
        elif hollow:
            put(H, facing(H, hf, (s * 3.3, 40.6 + dy), (1.6, 1.0), zmin=20), '#2B1F33')
            put(H, facing(H, hf, (s * 3.3, 40.6 + dy), (1.25, 0.55), zmin=20), GLOW_V, glow=1.0)
        else:
            put(H, facing(H, hf, (s * 3.3, 40.6 + dy), (0.85, 1.05), zmin=20), INK)
            put(H, facing(H, hf, (s * 3.0, 41.1 + dy), (0.32, 0.32), zmin=20), EYE_HI)
        # ears
        put(H, thorn(H, (s * 4.0, 42.4 + dy, 16.5), (s * 1.0, 0.45, -0.45), 4.6, 1.7), C['coat_lo'], empty=True)
    if p.get('mouth'):
        put(H, facing(H, snout, (0, 35.8 + dy), (1.8, 1.0), zmin=24), '#3A2026')
    # antlers of bramble
    glow = p.get('glow', 0.0)
    for s in (-1, 1):
        for br in ANTLER:
            pts = [(s * x, y + dy, z) for x, y, z in br]
            put(H, chain(H, pts, 1.35, 0.75), C['antler'])
        rng = np.random.default_rng(21 + s)
        for br in ANTLER[:3]:
            for i in range(len(br) - 1):
                a, b = np.array(br[i]), np.array(br[i + 1])
                for t in (0.35, 0.75):
                    q_ = a + (b - a) * t
                    q_ = (s * q_[0], q_[1] + dy, q_[2])
                    d = rng.normal(size=3)
                    put(H, thorn(H, q_, d, 2.0, 0.55), C['thorn'], empty=True)
        tips = [ANTLER[0][-1], ANTLER[1][-1], ANTLER[2][-1], ANTLER[3][-1]]
        for (x, y, z) in tips:
            c = (s * x, y + dy, z)
            if hollow:
                for t in np.linspace(0, 1, 8):
                    r = 1.2 * (1 - t * 0.8) + 0.2
                    put(H, E(H, (c[0] + s * t * 0.6, c[1] + t * 2.6, c[2] - t * 0.4), (r, r, r)),
                        C['crystal'][0] if t < 0.6 else C['crystal'][1], glow=0.55 + 0.4 * t + glow * 0.3)
            else:
                put(H, E(H, c, (1.6, 0.6, 1.2)), '#7DB357', empty=True)
                put(H, E(H, (c[0], c[1] + 0.8, c[2]), (0.8, 0.6, 0.8)), PINK if x < 11 else WHITE)
                put(H, E(H, (c[0], c[1] + 1.2, c[2]), (0.35, 0.35, 0.35)), GOLD)
    if hollow:
        # a Hollow vine wound up the neck and through the antlers
        for t in np.linspace(0, 1, 50):
            a = t * 2 * math.pi * 2.3
            c = np.array([0, 27 + dy, 8]) + (np.array([0, 37 + dy, 16]) - np.array([0, 27 + dy, 8])) * t
            put(H, E(H, (c[0] + 4.6 * math.cos(a), c[1], c[2] + 4.2 * math.sin(a)), (0.7, 0.7, 0.7)), VINE_H_HI, empty=True)
            if int(t * 50) % 9 == 4:
                put(H, E(H, (c[0] + 4.9 * math.cos(a), c[1] + 0.5, c[2] + 4.5 * math.sin(a)), (0.5, 0.5, 0.5)), GLOW_V, glow=0.95)
    H = turn(H, (0, 28 + dy, 7), rot(rx=p.get('head', 0.0), ry=p.get('yaw', 0.0), rz=p.get('tilt', 0.0)))
    merge(M, H)
    if hollow:
        # a ridge of thorns down the spine
        for k in range(9):
            z = 4.0 - k * 2.6
            y = 32.2 + dy - abs(z + 4) * 0.08
            put(M, thorn(M, (0, y - 1.5, z), (0, 1.0, -0.35), 4.2 - abs(k - 3) * 0.25, 1.4), C['antler'], empty=True)
            if k % 2 == 0:
                put(M, thorn(M, (0, y + 1.8, z - 1.0), (0, 1.0, -0.4), 1.3, 0.6), VIOLET_HI, glow=0.8)
        # vines over the back and Hollow cracks glowing in the flank
        for k in range(3):
            for t in np.linspace(0, 1, 44):
                a = math.pi * (0.1 + 0.8 * t)
                z = -16 + k * 9 + 2.5 * math.sin(t * 9 + k)
                x = 9.0 * math.cos(a)
                y = 24 + dy + 8.8 * math.sin(a)
                put(M, E(M, (x, y, z), (0.8, 0.8, 0.8)), VINE_H if k % 2 else VINE_H_HI, empty=True)
                if int(t * 44) % 11 == 5:
                    put(M, E(M, (x, y + 0.7, z), (0.55, 0.55, 0.55)), GLOW_V, glow=0.95)
        for s in (-1, 1):
            for (y0, z0, dz_, dy_) in ((22.0, -6.0, 1.0, 0.8), (26.0, 2.0, -0.7, 1.0)):
                for t in np.linspace(0, 1, 10):
                    c = (s * 8.6, y0 + dy + dy_ * t * 4, z0 + dz_ * t * 5)
                    put(M, E(M, c, (0.9, 0.55, 0.55)) & shell(M, body, 1), VIOLET, glow=0.75 + glow * 0.25)
    if p.get('rear'):
        M = turn(M, (0, 0, -13), rot(rx=-p['rear']))
    if p.get('roll'):
        M = turn(M, (0, 0, 0), rot(rz=p['roll']))
    return M, {'ground': (0, 0, 0), 'top': (0, 64.0, 0)}


# ------------------------------------------------------------------ cycles and poses
def quad_cycle(stride, lift, bob_amt, front_z=None, gallop=False):
    """frame i (None = idle) -> (pose feet, bob). A trot (diagonal pairs) or, galloping, the front feet
    together then the hind ones."""
    def pose(i):
        if i is None:
            return {'feet': {}}, 0.0
        t = i / FRAMES
        bob = q(bob_amt * math.sin(2 * math.pi * t) ** 2)
        feet = {}
        if gallop:
            phases = (((-1, True), 0.0), ((1, True), 0.1), ((-1, False), 0.5), ((1, False), 0.6))
        else:
            phases = (((-1, True), 0.0), ((1, False), 0.0), ((1, True), 0.5), ((-1, False), 0.5))
        for key, ph in phases:
            dy, dz = swing((t + ph) % 1.0, stride, lift)
            feet[key] = (q(dy) - bob, q(dz))
        return {'feet': feet}, bob
    return pose


def hop_cycle(height):
    def pose(i):
        if i is None:
            return {'feet': (0.0, 0.0)}, 0.0
        t = i / FRAMES
        bob = q(height * math.sin(math.pi * t))
        tuck = 0.6 * math.sin(math.pi * t)
        return {'feet': (q(tuck), q(0.5 * math.sin(2 * math.pi * t)))}, bob
    return pose


# ------------------------------------------------------------------ the Trail Guild's creatures, in the Wilds
# The Lumen Trails' three (tools/art/trail_art.py): the same models, turned and drawn like the foes so they
# share the floor. Petalune is never fought (you earn its trust), so its two looks are wary (as 'hollow')
# and befriended (as 'calm'); the Hollow Sprout's are tangled and restored.
def petalune(pose=None, variant='hollow'):
    import trail_art as TA
    p = pose or {}
    state = p.get('state') or ('wary' if variant == 'hollow' else 'happy')
    M, anc = TA.petalune(state)
    if p.get('tilt'):
        M = turn(M, (0, 0, 0), rot(rz=p['tilt']))
    if p.get('lean'):
        M = turn(M, (0, 0, 0), rot(rx=p['lean']))
    return M, {'ground': (0, 0, 0), 'top': anc['top']}


def hollow_sprout(pose=None, variant='hollow'):
    import trail_art as TA
    p = pose or {}
    M, anc = TA.hollow_sprout('hollow' if variant == 'hollow' else 'restored')
    if p.get('lean'):
        M = turn(M, (0, 0, 0), rot(rx=p['lean']))
    if p.get('tilt'):
        M = turn(M, (0, 0, 0), rot(rz=p['tilt']))
    if p.get('glow'):
        # gathering Lumen: every glowing voxel burns brighter
        g = M.glow > 0
        M.glow[g] = np.minimum(1.0, M.glow[g] + 0.35)
    return M, {'ground': (0, 0, 0), 'top': anc['top']}


def sentinel(pose=None, variant='hollow'):
    """The Forgotten Sentinel, waking at its gate (F5, the Sentinel's Gate): a hunched guardian of stacked
    stone with no legs to speak of, so it lumbers (a sway and a heave) and fights with its fists, its eyes
    and the runes in its chest"""
    import trail_art as TA
    p = pose or {}
    state = p.get('state') or ('hollow' if variant == 'hollow' else 'restored')
    arms = p.get('arms') or {'r': 'rest', 'l': 'raised'}
    M, anc = TA.sentinel(state, arms=arms)
    if p.get('glow'):
        # the runes and eyes burn brighter (a beam gathering, a shield raised)
        g = M.glow > 0
        M.glow[g] = np.minimum(1.0, M.glow[g] + 0.35)
    if p.get('lean'):
        M = turn(M, (0, 0, 0), rot(rx=p['lean']))
    if p.get('tilt'):
        M = turn(M, (0, 0, 0), rot(rz=p['tilt']))
    if p.get('turn'):
        M = turn(M, (0, 0, 0), rot(ry=p['turn']))
    return M, {'ground': (0, 0, 0), 'top': anc['top']}


def lumber_cycle(sway, heave):
    """no legs: it rocks its weight from side to side and heaves itself forward"""
    def pose(i):
        if i is None:
            return {'arms': {'r': 'rest', 'l': 'rest'}}, 0.0
        t = i / FRAMES
        side = math.sin(2 * math.pi * t)
        p = {'arms': {'r': 'rest', 'l': 'rest'}, 'tilt': round(sway * side, 3), 'lean': round(0.05 + 0.04 * abs(math.cos(2 * math.pi * t)), 3)}
        return p, q(heave * abs(side))
    return pose


class Foe:
    def __init__(self, key, build, scale, radius, gaits, act, variants=('hollow', 'calm')):
        self.key, self.build, self.scale, self.radius = key, build, scale, radius
        self.gaits = gaits            # name -> (pose fn, meta: waddle, squash, cycle, hop)
        self.act = act                # [(name, pose dict, bob)]
        self.variants = variants


FOES = {
    'thornling': lambda: Foe(
        'thornling', thornling, 6.0, 8.0,
        {'walk': (quad_cycle(1.8, 1.8, 0.6), dict(waddle=5.0, squash=0.05, cycle=7.2))},
        [('crouch', {'low': 1.2, 'bristle': 1.3, 'feet': {}}, 0.0),
         ('tuck', {'ball': 0.5, 'bristle': 1.25}, 0.0),
         ('ball', {'ball': 1.0, 'bristle': 1.15}, 0.0),
         ('nip', {'nip': 1.0, 'feet': {(-1, False): (0.0, -1.5), (1, False): (0.0, -1.5)}}, 0.0),
         ('hurt', {'hurt': True, 'roll': -0.22, 'bristle': 1.2}, 0.0)]),
    'sporecap': lambda: Foe(
        'sporecap', sporecap, 6.0, 8.0,
        {'walk': (hop_cycle(3.2), dict(waddle=0.0, squash=0.12, cycle=10.0, hop=True))},
        [('swell1', {'swell': 0.5}, 0.0), ('swell2', {'swell': 1.0}, 0.0), ('puff', {'puff': 1.0}, 0.5),
         ('hurt', {'hurt': True, 'tilt': 0.28}, 0.0)]),
    'briarback': lambda: Foe(
        'briarback', briarback, 3.6, 17.0,
        {'walk': (quad_cycle(4.0, 3.2, 1.0), dict(waddle=1.5, squash=0.02, cycle=16.0)),
         'charge': (lambda: _charge_pose(), dict(waddle=2.0, squash=0.04, cycle=30.0, hollow_only=True))},
        [('lower1', {'head': 0.38, 'low': 1.0}, 0.0),
         ('lower2', {'head': 0.8, 'low': 2.0, 'feet': {(-1, True): (0.0, 3.0), (1, True): (0.0, 3.0)}}, 0.0),
         ('sweep_l', {'head': 0.65, 'yaw': 0.75, 'tilt': 0.25, 'low': 1.5}, 0.0),
         ('sweep_r', {'head': 0.65, 'yaw': -0.75, 'tilt': -0.25, 'low': 1.5}, 0.0),
         ('rear1', {'rear': 0.24, 'head': -0.15, 'feet': {(-1, True): (5.0, 2.0), (1, True): (5.0, 2.0)}}, 0.0),
         ('rear2', {'rear': 0.4, 'head': -0.35, 'feet': {(-1, True): (8.0, 4.0), (1, True): (8.0, 4.0)}, 'glow': 1.0}, 0.0),
         ('stomp', {'head': 0.45, 'low': 2.5, 'feet': {(-1, True): (0.0, 3.0), (1, True): (0.0, 3.0)}, 'glow': 1.0}, 0.0),
         ('roar', {'head': -0.6, 'mouth': True, 'glow': 1.0}, 0.0),
         ('stagger', {'head': 0.55, 'tilt': 0.4, 'daze': True, 'splay': 1.5, 'low': 3.0, 'roll': 0.08}, 0.0),
         ('hurt', {'head': -0.25, 'tilt': -0.18, 'daze': True}, 0.0)]),
    'petalune': lambda: Foe(
        'petalune', petalune, 6.0, 7.0,
        {'walk': (hop_cycle(2.8), dict(waddle=0.0, squash=0.1, cycle=9.0, hop=True))},
        [('wary', {'state': 'wary'}, 0.0), ('neutral', {'state': 'neutral'}, 0.0), ('happy', {'state': 'happy'}, 0.0),
         ('hum', {'state': 'shy'}, 0.0), ('startle', {'state': 'wary', 'lean': -0.25}, 1.5),
         ('nuzzle', {'state': 'happy', 'lean': 0.3}, 0.0)]),
    'hollow_sprout': lambda: Foe(
        'hollow_sprout', hollow_sprout, 10.0, 9.0,
        {'walk': (hop_cycle(2.2), dict(waddle=0.0, squash=0.12, cycle=8.0, hop=True))},
        [('lash', {'lean': 0.4}, 0.0), ('rear', {'lean': -0.3, 'glow': True}, 1.0), ('slam', {'lean': 0.55}, 0.0),
         ('hurt', {'tilt': 0.3}, 0.0), ('swell', {'glow': True}, 0.5)]),
    'sentinel': lambda: Foe(
        'sentinel', sentinel, 5.0, 22.0,
        {'walk': (lumber_cycle(0.07, 0.8), dict(waddle=0.0, squash=0.02, cycle=7.0))},
        [('dormant', {'state': 'dormant', 'lean': 0.16, 'arms': {'r': 'rest', 'l': 'rest'}}, 0.0),
         ('waking', {'state': 'waking', 'lean': 0.06, 'arms': {'r': 'rest', 'l': 'raised'}}, 0.0),
         ('up', {'arms': {'r': 'up', 'l': 'up'}, 'lean': -0.1, 'glow': True}, 0.0),
         ('slam', {'arms': {'r': 'down', 'l': 'down'}, 'lean': 0.16}, 0.0),
         ('slam_r', {'arms': {'r': 'down', 'l': 'up'}, 'lean': 0.1, 'tilt': -0.06}, 0.0),
         ('slam_l', {'arms': {'r': 'up', 'l': 'down'}, 'lean': 0.1, 'tilt': 0.06}, 0.0),
         ('beam', {'arms': {'r': 'raised', 'l': 'raised'}, 'lean': -0.06, 'glow': True}, 0.0),
         ('cast', {'arms': {'r': 'wide', 'l': 'wide'}, 'lean': -0.04, 'glow': True}, 0.0),
         ('shield', {'arms': {'r': 'out', 'l': 'out'}, 'lean': 0.08, 'glow': True}, 0.0),
         ('hurt', {'arms': {'r': 'rest', 'l': 'raised'}, 'tilt': 0.12, 'lean': -0.08}, 0.0),
         ('bow', {'state': 'restored', 'arms': {'r': 'rest', 'l': 'rest'}, 'lean': 0.3}, 0.0)]),
}


def _charge_pose():
    base = quad_cycle(5.5, 4.5, 2.0, gallop=True)

    def pose(i):
        p, bob = base(i)
        p['head'] = 0.75
        p['low'] = 1.0
        return p, bob
    return pose


def gait_pose(foe, g):
    fn = foe.gaits[g][0]
    return fn() if g == 'charge' else fn


def built_frames(foe, g, variant):
    pose = gait_pose(foe, g)
    ps = [pose(None)] + [pose(i) for i in range(FRAMES)]
    return [(foe.build(p, variant)[0], bob) for p, bob in ps]


def _render_job(args):
    key, kind, name, variant, idx, w, h, gx, gy = args
    foe = FOES[key]()
    if kind == 'gait':
        pose = gait_pose(foe, name)
        p, bob = pose(None) if idx == 0 else pose(idx - 1)
    else:
        _, p, bob = foe.act[idx]
    M, anc = foe.build(p, variant)
    G = anc['ground']
    col = []
    for d in DIRS:
        cam = cam_for(d)
        light = light_for(cam.yaw)
        gpx, gpy, _ = cam.project(np.array([[G[0], -bob, G[2]]]))
        fit = Fit(foe.scale, gx - gpx[0] * foe.scale, gy - gpy[0] * foe.scale, w, h)
        o = render(M, {}, cam, w, h, fit=fit, light=light, ss=3, outline_px=max(1.5, foe.scale * 0.21), outline_col=OUTLINE,
                   inner_thresh=2.2, inner_alpha=0.8, inner_px=max(0.6, foe.scale * 0.045))
        col.append(o.rgba)
    return np.concatenate(col, 0)        # one column: the 8 directions


def render_foe(out, key, preview=False, jobs=2):
    foe = FOES[key]()
    # one frame size for every gait, pose and variant
    items = []
    for g in foe.gaits:
        items += [(M, b) for M, b in built_frames(foe, g, 'hollow')]
    for _, p, b in foe.act:
        items.append((foe.build(p, 'hollow')[0], b))
    G = (0.0, 0.0, 0.0)
    w, h, gx, gy = frame_box(items, G, foe.scale)
    print(key, 'frame', w, h, flush=True)
    meta = {'frameW': w, 'frameH': h, 'ground': [round(gx, 1), round(gy, 1)], 'scale': foe.scale, 'radius': foe.radius,
            'gaits': {}, 'act': {}}
    tasks = []
    for g, (_, gm) in foe.gaits.items():
        variants = ('hollow',) if gm.get('hollow_only') else foe.variants
        for v in variants:
            for idx in range(FRAMES + 1):
                tasks.append((key, 'gait', g, v, idx, w, h, gx, gy))
    for idx in range(len(foe.act)):
        tasks.append((key, 'act', 'act', 'hollow', idx, w, h, gx, gy))
    with ProcessPoolExecutor(jobs) as ex:
        cols = list(ex.map(_render_job, tasks))
    res = dict(zip([(t[1], t[2], t[3], t[4]) for t in tasks], cols))
    top = 0.0
    for g, (fn, gm) in foe.gaits.items():
        pose = gait_pose(foe, g)
        bobs = [pose(None)[1]] + [pose(i)[1] for i in range(FRAMES)]
        variants = ('hollow',) if gm.get('hollow_only') else foe.variants
        gmeta = {'sheets': {},
                 'roll': [0.0] + [round(gm['waddle'] * math.sin(2 * math.pi * i / FRAMES), 2) for i in range(FRAMES)],
                 'squash': [1.0] + ([round(1.0 - gm['squash'] * abs(math.cos(math.pi * i / FRAMES)) ** 6, 3) for i in range(FRAMES)]
                                    if gm.get('hop') else
                                    [round(1.0 - gm['squash'] * math.cos(2 * math.pi * i / FRAMES) ** 8, 3) for i in range(FRAMES)]),
                 'lift': [round(b * math.cos(math.radians(MAP_PITCH)) * foe.scale, 1) for b in bobs],
                 'cycle': gm['cycle']}
        for v in variants:
            sheet = np.concatenate([res[('gait', g, v, i)] for i in range(FRAMES + 1)], 1)
            fn_ = f'foe_{key}_{g}_{v}.webp'
            im = Image.fromarray(sheet, 'RGBA')
            im.save(os.path.join(out, fn_), quality=84, method=6)
            if preview:
                im.save(os.path.join(out, fn_.replace('.webp', '.png')))
            gmeta['sheets'][v] = fn_
            if g == 'walk' and v == 'hollow':
                a = sheet[:h, :w, 3]
                ys = np.where(a.max(1) > 40)[0]
                top = float(gy - ys.min()) if len(ys) else gy
            print(key, g, v, os.path.getsize(os.path.join(out, fn_)) // 1024, 'KB', flush=True)
        meta['gaits'][g] = gmeta
    sheet = np.concatenate([res[('act', 'act', 'hollow', i)] for i in range(len(foe.act))], 1)
    fn_ = f'foe_{key}_act.webp'
    im = Image.fromarray(sheet, 'RGBA')
    im.save(os.path.join(out, fn_), quality=84, method=6)
    if preview:
        im.save(os.path.join(out, fn_.replace('.webp', '.png')))
    meta['act'] = {'sheet': fn_, 'poses': [n for n, _, _ in foe.act]}
    meta['top'] = round(top, 1)
    print(key, 'act', os.path.getsize(os.path.join(out, fn_)) // 1024, 'KB', flush=True)
    return meta


def main(out, only=None, preview=False, jobs=2):
    os.makedirs(out, exist_ok=True)
    mp = os.path.join(out, 'wilds_foes.json')
    for key in only or list(FOES):
        m = render_foe(out, key, preview, jobs)
        meta = json.load(open(mp)) if os.path.exists(mp) else {}
        meta.update({'pitch': MAP_PITCH, 'dirs': DIRS, 'frames': FRAMES})
        meta.setdefault('foes', {})[key] = m
        json.dump(meta, open(mp, 'w'), indent=1)


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = {a.split('=', 1)[0]: a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--') and '=' in a}
    main(args[0], only=opts['--only'].split(',') if '--only' in opts else None, preview='--preview' in sys.argv,
         jobs=int(opts.get('--jobs', 2)))


# ------------------------------------------------------------------ the guardian's fragment (an item icon)
def briar_heartwood():
    """Briar Heartwood: a piece of the guardian's antler once the Hollow left it, warm wood split open on a
    mint-green glowing heart, a fresh leaf sprouting from it. A crafting fragment."""
    from voxel import Camera
    M = Model((-12, -2, -10), (12, 22, 10), [], res=2)
    wood = chain(M, [(-6.5, 1.5, 1.0), (-2.0, 6.5, 0.0), (2.5, 11.5, -0.5), (6.0, 17.0, -1.0)], 3.6, 2.2)
    put(M, wood, '#8A5D39')
    put(M, shell(M, wood) & (M.X < -1) & (M.Z > 0), '#A87A4E')
    put(M, shell(M, wood) & (np.sin(M.Y * 1.6 + M.X * 0.4) > 0.75), '#6A462B')
    seam = cap(M, (-4.6, 3.4, 2.4), (4.0, 14.5, 1.6), 1.25, 0.6) & shell(M, wood, 2)
    put(M, seam, '#8FE3D0', glow=0.9)
    put(M, cap(M, (-2.5, 6.0, 2.6), (2.0, 11.5, 2.2), 0.6, 0.4) & shell(M, wood, 1), '#C9F5EA', glow=1.0)
    # a little branch tine and a new leaf
    put(M, cap(M, (1.0, 10.0, -0.5), (-3.5, 15.5, -1.0), 1.4, 0.8), '#7B5435', empty=True)
    leaf = E(M, (-5.6, 17.0, -0.6), (2.6, 1.0, 1.4))
    put(M, leaf, '#6FA34C', empty=True)
    put(M, E(M, (-5.0, 17.4, -0.4), (1.6, 0.5, 0.9)) & leaf, '#8ABB66')
    for (x, y, z) in ((5.5, 15.0, 2.0), (-7.5, 4.0, 2.0), (0.5, 19.5, 1.0)):
        put(M, E(M, (x, y, z), (0.55, 0.55, 0.55)), '#C9F5EA', glow=1.0)
    return M, Camera(yaw=-18, pitch=16)


def icon(out_png):
    from build_items import render_model
    from voxel import save_rgba
    M, cam = briar_heartwood()
    save_rgba(render_model(M, cam, 256), out_png)

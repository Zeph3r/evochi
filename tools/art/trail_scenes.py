"""Lumen Trails: the places encounters happen, lit in Blender like the village scenes.

  mossy_ruins          1170x1300  a quiet forest ruin: a mossy stone arch, flagstone path, waterfall cliff
  mossy_ruins_hollow   1170x1300  the same ruin at golden hour, tangled in purple Hollow vines and crystals
  sentinel_gate        1170x1300  dusk: the great broken gate past the old bridge, Hollow crystals pulsing

Anchors (projected to pixels by village_blender.py): wild (where the wild Evochi stands), pet (where
your Evochi stands), clue (a glint for discoveries), arch (the arch's centre).

  <bpy-python> village_blender.py ../../assets/trails mossy_ruins mossy_ruins_hollow sentinel_gate --meta scenes.json
"""
from __future__ import annotations

import math

import numpy as np

from voxel import Model
from village_scenes import (
    VScene, CPainter, box, cyl_y, ball, tree2, flower_patch, far_terrain, STATE_LIGHT, GRASS, PATHC, WATERC,
    STONE, STONE_LT, SAGE, TREE_LEAVES, CLEAR_GLASS, FLOWERS, LEAF,
)

MOSS = ['#6E9A4C', '#7FAE5A', '#5F8C43', '#8ABB66']
RUIN = ['#B9B19C', '#ADA58F', '#C4BCA8', '#A39B86']
RUIN_DK = ['#8C8573', '#827B69']
RUNE_DIM = ['#7FB8A4', '#8CC4B0']
RUNE_LIT = ['#BDF7E4', '#D6FFF1']
HOLLOW = ['#7B48C4', '#8E5BD6', '#6A3AB0']
HOLLOW_LT = ['#B48CF0', '#C3A1F5']
VINE_H = ['#5B3F8C', '#6A4A9E', '#4E357A']
FERN = ['#5E9646', '#6FA552', '#4F8A3C']
CLIFF = ['#9C9480', '#918A77', '#A69F8B', '#8A836F']
CLIFF_TOP = ['#7FAE5F', '#86B566']
FOAM = ['#F2FBFF', '#E2F4FB']


def tuft(P, M, x, z, h, cols, r=0.35):
    m = (np.abs(M.X - x) <= r) & (np.abs(M.Z - z) <= r) & (M.Y >= 0) & (M.Y < h)
    m &= (np.abs(M.X - x) + np.abs(M.Z - z)) <= r * (1.6 - M.Y / max(h, 0.1))
    P.fill(m & (M.m == 0), cols, cell=9)


def fern(P, M, x, z, s, rng):
    for k in range(5):
        a = k * 1.25 + rng.uniform(-0.2, 0.2)
        for t in np.linspace(0, 1, 6):
            px, pz = x + math.cos(a) * t * 2.2 * s, z + math.sin(a) * t * 2.2 * s
            py = (0.4 + 1.6 * t - 1.8 * t * t) * s
            P.fill(ball(M, (px, py, pz), 0.45 * s), FERN, cell=9)


def flagstones(P, M, x0, x1, z0, z1, rng, cols=RUIN):
    ground = (M.Y >= -1) & (M.Y < 0.1)
    for zz in np.arange(z0, z1, 2.0):
        off = rng.uniform(-0.6, 0.6)
        for xx in np.arange(x0 + off, x1, 2.2):
            if rng.random() < 0.12:
                continue
            m = ground & (M.X >= xx + 0.15) & (M.X < xx + 2.0) & (M.Z >= zz + 0.15) & (M.Z < zz + 1.8)
            P.fill(m, cols, cell=9)
            if rng.random() < 0.3:
                P.fill(m & (M.X < xx + 0.9), MOSS, cell=9)


def pillar(P, M, x, z, h, w=1.2, broken=0.0, rng=None, runes=False, lit=False):
    rng = rng or np.random.default_rng(int(abs(x * 13 + z * 5)))
    top = h - broken
    p = (np.abs(M.X - x) <= w) & (np.abs(M.Z - z) <= w) & (M.Y >= 0) & (M.Y < top)
    if broken:
        p &= ~((M.Y > top - 1.6) & ((M.X - x) + (M.Z - z) * 0.5 > rng.uniform(-0.6, 0.6)))
    P.fill(p, RUIN, cell=(1.0, 1.0, 1.0))
    P.fill(p & (M.Y < 0.8), RUIN_DK, cell=9)
    P.fill(box(M, (x - w - 0.3, 0, z - w - 0.3), (x + w + 0.3, 0.8, z + w + 0.3)) & (M.m == 0), RUIN_DK, cell=9)
    # moss on the shaded side and the top
    mo = p & ((M.X - x) < -w + 0.6) & (rng.random(M.m.shape) > 0.35)
    P.fill(mo, MOSS, cell=9)
    P.fill(p & (M.Y > top - 0.7) & (rng.random(M.m.shape) > 0.3), MOSS, cell=9)
    if runes:
        r = p & ((M.Z - z) > w - 0.6) & (np.abs(M.X - x) < 0.26) & (M.Y > 2.0) & (M.Y < top - 1.2) & ((np.floor(M.Y * 1.0) % 3) == 0)
        P.fill(r, RUNE_LIT if lit else RUNE_DIM, glow=0.45 if lit else 0.06, cell=9)
    return p


def arch(P, M, cx, z, half, h, th=1.2, rise=1.6, rng=None, runes=True, lit=False):
    for s in (-1, 1):
        pillar(P, M, cx + s * half, z, h, w=th, rng=rng, runes=runes, lit=lit)
    a = (np.abs(M.Z - z) <= th) & (np.abs(M.X - cx) <= half + th)
    a &= np.abs(M.Y - h - rise * np.cos((M.X - cx) / (half + th) * 1.5)) <= 0.9
    P.fill(a, RUIN, cell=(1.0, 1.0, 1.0))
    P.fill(a & (M.Y > h + rise * np.cos((M.X - cx) / (half + th) * 1.5) + 0.3) & ((M.X * 7 + M.Z * 3) % 5 < 3), MOSS, cell=9)
    # keystone with the trail mark
    k = (np.abs(M.X - cx) <= 0.8) & (np.abs(M.Y - h - rise) <= 1.0) & (np.abs(M.Z - z) <= th + 0.25)
    P.fill(k, STONE_LT, cell=9)
    P.fill(k & ((M.Z - z) > th) & (np.abs(M.X - cx) < 0.3) & (np.abs(M.Y - h - rise) < 0.4),
           RUNE_LIT if lit else RUNE_DIM, glow=0.18 if lit else 0.08, cell=9)
    # hanging vines
    for vx in np.linspace(cx - half + 0.5, cx + half - 0.5, 6):
        ln = 1.5 + 2.5 * abs(math.sin(vx * 2.3))
        v = (np.abs(M.X - vx) < 0.3) & (np.abs(M.Z - z - th - 0.2) < 0.3) & (M.Y < h + 0.5) & (M.Y > h - ln)
        P.fill(v & (M.m == 0), MOSS, cell=9)


def wall(P, M, x0, x1, z, h, rng, th=1.0):
    for xx in np.arange(x0, x1, 1.6):
        hh = h * rng.uniform(0.35, 1.0)
        if rng.random() < 0.15:
            continue
        b = (M.X >= xx) & (M.X < xx + 1.5) & (np.abs(M.Z - z) <= th) & (M.Y >= 0) & (M.Y < hh)
        P.fill(b, RUIN, cell=(1.0, 1.0, 1.0))
        P.fill(b & (M.Y > hh - 0.6) & (rng.random(M.m.shape) > 0.25), MOSS, cell=9)


def block(P, M, c, s, rng, tilt=0.0):
    b = (np.abs(M.X - c[0] - (M.Y - c[1]) * tilt) <= s[0]) & (np.abs(M.Y - c[1]) <= s[1]) & (np.abs(M.Z - c[2]) <= s[2])
    b &= M.Y >= 0
    P.fill(b, RUIN, cell=(1.0, 1.0, 1.0))
    P.fill(b & (M.Y > c[1] + s[1] - 0.6) & (rng.random(M.m.shape) > 0.3), MOSS, cell=9)


def crystal(S, P, M, x, z, h, lean=(0.0, 0.0), light=True, power=6.0, y=0.0, cols=HOLLOW):
    """A Hollow crystal cluster: one tall shard and two small ones, glowing violet."""
    for k, (dx, dz, sh) in enumerate(((0, 0, 1.0), (0.9, 0.5, 0.55), (-0.8, 0.6, 0.45))):
        hh = h * sh
        t = np.clip((M.Y - y) / max(hh, 0.1), 0, 1)
        cx = x + dx + lean[0] * (M.Y - y)
        cz = z + dz + lean[1] * (M.Y - y)
        r = 0.55 * sh * (1.0 - t * 0.85) + 0.12
        m = (np.abs(M.X - cx) + np.abs(M.Z - cz) <= r * 1.4) & (M.Y >= y) & (M.Y < y + hh)
        P.fill(m, cols, glow=0.5, cell=9)
        P.fill(m & (M.Y > y + hh * 0.72), HOLLOW_LT, glow=0.7, cell=9)
    if light:
        S.lights.append({'type': 'point', 'pos': (x, y + h * 0.6, z + 1.0), 'power': power, 'color': (0.62, 0.38, 1.0), 'radius': 0.6})


def hollow_vines(P, M, rng, n, xr, zr, ymax=6.0):
    for _ in range(n):
        x, z = rng.uniform(*xr), rng.uniform(*zr)
        a = rng.uniform(0, 2 * math.pi)
        for t in np.linspace(0, 1, 14):
            px = x + math.cos(a) * t * 4.0 + math.sin(t * 6) * 0.6
            pz = z + math.sin(a) * t * 4.0
            py = max(0.2, math.sin(t * math.pi) * rng.uniform(0.5, ymax * 0.3))
            P.fill(ball(M, (px, py, pz), 0.35) & (M.m == 0), VINE_H, cell=9)
            if rng.random() < 0.18:
                P.fill(ball(M, (px, py + 0.4, pz), 0.3), HOLLOW_LT, glow=0.6, cell=9)


def cliff_and_falls(S, P, M, rng, z, h=18.0, fx=-10.0, fw=3.0):
    c = (M.Z < z) & (M.Y >= 0) & (M.Y < h + 2.0 * np.sin(M.X * 0.18) + 1.2 * np.sin(M.X * 0.5))
    P.fill(c, CLIFF, cell=(1.5, 1.0, 1.5))
    face = c & (M.Z > z - 1.6)
    P.fill(face & (np.sin(M.X * 0.45 + M.Y * 0.3) + np.cos(M.Y * 0.6 - M.X * 0.2) > 0.9), MOSS, cell=1.0)
    P.fill(c & (M.Y > h - 1.2 + 2.0 * np.sin(M.X * 0.18) + 1.2 * np.sin(M.X * 0.5)), CLIFF_TOP, cell=1.0)
    for vx in np.arange(-38.0, 38.0, 2.6):
        if abs(vx - fx) < fw + 1.0:
            continue
        top = h + 2.0 * math.sin(vx * 0.18) + 1.2 * math.sin(vx * 0.5)
        ln = 2.0 + 4.0 * abs(math.sin(vx * 1.7))
        P.fill((np.abs(M.X - vx) < 0.4) & (np.abs(M.Z - z - 0.3) < 0.4) & (M.Y < top) & (M.Y > top - ln), MOSS, cell=9)
    # waterfall: a lit strip of water down the face, a pool and foam at its foot
    fall = (np.abs(M.X - fx) < fw) & (M.Z >= z - 0.6) & (M.Z < z + 0.4) & (M.Y < h + 1.0)
    M.m[fall] = 0
    P.fill(fall, ['#8CCFE6', '#7CC2DE', '#9AD7EC', '#A9DEEF'], glow=0.12, cell=(0.5, 3.0, 0.5))
    P.fill(fall & (((M.X * 1.3) % 2.0) < 0.35), FOAM, glow=0.18, cell=(9, 9, 9))
    pool = ((M.X - fx) ** 2 / 36.0 + (M.Z - z - 4.0) ** 2 / 9.0 <= 1.0) & (M.Y >= -1.0) & (M.Y < 0.1)
    M.m[pool & (M.Y >= -0.4)] = 0
    P.fill(pool & (M.Y < -0.4), WATERC, cell=1.0)
    P.fill(((M.X - fx) ** 2 / 44.0 + (M.Z - z - 4.0) ** 2 / 13.0 <= 1.0) & ~pool & (M.Y >= -0.4) & (M.Y < 0.5), RUIN_DK + STONE, cell=1.0)
    P.fill(ball(M, (fx, 0.0, z + 1.2), 2.2, 0.4) & (M.m == 0), FOAM, glow=0.3, cell=9)


TRAIL_ANCHORS = {'wild': (5.0, 0.0, -3.0), 'pet': (-5.5, 0.0, 8.0), 'clue': (-11.0, 0.5, 1.0), 'arch': (0.0, 6.0, -14.0)}


def scene_mossy_ruins(hollow=False):
    st = STATE_LIGHT['golden' if hollow else 'day']
    cam = {'pos': (0.0, 8.5, 27.0), 'target': (0.0, 5.6, -6.0), 'fov': 46.0}
    name = 'mossy_ruins_hollow' if hollow else 'mossy_ruins'
    S = VScene(name, 1170, 1300, cam, world=st['world'] if not hollow else ((0.62, 0.52, 0.78), 0.55), samples=128,
               transparent=True, sky=st['sky'] if not hollow else ('#6F79B8', '#F2C7A0'))
    sun = dict(st['sun'])
    if hollow:
        sun['power'] = 2.2
    S.lights.append({'type': 'sun', **sun})
    S.anchors = dict(TRAIL_ANCHORS)
    rng = np.random.default_rng(91)
    M = Model((-40, -2, -60), (40, 30, 22), [], res=2)
    P = CPainter(M, 91)
    ground = (M.Y >= -1) & (M.Y < 0)
    P.fill((M.Y >= -2) & (M.Y < -1), ['#7A5A3C', '#6E5036'], cell=1)
    P.fill(ground, GRASS, cell=1.0)
    P.fill(ground & (np.sin(M.X * 0.3) + np.cos(M.Z * 0.27) > 1.2), MOSS, cell=1.0)
    # flagstone path from the viewer to the arch, and a clearing where the encounter happens
    flagstones(P, M, -3.0, 3.0, -16.0, 22.0, rng)
    clearing = ground & ((M.X / 12.0) ** 2 + ((M.Z + 1.0) / 8.0) ** 2 <= 1.0)
    P.fill(clearing & (rng.random(M.m.shape) > 0.55), ['#9BC27A', '#A6CA86'], cell=1.0)
    # the arch and its broken walls
    arch(P, M, 0.0, -14.0, 5.6, 10.5, th=1.4, rng=rng, lit=not hollow)
    wall(P, M, -20.0, -7.6, -14.0, 4.5, rng)
    wall(P, M, 7.6, 20.0, -14.0, 4.0, rng)
    pillar(P, M, -13.0, -6.0, 6.5, broken=2.0, rng=rng, runes=True, lit=False)
    pillar(P, M, 14.0, -4.0, 5.0, broken=1.5, rng=rng)
    pillar(P, M, -17.0, 6.0, 3.5, broken=1.0, rng=rng)
    # a toppled column and scattered blocks
    col = (np.abs(M.Y - 1.1) <= 1.1) & (np.abs(M.Z - 4.0 - (M.X + 14.0) * 0.18) <= 1.1) & (M.X > -24.0) & (M.X < -15.0)
    P.fill(col & (M.Y >= 0), RUIN, cell=(1.0, 1.0, 1.0))
    P.fill(col & (M.Y > 1.5) & (rng.random(M.m.shape) > 0.4), MOSS, cell=9)
    for (c, s) in (((11.0, 0.7, 6.0), (1.0, 0.7, 0.9)), ((16.0, 0.8, 9.0), (1.3, 0.8, 1.0)), ((-9.0, 0.6, -10.0), (0.9, 0.6, 0.8)),
                   ((9.0, 0.6, -9.0), (0.8, 0.6, 1.2))):
        block(P, M, c, s, rng)
    # the cliff and waterfall behind, and the forest closing in
    cliff_and_falls(S, P, M, rng, -34.0, h=15.0, fx=-13.0, fw=2.4)
    for (tx, tz, h, r) in ((-30.0, -22.0, 9, 6.0), (-34.0, -4.0, 8, 5.5), (-28.0, 12.0, 7, 5.0), (30.0, -20.0, 9, 6.5),
                           (34.0, 0.0, 8, 5.5), (29.0, 14.0, 6, 4.6), (18.0, -28.0, 8, 5.0), (-20.0, -28.0, 7, 4.6),
                           (24.0, -8.0, 6, 4.2)):
        tree2(P, M, tx, tz, h, r)
    for _ in range(14):
        fx_, fz_ = rng.uniform(-30, 30), rng.uniform(-12, 20)
        if abs(fx_) < 4.0 or (abs(fx_) < 13 and -9 < fz_ < 7):
            continue
        fern(P, M, fx_, fz_, rng.uniform(0.8, 1.3), rng)
    for _ in range(18):
        fx_, fz_ = rng.uniform(-32, 32), rng.uniform(-12, 20)
        if abs(fx_) < 4.0 or (abs(fx_) < 12 and -8 < fz_ < 6):
            continue
        flower_patch(P, M, fx_, fz_, 1.2, 0.9, rng, n=3)
    for _ in range(22):
        tuft(P, M, rng.uniform(-36, 36), rng.uniform(-14, 21), rng.uniform(0.4, 0.9), ['#79A85A', '#6E9A4C'])
    # mushrooms by the stones
    for (mx, mz) in ((-12.0, -4.6), (-11.2, -5.4), (13.0, -2.6), (-15.5, 7.2), (10.0, 7.6)):
        P.fill(cyl_y(M, (mx, mz), 0.25, 0, 0.7), ['#F4EAD6'], cell=9)
        P.fill(ball(M, (mx, 0.85, mz), 0.6, 0.55), ['#D85F51', '#E3705F'], cell=9)
    if hollow:
        # Hollow vines through the clearing, crystals pushing up between the stones
        hollow_vines(P, M, rng, 9, (-16, 16), (-12, 6))
        for (cx, cz, h, ln) in ((-8.5, -11.0, 3.6, (0.05, 0.0)), (8.0, -11.5, 4.2, (-0.06, 0.0)), (-13.5, -3.0, 2.8, (0.0, 0.0)),
                                (12.0, 2.0, 2.4, (0.0, 0.0)), (-4.0, -16.5, 2.2, (0.0, 0.0))):
            crystal(S, P, M, cx, cz, h, lean=ln, power=5.0)
        vine_arch = (np.abs(M.Z + 12.7) < 0.35) & (np.abs(M.X) < 5.8) & (M.Y > 2.0) & (M.Y < 10.5) & \
                    (np.abs(np.sin(M.Y * 1.3 + M.X * 0.9)) < 0.22)
        P.fill(vine_arch & (M.m == 0), VINE_H, cell=9)
        S.lights.append({'type': 'point', 'pos': (0.0, 5.0, -11.0), 'power': 10.0, 'color': (0.6, 0.36, 1.0), 'radius': 1.2})
    else:
        S.lights.append({'type': 'point', 'pos': (0.0, 12.0, -12.0), 'power': 0.8, 'color': (0.7, 1.0, 0.9), 'radius': 0.6})
    S.models.append((M, CLEAR_GLASS, {'water': WATERC}))
    S.models.append((far_terrain(seed=47), (), {'water': WATERC}))
    S.grade = {'bloom': 0.32 if hollow else 0.16, 'vignette': 0.18 if hollow else 0.1}
    return S


SENTINEL_ANCHORS = {'wild': (0.0, 1.6, -6.0), 'pet': (-7.0, 0.0, 10.0), 'clue': (10.0, 0.5, 4.0), 'arch': (0.0, 9.0, -16.0)}


def scene_sentinel_gate():
    st = STATE_LIGHT['dusk']
    cam = {'pos': (0.0, 10.0, 33.0), 'target': (0.0, 6.5, -6.0), 'fov': 46.0}
    S = VScene('sentinel_gate', 1170, 1300, cam, world=((0.34, 0.32, 0.6), 0.8), samples=128, transparent=True,
               sky=('#3E3F78', '#E79A86'))
    S.lights.append({'type': 'sun', **st['sun']})
    S.anchors = dict(SENTINEL_ANCHORS)
    rng = np.random.default_rng(97)
    M = Model((-40, -2, -60), (40, 34, 22), [], res=2)
    P = CPainter(M, 97)
    ground = (M.Y >= -1) & (M.Y < 0)
    P.fill((M.Y >= -2) & (M.Y < -1), ['#5E4A3A'], cell=1)
    P.fill(ground, ['#6F9A58', '#668F51', '#78A35F'], cell=1.0)
    # the old bridge: planks over a dry gully in the foreground
    gully = ground & (np.abs(M.Z - 16.0) < 2.4)
    M.m[gully] = 0
    P.fill((np.abs(M.Z - 16.0) < 2.4) & (M.Y >= -2) & (M.Y < -1), ['#4B3A2E'], cell=1)
    for xx in np.arange(-3.0, 3.0, 1.0):
        P.fill(box(M, (xx + 0.08, -0.2, 13.4), (xx + 0.92, 0.2, 18.6)), ['#9C7044', '#8D5D3B', '#A97C4B'], cell=9)
    for s in (-1, 1):
        P.fill(box(M, (s * 3.4 - 0.3, 0, 13.0), (s * 3.4 + 0.3, 2.6, 13.6)), ['#8D5D3B'], cell=9)
        P.fill(box(M, (s * 3.4 - 0.3, 0, 18.4), (s * 3.4 + 0.3, 2.6, 19.0)), ['#8D5D3B'], cell=9)
        P.fill(box(M, (s * 3.4 - 0.15, 2.0, 13.0), (s * 3.4 + 0.15, 2.3, 19.0)), ['#A97C4B'], cell=9)
    flagstones(P, M, -3.5, 3.5, -12.0, 13.0, rng, cols=RUIN_DK + RUIN)
    # raised platform with steps, the great gate behind it
    for k in range(3):
        P.fill(box(M, (-12.0 + k * 1.2, 0, -12.0 - k * 1.4), (12.0 - k * 1.2, 0.6 * (k + 1), -2.0 - k * 1.4)), RUIN, cell=(1.5, 9, 1.0))
    P.fill(box(M, (-12, 0, -12), (12, 1.8, -2)) & (rng.random(M.m.shape) > 0.75) & (M.m > 0), MOSS, cell=9)
    arch(P, M, 0.0, -16.0, 7.5, 14.0, th=1.8, rise=2.4, rng=rng, runes=True, lit=False)
    for s in (-1, 1):
        wall(P, M, s * 9.5 if s > 0 else -26.0, 26.0 if s > 0 else -9.5, -16.0, 7.0, rng, th=1.4)
        pillar(P, M, s * 13.0, -4.0, 8.0, w=1.4, broken=2.5, rng=rng, runes=True)
    # Hollow crystals: around the platform, growing out of the gate, and a big cluster behind
    for (cx, cz, h, y) in ((-9.0, -4.0, 4.4, 1.8), (9.5, -5.0, 5.2, 1.8), (-5.8, -14.0, 3.2, 0.0), (6.0, -14.4, 3.6, 0.0),
                           (-15.0, 3.0, 3.0, 0.0), (16.0, 5.0, 3.4, 0.0), (0.0, -19.0, 6.0, 0.0)):
        crystal(S, P, M, cx, cz, h, power=6.0, y=y)
    hollow_vines(P, M, rng, 12, (-18, 18), (-12, 10))
    # dead-ish trees and a far ridge
    for (tx, tz, h, r) in ((-30.0, -20.0, 10, 6.0), (30.0, -22.0, 10, 6.0), (-33.0, 4.0, 8, 5.0), (33.0, 6.0, 8, 5.0),
                           (-22.0, -34.0, 9, 5.0), (22.0, -36.0, 9, 5.0)):
        tree2(P, M, tx, tz, h, r, leaves=['#5F7F58', '#6B8A60', '#55744E'])
    P.fill((M.Z < -44) & (M.Y >= 0) & (M.Y < 14 + 4 * np.sin(M.X * 0.14)), CLIFF, cell=(1.5, 1, 1.5))
    for _ in range(26):
        tuft(P, M, rng.uniform(-36, 36), rng.uniform(-14, 21), rng.uniform(0.6, 1.4), ['#5E8A4A', '#6A9654'])
    S.lights.append({'type': 'point', 'pos': (0.0, 7.0, -10.0), 'power': 14.0, 'color': (0.62, 0.36, 1.0), 'radius': 1.5})
    S.models.append((M, CLEAR_GLASS, {'water': WATERC}))
    S.models.append((far_terrain(seed=53), (), {'water': WATERC}))
    S.grade = {'bloom': 0.4, 'vignette': 0.22}
    return S


SCENES = {'mossy_ruins': lambda: scene_mossy_ruins(False), 'mossy_ruins_hollow': lambda: scene_mossy_ruins(True),
          'sentinel_gate': scene_sentinel_gate}

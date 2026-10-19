"""Cinematic plates for the encounter Shorts (v5), lit in Blender like the places. Portrait, rendered
larger than the video frame so the composition can move a camera over them.

  short_trail        1296x2304  morning on the flagstone trail, looking up at the mossy arch (Mochi is
                                composited walking up the path)
  short_gate         1296x2304  dusk from the old bridge toward the gate; the Forgotten Sentinel sits
                                slumped in the gateway, dark, lit only by the crystals
  short_gate_lit     1296x2304  the same shot at night with the Sentinel restored (mint runes), the
                                trail beyond the gate glowing again

Anchors (projected to pixels): path_near / path_far (where Mochi walks), eye_l / eye_r / chest (for
the awakening overlays), gate (the gateway's centre).

  <bpy-python> village_blender.py ../../assets/shorts short_trail short_gate short_gate_lit --meta scenes.json --raw /tmp/shorts_raw
"""
from __future__ import annotations

import math

import numpy as np

from voxel import Model
from village_scenes import VScene, CPainter, box, ball, STATE_LIGHT, CLEAR_GLASS, WATERC, far_terrain
import trail_scenes as T
import trail_art as A

PW, PH = 1296, 2304


def place_model(S, src, pos, height, res=6, seed=5):
    """Resample a creature's voxel model (its own unit scale) into a fine Model standing on `pos`
    (feet at pos[1]) with the given height in scene units, and append it to the scene."""
    ys = np.where(src.m.any(axis=(0, 2)))[0]
    top = (ys.max() + 1 + src.lo[1]) / src.res
    bottom = (ys.min() + src.lo[1]) / src.res
    k = height / max(1e-6, top - bottom)
    lo = np.floor(np.array(pos) + np.array([src.lo[0] / src.res * k, 0, src.lo[2] / src.res * k]) - 1).astype(int)
    hi = np.ceil(np.array(pos) + np.array([src.hi[0] / src.res * k, height + 0.5, src.hi[2] / src.res * k]) + 1).astype(int)
    M = Model(tuple(lo), tuple(hi), [], res=res)
    # scene voxel centres -> model index
    ix = np.floor((M.X - pos[0]) / k * src.res).astype(int) - src.lo[0]
    iy = np.floor((M.Y - pos[1]) / k * src.res + bottom * src.res).astype(int) - src.lo[1]
    iz = np.floor((M.Z - pos[2]) / k * src.res).astype(int) - src.lo[2]
    ok = (ix >= 0) & (iy >= 0) & (iz >= 0) & (ix < src.m.shape[0]) & (iy < src.m.shape[1]) & (iz < src.m.shape[2])
    ixc, iyc, izc = np.clip(ix, 0, src.m.shape[0] - 1), np.clip(iy, 0, src.m.shape[1] - 1), np.clip(iz, 0, src.m.shape[2] - 1)
    sm = np.where(ok, src.m[ixc, iyc, izc], 0)
    sg = np.where(ok, src.glow[ixc, iyc, izc], 0.0)
    for mid in np.unique(sm):
        if mid == 0:
            continue
        name = src.mats[mid]
        M.m[sm == mid] = M.mid(name)
    M.glow[:] = sg
    S.models.append((M, ()))
    return M, k


def eye_points(src, anchors, pos, k, bottom_units):
    out = {}
    for key in ('eye_l', 'eye_r', 'chest', 'face', 'top'):
        if key in anchors:
            ax, ay, az = anchors[key]
            out[key] = (pos[0] + ax * k, pos[1] + (ay - bottom_units) * k, pos[2] + az * k)
    return out


# ------------------------------------------------------------------ the trail up to the ruins
def scene_short_trail():
    S = T.scene_mossy_ruins(False)
    S.name = 'short_trail'
    S.w, S.h = PW, PH
    # morning: a low warm sun from the right, soft sky
    S.lights = [L for L in S.lights if L['type'] != 'sun']
    S.lights.append({'type': 'sun', 'dir': (0.62, -0.46, -0.64), 'power': 3.0, 'color': 4500, 'angle': 4.0})
    S.world = ((0.78, 0.86, 0.98), 0.6)
    S.sky = ('#8EC3DE', '#F4E6CE')
    S.cam = {'pos': (0.8, 4.2, 25.0), 'target': (0.0, 6.4, -8.0), 'fov': 62.0, 'focus': (0.0, 2.0, 6.0), 'fstop': 4.0}
    M = S.models[0][0]
    P = CPainter(M, 31)
    rng = np.random.default_rng(31)
    # keep the path clear for Mochi: a longer flagstone run toward the camera, tufts and flowers beside it
    T.flagstones(P, M, -3.0, 3.0, 8.0, 30.0, rng)
    for sx, sz, r in ((-6.5, 14.0, 1.1), (6.8, 12.0, 0.9), (-7.5, 20.0, 1.2), (7.5, 19.0, 1.0), (-5.5, 26.0, 1.0), (6.0, 25.0, 0.8)):
        T.bush(P, M, np.array([sx, r * 0.5, sz]), r, rng, T.FG_LEAVES, ['#F5A3B5', '#FBC6D1', '#F28CA6'], n=7)
    for _ in range(30):
        x = rng.choice([-1, 1]) * rng.uniform(4.0, 12.0)
        T.tuft(P, M, x, rng.uniform(6.0, 30.0), rng.uniform(0.4, 0.9), ['#79A85A', '#6E9A4C', '#86B864'])
    S.anchors = {'path_near': (0.0, 0.0, 20.0), 'path_far': (0.0, 0.0, 2.0), 'arch': (0.0, 6.0, -14.0)}
    S.grade = {'bloom': 0.22, 'vignette': 0.14, 'warm': 0.03}
    return S


# ------------------------------------------------------------------ the bridge and the gate
def scene_short_gate(lit=False):
    S = T.scene_sentinel_gate()
    S.name = 'short_gate_lit' if lit else 'short_gate'
    S.w, S.h = PW, PH
    S.cam = {'pos': (1.4, 2.9, 27.0), 'target': (0.0, 5.6, -8.0), 'fov': 60.0, 'focus': (0.0, 5.0, -6.0), 'fstop': 5.6}
    M = S.models[0][0]
    P = CPainter(M, 41)
    rng = np.random.default_rng(41)
    # more bridge toward the camera, so the planks fill the bottom of the frame
    gully = (np.abs(M.Z - 22.0) < 2.4) & (M.Y >= -1) & (M.Y < 0)
    M.m[gully] = 0
    P.fill((np.abs(M.Z - 22.0) < 2.4) & (M.Y >= -2) & (M.Y < -1), ['#4B3A2E'], cell=1)
    for xx in np.arange(-3.0, 3.0, 1.0):
        P.fill(box(M, (xx + 0.08, -0.2, 11.0), (xx + 0.92, 0.2, 30.0)), ['#9C7044', '#8D5D3B', '#A97C4B'], cell=9)
    for s in (-1, 1):
        for zz in (13.0, 18.4, 24.0, 29.0):
            P.fill(box(M, (s * 3.4 - 0.3, 0, zz), (s * 3.4 + 0.3, 2.6, zz + 0.6)), ['#8D5D3B'], cell=9)
        P.fill(box(M, (s * 3.4 - 0.15, 2.0, 13.0), (s * 3.4 + 0.15, 2.3, 29.6)), ['#A97C4B'], cell=9)
    if lit:
        # night, and the trail beyond the gate lit again: rune stones glowing mint down the far path
        S.world = ((0.22, 0.24, 0.5), 0.55)
        S.sky = ('#1C2140', '#4A4F86')
        S.lights = [L for L in S.lights if L['type'] not in ('sun',)]
        S.lights.append({'type': 'sun', 'dir': (-0.5, -0.6, -0.4), 'power': 0.35, 'color': 9000, 'angle': 3.0})
        for i, zz in enumerate(np.arange(-20.0, -50.0, -4.0)):
            for s in (-1, 1):
                P.fill(box(M, (s * 3.0 - 0.4, 0, zz - 0.4), (s * 3.0 + 0.4, 1.4 - 0.1 * i, zz + 0.4)), T.RUNE_LIT, glow=0.7, cell=9)
                S.lights.append({'type': 'point', 'pos': (s * 3.0, 1.2, zz), 'power': 1.2, 'color': (0.62, 1.0, 0.86), 'radius': 0.5})
        S.lights.append({'type': 'point', 'pos': (0.0, 9.0, -8.0), 'power': 5.0, 'color': (0.6, 1.0, 0.85), 'radius': 2.0})
        # the crystals calm down to a soft mint
        for c in T.HOLLOW + T.HOLLOW_LT:
            if c in M.ids:
                M.glow[M.m == M.ids[c]] *= 0.3
    # the Sentinel in the gateway
    src, anc = A.sentinel('restored' if lit else 'dormant')
    pos = (0.0, 1.8, -6.0)
    Ms, k = place_model(S, src, pos, 12.0)
    if lit:
        Ms.glow *= 0.45
    ys = np.where(src.m.any(axis=(0, 2)))[0]
    bottom_units = (ys.min() + src.lo[1]) / src.res
    pts = eye_points(src, anc, pos, k, bottom_units)
    if lit:
        S.lights.append({'type': 'point', 'pos': (pts['chest'][0], pts['chest'][1], pts['chest'][2] + 1.5), 'power': 1.6, 'color': (0.6, 1.0, 0.85), 'radius': 0.8})
        for e in ('eye_l', 'eye_r'):
            S.lights.append({'type': 'point', 'pos': (pts[e][0], pts[e][1], pts[e][2] + 0.8), 'power': 0.5, 'color': (0.75, 1.0, 0.9), 'radius': 0.3})
    S.anchors = {'gate': (0.0, 7.0, -16.0), 'path_near': (0.0, 0.0, 24.0), 'path_far': (0.0, 0.0, 6.0), 'sentinel': pos, **pts}
    S.grade = {'bloom': 0.22 if lit else 0.36, 'vignette': 0.26}
    return S


SCENES = {'short_trail': scene_short_trail, 'short_gate': lambda: scene_short_gate(False), 'short_gate_lit': lambda: scene_short_gate(True)}

"""The opening mouth, in the voxels (after jaw_study.py): the lower head swings down about a hinge, rigidly at the
chin, blending to nothing at the hinge (the throat stretches) and toward the cheeks (the mouth's corners close).
The space it leaves inside the head is the mouth: its air, a palate above, inner cheeks and a back wall, a tongue
on the jaw's floor, lips along the front edges, and two modelled fangs hanging from the upper lip. Everything is
the head's own voxels, moved or recoloured, but the fangs.

It works in the head's own coordinates (the build's ch.rig: the head's volume, what it is fused with, its turn),
so the mouth opens the same whatever way the head is turned. jaw = 0 leaves the model as built.

    ch = build_juvenile(..., jaw=24)        # or open_jaw(ch, 24) on a built Character
"""
from __future__ import annotations

import dataclasses
import math

import numpy as np
from scipy import ndimage

# per stage, in the head's rest coordinates (y up, z forward, the face looks along +z):
#   hinge (y, z): the pivot, behind the mouth and below the eyes; lip (y, z): where the mouth plane meets the face
#   width: the mouth's half-width at the front (55% of it at the back); xfull / xzero: the jaw swings fully within
#   xfull of the middle, not at all beyond xzero; depth: the back wall, as a share of hinge-to-lip; skin: the share
#   of the jaw from the hinge over which the swing blends in
JAW = {2: dict(hinge=(14.4, 8.5), lip=(15.0, 16.6), width=3.2, xfull=4.2, xzero=8.6, depth=0.4, skin=0.3),
       3: dict(hinge=(14.8, 19.0), lip=(14.2, 28.6), width=3.0, xfull=3.8, xzero=7.2, depth=0.38, skin=0.28)}


def _smooth(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def open_jaw(ch, deg, spec=None):
    J = spec or JAW[ch.stage]
    rig = ch.rig
    M = ch.model
    R = np.asarray(rig['R'], float)
    pivot = np.asarray(rig['pivot'], float)
    t = np.asarray(rig['t'], float)
    (yh, zh), (yl, zl) = J['hinge'], J['lip']
    L = zl - zh
    th = math.radians(deg)

    def to_local(P):
        return (P - pivot - t) @ R + pivot

    def to_world(P):
        return (P - pivot) @ R.T + pivot + t

    def plane(Z):
        return yh + (Z - zh) * (yl - yh) / L

    def weight(Z, X):
        return _smooth((Z - zh) / (J['skin'] * L)) * (1 - _smooth((np.abs(X) - J['xfull']) / (J['xzero'] - J['xfull'])))

    W3 = np.stack([M.X, M.Y, M.Z], -1)
    Lc = to_local(W3)
    Xl, Yl, Zl = Lc[..., 0], Lc[..., 1], Lc[..., 2]
    filled = M.m > 0
    head = rig['head'] & filled
    fused = rig['fused']
    other = (filled & ~head) | (head & fused)
    jaw = head & ~fused & (Yl < plane(Zl)) & (Zl > zh)
    N = M.__class__.__new__(M.__class__)
    N.__dict__.update(M.__dict__)
    N.m, N.glow, N.layer = M.m.copy(), M.glow.copy(), M.layer.copy()
    N.mats, N.ids = list(M.mats), dict(M.ids)
    N.m[jaw] = 0
    N.glow[jaw] = 0
    # where each voxel near the swing comes from (the angle depends on the source: settle it)
    box = (Zl > zh - 2) & (Yl < yh + 4) & (np.abs(Xl) < 16)
    qi = np.argwhere(box)
    Q = Lc[box]
    p = Q.copy()
    for _ in range(4):
        a = th * weight(p[:, 2], p[:, 0])
        dz, dy = Q[:, 2] - zh, Q[:, 1] - yh
        p = np.stack([Q[:, 0], yh + dz * np.sin(a) + dy * np.cos(a), zh + dz * np.cos(a) - dy * np.sin(a)], 1)
    si = np.floor(to_world(p) * M.res).astype(int) - M.lo
    ok = np.all((si >= 0) & (si < np.array(M.m.shape)), 1)
    src = np.zeros(len(Q), bool)
    src[ok] = jaw[tuple(si[ok].T)]
    # traced back through the swing: from inside the jaw's rest volume (jaw), or from the gap it opened (mouth)
    from_jaw = (p[:, 1] < plane(p[:, 2])) & (p[:, 2] > zh)
    head_q = rig['head'][tuple(qi.T)]
    gap_fill = ~src & ok & from_jaw & head_q & ~rig['fused'][tuple(qi.T)]
    # the jaw's own voxels (and any gaps the resampling left inside it: the nearest jaw voxel's material)
    take = src | gap_fill
    dst, sv = tuple(qi[take].T), tuple(si[take].T)
    keep = ~other[dst]                                       # the neck and chest win where the jaw meets them
    dk = tuple(d[keep] for d in dst)
    vals = M.m[tuple(s_[keep] for s_ in sv)]
    if gap_fill.any():
        # a gap's source can be an empty voxel just outside the jaw's skin: fill from the jaw's nearest voxel
        jaw_idx = np.where(jaw, M.m, 0)
        _, (ii, jj, kk) = ndimage.distance_transform_edt(jaw_idx == 0, return_indices=True)
        srcs = tuple(s_[keep] for s_ in sv)
        vals = jaw_idx[ii[srcs], jj[srcs], kk[srcs]]
    N.m[dk] = vals
    jaw_after = np.zeros(M.m.shape, bool)
    jaw_after[dk] = True
    skull = head & ~jaw
    wedge = np.zeros(M.m.shape, bool)
    wq = ok & ~from_jaw & head_q & (p[:, 2] > zh - 0.5)      # came from above the mouth plane, in front of the hinge
    wedge[tuple(qi[wq].T)] = True
    Wv = wedge & rig['head'] & ~skull & ~jaw_after & ~other & (N.m == 0)
    half = J['width'] * (0.55 + 0.45 * np.clip((Zl - zh) / L, 0, 1))
    zback = zh + J['depth'] * L
    # the opening's shape seen from the front: flat under the upper lip, round at the bottom (a D, as the kit
    # draws it): narrower the further below the lip, against how far the jaw has opened there
    gap = np.maximum((Zl - zh) * np.tan(th * weight(Zl, Xl * 0)), 0.5)
    below = np.clip((plane(Zl) - Yl) / gap, 0, 1)
    half_d = half * np.sqrt(np.clip(1 - (below * 0.92) ** 2.2, 0.05, 1))
    hole = Wv & (np.abs(Xl) < half_d) & (Zl > zback)
    walls = Wv & ~hole
    near = ndimage.binary_dilation(hole, iterations=3)
    skin = walls & ~near                                     # the swing's sides, away from the mouth: stretched skin
    walls &= near
    mid = N.mid
    if deg > 0:
        N.m[walls & (Zl <= zback + 1.0)] = mid('jaw_deep')
        N.m[walls & (Zl > zback + 1.0)] = mid('jaw_in')
        N.m[skin] = np.where(M.m[skin] > 0, M.m[skin], mid('shell'))
    # neighbours along the head's own axes (it may be turned): shift a mask by one voxel along a local direction

    def nb(mask, d):
        w = R @ np.asarray(d, float)
        sh = tuple(int(v) for v in np.round(w))
        return np.roll(mask, (-sh[0], -sh[1], -sh[2]), axis=(0, 1, 2))
    if deg > 0:
        outside = (N.m == 0) & ~hole
        face = walls & (nb(outside, (0, 0, 1)) | nb(outside, (1, 0, 0)) | nb(outside, (-1, 0, 0)) | nb(outside, (0, -1, 0)))
        N.m[face] = np.where(M.m[face] > 0, M.m[face], mid('shell'))
        walls &= ~face
    inner = hole | walls
    full = N.m > 0
    palate = full & nb(hole, (0, -1, 0)) & ~jaw_after                 # the mouth's air just below it
    floor = full & nb(hole, (0, 1, 0)) & jaw_after                    # just above it
    if deg > 0:
        N.m[full & nb(inner, (0, -1, 0)) & ~jaw_after & ~palate & ~walls] = mid('jaw_in')
        N.m[full & nb(inner, (0, 1, 0)) & jaw_after & ~floor & ~walls] = mid('jaw_in')
        cheek_in = full & (nb(hole, (1, 0, 0)) | nb(hole, (-1, 0, 0))) & ~palate & ~floor
        N.m[cheek_in] = mid('jaw_in')
        N.m[palate] = mid('jaw_in')
        tongue = floor & (np.abs(Xl) < half * 0.62) & (Zl > zback + 0.5) & (Zl < zl - 1.0)
        N.m[tongue] = mid('jaw_tongue')
        N.m[floor & ~tongue] = mid('jaw_in')
        front_open = nb(~full & ~hole, (0, 0, 1))
        N.m[(palate | floor) & front_open] = mid('jaw_lip')
        # two fangs, modelled: three voxels at the lip, one at the point, two deep, straight down, flush in front
        fangs = np.zeros(M.m.shape, bool)
        free = (N.m == 0) | hole
        down = tuple(int(v) for v in np.round(R @ np.array([0.0, -1.0, 0.0])))
        back = tuple(int(v) for v in np.round(R @ np.array([0.0, 0.0, -1.0])))
        across = tuple(int(v) for v in np.round(R @ np.array([1.0, 0.0, 0.0])))
        for sgn in (-1, 1):
            x = sgn * J['width'] * 0.58
            col = palate & (np.abs(Xl - x) < 0.3)
            if not col.any():
                continue
            cand = np.argwhere(col)
            top = cand[np.argmax(Zl[col])]                           # the lip's front, underneath
            for r, (hw, deep) in enumerate(((1, 2), (0, 2))):
                for di in range(-hw, hw + 1):
                    for dz in range(deep):
                        v = top + np.array(down) * (1 + r) + np.array(across) * di + np.array(back) * dz
                        if np.all(v >= 0) and np.all(v < np.array(M.m.shape)) and free[tuple(v)]:
                            fangs[tuple(v)] = True
        N.m[fangs] = mid('jaw_teeth')
        N.glow[fangs] = 0.35                                 # teeth stay white in the mouth's shade
    if deg > 0:
        # strays: mouth colours on the outside that don't touch the opening go back to skin
        mouth_ids = [N.ids[k] for k in ('jaw_in', 'jaw_deep', 'jaw_lip') if k in N.ids]
        mm = np.isin(N.m, mouth_ids)
        outside = (N.m == 0) & ~hole
        cube = np.ones((3, 3, 3), bool)
        stray = mm & ndimage.binary_dilation(outside, structure=cube) & ~ndimage.binary_dilation(hole, structure=cube)
        N.m[stray] = np.where(M.m[stray] > 0, M.m[stray], N.mid('shell'))
    out = dataclasses.replace(ch, model=N)
    out.rig = dict(rig, jaw=deg, mouth_air=hole)
    out.anchors = dict(ch.anchors)
    return out

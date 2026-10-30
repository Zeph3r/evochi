"""Wearables on a posed Evochi: each piece is built on the model at rest (accessories.wear), then carried by the part
it sits on, so it stays where it belongs however the rig poses the body.

  head pieces (crowns, hats, the clip)   turn and move with the head (the rig's R about its pivot, then t)
  back pieces (packs, the mantle)        ride on the torso (its crouch, front and back: the rig's torso)
  neck pieces (scarves)                  between the two: on the Elder, the torso at the shoulders and the head at
                                         the top of the neck; on the Juvenile, mostly the torso
  everything on the Eggling              the whole egg's squash and lean (its rig's squash)

and on top, the whole body's turn and squash in a leap (the rig's turn: cine_jump.turn_body). The posed model is
filled by looking each voxel up at rest (the part maps undone), so nothing tears or leaves holes.
"""
from __future__ import annotations

import numpy as np

_rest = {}
_items = {}


def rest_item(stage, k):
    """the model at rest wearing k, and where it differs from the model at rest (the piece, and anything the piece
    cleared from under it)"""
    from accessories import wear
    from characters import build
    if stage not in _rest:
        _rest[stage] = build(stage)
    key = (stage, k)
    if key not in _items:
        rest = _rest[stage]
        Mi = wear(rest, k)
        _items[key] = (Mi, Mi.m != rest.model.m)
    return _items[key]


def part_map(stage, kind, rig, Q):
    """rest points Q (N, 3) -> where they are posed (before the leap's turn)"""
    if stage == 1:
        if 'squash' not in rig:
            return Q
        A, pv = rig['squash']
        return pv + (Q - pv) @ np.asarray(A, float).T
    R, pv, t = np.asarray(rig['R'], float), np.asarray(rig['pivot'], float), np.asarray(rig['t'], float)
    head = pv + (Q - pv) @ R.T + t
    zf, zb, bf, bb = rig['torso']
    f = np.clip((Q[:, 2] - zb) / (zf - zb), 0, 1)
    torso = Q.copy()
    torso[:, 1] += bb + (bf - bb) * f
    if kind == 'head':
        return head
    if kind == 'back':
        return torso
    if stage == 2:
        w = np.full((len(Q), 1), 0.35)
    else:
        w = np.clip((Q[:, 2] - 5.0) / 5.0, 0, 1)[:, None]
    return torso + (head - torso) * w


def posed_wear(ch, k):
    """the posed model wearing k"""
    from accessories import WEARABLES
    kind = WEARABLES[k][0]
    rig = getattr(ch, 'rig', {}) or {}
    Mi, diff = rest_item(ch.stage, k)
    M = ch.model.copy()
    # where the piece lands, roughly: its voxels carried forward, to bound the look-up
    ii = np.argwhere(diff)
    Qr = (ii + Mi.lo + 0.5) / Mi.res
    Pf = part_map(ch.stage, kind, rig, Qr)
    turn = rig.get('turn')
    if turn is not None:
        A, pt = np.asarray(turn[0], float), np.asarray(turn[1], float)
        Pf = pt + (Pf - pt) @ A.T
    lo = np.floor((Pf.min(0) - 3) * M.res).astype(int) - M.lo
    hi = np.ceil((Pf.max(0) + 3) * M.res).astype(int) - M.lo
    lo = np.clip(lo, 0, np.array(M.m.shape))
    hi = np.clip(hi, 0, np.array(M.m.shape))
    sl = tuple(slice(a, b) for a, b in zip(lo, hi))
    P = np.stack([M.X[sl], M.Y[sl], M.Z[sl]], -1).reshape(-1, 3)
    if turn is not None:
        P = pt + (P - pt) @ np.linalg.inv(A).T
    # undo the part's map: a few fixed-point steps (it is near a rigid move)
    Q = P.copy()
    for _ in range(7):
        Q = Q - (part_map(ch.stage, kind, rig, Q) - P)
    idx = np.floor(Q * Mi.res).astype(int) - Mi.lo
    ok = np.all((idx >= 0) & (idx < np.array(Mi.m.shape)), axis=1)
    idx = np.clip(idx, 0, np.array(Mi.m.shape) - 1)
    hit = ok & diff[idx[:, 0], idx[:, 1], idx[:, 2]]
    src = Mi.m[idx[:, 0], idx[:, 1], idx[:, 2]]
    gl = Mi.glow[idx[:, 0], idx[:, 1], idx[:, 2]]
    sub_m = M.m[sl].reshape(-1)
    sub_g = M.glow[sl].reshape(-1)
    for u in np.unique(src[hit]):
        sel = hit & (src == u)
        sub_m[sel] = M.mid(Mi.mats[u])
        sub_g[sel] = gl[sel]
    shape = M.m[sl].shape
    # what the piece cleared (the crest under a hat): a voxel wider, so no tips of it poke through where
    # the posed crest and the cleared space don't quite line up
    cleared = (hit & (src == 0)).reshape(shape)
    if cleared.any():
        from scipy import ndimage
        grow = ndimage.binary_dilation(cleared, iterations=2)
        crest_ids = [i for i, nm in enumerate(M.mats) if nm.startswith('crest')]
        sm = sub_m.reshape(shape)
        sm[grow & np.isin(sm, crest_ids) & ~(hit & (src > 0)).reshape(shape)] = 0
        sub_m = sm.reshape(-1)
    M.m[sl] = sub_m.reshape(shape)
    M.glow[sl] = sub_g.reshape(shape)
    return M

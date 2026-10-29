"""Poses for the cinematic Evochi (cine_evochi.py): each beat of the boss entrance gets its own body, not just its
own face. The rig moves the head, the feet and the tail (characters.build); on top of that the whole body leans
and squashes about its feet (transform_character), and its face, markings and anchors move with it.

Each stage acts its own way (the cinematic brief):
  Eggling   the most exaggerated: an oversized war cry, panicked-but-determined strain, a tiny stubborn glare
  Juvenile  the most energetic: a confident yell, clenched struggling, an aggressive focused stare
  Elder     the most controlled: a commanding roar, intense resistance (one eye nearly open), calm composure

Beats: shout (the roar hits: it yells back, rearing up), strain (eyes shut against the blast: low, squashed,
leaning in, feet braced), fierce (digs in and holds its ground: low, forward, set).
"""
from __future__ import annotations

import dataclasses
import math

import numpy as np

import charrender
from characters import build
from decals import Frame
from voxel import Camera, Model

charrender.FACE_LIFT = 0.3                # the far eye at a grazing angle: clear of the voxel steps
CAM = Camera(yaw=-30, pitch=-6)          # low, looking up at it; turned toward the guardian on the right
CAMS = {1: CAM, 2: Camera(yaw=-27, pitch=-6), 3: Camera(yaw=-19, pitch=-6)}   # the bigger heads turned less, so the far eye reads

# per stage, per beat: lean (degrees, + = forward toward the face), squash (height scale; the width grows to keep
# the volume), head (dx, dy, dz), feet {(side, front): (dy, dz)}, tail (sideways swing of the tip)
POSES = {
    1: {'shout': dict(lean=12, squash=1.02, feet={(-1, True): (0.0, 1.0), (1, True): (0.0, 1.0), (-1, False): (0.0, -0.5), (1, False): (0.0, -0.5)}),
        'strain': dict(lean=15, squash=0.86, feet={(-1, True): (0.0, 1.5), (1, True): (0.0, 1.5), (-1, False): (0.0, -1.5), (1, False): (0.0, -1.5)}),
        'fierce': dict(lean=10, squash=0.93, feet={(-1, True): (0.0, 1.0), (1, True): (0.0, 1.0), (-1, False): (0.0, -1.0), (1, False): (0.0, -1.0)})},
    2: {'shout': dict(lean=7, squash=1.02, head=(0.0, 1.2, 1.6), feet={(-1, True): (0.0, 1.0), (1, True): (0.0, 1.0), (-1, False): (0.0, -0.5), (1, False): (0.0, -0.5)}, tail=2.5),
        'strain': dict(lean=11, squash=0.89, head=(0.0, -1.6, 1.0), feet={(-1, True): (0.0, 1.5), (1, True): (0.0, 1.5), (-1, False): (0.0, -1.5), (1, False): (0.0, -1.5)}, tail=-3.0),
        'fierce': dict(lean=8, squash=0.94, head=(0.0, -0.6, 1.4), feet={(-1, True): (0.0, 1.0), (1, True): (0.0, 1.0), (-1, False): (0.0, -1.0), (1, False): (0.0, -1.0)}, tail=1.5)},
    3: {'shout': dict(lean=4, squash=1.02, head=(0.0, 2.2, 1.8), feet={(-1, True): (0.0, 1.0), (1, True): (0.0, 1.0), (-1, False): (0.0, -0.5), (1, False): (0.0, -0.5)}, tail=2.0),
        'strain': dict(lean=6, squash=0.91, head=(0.0, -1.4, 1.2), feet={(-1, True): (0.0, 1.5), (1, True): (0.0, 1.5), (-1, False): (0.0, -1.5), (1, False): (0.0, -1.5)}, tail=-3.0),
        'fierce': dict(lean=4, squash=0.95, head=(0.0, -0.6, 1.4), feet={(-1, True): (0.0, 1.0), (1, True): (0.0, 1.0), (-1, False): (0.0, -1.0), (1, False): (0.0, -1.0)}, tail=0.5)},
}


def _ground_y(M):
    idx = np.argwhere(M.m > 0)
    return (idx[:, 1].min() + M.lo[1]) / M.res


def transform_character(ch, lean=0.0, squash=1.0, pad=4):
    """the whole body leaning (a shear: the higher, the further toward the face, so the feet stay planted) and
    squashed (y scaled, x and z grown to keep the volume), about the middle of its footprint on the ground; the
    face, markings and anchors follow"""
    M = ch.model
    idx = np.argwhere(M.m > 0)
    pz = ((idx[:, 2].min() + idx[:, 2].max()) / 2 + M.lo[2]) / M.res
    pivot = np.array([0.0, _ground_y(M), pz])
    Sh = np.eye(3)
    Sh[2, 1] = math.tan(math.radians(lean))                           # z += tan(lean) * height
    S = np.diag([1 / math.sqrt(squash), squash, 1 / math.sqrt(squash)])
    A = Sh @ S
    Ai = np.linalg.inv(A)

    def P(p):
        return tuple((pivot + A @ (np.asarray(p, np.float64) - pivot)).tolist())

    def T(v, M_):
        w = M_ @ np.asarray(v, np.float64)
        return tuple((w / np.linalg.norm(w)).tolist())

    lo_u = np.floor(M.lo / M.res - pad).astype(int)
    hi_u = np.ceil(M.hi / M.res + pad).astype(int)
    hi_u[2] += int(math.ceil(abs(Sh[2, 1]) * (M.hi[1] / M.res)))
    lo_u[2] -= int(math.ceil(abs(Sh[2, 1]) * (M.hi[1] / M.res)))
    N = Model(tuple(lo_u), tuple(hi_u), M.mats[1:], res=M.res)
    Q = np.stack([N.X, N.Y, N.Z], -1).reshape(-1, 3)
    src = pivot + (Q - pivot) @ Ai.T                                   # where each new voxel comes from
    si = np.floor(src * M.res).astype(int) - M.lo
    ok = np.all((si >= 0) & (si < np.array(M.m.shape)), axis=1)
    flat = np.zeros(len(Q), np.int64)
    flat[ok] = np.ravel_multi_index(si[ok].T, M.m.shape)
    for k in ('m', 'glow', 'layer'):
        a_ = getattr(M, k).ravel()[flat]
        a_[~ok] = 0
        setattr(N, k, a_.reshape(N.m.shape).astype(getattr(M, k).dtype))

    def F(fr):
        return Frame(center=P(fr.center), n=T(fr.n, Ai.T), up=T(fr.up, A), reach=fr.reach)

    out = dataclasses.replace(ch, model=N, face=F(ch.face),
                              pattern_decals=[(F(f), ext, fn) for f, ext, fn in ch.pattern_decals],
                              anchors={k: P(v) for k, v in ch.anchors.items()})
    out.cine_xform = (pivot, A)
    return out


def posed(stage, beat):
    """the cinematic Evochi of [stage] in [beat]: the rig pose, then the lean and squash"""
    p = POSES[stage][beat]
    kw = {}
    if stage > 1:
        kw = dict(head=p.get('head'), tail=p.get('tail', 0.0))
    ch = build(stage, feet=p.get('feet'), **kw)
    u0, u1, v0, v1 = ch.face_extent
    ch = dataclasses.replace(ch, face_extent=(u0 - 2, u1 + 2, v0 - 4, v1 + 3))     # room for the big mouths and brows
    ch = transform_character(ch, p.get('lean', 0.0), p.get('squash', 1.0))
    ch.cine_beat = beat
    return ch

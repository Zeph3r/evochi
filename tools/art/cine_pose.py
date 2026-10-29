"""Poses for the cinematic Evochi, after the "Evochi Combat Posing Improvements" sheet: the same models (voxels,
patterns, horns, tails, feet), posed per beat of the boss entrance. The rig moves the head, the feet and the tail
(characters.build); on top of that the whole body leans (a shear: the higher, the further forward, so the feet
stay planted), squashes or stretches (volume kept) and puffs up, about the middle of its footprint. The face,
markings and anchors move with the body, and the face decal squashes with it (face_kit reads face_squash).

  Eggling   shout: leans forward and puffs up    strain: tucks in, braces    fierce: plants its feet, puffs up
  Juvenile  shout: throws chest and head forward strain: lowers its centre of gravity, pushes back with its legs
            fierce: stays low, ready to counter
  Elder     shout: braces wide, projects forward strain: drops low and wide, digs in    fierce: immovable, calm
"""
from __future__ import annotations

import dataclasses
import functools
import math

import numpy as np

from characters import build
from decals import Frame
from voxel import Model

F = lambda front, back: {(-1, True): (0.0, front), (1, True): (0.0, front),        # noqa: E731
                         (-1, False): (0.0, back), (1, False): (0.0, back)}
# per stage, per beat: lean (degrees forward), squash (height scale, volume kept), puff (overall scale),
# head (dx, dy, dz), feet (front, back: how far forward), tail (sideways swing of the tip)
POSES = {
    1: {'shout': dict(lean=15, squash=1.05, puff=1.03, turn=10, feet=F(1.0, -1.0)),
        'strain': dict(lean=15, squash=0.84, puff=1.0, turn=10, feet=F(1.5, -1.5)),
        'fierce': dict(lean=8, squash=0.94, puff=1.03, turn=10, feet=F(1.0, -1.0))},
    2: {'shout': dict(lean=15, squash=1.03, head=(0.0, 1.2, 3.5), turn=15, feet=F(2.0, -2.0), tail=2.5),
        'strain': dict(lean=13, squash=0.86, head=(0.0, -1.8, 2.0), turn=12, feet=F(1.5, -2.0), tail=-3.0),
        'fierce': dict(lean=10, squash=0.92, head=(0.0, -1.0, 2.2), turn=15, feet=F(1.5, -1.5), tail=1.0)},
    3: {'shout': dict(lean=7, squash=1.02, head=(0.0, 3.0, 3.0), turn=18, feet=F(1.5, -1.5), tail=2.0),
        'strain': dict(lean=8, squash=0.86, head=(0.0, -2.2, 1.8), turn=15, feet=F(2.0, -2.0), tail=-3.0),
        'fierce': dict(lean=5, squash=0.95, head=(0.0, -1.0, 1.8), turn=18, feet=F(1.0, -1.0), tail=0.5)},
}
# the head turn toward the camera (the body keeps facing the guardian): what turns, about which upright axis
#   Eggling all of it (it is all one egg); Juvenile the head (above the body); Elder the head and neck (in front)
def _smooth(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


TURN = {
    1: dict(axis=(0.0, 0.0), w=lambda X, Y, Z, hd: np.ones_like(X)),
    2: dict(axis=(0.0, 7.0), w=lambda X, Y, Z, hd: _smooth((Y - (11.0 + hd[1])) / 5.0)),
    3: dict(axis=(0.0, 10.0), w=lambda X, Y, Z, hd: _smooth((Z - (6.0 + hd[2])) / 6.0) * _smooth((Y - 8.0) / 4.0)),
}
NOTES = {
    1: {'shout': 'Leans forward and puffs up with energy.', 'strain': 'Tucks in and braces against the force.',
        'fierce': 'Plants its feet and puffs up. Small but fierce.'},
    2: {'shout': 'Throws its chest and head forward with force.',
        'strain': 'Lowers its centre of gravity and pushes back with its legs.',
        'fierce': 'Stays low and ready to counter. Focused.'},
    3: {'shout': 'Braces wide and projects forward with a powerful roar.',
        'strain': 'Drops low and wide, digging into the ground.', 'fierce': 'Immovable. Calm, controlled power.'},
}


def _ground_y(M):
    idx = np.argwhere(M.m > 0)
    return (idx[:, 1].min() + M.lo[1]) / M.res


def transform_character(ch, lean=0.0, squash=1.0, puff=1.0, turn=0.0, turn_spec=None, head=(0, 0, 0), pad=4):
    """the head (or whole egg) turned [turn] degrees about an upright axis, then the whole body leaning, squashed or
    stretched (volume kept) and puffed up, about the middle of its footprint on the ground; the face, markings and
    anchors follow, and the face decal squashes with the body"""
    M = ch.model
    idx = np.argwhere(M.m > 0)
    pz = ((idx[:, 2].min() + idx[:, 2].max()) / 2 + M.lo[2]) / M.res
    pivot = np.array([0.0, _ground_y(M), pz])
    t = math.tan(math.radians(lean))
    Sh = np.eye(3)
    Sh[2, 1] = t                                                       # z += tan(lean) * height
    S = np.diag([1 / math.sqrt(squash), squash, 1 / math.sqrt(squash)]) * puff
    A = Sh @ S
    Ai = np.linalg.inv(A)
    th = math.radians(turn)
    ax, az = turn_spec['axis'] if turn_spec else (0.0, 0.0)
    az += head[2]
    wfn = turn_spec['w'] if turn_spec else None

    def rot(p, sign=1.0):
        """the turn of points p (n, 3): each by its own share of the angle"""
        p = np.asarray(p, np.float64)
        if not th or wfn is None:
            return p
        a = sign * th * wfn(p[:, 0], p[:, 1], p[:, 2], head)
        c, s_ = np.cos(a), np.sin(a)
        x, z = p[:, 0] - ax, p[:, 2] - az
        out = p.copy()
        out[:, 0] = ax + c * x + s_ * z
        out[:, 2] = az - s_ * x + c * z
        return out

    def unrot(q):
        p = q
        for _ in range(3):                      # the angle depends on where the point came from: settle it
            if not th or wfn is None:
                return q
            a = -th * wfn(p[:, 0], p[:, 1], p[:, 2], head)
            c, s_ = np.cos(a), np.sin(a)
            x, z = q[:, 0] - ax, q[:, 2] - az
            p = q.copy()
            p[:, 0] = ax + c * x + s_ * z
            p[:, 2] = az - s_ * x + c * z
        return p

    def P(p):
        r = rot(np.asarray(p, np.float64)[None])[0]
        return tuple((pivot + A @ (r - pivot)).tolist())

    def T(v, M_, at):
        a = th * (wfn(*(np.asarray([[c] for c in at])), head)[0] if (th and wfn is not None) else 0.0)
        c, s_ = math.cos(a), math.sin(a)
        v = np.asarray(v, np.float64)
        v = np.array([c * v[0] + s_ * v[2], v[1], -s_ * v[0] + c * v[2]])
        w = M_ @ v
        return tuple((w / np.linalg.norm(w)).tolist())

    grow = math.ceil(abs(t) * M.hi[1] / M.res + (puff - 1) * 20 + 2 + (6 if turn else 0))
    lo_u = np.floor(M.lo / M.res - pad).astype(int) - np.array([grow, 0, grow])
    hi_u = np.ceil(M.hi / M.res + pad).astype(int) + np.array([grow, grow, grow])
    N = Model(tuple(lo_u), tuple(hi_u), M.mats[1:], res=M.res)
    Q = np.stack([N.X, N.Y, N.Z], -1).reshape(-1, 3)
    src = unrot(pivot + (Q - pivot) @ Ai.T)                            # where each new voxel comes from
    si = np.floor(src * M.res).astype(int) - M.lo
    ok = np.all((si >= 0) & (si < np.array(M.m.shape)), axis=1)
    flat = np.zeros(len(Q), np.int64)
    flat[ok] = np.ravel_multi_index(si[ok].T, M.m.shape)
    for k in ('m', 'glow', 'layer'):
        a_ = getattr(M, k).ravel()[flat]
        a_[~ok] = 0
        setattr(N, k, a_.reshape(N.m.shape).astype(getattr(M, k).dtype))

    def Fr(fr):
        return Frame(center=P(fr.center), n=T(fr.n, Ai.T, fr.center), up=T(fr.up, A, fr.center), reach=fr.reach)

    out = dataclasses.replace(ch, model=N, face=Fr(ch.face),
                              pattern_decals=[(Fr(f), ext, fn) for f, ext, fn in ch.pattern_decals],
                              anchors={k: P(v) for k, v in ch.anchors.items()})
    # the face plane's own scale on the posed body: across, and up the (sheared) face
    out.face_squash = (puff / math.sqrt(squash), puff * squash * math.sqrt(1 + t * t))
    return out


@functools.lru_cache(None)
def _toward_camera():
    """which way a turn brings the face round to the cinematic camera (cine_evochi.CAM)"""
    import cine_evochi as CE
    d = np.asarray(CE.CAM.basis()[0], np.float64)
    return 1.0 if np.array([math.sin(0.3), 0, math.cos(0.3)]) @ d > np.array([-math.sin(0.3), 0, math.cos(0.3)]) @ d else -1.0   # d: toward the camera


def posed(stage, beat):
    """the cinematic Evochi of [stage] in [beat]: the rig pose, then the lean, squash and puff"""
    p = POSES[stage][beat]
    kw = dict(head=p.get('head'), tail=p.get('tail', 0.0)) if stage > 1 else {}
    ch = build(stage, feet=p.get('feet'), **kw)
    return transform_character(ch, p.get('lean', 0.0), p.get('squash', 1.0), p.get('puff', 1.0),
                               turn=p.get('turn', 0.0) * _toward_camera(), turn_spec=TURN[stage],
                               head=p.get('head') or (0.0, 0.0, 0.0))

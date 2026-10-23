"""The villagers out walking: walk sheets for Pip, Alder, Bram and Mira (and Flint on the Old Trail) at the
walking camera, eight directions, standing and eight walk frames, in the same flat look and ink as your
Evochi's sheets, so they stand in the walkable maps the way it does (the portrait sprites made for
conversations face you, flatter, from another angle, and sank into the scene).

    python3 npc_walk.py flutter/assets/art/wilds [--only=npc_bram,...] [--preview]

The villagers are built for their rooms (village_npcs.py); here each pose moves their feet (a step
forward with a lift, the other foot carrying them, Sher's biped gait) and swings what they carry
against the step, and the body bobs as a foot passes under it. Flint walks like the Elder he is
(walk.py's four-footed gait) in his gear. Writes walk_npc_<id>_default.webp and adds each walker to
wilds_walk.json (so the app loads it like your Evochi's), with the sprite's height in px.
"""
import copy
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import walk as W  # noqa: E402
from village_npcs import ARM, BODY, INK, NPC_BUILDERS  # noqa: E402
from village_npc_render import npc_palette  # noqa: E402

FOOT_TOP = {'bram': 2.4, 'mira': 2.6, 'pip': 3.4, 'alder': 2.8}    # how high their feet (legs) reach
GAIT = {  # a calmer step than Sher's, each villager their own way
    'bram': dict(stride=1.2, lift=1.0, bob=0.5, flight=0.0, arms=0.5, lean=0.0, waddle=3.0, squash=0.03),
    'mira': dict(stride=1.4, lift=1.0, bob=0.5, flight=0.0, arms=0.5, lean=0.0, waddle=2.0, squash=0.02),
    'pip': dict(stride=1.6, lift=1.4, bob=1.0, flight=0.3, arms=0.8, lean=0.0, waddle=2.5, squash=0.05),
    'alder': dict(stride=1.0, lift=0.5, bob=0.0, flight=0.0, arms=0.3, lean=0.0, waddle=3.5, squash=0.015),
}


def _shift(m, mask, dy, dz, res):
    """Move the voxels under [mask] by (dy, dz) world units (whole voxels), into empty space only."""
    iy, iz = int(round(dy * res)), int(round(dz * res))
    moved = np.zeros_like(m)
    moved[mask] = m[mask]
    m = np.where(mask, 0, m)
    moved = np.roll(np.roll(moved, iy, 1), iz, 2)
    put = (moved > 0) & (m == 0)
    m[put] = moved[put]
    return m


def villager(key):
    base = NPC_BUILDERS[key]()
    M0 = base.model
    res = M0.res
    feet = (M0.layer == BODY) & (M0.Y < FOOT_TOP[key]) & (M0.m > 0)
    arm = (M0.layer == ARM) & (M0.m > 0)
    g = GAIT[key]

    def pose(i):
        if i is None:
            return {'legs': {}, 'arm': 0.0}, 0.0
        t = i / W.FRAMES
        bob = W.q(g['bob'] * math.sin(2 * math.pi * t) ** 2)
        legs = {}
        for side, ph in ((-1, 0.0), (1, 0.5)):
            dy, dz = W.swing((t + ph) % 1.0, g['stride'], g['lift'])
            legs[side] = (W.q(dy) - bob, W.q(dz))
        return {'legs': legs, 'arm': W.q(-legs[1][1] * g['arms'])}, bob

    def builder(p):
        ch = copy.copy(base)
        M = M0.copy()
        m = M.m
        for side, (dy, dz) in p['legs'].items():
            m = _shift(m, feet & ((M0.X < 0) if side < 0 else (M0.X >= 0)), dy, dz, res)
        if p['arm']:
            m = _shift(m, arm, 0.0, p['arm'], res)
        M.m = m
        ch.model = M
        return ch

    pal = npc_palette(base, INK)
    return W.Walker(f'npc_{key}', builder, {'walk': pose}, [('default', pal)], W.SCALE, 6.0, {'walk': g})


def flint_walker():
    from flint import FLINT_SCALE, flint_palette, gear_up
    from characters import build

    def builder(p):
        return gear_up(build(3, 2, feet=p['feet'], lo_y=-3))
    g = W.QUAD
    return W.Walker('npc_flint', builder, {k: W.quad_pose(k, 3) for k in g}, [('default', flint_palette())],
                    W.STAGE_SCALE[3] * FLINT_SCALE, W.RADIUS[3], g, W.QUAD_STAGE[3])


for _k in NPC_BUILDERS:
    W.WALKERS[f'npc_{_k}'] = (lambda k: (lambda: villager(k)))(_k)
W.WALKERS['npc_flint'] = flint_walker


def heights(out, keys):
    """The standing sprite's height (ground to the top of its head, facing you), for the app's scale."""
    from PIL import Image
    mpath = os.path.join(out, 'wilds_walk.json')
    meta = json.load(open(mpath))
    for k in keys:
        wk = meta['walkers'][k]
        im = np.asarray(Image.open(os.path.join(out, wk['gaits']['walk']['sheets']['default'])))
        a = im[:wk['frameH'], :wk['frameW'], 3]
        rows = np.nonzero(a.max(1) > 40)[0]
        wk['heightPx'] = round(wk['ground'][1] - rows[0], 1)
    json.dump(meta, open(mpath, 'w'), indent=1)


if __name__ == '__main__':
    out = sys.argv[1]
    only = next((a.split('=', 1)[1].split(',') for a in sys.argv if a.startswith('--only=')),
                [f'npc_{k}' for k in NPC_BUILDERS] + ['npc_flint'])
    W.main(out, preview='--preview' in sys.argv, only=only)
    heights(out, only)

"""The Eggling as a live model, for the game to pose and draw itself (lib/features/live): its voxels' faces
at rest, which part each belongs to (the body, or one of its four feet, which step on their own), how each is
lit by the clips' renderer apart from the light itself (its smoothed normal, its ambient occlusion), its
colours in every palette, and its face and markings (the decals the clips project onto it) for each
expression.

    python3 live_export.py [OUT_DIR]        (default flutter/assets/live/eggling)

  model.json      grid, parts, pivots, light, the camera the clips use, palettes (colour per material), the
                  expressions and where each decal set lies in its palette's file
  faces.bin       per face 10 bytes: i j k (voxel, u8), dir (0..5: +x -x +y -y +z -z), material, part,
                  ao (u8, x200), normal (3 x i8, x127)
  decals_<palette>.bin   quads: 4 corners (12 x i16, world x64), rgb, lit (x255), normal (3 x i8), alpha
"""
from __future__ import annotations

import json
import os
import struct
import sys

import numpy as np
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import charrender as CR                                           # noqa: E402
from characters import build                                     # noqa: E402
from palettes import VARIANT_ORDER, palette                       # noqa: E402
from voxel import FACES, Light, hexrgb, smooth_normals            # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
FEET = {'feet', 'feet_shade', 'claw'}
PARTS = ['body', 'foot_ln', 'foot_lf', 'foot_rn', 'foot_rf']     # l/r: its left (-x) / right (+x); n/f: front / back
EXPRS = ['default', 'blink', 'happy', 'curious', 'surprised', 'determined', 'sad', 'sleepy', 'excited']


def main(out):
    os.makedirs(out, exist_ok=True)
    ch = build(1, lo_y=-6)
    M = ch.model
    light = Light()
    filled = M.m > 0
    names = list(M.mats)
    # which part each voxel is: a foot by where it stands, else the body
    part = np.zeros(M.m.shape, np.uint8)
    footm = np.isin(M.m, [i for i, n in enumerate(names) if n in FEET]) & filled
    side = np.where(M.X < 0, 0, 2)
    front = np.where(M.Z > 0, 1, 2)          # foot_ln = 1 (left front) ...
    part[footm] = (side + front)[footm].astype(np.uint8)
    # its light, apart from the light: smoothed normals and the occlusion in front of each face
    sn = smooth_normals(M, light.smooth_sigma * M.res)
    aob = ndimage.gaussian_filter(filled.astype(np.float32), 1.6 * M.res, mode='constant')
    ao_off = max(1, int(round(1.5 * M.res)))
    jit = (np.random.default_rng(7).random(M.m.shape).astype(np.float32) - 0.5) * 2 * light.jitter
    padm = np.pad(filled, 1)
    padp = np.pad(part, 1, constant_values=255)
    rows = []
    for d, (normal, _) in enumerate(FACES):
        nx, ny, nz = normal
        sl = (slice(1 + nx, 1 + nx + M.m.shape[0]), slice(1 + ny, 1 + ny + M.m.shape[1]), slice(1 + nz, 1 + nz + M.m.shape[2]))
        # shown where nothing is beside it, or another part is (a foot moves off the body)
        vis = filled & (~padm[sl] | (padp[sl] != part))
        idx = np.argwhere(vis)
        fn = np.array(normal, np.float32)
        s = sn[idx[:, 0], idx[:, 1], idx[:, 2]]
        nrm = light.smooth * s + (1 - light.smooth) * fn
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-6)
        q = np.clip(idx + np.array(normal) * ao_off, 0, np.array(M.m.shape) - 1)
        ao = np.clip(1.0 - light.ao_amt * np.clip(aob[q[:, 0], q[:, 1], q[:, 2]] - 0.12, 0, 1) * 2.2, 0.55, 1.0)
        ao = ao * (1 + jit[idx[:, 0], idx[:, 1], idx[:, 2]])
        for (i, j, k), n_, a in zip(idx, nrm, ao):
            rows.append(struct.pack('<7B3b', i, j, k, d, M.m[i, j, k], part[i, j, k], int(round(min(1.27, a) * 200)),
                                    *[int(round(v * 127)) for v in n_]))
    open(os.path.join(out, 'faces.bin'), 'wb').write(b''.join(rows))
    # palettes: a colour for every material, and the outline
    pals = {}
    sets = None
    for v in VARIANT_ORDER:
        pal = dict(palette(v))
        cols = []
        for n in names:
            c = pal.get(n)
            if c is None:
                b = n.split('.')[0]
                c = b if b.startswith('#') else pal.get(b, '#ff00ff')
            cols.append([int(x) for x in (hexrgb(c) if isinstance(c, str) else np.array(c))])
        pals[v] = {'mats': cols, 'outline': [int(x) for x in hexrgb(pal['outline'])]}
        # its markings and its face in each expression, as quads lying on the body
        chunks, sets = [], []
        for name in ['pattern'] + EXPRS:
            qs = CR.pattern_quads(ch, pal, v) if name == 'pattern' else CR.face_quads(ch, pal, v, name)
            sets.append({'name': name, 'count': len(qs)})
            for qd in qs:
                p = np.clip(np.round(np.asarray(qd.pts, np.float64) * 64), -32767, 32767).astype(np.int16)
                c = np.clip(np.round(qd.color), 0, 255).astype(np.uint8)
                nn = np.clip(np.round(np.asarray(qd.normal, np.float64) * 127), -127, 127).astype(np.int8)
                chunks.append(p.tobytes() + bytes(c.tolist()) + bytes([int(round(float(qd.lit) * 255))])
                              + nn.tobytes() + bytes([int(round(float(qd.alpha) * 255))]))
        open(os.path.join(out, 'decals_%s.bin' % v), 'wb').write(b''.join(chunks))
        print(v, 'decals', sum(s['count'] for s in sets), flush=True)
    idx = np.argwhere(filled)
    meta = {
        'res': int(M.res), 'lo': [int(x) for x in M.lo], 'dims': [int(x) for x in M.m.shape],
        'mats': names, 'parts': PARTS, 'faces': len(rows),
        # it squashes, leans and puffs about the middle of its footprint, and turns about its spot
        'squashPivot': [0.0, float((idx[:, 1].min() + M.lo[1]) / M.res), float(((idx[:, 2].min() + idx[:, 2].max()) / 2 + M.lo[2]) / M.res)],
        'turnPivot': [0.0, 0.0, 0.0],
        'top': float((idx[:, 1].max() + 1 + M.lo[1]) / M.res),
        'light': {'key': list(light.key), 'keyCol': list(light.key_col), 'fillCol': list(light.fill_col),
                  'ambient': light.ambient, 'keyAmt': light.key_amt},
        'camera': {'yaw': 18.0, 'pitch': 13.0},
        'palettes': pals, 'decalSets': sets, 'decalBytes': 32,
    }
    json.dump(meta, open(os.path.join(out, 'model.json'), 'w'))
    print('faces', len(rows), 'bytes', os.path.getsize(os.path.join(out, 'faces.bin')))


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'flutter', 'assets', 'live', 'eggling'))

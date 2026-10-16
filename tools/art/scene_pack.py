"""Pack a VScene (voxel models, lights, world, camera) into one .npz so Blender can render it with
nothing but bpy + numpy: no scipy/cv2/PIL needed on the render machine (e.g. Steam's Blender on a
gaming PC with a GPU). village_blender.py and npc_blender.py read these packs.
"""
from __future__ import annotations

import json
from types import SimpleNamespace

import numpy as np

SCALARS = ('name', 'w', 'h', 'cam', 'lights', 'world', 'samples', 'transparent', 'view', 'look', 'exposure',
           'anchors', 'grade', 'sky')


def pack(vs, path):
    arrays = {}
    models = []
    for i, item in enumerate(vs.models):
        M, glass = item[0], item[1]
        opts = item[2] if len(item) > 2 else {}
        arrays[f'm{i}'] = M.m
        g = M.glow
        if np.any(g):
            arrays[f'g{i}'] = g.astype(np.float16)
        models.append({'lo': [int(v) for v in M.lo], 'res': int(M.res), 'mats': list(M.mats), 'glass': list(glass),
                       'opts': {k: (list(v) if isinstance(v, (tuple, list)) else v) for k, v in opts.items()}})
    meta = {k: getattr(vs, k) for k in SCALARS if hasattr(vs, k)}
    meta['models'] = models
    np.savez_compressed(path, meta=json.dumps(meta, default=lambda o: list(o) if isinstance(o, tuple) else str(o)),
                        **arrays)


def unpack(path_or_npz):
    D = np.load(path_or_npz) if isinstance(path_or_npz, str) else path_or_npz
    meta = json.loads(str(D['meta']))
    models = []
    for i, md in enumerate(meta['models']):
        m = D[f'm{i}']
        glow = D[f'g{i}'].astype(np.float32) if f'g{i}' in D.files else np.zeros(m.shape, np.float32)
        lo = np.array(md['lo'], np.int32)
        res = md['res']
        M = SimpleNamespace(m=m, glow=glow, lo=lo, res=res, mats=md['mats'],
                            ids={n: j for j, n in enumerate(md['mats'])})
        M.coords = lambda M=M: _coords(M)
        models.append((M, tuple(md['glass']), md['opts']))
    vs = SimpleNamespace(**{k: meta.get(k) for k in SCALARS})
    vs.models = models
    return vs


def _coords(M):
    r = float(M.res)
    xs = (np.arange(M.lo[0], M.lo[0] + M.m.shape[0]) + 0.5) / r
    ys = (np.arange(M.lo[1], M.lo[1] + M.m.shape[1]) + 0.5) / r
    zs = (np.arange(M.lo[2], M.lo[2] + M.m.shape[2]) + 0.5) / r
    return np.meshgrid(xs, ys, zs, indexing='ij')

"""Pack a cinematic scene (cine_scenes.py) into one .npz that cine_blender.py can render with nothing but bpy +
numpy (the PC's Blender on its GPU): the voxel models as scene_pack.py packs them, the actors as plain mesh
arrays (cine_blender.actor_arrays), the lights, camera, sky and grade.

    python3 cine_pack.py OUT_DIR scene [scene ...]        -> OUT_DIR/<scene>.npz
    <blender python> cine_blender.py OUT_DIR OUT_DIR/<scene>.npz --gpu     (renders the raw frame + depth)
    python3 cine_blender.py --regrade OUT_DIR scene      (the grade, back where PIL lives)
"""
from __future__ import annotations

import json
import os
import sys
from types import SimpleNamespace

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import scene_pack  # noqa: E402

SCALARS = scene_pack.SCALARS + ('sky_world', 'zmax', 'keep_alpha', 'polylines', 'cameras')


def pack(vs, path):
    from cine_blender import actor_arrays
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
    actors = []
    for j, a in enumerate(getattr(vs, 'actors', None) or []):
        A = actor_arrays(a)
        meta_a = {k: A[k] for k in ('name', 'pos', 'yaw', 'rot', 'scale', 'camera', 'shadow', 'glow_k', 'head')}
        meta_a['parts'] = []
        for k, p in enumerate(A['parts']):
            for key in ('C', 'COL', 'VN', 'GLOW'):
                arrays[f'a{j}p{k}{key}'] = p[key]
            meta_a['parts'].append({'name': p['name'], 'origin': p['origin']})
        meta_a['decals'] = []
        for key, d in A['decals'].items():
            for kk in ('Q', 'COL', 'UNLIT'):
                arrays[f'a{j}d{key}{kk}'] = d[kk]
            meta_a['decals'].append(key)
        actors.append(meta_a)
    meta = {k: getattr(vs, k) for k in SCALARS if hasattr(vs, k)}
    meta['models'] = models
    meta['actors'] = actors
    np.savez_compressed(path, meta=json.dumps(meta, default=lambda o: list(o) if isinstance(o, tuple) else (o.tolist() if hasattr(o, 'tolist') else str(o))),
                        **arrays)


def unpack(path):
    D = np.load(path)
    meta = json.loads(str(D['meta']))
    vs = scene_pack.unpack(D)
    for k in SCALARS:
        setattr(vs, k, meta.get(k))
    vs.actors = None
    vs.actor_arrays = []
    for j, ma in enumerate(meta.get('actors', [])):
        A = dict(ma)
        A['parts'] = [dict(p, **{key: D[f'a{j}p{k}{key}'] for key in ('C', 'COL', 'VN', 'GLOW')}) for k, p in enumerate(ma['parts'])]
        A['decals'] = {key: {kk: D[f'a{j}d{key}{kk}'] for kk in ('Q', 'COL', 'UNLIT')} for key in ma['decals']}
        vs.actor_arrays.append(A)
    vs.grade = vs.grade or {}
    vs.anchors = vs.anchors or {}
    return vs


if __name__ == '__main__':
    out, names = sys.argv[1], sys.argv[2:]
    import cine_scenes as CS
    if names == ['all']:
        names = list(CS.SCENES)
    os.makedirs(out, exist_ok=True)
    for n in names:
        vs = CS.SCENES[n]()
        p = os.path.join(out, n + '.npz')
        pack(vs, p)
        print(n, '->', p, round(os.path.getsize(p) / 1e6, 1), 'MB', flush=True)

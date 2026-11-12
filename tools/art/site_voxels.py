"""The website's 3D scenes (site/src/scene3d.js draws them with three.js): the floating island with the sleeping
Elder (petal mane, its face and markings) and the nest, egg and lantern in front of her, as on the start screen
(title_layers.py); and the Briarback, tangled in the Hollow and restored (wilds_foes.briarback).

Every exposed voxel face is written once, camera-free: where it is, which way it faces, its colour (the
palette's, with the renderer's soft occlusion and grain baked in), the smoothed normal the game shades with,
and how much it glows. The face and markings are the renderer's own decal quads, lying on the surface.

    python3 site_voxels.py [OUT_DIR]        (default site/assets/3d)

Writes hero.bin.gz, briar.bin.gz (gzipped; the page unpacks them with DecompressionStream) and scenes.json:
each part's grid resolution and origin, how many faces and decals, and where its columns start. The faces are
stored column by column (they pack far smaller that way): uint8 x, y, z (the voxel's index from the part's
origin), uint8 face (voxel.FACES order), uint8 r, g, b, int8 nx, ny, nz, uint8 glow. A decal record is 56 bytes:
float32 x, y, z for its four corners, uint8 r, g, b, alpha, lit, and three bytes of padding.
"""
import json
import os
import sys

import numpy as np
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from voxel import FACES, Light, hexrgb, smooth_normals    # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
FACE_DT = np.dtype([('p', '<i2', 3), ('f', 'u1'), ('c', 'u1', 3), ('n', 'i1', 3), ('g', 'u1')])
DECAL_DT = np.dtype([('p', '<f4', 12), ('c', 'u1', 5), ('pad', 'u1', 3)])


def faces_of(M, palette, light=None, seed=7):
    light = light or Light()
    m = M.m
    filled = m > 0
    pad = np.pad(filled, 1)
    sn = smooth_normals(M, light.smooth_sigma * M.res)
    ao_off = max(1, int(round(1.5 * M.res)))
    aob = ndimage.gaussian_filter(filled.astype(np.float32), 1.6 * M.res, mode='constant')
    rng = np.random.default_rng(seed)
    jit = (rng.random(m.shape).astype(np.float32) - 0.5) * 2 * light.jitter
    alb_of = {}
    for mid, name in enumerate(M.mats):
        if mid == 0:
            continue
        col = palette.get(name)
        if col is None:
            b = name.split('.')[0]
            col = b if b.startswith('#') else palette.get(b, '#ff00ff')
        alb_of[mid] = hexrgb(col) if isinstance(col, str) else np.array(col, np.float32)
    out = []
    for fi, (normal, _) in enumerate(FACES):
        nx, ny, nz = normal
        neigh = pad[1 + nx:1 + nx + m.shape[0], 1 + ny:1 + ny + m.shape[1], 1 + nz:1 + nz + m.shape[2]]
        idx = np.argwhere(filled & ~neigh)
        if len(idx) == 0:
            continue
        fn = np.array(normal, np.float32)
        s = sn[idx[:, 0], idx[:, 1], idx[:, 2]]
        nrm = light.smooth * s + (1 - light.smooth) * fn
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-6)
        q = np.clip(idx + np.array(normal) * ao_off, 0, np.array(m.shape) - 1)
        occ = aob[q[:, 0], q[:, 1], q[:, 2]]
        ao = np.clip(1.0 - light.ao_amt * np.clip(occ - 0.12, 0, 1) * 2.2, 0.55, 1.0)
        mids = m[idx[:, 0], idx[:, 1], idx[:, 2]]
        alb = np.zeros((len(idx), 3), np.float32)
        for mid in np.unique(mids):
            alb[mids == mid] = alb_of[int(mid)]
        col = alb * (ao * (1 + jit[idx[:, 0], idx[:, 1], idx[:, 2]]))[:, None]
        r = np.zeros(len(idx), FACE_DT)
        r['p'] = idx + M.lo
        r['f'] = fi
        r['c'] = np.clip(np.round(col), 0, 255)
        r['n'] = np.clip(np.round(nrm * 127), -127, 127)
        r['g'] = np.clip(np.round(M.glow[idx[:, 0], idx[:, 1], idx[:, 2]] * 255), 0, 255)
        out.append(r)
    return np.concatenate(out)


def coarse(M, k):
    """the model at 1/k of its grain (each k-block takes the colour of its topmost voxel), for islands seen
    from afar; its faces' resolution is then M.res / k"""
    from voxel import Model
    sh = np.array(M.m.shape)
    n = -(-sh // k)
    pad = [(0, int(v * k - s_)) for v, s_ in zip(n, sh)]
    m = np.pad(M.m, pad)
    g = np.pad(M.glow, pad)
    lo = M.lo // k
    C = Model(tuple(int(v) for v in lo), tuple(int(v) for v in lo + n), M.mats[1:], res=1)
    C.m = np.zeros(tuple(n), np.uint8)
    C.glow = np.zeros(tuple(n), np.float32)
    for dy in reversed(range(k)):            # the top of each block wins
        for dx in range(k):
            for dz in range(k):
                v = m[dx::k, dy::k, dz::k][:n[0], :n[1], :n[2]]
                put = (C.m == 0) & (v > 0)
                C.m[put] = v[put]
                C.glow[put] = g[dx::k, dy::k, dz::k][:n[0], :n[1], :n[2]][put]
    C.X, C.Y, C.Z = None, None, None
    return C


def decals_of(quads):
    r = np.zeros(len(quads), DECAL_DT)
    for i, q in enumerate(quads):
        r['p'][i] = np.asarray(q.pts, np.float32).reshape(-1)
        c = np.clip(np.asarray(q.color, np.float32), 0, 255)
        r['c'][i] = [c[0], c[1], c[2], np.clip(q.alpha * 255, 0, 255), np.clip(q.lit * 255, 0, 255)]
    return r


def write_scene(out, name, parts):
    """parts: [(part name, res, face records, decal records or None, extra metadata)]"""
    import gzip
    blob, meta = bytearray(), []
    for pname, res, F, D, extra in parts:
        o = F['p'].min(0)
        rel = F['p'] - o
        assert rel.max() < 256, (pname, rel.max(0))
        e = {'name': pname, 'res': res, 'origin': [int(v) for v in o], 'faces': int(len(F)), 'faceAt': len(blob)}
        for col in (rel.astype(np.uint8), F['f'], F['c'], F['n'], F['g']):
            blob += np.ascontiguousarray(col).tobytes()
        while len(blob) % 4:
            blob += b'\0'
        if D is not None and len(D):
            e['decals'] = int(len(D))
            e['decalAt'] = len(blob)
            blob += D.tobytes()
        e.update(extra or {})
        meta.append(e)
    with open(os.path.join(out, name + '.bin.gz'), 'wb') as f:
        f.write(gzip.compress(bytes(blob), 9, mtime=0))
    print(name, len(blob) // 1024, 'KB ->', os.path.getsize(os.path.join(out, name + '.bin.gz')) // 1024, 'KB gzipped',
          [(m['name'], m['faces'], m.get('decals', 0)) for m in meta], flush=True)
    return {'file': name + '.bin.gz', 'parts': meta}


def hero():
    import charrender
    import sleep_cycle as S
    import title_layers as T
    rng = np.random.default_rng(5)
    island = T.island_model(rng)
    front = T.front_model(rng, nest_at=(-30.0, 40.0), lantern_at=(70.0, -4.0))
    P = S.poses(3)
    ch = S.build_pose(3, P['settle'], None, 'petal')
    pal = dict(charrender.get_palette('amber'))
    for k, v in charrender.ACCESSORY.items():
        pal['acc_' + k] = v
    quads = charrender.pattern_quads(ch, pal, 'amber') + charrender.face_quads(ch, pal, 'amber', 'cosy')
    g = ch.anchors.get('ground', (0, 0, 0))
    far = coarse(island, 3)
    return [
        ('island', island.res, faces_of(island, {}), None, {}),
        ('island_far', 1 / 3, faces_of(far, {}), None, {}),
        ('front', front.res, faces_of(front, {}), None, {'lantern': [64.0, 25.5, -4.0], 'egg': [-30.0, 5.4, 40.0]}),
        ('elder', ch.model.res, faces_of(ch.model, pal), decals_of(quads),
         {'at': [2.0, 2.0, -6.0], 'ground': [float(v) for v in g], 'head': [float(v) for v in ch.anchors.get('head', ch.face.center)]}),
    ]


def briar():
    import wilds_foes as WF
    import title_layers as T
    isl = T.island_model(np.random.default_rng(11))
    out = [('thicket', 1 / 2, faces_of(coarse(isl, 2), {}, seed=11), None, {})]
    for v in ('hollow', 'calm'):
        M, anc = WF.briarback(None, v)
        out.append(('briar_' + v, M.res, faces_of(M, {}), None, {'top': list(anc.get('top', (0, 64, 0)))}))
    return out


def main(out):
    os.makedirs(out, exist_ok=True)
    meta = {'hero': write_scene(out, 'hero', hero()), 'briar': write_scene(out, 'briar', briar())}
    with open(os.path.join(out, 'scenes.json'), 'w') as f:
        json.dump(meta, f, indent=1)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'site', 'assets', '3d'))

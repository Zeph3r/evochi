"""The Lumen Wilds walk test: a sunny forest clearing and a few props, from the map camera (walk.py).

    python3 wilds_art.py OUT_DIR [--preview]

The clearing is one voxel slab (grass with colour noise, a dirt path, tufts, flowers, pebbles), the props
are separate sprites so the game can sort them against walkers by their foot point (walk behind the
tree, in front of the rock). Same flat renderer, camera, light and pixel scale as the walk sheets, so
everything lines up: world (x, 0, z) lands at pixel origin + (x, z * sin(pitch)) * scale.

Writes test_ground.webp, prop_<name>.webp and wilds_test.json (sizes, origins, props with their world
spot and footprint radius).
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from scipy import ndimage

from voxel import Model, Camera, Light, Fit, render, model_extent_points
from walk import MAP_PITCH, SCALE

GW, GD = 300, 560           # clearing size in world units (x, z), centred on the origin (fills a phone)
DEPTH = 6                   # the slab's thickness (its front edge shows)


def noise2(shape, scale, seed):
    rng = np.random.default_rng(seed)
    n = rng.random(shape)
    return ndimage.gaussian_filter(n, scale, mode='wrap')


def norm(a):
    return (a - a.min()) / max(a.max() - a.min(), 1e-6)


def no_id_lines(M):
    # colour changes inside the ground or a prop draw no ink; only silhouettes and depth steps do
    return np.ones(256, np.int32)


def ground():
    M = Model((-GW // 2, -DEPTH, -GD // 2), (GW // 2, 4, GD // 2), [], res=1)
    nx, ny, nz = M.m.shape
    top = M.Y < 0
    soil = M.Y < -1.0
    M.set(soil, '#7A5638')
    M.set(soil & (M.Y < -3.5), '#634530')
    # grass with two scales of colour noise
    n1 = norm(noise2((nx, nz), 9, 1))
    n2 = norm(noise2((nx, nz), 2.2, 2))
    g = 0.65 * n1 + 0.35 * n2
    cols = ['#5E9E43', '#69AB49', '#73B54F', '#7EBF57', '#8BC862']
    band = np.clip((g * len(cols)).astype(int), 0, len(cols) - 1)
    grass = top & ~soil
    for i, c in enumerate(cols):
        M.set(grass & (band[:, None, :] == i), c)
    # a winding dirt path from the south edge to the north
    X, Z = M.X[:, 0, :], M.Z[:, 0, :]
    cx = 18 * np.sin(Z / 38.0) - 10
    pw = 11 + 3 * np.sin(Z / 13.0)
    path2 = np.abs(X - cx) < pw
    edge2 = (np.abs(X - cx) < pw + 2.5) & ~path2 & (n2 > 0.45)
    pn = norm(noise2((nx, nz), 1.4, 3))
    M.set(grass & path2[:, None, :], '#C9A877')
    M.set(grass & (path2 & (pn > 0.62))[:, None, :], '#B99467')
    M.set(grass & (path2 & (pn < 0.22))[:, None, :], '#D8BB8C')
    M.set(grass & edge2[:, None, :], '#A8B866')
    rng = np.random.default_rng(11)
    on_grass = ~(path2 | edge2)
    # tufts: little 2-3 voxel blades in clumps
    for _ in range(1300):
        x, z = rng.integers(0, nx), rng.integers(0, nz)
        if not on_grass[x, z]:
            continue
        hgt = rng.integers(1, 3)
        col = ['#4F8E38', '#5E9E43', '#86C25C'][rng.integers(0, 3)]
        j0 = -M.lo[1]
        for dx, dz in ((0, 0), (1, 0), (0, 1)) if rng.random() < 0.5 else ((0, 0),):
            if x + dx < nx and z + dz < nz:
                M.m[x + dx, j0:j0 + hgt, z + dz] = M.mid(col)
    # flowers: a stem voxel and a coloured head
    for _ in range(280):
        x, z = rng.integers(1, nx - 1), rng.integers(1, nz - 1)
        if not on_grass[x, z]:
            continue
        j0 = -M.lo[1]
        M.m[x, j0, z] = M.mid('#4F8E38')
        M.m[x, j0 + 1, z] = M.mid(['#F4E07A', '#F6F1E4', '#E99AC0', '#9FC6F2'][rng.integers(0, 4)])
    # pebbles on and by the path
    for _ in range(200):
        x, z = rng.integers(0, nx - 1), rng.integers(0, nz - 1)
        j0 = -M.lo[1]
        M.m[x, j0, z] = M.mid(['#A9A39A', '#8F8A82', '#C2BDB3'][rng.integers(0, 3)])
    return M


def blob(M, c, r, p=2.2):
    return (np.abs((M.X - c[0]) / r[0]) ** p + np.abs((M.Y - c[1]) / r[1]) ** p + np.abs((M.Z - c[2]) / r[2]) ** p) <= 1


def prop_rock():
    M = Model((-14, 0, -12), (14, 16, 12), [], res=2)
    b = blob(M, (0, 3.5, 0), (11.5, 9.0, 9.5), 2.4) & (M.Y >= 0)
    b |= blob(M, (6, 2.5, 3), (6, 5.5, 6), 2.2) & (M.Y >= 0)
    M.set(b, '#9A958D')
    n = norm(noise2(M.m.shape, 1.5, 5))
    M.set(b & (n > 0.6), '#AEA9A0')
    M.set(b & (n < 0.3), '#857F77')
    sh = b & ~ndimage.binary_erosion(b, iterations=1)
    top = sh & (M.Y > 6.5) & (norm(noise2(M.m.shape, 1.2, 6)) > 0.35)
    M.set(top, '#6FA34C')
    M.set(top & (M.Y > 9.5), '#82B65A')
    return M, 11.0


def prop_stump():
    M = Model((-10, 0, -10), (10, 10, 10), [], res=2)
    r = np.hypot(M.X, M.Z)
    trunk = (r < 6.5) & (M.Y < 7.0)
    roots = (M.Y < 1.6) & ((np.abs(M.X) < 1.4) | (np.abs(M.Z) < 1.4)) & (r < 9.0)
    M.set(trunk | roots, '#7B5435')
    M.set((trunk | roots) & (np.floor(np.arctan2(M.Z, M.X) * 6) % 2 == 0) & (r > 5.5), '#6A462B')
    topf = trunk & (M.Y > 6.5)
    M.set(topf, '#D8B985')
    M.set(topf & ((np.floor(r * 1.3) % 2) == 0), '#C29E6C')
    M.set(topf & (r > 5.6), '#8C6440')
    moss = (trunk & (M.Y < 3.0) & (M.Z > 3.0) & (norm(noise2(M.m.shape, 1.0, 9)) > 0.5))
    M.set(moss, '#6FA34C')
    return M, 7.0


def prop_bush():
    M = Model((-12, 0, -11), (12, 16, 11), [], res=2)
    b = (blob(M, (0, 6.5, 0), (10, 7, 9)) | blob(M, (-5, 4.5, 3), (6, 4.5, 6)) | blob(M, (5.5, 5, -2), (6, 5, 6))) & (M.Y >= 0)
    n = norm(noise2(M.m.shape, 1.3, 13))
    M.set(b, '#4E8F3A')
    M.set(b & (n > 0.55), '#5FA046')
    M.set(b & (n > 0.75) & (M.Y > 8), '#78B856')
    sh = b & ~ndimage.binary_erosion(b, iterations=1)
    rng = np.random.default_rng(4)
    pts = np.argwhere(sh & (M.Y > 4))
    for i in rng.choice(len(pts), 22, replace=False):
        x, y, z = pts[i]
        M.m[x, y, z] = M.mid('#D9453B')
    return M, 9.5


def prop_tree():
    M = Model((-22, 0, -20), (22, 62, 20), [], res=1)
    r = np.hypot(M.X, M.Z)
    trunk = (r < 3.6 + np.maximum(0, 3 - M.Y) * 0.8) & (M.Y < 34)
    M.set(trunk, '#7B5435')
    M.set(trunk & (np.floor(np.arctan2(M.Z, M.X) * 4) % 2 == 0), '#6A462B')
    can = (blob(M, (0, 40, 0), (18, 13, 16)) | blob(M, (-9, 34, 4), (10, 8, 9)) | blob(M, (9, 35, -3), (10, 8, 9))
           | blob(M, (1, 49, -1), (11, 8, 10)))
    n = norm(noise2(M.m.shape, 1.6, 21))
    M.set(can, '#3F7E33')
    M.set(can & (n > 0.5), '#4C8E3B')
    M.set(can & (n > 0.7) & (M.Y > 40), '#64A64A')
    return M, 5.0


def _ring():
    """trees round the clearing (its walls), a few inside, and rocks, stumps and bushes"""
    rng = np.random.default_rng(31)
    trees = []
    for x in np.arange(-GW / 2 + 14, GW / 2 - 6, 40):
        trees.append((float(x + rng.uniform(-6, 6)), float(-GD / 2 + 12 + rng.uniform(-4, 6))))
    for z in np.arange(-GD / 2 + 60, GD / 2 - 30, 62):
        trees.append((float(-GW / 2 + 12 + rng.uniform(-3, 5)), float(z + rng.uniform(-8, 8))))
        trees.append((float(GW / 2 - 12 - rng.uniform(-3, 5)), float(z + rng.uniform(-8, 8))))
    trees += [(-80, -120), (92, -40), (-96, 140)]
    return {
        'tree': (prop_tree, trees),
        'rock': (prop_rock, [(64, 70), (-62, -30), (40, -170)]),
        'stump': (prop_stump, [(-58, 84), (88, 190)]),
        'bush': (prop_bush, [(34, -110), (-100, 30), (100, 120), (-40, 210), (70, -230)]),
    }


PROPS = _ring()


def main(out, preview=False):
    os.makedirs(out, exist_ok=True)
    cam = Camera(yaw=0, pitch=MAP_PITCH)
    light = Light()
    light.smooth = 0.5
    meta = {'pitch': MAP_PITCH, 'scale': SCALE, 'props': [], 'images': {}}
    G = ground()
    sx, sy, _ = cam.project(model_extent_points(G))
    pad = 4
    w = int(math.ceil((sx.max() - sx.min()) * SCALE)) + 2 * pad
    h = int(math.ceil((sy.max() - sy.min()) * SCALE)) + 2 * pad
    fit = Fit(SCALE, pad - sx.min() * SCALE, pad - sy.min() * SCALE, w, h)
    o = render(G, {}, cam, w, h, fit=fit, light=light, ss=2, outline_px=1.5, id_edges=no_id_lines(G),
               inner_thresh=3.0, inner_alpha=0.35, inner_px=0.8)
    from PIL import Image
    img = Image.fromarray(o.rgba)
    img.save(os.path.join(out, 'test_ground.webp'), quality=86, method=6)
    if preview:
        img.save(os.path.join(out, 'test_ground.png'))
    meta['ground'] = {'image': 'test_ground.webp', 'w': w, 'h': h, 'origin': [round(fit.ox, 1), round(fit.oy, 1)],
                      'world': [-GW / 2, -GD / 2, GW / 2, GD / 2]}
    print('ground', w, h, flush=True)
    for name, (fn, spots) in PROPS.items():
        M, rad = fn()
        sx, sy, _ = cam.project(model_extent_points(M))
        pw = int(math.ceil((sx.max() - sx.min()) * SCALE)) + 2 * pad
        ph = int(math.ceil((sy.max() - sy.min()) * SCALE)) + 2 * pad
        pf = Fit(SCALE, pad - sx.min() * SCALE, pad - sy.min() * SCALE, pw, ph)
        po = render(M, {}, cam, pw, ph, fit=pf, light=light, ss=3, outline_px=1.5, outline_col='#3B2923',
                    id_edges=no_id_lines(M), inner_thresh=2.5, inner_alpha=0.5, inner_px=0.8)
        Image.fromarray(po.rgba).save(os.path.join(out, f'prop_{name}.webp'), quality=88, method=6)
        meta['images'][name] = {'image': f'prop_{name}.webp', 'w': pw, 'h': ph, 'anchor': [round(pf.ox, 1), round(pf.oy, 1)], 'radius': rad}
        for (x, z) in spots:
            meta['props'].append({'kind': name, 'x': x, 'z': z})
        print('prop', name, pw, ph, flush=True)
    json.dump(meta, open(os.path.join(out, 'wilds_test.json'), 'w'), indent=1)
    if preview:
        # the clearing with its props, sorted by depth
        comp = img.copy()
        for p in sorted(meta['props'], key=lambda p: p['z']):
            im = meta['images'][p['kind']]
            spr = Image.open(os.path.join(out, im['image']))
            gx = fit.ox + p['x'] * SCALE
            gy = fit.oy + p['z'] * math.sin(math.radians(MAP_PITCH)) * SCALE
            comp.alpha_composite(spr, (int(gx - im['anchor'][0]), int(gy - im['anchor'][1])))
        comp.save(os.path.join(out, 'preview.png'))


if __name__ == '__main__':
    main(sys.argv[1], '--preview' in sys.argv)

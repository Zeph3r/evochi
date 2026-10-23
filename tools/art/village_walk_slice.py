"""The walkable village's first playable piece: the plaza, the bridge and the Trail Guild, packed for
the game (flutter/lib/features/village/village_walk.dart).

    python3 village_walk.py OUT --view slice            # the picture (Blender)
    python3 village_walk.py OUT --view slice --depth    # each pixel's world z
    python3 village_walk_slice.py OUT                   # -> the game's assets

Writes
  flutter/assets/art/village/walk_slice.webp        the picture (the walking camera, 45.8 px a unit)
  flutter/assets/art/village/walk_slice_depth.png   world z of what each pixel shows, 16 bits in R (high)
                                                    and G (low) over DEPTH_RANGE, and B 255 where it stands
                                                    up off the ground: whatever stands nearer the camera
                                                    than a character's feet is drawn over it
  flutter/assets/config/village_walk.json           the camera, the walk grid (0.5 unit cells), where the
                                                    villagers stand, where you start
and bakes the picture's living-scene mask (fx_zones/village_walk_slice.py).
"""
import json
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

import village_walk as V

HERE = os.path.dirname(os.path.abspath(__file__))
FLUTTER = os.path.join(HERE, '..', '..', 'flutter')
CELL = 0.5
AREA = (-20.0, 20.0, -40.0, 16.0)              # x0, x1, z0, z1 of the grid
PET_R = 0.9                                    # how close your Evochi's middle comes to anything solid
NPCS = {'pip': (-4.5, -31.0), 'alder': (4.6, -31.0)}
SPAWN = (0.0, 8.0)


def walk_grid(vs):
    """1 where your Evochi may stand. Anything solid from knee to head height blocks (walls, trunks,
    posts, benches, fences, bushes, the Waystone); so does open water. Canopies are above it."""
    x0, x1, z0, z1 = AREA
    xs = np.arange(x0, x1, CELL) + CELL / 2
    zs = np.arange(z0, z1, CELL) + CELL / 2
    X, Z = np.meshgrid(xs, zs, indexing='ij')
    block = np.zeros(X.shape, bool)
    top = np.full(X.shape, -9.0)
    wet = np.zeros(X.shape, bool)
    water = set(V.WATERC)
    for item in vs.models:
        M = item[0]
        r = M.res
        ix = np.floor(X * r).astype(int) - M.lo[0]
        iz = np.floor(Z * r).astype(int) - M.lo[2]
        ok = (ix >= 0) & (ix < M.m.shape[0]) & (iz >= 0) & (iz < M.m.shape[2])
        if not ok.any():
            continue
        ys = (M.lo[1] + np.arange(M.m.shape[1]) + 0.5) / r
        cols = M.m[np.clip(ix, 0, M.m.shape[0] - 1), :, np.clip(iz, 0, M.m.shape[2] - 1)]   # (nx, nz, ny)
        cols = np.where(ok[..., None], cols, 0)
        solid = cols > 0
        block |= (solid & (ys >= 0.9) & (ys < 3.5)).any(-1)
        low = solid & (ys < 0.9)
        has = low.any(-1)
        k = np.where(has, low.shape[-1] - 1 - np.argmax(low[..., ::-1], -1), 0)
        ty = np.where(has, ys[k], -9.0)
        mat = np.take_along_axis(cols, k[..., None], -1)[..., 0]
        names = np.array(M.mats + [''] * (256 - len(M.mats)))
        is_w = np.isin(names[mat], list(water)) & has
        newer = ty > top
        wet = np.where(newer, is_w, wet | (is_w & (ty == top)))
        top = np.maximum(top, ty)
    for (nx, nz) in NPCS.values():
        block |= (X - nx) ** 2 + (Z - nz) ** 2 < 1.4 ** 2
    solid = block | wet | (top < -5)
    # your Evochi's middle keeps PET_R clear of anything solid
    dist = ndimage.distance_transform_edt(~solid) * CELL
    walk = dist > PET_R
    # only the piece that joins up with where you start
    lab, _ = ndimage.label(walk)
    sx, sz = int((SPAWN[0] - x0) / CELL), int((SPAWN[1] - z0) / CELL)
    walk &= lab == lab[sx, sz]
    return walk, solid


def pack_depth(npy, out_png):
    d = np.load(npy)
    z, a, y = d[..., 0], d[..., 1], d[..., 2]
    z0, z1 = V.DEPTH_RANGE
    q = np.clip((z - z0) / (z1 - z0), 0, 1)
    q = np.where(a > 0.5, q, 0.0)
    v = np.round(q * 65535).astype(np.uint32)
    # B: 255 where the surface stands up off the ground (walls, trunks, posts, rails, bushes); only those
    # are drawn over a character, so its feet are never cut by the path in front of them
    tall = ((y > 0.7) & (a > 0.5)).astype(np.uint8) * 255
    rgb = np.dstack([(v >> 8).astype(np.uint8), (v & 255).astype(np.uint8), tall])
    Image.fromarray(rgb, 'RGB').save(out_png, optimize=True)


def main():
    src = sys.argv[1]
    (cx, cz), width, (w, h) = V.VIEWS['slice']
    vs = V.scene_village_walk('day_dim')
    walk, solid = walk_grid(vs)
    art = os.path.join(FLUTTER, 'assets', 'art', 'village')
    Image.open(os.path.join(src, 'village_walk_slice.png')).convert('RGB').save(os.path.join(art, 'walk_slice.webp'), quality=90, method=6)
    pack_depth(os.path.join(src, 'village_walk_slice_depth.npy'), os.path.join(art, 'walk_slice_depth.png'))
    x0, x1, z0, z1 = AREA
    rows = [''.join('1' if walk[i, j] else '0' for i in range(walk.shape[0])) for j in range(walk.shape[1])]
    lay = {
        'image': 'assets/art/village/walk_slice.webp',
        'depth': 'assets/art/village/walk_slice_depth.png',
        'w': w, 'h': h, 'ppu': w / width, 'centre': [cx, cz], 'pitch': V.PITCH,
        'depthRange': list(V.DEPTH_RANGE),
        'grid': {'x0': x0, 'z0': z0, 'cell': CELL, 'cols': walk.shape[0], 'rows': walk.shape[1], 'walk': rows},
        'npcs': [{'id': k, 'x': v[0], 'z': v[1], 'place': 'lodge'} for k, v in NPCS.items()],
        'spawn': list(SPAWN),
        'spots': {'guild': [0.0, -29.0], 'waystone': [0.0, 4.8], 'bridge': [0.0, -26.0]},
        'sun': [0.42, -0.78, -0.48],
    }
    with open(os.path.join(FLUTTER, 'assets', 'config', 'village_walk.json'), 'w') as f:
        json.dump(lay, f, indent=1)
    # the living-scene mask
    subprocess.run([sys.executable, os.path.join(HERE, 'scene_fx.py'), 'village/walk_slice.webp'], check=True)
    # a picture of the walk grid over the slice, for checking
    im = Image.open(os.path.join(src, 'village_walk_slice.png')).convert('RGBA')
    ov = Image.new('RGBA', im.size, (0, 0, 0, 0))
    px = ov.load()
    ppu = w / width
    s35, c35 = math.sin(math.radians(V.PITCH)), math.cos(math.radians(V.PITCH))
    for i in range(walk.shape[0]):
        for j in range(walk.shape[1]):
            x, z = x0 + (i + 0.5) * CELL, z0 + (j + 0.5) * CELL
            u, v = w / 2 + (x - cx) * ppu, h / 2 + (z - cz) * s35 * ppu
            if 0 <= u < w and 0 <= v < h:
                col = (60, 220, 90, 110) if walk[i, j] else ((230, 60, 60, 110) if solid[i, j] else None)
                if col:
                    for du in range(-3, 4):
                        for dv in range(-2, 3):
                            if 0 <= u + du < w and 0 <= v + dv < h:
                                px[int(u + du), int(v + dv)] = col
    im.alpha_composite(ov)
    im.convert('RGB').resize((w // 2, h // 2)).save(os.path.join(src, 'walk_grid_check.jpg'), quality=85)
    print('walkable cells', int(walk.sum()), 'of', walk.size)


if __name__ == '__main__':
    main()

"""The walkable Sunlit Village, packed for the game (flutter/lib/features/village/village_walk.dart).

    python3 village_walk.py OUT --view full --depth     # each pixel's world z and height (Blender)
    python3 village_walk.py OUT --view full             # the picture (Blender, about an hour)
    python3 village_walk_pack.py OUT                    # -> the game's assets

The picture is the whole village at the walking camera's detail (45.8 px a unit, 6046 x 4992), too big
for one texture on a phone, so it ships in 1024 px tiles (each with 8 px of its neighbours round it, so
the motion can reach across a seam), three images a tile:

  flutter/assets/art/village/walk/t_I_J.webp   the picture
  flutter/assets/art/village/walk/m_I_J.webp   its living-scene mask (scene_fx.py's channels)
  flutter/assets/art/village/walk/d_I_J.png    world z of what each pixel shows, 16 bits in R (high) and
                                               G (low) over DEPTH_RANGE, and B 255 where it stands up off
                                               what you walk on there: whatever stands nearer the camera
                                               than a character's feet is drawn over it
  flutter/assets/config/village_walk.json      the camera, the tiles, the emitters, the walk grid (0.5
                                               unit cells, with the height you stand at), where the
                                               villagers stand, where you arrive, the ways out
"""
import json
import math
import os
import shutil
import sys
import tempfile

import numpy as np
from PIL import Image
from scipy import ndimage

import village_walk as V

HERE = os.path.dirname(os.path.abspath(__file__))
FLUTTER = os.path.join(HERE, '..', '..', 'flutter')
VIEW = 'full'
CELL = 0.5
AREA = (-66.0, 66.0, -60.0, 60.0)              # x0, x1, z0, z1 of the grid
PET_R = 1.4                                    # how close your Evochi's middle comes to anything solid (its body is ~3 long)
NPC_R = 1.4
NPCS = {  # id: (x, z, the place their conversation opens in)
    # Pip and Alder wait at the foot of the Guild's bridge (in front of its door they'd close the only way
    # round the Guild, which stands close to the stream)
    'pip': (-4.6, -20.2, 'lodge'),
    'alder': (4.8, -20.4, 'lodge'),
    'bram': (24.4, -1.2, 'workshop'),
    'mira': (-25.4, 5.6, 'glasshouse'),
}
SPAWN = (0.0, 45.0)                            # in through the south gate, from the road home
SPOTS = {'waystone': (0.0, 6.0), 'gate': (0.0, 47.0), 'trail': (60.0, 5.2), 'falls': (-15.0, -50.0)}
EXITS = {  # walk into one and you leave: home down the road, east along the Old Trail
    'home': (0.0, 55.0, 4.0),
    'trail': (63.0, 4.6, 3.0),
}
TILE, PAD = 1024, 8


def walk_grid(vs):
    """1 where your Evochi may stand. Anything solid from knee to head height blocks (walls, trunks,
    posts, benches, fences, bushes, the Waystone, the far hills' first step); so does open water.
    Canopies are above it. Also the height of what you stand on (the bridge's deck is a unit up)."""
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
    for (nx, nz, _) in NPCS.values():
        block |= (X - nx) ** 2 + (Z - nz) ** 2 < NPC_R ** 2
    solid = block | wet | (top < -5)
    surface = np.clip(np.where(top < -5, 0.0, top + 0.5 / 2), 0.0, 2.0)
    dist = ndimage.distance_transform_edt(~solid) * CELL
    walk = dist > PET_R
    lab, _ = ndimage.label(walk)
    sx, sz = int((SPAWN[0] - x0) / CELL), int((SPAWN[1] - z0) / CELL)
    assert walk[sx, sz], 'you arrive somewhere you cannot stand'
    walk &= lab == lab[sx, sz]
    return walk, solid, surface


def depth_rgb(npy, surface, w, h, width, cx):
    d = np.load(npy, mmap_mode='r')
    z, a, y = np.asarray(d[..., 0]), np.asarray(d[..., 1]), np.asarray(d[..., 2])
    x = cx + (np.arange(w) + 0.5 - w / 2) / (w / width)
    gx0, _, gz0, _ = AREA
    ci = np.floor((x - gx0) / CELL).astype(int)
    base = np.zeros_like(y)
    for r0 in range(0, h, 512):                      # in bands: the whole picture at once is a lot
        zz = z[r0:r0 + 512]
        rj = np.floor((zz - gz0) / CELL).astype(int)
        ok = (ci[None, :] >= 0) & (ci[None, :] < surface.shape[0]) & (rj >= 0) & (rj < surface.shape[1])
        base[r0:r0 + 512] = np.where(ok, surface[np.clip(ci, 0, surface.shape[0] - 1)[None, :].repeat(len(zz), 0),
                                                 np.clip(rj, 0, surface.shape[1] - 1)], 0.0)
    z0, z1 = V.DEPTH_RANGE
    q = np.where(a > 0.5, np.clip((z - z0) / (z1 - z0), 0, 1), 0.0)
    v = np.round(q * 65535).astype(np.uint32)
    tall = ((y > base + 0.7) & (a > 0.5)).astype(np.uint8) * 255
    return np.dstack([(v >> 8).astype(np.uint8), (v & 255).astype(np.uint8), tall])


def bake_mask(picture_png, w, h):
    """The living-scene mask of the whole picture (fx_village_walk.zones for this view, through
    scene_fx.bake), and its emitters."""
    import importlib.util
    import scene_fx as SF
    spec_ = importlib.util.spec_from_file_location('fx_village_walk', os.path.join(HERE, 'village_mock', 'fx_village_walk.py'))
    fxm = importlib.util.module_from_spec(spec_)
    spec_.loader.exec_module(fxm)
    spec = fxm.zones(VIEW)
    tmp = tempfile.mkdtemp(prefix='walkfx_')
    os.makedirs(os.path.join(tmp, 'village'), exist_ok=True)
    os.makedirs(os.path.join(tmp, 'fx'), exist_ok=True)
    shutil.copy(picture_png, os.path.join(tmp, 'village', 'walk_village.png'))
    art0, out0 = SF.ART, SF.OUT_DIR
    SF.ART, SF.OUT_DIR = tmp, os.path.join(tmp, 'fx')
    try:
        d, _, mask = SF.bake('village/walk_village.png', spec)
    finally:
        SF.ART, SF.OUT_DIR = art0, out0
        shutil.rmtree(tmp, ignore_errors=True)
    return mask, d['emit']


def tiles(picture, mask, depth, out_dir):
    """Cut the three layers into tiles, each with PAD px of its neighbours round it."""
    h, w = picture.shape[:2]
    os.makedirs(out_dir, exist_ok=True)
    for f in os.listdir(out_dir):
        os.remove(os.path.join(out_dir, f))
    meta = []
    for j in range(math.ceil(h / TILE)):
        for i in range(math.ceil(w / TILE)):
            cx0, cy0 = i * TILE, j * TILE
            cx1, cy1 = min(w, cx0 + TILE), min(h, cy0 + TILE)
            x0, y0 = max(0, cx0 - PAD), max(0, cy0 - PAD)
            x1, y1 = min(w, cx1 + PAD), min(h, cy1 + PAD)
            Image.fromarray(picture[y0:y1, x0:x1]).save(os.path.join(out_dir, f't_{i}_{j}.webp'), quality=90, method=6)
            Image.fromarray(mask[y0:y1, x0:x1]).save(os.path.join(out_dir, f'm_{i}_{j}.webp'), 'WEBP', lossless=True, quality=100, method=6)
            Image.fromarray(depth[y0:y1, x0:x1]).save(os.path.join(out_dir, f'd_{i}_{j}.png'), optimize=True)
            meta.append({'i': i, 'j': j, 'x': x0, 'y': y0, 'w': x1 - x0, 'h': y1 - y0, 'core': [cx0, cy0, cx1 - cx0, cy1 - cy0]})
    return meta


def main():
    src = sys.argv[1]
    (cx, cz), width, (w, h) = V.VIEWS[VIEW]
    vs = V.scene_village_walk('day_dim')
    walk, solid, surface = walk_grid(vs)
    print('walkable cells', int(walk.sum()), 'of', walk.size, flush=True)
    png = os.path.join(src, f'village_walk_{VIEW}.png')
    picture = np.asarray(Image.open(png).convert('RGB'))
    mask, emit = bake_mask(png, w, h)
    depth = depth_rgb(os.path.join(src, f'village_walk_{VIEW}_depth.npy'), surface, w, h, width, cx)
    tmeta = tiles(picture, mask, depth, os.path.join(FLUTTER, 'assets', 'art', 'village', 'walk'))
    x0, x1, z0, z1 = AREA
    lay = {
        'w': w, 'h': h, 'ppu': w / width, 'centre': [cx, cz], 'pitch': V.PITCH,
        'depthRange': list(V.DEPTH_RANGE),
        'tiles': {'dir': 'assets/art/village/walk/', 'size': TILE, 'pad': PAD, 'list': tmeta},
        'emit': emit,
        'grid': {'x0': x0, 'z0': z0, 'cell': CELL, 'cols': walk.shape[0], 'rows': walk.shape[1],
                 'walk': [''.join('1' if walk[i, j] else '0' for i in range(walk.shape[0])) for j in range(walk.shape[1])],
                 # the height you stand at, in quarter units ('0'-'8')
                 'height': [''.join(str(int(round(min(surface[i, j], 2.0) * 4))) for i in range(walk.shape[0])) for j in range(walk.shape[1])]},
        'npcs': [{'id': k, 'x': v[0], 'z': v[1], 'place': v[2]} for k, v in NPCS.items()],
        'spawn': list(SPAWN),
        'spots': {k: list(v) for k, v in SPOTS.items()},
        'exits': {k: list(v) for k, v in EXITS.items()},
        'sun': [0.42, -0.78, -0.48],
    }
    with open(os.path.join(FLUTTER, 'assets', 'config', 'village_walk.json'), 'w') as f:
        json.dump(lay, f, separators=(',', ':'))
    # checks: the walk grid over the picture (half size), and that every spot and exit can be reached
    for name, (sx, sz, *_) in [*SPOTS.items(), *[(k, v) for k, v in EXITS.items()], *[(k, (v[0], v[1] + 2.3)) for k, v in NPCS.items()]]:
        i, j = int((sx - x0) / CELL), int((sz - z0) / CELL)
        near = walk[max(0, i - 6):i + 7, max(0, j - 6):j + 7].any()
        print(f'{name:9s} ({sx:6.1f}, {sz:6.1f}) reachable nearby: {near}')
    small = Image.fromarray(picture).resize((w // 4, h // 4))
    ov = Image.new('RGBA', small.size, (0, 0, 0, 0))
    px = ov.load()
    s35 = math.sin(math.radians(V.PITCH))
    ppu = w / width / 4
    for i in range(0, walk.shape[0]):
        for j in range(0, walk.shape[1]):
            if not walk[i, j]:
                continue
            x, z = x0 + (i + 0.5) * CELL, z0 + (j + 0.5) * CELL
            u = w / 8 + (x - cx) * ppu
            v = h / 8 + ((z - cz) * s35 - surface[i, j] * math.cos(math.radians(V.PITCH))) * ppu
            if 0 <= u < small.width and 0 <= v < small.height:
                px[int(u), int(v)] = (40, 240, 90, 200)
    small = small.convert('RGBA')
    small.alpha_composite(ov)
    small.convert('RGB').save(os.path.join(src, 'walk_full_grid.jpg'), quality=85)


if __name__ == '__main__':
    main()

"""The Deep Wilds' room kit: pieces of forest floor the game stitches into a new floor every time.

Each piece (a "chunk") is a CHUNK x CHUNK square of ground: a clearing (a room) or a narrow way (a hall)
with dirt paths out to the doorways it opens on (any of N, E, S, W). The game lays chunks side by side
on a grid and grows the forest over everything that is not a room or a path, so a floor can be any shape.

Seamless anywhere: every chunk shares one forest-floor pattern that repeats exactly every CHUNK units
(the noise is generated on a torus), and a band round each chunk's border is left to that pattern alone,
so two chunks always meet without a seam. The paths cross the border only at the middle of a side,
straight and the same width, so a path running into a doorway always meets the one on the other side.

The ground is voxels like the Thicket's (grass, leaf litter and moss, dirt paths, tufts, ferns, flowers,
pebbles), lit in Blender by the same sun and camera, so the Deep Wilds look like the Thicket.

    python3 wilds_kit.py OUT_DIR --only=blend     the slab with every chunk laid out (a Python with bpy);
                                                  render it on a GPU machine (render_gpu.py) to
                                                  OUT_DIR/work/kit_ground.png
    python3 wilds_kit.py OUT_DIR --only=cut       cut the chunks out of the render; write the json
    python3 wilds_kit.py OUT_DIR --only=preview   flat top colours instead of a render (no Blender; for
                                                  trying the generator before the real art exists)

A plain 'fill' chunk (no clearing, no way through) covers the cells round a floor.

Writes kit_<chunk>.webp and wilds_kit.json: the chunk size, the scale and pitch, and per chunk its
doorways, its clearing (a polygon) and its paths (polylines), in the chunk's own units (0..CHUNK), so the
game knows where it can walk and where the trees may grow.
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from voxel import Model                                          # noqa: E402
from walk import MAP_PITCH                                       # noqa: E402
import wilds_maps as WM                                          # noqa: E402

CHUNK = 160
GAP = 24                     # between chunks on the render slab (cut away)
EDGE = 10                    # the border band left to the shared pattern
COLS = 6
SCALE = WM.GROUND_SCALE
N, E, S, W = 1, 2, 4, 8
DOORS = {N: (CHUNK / 2, 0.0), E: (float(CHUNK), CHUNK / 2), S: (CHUNK / 2, float(CHUNK)), W: (0.0, CHUNK / 2)}
PATH_W = 11.0                # the dirt path's width (the walkable lane is wider: the game decides)


def chunk_list():
    """every doorway combination, as a room and as a hall"""
    out = [{'id': 'fill', 'kind': 'fill', 'mask': 0, 'seed': 99}]          # plain forest floor, no way through
    for mask in range(1, 16):
        for kind in ('room', 'hall'):
            out.append({'id': f'{kind}_{mask:02d}', 'kind': kind, 'mask': mask, 'seed': mask * 7 + (0 if kind == 'room' else 3)})
    return out


# ------------------------------------------------------------------ the shared pattern (periodic)
def torus_noise(scale, seed):
    rng = np.random.default_rng(seed)
    a = ndimage.gaussian_filter(rng.random((CHUNK, CHUNK)), scale, mode='wrap')
    return (a - a.min()) / max(a.max() - a.min(), 1e-9)


# ------------------------------------------------------------------ one chunk's plan (local units)
def plan_chunk(c):
    rng = np.random.default_rng(c['seed'])
    u, v = np.meshgrid(np.arange(CHUNK) + 0.5, np.arange(CHUNK) + 0.5, indexing='ij')
    cx = cy = CHUNK / 2
    # the clearing: a wobbly disc (a room's is big; a hall's is a small widening where the paths meet)
    r0 = {'room': rng.uniform(50, 58), 'hall': rng.uniform(16, 22)}.get(c['kind'], 0.0)
    ph = rng.uniform(0, 2 * math.pi, 3)
    ang = np.linspace(0, 2 * math.pi, 48, endpoint=False)
    rad = r0 * (1 + 0.09 * np.sin(3 * ang + ph[0]) + 0.06 * np.sin(5 * ang + ph[1]) + 0.04 * np.sin(2 * ang + ph[2]))
    poly = [(round(float(cx + math.cos(a) * r), 1), round(float(cy + math.sin(a) * r), 1)) for a, r in zip(ang, rad)] if r0 > 0 else []
    th = np.arctan2(v - cy, u - cx) % (2 * math.pi)
    rr = np.interp(th, np.append(ang, 2 * math.pi), np.append(rad, rad[0]))
    clear = ((u - cx) ** 2 + (v - cy) ** 2 < rr ** 2) & (r0 > 0)
    # the paths: from the middle out to each doorway, wandering a little in between and dead straight
    # for the last stretch, so they meet the next chunk's path exactly
    paths = []
    path = np.zeros((CHUNK, CHUNK), bool)
    for d, (dx, dy) in DOORS.items():
        if not c['mask'] & d:
            continue
        ex, ey = dx - cx, dy - cy
        L = math.hypot(ex, ey)
        nx, ny = -ey / L, ex / L
        bend = rng.uniform(-9, 9) if c['kind'] == 'room' else rng.uniform(-5, 5)
        pts = []
        for t in np.linspace(0, 1, 14):
            off = bend * math.sin(math.pi * min(t / 0.7, 1.0)) if t < 0.7 else 0.0
            pts.append((cx + ex * t + nx * off, cy + ey * t + ny * off))
        # past the edge a little, so the stroke reaches it squarely
        pts.append((dx + ex / L * 3, dy + ey / L * 3))
        paths.append([(round(float(x), 1), round(float(y), 1)) for x, y in pts])
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            seg = np.array([x1 - x0, y1 - y0])
            l2 = max(seg @ seg, 1e-9)
            t = np.clip(((u - x0) * seg[0] + (v - y0) * seg[1]) / l2, 0, 1)
            d2 = (u - x0 - t * seg[0]) ** 2 + (v - y0 - t * seg[1]) ** 2
            path |= d2 < (PATH_W / 2) ** 2
    if not paths and c['kind'] != 'fill':
        path |= (u - cx) ** 2 + (v - cy) ** 2 < 6 ** 2
    # the border band is the shared pattern's alone (bar the paths through the doorways)
    border = (u < EDGE) | (v < EDGE) | (u > CHUNK - EDGE) | (v > CHUNK - EDGE)
    clear &= ~border
    return {'clear': clear, 'path': path, 'border': border, 'poly': poly, 'paths': paths, 'r': round(float(r0), 1)}


def layout():
    cs = chunk_list()
    rows = (len(cs) + COLS - 1) // COLS
    X0 = 0
    Z0 = 0
    X1 = COLS * (CHUNK + GAP) + GAP
    Z1 = rows * (CHUNK + GAP) + GAP
    for i, c in enumerate(cs):
        r, k = divmod(i, COLS)
        c['x0'] = GAP + k * (CHUNK + GAP)
        c['z0'] = GAP + r * (CHUNK + GAP)
    return cs, (X0, X1, Z0, Z1)


# ------------------------------------------------------------------ the voxels
def build(cs, bounds):
    X0, X1, Z0, Z1 = bounds
    W, D = X1 - X0, Z1 - Z0
    M = Model((X0, -6, Z0), (X1, 6, Z1), [], res=1)
    j0 = -M.lo[1]
    rng = np.random.default_rng(2026)
    M.m[:, :j0 - 1, :] = M.mid(WM.SOIL[0])
    # the shared pattern: the same CHUNK-periodic fields pasted into every chunk at its own origin, so all
    # of them agree at their borders (the gaps between them on the slab are cut away)
    loc = {'g1': torus_noise(9, 1), 'g2': torus_noise(2.2, 2), 'gl': torus_noise(5, 11), 'gm': torus_noise(3, 12),
           'pn': torus_noise(1.4, 4), 'lk': torus_noise(0.6, 21)}
    fields = {k: np.zeros((W, D), np.float32) for k in loc}
    for c in cs:
        sl = (slice(c['x0'] - X0, c['x0'] - X0 + CHUNK), slice(c['z0'] - Z0, c['z0'] - Z0 + CHUNK))
        for k, a in loc.items():
            fields[k][sl] = a
    g1, g2, gl, gm, pn = fields['g1'], fields['g2'], fields['gl'], fields['gm'], fields['pn']
    g = 0.65 * g1 + 0.35 * g2
    grass_band = np.clip((g * len(WM.GRASS)).astype(int), 0, len(WM.GRASS) - 1)
    clear = np.zeros((W, D), bool)
    path = np.zeros((W, D), bool)
    inner = np.zeros((W, D), bool)               # inside a chunk, off its border band
    for c in cs:
        p = c['plan']
        sl = (slice(c['x0'] - X0, c['x0'] - X0 + CHUNK), slice(c['z0'] - Z0, c['z0'] - Z0 + CHUNK))
        clear[sl] |= p['clear']
        path[sl] |= p['path']
        inner[sl] |= ~p['border']
    # the forest floor everywhere: leaf litter and moss, with patches of grass where the light gets in
    lid = np.array([M.mid(col) for col in WM.LITTER], np.uint8)
    mid_ = np.array([M.mid(col) for col in WM.MOSS_FLOOR], np.uint8)
    gid = np.array([M.mid(col) for col in WM.GRASS], np.uint8)
    lk = (fields['lk'] * len(WM.LITTER) * 0.999).astype(int)
    mossy = gm > 0.58
    sunlit = gl > 0.62
    top = np.where(mossy, mid_[lk % 2], lid[lk])
    top = np.where(sunlit, gid[grass_band], top)
    # the clearings are grass, fraying into the litter at their edge
    soft = ndimage.binary_dilation(clear, iterations=3) & (gl > 0.35) & inner
    top = np.where(clear | soft, gid[grass_band], top)
    # the paths: dirt, with a fringe of rough grass
    pid = np.array([M.mid(col) for col in WM.PATH], np.uint8)
    pk = np.clip((pn * 3).astype(int), 0, 2)
    top = np.where(path, pid[pk], top)
    edge = ndimage.binary_dilation(path, iterations=2) & ~path & (g2 > 0.4) & inner
    top = np.where(edge, M.mid('#6F7E40'), top)
    M.m[:, j0 - 1, :] = top
    # small things standing up: tufts in the grass, leaves on the litter, flowers in the clearings, pebbles
    # on the paths (never in the border band: they would poke over the next chunk)
    ok = inner & ~path
    grassy = np.isin(top, gid)
    for (i, k) in np.argwhere(ok & grassy & (rng.random((W, D)) < 0.016)):
        M.m[i, j0:j0 + rng.integers(1, 3), k] = M.mid(['#3F6E2C', '#4A7A33', '#5C8A3C'][rng.integers(0, 3)])
    for (i, k) in np.argwhere(ok & ~grassy & (rng.random((W, D)) < 0.05)):
        M.m[i, j0, k] = M.mid(['#8A5A2C', '#A0682E', '#7A6A34', '#9C7A3A', '#6E4A2A'][rng.integers(0, 5)])
    for (i, k) in np.argwhere(ok & clear & (rng.random((W, D)) < 0.006)):
        M.m[i, j0, k] = M.mid('#3F6E2C')
        M.m[i, j0 + 1, k] = M.mid(['#F0DC7A', '#EDE6D6', '#D998B8', '#9DB8E2'][rng.integers(0, 4)])
    for (i, k) in np.argwhere(inner & path & (rng.random((W, D)) < 0.006)):
        M.m[i, j0, k] = M.mid(WM.STONE[rng.integers(0, 3)])
    # ferns on the forest floor, away from the paths and the clearings
    fern_cols = ['#2F5E2A', '#3A6C30', '#457A36']
    far = ndimage.distance_transform_edt(~(clear | path)) > 8
    for (fi, fk) in np.argwhere(inner & far & ~grassy & (rng.random((W, D)) < 0.0012)):
        for f in range(rng.integers(5, 8)):
            fa = f * 2 * math.pi / 7 + rng.uniform(-0.3, 0.3)
            ln = rng.uniform(3.5, 5.5)
            col = fern_cols[rng.integers(0, 3)]
            for t in np.linspace(0, 1, 7):
                i2 = int(round(fi + math.cos(fa) * ln * t))
                k2 = int(round(fk + math.sin(fa) * ln * t))
                if not (0 <= i2 < W and 0 <= k2 < D) or not inner[i2, k2]:
                    continue
                y = j0 + int(round(3.2 * math.sin(math.pi * (0.15 + 0.7 * t)) * (1 - 0.35 * t)))
                M.m[i2, y, k2] = M.mid(col)
    return M


# ------------------------------------------------------------------ Blender and the cut
def projection(G):
    p = math.radians(MAP_PITCH)
    ymax = G.hi[1] / G.res
    return p, ymax


def save_blend(G, bounds, path, samples=96):
    """the slab as a scene ready to render (wilds_blender's ground scene, framed on this slab)"""
    import bpy
    import wilds_blender as WB
    import village_blender as VB
    X0, X1, Z0, Z1 = bounds
    s = SCALE
    p = math.radians(MAP_PITCH)
    ymin, ymax = G.lo[1] / G.res, G.hi[1] / G.res
    sy0 = Z0 * math.sin(p) - ymax * math.cos(p)
    sy1 = Z1 * math.sin(p) - ymin * math.cos(p)
    w = int(round((X1 - X0) * s))
    h = int(round((sy1 - sy0) * s))
    ox, oy = -X0 * s, -sy0 * s
    sc = WB.scene(w, h, samples, transparent=False)
    VB.model_mesh(G, 'ground', (), water=WM.WATER)
    WB.ortho_camera(s, ox, oy, w, h)
    sc.render.filepath = '//kit_ground.png'
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(path), compress=True)
    return {'w': w, 'h': h, 'origin': [round(ox, 2), round(oy, 2)], 'scale': s}


def cut(cs, gm, png, out):
    im = Image.open(png).convert('RGB')
    p = math.radians(MAP_PITCH)
    s = gm['scale']
    ox, oy = gm['origin']
    ch = CHUNK * math.sin(p) * s
    for c in cs:
        x = ox + c['x0'] * s
        y = oy + c['z0'] * math.sin(p) * s
        box = (int(round(x)), int(round(y)), int(round(x + CHUNK * s)), int(round(y + ch)))
        im.crop(box).save(os.path.join(out, f"kit_{c['id']}.webp"), quality=86, method=6)


def preview(cs, G, bounds, out):
    """flat top colours, squashed to the map's pitch: enough to try the game's generator"""
    from voxel import hexrgb
    X0, X1, Z0, Z1 = bounds
    j0 = -G.lo[1]
    top = np.zeros((X1 - X0, Z1 - Z0, 3), np.float32)
    for j in range(G.m.shape[1]):
        col = G.m[:, j, :]
        for mid in np.unique(col):
            if mid == 0:
                continue
            top[col == mid] = hexrgb(G.mats[mid]) / 255.0
    p = math.radians(MAP_PITCH)
    for c in cs:
        a = top[c['x0'] - X0:c['x0'] - X0 + CHUNK, c['z0'] - Z0:c['z0'] - Z0 + CHUNK]
        img = Image.fromarray((np.clip(a.transpose(1, 0, 2), 0, 1) * 255).astype(np.uint8), 'RGB')
        img = img.resize((int(CHUNK * SCALE), int(round(CHUNK * math.sin(p) * SCALE))), Image.NEAREST)
        img.save(os.path.join(out, f"kit_{c['id']}.webp"), quality=86, method=6)


def write_json(cs, out):
    meta = {'chunk': CHUNK, 'scale': SCALE, 'pitch': MAP_PITCH, 'edge': EDGE, 'pathW': PATH_W, 'chunks': {}}
    for c in cs:
        p = c['plan']
        meta['chunks'][c['id']] = {'image': f"kit_{c['id']}.webp", 'kind': c['kind'], 'mask': c['mask'],
                                   'r': p['r'], 'clear': p['poly'], 'paths': p['paths']}
    json.dump(meta, open(os.path.join(out, 'wilds_kit.json'), 'w'))


def main(out, only):
    os.makedirs(os.path.join(out, 'work'), exist_ok=True)
    cs, bounds = layout()
    for c in cs:
        c['plan'] = plan_chunk(c)
    if 'blend' in only or 'preview' in only:
        G = build(cs, bounds)
        if 'blend' in only:
            gm = save_blend(G, bounds, os.path.join(out, 'work', 'kit_ground.blend'))
            json.dump(gm, open(os.path.join(out, 'work', 'kit_meta.json'), 'w'))
            print('saved the slab', gm, flush=True)
        if 'preview' in only:
            preview(cs, G, bounds, out)
            print('preview chunks written', flush=True)
    if 'cut' in only:
        gm = json.load(open(os.path.join(out, 'work', 'kit_meta.json')))
        cut(cs, gm, os.path.join(out, 'work', 'kit_ground.png'), out)
        print('chunks cut', flush=True)
    write_json(cs, out)


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = {a.split('=', 1)[0]: a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--') and '=' in a}
    main(args[0], opts.get('--only', 'preview').split(','))

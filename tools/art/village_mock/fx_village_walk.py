"""The walkable Sunlit Village (tools/art/village_walk.py): its living-scene zones, worked out from the
3D layout rather than drawn by hand, for each rendered view. Trees sway (the village's and the ones on
the cliffs), grass shimmers, the stream, the creek and the pool ripple, the waterfall falls, Bram's
chimney smokes and his forge and windows glow, the Guild's banners and flag and the market awning
ripple, cottage chimneys breathe a little smoke; leaves drift, pollen and a few lights float in the wind.

Concept only, so it lives here rather than in fx_zones; bake it with
    python3 tools/art/scene_fx.py --zones tools/art/village_mock/fx_village_walk.py --json OUT.json village/walk_falls.webp
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import village_walk as V  # noqa: E402

S35, C35 = math.sin(math.radians(V.PITCH)), math.cos(math.radians(V.PITCH))


def _proj(view):
    (cx, cz), width, (w, h) = V.VIEWS[view]
    ppu = w / width

    def at(x, z, y=0.0):
        return (w / 2 + (x - cx) * ppu, h / 2 + ((z - cz) * S35 - y * C35) * ppu)
    return at, ppu, w, h


def _rect(at, x0, x1, y0, y1, z0, z1, pad=0.0):
    pts = [at(x, z, y) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return [round(min(xs) - pad), round(min(ys) - pad), round(max(xs) + pad), round(max(ys) + pad)]


def _far_trees():
    """far_terrain(seed=41)'s trees, replayed: (x, canopy y, z, r) in village coordinates."""
    xs = np.arange(-130, 130) + 0.5
    zs = np.arange(-150, -44) + 0.5
    X2, Z2 = np.meshgrid(xs, zs, indexing='ij')
    t = np.clip((-46.0 - Z2) / 90.0, 0, 1)
    H = np.maximum(2.0 + 30.0 * np.floor(t * 5 + 0.6 * np.sin(X2 * 0.09) + 0.4 * np.cos(X2 * 0.23 + 1.0)) / 5, 0)
    rng = np.random.default_rng(41)
    out = []
    for _ in range(70):
        tx, tz = rng.uniform(-125, 125), rng.uniform(-145, -50)
        i, j = np.argmin(np.abs(xs - tx)), np.argmin(np.abs(zs - tz))
        ty = H[i, j]
        if abs(tx + 24.0) < 7 and tz > -70:
            continue
        r = rng.uniform(3.0, 5.5)
        out.append((tx, ty + 4.0 + r * 0.6, tz + V.FALLS_DZ, r))
    return out


def _buildings():
    """Boxes (x0, x1, y0, y1, z0, z1) of every building where it stands in the walkable village."""
    g, wk, lo, mk = V.MOVE['glasshouse'], V.MOVE['workshop'], V.MOVE['lodge'], V.MOVE['market']
    boxes = [(-24 + g[0], -11 + g[0], 0, 12.5, -10 + g[1], 2 + g[1]),
             (11 + wk[0], 24 + wk[0], 0, 12.5, -11 + wk[1], 1 + wk[1]),
             (-10 + lo[0], 10 + lo[0], 0, 16.5, -34 + lo[1], -24 + lo[1])]
    for (cx0, cx1, cz0, cz1, *_), (dx, dz) in V.COTTAGES:
        boxes.append((cx0 + dx, cx1 + dx, 0, 10.5, cz0 + dz, cz1 + dz))
    return boxes


def zones(view, lamp=False):
    at, ppu, w, h = _proj(view)
    fx = [('grass', [0, 0, w, h], 'green'),
          ('still', [0, 0, w, h], 'water')]
    for b in _buildings():                                  # walls, glass and roofs keep still
        fx.append(('none', _rect(at, *b)))
    for (tx, tz, th, tr) in V.TREES:
        cx, cy = at(tx, tz, th + tr * 0.35)
        fx.append(('tree', ('e', round(cx), round(cy), round(tr * 1.3 * ppu), round(tr * 1.15 * ppu)), 'green'))
    for (tx, ty, tz, r) in _far_trees():
        cx, cy = at(tx, tz, ty)
        if -3 * r * ppu < cx < w + 3 * r * ppu and -3 * r * ppu < cy < h + 3 * r * ppu:
            fx.append(('tree', ('e', round(cx), round(cy), round(r * 1.2 * ppu), round(r * 1.05 * ppu)), 'green', {'amp': 0.6}))
    fx.append(('fall', _rect(at, V.FALLS_X - 3.4, V.FALLS_X + 3.4, 1.5, V.CLIFF_TOP, V.FALLS_FACE - 0.4, V.FALLS_FACE + 0.8), 'waterfall'))
    # the white water at the foot of the falls, and the creek's two little spills on its way out
    fx.append(('fall', _rect(at, V.FALLS_X - 4.2, V.FALLS_X + 4.2, 1.0, 4.0, V.FALLS_FACE + 0.4, V.FALLS_FACE + 4.2), 'white'))
    fx.append(('fall', _rect(at, -26.2, -19.6, -1.0, 1.6, -63.4, -57.2), 'white'))
    for (tx, tz) in V.CLIFF_TREES:                          # the trees on the cliff top
        cx, cy = at(tx, tz, V.cliff_height(tx) + 6.0 + 3.8 * 0.35)
        fx.append(('tree', ('e', round(cx), round(cy), round(3.8 * 1.3 * ppu), round(3.8 * 1.15 * ppu)), 'green'))
    lz1 = -24 + V.MOVE['lodge'][1]
    for bx in (-9.2, 9.2):
        fx.append(('cloth', _rect(at, bx - 1.2, bx + 1.2, 3.4, 9.0, lz1, lz1 + 0.7), 'all', {'amp': 0.35, 'fade': 0.0}))
    fx.append(('cloth', _rect(at, 9.0, 12.8, 18.6, 21.0, -29.4 + V.MOVE['lodge'][1], -28.6 + V.MOVE['lodge'][1]), 'all', {'amp': 0.5}))
    mx, mz = -21 + V.MOVE['market'][0], 12 + V.MOVE['market'][1]
    fx.append(('cloth', _rect(at, mx - 4.3, mx + 4.3, 5.8, 7.8, mz - 2.7, mz + 2.7), 'cloth', {'amp': 0.3}))
    wdx = V.MOVE['workshop'][0]
    fx.append(('smoke', _rect(at, 34.5 + wdx - 16, 42 + wdx - 16, 15.6, 25.0, -9.0, -6.0), 'smoky'))
    fx.append(('fire', _rect(at, 19.4 + wdx, 21.0 + wdx, 15.4, 15.8, -8.2, -6.6, 2), 'bright'))
    fx.append(('lamp', _rect(at, 18.2 + wdx, 21.0 + wdx, 2.6, 5.0, 0.6, 1.4, 1), 'warm'))
    # emitters
    sx, sy = at(20.2 + wdx, -7.4, 16.2)
    emit = [{'t': 'smoke', 'x': round(sx), 'y': round(sy), 'n': 7, 's': round(0.55 * ppu), 'h': round(8.0 * ppu), 'drift': round(2.0 * ppu), 'c': '#f4efe6', 'a': 0.5},
            {'t': 'leaves', 'x': 0, 'y': 0, 'w': w, 'h': h, 'n': 3},
            {'t': 'motes', 'kind': 'pollen', 'x': 0, 'y': round(h * 0.25), 'w': w, 'h': round(h * 0.75), 'n': 10, 'c': '#fff6c8', 's': 3}]
    fx_, fy_ = at(20.2 + wdx, -7.4, 15.6)
    emit.append({'t': 'glow', 'x': round(fx_), 'y': round(fy_), 'r': round(1.8 * ppu), 'c': '#ffb04a', 'kind': 'fire', 'a': 0.5})
    for (x, y, z) in ((19.6 + wdx, 3.8, 1.2),):                    # the front window (the side one faces away)
        gx, gy = at(x, z, y)
        emit.append({'t': 'glow', 'x': round(gx), 'y': round(gy), 'r': round(1.5 * ppu), 'c': '#ffc561', 'kind': 'lamp', 'a': 0.45})
    for (cx0, cx1, cz0, cz1, *_), (dx, dz) in V.COTTAGES[:3]:                     # a breath of smoke at home
        cxx, cyy = at(cx1 - 1.9 + dx, cz0 + 2.7 + dz, 11.2)
        emit.append({'t': 'smoke', 'x': round(cxx), 'y': round(cyy), 'n': 4, 's': round(0.45 * ppu), 'h': round(5.0 * ppu), 'drift': round(1.6 * ppu), 'c': '#f4efe6', 'a': 0.3})
    # lights in the wind: a few soft lumen motes over the creek, the pool and the falls
    px0, py0 = at(-30.0, -70.0, 6.0)
    px1, py1 = at(-14.0, -26.0, 0.0)
    emit.append({'t': 'motes', 'kind': 'firefly', 'x': round(px0), 'y': round(py0), 'w': round(px1 - px0), 'h': round(py1 - py0), 'n': 7, 'c': '#e8fff6', 's': 4})
    if lamp:
        for (lx, lz) in V.TRAIL_LANTERNS + ((10.5, 7.5), (-10.5, 7.5), (-10.5, -8.0), (10.5, -8.0)):
            gx, gy = at(lx, lz, 5.2)
            emit.append({'t': 'glow', 'x': round(gx), 'y': round(gy), 'r': round(1.6 * ppu), 'c': '#ffd27a', 'kind': 'lamp', 'a': 0.6})
    # drop zones that miss the picture (a fade over an empty shape has nothing to measure)
    def inside(shape):
        if isinstance(shape, tuple) and shape[0] == 'e':
            _, cx, cy, rx, ry = shape
            x0, y0, x1, y1 = cx - rx, cy - ry, cx + rx, cy + ry
        else:
            x0, y0, x1, y1 = shape
        return x1 > 0 and y1 > 0 and x0 < w and y0 < h
    fx = [z for z in fx if inside(z[1])]
    # drop emitters that sit wholly outside the picture
    keep = []
    for e in emit:
        x, y = e.get('x', 0), e.get('y', 0)
        if e['t'] in ('leaves', 'motes') or (-200 < x < w + 200 and -200 < y < h + 200):
            keep.append(e)
    return {'fx': fx, 'emit': keep}


SCENES = {f'village/walk_{v}.webp': zones(v) for v in ('falls', 'plaza', 'workshop', 'road', 'all')}

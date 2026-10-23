"""The Old Trail (tools/art/village_trail.py): its living-scene zones, worked out from the 3D layout like
the walkable village's (fx_village_walk.py). The autumn trees and the pines sway, grass shimmers, the
stream steps down the cliffs and over the ledge's lip in a waterfall, the basin, the pool below and the
river ripple, the lanterns on their posts and Flint's windows breathe, his banner, his awning and the
Thicket's banner ripple; mist rises where the falls land, autumn leaves drift, pollen floats, and dust
hangs in the mine's mouth.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import village_walk as V  # noqa: E402
import village_trail as T  # noqa: E402

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


def zones(view):
    at, ppu, w, h = _proj(view)
    fx = [('grass', [0, 0, w, h], 'green'),
          ('still', [0, 0, w, h], 'water')]
    cz1 = float(T.zn(100.0)) + 0.6                      # Flint's front wall
    cz0 = cz1 - 7.1
    fx.append(('none', _rect(at, 95.0, 109.0, 0, 10.5, cz0, cz1 + 4.2)))          # his dwelling keeps still
    mx, mz = T.MINE
    fx.append(('none', _rect(at, mx - 5.6, mx + 5.6, 0, 12.8, mz - 8.5, mz + 0.9)))  # the mine's timbers and its sign
    for (kind, x, z, y, th, r, _) in T.TREES:
        if kind == 'pine':
            cx, cy = at(x, z, y + th * 0.55)
            fx.append(('tree', ('e', round(cx), round(cy), round(r * 1.15 * ppu), round(th * 0.6 * ppu)), 'green', {'amp': 0.7}))
        else:
            cx, cy = at(x, z, y + th + r * 0.35)
            fx.append(('tree', ('e', round(cx), round(cy), round(r * 1.3 * ppu), round(r * 1.15 * ppu)), 'cloth'))
    # the stream stepping down the terraces, and the wide falls over the ledge's lip
    zn = float(T.zn(T.STREAM_X))
    fx.append(('fall', _rect(at, T.STREAM_X - 3.4, T.STREAM_X + 3.4, -1.4, 31.0, zn - T.TER_D * 6, zn + 0.6), 'waterfall'))
    lip = float(T.zs(T.STREAM_X))
    fx.append(('fall', _rect(at, T.STREAM_X - 5.2, T.STREAM_X + 5.2, -9.6, -1.9, lip - 0.6, lip + 0.6), 'waterfall'))
    # cloth: Flint's red banner, his awning, the Thicket's banner
    fx.append(('cloth', _rect(at, 104.6, 107.0, 2.6, 6.4, cz1, cz1 + 0.5), 'cloth', {'amp': 0.35, 'fade': 0.0}))
    fx.append(('cloth', _rect(at, 94.5, 100.6, 4.6, 6.4, cz1, cz1 + 4.2), 'cloth', {'amp': 0.2}))
    gz = float(T.np.interp(T.GATE_X, [p[0] for p in T.PATH], [p[1] for p in T.PATH]))
    fx.append(('cloth', _rect(at, T.GATE_X - 1.2, T.GATE_X - 0.6, 5.2, 8.6, gz - 1.9, gz + 1.3), 'all', {'amp': 0.35, 'fade': 0.0}))
    # lamps: the lanterns on their posts, the ones at Flint's and the mine's, his windows
    lamps = [(x + (1.0 if z < 0 else -1.0) * 2.2, 3.4, z) for (x, z) in T.LANTERNS]
    lamps += [(x + sd * 2.2, 3.4, z) for (x, z, sd) in T.MINE_POSTS]
    lamps += [(95.3, 5.6, cz1 + 3.9), (108.2, 5.0, cz1 + 0.8)] + list(T.MINE_LAMPS)
    for (x, y, z) in lamps:
        fx.append(('fire', _rect(at, x - 0.6, x + 0.6, y - 0.8, y + 0.8, z - 0.6, z + 0.6, 1), 'warm'))   # flames flicker
    for wx in (98.0, 107.0):
        fx.append(('lamp', _rect(at, wx - 1.0, wx + 1.0, 2.6, 4.2, cz1, cz1 + 0.2, 1), 'warm'))
    # emitters
    emit = [{'t': 'leaves', 'x': 0, 'y': 0, 'w': w, 'h': h, 'n': 5, 'c': ['#E08A2E', '#E9B83C', '#C9552E', '#F2B04A']},
            {'t': 'motes', 'kind': 'pollen', 'x': 0, 'y': round(h * 0.3), 'w': w, 'h': round(h * 0.6), 'n': 8, 'c': '#fff6c8', 's': 3}]
    for (x, y, z) in lamps:
        gx, gy = at(x, z, y)
        emit.append({'t': 'glow', 'x': round(gx), 'y': round(gy), 'r': round(1.3 * ppu), 'c': '#ffc561', 'kind': 'fire', 'a': 0.4})
    gx, gy = at(mx, mz - 1.0, 2.6)                        # the mine's mouth glows warm
    emit.append({'t': 'glow', 'x': round(gx), 'y': round(gy), 'r': round(3.4 * ppu), 'c': '#ffb04a', 'kind': 'fire', 'a': 0.32})
    for wx in (98.0, 107.0):
        gx, gy = at(wx, cz1, 3.4)
        emit.append({'t': 'glow', 'x': round(gx), 'y': round(gy), 'r': round(1.5 * ppu), 'c': '#ffc561', 'kind': 'lamp', 'a': 0.4})
    # mist where the falls land, a little spray at the bridge
    fx_, fy_ = at(T.STREAM_X, lip + 1.6, -9.2)
    emit.append({'t': 'smoke', 'kind': 'steam', 'x': round(fx_), 'y': round(fy_), 'n': 6, 's': round(1.2 * ppu), 'h': round(5.0 * ppu),
                 'drift': round(1.0 * ppu), 'c': '#f4fbff', 'a': 0.35})
    # dust hanging in the mine's mouth
    d0x, d0y = at(mx - 2.6, mz - 2.0, 6.0)
    d1x, d1y = at(mx + 2.6, mz + 2.0, 0.5)
    emit.append({'t': 'motes', 'kind': 'dust', 'x': round(d0x), 'y': round(d0y), 'w': round(d1x - d0x), 'h': round(d1y - d0y), 'n': 6, 'c': '#ffe2a8', 's': 3})

    def inside(shape):
        if isinstance(shape, tuple) and shape[0] == 'e':
            _, cx, cy, rx, ry = shape
            x0, y0, x1, y1 = cx - rx, cy - ry, cx + rx, cy + ry
        else:
            x0, y0, x1, y1 = shape
        return x1 > 0 and y1 > 0 and x0 < w and y0 < h
    fx = [z for z in fx if inside(z[1])]
    keep = [e for e in emit if e['t'] in ('leaves', 'motes') or (-200 < e.get('x', 0) < w + 200 and -200 < e.get('y', 0) < h + 200)]
    return {'fx': fx, 'emit': keep}


SCENES = {f'village/walk_{v}.webp': zones(v) for v in ('trail', 'trail_falls')}

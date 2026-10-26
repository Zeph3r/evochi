"""The walkable Home (tools/art/home_walk.py): its living-scene zones. Trees sway, grass shimmers, the
pond ripples, the lanterns and the nook's window and egg lantern flicker, the cottage's chimney smokes,
leaves and pollen drift; in the Grove the lumen tree pulses and motes rise.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import village_walk as V  # noqa: E402
import home_walk as H  # noqa: E402

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
    cx0, cx1, cz0, cz1 = H.COTTAGE
    fx.append(('none', _rect(at, cx0 - 1, cx1 + 1, 0, 13, cz0 - 1, cz1 + 1)))            # the cottage keeps still
    nx0, nx1, nz0, nz1 = H.NOOK
    fx.append(('none', _rect(at, nx0 - 1, nx1 + 1, 0, 9, nz0 - 1, nz1 + 1)))
    trees = [(-36.0, -40.0, 8, 5.0), (-37.0, 10.0, 6, 4.4), (-22.0, 32.0, 5, 3.8), (2.0, 30.0, 5, 3.4),
             (40.0, 24.0, 6, 4.6), (40.0, -24.0, 7, 4.4), (-6.0, -38.0, 7, 4.6), (-40.0, -18.0, 6, 4.2),
             (30.0, 32.0, 5, 3.6), (38.0, 8.0, 6, 4.2), (-40.0, 34.0, 6, 4.0), (14.0, 26.0, 5, 3.6), (-30.0, -34.0, 6, 4.2),
             (H.GROVE[0], H.GROVE[1] - 3.0, 7, 4.6)]
    for (x, z, th, r) in trees:
        cx, cy = at(x, z, th + r * 0.35)
        fx.append(('tree', ('e', round(cx), round(cy), round(r * 1.3 * ppu), round(r * 1.15 * ppu)), 'green'))
    # the lumen tree pulses
    gx, gz = H.GROVE
    fx.append(('crystal', _rect(at, gx - 5.5, gx + 5.5, 3.0, 13.0, gz - 8.5, gz + 2.5), 'all'))
    # lamps: the nest's, the bench's, the gate's lantern; the nook's window and egg lantern; the cottage windows
    lamps = [(H.NEST[0] + 7.0, 4.0, H.NEST[1] + 3.5), (3.5 + 3.2, 3.8, -9.5), (H.GATE[0] + 6.0, 4.0, H.GATE[1] + 1.6)]
    for (x, y, z) in lamps:
        fx.append(('fire', _rect(at, x - 0.7, x + 0.7, y - 0.9, y + 0.9, z - 0.7, z + 0.7, 1), 'warm'))
    ex, ez = (nx0 + nx1) / 2 + 3.0, nz1 + 2.2
    fx.append(('lamp', _rect(at, ex + 0.3, ex + 1.9, 1.6, 3.8, ez - 0.8, ez + 0.8, 1), 'warm'))
    fx.append(('lamp', _rect(at, nx1 - 2.9, nx1 - 0.9, 1.6, 3.6, nz1, nz1 + 1.0, 1), 'warm'))
    fx.append(('lamp', _rect(at, cx0 + 1.0, cx1 - 1.0, 1.5, 5.5, cz1 - 0.2, cz1 + 0.6, 1), 'warm'))
    emit = [{'t': 'leaves', 'x': 0, 'y': 0, 'w': w, 'h': h, 'n': 4, 'c': ['#8DBD6C', '#E9B83C', '#F5A3B5']},
            {'t': 'motes', 'kind': 'pollen', 'x': 0, 'y': round(h * 0.25), 'w': w, 'h': round(h * 0.7), 'n': 7, 'c': '#fff6c8', 's': 3}]
    for (x, y, z) in lamps:
        gx_, gy_ = at(x, z, y)
        emit.append({'t': 'glow', 'x': round(gx_), 'y': round(gy_), 'r': round(1.3 * ppu), 'c': '#ffc561', 'kind': 'fire', 'a': 0.4})
    gx_, gy_ = at(ex + 1.1, ez, 2.7)
    emit.append({'t': 'glow', 'x': round(gx_), 'y': round(gy_), 'r': round(1.6 * ppu), 'c': '#ffd98a', 'kind': 'lamp', 'a': 0.45})
    # the chimney's smoke (the cottage's chimney sits at its west end)
    sx_, sy_ = at(cx0 + 3.0, cz0 + 4.0, 12.5)
    emit.append({'t': 'smoke', 'kind': 'smoke', 'x': round(sx_), 'y': round(sy_), 'n': 4, 's': round(0.7 * ppu), 'h': round(5.0 * ppu),
                 'drift': round(1.2 * ppu), 'c': '#e8e2d8', 'a': 0.3})
    # the Grove: lumen motes rising round the tree, a soft glow
    m0x, m0y = at(gx - 7.0, gz - 8.0, 9.0)
    m1x, m1y = at(gx + 7.0, gz + 4.0, 0.0)
    emit.append({'t': 'motes', 'kind': 'pollen', 'x': round(m0x), 'y': round(m0y), 'w': round(m1x - m0x), 'h': round(m1y - m0y), 'n': 10, 'c': '#c8fff0', 's': 3})
    gx_, gy_ = at(gx, gz - 3.0, 6.0)
    emit.append({'t': 'glow', 'x': round(gx_), 'y': round(gy_), 'r': round(4.0 * ppu), 'c': '#9ff0da', 'kind': 'crystal', 'a': 0.3})

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


SCENES = {f'village/walk_{v}.webp': zones(v) for v in ('home',)}

"""The Guild Lodge (tools/art/village_interiors.py): its living-scene zones. The fire flickers, the
candles and lanterns breathe, dust drifts in the window light, a little smoke lifts from the hearth.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import village_walk as V  # noqa: E402
import village_interiors as I  # noqa: E402

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
    rx0, rx1, rz0, rz1 = I.ROOM
    fz_ = I.FIRE_L[1]
    tx0, tx1, tz0, tz1 = I.TABLE_L
    dx0, dx1, dz0, dz1 = I.DESK_L
    fx = [('none', [0, 0, w, h]),
          ('fire', _rect(at, rx1 - 1.7, rx1 + 0.3, 0.4, 3.0, fz_ - 1.8, fz_ + 1.8, 2), 'warm')]
    for (x, y, z) in ((tx0 + 2.0, 3.6, (tz0 + tz1) / 2), (tx1 - 2.0, 3.6, (tz0 + tz1) / 2), (dx1 - 0.6, 3.7, dz1 - 0.6), (rx1 - 1.0, 6.9, fz_ - 2.4)):
        fx.append(('lamp', _rect(at, x - 0.4, x + 0.4, y - 0.4, y + 0.5, z - 0.4, z + 0.4, 1), 'warm'))
    for (x, y, z) in ((-6.4, 3.8, rz1 - 0.8), (0.0, 6.2, -1.0)):
        fx.append(('lamp', _rect(at, x - 0.7, x + 0.7, y - 0.8, y + 1.0, z - 0.7, z + 0.7, 1), 'warm'))
    emit = []
    gx_, gy_ = at(rx1 - 0.9, fz_, 1.6)
    emit.append({'t': 'glow', 'x': round(gx_), 'y': round(gy_), 'r': round(2.2 * ppu), 'c': '#ffc561', 'kind': 'fire', 'a': 0.45})
    for (x, y, z) in ((-6.4, 3.8, rz1 - 0.8), (0.0, 6.2, -1.0)):
        gx_, gy_ = at(x, z, y)
        emit.append({'t': 'glow', 'x': round(gx_), 'y': round(gy_), 'r': round(1.5 * ppu), 'c': '#ffd98a', 'kind': 'lamp', 'a': 0.4})
    sx_, sy_ = at(rx1 - 0.9, fz_, 3.4)
    emit.append({'t': 'smoke', 'kind': 'smoke', 'x': round(sx_), 'y': round(sy_), 'n': 3, 's': round(0.5 * ppu), 'h': round(2.4 * ppu),
                 'drift': round(0.5 * ppu), 'c': '#e8e2d8', 'a': 0.16})
    d0x, d0y = at(rx0 + 1, rz0 + 1, 7.5)
    d1x, d1y = at(rx1 - 1, rz1 - 1, 0.0)
    emit.append({'t': 'motes', 'kind': 'pollen', 'x': round(d0x), 'y': round(d0y), 'w': round(d1x - d0x), 'h': round(d1y - d0y), 'n': 6, 'c': '#fff6c8', 's': 2})
    return {'fx': fx, 'emit': emit}

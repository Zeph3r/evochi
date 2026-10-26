"""Bram's Workshop (tools/art/village_interiors.py): its living-scene zones. The forge's coals and the
hot bar flicker, the lanterns on his wall breathe, the quench barrel ripples, sparks and smoke rise from
the forge, dust drifts in the window light.
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
    fx_, fz_ = I.FORGE
    ax, az = I.ANVIL
    fx = [('none', [0, 0, w, h]),
          ('fire', _rect(at, fx_ - 2.2, fx_ + 2.2, 1.3, 3.2, rz0 - 0.3, rz0 + 2.4, 2), 'warm'),
          ('fire', _rect(at, ax - 0.4, ax + 1.5, 2.6, 3.1, az - 0.3, az + 0.3, 1), 'warm'),
          ('still', _rect(at, ax + 3.3, ax + 5.5, 2.2, 2.7, az - 1.7, az + 0.5, 1), 'water')]
    for k, lx in enumerate([x for x in [0.5 + 1.8 * i for i in range(5)] if not 4.0 < x < 7.0]):
        if k % 2 == 0:
            fx.append(('lamp', _rect(at, lx - 0.5, lx + 0.5, 3.9, 5.4, rz0 + 0.2, rz0 + 1.2, 1), 'warm'))
    fx.append(('lamp', _rect(at, 6.6 - 0.7, 6.6 + 0.7, 3.0, 4.8, rz1 - 1.5, rz1 - 0.1, 1), 'warm'))
    emit = []
    gx_, gy_ = at(fx_, rz0 + 1.4, 2.0)
    emit.append({'t': 'glow', 'x': round(gx_), 'y': round(gy_), 'r': round(2.8 * ppu), 'c': '#ffb347', 'kind': 'fire', 'a': 0.5})
    emit.append({'t': 'embers', 'x': round(gx_), 'y': round(gy_ - 0.4 * ppu), 'w': round(3.0 * ppu), 'h': round(3.2 * ppu), 'n': 8, 'c': '#ffc561', 's': 3})
    sx_, sy_ = at(fx_, rz0 + 1.0, 4.5)
    emit.append({'t': 'smoke', 'kind': 'smoke', 'x': round(sx_), 'y': round(sy_), 'n': 4, 's': round(0.7 * ppu), 'h': round(3.0 * ppu),
                 'drift': round(0.8 * ppu), 'c': '#d8d2c8', 'a': 0.22})
    gx_, gy_ = at(6.6, rz1 - 0.8, 3.8)
    emit.append({'t': 'glow', 'x': round(gx_), 'y': round(gy_), 'r': round(1.4 * ppu), 'c': '#ffd98a', 'kind': 'lamp', 'a': 0.4})
    d0x, d0y = at(rx0 + 1, rz0 + 1, 6.5)
    d1x, d1y = at(rx1 - 1, rz1 - 1, 0.0)
    emit.append({'t': 'motes', 'kind': 'pollen', 'x': round(d0x), 'y': round(d0y), 'w': round(d1x - d0x), 'h': round(d1y - d0y), 'n': 6, 'c': '#fff6c8', 's': 2})
    return {'fx': fx, 'emit': emit}

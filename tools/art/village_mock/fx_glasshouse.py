"""Mira's Glasshouse (tools/art/village_interiors.py): its living-scene zones. The plants in the beds
and the baskets sway, the birdbath ripples, the lantern breathes, pollen and butterflies drift in the
light through the glass.
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
    fx = [('none', [0, 0, w, h])]
    for (bx0, bx1, bz0, bz1) in I.BEDS_G:
        fx.append(('grass', _rect(at, bx0, bx1, 1.0, 3.6, bz0, bz1, 2), 'green'))
    for (hx_, hz_) in ((-7.0, -4.2), (-2.5, -4.2), (2.5, -4.2), (7.0, -4.2), (-8.0, 2.4), (0.0, 2.4), (8.0, 2.4)):
        cx, cy = at(hx_, hz_, 5.3)
        fx.append(('tree', ('e', round(cx), round(cy), round(1.3 * ppu), round(1.1 * ppu)), 'green'))
    fx.append(('grass', _rect(at, rx1 - 0.8, rx1 + 0.2, 1.6, 6.2, 2.6, 9.0, 2), 'green'))
    fx.append(('still', _rect(at, 7.5, 9.7, 1.7, 2.1, 6.7, 8.9, 1), 'water'))
    fx.append(('lamp', _rect(at, -4.4 - 0.7, -4.4 + 0.7, 3.0, 4.8, rz1 - 1.5, rz1 - 0.1, 1), 'warm'))
    emit = []
    gx_, gy_ = at(-4.4, rz1 - 0.8, 3.8)
    emit.append({'t': 'glow', 'x': round(gx_), 'y': round(gy_), 'r': round(1.4 * ppu), 'c': '#ffd98a', 'kind': 'lamp', 'a': 0.4})
    d0x, d0y = at(rx0 + 1, rz0 + 1, 6.5)
    d1x, d1y = at(rx1 - 1, rz1 - 1, 0.0)
    emit.append({'t': 'motes', 'kind': 'pollen', 'x': round(d0x), 'y': round(d0y), 'w': round(d1x - d0x), 'h': round(d1y - d0y), 'n': 12, 'c': '#fff6c8', 's': 3})
    emit.append({'t': 'leaves', 'x': round(d0x), 'y': round(d0y), 'w': round(d1x - d0x), 'h': round(d1y - d0y), 'n': 3, 'c': ['#F5A3B5', '#FFFDF6', '#F4C04E']})
    return {'fx': fx, 'emit': emit}

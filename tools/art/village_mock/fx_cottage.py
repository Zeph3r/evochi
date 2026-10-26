"""Inside the Cottage (tools/art/cottage_walk.py): its living-scene zones. The hearth and the stove
flicker, the candles and the lanterns breathe, the cauldron's brew pulses and its motes rise, a little
smoke lifts from the hearth, dust drifts in the window light.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import village_walk as V  # noqa: E402
import cottage_walk as C  # noqa: E402

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
    rx0, rx1, rz0, rz1 = C.ROOM
    hx, hz = C.HEARTH
    sx, sz = C.STOVE
    kx, kz = C.CAULDRON
    bx, bz = C.BED
    fx = [('none', [0, 0, w, h])]
    # the fires
    fx.append(('fire', _rect(at, hx - 1.6, hx + 1.6, 0.4, 3.0, rz0 - 0.3, rz0 + 1.6, 2), 'warm'))
    fx.append(('fire', _rect(at, sx + 1.1, sx + 1.6, 0.9, 1.9, sz - 0.7, sz + 0.7, 1), 'warm'))
    fx.append(('fire', _rect(at, kx - 1.0, kx + 1.0, 0.0, 1.0, kz - 1.0, kz + 1.0, 1), 'warm'))
    # the candles and lanterns
    for (x, y, z) in ((hx - 2.2, 7.4, rz0 + 0.8), (hx - 4.4, 5.2, rz0 + 0.35), (hx + 4.4, 5.2, rz0 + 0.35), (C.WORKTABLE[1] - 0.6, 3.7, C.WORKTABLE[2] + 0.8)):
        fx.append(('lamp', _rect(at, x - 0.4, x + 0.4, y - 0.4, y + 0.5, z - 0.4, z + 0.4, 1), 'warm'))
    for (x, y, z) in ((bx + 3.5, 2.5, bz), (6.6, 3.8, rz1 - 0.8)):
        fx.append(('lamp', _rect(at, x - 0.7, x + 0.7, y - 0.8, y + 1.0, z - 0.7, z + 0.7, 1), 'warm'))
    # the brew in the cauldron and the glowing bottles pulse
    fx.append(('crystal', _rect(at, kx - 1.5, kx + 1.5, 2.4, 3.2, kz - 1.5, kz + 1.5, 1), 'all'))
    fx.append(('crystal', _rect(at, rx1 - 1.3, rx1, 3.4, 7.0, -8.8, -1.4, 1), 'all'))
    emit = []
    for (x, y, z, r, a) in ((hx, 1.6, rz0 + 0.8, 2.2, 0.45), (sx + 1.4, 1.4, sz, 0.9, 0.35), (kx, 0.5, kz, 1.0, 0.3)):
        gx_, gy_ = at(x, z, y)
        emit.append({'t': 'glow', 'x': round(gx_), 'y': round(gy_), 'r': round(r * ppu), 'c': '#ffc561', 'kind': 'fire', 'a': a})
    for (x, y, z) in ((bx + 3.5, 2.5, bz), (6.6, 3.8, rz1 - 0.8)):
        gx_, gy_ = at(x, z, y)
        emit.append({'t': 'glow', 'x': round(gx_), 'y': round(gy_), 'r': round(1.4 * ppu), 'c': '#ffd98a', 'kind': 'lamp', 'a': 0.4})
    gx_, gy_ = at(kx, kz, 2.9)
    emit.append({'t': 'glow', 'x': round(gx_), 'y': round(gy_), 'r': round(2.2 * ppu), 'c': '#b98bff', 'kind': 'crystal', 'a': 0.35})
    m0x, m0y = at(kx - 1.6, kz - 1.6, 7.0)
    m1x, m1y = at(kx + 1.6, kz + 1.6, 2.6)
    emit.append({'t': 'motes', 'kind': 'pollen', 'x': round(m0x), 'y': round(m0y), 'w': round(m1x - m0x), 'h': round(m1y - m0y), 'n': 8, 'c': '#c8fff0', 's': 3})
    sx_, sy_ = at(hx, rz0 + 0.6, 3.2)
    emit.append({'t': 'smoke', 'kind': 'smoke', 'x': round(sx_), 'y': round(sy_), 'n': 3, 's': round(0.5 * ppu), 'h': round(2.6 * ppu),
                 'drift': round(0.6 * ppu), 'c': '#e8e2d8', 'a': 0.18})
    d0x, d0y = at(rx0 + 1, rz0 + 1, 6.5)
    d1x, d1y = at(rx1 - 1, rz1 - 1, 0.0)
    emit.append({'t': 'motes', 'kind': 'pollen', 'x': round(d0x), 'y': round(d0y), 'w': round(d1x - d0x), 'h': round(d1y - d0y), 'n': 6, 'c': '#fff6c8', 's': 2})
    return {'fx': fx, 'emit': emit}

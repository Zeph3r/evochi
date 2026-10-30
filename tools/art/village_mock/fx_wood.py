"""Fernlight Wood (tools/art/fern_wood.py): its living-scene zones, worked out from the 3D layout like the
Old Trail's (fx_trail.py). The trees, birches and ferns sway, grass shimmers, the brook and the pond ripple,
the little falls into the pond pour, the lanterns' flames flicker; leaves drift down, pollen floats, butterflies
wander over the meadow, the path and the pond, fireflies glow in the shade and round the arch, and the
Hollow's violet light breathes through the arch, a few motes of it drifting out.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import village_walk as V  # noqa: E402
import fern_wood as F  # noqa: E402

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


def _box(at, x0, x1, z0, z1, y0, y1):
    a, b = at(x0, z0, y1), at(x1, z1, y0)
    return round(a[0]), round(a[1]), round(b[0] - a[0]), round(b[1] - a[1])


def zones(view):
    at, ppu, w, h = _proj(view)
    fx = [('grass', [0, 0, w, h], 'green'),
          ('still', [0, 0, w, h], 'water')]
    ax, az = F.ARCH_X, F.ARCH_Z
    fx.append(('none', _rect(at, ax - F.ARCH_HALF - 3, ax + F.ARCH_HALF + 3, -1.0, F.ARCH_TOP - 1.0, az - 1.5, az + 1.5)))   # the arch's trunks keep still
    for (kind, x, z, th, r, _) in F.TREES:
        if kind == 'pine':
            cx, cy = at(x, z, th * 0.55)
            fx.append(('tree', ('e', round(cx), round(cy), round(r * 1.15 * ppu), round(th * 0.6 * ppu)), 'green', {'amp': 0.7}))
        elif kind == 'hollow':
            cx, cy = at(x, z, th + r * 0.35)
            fx.append(('tree', ('e', round(cx), round(cy), round(r * 1.3 * ppu), round(r * 1.15 * ppu)), 'all', {'amp': 0.45}))
        else:
            cx, cy = at(x, z, th + r * 0.35)
            fx.append(('tree', ('e', round(cx), round(cy), round(r * 1.3 * ppu), round(r * 1.15 * ppu)), 'cloth'))
    for (x, z, s, _) in F.FERNS:
        cx, cy = at(x, z, 0.6 * s)
        fx.append(('tree', ('e', round(cx), round(cy), round(2.0 * s * ppu), round(1.2 * s * ppu)), 'green', {'amp': 0.5}))
    # the arch's canopy and its vines stir; its far side breathes with the Hollow's light
    fx.append(('cloth', _rect(at, ax - F.ARCH_HALF - 4, ax + F.ARCH_HALF + 4, F.ARCH_TOP - 4, F.ARCH_TOP + 5, az - 4, az + 1), 'green', {'amp': 0.3, 'fade': 0.0}))
    fx.append(('crystal', _rect(at, ax - 4.0, ax + 4.0, -1.0, 4.0, az - 12.0, az - 1.0), 'crystal'))
    # the little falls into the pond
    fx_, fz_ = F.FALLS
    fx.append(('fall', _rect(at, fx_ - 1.3, fx_ + 1.3, -1.0, 5.6, fz_ - 1.0, fz_ + 0.6), 'waterfall'))
    # the lanterns' flames
    lamps = [(lx + 1.0, 2.2, lz) for (lx, lz) in F.LANTERNS]
    for (x, y, z) in lamps:
        fx.append(('fire', _rect(at, x - 0.45, x + 0.45, y - 0.6, y + 0.6, z - 0.45, z + 0.45, 1), 'warm'))
    # emitters
    emit = [{'t': 'leaves', 'x': 0, 'y': 0, 'w': w, 'h': h, 'n': 6, 'c': ['#6FA552', '#8CC06A', '#A4CF6C', '#5E9646']},
            {'t': 'motes', 'kind': 'pollen', 'x': 0, 'y': round(h * 0.2), 'w': w, 'h': round(h * 0.75), 'n': 12, 'c': '#fff6c8', 's': 3}]
    for (x, y, z) in lamps:
        gx, gy = at(x, z, y)
        emit.append({'t': 'glow', 'x': round(gx), 'y': round(gy), 'r': round(1.1 * ppu), 'c': '#ffc561', 'kind': 'fire', 'a': 0.35})
    # butterflies: over the meadow, along the path, by the pond
    wings = ['#F7D560', '#F5A3B5', '#B8D8FF', '#FFFFFF', '#FF9F7A']
    mx, mz, mrx, mrz = F.MEADOW
    px, pz, prx, prz = F.POND
    for (x0, x1, z0, z1, n) in ((mx - mrx, mx + mrx, mz - mrz, mz + mrz, 7), (px - prx - 2, px + prx + 2, pz - prz, pz + prz + 4, 5),
                                (12.0, 34.0, -4.0, 16.0, 4), (30.0, 48.0, -40.0, -20.0, 3)):
        bx, by, bw, bh = _box(at, x0, x1, z0, z1, 1.0, 4.0)
        emit.append({'t': 'motes', 'kind': 'butterfly', 'x': bx, 'y': by, 'w': bw, 'h': bh, 'n': n, 'c': wings, 's': round(0.35 * ppu)})
    # fireflies: in the shade under the trees, round the pond's reeds, thickest by the arch
    for (x0, x1, z0, z1, n) in ((2.0, 30.0, -50.0, -30.0, 10), (60.0, 90.0, -50.0, -20.0, 10), (52.0, 80.0, -16.0, 4.0, 8),
                                (ax - 12.0, ax + 12.0, az - 2.0, az + 10.0, 14), (0.0, 30.0, 0.0, 16.0, 6), (70.0, 92.0, 6.0, 16.0, 6)):
        bx, by, bw, bh = _box(at, x0, x1, z0, z1, 0.5, 6.0)
        emit.append({'t': 'motes', 'kind': 'firefly', 'x': bx, 'y': by, 'w': bw, 'h': bh, 'n': n, 'c': '#fff3a0', 's': 3})
    # the Hollow past the arch: a violet glow low in the opening, a few motes of it drifting out
    gx, gy = at(ax, az - 6.0, 1.5)
    emit.append({'t': 'glow', 'x': round(gx), 'y': round(gy), 'r': round(3.6 * ppu), 'c': '#9c5cf0', 'kind': 'crystal', 'a': 0.32})
    m0x, m0y = at(ax - 4.0, az - 8.0, 6.0)
    m1x, m1y = at(ax + 4.0, az + 2.0, 0.0)
    emit.append({'t': 'motes', 'kind': 'pollen', 'x': round(m0x), 'y': round(m0y), 'w': round(m1x - m0x), 'h': round(m1y - m0y), 'n': 5, 'c': '#d2b4ff', 's': 3})
    # mist off the little falls
    sx_, sy_ = at(fx_, fz_ + 1.0, -0.5)
    emit.append({'t': 'smoke', 'kind': 'steam', 'x': round(sx_), 'y': round(sy_), 'n': 4, 's': round(0.9 * ppu), 'h': round(2.6 * ppu),
                 'drift': round(0.6 * ppu), 'c': '#f4fbff', 'a': 0.28})

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


SCENES = {f'village/walk_{v}.webp': zones(v) for v in ('wood',)}

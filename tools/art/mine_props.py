"""The mine's finds: where a Wilds floor has a chest, a gallery has a miner's cart or a barrel, drawn like the
Wilds' props (voxels, the flat renderer, the map camera from the south) so they stand on the cave floor.

  cart    an old miner's cart on its rails' stub: an iron-banded wooden tub on four iron wheels, heaped with
          ore (copper, iron, a glint of lumen); searched, it's empty but for grit
  barrel  a stave barrel with two iron hoops and a lid; searched, the lid leans against it and the inside
          glints

    python3 tools/art/mine_props.py     # writes flutter/assets/art/wilds/mine_{cart,barrel}{,_open}.webp and
                                        # mine_props.json (anchor: the ground point in px, scale: px a unit)
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from voxel import Model, Fit, render                                  # noqa: E402
from walk import DIRS, cam_for, light_for, frame_box                   # noqa: E402
from wilds_foes import E, cap, put, shell, region, OUTLINE             # noqa: E402

OUT = os.path.join(HERE, '..', '..', 'flutter', 'assets', 'art', 'wilds')
SCALE = 6.0
WOOD, WOOD_LO, WOOD_HI = '#7A5235', '#5C3D27', '#93673F'
IRON, IRON_LO, IRON_HI = '#5D5A63', '#46434C', '#7C7884'
GRIT = '#3A3230'


def box(M, lo, hi):
    lo, hi = np.asarray(lo, float), np.asarray(hi, float)
    return region(M, lo, hi, lambda X, Y, Z: (X >= lo[0]) & (X <= hi[0]) & (Y >= lo[1]) & (Y <= hi[1]) & (Z >= lo[2]) & (Z <= hi[2]))


def cart(full=True):
    M = Model((-16, -2, -12), (16, 22, 12), [], res=2)
    # the tub: a wooden box, a little wider at the top, iron bands round it
    tub = box(M, (-10.5, 4.0, -6.5), (10.5, 12.5, 6.5)) | box(M, (-11.5, 10.0, -7.5), (11.5, 13.0, 7.5))
    hollow = box(M, (-9.5, 5.5, -5.5), (9.5, 14, 5.5))
    tub &= ~hollow
    put(M, tub, WOOD)
    put(M, tub & (np.abs(np.sin(M.X * 0.9)) < 0.18), WOOD_LO)     # the planks' seams
    put(M, tub & (M.Y > 12.0), WOOD_HI)
    for x in (-8.0, 0.0, 8.0):
        put(M, box(M, (x - 0.8, 3.8, -7.8), (x + 0.8, 13.2, 7.8)) & ~hollow, IRON)
    put(M, box(M, (-11.8, 12.6, -7.8), (11.8, 13.2, 7.8)) & ~hollow, '#68646E')
    # the floor of the tub and the axles
    put(M, box(M, (-9.5, 4.0, -5.5), (9.5, 5.5, 5.5)), WOOD_LO)
    for x in (-6.5, 6.5):
        put(M, cap(M, (x, 2.8, -8.0), (x, 2.8, 8.0), 0.7), IRON_LO)
        for z in (-7.8, 7.8):
            wheel = region(M, (x - 3.2, -0.5, z - 1.0), (x + 3.2, 6.2, z + 1.0),
                           lambda X, Y, Z, x=x: ((X - x) ** 2 + (Y - 2.8) ** 2) <= 3.0 ** 2)
            put(M, wheel, IRON)
            put(M, wheel & (((M.X - x) ** 2 + (M.Y - 2.8) ** 2) <= 1.1 ** 2), IRON_HI)
    if full:
        # a heap of ore: rock and copper and iron, a lumen glint on top
        rng = np.random.default_rng(4)
        put(M, E(M, (0, 12.0, 0), (9.0, 3.4, 5.0)), '#55504E')
        for k in range(16):
            x, z = rng.uniform(-8, 8), rng.uniform(-4.2, 4.2)
            y = 12.5 + 2.6 * math.cos(x / 9.0 * math.pi / 2) * math.cos(z / 5 * math.pi / 2)
            col = ['#C8783E', '#E09A5A', '#8E8A90', '#6E6A72', '#C8783E'][k % 5]
            put(M, E(M, (x, y, z), (1.4, 1.1, 1.3)), col)
        put(M, E(M, (2.0, 15.4, 0.8), (1.0, 1.4, 1.0)), '#9FF0DA', glow=0.9)
        put(M, E(M, (-4.5, 14.6, -1.5), (0.8, 1.1, 0.8)), '#D8FFF4', glow=0.8)
    else:
        put(M, box(M, (-9.5, 5.5, -5.5), (9.5, 6.2, 5.5)), GRIT)
        put(M, E(M, (3.0, 6.4, 1.0), (1.0, 0.6, 1.0)), '#C8783E')
    return M


def barrel(open_=False):
    M = Model((-12, -2, -12), (12, 20, 12), [], res=2)
    R, H = 5.6, 13.0

    def radius(y):  # bulging in the middle
        return R * (0.86 + 0.14 * math.sin(math.pi * max(0.0, min(1.0, y / H))))
    body = region(M, (-R - 1, 0, -R - 1), (R + 1, H, R + 1), lambda X, Y, Z: X ** 2 + Z ** 2 <= (R * (0.86 + 0.14 * np.sin(np.pi * np.clip(Y / H, 0, 1)))) ** 2)
    put(M, body, WOOD)
    ang = np.arctan2(M.Z, M.X)
    put(M, shell(M, body) & (np.abs(np.sin(ang * 6)) < 0.16), WOOD_LO)   # the staves
    for y in (2.6, H - 2.6):
        put(M, shell(M, body) & (np.abs(M.Y - y) < 0.8), IRON)
    top = body & (M.Y > H - 1.2)
    if open_:
        inside = region(M, (-R, H - 3, -R), (R, H + 1, R), lambda X, Y, Z: X ** 2 + Z ** 2 <= (R - 1.0) ** 2) & (M.Y > H - 3)
        M.m[inside] = 0
        put(M, box(M, (-R + 1, H - 3.2, -R + 1), (R - 1, H - 2.4, R - 1)) & body, GRIT)
        put(M, E(M, (1.0, H - 2.0, 0.5), (1.0, 0.8, 1.0)), '#9FF0DA', glow=0.9)
        # the lid, leaning against its side
        lid = region(M, (R - 0.5, 0, -R), (R + 3.0, H * 0.95, R), lambda X, Y, Z: ((Y - H * 0.48) ** 2 + Z ** 2) <= (R * 0.9) ** 2) & \
            region(M, (R - 0.5, 0, -R), (R + 3.0, H, R), lambda X, Y, Z: np.abs(X - (R + 0.6 + (H * 0.48 - Y) * 0.12)) < 0.9)
        put(M, lid, WOOD_HI)
    else:
        put(M, top, WOOD_HI)
        put(M, shell(M, body) & (M.Y > H - 0.8) & (np.abs(M.X) < 0.8), WOOD_LO)
    return M


def render_prop(name, M):
    G = (0.0, 0.0, 0.0)
    w, h, gx, gy = frame_box([(M, 0.0)], G, SCALE)
    cam = cam_for('S')
    fit = Fit(SCALE, gx, gy, w, h)
    o = render(M, {}, cam, w, h, fit=fit, light=light_for(cam.yaw), ss=3, outline_px=max(1.5, SCALE * 0.21), outline_col=OUTLINE,
               inner_thresh=2.2, inner_alpha=0.8, inner_px=max(0.6, SCALE * 0.045))
    Image.fromarray(o.rgba, 'RGBA').save(os.path.join(OUT, f'{name}.webp'), quality=88, method=6)
    return {'image': f'{name}.webp', 'anchor': [round(gx, 1), round(gy, 1)], 'scale': SCALE}


def main():
    meta = {'cart': render_prop('mine_cart', cart(True)), 'cart_open': render_prop('mine_cart_open', cart(False)),
            'barrel': render_prop('mine_barrel', barrel(False)), 'barrel_open': render_prop('mine_barrel_open', barrel(True))}
    json.dump(meta, open(os.path.join(OUT, 'mine_props.json'), 'w'), indent=1)
    print(meta)


if __name__ == '__main__':
    main()

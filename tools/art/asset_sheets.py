"""Art sheets for every item model (assets.py), drawn by the game's item renderer and outline: each item in its
game view (the camera its icon uses), front, side and back, one scale across its views, two items a row.

    python3 asset_sheets.py OUT_DIR [category ...]      -> OUT_DIR/assets_<category>.png
"""
from __future__ import annotations

import os
import sys
from multiprocessing import Pool

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from assets import CATEGORIES, category                    # noqa: E402
from turnarounds import font, BG, INKC, SUB, extents        # noqa: E402

CELL = 210
PAD = 14
VIEWS = [('Game view', None), ('Front', (0, 12)), ('Side', (90, 12)), ('Back', (180, 12))]
_items = None


def cams(a):
    from voxel import Camera
    return [a.cam if v is None else Camera(yaw=v[0], pitch=v[1]) for _, v in VIEWS]


def render_one(args):
    i, wi = args
    from voxel import Fit, render
    from build_items import LIGHT
    a = _items[i]
    cs = cams(a)
    ex = [extents(a.model, c) for c in cs]
    span = max(max(e[1] - e[0], e[3] - e[2]) for e in ex)
    scale = (CELL - 2 * PAD) / span
    e = ex[wi]
    fit = Fit(scale, (CELL - (e[1] - e[0]) * scale) / 2 - e[0] * scale, (CELL - (e[3] - e[2]) * scale) / 2 - e[2] * scale, CELL, CELL)
    o = render(a.model, a.pal, cs[wi], CELL, CELL, fit=fit, light=LIGHT, ss=3, outline_px=2.2, outline_col='#3B2923',
               inner_thresh=2.0, inner_alpha=0.55, inner_px=0.8)
    return i, wi, o.rgba


def sheet(title, items, tiles):
    per_row = 2
    block_w = len(VIEWS) * CELL
    gap = 40
    label_h = 34
    rows = (len(items) + per_row - 1) // per_row
    W = 30 + per_row * block_w + (per_row - 1) * gap + 30
    top = 120
    H = top + rows * (CELL + label_h + 16) + 20
    img = Image.new('RGB', (W, H), BG)
    d = ImageDraw.Draw(img)
    d.text((30, 22), title, font=font(40), fill=INKC)
    d.text((30, 70), '  ·  '.join(n for n, _ in VIEWS), font=font(18, False), fill=SUB)
    for i, a in enumerate(items):
        r, c = divmod(i, per_row)
        x0 = 30 + c * (block_w + gap)
        y0 = top + r * (CELL + label_h + 16)
        d.text((x0 + 4, y0), a.name, font=font(20), fill=INKC)
        for wi in range(len(VIEWS)):
            t = Image.fromarray(tiles[(i, wi)], 'RGBA')
            img.paste(t, (x0 + wi * CELL, y0 + label_h), t)
    return img


def main(out, only=None):
    global _items
    os.makedirs(out, exist_ok=True)
    for cat, title in CATEGORIES:
        if only and cat not in only:
            continue
        _items = category(cat)
        jobs = [(i, wi) for i in range(len(_items)) for wi in range(len(VIEWS))]
        tiles = {}
        with Pool(2) as pool:
            for i, wi, rgba in pool.imap_unordered(render_one, jobs, chunksize=4):
                tiles[(i, wi)] = rgba
        img = sheet(title, _items, tiles)
        img.save(os.path.join(out, 'assets_%s.png' % cat), optimize=True)
        print('sheet', cat, len(_items), img.size, flush=True)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2:] or None)

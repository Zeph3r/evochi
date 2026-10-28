"""Turnaround sheets for the whole cast (cast.py), drawn by the game's own flat voxel renderer and ink line:
front, three-quarter, side, back three-quarter and back, every colourway or variant a row, one scale and one
ground line across a sheet, the light turning with the camera so every view is lit alike. Plus a lineup of
everyone in three-quarter view, at the same scale per model unit.

    python3 turnarounds.py OUT_DIR [key ...]      -> OUT_DIR/turnaround_<key>.png, cast_lineup.png
"""
from __future__ import annotations

import math
import os
import sys
from multiprocessing import Pool

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from cast import cast   # noqa: E402

VIEWS = [('Front', 0), ('Three-quarter', 40), ('Side', 90), ('Back three-quarter', 140), ('Back', 180)]
PITCH = 10
TARGET_H = 360          # px: the tallest view of a character on its sheet
PAD = 26
BG = (246, 239, 226)
INKC = (59, 41, 35)
SUB = (128, 104, 88)
FONTS = os.path.join(HERE, '..', '..', 'flutter', 'assets', 'fonts')
_cast = None


def font(size, bold=True):
    return ImageFont.truetype(os.path.join(FONTS, 'Nunito-Black.ttf' if bold else 'Nunito-Bold.ttf'), size)


def light_for(yaw):
    from voxel import Light
    L = Light()
    x, y, z = L.key
    a = math.radians(yaw)
    L.key = (x * math.cos(a) + z * math.sin(a), y, -x * math.sin(a) + z * math.cos(a))
    return L


def extents(M, cam):
    from voxel import model_extent_points
    sx, sy, _ = cam.project(model_extent_points(M))
    return sx.min(), sx.max(), sy.min(), sy.max()


def layout(member, scale=None):
    """one scale for the sheet, the cell size, and per (variant, view) the fit that stands the model on the
    cell's ground line, centred"""
    from voxel import Camera, Fit
    cams = [Camera(yaw=y, pitch=PITCH) for _, y in VIEWS]
    ex = [[extents(v.model, c) for c in cams] for v in member.variants]
    hmax = max(e[3] - e[2] for row in ex for e in row)
    wmax = max(e[1] - e[0] for row in ex for e in row)
    scale = scale or TARGET_H / hmax
    cw, ch = int(wmax * scale) + 2 * PAD, int(hmax * scale) + 2 * PAD
    fits = [[Fit(scale, (cw - (e[1] - e[0]) * scale) / 2 - e[0] * scale, ch - PAD - e[3] * scale, cw, ch) for e in row]
            for row in ex]
    return cams, fits, cw, ch, scale


def render_one(args):
    mi, vi, wi, fit = args
    from voxel import render, Camera
    from charrender import render_char
    m = _cast[mi]
    v = m.variants[vi]
    cam = Camera(yaw=VIEWS[wi][1], pitch=PITCH)
    light = light_for(cam.yaw)
    if v.ch is not None:
        o = render_char(v.ch, v.pal_key if m.kind == 'evochi' else 'amber', 'default', cam, fit.w, fit.h, fit=fit,
                        light=light, pal=v.pal, pal_key=v.pal_key)
    else:
        from wilds_foes import OUTLINE
        o = render(v.model, {}, cam, fit.w, fit.h, fit=fit, light=light, ss=3, outline_px=max(1.5, fit.scale * 0.21),
                   outline_col=OUTLINE, inner_thresh=2.2, inner_alpha=0.8, inner_px=max(0.6, fit.scale * 0.045))
    return mi, vi, wi, o.rgba


def shadow(cw, ch):
    """a soft oval on the ground line"""
    im = Image.new('L', (cw, ch), 0)
    d = ImageDraw.Draw(im)
    rx, ry = cw * 0.3, max(6, cw * 0.045)
    cx, cy = cw / 2, ch - PAD
    for k in range(12, 0, -1):
        f = k / 12
        d.ellipse((cx - rx * f, cy - ry * f, cx + rx * f, cy + ry * f), fill=int(10 + 5 * (12 - k)))
    return im


def sheet(member, tiles, cw, ch):
    rows = len(member.variants)
    left = 150 if rows > 1 else 30
    top = 150
    W, H = left + len(VIEWS) * cw + 30, top + rows * ch + 30
    img = Image.new('RGB', (W, H), BG)
    d = ImageDraw.Draw(img)
    d.text((30, 22), member.name, font=font(44), fill=INKC)
    d.text((30, 74), member.blurb, font=font(20, False), fill=SUB)
    for wi, (vname, _) in enumerate(VIEWS):
        tw = d.textlength(vname, font=font(18, False))
        d.text((left + wi * cw + (cw - tw) / 2, top - 26), vname, font=font(18, False), fill=SUB)
    sh = shadow(cw, ch)
    for vi, v in enumerate(member.variants):
        if rows > 1:
            d.text((30, top + vi * ch + ch / 2 - 12), v.label, font=font(22), fill=INKC)
        for wi in range(len(VIEWS)):
            x, y = left + wi * cw, top + vi * ch
            img.paste((214, 200, 178), (x, y), sh)
            t = Image.fromarray(tiles[(vi, wi)], 'RGBA')
            img.paste(t, (x, y), t)
    return img


def main(out, only=None):
    global _cast
    os.makedirs(out, exist_ok=True)
    _cast = cast(only)
    plans = [layout(m) for m in _cast]
    jobs = [(mi, vi, wi, plans[mi][1][vi][wi]) for mi, m in enumerate(_cast) for vi in range(len(m.variants))
            for wi in range(len(VIEWS))]
    tiles = {}
    with Pool(2) as pool:
        for n, (mi, vi, wi, rgba) in enumerate(pool.imap_unordered(render_one, jobs, chunksize=2)):
            tiles[(mi, vi, wi)] = rgba
            if n % 20 == 0:
                print('rendered %d / %d' % (n + 1, len(jobs)), flush=True)
    for mi, m in enumerate(_cast):
        _, _, cw, ch, _ = plans[mi]
        img = sheet(m, {(vi, wi): tiles[(mi, vi, wi)] for vi in range(len(m.variants)) for wi in range(len(VIEWS))}, cw, ch)
        img.save(os.path.join(out, 'turnaround_%s.png' % m.key), optimize=True)
        print('sheet', m.key, img.size, flush=True)
    if not only:
        lineup(out)


def lineup(out):
    """everyone in three-quarter view, side by side at one scale per model unit (Flint at the size the game draws him)"""
    from voxel import Camera, Fit
    from flint import FLINT_SCALE
    cam = Camera(yaw=35, pitch=PITCH)
    scale = 9.0
    ims = []
    for m in _cast:
        v = m.variants[0]
        s = scale * (FLINT_SCALE if m.key == 'flint' else 1.0)
        e = extents(v.model, cam)
        w, h = int((e[1] - e[0]) * s) + 2 * PAD, int((e[3] - e[2]) * s) + 2 * PAD
        fit = Fit(s, PAD - e[0] * s, h - PAD - e[3] * s, w, h)
        from charrender import render_char
        from voxel import render
        light = light_for(cam.yaw)
        if v.ch is not None:
            rgba = render_char(v.ch, v.pal_key if m.kind == 'evochi' else 'amber', 'default', cam, w, h, fit=fit,
                               light=light, pal=v.pal, pal_key=v.pal_key).rgba
        else:
            from wilds_foes import OUTLINE
            rgba = render(v.model, {}, cam, w, h, fit=fit, light=light, ss=3, outline_px=max(1.5, s * 0.21), outline_col=OUTLINE,
                          inner_thresh=2.2, inner_alpha=0.8, inner_px=max(0.6, s * 0.045)).rgba
        ims.append((m.name, Image.fromarray(rgba, 'RGBA')))
    H = max(i.height for _, i in ims) + 150
    W = sum(i.width for _, i in ims) + 60
    img = Image.new('RGB', (W, H), BG)
    d = ImageDraw.Draw(img)
    d.text((30, 20), 'The cast of Evochi', font=font(44), fill=INKC)
    x = 30
    base = H - 60
    for name, im in ims:
        img.paste(im, (x, base - im.height + PAD), im)
        tw = d.textlength(name, font=font(18, False))
        d.text((x + (im.width - tw) / 2, base + 10), name, font=font(18, False), fill=SUB)
        x += im.width
    img.save(os.path.join(out, 'cast_lineup.png'), optimize=True)
    print('lineup', img.size, flush=True)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2:] or None)

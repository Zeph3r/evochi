"""A review sheet of the cinematic Evochi (cine_pose.py + cine_faces.py), laid out like the "Evochi Combat
Expressions (Improved)" concept: per stage, the three beats of the boss entrance posed, with their effects (the
roar's burst, sweat, dust), and three face close-ups under each (the takes: expr.0, expr, expr.2).

    python3 cine_review.py OUT.png [palette]
"""
from __future__ import annotations

import math
import os
import sys
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from cine_pose import posed, CAMS                                 # noqa: E402
from charrender import render_char, face_quads                    # noqa: E402
from characters import build, paint_face                          # noqa: E402
from decals import Canvas                                         # noqa: E402
from palettes import palette as get_palette                       # noqa: E402
from voxel import fit_camera, model_extent_points, project_px     # noqa: E402
from turnarounds import font, light_for                           # noqa: E402

BEATS = [('shout', 'the roar hits'), ('strain', 'eyes shut against the blast'), ('fierce', 'digs in, holds its ground')]
STAGES = {1: ('Eggling', 'Young, expressive,\nadorable but brave.\nBig emotions.'),
          2: ('Juvenile', 'More confident,\nenergetic and\nexpressive.'),
          3: ('Elder', 'Calm, powerful\nand intimidating.\nControlled strength.')}
BG = (250, 236, 222)
INK = (52, 36, 30)
SUB = (120, 96, 82)
TILE = (247, 228, 210)
CW, CH = 700, 470          # a posed cell
TW, TH = 214, 150          # a face close-up
LEFT = 330
SS = 3                     # the effects are drawn this much bigger, then scaled down


def _cell(args):
    stage, beat, pal, fit = args
    ch = posed(stage, beat)
    cam = CAMS[stage]
    out = render_char(ch, pal, beat, cam, fit.w, fit.h, fit=fit, light=light_for(cam.yaw))
    pts = np.concatenate([q.pts for q in face_quads(ch, get_palette(pal), pal, beat)])
    return stage, beat, out.rgba, project_px(cam, fit, pts)


def _fit(stage):
    pts = np.concatenate([model_extent_points(posed(stage, b).model) for b, _ in BEATS])
    f = fit_camera(CAMS[stage], pts, CW, CH, margin=0.05)
    return f


def flat_face(stage, expr, pal):
    """the face alone, flat, as on the concept's close-up tiles"""
    ch = build(stage)
    u0, u1, v0, v1 = ch.face_extent
    cv = Canvas(u0 - 2, u1 + 2, v0 - 4, v1 + 3, cell=0.05)
    paint_face(ch, cv, get_palette(pal), expr)
    rgb = cv.rgb / (255.0 if cv.rgb.max() > 1.5 else 1.0)
    a = cv.a[..., None]
    bg = np.array(TILE, np.float32) / 255
    img = (np.clip(rgb * a + bg * (1 - a), 0, 1)[::-1] * 255).astype(np.uint8)
    ys, xs = np.nonzero(cv.a[::-1] > 0)
    cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
    w = max(xs.max() - xs.min(), (ys.max() - ys.min()) * TW / TH) * 1.1
    h = w * TH / TW
    im = Image.fromarray(img)
    return im.crop((int(cx - w / 2), int(cy - h / 2), int(cx + w / 2), int(cy + h / 2))).resize((TW, TH), Image.LANCZOS)


# ---- the effects, drawn over a posed cell ------------------------------------------------------------------------
BURST = (226, 146, 92)
DUST = (232, 218, 198, 235)
DUST_EDGE = (204, 184, 160, 235)


def _wedge(d, o, ang, r0, r1, w, col):
    a = math.radians(ang)
    ux, uy = math.cos(a), math.sin(a)
    px, py = -uy, ux
    p0 = (o[0] + ux * r0, o[1] + uy * r0)
    p1 = (o[0] + ux * r1, o[1] + uy * r1)
    d.polygon([(p0[0] + px * w * 0.15, p0[1] + py * w * 0.15), (p1[0] + px * w, p1[1] + py * w),
               (p1[0] - px * w, p1[1] - py * w), (p0[0] - px * w * 0.15, p0[1] - py * w * 0.15)], fill=col)


def _drop(d, x, y, s, ang=0.0):
    """a sweat drop flying off: a round bottom, a point toward where it came from"""
    D = 2.3 * s
    phi = math.acos(s / D)
    t0 = math.radians(-90 + ang)                         # the tip's direction (up, tipped by ang)
    pts = [(x + D * math.cos(t0), y + D * math.sin(t0))]
    for t in np.linspace(t0 + phi, t0 + 2 * math.pi - phi, 30):
        pts.append((x + s * math.cos(t), y + s * math.sin(t)))
    d.polygon(pts, fill=(226, 243, 252), outline=INK)
    d.line(pts + [pts[0]], fill=INK, width=max(2, int(s * 0.3)), joint='curve')


def _arc(d, x, y, r, a0, a1, w):
    d.arc((x - r, y - r, x + r, y + r), a0, a1, fill=INK, width=w)


def _puff(d, x, y, r, rng):
    for _ in range(4):
        dx, dy, rr = rng.uniform(-r, r), rng.uniform(-r * 0.35, r * 0.1), r * rng.uniform(0.45, 0.8)
        d.ellipse((x + dx - rr - 2, y + dy - rr - 2, x + dx + rr + 2, y + dy + rr + 2), fill=DUST_EDGE)
    for _ in range(4):
        dx, dy, rr = rng.uniform(-r, r) * 0.8, rng.uniform(-r * 0.35, r * 0.1), r * rng.uniform(0.4, 0.72)
        d.ellipse((x + dx - rr, y + dy - rr, x + dx + rr, y + dy + rr), fill=DUST)


def effects(cell, beat, face_px, stage):
    """the roar's burst by the face (shout), sweat flying off (strain), effort marks (fierce), dust at the feet"""
    a = np.asarray(cell)[..., 3]
    ys, xs = np.nonzero(a > 30)
    gy = ys.max()
    foot = xs[ys > gy - 0.08 * (gy - ys.min())]
    x0, x1 = foot.min(), foot.max()
    top = ys.min()
    fx0, fy0 = face_px.min(0)
    fx1, fy1 = face_px.max(0)
    fw, fh = fx1 - fx0, fy1 - fy0
    right = xs.max()
    rng = np.random.default_rng(stage * 10 + len(beat))
    lay = Image.new('RGBA', (cell.width * SS, cell.height * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    S = lambda v: v * SS
    if beat == 'shout':
        o = (S(max(fx1, right - 0.1 * fw) + 0.06 * fw), S(fy0 + fh * 0.5))
        for k, ang in enumerate((-58, -32, -8, 16, 40)):
            L = fw * (0.34 + 0.12 * (k % 2))
            _wedge(d, o, ang, S(fw * 0.12), S(fw * 0.12 + L), S(fw * 0.035), BURST)
    elif beat == 'strain':
        for k, (dx, dy, s, ang) in enumerate(((0.15, -0.25, 0.07, 20), (0.42, -0.05, 0.055, 35),
                                              (0.3, 0.32, 0.05, 55), (-0.35, -0.42, 0.045, -15))):
            x = (right if dx > 0 else fx0) + dx * fw
            _drop(d, S(x), S(top + (fy0 - top) * 0.5 + dy * fh + fh * 0.3), S(fw * s), ang)
        for k, (dx, dy) in enumerate(((0.1, -0.05), (0.2, 0.12))):
            _arc(d, S(right + dx * fw), S(fy0 + dy * fh), S(fw * 0.12), 200 + 25 * k, 280 + 25 * k, max(2, int(S(fw * 0.018))))
    else:
        o = (S(right + 0.02 * fw), S(fy0 + fh * 0.1))
        for ang in (-50, -26, -2):
            _wedge(d, o, ang, S(fw * 0.1), S(fw * 0.34), S(fw * 0.028), BURST)
    back = Image.new('RGBA', lay.size, (0, 0, 0, 0))
    db = ImageDraw.Draw(back)
    sz = (x1 - x0) * 0.09
    for x, y, r in ((x0 - sz * 0.6, gy - sz * 0.3, sz), (x0 + sz * 0.6, gy, sz * 0.7), (x1 + sz * 0.4, gy - sz * 0.2, sz * 0.85)):
        _puff(db, S(x), S(y), S(r), rng)
    if beat == 'strain':
        _puff(db, S(x0 - sz * 1.6), S(gy - sz * 0.4), S(sz * 0.8), rng)
    base = Image.new('RGBA', cell.size, (0, 0, 0, 0))
    base.alpha_composite(back.resize(cell.size, Image.LANCZOS))     # the dust behind its feet,
    base.alpha_composite(cell)
    base.alpha_composite(lay.resize(cell.size, Image.LANCZOS))      # the burst, sweat and marks in front
    return base


def rounded(d, box, r, fill, outline=None):
    d.rounded_rectangle(box, r, fill=fill, outline=outline, width=2)


def main(out, pal='amber'):
    fits = {s: _fit(s) for s in STAGES}
    jobs = [(s, b, pal, fits[s]) for s in STAGES for b, _ in BEATS]
    with ProcessPoolExecutor(2) as ex:
        res = list(ex.map(_cell, jobs))
    gapx = 18
    W = LEFT + 3 * CW + 2 * gapx + 30
    top = 150
    rowh = 52 + CH + TH + 40
    img = Image.new('RGB', (W, top + 3 * rowh + 30), BG)
    d = ImageDraw.Draw(img)
    d.text((40, 28), 'Evochi Combat Expressions', font=font(54), fill=INK)
    d.text((40, 96), 'More distinct, expressive and cinematic while keeping the original design and charm',
           font=font(24, False), fill=SUB)
    rounded(d, (W - 700, 30, W - 40, 112), 16, (240, 222, 204))
    d.multiline_text((W - 680, 44), 'Each expression has a clear emotion, silhouette and personality.\n'
                     'For the Wilds\' boss entrance: the roar hits, it braces, it holds its ground.',
                     font=font(19, False), fill=SUB, spacing=8)
    for i, (stage, beat, rgba, px) in enumerate(res):
        r, c = divmod(i, 3)
        y = top + r * rowh
        if c == 0:
            if r:
                d.line((40, y - 22, W - 40, y - 22), fill=(226, 206, 186), width=2)
            name, desc = STAGES[stage]
            d.text((40, y + 120), name, font=font(44), fill=INK)
            d.multiline_text((40, y + 182), desc, font=font(24, False), fill=SUB, spacing=6)
            rounded(d, (40, y + 52 + CH + 4, LEFT - 40, y + 52 + CH + 4 + TH), 14, (243, 226, 208))
            d.text((LEFT / 2 - 75, y + 52 + CH + 4 + TH / 2 - 12), 'Face close-ups', font=font(19, False), fill=SUB)
        x = LEFT + c * (CW + gapx)
        key, what = BEATS[c]
        t1 = key.capitalize()
        f1, f2 = font(22), font(22, False)
        w1 = d.textlength(t1, font=f1)
        w2 = d.textlength(' (%s)' % what, font=f2)
        tx = x + (CW - w1 - w2) / 2
        d.text((tx, y), t1, font=f1, fill=INK)
        d.text((tx + w1, y), ' (%s)' % what, font=f2, fill=SUB)
        cell = effects(Image.fromarray(rgba), beat, px, stage)
        img.paste(cell, (x, y + 34), cell)
        for k, take in enumerate(('.0', '', '.2')):
            tile = flat_face(stage, beat + take, pal)
            tx = x + (CW - 3 * TW - 2 * 14) // 2 + k * (TW + 14)
            ty = y + 52 + CH + 4
            mask = Image.new('L', (TW, TH), 0)
            ImageDraw.Draw(mask).rounded_rectangle((0, 0, TW - 1, TH - 1), 12, fill=255)
            img.paste(tile, (tx, ty), mask)
            d.rounded_rectangle((tx, ty, tx + TW - 1, ty + TH - 1), 12, outline=(232, 204, 178), width=2)
    img.save(out, optimize=True)
    print(out, img.size)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else 'amber')

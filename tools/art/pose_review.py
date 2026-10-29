"""A review sheet of the posed cinematic Evochi (cine_pose.py) with the kit faces (face_kit.py), laid out like the
"Evochi Combat Posing Improvements" sheet: per stage, shout, strain and fierce posed, from the game's cinematic
camera with its lighting (cine_evochi.py), and each beat's face decal.

    python3 pose_review.py OUT.png [personality] [palette]
"""
from __future__ import annotations

import os
import sys
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cine_evochi as CE                                          # noqa: E402
from cine_pose import posed, NOTES                                # noqa: E402
from charrender import render_char                                # noqa: E402
from voxel import fit_camera, model_extent_points                 # noqa: E402
from turnarounds import font                                      # noqa: E402
from face_review import flat_decal                                # noqa: E402
import face_kit as FK                                             # noqa: E402

BEATS = [('shout', 'the roar hits'), ('strain', 'eyes shut against the blast'), ('fierce', 'digs in, holds its ground')]
STAGES = {1: ('Eggling', 'Young, expressive,\nadorable but brave.\nBig feelings.'),
          2: ('Juvenile', 'More confident,\nenergetic and\nexpressive.'),
          3: ('Elder', 'Calm, powerful\nand intimidating.\nControlled strength.')}
BG = (250, 238, 224)
INK = (52, 36, 30)
SUB = (120, 96, 82)
CW, CH = 600, 440
TW, TH = 180, 112
LEFT = 300


def _cell(args):
    stage, beat, expr, pal, fit = args
    r = render_char(posed(stage, beat), pal, expr, CE.CAM, fit.w, fit.h, fit=fit)
    return r.rgba


def _fit(stage):
    pts = np.concatenate([model_extent_points(posed(stage, b).model) for b, _ in BEATS])
    return fit_camera(CE.CAM, pts, CW, CH, margin=0.04)


def tile(name, pal):
    im = flat_decal(name, pal, 768)
    a = np.asarray(im).astype(int)
    bgc = a[2, 2]
    ys, xs = np.nonzero(np.abs(a - bgc).sum(-1) > 30)
    cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
    w = max(xs.max() - xs.min(), (ys.max() - ys.min()) * TW / TH) * 1.12
    h = w * TH / TW
    return im.crop((int(cx - w / 2), int(cy - h / 2), int(cx + w / 2), int(cy + h / 2))).resize((TW, TH), Image.LANCZOS)


def main(out, pers='brave', pal='amber'):
    fits = {s: _fit(s) for s in STAGES}
    jobs = []
    for s in STAGES:
        for b, _ in BEATS:
            jobs.append((s, b, b if pers == 'brave' else '%s:%s' % (b, pers), pal, fits[s]))
    with ProcessPoolExecutor(2) as ex:
        cells = list(ex.map(_cell, jobs))
    gap = 14
    W = LEFT + 3 * CW + 2 * gap + 30
    top = 130
    rowh = 40 + CH + TH + 46
    img = Image.new('RGB', (W, top + 3 * rowh + 10), BG)
    d = ImageDraw.Draw(img)
    d.text((40, 26), 'Evochi Combat Posing', font=font(50), fill=INK)
    d.text((40, 88), 'The game\'s models, posed per beat (the face is the %s kit face). The boss entrance\'s camera and '
           'lighting (yaw -32, pitch -7).' % pers.capitalize(), font=font(21, False), fill=SUB)
    for i, (job, rgba) in enumerate(zip(jobs, cells)):
        stage, beat = job[0], job[1]
        r, c = divmod(i, 3)
        y = top + r * rowh
        if c == 0:
            if r:
                d.line((40, y - 16, W - 40, y - 16), fill=(228, 210, 190), width=2)
            name, desc = STAGES[stage]
            d.text((40, y + 70), name, font=font(40), fill=INK)
            d.multiline_text((40, y + 126), desc, font=font(22, False), fill=SUB, spacing=6)
        x = LEFT + c * (CW + gap)
        key, what = BEATS[c]
        f1, f2 = font(23), font(19, False)
        d.text((x + 8, y), key.capitalize(), font=f1, fill=INK)
        d.text((x + 8 + d.textlength(key.capitalize() + ' ', font=f1), y + 3), '(%s)' % what, font=f2, fill=SUB)
        cell = Image.fromarray(rgba)
        img.paste(cell, (x, y + 34), cell)
        note = NOTES[stage][beat]
        t = tile('%s_%s_%s' % (pers, FK.STAGE_NAMES[stage], beat) if True else '', pal)
        tx, ty = x + 40, y + 34 + CH + 4
        mask = Image.new('L', (TW, TH), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, TW - 1, TH - 1), 10, fill=255)
        img.paste(t, (tx, ty), mask)
        d.rounded_rectangle((tx, ty, tx + TW - 1, ty + TH - 1), 10, outline=(232, 206, 180), width=2)
        d.multiline_text((tx + TW + 18, ty + 8), _wrap(d, note, font(17, False), CW - (tx - x) - TW - 30), font=font(17, False), fill=SUB, spacing=4)
    img.save(out, optimize=True)
    print(out, img.size)


def _wrap(d, text, f, width):
    words, lines, cur = text.split(), [], ''
    for w in words:
        t = (cur + ' ' + w).strip()
        if d.textlength(t, font=f) > width and cur:
            lines.append(cur)
            cur = w
        else:
            cur = t
    lines.append(cur)
    return '\n'.join(lines)


if __name__ == '__main__':
    a = sys.argv
    main(a[1], a[2] if len(a) > 2 else 'brave', a[3] if len(a) > 3 else 'amber')

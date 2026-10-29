"""Fidelity check of the combat faces (face_kit.py) on the real models: per expression, the original reference,
the in-game cinematic render (cine_evochi.py's camera, framing and lighting, the model untouched), a close-up of
the render's face, and the kit's flat decal.

    python3 face_review.py OUT.png REFERENCE.png STAGE PERSONALITY [palette] [x0,y0,x1,y1 x3]

The reference crops (one box per expression, in the reference image's pixels) default to the Eggling row of
02_Brave_Reference.png.
"""
from __future__ import annotations

import io
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cine_evochi as CE                                          # noqa: E402
from characters import build                                      # noqa: E402
from charrender import render_char, face_quads                    # noqa: E402
from palettes import palette                                      # noqa: E402
from voxel import project_px                                      # noqa: E402
from turnarounds import font                                      # noqa: E402
import face_kit as FK                                             # noqa: E402

BG = (250, 240, 228)
INK = (52, 36, 30)
SUB = (120, 96, 82)
BRAVE_EGGLING = [(165, 85, 588, 392), (612, 85, 1008, 392), (1040, 85, 1430, 392)]
COLW = 560


def flat_decal(name, pal, w):
    import cairosvg
    svg = open(FK.svg_path(name)).read()
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=w, output_height=int(w * 160 / 256))
    im = Image.open(io.BytesIO(png)).convert('RGBA')
    bg = Image.new('RGBA', im.size, (246, 226, 206, 255))
    bg.alpha_composite(im)
    return bg.convert('RGB')


def main(out, ref, stage, pers, pal='amber', boxes=None):
    boxes = boxes or BRAVE_EGGLING
    ch = build(stage)
    fit = CE._fit(stage)
    R = Image.open(ref).convert('RGB')
    cols = []
    for state in FK.STATES:
        expr = state if pers == 'brave' else '%s:%s' % (state, pers)
        r = render_char(ch, pal, expr, CE.CAM, fit.w, fit.h, fit=fit)
        px = project_px(CE.CAM, fit, np.concatenate([q.pts for q in face_quads(ch, palette(pal), pal, expr)]))
        cols.append((state, Image.fromarray(r.rgba), px))
    rowh = [None] * 4
    W = 60 + 3 * COLW + 2 * 30 + 40
    img = Image.new('RGB', (W, 3000), BG)
    d = ImageDraw.Draw(img)
    d.text((60, 34), '%s %s, %s: the kit faces on the in-game model' % (pal.capitalize(), FK.STAGE_NAMES[stage].capitalize(),
                                                                       pers.capitalize()), font=font(40), fill=INK)
    d.text((60, 92), 'Same camera, framing and lighting as the game\'s boss entrance (yaw -32, pitch -7). The model, '
           'its voxels and materials are unchanged; only the face is new.', font=font(20, False), fill=SUB)
    y = 150
    labels = ['Original reference', 'In game (rendered)', 'In game, the face close up', 'Face decal (flat: the kit, or its correction)']
    for row in range(4):
        tiles = []
        for c, (state, cell, px) in enumerate(cols):
            if row == 0:
                t = R.crop(boxes[c])
            elif row == 1:
                t = Image.new('RGB', cell.size, BG)
                t.paste(cell, (0, 0), cell)
                a = np.asarray(cell)[..., 3]
                ys, xs = np.nonzero(a > 10)
                t = t.crop((max(0, xs.min() - 20), max(0, ys.min() - 20), min(cell.width, xs.max() + 20), min(cell.height, ys.max() + 20)))
            elif row == 2:
                (x0, y0), (x1, y1) = px.min(0), px.max(0)       # brows, cheeks and mouth: the whole face
                t = Image.new('RGB', cell.size, BG)
                t.paste(cell, (0, 0), cell)
                p = (x1 - x0) * 0.06
                t = t.crop((int(x0 - p), int(y0 - p), int(x1 + p), int(y1 + p)))
            else:
                t = flat_decal('%s_%s_%s' % (pers, FK.STAGE_NAMES[stage], state), palette(pal), 512)
            t.thumbnail((COLW, 430 if row < 2 else 300), Image.LANCZOS)
            tiles.append(t)
        h = max(t.height for t in tiles)
        d.text((60, y), labels[row], font=font(22), fill=INK)
        y += 36
        for c, t in enumerate(tiles):
            x = 60 + c * (COLW + 30)
            img.paste(t, (x + (COLW - t.width) // 2, y + (h - t.height) // 2))
            if row == 0:
                d.text((x, y - 70 + 0), '', font=font(20), fill=INK)
        y += h + 34
    for c, (state, _, _) in enumerate(cols):
        d.text((60 + c * (COLW + 30) + COLW // 2 - 40, 150 - 2), '', font=font(22), fill=INK)
    img = img.crop((0, 0, W, y + 10))
    # column heads
    d = ImageDraw.Draw(img)
    for c, state in enumerate(FK.STATES):
        tx = 60 + c * (COLW + 30) + COLW - 140
        d.text((tx, 150), state.capitalize(), font=font(24), fill=INK)
    img.save(out, optimize=True)
    print(out, img.size)


if __name__ == '__main__':
    a = sys.argv
    boxes = None
    if len(a) > 6:
        boxes = [tuple(int(v) for v in b.split(',')) for b in a[6:9]]
    main(a[1], a[2], int(a[3]), a[4], a[5] if len(a) > 5 else 'amber', boxes)

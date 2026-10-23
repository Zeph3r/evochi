"""Flint's model sheet: a turnaround (eight views round him on one baseline, at one scale), his faces, and
beside an ordinary Obsidian Elder for size. From flint.py's model, rendered with the game's flat renderer.

    python3 flint_turnaround.py OUT_DIR
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from build_characters import SCALE_HERO, fit_for  # noqa: E402
from characters import build  # noqa: E402
from charrender import render_char  # noqa: E402
from flint import FLINT_SCALE, flint, flint_palette  # noqa: E402
from voxel import Camera, project_px  # noqa: E402

FONTS = '/home/claude/evochi/flutter/assets/fonts/'
BG = (232, 226, 214)
INK = (59, 41, 35)
VIEWS = [(0, 'Front'), (45, 'Front 3/4'), (90, 'Side'), (135, 'Back 3/4'), (180, 'Back'), (-135, 'Back 3/4'), (-90, 'Side'), (-45, 'Front 3/4')]


def font(w, size):
    return ImageFont.truetype(FONTS + {'black': 'Nunito-Black.ttf', 'bold': 'Nunito-Bold.ttf', 'xbold': 'Nunito-ExtraBold.ttf'}[w], size)


def shot(ch, yaw, expr, scale, pal=None, pal_key='flint', variant='obsidian', pitch=10):
    cam = Camera(yaw=yaw, pitch=pitch)
    fit = fit_for([ch.model], cam, scale)
    o = render_char(ch, variant, expr, cam, fit.w, fit.h, fit=fit, pal=pal, pal_key=f'{pal_key}_{yaw}_{pitch}')
    g = project_px(cam, fit, [(0, 0, 0)])[0]
    return Image.fromarray(o.rgba, 'RGBA'), g


def row(items, gap=26, pad=30, label_h=40):
    """Images standing on one baseline (their ground points), labelled underneath."""
    above = max(g[1] for _, im, g in items)
    below = max(im.height - g[1] for _, im, g in items)
    W = sum(im.width for _, im, _ in items) + gap * (len(items) - 1) + 2 * pad
    H = int(above + below) + label_h + 2 * pad
    b = Image.new('RGBA', (W, H), BG + (255,))
    d = ImageDraw.Draw(b)
    x = pad
    base = pad + above
    d.line([(pad - 10, base), (W - pad + 10, base)], fill=(205, 196, 180), width=3)
    for lab, im, g in items:
        b.alpha_composite(im, (int(x), int(base - g[1])))
        f = font('xbold', 22)
        tw = d.textlength(lab, font=f)
        d.text((x + im.width / 2 - tw / 2, H - pad - label_h + 8), lab, font=f, fill=INK)
        x += im.width + gap
    return b


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    fl = flint()
    pal = flint_palette()
    scale = SCALE_HERO * FLINT_SCALE * 0.62
    turn = row([(lab, *shot(fl, yaw, 'default', scale, pal)) for yaw, lab in VIEWS])
    faces = row([(e.title() if e != 'default' else 'Neutral', *shot(fl, 30, e, scale * 1.15, pal))
                 for e in ('default', 'happy', 'thinking', 'surprised', 'worried', 'determined')])
    plain = build(3)
    elder = shot(plain, 30, 'default', scale / FLINT_SCALE, None, 'elder', 'obsidian')
    size = row([('An Obsidian Elder', *elder), ('Flint (1.4x)', *shot(fl, 30, 'happy', scale, pal))])
    # the sheet
    W = max(turn.width, faces.width + size.width + 40) + 80
    H = 120 + turn.height + 70 + max(faces.height, size.height) + 40
    b = Image.new('RGB', (W, H), (36, 32, 44))
    d = ImageDraw.Draw(b)
    d.text((40, 24), 'Flint, keeper of the mines: model sheet', font=font('black', 40), fill=(255, 236, 200))
    d.text((40, 76), 'An Obsidian Elder, 1.4x. Hard hat with a headlamp, heavy-lidded old eyes, no blush, grey brows and chin tuft, '
           'frosted spikes, a red bandana, a tool belt and a pickaxe over his shoulder.', font=font('bold', 21), fill=(205, 205, 215))
    b.paste(turn.convert('RGB'), (40, 120))
    y = 120 + turn.height + 30
    d.text((40, y), 'Faces', font=font('xbold', 26), fill=(255, 214, 120))
    d.text((80 + faces.width, y), 'Size', font=font('xbold', 26), fill=(255, 214, 120))
    b.paste(faces.convert('RGB'), (40, y + 40))
    b.paste(size.convert('RGB'), (80 + faces.width, y + 40))
    b.save(os.path.join(out, 'flint_model_sheet.png'), optimize=True)
    for yaw, lab in VIEWS[:5]:
        im, _ = shot(fl, yaw, 'default', SCALE_HERO * FLINT_SCALE, pal)
        im.save(os.path.join(out, f'flint_turn_{yaw}.png'))
    print('ok', b.size)


if __name__ == '__main__':
    main()

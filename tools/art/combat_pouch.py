# The Wilds' Pouch button in the combat pack's style: the pack's utility frame (its Eat button: a wood rim round a
# parchment face), the apple lifted off the face (refilled smoothly from the parchment round it), and a drawstring
# pouch drawn in the pack's icon style (a thick dark outline round flat, softly shaded leather, a stitched leaf).
#   python3 tools/art/combat_pouch.py <pack dir> flutter/assets/art/combat
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as nd

K = 4
OUT = (90, 52, 30, 255)
LEATHER, LIGHT, SHADE, TIE, FRILL = (196, 132, 76), (226, 168, 106), (156, 96, 52), (122, 74, 40), (214, 158, 98)


def erase_icon(a, hole_r=70):
    """the face with its icon lifted off: the parchment carried in from the ring round it (a harmonic fill)"""
    rgb = a[..., :3].astype(float)
    yy, xx = np.mgrid[0:256, 0:256]
    d = np.hypot(xx - 127.5, yy - 127.5)
    hole = d < hole_r
    small = np.array(Image.fromarray(rgb.astype(np.uint8)).resize((64, 64), Image.BOX)).astype(float)
    sh = np.array(Image.fromarray(hole.astype(np.uint8) * 255).resize((64, 64), Image.NEAREST)) > 0
    for _ in range(1500):
        small[sh] = nd.uniform_filter(small, (3, 3, 1))[sh]
    up = np.array(Image.fromarray(small.clip(0, 255).astype(np.uint8)).resize((256, 256), Image.BICUBIC)).astype(float)
    out = rgb.copy()
    out[hole] = up[hole]
    for _ in range(300):
        out[hole] = nd.uniform_filter(out, (3, 3, 1))[hole]
    w = np.clip((hole_r + 2 - d) / 4, 0, 1)[..., None]
    res = a.astype(float).copy()
    res[..., :3] = rgb * (1 - w) + out * w
    return res


def clean_bottom(a, r=117.5):
    """the pack baked its label's tail into the shadow under the rim: refill that sector from 52 degrees round"""
    yy, xx = np.mgrid[0:256, 0:256].astype(float)
    d = np.hypot(xx - 127.5, yy - 127.5)
    phi = np.degrees(np.arctan2(xx - 127.5, yy - 127.5))
    w = np.clip((40 - np.abs(phi)) / 8, 0, 1) * np.clip((d - (r - 1.5)) / 2.5, 0, 1)
    th = np.radians(phi + np.where(phi >= 0, 1, -1) * 52)
    sx, sy = 127.5 + d * np.sin(th), 127.5 + d * np.cos(th)
    src = np.stack([nd.map_coordinates(a[..., c], [sy, sx], order=1, mode='nearest') for c in range(4)], -1)
    return a * (1 - w[..., None]) + src * w[..., None]


def pouch(scale=1.0):
    n = 256 * K
    im = Image.new('RGBA', (n, n))
    d = ImageDraw.Draw(im)
    c = 128 * K

    def P(x, y):
        return (c + (x - 128) * K * scale, c + (y - 128) * K * scale)

    def shape(grow, fill, layer):
        g = grow * K * scale
        # the frill, opening above the tie
        d.polygon([P(98 - grow, 92), P(104, 74 - grow), P(116, 82), P(128, 70 - grow), P(140, 82), P(152, 74 - grow), P(158 + grow, 92)], fill=fill)
        # the bag: narrow at the neck, round below
        d.ellipse([P(80 - grow, 98 - grow), P(176 + grow, 178 + grow)], fill=fill)
        d.polygon([P(104 - grow, 96), P(152 + grow, 96), P(170 + grow, 128), P(86 - grow, 128)], fill=fill)
        if layer == 'fill':
            return
    shape(6, OUT, 'out')
    shape(0, LEATHER + (255,), 'fill')
    # shading: light down its left, shade down its right and under it
    d.ellipse([P(88, 106), P(132, 168)], fill=LIGHT + (255,))
    d.ellipse([P(140, 116), P(172, 174)], fill=SHADE + (255,))
    d.ellipse([P(94, 112), P(160, 172)], fill=LEATHER + (255,))
    d.ellipse([P(96, 114), P(118, 150)], fill=LIGHT + (255,))
    # the frill, lighter
    d.polygon([P(102, 90), P(106, 78), P(117, 85), P(128, 74), P(139, 85), P(150, 78), P(154, 90)], fill=FRILL + (255,))
    # its tie, and the cord's two ends hanging
    d.rounded_rectangle([P(98, 88), P(158, 100)], radius=4 * K * scale, fill=OUT)
    d.rounded_rectangle([P(100, 90), P(156, 98)], radius=3 * K * scale, fill=TIE + (255,))
    for (x0, y0, x1, y1) in ((148, 96, 158, 124), (156, 96, 170, 118)):
        d.line([P(x0, y0), P(x1, y1)], fill=OUT, width=int(7 * K * scale))
        d.line([P(x0, y0), P(x1, y1)], fill=TIE + (255,), width=int(3.5 * K * scale))
        d.ellipse([P(x1 - 4, y1 - 4), P(x1 + 4, y1 + 4)], fill=OUT)
        d.ellipse([P(x1 - 2.4, y1 - 2.4), P(x1 + 2.4, y1 + 2.4)], fill=(232, 176, 92, 255))
    # a stitched leaf on its front
    leaf = [P(116, 150), P(124, 132), P(140, 126), P(136, 144)]
    d.polygon(leaf, fill=(60, 110, 44, 255))
    d.polygon([P(118, 148), P(125, 134), P(137, 129), P(134, 143)], fill=(108, 178, 72, 255))
    d.line([P(119, 147), P(134, 131)], fill=(60, 110, 44, 255), width=int(1.6 * K * scale))
    return im.resize((256, 256), Image.LANCZOS)


if __name__ == '__main__':
    pack, out = sys.argv[1], sys.argv[2]
    for st in ('normal', 'ready', 'pressed', 'disabled'):
        a = np.array(Image.open(os.path.join(pack, 'png', '256', 'eat', f'{st}.png')).convert('RGBA')).astype(float)
        a = clean_bottom(a, 117.5 - (8 if st == 'pressed' else 0))
        a = erase_icon(a, 66 if st == 'pressed' else 70)
        base = Image.fromarray(a.clip(0, 255).astype(np.uint8), 'RGBA')
        icon = pouch(0.93 if st == 'pressed' else 1.0)
        if st == 'disabled':  # grey and faint, as the pack's own
            ia = np.array(icon).astype(float)
            ia[..., :3] = ia[..., :3].mean(-1, keepdims=True) * 0.85
            ia[..., 3] *= 0.55
            icon = Image.fromarray(ia.astype(np.uint8), 'RGBA')
        base.alpha_composite(icon)
        base.save(os.path.join(out, f'pouch_{st}.webp'), 'WEBP', quality=90, method=6, alpha_quality=95)

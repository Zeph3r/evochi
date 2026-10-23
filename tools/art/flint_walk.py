"""Flint for the walkable Old Trail: his sprite standing at the Crossing (the walking camera's 35 degrees,
facing down the trail toward you as you come), and his faces for the talk sheet. From flint.py's model,
in the game's flat look (the same renderer as your Evochi's walk sheets, so the two match).

    python3 flint_walk.py            -> flutter/assets/art/trail/flint_walk.webp, flint_face_<expr>.webp,
                                        flint.json (the sprite's ground and top points, his height in world
                                        units at the village's 1.2x, and the faces with their face point)
"""
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_characters import fit_for  # noqa: E402
from characters import build  # noqa: E402
from charrender import render_char  # noqa: E402
from flint import FLINT_SCALE, flint, flint_palette  # noqa: E402
from voxel import Camera, project_px  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'flutter', 'assets', 'art', 'trail')
ELDER_H = 3.4 * 1.2          # an Elder's height in the village, world units (village_walk.dart's _evochiH)
WALK_SCALE = 6.0             # sprite px per model unit for the walk sprite (it's drawn at ~3x that on a phone)
FACE_SCALE = 9.0
FACES = ('default', 'happy', 'thinking', 'surprised', 'determined')


def shot(ch, cam, expr, scale, pal, key, variant='obsidian'):
    fit = fit_for([ch.model], cam, scale)
    o = render_char(ch, variant, expr, cam, fit.w, fit.h, fit=fit, pal=pal, pal_key=key)
    pts = {k: project_px(cam, fit, [v])[0] for k, v in ch.anchors.items()}
    return o.rgba, pts


def alpha_top(rgba):
    rows = np.nonzero(rgba[..., 3].max(1) > 40)[0]
    return int(rows[0])


def crop(rgba, pts, pad=4):
    ys, xs = np.nonzero(rgba[..., 3] > 0)
    x0, y0 = max(0, xs.min() - pad), max(0, ys.min() - pad)
    x1, y1 = min(rgba.shape[1], xs.max() + pad + 1), min(rgba.shape[0], ys.max() + pad + 1)
    return rgba[y0:y1, x0:x1], {k: (float(v[0] - x0), float(v[1] - y0)) for k, v in pts.items()}


def main():
    os.makedirs(OUT, exist_ok=True)
    fl, pal = flint(), flint_palette()
    # facing down the trail toward you, a little to the west (where you come from): the walk sheets'
    # SW-ish, between S and SW
    cam = Camera(yaw=30.0, pitch=35.0)
    sprite, pts = shot(fl, cam, 'happy', WALK_SCALE * FLINT_SCALE, pal, 'flint_walk')
    sprite, pts = crop(sprite, pts)
    # his height: an ordinary Obsidian Elder under the same camera and scale is ELDER_H tall in the village
    elder, ept = shot(build(3), cam, 'default', WALK_SCALE, None, 'elder_walk')
    he = ept['ground'][1] - alpha_top(elder)
    hf = pts['ground'][1] - alpha_top(sprite)
    # he is rendered FLINT_SCALE bigger, and stands FLINT_SCALE bigger in the world, so px map the same
    height = ELDER_H * hf / he
    Image.fromarray(sprite, 'RGBA').save(os.path.join(OUT, 'flint_walk.webp'), 'WEBP', lossless=True, quality=100, method=6)
    faces = {}
    fcam = Camera(yaw=30.0, pitch=10.0)
    for e in FACES:
        im, fp = shot(fl, fcam, e, FACE_SCALE * FLINT_SCALE, pal, 'flint_face')
        im, fp = crop(im, fp)
        fn = f'flint_face_{e}.webp'
        Image.fromarray(im, 'RGBA').save(os.path.join(OUT, fn), 'WEBP', lossless=True, quality=100, method=6)
        faces[e] = {'src': f'assets/art/trail/{fn}', 'w': im.shape[1], 'h': im.shape[0], 'face': [round(v, 1) for v in fp['face']],
                    'headTop': [round(v, 1) for v in fp['head_top']]}
    meta = {'art': 'assets/art/trail/flint_walk.webp', 'w': sprite.shape[1], 'h_px': sprite.shape[0],
            'ground': [round(v, 1) for v in pts['ground']], 'top': [round(pts['ground'][0], 1), float(alpha_top(sprite))],
            'height': round(height, 2), 'faces': faces}
    with open(os.path.join(OUT, 'flint.json'), 'w') as f:
        json.dump(meta, f, indent=1)
    print('flint', sprite.shape, 'height', round(height, 2), 'elder px', he, 'flint px', hf)


if __name__ == '__main__':
    main()

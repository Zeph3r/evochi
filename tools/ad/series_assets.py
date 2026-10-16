"""Extra art for the "evolved-first", nostalgia and Evolution Reveal videos (comp_v3.html).

- Elder turntables (36 views, 10 degrees apart, hero scale) in Ocean, Amethyst and the secret Aurora
- Elder expression sheets (Ocean, Amethyst, Forest, Aurora) and the Aurora Eggling/Juvenile
- the autumn outfit (leaf scarf + explorer hat) on all three Forest forms

python3 series_assets.py OUT_DIR [--turn] [--sheets] [--outfit]
"""
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'art'))

import palettes  # noqa: E402
from characters import build  # noqa: E402
from charrender import render_char  # noqa: E402
from accessories import wear, WEARABLES, FRAME_WEARABLES  # noqa: E402
from voxel import Camera, Fit, model_extent_points, project_px  # noqa: E402
from build_characters import fit_for, HERO_CAM, SCALE_HERO  # noqa: E402

A = os.path.join(ROOT, 'assets', 'characters')
out = sys.argv[1]
os.makedirs(out, exist_ok=True)

# The secret seventh colour, "Aurora": mint shell, teal pattern, violet crest, pink cheeks.
# shell, pattern, crest, cheeks, feet, foot shadow, eyes, claws
palettes._VARIANTS['aurora'] = ('#F2F4FB', '#C3B2F2', '#48C9C4', '#F4A6C6', '#5F6E80', '#44505E', '#282725', '#F6F3FF')
PAL = {v: palettes.palette(v) for v in ('ocean', 'amethyst', 'forest', 'aurora')}


def webp(arr_or_img, name, q=88):
    img = arr_or_img if isinstance(arr_or_img, Image.Image) else Image.fromarray(arr_or_img, 'RGBA')
    path = os.path.join(out, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, 'WEBP', quality=q, method=5)
    return path


_chars = {}
def char(stage):
    if stage not in _chars:
        ch = build(stage)
        worn = {k: wear(ch, k) for k in WEARABLES}
        fit = fit_for([ch.model] + [worn[k] for k in FRAME_WEARABLES], HERO_CAM[stage], SCALE_HERO)
        _chars[stage] = (ch, fit)
    return _chars[stage]


# ------------------------------------------------------------------ 1. Elder turntables
def turntables(pals=('ocean', 'amethyst', 'aurora'), n=36):
    ch, _ = char(3)
    yaws = [36 + k * (360 / n) for k in range(n)]
    cams = [Camera(yaw=y, pitch=13) for y in yaws]
    pts = model_extent_points(ch.model)
    lo = np.array([np.inf, np.inf]); hi = np.array([-np.inf, -np.inf])
    for cam in cams:
        sx, sy, _ = cam.project(pts)
        lo = np.minimum(lo, [sx.min(), sy.min()]); hi = np.maximum(hi, [sx.max(), sy.max()])
    pad = 10
    w = int(np.ceil((hi[0] - lo[0]) * SCALE_HERO + 2 * pad)); h = int(np.ceil((hi[1] - lo[1]) * SCALE_HERO + 2 * pad))
    w += w % 2; h += h % 2
    fit = Fit(SCALE_HERO, pad - lo[0] * SCALE_HERO, pad - lo[1] * SCALE_HERO, w, h)
    meta = {'w': w, 'h': h, 'n': n, 'yaw0': 36, 'frames': []}
    for k, cam in enumerate(cams):
        g = project_px(cam, fit, ch.anchors['ground'])[0]
        meta['frames'].append([round(float(g[0]), 1), round(float(g[1]), 1)])
    for p in pals:
        for k, cam in enumerate(cams):
            o = render_char(ch, p, 'default', cam, w, h, fit=fit, pal=PAL[p], pal_key=p)
            webp(o.rgba, f'turn3/{p}/y{k:02d}.webp')
        print('turntable', p, 'done', flush=True)
    json.dump(meta, open(os.path.join(out, 'turn3', 'meta.json'), 'w'))


# ------------------------------------------------------------------ 2. expression sheets
def sheets():
    for p, exprs in (('ocean', ['default', 'blink', 'happy', 'curious', 'surprised', 'excited', 'sleepy', 'determined']),
                     ('amethyst', ['default', 'blink', 'happy', 'curious']),
                     ('forest', ['default', 'blink', 'happy', 'curious'])):
        for e in exprs:
            im = Image.open(os.path.join(A, f'evochi_lizard_s03_{p}_{e}_left3q_f000.png')).convert('RGBA')
            webp(im, f'elder/{p}/{e}.webp')
        for st in ('s01', 's02'):
            for e in ('happy', 'default', 'blink', 'curious', 'sleepy', 'excited'):
                im = Image.open(os.path.join(A, f'evochi_lizard_{st}_{p}_{e}_left3q_f000.png')).convert('RGBA')
                webp(im, f'{st}/{p}/{e}.webp')
    # Aurora: rendered fresh (not in the game yet)
    for stage, exprs in ((1, ['happy', 'excited', 'default', 'blink']), (2, ['happy', 'default']), (3, ['default', 'blink', 'happy', 'curious', 'surprised'])):
        ch, fit = char(stage)
        for e in exprs:
            o = render_char(ch, 'aurora', e, HERO_CAM[stage], fit.w, fit.h, fit=fit, pal=PAL['aurora'], pal_key='aurora')
            webp(o.rgba, f'{"elder" if stage == 3 else "s%02d" % stage}/aurora/{e}.webp')
        print('aurora stage', stage, 'done', flush=True)


# ------------------------------------------------------------------ 3. autumn outfit on the Forest forms
def outfit():
    for st, expr in (('s01', 'happy'), ('s02', 'happy'), ('s03', 'happy'), ('s03', 'default'), ('s03', 'blink')):
        body = Image.open(os.path.join(A, f'evochi_lizard_{st}_forest_{expr}_left3q_f000.png')).convert('RGBA')
        for it, slot in (('leaf_scarf', 'neck'), ('explorer_hat', 'head')):
            ov = Image.open(os.path.join(A, f'item_{it}_{slot}_{st}_left3q.png')).convert('RGBA')
            body.alpha_composite(ov)
        webp(body, f'outfit/{st}_{expr}.webp')
    print('outfit done', flush=True)


if __name__ == '__main__':
    only = [a[2:] for a in sys.argv[2:] if a.startswith('--')]
    for name, fn in {'sheets': sheets, 'outfit': outfit, 'turn': turntables}.items():
        if not only or name in only:
            fn()

"""Re-make every wearable overlay the game draws over its Evochi sprites, after the wearables are refitted
(accessories.py), inside the frames the body sheets were made with (frames_frozen.json), so only the
overlays change:

  chars/sNN_overlays.webp          the home's hero view (as build_characters + build_web_assets pack them)
  chars/sNN_battle_overlays.webp   the encounter view
  wilds/cine_sNN_wear.webp         the Briarback entrance's Evochi (cine_evochi)

    python3 wear_refresh.py ASSETS_ART_DIR [stage ...]

(the walk's wearables: walk.py OUT --wear; the boss entrances' reaction: cine_react_export.py OUT --wear and
--wear-back.)
"""
from __future__ import annotations

import json
import os
import sys
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_characters as BC                                     # noqa: E402
import cine_evochi as CE                                          # noqa: E402
from accessories import wear, WEARABLES                           # noqa: E402
from build_web_assets import atlas, webp, HERO_SCALE              # noqa: E402
from characters import build                                      # noqa: E402
from charrender import render_char                                # noqa: E402


def overlay(ch, k, cam, fit):
    body = render_char(ch, 'amber', 'default', cam, fit.w, fit.h, fit=fit)
    comb = render_char(ch, 'amber', 'default', cam, fit.w, fit.h, fit=fit, extra_model=wear(ch, k), cov_prefix='acc_')
    ab = body.rgba[..., 3] / 255.0
    ac = comb.rgba[..., 3] / 255.0
    extra = np.clip((ac - ab) / np.maximum(1 - ab, 1e-3), 0, 1)
    a = np.clip(np.maximum(comb.cov, extra) * 1.05, 0, 1)
    ov = comb.rgba.copy()
    ov[..., 3] = (a * 255).astype(np.uint8)
    return ov


def _job(args):
    view, stage, k = args
    import charrender
    charrender._surf_cache.clear()
    charrender._quad_cache.clear()
    ch = build(stage)
    if view == 'hero':
        cam = BC.HERO_CAM[stage]
        fit = BC.frozen('hero_s%02d' % stage, None)
    elif view == 'battle':
        cam = BC.BATTLE_CAM
        fit = BC.frozen('battle_s%02d' % stage, None)
    else:
        cam = CE.CAM
        fit = BC.frozen('cine_s%02d' % stage, None)
    return view, stage, k, overlay(ch, k, cam, fit)


def main(art, stages):
    man = json.load(open(os.path.join(art, 'manifest.json')))
    cine = json.load(open(os.path.join(art, 'wilds', 'wilds_cine.json')))
    jobs = [(v, s, k) for s in stages for v in ('hero', 'battle', 'cine') for k in WEARABLES]
    with ProcessPoolExecutor(int(os.environ.get('JOBS', '1'))) as ex:
        res = {(v, s, k): ov for v, s, k, ov in ex.map(_job, jobs)}
    for s in stages:
        sid = 's%02d' % s
        ent = man['chars'][sid]
        # the hero view: scaled down as the packer does, in the same atlas
        frames = [Image.fromarray(res[('hero', s, k)]).resize((ent['w'], ent['h']), Image.LANCZOS) for k in WEARABLES]
        A, rects = atlas(frames, 4)
        assert dict(zip(WEARABLES, rects)) == ent['overlays']['rects'], 'the hero overlays moved'
        webp(A, os.path.join(art, ent['overlays']['file']), 90)
        frames = [Image.fromarray(res[('battle', s, k)]) for k in WEARABLES]
        A, rects = atlas(frames, 4)
        assert dict(zip(WEARABLES, rects)) == ent['battle']['overlays']['rects'], 'the battle overlays moved'
        webp(A, os.path.join(art, ent['battle']['overlays']['file']), 90)
        # the Briarback entrance's wear grid
        st = cine[sid]
        w, h = st['w'], st['h']
        cols = CE.WEAR_COLS
        rows = (len(WEARABLES) + cols - 1) // cols
        grid = np.zeros((rows * h, cols * w, 4), np.uint8)
        for k in WEARABLES:
            c, r = st['wear'][k]
            ov = res[('cine', s, k)]
            assert ov.shape[:2] == (h, w), 'the cine frame moved'
            grid[r * h:(r + 1) * h, c * w:(c + 1) * w] = ov
        Image.fromarray(grid, 'RGBA').save(os.path.join(art, 'wilds', st['wearSheet']), quality=88, method=6)
        print(sid, 'overlays remade', flush=True)


if __name__ == '__main__':
    main(sys.argv[1], [int(a) for a in sys.argv[2:]] or [1, 2, 3])

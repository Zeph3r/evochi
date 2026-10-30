"""Your Evochi for the Wilds' boss entrance: a big, low-angle, heroic view (looking up at it, turned toward
the guardian on the right) with the cinematic faces: a yell as the roar hits (shout), squeezed shut against
the blast (strain), and set and ready (fierce). Every stage and colour, plus the wearable overlays from
the same camera so whatever it wears comes along.

    python3 cine_evochi.py OUT_DIR [stage ...]

Writes OUT_DIR/cine_sNN_<palette>.webp (the three faces side by side), cine_sNN_wear.webp (a grid of the
wearables) and wilds_cine.json (cell size, faces, wearable cells, anchors: ground, face, head top).
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
from characters import build                                      # noqa: E402
from charrender import render_char                                # noqa: E402
from accessories import wear, WEARABLES, FRAME_WEARABLES          # noqa: E402
from voxel import Camera, project_px                              # noqa: E402
from palettes import VARIANT_ORDER                                # noqa: E402
import build_characters as BC                                     # noqa: E402

CAM = Camera(yaw=-32, pitch=-7)          # low, looking up; turned to face right
FACES = ['shout', 'strain', 'fierce']
CELL_H = 760
WEAR_COLS = 3


def _fit(stage):
    ch = build(stage)
    worn = [wear(ch, k) for k in FRAME_WEARABLES]
    f1 = BC.fit_for([ch.model] + worn, CAM, 10.0)
    return BC.frozen('cine_s%02d' % stage, BC.fit_for([ch.model] + worn, CAM, 10.0 * CELL_H / f1.h))


def _faces(args):
    stage, v = args
    ch = build(stage)
    fit = _fit(stage)
    cells = [render_char(ch, v, e, CAM, fit.w, fit.h, fit=fit).rgba for e in FACES]
    return stage, v, np.concatenate(cells, 1)


def _wear(args):
    stage, k = args
    ch = build(stage)
    fit = _fit(stage)
    body = render_char(ch, 'amber', 'default', CAM, fit.w, fit.h, fit=fit)
    comb = render_char(ch, 'amber', 'default', CAM, fit.w, fit.h, fit=fit, extra_model=wear(ch, k), cov_prefix='acc_')
    ab = body.rgba[..., 3] / 255.0
    ac = comb.rgba[..., 3] / 255.0
    extra = np.clip((ac - ab) / np.maximum(1 - ab, 1e-3), 0, 1)
    a = np.clip(np.maximum(comb.cov, extra) * 1.05, 0, 1)
    ov = comb.rgba.copy()
    ov[..., 3] = (a * 255).astype(np.uint8)
    return stage, k, ov


def main(out, stages, jobs=2):
    os.makedirs(out, exist_ok=True)
    mp = os.path.join(out, 'wilds_cine.json')
    meta = json.load(open(mp)) if os.path.exists(mp) else {}
    meta.update({'faces': FACES, 'yaw': CAM.yaw, 'pitch': CAM.pitch})
    with ProcessPoolExecutor(jobs) as ex:
        faces = list(ex.map(_faces, [(s, v) for s in stages for v in VARIANT_ORDER]))
        wears = list(ex.map(_wear, [(s, k) for s in stages for k in WEARABLES]))
    for stage in stages:
        sid = 's%02d' % stage
        ch = build(stage)
        fit = _fit(stage)
        anchors = {k: project_px(CAM, fit, ch.anchors[k])[0].round(1).tolist() for k in ('ground', 'face', 'head_top')}
        st = {'w': fit.w, 'h': fit.h, 'anchors': anchors, 'sheets': {}, 'wear': {}}
        for s_, v, sheet in faces:
            if s_ != stage:
                continue
            fn = f'cine_{sid}_{v}.webp'
            Image.fromarray(sheet, 'RGBA').save(os.path.join(out, fn), quality=88, method=6)
            st['sheets'][v] = fn
            print(fn, os.path.getsize(os.path.join(out, fn)) // 1024, 'KB', flush=True)
        ws = [(k, ov) for s_, k, ov in wears if s_ == stage]
        rows = (len(ws) + WEAR_COLS - 1) // WEAR_COLS
        grid = np.zeros((rows * fit.h, WEAR_COLS * fit.w, 4), np.uint8)
        for i, (k, ov) in enumerate(ws):
            r, c = divmod(i, WEAR_COLS)
            grid[r * fit.h:(r + 1) * fit.h, c * fit.w:(c + 1) * fit.w] = ov
            st['wear'][k] = [c, r]
        fn = f'cine_{sid}_wear.webp'
        Image.fromarray(grid, 'RGBA').save(os.path.join(out, fn), quality=88, method=6)
        st['wearSheet'] = fn
        print(fn, os.path.getsize(os.path.join(out, fn)) // 1024, 'KB', flush=True)
        meta[sid] = st
        json.dump(meta, open(mp, 'w'), indent=1)


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    stages = [int(a) for a in args[1:]] or [1, 2, 3]
    jobs = int(next((a.split('=')[1] for a in sys.argv if a.startswith('--jobs=')), '2'))
    main(args[0], stages, jobs)

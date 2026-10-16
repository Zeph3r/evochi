"""Batch-render every Evochi character sprite, accessory overlay and turnaround.

Usage: python3 build_characters.py OUT_DIR [stage ...]
Writes PNG masters named per the style guide convention:
  evochi_lizard_s01_amber_happy_left3q_f000.png
plus accessory overlays and a JSON manifest of anchors.
"""
import json
import os
import sys

import numpy as np

from characters import build, EXPRESSIONS
from charrender import render_char
from accessories import wear, WEARABLES, FRAME_WEARABLES
from voxel import Camera, fit_camera, model_extent_points, save_rgba, project_px, Fit
from palettes import palette, muted, VARIANT_ORDER

HERO_CAM = {1: Camera(yaw=18, pitch=13), 2: Camera(yaw=36, pitch=13), 3: Camera(yaw=36, pitch=13)}
SCALE_HERO = 14.0
SCALE_TURN = 7.0
TURN_VIEWS = {'front': (0, 10), 'left': (90, 8), 'back': (180, 10), 'right': (-90, 8), 'top': (0, 89)}


def fit_for(models, cam, scale, pad=10):
    pts = np.concatenate([model_extent_points(m) for m in models])
    sx, sy, _ = cam.project(pts)
    w = int(np.ceil((sx.max() - sx.min()) * scale + 2 * pad))
    h = int(np.ceil((sy.max() - sy.min()) * scale + 2 * pad))
    w += w % 2
    h += h % 2
    return Fit(scale, pad - sx.min() * scale, pad - sy.min() * scale, w, h)


def main(out, stages):
    os.makedirs(out, exist_ok=True)
    manifest = {}
    mpath = os.path.join(out, 'manifest_part_%s.json' % '_'.join(map(str, stages)))
    for stage in stages:
        ch = build(stage)
        cam = HERO_CAM[stage]
        worn = {k: wear(ch, k) for k in WEARABLES}
        # the frame comes from the shop wearables only, so adding a wearable never moves existing sprites
        fit = fit_for([ch.model] + [worn[k] for k in FRAME_WEARABLES], cam, SCALE_HERO)
        anchors = {k: project_px(cam, fit, v)[0].round(1).tolist() for k, v in ch.anchors.items()}
        sid = 's%02d' % stage
        manifest[sid] = {'hero': {'w': fit.w, 'h': fit.h, 'scale': fit.scale, 'yaw': cam.yaw,
                                  'pitch': cam.pitch, 'anchors': anchors}}
        for v in VARIANT_ORDER:
            base = palette(v)
            for e in EXPRESSIONS:
                pal = muted(base) if e in ('sick', 'memorial') else base
                key = v + ('_muted' if e in ('sick', 'memorial') else '')
                o = render_char(ch, v, e, cam, fit.w, fit.h, fit=fit, pal=pal, pal_key=key)
                save_rgba(o.rgba, os.path.join(out, f'evochi_lizard_{sid}_{v}_{e}_left3q_f000.png'))
            print(sid, v, 'hero done', flush=True)
        # accessory overlays (palette independent)
        body = render_char(ch, 'amber', 'default', cam, fit.w, fit.h, fit=fit)
        for k, M in worn.items():
            comb = render_char(ch, 'amber', 'default', cam, fit.w, fit.h, fit=fit, extra_model=M,
                               cov_prefix='acc_')
            ab = body.rgba[..., 3] / 255.0
            ac = comb.rgba[..., 3] / 255.0
            extra = np.clip((ac - ab) / np.maximum(1 - ab, 1e-3), 0, 1)
            a = np.maximum(comb.cov, extra)
            a = np.clip(a * 1.05, 0, 1)
            ov = comb.rgba.copy()
            ov[..., 3] = (a * 255).astype(np.uint8)
            slot = WEARABLES[k][0]
            save_rgba(ov, os.path.join(out, f'item_{k}_{slot}_{sid}_left3q.png'))
        print(sid, 'overlays done', flush=True)
        # turnarounds
        turn = {}
        for view, (yaw, pitch) in TURN_VIEWS.items():
            c2 = Camera(yaw=yaw, pitch=pitch)
            f2 = fit_for([ch.model], c2, SCALE_TURN)
            turn[view] = {'w': f2.w, 'h': f2.h,
                          'ground': project_px(c2, f2, ch.anchors['ground'])[0].round(1).tolist()}
            for v in VARIANT_ORDER:
                o = render_char(ch, v, 'default', c2, f2.w, f2.h, fit=f2)
                save_rgba(o.rgba, os.path.join(out, f'evochi_lizard_{sid}_{v}_default_{view}_f000.png'))
        manifest[sid]['turnaround'] = turn
        print(sid, 'turnaround done', flush=True)
        json.dump(manifest, open(mpath, 'w'), indent=1)


if __name__ == '__main__':
    main(sys.argv[1], [int(s) for s in sys.argv[2:]] or [1, 2, 3])

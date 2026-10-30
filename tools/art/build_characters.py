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
# encounters: your Evochi from behind, turned toward the wild one up and to the right of the shot
BATTLE_CAM = Camera(yaw=-125, pitch=10)
BATTLE_EXPR = ['default', 'blink', 'happy', 'determined', 'surprised', 'sleepy', 'excited']


# the sprite frames as they were when the sheets were made (tools/art/frames_frozen.json): a wearable refitted
# later draws inside the same frame, so the body sheets never need making again
_FROZEN = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'frames_frozen.json'))) \
    if os.path.exists(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'frames_frozen.json')) else {}


def frozen(key, fit):
    f = _FROZEN.get(key)
    return Fit(*f) if f else fit


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
        fit = frozen('hero_s%02d' % stage, fit_for([ch.model] + [worn[k] for k in FRAME_WEARABLES], cam, SCALE_HERO))
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


def battle(out, stages):
    """The encounter view: every stage x palette x BATTLE_EXPR from BATTLE_CAM, plus wearable overlays,
    named evochi_lizard_sNN_<palette>_<expr>_battle_f000.png / item_<k>_<slot>_sNN_battle.png."""
    os.makedirs(out, exist_ok=True)
    mpath = os.path.join(out, 'manifest_battle_%s.json' % '_'.join(map(str, stages)))
    manifest = {}
    cam = BATTLE_CAM
    for stage in stages:
        ch = build(stage)
        worn = {k: wear(ch, k) for k in WEARABLES}
        fit = frozen('battle_s%02d' % stage, fit_for([ch.model] + [worn[k] for k in FRAME_WEARABLES], cam, SCALE_HERO))
        anchors = {k: project_px(cam, fit, v)[0].round(1).tolist() for k, v in ch.anchors.items()}
        # the body's own top (no hats), so the game can size every stage by its body
        bfit_pts = model_extent_points(ch.model)
        sx, sy, _ = cam.project(bfit_pts)
        anchors['body_top'] = [round(float((sx.min() + sx.max()) / 2 * fit.scale + fit.ox), 1), round(float(sy.min() * fit.scale + fit.oy), 1)]
        sid = 's%02d' % stage
        manifest[sid] = {'battle': {'w': fit.w, 'h': fit.h, 'scale': fit.scale, 'yaw': cam.yaw, 'pitch': cam.pitch,
                                    'anchors': anchors, 'expressions': BATTLE_EXPR}}
        for v in VARIANT_ORDER:
            for e in BATTLE_EXPR:
                o = render_char(ch, v, e, cam, fit.w, fit.h, fit=fit)
                save_rgba(o.rgba, os.path.join(out, f'evochi_lizard_{sid}_{v}_{e}_battle_f000.png'))
            print(sid, v, 'battle done', flush=True)
        body = render_char(ch, 'amber', 'default', cam, fit.w, fit.h, fit=fit)
        for k, M in worn.items():
            comb = render_char(ch, 'amber', 'default', cam, fit.w, fit.h, fit=fit, extra_model=M, cov_prefix='acc_')
            ab = body.rgba[..., 3] / 255.0
            ac = comb.rgba[..., 3] / 255.0
            extra = np.clip((ac - ab) / np.maximum(1 - ab, 1e-3), 0, 1)
            a = np.clip(np.maximum(comb.cov, extra) * 1.05, 0, 1)
            ov = comb.rgba.copy()
            ov[..., 3] = (a * 255).astype(np.uint8)
            save_rgba(ov, os.path.join(out, f'item_{k}_{WEARABLES[k][0]}_{sid}_battle.png'))
        print(sid, 'battle overlays done', flush=True)
        json.dump(manifest, open(mpath, 'w'), indent=1)


if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[2] == '--battle':
        battle(sys.argv[1], [int(s) for s in sys.argv[3:]] or [1, 2, 3])
    else:
        main(sys.argv[1], [int(s) for s in sys.argv[2:]] or [1, 2, 3])

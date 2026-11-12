"""The sleep clips for the Nest (features/shared/scene_view.dart plays them: 'sleep_settle' when it falls
asleep, 'sleep_hold' looping while it sleeps, 'sleep_wake' when it is woken), from the sleep cycle's poses
(sleep_cycle.py: the circle walked round after its tail, curling as it goes, the sniff, the lie-down, the curl,
breathing, the stir and the push up), seen as the Nest shows it: the stage's hero view with its camera fixed,
so the circle's turn becomes the body turned about its own ground point (cine_jump.turn_body).

    python3 sleep_acting.py OUT_DIR [--stage=2,3] [--only=sleep_hold] [--jobs=2] [--preview]

Writes acting_<clip>_sNN_<palette>.webp (an animated WebP, 10 fps, the face baked in) into the acting pack and
the stage's entry in acting.json (its rate, scale and ground, and each clip's frames, box, lift, body files and
whether it loops), and acting_<clip>_sNN_wear_<item>.webp for each worn piece. Shipped at half the hero's
pixel scale (SHIP): the clips are long and the frames large.
"""
import json
import math
import os
import sys
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_characters as BC                                     # noqa: E402
import cine_jump as J                                             # noqa: E402
import sleep_cycle as S                                           # noqa: E402
from characters import build, head_rotation                      # noqa: E402
from palettes import VARIANT_ORDER                                # noqa: E402
from voxel import Fit, project_px                                 # noqa: E402

FPS = 10
SHIP = 0.5                                   # px per voxel shipped, relative to the hero render (acting.py ships 0.75)
# clip: (from, to, loops) in the sleep cycle's seconds; the hold is one breath (3 s), ending short of its first frame
CLIPS = {'sleep_settle': (1.0, 7.8, False), 'sleep_hold': (7.8, 10.8, True), 'sleep_wake': (11.3, 13.8, False)}
# the hero's frame grown so the lying body, turned any way round, never leaves it: (left, top, right, bottom) px
GROW = {2: (110, 40, 110, 40), 3: (150, 40, 150, 50)}
# turn_body's grid for each stage (design units: lo xyz, hi xyz)
PAD = {2: (-46, -14, -46, 46, 40, 46), 3: (-66, -14, -66, 66, 52, 66)}


def fit_for(stage):
    f = BC.frozen('hero_s%02d' % stage, None)
    l, t, r, b = GROW[stage]
    return Fit(f.scale, f.ox + l, f.oy + t, f.w + l + r, f.h + t + b)


def times(clip):
    t0, t1, loops = CLIPS[clip]
    n = int(round((t1 - t0) * FPS)) + (0 if loops else 1)
    return [round(t0 + i / FPS, 4) for i in range(n)]


def character(stage, t, P):
    pose, face, turn, circ, walk, what = S.frame_at(stage, t, P)
    ch = S.build_pose(stage, pose, walk, 'petal')
    if abs(turn) > 1e-3:
        g = ch.anchors['ground']
        ch = J.turn_body(ch, head_rotation((0.0, -turn, 0.0)), 1.0, pivot=np.array([g[0], 0.0, g[2]]), pad=PAD[stage])
    return ch, face


def _frame(args):
    """one frame: the body in every palette, and each worn piece as an overlay (as acting._wear: the piece
    rendered on the amber body, what it adds over the bare body kept)"""
    stage, clip, i, t, pals, wear = args
    import charrender
    from accessories import WEARABLES
    from wear_pose import posed_wear
    P = S.poses(stage)
    ch, face = character(stage, t, P)
    fit = fit_for(stage)
    cam = BC.HERO_CAM[stage]
    out, ov = {}, {}
    W, H = int(round(fit.w * SHIP)), int(round(fit.h * SHIP))
    small = lambda a: np.asarray(Image.fromarray(a).resize((W, H), Image.LANCZOS))   # shipped size here: the
    for v in pals:                                                                      # Elder's full frames ran out of memory
        out[v] = small(charrender.render_char(ch, v, face, cam, fit.w, fit.h, fit=fit).rgba)
        charrender._quad_cache.clear()
    if wear:
        body = charrender.render_char(ch, 'amber', face, cam, fit.w, fit.h, fit=fit)
        ab = body.rgba[..., 3] / 255.0
        for k in WEARABLES:
            comb = charrender.render_char(ch, 'amber', face, cam, fit.w, fit.h, fit=fit, extra_model=posed_wear(ch, k), cov_prefix='acc_')
            ac = comb.rgba[..., 3] / 255.0
            extra = np.clip((ac - ab) / np.maximum(1 - ab, 1e-3), 0, 1)
            a = np.clip(np.maximum(comb.cov, extra) * 1.05, 0, 1)
            o = comb.rgba.copy()
            o[..., 3] = (a * 255).astype(np.uint8)
            ov[k] = small(o)
            charrender._quad_cache.clear()
    charrender._surf_cache.clear()
    return clip, i, out, ov


def box_of(layers, w, h, pad=2):
    """the clip's own frame: everything any of its frames covers, at the shipped scale"""
    m = np.zeros(layers[0].shape[:2], bool)
    for c in layers:
        m |= c[..., 3] > 3
    ys, xs = np.nonzero(m)
    k = 1.0           # (the frames come at the shipped size)
    x0, y0 = max(0, int(xs.min() * k) - pad), max(0, int(ys.min() * k) - pad)
    x1, y1 = min(w, int(math.ceil((xs.max() + 1) * k)) + pad), min(h, int(math.ceil((ys.max() + 1) * k)) + pad)
    x1 += (x1 - x0) % 2
    y1 += (y1 - y0) % 2
    return [x0, y0, min(w, x1) - x0, min(h, y1) - y0]


def anim(cells, w, h, box, path):
    x, y, bw, bh = box
    ims = [Image.fromarray(c).crop((x, y, x + bw, y + bh)) for c in cells]
    ims[0].save(path, save_all=True, append_images=ims[1:], duration=int(round(1000 / FPS)), loop=0,
                quality=75, method=6, minimize_size=False, allow_mixed=False)


def main(out, stages=(2, 3), only=None, jobs=2, preview=False):
    os.makedirs(out, exist_ok=True)
    mp = os.path.join(out, 'acting.json')
    meta = json.load(open(mp)) if os.path.exists(mp) else {}
    pals = ['amber'] if preview else list(VARIANT_ORDER)
    for stage in stages:
        sid = 's%02d' % stage
        fit = fit_for(stage)
        cam = BC.HERO_CAM[stage]
        w, h = int(round(fit.w * SHIP)), int(round(fit.h * SHIP))
        ground = (project_px(cam, fit, [list(build(stage).anchors['ground'])])[0] * SHIP).round(1).tolist()
        st = meta.setdefault(sid, {})
        st.update({'fps': FPS, 'scale': fit.scale * SHIP, 'ground': ground})
        st.setdefault('clips', {})
        for clip, (t0, t1, loops) in CLIPS.items():
            if only and clip not in only:
                continue
            ts = times(clip)
            with ProcessPoolExecutor(jobs) as ex:
                frames = sorted(ex.map(_frame, [(stage, clip, i, t, pals, not preview) for i, t in enumerate(ts)]), key=lambda r: r[1])
            box = box_of([f[2][pals[0]] for f in frames] + [f[3][k] for f in frames for k in f[3]], w, h)
            c = {'n': len(ts), 'end': round(t1 - t0, 3), 'box': box, 'lift': [0.0] * len(ts), 'fps': FPS, 'loop': loops,
                 'body': {}, 'wear': {}}
            for v in pals:
                fn = 'acting_%s_%s_%s.webp' % (clip, sid, v)
                anim([f[2][v] for f in frames], w, h, box, os.path.join(out, fn))
                c['body'][v] = fn
                print(fn, os.path.getsize(os.path.join(out, fn)) // 1024, 'KB', flush=True)
            for k in (frames[0][3] if frames else {}):
                fn = 'acting_%s_%s_wear_%s.webp' % (clip, sid, k)
                anim([f[3][k] for f in frames], w, h, box, os.path.join(out, fn))
                c['wear'][k] = fn
            st['clips'][clip] = c
            json.dump(meta, open(mp, 'w'), indent=1)
            print(sid, clip, len(ts), 'frames, box', box, flush=True)


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = dict(a[2:].split('=', 1) if '=' in a else (a[2:], '1') for a in sys.argv[1:] if a.startswith('--'))
    main(args[0] if args else os.path.join(HERE, '..', '..', 'flutter', 'assets', 'art', 'acting'),
         stages=tuple(int(s) for s in opts.get('stage', '2,3').split(',')),
         only=opts['only'].split(',') if 'only' in opts else None,
         jobs=int(opts.get('jobs', 2)), preview='preview' in opts)

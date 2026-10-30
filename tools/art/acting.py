"""Personality acting clips (the Personality system, game/personality): the habits your Evochi is recognised by,
posed from its rig frame by frame and seen as the home shows it (build_characters' hero view, its frozen frame),
so a clip can stand in for the still sprite in the nest. A signature (a double hop, a tilt then a lean, a step
back then a commit), supporting habits (a proud chin lift, a careful peek, a happy wiggle ...) and idles.

The Eggling first (what hatches): it is all one egg, so its squash and stretch, lean, puff and the whole egg's
turn carry the acting, with its feet stepping and tucking.

    python3 acting.py OUT_DIR [--only=clip,clip] [--preview]

Writes acting_<clip>_s01_<palette>.webp (an animated WebP, the face baked in), acting_<clip>_s01_wear_<item>.webp
(each worn piece, posed with it) and acting.json: per stage its rate, scale (px per voxel, the hero sprite's) and
where it stands in the full cell (the hero's ground anchor); per clip its frames, its box in that cell (each clip
is cropped to what it covers) and how high it is each frame (for the shadow).
"""
from __future__ import annotations

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
from characters import build, head_rotation                      # noqa: E402
from palettes import VARIANT_ORDER                                # noqa: E402
from voxel import Fit, project_px                                 # noqa: E402

FPS = 20
HERO_SCALE = 0.75                       # as the game's hero atlases are packed (build_web_assets)
STAGE = 1
COLS = 6
NEAR, FAR = -1, 1
FN, FF, BN, BF = (NEAR, True), (FAR, True), (NEAR, False), (FAR, False)


def _f(front, back):
    return {FN: front, FF: front, BN: back, BF: back}


REST = dict()
# per clip: keys (time s, pose) and the faces (from time, expression). Pose: squash (height, volume kept), lean
# (degrees forward, a shear: the feet stay down), puff, roll (degrees, + tips toward its right), yaw (+ turns to
# its left), root (x, y, z: where the body is over its spot), feet {foot: (dy, dz, dx)}
CLIPS = {
    # the lively signature: two hops on the spot, the second higher, landing squashed each time
    'double_hop': dict(faces=[(0.0, 'happy'), (0.15, 'excited')], keys=[
        (0.00, REST),
        (0.10, dict(squash=0.84, lean=4)),
        (0.18, dict(squash=1.14, root=(0, 2.5, 0), feet=_f((0.6, 0.4, 0), (0.6, -0.4, 0)))),
        (0.27, dict(squash=1.05, root=(0, 5.0, 0), feet=_f((1.4, 0.2, 0), (1.4, -0.2, 0)))),
        (0.36, dict(squash=1.08, root=(0, 2.0, 0), feet=_f((0.4, 0.4, 0), (0.4, -0.4, 0)))),
        (0.42, dict(squash=0.82, lean=3)),
        (0.52, dict(squash=1.16, root=(0, 3.5, 0), feet=_f((0.8, 0.4, 0), (0.8, -0.4, 0)))),
        (0.64, dict(squash=1.06, root=(0, 7.0, 0), roll=-4, feet=_f((1.8, 0.2, 0), (1.8, -0.2, 0)))),
        (0.76, dict(squash=1.08, root=(0, 2.6, 0), roll=-1, feet=_f((0.4, 0.4, 0), (0.4, -0.4, 0)))),
        (0.84, dict(squash=0.8, lean=2)),
        (0.98, dict(squash=1.04)),
        (1.12, dict(squash=0.98)),
        (1.25, REST),
    ]),
    # the calm signature: a slow tilt of the whole egg, held (it's studying something), then it leans in
    'tilt_then_lean': dict(faces=[(0.0, 'curious'), (1.2, 'happy')], keys=[
        (0.00, REST),
        (0.30, dict(roll=12, squash=1.02)),
        (0.75, dict(roll=14, squash=1.02)),
        (1.05, dict(roll=6, lean=12, root=(0, 0, 1.2), squash=0.98, feet=_f((0, 0.6, 0), (0, 0.0, 0)))),
        (1.30, dict(roll=4, lean=14, root=(0, 0, 1.5), squash=0.98, feet=_f((0, 0.6, 0), (0, 0.0, 0)))),
        (1.60, REST),
    ]),
    # the cautious signature: startled, a small step back, then it gathers itself and steps in
    'step_back_then_commit': dict(faces=[(0.0, 'surprised'), (0.7, 'determined'), (1.3, 'happy')], keys=[
        (0.00, REST),
        (0.10, dict(squash=1.08, lean=-6)),
        (0.28, dict(squash=0.94, lean=-10, root=(0, 0, -2.4), feet=_f((0, -1.0, 0), (0, -1.6, 0)))),
        (0.62, dict(squash=0.92, lean=-8, root=(0, 0, -2.6), feet=_f((0, -1.2, 0), (0, -1.8, 0)))),
        (0.80, dict(squash=0.9, lean=-2, root=(0, 0, -2.4))),
        (1.00, dict(squash=1.04, lean=10, root=(0, 0.6, -0.4), feet=_f((0.6, 0.8, 0), (0, 0.4, 0)))),
        (1.18, dict(squash=0.96, lean=8, root=(0, 0, 0.6), feet=_f((0, 0.6, 0), (0, 0.4, 0)))),
        (1.50, REST),
    ]),
    # a proud chin lift: it puffs up, leans back with its chin up, holds it, settles
    'chin_lift': dict(faces=[(0.0, 'happy')], keys=[
        (0.00, REST),
        (0.20, dict(squash=1.06, lean=-9, puff=1.04)),
        (0.70, dict(squash=1.07, lean=-10, puff=1.05)),
        (0.90, dict(squash=0.97, lean=-2)),
        (1.10, REST),
    ]),
    # a careful peek: a tip to one side and a slow lean in, then back
    'careful_peek': dict(faces=[(0.0, 'curious')], keys=[
        (0.00, REST),
        (0.35, dict(roll=-8, lean=6, root=(0, 0, 0.6), squash=0.98)),
        (0.80, dict(roll=-10, lean=11, root=(0, 0, 1.4), squash=0.97, feet=_f((0, 0.6, 0), (0, 0, 0)))),
        (1.30, REST),
    ]),
    # a small relieved hop
    'small_hop': dict(faces=[(0.0, 'happy')], keys=[
        (0.00, REST),
        (0.10, dict(squash=0.86)),
        (0.20, dict(squash=1.12, root=(0, 2.4, 0), feet=_f((0.6, 0.3, 0), (0.6, -0.3, 0)))),
        (0.32, dict(squash=1.04, root=(0, 4.0, 0), feet=_f((1.2, 0.2, 0), (1.2, -0.2, 0)))),
        (0.44, dict(squash=1.06, root=(0, 1.4, 0), feet=_f((0.3, 0.3, 0), (0.3, -0.3, 0)))),
        (0.52, dict(squash=0.86)),
        (0.68, dict(squash=1.03)),
        (0.90, REST),
    ]),
    # a look round: it turns one way, the other, back
    'look_around': dict(faces=[(0.0, 'curious')], keys=[
        (0.00, REST),
        (0.30, dict(yaw=-24, roll=-3)),
        (0.62, dict(yaw=-26, roll=-3)),
        (0.90, dict(yaw=22, roll=3)),
        (1.15, dict(yaw=22, roll=3)),
        (1.40, REST),
    ]),
    # a happy wiggle: side to side, quick, with a bounce in it
    'happy_wiggle': dict(faces=[(0.0, 'excited')], keys=[
        (0.00, REST),
        (0.12, dict(roll=-10, squash=0.95)),
        (0.27, dict(roll=10, squash=1.04)),
        (0.42, dict(roll=-9, squash=0.95)),
        (0.57, dict(roll=8, squash=1.04)),
        (0.72, dict(roll=-3, squash=0.98)),
        (0.90, REST),
    ]),
    # a quick look over its shoulder
    'quick_look': dict(faces=[(0.0, 'curious')], keys=[
        (0.00, REST),
        (0.15, dict(yaw=-28, roll=-2)),
        (0.55, dict(yaw=-28, roll=-2)),
        (0.90, REST),
    ]),
    # bouncing in place, all energy
    'bounce_in_place': dict(faces=[(0.0, 'happy')], keys=[
        (0.00, REST),
        (0.10, dict(squash=0.88)),
        (0.22, dict(squash=1.08, root=(0, 1.4, 0))),
        (0.34, dict(squash=0.88)),
        (0.46, dict(squash=1.08, root=(0, 1.6, 0))),
        (0.58, dict(squash=0.9)),
        (0.75, dict(squash=1.03)),
        (1.00, REST),
    ]),
    # a gentle sway, easy, content
    'gentle_sway': dict(faces=[(0.0, 'happy')], keys=[
        (0.00, REST),
        (0.45, dict(roll=-6, lean=2)),
        (0.90, dict(roll=0, lean=-1, squash=1.01)),
        (1.35, dict(roll=6, lean=2)),
        (1.80, REST),
    ]),
}

PIVOT = np.array([0.0, 0.0, 0.0])          # the egg turns about its footprint's middle: its feet stay put
SCHEMA = ['squash', 'lean', 'puff', 'roll', 'yaw', 'pitch', 'rx', 'ry', 'rz'] + [
    'f%d%d' % (k, j) for k in range(4) for j in range(3)]
FEET = [FN, FF, BN, BF]
DEFAULT = {'squash': 1.0, 'puff': 1.0}


def _vec(p):
    v = [float(p.get(k, DEFAULT.get(k, 0.0))) for k in SCHEMA[:6]]
    v += list(p.get('root', (0.0, 0.0, 0.0)))
    for foot in FEET:
        f = (p.get('feet') or {}).get(foot, (0.0, 0.0, 0.0))
        v += list(f) + [0.0] * (3 - len(f))
    return np.array(v, float)


def _pose(v):
    p = {k: float(x) for k, x in zip(SCHEMA[:6], v[:6])}
    p['root'] = tuple(v[6:9])
    p['feet'] = {foot: tuple(v[9 + 3 * i:12 + 3 * i]) for i, foot in enumerate(FEET)}
    return p


def pose_at(clip, t):
    """a cubic through the keys (each key's tangent from its neighbours), so the motion carries through them"""
    keys = [(k, _vec(p)) for k, p in CLIPS[clip]['keys']]
    ts = [k for k, _ in keys]
    t = min(max(t, ts[0]), ts[-1])
    i = max(0, min(len(ts) - 2, int(np.searchsorted(ts, t, side='right')) - 1))
    t0, t1 = ts[i], ts[i + 1]
    p0, p1 = keys[i][1], keys[i + 1][1]
    pm = keys[i - 1][1] if i > 0 else p0
    pp = keys[i + 2][1] if i + 2 < len(keys) else p1
    tm = ts[i - 1] if i > 0 else t0 - (t1 - t0)
    tp = ts[i + 2] if i + 2 < len(keys) else t1 + (t1 - t0)
    m0 = (p1 - pm) / (t1 - tm) * (t1 - t0) * (0 if i == 0 else 1)
    m1 = (pp - p0) / (tp - t0) * (t1 - t0) * (0 if i + 2 >= len(keys) else 1)
    u = (t - t0) / (t1 - t0)
    h00, h10, h01, h11 = 2 * u ** 3 - 3 * u ** 2 + 1, u ** 3 - 2 * u ** 2 + u, -2 * u ** 3 + 3 * u ** 2, u ** 3 - u ** 2
    return _pose(h00 * p0 + h10 * m0 + h01 * p1 + h11 * m1)


def _grid(v):
    return round(v * 2) / 2               # the feet on the voxel grid (res 2), so they never shimmer


def character(p):
    import cine_jump as J
    feet = {k: tuple(_grid(x) for x in f) for k, f in p['feet'].items()}
    ch = build(STAGE, lo_y=-6, squash=p['squash'], lean=p['lean'], puff=p['puff'], feet=feet)
    if abs(p['roll']) + abs(p['yaw']) + abs(p['pitch']) > 1e-3:
        ch = J.turn_body(ch, head_rotation((p['pitch'], p['yaw'], p['roll'])), 1.0, pivot=PIVOT,
                         pad=(-26, -10, -26, 26, 44, 28))
    return ch


def times(clip):
    end = CLIPS[clip]['keys'][-1][0]
    return [round(i / FPS, 4) for i in range(int(round(end * FPS)) + 1)]


# the hero's frame (the still sprite's), grown so a hop or a lean never leaves it: (left, top, right, bottom) px
GROW = (60, 150, 60, 20)


def acting_fit():
    f = BC.frozen('hero_s%02d' % STAGE, None)
    l, t, r, b = GROW
    return type(f)(f.scale, f.ox + l, f.oy + t, f.w + l + r, f.h + t + b)


def _at(fit, root):
    """the frame for a body standing [root] (voxels) from its spot: the whole render moves, not the grid"""
    cam = BC.HERO_CAM[STAGE]
    d = project_px(cam, fit, [list(root)])[0] - project_px(cam, fit, [[0, 0, 0]])[0]
    return type(fit)(fit.scale, fit.ox + d[0], fit.oy + d[1], fit.w, fit.h)


XFADE = 0.12                                # s: one expression eases into the next


def faces_at(clip, t):
    """(face, previous face, how far into the change 0..1)"""
    fs = CLIPS[clip]['faces']
    cur, prev, k = fs[0][1], None, 1.0
    for i, (t0, e) in enumerate(fs):
        if t >= t0:
            cur = e
            if i > 0 and t < t0 + XFADE:
                prev, k = fs[i - 1][1], (t - t0) / XFADE
            else:
                prev, k = None, 1.0
    return cur, prev, k


def _render(ch, v, clip, t, fit, extra=None):
    import charrender
    cam = BC.HERO_CAM[STAGE]
    cur, prev, k = faces_at(clip, t)
    kw = dict(extra_model=extra, cov_prefix='acc_') if extra is not None else {}
    r = charrender.render_char(ch, v, cur, cam, fit.w, fit.h, fit=fit, **kw)
    if prev is None or extra is not None:
        return r
    q = charrender.render_char(ch, v, prev, cam, fit.w, fit.h, fit=fit)
    e = k * k * (3 - 2 * k)
    r.rgba = (q.rgba.astype(float) * (1 - e) + r.rgba.astype(float) * e).round().astype(np.uint8)
    return r


def _frame(args):
    clip, i, t, pals = args
    import charrender
    p = pose_at(clip, t)
    ch = character(p)
    fit = _at(acting_fit(), p['root'])
    out = {}
    for v in pals:
        out[v] = _render(ch, v, clip, t, fit).rgba
        charrender._quad_cache.clear()
    charrender._surf_cache.clear()
    return clip, i, out


def _wear(args):
    clip, i, t = args
    import charrender
    from accessories import WEARABLES
    from wear_pose import posed_wear
    p = pose_at(clip, t)
    ch = character(p)
    fit = _at(acting_fit(), p['root'])
    body = _render(ch, 'amber', clip, t, fit)
    ab = body.rgba[..., 3] / 255.0
    out = {}
    for k in WEARABLES:
        comb = _render(ch, 'amber', clip, t, fit, extra=posed_wear(ch, k))
        ac = comb.rgba[..., 3] / 255.0
        extra = np.clip((ac - ab) / np.maximum(1 - ab, 1e-3), 0, 1)
        a = np.clip(np.maximum(comb.cov, extra) * 1.05, 0, 1)
        ov = comb.rgba.copy()
        ov[..., 3] = (a * 255).astype(np.uint8)
        out[k] = ov
        charrender._quad_cache.clear()
    charrender._surf_cache.clear()
    return clip, i, out


def _box(layers, w, h, pad=2):
    """the clip's own frame: everything any of its frames (and worn pieces) covers, at the shipped scale"""
    m = np.zeros(layers[0].shape[:2], bool)
    for c in layers:
        m |= c[..., 3] > 3
    ys, xs = np.nonzero(m)
    k = HERO_SCALE
    x0, y0 = max(0, int(xs.min() * k) - pad), max(0, int(ys.min() * k) - pad)
    x1, y1 = min(w, int(math.ceil((xs.max() + 1) * k)) + pad), min(h, int(math.ceil((ys.max() + 1) * k)) + pad)
    x1 += (x1 - x0) % 2
    y1 += (y1 - y0) % 2
    return [x0, y0, min(w, x1) - x0, min(h, y1) - y0]


def _anim(cells, w, h, box, path):
    """an animated WebP (the game streams its frames: only the one on screen is ever decoded)"""
    x, y, bw, bh = box
    ims = [Image.fromarray(c).resize((w, h), Image.LANCZOS).crop((x, y, x + bw, y + bh)) for c in cells]
    ims[0].save(path, save_all=True, append_images=ims[1:], duration=int(round(1000 / FPS)), loop=0,
                quality=88, method=6, minimize_size=False, allow_mixed=False)


def main(out, only=None, preview=False):
    from accessories import WEARABLES
    os.makedirs(out, exist_ok=True)
    mp = os.path.join(out, 'acting.json')
    meta = json.load(open(mp)) if os.path.exists(mp) else {}
    fit = acting_fit()
    cam = BC.HERO_CAM[STAGE]
    w, h = int(round(fit.w * HERO_SCALE)), int(round(fit.h * HERO_SCALE))
    ground = (project_px(cam, fit, [list(build(STAGE).anchors['ground'])])[0] * HERO_SCALE).round(1).tolist()
    sid = 's%02d' % STAGE
    st = meta.setdefault(sid, {'clips': {}})
    st.update({'fps': FPS, 'scale': fit.scale * HERO_SCALE, 'ground': ground})
    clips = [c for c in CLIPS if not only or c in only]
    workers = int(os.environ.get('JOBS', '2'))
    pals = ['amber'] if preview else list(VARIANT_ORDER)
    for clip in clips:
        ts = times(clip)
        with ProcessPoolExecutor(workers) as ex:
            frames = sorted(ex.map(_frame, [(clip, i, t, pals) for i, t in enumerate(ts)]), key=lambda r: r[1])
        wears = []
        if not preview:
            with ProcessPoolExecutor(workers) as ex:
                wears = sorted(ex.map(_wear, [(clip, i, t) for i, t in enumerate(ts)]), key=lambda r: r[1])
        box = _box([f[2][pals[0]] for f in frames] + [x[2][k] for x in wears for k in x[2]], w, h)
        c = {'n': len(ts), 'end': CLIPS[clip]['keys'][-1][0], 'box': box,
             'lift': [round(float(pose_at(clip, t)['root'][1]), 2) for t in ts], 'body': {}, 'wear': {}}
        for v in pals:
            fn = 'acting_%s_%s_%s.webp' % (clip, sid, v)
            _anim([f[2][v] for f in frames], w, h, box, os.path.join(out, fn))
            c['body'][v] = fn
        for k in (WEARABLES if wears else []):
            fn = 'acting_%s_%s_wear_%s.webp' % (clip, sid, k)
            _anim([x[2][k] for x in wears], w, h, box, os.path.join(out, fn))
            c['wear'][k] = fn
        st['clips'][clip] = c
        json.dump(meta, open(mp, 'w'), indent=1)
        print(clip, len(ts), 'frames', box, flush=True)
    print(mp, flush=True)


if __name__ == '__main__':
    a = [x for x in sys.argv[1:] if not x.startswith('--')]
    only = next((x.split('=', 1)[1].split(',') for x in sys.argv if x.startswith('--only=')), None)
    main(a[0], only, '--preview' in sys.argv)

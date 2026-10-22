"""The Forgotten Sentinel's entrance (the Sentinel's Gate, F5): seen from low down in perspective, asleep
against its gate, its eyes igniting, heaving itself up, fists raised in a roar, then leaning in as its eyes
gather the beam it fires at your Evochi; then (a second camera, lower and closer) looming over you for the
title card. Drawn with the same voxels and flat renderer as its fighting sprites, at finer voxels, with a
grain in the stone so it holds up close.

    python3 sentinel_intro.py OUT_DIR [--preview] [--jobs=2]
    python3 sentinel_intro.py OUT_DIR --frames=0,6,12,16,22,26,39      a strip of a few frames to look at

Writes OUT_DIR/sentinel_intro_00.webp ... (transparent frames) and sentinel_intro.json: the frame size and
rate, where the shots change, and per frame where its eyes, chest rune, fists and the ground under it
land in the picture (the app draws the beam out of its eyes, flares the runes and shakes on the fists).
"""
from __future__ import annotations

import json
import math
import os
import sys
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import trail_art as TA                                           # noqa: E402
import wilds_foes as WF                                          # noqa: E402
from voxel import Camera, Fit, Light, render, project_px         # noqa: E402

W, H = 864, 1296
FPS = 12
N = 40
WAKE, ROAR, BEAM, MENACE = 0, 12, 20, 26          # where each part starts
LIT = 4                                           # the frame its eyes ignite

# finer voxels than its map sprite: it fills the screen here
_M = TA.M_


def _fine(lo, hi, res=1):
    if tuple(lo) == (-27, -1, -18):
        return _M(lo, hi, res=3)
    return _M(lo, hi, res=res)


TA.M_ = _fine

# stone grain: lighter and darker flecks and seams as each part is painted (so they ride with the body)
_put = TA.put
_GRAIN = {TA.STONE_B: ('#B9B3A7', '#948E83'), TA.STONE_B_LO: ('#958F85', '#6E6961'), TA.STONE_B_HI: ('#D3CDC0', '#B2AC9F'),
          TA.MOSS_B: ('#7FAD5A', '#557C3A'), TA.MOSS_B_HI: ('#9BCB74', '#6E9A4C')}


def _grainy(M, mask, col, glow=None, empty=False):
    m = _put(M, mask, col, glow, empty)
    if col in _GRAIN and np.any(m):
        hi, lo = _GRAIN[col]
        X, Y, Z = M.X, M.Y, M.Z
        n = (np.sin(X * 1.9 + np.sin(Z * 1.1) * 1.4) * np.cos(Y * 2.3 - X * 0.4)
             + 0.3 * np.sin(X * 6.1 + Y * 4.7 + Z * 5.3) + 0.18 * np.sin(Z * 8.3 - Y * 3.1))
        M.set(m & (n > 0.86), hi)
        M.set(m & (n < -0.9), lo)
    return m


TA.put = _grainy


def _spec(name):
    (uc, ur), (fc, fr) = TA.SENTINEL_ARMS[name]
    return np.array([*uc, *ur, *fc, *fr], float)


def _unspec(v):
    v = [float(x) for x in v]
    return ((tuple(v[0:3]), tuple(v[3:6])), (tuple(v[6:9]), tuple(v[9:12])))


# keyframes: frame -> pose (numbers and arms ease between keys; the state holds until the next key)
KEYS = [
    (0, dict(state='dormant', lean=0.24, tilt=0.03, glow=0.0, r='rest', l='rest')),
    (3, dict(state='dormant', lean=0.23, tilt=0.02, glow=0.0, r='rest', l='rest')),
    (LIT, dict(state='waking', lean=0.21, tilt=0.0, glow=0.3, r='rest', l='rest')),
    (8, dict(state='waking', lean=0.08, tilt=-0.03, glow=0.5, r='rest', l='raised')),
    (11, dict(state='waking', lean=-0.02, tilt=0.0, glow=0.7, r='raised', l='raised')),
    (14, dict(state='waking', lean=-0.13, tilt=0.03, glow=1.0, r='up', l='up')),
    (16, dict(state='waking', lean=-0.16, tilt=-0.04, glow=1.0, r='up', l='up')),
    (18, dict(state='waking', lean=-0.13, tilt=0.04, glow=1.0, r='up', l='up')),
    (19, dict(state='waking', lean=-0.12, tilt=0.0, glow=1.0, r='up', l='up')),
    (21, dict(state='waking', lean=0.02, tilt=0.0, glow=1.0, r='raised', l='raised')),
    (23, dict(state='waking', lean=0.12, tilt=0.0, glow=1.0, r='wide', l='wide')),
    (25, dict(state='waking', lean=0.16, tilt=0.0, glow=1.0, r='wide', l='wide')),
    # the second camera: looming over you, fists raised, breathing
    (MENACE, dict(state='waking', lean=0.15, tilt=0.0, glow=1.0, r='raised', l='raised')),
    (32, dict(state='waking', lean=0.19, tilt=-0.02, glow=1.0, r='raised', l='wide')),
    (39, dict(state='waking', lean=0.16, tilt=0.02, glow=1.0, r='wide', l='raised')),
]


def _ease(t):
    return t * t * (3 - 2 * t)


def pose_at(f):
    for (fa, a), (fb, b) in zip(KEYS, KEYS[1:]):
        if fa <= f <= fb:
            if fb == MENACE and f < MENACE:
                fb, b = fa, a
            t = _ease((f - fa) / max(fb - fa, 1))
            p = {k: a[k] + (b[k] - a[k]) * t for k in ('lean', 'tilt', 'glow')}
            p['state'] = b['state'] if t >= 1 else a['state']
            p['arms'] = {s: _unspec(_spec(a[s]) + (_spec(b[s]) - _spec(a[s])) * t) for s in ('r', 'l')}
            return p
    k = KEYS[-1][1]
    return {'lean': k['lean'], 'tilt': k['tilt'], 'glow': k['glow'], 'state': k['state'], 'arms': {s: k[s] for s in ('r', 'l')}}


def camera_at(f):
    if f < MENACE:
        t = _ease(f / (MENACE - 1))
        return Camera(yaw=-28.0 + 10.0 * t, pitch=-9.0 - 6.0 * t, target=(0.0, 17.0, 2.0), persp=96.0 - 16.0 * t, fov=40.0)
    t = _ease((f - MENACE) / (N - 1 - MENACE))
    return Camera(yaw=8.0 - 5.0 * t, pitch=-17.0 - 3.0 * t, target=(0.0, 20.0, 3.0), persp=74.0 - 8.0 * t, fov=42.0)


def light():
    L = Light()
    L.key = (-0.5, 0.8, 0.45)            # pale moonlight from high front-left
    L.key_col = (0.92, 0.94, 1.0)
    L.ambient = 0.6
    L.key_amt = 0.46
    L.ao_amt = 0.26
    L.jitter = 0.0                       # no per-face speckle: it would flicker frame to frame
    L.rim = (0.25, 0.35, -0.9)           # the gate's Hollow light from behind it
    L.rim_col = (0.78, 0.6, 1.0)
    L.rim_amt = 0.6
    L.rim_pow = 1.3
    return L


GLOWS = np.array([[217, 194, 255], [200, 177, 228], [153, 117, 201], [241, 230, 255]], np.float32)


def bloom(rgba):
    """its eyes, runes and crystals bleed light: a soft violet halo baked round them"""
    a = rgba[..., 3:4].astype(np.float32) / 255.0
    rgb = rgba[..., :3].astype(np.float32)
    d = np.min(np.linalg.norm(rgb[..., None, :] - GLOWS[None, None], axis=-1), -1)
    src = (np.clip(1.0 - d / 60.0, 0, 1) * a[..., 0])
    im = Image.fromarray((src * 255).astype(np.uint8), 'L')
    halo = (np.asarray(im.filter(ImageFilter.GaussianBlur(8)), np.float32) / 255.0 * 0.9
            + np.asarray(im.filter(ImageFilter.GaussianBlur(24)), np.float32) / 255.0 * 0.7)
    halo = np.clip(halo * 1.5, 0, 1)[..., None]
    col = np.array([196, 160, 255], np.float32)
    out_a = np.maximum(a, halo * 0.7)
    out_rgb = np.where(a > 0.01, rgb + (255.0 - rgb) * halo * 0.45, col)
    return np.dstack([np.clip(out_rgb, 0, 255), out_a * 255]).astype(np.uint8)


def fit_for(f):
    """the ground under it at a fixed spot for each camera: low in the frame and filling it for the first,
    closer still (its feet off the bottom) for the second"""
    cam = camera_at(MENACE if f >= MENACE else 0)
    if f >= MENACE:
        scale, gy = 660.0, H * 0.99
    else:
        scale, gy = 540.0, H * 0.88
    gx, gyy, _ = cam.project(np.array([[0.0, 0.0, 0.0]]))
    return Fit(scale, W * 0.5 - gx[0] * scale, gy - gyy[0] * scale, W, H)


def _xform(p, pt):
    """a point on the model, moved as the pose moves the model (lean, then tilt; about its feet)"""
    v = np.asarray(pt, float)
    v = WF.rot(rx=p['lean']) @ v
    v = WF.rot(rz=p['tilt']) @ v
    return v


def _frame(f):
    p = pose_at(f)
    M, anc = WF.sentinel({'state': p['state'], 'arms': p['arms'], 'lean': p['lean'], 'tilt': p['tilt'], 'glow': p['glow'] > 0.5}, 'hollow')
    cam = camera_at(f)
    ft = fit_for(f)
    o = render(M, {}, cam, W, H, fit=ft, light=light(), ss=3, outline_px=3.2, outline_col=WF.OUTLINE,
               inner_thresh=2.0, inner_alpha=0.7, inner_px=1.1)
    rgba = bloom(o.rgba)
    (_, _), (fr, _) = p['arms']['r'] if not isinstance(p['arms']['r'], str) else _unspec(_spec(p['arms']['r']))
    (_, _), (fl, _) = p['arms']['l'] if not isinstance(p['arms']['l'], str) else _unspec(_spec(p['arms']['l']))
    pts = [(0.0, 0.0, 0.0), _xform(p, (0.0, 27.3, 6.6)), _xform(p, (0.0, 14.5, 9.0)),
           _xform(p, fr), _xform(p, (-fl[0], fl[1], fl[2]))]
    px = project_px(cam, ft, np.array(pts))
    return rgba, [[round(float(x), 1), round(float(y), 1)] for x, y in px]


def main(out, preview=False, jobs=2):
    os.makedirs(out, exist_ok=True)
    with ProcessPoolExecutor(jobs) as ex:
        res = list(ex.map(_frame, range(N)))
    meta = {'w': W, 'h': H, 'fps': FPS, 'frames': N, 'lit': LIT, 'roar': ROAR, 'beam': BEAM, 'menace': MENACE,
            'ground': [], 'eyes': [], 'chest': [], 'fists': []}
    for i, (rgba, pts) in enumerate(res):
        fn = f'sentinel_intro_{i:02d}.webp'
        im = Image.fromarray(rgba, 'RGBA')
        im.save(os.path.join(out, fn), quality=86, method=6)
        if preview:
            im.save(os.path.join(out, fn.replace('.webp', '.png')))
        meta['ground'].append(pts[0])
        meta['eyes'].append(pts[1])
        meta['chest'].append(pts[2])
        meta['fists'].append(pts[3:5])
        print(fn, os.path.getsize(os.path.join(out, fn)) // 1024, 'KB', flush=True)
    json.dump(meta, open(os.path.join(out, 'sentinel_intro.json'), 'w'))


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    jobs = int(next((a.split('=')[1] for a in sys.argv if a.startswith('--jobs=')), '2'))
    if '--frames' in ' '.join(sys.argv):
        fs = [int(x) for x in next(a.split('=')[1] for a in sys.argv if a.startswith('--frames=')).split(',')]
        os.makedirs(args[0], exist_ok=True)
        with ProcessPoolExecutor(jobs) as ex:
            res = list(ex.map(_frame, fs))
        strip = np.concatenate([r[0] for r in res], 1)
        bg = Image.new('RGBA', (strip.shape[1], strip.shape[0]), (40, 40, 56, 255))
        bg.alpha_composite(Image.fromarray(strip, 'RGBA'))
        from PIL import ImageDraw
        dr = ImageDraw.Draw(bg)
        for k, (_, pts) in enumerate(res):
            for (x, y) in pts:
                dr.ellipse((x + k * W - 8, y - 8, x + k * W + 8, y + 8), outline=(255, 80, 80, 255), width=3)
        bg.convert('RGB').resize((strip.shape[1] // 3, strip.shape[0] // 3)).save(os.path.join(args[0], 'intro_keys.jpg'), quality=85)
    else:
        main(args[0], '--preview' in sys.argv, jobs)

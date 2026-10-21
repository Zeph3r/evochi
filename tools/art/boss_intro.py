"""The Briarback's entrance: the guardian seen from low down in perspective, pawing the moss, rearing up
with its front hooves thrashing and a roar, then slamming down and lowering its antlers at you. Drawn
with the same voxels and flat renderer as its walking sprites, so it matches the game, but through a low
perspective camera that drifts in while it moves.

    python3 boss_intro.py OUT_DIR [--preview] [--jobs=2]

Writes OUT_DIR/briarback_intro_00.webp ... (transparent frames, FPS below) and briarback_intro.json:
the frame size and rate, the frame where the hooves hit the ground (the app shakes the screen and slams
the title card there), the frames with the mouth open (the roar), and per frame where the hooves and the
ground under it land in the picture (for dust and the contact shadow).
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
import voxel                                                     # noqa: E402
from voxel import Camera, Fit, Light, render, project_px         # noqa: E402
import wilds_foes as WF                                          # noqa: E402

W, H = 864, 1296
FPS = 15
N = 36
IMPACT = 25

# room to rear up: the walking sprites never lift the head this high, so the model's box grows here
_Model = voxel.Model


RES = 3          # finer voxels than its map sprite (2): it fills the screen here


def _roomy(lo, hi, *a, **k):
    # only the Briarback's own box (its parts are made from the grown one and must keep its size)
    if tuple(lo) == (-24, -6, -30) and tuple(hi) == (24, 68, 36):
        lo, hi = (lo[0] - 4, lo[1], lo[2] - 14), (hi[0] + 4, hi[1] + 34, hi[2] + 12)
        k['res'] = RES
    return _Model(lo, hi, *a, **k)


WF.Model = _roomy

# a close-up wants texture: the coat gets tufts of lighter and darker fur and the moss gets clumps. Laid
# down as each part is painted (before it is posed), so the pattern rides with the body and never swims.
_put = WF.put
_C = WF.BB['hollow']
_FUR = {_C['coat']: (_C['coat_hi'], _C['coat_lo']), _C['coat_lo']: (_C['coat'], '#3F291F'),
        _C['coat_hi']: ('#9C7458', _C['coat']), _C['belly']: ('#B39A86', '#86705F'),
        _C['moss']: ('#76985A', '#4A673A'), _C['antler']: (_C['antler_hi'], '#3A2943')}


def _furry(M, mask, col, glow=None, empty=False):
    mask = _put(M, mask, col, glow, empty)
    if col in _FUR and mask.any():
        hi, lo = _FUR[col]
        X, Y, Z = M.X, M.Y, M.Z
        n = (np.sin(X * 2.2 + np.sin(Z * 0.8) * 1.6) * np.cos(Y * 1.7 - Z * 0.55)
             + 0.22 * np.sin(X * 5.1 + Y * 3.7 + Z * 4.3) + 0.12 * np.sin(Z * 7.9 - X * 2.3))
        M.set(mask & (n > 0.78), hi)
        M.set(mask & (n < -0.82), lo)
    return mask


WF.put = _furry

FL, FR, BL, BR = (-1, True), (1, True), (-1, False), (1, False)

# keyframes: frame -> pose (numbers ease between keys; 'mouth' and 'daze' hold until the next key)
KEYS = [
    (0, dict(head=0.45, low=1.0, glow=0.3, feet={FL: (0.0, 3.0)})),
    (3, dict(head=0.5, low=1.1, glow=0.35, feet={FL: (2.6, -1.5)})),
    (6, dict(head=0.5, low=1.2, glow=0.4, feet={FL: (0.0, 3.2)})),
    (9, dict(head=0.72, low=1.9, glow=0.6, feet={FL: (0.0, 1.0), FR: (0.0, 1.0)})),
    (14, dict(rear=0.5, head=0.25, low=0.0, glow=1.0, mouth=True, feet={FL: (11.0, 6.0), FR: (11.0, 6.0)})),
    (16, dict(rear=0.56, head=0.42, tilt=0.2, glow=1.0, mouth=True, feet={FL: (15.0, 9.0), FR: (8.0, 4.0)})),
    (18, dict(rear=0.58, head=0.34, tilt=-0.2, glow=1.0, mouth=True, feet={FL: (8.0, 4.0), FR: (15.0, 9.0)})),
    (20, dict(rear=0.56, head=0.45, tilt=0.14, glow=1.0, mouth=True, feet={FL: (15.0, 9.0), FR: (8.0, 4.0)})),
    (22, dict(rear=0.48, head=0.3, glow=1.0, mouth=True, feet={FL: (11.0, 6.0), FR: (11.0, 6.0)})),
    (25, dict(rear=0.0, head=0.6, low=2.8, splay=1.0, glow=1.0, feet={FL: (0.0, 4.0), FR: (0.0, 4.0)})),
    (28, dict(head=0.72, low=1.7, splay=0.6, glow=0.9, feet={FL: (0.0, 3.0), FR: (0.0, 3.0)})),
    (35, dict(head=0.8, low=1.25, yaw=0.08, glow=0.8, feet={FL: (0.0, 2.0), FR: (0.0, 2.0)})),
]
NUMS = ('head', 'low', 'glow', 'rear', 'tilt', 'yaw', 'splay', 'roll')


def _ease(t):
    return t * t * (3 - 2 * t)


def pose_at(f):
    for (fa, a), (fb, b) in zip(KEYS, KEYS[1:]):
        if fa <= f <= fb:
            t = (f - fa) / max(fb - fa, 1)
            # the slam is a fall: it speeds up into the ground
            t = t * t if fb == IMPACT else _ease(t)
            p = {k: a.get(k, 0.0) + (b.get(k, 0.0) - a.get(k, 0.0)) * t for k in NUMS}
            feet = {}
            for leg in (FL, FR, BL, BR):
                ya, za = a.get('feet', {}).get(leg, (0.0, 0.0))
                yb, zb = b.get('feet', {}).get(leg, (0.0, 0.0))
                feet[leg] = (ya + (yb - ya) * t, za + (zb - za) * t)
            p['feet'] = feet
            if a.get('mouth') and (b.get('mouth') or t < 0.5):
                p['mouth'] = True
            return p
    return dict(KEYS[-1][1])


def camera_at(f):
    t = _ease(f / (N - 1))
    return Camera(yaw=-30.0 + 9.0 * t, pitch=-14.0 - 4.0 * t, target=(0.0, 32.0, 2.0), persp=124.0 - 20.0 * t, fov=38.0)


def light():
    L = Light()
    L.key = (-0.45, 0.85, 0.4)          # a shaft of light from high front-left
    L.key_col = (1.0, 0.95, 0.86)
    L.ambient = 0.66
    L.key_amt = 0.42
    L.ao_amt = 0.24
    L.jitter = 0.0                      # no per-face speckle: it would flicker frame to frame
    L.rim = (0.3, 0.3, -0.9)            # a violet Hollow glow from behind it
    L.rim_col = (0.8, 0.62, 1.0)
    L.rim_amt = 0.55
    L.rim_pow = 1.3
    return L


GLOWS = np.array([[217, 194, 255], [200, 177, 228], [153, 117, 201]], np.float32)


def bloom(rgba):
    """the Hollow crystals, eyes and cracks bleed light: a soft violet halo baked round them"""
    from PIL import ImageFilter
    a = rgba[..., 3:4].astype(np.float32) / 255.0
    rgb = rgba[..., :3].astype(np.float32)
    d = np.min(np.linalg.norm(rgb[..., None, :] - GLOWS[None, None], axis=-1), -1)
    src = (np.clip(1.0 - d / 70.0, 0, 1) * a[..., 0])
    im = Image.fromarray((src * 255).astype(np.uint8), 'L')
    halo = (np.asarray(im.filter(ImageFilter.GaussianBlur(9)), np.float32) / 255.0 * 0.9
            + np.asarray(im.filter(ImageFilter.GaussianBlur(26)), np.float32) / 255.0 * 0.7)
    halo = np.clip(halo * 1.6, 0, 1)[..., None]
    col = np.array([196, 160, 255], np.float32)
    # over the body: add light; off it: a glow with its own alpha
    out_a = np.maximum(a, halo * 0.75)
    out_rgb = np.where(a > 0.01, rgb + (255.0 - rgb) * halo * 0.5, col)
    o = np.dstack([np.clip(out_rgb, 0, 255), out_a * 255]).astype(np.uint8)
    return o


def fit():
    # the ground under it at the same spot in every frame of the first camera; it grows as the camera
    # drifts in
    cam = camera_at(0)
    scale = 500.0
    gx, gy, _ = cam.project(np.array([[0.0, 0.0, 0.0]]))
    return Fit(scale, W * 0.5 - gx[0] * scale, H * 0.93 - gy[0] * scale, W, H)


def _frame(f):
    p = pose_at(f)
    M, _ = WF.briarback(p, 'hollow')
    cam = camera_at(f)
    ft = fit()
    o = render(M, {}, cam, W, H, fit=ft, light=light(), ss=3, outline_px=3.4, outline_col=WF.OUTLINE,
               inner_thresh=2.0, inner_alpha=0.7, inner_px=1.1)
    rgba = bloom(o.rgba)
    # where things land in the picture this frame (the body's rotation is about the hind hip)
    pts = [(0.0, 0.0, 0.0)]
    for side in (-1, 1):
        dy, dz = p['feet'][(side, True)]
        hoof = np.array([side * 4.9, 1.2 + dy, 10.0 + dz])
        r = p.get('rear', 0.0)
        if r:
            c, s = math.cos(r), math.sin(r)
            rel = hoof - np.array([0.0, 0.0, -13.0])
            hoof = np.array([rel[0], rel[1] * c + rel[2] * s, -rel[1] * s + rel[2] * c]) + np.array([0.0, 0.0, -13.0])
        pts.append(tuple(hoof))
    # the mouth (the roar's blast comes from here): turned with the head about the neck, then reared
    dy = -p.get('low', 0.0)
    piv = np.array([0.0, 28 + dy, 7.0])
    R = WF.rot(rx=p.get('head', 0.0), ry=p.get('yaw', 0.0), rz=p.get('tilt', 0.0))
    mouth = piv + R @ (np.array([0.0, 36.0 + dy, 26.5]) - piv)
    r = p.get('rear', 0.0)
    if r:
        mouth = WF.rot(rx=-r) @ (mouth - np.array([0.0, 0.0, -13.0])) + np.array([0.0, 0.0, -13.0])
    pts.append(tuple(mouth))
    px = project_px(cam, ft, np.array(pts))
    return rgba, [[round(float(x), 1), round(float(y), 1)] for x, y in px], bool(p.get('mouth'))


def main(out, preview=False, jobs=2):
    os.makedirs(out, exist_ok=True)
    with ProcessPoolExecutor(jobs) as ex:
        res = list(ex.map(_frame, range(N)))
    meta = {'w': W, 'h': H, 'fps': FPS, 'frames': N, 'impact': IMPACT, 'roar': [], 'ground': [], 'hooves': []}
    for i, (rgba, pts, mouth) in enumerate(res):
        fn = f'briarback_intro_{i:02d}.webp'
        im = Image.fromarray(rgba, 'RGBA')
        im.save(os.path.join(out, fn), quality=86, method=6)
        if preview:
            im.save(os.path.join(out, fn.replace('.webp', '.png')))
        meta['ground'].append(pts[0])
        meta['hooves'].append(pts[1:3])
        meta.setdefault('mouth', []).append(pts[3])
        if mouth:
            meta['roar'].append(i)
        print(fn, os.path.getsize(os.path.join(out, fn)) // 1024, 'KB', flush=True)
    json.dump(meta, open(os.path.join(out, 'briarback_intro.json'), 'w'))


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    jobs = int(next((a.split('=')[1] for a in sys.argv if a.startswith('--jobs=')), '2'))
    if '--frames' in ' '.join(sys.argv):
        # a quick look at a few frames: --frames=0,9,16,25,35
        fs = [int(x) for x in next(a.split('=')[1] for a in sys.argv if a.startswith('--frames=')).split(',')]
        os.makedirs(args[0], exist_ok=True)
        with ProcessPoolExecutor(jobs) as ex:
            res = list(ex.map(_frame, fs))
        strip = np.concatenate([r[0] for r in res], 1)
        bg = Image.new('RGBA', (strip.shape[1], strip.shape[0]), (40, 52, 44, 255))
        bg.alpha_composite(Image.fromarray(strip, 'RGBA'))
        bg.convert('RGB').resize((strip.shape[1] // 3, strip.shape[0] // 3)).save(os.path.join(args[0], 'intro_keys.jpg'), quality=85)
    else:
        main(args[0], '--preview' in sys.argv, jobs)

"""The Hollow Sprout's entrance (the Mossy Ruins, F3): seen from low down in perspective among the stones,
wilted and asleep in its roots; its slit eyes ignite, it uncurls and rears back, its crystals flaring as it
swells and bursts a storm of Hollow spores at your Evochi; then it slams its bulb down, and (a second camera,
lower and closer) sways over you for the title card. Drawn with the same voxels and flat renderer as its
fighting sprites, at finer voxels, so it holds up close.

    python3 sprout_intro.py OUT_DIR [--jobs=2]
    python3 sprout_intro.py OUT_DIR --frames=0,4,10,16,19,23,28      a strip of a few frames to look at

Writes OUT_DIR/sprout_intro_00.webp ... (transparent frames) and sprout_intro.json: the frame size and rate,
where the parts start, and per frame where its eyes, crystal tips, sprout and the ground under it land in the
picture (the app bursts the spores out of it, flares the crystals and shakes on the slam): 'eyes' (one point
per frame, in a list), 'top', 'mouth', 'crystals', and its root feet as 'hooves'.
"""
from __future__ import annotations

import json
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

W, H = 900, 1100
FPS = 12
N = 36
WAKE, RISE, SWELL, SLAM, MENACE = 0, 10, 16, 20, 26     # where each part starts
LIT = 4                                                 # its eyes ignite
BURST = 19                                              # the spores burst out
IMPACT = 23                                             # the bulb hits the ground

# finer voxels than its map sprite: it fills the screen here
_M = TA.M_


def _fine(lo, hi, res=1):
    if tuple(lo) == (-14, -1, -14):
        return _M((-16, -1, -16), (16, 32, 16), res=3)
    return _M(lo, hi, res=res)


TA.M_ = _fine

# keyframes: frame -> pose (lean forward +, tilt sideways, glow 0..1, swell: its size)
KEYS = [
    (0, dict(lean=0.26, tilt=0.05, glow=0.0, swell=0.96)),
    (3, dict(lean=0.25, tilt=0.04, glow=0.0, swell=0.96)),
    (LIT, dict(lean=0.24, tilt=0.03, glow=0.35, swell=0.97)),
    (7, dict(lean=0.18, tilt=-0.02, glow=0.5, swell=0.98)),
    (RISE, dict(lean=0.05, tilt=-0.05, glow=0.6, swell=1.0)),
    (13, dict(lean=-0.2, tilt=0.04, glow=0.8, swell=1.02)),
    (15, dict(lean=-0.3, tilt=0.0, glow=0.9, swell=1.04)),
    (SWELL, dict(lean=-0.32, tilt=-0.02, glow=1.0, swell=1.08)),
    (18, dict(lean=-0.34, tilt=0.02, glow=1.0, swell=1.14)),
    (BURST, dict(lean=-0.28, tilt=0.0, glow=1.0, swell=1.02)),
    (SLAM, dict(lean=-0.1, tilt=0.0, glow=1.0, swell=1.0)),
    (22, dict(lean=0.4, tilt=0.0, glow=1.0, swell=1.0)),
    (IMPACT, dict(lean=0.56, tilt=0.0, glow=1.0, swell=0.94)),
    (25, dict(lean=0.42, tilt=0.0, glow=1.0, swell=1.0)),
    # the second camera: swaying over you, its crystals pulsing
    (MENACE, dict(lean=0.12, tilt=-0.04, glow=1.0, swell=1.0)),
    (31, dict(lean=0.16, tilt=0.05, glow=1.0, swell=1.03)),
    (N - 1, dict(lean=0.12, tilt=-0.03, glow=1.0, swell=1.0)),
]


def _ease(t):
    return t * t * (3 - 2 * t)


def pose_at(f):
    for (fa, a), (fb, b) in zip(KEYS, KEYS[1:]):
        if fa <= f <= fb:
            if fb == MENACE and f < MENACE:
                fb, b = fa, a
            t = _ease((f - fa) / max(fb - fa, 1))
            return {k: a[k] + (b[k] - a[k]) * t for k in a}
    return dict(KEYS[-1][1])


def camera_at(f):
    if f < MENACE:
        t = _ease(f / (MENACE - 1))
        return Camera(yaw=30.0 - 10.0 * t, pitch=-5.0 - 5.0 * t, target=(0.0, 9.0, 1.0), persp=70.0 - 12.0 * t, fov=40.0)
    t = _ease((f - MENACE) / (N - 1 - MENACE))
    return Camera(yaw=14.0 - 6.0 * t, pitch=-13.0 - 3.0 * t, target=(0.0, 10.5, 2.0), persp=54.0 - 6.0 * t, fov=42.0)


def light():
    L = Light()
    L.key = (-0.45, 0.8, 0.5)            # dusk from high front-left, through the broken roof
    L.key_col = (1.0, 0.93, 0.92)
    L.ambient = 0.78
    L.key_amt = 0.55
    L.ao_amt = 0.28
    L.jitter = 0.0                       # no per-face speckle: it would flicker frame to frame
    L.rim = (0.3, 0.3, -0.9)             # the Hollow's light behind it
    L.rim_col = (0.8, 0.6, 1.0)
    L.rim_amt = 0.85
    L.rim_pow = 1.3
    return L


GLOWS = np.array([[217, 194, 255], [200, 177, 228], [153, 117, 201], [241, 230, 255]], np.float32)


def bloom(rgba, k):
    """its eyes, crystals and glowing vine buds bleed light: a soft violet halo baked round them"""
    a = rgba[..., 3:4].astype(np.float32) / 255.0
    rgb = rgba[..., :3].astype(np.float32)
    d = np.min(np.linalg.norm(rgb[..., None, :] - GLOWS[None, None], axis=-1), -1)
    src = (np.clip(1.0 - d / 60.0, 0, 1) * a[..., 0]) * (0.35 + 0.65 * k)
    im = Image.fromarray((src * 255).astype(np.uint8), 'L')
    halo = (np.asarray(im.filter(ImageFilter.GaussianBlur(7)), np.float32) / 255.0 * 0.9
            + np.asarray(im.filter(ImageFilter.GaussianBlur(20)), np.float32) / 255.0 * 0.7)
    halo = np.clip(halo * 1.5, 0, 1)[..., None]
    col = np.array([196, 160, 255], np.float32)
    out_a = np.maximum(a, halo * 0.7)
    out_rgb = np.where(a > 0.01, rgb + (255.0 - rgb) * halo * 0.45, col)
    return np.dstack([np.clip(out_rgb, 0, 255), out_a * 255]).astype(np.uint8)


def fit_for(f):
    """the ground under it at a fixed spot for each camera: low in the frame for the first, closer still for
    the second"""
    cam = camera_at(MENACE if f >= MENACE else 0)
    if f >= MENACE:
        scale, gy = 1120.0, H * 0.97
    else:
        scale, gy = 900.0, H * 0.86
    gx, gyy, _ = cam.project(np.array([[0.0, 0.0, 0.0]]))
    return Fit(scale, W * 0.5 - gx[0] * scale, gy - gyy[0] * scale, W, H)


CRYSTALS = [(-3.0 + 0.4, 8.0 + 4.5, -5.5 - 1.2), (2.5 + 0.4, 8.0 + 3.6, -6.0 - 1.2), (5.5 + 0.4, 8.0 + 2.8, -3.0 - 1.2)]


def _xform(p, pt):
    """a point on the model, moved as the pose moves it (swell, lean, then tilt; about its root)"""
    v = np.asarray(pt, float) * p['swell']
    v = WF.rot(rx=p['lean']) @ v
    v = WF.rot(rz=p['tilt']) @ v
    return v


def model(p):
    M, _ = TA.hollow_sprout('hollow')
    s = p['swell']
    if abs(s - 1) > 1e-3:
        M = WF.turn(M, (0, 0, 0), np.diag([1 / s, 1 / s, 1 / s]))
    if p['lean']:
        M = WF.turn(M, (0, 0, 0), WF.rot(rx=p['lean']))
    if p['tilt']:
        M = WF.turn(M, (0, 0, 0), WF.rot(rz=p['tilt']))
    g = M.glow > 0
    if p['glow'] < 0.2:
        # asleep: its eyes, mouth and buds dark (no light in them yet)
        M.m[g] = M.mid(TA.VINE_H_HI)
        M.glow[g] = 0
        return M
    M.glow[g] = np.clip(M.glow[g] * (0.35 + 0.65 * p['glow']) + 0.3 * p['glow'], 0, 1)
    return M


def _frame(f):
    p = pose_at(f)
    M = model(p)
    cam = camera_at(f)
    ft = fit_for(f)
    o = render(M, {}, cam, W, H, fit=ft, light=light(), ss=3, outline_px=3.0, outline_col=WF.OUTLINE,
               inner_thresh=2.0, inner_alpha=0.7, inner_px=1.0)
    rgba = bloom(o.rgba, p['glow'])
    pts = [(0.0, 0.0, 0.0), _xform(p, (0.0, 7.6, 7.5)), _xform(p, (0.0, 17.5, 0.0)), _xform(p, (0.0, 5.2, 7.4))]
    pts += [_xform(p, c) for c in CRYSTALS]
    pts += [_xform(p, (s * 5.5, 0.6, dz)) for s in (-1, 1) for dz in (2.5, -2.5)]     # its root feet
    px = project_px(cam, ft, np.array(pts))
    return rgba, [[round(float(x), 1), round(float(y), 1)] for x, y in px]


def main(out, jobs=2):
    os.makedirs(out, exist_ok=True)
    with ProcessPoolExecutor(jobs) as ex:
        res = list(ex.map(_frame, range(N)))
    meta = {'w': W, 'h': H, 'fps': FPS, 'frames': N, 'lit': LIT, 'rise': RISE, 'swell': SWELL, 'burst': BURST,
            'slam': SLAM, 'impact': IMPACT, 'menace': MENACE, 'ground': [], 'eyes': [], 'top': [], 'mouth': [],
            'crystals': [], 'hooves': []}
    for i, (rgba, pts) in enumerate(res):
        fn = f'sprout_intro_{i:02d}.webp'
        Image.fromarray(rgba, 'RGBA').save(os.path.join(out, fn), quality=86, method=6)
        meta['ground'].append(pts[0])
        meta['eyes'].append([pts[1]])
        meta['top'].append(pts[2])
        meta['mouth'].append(pts[3])
        meta['crystals'].append(pts[4:7])
        meta['hooves'].append(pts[7:11])       # its root feet (the app's name for what stands on the ground)
        print(fn, os.path.getsize(os.path.join(out, fn)) // 1024, 'KB', flush=True)
    json.dump(meta, open(os.path.join(out, 'sprout_intro.json'), 'w'))


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
        main(args[0], jobs)

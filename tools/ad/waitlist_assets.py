"""Extra art for the waitlist videos: the Eggling building itself voxel by voxel, its expressions and
turnaround, the Founder's Crown (a rose-gold recolour of the Golden Crest Crown) on all three forms,
and a night version of the meadow vista.

python3 waitlist_assets.py OUT_DIR
"""
import copy
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'art'))

from characters import build  # noqa: E402
from charrender import render_char  # noqa: E402
from voxel import Camera, save_rgba  # noqa: E402

A = os.path.join(ROOT, 'assets')
SITE = os.path.join(ROOT, 'site', 'assets', 'img')
PAL = 'ocean'
out = sys.argv[1]
os.makedirs(out, exist_ok=True)


def webp(img, name, q=88):
    path = os.path.join(out, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, 'WEBP', quality=q, method=6)
    return path


# ------------------------------------------------------------------ 1. voxel build-up
def buildup(frames=40):
    ch = build(1)
    from charrender import char_fit
    cam = Camera(yaw=18, pitch=13)
    fit = char_fit(ch, cam, 440, 500)
    M = ch.model
    ys = M.Y
    y0, y1 = ys[M.m > 0].min(), ys[M.m > 0].max()
    base_m = M.m.copy()
    for k in range(frames):
        p = (k + 1) / frames
        h = y0 + (y1 - y0) * (p ** 0.9)
        c2 = copy.copy(ch)
        c2.model = copy.copy(M)
        c2.model.m = np.where(ys <= h, base_m, 0)
        o = render_char(c2, PAL, 'happy', cam, 440, 500, fit=fit)
        save_rgba(o.rgba, os.path.join(out, 'build', f'b{k:03d}.png'))
        Image.open(os.path.join(out, 'build', f'b{k:03d}.png')).save(os.path.join(out, 'build', f'b{k:03d}.webp'), 'WEBP', quality=90, method=4)
        os.remove(os.path.join(out, 'build', f'b{k:03d}.png'))
    print('build-up done', flush=True)
    return fit


# ------------------------------------------------------------------ 2. expressions + turnaround
def sheets():
    for e in ['default', 'blink', 'happy', 'curious', 'surprised', 'determined', 'sad', 'sleepy', 'excited', 'neutral']:
        im = Image.open(os.path.join(A, 'characters', f'evochi_lizard_s01_{PAL}_{e}_left3q_f000.png')).convert('RGBA')
        webp(im, f'expr/{e}.webp')
    for v in ['front', 'left', 'back', 'right', 'top']:
        im = Image.open(os.path.join(A, 'characters', f'evochi_lizard_s01_{PAL}_default_{v}_f000.png')).convert('RGBA')
        webp(im, f'turn/{v}.webp')
    for st in ('s02', 's03'):
        im = Image.open(os.path.join(A, 'characters', f'evochi_lizard_{st}_{PAL}_happy_left3q_f000.png')).convert('RGBA')
        webp(im, f'forms/{st}.webp')
    print('sheets done', flush=True)


# ------------------------------------------------------------------ 3. Founder's Crown
def founder_tint(img):
    """Gold -> rose gold, keeping the shading. Pixels that aren't gold (gems, outlines) stay."""
    hsv = np.asarray(img.convert('RGBA').convert('RGB').convert('HSV'), float)
    a = np.asarray(img.convert('RGBA'))[..., 3]
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    gold = (h > 18) & (h < 50) & (s > 60) & (a > 0)        # PIL hue is 0..255
    h2 = np.where(gold, 238.0, h)                           # ~336 deg: rose gold
    s2 = np.where(gold, np.clip(s * 0.62, 0, 255), s)
    v2 = np.where(gold, np.clip(v * 1.0, 0, 255), v)
    rgb = Image.fromarray(np.dstack([h2, s2, v2]).astype(np.uint8), 'HSV').convert('RGB')
    res = Image.fromarray(np.dstack([np.asarray(rgb), a]).astype(np.uint8), 'RGBA')
    return res


def founder_crown():
    icon = Image.open(os.path.join(A, 'items', 'item_golden_crest_crown_icon.png')).convert('RGBA')
    ic = founder_tint(icon)
    webp(ic, 'crown/icon.webp', 92)
    webp(icon, 'crown/icon_gold.webp', 92)
    for st, expr in (('s01', 'happy'), ('s02', 'happy'), ('s03', 'default')):
        body = Image.open(os.path.join(A, 'characters', f'evochi_lizard_{st}_{PAL}_{expr}_left3q_f000.png')).convert('RGBA')
        ov = Image.open(os.path.join(A, 'characters', f'item_golden_crest_crown_head_{st}_left3q.png')).convert('RGBA')
        ov = founder_tint(ov)
        comb = body.copy()
        comb.alpha_composite(ov)
        webp(comb, f'crown/{st}_crowned.webp')
        webp(body, f'crown/{st}_plain.webp')
    print('crown done', flush=True)


# ------------------------------------------------------------------ 4. night vista
def night():
    day = Image.open(os.path.join(SITE, 'hero', 'hero-2880.webp')).convert('RGB')
    arr = np.asarray(day, float) / 255
    # lantern: the brightest warm patch in the upper right
    lum = arr[..., 0] * 0.6 + arr[..., 1] * 0.4 - arr[..., 2] * 0.6
    sub = lum[100:600, 2000:2800]
    ly, lx = np.unravel_index(np.argmax(sub), sub.shape)
    lx += 2000
    ly += 100
    H, W = arr.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.sqrt((xx - lx) ** 2 + (yy - ly) ** 2)
    glow = np.exp(-(d / 520) ** 2)
    tint = np.array([0.30, 0.36, 0.62])
    nightc = arr * tint[None, None, :] * 0.9
    warm = np.array([1.0, 0.82, 0.5])
    nightc = nightc + arr * warm[None, None, :] * glow[..., None] * 0.9
    # stars in the sky band
    rng = np.random.default_rng(3)
    stars = np.zeros((H, W))
    for _ in range(260):
        sx, sy = rng.integers(0, W), rng.integers(0, int(H * 0.42))
        if arr[sy, sx, 2] > 0.6 and arr[sy, sx, 0] < 0.75:   # on sky, not on clouds
            stars[max(0, sy - 1):sy + 2, max(0, sx - 1):sx + 2] = rng.uniform(0.5, 1.0)
    stars = np.asarray(Image.fromarray((stars * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)), float) / 255
    nightc = nightc + stars[..., None] * np.array([0.9, 0.95, 1.0])[None, None, :]
    img = Image.fromarray((np.clip(nightc, 0, 1) * 255).astype(np.uint8))
    webp(img, 'vista/night.webp', 82)
    webp(day, 'vista/day.webp', 82)
    print('night done, lantern at', lx, ly, flush=True)


if __name__ == '__main__':
    only = [a[2:] for a in sys.argv[2:] if a.startswith('--')]
    steps = {'sheets': sheets, 'crown': founder_crown, 'night': night, 'build': buildup}
    for name, fn in steps.items():
        if not only or name in only:
            fn()

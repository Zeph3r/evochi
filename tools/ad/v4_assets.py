"""Extra art for the v4 videos (comp_v4.html): Mochi's egg, whole and cracked, in the Ocean palette.

The game hatches from a glowing nest and never shows the egg itself, so the "started as an egg"
shots need one. Same voxel renderer, outline and camera pitch as the character sprites.

python3 v4_assets.py OUT_DIR
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'art'))

from voxel import Model, Camera, Light, render  # noqa: E402
from characters import egg_mask, shell_region, stamp, diamond_shape, plus_shape  # noqa: E402

out = sys.argv[1]
os.makedirs(os.path.join(out, 'egg'), exist_ok=True)

SHELL, SHELL_HI, SHELL_LO = '#F0F7FB', '#FFFFFF', '#D9E6EF'
PAT, PAT_HI, PAT_LO = '#97CDEB', '#C2E3F5', '#6FB0D8'
CREST, CREST_HI = '#4C9BCC', '#93C4E3'
CRACK = '#3B2923'
GLOW = '#FFE5A2'
LIGHT = Light(smooth=0.6, ao_amt=0.16, jitter=0.015, smooth_sigma=1.2)


def egg(cracked=0):
    M = Model((-14, -1, -14), (14, 34, 14), [], res=2)
    body = egg_mask(M, (0, 13.0, 0), 10.6, 17.5, 11.5, 10.6, p=2.05)
    M.set(body, SHELL)
    M.set(body & (M.Y > 20) & (M.X < -2) & (M.Z > 0), SHELL_HI)
    M.set(body & (M.Y < 4.5), SHELL_LO)
    skin = body & ~egg_mask(M, (0, 13.0, 0), 9.4, 16.3, 10.3, 9.4, p=2.05)
    # Mochi's markings: the diamond cluster on the front, plus spots around the shell
    for (c, n, shape, col) in [
        ((0.0, 17.5, 10.0), (0, 0.15, 1), plus_shape(1.6, 5.6), PAT),
        ((-6.8, 21.5, 6.0), (-0.6, 0.4, 0.7), diamond_shape(2.2), PAT_HI),
        ((7.4, 10.0, 6.5), (0.7, 0.0, 0.7), diamond_shape(2.6), PAT),
        ((-8.6, 8.0, 5.0), (-0.85, -0.1, 0.5), square_s(2.6), PAT_LO),
        ((5.2, 24.5, 3.0), (0.5, 0.75, 0.4), square_s(2.0), PAT),
        ((0.0, 6.0, 10.8), (0, -0.2, 1), diamond_shape(1.8), PAT_HI),
        ((-9.8, 15.0, -1.0), (-1, 0.1, 0), diamond_shape(2.4), PAT),
        ((9.6, 18.0, -2.0), (1, 0.2, -0.1), plus_shape(1.4, 4.4), PAT_LO),
    ]:
        stamp(M, skin, c, n, shape, col, depth=2.2)
    if cracked:
        # a zigzag crack across the front, a few voxels deep, glowing gold inside
        zig = [(-9, 19.0), (-6, 21.5), (-3, 18.5), (0, 22.0), (3, 19.0), (6, 21.8), (9, 19.5)]
        xs = np.array([p[0] for p in zig], float); ys = np.array([p[1] for p in zig], float)
        yline = np.interp(M.X, xs, ys)
        band = skin & (M.Z > 1.0) & (np.abs(M.Y - yline) <= 0.75)
        M.set(band, CRACK)
        M.set(band & (np.abs(M.Y - yline) <= 0.3), GLOW, glow=1.0)
        if cracked > 1:
            # second crack, rising toward the crest
            zig2 = [(0, 21.5), (-2.5, 24.5), (0.5, 27.0), (-1.5, 30.0)]
            ys2 = np.array([p[1] for p in zig2]); xs2 = np.array([p[0] for p in zig2], float)
            xline = np.interp(M.Y, ys2, xs2)
            band2 = skin & (M.Z > 0.0) & (np.abs(M.X - xline) <= 0.75) & (M.Y > 21.0) & (M.Y < 30.0)
            M.set(band2, CRACK)
            M.set(band2 & (np.abs(M.X - xline) <= 0.3), GLOW, glow=1.0)
    return M


def square_s(w):
    return lambda U, V: (np.abs(U) <= w / 2) & (np.abs(V) <= w / 2)


# the meadow nest from the game's decor, plus its front rim on its own so the egg can sit inside it
nest = Image.open(os.path.join(ROOT, 'assets', 'habitats', 'decor_meadow_nest_nest.png')).convert('RGBA')
nest.save(os.path.join(out, 'nest.webp'), 'WEBP', quality=92)
a = np.array(nest); hh, ww = a.shape[:2]; cx, cy, rx, ry = 228, 116, 128, 44
Y, X = np.mgrid[0:hh, 0:ww]
bound = np.where(np.abs(X - cx) < rx, cy + ry * np.sqrt(np.clip(1 - ((X - cx) / rx) ** 2, 0, 1)), cy)
a[Y < bound] = 0
Image.fromarray(a).save(os.path.join(out, 'nest_front.webp'), 'WEBP', quality=92)

cam = Camera(yaw=36, pitch=13)
size = (520, 640)
for name, k in (('egg', 0), ('egg_crack1', 1), ('egg_crack2', 2)):
    M = egg(k)
    o = render(M, {}, cam, *size, light=LIGHT, ss=3, margin=0.04, outline_px=3.2, outline_col='#3B2923',
               inner_thresh=2.0, inner_alpha=0.5, inner_px=1.0)
    im = Image.fromarray(o.rgba, 'RGBA')
    bb = im.getbbox()
    print(name, im.size, bb)
    im.save(os.path.join(out, 'egg', name + '.webp'), 'WEBP', quality=90, method=5)

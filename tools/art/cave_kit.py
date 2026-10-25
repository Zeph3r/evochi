"""The mine's galleries: the Wilds room kit's chunks (tools/art/wilds_kit.py) turned to cave floor, so
deep_floor.dart can lay out a mine with the same rooms and halls. Grass becomes cool grey rock with a
little moss in the cracks, the dirt ways become trodden gravel, everything a shade darker.

    python3 tools/art/cave_kit.py          # writes flutter/assets/art/wilds/kit_cave_*.webp
"""
import glob
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'flutter', 'assets', 'art', 'wilds')


def rgb_to_hsv(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx, mn = a.max(-1), a.min(-1)
    d = mx - mn + 1e-9
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    s = np.where(mx > 1e-9, d / (mx + 1e-9), 0)
    return h, s, mx


def hsv_to_rgb(h, s, v):
    c = v * s
    x = c * (1 - np.abs((h / 60) % 2 - 1))
    m = v - c
    z = np.zeros_like(h)
    hh = (h % 360) / 60
    r = np.select([hh < 1, hh < 2, hh < 3, hh < 4, hh < 5, hh >= 5], [c, x, z, z, x, c])
    g = np.select([hh < 1, hh < 2, hh < 3, hh < 4, hh < 5, hh >= 5], [x, c, c, x, z, z])
    b = np.select([hh < 1, hh < 2, hh < 3, hh < 4, hh < 5, hh >= 5], [z, z, x, c, c, x])
    return np.stack([r + m, g + m, b + m], -1)


def cave(im, seed):
    a = np.asarray(im.convert('RGB'), np.float32) / 255
    h, s, v = rgb_to_hsv(a)
    rng = np.random.default_rng(seed)
    n1 = ndimage.gaussian_filter(rng.random(a.shape[:2]), 2.5)
    n1 = (n1 - n1.min()) / (n1.max() - n1.min() + 1e-9)
    n2 = ndimage.gaussian_filter(rng.random(a.shape[:2]), 9)
    n2 = (n2 - n2.min()) / (n2.max() - n2.min() + 1e-9)
    green = (h > 55) & (h < 170) & (s > 0.18)
    dirt = (h >= 15) & (h <= 55) & (s > 0.2) & ~green
    # rock: cool grey, the grass's own light and dark kept as the stone's grain, a little speckle
    h2 = np.where(green, 225 + 20 * (n2 - 0.5), h)
    s2 = np.where(green, 0.07 + 0.05 * n2, s)
    v2 = np.where(green, 0.30 + 0.42 * v + 0.08 * (n1 - 0.5), v)
    # moss in the cracks: where the grass was darkest, in patches
    moss = green & (v < 0.42) & (n2 > 0.58)
    h2 = np.where(moss, 95 + 15 * n1, h2)
    s2 = np.where(moss, 0.45, s2)
    v2 = np.where(moss, 0.28 + 0.2 * v, v2)
    # the ways: trodden gravel, grey-brown, darker
    h2 = np.where(dirt, 32, h2)
    s2 = np.where(dirt, s * 0.42, s2)
    v2 = np.where(dirt, v * 0.78 + 0.04 * (n1 - 0.5), v2)
    rest = ~green & ~dirt
    s2 = np.where(rest, s * 0.55, s2)
    v2 = np.where(rest, v * 0.78, v2)
    out = hsv_to_rgb(h2, np.clip(s2, 0, 1), np.clip(v2, 0, 1))
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))


def main():
    n = 0
    for path in sorted(glob.glob(os.path.join(ROOT, 'kit_*.webp'))):
        name = os.path.basename(path)
        if name.startswith('kit_cave_'):
            continue
        out = os.path.join(ROOT, name.replace('kit_', 'kit_cave_'))
        cave(Image.open(path), n + 11).save(out, quality=84, method=6)
        n += 1
    print(n, 'cave chunks')


if __name__ == '__main__':
    main()

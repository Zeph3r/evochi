"""The deep galleries' floors (the mine from F3 down, deep_floor.dart galleryKind), from the cave kit's chunks
(tools/art/cave_kit.py):
  lava    warm black basalt, a few cracks with the heat below in them, ash and cinder in the ways (the pools,
          falls and their light are drawn live over it: wilds_screen.dart _lava*)
  hollow  cold violet-black rock split with the Hollow: its cracks glow violet, wider and more of them, the
          glowing caps grow from them (drawn live)

    python3 tools/art/lava_kit.py          # writes flutter/assets/art/wilds/kit_{lava,hollow}_*.webp
"""
import glob
import os

import numpy as np
from PIL import Image
from scipy import ndimage

from cave_kit import ROOT, hsv_to_rgb, rgb_to_hsv


def _noise(shape, sigma, rng):
    n = ndimage.gaussian_filter(rng.random(shape), sigma)
    return (n - n.min()) / (n.max() - n.min() + 1e-9)


LOOKS = {
    # rock hue, sat, crack threshold (width, heat), glow colour, core colour, glow strength, crack strength
    'lava': (18.0, 0.10, 0.024, 0.63, (0.62, 0.17, 0.05), (0.88, 0.40, 0.12), 0.45, 0.85),
    'hollow': (262.0, 0.16, 0.028, 0.36, (0.42, 0.18, 0.78), (0.78, 0.58, 1.0), 0.6, 1.0),
}


def basalt(im, seed, look='lava'):
    hue, sat, cw, ch, hot_c, core_c, gk, ck = LOOKS[look]
    a = np.asarray(im.convert('RGB'), np.float32) / 255
    h, s, v = rgb_to_hsv(a)
    rng = np.random.default_rng(seed)
    shp = a.shape[:2]
    n1, n2, n3 = _noise(shp, 2.0, rng), _noise(shp, 7, rng), _noise(shp, 16, rng)
    gravel = (h >= 20) & (h <= 45) & (s > 0.12)
    # the rock: near-black, warm, its own grain kept
    h2 = np.full_like(h, hue) + 8 * (n2 - 0.5)
    s2 = sat + 0.06 * n2
    v2 = 0.07 + 0.46 * v ** 1.2 + 0.04 * (n1 - 0.5)
    # the ways: ash and cinder, a touch lighter so they still read as the way through
    h2 = np.where(gravel, 24.0 if look == 'lava' else 250.0, h2)
    s2 = np.where(gravel, 0.08 + 0.05 * n1, s2)
    v2 = np.where(gravel, 0.14 + 0.4 * v + 0.04 * (n1 - 0.5), v2)
    out = hsv_to_rgb(h2, np.clip(s2, 0, 1), np.clip(v2, 0, 1))
    # a few cracks with the heat in them, in voxel blocks like the rest of the ground: the zero lines of a
    # smooth field, only where a deeper field runs hot, none in the ways (you walk on cooled cinder)
    B = 4
    sh = (shp[0] // B + 1, shp[1] // B + 1)
    m2, m3 = _noise(sh, 3.0 if look == 'lava' else 4.5, rng), _noise(sh, 6.0, rng)
    crack = (np.abs(m2 - 0.5) < cw) & (m3 > ch)
    crack = np.kron(crack, np.ones((B, B), bool))[:shp[0], :shp[1]] & ~gravel
    warm = np.kron(np.clip((m3 - ch) / 0.25, 0, 1), np.ones((B, B)))[:shp[0], :shp[1]]
    glow = np.clip(ndimage.gaussian_filter(crack.astype(np.float32), 3.0) * 1.5, 0, 1) * (0.25 + 0.5 * warm)
    # faint: the heat under the floor, never to be mistaken for the lava you must keep out of
    hot = np.array(hot_c)
    core = np.array(core_c)
    out = out * (1 - glow[..., None] * gk) + hot * (glow * gk)[..., None]
    c = crack[..., None] * (0.45 + 0.4 * warm[..., None]) * ck
    out = out * (1 - c) + core * c
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))


def main():
    n = 0
    for path in sorted(glob.glob(os.path.join(ROOT, 'kit_cave_*.webp'))):
        for look in LOOKS:
            out = os.path.join(ROOT, os.path.basename(path).replace('kit_cave_', f'kit_{look}_'))
            basalt(Image.open(path), n + 41, look).save(out, quality=84, method=6)
        n += 1
    print(n, 'chunks each:', ', '.join(LOOKS))


if __name__ == '__main__':
    main()

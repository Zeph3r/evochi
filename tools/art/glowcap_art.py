"""The Glowcap's art, from the Moonshroom's: the mine's glowing cave mushroom (a Hollow gallery's, foraged;
and grown at home from its spores). The violet turns to a cool cyan-teal, the pale spots and highlights to
light, and the item icons get a soft glow round them.

    python3 tools/art/glowcap_art.py    # writes items/{glowcap,seed_glowcap,gilded_glowcap}.webp,
                                        # home/crop_glowcap_{sprout,growing,ripe}.webp; adds them to manifest.json
"""
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

from cave_kit import hsv_to_rgb, rgb_to_hsv

ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'flutter', 'assets', 'art')


def recolour(im, glow=False, gilded=False):
    a = np.asarray(im.convert('RGBA'), np.float32) / 255
    rgb, al = a[..., :3], a[..., 3]
    h, s, v = rgb_to_hsv(rgb)
    violet = (h > 235) & (h < 330) & (s > 0.15)
    pale = (s < 0.18) & (v > 0.82) & (al > 0.1)          # the spots and the shine
    h2 = np.where(violet, 186 + (h - 275) * 0.35, h)
    s2 = np.where(violet, np.clip(s * 1.35 + 0.1, 0, 1), s)
    v2 = np.where(violet, np.clip(v * 0.92, 0, 1), v)
    out = hsv_to_rgb(h2, s2, v2)
    near = ndimage.binary_dilation(violet, iterations=2)          # the cap's own spots, not the stem or a packet
    lit = pale & (near if not gilded else (pale & (v > 0.95)))
    out = np.where(lit[..., None], np.array([0.80, 1.0, 0.98]), out)
    res = np.dstack([out, al])
    if glow:
        m = ndimage.gaussian_filter((violet | lit).astype(np.float32) * (al > 0.1), 5) * 1.5
        g = np.clip(m, 0, 1) * 0.5
        col = np.array([0.55, 0.95, 1.0])
        under = (1 - res[..., 3]) * g
        res[..., :3] = (res[..., :3] * res[..., 3:4] + col * under[..., None]) / np.maximum(res[..., 3:4] + under[..., None], 1e-6)
        res[..., 3] = res[..., 3] + under
    return Image.fromarray((np.clip(res, 0, 1) * 255).astype(np.uint8), 'RGBA')


def main():
    man_p = os.path.join(ART, 'manifest.json')
    man = json.load(open(man_p))
    for src, dst, glow, gilded in (('moonshroom', 'glowcap', True, False), ('seed_moonshroom', 'seed_glowcap', False, False),
                                   ('gilded_moonshroom', 'gilded_glowcap', True, True)):
        recolour(Image.open(os.path.join(ART, 'items', f'{src}.webp')), glow, gilded).save(os.path.join(ART, 'items', f'{dst}.webp'), quality=92, method=6)
        man['items'][dst] = f'items/{dst}.webp'
    # the Glowcap Elixir: the Glowleaf Tonic's bottle, its green brew turned the glowcap's cyan
    im = Image.open(os.path.join(ART, 'items', 'glowleaf_tonic.webp'))
    a = np.asarray(im.convert('RGBA'), np.float32) / 255
    h, sat, v = rgb_to_hsv(a[..., :3])
    green = (h > 70) & (h < 175) & (sat > 0.2)
    rgb = hsv_to_rgb(np.where(green, 188 + (h - 120) * 0.25, h), np.where(green, np.clip(sat * 1.1, 0, 1), sat), np.where(green, np.clip(v * 1.05, 0, 1), v))
    recolour(Image.fromarray((np.dstack([rgb, a[..., 3]]) * 255).astype(np.uint8), 'RGBA'), glow=True).save(
        os.path.join(ART, 'items', 'glowcap_elixir.webp'), quality=92, method=6)
    man['items']['glowcap_elixir'] = 'items/glowcap_elixir.webp'
    stages = {}
    for st in ('sprout', 'growing', 'ripe'):
        recolour(Image.open(os.path.join(ART, 'home', f'crop_moonshroom_{st}.webp'))).save(os.path.join(ART, 'home', f'crop_glowcap_{st}.webp'), quality=90, method=6)
        stages[st] = f'home/crop_glowcap_{st}.webp'
    man['home']['crops']['files']['glowcap'] = stages
    open(man_p, 'w').write(json.dumps(man, indent=1))
    print('ok')


if __name__ == '__main__':
    main()

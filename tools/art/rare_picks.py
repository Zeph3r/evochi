"""The lava galleries' picks: the Iron Pick's art (the shop icon and each stage's worn sheet) with its head
re-made: a Lumen Pick's of glowing mint glass, an Obsidian Pick's of black lava-glass with a violet sheen.
The handle stays as it was.

    python3 tools/art/rare_picks.py     # writes flutter/assets/art/items/gear_{lumen,obsidian}_pick.webp and
                                        # flutter/assets/art/wilds/gear_s0N_{lumen,obsidian}_pick.webp,
                                        # and adds them to manifest.json and wilds_walk.json
"""
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'flutter', 'assets', 'art')

HEADS = {
    # dark, light, highlight, glow (rgba or None)
    'lumen': ((0.16, 0.45, 0.48), (0.80, 1.00, 0.95), (1.0, 1.0, 1.0), (0.62, 0.95, 0.85, 0.55)),
    'obsidian': ((0.05, 0.03, 0.09), (0.42, 0.34, 0.62), (0.93, 0.88, 1.0), None),
}


def recolour(im, kind, glow=False):
    a = np.asarray(im.convert('RGBA'), np.float32) / 255
    rgb, al = a[..., :3], a[..., 3]
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = (mx - mn) / (mx + 1e-6)
    head = (al > 0.05) & (sat < 0.2) & (mx > 0.22)
    head = ndimage.binary_opening(head, iterations=1)
    dark, light, hi, gl = HEADS[kind]
    v = np.clip((mx - 0.25) / 0.7, 0, 1)
    if kind == 'obsidian':
        v = v ** 1.5
    col = np.array(dark) + (np.array(light) - np.array(dark)) * v[..., None]
    shine = np.clip((mx - 0.86) / 0.12, 0, 1)[..., None]
    col = col + (np.array(hi) - col) * shine
    out = a.copy()
    out[..., :3] = np.where(head[..., None], col, rgb)
    if glow and gl is not None:
        m = ndimage.gaussian_filter(head.astype(np.float32), 4) * 1.6
        g = np.clip(m, 0, 1) * gl[3]
        under = (1 - out[..., 3]) * g
        out[..., :3] = (out[..., :3] * out[..., 3][..., None] + np.array(gl[:3]) * under[..., None]) / np.maximum(out[..., 3] + under, 1e-6)[..., None]
        out[..., 3] = out[..., 3] + under
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), 'RGBA')


def main():
    man_p = os.path.join(ART, 'manifest.json')
    man = json.load(open(man_p))
    walk_p = os.path.join(ART, 'wilds', 'wilds_walk.json')
    walk = json.load(open(walk_p))
    src = Image.open(os.path.join(ART, 'items', 'gear_iron_pick.webp'))
    for kind in HEADS:
        recolour(src, kind, glow=True).save(os.path.join(ART, 'items', f'gear_{kind}_pick.webp'), quality=92, method=6)
        man['items'][f'gear_{kind}_pick'] = f'items/gear_{kind}_pick.webp'
        for key, w in walk['walkers'].items():
            iron = w.get('wear', {}).get('iron_pick')
            if not iron:
                continue
            sheet = Image.open(os.path.join(ART, 'wilds', iron['file']))
            name = iron['file'].replace('iron_pick', f'{kind}_pick')
            recolour(sheet, kind).save(os.path.join(ART, 'wilds', name), quality=92, method=6)
            w['wear'][f'{kind}_pick'] = dict(iron, file=name)
    open(man_p, 'w').write(json.dumps(man, indent=1))
    open(walk_p, 'w').write(json.dumps(walk, indent=1))
    print('ok')


if __name__ == '__main__':
    main()

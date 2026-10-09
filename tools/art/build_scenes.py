"""Render layered habitat scenes + decoration slot sprites.

python3 build_scenes.py OUT_DIR [scene ...] [--scale 0.5]
"""
import json
import os
import sys
import time

import numpy as np
from PIL import Image

from voxel import project_px, save_rgba, Camera
import scenes as S

SCENES = {
    'meadow': S.scene_meadow, 'market': S.scene_market, 'welcome': S.scene_welcome,
    'forest': S.scene_forest, 'cliffs': S.scene_cliffs,
}


def px_per_unit(sc, fit, p):
    a = project_px(sc.cam, fit, [p])[0]
    b = project_px(sc.cam, fit, [(p[0] + 1, p[1], p[2])])[0]
    return float(np.linalg.norm(b - a))


def build(name, out, scale=1.0, fmt='png'):
    t = time.time()
    fn = SCENES[name]
    if name in ('forest', 'cliffs'):
        sc = fn(int(720 * scale), int(480 * scale))
    else:
        sc = fn(int(1170 * scale), int(2532 * scale))
    fit = S.make_fit(sc)
    layers = [S.sky_image(sc)]
    names = ['sky']
    for L in sc.layers:
        if L.blur:
            L.blur *= scale
        img, _ = S.render_layer(sc, L, fit)
        layers.append(img)
        names.append(L.name)
    comp = S.composite(layers)
    base = f'habitat_{name}'
    os.makedirs(out, exist_ok=True)
    for n, img in zip(names, layers):
        save_rgba(img, os.path.join(out, f'{base}_{n}_day.png'))
    Image.fromarray(comp[..., :3]).save(os.path.join(out, f'{base}_composite_day.png'))
    meta = {'w': sc.w, 'h': sc.h, 'layers': names,
            'pet': project_px(sc.cam, fit, [sc.pet])[0].round(1).tolist(),
            'pet_px_per_unit': round(px_per_unit(sc, fit, sc.pet), 3),
            'slots': {k: {'px': project_px(sc.cam, fit, [v])[0].round(1).tolist(),
                          'px_per_unit': round(px_per_unit(sc, fit, v), 3), 'world': list(v)}
                      for k, v in sc.slots.items()}}
    json.dump(meta, open(os.path.join(out, f'{base}.json'), 'w'), indent=1)
    print(name, 'done in %.1fs' % (time.time() - t), flush=True)
    return sc, fit, meta


if __name__ == '__main__':
    args = sys.argv[1:]
    scale = 1.0
    if '--scale' in args:
        i = args.index('--scale')
        scale = float(args[i + 1])
        args = args[:i] + args[i + 2:]
    out = args[0]
    for n in (args[1:] or list(SCENES)):
        build(n, out, scale)

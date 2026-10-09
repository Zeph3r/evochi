"""Render decoration sprites in the meadow scene's perspective for each anchor slot."""
import json
import os
import sys

import numpy as np

from voxel import Camera, render, save_rgba
from build_items import LIGHT
from items import ITEM_BUILDERS
import scenes as S

PLACEMENTS = {   # item -> (slots, world scale)
    'nest_bed': (['nest'], 0.40),
    'meadow_nest': (['nest'], 0.40),
    'platform': (['nest'], 0.46),
    'sunlit_flower': (['left', 'right', 'back'], 0.22),
    'explorer_lantern': (['left', 'right', 'back'], 0.24),
}


def main(out, scale=1.0):
    sc = S.scene_meadow(int(1170 * scale), int(2532 * scale))
    fit = S.make_fit(sc)
    meta = {}
    os.makedirs(out, exist_ok=True)
    for item, (slots, s) in PLACEMENTS.items():
        M, _ = ITEM_BUILDERS[item]()
        for slot in slots:
            p = np.array(sc.slots[slot], float)
            c = sc.cam
            cam2 = Camera(yaw=c.yaw, pitch=c.pitch, target=tuple((np.array(c.target) - p) / s),
                          persp=c.persp / s, fov=c.fov)
            o = render(M, {}, cam2, fit.w, fit.h, fit=fit, light=LIGHT, ss=3,
                       outline_px=2.2 * scale + 0.8, outline_col='#3B2923', inner_thresh=2.0 / s * 0.5,
                       inner_alpha=0.45, inner_px=0.7)
            a = o.rgba[..., 3]
            ys, xs = np.where(a > 0)
            x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
            crop = o.rgba[y0:y1, x0:x1]
            name = f'decor_{item}_{slot}.png'
            save_rgba(crop, os.path.join(out, name))
            meta[f'{item}@{slot}'] = {'file': name, 'x': int(x0), 'y': int(y0), 'w': int(x1 - x0),
                                      'h': int(y1 - y0)}
            print(name, flush=True)
    json.dump(meta, open(os.path.join(out, 'habitat_meadow_decor.json'), 'w'), indent=1)


if __name__ == '__main__':
    main(sys.argv[1])

"""Pack the onboarding cinematic's rendered plates for the app: the graded plates (cine_blender.py's OUT_DIR) as
WebP into flutter/assets/art/cine/, sized for phones, with cine.json (anchors and trails, rescaled to the packed
size) and the shot list (onboarding_cine.json).

    python3 cine_assets.py PLATE_DIR ../../flutter/assets/art/cine [--max 1600]

Sprites with alpha (eggs, shards, the Elder orbit, the nest's single eggs) keep it (lossless alpha, lossy colour);
the Lumen footprint stays small and lossless.
"""
from __future__ import annotations

import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))

LOSSLESS = {'lumen_print'}
PLATE_MAX = {'map_lit': 1600, 'map_faded': 1600, 'map_hollow': 1600, 'village_dusk': 1400, 'glasshouse_night': 1400,
             'nest': 1200, 'nest_empty': 1200, 'mira': 1200, 'aisle': 1200, 'steps': 1200, 'pip': 1100, 'pip_gold': 1100}


def pack(plate_dir, out_dir, max_default=1200, quality=82):
    os.makedirs(out_dir, exist_ok=True)
    meta_in = json.load(open(os.path.join(plate_dir, 'cine.json')))
    meta_out = {}
    names = sorted(f[:-4] for f in os.listdir(plate_dir) if f.endswith('.png') and not f.endswith('_zvis.png'))
    for n in names:
        im = Image.open(os.path.join(plate_dir, n + '.png'))
        cap = PLATE_MAX.get(n.split('_')[0] if n.startswith('elder') else n, max_default)
        if n.startswith('egg_') or n.startswith('elder_') or n.startswith('nest_egg_'):
            cap = 900
        scale = min(1.0, cap / max(im.width, im.height))
        if scale < 1.0:
            im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
        path = os.path.join(out_dir, n + '.webp')
        if n in LOSSLESS:
            im.save(path, 'WEBP', lossless=True, quality=100)
        elif im.mode == 'RGBA':
            im.save(path, 'WEBP', quality=quality, method=6, exact=False)
        else:
            im.convert('RGB').save(path, 'WEBP', quality=quality, method=6)
        m = meta_in.get(n)
        if m:
            # anchors and lines are in the scene's full-size pixels (whatever the render's scale): packed px = scene px * k
            k = im.width / m['w']
            meta_out[n] = {'w': im.width, 'h': im.height,
                           'anchors': {a: [round(v[0] * k, 1), round(v[1] * k, 1)] for a, v in m.get('anchors', {}).items()},
                           'lines': {a: [[round(p[0] * k, 1), round(p[1] * k, 1)] for p in pts] for a, pts in m.get('lines', {}).items()},
                           'scale': 1.0}
        print('%-24s %5dx%-5d %6.1f KB' % (n, im.width, im.height, os.path.getsize(path) / 1024), flush=True)
    json.dump(meta_out, open(os.path.join(out_dir, 'cine.json'), 'w'), indent=1)
    tl = os.path.join(plate_dir, 'onboarding_cine.json')
    if not os.path.exists(tl):
        sys.path.insert(0, HERE)
        import onboarding_cine
        onboarding_cine.write_timeline(tl)
    json.dump(json.load(open(tl)), open(os.path.join(out_dir, 'onboarding_cine.json'), 'w'), indent=1)
    print('packed', len(names), 'plates ->', out_dir)


if __name__ == '__main__':
    args = sys.argv[1:]
    mx = 1200
    if '--max' in args:
        i = args.index('--max')
        mx = int(args[i + 1])
        del args[i:i + 2]
    pack(args[0], args[1], mx)

"""Grade and pack a few re-rendered cinematic plates without touching the rest (cine_assets.py packs the whole set
and rewrites cine.json): each pack's raw frame and depth from the PC (render_cine_pc.py) are graded as
cine_blender.py does, sized as cine_assets.py does, and their entries merged into cine.json.

    python3 cine_repack.py RAW_DIR PACK_DIR ../../flutter/assets/art/cine egg_coral_0 nest_egg_coral ...
"""
from __future__ import annotations

import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import cine_assets as CA    # noqa: E402
import cine_blender as CB   # noqa: E402
import cine_pack            # noqa: E402


def repack(raw_dir, pack_dir, out_dir, names, quality=82):
    cj = os.path.join(out_dir, 'cine.json')
    meta_out = json.load(open(cj))
    for n in names:
        vs = cine_pack.unpack(os.path.join(pack_dir, n + '.npz'))
        graded = os.path.join(raw_dir, n + '.png')
        CB.finish(vs, os.path.join(raw_dir, n + '_raw.png'), graded, os.path.join(raw_dir, n + '_z.exr'))
        im = Image.open(graded)
        cap = 900 if n.startswith(('egg_', 'nest_egg_', 'elder_')) else CA.PLATE_MAX.get(n, 1200)
        k = min(1.0, cap / max(im.width, im.height))
        if k < 1.0:
            im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
        path = os.path.join(out_dir, n + '.webp')
        if im.mode == 'RGBA':
            im.save(path, 'WEBP', quality=quality, method=6, exact=False)
        else:
            im.convert('RGB').save(path, 'WEBP', quality=quality, method=6)
        m = json.load(open(os.path.join(raw_dir, n + '_meta.json')))
        kk = im.width / m['w']
        meta_out[n] = {'w': im.width, 'h': im.height,
                       'anchors': {a: [round(v[0] * kk, 1), round(v[1] * kk, 1)] for a, v in m.get('anchors', {}).items()},
                       'lines': {a: [[round(p[0] * kk, 1), round(p[1] * kk, 1)] for p in pts] for a, pts in m.get('lines', {}).items()},
                       'scale': 1.0}
        print('%-20s %dx%d %.0f KB' % (n, im.width, im.height, os.path.getsize(path) / 1024), flush=True)
    json.dump(meta_out, open(cj, 'w'), indent=1)


if __name__ == '__main__':
    repack(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:])

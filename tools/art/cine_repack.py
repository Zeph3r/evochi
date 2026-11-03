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
        # the nest's egg layers keep the full render (they're seen big, laid over a plate the phone fills its
        # height with), each cut to its own egg and shadow so six full-size layers aren't held in memory
        nest = n.startswith('nest_egg_')
        cap = max(im.size) if nest else 900 if n.startswith(('egg_', 'elder_')) else CA.PLATE_MAX.get(n, 1200)
        k = min(1.0, cap / max(im.width, im.height))
        if k < 1.0:
            im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
        full = im.size
        crop = None
        if nest and im.mode == 'RGBA':
            bb = im.getchannel('A').point(lambda a: 255 if a > 3 else 0).getbbox()
            if bb:
                crop = [max(0, bb[0] - 6), max(0, bb[1] - 6), min(full[0], bb[2] + 6), min(full[1], bb[3] + 6)]
                im = im.crop(crop)
        path = os.path.join(out_dir, n + '.webp')
        if im.mode == 'RGBA':
            im.save(path, 'WEBP', quality=quality, method=6, exact=False)
        else:
            im.convert('RGB').save(path, 'WEBP', quality=quality, method=6)
        m = json.load(open(os.path.join(raw_dir, n + '_meta.json')))
        kk = full[0] / m['w']
        meta_out[n] = {'w': full[0], 'h': full[1],
                       'anchors': {a: [round(v[0] * kk, 1), round(v[1] * kk, 1)] for a, v in m.get('anchors', {}).items()},
                       'lines': {a: [[round(p[0] * kk, 1), round(p[1] * kk, 1)] for p in pts] for a, pts in m.get('lines', {}).items()},
                       'scale': 1.0}
        if crop:
            meta_out[n]['crop'] = crop   # where the picture sits on the plate (its w x h), plate pixels
        print('%-20s %dx%d %.0f KB' % (n, im.width, im.height, os.path.getsize(path) / 1024), flush=True)
    json.dump(meta_out, open(cj, 'w'), indent=1)


if __name__ == '__main__':
    repack(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:])

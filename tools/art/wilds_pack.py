"""Pack the Lumen Wilds' people into the app the way build_web_assets packs the villagers: each
expression flattened, the layered puppet (shadow, body, head per expression, blink, arm) in the
room-lit and classic looks, and their idle/talk/listen animation, under manifest village.npcs.<name>.

    python3 wilds_pack.py SRC_DIR APP_ART_DIR [name ...]

SRC_DIR holds the render_all output (npc_<name>_*.png and npc_<name>.json, see wilds_npcs.py);
APP_ART_DIR is flutter/assets/art.
"""
from __future__ import annotations

import json
import os
import sys

from PIL import Image

from village_npcs import NPC_ANIM


def pack(src, art, names):
    mp = os.path.join(art, 'manifest.json')
    man = json.load(open(mp))
    vm = man.setdefault('village', {}).setdefault('npcs', {})
    os.makedirs(os.path.join(art, 'village'), exist_ok=True)

    def enc(fn, q=90):
        out_fn = 'village/' + fn.replace('.png', '.webp')
        Image.open(os.path.join(src, fn)).save(os.path.join(art, out_fn), 'WEBP', quality=q, method=6)
        return out_fn

    for name in names:
        m = json.load(open(os.path.join(src, f'npc_{name}.json')))[name]
        e = {k: m[k] for k in ('w', 'h', 'ground', 'face', 'top', 'stage', 'place') if k in m}
        e['expr'] = {ex: enc(f'npc_{name}_{ex}.png') for ex in m['expressions']}
        e['exprClassic'] = {ex: enc(f'npc_{name}_{ex}_c.png') for ex in m['expressions']}
        layers = []
        for L in m.get('layers', []):
            o = {k: L[k] for k in ('part', 'box', 'pivot') if k in L}
            if 'file' in L:
                o['file'] = enc(L['file'])
            for look in ('lit', 'classic'):
                v = L.get(look)
                if isinstance(v, dict):
                    o[look] = {ex: enc(fn) for ex, fn in v.items()}
                elif v:
                    o[look] = enc(v)
            if 'blink' in L:
                o['blink'] = {look: {'file': enc(b['file']), 'box': b['box']} for look, b in L['blink'].items()}
            layers.append(o)
        e['layers'] = layers
        e['anim'] = NPC_ANIM.get(name, {})
        vm[name] = e
        print('packed', name, flush=True)
    json.dump(man, open(mp, 'w'), indent=1)


if __name__ == '__main__':
    pack(sys.argv[1], sys.argv[2], sys.argv[3:] or ['sher'])

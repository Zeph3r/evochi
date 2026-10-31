"""Repack only the game's hero sprite sheets (chars/sNN_<palette>_hero.webp) from the masters in assets/characters,
with every expression in characters.EXPRESSIONS, and update the app's manifest to match. For new faces: render
them (build_characters.py, or just the new expressions), then run this; nothing else in the pack is touched.

    python3 repack_hero.py [ASSETS_DIR] [FLUTTER_ART_DIR]
"""
import json
import os
import sys

from PIL import Image

from build_web_assets import atlas, webp, VARIANTS
from characters import EXPRESSIONS

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main(src, art):
    mpath = os.path.join(art, 'manifest.json')
    man = json.load(open(mpath))
    C = os.path.join(src, 'characters')
    for sid, entry in man['chars'].items():
        w, h = entry['w'], entry['h']
        for v in VARIANTS:
            frames = [Image.open(os.path.join(C, f'evochi_lizard_{sid}_{v}_{e}_left3q_f000.png')).resize((w, h), Image.LANCZOS)
                      for e in EXPRESSIONS]
            A, rects = atlas(frames, 4)
            name = f'chars/{sid}_{v}_hero.webp'
            webp(A, os.path.join(art, name), 88)
            entry['atlas'][v] = {'file': name, 'rects': rects}
        entry['expressions'] = list(EXPRESSIONS)
        print(sid, 'repacked with', len(EXPRESSIONS), 'faces', flush=True)
    with open(mpath, 'w') as f:
        json.dump(man, f, indent=1)


if __name__ == '__main__':
    a = sys.argv[1:]
    main(a[0] if a else os.path.join(ROOT, 'assets'), a[1] if len(a) > 1 else os.path.join(ROOT, 'flutter', 'assets', 'art'))

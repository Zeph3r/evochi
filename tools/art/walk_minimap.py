"""A walkable map's overview for the in-game map (the corner minimap and the full map window): its tiles
stitched back together and shrunk to MAX_W px wide. Run after village_walk_pack.py.

    python3 tools/art/walk_minimap.py village|trail
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'flutter')
MAX_W = 520


def main(key):
    j = json.load(open(os.path.join(ROOT, f'assets/config/{key}_walk.json')))
    t = j['tiles']
    s = MAX_W / j['w']
    out = Image.new('RGB', (MAX_W, round(j['h'] * s)), (134, 181, 102))
    for tl in t['list']:
        im = Image.open(os.path.join(ROOT, t['dir'], f"t_{tl['i']}_{tl['j']}.webp")).convert('RGB')
        cx, cy, cw, ch = tl['core']
        core = im.crop((cx - tl['x'], cy - tl['y'], cx - tl['x'] + cw, cy - tl['y'] + ch))
        x0, y0, x1, y1 = round(cx * s), round(cy * s), round((cx + cw) * s), round((cy + ch) * s)
        out.paste(core.resize((max(1, x1 - x0), max(1, y1 - y0)), Image.LANCZOS), (x0, y0))
    path = os.path.join(ROOT, t['dir'], 'mini.webp')
    out.save(path, quality=82, method=6)
    print(path, out.size, os.path.getsize(path))


if __name__ == '__main__':
    main(sys.argv[1])

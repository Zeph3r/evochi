"""Repack one stage's character sheets in the app from fresh masters (build_characters.py OUT_DIR N, and
--battle N): its hero sheets (repack_hero.py, every stage), its turnarounds and wearable overlays, the thumbs
strip (every stage) and the encounter sheets (every stage), with the manifest updated to match. For when one
stage's model changes (the Elder's mane, 11 Nov 2026) and the rest of the pack should stay as it is.

    python3 repack_elder.py STAGE [ASSETS_DIR] [FLUTTER_ART_DIR]
"""
import json
import os
import sys

from PIL import Image

from accessories import WEARABLES
from build_web_assets import atlas, webp, VARIANTS, VIEWS, build_thumbs, build_battle
import repack_hero

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main(stage, src, art):
    sid = 's%02d' % stage
    repack_hero.main(src, art)
    mpath = os.path.join(art, 'manifest.json')
    man = json.load(open(mpath))
    entry = man['chars'][sid]
    C = os.path.join(src, 'characters')
    w, h = entry['w'], entry['h']
    frames = [Image.open(os.path.join(C, f'item_{k}_{WEARABLES[k][0]}_{sid}_left3q.png')).resize((w, h), Image.LANCZOS) for k in WEARABLES]
    A, rects = atlas(frames, 4)
    name = f'chars/{sid}_overlays.webp'
    webp(A, os.path.join(art, name), 90)
    entry['overlays'] = {'file': name, 'rects': dict(zip(WEARABLES.keys(), rects))}
    for v in VARIANTS:
        frames = [Image.open(os.path.join(C, f'evochi_lizard_{sid}_{v}_default_{view}_f000.png')) for view in VIEWS]
        A, rects = atlas(frames, 5)
        name = f'chars/{sid}_{v}_turn.webp'
        webp(A, os.path.join(art, name), 88)
        entry['turn'][v] = {'file': name, 'rects': dict(zip(VIEWS, rects))}
    part = json.load(open(os.path.join(C, f'manifest_part_{stage}.json')))[sid]
    entry['turnGround'] = {k: v['ground'] for k, v in part['turnaround'].items()}
    sc = entry['scale'] / part['hero']['scale']
    entry['anchors'] = {k: [round(v[0] * sc, 1), round(v[1] * sc, 1)] for k, v in part['hero']['anchors'].items()}
    with open(mpath, 'w') as f:
        json.dump(man, f, indent=1)
    print(sid, 'overlays, turnarounds and anchors repacked', flush=True)
    build_thumbs(src, art)
    build_battle(src, art)


if __name__ == '__main__':
    a = sys.argv[1:]
    main(int(a[0]), a[1] if len(a) > 1 else os.path.join(ROOT, 'assets'), a[2] if len(a) > 2 else os.path.join(ROOT, 'flutter', 'assets', 'art'))

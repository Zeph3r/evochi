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
import glob

from build_web_assets import atlas, webp, VARIANTS, VIEWS, BATTLE_EXPR, build_thumbs
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
    battle(stage, src, art)


def battle(stage, src, art):
    """the stage's encounter view (build_web_assets.build_battle packs every stage's, plus the backdrops,
    creatures, icons and audio, which have not changed)"""
    sid = 's%02d' % stage
    mpath = os.path.join(art, 'manifest.json')
    man = json.load(open(mpath))
    C = os.path.join(src, 'characters')
    cmeta = {}
    for f in sorted(glob.glob(os.path.join(C, 'manifest_battle_*.json'))):
        cmeta.update(json.load(open(f)))
    bm = cmeta[sid]['battle']
    entry = {'w': bm['w'], 'h': bm['h'], 'anchors': bm['anchors'], 'expressions': BATTLE_EXPR, 'atlas': {}}
    for v in VARIANTS:
        frames = [Image.open(os.path.join(C, f'evochi_lizard_{sid}_{v}_{e}_battle_f000.png')) for e in BATTLE_EXPR]
        A, rects = atlas(frames, 4)
        name = f'chars/{sid}_{v}_battle.webp'
        webp(A, os.path.join(art, name), 88)
        entry['atlas'][v] = {'file': name, 'rects': rects}
    frames = [Image.open(os.path.join(C, f'item_{k}_{WEARABLES[k][0]}_{sid}_battle.png')) for k in WEARABLES]
    A, rects = atlas(frames, 4)
    name = f'chars/{sid}_battle_overlays.webp'
    webp(A, os.path.join(art, name), 90)
    entry['overlays'] = {'file': name, 'rects': dict(zip(WEARABLES.keys(), rects))}
    man['chars'][sid]['battle'] = entry
    with open(mpath, 'w') as f:
        json.dump(man, f, indent=1)
    print(sid, 'battle view packed', flush=True)


if __name__ == '__main__':
    a = sys.argv[1:]
    main(int(a[0]), a[1] if len(a) > 1 else os.path.join(ROOT, 'assets'), a[2] if len(a) > 2 else os.path.join(ROOT, 'flutter', 'assets', 'art'))

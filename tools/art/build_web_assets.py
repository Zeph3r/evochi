"""Pack the PNG master asset pack into web-ready WebP atlases + a JSON manifest.

python3 build_web_assets.py ASSETS_DIR OUT_DIR FONTS_DIR
"""
import glob
import json
import os
import shutil
import subprocess
import sys

from PIL import Image

EXPR = ['default', 'blink', 'happy', 'curious', 'surprised', 'determined', 'sad', 'sleepy', 'excited',
        'neutral', 'sick', 'memorial']
VARIANTS = ['amber', 'forest', 'coral', 'ocean', 'amethyst', 'obsidian']
WEARABLES = {'leaf_scarf': 'neck', 'blue_scarf': 'neck', 'tiny_crown': 'head', 'golden_crest_crown': 'head',
             'explorer_hat': 'head', 'butterfly_clip': 'head', 'red_backpack': 'back', 'explorer_pack': 'back'}
VIEWS = ['front', 'left', 'back', 'right', 'top']
HERO_SCALE = 0.75


def webp(img, path, q=86):
    img.save(path, 'WEBP', quality=q, method=6)


def atlas(frames, cols):
    w = max(f.width for f in frames)
    h = max(f.height for f in frames)
    rows = (len(frames) + cols - 1) // cols
    A = Image.new('RGBA', (cols * w, rows * h), (0, 0, 0, 0))
    rects = []
    for i, f in enumerate(frames):
        x, y = (i % cols) * w, (i // cols) * h
        A.paste(f, (x, y))
        rects.append([x, y, f.width, f.height])
    return A, rects


def main(src, out, fonts):
    os.makedirs(out, exist_ok=True)
    for d in ('chars', 'habitats', 'items', 'icons', 'titles', 'audio', 'fonts'):
        os.makedirs(os.path.join(out, d), exist_ok=True)
    man = {'chars': {}, 'habitats': {}, 'items': {}, 'icons': {}, 'titles': {}, 'audio': {}}
    cmeta = {}
    for f in glob.glob(os.path.join(src, 'characters', 'manifest_part_*.json')):
        cmeta.update(json.load(open(f)))
    C = os.path.join(src, 'characters')
    for stage in (1, 2, 3):
        sid = 's%02d' % stage
        hm = cmeta[sid]['hero']
        sc = HERO_SCALE
        entry = {'scale': hm['scale'] * sc, 'w': round(hm['w'] * sc), 'h': round(hm['h'] * sc),
                 'anchors': {k: [round(v[0] * sc, 1), round(v[1] * sc, 1)] for k, v in hm['anchors'].items()},
                 'expressions': EXPR, 'atlas': {}, 'overlays': {}, 'turn': {}}
        for v in VARIANTS:
            frames = []
            for e in EXPR:
                im = Image.open(os.path.join(C, f'evochi_lizard_{sid}_{v}_{e}_left3q_f000.png'))
                frames.append(im.resize((entry['w'], entry['h']), Image.LANCZOS))
            A, rects = atlas(frames, 4)
            name = f'chars/{sid}_{v}_hero.webp'
            webp(A, os.path.join(out, name), 88)
            entry['atlas'][v] = {'file': name, 'rects': rects}
        frames = []
        for k, slot in WEARABLES.items():
            im = Image.open(os.path.join(C, f'item_{k}_{slot}_{sid}_left3q.png'))
            frames.append(im.resize((entry['w'], entry['h']), Image.LANCZOS))
        A, rects = atlas(frames, 4)
        name = f'chars/{sid}_overlays.webp'
        webp(A, os.path.join(out, name), 90)
        entry['overlays'] = {'file': name, 'rects': dict(zip(WEARABLES.keys(), rects))}
        tmeta = cmeta[sid]['turnaround']
        for v in VARIANTS:
            frames = [Image.open(os.path.join(C, f'evochi_lizard_{sid}_{v}_default_{view}_f000.png')) for view in VIEWS]
            A, rects = atlas(frames, 5)
            name = f'chars/{sid}_{v}_turn.webp'
            webp(A, os.path.join(out, name), 88)
            entry['turn'][v] = {'file': name, 'rects': dict(zip(VIEWS, rects))}
        entry['turnGround'] = {k: v['ground'] for k, v in tmeta.items()}
        man['chars'][sid] = entry
        print(sid, 'packed', flush=True)

    H = os.path.join(src, 'habitats')
    hs = 2 / 3
    for name in ('meadow', 'market', 'welcome'):
        meta = json.load(open(os.path.join(H, f'habitat_{name}.json')))
        e = {'w': round(meta['w'] * hs), 'h': round(meta['h'] * hs), 'layers': {}, 'pet': [round(c * hs, 1) for c in meta['pet']],
             'petPxPerUnit': meta['pet_px_per_unit'] * hs,
             'slots': {k: {'px': [round(c * hs, 1) for c in v['px']], 'pxPerUnit': v['px_per_unit'] * hs} for k, v in meta['slots'].items()}}
        for layer in meta['layers']:
            im = Image.open(os.path.join(H, f'habitat_{name}_{layer}_day.png'))
            im = im.resize((e['w'], e['h']), Image.LANCZOS)
            fn = f'habitats/{name}_{layer}.webp'
            if layer == 'sky':
                im.convert('RGB').save(os.path.join(out, fn), 'WEBP', quality=80, method=6)
            else:
                webp(im, os.path.join(out, fn), 82)
            e['layers'][layer] = fn
        man['habitats'][name] = e
    # decorations (meadow perspective)
    dmeta = json.load(open(os.path.join(H, 'habitat_meadow_decor.json')))
    man['habitats']['meadow']['decor'] = {}
    for key, d in dmeta.items():
        im = Image.open(os.path.join(H, d['file']))
        im = im.resize((max(1, round(d['w'] * hs)), max(1, round(d['h'] * hs))), Image.LANCZOS)
        fn = 'habitats/' + d['file'].replace('.png', '.webp')
        webp(im, os.path.join(out, fn), 88)
        man['habitats']['meadow']['decor'][key] = {'file': fn, 'x': round(d['x'] * hs, 1), 'y': round(d['y'] * hs, 1),
                                                   'w': im.width, 'h': im.height}
    # habitat thumbnails (landscape cards)
    man['habitats']['thumbs'] = {}
    for name, crop in (('meadow', (0, 300, 1170, 1080)), ('forest', None), ('cliffs', None)):
        im = Image.open(os.path.join(H, f'habitat_{name}_composite_day.png'))
        if crop:
            im = im.crop(crop)
        im = im.resize((360, 240), Image.LANCZOS)
        fn = f'habitats/thumb_{name}.webp'
        im.convert('RGB').save(os.path.join(out, fn), 'WEBP', quality=84, method=6)
        man['habitats']['thumbs'][name] = fn

    for f in sorted(glob.glob(os.path.join(src, 'items', '*.png'))):
        k = os.path.basename(f)[5:-9]
        im = Image.open(f).resize((168, 168), Image.LANCZOS)
        fn = f'items/{k}.webp'
        webp(im, os.path.join(out, fn), 90)
        man['items'][k] = fn
    for f in sorted(glob.glob(os.path.join(src, 'ui_icons', '*.png'))):
        k = os.path.basename(f)[5:-4]
        im = Image.open(f).resize((112, 112), Image.LANCZOS)
        fn = f'icons/{k}.webp'
        webp(im, os.path.join(out, fn), 90)
        man['icons'][k] = fn
    for f in sorted(glob.glob(os.path.join(src, 'ui_titles', '*.png'))):
        k = os.path.basename(f)[:-4]
        im = Image.open(f)
        im = im.resize((round(im.width * 0.55), round(im.height * 0.55)), Image.LANCZOS)
        fn = f'titles/{k}.webp'
        webp(im, os.path.join(out, fn), 92)
        man['titles'][k] = {'file': fn, 'w': im.width, 'h': im.height}
    for f in sorted(glob.glob(os.path.join(src, 'audio', '*.wav'))):
        k = os.path.basename(f)[4:-4]
        fn = f'audio/{k}.mp3'
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', f, '-ac', '1', '-b:a', '80k', os.path.join(out, fn)], check=True)
        man['audio'][k] = fn
    for f in ('nunito-latin-700-normal.woff2', 'nunito-latin-800-normal.woff2', 'nunito-latin-900-normal.woff2'):
        shutil.copy(os.path.join(fonts, 'nunito', 'files', f), os.path.join(out, 'fonts', f))
    for f in ('lato-latin-400-normal.woff2', 'lato-latin-700-normal.woff2', 'lato-latin-900-normal.woff2'):
        shutil.copy(os.path.join(fonts, 'lato', 'files', f), os.path.join(out, 'fonts', f))
    json.dump(man, open(os.path.join(out, 'manifest.json'), 'w'), indent=1)
    build_thumbs(src, out)
    print('manifest written', flush=True)




def build_thumbs(src, out):
    """Small atlas of every stage x palette x (default, determined) at 150px for strips and swatches."""
    C = os.path.join(src, 'characters')
    frames, keys = [], []
    for stage in (1, 2, 3):
        sid = 's%02d' % stage
        for v in VARIANTS:
            for e in ('default', 'determined'):
                im = Image.open(os.path.join(C, f'evochi_lizard_{sid}_{v}_{e}_left3q_f000.png'))
                bb = im.getbbox()
                im = im.crop(bb)
                h = 150
                im = im.resize((round(im.width * h / im.height), h), Image.LANCZOS)
                frames.append(im)
                keys.append(f'{stage}|{v}|{e}')
    # pack rows by stage
    W = 1600
    x = y = rowh = 0
    rects = {}
    placed = []
    for k, f in zip(keys, frames):
        if x + f.width > W:
            x = 0
            y += rowh + 2
            rowh = 0
        placed.append((f, x, y))
        rects[k] = [x, y, f.width, f.height]
        x += f.width + 2
        rowh = max(rowh, f.height)
    A = Image.new('RGBA', (W, y + rowh), (0, 0, 0, 0))
    for f, px, py in placed:
        A.paste(f, (px, py))
    webp(A, os.path.join(out, 'chars/thumbs.webp'), 88)
    mp = os.path.join(out, 'manifest.json')
    man = json.load(open(mp))
    man['thumbs'] = {'file': 'chars/thumbs.webp', 'rects': rects}
    json.dump(man, open(mp, 'w'), indent=1)
    print('thumbs', A.size, os.path.getsize(os.path.join(out, 'chars/thumbs.webp')))


if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[-1] == '--thumbs-only':
        build_thumbs(sys.argv[1], sys.argv[2])
    else:
        main(*sys.argv[1:4])

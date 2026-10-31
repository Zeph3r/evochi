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
        'neutral', 'sick', 'memorial', 'afraid', 'frustrated', 'affectionate']  # characters.EXPRESSIONS
VARIANTS = ['amber', 'forest', 'coral', 'ocean', 'amethyst', 'obsidian']
WEARABLES = {'leaf_scarf': 'neck', 'blue_scarf': 'neck', 'tiny_crown': 'head', 'golden_crest_crown': 'head',
             'explorer_hat': 'head', 'butterfly_clip': 'head', 'red_backpack': 'back', 'explorer_pack': 'back',
             'reward_windtrail_mantle': 'back'}
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
    build_village(src, out)
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


def build_village(src, out):
    """Village Tales, Chapter 1: villagers, scenes, quest-item icons, the Windtrail Mantle overlays and
    the story decor. Updates the existing manifest in place, so it can run on its own (--village-only)
    without re-encoding the rest of the pack."""
    mp = os.path.join(out, 'manifest.json')
    man = json.load(open(mp))
    V = os.path.join(src, 'village')
    os.makedirs(os.path.join(out, 'village'), exist_ok=True)
    vm = {'npcs': {}, 'square': {}, 'places': {}, 'waystone': {}}
    # villagers: flattened sprites per expression (cards, tabs, cameo) and, for the rooms, the layered
    # puppet (shadow, body, head per expression, blink, arm) in two looks: room-lit and classic
    from village_npcs import NPC_ANIM
    nmeta = json.load(open(os.path.join(V, 'npc.json')))

    def enc(fn, q=90):
        out_fn = 'village/' + fn.replace('.png', '.webp')
        webp(Image.open(os.path.join(V, fn)), os.path.join(out, out_fn), q)
        return out_fn
    for name, m in nmeta.items():
        e = {k: m[k] for k in ('w', 'h', 'ground', 'face', 'top', 'stage', 'place') if k in m}
        e['expr'] = {ex: enc(f'npc_{name}_{ex}.png') for ex in m['expressions']}
        if os.path.exists(os.path.join(V, f'npc_{name}_{m["expressions"][0]}_c.png')):
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
        if layers:
            e['layers'] = layers
            e['anim'] = NPC_ANIM.get(name, {})
        vm['npcs'][name] = e
    smeta = json.load(open(os.path.join(V, 'scenes.json')))
    k = 2 / 3

    def scene(name, q=84):
        im = Image.open(os.path.join(V, f'{name}.png')).convert('RGB')
        im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
        fn = f'village/{name}.webp'
        im.save(os.path.join(out, fn), 'WEBP', quality=q, method=6)
        return fn, im.width, im.height

    for st in ('day_dim', 'lamp_lit', 'waystone_restored'):
        fn, w, h = scene(f'square_{st}')
        vm['square'][st] = fn
        vm['square']['w'], vm['square']['h'] = w, h
    vm['square']['anchors'] = {a: [round(v[0] * k, 1), round(v[1] * k, 1)] for a, v in smeta['square_day_dim']['anchors'].items()}
    for place in ('glasshouse', 'workshop', 'lodge'):
        fn, w, h = scene(place)
        vm['places'][place] = {'file': fn, 'w': w, 'h': h}
    for st in ('dormant', 'restored'):
        fn, w, h = scene(f'waystone_{st}')
        vm['waystone'][st] = fn
        vm['waystone']['w'], vm['waystone']['h'] = w, h
    man['village'] = vm
    # quest-item and story-reward icons (same treatment as the shop items)
    for f in sorted(glob.glob(os.path.join(src, 'items', 'item_q_*_icon.png')) + glob.glob(os.path.join(src, 'items', 'item_reward_*_icon.png'))):
        key = os.path.basename(f)[5:-9]
        im = Image.open(f).resize((168, 168), Image.LANCZOS)
        fn = f'items/{key}.webp'
        webp(im, os.path.join(out, fn), 90)
        man['items'][key] = fn
    # overlay atlases now include the mantle (same frames, one more cell)
    C = os.path.join(src, 'characters')
    for stage in (1, 2, 3):
        sid = 's%02d' % stage
        entry = man['chars'][sid]
        frames = []
        for key, slot in WEARABLES.items():
            im = Image.open(os.path.join(C, f'item_{key}_{slot}_{sid}_left3q.png'))
            frames.append(im.resize((entry['w'], entry['h']), Image.LANCZOS))
        A, rects = atlas(frames, 4)
        name = f'chars/{sid}_overlays.webp'
        webp(A, os.path.join(out, name), 90)
        entry['overlays'] = {'file': name, 'rects': dict(zip(WEARABLES.keys(), rects))}
    # story decor in the meadow's perspective
    H = os.path.join(src, 'habitats')
    hs = 2 / 3
    dmeta = json.load(open(os.path.join(H, 'habitat_meadow_decor.json')))
    for key, d in dmeta.items():
        if not key.startswith('reward_'):
            continue
        im = Image.open(os.path.join(H, d['file']))
        im = im.resize((max(1, round(d['w'] * hs)), max(1, round(d['h'] * hs))), Image.LANCZOS)
        fn = 'habitats/' + d['file'].replace('.png', '.webp')
        webp(im, os.path.join(out, fn), 88)
        man['habitats']['meadow']['decor'][key] = {'file': fn, 'x': round(d['x'] * hs, 1), 'y': round(d['y'] * hs, 1),
                                                   'w': im.width, 'h': im.height}
    json.dump(man, open(mp, 'w'), indent=1)
    print('village packed', flush=True)


HOME_ITEMS = ['sunberry', 'meadow_carrot', 'golden_wheat', 'glowleaf', 'moonshroom', 'seed_sunberry', 'seed_meadow_carrot',
              'seed_golden_wheat', 'seed_glowleaf', 'seed_moonshroom', 'sunberry_tart', 'carrot_stew', 'golden_bun',
              'moonshroom_pie', 'glowleaf_tonic', 'meadow_tea', 'sprout_tonic', 'moonlight_draught', 'q_sturdy_timber']
HOME_ICONS = ['skill_farming', 'skill_cooking', 'skill_alchemy', 'home_map']


def build_home(src, out):
    """Home: the Home Map (cottage ruined / restored), the Garden with its bed anchors, the Kitchen and
    Apothecary rooms, the crop sprites (one shared canvas) and the new item and UI icons. Updates the
    manifest in place (--home-only)."""
    mp = os.path.join(out, 'manifest.json')
    man = json.load(open(mp))
    Hs = os.path.join(src, 'home')
    os.makedirs(os.path.join(out, 'home'), exist_ok=True)
    smeta = json.load(open(os.path.join(Hs, 'scenes.json')))
    k = 2 / 3

    def scene(name, q=84):
        im = Image.open(os.path.join(Hs, f'{name}.png')).convert('RGB')
        im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
        fn = f'home/{name}.webp'
        im.save(os.path.join(out, fn), 'WEBP', quality=q, method=6)
        return fn, im.width, im.height

    def anchors(name):
        return {a: [round(v[0] * k, 1), round(v[1] * k, 1)] for a, v in smeta[name]['anchors'].items()}

    hm = {'map': {}, 'garden': {}, 'rooms': {}, 'crops': {}, 'cottage': {}}
    for st in ('ruined', 'restored'):
        fn, w, h = scene(f'home_map_{st}')
        hm['map'][st] = fn
        hm['map']['w'], hm['map']['h'] = w, h
    hm['map']['anchors'] = anchors('home_map_ruined')
    fn, w, h = scene('garden')
    hm['garden'] = {'file': fn, 'w': w, 'h': h, 'anchors': anchors('garden')}
    for room in ('kitchen', 'apothecary'):
        fn, w, h = scene(room)
        hm['rooms'][room] = {'file': fn, 'w': w, 'h': h}
    if all(os.path.exists(os.path.join(Hs, f'cottage_{st}.png')) for st in ('ruined', 'restored')):
        for st in ('ruined', 'restored'):
            fn, w, h = scene(f'cottage_{st}')
            hm['cottage'][st] = fn
            hm['cottage']['w'], hm['cottage']['h'] = w, h
    cm = json.load(open(os.path.join(Hs, 'crops.json')))
    cs = 0.6
    files = {}
    for crop in cm['crops']:
        files[crop] = {}
        for stage in cm['stages']:
            im = Image.open(os.path.join(Hs, f'crop_{crop}_{stage}.png'))
            im = im.resize((round(im.width * cs), round(im.height * cs)), Image.LANCZOS)
            fn = f'home/crop_{crop}_{stage}.webp'
            webp(im, os.path.join(out, fn), 90)
            files[crop][stage] = fn
    hm['crops'] = {'w': round(cm['w'] * cs), 'h': round(cm['h'] * cs), 'ground': [round(v * cs, 1) for v in cm['ground']],
                   'bedW': round(cm['bedW'] * cs, 1), 'files': files}
    man['home'] = hm
    for key in HOME_ITEMS:
        im = Image.open(os.path.join(src, 'items', f'item_{key}_icon.png')).resize((168, 168), Image.LANCZOS)
        fn = f'items/{key}.webp'
        webp(im, os.path.join(out, fn), 90)
        man['items'][key] = fn
    for key in HOME_ICONS:
        im = Image.open(os.path.join(src, 'ui_icons', f'icon_{key}.png')).resize((112, 112), Image.LANCZOS)
        fn = f'icons/{key}.webp'
        webp(im, os.path.join(out, fn), 90)
        man['icons'][key] = fn
    json.dump(man, open(mp, 'w'), indent=1)
    print('home packed', flush=True)


TRAIL_ITEMS = ['lumen_shard', 'lantern_tonic', 'ancient_relic', 'q_mossy_clue', 'q_lumen_trace', 'q_old_trail_map']
TRAIL_ICONS = ['discover', 'encounter', 'hollow', 'calm', 'energy', 'trail', 'aff_nature', 'aff_ember', 'aff_water', 'aff_stone',
               'aff_celestial']


def build_trails(src, out):
    """Lumen Trails: the encounter places (Mossy Ruins, its Hollow twin, the Sentinel's gate) with their
    anchors, the creature sprites (one shared fit per creature) and the new item / UI icons."""
    mp = os.path.join(out, 'manifest.json')
    man = json.load(open(mp))
    Ts = os.path.join(src, 'trails')
    os.makedirs(os.path.join(out, 'trails'), exist_ok=True)
    smeta = json.load(open(os.path.join(Ts, 'scenes.json')))
    k = 2 / 3
    tm = {'scenes': {}, 'creatures': {}}
    for name in ('mossy_ruins', 'mossy_ruins_hollow', 'sentinel_gate'):
        im = Image.open(os.path.join(Ts, f'{name}.png')).convert('RGB')
        im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
        fn = f'trails/{name}.webp'
        im.save(os.path.join(out, fn), 'WEBP', quality=84, method=6)
        tm['scenes'][name] = {'file': fn, 'w': im.width, 'h': im.height,
                              'anchors': {a: [round(v[0] * k, 1), round(v[1] * k, 1)] for a, v in smeta[name]['anchors'].items()}}
    cm = json.load(open(os.path.join(Ts, 'creatures.json')))
    cs = 0.75
    for cid, c in cm.items():
        files = {}
        for st in c['states']:
            im = Image.open(os.path.join(Ts, f'creature_{cid}_{st}.png'))
            im = im.resize((round(im.width * cs), round(im.height * cs)), Image.LANCZOS)
            fn = f'trails/creature_{cid}_{st}.webp'
            webp(im, os.path.join(out, fn), 90)
            files[st] = fn
        tm['creatures'][cid] = {'w': round(c['w'] * cs), 'h': round(c['h'] * cs), 'states': files,
                                'anchors': {a: [round(v[0] * cs, 1), round(v[1] * cs, 1)] for a, v in c['anchors'].items()}}
        # a small portrait icon (the happiest state) for cards, the EvoDex and the Home Map
        last = c['states'][-1]
        im = Image.open(os.path.join(Ts, f'creature_{cid}_{last}.png'))
        bb = im.getbbox()
        im = im.crop(bb)
        side = max(im.width, im.height)
        sq = Image.new('RGBA', (side, side), (0, 0, 0, 0))
        sq.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
        fn = f'icons/creature_{cid}.webp'
        webp(sq.resize((112, 112), Image.LANCZOS), os.path.join(out, fn), 90)
        man['icons'][f'creature_{cid}'] = fn
    man['trails'] = tm
    for key in TRAIL_ITEMS:
        im = Image.open(os.path.join(src, 'items', f'item_{key}_icon.png')).resize((168, 168), Image.LANCZOS)
        fn = f'items/{key}.webp'
        webp(im, os.path.join(out, fn), 90)
        man['items'][key] = fn
    for key in TRAIL_ICONS:
        im = Image.open(os.path.join(src, 'ui_icons', f'icon_{key}.png')).resize((112, 112), Image.LANCZOS)
        fn = f'icons/{key}.webp'
        webp(im, os.path.join(out, fn), 90)
        man['icons'][key] = fn
    # the Guild badge icon doubles as the rank mark
    im = Image.open(os.path.join(src, 'items', 'item_trail_badge_icon.png')).resize((112, 112), Image.LANCZOS)
    webp(im, os.path.join(out, 'icons/trail_badge.webp'), 90)
    man['icons']['trail_badge'] = 'icons/trail_badge.webp'
    json.dump(man, open(mp, 'w'), indent=1)
    print('trails packed', flush=True)


BATTLE_EXPR = ['default', 'blink', 'happy', 'determined', 'surprised', 'sleepy', 'excited']
BATTLE_BASES = ('mossy_ruins', 'mossy_ruins_hollow', 'sentinel_gate')
BATTLE_ICONS = ('sun', 'purify', 'nudge', 'moon', 'swirl')


def soft_layer(im, radius):
    """Gaussian blur an RGBA layer with premultiplied alpha (so edges don't pick up a dark fringe)."""
    import numpy as np
    from PIL import ImageFilter
    a = np.asarray(im.convert('RGBA')).astype(np.float32) / 255
    pm = np.concatenate([a[..., :3] * a[..., 3:4], a[..., 3:4]], -1)
    ch = [np.asarray(Image.fromarray((pm[..., i] * 255).round().astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255
          for i in range(4)]
    al = ch[3]
    rgb = np.stack(ch[:3], -1) / np.maximum(al[..., None], 1e-4)
    return Image.fromarray(np.concatenate([np.clip(rgb, 0, 1) * 255, al[..., None] * 255], -1).round().astype(np.uint8), 'RGBA')


def build_battle(src, out):
    """Encounters (the battle shot): your Evochi from behind (every stage x palette x BATTLE_EXPR + wearable
    overlays), the low-camera backdrops with their soft foreground layers, the creatures turned toward you,
    the new button icons and the encounter music / cues."""
    mp = os.path.join(out, 'manifest.json')
    man = json.load(open(mp))
    C = os.path.join(src, 'characters')
    cmeta = {}
    for f in glob.glob(os.path.join(C, 'manifest_battle_*.json')):
        cmeta.update(json.load(open(f)))
    for stage in (1, 2, 3):
        sid = 's%02d' % stage
        bm = cmeta[sid]['battle']
        entry = {'w': bm['w'], 'h': bm['h'], 'anchors': bm['anchors'], 'expressions': BATTLE_EXPR, 'atlas': {}}
        for v in VARIANTS:
            frames = [Image.open(os.path.join(C, f'evochi_lizard_{sid}_{v}_{e}_battle_f000.png')) for e in BATTLE_EXPR]
            A, rects = atlas(frames, 4)
            name = f'chars/{sid}_{v}_battle.webp'
            webp(A, os.path.join(out, name), 88)
            entry['atlas'][v] = {'file': name, 'rects': rects}
        frames = [Image.open(os.path.join(C, f'item_{k}_{slot}_{sid}_battle.png')) for k, slot in WEARABLES.items()]
        A, rects = atlas(frames, 4)
        name = f'chars/{sid}_battle_overlays.webp'
        webp(A, os.path.join(out, name), 90)
        entry['overlays'] = {'file': name, 'rects': dict(zip(WEARABLES.keys(), rects))}
        man['chars'][sid]['battle'] = entry
        print(sid, 'battle view packed', flush=True)
    Ts = os.path.join(src, 'trails')
    smeta = json.load(open(os.path.join(Ts, 'scenes.json')))
    k = 0.75
    tm = man['trails']
    tm['battle'] = {}
    for base in BATTLE_BASES:
        n = base + '_battle'
        im = Image.open(os.path.join(Ts, f'{n}.png')).convert('RGB')
        im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
        fn = f'trails/{n}.webp'
        im.save(os.path.join(out, fn), 'WEBP', quality=84, method=6)
        fg = Image.open(os.path.join(Ts, f'{n}_fg.png')).convert('RGBA')
        fg = fg.resize(im.size, Image.LANCZOS)
        fg = soft_layer(fg, im.width * 0.009)
        ffn = f'trails/{n}_fg.webp'
        webp(fg, os.path.join(out, ffn), 82)
        tm['battle'][base] = {'file': fn, 'fg': ffn, 'w': im.width, 'h': im.height,
                              'anchors': {a: [round(v[0] * k, 1), round(v[1] * k, 1)] for a, v in smeta[n]['anchors'].items()}}
    cb = json.load(open(os.path.join(Ts, 'creatures_battle.json')))
    tm['battleCreatures'] = {}
    for cid, c in cb.items():
        files = {}
        for st in c['states']:
            im = Image.open(os.path.join(Ts, f'creature_{cid}_{st}_battle.png'))
            fn = f'trails/creature_{cid}_{st}_battle.webp'
            webp(im, os.path.join(out, fn), 90)
            files[st] = fn
        tm['battleCreatures'][cid] = {'w': c['w'], 'h': c['h'], 'states': files, 'anchors': c['anchors']}
    for key in BATTLE_ICONS:
        im = Image.open(os.path.join(src, 'ui_icons', f'icon_{key}.png')).resize((112, 112), Image.LANCZOS)
        fn = f'icons/{key}.webp'
        webp(im, os.path.join(out, fn), 90)
        man['icons'][key] = fn
    for f in sorted(glob.glob(os.path.join(src, 'audio', 'sfx_enc_*.wav'))):
        key = os.path.basename(f)[4:-4]
        fn = f'audio/{key}.mp3'
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', f, '-ac', '1', '-b:a', '80k', os.path.join(out, fn)], check=True)
        man['audio'][key] = fn
    json.dump(man, open(mp, 'w'), indent=1)
    print('battle packed', flush=True)


if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[-1] == '--battle-only':
        build_battle(sys.argv[1], sys.argv[2])
    elif len(sys.argv) > 2 and sys.argv[-1] == '--trails-only':
        build_trails(sys.argv[1], sys.argv[2])
    elif len(sys.argv) > 2 and sys.argv[-1] == '--home-only':
        build_home(sys.argv[1], sys.argv[2])
    elif len(sys.argv) > 2 and sys.argv[-1] == '--thumbs-only':
        build_thumbs(sys.argv[1], sys.argv[2])
    elif len(sys.argv) > 2 and sys.argv[-1] == '--village-only':
        build_village(sys.argv[1], sys.argv[2])
    else:
        main(*sys.argv[1:4])

"""Contact sheets of the game's animations, frame by frame, for review: the Wilds walk and run cycles (three
of the eight directions), the Pounce leap, the Nest's acting clips (the Eggling's: the only stage with them),
the encounter faces, and the Elders' ultimate cut-ins (sampled). Read from the packed assets, so what is here
is what the game draws.

    python3 review_sheets.py OUT_DIR [--palette=amber]
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ART = os.path.join(ROOT, 'flutter', 'assets', 'art')
BG = (250, 244, 232, 255)
INK = (60, 40, 30, 255)


def font(size):
    try:
        return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', size)
    except OSError:
        return ImageFont.load_default()


def grid(rows, title, cell, labels_left=(), labels_top=(), gap=4, scale=1.0):
    """rows: lists of RGBA tiles (any size, drawn at [cell] after [scale])"""
    cw, ch = int(cell[0] * scale), int(cell[1] * scale)
    left = 120 if labels_left else 0
    top = 34 + (22 if labels_top else 0)
    ncol = max(len(r) for r in rows)
    W = left + ncol * (cw + gap)
    H = top + len(rows) * (ch + gap)
    img = Image.new('RGBA', (W, H), BG)
    d = ImageDraw.Draw(img)
    d.text((8, 8), title, fill=INK, font=font(16))
    for i, lab in enumerate(labels_top):
        d.text((left + i * (cw + gap) + 4, 36), lab, fill=INK, font=font(12))
    for r, row in enumerate(rows):
        y = top + r * (ch + gap)
        if labels_left:
            d.text((8, y + ch // 2 - 7), labels_left[r], fill=INK, font=font(12))
        for c, tile in enumerate(row):
            t = tile.resize((cw, ch), Image.LANCZOS) if scale != 1.0 else tile
            img.alpha_composite(t, (left + c * (cw + gap), y))
    return img


def frames_of(path):
    im = Image.open(path)
    out = []
    try:
        i = 0
        while True:
            im.seek(i)
            out.append(im.convert('RGBA'))
            i += 1
    except EOFError:
        pass
    return out


def walk_sheets(out, palette):
    j = json.load(open(os.path.join(ART, 'wilds', 'wilds_walk.json')))
    dirs = j['dirs']
    for sid in ('s01', 's02', 's03'):
        w = j['walkers'][sid]
        fw, fh, n = w['frameW'], w['frameH'], w['frames']
        rows, labels = [], []
        for gait in ('walk', 'run'):
            sheet = Image.open(os.path.join(ART, 'wilds', w['gaits'][gait]['sheets'][palette])).convert('RGBA')
            for d in ('S', 'SE', 'E'):
                r = dirs.index(d)
                rows.append([sheet.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh)) for c in range(n + 1)])
                labels.append(f'{gait} {d}')
        img = grid(rows, f'{sid} {palette}: walk and run cycles (idle, then the {n} frames; {j["fps"]} fps; S, SE, E of the 8 directions)',
                   (fw, fh), labels, ['idle'] + [str(i + 1) for i in range(n)], scale=0.5)
        img.save(os.path.join(out, f'review_walk_run_{sid}.png'))
        print('walk/run', sid, img.size, flush=True)


def leap_sheets(out, palette):
    j = json.load(open(os.path.join(ART, 'wilds', 'wilds_jump.json')))
    cols = j['cols']
    for sid in ('s01', 's02', 's03'):
        e = j[sid]
        fw, fh, n = e['w'], e['h'], e['n']
        sheet = Image.open(os.path.join(ART, 'wilds', e['sheets'][palette])).convert('RGBA')
        tiles = [sheet.crop(((i % cols) * fw, (i // cols) * fh, (i % cols + 1) * fw, (i // cols + 1) * fh)) for i in range(n)]
        rows = [tiles[i:i + 9] for i in range(0, n, 9)]
        img = grid(rows, f'{sid} {palette}: Pounce, the leap ({n} frames at {j["fps"]} fps: aim, the beam from {j["beam"]["on"]:.2f}s, the hit at {j["beam"]["hit"]:.2f}s, landing {j["land"]:.2f}s)',
                   (fw, fh), scale=0.4)
        img.save(os.path.join(out, f'review_pounce_{sid}.png'))
        print('pounce', sid, img.size, flush=True)


def acting_sheets(out, palette):
    j = json.load(open(os.path.join(ART, 'acting', 'acting.json')))['s01']
    rows, labels = [], []
    for name, c in j['clips'].items():
        fr = frames_of(os.path.join(ART, 'acting', c['body'][palette]))
        n = len(fr)
        step = max(1, (n + 12) // 13)
        rows.append(fr[::step])
        labels.append(f'{name} ({n}f)')
    fw, fh = rows[0][0].size
    img = grid(rows, f's01 {palette}: the Nest acting clips ({j["fps"]} fps; every {"frame" if max(len(r) for r in rows) >= 13 else "few frames"} shown)', (fw, fh), labels, scale=0.3)
    img.save(os.path.join(out, 'review_acting_s01.png'))
    print('acting', img.size, flush=True)


def face_sheets(out, palette):
    j = json.load(open(os.path.join(ART, 'wilds', 'wilds_cine.json')))
    rows, labels = [], []
    for sid in ('s01', 's02', 's03'):
        e = j[sid]
        sheet = Image.open(os.path.join(ART, 'wilds', f'cine_{sid}_{palette}.webp')).convert('RGBA')
        fw, fh = e['w'], e['h']
        rows.append([sheet.crop((i * fw, 0, (i + 1) * fw, fh)).resize((346, 376), Image.LANCZOS) for i in range(len(j['faces']))])
        labels.append(sid)
    img = grid(rows, f'{palette}: the encounter faces (the guardian entrances): ' + ', '.join(j['faces']), (346, 376), labels, j['faces'])
    img.save(os.path.join(out, 'review_encounter_faces.png'))
    print('faces', img.size, flush=True)


def ultimate_sheets(out):
    j = json.load(open(os.path.join(ART, 'wilds', 'ultimates.json')))
    rows, labels = [], []
    for name, a in j['abilities'].items():
        f = a['variants'].get('brave') or next(iter(a['variants'].values()))
        fr = frames_of(os.path.join(ART, 'wilds', f))
        n = len(fr)
        idx = [round(i * (n - 1) / 11) for i in range(12)]
        rows.append([fr[i] for i in idx])
        labels.append(f"{a['name']} ({a['palette']}, {n}f, {a['t1']:.1f}s)")
    img = grid(rows, f'the Elders\' ultimate cut-ins ({j["fps"]} fps; 12 frames sampled across each)', (j['w'], j['h']), labels, scale=0.16)
    img.save(os.path.join(out, 'review_ultimates.png'))
    print('ultimates', img.size, flush=True)


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = dict(a[2:].split('=', 1) for a in sys.argv[1:] if a.startswith('--') and '=' in a)
    out = args[0] if args else 'review_out'
    os.makedirs(out, exist_ok=True)
    pal = opts.get('palette', 'amber')
    walk_sheets(out, pal)
    leap_sheets(out, pal)
    acting_sheets(out, pal)
    face_sheets(out, pal)
    ultimate_sheets(out)

"""The game's finished background art, gathered per place: the walkable maps stitched back together from their
tiles (village/walk/t_<col>_<row>.webp and the like), the Thicket's ground from its tiles, the story and
encounter scenes as shipped, the Sunlit Meadow's layers stacked, and a gallery of everything.

    python3 places_art.py OUT_DIR        -> OUT_DIR/<place>.jpg (full size) and OUT_DIR/backgrounds_gallery.png
"""
from __future__ import annotations

import glob
import os
import re
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ART = os.path.join(HERE, '..', '..', 'flutter', 'assets', 'art')
from turnarounds import font, BG, INKC, SUB   # noqa: E402

WALK = [('village_map', 'Sunlit Village (walkable)', 'village/walk'), ('old_trail', 'The Old Trail (walkable)', 'trail/walk'),
        ('workshop_inside', 'Bram\'s Workshop (inside)', 'workshop/walk'), ('glasshouse_inside', 'Mira\'s Glasshouse (inside)', 'glasshouse/walk'),
        ('lodge_inside', 'The Guild Lodge (inside)', 'lodge/walk'), ('cottage_inside', 'The Cottage (inside)', 'cottage/walk'),
        ('home_grounds', 'The Home grounds (walkable)', 'home/walk')]
FILES = [('square_day', 'The Square', 'village/square_day_dim.webp'), ('square_lamplit', 'The Square, lamplit', 'village/square_lamp_lit.webp'),
         ('square_restored', 'The Square, Waystone restored', 'village/square_waystone_restored.webp'),
         ('waystone_dormant', 'The Waystone, dormant', 'village/waystone_dormant.webp'),
         ('waystone_restored', 'The Waystone, restored', 'village/waystone_restored.webp'),
         ('workshop_story', 'Bram\'s Workshop', 'village/workshop.webp'), ('glasshouse_story', 'Mira\'s Glasshouse', 'village/glasshouse.webp'),
         ('lodge_story', 'The Guild Lodge', 'village/lodge.webp'), ('forge_stage', 'Bram\'s forge (minigame)', 'village/forge_stage.webp'),
         ('home_map_ruined', 'The Home Map, in ruins', 'home/home_map_ruined.webp'), ('home_map_restored', 'The Home Map, restored', 'home/home_map_restored.webp'),
         ('garden', 'The Garden', 'home/garden.webp'), ('kitchen', 'The Kitchen', 'home/kitchen.webp'), ('apothecary', 'The Apothecary', 'home/apothecary.webp'),
         ('cottage_ruined', 'The Cottage, in ruins', 'home/cottage_ruined.webp'), ('cottage_restored', 'The Cottage, restored', 'home/cottage_restored.webp'),
         ('mossy_ruins', 'The Mossy Ruins', 'trails/mossy_ruins.webp'), ('mossy_ruins_hollow', 'The Mossy Ruins, Hollow', 'trails/mossy_ruins_hollow.webp'),
         ('sentinel_gate', 'The Sentinel\'s Gate', 'trails/sentinel_gate.webp'),
         ('mossy_ruins_battle', 'The Mossy Ruins (battle)', 'trails/mossy_ruins_battle.webp'),
         ('sentinel_gate_battle', 'The Sentinel\'s Gate (battle)', 'trails/sentinel_gate_battle.webp')]


def stitch(paths, pos, tile=None, pad=0):
    """tiles at grid positions (col, row) -> one picture. The walk maps' tiles are TILE (1024) px with PAD (8) px
    of bleed on every side that has a neighbour (village_walk_pack.py), which comes off here"""
    ims = {pos(p): Image.open(p).convert('RGBA') for p in paths}
    tile = tile or ims[(0, 0)].width
    cut = {}
    for (c, r), im in ims.items():
        x0, y0 = (pad if c > 0 else 0), (pad if r > 0 else 0)
        cut[(c, r)] = im.crop((x0, y0, im.width, im.height))
    W = max(c * tile + min(im.width, tile) for (c, r), im in cut.items() if (c + 1, r) not in cut) if pad else \
        max(c * tile + im.width for (c, r), im in cut.items())
    H = max(r * tile + min(im.height, tile) for (c, r), im in cut.items() if (c, r + 1) not in cut) if pad else \
        max(r * tile + im.height for (c, r), im in cut.items())
    out = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    for (c, r), im in sorted(cut.items()):
        out.paste(im.crop((0, 0, min(im.width, tile) if (c + 1, r) in cut or pad else im.width,
                           min(im.height, tile) if (c, r + 1) in cut or pad else im.height)), (c * tile, r * tile))
    return out


def flatten(im):
    bg = Image.new('RGB', im.size, BG)
    bg.paste(im, (0, 0), im if im.mode == 'RGBA' else None)
    return bg


def gather(out):
    got = []
    for key, title, d in WALK:
        ts = glob.glob(os.path.join(ART, d, 't_*_*.webp'))
        if not ts:
            continue
        im = stitch(ts, lambda p: tuple(int(v) for v in re.findall(r't_(\d+)_(\d+)', p)[0]), tile=1024, pad=8)   # t_<col>_<row>
        got.append((key, title, im))
    ts = glob.glob(os.path.join(ART, 'wilds', 'thicket_ground_*_*.webp'))
    if ts:
        im = stitch(ts, lambda p: tuple(int(v) for v in re.findall(r'ground_(\d+)_(\d+)', p)[0][::-1]))   # _<row>_<col>
        got.append(('thicket_ground', 'The Sunlit Thicket (Wilds F1) ground', im))
    for key, title, f in FILES:
        p = os.path.join(ART, f)
        if os.path.exists(p):
            got.append((key, title, Image.open(p).convert('RGBA')))
    layers = [os.path.join(ART, 'habitats', 'meadow_%s.webp' % k) for k in ('sky', 'far', 'mid', 'near')]
    if all(os.path.exists(p) for p in layers):
        base = Image.open(layers[0]).convert('RGBA')
        for p in layers[1:]:
            lay = Image.open(p).convert('RGBA').resize(base.size)
            base.alpha_composite(lay)
        got.append(('sunlit_meadow', 'The Sunlit Meadow (the Nest)', base))
    os.makedirs(out, exist_ok=True)
    for key, title, im in got:
        flatten(im).save(os.path.join(out, key + '.jpg'), quality=92, subsampling=0)
        print('%-20s %s' % (key, im.size), flush=True)
    return got


def gallery(got, out, th=300):
    tiles = []
    for key, title, im in got:
        t = flatten(im)
        t.thumbnail((int(th * 1.6), th))
        tiles.append((title, t))
    cols = 4
    cw = int(th * 1.6) + 30
    ch = th + 50
    rows = (len(tiles) + cols - 1) // cols
    img = Image.new('RGB', (30 + cols * cw, 110 + rows * ch), BG)
    d = ImageDraw.Draw(img)
    d.text((30, 22), 'The places of Evochi', font=font(40), fill=INKC)
    for i, (title, t) in enumerate(tiles):
        r, c = divmod(i, cols)
        x, y = 30 + c * cw, 100 + r * ch
        img.paste(t, (x + (cw - 30 - t.width) // 2, y + (th - t.height) // 2))
        d.text((x, y + th + 8), title, font=font(17, False), fill=SUB)
    img.save(os.path.join(out, 'backgrounds_gallery.png'), optimize=True)
    print('gallery', img.size)


if __name__ == '__main__':
    g = gather(sys.argv[1])
    gallery(g, sys.argv[1])

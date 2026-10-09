"""Export the marketing-site images from the master art.

python3 make_site_assets.py HERO_DIR OUT_DIR

HERO_DIR holds the output of tools/art/site_art.py (hero_composite.png, hero.json).
OUT_DIR is site/assets/img. Every image is WebP except the social card and icons,
which use PNG because some link previewers and browsers still expect it.
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
A = os.path.join(ROOT, 'assets')
FONTS = os.path.join(ROOT, 'flutter', 'assets', 'fonts')
PALETTES = ['amber', 'forest', 'coral', 'ocean', 'amethyst', 'obsidian']
HERO_EXPR = {'s01': 'happy', 's02': 'default', 's03': 'default'}
# master frame anchors (web manifest anchors are at 10.5 px/unit; masters are at 14)
GROUND = {'s01': (165.4, 334.6), 's02': (217.0, 339.0), 's03': (282.6, 402.9)}


def char(stage, pal, expr, view='left3q'):
    return Image.open(os.path.join(A, 'characters', f'evochi_lizard_{stage}_{pal}_{expr}_{view}_f000.png')).convert('RGBA')


def overlay(item, slot, stage):
    return Image.open(os.path.join(A, 'characters', f'item_{item}_{slot}_{stage}_left3q.png')).convert('RGBA')


def webp(img, path, q=84, width=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if width and img.width > width:
        img = img.resize((width, round(img.height * width / img.width)), Image.LANCZOS)
    img.save(path, 'WEBP', quality=q, method=6)
    return img.size


def main(hero_dir, out):
    sizes = {}
    # hero vista
    hero = Image.open(os.path.join(hero_dir, 'hero_composite.png')).convert('RGB')
    for w in (2880, 1920, 1200):
        sizes[f'hero-{w}'] = webp(hero, os.path.join(out, 'hero', f'hero-{w}.webp'), q=78, width=w)
    meta = json.load(open(os.path.join(hero_dir, 'hero.json')))

    # pets: three forms in all six colourways (same frame so overlays line up)
    for st, ex in HERO_EXPR.items():
        for p in PALETTES:
            sizes[f'{st}-{p}'] = webp(char(st, p, ex), os.path.join(out, 'pets', f'{st}-{p}.webp'), q=86)
    for (st, p, ex) in (('s02', 'amber', 'sleepy'), ('s01', 'ocean', 'curious'), ('s02', 'coral', 'happy'),
                        ('s03', 'forest', 'happy'), ('s01', 'amber', 'excited')):
        sizes[f'{st}-{p}-{ex}'] = webp(char(st, p, ex), os.path.join(out, 'pets', f'{st}-{p}-{ex}.webp'), q=86)

    # dressed-up composites for the wardrobe section
    looks = {
        'look-leaf': ('s02', 'forest', 'happy', [('leaf_scarf', 'neck')]),
        'look-explorer': ('s02', 'ocean', 'determined', [('explorer_pack', 'back'), ('explorer_hat', 'head')]),
        'look-crown': ('s03', 'amethyst', 'default', [('golden_crest_crown', 'head'), ('blue_scarf', 'neck')]),
        'look-clip': ('s01', 'coral', 'happy', [('butterfly_clip', 'head'), ('red_backpack', 'back')]),
    }
    for name, (st, p, ex, items) in looks.items():
        im = char(st, p, ex)
        for it, slot in items:
            im.alpha_composite(overlay(it, slot, st))
        im = im.crop(im.getbbox())
        sizes[name] = webp(im, os.path.join(out, 'looks', f'{name}.webp'), q=86, width=520)

    # item and UI icons
    for it in ('leaf_scarf', 'explorer_hat', 'golden_crest_crown', 'blue_scarf', 'tiny_crown', 'butterfly_clip',
               'red_backpack', 'explorer_pack', 'meadow_nest', 'explorer_lantern', 'sunlit_flower', 'berry_snack',
               'healing_herb', 'nest_bed'):
        im = Image.open(os.path.join(A, 'items', f'item_{it}_icon.png')).convert('RGBA')
        sizes['item-' + it] = webp(im, os.path.join(out, 'items', f'{it.replace("_", "-")}.webp'), q=88, width=192)
    for ic in ('steps', 'xp', 'evolve', 'coin', 'heart', 'star', 'chest', 'lock', 'paw', 'play', 'care', 'trophy',
               'potion', 'bell', 'journey', 'wearables', 'decorations', 'palette', 'home', 'evodex', 'shop', 'pin'):
        im = Image.open(os.path.join(A, 'ui_icons', f'icon_{ic}.png')).convert('RGBA')
        sizes['icon-' + ic] = webp(im, os.path.join(out, 'icons', f'{ic}.webp'), q=88, width=128)

    wm = Image.open(os.path.join(A, 'ui_titles', 'wordmark_evochi.png')).convert('RGBA')
    sizes['wordmark'] = webp(wm, os.path.join(out, 'wordmark.webp'), q=90)

    # social card (1200x630): vista on the right, wordmark and tagline on a cream panel
    HW, HH, X0, Y0 = 1400, 700, 20, 50
    card = hero.resize((HW, HH), Image.LANCZOS).crop((X0, Y0, X0 + 1200, Y0 + 630)).convert('RGBA')
    for st in ('s01', 's02', 's03'):
        im = char(st, 'amber', HERO_EXPR[st])
        k = meta['pets'][st]['k'] * HH
        im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
        gx, gy = GROUND[st][0] * 14 / 10.5 * k, GROUND[st][1] * 14 / 10.5 * k
        x = meta['pets'][st]['x'] * HW - X0 - gx
        y = meta['pets'][st]['y'] * HH - Y0 - gy
        card.alpha_composite(im, (round(x), round(y)))
    panel = Image.new('RGBA', card.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(panel)
    d.rounded_rectangle((44, 150, 560, 480), 36, fill=(255, 249, 240, 242), outline=(201, 167, 140, 255), width=4)
    shadow = panel.filter(ImageFilter.GaussianBlur(14))
    sh = Image.new('RGBA', card.size, (59, 41, 35, 0))
    sh.putalpha(shadow.getchannel('A').point(lambda a: a * 0.35))
    card.alpha_composite(sh, (0, 10))
    card.alpha_composite(panel)
    wmr = wm.resize((420, round(wm.height * 420 / wm.width)), Image.LANCZOS)
    card.alpha_composite(wmr, (92, 190))
    d = ImageDraw.Draw(card)
    f1 = ImageFont.truetype(os.path.join(FONTS, 'Nunito-ExtraBold.ttf'), 34)
    f2 = ImageFont.truetype(os.path.join(FONTS, 'Lato-Bold.ttf'), 24)
    d.text((92, 340), 'Every step brings your', font=f1, fill=(59, 41, 35))
    d.text((92, 380), 'Evochi to life.', font=f1, fill=(59, 41, 35))
    d.text((92, 434), 'A cozy voxel pet that grows as you walk.', font=f2, fill=(104, 76, 60))
    card.convert('RGB').save(os.path.join(out, 'og-image.jpg'), quality=88, optimize=True, progressive=True)

    # app icon style favicons: eggling on a gold tile
    egg = char('s01', 'amber', 'happy')
    egg = egg.crop(egg.getbbox())
    for size, name in ((512, 'icon-512.png'), (180, 'apple-touch-icon.png'), (48, 'favicon-48.png'),
                       (32, 'favicon-32.png')):
        tile = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        dd = ImageDraw.Draw(tile)
        r = round(size * 0.22)
        dd.rounded_rectangle((0, 0, size - 1, size - 1), r, fill=(200, 131, 44, 255))
        dd.rounded_rectangle((0, 0, size - 1, round(size * 0.93)), r, fill=(244, 184, 78, 255))
        dd.rounded_rectangle((round(size * 0.06), round(size * 0.05), size - 1 - round(size * 0.06), round(size * 0.5)),
                             round(r * 0.8), fill=(249, 202, 112, 255))
        e = egg.copy()
        s = size * 0.8 / max(e.size)
        e = e.resize((max(1, round(e.width * s)), max(1, round(e.height * s))), Image.LANCZOS)
        tile.alpha_composite(e, ((size - e.width) // 2, round(size * 0.47 - e.height / 2)))
        if size == 180:
            # iOS ignores transparency; give it a solid ground
            solid = Image.new('RGBA', tile.size, (244, 184, 78, 255))
            solid.alpha_composite(tile)
            tile = solid
        tile.save(os.path.join(out, name))
    ico = Image.open(os.path.join(out, 'favicon-48.png'))
    ico.save(os.path.join(out, 'favicon.ico'), sizes=[(16, 16), (32, 32), (48, 48)])

    sizes['hero_meta'] = meta
    json.dump(sizes, open(os.path.join(out, 'sizes.json'), 'w'), indent=1)
    print('ok', len(sizes))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])

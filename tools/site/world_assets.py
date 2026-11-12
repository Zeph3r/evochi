"""The website's images that come from the game's own art (the 3D world's posters and the Briarback stills are
screenshots of the page itself: tools/site/shoot_world.mjs).

    python3 world_assets.py [OUT_DIR]                 (default site/assets/img)
    python3 world_assets.py --stills=DIR [OUT_DIR]    only the screenshots in DIR (shoot_world.cjs stills): the world's
                                                      posters, the Briarback stills and the social card

  logo.webp, wordmark.webp     the start screen's logo and the letters-only wordmark (flutter/assets/art/title, titles)
  world/moon.webp              the start screen's pixel moon, scaled up by whole pixels
  acting/<clip>.webp           the Eggling's habits (amber), from the game's acting clips: every clip placed in one
                               shared frame so it stands in the same spot whichever plays, its hops lifted as the
                               game lifts them, and a pause on the last frame before it plays again
  pets/s03-<palette>.webp      the Elder (petal mane) from the character masters, and s03-forest-happy
  favicons and app icons       the brand's crystal mark
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
ART = os.path.join(ROOT, 'flutter', 'assets', 'art')
CHARS = os.path.join(ROOT, 'assets', 'characters')
PALETTES = ['amber', 'forest', 'coral', 'ocean', 'amethyst', 'obsidian']
CLIPS = ['double_hop', 'happy_wiggle', 'bounce_in_place', 'small_hop', 'quick_look', 'step_back_then_commit',
         'careful_peek', 'look_around', 'chin_lift', 'tilt_then_lean', 'gentle_sway']
CLIP_SCALE = 0.75
HOLD_MS = 1400


def webp(img, path, q=86):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, 'WEBP', quality=q, method=6)
    return list(img.size)


def frames(path):
    im = Image.open(path)
    out = []
    for i in range(im.n_frames):
        im.seek(i)
        out.append(im.convert('RGBA'))
    return out


def acting(out, sizes):
    meta = json.load(open(os.path.join(ART, 'acting', 'acting.json')))['s01']
    k = meta['scale']                       # px per unit at the clips' scale: a hop's lift on screen
    clips = {c: meta['clips'][c] for c in CLIPS}
    x0 = min(c['box'][0] for c in clips.values())
    x1 = max(c['box'][0] + c['box'][2] for c in clips.values())
    y0 = min(c['box'][1] - max(c['lift']) * k for c in clips.values())
    y1 = max(c['box'][1] + c['box'][3] - min(c['lift']) * k for c in clips.values())
    W, H = int(x1 - x0) + 4, int(y1 - y0) + 4
    w, h = round(W * CLIP_SCALE), round(H * CLIP_SCALE)
    for name, c in clips.items():
        fps = c.get('fps') or meta['fps']
        cells = []
        for i, f in enumerate(frames(os.path.join(ART, 'acting', c['body']['amber']))):
            cv = Image.new('RGBA', (W, H), (0, 0, 0, 0))
            cv.alpha_composite(f, (round(c['box'][0] - x0 + 2), round(c['box'][1] - y0 + 2 - c['lift'][min(i, len(c['lift']) - 1)] * k)))
            cells.append(cv.resize((w, h), Image.LANCZOS))
        dur = [round(1000 / fps)] * len(cells)
        dur[-1] += HOLD_MS
        p = os.path.join(out, 'acting', name + '.webp')
        os.makedirs(os.path.dirname(p), exist_ok=True)
        cells[0].save(p, save_all=True, append_images=cells[1:], duration=dur, loop=0, quality=72, method=6,
                      minimize_size=False, allow_mixed=False)
        sizes['acting/' + name] = [w, h]
        print(name, len(cells), 'frames', os.path.getsize(p) // 1024, 'KB', flush=True)


def icons(out, sizes):
    mark = Image.open(os.path.join(ROOT, 'assets', 'brand', 'logo_pack', 'brand_crystal_icon.png')).convert('RGBA')
    mark = mark.crop(mark.getbbox())
    for size, name, solid in ((512, 'icon-512.png', False), (180, 'apple-touch-icon.png', True), (48, 'favicon-48.png', False),
                              (32, 'favicon-32.png', False)):
        tile = Image.new('RGBA', (size, size), (255, 249, 240, 255) if solid else (0, 0, 0, 0))
        s = size * (0.8 if solid else 0.96) / max(mark.size)
        m = mark.resize((max(1, round(mark.width * s)), max(1, round(mark.height * s))), Image.LANCZOS)
        tile.alpha_composite(m, ((size - m.width) // 2, (size - m.height) // 2))
        tile.save(os.path.join(out, name))
    Image.open(os.path.join(out, 'favicon-48.png')).save(os.path.join(out, 'favicon.ico'), sizes=[(16, 16), (32, 32), (48, 48)])


def stills(src, out):
    """the world's screenshots as the site ships them, and the social card: the island at night, the logo over it"""
    from PIL import ImageDraw, ImageFont
    for name, q in (('poster-wide', 74), ('poster-tall', 72), ('briarback-hollow', 80), ('briarback-restored', 80)):
        webp(Image.open(os.path.join(src, name + '.png')).convert('RGB'), os.path.join(out, 'world', name + '.webp'), q)
    card = Image.open(os.path.join(src, 'og-world.png')).convert('RGBA')
    shade = Image.new('L', card.size, 0)
    d = ImageDraw.Draw(shade)
    for x in range(card.width):                      # darken the left, where the words go
        d.line([(x, 0), (x, card.height)], fill=int(150 * max(0.0, 1 - x / (card.width * 0.62)) ** 1.4))
    card = Image.composite(Image.new('RGBA', card.size, (10, 8, 30, 255)), card, shade)
    logo = Image.open(os.path.join(ART, 'title', 'logo.webp')).convert('RGBA')
    logo = logo.resize((480, round(logo.height * 480 / logo.width)), Image.LANCZOS)
    card.alpha_composite(logo, (56, 120))
    fonts = os.path.join(ROOT, 'flutter', 'assets', 'fonts')
    d = ImageDraw.Draw(card)
    d.text((70, 120 + logo.height + 18), 'Every step brings the light back.', font=ImageFont.truetype(os.path.join(fonts, 'Nunito-ExtraBold.ttf'), 36), fill=(255, 246, 228))
    d.text((70, 120 + logo.height + 70), 'A cozy voxel pet that grows as you walk.', font=ImageFont.truetype(os.path.join(fonts, 'Lato-Bold.ttf'), 25), fill=(214, 206, 240))
    card.convert('RGB').save(os.path.join(out, 'og-image.jpg'), quality=88, optimize=True, progressive=True)
    print('stills ok')


def main(out):
    sp = os.path.join(out, 'sizes.json')
    sizes = json.load(open(sp)) if os.path.exists(sp) else {}
    sizes.pop('hero_meta', None)
    for k in [k for k in sizes if k.startswith('hero-')]:
        sizes.pop(k)
    sizes['logo'] = webp(Image.open(os.path.join(ART, 'title', 'logo.webp')).convert('RGBA'), os.path.join(out, 'logo.webp'), 90)
    sizes['wordmark'] = webp(Image.open(os.path.join(ART, 'titles', 'wordmark_evochi.webp')).convert('RGBA'), os.path.join(out, 'wordmark.webp'), 90)
    moon = Image.open(os.path.join(ART, 'title', 'moon.webp')).convert('RGBA')
    sizes['moon'] = webp(moon.resize((moon.width * 4, moon.height * 4), Image.NEAREST), os.path.join(out, 'world', 'moon.webp'), 92)
    for p in PALETTES:
        im = Image.open(os.path.join(CHARS, f'evochi_lizard_s03_{p}_default_left3q_f000.png')).convert('RGBA')
        sizes['s03-' + p] = webp(im, os.path.join(out, 'pets', f's03-{p}.webp'))
    im = Image.open(os.path.join(CHARS, 'evochi_lizard_s03_forest_happy_left3q_f000.png')).convert('RGBA')
    sizes['s03-forest-happy'] = webp(im, os.path.join(out, 'pets', 's03-forest-happy.webp'))
    icons(out, sizes)
    acting(out, sizes)
    json.dump(sizes, open(sp, 'w'), indent=1)


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    out = args[0] if args else os.path.join(ROOT, 'site', 'assets', 'img')
    st = [a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--stills=')]
    stills(st[0], out) if st else main(out)

"""Concept boards for the walkable Sunlit Village and for Flint, composited (PIL) from the renders
(village_walk.py, flint.py) and the real sprites. Pictures of the plan, not the game.

    python3 village_concept.py VW_DIR FLINT_DIR OUT_DIR
"""
import json
import math
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ART = '/home/claude/evochi/flutter/assets/art/'
UI = '/home/claude/evochi/flutter/assets/ui/'
FONTS = '/home/claude/evochi/flutter/assets/fonts/'
VW, FL, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
man = json.load(open(ART + 'manifest.json'))
INK = (59, 41, 35)
X = 2                     # px per dp in the phone frames
EVOCHI_H = 3.4            # world units, an Elder standing
NPC_H = {'bram': 4.0, 'mira': 4.2, 'pip': 3.4, 'alder': 3.8}


def font(weight, size, k=X):
    f = {'black': 'Nunito-Black.ttf', 'xbold': 'Nunito-ExtraBold.ttf', 'bold': 'Nunito-Bold.ttf'}[weight]
    return ImageFont.truetype(FONTS + f, int(size * k))


def icon(name, size, k=X):
    return Image.open(ART + man['icons'][name]).convert('RGBA').resize((int(size * k), int(size * k)), Image.LANCZOS)


class View:
    def __init__(self, name):
        self.img = Image.open(f'{VW}/village_walk_{name}.png').convert('RGBA')
        self.p = json.load(open(f'{VW}/village_walk_{name}.json'))
        self.k = self.img.width / self.p['w']          # if rendered smaller than planned

    def at(self, x, z, y=0.0):
        p = self.p
        s = math.sin(math.radians(p['pitch']))
        c = math.cos(math.radians(p['pitch']))
        cx, cz = p['centre']
        ppu = p['ppu'] * self.k
        return (self.img.width / 2 + (x - cx) * ppu, self.img.height / 2 + ((z - cz) * s - y * c) * ppu)

    @property
    def ppu(self):
        return self.p['ppu'] * self.k


def shadow(img, x, y, rx, ry, a=80):
    sh = Image.new('RGBA', img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse((x - rx, y - ry, x + rx, y + ry), fill=(40, 40, 20, a))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(max(2, ry * 0.6))))


def evochi(v, x, z, d='E', f=3, palette='amber', hat=True):
    ww = json.load(open(ART + 'wilds/wilds_walk.json'))
    wk = ww['walkers']['s03']
    di = ww['dirs'].index(d)
    fw, fh = wk['frameW'], wk['frameH']
    sheet = Image.open(ART + 'wilds/' + wk['gaits']['walk']['sheets'][palette]).convert('RGBA')
    im = sheet.crop(((f + 1) * fw, di * fh, (f + 2) * fw, (di + 1) * fh))
    if hat:
        h = Image.open(ART + 'wilds/wear_s03_explorer_hat.webp').convert('RGBA').crop((di * fw, 0, (di + 1) * fw, fh))
        im.alpha_composite(h, (0, -4))
    s = EVOCHI_H * v.ppu / 202.0
    im = im.resize((int(im.width * s), int(im.height * s)), Image.LANCZOS)
    px, py = v.at(x, z)
    shadow(v.img, px, py, im.width * 0.22, 5 * s * 4)
    v.img.alpha_composite(im, (int(px - wk['ground'][0] * s), int(py - wk['ground'][1] * s)))
    return px, py, im.height


def npc(v, who, x, z, expr='neutral'):
    n = man['village']['npcs'][who]
    im = Image.open(ART + n['expr'][expr]).convert('RGBA')
    tall = n['ground'][1] - n['top'][1]
    s = NPC_H[who] * v.ppu / tall
    im = im.resize((int(im.width * s), int(im.height * s)), Image.LANCZOS)
    px, py = v.at(x, z)
    shadow(v.img, px, py, im.width * 0.3, 4 * X)
    v.img.alpha_composite(im, (int(px - n['ground'][0] * s), int(py - n['ground'][1] * s)))
    return px, py - tall * s


def marker(img, x, y, kind='quest'):
    d = ImageDraw.Draw(img)
    r = 15 * X
    gold = (243, 192, 78) if kind == 'quest' else (126, 196, 86)
    d.ellipse((x - r, y - r * 2.2, x + r, y - r * 0.2), fill=gold, outline=(90, 55, 20), width=int(2.5 * X))
    d.polygon([(x - 6 * X, y - r * 0.5), (x + 6 * X, y - r * 0.5), (x, y + 4 * X)], fill=gold)
    t = '!' if kind == 'quest' else '✓'
    f = font('black', 19)
    d.text((x - d.textlength(t, font=f) / 2, y - r * 2.2 + 3 * X), t, font=f, fill=INK)


def tap_ring(img, x, y, rx):
    d = ImageDraw.Draw(img)
    for i, a in enumerate((230, 120)):
        g = 4 * X * i
        d.ellipse((x - rx - g, y - rx * 0.42 - g * 0.42, x + rx + g, y + rx * 0.42 + g * 0.42), outline=(255, 250, 230, a), width=int(2.5 * X))


def chip(img, x, y, text):
    d = ImageDraw.Draw(img)
    f = font('black', 15)
    tw = d.textlength(text, font=f)
    d.rounded_rectangle((x - tw / 2 - 12 * X, y - 15 * X, x + tw / 2 + 12 * X, y + 15 * X), radius=12 * X, fill=(255, 248, 232), outline=(201, 167, 140), width=int(1.5 * X))
    d.text((x - tw / 2, y - 11 * X), text, font=f, fill=INK)


def bubble(img, x, y, text, w_dp=210):
    d = ImageDraw.Draw(img)
    f = font('bold', 13)
    words, lines, line = text.split(), [], ''
    for wd in words:
        t = (line + ' ' + wd).strip()
        if d.textlength(t, font=f) > (w_dp - 24) * X:
            lines.append(line)
            line = wd
        else:
            line = t
    lines.append(line)
    hh = (len(lines) * 18 + 16) * X
    x0, y0 = x - w_dp * X / 2, y - hh - 10 * X
    d.rounded_rectangle((x0, y0, x0 + w_dp * X, y0 + hh), radius=12 * X, fill=(255, 248, 232), outline=(201, 167, 140), width=3)
    d.polygon([(x - 8 * X, y0 + hh - 2), (x + 8 * X, y0 + hh - 2), (x, y)], fill=(255, 248, 232))
    for i, ln in enumerate(lines):
        d.text((x0 + 12 * X, y0 + 8 * X + i * 18 * X), ln, font=f, fill=INK)


def motes(img, pts, n=14):
    g = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(g)
    for i in range(n):
        t = i / (n - 1)
        seg = min(int(t * (len(pts) - 1)), len(pts) - 2)
        u = t * (len(pts) - 1) - seg
        x = pts[seg][0] + (pts[seg + 1][0] - pts[seg][0]) * u
        y = pts[seg][1] + (pts[seg + 1][1] - pts[seg][1]) * u - 10 * X - 4 * X * math.sin(i * 1.3)
        r = (3.5 + 1.5 * (i % 3 == 0)) * X
        d.ellipse((x - r * 2.4, y - r * 2.4, x + r * 2.4, y + r * 2.4), fill=(190, 250, 255, 70))
        d.ellipse((x - r, y - r, x + r, y + r), fill=(230, 255, 255, 235))
    img.alpha_composite(g.filter(ImageFilter.GaussianBlur(1.2 * X)))
    img.alpha_composite(g)


def wood(img, box, r, tone='light', border=(74, 42, 20), bw=2.5):
    x0, y0, x1, y1 = [int(v) for v in box]
    tex = Image.open(UI + f'wood_{tone}.png').convert('RGBA').resize((x1 - x0, y1 - y0))
    m = Image.new('L', (x1 - x0, y1 - y0), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, x1 - x0 - 1, y1 - y0 - 1], radius=int(r * X), fill=255)
    img.paste(tex, (x0, y0), m)
    ImageDraw.Draw(img).rounded_rectangle([x0, y0, x1 - 1, y1 - 1], radius=int(r * X), outline=border, width=int(bw * X))


def phone(v, title='Sunlit Village', marks=None):
    """The map full-bleed, a slim bar on top (back, the place, coins), the quick-travel row below."""
    W = v.img.width
    top, bot = 64 * X, 92 * X
    c = Image.new('RGBA', (W, v.img.height + top + bot), (134, 181, 102, 255))
    c.alpha_composite(v.img, (0, top))
    d = ImageDraw.Draw(c)
    wood(c, (0, 0, W, top), 0, 'dark', (46, 24, 10), 2)
    wood(c, (12 * X, 14 * X, 52 * X, 54 * X), 10, 'light')
    d.text((22 * X, 16 * X), '‹', font=font('black', 28), fill=INK)
    f = font('black', 19)
    d.text(((W - d.textlength(title, font=f)) / 2, 20 * X), title, font=f, fill=(255, 240, 220))
    wood(c, (W - 128 * X, 16 * X, W - 12 * X, 50 * X), 16, 'dark', (30, 14, 4), 2)
    c.alpha_composite(icon('coin', 22), (W - 122 * X, 22 * X))
    d.text((W - 94 * X, 22 * X), '7,028', font=font('black', 15), fill=(255, 255, 255))
    y0 = top + v.img.height
    wood(c, (0, y0, W, y0 + bot), 0, 'dark', (46, 24, 10), 2)
    items = [('mail', 'Guild'), ('care', 'Glasshouse'), ('bell', 'Workshop'), ('star', 'Waystone'), ('shop', 'Market')]
    bw = W / len(items)
    for i, (ic, lab) in enumerate(items):
        cx = bw * (i + 0.5)
        wood(c, (cx - 26 * X, y0 + 10 * X, cx + 26 * X, y0 + 62 * X), 26, 'light')
        c.alpha_composite(icon(ic, 32), (int(cx - 16 * X), int(y0 + 20 * X)))
        tf = font('xbold', 11)
        d.text((cx - d.textlength(lab, font=tf) / 2, y0 + 68 * X), lab, font=tf, fill=(255, 240, 220))
        if marks and lab in marks:
            d.ellipse((cx + 14 * X, y0 + 6 * X, cx + 30 * X, y0 + 22 * X), fill=(216, 95, 81), outline=(255, 246, 236), width=int(2 * X))
    return c


def board(title, sub, panels, out, gap=40):
    tf = font('black', 30, 1)
    sf = font('bold', 20, 1)
    lf = font('xbold', 20, 1)
    hs = max(p.height for _, p in panels)
    W = sum(p.width for _, p in panels) + gap * (len(panels) + 1)
    H = hs + 150
    b = Image.new('RGB', (W, H), (36, 32, 44))
    d = ImageDraw.Draw(b)
    d.text((gap, 18), title, font=tf, fill=(255, 236, 200))
    d.text((gap, 58), sub, font=sf, fill=(205, 205, 215))
    x = gap
    for lab, p in panels:
        d.text((x, 104), lab, font=lf, fill=(255, 214, 120))
        b.paste(p.convert('RGB'), (x, 136))
        x += p.width + gap
    b.save(out, quality=90)
    return b


# ---------------------------------------------------------------- the phone views
pl = View('plaza')
ex, ey, eh = evochi(pl, 2.0, 5.0, 'NE')
px_, py_ = npc(pl, 'pip', -4.5, -31.0, 'happy')
marker(pl.img, px_, py_ - 6 * X, 'quest')
npc(pl, 'alder', 4.6, -31.0)
plaza = phone(pl, marks={'Guild'})

ws = View('workshop')
bx, by_top = npc(ws, 'bram', 24.4, -1.2, 'happy')
bpx, bpy = ws.at(24.4, -1.2)
tap_ring(ws.img, bpx, bpy, 26 * X)
evochi(ws, 17.5, -0.6, 'E')
chip(ws.img, bx, by_top - 20 * X, 'Bram')
bubble(ws.img, bx, by_top - 42 * X, "Back again? Bring me some ore and I'll make you something sturdy.")
workshop_ = phone(ws)

rd = View('road')
trail = [rd.at(38, 8.4), rd.at(48, 7.6), rd.at(56, 5.6), rd.at(66, 4.0)]
motes(rd.img, trail)
evochi(rd, 34.0, 8.6, 'E')
sx, sy = rd.at(50.0, 4.0, 3.6)
bubble(rd.img, sx, sy - 4 * X, 'East: the Crossing. The old mine, and the trail into the Sunlit Thicket.', 220)
road = phone(rd)

fa = View('falls')
evochi(fa, -18.0, -44.0, 'N')
falls = phone(fa)

s = 0.5
panels = [(n, p.resize((int(p.width * s), int(p.height * s)), Image.LANCZOS)) for n, p in
          (('The plaza: the Guild across the bridge', plaza), ('Bram outside his workshop: tap to talk', workshop_),
           ('The Old Trail east, to the Crossing', road), ('The waterfall, the pool and the creek', falls))]
board('Sunlit Village, walkable', 'Same buildings, spaced out, seen from the Wilds camera. No labels: names show when you tap or walk up; "!" marks who has something for you.',
      panels, f'{OUT}/village_walk_views.jpg')

# ---------------------------------------------------------------- the whole map, with callouts (for the concept only)
al = View('all')
im = al.img
d = ImageDraw.Draw(im)
calls = [('Trail Guild', 0, -39, 12), ('Glasshouse (Mira)', -33, -4, 10), ('Workshop (Bram)', 34, -5, 14), ('Waystone', 0, 0, 10),
         ('Market', -16, 24, 8), ('Road home', 0, 56, 0), ('Old Trail to the Crossing', 50, 6, 4), ('Bridge', 0, -26, 3)]
for (t, x, z, y) in calls:
    cx, cy = al.at(x, z, y)
    f = font('black', 15, 1.2)
    tw = d.textlength(t, font=f)
    d.rounded_rectangle((cx - tw / 2 - 10, cy - 34, cx + tw / 2 + 10, cy - 6), radius=10, fill=(36, 32, 44, 225))
    d.text((cx - tw / 2, cy - 31), t, font=f, fill=(255, 236, 200))
board('Sunlit Village: the new layout', 'The callouts are for this picture only; in the game the buildings have no labels.',
      [('The whole village from the walking camera', im)], f'{OUT}/village_walk_map.jpg')

# ---------------------------------------------------------------- Flint
f_ = {e: Image.open(f'{FL}/flint_{e}.png').convert('RGBA') for e in ('default', 'happy', 'thinking')}
el = Image.open(f'{FL}/elder_obsidian.png').convert('RGBA')
H = f_['default'].height + 40
pan = Image.new('RGBA', (el.width + f_['default'].width + 80, H), (232, 226, 214, 255))
pan.alpha_composite(el, (20, H - 20 - el.height))
pan.alpha_composite(f_['default'], (el.width + 60, 20))
d = ImageDraw.Draw(pan)
lf = font('black', 22, 1)
d.text((24, 20), 'An Obsidian Elder', font=lf, fill=INK)
d.text((el.width + 64, 20), 'Flint', font=font('black', 30, 1), fill=INK)
faces = Image.new('RGBA', (f_['happy'].width // 2 * 2 + 40, H), (232, 226, 214, 255))
faces.alpha_composite(f_['happy'].resize((f_['happy'].width // 2, f_['happy'].height // 2), Image.LANCZOS), (10, 30))
faces.alpha_composite(f_['thinking'].resize((f_['thinking'].width // 2, f_['thinking'].height // 2), Image.LANCZOS), (10, 30 + H // 2))
s = 0.62
board('Flint, keeper of the mines', 'About 1.4x an Elder. Hard hat and headlamp, heavy-lidded old eyes, no blush, grey brows and chin tuft, frosted spikes, a red bandana, a tool belt and a pickaxe.',
      [('Beside an ordinary Obsidian Elder', pan.resize((int(pan.width * s), int(pan.height * s)), Image.LANCZOS)),
       ('Happy / thinking', faces.resize((int(faces.width * s), int(faces.height * s)), Image.LANCZOS))],
      f'{OUT}/flint_concept.jpg')
print('ok')

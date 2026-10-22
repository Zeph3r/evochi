"""Phone-frame preview + layout map of the nest hub (PIL), using the real art and the game's layout
numbers (SceneScaffold / NestScreen). Not the game: a picture of where things will go.

python3 compose.py SCENE_DIR STATE OUT_PREFIX [--h 915]
"""
import json
import math
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ART = '/home/claude/evochi/flutter/assets/art/'
UI = '/home/claude/evochi/flutter/assets/ui/'
FONTS = '/home/claude/evochi/flutter/assets/fonts/'
SD, STATE, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
H_DP = int(sys.argv[sys.argv.index('--h') + 1]) if '--h' in sys.argv else 915
W_DP = 412
X = 2  # px per dp
W, H = W_DP * X, H_DP * X
man = json.load(open(ART + 'manifest.json'))
meta = json.load(open(f'{SD}/habitat_hub_{STATE}.json'))
hab = man['habitats']['meadow']


def font(weight, size):
    f = {'black': 'Nunito-Black.ttf', 'xbold': 'Nunito-ExtraBold.ttf', 'bold': 'Nunito-Bold.ttf'}[weight]
    return ImageFont.truetype(FONTS + f, int(size * X))


def icon(name, size):
    im = Image.open(ART + man['icons'][name]).convert('RGBA')
    return im.resize((int(size * X), int(size * X)), Image.LANCZOS)


INK = (59, 41, 35)
SIGN_INK = (58, 32, 14)

# ---------------------------------------------------------------- layout (dp), as NestScreen lays it out
STATUS = 28
HEADER = 10 + 148               # right column: coin pill 36 + 10 + 46 + 10 + 46 (the trip row is gone)
NAV = 80
MOCK = '--panel' in sys.argv and sys.argv[sys.argv.index('--panel') + 1] == 'mockup'
# today's: chip, nameplate, steps, Pet/Play/Inspect, Evolution Family; the mockup's: the last three
PANEL = (290 if MOCK else (450 if H_DP >= 800 else 330))
hero_top = STATUS + HEADER
hero_bottom = H_DP - NAV - PANEL
gy = hero_bottom - 22                 # the pet's ground: the hero's bottom less groundOffset
k_dp = W_DP / hab['w']                # dp per design px
mscale0 = hab['w'] / meta['w']
anchor = [v * mscale0 for v in meta['pet']]
DY = anchor[1] - hab['pet'][1]        # the hub's nest sits lower in its frame than the meadow's
oy_dp = min(0.0, gy - anchor[1] * k_dp)
SC = k_dp * X                         # px per design px


def d2p(x, y):
    """design px (780-wide scene) -> preview px"""
    return x * SC, oy_dp * X + y * SC


# ---------------------------------------------------------------- the scene
canvas = Image.new('RGBA', (W, H), (134, 201, 91, 255))
layers = {n: Image.open(f'{SD}/habitat_hub_{STATE}_{n}_day.png').convert('RGBA') for n in ('sky', 'far', 'mid', 'near')}
scale_src = hab['w'] / layers['sky'].width     # the render may be at another scale than 780 wide
sw, sh = int(layers['sky'].width * scale_src * SC), int(layers['sky'].height * scale_src * SC)
oy_px = int(oy_dp * X)
for n in ('sky', 'far', 'mid'):
    canvas.alpha_composite(layers[n].resize((sw, sh), Image.LANCZOS), (0, oy_px))
# meta is in render px; to design px
mscale = hab['w'] / meta['w']

# the nest (the meadow's straw nest decoration)
d = hab['decor']['meadow_nest@nest']
nest = Image.open(ART + d['file']).convert('RGBA')
nw = int(d['w'] * SC)
nest = nest.resize((nw, int(nest.height * nw / nest.width)), Image.LANCZOS)
nx, ny = d2p(d['x'], d['y'] + DY)
canvas.alpha_composite(nest, (int(nx), int(ny)))

# ---------------------------------------------------------------- the signs
board = Image.open(f'{SD}/hub_sign_board.png').convert('RGBA')
BOARD_W, BOARD_H = 124, 48
sign_rects = {}


def sign(key, label, ic, point_left):
    top = meta['signs'][key]['top']['px']
    cx, cy = d2p(top[0] * mscale, top[1] * mscale)
    b = board.resize((BOARD_W * X, BOARD_H * X), Image.LANCZOS)
    if point_left:
        b = b.transpose(Image.FLIP_LEFT_RIGHT)
    x0, y0 = int(cx - BOARD_W * X / 2), int(cy - BOARD_H * X * 0.62)
    canvas.alpha_composite(b, (x0, y0))
    # icon + lettering on the plank's square end
    body_x0 = x0 + (16 * X if point_left else 6 * X)
    body_w = BOARD_W * X - 22 * X
    dr = ImageDraw.Draw(canvas)
    f = font('black', 17 if len(label) < 6 else 15)
    tw = dr.textlength(label, font=f)
    iw = 24 * X
    total = iw + 4 * X + tw
    sx = body_x0 + (body_w - total) / 2
    canvas.alpha_composite(icon(ic, 24), (int(sx), int(y0 + (BOARD_H * X - iw) / 2)))
    ty = y0 + BOARD_H * X / 2 - 12 * X
    dr.text((sx + iw + 4 * X, ty + 1 * X), label, font=f, fill=(255, 232, 196, 180))
    dr.text((sx + iw + 4 * X, ty), label, font=f, fill=SIGN_INK)
    sign_rects[key] = (x0, y0, x0 + BOARD_W * X, y0 + BOARD_H * X)


sign('home', 'HOME', 'home', True)
sign('village', 'VILLAGE', 'habitats', False)


# the Evochi: an Amber Elder in its explorer hat
ch = man['chars']['s03']
atlas = Image.open(ART + ch['atlas']['amber']['file']).convert('RGBA')
r = ch['atlas']['amber']['rects'][ch['expressions'].index('happy')]
pet = atlas.crop((r[0], r[1], r[0] + r[2], r[1] + r[3]))
ov = Image.open(ART + ch['overlays']['file']).convert('RGBA')
orr = ch['overlays']['rects']['explorer_hat']
pet.alpha_composite(ov.crop((orr[0], orr[1], orr[0] + orr[2], orr[1] + orr[3])))
ps = hab['petPxPerUnit'] * 0.165 / ch['scale']          # design px per atlas px
gpx, gpy = d2p(*anchor)
pw, ph = int(ch['w'] * ps * SC), int(ch['h'] * ps * SC)
pet = pet.resize((pw, ph), Image.LANCZOS)
ga = ch['anchors']['ground']
pet_box = (int(gpx - ga[0] * ps * SC), int(gpy - ga[1] * ps * SC))
sh_ = Image.new('RGBA', (W, H), (0, 0, 0, 0))
ImageDraw.Draw(sh_).ellipse((gpx - pw * 0.28, gpy - 10 * X, gpx + pw * 0.28, gpy + 8 * X), fill=(40, 60, 20, 70))
canvas.alpha_composite(sh_.filter(ImageFilter.GaussianBlur(4 * X)))
canvas.alpha_composite(pet, pet_box)
bbox = pet.getbbox()
pet_rect = (pet_box[0] + bbox[0], pet_box[1] + bbox[1], pet_box[0] + bbox[2], pet_box[1] + bbox[3])

# the near flora over everything in the scene
canvas.alpha_composite(layers['near'].resize((sw, sh), Image.LANCZOS), (0, oy_px))
scene_only = canvas.copy()

# ---------------------------------------------------------------- UI: header
dr = ImageDraw.Draw(canvas)


def rrect(box, r, fill, outline=None, width=0):
    dr.rounded_rectangle([int(v) for v in box], radius=int(r * X), fill=fill, outline=outline, width=int(width * X))


def wood(box, r, tone='light', border=(74, 42, 20), bw=2.5):
    x0, y0, x1, y1 = [int(v) for v in box]
    tex = Image.open(UI + f'wood_{tone}.png').convert('RGBA').resize((x1 - x0, y1 - y0))
    m = Image.new('L', (x1 - x0, y1 - y0), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, x1 - x0 - 1, y1 - y0 - 1], radius=int(r * X), fill=255)
    canvas.paste(tex, (x0, y0), m)
    ImageDraw.Draw(canvas).rounded_rectangle([x0, y0, x1 - 1, y1 - 1], radius=int(r * X), outline=border, width=int(bw * X))


def card(box, r=14, fill=(255, 248, 232), edge=(107, 63, 30)):
    x0, y0, x1, y1 = box
    rrect((x0, y0 + 3 * X, x1, y1 + 3 * X), r, (199, 154, 98))
    rrect(box, r, fill, edge, 2)


wm = Image.open(ART + man['titles']['wordmark_evochi']['file']).convert('RGBA')
wm = wm.resize((int(40 * X * wm.width / wm.height), 40 * X), Image.LANCZOS)
hy = (STATUS + 10) * X
canvas.alpha_composite(wm, (14 * X, hy))
py = hy + 50 * X
_pw = dr.textlength('Sunlit Meadow  ›', font=font('xbold', 16)) + 46 * X
rrect((14 * X, py, 14 * X + _pw, py + 36 * X), 10, (255, 246, 224), (201, 167, 140), 1.5)
canvas.alpha_composite(icon('pin', 24), (20 * X, py + 6 * X))
dr.text((48 * X, py + 7 * X), 'Sunlit Meadow  ›', font=font('xbold', 16), fill=INK)
# right column: coins, settings, mail
rx1 = (W_DP - 14) * X
wood((rx1 - 118 * X, hy, rx1, hy + 36 * X), 18, 'dark', (46, 24, 10), 2)
canvas.alpha_composite(icon('coin', 24), (rx1 - 112 * X, hy + 6 * X))
dr.text((rx1 - 84 * X, hy + 8 * X), '7,028', font=font('black', 15), fill=(255, 255, 255))
rrect((rx1 - 32 * X, hy + 6 * X, rx1 - 8 * X, hy + 30 * X), 6, (243, 192, 78), (120, 70, 20), 1.5)
dr.text((rx1 - 25 * X, hy + 3 * X), '+', font=font('black', 19), fill=INK)
for k, ic in enumerate(('settings', 'mail')):
    by = hy + (46 + k * 56) * X
    wood((rx1 - 46 * X, by, rx1, by + 46 * X), 11, 'light')
    canvas.alpha_composite(icon(ic, 30), (rx1 - 38 * X, by + 8 * X))

# the hint bubble, over the pet (until the first trip)
bt = 'Tap a trail sign to wander.'
bf = font('bold', 14)
btw = dr.textlength(bt, font=bf)
bx0 = (W - btw) / 2 - 12 * X
by0 = pet_rect[1] - 44 * X
rrect((bx0, by0, bx0 + btw + 24 * X, by0 + 32 * X), 12, (255, 248, 232), (201, 167, 140), 1.5)
dr.polygon([(W / 2 - 8 * X, by0 + 32 * X - 2), (W / 2 + 8 * X, by0 + 32 * X - 2), (W / 2, by0 + 41 * X)], fill=(255, 248, 232))
dr.line([(W / 2 - 8 * X, by0 + 32 * X), (W / 2, by0 + 41 * X), (W / 2 + 8 * X, by0 + 32 * X)], fill=(201, 167, 140), width=int(1.5 * X))
dr.text((bx0 + 12 * X, by0 + 6 * X), bt, font=bf, fill=INK)

# ---------------------------------------------------------------- UI: panel (today's, unchanged)
y = hero_bottom * X
L, R = 12 * X, (W_DP - 12) * X
if H_DP >= 800 and not MOCK:
    rrect((L, y, R, y + 36 * X), 12, (229, 242, 207), (150, 190, 120), 1.5)
    canvas.alpha_composite(icon('discover', 24), (L + 8 * X, y + 6 * X))
    dr.text((L + 40 * X, y + 8 * X), "Today's discovery: a glint by the old bridge", font=font('xbold', 13), fill=INK)
    y += 44 * X
# nameplate
if not MOCK:
    card((L, y, R, y + 96 * X))
    dr.text((L + 14 * X, y + 10 * X), 'Mochi', font=font('black', 28), fill=INK)
    rrect((L + 14 * X, y + 52 * X, L + 70 * X, y + 74 * X), 8, (233, 222, 246), (160, 130, 200), 1)
    dr.text((L + 22 * X, y + 54 * X), 'Elder', font=font('xbold', 13), fill=(90, 60, 140))
    rrect((L + 76 * X, y + 52 * X, L + 140 * X, y + 74 * X), 8, (229, 242, 207), (150, 190, 120), 1)
    dr.text((L + 84 * X, y + 54 * X), 'Healthy', font=font('xbold', 13), fill=(70, 120, 50))
    mx = L + 200 * X
    dr.line([(mx - 14 * X, y + 12 * X), (mx - 14 * X, y + 84 * X)], fill=(196, 150, 96), width=int(1.5 * X))
    dr.text((mx, y + 10 * X), 'Lv. 24', font=font('black', 22), fill=INK)
    rrect((mx, y + 44 * X, R - 14 * X, y + 56 * X), 6, (240, 225, 200), (180, 140, 100), 1)
    rrect((mx, y + 44 * X, mx + 80 * X, y + 56 * X), 6, (243, 192, 78))
    for i in range(5):
        canvas.alpha_composite(icon('heart' if i < 4 else 'heart_empty', 18), (mx + i * 20 * X, y + 64 * X))
    y += 104 * X
# steps
wood((L, y, R, y + 68 * X), 14, 'light')
dr.ellipse((L + 10 * X, y + 9 * X, L + 60 * X, y + 59 * X), fill=(255, 244, 220), outline=(107, 63, 30), width=int(2 * X))
canvas.alpha_composite(icon('steps', 36), (L + 17 * X, y + 16 * X))
dr.text((L + 72 * X, y + 8 * X), 'Daily Steps', font=font('bold', 13), fill=SIGN_INK)
dr.text((L + 72 * X, y + 24 * X), '0 / 7,000 steps', font=font('black', 19), fill=SIGN_INK)
rrect((L + 72 * X, y + 48 * X, L + 250 * X, y + 60 * X), 6, (60, 40, 25))
rrect((R - 120 * X, y + 18 * X, R - 10 * X, y + 48 * X), 10, (229, 242, 207), (210, 232, 185), 1.5)
dr.text((R - 112 * X, y + 24 * X), '+0 XP today!', font=font('xbold', 12), fill=(70, 120, 50))
y += 76 * X
# Pet / Play / Inspect
bw_ = (R - L - 20 * X) / 3
for i, (lab, ic, col, edge) in enumerate((('Pet', 'heart', (247, 200, 92), (176, 120, 40)),
                                          ('Play', 'play', (126, 196, 86), (62, 110, 43)),
                                          ('Inspect', 'inspect', (255, 246, 224), (180, 150, 110)))):
    bx = L + i * (bw_ + 10 * X)
    rrect((bx, y + 3 * X, bx + bw_, y + 61 * X), 14, edge)
    rrect((bx, y, bx + bw_, y + 58 * X), 14, col, edge, 2)
    tf = font('black', 17)
    tw = dr.textlength(lab, font=tf)
    sx = bx + (bw_ - (26 * X + 6 * X + tw)) / 2
    canvas.alpha_composite(icon(ic, 26), (int(sx), y + 16 * X))
    dr.text((sx + 32 * X, y + 16 * X), lab, font=tf, fill=INK)
y += 66 * X
# Evolution Family
eh = hero_bottom * X + PANEL * X - 8 * X - y
card((L, y, R, y + eh))
dr.text((L + 12 * X, y + 8 * X), 'Evolution Family', font=font('xbold', 15), fill=INK)
dr.text((R - 100 * X, y + 10 * X), 'Grow together!', font=font('bold', 12), fill=(142, 116, 98))
for i, st in enumerate(('s01', 's02', 's03')):
    c2 = man['chars'][st]
    a2 = Image.open(ART + c2['atlas']['amber']['file']).convert('RGBA')
    r2 = c2['atlas']['amber']['rects'][0]
    sp = a2.crop((r2[0], r2[1], r2[0] + r2[2], r2[1] + r2[3]))
    hh = int(min(eh - 40 * X, 80 * X))
    sp = sp.resize((int(sp.width * hh / sp.height), hh), Image.LANCZOS)
    cx = L + (R - L) * (i * 2 + 1) / 6
    canvas.alpha_composite(sp, (int(cx - sp.width / 2), int(y + 30 * X)))
# nav
wood((0, (H_DP - NAV) * X, W, H), 0, 'dark', (46, 24, 10), 2)
for i, (lab, ic) in enumerate((('Home', 'home'), ('Journey', 'journey'), ('Bag', 'bag'), ('Shop', 'shop'), ('EvoDex', 'evodex'))):
    cx = W * (i * 2 + 1) / 10
    if i == 0:
        rrect((cx - 36 * X, (H_DP - NAV + 8) * X, cx + 36 * X, (H_DP - 10) * X), 12, (255, 236, 200), (120, 80, 40), 2)
    canvas.alpha_composite(icon(ic, 32), (int(cx - 16 * X), (H_DP - NAV + 12) * X))
    tf = font('xbold', 12)
    dr.text((cx - dr.textlength(lab, font=tf) / 2, (H_DP - NAV + 48) * X), lab, font=tf, fill=INK if i == 0 else (255, 240, 220))

canvas.convert('RGB').save(f'{OUT}_preview.png')

# ---------------------------------------------------------------- the map (annotations over a dimmed copy)
m = canvas.copy()
ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
od = ImageDraw.Draw(ov)
# header and panel: tinted, labelled
od.rectangle((0, 0, W, hero_top * X), fill=(30, 40, 90, 95))
od.rectangle((0, hero_bottom * X, W, H), fill=(30, 40, 90, 95))
m.alpha_composite(ov)
ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
od = ImageDraw.Draw(ov)
lf = font('black', 13)
sf = font('bold', 12)


def tag(x, y, text, col=(255, 255, 255), bg=(30, 30, 40, 200), f=None):
    f = f or sf
    tw = od.textlength(text, font=f)
    od.rounded_rectangle((x, y, x + tw + 12 * X, y + 20 * X), radius=6 * X, fill=bg)
    od.text((x + 6 * X, y + 2 * X), text, font=f, fill=col)


# the hero band
od.rectangle((2, hero_top * X, W - 2, hero_bottom * X), outline=(255, 214, 90, 255), width=int(2 * X))
tag(8 * X, hero_top * X + 4 * X, f'scene: {hero_bottom - hero_top} dp tall on a 412x915 phone', (255, 230, 150))
# sign tap areas (≥ 48 dp tall), glow outline
GOLD = (255, 200, 60, 255)
for key, rct in sign_rects.items():
    x0, y0, x1, y1 = rct
    od.rounded_rectangle((x0 - 4 * X, y0 - 4 * X, x1 + 4 * X, y1 + 4 * X), radius=10 * X, outline=GOLD, width=int(2.5 * X))
tag(sign_rects['home'][0] + 2 * X, sign_rects['home'][3] + 6 * X, 'tap: HOME (Home Map)', (255, 220, 120))
tag(sign_rects['village'][0] - 52 * X, sign_rects['village'][3] + 6 * X, 'tap: VILLAGE (the Square)', (255, 220, 120))
# the two walks, dotted, with arrowheads
for key, col in (('home', (120, 230, 255, 255)), ('village', (255, 140, 200, 255))):
    pts = [d2p(p['px'][0] * mscale, p['px'][1] * mscale) for p in meta['walks'][key]]
    for a, b in zip(pts, pts[1:]):
        n = max(2, int(math.dist(a, b) / (7 * X)))
        for i in range(0, n, 2):
            p0 = (a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n)
            p1 = (a[0] + (b[0] - a[0]) * (i + 1) / n, a[1] + (b[1] - a[1]) * (i + 1) / n)
            od.line([p0, p1], fill=col, width=int(3 * X))
    a, b = pts[-2], pts[-1]
    ang = math.atan2(b[1] - a[1], b[0] - a[0])
    od.polygon([b, (b[0] - 12 * X * math.cos(ang - 0.5), b[1] - 12 * X * math.sin(ang - 0.5)),
                (b[0] - 12 * X * math.cos(ang + 0.5), b[1] - 12 * X * math.sin(ang + 0.5))], fill=col)
    g = meta['goals'][key]['px']
    gx, gy2 = d2p(g[0] * mscale, g[1] * mscale)
    od.ellipse((gx - 6 * X, gy2 - 6 * X, gx + 6 * X, gy2 + 6 * X), outline=col, width=int(2.5 * X))
# decoration slots (the player's placed decor) as small rings
for k2, s in meta['slots'].items():
    if k2 == 'nest':
        continue
    sx2, sy2 = d2p(s['px'][0] * mscale, s['px'][1] * mscale)
    od.ellipse((sx2 - 7 * X, sy2 - 4 * X, sx2 + 7 * X, sy2 + 4 * X), outline=(255, 255, 255, 230), width=int(2 * X))
    tag(sx2 - 20 * X, sy2 + 6 * X, f'decor: {k2}', (255, 255, 255), (60, 60, 60, 170))
# labels for header / panel
tag(14 * X, (hero_top - 26) * X, 'header (trip buttons removed)', (220, 230, 255), (30, 40, 90, 220))
tag(14 * X, hero_bottom * X + 6 * X, "panel: as in your mockup (no nameplate, no discovery chip)" if MOCK else "panel: today's (nameplate + discovery chip)", (220, 230, 255), (30, 40, 90, 220))
m.alpha_composite(ov)
m.convert('RGB').save(f'{OUT}_map.png')
scene_only.convert('RGB').save(f'{OUT}_scene.png')
print(json.dumps({'hero': [hero_top, hero_bottom], 'gy': gy, 'oy_dp': oy_dp, 'pet_rect_dp': [v / X for v in pet_rect],
                  'signs_dp': {k: [v / X for v in r] for k, r in sign_rects.items()}}))

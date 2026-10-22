"""Nest hub storyboard: the tap on a sign, beat by beat, composited from the real art at the game's
layout numbers (the mockup's panel). A picture of the plan, not the game.

python3 hubpreview.py SCENE_DIR STATE OUT.png
"""
import json
import math
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ART = '/home/claude/evochi/flutter/assets/art/'
UI = '/home/claude/evochi/flutter/assets/ui/'
FONTS = '/home/claude/evochi/flutter/assets/fonts/'
SD, STATE, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
X = 2
W_DP, H_DP = 412, 915
W, H = W_DP * X, H_DP * X
man = json.load(open(ART + 'manifest.json'))
meta = json.load(open(f'{SD}/habitat_hub_{STATE}.json'))
hab = man['habitats']['meadow']
INK, SIGN_INK = (59, 41, 35), (58, 32, 14)

STATUS, HEADER, NAV, PANEL = 28, 158, 80, 290
hero_top, hero_bottom = STATUS + HEADER, H_DP - NAV - PANEL
gy = hero_bottom - 22
k_dp = W_DP / hab['w']
ms = hab['w'] / meta['w']
anchor = [v * ms for v in meta['pet']]
DY = anchor[1] - hab['pet'][1]
oy_dp = min(0.0, gy - anchor[1] * k_dp)
SC = k_dp * X


def d2p(x, y):
    return x * SC, oy_dp * X + y * SC


def mp(p):
    return d2p(p[0] * ms, p[1] * ms)


def font(weight, size):
    f = {'black': 'Nunito-Black.ttf', 'xbold': 'Nunito-ExtraBold.ttf', 'bold': 'Nunito-Bold.ttf'}[weight]
    return ImageFont.truetype(FONTS + f, int(size * X))


def icon(name, size):
    return Image.open(ART + man['icons'][name]).convert('RGBA').resize((int(size * X), int(size * X)), Image.LANCZOS)


LAYERS = {n: Image.open(f'{SD}/habitat_hub_{STATE}_{n}_day.png').convert('RGBA') for n in ('sky', 'far', 'mid', 'near')}
_s = hab['w'] / LAYERS['sky'].width
SW, SH = int(LAYERS['sky'].width * _s * SC), int(LAYERS['sky'].height * _s * SC)
LAYERS = {n: im.resize((SW, SH), Image.LANCZOS) for n, im in LAYERS.items()}
OYP = int(oy_dp * X)
BOARD = Image.open(f'{SD}/hub_sign_board.png').convert('RGBA')
BW, BH = 124, 48

# the Evochi: the hero atlas (standing) and the Wilds walk cycle (walking), an Amber Elder in its hat
ch = man['chars']['s03']
_atlas = Image.open(ART + ch['atlas']['amber']['file']).convert('RGBA')
_ov = Image.open(ART + ch['overlays']['file']).convert('RGBA')
_hat = ch['overlays']['rects']['explorer_hat']


def hero(expr):
    r = ch['atlas']['amber']['rects'][ch['expressions'].index(expr)]
    im = _atlas.crop((r[0], r[1], r[0] + r[2], r[1] + r[3]))
    im.alpha_composite(_ov.crop((_hat[0], _hat[1], _hat[0] + _hat[2], _hat[1] + _hat[3])))
    return im


ww = json.load(open(ART + 'wilds/wilds_walk.json'))
wk = ww['walkers']['s03']
_walk = Image.open(ART + 'wilds/' + wk['gaits']['walk']['sheets']['amber']).convert('RGBA')
_wear = Image.open(ART + 'wilds/wear_s03_explorer_hat.webp').convert('RGBA')


def walker(d, f):
    i = ww['dirs'].index(d)
    fw, fh = wk['frameW'], wk['frameH']
    im = _walk.crop(((f + 1) * fw, i * fh, (f + 2) * fw, (i + 1) * fh))
    lift = wk['gaits']['walk']['lift'][f + 1]
    hat = _wear.crop((i * fw, 0, (i + 1) * fw, fh))
    im.alpha_composite(hat, (0, -int(round(lift))))
    return im


PET_UNIT = hab['petPxPerUnit'] * 0.165       # design px per character unit at the nest


def scene(pet='idle', walk=None, glow=None, hop=0.0):
    """The scene (no UI) at 1x camera: layers, nest, signs, the Evochi, near flora."""
    c = Image.new('RGBA', (W, H), (134, 201, 91, 255))
    for n in ('sky', 'far', 'mid'):
        c.alpha_composite(LAYERS[n], (0, OYP))
    d = hab['decor']['meadow_nest@nest']
    nest = Image.open(ART + d['file']).convert('RGBA')
    nw = int(d['w'] * SC)
    nest = nest.resize((nw, int(nest.height * nw / nest.width)), Image.LANCZOS)
    nx, ny = d2p(d['x'], d['y'] + DY)
    c.alpha_composite(nest, (int(nx), int(ny)))
    rects = {}
    for key, label, ic, left in (('home', 'HOME', 'home', True), ('village', 'VILLAGE', 'habitats', False)):
        cx, cy = mp(meta['signs'][key]['top']['px'])
        b = BOARD.resize((BW * X, BH * X), Image.LANCZOS)
        if left:
            b = b.transpose(Image.FLIP_LEFT_RIGHT)
        x0, y0 = int(cx - BW * X / 2), int(cy - BH * X * 0.62)
        if glow == key:
            g = Image.new('RGBA', (W, H), (0, 0, 0, 0))
            gd = ImageDraw.Draw(g)
            gd.rounded_rectangle((x0 - 6 * X, y0 - 6 * X, x0 + (BW + 6) * X, y0 + (BH + 6) * X), radius=14 * X, fill=(255, 210, 90, 210))
            c.alpha_composite(g.filter(ImageFilter.GaussianBlur(7 * X)))
        c.alpha_composite(b, (x0, y0))
        dr = ImageDraw.Draw(c)
        f = font('black', 17 if len(label) < 6 else 15)
        tw = dr.textlength(label, font=f)
        total = 24 * X + 4 * X + tw
        bx0 = x0 + (18 * X if left else 6 * X)
        sx = bx0 + (BW * X - 24 * X - total) / 2
        c.alpha_composite(icon(ic, 24), (int(sx), int(y0 + 12 * X)))
        ty = y0 + BH * X / 2 - 12 * X
        dr.text((sx + 28 * X, ty + X), label, font=f, fill=(255, 232, 196, 180))
        dr.text((sx + 28 * X, ty), label, font=f, fill=SIGN_INK)
        if glow == key:
            dr.rounded_rectangle((x0 - 3 * X, y0 - 3 * X, x0 + (BW + 3) * X, y0 + (BH + 3) * X), radius=12 * X, outline=(255, 214, 90), width=int(3 * X))
            for (sx_, sy_, s_) in ((x0 - 4, y0 - 8, 16), (x0 + BW * X - 10, y0 - 12, 20), (x0 + BW * X * 0.45, y0 + BH * X - 2, 14)):
                c.alpha_composite(icon('star', s_), (int(sx_), int(sy_)))
        rects[key] = (x0, y0, x0 + BW * X, y0 + BH * X)
    # the Evochi
    gpx, gpy = mp(meta['pet'])
    if walk is None:
        im = hero('excited' if hop else ('happy' if pet == 'idle' else pet))
        ps = PET_UNIT / ch['scale'] * SC
        im = im.resize((int(im.width * ps), int(im.height * ps)), Image.LANCZOS)
        ga = ch['anchors']['ground']
        sh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        sw = im.width * (0.28 - 0.08 * hop)
        ImageDraw.Draw(sh).ellipse((gpx - sw, gpy - 9 * X, gpx + sw, gpy + 7 * X), fill=(40, 60, 20, int(70 - 30 * hop)))
        c.alpha_composite(sh.filter(ImageFilter.GaussianBlur(4 * X)))
        c.alpha_composite(im, (int(gpx - ga[0] * ps), int(gpy - ga[1] * ps - hop * 26 * X)))
    else:
        key, t, d = walk                        # along the walk: t in 0..1 over its points
        pts = meta['walks'][key]
        seg = min(int(t * (len(pts) - 1)), len(pts) - 2)
        u = t * (len(pts) - 1) - seg
        a, b = pts[seg], pts[seg + 1]
        px = a['px'][0] + (b['px'][0] - a['px'][0]) * u
        py = a['px'][1] + (b['px'][1] - a['px'][1]) * u
        ppu = a['px_per_unit'] + (b['px_per_unit'] - a['px_per_unit']) * u
        depth = ppu / meta['pet_px_per_unit']
        im = walker(d, 3)
        ws = PET_UNIT / wk['scale'] * SC * depth
        im = im.resize((int(im.width * ws), int(im.height * ws)), Image.LANCZOS)
        x, y = mp((px, py))
        sh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse((x - im.width * 0.22, y - 6 * X * depth, x + im.width * 0.22, y + 5 * X * depth), fill=(40, 60, 20, 70))
        c.alpha_composite(sh.filter(ImageFilter.GaussianBlur(3 * X)))
        c.alpha_composite(im, (int(x - wk['ground'][0] * ws), int(y - wk['ground'][1] * ws)))
    c.alpha_composite(LAYERS['near'], (0, OYP))
    return c, rects


def zoom(img, z, fx, fy):
    """The camera: zoom z about the scene point (fx, fy) px, kept inside the picture."""
    if z == 1:
        return img
    big = img.resize((int(W * z), int(H * z)), Image.LANCZOS)
    x0 = min(max(fx * z - fx, 0), big.width - W)
    y0 = min(max(fy * z - fy, 0), big.height - H)
    return big.crop((int(x0), int(y0), int(x0) + W, int(y0) + H))


def wood(c, box, r, tone='light', border=(74, 42, 20), bw=2.5):
    x0, y0, x1, y1 = [int(v) for v in box]
    tex = Image.open(UI + f'wood_{tone}.png').convert('RGBA').resize((x1 - x0, y1 - y0))
    m = Image.new('L', (x1 - x0, y1 - y0), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, x1 - x0 - 1, y1 - y0 - 1], radius=int(r * X), fill=255)
    c.paste(tex, (x0, y0), m)
    ImageDraw.Draw(c).rounded_rectangle([x0, y0, x1 - 1, y1 - 1], radius=int(r * X), outline=border, width=int(bw * X))


def ui(c, bubble=True, dim=0.0):
    """Header and panel over the scene (the mockup's panel); dim darkens them during a trip."""
    u = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(u)

    def rrect(box, r, fill, outline=None, width=0):
        dr.rounded_rectangle([int(v) for v in box], radius=int(r * X), fill=fill, outline=outline, width=int(width * X))

    wm = Image.open(ART + man['titles']['wordmark_evochi']['file']).convert('RGBA')
    wm = wm.resize((int(40 * X * wm.width / wm.height), 40 * X), Image.LANCZOS)
    hy = (STATUS + 10) * X
    u.alpha_composite(wm, (14 * X, hy))
    py = hy + 50 * X
    pw = dr.textlength('Sunlit Meadow  ›', font=font('xbold', 16)) + 46 * X
    rrect((14 * X, py, 14 * X + pw, py + 36 * X), 10, (255, 246, 224), (201, 167, 140), 1.5)
    u.alpha_composite(icon('pin', 24), (20 * X, py + 6 * X))
    dr.text((48 * X, py + 7 * X), 'Sunlit Meadow  ›', font=font('xbold', 16), fill=INK)
    rx1 = (W_DP - 14) * X
    wood(u, (rx1 - 118 * X, hy, rx1, hy + 36 * X), 18, 'dark', (46, 24, 10), 2)
    u.alpha_composite(icon('coin', 24), (rx1 - 112 * X, hy + 6 * X))
    dr.text((rx1 - 84 * X, hy + 8 * X), '7,028', font=font('black', 15), fill=(255, 255, 255))
    rrect((rx1 - 32 * X, hy + 6 * X, rx1 - 8 * X, hy + 30 * X), 6, (243, 192, 78), (120, 70, 20), 1.5)
    dr.text((rx1 - 25 * X, hy + 3 * X), '+', font=font('black', 19), fill=INK)
    for k, ic in enumerate(('settings', 'mail')):
        by = hy + (46 + k * 56) * X
        wood(u, (rx1 - 46 * X, by, rx1, by + 46 * X), 11, 'light')
        u.alpha_composite(icon(ic, 30), (rx1 - 38 * X, by + 8 * X))
    # panel: steps, Pet/Play/Inspect, Evolution Family; the nav
    L, R = 12 * X, (W_DP - 12) * X
    y = hero_bottom * X
    wood(u, (L, y, R, y + 68 * X), 14, 'light')
    dr.ellipse((L + 10 * X, y + 9 * X, L + 60 * X, y + 59 * X), fill=(255, 244, 220), outline=(107, 63, 30), width=int(2 * X))
    u.alpha_composite(icon('steps', 36), (L + 17 * X, y + 16 * X))
    dr.text((L + 72 * X, y + 8 * X), 'Daily Steps', font=font('bold', 13), fill=SIGN_INK)
    dr.text((L + 72 * X, y + 24 * X), '0 / 7,000 steps', font=font('black', 19), fill=SIGN_INK)
    rrect((L + 72 * X, y + 48 * X, L + 250 * X, y + 60 * X), 6, (60, 40, 25))
    rrect((R - 120 * X, y + 18 * X, R - 10 * X, y + 48 * X), 10, (229, 242, 207), (210, 232, 185), 1.5)
    dr.text((R - 112 * X, y + 24 * X), '+0 XP today!', font=font('xbold', 12), fill=(70, 120, 50))
    y += 76 * X
    bw_ = (R - L - 20 * X) / 3
    for i, (lab, ic, col, edge) in enumerate((('Pet', 'heart', (247, 200, 92), (176, 120, 40)),
                                              ('Play', 'play', (126, 196, 86), (62, 110, 43)),
                                              ('Inspect', 'inspect', (255, 246, 224), (180, 150, 110)))):
        bx = L + i * (bw_ + 10 * X)
        rrect((bx, y + 3 * X, bx + bw_, y + 61 * X), 14, edge)
        rrect((bx, y, bx + bw_, y + 58 * X), 14, col, edge, 2)
        tf = font('black', 17)
        tw = dr.textlength(lab, font=tf)
        sx = bx + (bw_ - (32 * X + tw)) / 2
        u.alpha_composite(icon(ic, 26), (int(sx), y + 16 * X))
        dr.text((sx + 32 * X, y + 16 * X), lab, font=tf, fill=INK)
    y += 66 * X
    eh = (H_DP - NAV - 8) * X - y
    rrect((L, y + 3 * X, R, y + eh + 3 * X), 14, (199, 154, 98))
    rrect((L, y, R, y + eh), 14, (255, 248, 232), (107, 63, 30), 2)
    dr.text((L + 12 * X, y + 8 * X), 'Evolution Family', font=font('xbold', 15), fill=INK)
    dr.text((R - 100 * X, y + 10 * X), 'Grow together!', font=font('bold', 12), fill=(142, 116, 98))
    for i, st in enumerate(('s01', 's02', 's03')):
        c2 = man['chars'][st]
        a2 = Image.open(ART + c2['atlas']['amber']['file']).convert('RGBA')
        r2 = c2['atlas']['amber']['rects'][0]
        sp = a2.crop((r2[0], r2[1], r2[0] + r2[2], r2[1] + r2[3]))
        hh = int(eh - 40 * X)
        sp = sp.resize((int(sp.width * hh / sp.height), hh), Image.LANCZOS)
        cx = L + (R - L) * (i * 2 + 1) / 6
        u.alpha_composite(sp, (int(cx - sp.width / 2), int(y + 30 * X)))
    wood(u, (0, (H_DP - NAV) * X, W, H), 0, 'dark', (46, 24, 10), 2)
    for i, (lab, ic) in enumerate((('Home', 'home'), ('Journey', 'journey'), ('Bag', 'bag'), ('Shop', 'shop'), ('EvoDex', 'evodex'))):
        cx = W * (i * 2 + 1) / 10
        if i == 0:
            rrect((cx - 36 * X, (H_DP - NAV + 8) * X, cx + 36 * X, (H_DP - 10) * X), 12, (255, 236, 200), (120, 80, 40), 2)
        u.alpha_composite(icon(ic, 32), (int(cx - 16 * X), (H_DP - NAV + 12) * X))
        tf = font('xbold', 12)
        dr.text((cx - dr.textlength(lab, font=tf) / 2, (H_DP - NAV + 48) * X), lab, font=tf, fill=INK if i == 0 else (255, 240, 220))
    if dim:
        a = u.split()[3]
        rgb = ImageEnhance.Brightness(u.convert('RGB')).enhance(1 - dim)
        u = Image.merge('RGBA', (*rgb.split(), a))
    c.alpha_composite(u)
    if bubble:
        dr = ImageDraw.Draw(c)
        bt = 'Tap a trail sign to wander.'
        bf = font('bold', 14)
        btw = dr.textlength(bt, font=bf)
        _, gpy = mp(meta['pet'])
        bx0 = (W - btw) / 2 - 12 * X
        by0 = gpy - 196 * X
        dr.rounded_rectangle((bx0, by0, bx0 + btw + 24 * X, by0 + 32 * X), radius=12 * X, fill=(255, 248, 232), outline=(201, 167, 140), width=3)
        dr.polygon([(W / 2 - 8 * X, by0 + 32 * X - 3), (W / 2 + 8 * X, by0 + 32 * X - 3), (W / 2, by0 + 41 * X)], fill=(255, 248, 232))
        dr.text((bx0 + 12 * X, by0 + 6 * X), bt, font=bf, fill=INK)
    return c


def frame(**kw):
    z = kw.pop('z', 1.0)
    focus = kw.pop('focus', None)
    dim = kw.pop('dim', 0.0)
    bubble = kw.pop('bubble', False)
    fade = kw.pop('fade', None)
    c, rects = scene(**kw)
    if z != 1:
        fx, fy = focus
        c = zoom(c, z, fx, fy)
    c = ui(c, bubble=bubble, dim=dim)
    if fade:
        img, amt = fade
        dest = Image.open(ART + img).convert('RGBA')
        dest = dest.resize((W, int(dest.height * W / dest.width)), Image.LANCZOS)
        d2 = Image.new('RGBA', (W, H), (250, 244, 228, 255))
        d2.alpha_composite(dest, (0, max(0, (H - dest.height) // 2 - 80 * X)))
        c = Image.blend(c, d2, amt)
    return c


goal = {k: mp(meta['goals'][k]['px']) for k in ('home', 'village')}
beats = []
for key, d, dest in (('home', 'NW', man['home']['map']['restored'] if STATE == 'restored' else man['home']['map']['ruined']),
                     ('village', 'NE', man['village']['square']['day_dim'])):
    beats.append([
        ('0.0 s  tap', frame(glow=key, dim=0.28)),
        ('0.15 s  hop out', frame(glow=key, dim=0.28, hop=1.0)),
        ('0.6 s  walk + camera', frame(walk=(key, 0.62, d), dim=0.28, z=1.12, focus=goal[key])),
        ('1.1 s  fade in', frame(walk=(key, 0.95, d), dim=0.28, z=1.2, focus=goal[key], fade=(dest, 0.72))),
    ])

# a sheet: the idle screen big on the left, the two rows of beats on the right (cropped to header + scene)
CROP = (0, 0, W, (hero_bottom + 10) * X)
idle = frame(bubble=True)
th = 0.5
cw, chh = int(W * th), int((CROP[3] - CROP[1]) * th)
gut = 24
lab_h = 40
big_w = int(W * 0.62)
big_h = int(H * 0.62)
sheet_w = big_w + gut * 3 + 4 * cw + 3 * gut
sheet_h = max(big_h + 70, 2 * (chh + lab_h) + gut * 3 + 70)
sheet = Image.new('RGB', (sheet_w, sheet_h), (36, 32, 44))
sd = ImageDraw.Draw(sheet)
tf = ImageFont.truetype(FONTS + 'Nunito-Black.ttf', 30)
lf = ImageFont.truetype(FONTS + 'Nunito-ExtraBold.ttf', 20)
sd.text((gut, 18), 'The nest hub: idle', font=tf, fill=(255, 236, 200))
sheet.paste(idle.convert('RGB').resize((big_w, big_h), Image.LANCZOS), (gut, 64))
x0 = big_w + gut * 3
sd.text((x0, 18), 'Tap a sign: about 1.2 s, tap again to skip', font=tf, fill=(255, 236, 200))
for r, (row, name) in enumerate(zip(beats, ('HOME', 'VILLAGE'))):
    y0 = 64 + r * (chh + lab_h + gut)
    for i, (lab, im) in enumerate(row):
        x = x0 + i * (cw + gut)
        sd.text((x, y0), f'{name} · {lab}', font=lf, fill=(255, 214, 120) if i == 0 else (225, 225, 235))
        sheet.paste(im.crop(CROP).convert('RGB').resize((cw, chh), Image.LANCZOS), (x, y0 + lab_h - 8))
sheet.save(OUT, quality=92)
idle.convert('RGB').save(OUT.replace('.', '_idle.', 1))
print(sheet.size)

"""One phone frame of the Blender-lit nest hub (hub_blender.py), composited from the real art at the
game's layout numbers: the render behind, the Evochi (standing, hopping or walking), the sign boards
lettered (one lit, optionally), the header and the panel, a camera zoom and a fade. A picture of the
plan, not the game.
"""
import json

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ART = '/home/claude/evochi/flutter/assets/art/'
UI = '/home/claude/evochi/flutter/assets/ui/'
FONTS = '/home/claude/evochi/flutter/assets/fonts/'
X = 2
W_DP, H_DP = 412, 915
W, H = W_DP * X, H_DP * X
INK, SIGN_INK = (59, 41, 35), (58, 32, 14)
STATUS, HEADER, NAV = 28, 158, 80
man = json.load(open(ART + 'manifest.json'))
_cache = {}


def font(weight, size):
    f = {'black': 'Nunito-Black.ttf', 'xbold': 'Nunito-ExtraBold.ttf', 'bold': 'Nunito-Bold.ttf'}[weight]
    return ImageFont.truetype(FONTS + f, int(size * X))


def icon(name, size):
    return Image.open(ART + man['icons'][name]).convert('RGBA').resize((max(1, int(size * X)), max(1, int(size * X))), Image.LANCZOS)


def img(path):
    if path not in _cache:
        _cache[path] = Image.open(path).convert('RGBA')
    return _cache[path]


class Hub:
    def __init__(self, hub_dir, state, panel='mockup'):
        self.meta = json.load(open(f'{hub_dir}/hub_{state}.json'))
        self.A = self.meta['anchors']
        self.bg_path = f'{hub_dir}/hub_{state}.png'
        self.panel = panel
        self.PANEL = 290 if panel == 'mockup' else 450
        self.hero_top, self.hero_bottom = STATUS + HEADER, H_DP - NAV - self.PANEL
        self.gy = self.hero_bottom - 44
        self.k = W_DP / self.meta['w']
        self.oy = min(0.0, self.gy - self.A['nest'][1] * self.k)
        self.dpu = (self.A['nest_r'][0] - self.A['nest'][0]) * self.k / 5.0
        self.state = state

    def p(self, a):
        return a[0] * self.k * X, (self.oy + a[1] * self.k) * X

    # ---------------------------------------------------------------- the scene
    def scene(self, glow=None, expr='happy', hop=0.0, walk=None):
        c = Image.new('RGBA', (W, H), (134, 181, 102, 255))
        bg = img(self.bg_path)
        bgs = bg.resize((W, int(bg.height * W / bg.width)), Image.LANCZOS)
        c.alpha_composite(bgs, (0, int(self.oy * X)))
        A = self.A
        for key, label, ic, left in (('home', 'HOME', 'home', True), ('village', 'VILLAGE', 'habitats', False)):
            l, r = self.p(A[f'sign_{key}_l']), self.p(A[f'sign_{key}_r'])
            t, b = self.p(A[f'sign_{key}_t']), self.p(A[f'sign_{key}_b'])
            x0, x1, y0, y1 = min(l[0], r[0]), max(l[0], r[0]), t[1], b[1]
            bh = y1 - y0
            if glow == key:
                g = Image.new('RGBA', (W, H), (0, 0, 0, 0))
                ImageDraw.Draw(g).rounded_rectangle((x0 - 8 * X, y0 - 8 * X, x1 + 8 * X, y1 + 8 * X), radius=14 * X, fill=(255, 205, 80, 235))
                c.alpha_composite(g.filter(ImageFilter.GaussianBlur(9 * X)))
                c.alpha_composite(bgs.crop((int(x0), int(y0 - self.oy * X), int(x1), int(y1 - self.oy * X))), (int(x0), int(y0)))
            tipw = (x1 - x0) * 1.8 / 8.4
            sx0, sx1 = (x0 + tipw, x1) if left else (x0, x1 - tipw)
            d = ImageDraw.Draw(c)
            fs = bh / X * (0.40 if len(label) < 6 else 0.36)
            f = font('black', fs)
            tw = d.textlength(label, font=f)
            isz = bh / X * 0.62
            tx = sx0 + (sx1 - sx0 - (isz * X + 4 * X + tw)) / 2
            c.alpha_composite(icon(ic, isz), (int(tx), int(y0 + (bh - isz * X) / 2)))
            ty = y0 + bh / 2 - fs * X * 0.62
            d.text((tx + isz * X + 4 * X, ty + X), label, font=f, fill=(255, 236, 205))
            d.text((tx + isz * X + 4 * X, ty), label, font=f, fill=SIGN_INK)
            if glow == key:
                d.rounded_rectangle((x0 - 3 * X, y0 - 3 * X, x1 + 3 * X, y1 + 3 * X), radius=10 * X, outline=(255, 222, 110), width=int(2.5 * X))
                for (sx_, sy_, s_) in ((x0 - 6 * X, y0 - 10 * X, 16), (x1 - 8 * X, y0 - 14 * X, 20), ((x0 + x1) / 2, y1 - 4 * X, 14)):
                    c.alpha_composite(icon('star', s_), (int(sx_), int(sy_)))
        ch = man['chars']['s03']
        gx, gy = self.p(A['nest'])
        if walk is None:
            atlas = img(ART + ch['atlas']['amber']['file'])
            rr = ch['atlas']['amber']['rects'][ch['expressions'].index('excited' if hop else expr)]
            pet = atlas.crop((rr[0], rr[1], rr[0] + rr[2], rr[1] + rr[3]))
            ov = img(ART + ch['overlays']['file'])
            hr = ch['overlays']['rects']['explorer_hat']
            pet.alpha_composite(ov.crop((hr[0], hr[1], hr[0] + hr[2], hr[1] + hr[3])))
            ps = self.dpu * 0.165 / ch['scale'] * X
            pet = pet.resize((int(pet.width * ps), int(pet.height * ps)), Image.LANCZOS)
            ga = ch['anchors']['ground']
            sh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
            sw = pet.width * (0.27 - 0.08 * hop)
            ImageDraw.Draw(sh).ellipse((gx - sw, gy - 8 * X, gx + sw, gy + 7 * X), fill=(50, 40, 20, int(80 - 35 * hop)))
            c.alpha_composite(sh.filter(ImageFilter.GaussianBlur(4 * X)))
            c.alpha_composite(pet, (int(gx - ga[0] * ps), int(gy - ga[1] * ps - hop * 24 * X)))
            self.pet_top = gy - ga[1] * ps + pet.getbbox()[1]
        else:
            key, t, dname = walk
            ww = json.load(open(ART + 'wilds/wilds_walk.json'))
            wk = ww['walkers']['s03']
            pts = [(A[f'walk_{key}_{i}'], A[f'walk_{key}_{i}_u']) for i in range(4)]
            seg = min(int(t * 3), 2)
            u = t * 3 - seg
            (a, au), (b, bu) = pts[seg], pts[seg + 1]
            px = a[0] + (b[0] - a[0]) * u
            py = a[1] + (b[1] - a[1]) * u
            ppu = (au[0] - a[0]) + ((bu[0] - b[0]) - (au[0] - a[0])) * u
            depth = ppu * self.k / self.dpu
            di = ww['dirs'].index(dname)
            fw, fh = wk['frameW'], wk['frameH']
            sheet = img(ART + 'wilds/' + wk['gaits']['walk']['sheets']['amber'])
            im = sheet.crop((4 * fw, di * fh, 5 * fw, (di + 1) * fh))
            hat = img(ART + 'wilds/wear_s03_explorer_hat.webp').crop((di * fw, 0, (di + 1) * fw, fh))
            im.alpha_composite(hat, (0, -4))
            ws = self.dpu * 0.165 / wk['scale'] * X * depth
            im = im.resize((int(im.width * ws), int(im.height * ws)), Image.LANCZOS)
            x, y = self.p((px, py))
            sh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
            ImageDraw.Draw(sh).ellipse((x - im.width * 0.2, y - 5 * X, x + im.width * 0.2, y + 4 * X), fill=(50, 40, 20, 80))
            c.alpha_composite(sh.filter(ImageFilter.GaussianBlur(3 * X)))
            c.alpha_composite(im, (int(x - wk['ground'][0] * ws), int(y - wk['ground'][1] * ws)))
            self.pet_top = y - 60 * X
        return c

    # ---------------------------------------------------------------- the UI
    def ui(self, c, dim=0.0, bubble=False):
        u = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        dr = ImageDraw.Draw(u)

        def rrect(box, r, fill, outline=None, width=0):
            dr.rounded_rectangle([int(v) for v in box], radius=int(r * X), fill=fill, outline=outline, width=int(width * X))

        def wood(box, r, tone='light', border=(74, 42, 20), bw=2.5):
            x0, y0, x1, y1 = [int(v) for v in box]
            tex = img(UI + f'wood_{tone}.png').resize((x1 - x0, y1 - y0))
            m = Image.new('L', (x1 - x0, y1 - y0), 0)
            ImageDraw.Draw(m).rounded_rectangle([0, 0, x1 - x0 - 1, y1 - y0 - 1], radius=int(r * X), fill=255)
            u.paste(tex, (x0, y0), m)
            dr.rounded_rectangle([x0, y0, x1 - 1, y1 - 1], radius=int(r * X), outline=border, width=int(bw * X))

        wm = img(ART + man['titles']['wordmark_evochi']['file'])
        wm = wm.resize((int(40 * X * wm.width / wm.height), 40 * X), Image.LANCZOS)
        hy = (STATUS + 10) * X
        u.alpha_composite(wm, (14 * X, hy))
        py = hy + 50 * X
        pw = dr.textlength('Sunlit Meadow  ›', font=font('xbold', 16)) + 46 * X
        rrect((14 * X, py, 14 * X + pw, py + 36 * X), 10, (255, 246, 224), (201, 167, 140), 1.5)
        u.alpha_composite(icon('pin', 24), (20 * X, py + 6 * X))
        dr.text((48 * X, py + 7 * X), 'Sunlit Meadow  ›', font=font('xbold', 16), fill=INK)
        rx1 = (W_DP - 14) * X
        wood((rx1 - 118 * X, hy, rx1, hy + 36 * X), 18, 'dark', (46, 24, 10), 2)
        u.alpha_composite(icon('coin', 24), (rx1 - 112 * X, hy + 6 * X))
        dr.text((rx1 - 84 * X, hy + 8 * X), '7,028', font=font('black', 15), fill=(255, 255, 255))
        rrect((rx1 - 32 * X, hy + 6 * X, rx1 - 8 * X, hy + 30 * X), 6, (243, 192, 78), (120, 70, 20), 1.5)
        dr.text((rx1 - 25 * X, hy + 3 * X), '+', font=font('black', 19), fill=INK)
        for i, ic in enumerate(('settings', 'mail')):
            by = hy + (46 + i * 56) * X
            wood((rx1 - 46 * X, by, rx1, by + 46 * X), 11, 'light')
            u.alpha_composite(icon(ic, 30), (rx1 - 38 * X, by + 8 * X))
        L, R = 12 * X, (W_DP - 12) * X
        y = self.hero_bottom * X
        if self.panel != 'mockup':
            rrect((L, y, R, y + 36 * X), 12, (229, 242, 207), (150, 190, 120), 1.5)
            u.alpha_composite(icon('discover', 24), (L + 8 * X, y + 6 * X))
            dr.text((L + 40 * X, y + 8 * X), "Today's discovery: a glint by the old bridge", font=font('xbold', 13), fill=INK)
            y += 44 * X
            rrect((L, y + 3 * X, R, y + 99 * X), 14, (199, 154, 98))
            rrect((L, y, R, y + 96 * X), 14, (255, 248, 232), (107, 63, 30), 2)
            dr.text((L + 14 * X, y + 10 * X), 'Mochi', font=font('black', 28), fill=INK)
            mx = L + 200 * X
            dr.text((mx, y + 10 * X), 'Lv. 24', font=font('black', 22), fill=INK)
            rrect((mx, y + 44 * X, R - 14 * X, y + 56 * X), 6, (240, 225, 200), (180, 140, 100), 1)
            rrect((mx, y + 44 * X, mx + 80 * X, y + 56 * X), 6, (243, 192, 78))
            y += 104 * X
        wood((L, y, R, y + 68 * X), 14, 'light')
        dr.ellipse((L + 10 * X, y + 9 * X, L + 60 * X, y + 59 * X), fill=(255, 244, 220), outline=(107, 63, 30), width=int(2 * X))
        u.alpha_composite(icon('steps', 36), (L + 17 * X, y + 16 * X))
        dr.text((L + 72 * X, y + 8 * X), 'Daily Steps', font=font('bold', 13), fill=SIGN_INK)
        dr.text((L + 72 * X, y + 24 * X), '0 / 7,000 steps', font=font('black', 19), fill=SIGN_INK)
        rrect((L + 72 * X, y + 48 * X, L + 250 * X, y + 60 * X), 6, (60, 40, 25))
        rrect((R - 120 * X, y + 18 * X, R - 10 * X, y + 48 * X), 10, (229, 242, 207), (210, 232, 185), 1.5)
        dr.text((R - 112 * X, y + 24 * X), '+0 XP today!', font=font('xbold', 12), fill=(70, 120, 50))
        y += 76 * X
        bw3 = (R - L - 20 * X) / 3
        for i, (lab, ic, col, edge) in enumerate((('Pet', 'heart', (247, 200, 92), (176, 120, 40)),
                                                  ('Play', 'play', (126, 196, 86), (62, 110, 43)),
                                                  ('Inspect', 'inspect', (255, 246, 224), (180, 150, 110)))):
            bx = L + i * (bw3 + 10 * X)
            rrect((bx, y + 3 * X, bx + bw3, y + 61 * X), 14, edge)
            rrect((bx, y, bx + bw3, y + 58 * X), 14, col, edge, 2)
            tf = font('black', 17)
            tw = dr.textlength(lab, font=tf)
            sx = bx + (bw3 - (32 * X + tw)) / 2
            u.alpha_composite(icon(ic, 26), (int(sx), y + 16 * X))
            dr.text((sx + 32 * X, y + 16 * X), lab, font=tf, fill=INK)
        y += 66 * X
        eh = min((H_DP - NAV - 8) * X - y, 132 * X)
        rrect((L, y + 3 * X, R, y + eh + 3 * X), 14, (199, 154, 98))
        rrect((L, y, R, y + eh), 14, (255, 248, 232), (107, 63, 30), 2)
        dr.text((L + 12 * X, y + 8 * X), 'Evolution Family', font=font('xbold', 15), fill=INK)
        dr.text((R - 100 * X, y + 10 * X), 'Grow together!', font=font('bold', 12), fill=(142, 116, 98))
        for i, st in enumerate(('s01', 's02', 's03')):
            c2 = man['chars'][st]
            a2 = img(ART + c2['atlas']['amber']['file'])
            r2 = c2['atlas']['amber']['rects'][0]
            sp = a2.crop((r2[0], r2[1], r2[0] + r2[2], r2[1] + r2[3]))
            hh = int(min(eh - 40 * X, 80 * X))
            sp = sp.resize((int(sp.width * hh / sp.height), hh), Image.LANCZOS)
            cx = L + (R - L) * (i * 2 + 1) / 6
            u.alpha_composite(sp, (int(cx - sp.width / 2), int(y + 30 * X)))
        wood((0, (H_DP - NAV) * X, W, H), 0, 'dark', (46, 24, 10), 2)
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
            d = ImageDraw.Draw(c)
            bt = 'Tap a trail sign to wander.'
            bf = font('bold', 14)
            btw = d.textlength(bt, font=bf)
            bx0 = (W - btw) / 2 - 12 * X
            by0 = max(self.pet_top - 46 * X, (self.hero_top + 4) * X)
            d.rounded_rectangle((bx0, by0, bx0 + btw + 24 * X, by0 + 32 * X), radius=12 * X, fill=(255, 248, 232), outline=(201, 167, 140), width=3)
            d.polygon([(W / 2 - 8 * X, by0 + 32 * X - 3), (W / 2 + 8 * X, by0 + 32 * X - 3), (W / 2, by0 + 41 * X)], fill=(255, 248, 232))
            d.text((bx0 + 12 * X, by0 + 6 * X), bt, font=bf, fill=INK)
        return c

    def frame(self, glow=None, dim=0.0, bubble=False, expr='happy', hop=0.0, walk=None, zoom=1.0, focus=None, fade=None):
        c = self.scene(glow=glow, expr=expr, hop=hop, walk=walk)
        if zoom != 1.0:
            fx, fy = self.p(self.A[focus])
            big = c.resize((int(W * zoom), int(H * zoom)), Image.LANCZOS)
            x0 = min(max(fx * zoom - fx, 0), big.width - W)
            y0 = min(max(fy * zoom - fy, 0), big.height - H)
            c = big.crop((int(x0), int(y0), int(x0) + W, int(y0) + H))
        c = self.ui(c, dim=dim, bubble=bubble)
        if fade:
            dest, amt = fade
            dimg = img(ART + dest)
            dimg = dimg.resize((W, int(dimg.height * W / dimg.width)), Image.LANCZOS)
            d2 = Image.new('RGBA', (W, H), (250, 244, 228, 255))
            d2.alpha_composite(dimg, (0, max(0, (H - dimg.height) // 2 - 80 * X)))
            c = Image.blend(c, d2, amt)
        return c

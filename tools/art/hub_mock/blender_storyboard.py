"""The nest hub storyboard (Blender-lit): the idle screen, and a tap on each sign beat by beat.

    python3 blender_storyboard.py HUB_DIR STATE OUT.jpg [--panel mockup|today]
"""
import sys

from PIL import Image, ImageDraw, ImageFont

from hubframe import Hub, W, H, X, man, FONTS

HD, STATE, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
panel = sys.argv[sys.argv.index('--panel') + 1] if '--panel' in sys.argv else 'mockup'
hub = Hub(HD, STATE, panel)
idle = hub.frame(bubble=True)
idle.convert('RGB').save(OUT.replace('.', '_idle.', 1), quality=92)
rows = []
for key, d, dest in (('home', 'NW', man['home']['map'][STATE]), ('village', 'NE', man['village']['square']['day_dim'])):
    rows.append([
        ('0.0 s  tap', hub.frame(glow=key, dim=0.28)),
        ('0.15 s  hop out', hub.frame(glow=key, dim=0.28, hop=1.0)),
        ('0.6 s  walk + camera', hub.frame(walk=(key, 0.7, d), dim=0.28, zoom=1.12, focus=f'goal_{key}')),
        ('1.1 s  fade in', hub.frame(walk=(key, 1.0, d), dim=0.28, zoom=1.2, focus=f'goal_{key}', fade=(dest, 0.72))),
    ])
crop = (0, 0, W, (hub.hero_bottom + 10) * X)
th = 0.5
cw, chh = int(W * th), int((crop[3] - crop[1]) * th)
gut, lab_h = 24, 40
bw, bh = int(W * 0.62), int(H * 0.62)
sw = bw + gut * 3 + 4 * cw + 3 * gut
sh = max(bh + 70, 2 * (chh + lab_h) + gut * 3 + 70)
sheet = Image.new('RGB', (sw, sh), (36, 32, 44))
sd = ImageDraw.Draw(sheet)
tf = ImageFont.truetype(FONTS + 'Nunito-Black.ttf', 30)
lf = ImageFont.truetype(FONTS + 'Nunito-ExtraBold.ttf', 20)
sd.text((gut, 18), 'The nest hub', font=tf, fill=(255, 236, 200))
sheet.paste(idle.convert('RGB').resize((bw, bh), Image.LANCZOS), (gut, 64))
x0 = bw + gut * 3
sd.text((x0, 18), 'Tap a sign: about 1.2 s, tap again to skip', font=tf, fill=(255, 236, 200))
for r, (row, name) in enumerate(zip(rows, ('HOME', 'VILLAGE'))):
    y0 = 64 + r * (chh + lab_h + gut)
    for i, (lab, im) in enumerate(row):
        x = x0 + i * (cw + gut)
        sd.text((x, y0), f'{name} · {lab}', font=lf, fill=(255, 214, 120) if i == 0 else (225, 225, 235))
        sheet.paste(im.crop(crop).convert('RGB').resize((cw, chh), Image.LANCZOS), (x, y0 + lab_h - 8))
sheet.save(OUT, quality=90)
print(sheet.size)

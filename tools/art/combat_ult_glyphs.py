# Two of the pack's Elder ultimates carry a symbol that isn't their move: coral's flame (its move is Reef Bloom) and
# obsidian's shield (Quake). This lifts the old symbol off the face (the face refitted as a smooth gradient) and
# draws a coral branch and a cracked slab in the pack's own line style (a cream outline round a tinted fill).
#   python3 tools/art/combat_ult_glyphs.py <dir of cleaned webp>   (after combat_buttons_clean.py)
# reads spark_burst_<state>.webp / stone_guard_<state>.webp, writes reef_bloom_<state>.webp / quake_<state>.webp
import os, sys
import numpy as np
from PIL import Image, ImageDraw

K = 4  # drawn at 4x, then down
CREAM = (246, 240, 226, 255)


def face_fit(im):
    """the face without its symbol: the ring round the symbol carried smoothly inward (a harmonic fill, coarse
    then fine, so it can't overshoot)"""
    from scipy import ndimage as nd
    yy, xx = np.mgrid[0:256, 0:256].astype(float)
    d = np.hypot(xx - 127.5, yy - 127.5)
    hole = d < 50
    out = im.copy()
    small = np.array(Image.fromarray(im.clip(0, 255).astype(np.uint8)).resize((64, 64), Image.BOX)).astype(float)
    sh = np.array(Image.fromarray(hole.astype(np.uint8) * 255).resize((64, 64), Image.NEAREST)) > 0
    for _ in range(1500):
        small[sh] = nd.uniform_filter(small, (3, 3, 1))[sh]
    up = np.array(Image.fromarray(small.clip(0, 255).astype(np.uint8)).resize((256, 256), Image.BICUBIC)).astype(float)
    out[hole] = up[hole]
    for _ in range(300):
        out[hole] = nd.uniform_filter(out, (3, 3, 1))[hole]
    w = np.clip((52 - d) / 4, 0, 1)[..., None]  # a soft seam
    return im * (1 - w) + out * w


def strokes(draw, lines, dots, width, grow):
    for pts in lines:
        p = [(x * K, y * K) for x, y in pts]
        draw.line(p, fill=255, width=int((width + 2 * grow) * K), joint='curve')
        for x, y in p:
            r = (width / 2 + grow) * K
            draw.ellipse((x - r, y - r, x + r, y + r), fill=255)
    for x, y, r in dots:
        r = (r + grow) * K
        draw.ellipse((x * K - r, y * K - r, x * K + r, y * K + r), fill=255)


def reef(grow, draw):
    lines = [
        [(128, 166), (128, 140), (125, 116), (129, 98)],
        [(128, 147), (114, 132), (106, 112)],
        [(114, 132), (100, 126)],
        [(127, 128), (145, 118), (151, 100)],
        [(145, 118), (159, 113)],
    ]
    dots = [(129, 97, 5.5), (106, 111, 5.5), (99, 126, 5), (151, 99, 5.5), (160, 113, 5)]
    strokes(draw, lines, dots, 9, grow * 0.8)
    # its rock
    draw.rounded_rectangle(((110 - grow) * K, (160 - grow) * K, (146 + grow) * K, (171 + grow) * K), radius=(5 + grow) * K, fill=255)


def reef_extra(od):
    # two bubbles rising
    for x, y, r in ((163, 94, 3.6), (157, 82, 2.6)):
        od.ellipse(((x - r) * K, (y - r) * K, (x + r) * K, (y + r) * K), outline=CREAM, width=int(2.2 * K))


def poly(draw, pts, grow):
    p = [(x * K, y * K) for x, y in pts]
    draw.polygon(p, fill=255)
    if grow:
        draw.line(p + [p[0]], fill=255, width=int(2 * grow * K), joint='curve')
        for x, y in p:
            r = grow * K
            draw.ellipse((x - r, y - r, x + r, y + r), fill=255)


Z = [(126, 146), (120, 154), (128, 160), (122, 170)]  # the crack


def quake(grow, draw):
    # the ground split in two, the right side heaved up and tilted, and stones thrown
    poly(draw, [(88, 150)] + [(x - 3, y) for x, y in Z] + [(84, 170)], grow)
    poly(draw, [(x + 3, y - 5) for x, y in Z] + [(172, 162), (166, 141)], grow)
    for cx, cy, sz in ((104, 126, 8), (150, 113, 10), (127, 102, 5.5)):
        pts = [(cx - sz, cy - sz * 0.2), (cx - sz * 0.3, cy - sz), (cx + sz * 0.7, cy - sz * 0.7), (cx + sz, cy + sz * 0.2), (cx + sz * 0.2, cy + sz * 0.9), (cx - sz * 0.8, cy + sz * 0.6)]
        poly(draw, pts, grow)


def quake_extra(od, dark):
    # the jolt either side
    for sx in (-1, 1):
        for r, a in ((9, 0.9), (15, 0.6)):
            cx = 128 + sx * 44
            box = ((cx - r) * K, (157 - r) * K, (cx + r) * K, (157 + r) * K)
            start, end = (150, 210) if sx < 0 else (-30, 30)
            od.arc(box, start, end, fill=CREAM[:3] + (int(255 * a),), width=int(2.4 * K))


def glyph(kind, top, bottom, face_dark):
    n = 256 * K
    outer = Image.new('L', (n, n), 0)
    inner = Image.new('L', (n, n), 0)
    shape = reef if kind == 'reef' else quake
    shape(2.8, ImageDraw.Draw(outer))
    shape(0.0, ImageDraw.Draw(inner))
    g = np.clip((np.arange(n) / K - 92) / 80, 0, 1)[:, None, None]  # top to bottom of the symbol
    fill = (np.array(top)[None, None] * (1 - g) + np.array(bottom)[None, None] * g).repeat(n, 1)
    img = np.zeros((n, n, 4))
    img[..., :3] = np.where(np.array(inner)[..., None] > 0, fill, np.array(CREAM[:3]))
    img[..., 3] = np.array(outer)
    out = Image.fromarray(img.astype(np.uint8), 'RGBA')
    od = ImageDraw.Draw(out)
    if kind == 'reef':
        reef_extra(od)
    else:
        quake_extra(od, tuple(int(v) for v in face_dark) + (255,))
    return out.resize((256, 256), Image.LANCZOS)


JOBS = {
    'spark_burst': ('reef_bloom', 'reef', (255, 196, 168), (232, 84, 58)),
    'stone_guard': ('quake', 'quake', (214, 206, 192), (118, 110, 100)),
}

if __name__ == '__main__':
    d = sys.argv[1]
    for src, (dst, kind, top, bottom) in JOBS.items():
        for st in ('normal', 'ready', 'pressed', 'disabled'):
            im = np.array(Image.open(os.path.join(d, f'{src}_{st}.webp')).convert('RGBA')).astype(float)
            im[..., :3] = face_fit(im[..., :3])
            dark = np.clip(np.median(im[118:138, 118:138, :3].reshape(-1, 3), 0) * 0.55, 0, 255)
            gl = glyph(kind, top, bottom, dark)
            if st == 'pressed':  # its art is a little smaller and lit
                gl = gl.resize((244, 244), Image.LANCZOS)
                pad = Image.new('RGBA', (256, 256)); pad.alpha_composite(gl, (6, 6)); gl = pad
            if st == 'disabled':  # grey, and faint, like the pack's own
                a = np.array(gl).astype(float)
                lum = a[..., :3].mean(-1, keepdims=True)
                a[..., :3] = lum * 0.85
                a[..., 3] *= 0.5
                gl = Image.fromarray(a.astype(np.uint8), 'RGBA')
            base = Image.fromarray(im.clip(0, 255).astype(np.uint8), 'RGBA')
            base.alpha_composite(gl)
            base.save(os.path.join(d, f'{dst}_{st}.webp'), 'WEBP', quality=90, method=6, alpha_quality=95)

# The Gilded crops (a Golden harvest's keepsake): each crop's item icon turned to gold (its shading kept, mapped
# onto a gold ramp), a soft warm glow behind it and three little glints.
#   python3 tools/art/gilded_crops.py flutter
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

CROPS = {'sunberry': 'gilded_sunberry', 'meadow_carrot': 'gilded_carrot', 'golden_wheat': 'gilded_wheat',
         'glowleaf': 'gilded_glowleaf', 'moonshroom': 'gilded_moonshroom'}
RAMP = np.array([(70, 36, 8), (156, 96, 18), (222, 162, 38), (250, 208, 80), (255, 238, 160), (255, 252, 228)], float)


def gild(im):
    a = np.array(im.convert('RGBA')).astype(float)
    rgb, al = a[..., :3], a[..., 3:]
    lum = (rgb @ [0.3, 0.55, 0.15]) / 255
    lo, hi = np.percentile(lum[al[..., 0] > 40], [3, 97])
    t = np.clip((lum - lo) / max(1e-3, hi - lo), 0, 1) * (len(RAMP) - 1)
    i = np.clip(t.astype(int), 0, len(RAMP) - 2)
    f = (t - i)[..., None]
    gold = RAMP[i] * (1 - f) + RAMP[i + 1] * f
    out = np.concatenate([gold * 0.88 + rgb * 0.12, al], -1)
    return Image.fromarray(out.clip(0, 255).astype(np.uint8), 'RGBA')


def glints(size, k=4):
    n = size * k
    g = Image.new('RGBA', (n, n))
    d = ImageDraw.Draw(g)
    for fx, fy, r in ((0.78, 0.2, 0.075), (0.2, 0.32, 0.05), (0.7, 0.74, 0.04)):
        cx, cy, rr = fx * n, fy * n, r * n
        w = rr * 0.22
        d.polygon([(cx, cy - rr), (cx + w, cy - w), (cx + rr, cy), (cx + w, cy + w), (cx, cy + rr), (cx - w, cy + w), (cx - rr, cy), (cx - w, cy - w)], fill=(255, 253, 236, 255))
    return g.resize((size, size), Image.LANCZOS)


if __name__ == '__main__':
    game = sys.argv[1]
    items = os.path.join(game, 'assets', 'art', 'items')
    mp = os.path.join(game, 'assets', 'art', 'manifest.json')
    man = json.load(open(mp))
    for crop, gid in CROPS.items():
        src = Image.open(os.path.join(items, crop + '.webp')).convert('RGBA')
        g = gild(src)
        glow = Image.new('RGBA', src.size, (255, 214, 90, 0))
        glow.putalpha(src.getchannel('A').filter(ImageFilter.GaussianBlur(src.width * 0.05)).point(lambda v: int(v * 0.55)))
        out = Image.new('RGBA', src.size)
        out.alpha_composite(glow)
        out.alpha_composite(g)
        out.alpha_composite(glints(src.width))
        out.save(os.path.join(items, gid + '.webp'), 'WEBP', quality=88, method=6)
        man['items'][gid] = 'items/' + gid + '.webp'
    json.dump(man, open(mp, 'w'), indent=1)

"""Living scenes: bake each scene image's effect mask and emitters for the Flutter client.

The art is pre-rendered, so the motion is layered on at runtime (flutter/shaders/scene_fx.frag and
lib/features/shared/live_scene.dart). This script says where each effect goes:

* A mask image, the same size as the scene, read by the shader (nearest texel):
    R  sway:  how far the pixel moves, 0-255, feathered at the edges so nothing tears. How it moves
              comes from B: smoke wavers as it rises, cloth ripples, anything else is foliage (sways
              in gusts and its leaves shimmer).
    G  surface: 255 falling water (streaks run down), 128 still water (ripples and glints),
              64 grass (a faint fine shimmer, no movement)
    B  kind:  255 fire (flickers), 200 crystal (slow pulse), 128 lamp or window (breathes),
              80 cloth, 40 smoke
* Emitters, drawn over the scene by a painter: glows, embers, smoke and steam, bubbles, motes
  (dust, pollen, fireflies, sparks) and drifting leaves.

Zones live in tools/art/fx_zones/*.py, one module per area, each with a SCENES dict:

    SCENES = {
        'village/square_lamp_lit.webp': {
            'fx': [
                # (effect, shape, key): shape is [x0, y0, x1, y1] or a polygon [(x, y), ...]
                # key picks the pixels inside the shape (see KEYS); later entries win
                ('tree', [0, 120, 240, 330], 'green'),
                ('fall', [118, 0, 182, 58], 'all'),
                ('none', [240, 80, 540, 300], 'all'),   # clears every channel in the shape
            ],
            'emit': [
                {'t': 'glow', 'x': 690, 'y': 485, 'r': 60, 'c': '#ffc66b', 'kind': 'lamp'},
                {'t': 'smoke', 'x': 712, 'y': 250, 'n': 6, 's': 14, 'h': 170, 'drift': 40},
            ],
            'also': ['village/square_day_dim.webp'],  # optional: the same zones on other variants
            'wind': 2.6,  # optional: how hard the wind blows (1 = a breezy day; for a plate seen small, as in
                          # the cold open's wide shots, more, so the sway still reads)
        },
    }

Effects: tree, blades, grass, cloth, smoke, fall, still, fire, crystal, lamp, and none (clears).
A 4th element can tune the sway: {'amp': 0.5} (0-1, default per effect), {'fade': 0.2} (the
bottom of the shape moves this much of the top: blades and stems are rooted) and {'halo': 8} (the sway
reaches that many px past what the key picked, so an outline moves, not only what is inside it).
Keys: all, green, water, waterfall, fire, warm (lit window glass), white, pale, smoky, crystal,
bright, cloth.

How the client plays them (scene_fx.frag): foliage sways up to ~2 image px at full R, in gusts,
and its leaves shimmer; grass gets a faint fine shimmer (no movement); still water ripples
under a px and glints; falling water gets bright streaks running down; fire flickers ±25%
brightness, lamps breathe ±12%, crystals pulse ±25%; smoke wavers up to ~3 px, more as it rises;
cloth ripples ~2 px.

Emitters (all coordinates and sizes in image px; c is '#rrggbb'):
    glow     x, y, r, c, a (peak alpha, default 0.5), kind: fire | lamp | crystal | sun
             a soft additive light; fire flickers fast, lamp breathes, crystal pulses, sun drifts
    embers   x, y, w (source width), h (how high they rise), n (alive at once), c, s (size)
    smoke    x, y, n, s (start size), h (rise), drift (px sideways by the top, + is right), c, a,
             kind: smoke (default) | steam (whiter, quicker, fades sooner)
    bubbles  x, y (centre of the liquid), w, h (half sizes of its surface), n, c
    motes    x, y, w, h (a box), n, c, s, kind: dust (slow, twinkles in light) | pollen (drifts on
             the wind) | firefly (wanders, pulses) | spark (magic glints that twinkle in place)
    leaves   x, y, w, h (the band they blow across), n, c (optional list of colours)

Coordinates are the image's own pixels. Run:

    python3 tools/art/scene_fx.py            # writes flutter/assets/art/fx/*.webp + assets/config/scene_fx.json
    python3 tools/art/scene_fx.py --preview DIR   # also writes colourised previews to DIR

Concept art not in the game yet keeps its zones elsewhere; bake it into a copy of the json:

    python3 tools/art/scene_fx.py --zones tools/art/village_mock/fx_village_walk.py --json OUT.json village/walk_falls.webp
"""
import importlib.util
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ART = os.path.join(ROOT, 'flutter', 'assets', 'art')
OUT_DIR = os.path.join(ART, 'fx')
OUT_JSON = os.path.join(ROOT, 'flutter', 'assets', 'config', 'scene_fx.json')
ZONES = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fx_zones')

# effect -> (G value, B value, sway amplitude 0-1); None leaves that channel alone
EFFECTS = {
    'tree': (None, 0, 1.0),      # canopies: sway + leaf shimmer
    'blades': (64, 0, 0.75),     # big foreground grass and flowers: sway + gust waves
    'grass': (64, None, None),   # ground grass: a faint shimmer only
    'cloth': (None, 80, 0.8),
    'smoke': (None, 40, 1.0),
    'fall': (255, None, None),
    'still': (128, None, None),
    'fire': (None, 255, None),
    'crystal': (None, 200, None),
    'lamp': (None, 128, None),
}
SWAY_FEATHER = 4.0  # px: the sway amplitude fades out past a shape's edge instead of stopping dead
EMITTERS = {'glow', 'embers', 'smoke', 'bubbles', 'motes', 'leaves'}


def _hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    v = mx / 255.0
    s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0)
    return s, v


def _green(rgb, a):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    s, v = _hsv(rgb)
    return (g > r * 1.04) & (g > b * 1.08) & (s > 0.18) & (v > 0.12)


def _water(rgb, a):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    s, v = _hsv(rgb)
    return (b > r + 18) & (b >= g - 12) & (v > 0.3)


def _waterfall(rgb, a):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    s, v = _hsv(rgb)
    return ((b >= r) & (v > 0.5)) | ((s < 0.12) & (v > 0.78))


def _fire(rgb, a):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    s, v = _hsv(rgb)
    return (r > 170) & (r > b + 70) & (g > 60) & (v > 0.62)


def _warm(rgb, a):
    # lit window glass: bright and properly yellow (sunlit plaster is paler and is left out)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    s, v = _hsv(rgb)
    return (r > 190) & (g > 130) & (b < r - 60) & (s > 0.38) & (v > 0.8)


def _white(rgb, a):
    s, v = _hsv(rgb)
    return (s < 0.16) & (v > 0.72)


def _pale(rgb, a):
    # smoke and foam under any light: washed out and light
    s, v = _hsv(rgb)
    return (s < 0.32) & (v > 0.6)


def _smoky(rgb, a):
    # smoke at dusk too: greyish, not too dark (saturated foliage behind it is left out)
    s, v = _hsv(rgb)
    return (s < 0.3) & (v > 0.42)


def _crystal(rgb, a):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    s, v = _hsv(rgb)
    return (b > 150) & (r > g + 15) & (b > g + 30) & (v > 0.45)


def _bright(rgb, a):
    s, v = _hsv(rgb)
    return v > 0.8


def _cloth(rgb, a):
    s, v = _hsv(rgb)
    return (s > 0.3) & (v > 0.3)


KEYS = {
    'all': lambda rgb, a: np.ones(rgb.shape[:2], bool),
    'green': _green, 'water': _water, 'waterfall': _waterfall, 'fire': _fire, 'warm': _warm,
    'white': _white, 'pale': _pale, 'smoky': _smoky, 'crystal': _crystal, 'bright': _bright, 'cloth': _cloth,
}


def _shape_mask(shape, w, h):
    """[x0, y0, x1, y1], ('e', cx, cy, rx, ry) for an ellipse, or a polygon [(x, y), ...]."""
    m = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(m)
    if shape and shape[0] == 'e':
        _, cx, cy, rx, ry = shape
        d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255)
    elif len(shape) == 4 and all(isinstance(v, (int, float)) for v in shape):
        x0, y0, x1, y1 = shape
        d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=255)
    else:
        d.polygon([tuple(p) for p in shape], fill=255)
    return np.array(m) > 0


def _load_zones(extra=()):
    scenes = {}
    files = [os.path.join(ZONES, f) for f in sorted(os.listdir(ZONES)) if f.endswith('.py') and not f.startswith('_')]
    for path in files + list(extra):
        f = os.path.basename(path)
        spec = importlib.util.spec_from_file_location('fx_zones_' + f[:-3], path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        for k, v in mod.SCENES.items():
            if k in scenes:
                raise SystemExit(f'{k} is defined twice ({f})')
            scenes[k] = v
            for other in v.get('also', []):
                scenes[other] = {k2: v2 for k2, v2 in v.items() if k2 != 'also'}
    return scenes


def bake(rel, spec):
    img = Image.open(os.path.join(ART, rel)).convert('RGBA')
    w, h = img.size
    arr = np.array(img).astype(np.int32)
    rgb, a = arr[..., :3], arr[..., 3]
    visible = a > 24
    sway = np.zeros((h, w), np.float32)
    surf = np.zeros((h, w), np.uint8)
    kind = np.zeros((h, w), np.uint8)
    for entry in spec.get('fx', []):
        eff, shape = entry[0], entry[1]
        key = entry[2] if len(entry) > 2 else 'all'
        opts = entry[3] if len(entry) > 3 else {}
        zone = _shape_mask(shape, w, h)
        if eff == 'none':
            sway[zone] = 0
            surf[zone] = 0
            kind[zone] = 0
            continue
        g_val, b_val, amp = EFFECTS[eff]
        sel = zone & KEYS[key](rgb, a) & visible
        if key != 'all':  # drop speckle: single stray pixels flicker badly
            sel = ndimage.binary_opening(sel, iterations=1) | (ndimage.binary_closing(sel, iterations=1) & sel)
        if g_val is not None:
            surf[sel] = g_val
        if b_val is not None:
            kind[sel] = b_val
        if amp is not None:
            amp = opts.get('amp', amp)
            src = sel
            if opts.get('halo'):
                # the sway reaches a few px past the leaves, so the canopy's outline moves too (inside the outline
                # a voxel canopy's stripes hide a sideways slide)
                src = ndimage.binary_dilation(sel, iterations=int(opts['halo'])) & visible
            field = src.astype(np.float32) * amp
            if 'fade' in opts:  # the bottom of the shape moves less (a trunk, a blade's root)
                ys = np.nonzero(zone.any(axis=1))[0]
                y0, y1 = ys.min(), ys.max() + 1
                t = np.clip((np.arange(h) - y0) / max(1, y1 - y0), 0, 1)[:, None]
                field *= (1 - t) + t * opts['fade']
            soft = ndimage.gaussian_filter(field, SWAY_FEATHER)
            sway = np.maximum(sway, np.maximum(field, soft * 1.6).clip(0, amp) * visible)
    mask = np.dstack([(sway.clip(0, 1) * 255).round().astype(np.uint8), surf, kind])
    for e in spec.get('emit', []):
        if e['t'] not in EMITTERS:
            raise SystemExit(f"{rel}: unknown emitter {e['t']}")
    name = rel.replace('/', '__').rsplit('.', 1)[0] + '.webp'
    out = os.path.join(OUT_DIR, name)
    Image.fromarray(mask, 'RGB').save(out, 'WEBP', lossless=True, quality=100, method=6)
    out = {'mask': 'assets/art/fx/' + name, 'w': w, 'h': h, 'emit': spec.get('emit', [])}
    if 'wind' in spec:
        out['wind'] = spec['wind']
    return out, img, mask


TINT = {  # preview colours: (channel, value) -> colour
    (1, 255): (0, 255, 255), (1, 128): (30, 90, 255), (1, 64): (190, 255, 0),
    (2, 255): (255, 30, 0), (2, 200): (190, 60, 255), (2, 128): (255, 230, 0), (2, 80): (255, 80, 200), (2, 40): (160, 160, 160),
}


def counts(mask):
    c = {'sway': int((mask[..., 0] > 0).sum())}
    names = {(1, 255): 'fall', (1, 128): 'still', (1, 64): 'grass', (2, 255): 'fire', (2, 200): 'crystal', (2, 128): 'lamp', (2, 80): 'cloth', (2, 40): 'smoke'}
    for (ch, val), n in names.items():
        k = int((mask[..., ch] == val).sum())
        if k:
            c[n] = k
    return c


def preview(rel, img, mask, data, out_dir):
    base = Image.new('RGBA', img.size, (255, 0, 255, 255))
    base.alpha_composite(img)
    base = np.array(base.convert('RGB')).astype(np.float32)
    over = base.copy()
    for (ch, val), col in TINT.items():
        sel = mask[..., ch] == val
        over[sel] = over[sel] * 0.35 + np.array(col) * 0.65
    # sway: a red wash, as strong as the movement
    k = (mask[..., 0].astype(np.float32) / 255.0)[..., None] * 0.7
    over = over * (1 - k) + np.array([255, 0, 60]) * k
    im = Image.fromarray(np.concatenate([base, over], axis=1).astype(np.uint8))
    d = ImageDraw.Draw(im)
    ox = img.width
    for e in data['emit']:
        x, y = e['x'] + ox, e['y']
        if e['t'] == 'glow':
            r = e['r']
            d.ellipse([x - r, y - r, x + r, y + r], outline=(255, 255, 0), width=2)
        else:
            ww, hh = e.get('w', 20), e.get('h', 20)
            col = {'embers': (255, 120, 0), 'smoke': (255, 255, 255), 'bubbles': (120, 255, 120),
                   'motes': (255, 255, 160), 'leaves': (0, 200, 0)}[e['t']]
            if e['t'] in ('smoke', 'embers', 'bubbles'):
                d.line([x, y, x, y - e.get('h', 60)], fill=col, width=2)
                d.ellipse([x - 5, y - 5, x + 5, y + 5], outline=col, width=2)
            else:
                d.rectangle([x, y, x + ww, y + hh], outline=col, width=2)
        d.text((x + 4, y + 4), e['t'], fill=(255, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0))
    os.makedirs(out_dir, exist_ok=True)
    p = os.path.join(out_dir, rel.replace('/', '__').rsplit('.', 1)[0] + '.png')
    im.save(p)
    return p


def main():
    args = sys.argv[1:]
    prev = None
    only = None
    extra, out_json = [], OUT_JSON
    if '--preview' in args:
        i = args.index('--preview'); prev = args[i + 1]; del args[i:i + 2]
    while '--zones' in args:
        i = args.index('--zones'); extra.append(os.path.abspath(args[i + 1])); del args[i:i + 2]
    if '--json' in args:
        i = args.index('--json'); out_json = os.path.abspath(args[i + 1]); del args[i:i + 2]
    if args:
        only = set(args)
    os.makedirs(OUT_DIR, exist_ok=True)
    scenes = _load_zones(extra)
    data = {}
    src = out_json if os.path.exists(out_json) else OUT_JSON      # a concept json builds on itself
    if os.path.exists(src) and only:
        data = json.load(open(src))
    for rel, spec in scenes.items():
        if only and rel not in only:
            continue
        d, img, mask = bake(rel, spec)
        data['assets/art/' + rel] = d
        line = f'{rel}: {counts(mask)} emit={len(d["emit"])}'
        if prev:
            line += ' -> ' + preview(rel, img, mask, d, prev)
        print(line)
    # drop masks for scenes that no longer have zones
    keep = {os.path.basename(v['mask']) for v in data.values()}
    for f in os.listdir(OUT_DIR):
        if f not in keep and not only:
            os.remove(os.path.join(OUT_DIR, f))
    with open(out_json, 'w') as f:
        json.dump(dict(sorted(data.items())), f, indent=1)
    print('wrote', out_json, len(data), 'scenes')


if __name__ == '__main__':
    main()

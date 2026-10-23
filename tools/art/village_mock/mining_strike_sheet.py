"""Mining with the Pounce: how the Wilds' melee move (a crouch, a lunge that drives the head in, a
landing squash; the third in a combo is a big one) breaks an ore node, drawn frame by frame from the
real walk sheets with the same squash, stretch, tilt and lunge the game applies (wilds_combat.dart,
PetAct.swing). The Evochi needs no new sprites: the move is the walk sheet animated in code. What
mining adds is the ore: a node per ore in four states (whole, cracked, splitting, burst).

    python3 mining_strike_sheet.py OUT_DIR

Writes mining_strike_sheet.png (the board), ore_<id>_<stage>.png, and walk_<stage>_obsidian.png (the
sprite sheets the move uses: 8 directions down, idle + 8 walk frames across).
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from build_characters import fit_for  # noqa: E402
from build_items import LIGHT  # noqa: E402
from village_scenes import CPainter  # noqa: E402
from voxel import Camera, Model, render  # noqa: E402

ART = '/home/claude/evochi/flutter/assets/art/wilds/'
FONTS = '/home/claude/evochi/flutter/assets/fonts/'
WALK = json.load(open(ART + 'wilds_walk.json'))
DIRS = WALK['dirs']
INK = (59, 41, 35)
CAVE = (58, 52, 60)

ORES = {   # stone, ore colours, glow, hardness
    'copper': (['#8E8A86', '#7B7773', '#A39E98'], ['#D9844A', '#B8622E', '#F0A56A'], None, 1),
    'iron': (['#7D7A80', '#6B6870', '#8F8B93'], ['#C9CDD6', '#9EA4B0', '#E6E9EF'], None, 2),
    'lumen': (['#6E6A78', '#5E5A68', '#7F7A8A'], ['#9FF0DA', '#6FD8C0', '#D8FFF4'], 0.8, 3),
    'obsidian': (['#4A4550', '#3C3742', '#57525E'], ['#2A2230', '#5B3B6E', '#9A6BC0'], 0.35, 4),
}


def font(w, size):
    return ImageFont.truetype(FONTS + {'black': 'Nunito-Black.ttf', 'bold': 'Nunito-Bold.ttf', 'xbold': 'Nunito-ExtraBold.ttf'}[w], size)


# ------------------------------------------------------------------------------------------- ore nodes
def ore_node(kind, stage, seed=7):
    """A lumpy rock studded with ore. Stage 0 whole, 1 cracked, 2 splitting (a chunk gone, wider
    cracks), 3 burst (only the stump and the ore pieces left)."""
    stone, ore, glow, _ = ORES[kind]
    M = Model((-7, -1, -7), (7, 11, 7), [], res=2)
    P = CPainter(M, seed)
    rng = np.random.default_rng(seed)
    X, Y, Z = M.X, M.Y, M.Z
    n = (np.sin(X * 1.3 + 1.1) * np.cos(Z * 1.1) + np.sin(Y * 1.7 + X * 0.6)) * 0.08
    rock = (((X / 5.2) ** 2 + ((Y - 3.4) / 3.9) ** 2 + (Z / 4.6) ** 2 + n) < 1.0) & (Y >= 0)
    if stage == 3:
        rock &= Y < 1.6 + 0.6 * np.sin(X * 1.7)              # the stump
    P.fill(rock, stone, cell=(1.0, 1.0, 1.0))
    surf = rock & ~(np.roll(rock, 1, 1) & np.roll(rock, -1, 1) & np.roll(rock, 1, 0) & np.roll(rock, -1, 0) & np.roll(rock, 1, 2) & np.roll(rock, -1, 2))
    fleck = surf & (rng.random(M.m.shape) < 0.11)
    fleck = fleck | (surf & (np.roll(fleck, 1, 0) | np.roll(fleck, 1, 1)) & (rng.random(M.m.shape) < 0.5))
    if glow:
        P.fill(fleck, ore, glow=glow, cell=0.5)
    else:
        P.fill(fleck, ore, cell=0.5)
    if stage in (1, 2):
        # cracks run over the face toward you, from where the hits land
        lines = [[(-0.6, 6.8), (0.3, 5.2), (-0.4, 3.9), (0.6, 2.2), (0.1, 0.6)]]
        if stage == 2:
            lines += [[(0.3, 5.2), (2.4, 4.6), (3.6, 3.1)], [(-0.4, 3.9), (-2.6, 3.4), (-3.8, 1.8)], [(0.6, 2.2), (2.2, 1.0)]]
        crack = np.zeros(M.m.shape, bool)
        w = 0.32 if stage == 1 else 0.48
        for ln in lines:
            for (x0, y0), (x1, y1) in zip(ln, ln[1:]):
                t = np.clip(((X - x0) * (x1 - x0) + (Y - y0) * (y1 - y0)) / ((x1 - x0) ** 2 + (y1 - y0) ** 2), 0, 1)
                d = np.hypot(X - (x0 + t * (x1 - x0)), Y - (y0 + t * (y1 - y0)))
                crack |= d < w
        crack &= rock & (Z > 0.5)
        if stage == 2:
            M.m[crack & surf] = 0                               # the deepest cracks open
            gone = rock & ((X - 3.2) ** 2 + (Y - 6.0) ** 2 + (Z - 2.0) ** 2 < 2.6 ** 2)
            M.m[gone] = 0
        M.set(crack & (M.m > 0), '#2A2426')
    if stage == 3:
        # the ore pieces that fall out (they pop toward you, then fly to your bag)
        for (x, y, z, r) in ((-3.0, 1.0, 3.6, 0.9), (1.4, 0.8, 4.4, 1.0), (3.6, 1.2, 2.2, 0.8), (-0.6, 0.9, 5.4, 0.7)):
            nug = ((X - x) ** 2 + (Y - y) ** 2 + (Z - z) ** 2) < r ** 2
            if glow:
                P.fill(nug, ore, glow=glow, cell=0.5)
            else:
                P.fill(nug, ore, cell=0.5)
        for (x, y, z, r) in ((-4.6, 0.6, -1.0, 0.7), (4.8, 0.6, 0.4, 0.6), (2.0, 0.5, -3.6, 0.6)):
            M.set(((X - x) ** 2 + (Y - y) ** 2 + (Z - z) ** 2) < r ** 2, stone[1])
    return M


def render_ore(M, cam, fit):
    o = render(M, {}, cam, fit.w, fit.h, fit=fit, light=LIGHT, ss=3, outline_px=2.2, outline_col='#3B2923',
               inner_thresh=2.0, inner_alpha=0.55, inner_px=0.8)
    return Image.fromarray(o.rgba, 'RGBA')


# ------------------------------------------------------------------------------------------- the move
def sheet(stage, palette='obsidian'):
    w = WALK['walkers'][stage]
    g = w['gaits']['walk']
    return Image.open(ART + g['sheets'][palette]).convert('RGBA'), w, g


def pose(img, w, g, d, col, sx, sy, tilt, lift, k):
    """One frame of the walker as the game draws it: about its feet, rolled, squashed, lifted."""
    fw, fh = w['frameW'], w['frameH']
    gx, gy = w['ground']
    fr = img.crop((col * fw, d * fh, (col + 1) * fw, (d + 1) * fh))
    face = d * math.pi / 4
    th = g['roll'][col] * math.pi / 180 * math.cos(face) + tilt
    a, b = math.cos(th), math.sin(th)
    ssy = sy * g['squash'][col]
    # forward: p' = R S (p - anchor) * k, with the canvas centre at the feet
    W = H = int(max(fw, fh) * k * 1.6)
    cx, cy = W / 2, H * 0.72 - lift * k
    # inverse for PIL: p = S^-1 R^-1 (p' - c) / k + anchor
    inv = np.linalg.inv(np.array([[a * sx * k, -b * ssy * k, cx - (a * sx * gx - b * ssy * gy) * k],
                                  [b * sx * k, a * ssy * k, cy - (b * sx * gx + a * ssy * gy) * k],
                                  [0, 0, 1]]))
    out = fr.transform((W, H), Image.AFFINE, tuple(inv[:2].ravel()), resample=Image.BICUBIC)
    return out, (cx, H * 0.72)


def timeline(c):
    """The Pounce, as wilds_combat.dart plays it (seconds -> squash, stretch, tilt, lift, forward 0-1)."""
    big = 1.6 if c == 2 else 1.0
    out = []
    for t in (0.0, 0.035, 0.07, 0.11, 0.155, 0.2, 0.26, 0.36):
        if t < 0.07:
            k = t / 0.07
            out.append((t, 1 + 0.08 * k, 1 - 0.14 * k, -0.12 * k, 0.0, 0.0, 'crouch'))
        elif t < 0.2:
            u = (t - 0.07) / 0.13
            lift = math.sin(u * math.pi) * 9 if c == 2 else 0
            out.append((t, 1 - 0.08 * big, 1 + 0.12 * big, 0.2 * big, lift, u, 'pounce'))
        else:
            k = min(1.0, (t - 0.2) / 0.16)
            land = (1 - k) ** 2
            out.append((t, 1 + 0.09 * big * land, 1 - 0.1 * big * land, -0.06 * land * big, 0.0, 1.0, 'hit!' if t == 0.2 else 'land'))
    return out


def strip(stage, d, ore_imgs, hits=(0, 1, 2), k=1.0, ch=270):
    """A combo breaking a node: per hit the frames of the move, the node cracking at each impact. The
    node stays put; each pounce starts its own lunge back from it."""
    img, w, g = sheet(stage)
    lunge = [9.0, 9.0, 16.0]
    face = (math.sin(d * math.pi / 4), math.cos(d * math.pi / 4))       # world (x, z) the way it faces
    s35 = math.sin(math.radians(35))
    f2 = (face[0], face[1] * s35)                                        # on screen
    ow = max(o.width for o in ore_imgs)
    reach = w['frameW'] * 0.36 * k + ow * 0.3
    far = lunge[2 if 2 in hits else 0] * 6 * k + reach
    cw = int(w['frameW'] * 0.62 * k + far * f2[0] + ow * 0.6 + 40)
    cell = (cw, ch)
    ore_g = (cw - ow * 0.5 - 16, ch - 46)                               # the node's ground point
    cells = []
    for c in hits:
        L = lunge[c] * 6 * k
        p0 = (ore_g[0] - f2[0] * (L + reach), ore_g[1] - f2[1] * (L + reach))
        for i, (t, sx, sy, tilt, lift, fwd, lab) in enumerate(timeline(c)):
            lean = face[0]
            fr, (fx, fy) = pose(img, w, g, d, 1 + i % 8 if 0.07 <= t < 0.2 else 0, sx, sy, tilt * lean, lift, k)
            cv = Image.new('RGBA', cell, CAVE + (255,))
            dd = ImageDraw.Draw(cv)
            px, py = p0[0] + f2[0] * L * fwd, p0[1] + f2[1] * L * fwd
            ore = ore_imgs[min(3, c + (1 if t >= 0.2 else 0))]
            nx, ny = ore_g[0] - ore.width / 2, ore_g[1] - ore.height * 0.86
            dd.ellipse((nx + ore.width * 0.15, ny + ore.height * 0.78, nx + ore.width * 0.85, ny + ore.height * 0.94), fill=(40, 35, 42))
            cv.alpha_composite(ore, (int(nx), int(ny)))
            # afterimages behind a pounce
            if lab == 'pounce':
                for back in (0.35, 0.7):
                    a = np.asarray(fr).copy()
                    a[..., :3] = (159, 240, 218)
                    a[..., 3] = (a[..., 3] * 0.28 * (1 - back * 0.8)).astype(np.uint8)
                    cv.alpha_composite(Image.fromarray(a), (int(px - fx - f2[0] * back * 40), int(py - fy - f2[1] * back * 40)))
            cv.alpha_composite(fr, (int(px - fx), int(py - fy)))
            if lab == 'hit!':
                # the swipe of light, chips off the rock
                hx, hy = nx + ore.width * 0.36, ny + ore.height * 0.45
                for r, al in ((44 * k, 230), (54 * k, 120)):
                    dd.arc((hx - r, hy - r, hx + r, hy + r), 200, 330, fill=(230, 255, 248, al), width=6)
                rng = np.random.default_rng(c)
                for j in range(9 if c == 2 else 5):
                    ang = rng.uniform(-2.6, -0.4)
                    dist = rng.uniform(18, 60) * (1.4 if c == 2 else 1)
                    sz = rng.uniform(4, 9)
                    x, y = hx + math.cos(ang) * dist, hy + math.sin(ang) * dist
                    col = ORE_COL if j % 3 == 0 else (150, 144, 140)
                    dd.rectangle((x - sz / 2, y - sz / 2, x + sz / 2, y + sz / 2), fill=col, outline=(40, 30, 30))
            if lab == 'land' and t < 0.3:
                for j in range(4):
                    x = px - 30 + j * 20
                    dd.ellipse((x - 10, py - 6, x + 10, py + 6), fill=(140, 130, 140, 120))
            f = font('xbold', 18)
            tag = f'hit {c + 1}: {lab}' if i == 0 else lab
            dd.text((10, 8), tag, font=f, fill=(255, 236, 200))
            cells.append(cv)
    return cells


ORE_COL = (217, 132, 74)


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    cam = Camera(yaw=0, pitch=35)
    base = ore_node('copper', 0)
    fit = fit_for([base], cam, 13.0)
    ores = {}
    for kind in ORES:
        ores[kind] = []
        for st in range(4):
            im = render_ore(ore_node(kind, st), cam, fit)
            im.save(os.path.join(out, f'ore_{kind}_{st}.png'))
            ores[kind].append(im)
    # the sprite sheets the move uses
    for stage in ('s01', 's02', 's03'):
        img, _, _ = sheet(stage)
        img.save(os.path.join(out, f'walk_{stage}_obsidian.png'))
    # the board: the Elder breaking copper (a full three-hit combo, side on), then the Hatchling and the
    # Juvenile landing one hit facing down-right (how the mines camera mostly sees it)
    big = strip('s03', DIRS.index('E'), [o.resize((int(o.width * 0.75), int(o.height * 0.75))) for o in ores['copper']], k=0.75, ch=230)
    small = strip('s01', DIRS.index('SE'), [o.resize((int(o.width * 0.62), int(o.height * 0.62))) for o in ores['lumen']], hits=(0,), k=0.8, ch=300)
    mid = strip('s02', DIRS.index('SE'), [o.resize((int(o.width * 0.7), int(o.height * 0.7))) for o in ores['iron']], hits=(0,), k=0.8, ch=300)
    cw, ch = big[0].size
    cols = 8
    rows_big = math.ceil(len(big) / cols)
    W = max(40 + cols * (cw + 10), 40 + cols * (mid[0].width + 10)) + 30
    ore_row_h = max(o.height for o in ores['copper']) + 60
    H = 150 + rows_big * (ch + 10) + 60 + (mid[0].height + 10) * 2 + 60 + ore_row_h * 1 + 60
    b = Image.new('RGB', (W, H), (36, 32, 44))
    d = ImageDraw.Draw(b)
    d.text((40, 22), 'Mining with the Pounce: the melee move, reused on ore', font=font('black', 36), fill=(255, 236, 200))
    d.text((40, 70), 'No new Evochi sprites: the move is the walk sheet animated in code (crouch, a lunge that drives the head in, a landing squash; '
           'every third hit is a big one).', font=font('bold', 19), fill=(205, 205, 215))
    d.text((40, 96), 'Each hit: a light tick of haptics and chips off the rock; the node cracks a stage. The breaking hit: a heavy bump, the rock '
           'bursts, the ore pops out toward you and flies to your bag.', font=font('bold', 19), fill=(205, 205, 215))
    y = 140
    d.text((40, y), 'An Obsidian Elder, three hits on copper', font=font('xbold', 22), fill=(255, 214, 120))
    y += 34
    for i, cimg in enumerate(big):
        b.paste(cimg.convert('RGB'), (40 + (i % cols) * (cw + 10), y + (i // cols) * (ch + 10)))
    y += rows_big * (ch + 10) + 20
    d.text((40, y), 'A Juvenile on iron and a Hatchling on lumen crystal, one hit each, facing down-right', font=font('xbold', 22), fill=(255, 214, 120))
    y += 34
    for r, cs in enumerate((mid, small)):
        for i, cimg in enumerate(cs):
            b.paste(cimg.convert('RGB'), (40 + i * (cimg.width + 10), y + r * (cimg.height + 10)))
    y += 2 * (mid[0].height + 10) + 20
    d.text((40, y), 'Ore nodes, whole to burst (copper, iron, lumen crystal, obsidian: softest to hardest)', font=font('xbold', 22), fill=(255, 214, 120))
    y += 34
    x = 40
    for kind in ORES:
        for st in range(4):
            o = ores[kind][st].resize((int(ores[kind][st].width * 0.62), int(ores[kind][st].height * 0.62)))
            tile = Image.new('RGBA', o.size, CAVE + (255,))
            tile.alpha_composite(o)
            b.paste(tile.convert('RGB'), (x, y))
            x += o.width + 4
        x += 26
    b.save(os.path.join(out, 'mining_strike_sheet.png'), optimize=True)
    print('ok', b.size)


if __name__ == '__main__':
    main()

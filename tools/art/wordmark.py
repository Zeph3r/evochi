"""Chunky voxel wordmarks and screen titles (EVOCHI, BAG, MARKET, ...)."""
import os
import sys

import numpy as np

from voxel import Model, Camera, Light, render, save_rgba
from characters import spike

FONT = {
    'A': ['.####.', '##..##', '##..##', '######', '##..##', '##..##', '##..##'],
    'B': ['#####.', '##..##', '##..##', '#####.', '##..##', '##..##', '#####.'],
    'C': ['.####.', '##..##', '##....', '##....', '##....', '##..##', '.####.'],
    'D': ['#####.', '##..##', '##..##', '##..##', '##..##', '##..##', '#####.'],
    'E': ['######', '##....', '##....', '#####.', '##....', '##....', '######'],
    'F': ['######', '##....', '##....', '#####.', '##....', '##....', '##....'],
    'G': ['.####.', '##..##', '##....', '##.###', '##..##', '##..##', '.#####'],
    'H': ['##..##', '##..##', '##..##', '######', '##..##', '##..##', '##..##'],
    'I': ['##', '##', '##', '##', '##', '##', '##'],
    'J': ['....##', '....##', '....##', '....##', '##..##', '##..##', '.####.'],
    'K': ['##..##', '##.##.', '####..', '###...', '####..', '##.##.', '##..##'],
    'L': ['##....', '##....', '##....', '##....', '##....', '##....', '######'],
    'M': ['##...##', '###.###', '#######', '##.#.##', '##...##', '##...##', '##...##'],
    'N': ['##..##', '###.##', '######', '##.###', '##..##', '##..##', '##..##'],
    'O': ['.####.', '##..##', '##..##', '##..##', '##..##', '##..##', '.####.'],
    'P': ['#####.', '##..##', '##..##', '#####.', '##....', '##....', '##....'],
    'Q': ['.####.', '##..##', '##..##', '##..##', '##.###', '##..##', '.###.#'],
    'R': ['#####.', '##..##', '##..##', '#####.', '####..', '##.##.', '##..##'],
    'S': ['.#####', '##....', '##....', '.####.', '....##', '....##', '#####.'],
    'T': ['######', '..##..', '..##..', '..##..', '..##..', '..##..', '..##..'],
    'U': ['##..##', '##..##', '##..##', '##..##', '##..##', '##..##', '.####.'],
    'V': ['##..##', '##..##', '##..##', '##..##', '##..##', '.####.', '..##..'],
    'W': ['##...##', '##...##', '##...##', '##.#.##', '#######', '###.###', '##...##'],
    'X': ['##..##', '##..##', '.####.', '..##..', '.####.', '##..##', '##..##'],
    'Y': ['##..##', '##..##', '.####.', '..##..', '..##..', '..##..', '..##..'],
    'Z': ['######', '....##', '...##.', '..##..', '.##...', '##....', '######'],
    ' ': ['...', '...', '...', '...', '...', '...', '...'],
}

CREAM, CREAM_HI, CREAM_LO = '#FFF4E2', '#FFFBF3', '#EFDCC2'
OUT_DK, SIDE = '#4A2E22', '#8A5A3C'


def layout(word, gap=1):
    cells = []
    x = 0
    starts = []
    for ch in word:
        g = FONT[ch]
        starts.append(x)
        for r, row in enumerate(g):
            for c, v in enumerate(row):
                if v == '#':
                    cells.append((x + c, 6 - r))
        x += len(g[0]) + gap
    return cells, x - gap, starts


def build_word(word, sprouts=(), gold_on=None, board=False):
    cells, width, starts = layout(word)
    pad = 4
    M = Model((-pad, -pad - 2, -4), (width + pad, 7 + pad + 6, 4), [], res=2)
    occ = np.zeros(M.m.shape[::2][:2], bool)
    mask = np.zeros(M.m.shape, bool)
    for (cx, cy) in cells:
        mask |= (M.X >= cx) & (M.X < cx + 1) & (M.Y >= cy) & (M.Y < cy + 1)
    face = mask & (M.Z >= 0) & (M.Z < 1.0)
    # outline ring (dilate 0.5 in x/y), sits slightly behind the face
    from scipy import ndimage
    m2 = mask[:, :, M.m.shape[2] // 2]
    dil = ndimage.binary_dilation(m2, iterations=1)
    dil3 = np.repeat(dil[:, :, None], M.m.shape[2], 2)
    ring = dil3 & (M.Z >= -0.5) & (M.Z < 0.6)
    # extrusion: dilated shape shifted down by 1.2 units, behind the face
    sh = np.roll(dil, -3, axis=1)
    sh = ndimage.binary_dilation(sh, iterations=0) if False else sh
    sh3 = np.repeat((sh | dil)[:, :, None], M.m.shape[2], 2)
    ext = sh3 & (M.Z >= -1.6) & (M.Z < 0.2)
    if board:
        x0, x1 = -2.2, width + 2.2
        b = (M.X >= x0) & (M.X < x1) & (M.Y >= -1.8) & (M.Y < 8.6) & (M.Z >= -3.2) & (M.Z < -1.4)
        M.set(b, '#A8703F')
        planks = b & ((np.floor((M.Y + 1.8) / 3.5).astype(int) % 2) == 1)
        M.set(planks, '#B98149')
        M.set(b & ((M.Y < -1.2) | (M.Y >= 8.0) | (M.X < x0 + 0.6) | (M.X >= x1 - 0.6)), '#6E4529')
        for nx in (x0 + 1.0, x1 - 1.0):
            for ny in (-0.6, 7.4):
                M.set((np.abs(M.X - nx) < 0.3) & (np.abs(M.Y - ny) < 0.3) & (M.Z >= -1.5) & (M.Z < -1.2), '#C9C3B8')
    M.set(ext, SIDE)
    M.set(ring, OUT_DK)
    M.set(face, CREAM)
    M.set(face & (np.floor(M.Y) - M.Y > -0.5) & (np.isin(np.floor(M.Y), [c[1] for c in cells])), CREAM)
    # top highlight / bottom shade on each glyph row
    top = face & ~np.roll(mask, -1, axis=1)
    M.set(top, CREAM_HI)
    bot = face & ~np.roll(mask, 1, axis=1)
    M.set(bot, CREAM_LO)
    # leaf sprouts on chosen letters
    for li in sprouts:
        ch = word[li]
        gx = starts[li] + len(FONT[ch][0]) / 2
        base = (gx, 7.0, 0.3)
        for d, L in (((-0.8, 1.0, 0.1), 2.6), ((0.8, 1.0, 0.1), 2.4)):
            sp = spike(M, base, d, L, 0.9, 0.3)
            M.set(sp & (M.m == 0), '#6CB25A')
            M.set(sp & (M.m > 0) & (M.Y > base[1] + 1.2), '#8ED06A')
        M.set((np.abs(M.X - gx) < 0.35) & (M.Y >= 6.8) & (M.Y < 7.8) & (np.abs(M.Z - 0.3) < 0.35), '#3F7D35')
    if gold_on is not None:
        ch = word[gold_on]
        gx = starts[gold_on] + len(FONT[ch][0]) / 2
        blk = (np.abs(M.X - gx + 0.4) < 1.2) & (M.Y >= 7.0) & (M.Y < 8.8) & (np.abs(M.Z - 0.2) < 0.9)
        blk2 = (np.abs(M.X - gx - 1.2) < 0.8) & (M.Y >= 7.0) & (M.Y < 8.2) & (np.abs(M.Z - 0.2) < 0.7)
        M.set(blk | blk2, '#F4C04E')
        M.set((blk | blk2) & (M.Y >= 8.2), '#FFE29A')
    return M


TITLES = {
    'wordmark_evochi': dict(word='EVOCHI', sprouts=(1, 4), gold_on=2),
    'title_bag': dict(word='BAG', sprouts=(0, 2)),
    'title_market': dict(word='MARKET', board=True),
    'title_create_your': dict(word='CREATE YOUR'),
    'title_journey': dict(word='JOURNEY', sprouts=(0,)),
    'title_evodex': dict(word='EVODEX', sprouts=(2,)),
    'title_profile': dict(word='PROFILE'),
    'title_memorial': dict(word='MEMORIAL'),
}


def main(out, height=220):
    os.makedirs(out, exist_ok=True)
    light = Light(smooth=0.2, ao_amt=0.25, jitter=0.0, ambient=0.86, key_amt=0.3, key=(-0.3, 0.8, 0.9))
    for name, kw in TITLES.items():
        M = build_word(**kw)
        cam = Camera(yaw=0, pitch=6)
        cells, width, _ = layout(kw['word'])
        w = int(height * (width + 8) / (7 + 10))
        o = render(M, {}, cam, w, height, light=light, ss=3, margin=0.03, outline_px=3.0,
                   outline_col='#3B2620', inner_thresh=0.8, inner_alpha=0.35, inner_px=0.6)
        a = o.rgba[..., 3]
        ys, xs = np.where(a > 0)
        crop = o.rgba[max(0, ys.min() - 2):ys.max() + 3, max(0, xs.min() - 2):xs.max() + 3]
        save_rgba(crop, os.path.join(out, name + '.png'))
        print(name, crop.shape, flush=True)


if __name__ == '__main__':
    main(sys.argv[1])

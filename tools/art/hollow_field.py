"""The Hollow taking Alder's map (the cold open's map_hollow shot): when the Hollow reaches each pixel of the map.

The corruption starts at the far places the trails lead to (ruins, gate, cliffs, cove, grove) and along the
board's northern edge, and creeps inward: fastest down the trails (it follows the paths, putting their lights out
as it comes), in fingers (a noisy speed), slowest round the village, which it never quite reaches (the shot ends
with the village still glowing). Written as the arrival time per pixel, 0 (first) to 1 (the village), for the
app's shader (flutter/shaders/hollow_fx.frag) to play forward.

    python3 hollow_field.py ../../flutter/assets/art/cine
R: arrival time (255 = never: off the board). G: the board (255 on it).
"""
from __future__ import annotations

import heapq
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

DOWN = 4    # the field at a quarter of the plate's size (the shader adds the fine detail)
BOARD = [(48, 478), (1196, 478), (1236, 1282), (10, 1282)]     # the map board's corners on the plate (px)


def fbm(h, w, seed, octaves=5, base=6.0):
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        n = int(base * 2 ** o)
        g = rng.random((n + 1, n + 1)).astype(np.float32)
        up = np.asarray(Image.fromarray(g).resize((w, h), Image.BICUBIC), np.float32)
        out += amp * up
        tot += amp
        amp *= 0.55
    out /= tot
    return (out - out.min()) / (out.max() - out.min() + 1e-6)


def main(cine_dir):
    meta = json.load(open(os.path.join(cine_dir, 'cine.json')))['map_lit']
    W, H = meta['w'], meta['h']
    w, h = W // DOWN, H // DOWN
    board_im = Image.new('L', (W, H), 0)
    ImageDraw.Draw(board_im).polygon(BOARD, fill=255)
    board = np.asarray(board_im.resize((w, h), Image.BILINEAR)) > 127
    A = {k: (v[0] / DOWN, v[1] / DOWN) for k, v in meta['anchors'].items()}
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # the trails: distance to the nearest
    tr = np.zeros((h, w), bool)
    trail_im = Image.new('L', (w, h), 0)
    d_ = ImageDraw.Draw(trail_im)
    for pts in meta['lines'].values():
        d_.line([(p[0] / DOWN, p[1] / DOWN) for p in pts], fill=255, width=2)
    tr = np.asarray(trail_im) > 0
    dtrail = ndimage.distance_transform_edt(~tr)
    vx, vy = A['village']
    dvil = np.hypot(xx - vx, yy - vy)
    n1 = fbm(h, w, 7)
    n2 = fbm(h, w, 19, base=14.0)
    speed = 0.45 + 1.1 * n1 ** 1.5 + 0.35 * n2
    speed *= 1 + 2.2 * np.exp(-(dtrail / 5.0) ** 2)               # down the paths
    speed *= np.clip(0.25 + 0.75 * (dvil / 70.0) ** 1.5, 0.12, 1)  # the village holds
    speed[~board] = 0
    cost = 1.0 / np.maximum(speed, 1e-3)
    # the sources: the northern edge (staggered) and the far ends of the trails
    T = np.full((h, w), np.inf, np.float32)
    heap = []
    # every edge of the board, the north first, the sides later, the south (nearest the village) last
    edge = board & ~ndimage.binary_erosion(board, iterations=2)
    ys, xs = np.nonzero(edge)
    rows = np.nonzero(board.any(1))[0]
    top, bot = rows.min(), rows.max()
    for y, x in zip(ys, xs):
        v = (y - top) / max(1, bot - top)          # 0 north .. 1 south
        t0 = 6.0 + 55.0 * v + 30.0 * n2[y, x]
        heapq.heappush(heap, (t0, y, x))
    for k, t0 in (('gate', 0.0), ('ruins', 4.0), ('cliffs', 10.0), ('cove', 16.0), ('grove', 22.0)):
        x, y = int(A[k][0]), int(A[k][1])
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                if 0 <= y + dy < h and 0 <= x + dx < w and board[y + dy, x + dx]:
                    heapq.heappush(heap, (t0 + abs(dx) + abs(dy), y + dy, x + dx))
    nb = [(-1, 0, 1.0), (1, 0, 1.0), (0, -1, 1.0), (0, 1, 1.0), (-1, -1, 1.414), (-1, 1, 1.414), (1, -1, 1.414), (1, 1, 1.414)]
    while heap:
        t, y, x = heapq.heappop(heap)
        if t >= T[y, x]:
            continue
        T[y, x] = t
        for dy, dx, l in nb:
            yy_, xx_ = y + dy, x + dx
            if 0 <= yy_ < h and 0 <= xx_ < w and speed[yy_, xx_] > 0:
                nt = t + l * 0.5 * (cost[y, x] + cost[yy_, xx_])
                if nt < T[yy_, xx_]:
                    heapq.heappush(heap, (nt, yy_, xx_))
    finite = np.isfinite(T)
    # the village holds out last: it, and a little round it, after everything else
    T = np.where(finite, T + float(np.nanmax(np.where(finite, T, np.nan))) * 0.9 * np.exp(-(dvil / 55.0) ** 2), T)
    tv = T[int(vy), int(vx)]
    # evened out: by time p, about p of the board is taken (the village, last, at ~1)
    order = np.argsort(T[finite])
    rank = np.empty(order.size, np.float32)
    rank[order] = np.linspace(0, 1, order.size, dtype=np.float32)
    Tn = np.full(T.shape, 1.4, np.float32)
    Tn[finite] = rank
    Tn = ndimage.gaussian_filter(Tn, 0.8)
    Tn[~finite] = 9.0
    R = np.clip(Tn / 1.25, 0, 1) * 254
    R[~finite] = 255
    G = board * 255
    out = np.dstack([R, G, np.zeros_like(R)]).astype(np.uint8)
    path = os.path.join(cine_dir, 'map_hollow_field.png')
    Image.fromarray(out, 'RGB').save(path, optimize=True)
    print(path, out.shape, 'village at', round(float(tv), 1), 'reached by 0.5:', round(float((Tn < 0.5).mean() / board.mean()), 2),
          'by 0.9:', round(float((Tn < 0.9).mean() / board.mean()), 2))


if __name__ == '__main__':
    main(sys.argv[1])

"""Ore nodes for mining with the Pounce (MINES_PLAN.md): a lumpy rock studded with ore, in four states
(whole, chipped, cracked, burst), for copper, iron, lumen crystal and obsidian, seen from the walking
camera (35 degrees down) so they stand in the walkable maps and the mine like your Evochi does; and a
nugget of each, the piece that pops out and arcs into your satchel. Same flat look as the items.

    python3 mining_art.py      -> flutter/assets/art/mining/ore_<kind>_<state>.webp, nugget_<kind>.webp,
                                  mining.json (each sprite's ground point, its height in world units)

State 0 is whole; 1 a first crack from where the hit landed; 2 cracked through, a chunk knocked off;
3 burst: the stump and some stone chips (the ore itself has flown out as nuggets).
"""
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_characters import fit_for  # noqa: E402
from build_items import LIGHT  # noqa: E402
from village_scenes import CPainter  # noqa: E402
from voxel import Camera, Light, Model, project_px, render  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'flutter', 'assets', 'art', 'mining')
ORES = {   # stone, ore colours, glow, how many hits it takes with no gear (copper: 3)
    'copper': (['#8E8A86', '#7B7773', '#A39E98'], ['#D9844A', '#B8622E', '#F0A56A'], None, 3),
    'iron': (['#7D7A80', '#6B6870', '#8F8B93'], ['#C9CDD6', '#9EA4B0', '#E6E9EF'], None, 4),
    'lumen': (['#6E6A78', '#5E5A68', '#7F7A8A'], ['#9FF0DA', '#6FD8C0', '#D8FFF4'], 0.8, 4),
    'obsidian': (['#4A4550', '#3C3742', '#57525E'], ['#2A2230', '#5B3B6E', '#9A6BC0'], 0.35, 5),
}
NODE_H = 2.4             # a node's height in the world (an Elder in the village is 4.1)
NUGGET_H = 0.7
SCALE = 16.0             # sprite px per model unit (a node is ~7.5 units tall: ~120 px; drawn at ~0.8x on a phone)
CAM = Camera(yaw=0.0, pitch=35.0)
# rock wants more modelling than the characters' soft flat light: a stronger key from the scene's sun side
ROCK_LIGHT = Light(ambient=0.62, key_amt=0.55, ao_amt=0.32, smooth=0.45, smooth_sigma=1.0, jitter=0.03)


def _lump(M, c, half, p=3.0):
    (cx, cy, cz), (a, b, cc) = c, half
    return (np.abs((M.X - cx) / a) ** p + np.abs((M.Y - cy) / b) ** p + np.abs((M.Z - cz) / cc) ** p) < 1.0


# where the ore shows on the rock: (x, y, z, size) on its faces toward you and on top
SEAMS = ((-2.6, 3.6, 3.3, 1.15), (1.2, 4.8, 2.9, 1.0), (3.4, 2.4, 2.6, 0.95), (-0.4, 1.6, 3.9, 0.9), (-3.9, 1.4, 1.9, 0.8),
         (0.6, 6.6, 0.4, 1.0), (-1.8, 5.9, 1.2, 0.8), (2.9, 4.4, -0.8, 0.85), (-3.4, 4.6, -1.0, 0.75))
# which seams are gone by each state (knocked out with the chunk, or flown out as nuggets)
GONE = {0: (), 1: (), 2: (1, 2), 3: tuple(range(len(SEAMS)))}


def ore_node(kind, stage, seed=7):
    """The node in [stage] (0 whole, 1 chipped, 2 cracked, 3 burst): a chunky boulder of a few rounded
    blocks, banded, with the ore standing proud of it in clusters (copper with green malachite stains
    round it, iron in bright blocky chunks, lumen as glowing crystal points, obsidian as glassy shards)."""
    stone, ore, glow, _ = ORES[kind]
    M = Model((-7, -1, -7), (7, 11, 7), [], res=3)
    P = CPainter(M, seed)
    rng = np.random.default_rng(seed)
    X, Y, Z = M.X, M.Y, M.Z
    rock = (_lump(M, (0, 3.3, 0), (4.6, 3.5, 4.0)) | _lump(M, (-2.4, 2.0, 1.4), (2.9, 2.2, 2.7)) |
            _lump(M, (2.8, 1.7, -0.8), (2.6, 1.9, 2.8)) | _lump(M, (0.6, 5.7, -0.4), (2.8, 1.6, 2.5))) & (Y >= 0)
    if stage == 3:
        rock &= Y < 1.5 + 0.5 * np.sin(X * 1.7) + 0.3 * np.cos(Z * 2.1)      # the stump
    band = (np.floor(Y * 1.1 + 0.6 * np.sin(X * 0.7 + Z * 0.4)).astype(int) % 3)
    dark = [stone[1]] + stone[1:2]
    for k, cols in enumerate((stone, dark, stone)):
        P.fill(rock & (band == k), cols, cell=(1.0, 0.67, 1.0))
    if stage == 2:
        rock &= ~(((X - 3.2) ** 2 + (Y - 6.0) ** 2 + (Z - 2.0) ** 2) < 2.7 ** 2)
        M.m[~rock] = 0
    # the ore, proud of the rock
    for i, (x, y, z, r) in enumerate(SEAMS):
        if i in GONE[stage] or y > (1.5 if stage == 3 else 99):
            continue
        d = np.array([x, y - (3.0 if kind in ('copper', 'iron') else 0.5), z])     # crystals and shards point up and out
        d = d / np.linalg.norm(d)
        cx, cy, cz = x + d[0] * 0.35, y + d[1] * 0.35, z + d[2] * 0.35
        if kind == 'copper':                                   # rounded nodules
            blob = ((X - cx) ** 2 + (Y - cy) ** 2 + (Z - cz) ** 2) < r ** 2
            blob |= ((X - cx - 0.5 * r) ** 2 + (Y - cy + 0.3 * r) ** 2 + (Z - cz) ** 2) < (0.6 * r) ** 2
            stain = (((X - cx) ** 2 + (Y - cy) ** 2 + (Z - cz) ** 2) < (r + 0.6) ** 2) & rock & (rng.random(M.m.shape) < 0.2)
            P.fill(stain & (M.m > 0), ['#3E9E6E', '#57B784', '#4C8F67'], cell=0.34)
        elif kind == 'iron':                                   # blocky chunks
            blob = (np.abs(X - cx) < r * 0.8) & (np.abs(Y - cy) < r * 0.7) & (np.abs(Z - cz) < r * 0.8)
            blob |= (np.abs(X - cx - 0.6 * r) < r * 0.45) & (np.abs(Y - cy - 0.5 * r) < r * 0.45) & (np.abs(Z - cz) < r * 0.5)
        else:                                                  # crystal points / glass shards, along the way out
            t = (X - x) * d[0] + (Y - y) * d[1] + (Z - z) * d[2]
            perp = np.sqrt(np.maximum((X - x) ** 2 + (Y - y) ** 2 + (Z - z) ** 2 - t ** 2, 0))
            ln = r * (2.9 if kind == 'lumen' else 2.5)
            blob = (t > -0.6) & (t < ln) & (perp < r * 0.7 * (1 - np.clip(t / ln, 0, 1) ** 1.4) + 0.15)
            if kind == 'obsidian':
                blob &= (np.abs((X - x) * d[2] - (Z - z) * d[0]) < r * 0.6)    # flat, like a flake
        if glow:
            P.fill(blob, ore, glow=glow, cell=0.34)
        else:
            P.fill(blob, ore, cell=0.34)
        hi = blob & ~np.roll(blob, -1, 1)                      # the top of each piece catches the light
        M.set(hi & (rng.random(M.m.shape) < 0.5), ore[2])
    if stage in (1, 2):
        # cracks run over the face toward you, from where the head lands (low and to the front)
        lines = [[(-0.2, 6.6), (0.4, 5.0), (-0.3, 3.8), (0.5, 2.4), (0.0, 0.4)]]
        if stage == 2:
            lines += [[(0.4, 5.0), (2.4, 4.4), (3.8, 3.0)], [(-0.3, 3.8), (-2.6, 3.2), (-4.0, 1.6)], [(0.5, 2.4), (2.4, 1.0)]]
        crack = np.zeros(M.m.shape, bool)
        w = 0.3 if stage == 1 else 0.45
        for ln in lines:
            for (x0, y0), (x1, y1) in zip(ln, ln[1:]):
                t = np.clip(((X - x0) * (x1 - x0) + (Y - y0) * (y1 - y0)) / ((x1 - x0) ** 2 + (y1 - y0) ** 2), 0, 1)
                d = np.hypot(X - (x0 + t * (x1 - x0)), Y - (y0 + t * (y1 - y0)))
                crack |= d < w
        crack &= (M.m > 0) & (Z > 0.5)
        surf = crack & ~np.roll(M.m > 0, -1, 2)
        if stage == 2:
            M.m[surf] = 0                                       # the deepest cracks open
        M.set(crack & (M.m > 0), '#2A2426')
    if stage == 3:
        for (x, y, z, r) in ((-4.6, 0.5, -1.0, 0.7), (4.8, 0.5, 0.4, 0.6), (2.0, 0.4, -3.6, 0.6), (-2.2, 0.4, 3.8, 0.6), (3.6, 0.4, 3.2, 0.5)):
            M.set(((X - x) ** 2 + (Y - y) ** 2 + (Z - z) ** 2) < r ** 2, stone[1])
    return M


def nugget(kind, seed=3):
    """One piece of ore, lumpy, a little stone still on it."""
    stone, ore, glow, _ = ORES[kind]
    M = Model((-2, -1, -2), (2, 3, 2), [], res=4)
    P = CPainter(M, seed)
    X, Y, Z = M.X, M.Y, M.Z
    n = np.sin(X * 3.1) * np.cos(Z * 2.7 + 0.4) * 0.12
    body = ((X / 1.3) ** 2 + ((Y - 0.9) / 0.95) ** 2 + (Z / 1.1) ** 2 + n) < 1.0
    if kind in ('lumen', 'obsidian'):                         # crystal and glass: faceted, pointed
        body = (np.abs(X) * 0.9 + np.abs(Z) * 0.9 + np.abs(Y - 0.9) * 0.7 < 1.25) & (Y >= -0.1)
    if glow:
        P.fill(body, ore, glow=glow, cell=0.5)
    else:
        P.fill(body, ore, cell=0.5)
    if kind in ('copper', 'iron'):
        rng = np.random.default_rng(seed)
        P.fill(body & (rng.random(M.m.shape) < 0.12) & (Y < 0.9), stone, cell=0.5)
    return M


def shot(M, scale):
    fit = fit_for([M], CAM, scale)
    o = render(M, {}, CAM, fit.w, fit.h, fit=fit, light=ROCK_LIGHT, ss=3, outline_px=2.2, outline_col='#3B2923',
               inner_thresh=2.0, inner_alpha=0.55, inner_px=0.8)
    g = project_px(CAM, fit, [(0, 0, 0)])[0]
    return o.rgba, (float(g[0]), float(g[1]))


def main():
    os.makedirs(OUT, exist_ok=True)
    meta = {'nodeH': NODE_H, 'nuggetH': NUGGET_H, 'ores': {}}
    whole_top = {}
    for kind, (_, _, _, hits) in ORES.items():
        states = []
        for st in range(4):
            rgba, g = shot(ore_node(kind, st), SCALE)
            ys = np.nonzero(rgba[..., 3].max(1) > 40)[0]
            if st == 0:
                whole_top[kind] = g[1] - ys[0]                 # px from the ground to the top of the whole rock
            fn = f'ore_{kind}_{st}.webp'
            Image.fromarray(rgba, 'RGBA').save(os.path.join(OUT, fn), 'WEBP', lossless=True, quality=100, method=6)
            states.append({'src': f'assets/art/mining/{fn}', 'w': rgba.shape[1], 'h': rgba.shape[0], 'ground': [round(g[0], 1), round(g[1], 1)]})
        rgba, g = shot(nugget(kind), SCALE * 2)
        fn = f'nugget_{kind}.webp'
        Image.fromarray(rgba, 'RGBA').save(os.path.join(OUT, fn), 'WEBP', lossless=True, quality=100, method=6)
        meta['ores'][kind] = {'hits': hits, 'states': states,
                              # world units per sprite px: the whole rock is NODE_H tall
                              'unit': round(NODE_H / whole_top[kind], 5),
                              'nugget': {'src': f'assets/art/mining/{fn}', 'w': rgba.shape[1], 'h': rgba.shape[0],
                                         'ground': [round(g[0], 1), round(g[1], 1)], 'unit': round(NODE_H / whole_top[kind] / 2, 5)}}
        print(kind, [s['w'] for s in states], flush=True)
    with open(os.path.join(OUT, 'mining.json'), 'w') as f:
        json.dump(meta, f, indent=1)


if __name__ == '__main__':
    main()

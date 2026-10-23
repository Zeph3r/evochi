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


def _boulder(M, grow=0.0):
    """The rock: a few rounded blocks run together, low and wide (never a cube)."""
    g = 1.0 + grow
    return ((_lump(M, (0, 2.9, 0), (4.6 * g, 3.0 * g, 4.0 * g), 2.6) | _lump(M, (-2.5, 1.8, 1.3), (2.9 * g, 2.0 * g, 2.7 * g), 2.4) |
             _lump(M, (2.7, 1.6, -0.6), (2.7 * g, 1.8 * g, 2.9 * g), 2.4)) & (M.Y >= 0))


def _cracks(M, rock, stage):
    """Cracks over the face toward you, from where the head lands (low and to the front)."""
    X, Y, Z = M.X, M.Y, M.Z
    lines = [[(-0.2, 5.8), (0.4, 4.4), (-0.3, 3.2), (0.5, 1.8), (0.0, 0.3)]]
    if stage == 2:
        lines += [[(0.4, 4.4), (2.4, 3.8), (3.8, 2.4)], [(-0.3, 3.2), (-2.6, 2.6), (-4.0, 1.2)], [(0.5, 1.8), (2.4, 0.8)]]
    crack = np.zeros(M.m.shape, bool)
    w = 0.3 if stage == 1 else 0.45
    for ln in lines:
        for (x0, y0), (x1, y1) in zip(ln, ln[1:]):
            t = np.clip(((X - x0) * (x1 - x0) + (Y - y0) * (y1 - y0)) / ((x1 - x0) ** 2 + (y1 - y0) ** 2), 0, 1)
            crack |= np.hypot(X - (x0 + t * (x1 - x0)), Y - (y0 + t * (y1 - y0))) < w
    crack &= rock & (Z > 0.5) & (M.m > 0)
    if stage == 2:
        M.m[crack & ~np.roll(M.m > 0, -1, 2)] = 0          # the deepest cracks open
    M.set(crack & (M.m > 0), '#2A2426')


def _prism(M, base, d, r, length):
    """A crystal: a column from [base] along [d] that comes to a point (faceted: a diamond cross-section)."""
    X, Y, Z = M.X, M.Y, M.Z
    d = np.asarray(d, float) / np.linalg.norm(d)
    a = np.cross(d, [0.0, 0.0, 1.0] if abs(d[2]) < 0.9 else [1.0, 0.0, 0.0])
    a /= np.linalg.norm(a)
    b = np.cross(d, a)
    px, py, pz = X - base[0], Y - base[1], Z - base[2]
    t = px * d[0] + py * d[1] + pz * d[2]
    u = np.abs(px * a[0] + py * a[1] + pz * a[2])
    v = np.abs(px * b[0] + py * b[1] + pz * b[2])
    taper = np.clip((length - t) / (length * 0.32), 0, 1)        # the last third narrows to the tip
    return (t > -0.4) & (t < length) & (u + v < r * taper + 0.1)


def _bud(M, base, d, r, length):
    """A lumen bud: a soft, rounded swelling from [base] along [d], fattest past its middle and round at the
    tip (no facets, nothing like a cut gem). Returns the shape and how far along it each voxel is (0-1)."""
    X, Y, Z = M.X, M.Y, M.Z
    d = np.asarray(d, float) / np.linalg.norm(d)
    px, py, pz = X - base[0], Y - base[1], Z - base[2]
    t = px * d[0] + py * d[1] + pz * d[2]
    perp = np.sqrt(np.maximum(px * px + py * py + pz * pz - t * t, 0))
    u = np.clip(t / length, 0, 1)
    prof = r * np.sqrt(np.clip(1 - ((u - 0.55) / 0.55) ** 2, 0, 1)) * (0.75 + 0.25 * u)
    return (t > -0.3) & (t < length) & (perp < prof + 0.08), u


def _flake(M, c, n, r, thick=0.32, spin=0.0):
    """A flake of volcanic glass: a thin angular shard (a diamond outline in its own plane, longer one
    way), thickest in the middle and sharp at its rim."""
    X, Y, Z = M.X, M.Y, M.Z
    n = np.asarray(n, float) / np.linalg.norm(n)
    a = np.cross(n, [0.0, 1.0, 0.0] if abs(n[1]) < 0.9 else [1.0, 0.0, 0.0])
    a /= np.linalg.norm(a)
    b = np.cross(n, a)
    a, b = a * np.cos(spin) + b * np.sin(spin), b * np.cos(spin) - a * np.sin(spin)
    px, py, pz = X - c[0], Y - c[1], Z - c[2]
    h = px * n[0] + py * n[1] + pz * n[2]
    u = np.abs(px * a[0] + py * a[1] + pz * a[2]) / (r * 1.3)
    v = np.abs(px * b[0] + py * b[1] + pz * b[2]) / (r * 0.8)
    q = u + v
    return (q < 1.0) & (np.abs(h) < thick * (1 - q ** 2) + 0.06), q


ROCK = {   # each ore's rock: none of them a grey stone with specks
    'copper': ['#BFA07C', '#AE8F6C', '#CCAE8A'],          # warm sandstone
    'iron': ['#6E4A44', '#5E3E3A', '#7C5650'],            # dark, rust-stained
    'lumen': ['#5A5F72', '#4E5366', '#666B80'],           # slate blue
    'obsidian': ['#3E3A42', '#35313A', '#47434C'],        # basalt
}
COPPER = ['#D9844A', '#C46B34', '#E8945A']
IRON_SILVER = ['#B9C0C8', '#A3AAB3', '#CDD3DA']
IRON_RUST = ['#9A4B3A', '#8A4232']
LUMEN = ['#6FE3C0', '#62D6B3', '#7FEBCB']                 # the game's lumen mint (the Lumenbud, the shards)
LUMEN_CORE = ['#2E8F82', '#2A8076']
LUMEN_TIP = ['#C9F8E8', '#B5F2DD']
GLASS = ['#1E1724', '#251C2C', '#2E2338']


def ore_node(kind, stage, seed=7):
    """The node in [stage] (0 whole, 1 chipped, 2 cracked, 3 burst). The ore is never specks in stone:
    copper bulges out of sandstone in fat rounded nodules; iron runs through dark rock in bands with
    bright metal ridges; lumen crystal bursts from the top in a cluster of glowing prisms; obsidian is a
    heap of glossy black glass flakes with a violet sheen at their edges."""
    M = Model((-7, -1, -7), (7, 12, 7), [], res=3)
    P = CPainter(M, seed)
    rng = np.random.default_rng(seed)
    X, Y, Z = M.X, M.Y, M.Z
    rock = _boulder(M)
    if stage == 3:
        rock &= Y < 1.4 + 0.5 * np.sin(X * 1.7) + 0.3 * np.cos(Z * 2.1)   # the stump
    if stage == 2:
        rock &= ~(((X - 3.0) ** 2 + (Y - 4.6) ** 2 + (Z - 2.0) ** 2) < 2.4 ** 2)   # a chunk knocked off
    band = np.floor(Y * 1.0 + 0.5 * np.sin(X * 0.6 + Z * 0.4)).astype(int) % 2
    P.fill(rock & (band == 0), ROCK[kind], cell=(1.0, 0.67, 1.0))
    P.fill(rock & (band == 1), ROCK[kind][1:] + ROCK[kind][1:], cell=(1.0, 0.67, 1.0))
    keep = (lambda i: True) if stage < 2 else (lambda i: i % 3 != 1) if stage == 2 else (lambda i: False)
    if kind == 'copper':
        nods = ((-2.5, 3.2, 2.9, 1.9), (1.5, 4.7, 2.4, 1.7), (3.6, 2.0, 2.7, 1.5), (-0.4, 1.5, 3.9, 1.4), (0.4, 5.9, -0.4, 1.8),
                (-3.9, 3.8, -1.2, 1.4), (3.2, 4.2, -1.9, 1.3), (-1.2, 5.6, 1.4, 1.2))
        for i, (x, y, z, r) in enumerate(nods):
            if not keep(i):
                continue
            blob = ((X - x) ** 2 + (Y - y) ** 2 + (Z - z) ** 2) < r ** 2
            blob |= ((X - x - 0.6 * r) ** 2 + (Y - y + 0.35 * r) ** 2 + (Z - z + 0.2) ** 2) < (0.62 * r) ** 2   # bunched, like grapes
            blob |= ((X - x + 0.5 * r) ** 2 + (Y - y - 0.4 * r) ** 2 + (Z - z + 0.3) ** 2) < (0.55 * r) ** 2
            P.fill(blob & (M.m == 0) | blob & rock, COPPER, cell=0.34)
            top = blob & ~np.roll(blob, -1, 1)
            M.set(top & (rng.random(M.m.shape) < 0.6), '#FFC48E')            # sun on their tops
            M.set(blob & ~np.roll(blob, 1, 1) & (Y > 0.4), '#8A4420')         # dark undersides
    elif kind == 'iron':   # a vein of metal running across the rock, standing proud of it in thick ribs
        out = _boulder(M, 0.12) & (Y >= 0)
        if stage == 3:
            out &= Y < 1.7
        if stage == 2:
            out &= ~(((X - 3.0) ** 2 + (Y - 4.6) ** 2 + (Z - 2.0) ** 2) < 2.6 ** 2)
        n = np.array([0.75, 0.6, 0.28]) / np.linalg.norm([0.75, 0.6, 0.28])
        dd = X * n[0] + (Y - 3.0) * n[1] + Z * n[2]
        for c, w in ((-1.6, 0.55), (0.6, 0.75), (2.6, 0.45)):
            rib = out & (np.abs(dd - c) < w)
            P.fill(rib, IRON_SILVER, cell=0.5)
            M.set(rib & ~np.roll(rib, -1, 1) & (rng.random(M.m.shape) < 0.6), '#EEF2F6')   # catching the light
            M.set(rib & (np.abs(dd - c) > w - 0.2), '#7E858E')                             # its darker edges
        P.fill(rock & (np.abs(dd + 0.5) < 0.3) & ~np.roll(rock, -1, 2), IRON_RUST, cell=0.67)   # rust weeping between
    elif kind == 'lumen':   # soft glowing buds swelling out of a crack in the top, like Lumenbuds in stone
        buds = ((0.0, 4.4, 0.3, (0.05, 1.0, 0.2), 1.35, 4.2), (-1.7, 4.0, 0.9, (-0.6, 1.0, 0.35), 1.1, 3.3), (1.8, 4.1, 0.5, (0.6, 1.0, 0.25), 1.15, 3.5),
                (0.4, 4.0, -1.5, (0.15, 1.0, -0.5), 0.95, 2.8), (-0.7, 3.8, 2.1, (-0.15, 0.8, 0.8), 0.9, 2.5), (2.9, 2.9, 2.0, (0.8, 0.6, 0.6), 0.7, 1.9),
                (-3.1, 2.5, 1.7, (-0.85, 0.5, 0.5), 0.65, 1.7))
        hole = ((X ** 2) / 2.8 ** 2 + ((Y - 5.4) ** 2) / 1.6 ** 2 + (Z ** 2) / 2.4 ** 2 < 1.0)  # the top split open round the cluster
        M.m[hole & rock & (Y > 4.5)] = 0
        for i, (x, y, z, d, r, ln) in enumerate(buds):
            if not keep(i):
                continue
            body, t = _bud(M, (x, y, z), d, r * 0.9, ln * 1.3 * (0.6 if stage == 2 and i == 0 else 1.0))
            P.fill(body & (t < 0.38), LUMEN_CORE, glow=0.35, cell=0.34)        # a deep teal heart low down
            P.fill(body & (t >= 0.38) & (t < 0.78), LUMEN, glow=0.75, cell=0.34)
            P.fill(body & (t >= 0.78), LUMEN_TIP, glow=1.0, cell=0.34)         # brightest at the tip
    else:   # obsidian: a low basalt bed under a heap of big glass shards leaning every way
        M.m[rock & (Y > 2.4 + 0.4 * np.sin(X * 0.9))] = 0
        flakes = ((-1.8, 3.8, 1.2, (-0.6, 0.35, 1.0), 3.0, 0.3), (1.9, 4.4, 0.6, (0.8, 0.4, 0.9), 2.9, 1.2), (0.0, 5.0, -1.4, (0.1, 0.45, 1.0), 3.2, 0.0),
                  (-0.2, 2.6, 3.0, (0.25, 0.3, 1.0), 2.2, 0.7))
        for i, (x, y, z, n, r, sp) in enumerate(flakes):
            if not keep(i):
                continue
            fl, q = _flake(M, (x, y, z), n, r, 0.42, sp)
            fl &= Y >= 0
            P.fill(fl, [GLASS[i % 3]], cell=1.0)                                 # each shard one smooth glass
            M.set(fl & (q > 0.86), '#9A6BC0')                                  # violet sheen at the rim
            M.set(fl & (q < 0.5) & (q > 0.3) & (np.abs(X - x - (Y - y) * 0.6) < 0.35), '#6E4A86')   # a gleam across its face
    if stage in (1, 2):
        _cracks(M, rock, stage)
    if stage == 3:
        for (x, y, z, r) in ((-4.6, 0.5, -1.0, 0.7), (4.8, 0.5, 0.4, 0.6), (2.0, 0.4, -3.6, 0.6), (-2.2, 0.4, 3.8, 0.6), (3.6, 0.4, 3.2, 0.5)):
            M.set(((X - x) ** 2 + (Y - y) ** 2 + (Z - z) ** 2) < r ** 2, ROCK[kind][1])
    return M


def nugget(kind, seed=3):
    """The piece that pops out: a bunched copper nodule, a banded iron chunk, one lumen prism, a glass flake."""
    M = Model((-2.5, -1, -2.5), (2.5, 4, 2.5), [], res=4)
    P = CPainter(M, seed)
    X, Y, Z = M.X, M.Y, M.Z
    if kind == 'copper':
        b = (((X ** 2 + (Y - 0.9) ** 2 + Z ** 2) < 1.0) | (((X - 0.6) ** 2 + (Y - 0.6) ** 2 + (Z - 0.2) ** 2) < 0.55) |
             (((X + 0.5) ** 2 + (Y - 1.3) ** 2 + (Z + 0.2) ** 2) < 0.45))
        P.fill(b, COPPER, cell=0.25)
        M.set(b & ~np.roll(b, -1, 1), '#FFC48E')
    elif kind == 'iron':   # a lump of rust-red rock with a rib of bright metal standing proud across it
        b = (np.abs(X / 1.25) ** 2.2 + np.abs((Y - 0.8) / 0.85) ** 2.2 + np.abs(Z / 1.0) ** 2.2) < 1.0
        n = np.array([0.75, 0.6, 0.28]) / np.linalg.norm([0.75, 0.6, 0.28])
        rib = ((np.abs(X / 1.45) ** 2.2 + np.abs((Y - 0.8) / 1.05) ** 2.2 + np.abs(Z / 1.2) ** 2.2) < 1.0) & \
            ((np.abs(X * n[0] + (Y - 0.8) * n[1] + Z * n[2] - 0.35) < 0.2) | (np.abs(X * n[0] + (Y - 0.8) * n[1] + Z * n[2] + 0.45) < 0.14))
        rib &= ~b                                           # only where it stands proud of the lump
        P.fill(b, ROCK['iron'], cell=0.5)
        P.fill(b & ~np.roll(b, -1, 1) & (np.sin(X * 3 + Z * 2) > 0.6), IRON_RUST, cell=0.5)
        P.fill(rib, IRON_SILVER, cell=0.25)
        M.set(rib & ~np.roll(rib, -1, 1), '#EEF2F6')
    elif kind == 'lumen':
        b, t = _bud(M, (0, 0, 0), (0.15, 1.0, 0.1), 1.0, 2.8)
        P.fill(b & (t < 0.38), LUMEN_CORE, glow=0.35, cell=0.25)
        P.fill(b & (t >= 0.38) & (t < 0.78), LUMEN, glow=0.75, cell=0.25)
        P.fill(b & (t >= 0.78), LUMEN_TIP, glow=1.0, cell=0.25)
    else:
        b, q = _flake(M, (0, 1.2, 0), (0.35, 0.55, 0.9), 1.4, 0.45, 0.9)
        P.fill(b, GLASS, cell=0.25)
        M.set(b & (q > 0.75), '#9A6BC0')
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
    icons()


ITEM_IDS = {'copper': 'copper_ore', 'iron': 'iron_ore', 'lumen': 'lumen_crystal', 'obsidian': 'obsidian_shard'}


def icons():
    """The ores' Bag icons (168 px, like the other items), listed in the art manifest."""
    from build_items import render_model
    items = os.path.join(OUT, '..', 'items')
    mp = os.path.join(OUT, '..', 'manifest.json')
    with open(mp) as f:
        man = json.load(f)
    cam = Camera(yaw=30.0, pitch=24.0)
    for kind, item in ITEM_IDS.items():
        rgba = render_model(nugget(kind), cam, 168, outline=2.4)
        Image.fromarray(rgba, 'RGBA').save(os.path.join(items, f'{item}.webp'), 'WEBP', quality=92, method=6)
        man['items'][item] = f'items/{item}.webp'
    with open(mp, 'w') as f:
        json.dump(man, f, indent=1)


if __name__ == '__main__':
    main()

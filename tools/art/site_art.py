"""Marketing-site art: a wide hero vista with a three-step voxel stair for the evolution line.

python3 site_art.py OUT_DIR [--scale 0.5]

Writes hero_{sky,far,mid,near}.png, hero_composite.png and hero.json. The JSON gives each
pet's ground anchor (fraction of width/height) and the scene's pixels per world unit there,
so the site can place the separate character sprites at the right size.
"""
import json
import math
import os
import sys
import time

import cv2
import numpy as np
from PIL import Image

from voxel import Model, Camera, project_px, save_rgba, hexrgb
import scenes as S
from scenes import (Painter, Layer, Scene, GRASS, DIRT, STONE, WOOD_PL, LEAVES, terrace_cliffs, ground,
                    grass_tufts, daisy, tree)

# Pets stand on the stair tops. World units; y is the block top.
STEPS = (
    # name, x0, x1, z0, z1, height
    ('s01', -11.5, -4.5, -0.5, 6.0, 1.5),
    ('s02', -4.5, 2.5, -4.0, 3.0, 3.5),
    ('s03', 2.5, 13.5, -8.0, 0.5, 5.5),
)
# sprite master px per model unit, and model->world scale per stage
MASTER_PX_PER_UNIT = 14.0
WORLD_SCALE = {'s01': 0.17, 's02': 0.2, 's03': 0.215}   # site: a clearer size progression than in-game


def hero_sky(sc):
    w, h = sc.w, sc.h
    top, hor = hexrgb('#5FB1E6'), hexrgb('#D6EDFB')
    t = np.linspace(0, 1, h)[:, None]
    t = np.clip(t / 0.62, 0, 1) ** 1.15
    g = top * (1 - t[..., None]) + hor * t[..., None]
    img = np.repeat(g, w, axis=1).astype(np.float32)
    rng = np.random.default_rng(sc.seed)
    cl = np.zeros((h, w), np.float32)
    base = h * 0.9
    for i in range(11):
        cx = (i + rng.uniform(0.1, 0.9)) / 11 * w
        cy = rng.uniform(0.05, 0.36) * h
        s = rng.uniform(0.05, 0.10) * base
        for _ in range(7):
            ox = cx + rng.uniform(-1.4, 1.4) * s
            oy = cy + rng.uniform(-0.3, 0.25) * s
            r = s * rng.uniform(0.35, 0.7)
            cv2.rectangle(cl, (int(ox - r), int(oy - r * 0.6)), (int(ox + r), int(oy + r * 0.45)), 1.0, -1)
    cl = cv2.GaussianBlur(cl, (0, 0), base * 0.006)
    img = img * (1 - cl[..., None] * 0.92) + np.array([255, 255, 255]) * cl[..., None] * 0.92
    # floating islands, sized from the height so they stay small on a wide frame
    for (fx, fy, fs) in ((0.86, 0.10, 0.075), (0.955, 0.17, 0.045), (0.40, 0.08, 0.04), (0.70, 0.16, 0.03),
                         (0.12, 0.13, 0.05)):
        x, y, r = int(fx * w), int(fy * h), int(fs * h)
        top_c = np.array([110, 185, 90], float)
        dirt = np.array([186, 150, 110], float)
        for k in range(5):
            ww = int(r * (1 - k * 0.18))
            y0 = y + k * int(r * 0.22)
            cv2.rectangle(img, (x - ww, y0), (x + ww, y0 + int(r * 0.22)), (dirt * (0.95 - k * 0.04)).tolist(), -1)
        cv2.rectangle(img, (x - r, y - int(r * 0.18)), (x + r, y), top_c.tolist(), -1)
        for tx in (x - int(r * 0.45), x + int(r * 0.2)):
            cv2.rectangle(img, (tx - int(r * 0.18), y - int(r * 0.55)), (tx + int(r * 0.18), y - int(r * 0.18)),
                          (90, 165, 75), -1)
        cv2.rectangle(img, (x + int(r * 0.35), y + int(r * 0.6)), (x + int(r * 0.45), y + int(r * 1.7)),
                      (230, 245, 252), -1)
    img = cv2.GaussianBlur(img, (0, 0), 1.6 * h / 1440)
    a = np.full((h, w, 1), 255, np.float32)
    return np.dstack([np.clip(img, 0, 255), a]).astype(np.uint8)


def scene_site_hero(w=2880, h=1440, seed=11):
    rng = np.random.default_rng(seed)
    cam = Camera(yaw=0, pitch=5, target=(1, 6.0, 0), persp=50, fov=34)
    layers = []

    # far: terraced cliffs with waterfalls, wide enough for a 2:1 frame
    F = Model((-280, -2, -200), (280, 70, -40), [], res=1)
    PF = Painter(F, rng)
    lake = (F.Y >= -1) & (F.Y < 0) & (F.Z >= -64) & (F.Z < -40)
    PF.fill(lake, S.WATER)
    terrace_cliffs(F, PF, rng, (-280, 280), (-170, -62), 4, 24, steps=4,
                   falls=((-70, 8, -66), (-18, 7, -70), (40, 8, -66), (95, 6, -72), (-130, 7, -70), (150, 7, -68)),
                   trees=60)
    far2 = (F.Z < -175) & (F.Y < 34 + 8 * np.sin(F.X / 15.0)) & (F.Y >= 0)
    PF.fill(far2, ['#9DBF8F', '#A7C79A'])
    layers.append(Layer('far', F, blur=5.0, haze=0.26, haze_col='#CBE6F2', inner_alpha=0.15))

    # mid: meadow, the three-step stair, framing trees, lantern post
    M = Model((-80, -6, -40), (60, 30, 12), [], res=2)
    P = Painter(M, rng)
    xs = M.X[:, 0, 0]
    zs = M.Z[0, 0, :]
    X2, Z2 = np.meshgrid(xs, zs, indexing='ij')
    Hn = cv2.resize(rng.random((40, 18)).astype(np.float32), (len(zs), len(xs)), interpolation=cv2.INTER_NEAREST)
    H = np.round((Hn - 0.5) * 1.0) / 2
    near_stairs = (X2 > -15) & (X2 < 17) & (Z2 > -11) & (Z2 < 9)
    H = np.where(near_stairs, 0, H)
    H = np.where(Z2 < -36, -0.5, H)
    path = lambda X, Z: (np.abs(Z - 8.0 - 0.06 * X) < 1.4) & (X > -40) & (X < 30)
    ground(M, P, rng, H, path=path)
    grass_tufts(M, P, H, ~near_stairs & ~path(X2, Z2), 0.07, rng, max_h=1.0)

    for (_, x0, x1, z0, z1, top) in STEPS:
        blk = (M.X >= x0) & (M.X < x1) & (M.Z >= z0) & (M.Z < z1) & (M.Y >= 0) & (M.Y < top)
        strata = np.floor(M.Y / 1.0).astype(int) % 2
        P.fill(blk & (strata == 0), [DIRT[0], DIRT[2]])
        P.fill(blk & (strata == 1), [DIRT[1], DIRT[0]])
        P.fill(blk & (M.Y >= top - 0.5), GRASS)
        lip = (M.X >= x0 - 0.5) & (M.X < x1 + 0.5) & (M.Z >= z0 - 0.5) & (M.Z < z1 + 0.5) & \
              (M.Y >= top - 1.0) & (M.Y < top) & ~blk
        P.fill(lip & (np.random.default_rng(int(top * 10)).random(M.m.shape) > 0.55), GRASS)
    # stone stepping slabs leading up to the stair
    for (sx, sz) in ((-14.5, 7.2), (-18.5, 7.8), (-22.5, 8.2)):
        slab = (np.abs(M.X - sx) <= 1.4) & (np.abs(M.Z - sz) <= 1.0) & (M.Y >= -0.5) & (M.Y < 0.5)
        P.fill(slab, STONE)

    # lantern post right of the stair
    px, pz = 19.5, -9.0
    post = (np.abs(M.X - px) <= 0.6) & (np.abs(M.Z - pz) <= 0.6) & (M.Y >= 0) & (M.Y < 20)
    P.fill(post, ['#6E4529', '#7A4E2E'])
    arm = (M.X >= px - 4) & (M.X < px) & (np.abs(M.Y - 19.5) <= 0.4) & (np.abs(M.Z - pz) <= 0.4)
    P.fill(arm, ['#6E4529'])
    lx, ly, lz = px - 3.4, 16.6, pz
    lf = (np.maximum(np.abs(M.X - lx), np.abs(M.Z - lz)) <= 1.2) & (M.Y >= ly - 1.6) & (M.Y < ly + 2)
    P.fill(lf, ['#FFD46A', '#FFE08A'], glow=1.0)
    P.fill(lf & ((M.Y >= ly + 1.5) | (M.Y < ly - 1.1)), ['#4A3328'])

    # framing trees and rocks
    for (tx, tz, th, tr) in ((-44, -16, 13, 6.0), (-30, -30, 10, 5.0), (30, -20, 12, 5.5), (46, -10, 14, 6.0),
                             (-62, -8, 12, 6.0), (54, -32, 9, 4.5), (-20, -34, 9, 4.5)):
        tree(M, P, (tx, 0, tz), trunk_h=th, r=tr, rng=rng)
        trunk = ((M.X - tx) ** 2 + (M.Z - tz) ** 2 <= 1.2 ** 2) & (M.Y >= 0) & (M.Y < th + 1)
        P.fill(trunk, ['#7A4E2E', '#8A5A34', '#6E4529'])
    for (rx_, rz_, rs) in ((-18, -2, 1.6), (-20.5, -4.5, 1.0), (17, 5, 1.2), (25, -2, 1.6), (-34, 2, 1.3)):
        rk = ((np.abs(M.X - rx_) / rs) ** 4 + (np.abs(M.Y) / (rs * 1.1)) ** 4 +
              (np.abs(M.Z - rz_) / (rs * 0.85)) ** 4) <= 1.3
        P.fill(rk & (M.Y >= -0.5), STONE)
    # fence on the far right
    p0, p1 = np.array([28.0, 0, 6.0]), np.array([40.0, 0, -12.0])
    for k in range(6):
        q = p0 + (p1 - p0) * k / 5
        pst = (np.abs(M.X - q[0]) <= 0.4) & (np.abs(M.Z - q[2]) <= 0.4) & (M.Y >= 0) & (M.Y < 3.4)
        P.fill(pst, ['#8A5A34'])
    d = (p1 - p0) / np.linalg.norm(p1 - p0)
    rx, rz = M.X - p0[0], M.Z - p0[2]
    t = rx * d[0] + rz * d[2]
    perp = np.abs(-rx * d[2] + rz * d[0])
    for ry in (1.3, 2.6):
        rail = (perp <= 0.25) & (t >= 0) & (t <= np.linalg.norm(p1 - p0)) & (np.abs(M.Y - ry) <= 0.3)
        P.fill(rail, WOOD_PL[:3])
    for _ in range(110):
        fx = rng.uniform(-70, 55)
        fz = rng.uniform(-34, 10)
        if near_stairs[np.argmin(np.abs(xs - fx)), np.argmin(np.abs(zs - fz))]:
            continue
        hh = H[np.argmin(np.abs(xs - fx)), np.argmin(np.abs(zs - fz))]
        petal = ['#FFFDF6', '#FFFDF6', '#F7B6C8', '#FFE08A'][rng.integers(0, 4)]
        daisy(M, P, (fx, hh + rng.uniform(0.6, 1.2), fz), size=rng.uniform(0.4, 0.55), petal=petal)
    layers.append(Layer('mid', M, inner_alpha=0.28))

    # near: soft-focus tufts and flowers along the bottom edge
    N = Model((-60, -6, 12), (44, 8, 24), [], res=2)
    PN = Painter(N, rng)
    xsn = N.X[:, 0, 0]
    zsn = N.Z[0, 0, :]
    X2n, Z2n = np.meshgrid(xsn, zsn, indexing='ij')
    Hn2 = np.round((cv2.resize(rng.random((30, 6)).astype(np.float32), (len(zsn), len(xsn)),
                               interpolation=cv2.INTER_NEAREST) - 0.5)) / 2
    ground(N, PN, rng, Hn2)
    grass_tufts(N, PN, Hn2, np.ones_like(X2n, bool), 0.2, rng, max_h=1.6)
    for _ in range(26):
        fx = rng.uniform(-55, 40)
        fz = rng.uniform(13, 20)
        daisy(N, PN, (fx, rng.uniform(1.0, 1.8), fz), size=rng.uniform(0.5, 0.7))
    layers.append(Layer('near', N, blur=3.0, inner_alpha=0.15))

    sc = Scene('site_hero', cam, w, h, (0.66, 0.56), ('#5FB1E6', '#D6EDFB'), layers, seed=seed, clouds=0)
    sc.pets = {name: ((x0 + x1) / 2, top, (z0 + z1) / 2 - 0.5) for (name, x0, x1, z0, z1, top) in STEPS}
    return sc


def px_per_unit(sc, fit, p):
    a = project_px(sc.cam, fit, [p])[0]
    b = project_px(sc.cam, fit, [(p[0] + 1, p[1], p[2])])[0]
    return float(np.linalg.norm(b - a))


def build(out, scale=1.0):
    t0 = time.time()
    sc = scene_site_hero(int(2880 * scale), int(1440 * scale))
    fit = S.make_fit(sc)
    imgs = [hero_sky(sc)]
    names = ['sky']
    for L in sc.layers:
        if L.blur:
            L.blur *= scale
        img, _ = S.render_layer(sc, L, fit)
        imgs.append(img)
        names.append(L.name)
    comp = S.composite(imgs)
    os.makedirs(out, exist_ok=True)
    for n, img in zip(names, imgs):
        save_rgba(img, os.path.join(out, f'hero_{n}.png'))
    Image.fromarray(comp[..., :3]).save(os.path.join(out, 'hero_composite.png'))
    pets = {}
    for name, p in sc.pets.items():
        g = project_px(sc.cam, fit, [p])[0]
        ppu = px_per_unit(sc, fit, p)
        pets[name] = {'x': round(g[0] / sc.w, 5), 'y': round(g[1] / sc.h, 5),
                      # sprite master pixels -> fraction of scene height
                      'k': round(ppu * WORLD_SCALE[name] / MASTER_PX_PER_UNIT / sc.h, 6)}
    meta = {'w': sc.w, 'h': sc.h, 'pets': pets}
    json.dump(meta, open(os.path.join(out, 'hero.json'), 'w'), indent=1)
    print('site hero done in %.1fs' % (time.time() - t0), meta, flush=True)


if __name__ == '__main__':
    out = sys.argv[1]
    scale = float(sys.argv[sys.argv.index('--scale') + 1]) if '--scale' in sys.argv else 1.0
    build(out, scale)

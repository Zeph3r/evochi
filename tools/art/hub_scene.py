"""The nest hub: the Sunlit Meadow re-dressed as a crossroads. Same camera, nest and decoration
slots as the meadow (scenes.scene_meadow), so placed decorations still line up; behind the nest the
path forks: up the left to the Cottage (ruined or restored, home_scenes.cottage), up the right through
the stone arch to Sunlit Village (its roofs beyond, where the meadow had its lake). Two sign posts
stand at the fork; their boards are a separate sprite (hub_sign_board), lettered and lit by the game.

    python3 hub_scene.py OUT_DIR [--scale 0.5] [--ruined]

Writes habitat_hub_<state>_{sky,far,mid,near}_day.png, a composite, the board sprite and
habitat_hub_<state>.json: the meadow's slots plus the hub's anchors (sign posts, the two walks, the
two destinations), each in scene pixels with px-per-unit for depth.
"""
from __future__ import annotations

import json
import math
import os
import sys
import time

import cv2
import numpy as np
from PIL import Image

from voxel import Model, Camera, Fit, Light, render, project_px, save_rgba
import scenes as SC
from scenes import Painter, Layer, Scene, portrait_cam, terrace_cliffs, ground, grass_tufts, daisy, tree
from village_scenes import (CPainter, box, gable, fence_line, outdoor_lantern, PLASTER, ROOF, HONEY, WALNUT,
                            STONE as VSTONE, STONE_LT)
from home_scenes import cottage


class _Kit:
    """What the Blender kit's builders expect of a scene (lights, glass); the flat renderer lights
    everything itself and glows what is marked to glow."""

    def __init__(self):
        self.lights = []
        self.models = []


# where things stand (world units; the nest at the origin, +z toward the camera)
LEFT_WALK = [(0.0, 0.0), (-2.0, -2.0), (-5.5, -6.5), (-8.5, -13.0), (-11.0, -19.5)]       # to the Cottage door
RIGHT_WALK = [(0.0, 0.0), (2.0, -2.0), (5.5, -6.5), (8.0, -13.0), (9.5, -19.0), (10.0, -24.0), (10.5, -30.0)]
SIGNS = {'home': (-7.6, -5.0), 'village': (7.6, -5.0)}
POST_H = 4.4
COTTAGE = (-17.5, -4.5, -29.0, -19.5)          # x0, x1, z0, z1 (door on +z)
GATE = (10.0, -24.0)                            # the arch's centre


def _seg(X, Z, a, b, w):
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    t = np.clip(((X - ax) * dx + (Z - az) * dz) / (dx * dx + dz * dz), 0, 1)
    return (X - ax - t * dx) ** 2 + (Z - az - t * dz) ** 2 <= w * w


def _walk_mask(X, Z, pts, w):
    m = np.zeros(X.shape, bool)
    for a, b in zip(pts[1:-1], pts[2:]):
        m |= _seg(X, Z, a, b, w)
    return m


def path_mask(X, Z, w=1.15):
    nest = np.sqrt((X * 0.9) ** 2 + (Z * 1.25) ** 2) < 4.5
    trunk = (np.abs(X - Z * 0.3 - 1.5) < 1.1) & (Z > 2)
    # a little wobble so the paths read as trodden, not ruled
    ww = w + 0.25 * np.sin(Z * 0.9 + X * 0.4)
    return nest | trunk | _walk_mask(X, Z, LEFT_WALK, ww) | _walk_mask(X, Z, RIGHT_WALK, ww)


def hub_far(rng, restored):
    """The meadow's far layer, with land on the right where the village stands; the lake and the
    waterfalls stay on the left."""
    F = Model((-110, -2, -190), (110, 80, -28), [], res=1)
    PF = Painter(F, rng)
    CF = CPainter(F, 17)
    shore = 3.0 + 0.35 * (F.Z + 30)                         # the lake gives way to land on the right
    lake = (F.Y >= -1) & (F.Y < 0) & (F.Z >= -58) & (F.Z < -30) & (F.X < shore)
    land = (F.Y >= -1) & (F.Y < 0) & (F.Z >= -58) & (F.Z < -28) & (F.X >= shore)
    PF.fill(lake, SC.WATER)
    PF.fill(land, SC.GRASS)
    PF.fill(land & (F.X < shore + 1.2), ['#E7DDC3', '#D9CDB4'])     # a sandy edge
    road = _seg(F.X[:, 0, :], F.Z[:, 0, :], (10.5, -28.0), (11.5, -38.0), 1.3) | \
        _seg(F.X[:, 0, :], F.Z[:, 0, :], (11.5, -38.0), (15.0, -56.0), 1.3)
    PF.fill(land & road[:, None, :], SC.DIRT)
    terrace_cliffs(F, PF, rng, (-110, 110), (-160, -58), 5, 40, steps=5,
                   falls=((-15, 8, -60), (-34, 6, -62), (-40, 6, -70)), trees=34)
    far2 = (F.Z < -165) & (F.Y < 58 + 10 * np.sin(F.X / 13.0)) & (F.Y >= 0)
    PF.fill(far2, ['#9DBF8F', '#A7C79A'])
    # Sunlit Village: plaster and red roofs along the road, a little blue one, trees between
    houses = ((5.5, -37.0, 6.0, 4.0, PLASTER, ROOF), (18.0, -40.0, 7.0, 4.5, PLASTER, ROOF),
              (8.0, -47.0, 5.0, 3.6, ['#DCE6EE', '#CFDCE6'], ['#3E5F7E', '#36546F', '#4A6C8C']),
              (21.0, -50.0, 6.0, 4.0, PLASTER, ROOF), (28.0, -38.0, 5.0, 3.4, PLASTER, ROOF))
    for (hx, hz, hw, hh, walls, roof) in houses:
        gable(CF, F, hx - hw / 2, hx + hw / 2, hz - 2.2, hz + 2.2, hh, 2.8, walls, roof, oh=0.6, ridge='x', wall_cell=(2, 2, 2))
        for wx in (hx - hw / 4, hx + hw / 4):
            CF.fill(box(F, (wx - 0.5, hh * 0.45, hz + 2.2), (wx + 0.5, hh * 0.45 + 1.0, hz + 2.6)),
                    ['#FFD46A'] if restored else ['#9BB4C4'], glow=0.8 if restored else None)
    for (tx, tz, th, tr) in ((14.0, -33.0, 4, 2.6), (25.0, -45.0, 5, 3.0), (2.5, -42.0, 4, 2.4), (31.0, -31.0, 5, 3.2)):
        tree(F, PF, (tx, 0, tz), trunk_h=th, r=tr, rng=rng)
    return Layer('far', F, blur=7.0, haze=0.26, haze_col='#CBE6F2', inner_alpha=0.15)


def gate(K, P, M, gcx, gcz, restored):
    """The village gate: two stone pillars, an arch, a plank on it and a lantern (home_scenes' gate)."""
    for px in (gcx - 4.0, gcx + 4.0):
        P.fill(box(M, (px - 0.9, 0, gcz - 0.9), (px + 0.9, 6.4, gcz + 0.9)), VSTONE, cell=(1.0, 1.0, 1.0))
        P.fill(box(M, (px - 1.1, 6.4, gcz - 1.1), (px + 1.1, 7.0, gcz + 1.1)), STONE_LT, cell=9)
    arch = (np.abs(M.Z - gcz) <= 0.9) & (np.abs(M.Y - 7.4 - 1.2 * np.cos((M.X - gcx) / 4.6 * 1.45)) <= 0.7) & (np.abs(M.X - gcx) <= 4.9)
    P.fill(arch, STONE_LT, cell=(1.0, 1.0, 1.0))
    P.fill(box(M, (gcx - 2.0, 5.2, gcz + 0.9), (gcx + 2.0, 6.6, gcz + 1.3)), HONEY, cell=9)
    P.fill(box(M, (gcx - 1.4, 5.7, gcz + 1.2), (gcx + 1.4, 6.1, gcz + 1.4)), ['#8D5D3B'], cell=9)
    # vines on the pillars (always), little lights in them once the village is lit
    for px in (gcx - 4.0, gcx + 4.0):
        vine = (np.abs(M.X - px - 0.7 * np.sin(M.Y * 1.1 + px)) < 0.5) & (M.Z >= gcz + 0.8) & (M.Z < gcz + 1.3) & (M.Y < 5.5) & (M.Y >= 0)
        P.fill(vine, ['#5EA046', '#4F9C3E', '#6FB24E'], cell=0.5)
    outdoor_lantern(K, P, M, gcx - 5.6, gcz + 1.6, 4.4, lit=True, s=0.6)
    fence_line(P, M, (gcx + 5.0, gcz - 0.5), (26.0, gcz - 2.0))
    fence_line(P, M, (gcx - 6.4, gcz - 0.5), (-3.0, gcz - 1.5))


def sign_post(P, M, x, z, h=POST_H):
    P.fill(box(M, (x - 0.35, 0, z - 0.35), (x + 0.35, h, z + 0.35)), ['#8A5A34', '#7A4E2E'], cell=(9, 1.0, 9))
    P.fill(box(M, (x - 0.7, 0, z - 0.7), (x + 0.7, 0.5, z + 0.7)), VSTONE, cell=0.5)


def scene_hub(restored=True, w=1170, h=2532, seed=4, target_y=0.45):
    rng = np.random.default_rng(seed)
    cam = portrait_cam()
    K = _Kit()
    layers = [hub_far(rng, restored)]

    Mm = Model((-26, -6, -30), (26, 34, 10), [], res=2)
    P = Painter(Mm, rng)
    C = CPainter(Mm, 23)
    xs = Mm.X[:, 0, 0]
    zs = Mm.Z[0, 0, :]
    X2, Z2 = np.meshgrid(xs, zs, indexing='ij')
    Hn = cv2.resize(rng.random((24, 20)).astype(np.float32), (len(zs), len(xs)), interpolation=cv2.INTER_NEAREST)
    H = np.round((Hn - 0.5) * 1.0) / 2
    paths = path_mask(X2, Z2)
    near_path = cv2.dilate(paths.astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool)
    H = np.where(near_path | (np.sqrt(X2 ** 2 + Z2 ** 2) < 6.0), 0, H)
    H = np.where(Z2 < -27, -0.5, H)
    ground(Mm, P, rng, H, path=lambda X, Z: path_mask(X, Z))
    # pale stones scattered in the dirt
    pebble = paths & (rng.random(paths.shape) < 0.05)
    top = (Mm.Y < H[:, None, :]) & (Mm.Y >= H[:, None, :] - 0.5) & pebble[:, None, :]
    P.fill(top, ['#D9CDB4', '#CFC2A6'])
    grass_tufts(Mm, P, H, ~near_path & (np.sqrt(X2 ** 2 + Z2 ** 2) > 5.7), 0.10, rng, max_h=0.9)

    # the Cottage up the left path, the gate up the right
    x0, x1, z0, z1 = COTTAGE
    cottage(K, C, Mm, rng, x0, x1, z0, z1, restored)
    gate(K, C, Mm, GATE[0], GATE[1], restored)
    for (x, z) in SIGNS.values():
        sign_post(C, Mm, x, z)
    # rocks by the nest (as in the meadow) and trees: behind the Cottage, between the paths, by the gate
    for (rx_, rz_, rs) in ((-8.6, 1.5, 1.5), (-10.2, -0.6, 1.0), (-7.0, 3.4, 0.8), (12.5, 4.0, 0.9)):
        rk = ((np.abs(Mm.X - rx_) / rs) ** 4 + (np.abs(Mm.Y) / (rs * 1.1)) ** 4 + (np.abs(Mm.Z - rz_) / (rs * 0.85)) ** 4) <= 1.3
        P.fill(rk & (Mm.Y >= -0.5), SC.STONE)
    for (tx, tz, th, tr) in ((-21.5, -27.0, 8, 4.6), (1.5, -28.5, 7, 3.6), (19.0, -21.0, 8, 4.4), (-23.0, -12.0, 6, 3.8)):
        tree(Mm, P, (tx, 0, tz), trunk_h=th, r=tr, rng=rng)
    # daisies, off the paths and clear of the buildings
    for _ in range(70):
        fx = rng.uniform(-20, 20)
        fz = rng.uniform(-28, 8)
        ix, iz = np.argmin(np.abs(xs - fx)), np.argmin(np.abs(zs - fz))
        if near_path[ix, iz] or math.hypot(fx, fz * 1.2) < 6.5:
            continue
        if x0 - 1 < fx < x1 + 1 and z0 - 1 < fz < z1 + 2.5:
            continue
        if abs(fx - GATE[0]) < 6 and abs(fz - GATE[1]) < 2.5:
            continue
        if any(math.hypot(fx - sx, fz - sz) < 1.4 for (sx, sz) in SIGNS.values()):
            continue
        daisy(Mm, P, (fx, H[ix, iz] + rng.uniform(0.6, 1.2), fz), size=rng.uniform(0.38, 0.52))
    layers.append(Layer('mid', Mm, blur=0.0, inner_alpha=0.28, outline=0.0))

    # near: foreground tufts and flowers (soft focus), as in the meadow
    N = Model((-16, -6, 8), (16, 10, 26), [], res=2)
    PN = Painter(N, rng)
    xsn = N.X[:, 0, 0]
    zsn = N.Z[0, 0, :]
    X2n, Z2n = np.meshgrid(xsn, zsn, indexing='ij')
    Hn2 = np.round((cv2.resize(rng.random((16, 10)).astype(np.float32), (len(zsn), len(xsn)),
                               interpolation=cv2.INTER_NEAREST) - 0.5)) / 2
    ground(N, PN, rng, Hn2)
    grass_tufts(N, PN, Hn2, np.abs(X2n) > 2.5, 0.28, rng, max_h=1.8)
    for _ in range(14):
        fx = rng.choice([-1, 1]) * rng.uniform(4, 11)
        fz = rng.uniform(9, 18)
        daisy(N, PN, (fx, rng.uniform(1.2, 2.0), fz), size=rng.uniform(0.55, 0.75))
    layers.append(Layer('near', N, blur=3.5, inner_alpha=0.15))

    # the nest sits lower in the frame than the meadow's (0.29): more sky above it, so on a phone with a
    # shorter panel the nest can come down and the Cottage and the gate clear the header
    sc = Scene('hub', cam, w, h, (0.5, target_y), ('#5FB1E6', '#CFEAF7'), layers, seed=seed, clouds=5)
    sc.slots = {'nest': (0, 0, 0), 'left': (-5.6, 0, 2.6), 'right': (5.8, 0, 1.8), 'back': (-3.0, 0, -6.5)}
    return sc


# ------------------------------------------------------------------ the sign board ----
def board_model(length=9.0, height=3.0, depth=0.8, tip=1.6):
    """A plank pointing right (+x): three boards, an arrow tip, a darker rim. Mirrored for left."""
    M = Model((-length / 2 - 0.5, -height / 2 - 0.5, -1.0), (length / 2 + 0.5, height / 2 + 0.5, 1.0), [], res=4)
    P = CPainter(M, 31)
    x_tip = length / 2 - tip
    shape = (np.abs(M.Y) <= height / 2 - np.clip(M.X - x_tip, 0, None) * (height / 2) / tip) & \
            (M.X >= -length / 2) & (M.X < length / 2) & (np.abs(M.Z) <= depth / 2)
    P.fill(shape, ['#C9965E', '#BE8A53', '#D4A36A'], cell=(2.0, 1.0, 1.0))
    boards = shape & (np.abs(np.abs(M.Y) - height / 6) < 0.13)
    P.fill(boards, ['#9A6538'], cell=9)
    inner = (np.abs(M.Y) <= height / 2 - 0.35 - np.clip(M.X - x_tip + 0.35, 0, None) * (height / 2) / tip) & \
            (M.X >= -length / 2 + 0.35)
    P.fill(shape & ~inner, ['#8A5A34', '#7A4E2E'], cell=0.5)
    for nx in (-length / 2 + 0.8, x_tip - 0.3):            # nails
        for ny in (-height / 4, height / 4):
            P.fill((np.abs(M.X - nx) < 0.18) & (np.abs(M.Y - ny) < 0.18) & (M.Z > depth / 2 - 0.3) & shape, ['#5A4636'], cell=9)
    return M


def render_board(out, px_w=480):
    M = board_model()
    cam = Camera(yaw=0, pitch=6, target=(0, 0, 0), persp=0)
    o = render(M, {}, cam, px_w, int(px_w * 0.42), light=Light(ambient=0.82, key_amt=0.32), ss=3,
               outline_px=3.0, outline_col='#3B2923', inner_alpha=0.35, margin=0.04)
    save_rgba(o.rgba, os.path.join(out, 'hub_sign_board.png'))
    return o.rgba


# ------------------------------------------------------------------ build ----
def px_per_unit(sc, fit, p):
    a = project_px(sc.cam, fit, [p])[0]
    b = project_px(sc.cam, fit, [(p[0] + 1, p[1], p[2])])[0]
    return float(np.linalg.norm(b - a))


def build(out, scale=1.0, restored=True):
    t = time.time()
    sc = scene_hub(restored, int(1170 * scale), int(2532 * scale))
    fit = SC.make_fit(sc)
    imgs = [SC.sky_image(sc)]
    names = ['sky']
    for L in sc.layers:
        if L.blur:
            L.blur *= scale
        img, _ = SC.render_layer(sc, L, fit)
        imgs.append(img)
        names.append(L.name)
    comp = SC.composite(imgs)
    state = 'restored' if restored else 'ruined'
    base = f'habitat_hub_{state}'
    os.makedirs(out, exist_ok=True)
    for n, img in zip(names, imgs):
        save_rgba(img, os.path.join(out, f'{base}_{n}_day.png'))
    Image.fromarray(comp[..., :3]).save(os.path.join(out, f'{base}_composite_day.png'))

    def pt(p):
        return {'px': project_px(sc.cam, fit, [p])[0].round(1).tolist(), 'px_per_unit': round(px_per_unit(sc, fit, p), 3)}

    meta = {'w': sc.w, 'h': sc.h, 'layers': names,
            'pet': project_px(sc.cam, fit, [(0, 0, 0)])[0].round(1).tolist(),
            'pet_px_per_unit': round(px_per_unit(sc, fit, (0, 0, 0)), 3),
            'slots': {k: {**pt(v), 'world': list(v)} for k, v in sc.slots.items()},
            'signs': {k: {'base': pt((x, 0, z)), 'top': pt((x, POST_H, z))} for k, (x, z) in SIGNS.items()},
            'walks': {'home': [pt((x, 0, z)) for (x, z) in LEFT_WALK[:4]],
                      'village': [pt((x, 0, z)) for (x, z) in RIGHT_WALK[:4]]},
            'goals': {'home': pt(((COTTAGE[0] + COTTAGE[1]) / 2, 3.0, COTTAGE[3])), 'village': pt((GATE[0], 4.0, GATE[1]))}}
    json.dump(meta, open(os.path.join(out, f'{base}.json'), 'w'), indent=1)
    print(base, 'done in %.1fs' % (time.time() - t), flush=True)
    return meta


if __name__ == '__main__':
    args = sys.argv[1:]
    scale = 1.0
    if '--scale' in args:
        i = args.index('--scale')
        scale = float(args[i + 1])
        args = args[:i] + args[i + 2:]
    restored = '--ruined' not in args
    args = [a for a in args if a != '--ruined']
    out = args[0]
    build(out, scale, restored)
    render_board(out)

"""The start screen's layers, from the environment production sheet (11 Nov 2026): 2D pixel art for the sky's
moon, the drifting clouds, the far hills with their village lights and the lakeshore with its cottages, and the
floating island with the sleeping Elder (petal mane) as flat voxel renders: the island, a strip of the Elder
breathing, and the props in front of her (the nest with the glowing egg, the lantern post). The app draws them
over its own sky gradient, stars, lake, shimmer and particles (features/title/title_screen.dart).

    python3 title_layers.py [FLUTTER_ART_DIR/title] [--only=sky,clouds,hills,shore,island,logo]

Everything is at 2x (the app draws at half size). The Elder strip is a breathing loop: ELDER_FRAMES frames at
ELDER_FPS, looping.
"""
import json
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image

from voxel import Model, Camera, Light, Fit, render, fit_camera, model_extent_points, project_px
from scenes import Painter, daisy, grass_tufts, GRASS, CLIFF, STONE, DIRT
from charrender import render_char
from walk import light_for
import sleep_cycle as S

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'flutter', 'assets', 'art', 'title')

# the sheet's palette (night)
SKY = {'top': '#1B1540', 'mid': '#2B2360', 'low': '#4A3F82', 'horizon': '#6E5A9A'}
CLOUD = ['#5D53A0', '#7A6FBF', '#978CD4', '#B3A8E6']       # shadow, base, light, highlight
HILL_FAR, HILL_NEAR, SHORE = '#3B3374', '#2E2758', '#262048'
LIGHT_WARM = '#FFD27A'
PX = 6   # one art pixel in the 2D layers, at 2x (3 px at 1x)

ELDER_FRAMES, ELDER_FPS = 20, 10
CAM = Camera(yaw=56.0, pitch=18.0)
NIGHT = np.array([0.80, 0.81, 1.0])    # the island's daylight render, moonlit
NIGHT_ELDER = np.array([0.94, 0.92, 1.0])   # she keeps her warmth (the lantern and the egg beside her)
GLOW_MATS = ['#6FE3FF', '#B07CE8', '#FFF1C8', '#F4C04E', '#FFD46A']   # left untinted: the glowing things


# ---- helpers ---------------------------------------------------------------------------------------------------
def hexrgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def pixel_canvas(w, h):
    return Image.new('RGBA', (w // PX, h // PX), (0, 0, 0, 0))


def up(img):
    return img.resize((img.width * PX, img.height * PX), Image.NEAREST)


def blob(d, cx, cy, rx, ry, col):
    """an ellipse of pixels"""
    for y in range(int(cy - ry), int(cy + ry) + 1):
        for x in range(int(cx - rx), int(cx + rx) + 1):
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                d.putpixel((x, y), col) if 0 <= x < d.width and 0 <= y < d.height else None


def webp(img, path, q=88):
    img.save(path, 'WEBP', quality=q, method=6)
    print(os.path.basename(path), img.size, os.path.getsize(path) // 1024, 'KB', flush=True)


# ---- the moon ------------------------------------------------------------------------------------------------------
def moon(out):
    n = 11
    im = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    blob(im, 5, 5, 5.2, 5.2, hexrgb('#F3E3A6') + (255,))
    for cx, cy, r in ((3.5, 4, 1.3), (6.5, 6.5, 1.6), (7, 3, 0.9)):
        blob(im, cx, cy, r, r, hexrgb('#E2CE86') + (255,))
    # a lit rim top-left
    for y in range(n):
        for x in range(n):
            if im.getpixel((x, y))[3] and ((x - 5) ** 2 + (y - 5) ** 2) > 17 and x + y < 8:
                im.putpixel((x, y), hexrgb('#FFF4CC') + (255,))
    webp(up(im), os.path.join(out, 'moon.webp'), 95)
    return {'w': n * PX, 'h': n * PX}


# ---- clouds --------------------------------------------------------------------------------------------------------
def clouds(out):
    rng = np.random.default_rng(3)
    sprites, rects = [], []
    for i, (w, h) in enumerate(((34, 12), (26, 10), (44, 14), (20, 8))):
        im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        base = hexrgb(CLOUD[1]) + (255,)
        n = 4 + w // 8
        for k in range(n):
            cx = 4 + (w - 8) * (k + 0.5) / n + rng.uniform(-1.5, 1.5)
            ry = rng.uniform(h * 0.28, h * 0.46)
            blob(im, cx, h - ry - 0.5, ry * rng.uniform(1.3, 1.9), ry, base)
        # flat bottom, a shadow band along it, a highlight along the top edge
        px = im.load()
        for y in range(h):
            for x in range(w):
                if px[x, y][3]:
                    if y >= h - 2:
                        px[x, y] = hexrgb(CLOUD[0]) + (255,)
                    elif y == 0 or not px[x, y - 1][3]:
                        px[x, y] = hexrgb(CLOUD[3]) + (255,)
                    elif y == 1 or not px[x, y - 2][3]:
                        px[x, y] = hexrgb(CLOUD[2]) + (255,)
        sprites.append(im)
    W = sum(s.width for s in sprites) + len(sprites)
    H = max(s.height for s in sprites)
    strip = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    x = 0
    for s in sprites:
        strip.alpha_composite(s, (x, H - s.height))
        rects.append([x * PX, (H - s.height) * PX, s.width * PX, s.height * PX])
        x += s.width + 1
    webp(up(strip), os.path.join(out, 'clouds.webp'), 92)
    return {'file': 'clouds.webp', 'rects': rects}


# ---- the far hills and the lakeshore ----------------------------------------------------------------------------------
def skyline(rng, w, base, amp, bumps, wobble=1.0):
    """heights (pixels) along x: soft ridges"""
    x = np.arange(w)
    h = np.full(w, float(base))
    for _ in range(bumps):
        cx, r, a = rng.uniform(0, w), rng.uniform(w * 0.04, w * 0.14), rng.uniform(0.4, 1.0) * amp
        d = np.minimum(np.abs(x - cx), w - np.abs(x - cx)) / r   # wraps, so the layer tiles
        h += a * np.clip(1 - d ** 2, 0, 1)
    h += rng.uniform(-wobble, wobble, w)
    return h


def hills(out):
    rng = np.random.default_rng(11)
    w, H = 256, 40   # art pixels; tiles horizontally
    im = Image.new('RGBA', (w, H), (0, 0, 0, 0))
    px = im.load()
    far = skyline(rng, w, 14, 16, 7)
    near = skyline(rng, w, 7, 9, 9)
    for x in range(w):
        for y in range(H):
            yy = H - y
            if yy <= far[x]:
                px[x, y] = hexrgb(HILL_FAR) + (255,)
            if yy <= near[x]:
                px[x, y] = hexrgb(HILL_NEAR) + (255,)
    # pines along the near ridge
    for _ in range(26):
        x = int(rng.uniform(0, w))
        base = int(near[x])
        t = int(rng.uniform(2, 5))
        for k in range(t):
            y = H - base - k - 1
            hw = max(0, (t - k) // 2)
            for xx in range(x - hw, x + hw + 1):
                if 0 <= xx < w and 0 <= y < H:
                    px[xx, y] = hexrgb(HILL_NEAR) + (255,)
    # village lights on the near slope
    lights = []
    for _ in range(9):
        x = int(rng.uniform(0, w))
        y = H - int(near[x]) + int(rng.uniform(1, 3))
        if 0 <= y < H and px[x, y][3]:
            px[x, y] = hexrgb(LIGHT_WARM) + (255,)
            lights.append([x * PX + PX // 2, y * PX + PX // 2])
    webp(up(im), os.path.join(out, 'hills.webp'), 92)
    return {'file': 'hills.webp', 'w': w * PX, 'h': H * PX, 'lights': lights}


def cottage(im, x0, y0, w, h, roof, wall, win):
    """a pixel cottage, y0 its ground row; returns its lit windows"""
    px = im.load()

    def put(x, y, col):
        if 0 <= x < im.width and 0 <= y < im.height:
            px[x, y] = hexrgb(col) + (255,)

    for y in range(h):
        for x in range(w):
            put(x0 + x, y0 - y, wall)
    for k in range(h // 2 + 2):   # the roof, a step in on each row
        for x in range(-1 + k, w + 1 - k):
            put(x0 + x, y0 - h - k, roof)
    wins = []
    for x in (1, w - 2):
        if 0 < x < w - 1:
            put(x0 + x, y0 - 2, win)
            wins.append((x0 + x, y0 - 2))
    return wins


def shore(out, cottages=False):
    rng = np.random.default_rng(7)
    w, H = 256, 34
    im = Image.new('RGBA', (w, H), (0, 0, 0, 0))
    px = im.load()
    land = skyline(rng, w, 7, 5, 6, 0.6)
    for x in range(w):
        for y in range(H):
            if H - y <= land[x]:
                px[x, y] = hexrgb(SHORE) + (255,)
    # a lighter grass line along the top of the bank
    for x in range(w):
        y = H - int(land[x])
        if 0 <= y < H:
            px[x, y] = hexrgb('#3A3268') + (255,)
    lights = []
    for cx in ((22, 70, 128, 176, 230) if cottages else ()):
        cw, ch = int(rng.uniform(7, 10)), int(rng.uniform(5, 7))
        y0 = H - int(land[cx]) + 1
        wins = cottage(im, cx - cw // 2, y0, cw, ch, '#6B3A5E', '#4C3F78', LIGHT_WARM)
        lights += [[x * PX + PX // 2, y * PX + PX // 2] for x, y in wins]
        # a round tree beside it
        tx = cx + cw // 2 + 4
        blob(im, tx, y0 - 5, 3, 3.5, hexrgb('#35406A') + (255,))
        for y in range(y0 - 2, y0 + 1):
            if 0 <= tx < w and 0 <= y < H:
                px[tx, y] = hexrgb('#2C2450') + (255,)
    for tx in (10, 48, 95, 150, 198, 238):
        y0 = H - int(land[tx]) + 1
        blob(im, tx, y0 - 5, 3, 3.5, hexrgb('#35406A') + (255,))
        for y in range(y0 - 2, y0 + 1):
            if 0 <= y < H:
                px[tx, y] = hexrgb('#2C2450') + (255,)
    # reeds at the water's edge
    for _ in range(40):
        x = int(rng.uniform(0, w))
        y0 = H - int(land[x])
        for k in range(int(rng.uniform(2, 4))):
            if 0 <= y0 - k < H:
                px[x, y0 - k] = hexrgb('#3F3A74') + (255,)
    webp(up(im), os.path.join(out, 'shore.webp'), 92)
    return {'file': 'shore.webp', 'w': w * PX, 'h': H * PX, 'lights': lights}


def lily(out):
    im = Image.new('RGBA', (7, 5), (0, 0, 0, 0))
    blob(im, 3, 2, 3.2, 2.2, hexrgb('#4F9C5E') + (255,))
    im.putpixel((5, 1), (0, 0, 0, 0))
    im.putpixel((6, 1), (0, 0, 0, 0))
    for x, y in ((2, 1), (3, 1)):
        im.putpixel((x, y), hexrgb('#6DBB74') + (255,))
    im.putpixel((3, 0), hexrgb('#F4A7C4') + (255,))
    webp(up(im), os.path.join(out, 'lily.webp'), 95)
    return {'w': 7 * PX, 'h': 5 * PX}


# ---- the floating island (voxel) ------------------------------------------------------------------------------------
RX, RZ = 86.0, 62.0


def island_model(rng):
    M = Model((-96, -40, -72), (96, 30, 72), [], res=1)
    P = Painter(M, rng)
    X, Y, Z = M.X, M.Y, M.Z
    r = np.sqrt((X / RX) ** 2 + (Z / RZ) ** 2)
    ang = np.arctan2(Z / RZ, X / RX)
    rim = 1.0 + 0.045 * np.sin(5 * ang + 1.0) + 0.03 * np.sin(11 * ang)     # a wobbly coastline
    top = (r <= rim) & (Y >= 0) & (Y < 2)
    P.fill(top, GRASS)
    # the underside: a cone of cliff that narrows to a few hanging stones, jagged per column
    jag = rng.uniform(0.0, 0.12, (M.m.shape[0], 1, M.m.shape[2]))
    depth = (-Y) / 34.0
    under = (Y < 0) & (Y >= -34) & (r <= rim * np.clip(1.0 - 0.9 * depth ** 3 - jag, 0.06, 1.0))
    P.fill(under, CLIFF)
    P.fill(under & (rng.random(M.m.shape) < 0.12), STONE)
    P.fill(under & (Y >= -3), DIRT)
    # the layers of strata, a touch darker
    P.fill(under & (((-Y) // 5) % 2 == 1) & (rng.random(M.m.shape) < 0.5), ['#B88F66', '#A97F59'])
    # glow blocks set into the cliff (cyan, as the sheet's), and two amethyst crystals on top
    surf = M.surface()
    cand = np.argwhere(under & surf & (Y < -4) & (Y > -22) & (X + Z * 0.6 > 0))   # on the side the camera sees
    for i in rng.choice(len(cand), 10, replace=False):
        x, y, z = cand[i]
        sel = (np.abs(M.X - (x + M.lo[0] + 0.5)) <= 1.2) & (np.abs(M.Y - (y + M.lo[1] + 0.5)) <= 1.2) & (np.abs(M.Z - (z + M.lo[2] + 0.5)) <= 1.2)
        M.set(sel & (M.m > 0), '#6FE3FF', glow=0.9, layer=1)
    # hanging vines off the rim
    for a in rng.uniform(0, 2 * math.pi, 14):
        x, z = RX * 0.97 * math.cos(a), RZ * 0.97 * math.sin(a)
        L = rng.uniform(6, 16)
        v = (np.abs(X - x) <= 0.6) & (np.abs(Z - z) <= 0.6) & (Y < 0) & (Y >= -L)
        P.fill(v & (M.m == 0), ['#4F8E38', '#5E9E40'])
        for k in range(int(L // 3)):
            yy = -2 - 3 * k
            leaf = (np.abs(X - x - rng.choice([-1, 1])) <= 0.6) & (np.abs(Z - z) <= 0.6) & (np.abs(Y - yy) <= 0.5)
            P.fill(leaf & (M.m == 0), '#6CB25A')
    # the hanging stones below
    for _ in range(4):
        x, z = rng.uniform(-RX * 0.5, RX * 0.5), rng.uniform(-RZ * 0.5, RZ * 0.5)
        s = rng.uniform(2.0, 3.5)
        st = (np.abs(X - x) <= s) & (np.abs(Z - z) <= s) & (Y < -33 + rng.uniform(-1, 1)) & (Y >= -34 - s)
        P.fill(st, STONE)
    # rocks on top (left, back), bushes, flowers and tufts
    for x, z, s in ((-64, -14, 6.0), (-52, -32, 4.0), (-30, 40, 3.5), (44, -44, 5.0), (-72, 18, 3.0)):
        rock = ((X - x) / s) ** 2 + ((Y - 1.5) / (s * 0.7)) ** 2 + ((Z - z) / (s * 0.85)) ** 2 <= 1.0
        P.fill(rock, STONE)
    for x, z, s in ((-66, 28, 5.0), (58, 34, 4.0), (10, -52, 4.5)):
        bush = ((X - x) / s) ** 2 + ((Y - 2.5) / (s * 0.8)) ** 2 + ((Z - z) / s) ** 2 <= 1.0
        P.fill(bush & (Y >= 1.5), ['#5EAE47', '#6BBB50', '#4F9C3E'])
    H = np.where(r[:, 0, :] <= rim[:, 0, :], 2.0, -99.0)
    grass_tufts(M, P, H, (r[:, 0, :] <= rim[:, 0, :] * 0.98) & (r[:, 0, :] > 0.3), 0.035, rng, max_h=2.2)
    for _ in range(26):
        a, rr = rng.uniform(0, 2 * math.pi), rng.uniform(0.35, 0.95)
        x, z = RX * rr * math.cos(a), RZ * rr * math.sin(a)
        petal = rng.choice(['#FFFDF6', '#F6A7C8', '#C89BEA', '#FFFDF6'])
        daisy(M, P, (x, 3.6, z), size=0.9, petal=petal)
    for x, z in ((-46, 10), (30, -40)):
        cr = (np.abs(X - x) <= 1.5) & (np.abs(Z - z) <= 1.5) & (Y >= 2) & (Y < 7 - np.abs(X - x) - np.abs(Z - z))
        M.set(cr, '#B07CE8', glow=0.5, layer=1)
    return M


def front_model(rng, nest_at, lantern_at):
    """the props in front of the Elder: her nest with the glowing egg, the lantern post"""
    M = Model((-96, -34, -72), (96, 30, 72), [], res=1)
    P = Painter(M, rng)
    X, Y, Z = M.X, M.Y, M.Z
    nx, nz = nest_at
    rr = np.sqrt((X - nx) ** 2 + (Z - nz) ** 2)
    ring = (np.abs(rr - 8.0) <= 2.4) & (Y >= 2) & (Y < 5.5 - (rr - 8.0) ** 2 * 0.25)
    P.fill(ring, ['#8A5A34', '#7A4E2E', '#A06A3C', '#6E4529'])
    straw = ring & (rng.random(M.m.shape) < 0.18)
    P.fill(straw, ['#D9B16A', '#C9A25C'])
    egg = ((X - nx) / 4.2) ** 2 + ((Y - 5.4) / 5.4) ** 2 + ((Z - nz) / 4.2) ** 2 <= 1.0
    M.set(egg & (Y >= 2.5), '#FFF1C8', glow=0.85, layer=1)
    spots = egg & (Y >= 2.5) & (rng.random(M.m.shape) < 0.06)
    M.set(spots, '#F4C04E', glow=0.9, layer=1)
    lx, lz = lantern_at
    post = (np.abs(X - lx) <= 0.9) & (np.abs(Z - lz) <= 0.9) & (Y >= 2) & (Y < 30)
    P.fill(post, ['#6E4529', '#7A4E2E'])
    arm = (X >= lx - 7) & (X < lx) & (np.abs(Y - 29.3) <= 0.6) & (np.abs(Z - lz) <= 0.6)
    P.fill(arm, '#6E4529')
    hx, hy = lx - 6, 25.5
    frame = (np.maximum(np.abs(X - hx), np.abs(Z - lz)) <= 1.8) & (Y >= hy - 2.4) & (Y < hy + 2.6)
    M.set(frame, '#FFD46A', glow=1.0, layer=1)
    M.set(frame & ((Y >= hy + 2.0) | (Y < hy - 1.9)), '#4A3328', layer=1)
    return M


def moonlit(rgba, keep=None, tint=NIGHT, lerp=0.1):
    """the render by moonlight: cooler and a shade darker, except where [keep] (the glowing things)"""
    out = rgba.astype(np.float32)
    rgb = out[..., :3] * tint
    rgb = rgb * (1 - lerp) + np.array([58, 46, 106]) * lerp
    if keep is not None:
        rgb = np.where(keep[..., None], out[..., :3], rgb)
    out[..., :3] = rgb
    return np.clip(out, 0, 255).astype(np.uint8)


def glow_mask(o, M):
    ids = [M.ids[m] for m in GLOW_MATS if m in M.ids]
    return np.isin(o.ids, ids)


def over(base, top):
    b, t = base.astype(np.float32) / 255, top.astype(np.float32) / 255
    a = t[..., 3:4]
    rgb = t[..., :3] * a + b[..., :3] * b[..., 3:4] * (1 - a)
    aa = a + b[..., 3:4] * (1 - a)
    rgb = np.where(aa > 0, rgb / np.maximum(aa, 1e-6), 0)
    return (np.concatenate([rgb, aa], -1) * 255).astype(np.uint8)


def island(out):
    rng = np.random.default_rng(5)
    W, H = 1100, 900
    M = island_model(rng)
    light = light_for(CAM.yaw)
    light.ambient, light.key_amt = 0.78, 0.38
    pts = np.concatenate([model_extent_points(M), np.array([[0.0, 52.0, 0.0]])])   # headroom for the Elder
    fit = fit_camera(CAM, pts, W, H, margin=0.03)
    kw = dict(fit=fit, light=light, ss=3, outline_px=2.5, inner_alpha=0.5)
    o = render(M, {}, CAM, W, H, **kw)
    isl = moonlit(o.rgba, glow_mask(o, M))
    # the Elder, placed at the island's centre, breathing
    T = np.array([2.0, 2.0, -6.0])
    P = S.poses(3)
    o0, oT = project_px(CAM, fit, [0, 0, 0])[0], project_px(CAM, fit, T)[0]
    efit = Fit(fit.scale, fit.ox + (oT[0] - o0[0]), fit.oy + (oT[1] - o0[1]), W, H)
    frames = []
    for i in range(ELDER_FRAMES):
        b2 = math.sin(2 * math.pi * i / ELDER_FRAMES)
        pose = dict(P['settle'])
        pose['body'] = (pose['body'][0] + 0.5 * b2, pose['body'][1] + 0.4 * b2)
        pose['head'] = (pose['head'][0], pose['head'][1] + 0.3 * b2, pose['head'][2])
        pose['head_rot'] = (pose['head_rot'][0] + 1.2 * b2, pose['head_rot'][1], pose['head_rot'][2])
        pose['tail_lift'] = pose['tail_lift'] + 0.3 * b2
        ch = S.build_pose(3, pose, None, 'petal')
        e = render_char(ch, 'amber', 'cosy', CAM, W, H, fit=efit, light=light)
        frames.append(moonlit(e.rgba, tint=NIGHT_ELDER, lerp=0.04))
        print('elder', i, flush=True)
    F = front_model(rng, nest_at=(-30.0, 40.0), lantern_at=(70.0, -4.0))
    fo = render(F, {}, CAM, W, H, **kw)
    front = moonlit(fo.rgba, glow_mask(fo, F))
    # crop everything to what is drawn, keeping one pixel space
    a = np.maximum(np.maximum(isl[..., 3], front[..., 3]), np.max([f[..., 3] for f in frames], 0))
    ys, xs = np.where(a > 0)
    cx0, cx1, cy0, cy1 = max(0, xs.min() - 2), xs.max() + 3, max(0, ys.min() - 2), ys.max() + 3
    isl, front = isl[cy0:cy1, cx0:cx1], front[cy0:cy1, cx0:cx1]
    frames = [f[cy0:cy1, cx0:cx1] for f in frames]
    # the strip, cropped to the Elder's extent over all frames
    a = np.max([f[..., 3] for f in frames], 0)
    ys, xs = np.where(a > 0)
    x0, x1, y0, y1 = xs.min() - 2, xs.max() + 3, ys.min() - 2, ys.max() + 3
    fw, fh = x1 - x0, y1 - y0
    strip = Image.new('RGBA', (fw * ELDER_FRAMES, fh), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(Image.fromarray(np.ascontiguousarray(f[y0:y1, x0:x1])), (i * fw, 0))
    webp(Image.fromarray(np.ascontiguousarray(isl)), os.path.join(out, 'island.webp'), 90)
    webp(Image.fromarray(np.ascontiguousarray(front)), os.path.join(out, 'island_front.webp'), 90)
    webp(strip, os.path.join(out, 'elder_sleep.webp'), 88)
    # where the lantern's flame, the egg and her head are, for the app's glows and z's (island pixel space)
    flame = project_px(CAM, fit, [64.0, 25.5, -4.0])[0]
    eggp = project_px(CAM, fit, [-30.0, 5.4, 40.0])[0]
    head = project_px(CAM, fit, T + np.array([-24.0, 16.0, 14.0]))[0]
    comp = over(over(isl, frames[0]), front)
    Image.fromarray(comp).save(os.path.join(out, '_island_preview.png'))
    return {'island': {'file': 'island.webp', 'w': int(cx1 - cx0), 'h': int(cy1 - cy0)},
            'front': {'file': 'island_front.webp'},
            'elder': {'file': 'elder_sleep.webp', 'frameW': int(fw), 'frameH': int(fh), 'frames': ELDER_FRAMES, 'fps': ELDER_FPS,
                      'x': int(x0), 'y': int(y0)},
            'flame': [float(flame[0] - cx0), float(flame[1] - cy0)],
            'egg': [float(eggp[0] - cx0), float(eggp[1] - cy0)],
            'zs': [float(head[0] - cx0), float(head[1] - cy0)]}


# ---- the village across the water: the walkable Village's own voxel set, seen from afar ----------------------------
VILLAGE_CAM = Camera(yaw=-14.0, pitch=9.0)
VILLAGE_PPU = 4.5     # px per unit at 2x: the village across the water about nine tenths of the screen wide


def merged(models, res=2):
    """one Model from the scene's many (their res may differ), the later ones over the earlier"""
    lo = np.min([np.floor(m.lo / m.res) for m in models], 0).astype(int) - 1
    hi = np.max([np.ceil((m.lo + np.array(m.m.shape)) / m.res) for m in models], 0).astype(int) + 1
    T = Model(tuple(lo), tuple(hi), [], res=res)
    for A in models:
        idx = np.argwhere(A.m > 0)
        if len(idx) == 0:
            continue
        lut = np.array([0] + [T.mid(n) for n in A.mats[1:]], np.int32)
        mats, glow = lut[A.m[idx[:, 0], idx[:, 1], idx[:, 2]]], A.glow[idx[:, 0], idx[:, 1], idx[:, 2]]
        k = max(1, res // A.res)
        for off in np.ndindex(k, k, k):
            w = (A.lo + idx + (np.array(off) + 0.5) / k) / A.res      # world position of each (sub)voxel
            ti = np.floor(w * res).astype(int) - T.lo
            ok = np.all((ti >= 0) & (ti < np.array(T.m.shape)), 1)
            T.m[ti[ok, 0], ti[ok, 1], ti[ok, 2]] = mats[ok]
            T.glow[ti[ok, 0], ti[ok, 1], ti[ok, 2]] = glow[ok]
    return T


def quantise(rgba, px=PX):
    """the render as pixel art: one art pixel per [px] square, the colour the average of what covers it"""
    h, w = rgba.shape[:2]
    H, W = h // px, w // px
    a = rgba[:H * px, :W * px].astype(np.float32)
    a = a.reshape(H, px, W, px, 4).mean((1, 3))
    cov = a[..., 3] / 255.0
    rgb = np.where(cov[..., None] > 0, a[..., :3] / np.maximum(cov[..., None], 1e-6), 0)   # un-premultiply the average
    out = np.zeros((H, W, 4), np.uint8)
    on = cov >= 0.45
    out[..., :3] = np.clip(rgb, 0, 255)
    out[..., 3] = np.where(on, 255, 0)
    return Image.fromarray(out).resize((W * px, H * px), Image.NEAREST)


def village(out):
    import village_walk as VW
    Sc = VW.scene_village_walk('lamp_lit')
    T = merged([it[0] for it in Sc.models if it[0].res > 1])   # not the far hills (res 1): the title has its own
    print('village merged', T.m.shape, int((T.m > 0).sum()), 'voxels', flush=True)
    light = light_for(VILLAGE_CAM.yaw)
    light.ambient, light.key_amt = 0.8, 0.3
    pts = model_extent_points(T)
    sx, sy, _ = VILLAGE_CAM.project(pts)
    W = int((sx.max() - sx.min()) * VILLAGE_PPU) + 2 * PX
    H = int((sy.max() - sy.min()) * VILLAGE_PPU) + 2 * PX
    fit = fit_camera(VILLAGE_CAM, pts, W, H, margin=0.0, scale=VILLAGE_PPU)
    o = render(T, {}, VILLAGE_CAM, W, H, fit=fit, light=light, ss=2, outline_px=0.0, inner_lines=False, margin=0.0)
    glow_ids = np.unique(T.m[T.glow > 0])
    keep = np.isin(o.ids, glow_ids)
    lit = moonlit(o.rgba, keep, tint=np.array([0.66, 0.68, 1.0]), lerp=0.18)
    im = quantise(lit)
    # crop to the pixels drawn
    a = np.array(im)[..., 3]
    ys, xs = np.where(a > 0)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    x0, x1, y0, y1 = x0 - x0 % PX, x1 + (-x1) % PX, y0 - y0 % PX, y1 + (-y1) % PX
    im = im.crop((x0, y0, x1, y1))
    webp(im, os.path.join(out, 'village.webp'), 92)
    # its lamps and lit windows, for the app's halos: the scene's own point lights, projected
    lights = []
    for L in Sc.lights:
        if 'pos' not in L:
            continue
        p = project_px(VILLAGE_CAM, fit, L['pos'])[0]
        px_, py_ = float(p[0] - x0), float(p[1] - y0)
        if 0 <= px_ < im.width and 0 <= py_ < im.height:
            lights.append([round(px_ / PX) * PX + PX / 2, round(py_ / PX) * PX + PX / 2])
    # the ground line: where the village stands (the plaza's centre), so the app sets it on the shore
    g = project_px(VILLAGE_CAM, fit, [0.0, 0.0, 40.0])[0]
    return {'file': 'village.webp', 'w': im.width, 'h': im.height, 'lights': lights, 'ground': float(g[1] - y0)}


def logo(out):
    """the logo, rastered at 2x for the app (assets/brand/evochi_logo.svg is the master)"""
    src = os.path.join(ROOT, 'assets', 'brand', 'evochi_logo.svg')
    png = os.path.join(out, '_logo.png')
    subprocess.run(['rsvg-convert', '-w', '760', '-o', png, src], check=True)
    im = Image.open(png).convert('RGBA')
    webp(im, os.path.join(out, 'logo.webp'), 95)
    os.remove(png)
    return {'file': 'logo.webp', 'w': im.width, 'h': im.height}


def main(out, only=None):
    os.makedirs(out, exist_ok=True)
    mpath = os.path.join(out, 'title.json')
    man = json.load(open(mpath)) if os.path.exists(mpath) else {}
    steps = {'moon': moon, 'clouds': clouds, 'hills': hills, 'shore': shore, 'lily': lily, 'island': island, 'village': village, 'logo': logo}
    only = [o for o in only if o != 'preview'] if only else only
    for k, fn in steps.items():
        if only and k not in only:
            continue
        man[k] = fn(out)
        with open(mpath, 'w') as f:
            json.dump(man, f, indent=1)
    man['px'] = PX
    man['scale'] = 2
    man['layout'] = LAYOUT
    with open(mpath, 'w') as f:
        json.dump(man, f, indent=1)
    print('wrote', mpath, flush=True)
    if not only or 'preview' in only:
        preview(out)




# ---- a still of the composed screen, the app's layout mirrored, to check the composition without the app ------
LAYOUT = dict(horizon=0.60, moon=(0.22, 0.30, 0.055), island_w=0.70, island_bottom=0.56, village_x=0.74, logo_w=0.72, logo_y=0.055, plank_y=0.865)


def preview(out, w=390, h=844):
    """the start screen at 2x (w x h logical): sky, stars, moon, clouds, hills, the lake, the village and the
    shore, the island with the Elder and the props, the logo and the plank (features/title/title_screen.dart
    draws the same layout; keep LAYOUT and its numbers together)"""
    from PIL import ImageDraw, ImageFont
    man = json.load(open(os.path.join(out, 'title.json')))
    S = 2
    W, H = w * S, h * S
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    horizon = int(LAYOUT['horizon'] * H)
    # sky
    stops = [(0.0, hexrgb(SKY['top'])), (0.45, hexrgb(SKY['mid'])), (0.82, hexrgb(SKY['low'])), (1.0, hexrgb(SKY['horizon']))]
    for y in range(horizon + 1):
        u = y / horizon
        for (u0, c0), (u1, c1) in zip(stops, stops[1:]):
            if u0 <= u <= u1:
                k = (u - u0) / (u1 - u0)
                col = tuple(int(c0[i] + (c1[i] - c0[i]) * k) for i in range(3)) + (255,)
                d.line((0, y, W, y), fill=col)
                break
    rng = np.random.default_rng(7)
    for _ in range(110):
        x, y, sz = rng.uniform(0, W), rng.uniform(0, horizon * 0.95), S * (1 + rng.integers(0, 2))
        d.rectangle((x, y, x + sz, y + sz), fill=(255, 255, 255, int(rng.uniform(100, 240))))
    # moon
    mx, my, mr = LAYOUT['moon'][0] * W, LAYOUT['moon'][1] * H, LAYOUT['moon'][2] * W
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for k in range(8, 0, -1):
        r = mr * (1 + k * 0.22)
        gd.ellipse((mx - r, my - r, mx + r, my + r), fill=hexrgb('#F3E3A6') + (int(10 + 2 * (8 - k)),))
    img.alpha_composite(glow)
    moon_im = Image.open(os.path.join(out, 'moon.webp')).convert('RGBA').resize((int(2 * mr), int(2 * mr)), Image.NEAREST)
    img.alpha_composite(moon_im, (int(mx - mr), int(my - mr)))
    # clouds
    cl = Image.open(os.path.join(out, 'clouds.webp')).convert('RGBA')
    for i, x, y, sc, op in ((2, 0.05, 0.16, 0.9, 0.72), (0, 0.55, 0.09, 1.0, 0.85), (3, 0.85, 0.22, 0.8, 0.7), (1, 0.3, 0.27, 1.15, 1.0), (0, 0.78, 0.33, 1.25, 1.0)):
        r = man['clouds']['rects'][i]
        c = cl.crop((r[0], r[1], r[0] + r[2], r[1] + r[3]))
        c = c.resize((int(r[2] * sc), int(r[3] * sc)), Image.NEAREST)
        if op < 1:
            a = c.split()[3].point(lambda v: int(v * op))
            c.putalpha(a)
        img.alpha_composite(c, (int(x * W) % W, int(y * H)))
    # hills (tiled), the lake, the shore band, the village
    hills = Image.open(os.path.join(out, 'hills.webp')).convert('RGBA')
    for x in range(0, W, hills.width):
        img.alpha_composite(hills, (x, horizon + 2 * S - hills.height))
    lake = Image.new('RGBA', (W, H - horizon), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lake)
    c0, c1 = hexrgb('#34306F'), hexrgb('#1A1842')
    for y in range(H - horizon):
        k = y / (H - horizon)
        ld.line((0, y, W, y), fill=tuple(int(c0[i] + (c1[i] - c0[i]) * k) for i in range(3)) + (255,))
    img.alpha_composite(lake, (0, horizon))
    shore = Image.open(os.path.join(out, 'shore.webp')).convert('RGBA')
    for x in range(0, W, shore.width):
        img.alpha_composite(shore, (x, horizon + 12 * S - shore.height))
    if 'village' in man:
        v = Image.open(os.path.join(out, 'village.webp')).convert('RGBA')
        vx = int(LAYOUT['village_x'] * W - v.width / 2)
        vy = int(horizon + 6 * S - man['village']['ground'])
        img.alpha_composite(v, (vx, vy))
        # the moon and the lights on the water
        for lx, ly in man['village']['lights']:
            px_, py_ = vx + lx, vy + ly
            for k in range(4):
                d.rectangle((px_ - 2 - k, horizon + 10 * S + k * 8 * S, px_ + 2 + k, horizon + 10 * S + k * 8 * S + 2 * S), fill=hexrgb(LIGHT_WARM) + (int(60 - k * 12),))
    for k in range(30):
        y = horizon + 10 * S + k * 10 * S
        if y > H:
            break
        wd = (8 + 20 * k / 30) * S
        d.rectangle((mx - wd / 2, y, mx + wd / 2, y + 2 * S), fill=hexrgb('#F3E3A6') + (int(45 * (1 - k / 40)),))
    # the island with the Elder and the props
    isl = Image.open(os.path.join(out, 'island.webp')).convert('RGBA')
    iw = int(LAYOUT['island_w'] * W)
    sc = iw / isl.width
    ih = int(isl.height * sc)
    ix, iy = (W - iw) // 2, int(LAYOUT['island_bottom'] * H - ih)
    comp = isl.copy()
    e = man['island']['elder']
    strip = Image.open(os.path.join(out, 'elder_sleep.webp')).convert('RGBA')
    comp.alpha_composite(strip.crop((0, 0, e['frameW'], e['frameH'])), (e['x'], e['y']))
    comp.alpha_composite(Image.open(os.path.join(out, 'island_front.webp')).convert('RGBA'))
    comp = comp.resize((iw, ih), Image.LANCZOS)
    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse((W / 2 - iw * 0.25, horizon + 20 * S, W / 2 + iw * 0.25, horizon + 34 * S), fill=(0, 0, 0, 50))
    img.alpha_composite(shadow)
    img.alpha_composite(comp, (ix, iy))
    # the logo and the plank
    logo_im = Image.open(os.path.join(out, 'logo.webp')).convert('RGBA')
    lw = int(LAYOUT['logo_w'] * W)
    logo_im = logo_im.resize((lw, int(logo_im.height * lw / logo_im.width)), Image.LANCZOS)
    img.alpha_composite(logo_im, ((W - lw) // 2, int(LAYOUT['logo_y'] * H)))
    pw, ph = min(W * 0.62, 300 * S), 54 * S
    cx, cy = W / 2, LAYOUT['plank_y'] * H
    d.rounded_rectangle((cx - pw / 2, cy - ph / 2 + 4 * S, cx + pw / 2, cy + ph / 2 + 4 * S), radius=8 * S, fill=hexrgb('#4A2E1E'))
    d.rounded_rectangle((cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2), radius=8 * S, fill=hexrgb('#6E4529'))
    d.rounded_rectangle((cx - pw / 2 + 3 * S, cy - ph / 2 + 3 * S, cx + pw / 2 - 3 * S, cy + ph / 2 - 3 * S), radius=6 * S, fill=hexrgb('#B98149'))
    try:
        f = ImageFont.truetype(os.path.join(os.path.dirname(__file__), '..', '..', 'flutter', 'assets', 'fonts', 'Nunito-Black.ttf'), 20 * S)
    except OSError:
        f = ImageFont.load_default()
    d.text((cx, cy), 'Tap to begin', fill=hexrgb('#FFF4E2'), font=f, anchor='mm')
    img.save(os.path.join(out, '_screen_preview.png'))
    print('_screen_preview.png', img.size, flush=True)


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = dict(a[2:].split('=', 1) for a in sys.argv[1:] if a.startswith('--') and '=' in a)
    main(args[0] if args else OUT, opts['only'].split(',') if 'only' in opts else None)

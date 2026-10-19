"""Paints the game-native UI materials for the web and Flutter builds (procedural, no external art):

  wood_light.png / wood_mid.png / wood_dark.png   tileable plank grain (horizontal), 512x128
  paper_grain.png                                 tileable paper fibres and mottling as a brown overlay, 256x256
  cloth_weave.png                                 tileable canvas weave overlay for the Bag, 128x128
  frame_wood.png / frame_plum.png / frame_leather.png / frame_cloth.png
                                                  9-slice window frames, 192x192, slice 56 (carved, mitred
                                                  corners, brass rivets; the centre is transparent)

python3 ui_textures.py OUT_DIR
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(43)


def periodic_noise(h, w, scale_y, scale_x, seed):
    """Smooth noise that tiles in both directions (band-limited random field)."""
    r = np.random.default_rng(seed)
    f = np.fft.fft2(r.standard_normal((h, w)))
    fy = np.fft.fftfreq(h)[:, None] * h
    fx = np.fft.fftfreq(w)[None, :] * w
    env = np.exp(-((fy / scale_y) ** 2 + (fx / scale_x) ** 2))
    n = np.real(np.fft.ifft2(f * env))
    n -= n.min()
    return n / (n.max() + 1e-9)


def hexrgb(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float)


def grain(h, w, seed, rings=9.0):
    """Wood grain along x: warped sine bands plus fine streaks, tileable."""
    warp = periodic_noise(h, w, 3, 2.5, seed) - 0.5
    warp2 = periodic_noise(h, w, 10, 6, seed + 1) - 0.5
    y = np.arange(h)[:, None] / h
    v = (y + 0.22 * warp + 0.05 * warp2) * rings
    bands = 0.5 + 0.5 * np.sin(2 * np.pi * v)
    bands = bands ** 3
    streak = periodic_noise(h, w, 40, 3, seed + 2)
    knots = periodic_noise(h, w, 2, 2, seed + 3)
    return np.clip(0.55 * bands + 0.35 * streak + 0.25 * (knots ** 4), 0, 1)


def wood_tile(name, base, dark, light, seed):
    h, w = 128, 512
    g = grain(h, w, seed)
    c0, c1, c2 = hexrgb(base), hexrgb(dark), hexrgb(light)
    img = c0[None, None, :] * (1 - g[..., None]) + c1[None, None, :] * g[..., None]
    hi = periodic_noise(h, w, 30, 2, seed + 9)
    img = img * (1 - 0.18 * hi[..., None]) + c2[None, None, :] * (0.18 * hi[..., None])
    img += rng.normal(0, 3, img.shape)
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(os.path.join(OUT, name), optimize=True)
    return img


def paper_grain():
    h = w = 256
    mott = periodic_noise(h, w, 6, 6, 11)
    fib = periodic_noise(h, w, 60, 60, 12)
    speck = (rng.random((h, w)) > 0.9965).astype(float)
    speck = np.array(Image.fromarray((speck * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))) / 255.0
    a = 0.05 * mott + 0.035 * fib + 0.35 * speck
    rgba = np.zeros((h, w, 4))
    rgba[..., :3] = hexrgb('#8A5A2B')
    rgba[..., 3] = np.clip(a, 0, 1) * 255
    Image.fromarray(rgba.astype(np.uint8), 'RGBA').save(os.path.join(OUT, 'paper_grain.png'), optimize=True)


def cloth_weave():
    h = w = 128
    y, x = np.mgrid[0:h, 0:w]
    warp = 0.5 + 0.5 * np.sin(2 * np.pi * x / 8)
    weft = 0.5 + 0.5 * np.sin(2 * np.pi * y / 8)
    over = ((x // 8 + y // 8) % 2).astype(float)
    t = over * warp + (1 - over) * weft
    n = periodic_noise(h, w, 12, 12, 21)
    a = 0.06 + 0.10 * t + 0.05 * n
    rgba = np.zeros((h, w, 4))
    rgba[..., :3] = hexrgb('#6B4A2A')
    rgba[..., 3] = np.clip(a, 0, 1) * 255
    Image.fromarray(rgba.astype(np.uint8), 'RGBA').save(os.path.join(OUT, 'cloth_weave.png'), optimize=True)


def rounded_rect_sdf(h, w, x0, y0, x1, y1, r):
    """Signed distance (px) to a rounded rectangle, negative inside."""
    y, x = np.mgrid[0:h, 0:w] + 0.5
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
    qx, qy = np.abs(x - cx) - hx, np.abs(y - cy) - hy
    out = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
    inside = np.minimum(np.maximum(qx, qy), 0)
    return out + inside - r


def frame(name, base, dark, light, ink, seed, rivet='#E8B65A', stitch=None, cloth=False):
    S = 192
    sl = 56
    sdf_out = rounded_rect_sdf(S, S, 4, 4, S - 4, S - 4, 46)
    sdf_in = rounded_rect_sdf(S, S, 4 + 46, 4 + 46, S - 4 - 46, S - 4 - 46, 18)
    body = (sdf_out < 0) & (sdf_in > 0)
    # grain: horizontal on top/bottom, vertical on the sides, mitred along the diagonals
    gh = grain(S, S * 2, seed, rings=5)[:, :S]
    gv = grain(S, S * 2, seed + 5, rings=5)[:, :S].T
    y, x = np.mgrid[0:S, 0:S] + 0.5
    dx, dy = np.minimum(x, S - x), np.minimum(y, S - y)
    side = dx < dy
    g = np.where(side, gv, gh)
    if cloth:
        over = (((x // 6) + (y // 6)) % 2).astype(float)
        g = 0.35 + 0.2 * over * (0.5 + 0.5 * np.sin(2 * np.pi * x / 6)) + 0.2 * (1 - over) * (0.5 + 0.5 * np.sin(2 * np.pi * y / 6))
        g += 0.15 * periodic_noise(S, S, 10, 10, seed)
    c0, c1, c2, ci = hexrgb(base), hexrgb(dark), hexrgb(light), hexrgb(ink)
    col = c0 * (1 - g[..., None]) + c1 * g[..., None]
    # bevel: distance into the frame band (0 at the outer edge, 1 at the inner edge)
    band = np.clip((-sdf_out) / 46.0, 0, 1)
    # light from the top-left: brighten the outer-top-left slope, darken the inner slope
    ny = np.where(side, 0, np.where(y < S / 2, -1, 1))
    nx = np.where(side, np.where(x < S / 2, -1, 1), 0)
    facing = -(nx + ny) * 0.5   # +1 facing the light
    outer = np.clip(1 - band / 0.45, 0, 1)
    inner = np.clip((band - 0.55) / 0.45, 0, 1)
    col = col + (c2 - col) * (0.45 * outer * np.clip(facing + 0.3, 0, 1))[..., None]
    col = col * (1 - 0.30 * inner * np.clip(0.6 - facing, 0, 1.2))[..., None]
    # a carved groove along the middle of the band
    groove = np.exp(-((band - 0.5) / 0.035) ** 2)
    col = col * (1 - 0.35 * groove)[..., None]
    col = col + (c2 - col) * (0.25 * np.exp(-((band - 0.56) / 0.03) ** 2))[..., None]
    # mitre seams
    mitre = np.exp(-((np.abs(dx - dy)) / 1.1) ** 2) * (np.minimum(dx, dy) > 6) * (band < 0.98)
    if not cloth:
        col = col * (1 - 0.35 * mitre)[..., None]
    if stitch:
        cs = hexrgb(stitch)
        # a dashed stitch line at 30% into the band
        along = np.where(side, y, x)
        dash = ((along // 7) % 2 == 0).astype(float)
        line = np.exp(-((band - 0.3) / 0.03) ** 2) * dash
        col = col + (cs - col) * (0.9 * line)[..., None]
    # ink outline outside and inside
    ol = np.clip(1 - np.abs(sdf_out + 2.5) / 2.5, 0, 1)
    il = np.clip(1 - np.abs(sdf_in - 2.0) / 2.0, 0, 1)
    col = col + (ci - col) * np.maximum(ol, il)[..., None]
    # rivets at the four corners
    if rivet:
        cr = hexrgb(rivet)
        for (rx, ry) in [(30, 30), (S - 30, 30), (30, S - 30), (S - 30, S - 30)]:
            d = np.hypot(x - rx, y - ry)
            m = d < 7.5
            hl = np.clip(1 - np.hypot(x - rx + 2.5, y - ry + 2.5) / 5.5, 0, 1)
            rc = cr * (0.75 + 0.25 * hl[..., None]) + 60 * hl[..., None] ** 3
            col = np.where(m[..., None], rc, col)
            ring = np.clip(1 - np.abs(d - 7.5) / 1.3, 0, 1)
            col = col + (ci - col) * ring[..., None]
    alpha = np.clip(0.5 - sdf_out, 0, 1) * np.clip(sdf_in + 0.5, 0, 1)
    col += rng.normal(0, 2.5, col.shape)
    rgba = np.concatenate([np.clip(col, 0, 255), alpha[..., None] * 255], axis=-1).astype(np.uint8)
    Image.fromarray(rgba, 'RGBA').save(os.path.join(OUT, name), optimize=True)


def add_leaves(path, sprigs):
    """Paints little leaf sprigs over a frame's top corners (inside the 56 px corner slices, so they never stretch)."""
    im = np.array(Image.open(path)).astype(float)
    S = im.shape[0]
    y, x = np.mgrid[0:S, 0:S] + 0.5
    for (cx, cy, L, W, ang) in sprigs:
        for mirror in (False, True):
            px = S - cx if mirror else cx
            a = np.radians(180 - ang if mirror else ang)
            ux, uy = np.cos(a), np.sin(a)
            dx, dy = x - px, y - py if False else y - cy
            u = dx * ux + dy * uy           # along the leaf, 0 at the stem
            v = -dx * uy + dy * ux          # across
            t = np.clip(u / L, 0, 1)
            half = W * np.sin(np.pi * t) ** 0.8
            inside = (u > 0) & (u < L) & (np.abs(v) < half)
            edge = inside & (np.abs(v) > half - 1.8) | ((u > 0) & (u < L) & (np.abs(np.abs(v) - half) < 1.0))
            shade = 0.5 + 0.5 * np.clip(-v / (W + 1e-6), -1, 1)
            light, dark = hexrgb('#A9D67A'), hexrgb('#5E9A3E')
            col = light * (1 - shade[..., None]) + dark * shade[..., None]
            rib = inside & (np.abs(v) < 0.9) & (t > 0.08) & (t < 0.85)
            col = np.where(rib[..., None], hexrgb('#3F6E2C'), col)
            ink = hexrgb('#2E4F1E')
            im[..., :3] = np.where(inside[..., None], col, im[..., :3])
            im[..., :3] = np.where(edge[..., None], ink, im[..., :3])
            im[..., 3] = np.where(inside | edge, 255, im[..., 3])
    Image.fromarray(np.clip(im, 0, 255).astype(np.uint8), 'RGBA').save(path, optimize=True)


wood_tile('wood_light.png', '#D6A066', '#B87A42', '#F0C88E', 1)
wood_tile('wood_mid.png', '#A8693A', '#83502A', '#C88A52', 2)
wood_tile('wood_dark.png', '#7A4A28', '#5C361C', '#9A6236', 3)
paper_grain()
cloth_weave()
frame('frame_wood.png', '#B8783F', '#8E5428', '#E3AE6E', '#4A2A14', 31)
frame('frame_plum.png', '#6E4A78', '#4E3158', '#9A76A6', '#2A1730', 32, rivet='#D7B3F0')
frame('frame_leather.png', '#9A4E34', '#7A3824', '#C2775A', '#3E1E12', 33, rivet='#E8B65A', stitch='#F1D9A8')
frame('frame_cloth.png', '#C9A97E', '#B08D62', '#E8D0A8', '#5E4126', 34, rivet=None, stitch='#7A5A36', cloth=True)
# leaf sprigs growing over the top corners of the wood frame (the Market, modals, the encounter panel)
add_leaves(os.path.join(OUT, 'frame_wood.png'), [(8, 34, 26, 7.5, -62), (22, 12, 24, 7, -18), (6, 14, 18, 6, -42)])
print('wrote', sorted(os.listdir(OUT)))

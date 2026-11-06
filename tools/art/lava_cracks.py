"""Lava cracks for the Obsidian charge: each footfall splits the ground in a detailed branching crack (long tapering
trunks, many short spurs, hot nodes at the forks), lava inside it: a yellow-white core, orange body, red edge glow, a
charred rim. Drawn once into a ground texture (with smaller copies for distance) and laid on the ground plane through
the lens (each pixel's ray hits the ground), opening out from the footfall and staying molten after."""
import math

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

S = 768          # texture size
SS = 2           # drawn at twice that, then reduced (smooth thin lines)
CH = ('body', 'core', 'edge', 'wide', 'flare', 'char', 'A', 'Ah', 'N')


def make_texture(seed, trunks=5, reach=0.46, w0=1.25, D=70.0, depth=3, pb=(0.30, 0.18)):
    """the crack texture: channels (S, S) in 0..1; A, Ah: when (0..1 of the way out) each line / its halo is reached"""
    rng = np.random.default_rng(seed)
    Z = S * SS
    upx = Z / D                                     # drawing px per world unit
    segs = []                                       # (dist, p0, p1, width px)
    nodes = []                                      # (x, y, r px)
    c = np.array([Z / 2, Z / 2])

    def branch(p, ang, length, w, depth, dist):
        base = ang
        n = max(4, int(length / (1.7 * upx)))
        step = length / n
        pts = [p]
        for i in range(n):
            ang += rng.normal(0, 0.36) + (base - ang) * 0.22
            q = pts[-1] + np.array([math.cos(ang), math.sin(ang)]) * step * rng.uniform(0.6, 1.4)
            s = i / n
            wd = max(0.12 * upx, w * (1 - s) ** 0.75)
            segs.append((dist + i * step, pts[-1], q, wd))
            pts.append(q)
            if depth > 0 and i > 1 and rng.random() < (pb[0] if depth > 1 else pb[1]):
                side = rng.choice((-1, 1))
                if wd > 0.4 * upx:
                    nodes.append((q[0], q[1], wd * 1.1))
                branch(q, ang + side * rng.uniform(0.5, 1.25), length * (1 - s) * rng.uniform(0.35, 0.7),
                       wd * rng.uniform(0.55, 0.8), depth - 1, dist + (i + 1) * step)
        if depth > 0 and rng.random() < 0.5:        # a fork at the tip
            q = pts[-1]
            for side in (-1, 1):
                branch(q, ang + side * rng.uniform(0.3, 0.7), length * rng.uniform(0.15, 0.3),
                       max(0.12 * upx, w * 0.25), 0, dist + length)
    nodes.append((c[0], c[1], w0 * upx * 1.8))
    a0 = rng.uniform(0, 2 * math.pi)
    for k in range(trunks):
        ang = a0 + k * 2 * math.pi / trunks + rng.uniform(-0.35, 0.35)
        L = Z * reach * rng.uniform(0.6, 1.0)
        start = c + np.array([math.cos(ang), math.sin(ang)]) * rng.uniform(0, 0.6) * upx
        branch(start, ang, L, w0 * upx * rng.uniform(0.75, 1.1), depth, 0.0)
    maxd = max(s_[0] for s_ in segs) + 1e-6
    body = Image.new('L', (Z, Z), 0)
    core = Image.new('L', (Z, Z), 0)
    A = Image.new('L', (Z, Z), 255)
    db, dc, da = ImageDraw.Draw(body), ImageDraw.Draw(core), ImageDraw.Draw(A)
    for dist, p0, p1, wd in segs:
        for dr_, wk in ((db, 1.0), (dc, 0.38)):
            ww = max(1, int(wd * wk))
            dr_.line([tuple(p0), tuple(p1)], fill=255, width=ww)
            r = ww / 2
            dr_.ellipse([p1[0] - r, p1[1] - r, p1[0] + r, p1[1] + r], fill=255)
    for dist, p0, p1, wd in sorted(segs, key=lambda s_: -s_[0]):  # nearest last: each pixel keeps its earliest
        ww = max(2, int(wd * 1.6) + 4)
        da.line([tuple(p0), tuple(p1)], fill=int(254 * dist / maxd), width=ww)
    fl = Image.new('L', (Z, Z), 0)
    dfl = ImageDraw.Draw(fl)
    for x, y, r in nodes:
        dfl.ellipse([x - r, y - r, x + r, y + r], fill=255)
    out = {}
    out['body'] = np.asarray(body.resize((S, S), Image.LANCZOS), np.float32) / 255
    out['core'] = np.asarray(core.resize((S, S), Image.LANCZOS), np.float32) / 255
    out['A'] = np.asarray(A.resize((S, S), Image.NEAREST), np.float32) / 255
    flm = np.asarray(fl.resize((S, S), Image.LANCZOS), np.float32) / 255
    b = out['body']
    out['edge'] = np.clip(ndimage.gaussian_filter(b, 2.0) * 1.4, 0, 1)
    out['wide'] = np.clip(ndimage.gaussian_filter(b, 8.0) * 2.0, 0, 1)
    out['flare'] = np.clip(ndimage.gaussian_filter(flm, 2.0) * 1.0 + ndimage.gaussian_filter(flm, 7.0) * 1.2, 0, 1)
    out['char'] = np.clip(ndimage.gaussian_filter(ndimage.grey_dilation(b, size=5), 5.0) * 1.8, 0, 1)
    out['Ah'] = ndimage.grey_erosion(out['A'], size=27)
    nz = rng.random((S // 16, S // 16))
    out['N'] = np.asarray(Image.fromarray((nz * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC), np.float32) / 255
    stack = np.stack([out[k] for k in CH], -1)
    levels = [stack]
    for _ in range(2):                              # smaller copies for the distance (no shimmer)
        s = levels[-1]
        levels.append(s.reshape(s.shape[0] // 2, 2, s.shape[1] // 2, 2, len(CH)).mean((1, 3)))
    return [np.clip(l * 255, 0, 255).astype(np.uint8) for l in levels]


def ground_rays(cam, fit, W, H, yg):
    """where each pixel's ray meets the ground (y = yg): (gx, gz, depth, valid), all (H, W)"""
    d, r, u = cam.basis()
    f = 1.0 / math.tan(math.radians(cam.fov) / 2)
    X, Y = np.meshgrid(np.arange(W) + 0.5, np.arange(H) + 0.5)
    sx, sy = (X - fit.ox) / fit.scale, (Y - fit.oy) / fit.scale
    dirs = (sx / f)[..., None] * r + (-sy / f)[..., None] * u - d
    C = np.array(cam.target, float) + d * cam.persp
    with np.errstate(divide='ignore', invalid='ignore'):
        t = (yg - C[1]) / dirs[..., 1]
    ok = (t > 0) & np.isfinite(t)
    t = np.where(ok, t, 0)
    G = C + dirs * t[..., None]
    graze = np.abs(dirs[..., 1]) / np.linalg.norm(dirs, axis=-1)
    foot = t / (f * fit.scale) / np.maximum(graze, 0.12) ** 0.6    # world units a pixel covers (roughly)
    return G[..., 0], G[..., 2], foot, ok


def _bilinear(tex, u, v):
    n = tex.shape[0]
    u = np.clip(u, 0, n - 1.001)
    v = np.clip(v, 0, n - 1.001)
    i0, j0 = u.astype(int), v.astype(int)
    fu, fv = (u - i0)[:, None], (v - j0)[:, None]
    a = tex[j0, i0].astype(np.float32)
    b = tex[j0, i0 + 1].astype(np.float32)
    c = tex[j0 + 1, i0].astype(np.float32)
    d = tex[j0 + 1, i0 + 1].astype(np.float32)
    return ((a * (1 - fu) + b * fu) * (1 - fv) + (c * (1 - fu) + d * fu) * fv) / 255.0


def sample(levels, rays, cx, cz, D, rot):
    """the crack's channels where its square of ground shows: (index of pixels, (n, channels))"""
    gx, gz, foot, ok = rays
    dx, dz = gx - cx, gz - cz
    cr, sr = math.cos(rot), math.sin(rot)
    lu, lv = dx * cr - dz * sr, dx * sr + dz * cr
    m = ok & (np.abs(lu) < D / 2) & (np.abs(lv) < D / 2)
    idx = np.nonzero(m.ravel())[0]
    if idx.size == 0:
        return idx, None
    lu, lv, ft = lu.ravel()[idx], lv.ravel()[idx], foot.ravel()[idx]
    tpp = ft * S / D
    lod = np.clip(np.log2(np.maximum(tpp, 1e-6)), 0, 2)
    out = np.zeros((idx.size, len(CH)), np.float32)
    for k in range(3):
        sel = (np.floor(lod) == k) if k < 2 else (lod >= 2)
        if not sel.any():
            continue
        n = levels[k].shape[0]
        u = (lu[sel] / D + 0.5) * n - 0.5
        v = (lv[sel] / D + 0.5) * n - 0.5
        s0 = _bilinear(levels[k], u, v)
        if k < 2:
            n1 = levels[k + 1].shape[0]
            s1 = _bilinear(levels[k + 1], (lu[sel] / D + 0.5) * n1 - 0.5, (lv[sel] / D + 0.5) * n1 - 0.5)
            fr = (lod[sel] - k)[:, None]
            s0 = s0 * (1 - fr) + s1 * fr
        out[sel] = s0
    return idx, out


HOTC = np.array([255, 244, 196], np.float32) / 255
YEL = np.array([255, 196, 70], np.float32) / 255
ORA = np.array([255, 110, 28], np.float32) / 255
RED = np.array([214, 46, 14], np.float32) / 255
DEEP = np.array([150, 24, 6], np.float32) / 255


def shade(ch, g, heat, T):
    """the lava's light and the char's darkening for sampled channels: g how far out it has split (0..1)"""
    body, core, edge, wide, flare, char, A, Ah, N = [ch[:, i:i + 1] for i in range(len(CH))]
    vis = np.clip((g - A) / 0.05, 0, 1)
    vh = np.clip((g - Ah) / 0.08, 0, 1)
    pulse = 0.82 + 0.18 * np.sin(T * 5.0 + N * 9.0) + 0.1 * np.sin(T * 11.0 + N * 23.0)
    h = heat * pulse
    light = (core * vis * (YEL * 0.9 + HOTC * 0.5) * h
             + body * vis * ORA * 0.95 * h
             + edge * vh * RED * 0.55 * h
             + wide * vh * DEEP * 0.22 * h
             + flare * vh * (ORA * 0.5 + YEL * 0.6) * h)
    dark = char * vh * 0.65
    return light, dark

"""Bakes the effect sprites the Elders' ultimates play in the Wilds once their cut-in hands back to the fight
(wilds_screen.dart draws them; ult_fx.dart loads them). Each is a flipbook in one WebP atlas, listed in
ultfx.json with its frame size, frame count, variants (rows) and the anchor it is drawn from:

  quake_cracks   ground   the Obsidian's Quake: the lava cracks of its cinematic splitting out across the ground
  snare_web      ground   the Forest's Thorn Snare: a web of glowing roots spreading underfoot
  snare_root     stand    a thorned root bursting up out of it (three shapes), growing over 12 frames
  sun_flare      add      the Amber's Sunflare: a sun's disc breaking open, its rays sweeping, a ring of light
  dazzle         add      the glint on each creature the Sunflare dazzles
  reef_web       ground   the Coral's Reef Bloom: a glowing reef of polyps spreading underfoot
  reef_coral     stand    a branch of coral growing up out of it (three shapes)
  crystal_burst  add      the Amethyst's Crystal Shards: a violet star breaking open as the shards leave
  dust           normal   a billow of dust (four shapes), lit warm from underneath
  rocks          normal   tumbling rock chunks (six shapes, 12 turns: rendered in Blender by
                          rock_chunks_blender.py into CHUNKS_DIR)

    python3 ult_fx_bake.py ../../flutter/assets/art/wilds [CHUNKS_DIR]

Ground decals are drawn from straight above (the app squashes them onto the ground's ellipse); standing pieces
from the Wilds' map pitch (35 degrees), their anchor at the root.
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

import lava_cracks as LC

OUT = sys.argv[1] if len(sys.argv) > 1 else '../../flutter/assets/art/wilds'
CHUNKS = sys.argv[2] if len(sys.argv) > 2 else None
META = {}


def hx(c):
    c = c.lstrip('#')
    return np.array([int(c[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255


def save_atlas(name, frames, fw, fh, kind, ax=0.5, ay=0.5, quality=80, variants=1):
    """frames: list (variant-major) of RGBA float (fh, fw, 4) in 0..1, premultiplied=False"""
    n = len(frames) // variants
    cols = n
    W, H = fw * cols, fh * variants
    sheet = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        im = Image.fromarray((np.clip(f, 0, 1) * 255).round().astype(np.uint8), 'RGBA')
        sheet.paste(im, ((i % n) * fw, (i // n) * fh))
    fn = 'ultfx_%s.webp' % name
    sheet.save(os.path.join(OUT, fn), 'WEBP', quality=quality, method=6, exact=False)
    META[name] = {'file': fn, 'fw': fw, 'fh': fh, 'n': n, 'variants': variants, 'kind': kind, 'ax': ax, 'ay': ay}
    print('%-14s %2d x %d  %4dx%-4d %6.1f KB' % (name, n, variants, fw, fh, os.path.getsize(os.path.join(OUT, fn)) / 1024), flush=True)


# ------------------------------------------------------------------------------------------- ground decals
def decal(levels, g, colours, heat=1.0, T=0.3, soft=1.0):
    """a crack/root/reef texture opened out to g (0..1) as an RGBA decal: the light in its colours (core, body,
    edge, wide, flare) over a darkened rim"""
    st = levels[0].astype(np.float32) / 255
    body, core, edge, wide, flare, char, A, Ah, N = [st[..., i:i + 1] for i in range(len(LC.CH))]
    vis = np.clip((g - A) / 0.05, 0, 1)
    vh = np.clip((g - Ah) / 0.08, 0, 1)
    pulse = 0.85 + 0.15 * np.sin(T * 5 + N * 9)
    h = heat * pulse
    c_core, c_body, c_edge, c_wide, c_flare, c_dark = colours
    light = (core * vis * c_core * 1.6 + body * vis * c_body * 0.95 + edge * vh * c_edge * 0.5 * soft
             + wide * vh * c_wide * 0.25 * soft + flare * vh * c_flare * 0.7) * h
    m = light.max(-1, keepdims=True)
    al = np.clip(m * 1.4, 0, 1)
    col = np.clip(light / np.maximum(m, 1e-4), 0, 1)            # its hue at full brightness: saturated lava
    ca = char * vh * 0.55
    a = al + ca * (1 - al)
    rgb = (col * al + c_dark * ca * (1 - al)) / np.maximum(a, 1e-4)
    return np.concatenate([rgb, a], -1)


def bake_decal(name, seed, colours, D, trunks, w0, frames=10, size=384, soft=1.0, reach=0.46, depth=2, pb=(0.22, 0.12)):
    lv = LC.make_texture(seed, trunks=trunks, reach=reach, w0=w0, D=D, depth=depth, pb=pb)
    out = []
    for f in range(frames):
        u = (f + 1) / frames
        g = (1 - (1 - u) ** 2) * 1.02
        heat = 1.0 + 0.4 * (1 - u)                       # a flash as it splits
        d = decal(lv, g, colours, heat=heat, T=f * 0.05, soft=soft)
        im = Image.fromarray((np.clip(d, 0, 1) * 255).astype(np.uint8), 'RGBA').resize((size, size), Image.LANCZOS)
        out.append(np.asarray(im, np.float32) / 255)
    save_atlas(name, out, size, size, 'ground')


LAVA = (np.array([1.0, 0.92, 0.70]) * 1.0, np.array([1.0, 0.45, 0.12]), np.array([0.85, 0.18, 0.05]),
        np.array([0.6, 0.1, 0.03]), np.array([1.0, 0.75, 0.3]), np.array([0.10, 0.06, 0.05]))
ROOTS = (np.array([0.93, 1.0, 0.70]), np.array([0.55, 0.85, 0.30]), np.array([0.30, 0.62, 0.16]),
         np.array([0.20, 0.45, 0.10]), np.array([0.85, 1.0, 0.55]), np.array([0.12, 0.16, 0.07]))
REEF = (np.array([1.0, 0.78, 0.72]), np.array([1.0, 0.46, 0.42]), np.array([0.95, 0.36, 0.40]),
        np.array([0.80, 0.30, 0.40]), np.array([1.0, 0.85, 0.75]), np.array([0.14, 0.10, 0.12]))


# ------------------------------------------------------------------------------------------ standing pieces
SS = 3


def _poly_tube(dr, pts, widths, fill):
    for (p0, w0), (p1, w1) in zip(zip(pts, widths), zip(pts[1:], widths[1:])):
        d = np.array(p1) - np.array(p0)
        n = np.array([-d[1], d[0]]) / (np.linalg.norm(d) + 1e-6)
        q = [tuple(np.array(p0) + n * w0), tuple(np.array(p1) + n * w1), tuple(np.array(p1) - n * w1),
             tuple(np.array(p0) - n * w0)]
        dr.polygon(q, fill=fill)
        dr.ellipse([p1[0] - w1, p1[1] - w1, p1[0] + w1, p1[1] + w1], fill=fill)


def root_frames(seed, fw=128, fh=192, n=12):
    """a thorned root bursting up out of the ground and curling over at its tip: dark bark, a lit side, thorns
    along it, a couple of leaves; growing along its own length over the frames"""
    rng = np.random.default_rng(seed)
    W, H = fw * SS, fh * SS
    base = np.array([W * 0.5, H * 0.94])
    lean = rng.uniform(-0.5, 0.5)
    curl = rng.choice((-1, 1)) * rng.uniform(0.9, 1.6)
    L = H * rng.uniform(0.70, 0.82)
    m = 40
    path = [base]
    ang = -math.pi / 2 + lean * 0.4
    for i in range(1, m + 1):
        s = i / m
        ang += (curl * 1.6 * s ** 2.2 + rng.normal(0, 0.05)) / m * 2.2
        path.append(path[-1] + np.array([math.cos(ang), math.sin(ang)]) * L / m)
    path = np.array(path)
    wid = W * 0.13 * (1 - np.linspace(0, 1, m + 1)) ** 0.75 + SS * 1.6
    thorns = [(int(rng.uniform(6, m - 4)), rng.choice((-1, 1)), rng.uniform(0.6, 1.0)) for _ in range(9)]
    leaves = [(int(rng.uniform(10, m - 10)), rng.choice((-1, 1))) for _ in range(2)]
    out = []
    for f in range(n):
        g = 1 - (1 - (f + 1) / n) ** 2.2
        k = max(2, int(round(g * m)))
        P, Wd = path[:k + 1], wid[:k + 1] * (0.55 + 0.45 * g)
        im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        # the mound of earth it breaks out of
        rr = W * 0.16 * min(1.0, g * 2.5)
        dr.ellipse([base[0] - rr * 1.5, base[1] - rr * 0.55, base[0] + rr * 1.5, base[1] + rr * 0.35], fill=(70, 52, 34, 235))
        _poly_tube(dr, P, Wd, (52, 78, 34, 255))                                     # bark
        lit = [tuple(p + np.array([-w * 0.35, -w * 0.15])) for p, w in zip(P, Wd)]
        _poly_tube(dr, lit, Wd * 0.45, (112, 160, 62, 255))                         # the lit side
        _poly_tube(dr, [tuple(p + np.array([-w * 0.45, -w * 0.2])) for p, w in zip(P, Wd)], Wd * 0.14,
                   (190, 230, 120, 255))                                             # its glint
        for idx, side, sz in thorns:
            if idx >= k - 1:
                continue
            p, q = P[idx], P[idx + 1]
            d = (q - p) / (np.linalg.norm(q - p) + 1e-6)
            nrm = np.array([-d[1], d[0]]) * side
            w = Wd[idx]
            tip = p + nrm * (w + W * 0.07 * sz) + d * W * 0.03
            dr.polygon([tuple(p + nrm * w * 0.8 - d * w * 0.5), tuple(p + nrm * w * 0.8 + d * w * 0.5), tuple(tip)],
                       fill=(200, 214, 150, 255))
        for idx, side in leaves:
            if idx >= k - 2:
                continue
            p = P[idx]
            d = (P[idx + 1] - p) / (np.linalg.norm(P[idx + 1] - p) + 1e-6)
            nrm = np.array([-d[1], d[0]]) * side
            c = p + nrm * W * 0.14 - d * W * 0.04
            box = [c[0] - W * 0.09, c[1] - W * 0.045, c[0] + W * 0.09, c[1] + W * 0.045]
            lf = Image.new('RGBA', (W, H), (0, 0, 0, 0))
            ImageDraw.Draw(lf).ellipse(box, fill=(130, 196, 80, 255))
            ImageDraw.Draw(lf).line([tuple(p), tuple(c + nrm * W * 0.08)], fill=(90, 140, 50, 255), width=SS * 2)
            im = Image.alpha_composite(im, lf)
            dr = ImageDraw.Draw(im)
        a = np.asarray(im.resize((fw, fh), Image.LANCZOS), np.float32) / 255
        # a soft green light round it (the snare's magic)
        glow = ndimage.gaussian_filter(a[..., 3], 5) * 0.35 * g
        rgb = a[..., :3] * a[..., 3:4] + np.array([0.7, 1.0, 0.45]) * glow[..., None] * (1 - a[..., 3:4])
        al = np.clip(a[..., 3] + glow * (1 - a[..., 3]), 0, 1)
        out.append(np.dstack([rgb / np.maximum(al[..., None], 1e-4), al]))
    return out


def coral_frames(seed, fw=160, fh=176, n=12):
    """a branch of coral growing up out of the reef: forking arms, thick at the root, their tips glowing"""
    rng = np.random.default_rng(seed)
    W, H = fw * SS, fh * SS
    segs = []

    def grow(p, ang, L, w, depth, t0):
        steps = 6
        q = np.array(p, float)
        for i in range(steps):
            ang += rng.normal(0, 0.12)
            q2 = q + np.array([math.cos(ang), math.sin(ang)]) * L / steps
            segs.append((t0 + i / steps * 0.45, q.copy(), q2.copy(), w * (1 - 0.35 * i / steps), depth))
            q = q2
            if depth > 0 and i in (2, 4) and rng.random() < 0.8:
                grow(q, ang + rng.choice((-1, 1)) * rng.uniform(0.3, 0.6), L * 0.55, w * 0.72, depth - 1,
                     t0 + (i + 1) / steps * 0.45)
        segs.append((t0 + 0.45, q.copy(), None, w, -1))            # its tip
    grow((W * 0.5, H * 0.95), -math.pi / 2 + rng.uniform(-0.2, 0.2), H * 0.42, W * 0.075, 2, 0.0)
    tmax = max(s[0] for s in segs) + 0.05
    pink, deep, tipc = (255, 140, 128, 255), (214, 92, 88, 255), (255, 228, 214, 255)
    out = []
    for f in range(n):
        g = (1 - (1 - (f + 1) / n) ** 2) * tmax
        im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        tips = []
        for t0, p, q, w, depth in segs:
            if t0 > g:
                continue
            if q is None:
                tips.append((p, w))
                continue
            k = min(1.0, (g - t0) / 0.08)
            q2 = p + (q - p) * k
            dr.line([tuple(p), tuple(q2)], fill=deep, width=int(w * 2))
            dr.line([tuple(p - np.array([w * 0.3, 0])), tuple(q2 - np.array([w * 0.3, 0]))], fill=pink, width=max(1, int(w * 1.2)))
            dr.ellipse([q2[0] - w, q2[1] - w, q2[0] + w, q2[1] + w], fill=deep)
        for p, w in tips:
            dr.ellipse([p[0] - w * 0.95, p[1] - w * 0.95, p[0] + w * 0.95, p[1] + w * 0.95], fill=tipc)
        a = np.asarray(im.resize((fw, fh), Image.LANCZOS), np.float32) / 255
        glow = ndimage.gaussian_filter(a[..., 3], 4) * 0.3
        rgb = a[..., :3] * a[..., 3:4] + np.array([1.0, 0.8, 0.75]) * glow[..., None] * (1 - a[..., 3:4])
        al = np.clip(a[..., 3] + glow * (1 - a[..., 3]), 0, 1)
        out.append(np.dstack([rgb / np.maximum(al[..., None], 1e-4), al]))
    return out


# ------------------------------------------------------------------------------------------- light bursts
def _radial(size):
    yy, xx = (np.mgrid[0:size, 0:size] + 0.5) / size * 2 - 1
    return np.hypot(xx, yy), np.arctan2(yy, xx)


def add_frame(light):
    """an additive frame: colour premultiplied by its own brightness, alpha its brightness (drawn with plus)"""
    L = 1 - np.exp(-light * 1.3)
    a = np.clip(L.max(-1), 0, 1)
    return np.dstack([L / np.maximum(a[..., None], 1e-4), a])


def sun_frames(size=384, n=16):
    r, th = _radial(size)
    rng = np.random.default_rng(5)
    rays = [(rng.uniform(0, 2 * math.pi), rng.uniform(0.02, 0.05), rng.uniform(0.6, 1.0)) for _ in range(14)]
    wide = [(i * 2 * math.pi / 6 + 0.3, 0.16, 0.8) for i in range(6)]
    gold, white, orange = np.array([1.0, 0.82, 0.38]), np.array([1.0, 0.97, 0.88]), np.array([1.0, 0.6, 0.2])
    out = []
    for f in range(n):
        u = f / (n - 1)
        burst = 1 - (1 - min(1.0, u / 0.35)) ** 2               # opening
        fade = 1 - max(0.0, (u - 0.45) / 0.55) ** 1.5
        rot = 0.35 * u
        disc = np.exp(-(r / (0.08 + 0.08 * burst)) ** 2) * 1.2
        halo = np.exp(-(r / (0.30 + 0.3 * burst)) ** 2) * 0.45
        ray = np.zeros_like(r)
        for a0, w, s in rays:
            d = np.angle(np.exp(1j * (th - a0 - rot)))
            ray += np.exp(-(d / w) ** 2) * s * np.clip(1 - r / (0.25 + 0.75 * burst * s), 0, 1)
        for a0, w, s in wide:
            d = np.angle(np.exp(1j * (th - a0 + rot * 0.6)))
            ray += np.exp(-(d / w) ** 2) * 0.35 * np.clip(1 - r / (0.2 + 0.8 * burst), 0, 1)
        ringr = 0.15 + 0.8 * (1 - (1 - u) ** 2)
        ring = np.exp(-((r - ringr) / 0.025) ** 2) * 0.9 * (1 - u)
        light = (disc[..., None] * white + halo[..., None] * gold + ray[..., None] * (gold * 0.8 + white * 0.4)
                 + ring[..., None] * orange) * fade
        out.append(add_frame(light))
    return out


def dazzle_frames(size=96, n=8):
    r, th = _radial(size)
    out = []
    for f in range(n):
        u = f / (n - 1)
        s = math.sin(u * math.pi)
        star = np.zeros_like(r)
        for k, w in ((0, 0.06), (math.pi / 4, 0.04)):
            for a in (k, k + math.pi / 2):
                d = np.abs(np.sin(th - a - u * 0.6))
                star += np.exp(-(d / w) ** 2) * np.clip(1 - r / (0.95 * s + 0.05), 0, 1) * (1.0 if k == 0 else 0.5)
        core = np.exp(-(r / 0.12) ** 2) * 1.5
        light = (star[..., None] * np.array([1.0, 0.93, 0.7]) + core[..., None] * np.array([1.0, 1.0, 0.95])) * s * 1.4
        out.append(add_frame(light))
    return out


def crystal_frames(size=256, n=12):
    r, th = _radial(size)
    rng = np.random.default_rng(9)
    spokes = [(i * 2 * math.pi / 12 + rng.uniform(-0.1, 0.1), rng.uniform(0.7, 1.0)) for i in range(12)]
    vio, pale, deep = np.array([0.78, 0.6, 1.0]), np.array([0.96, 0.92, 1.0]), np.array([0.5, 0.3, 0.85])
    out = []
    for f in range(n):
        u = f / (n - 1)
        burst = 1 - (1 - min(1.0, u / 0.4)) ** 2
        fade = 1 - max(0.0, (u - 0.35) / 0.65)
        core = np.exp(-(r / (0.08 + 0.1 * burst)) ** 2) * 2.0
        sp = np.zeros_like(r)
        for a0, s in spokes:
            d = np.angle(np.exp(1j * (th - a0)))
            reach = 0.2 + 0.8 * burst * s
            sp += np.exp(-(d / (0.05 * (1 - r) + 0.008)) ** 2) * np.clip(1 - r / reach, 0, 1) ** 0.6
        hexr = 0.1 + 0.75 * burst
        hexd = r * np.cos((np.angle(np.exp(1j * th * 6)) / 6))   # a hexagonal ring
        ring = np.exp(-((hexd - hexr) / 0.02) ** 2) * (1 - u) * 0.9
        light = (core[..., None] * pale + sp[..., None] * (vio * 0.9 + pale * 0.3) + ring[..., None] * deep * 1.4) * fade
        out.append(add_frame(light))
    return out


def dust_frames(n=4, size=128):
    out = []
    for k in range(n):
        rng = np.random.default_rng(300 + k)
        yy, xx = (np.mgrid[0:size, 0:size] + 0.5) / size - 0.5
        den = np.zeros((size, size))
        for _ in range(16):
            cx, cy = rng.normal(0, 0.13, 2)
            sg = rng.uniform(0.07, 0.16)
            den += rng.uniform(0.5, 1.0) * np.exp(-((xx - cx) ** 2 + (yy - cy) ** 2) / (2 * sg * sg))
        nz = ndimage.gaussian_filter(rng.random((size, size)), 3, mode='wrap')
        nz = (nz - nz.min()) / (nz.max() - nz.min())
        den = den * (0.55 + 0.9 * nz)
        al = np.clip(den * 1.2 - 0.12, 0, 1) * np.clip(1 - (np.hypot(xx, yy) / 0.5) ** 3, 0, 1)
        top = np.clip(0.5 - yy * 1.2, 0, 1)[..., None]
        sh = ndimage.gaussian_filter(den, 3)
        lit = np.clip((sh - np.roll(sh, 5, axis=0)) * 2.0, -0.3, 0.4)[..., None]
        rgb = np.array([150, 128, 112]) / 255 * (0.8 + 0.35 * top + lit) + np.array([255, 130, 60]) / 255 * 0.22 * (1 - top)
        out.append(np.dstack([np.clip(rgb, 0, 1), al * 0.9]))
    return out


def rock_frames(src, size=64):
    out = []
    for s in range(1, 7):
        for f in range(12):
            p = os.path.join(src, 'c%d_%02d.png' % (s, f))
            im = Image.open(p).convert('RGBA').resize((size, size), Image.LANCZOS)
            out.append(np.asarray(im, np.float32) / 255)
    return out


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    bake_decal('quake_cracks', 777, LAVA, D=200.0, trunks=7, w0=2.2)
    bake_decal('snare_web', 412, ROOTS, D=160.0, trunks=8, w0=1.8, soft=0.8)
    bake_decal('reef_web', 233, REEF, D=120.0, trunks=9, w0=1.4, soft=1.2, reach=0.44, depth=3, pb=(0.25, 0.15))
    save_atlas('snare_root', sum((root_frames(s) for s in (11, 12, 13)), []), 128, 192, 'stand', ax=0.5, ay=0.94,
               variants=3)
    save_atlas('reef_coral', sum((coral_frames(s) for s in (21, 22, 23)), []), 160, 176, 'stand', ax=0.5, ay=0.95,
               variants=3)
    save_atlas('sun_flare', sun_frames(), 384, 384, 'add')
    save_atlas('dazzle', dazzle_frames(), 96, 96, 'add')
    save_atlas('crystal_burst', crystal_frames(), 256, 256, 'add')
    save_atlas('dust', dust_frames(), 128, 128, 'normal', ay=0.6)
    if CHUNKS and os.path.isdir(CHUNKS):
        save_atlas('rocks', rock_frames(CHUNKS), 64, 64, 'normal', variants=6)
    path = os.path.join(OUT, 'ultfx.json')
    old = json.load(open(path)) if os.path.exists(path) else {}
    old.update(META)
    json.dump(old, open(path, 'w'), indent=1)
    print('->', path)

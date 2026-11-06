"""Bakes the effect sprites the Elders' ultimates play in the Wilds once their cut-in hands back to the fight
(wilds_screen.dart draws them; ult_fx.dart loads them). Each is a flipbook in one WebP atlas, listed in
ultfx.json with its frame size, frame count, variants (rows) and the anchor it is drawn from:

  quake_cracks   ground   the Obsidian's Quake: the ground ruptured from where it lands, seven jagged cracks and
                          their forks, dark split edges round a lava core, a scorched rim; 8 frames splitting out
                          (the lava at its hottest), then 8 cooling (yellow to orange to red, to charred cracks)
  snare_root     stand    the Forest's Thorn Snare: a thorned root bursting up out of the earth and hooking over
                          (three shapes), growing over 12 frames
  reef_caustics  ground   the Coral's Reef Bloom: a pool of water-light, its caustics rippling (8 frames, a loop)
  reef_coral     stand    a fan of staghorn coral growing up out of it (three shapes)
  sun_flare      add      the Amber's Sunflare: a sun's disc breaking open, eight god rays turning, one soft ring
  dazzle         add      the glint on each creature the Sunflare dazzles
  crystal_burst  add      the Amethyst's Crystal Shards: a six-pointed violet star breaking open, glints flung off
  dust           normal   a billow of dust (four shapes), lit warm from underneath
  rocks          normal   tumbling rock chunks (six shapes, 12 turns: rendered in Blender by
                          rock_chunks_blender.py into CHUNKS_DIR)

    python3 ult_fx_bake.py ../../flutter/assets/art/wilds [CHUNKS_DIR]

The look follows the usual rules for readable effects: one clear main shape per effect, a few secondary pieces,
sparse small ones, and empty space between; a fast, bright impact that loses its intensity before it goes.
Ground decals are drawn from straight above (the app squashes them onto the ground's ellipse); standing pieces
from the Wilds' map pitch, their anchor at the root.
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

OUT = sys.argv[1] if len(sys.argv) > 1 else '../../flutter/assets/art/wilds'
CHUNKS = sys.argv[2] if len(sys.argv) > 2 else None
META = {}
SS = 3                                                   # supersampling for the drawn shapes


def save_atlas(name, frames, fw, fh, kind, ax=0.5, ay=0.5, quality=80, variants=1, **extra):
    """frames: list (variant-major) of RGBA float (fh, fw, 4) in 0..1, not premultiplied"""
    n = len(frames) // variants
    sheet = Image.new('RGBA', (fw * n, fh * variants), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        im = Image.fromarray((np.clip(f, 0, 1) * 255).round().astype(np.uint8), 'RGBA')
        sheet.paste(im, ((i % n) * fw, (i // n) * fh))
    fn = 'ultfx_%s.webp' % name
    sheet.save(os.path.join(OUT, fn), 'WEBP', quality=quality, method=6, exact=False)
    META[name] = dict({'file': fn, 'fw': fw, 'fh': fh, 'n': n, 'variants': variants, 'kind': kind, 'ax': ax, 'ay': ay}, **extra)
    print('%-14s %2d x %d  %4dx%-4d %6.1f KB' % (name, n, variants, fw, fh, os.path.getsize(os.path.join(OUT, fn)) / 1024), flush=True)


def over(dst, rgb, a):
    """composite a layer (rgb (H, W, 3) or a colour, alpha (H, W)) over dst (H, W, 4)"""
    a = np.clip(a, 0, 1)[..., None]
    da = dst[..., 3:4]
    oa = a + da * (1 - a)
    col = (np.asarray(rgb) * a + dst[..., :3] * da * (1 - a)) / np.maximum(oa, 1e-5)
    return np.concatenate([col, oa], -1)


def lerp(a, b, t):
    return np.asarray(a) * (1 - t) + np.asarray(b) * t


# ------------------------------------------------------------------------------------------- the rupture
def rupture_geometry(seed, K=7):
    """the cracks, in a unit disc: [(points (m, 2), half-widths (m,), distance along from the centre (m,))],
    and the crater's outline"""
    rng = np.random.default_rng(seed)
    crater = [(math.cos(a) * r, math.sin(a) * r) for a, r in
              ((i * 2 * math.pi / 11, 0.10 * rng.uniform(0.75, 1.25)) for i in range(11))]
    cracks = []
    forks = []                                           # where a crack forks: a hot node, as in the cinematic

    def crack(p0, ang, L, w0, d0, depth):
        m = int(rng.integers(4, 7)) if depth == 0 else int(rng.integers(2, 4))
        pts, base = [np.array(p0)], ang
        for i in range(m):
            ang += rng.choice((-1, 1)) * rng.uniform(0.25, 0.6) + (base - ang) * 0.5   # straight runs, sharp turns
            pts.append(pts[-1] + np.array([math.cos(ang), math.sin(ang)]) * L / m * rng.uniform(0.7, 1.3))
        pts = np.array(pts)
        seg = np.r_[0, np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))]
        s = seg / seg[-1]
        w = (w0 * (1 - s) ** 0.85 + 0.0035) * rng.uniform(0.75, 1.25, len(s))   # tapered, chipped
        cracks.append((pts, w, d0 + seg))
        if depth == 0:
            for _ in range(int(rng.integers(0, 2)) + (1 if rng.random() < 0.5 else 0)):
                j = int(rng.integers(2, m - 1))
                side = rng.choice((-1, 1))
                dj = pts[j + 1] - pts[j]
                forks.append((pts[j], d0 + seg[j]))
                crack(pts[j], math.atan2(dj[1], dj[0]) + side * rng.uniform(0.6, 1.0),
                      L * rng.uniform(0.22, 0.38), w[j] * 0.55, d0 + seg[j], 1)
    a0 = rng.uniform(0, 2 * math.pi)
    for k in range(K):
        a = a0 + k * 2 * math.pi / K + rng.uniform(-0.25, 0.25)
        crack((math.cos(a) * 0.09, math.sin(a) * 0.09), a, rng.uniform(0.70, 0.96), 0.030 * rng.uniform(0.8, 1.2), 0.0, 0)
    return cracks, crater, forks


def _crack_polys(cracks, reach, scale, c, wk):
    """the cracks as polygons, cut where the split has reached (reach: distance from the centre)"""
    polys = []
    for pts, w, d in cracks:
        if d[0] >= reach:
            continue
        k = int(np.searchsorted(d, reach))
        P, Wd = list(pts[:k]), list(w[:k])
        if k < len(d):                                   # the front, part of the way along its segment
            t = (reach - d[k - 1]) / max(d[k] - d[k - 1], 1e-6)
            P.append(pts[k - 1] + (pts[k] - pts[k - 1]) * t)
            Wd.append(w[k - 1] + (w[k] - w[k - 1]) * t)
        P, Wd = np.array(P), np.array(Wd) * wk
        if len(P) < 2:
            continue
        left, right = [], []
        for i in range(len(P)):
            d0 = P[min(i + 1, len(P) - 1)] - P[max(i - 1, 0)]
            n = np.array([-d0[1], d0[0]]) / (np.linalg.norm(d0) + 1e-9)
            left.append(c + (P[i] + n * Wd[i]) * scale)
            right.append(c + (P[i] - n * Wd[i]) * scale)
        polys.append([tuple(p) for p in left + right[::-1]])
    return polys


def rupture_frames(seed=777, size=384, n_open=8, n_cool=8, n_erode=4):
    cracks, crater, forks = rupture_geometry(seed)
    erode_n = ndimage.gaussian_filter(np.random.default_rng(seed + 1).random((size * 2, size * 2)), 6)
    erode_n = (erode_n - erode_n.min()) / (erode_n.max() - erode_n.min())
    Z = size * 2
    c, scale = np.array([Z / 2, Z / 2]), Z / 2 * 0.98
    maxd = max(d[-1] for _, _, d in cracks)
    frames = []
    for f in range(n_open + n_cool + n_erode):
        if f < n_open:
            g, h = 1 - (1 - (f + 1) / n_open) ** 2, 1.0
        else:
            g, h = 1.0, max(0.0, 1 - (f - n_open + 1) / n_cool)
        reach = g * maxd

        def mask(wk, crater_k=None):
            im = Image.new('L', (Z, Z), 0)
            dr = ImageDraw.Draw(im)
            for poly in _crack_polys(cracks, reach, scale, c, wk):
                dr.polygon(poly, fill=255)
            if crater_k:
                dr.polygon([tuple(c + np.array(p) * scale * crater_k) for p in crater], fill=255)
            return np.asarray(im, np.float32) / 255
        edge, body, core = mask(1.65, 1.2), mask(1.0, 1.0), mask(0.38, 0.65)
        # the scorch round it all, the split ground's dark edges, the lava in them, its hot core
        out = np.zeros((Z, Z, 4), np.float32)
        out = over(out, np.array([0.10, 0.07, 0.06]), ndimage.gaussian_filter(edge, 10) * (0.25 + 0.15 * h))
        out = over(out, np.array([0.08, 0.05, 0.045]), edge * (0.6 + 0.3 * h))
        glow = ndimage.gaussian_filter(body, 8) * 0.7 * h
        out = over(out, lerp([0.45, 0.06, 0.02], [0.92, 0.22, 0.05], h), ndimage.gaussian_filter(body, 16) * 0.45 * h)  # red
        out = over(out, lerp([0.55, 0.10, 0.03], [1.0, 0.42, 0.12], h), glow * (1 - edge * 0.5))
        out = over(out, lerp([0.22, 0.06, 0.04], lerp([0.85, 0.20, 0.05], [1.0, 0.45, 0.12], h), min(1.0, h * 1.6)),
                   body * min(1.0, 0.35 + h * 1.4))
        if h > 0.05:
            hot = lerp([1.0, 0.35, 0.08], [1.0, 0.78, 0.32], h)
            out = over(out, hot, core * min(1.0, h * 1.5))
        if h > 0.25:                                      # the forks and the crater: hot nodes (the cinematic's)
            nodes = Image.new('L', (Z, Z), 0)
            dn = ImageDraw.Draw(nodes)
            for q, dd in forks + [(np.zeros(2), 0.0)]:
                if dd > reach:
                    continue
                rr = Z * (0.012 if dd > 0 else 0.03)
                qq = c + q * scale
                dn.ellipse([qq[0] - rr, qq[1] - rr, qq[0] + rr, qq[1] + rr], fill=255)
            nm = np.asarray(nodes, np.float32) / 255
            out = over(out, np.array([1.0, 0.62, 0.2]), ndimage.gaussian_filter(nm, 7) * 0.8 * h)
            out = over(out, np.array([1.0, 0.92, 0.6]), nm * min(1.0, (h - 0.25) * 2))
        if f < n_open:                                    # the fresh front of the split: hottest
            out = over(out, np.array([1.0, 0.93, 0.70]), core * 0.45 * (1 - f / n_open))
        if f >= n_open + n_cool:                          # the charred cracks crumble away (eroded, not faded)
            thr = (f - n_open - n_cool + 1) / (n_erode + 1)
            out[..., 3] *= np.clip((erode_n - thr) * 12, 0, 1)
        im = Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), 'RGBA').resize((size, size), Image.LANCZOS)
        frames.append(np.asarray(im, np.float32) / 255)
    return frames


# ------------------------------------------------------------------------------------------ standing pieces
def _tube(dr, pts, widths, fill):
    for (p0, w0), (p1, w1) in zip(zip(pts, widths), zip(pts[1:], widths[1:])):
        d = np.array(p1) - np.array(p0)
        n = np.array([-d[1], d[0]]) / (np.linalg.norm(d) + 1e-6)
        dr.polygon([tuple(np.array(p0) + n * w0), tuple(np.array(p1) + n * w1), tuple(np.array(p1) - n * w1),
                    tuple(np.array(p0) - n * w0)], fill=fill)
        dr.ellipse([p1[0] - w1, p1[1] - w1, p1[0] + w1, p1[1] + w1], fill=fill)


def root_frames(seed, fw=128, fh=192, n=12):
    """a thorned root bursting up out of the earth and hooking over at its tip: dark bark, a lit upper edge,
    pale thorns down the outside of its curve; the earth broken round its foot"""
    rng = np.random.default_rng(seed)
    W, H = fw * SS, fh * SS
    base = np.array([W * 0.5, H * 0.93])
    lean = rng.uniform(-0.25, 0.25)
    curl = rng.uniform(2.2, 2.9)                          # it hooks over to its right (the app mirrors it)
    L = H * rng.uniform(0.72, 0.82)
    m = 44
    thorns = sorted(rng.choice(np.arange(4, m - 4), 8, replace=False))
    clods = [(rng.uniform(-1, 1), rng.uniform(0.5, 1.0)) for _ in range(3)]
    out = []
    for f in range(n):
        g = 1 - (1 - (f + 1) / n) ** 2.2
        path, ang = [base], -math.pi / 2 + lean * 0.5
        for i in range(1, m + 1):
            s = i / m
            ang += curl * (0.25 + 0.75 * g) * 2.0 * s ** 2.4 / m     # it hooks over as it rises
            path.append(path[-1] + np.array([math.cos(ang), math.sin(ang)]) * L / m)
        path = np.array(path)
        k = max(2, int(round(g * m)))
        P = path[:k + 1]
        wid = (W * 0.115 * (1 - np.linspace(0, 1, m + 1)) ** 0.75 + SS * 1.5)[:k + 1] * (0.6 + 0.4 * g)
        wid = wid * (1 + 0.12 * np.sin(np.arange(len(wid)) * 0.9 + seed))     # gnarled
        im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        rr = W * 0.17 * min(1.0, g * 2.2)                 # the broken earth round its foot
        dr.ellipse([base[0] - rr * 1.4, base[1] - rr * 0.45, base[0] + rr * 1.4, base[1] + rr * 0.35], fill=(58, 42, 30, 240))
        dr.ellipse([base[0] - rr * 0.8, base[1] - rr * 0.22, base[0] + rr * 0.8, base[1] + rr * 0.18], fill=(26, 20, 16, 255))
        for cx, cs in clods:
            q = base + np.array([cx * rr * 1.2, -rr * 0.15 * cs])
            r = W * 0.03 * cs * min(1.0, g * 2)
            dr.rectangle([q[0] - r, q[1] - r, q[0] + r, q[1] + r], fill=(84, 62, 44, 255))
        sign = 1 if curl > 0 else -1
        for ti, idx in enumerate(thorns):                  # thorns, both sides by turns, pointing up it
            if idx >= k - 2:
                continue
            p, q = P[idx], P[idx + 1]
            d = (q - p) / (np.linalg.norm(q - p) + 1e-6)
            nrm = np.array([-d[1], d[0]]) * (-sign if ti % 2 == 0 else sign)
            w = wid[idx]
            tip = p + nrm * (w + W * 0.06) + d * W * 0.045
            dr.polygon([tuple(p + nrm * w * 0.6 - d * w * 0.6), tuple(p + nrm * w * 0.6 + d * w * 0.5), tuple(tip)],
                       fill=(206, 196, 150, 255))
        _tube(dr, P, wid, (70, 56, 36, 255))                                            # bark
        _tube(dr, [tuple(p + np.array([-w * 0.2, -w * 0.3])) for p, w in zip(P, wid)], wid * 0.55, (124, 112, 62, 255))   # lit side
        _tube(dr, [tuple(p + np.array([-w * 0.42, -w * 0.5])) for p, w in zip(P, wid)], wid * 0.2, (176, 218, 104, 255))  # moss on it
        a = np.asarray(im.resize((fw, fh), Image.LANCZOS), np.float32) / 255
        glow = ndimage.gaussian_filter(a[..., 3], 5) * 0.42 * g      # the snare's green light round it
        res = over(np.dstack([np.zeros((fh, fw, 3)), np.zeros((fh, fw))]), np.array([0.72, 1.0, 0.45]), glow)
        res = over(res, a[..., :3], a[..., 3])
        out.append(res)
    return out


def coral_frames(seed, fw=160, fh=176, n=12):
    """a fan of staghorn coral growing up out of a little rock: rounded arms fanning from its foot, a lighter
    top to each, pale tips, a few polyps"""
    rng = np.random.default_rng(seed)
    W, H = fw * SS, fh * SS
    base = np.array([W * 0.5, H * 0.92])
    arms = []
    k = int(rng.integers(4, 6))
    for i in range(k):
        a = -math.pi / 2 + (i / (k - 1) - 0.5) * rng.uniform(1.6, 2.0) + rng.normal(0, 0.08)
        L = H * rng.uniform(0.42, 0.62) * (1 - abs(i / (k - 1) - 0.5) * 0.5)
        bend = rng.uniform(-0.25, 0.25)
        sub = rng.random() < 0.6
        arms.append((a, L, bend, sub, rng.uniform(0.35, 0.6), rng.choice((-1, 1))))
    body, top, tipc, rock = (232, 104, 98, 255), (255, 158, 140, 255), (255, 222, 206, 255), (112, 100, 112, 255)
    edge = (150, 50, 60, 255)
    out = []
    for f in range(n):
        g = 1 - (1 - (f + 1) / n) ** 2
        im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        rr = W * 0.11
        dr.ellipse([base[0] - rr * 1.3, base[1] - rr * 0.55, base[0] + rr * 1.3, base[1] + rr * 0.45], fill=rock)
        tips = []
        for a, L, bend, sub, at, sd in arms:
            m = 12
            pts, ang = [base + np.array([0, -rr * 0.2])], a
            for i in range(int(m * g) + 1):
                ang += bend / m
                pts.append(pts[-1] + np.array([math.cos(ang), math.sin(ang)]) * L / m)
            pts = np.array(pts)
            w = W * 0.045 * (1 - np.linspace(0, 0.45, len(pts)))
            _tube(dr, pts, w * 1.28, edge)                 # a darker edge round it: it reads on any ground
            _tube(dr, pts, w, body)
            _tube(dr, [tuple(p + np.array([-wi * 0.25, -wi * 0.3])) for p, wi in zip(pts, w)], w * 0.5, top)
            tips.append((pts[-1], w[-1]))
            if sub and len(pts) > m * at + 2:
                j = int(m * at)
                q, sa = [pts[j]], ang + sd * 0.7
                for i in range(int(m * 0.45 * min(1.0, (g - at) / (1 - at + 1e-6))) + 1):
                    q.append(q[-1] + np.array([math.cos(sa), math.sin(sa)]) * L * 0.5 / m)
                q = np.array(q)
                ws = W * 0.03 * (1 - np.linspace(0, 0.4, len(q)))
                if len(q) > 1:
                    _tube(dr, q, ws * 1.28, edge)
                    _tube(dr, q, ws, body)
                    _tube(dr, [tuple(p + np.array([-wi * 0.25, -wi * 0.3])) for p, wi in zip(q, ws)], ws * 0.5, top)
                    tips.append((q[-1], ws[-1]))
        for p, w in tips:
            dr.ellipse([p[0] - w * 1.3, p[1] - w * 1.3, p[0] + w * 1.3, p[1] + w * 1.3], fill=edge)
            dr.ellipse([p[0] - w * 1.05, p[1] - w * 1.05, p[0] + w * 1.05, p[1] + w * 1.05], fill=tipc)
        a = np.asarray(im.resize((fw, fh), Image.LANCZOS), np.float32) / 255
        glow = ndimage.gaussian_filter(a[..., 3], 3) * 0.16
        res = over(np.zeros((fh, fw, 4), np.float32), np.array([1.0, 0.8, 0.75]), glow)
        out.append(over(res, a[..., :3], a[..., 3]))
    return out


# ------------------------------------------------------------------------------------------- light and water
def _radial(size):
    yy, xx = (np.mgrid[0:size, 0:size] + 0.5) / size * 2 - 1
    return np.hypot(xx, yy), np.arctan2(yy, xx)


def add_frame(light):
    """an additive frame: colour by its own brightness, alpha its brightness (drawn with plus)"""
    L = 1 - np.exp(-light * 1.3)
    a = np.clip(L.max(-1), 0, 1)
    return np.dstack([L / np.maximum(a[..., None], 1e-4), a])


def caustic_frames(size=256, n=8):
    """a pool of water-light: pink at its heart, sea-green at its rim, soft rings of light rippling out (a loop)"""
    yy, xx = (np.mgrid[0:size, 0:size] + 0.5) / size * 2 - 1
    r = np.hypot(xx, yy)
    pool = np.clip(1 - r, 0, 1) ** 0.7
    rgb = lerp(np.array([0.50, 0.88, 0.84]), np.array([1.0, 0.72, 0.68]), np.clip(1 - r * 1.15, 0, 1)[..., None])
    out = []
    for f in range(n):
        rings = np.zeros_like(r)
        for k in range(3):
            rr = (f / n + k / 3) % 1.0
            rings += np.exp(-((r - rr * 0.95) / 0.035) ** 2) * math.sin(rr * math.pi)
        a = pool * 0.30 + rings * 0.45 * np.clip((1 - r) * 3, 0, 1)
        out.append(np.dstack([np.clip(rgb + rings[..., None] * 0.2, 0, 1), np.clip(a, 0, 1)]))
    return out


def _wedge(c, a, r0, r1, w0, w1):
    """a tapered ray from r0 to r1 out along angle a, w0 wide at its root, w1 at its tip"""
    d = np.array([math.cos(a), math.sin(a)])
    n = np.array([-d[1], d[0]])
    return [tuple(c + d * r0 + n * w0), tuple(c + d * r1 + n * w1), tuple(c + d * r1 - n * w1), tuple(c + d * r0 - n * w0)]


def sun_frames(size=384, n=16):
    """the sun breaking open, drawn behind the Elder (its silhouette stays clear against it): a hard-edged pale
    disc with an amber rim, eight crisp god rays (a saturated amber edge round a pale core; long and short by
    turns) turning slowly, one crisp ring early; it goes by its rays thinning and drawing in, not by fading"""
    Z = size * SS
    c = np.array([Z / 2, Z / 2])
    R = Z / 2
    amber, gold, pale = (255, 150, 40, 255), (255, 206, 92, 255), (255, 246, 214, 255)
    out = []
    for f in range(n):
        u = f / (n - 1)
        burst = 1 - (1 - min(1.0, u / 0.25)) ** 3            # out fast, slowing (drag)
        go = max(0.0, (u - 0.45) / 0.55)                      # going
        im = Image.new('RGBA', (Z, Z), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        rot = 0.22 * u
        for i in range(8):
            a = i * math.pi / 4 + rot
            L = R * (0.92 if i % 2 == 0 else 0.62) * burst
            w = R * (0.085 if i % 2 == 0 else 0.06) * (1 - go)
            r0 = R * (0.10 + 0.55 * go ** 1.5)                # drawing in from the sun as it goes
            if L <= r0 + 2 or w <= 1:
                continue
            dr.polygon(_wedge(c, a, r0, L, w, w * 0.06), fill=amber)              # wide at the sun, sharp tips
            dr.polygon(_wedge(c, a, r0, L * 0.84, w * 0.6, w * 0.04), fill=gold)
            dr.polygon(_wedge(c, a, r0, L * 0.58, w * 0.26, w * 0.03), fill=pale)
        dk = (0.16 * min(1.0, u / 0.12) * (1 - 0.6 * go)) * R      # the disc: snaps open, then shrinks
        if dk > 2:
            dr.ellipse([c[0] - dk * 1.18, c[1] - dk * 1.18, c[0] + dk * 1.18, c[1] + dk * 1.18], fill=amber)
            dr.ellipse([c[0] - dk, c[1] - dk, c[0] + dk, c[1] + dk], fill=pale)
        rk = min(1.0, u / 0.35)                                # one ring, early, thinning as it goes out
        if rk < 1:
            rr, wd = R * (0.15 + 0.8 * (1 - (1 - rk) ** 3)), max(1, int(R * 0.022 * (1 - rk)))
            dr.ellipse([c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr], outline=gold, width=wd)
        a_ = np.asarray(im.resize((size, size), Image.LANCZOS), np.float32) / 255
        # a little soft light round the disc (the only soft part)
        r, _ = _radial(size)
        halo = np.exp(-(r / 0.28) ** 2) * 0.35 * (1 - min(1.0, u / 0.4)) ** 1.5 * min(1.0, u / 0.08)
        res = over(np.zeros((size, size, 4), np.float32), np.array([1.0, 0.85, 0.5]), halo)
        out.append(over(res, a_[..., :3], a_[..., 3]))
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
    """a six-pointed violet star breaking open behind the Elder: crisp diamond spokes (a deep violet edge round a
    pale core), one crisp ring, a few glints flung out; it goes by its spokes drawing in and thinning"""
    Z = size * SS
    c = np.array([Z / 2, Z / 2])
    R = Z / 2
    deep, vio, pale = (110, 62, 196, 255), (176, 136, 246, 255), (246, 238, 255, 255)
    rng = np.random.default_rng(9)
    glints = [(rng.uniform(0, 2 * math.pi), rng.uniform(0.6, 1.0)) for _ in range(6)]
    out = []
    for f in range(n):
        u = f / (n - 1)
        burst = 1 - (1 - min(1.0, u / 0.25)) ** 3
        go = max(0.0, (u - 0.35) / 0.65)
        im = Image.new('RGBA', (Z, Z), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)

        def diamond(a, r0, r1, w, fill):
            d = np.array([math.cos(a), math.sin(a)])
            nn = np.array([-d[1], d[0]])
            m = r0 + (r1 - r0) * 0.35
            dr.polygon([tuple(c + d * r0), tuple(c + d * m + nn * w), tuple(c + d * r1), tuple(c + d * m - nn * w)], fill=fill)
        for i in range(6):
            a = i * math.pi / 3 + math.pi / 6
            L = R * (0.95 if i % 2 == 0 else 0.7) * burst
            r0 = R * (0.05 + 0.5 * go ** 1.5)
            w = R * 0.085 * (1 - go)
            if L <= r0 + 2 or w <= 1:
                continue
            diamond(a, r0, L, w, deep)
            diamond(a, r0 + (L - r0) * 0.06, L * 0.9, w * 0.62, vio)
            diamond(a, r0 + (L - r0) * 0.1, L * 0.7, w * 0.28, pale)
        rk = min(1.0, u / 0.3)
        if rk < 1:
            rr, wd = R * (0.12 + 0.75 * (1 - (1 - rk) ** 3)), max(1, int(R * 0.03 * (1 - rk)))
            dr.ellipse([c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr], outline=vio, width=wd)
        for a, s_ in glints:
            d = R * (0.2 + 0.75 * burst * s_)
            q = c + np.array([math.cos(a), math.sin(a)]) * d
            g = R * 0.03 * (1 - u)
            if g > 1:
                dr.polygon([(q[0], q[1] - g * 2), (q[0] + g, q[1]), (q[0], q[1] + g * 2), (q[0] - g, q[1])], fill=pale)
        a_ = np.asarray(im.resize((size, size), Image.LANCZOS), np.float32) / 255
        r, _ = _radial(size)
        halo = np.exp(-(r / 0.22) ** 2) * 0.35 * (1 - min(1.0, u / 0.3)) ** 2   # only as it breaks open
        res = over(np.zeros((size, size, 4), np.float32), np.array([0.92, 0.86, 1.0]), halo)
        out.append(over(res, a_[..., :3], a_[..., 3]))
    return out


def flash_frames(size=192, n=3):
    """the instant flash an ultimate lands with: two or three frames, white (the app tints it): a hard-edged
    eight-pointed burst and its disc, then thinner and wider, then a broken ring"""
    Z = size * SS
    c = np.array([Z / 2, Z / 2])
    R = Z / 2
    out = []
    for f in range(n):
        im = Image.new('RGBA', (Z, Z), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        k = (f + 1) / n
        if f < 2:
            for i in range(8):
                a = i * math.pi / 4 + 0.2
                L = R * (0.95 if i % 2 == 0 else 0.55) * (0.6 + 0.4 * k)
                w = R * (0.09 if i % 2 == 0 else 0.06) * (1.2 - k)
                dr.polygon(_wedge(c, a, 0, L, w, 0.5), fill=(255, 255, 255, 255))
            dk = R * (0.28 if f == 0 else 0.18)
            dr.ellipse([c[0] - dk, c[1] - dk, c[0] + dk, c[1] + dk], fill=(255, 255, 255, 255))
        else:
            rr = R * 0.8
            for i in range(10):
                a0 = i * 36 + 8
                dr.arc([c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr], a0, a0 + 22, fill=(255, 255, 255, 255), width=int(R * 0.05))
        a_ = np.asarray(im.resize((size, size), Image.LANCZOS), np.float32) / 255
        out.append(a_)
    return out


def dust_frames(n=4, size=128, frames=6):
    """a billow of dust (four shapes), lit warm from underneath; over its frames it swells a little and breaks
    up, holes opening through its thin parts until it is wisps (dissipating by erosion, not by fading)"""
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
        al0 = np.clip(den * 1.2 - 0.12, 0, 1) * np.clip(1 - (np.hypot(xx, yy) / 0.5) ** 3, 0, 1)
        top = np.clip(0.5 - yy * 1.2, 0, 1)[..., None]
        sh = ndimage.gaussian_filter(den, 3)
        lit = np.clip((sh - np.roll(sh, 5, axis=0)) * 2.0, -0.3, 0.4)[..., None]
        rgb = np.array([150, 128, 112]) / 255 * (0.8 + 0.35 * top + lit) + np.array([255, 130, 60]) / 255 * 0.22 * (1 - top)
        for f in range(frames):
            t = f / (frames - 1)
            al = np.clip((al0 * (1 - 0.25 * t) - t * 0.55) * (1.0 + 2.5 * t), 0, 1)   # thin parts go first
            out.append(np.dstack([np.clip(rgb, 0, 1), al * 0.9]))
    return out


def rock_frames(src, size=64):
    out = []
    for s in range(1, 7):
        for f in range(12):
            im = Image.open(os.path.join(src, 'c%d_%02d.png' % (s, f))).convert('RGBA').resize((size, size), Image.LANCZOS)
            out.append(np.asarray(im, np.float32) / 255)
    return out


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    save_atlas('quake_cracks', rupture_frames(), 384, 384, 'ground', open=8, cool=8)
    save_atlas('snare_root', sum((root_frames(s) for s in (11, 12, 13)), []), 128, 192, 'stand', ax=0.5, ay=0.93,
               variants=3)
    save_atlas('reef_caustics', caustic_frames(), 256, 256, 'ground')
    save_atlas('reef_coral', sum((coral_frames(s) for s in (21, 22, 23)), []), 160, 176, 'stand', ax=0.5, ay=0.92,
               variants=3)
    save_atlas('sun_flare', sun_frames(), 384, 384, 'normal')
    save_atlas('dazzle', dazzle_frames(), 96, 96, 'add')
    save_atlas('crystal_burst', crystal_frames(), 256, 256, 'normal')
    save_atlas('flash', flash_frames(), 192, 192, 'normal')
    save_atlas('dust', dust_frames(), 128, 128, 'normal', ay=0.6, variants=4)
    if CHUNKS and os.path.isdir(CHUNKS):
        save_atlas('rocks', rock_frames(CHUNKS), 64, 64, 'normal', variants=6)
    path = os.path.join(OUT, 'ultfx.json')
    old = json.load(open(path)) if os.path.exists(path) else {}
    for gone in ('snare_web', 'reef_web'):
        old.pop(gone, None)
    old.update(META)
    json.dump(old, open(path, 'w'), indent=1)
    print('->', path)

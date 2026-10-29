"""The combat faces from the Evochi Expression Style Kit (face_kit/: 6 personalities x 3 stages x shout, strain,
fierce, as editable SVGs), put on the existing face: each SVG is drawn into the face's own canvas (the face Frame's
(u, v) space that characters.paint_face paints and decals.project_canvas lays on the voxels), registered by the
eyes: the kit's two eye centres land on the model's eye centres (ch.eye_u, ch.eye_v), so the eyes stay where the
model has them and everything else keeps its place around them. The mesh, voxels and materials are untouched.

The kit's ink and highlight take the palette's eye colours, its blush the palette's cheek (so every colour keeps
its facial materials, Obsidian's light eyes included); the mouth keeps the kit's reds, tongue and teeth (on dark
palettes the mouth takes the palette's mouth colours).

Expressions: 'shout', 'strain', 'fierce' (Brave), or with a personality: 'shout:timid', 'fierce:calm' ...
"""
from __future__ import annotations

import functools
import io
import os
import re

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.join(HERE, 'face_kit')
STATES = ('shout', 'strain', 'fierce')
PERSONALITIES = ('brave', 'timid', 'stubborn', 'playful', 'curious', 'calm')
STAGE_NAMES = {1: 'eggling', 2: 'juvenile', 3: 'elder'}
INK, WHITE, BLUSH = '#2D2928', '#FFFCF9', '#ECA096'
MOUTH_KEYS = {'#963C42': 'mouth_in', '#712E37': 'mouth_in', '#8E4444': 'mouth'}
SUB = 4                     # subsamples per canvas cell, each way


def svg_path(name):
    """the kit's SVG, or its correction in face_kit/overrides/ where the kit strays from the original reference
    (the manifest ranks the reference sheets above the kit)"""
    o = os.path.join(KIT, 'overrides', name + '.svg')
    return o if os.path.exists(o) else os.path.join(KIT, 'svg', name + '.svg')


def parse(expr):
    """'fierce:calm' -> ('fierce', 'calm'); None when it is not a kit expression"""
    state, _, pers = expr.partition(':')
    if state not in STATES:
        return None
    return state, (pers or 'brave')


@functools.lru_cache(None)
def _eyes(stage):
    """the kit's eye centres for a stage (its open-eyed shout): x left, x right, y"""
    svg = open(os.path.join(KIT, 'svg', 'brave_%s_shout.svg' % STAGE_NAMES[stage])).read()
    rects = [tuple(float(v) for v in m) for m in
             re.findall(r'<rect x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" height="([\d.]+)" rx="[\d.]+" fill="%s"' % INK, svg)]
    (x0, y0, w0, h0), (x1, y1, w1, h1) = sorted(rects)[:2]
    return x0 + w0 / 2, x1 + w1 / 2, (y0 + h0 / 2 + y1 + h1 / 2) / 2


def mapping(ch):
    """kit pixels (256 x 160 space) per face unit, and the kit point that sits at u = 0, v = ch.eye_v"""
    xl, xr, y = _eyes(ch.stage)
    k = 2 * ch.eye_u / (xr - xl)
    return k, (xl + xr) / 2, y


def extent(ch):
    """the canvas the whole kit face needs, in face units"""
    k, cx, cy = mapping(ch)
    return (-cx * k, (256 - cx) * k, ch.eye_v - (160 - cy) * k, ch.eye_v + cy * k)


def _colours(pal):
    dark = pal['mouth_in'].upper() in ('#2A2228',)
    sub = {INK: pal['eye'], WHITE: pal['eye_hi'], BLUSH: pal['cheek']}
    if dark:
        sub.update({c: pal[k] for c, k in MOUTH_KEYS.items()})
    return sub


@functools.lru_cache(64)
def _raster(name, subs, scale):
    import cairosvg
    from PIL import Image
    svg = open(svg_path(name)).read()
    for a, b in subs:
        svg = re.sub(re.escape(a), b, svg, flags=re.I)
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=int(round(256 * scale)), output_height=int(round(160 * scale)))
    return np.asarray(Image.open(io.BytesIO(png)).convert('RGBA')).astype(np.float32) / 255.0


def _hex(c):
    c = c.lstrip('#')
    return np.array([int(c[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0


def paint_kit(ch, cv, pal, state, personality='brave'):
    name = '%s_%s_%s' % (personality, STAGE_NAMES[ch.stage], state)
    k, cx, cy = mapping(ch)
    scale = SUB / (cv.cell / k)                      # raster pixels per kit unit: SUB per canvas cell
    sub = _colours(pal)
    R = _raster(name, tuple(sorted(sub.items())), round(scale, 3))
    H, W = R.shape[:2]
    svg = open(svg_path(name)).read()
    cols = sorted({sub.get(c.upper(), c.upper()) for c in re.findall(r'#[0-9A-Fa-f]{6}', svg)})
    P = np.stack([_hex(c) for c in cols])
    # each subsample snapped to the nearest of the kit's colours (after the palette swap); each cell takes the
    # colour most of its subsamples have, so edges never pick up an unrelated in-between colour
    votes = np.zeros(cv.U.shape + (len(cols),), np.float32)
    alpha = np.zeros(cv.U.shape + (len(cols),), np.float32)
    for i in range(SUB):
        for j in range(SUB):
            du = ((i + 0.5) / SUB - 0.5) * cv.cell
            dv = ((j + 0.5) / SUB - 0.5) * cv.cell
            X = ((cx + (cv.U + du) / k) * scale).astype(int)
            Y = ((cy - (cv.V + dv - ch.eye_v) / k) * scale).astype(int)
            ok = (X >= 0) & (X < W) & (Y >= 0) & (Y < H)
            px = np.zeros(cv.U.shape + (4,), np.float32)
            px[ok] = R[Y[ok], X[ok]]
            on = px[..., 3] > 0.35
            near = np.argmin(((px[..., None, :3] - P) ** 2).sum(-1), -1)
            oh = np.eye(len(cols), dtype=np.float32)[near] * on[..., None]
            votes += oh
            alpha += oh * px[..., 3:4]
    n = SUB * SUB
    best = votes.argmax(-1)
    filled = votes.max(-1) >= n * 0.5 - 1e-6
    cheek = _hex(pal['cheek'])
    for c in range(len(cols)):
        mask = filled & (best == c)
        if not mask.any():
            continue
        a = float(np.round(np.median(alpha[..., c][mask] / votes[..., c][mask]), 2))
        is_cheek = np.allclose(P[c], cheek, atol=1e-3)
        cv.paint(mask, cols[c], alpha=min(1.0, a), lit=0.5 if is_cheek else 0.0)

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
# the leap clear of the Sentinel's beam (cine_jump.py): its own faces, Brave Juvenile so far
JUMP_STATES = ('surprise', 'effort', 'focus', 'set', 'whoop', 'gaze', 'ready')
PERSONALITIES = ('brave', 'timid', 'stubborn', 'playful', 'curious', 'calm')
STAGE_NAMES = {1: 'eggling', 2: 'juvenile', 3: 'elder'}
STAGES = {v: k for k, v in STAGE_NAMES.items()}
INK, WHITE, BLUSH = '#2D2928', '#FFFCF9', '#ECA096'
MOUTH_KEYS = {'#963C42': 'mouth_in', '#712E37': 'mouth_in', '#8E4444': 'mouth'}
SUB = 4                     # subsamples per canvas cell, each way


def svg_path(name):
    """the kit's SVG, or its correction in face_kit/overrides/ where the kit strays from the original reference
    (the manifest ranks the reference sheets above the kit)"""
    o = os.path.join(KIT, 'overrides', name + '.svg')
    return o if os.path.exists(o) else os.path.join(KIT, 'svg', name + '.svg')


MOUTH_ALL = ('#712E37', '#963C42', '#8E4444', '#E98D87', '#FFFBF2')   # the kit's mouth colours (and teeth)


def parse(expr):
    """'fierce:calm' -> ('fierce', 'calm'); 'shout:brave:nomouth' -> ('shout', 'brave', False): the face without
    its painted mouth, for when the jaw opens in the geometry; None when it is not a kit expression"""
    state, pers, *flags = expr.split(':') + ['']
    if state not in STATES and state not in JUMP_STATES:
        return None
    if 'nomouth' in flags:
        return state, (pers or 'brave'), False
    return state, (pers or 'brave')


# where each stage's eyes sit in the kit's 256 x 160 face space (x of the left and right eye centres, y): the
# registration onto the model's own eye centres. Fixed, so hand-editing an SVG moves only what you move.
EYES = {1: (83.95, 172.95, 82.05), 2: (84.0, 173.0, 82.0), 3: (84.05, 173.05, 81.95)}


def _eyes(stage):
    return EYES[stage]


# how much bigger than the kit's own the eyes are drawn on each stage (closer to the size the models' own eyes have:
# the kit's run small on the Juvenile and Elder). Each eye grows about its own centre; the brows rise with it. The
# SVGs stay as they are, so a hand edit is scaled the same way.
EYE_SCALE = {1: 1.08, 2: 1.25, 3: 1.3}
_TAG = re.compile(r'<(rect|ellipse|circle|polyline|polygon|path|line)\b[^>]*?/>')


def _box(el):
    """a rough bounding box of one SVG shape, from its own numbers"""
    def num(a):
        m = re.search(r'\b%s="([-\d.]+)"' % a, el)
        return float(m.group(1)) if m else None
    tag = el[1:].split(None, 1)[0]
    if tag == 'rect':
        x, y, w, h = num('x'), num('y'), num('width'), num('height')
        return x, y, x + w, y + h
    if tag in ('ellipse', 'circle'):
        cx, cy = num('cx'), num('cy')
        rx = num('rx') if tag == 'ellipse' else num('r')
        ry = num('ry') if tag == 'ellipse' else rx
        return cx - rx, cy - ry, cx + rx, cy + ry
    m = re.search(r'\b(?:points|d)="([^"]*)"', el)
    v = [float(n) for n in re.findall(r'-?\d+(?:\.\d+)?', m.group(1))] if m else []
    if len(v) < 2:
        return None
    xs, ys = v[0::2], v[1::2]
    return min(xs), min(ys), max(xs), max(ys)


def scale_eyes(svg, stage):
    """the face with its eyes drawn EYE_SCALE[stage] times the kit's size, each about its own centre; brows rise with
    the eyes' tops. Cheeks, sweat and mouth are left where they are"""
    s = EYE_SCALE.get(stage, 1.0)
    if abs(s - 1) < 1e-3:
        return svg
    xl, xr, ey = EYES[stage]
    els = [(m.start(), m.end(), m.group(0), _box(m.group(0))) for m in _TAG.finditer(svg)]
    side = {}
    for a, b, el, bx in els:
        if bx is None or BLUSH.lower() in el.lower():
            continue
        cx, cy = (bx[0] + bx[2]) / 2, (bx[1] + bx[3]) / 2
        for k, ex in ((0, xl), (1, xr)):
            if abs(cx - ex) < 22 and ey - 24 < cy < ey + 24:
                side.setdefault(k, []).append((a, bx))
    pivot, lift = {}, {}
    for k, items in side.items():
        x0 = min(bx[0] for _, bx in items); y0 = min(bx[1] for _, bx in items)
        x1 = max(bx[2] for _, bx in items); y1 = max(bx[3] for _, bx in items)
        pivot[k] = ((x0 + x1) / 2, (y0 + y1) / 2)
        lift[k] = (y0 - pivot[k][1]) * (s - 1)               # how far the eye's top rises
    eye_at = {a: k for k, items in side.items() for a, _ in items}
    out, last = [], 0
    for a, b, el, bx in els:
        out.append(svg[last:a])
        last = b
        if a in eye_at:
            px, py = pivot[eye_at[a]]
            out.append('<g transform="translate(%.2f %.2f) scale(%.3f) translate(%.2f %.2f)">%s</g>' % (px, py, s, -px, -py, el))
            continue
        if bx is not None and INK.lower() in el.lower() and (bx[1] + bx[3]) / 2 < ey - 24:
            k = 0 if abs((bx[0] + bx[2]) / 2 - xl) < abs((bx[0] + bx[2]) / 2 - xr) else 1
            if k in lift:
                out.append('<g transform="translate(0 %.2f)">%s</g>' % (lift[k], el))
                continue
        out.append(el)
    out.append(svg[last:])
    return ''.join(out)


def mapping(ch):
    """kit pixels (256 x 160 space) per face unit, and the kit point that sits at u = 0, v = ch.eye_v"""
    xl, xr, y = _eyes(ch.stage)
    k = 2 * ch.eye_u / (xr - xl)
    return k, (xl + xr) / 2, y


def squash(ch):
    """how the face plane is scaled on a squashed body (characters.squash_body): across, up"""
    return getattr(ch, 'face_squash', (1.0, 1.0))


def extent(ch):
    """the canvas the whole kit face needs, in face units"""
    k, cx, cy = mapping(ch)
    sx, sy = squash(ch)
    ev = ch.eye_v * sy
    return (-cx * k * sx, (256 - cx) * k * sx, ev - (160 - cy) * k * sy, ev + cy * k * sy)


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
    svg = scale_eyes(open(svg_path(name)).read(), STAGES[name.split('_')[1]])
    for a, b in subs:
        svg = re.sub(re.escape(a), b, svg, flags=re.I)
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=int(round(256 * scale)), output_height=int(round(160 * scale)))
    return np.asarray(Image.open(io.BytesIO(png)).convert('RGBA')).astype(np.float32) / 255.0


def _hex(c):
    c = c.lstrip('#')
    return np.array([int(c[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0


def paint_kit(ch, cv, pal, state, personality='brave', mouth=True):
    name = '%s_%s_%s' % (personality, STAGE_NAMES[ch.stage], state)
    k, cx, cy = mapping(ch)
    sx, sy = squash(ch)                              # a posed body squashes its face with it
    scale = SUB * k * max(sx, sy) / cv.cell          # raster pixels per kit unit: SUB per canvas cell
    sub = _colours(pal)
    R = _raster(name, tuple(sorted(sub.items())), round(scale, 3))
    H, W = R.shape[:2]
    svg = open(svg_path(name)).read()
    orig = sorted({c.upper() for c in re.findall(r'#[0-9A-Fa-f]{6}', svg)})
    cols = [sub.get(c, c) for c in orig]
    P = np.stack([_hex(c) for c in cols])
    # each subsample snapped to the nearest of the kit's colours (after the palette swap); each cell takes the
    # colour most of its subsamples have, so edges never pick up an unrelated in-between colour
    votes = np.zeros(cv.U.shape + (len(cols),), np.float32)
    alpha = np.zeros(cv.U.shape + (len(cols),), np.float32)
    for i in range(SUB):
        for j in range(SUB):
            du = ((i + 0.5) / SUB - 0.5) * cv.cell
            dv = ((j + 0.5) / SUB - 0.5) * cv.cell
            X = ((cx + (cv.U + du) / (k * sx)) * scale).astype(int)
            Y = ((cy - (cv.V + dv - ch.eye_v * sy) / (k * sy)) * scale).astype(int)
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
        if not mask.any() or (not mouth and orig[c] in MOUTH_ALL):
            continue
        a = float(np.round(np.median(alpha[..., c][mask] / votes[..., c][mask]), 2))
        is_cheek = np.allclose(P[c], cheek, atol=1e-3)
        cv.paint(mask, cols[c], alpha=min(1.0, a), lit=0.5 if is_cheek else 0.0)

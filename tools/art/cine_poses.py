"""Cut a posed character out of its re-rendered shots for the app (flutter/lib/features/onboarding/posed_plate.dart).

A character's shot is rendered again in a few poses (cine_scenes.py PIP_POSES, MIRA_POSES: the same scene, only the
character's face and the turn of its head or arm changing). This finds the box where the poses differ, cuts that
box (feathered at its edges, so it melts into the plate) out of every pose into one sheet, writes the first pose
as the plate itself (so the box and the plate always match), and describes the sheet, the box and the clips in
assets/art/cine/cine_poses.json.

    python3 cine_poses.py GRADED_DIR ../../flutter/assets/art/cine
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

# each posed plate: its frames (graded renders, the first is the plate as it rests), the cap its plate is packed at
# (cine_assets.PLATE_MAX), the clips (frame, ms) and how it idles
SETS = {
    'pip': {
        'frames': {'p0': 'pip_p0', 'p1': 'pip_p1', 'p2': 'pip_p2', 'p3': 'pip_p3', 'p4': 'pip_p4', 'p5': 'pip_p5', 'p6': 'pip_p6', 'p7': 'pip_p7'},
        'cap': 1100,
        'focus': ('face', (-650, -400, 400, 250)),  # where to look for what moved: round an anchor (full-size px)
        'clips': {
            'blink': [['p1', 130]],
            'tilt': [['p2', 70], ['p3', 70], ['p4', 1500], ['p3', 70], ['p2', 70]],
            'present': [['p5', 80], ['p6', 80], ['p7', 1700], ['p6', 80], ['p5', 80]],
        },
        'idle': {'blink_every': [2.6, 5.0], 'gesture_every': [6.5, 9.5], 'gestures': ['tilt', 'present'], 'opening': 'present', 'opening_at': 0.7},
    },
    'nest_empty': {
        'frames': {'m0': 'nest_m0', 'm1': 'nest_m1', 'm2': 'nest_m2', 'm3': 'nest_m3', 'm4': 'nest_m4', 'm5': 'nest_m5'},
        'cap': 1200,
        # (the Glasshouse's glass and lamps render a little differently every time: only round Mira counts)
        'focus': ('mira_face', (-500, -500, 500, 700)),
        'clips': {
            'blink': [['m1', 130]],
            'look': [['m2', 80], ['m3', 80], ['m4', 1600], ['m3', 80], ['m2', 80]],
            'back': [['m5', 1300]],
        },
        'idle': {'blink_every': [2.8, 5.2], 'gesture_every': [7.0, 11.0], 'gestures': ['back', 'look'], 'opening': 'look', 'opening_at': 1.0},
    },
}

FEATHER = 14  # packed px: the box fades into the plate over this much of its edge


def cut(graded, out, name, spec, meta_in, meta_out):
    frames = {k: Image.open(os.path.join(graded, v + '.png')).convert('RGB') for k, v in spec['frames'].items()}
    keys = list(frames)
    base = frames[keys[0]]
    k = min(1.0, spec['cap'] / max(base.size))
    size = (round(base.width * k), round(base.height * k))
    packed = {f: im.resize(size, Image.LANCZOS) for f, im in frames.items()}
    # where any pose differs from the rest pose (the character and whatever its light and shadow touch), round the
    # character only, ignoring specks
    b = np.asarray(base, np.int16)
    diff = np.zeros(b.shape[:2], bool)
    for f in keys[1:]:
        diff |= np.abs(np.asarray(frames[f], np.int16) - b).sum(-1) > 60
    anchor, (wx0, wy0, wx1, wy1) = spec['focus']
    ax, ay = meta_in[spec['frames'][keys[0]]]['anchors'][anchor]
    win = np.zeros_like(diff)
    win[int(max(0, ay + wy0)):int(ay + wy1), int(max(0, ax + wx0)):int(ax + wx1)] = True
    diff = ndimage.binary_opening(diff & win, iterations=2)
    lab, n = ndimage.label(diff)
    if n > 3:
        sizes = ndimage.sum(diff, lab, range(1, n + 1))
        diff = np.isin(lab, 1 + np.argsort(sizes)[-3:])
    diff = ndimage.binary_dilation(diff, iterations=16)
    ys, xs = np.nonzero(diff)
    pad = FEATHER + 6
    x0, x1 = max(0, int(xs.min() * k) - pad), min(size[0], int(xs.max() * k) + 1 + pad)
    y0, y1 = max(0, int(ys.min() * k) - pad), min(size[1], int(ys.max() * k) + 1 + pad)
    w, h = x1 - x0, y1 - y0
    # the feather: full inside, fading to nothing at the box's edge (not where it meets the picture's own edge)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    dl = xx if x0 > 0 else np.full_like(xx, 1e9)
    dr = (w - 1 - xx) if x1 < size[0] else np.full_like(xx, 1e9)
    dt = yy if y0 > 0 else np.full_like(yy, 1e9)
    db = (h - 1 - yy) if y1 < size[1] else np.full_like(yy, 1e9)
    a = np.clip(np.minimum(np.minimum(dl, dr), np.minimum(dt, db)) / FEATHER, 0, 1)
    a = (a * a * (3 - 2 * a) * 255).astype(np.uint8)
    cols = 4
    rows = (len(keys) + cols - 1) // cols
    sheet = Image.new('RGBA', (cols * w, rows * h), (0, 0, 0, 0))
    rects = {}
    for i, f in enumerate(keys):
        cell = packed[f].crop((x0, y0, x1, y1)).convert('RGBA')
        cell.putalpha(Image.fromarray(a))
        cx, cy = (i % cols) * w, (i // cols) * h
        sheet.paste(cell, (cx, cy))
        rects[f] = [int(cx), int(cy), int(w), int(h)]
    sheet_name = name + '_poses.webp'
    sheet.save(os.path.join(out, sheet_name), 'WEBP', quality=86, method=6, exact=False)
    # the rest pose is the plate
    packed[keys[0]].save(os.path.join(out, name + '.webp'), 'WEBP', quality=82, method=6)
    m = meta_in.get(spec['frames'][keys[0]])
    if m:
        kk = size[0] / m['w']
        meta_out[name] = {'w': size[0], 'h': size[1],
                          'anchors': {n: [round(v[0] * kk, 1), round(v[1] * kk, 1)] for n, v in m.get('anchors', {}).items()},
                          'lines': {}, 'scale': 1.0}
    print(f'{name}: box {x0},{y0} {w}x{h} of {size[0]}x{size[1]}, {len(keys)} poses, sheet {sheet.size}', flush=True)
    return {'atlas': sheet_name, 'box': [int(x0), int(y0), int(w), int(h)], 'frames': {f: rects[f] for f in keys[1:]},
            'clips': spec['clips'], 'idle': spec['idle']}


def main(graded, out, only=None):
    meta_in = json.load(open(os.path.join(graded, 'cine.json')))
    meta_path = os.path.join(out, 'cine.json')
    meta_out = json.load(open(meta_path))
    poses_path = os.path.join(out, 'cine_poses.json')
    poses = json.load(open(poses_path)) if os.path.exists(poses_path) else {}
    for name, spec in SETS.items():
        if only and name not in only:
            continue
        poses[name] = cut(graded, out, name, spec, meta_in, meta_out)
    json.dump(meta_out, open(meta_path, 'w'), indent=1)
    json.dump(poses, open(poses_path, 'w'), indent=1)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], set(sys.argv[3:]) or None)

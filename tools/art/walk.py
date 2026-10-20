"""The Lumen Wilds: walk cycles for the explorable map, seen from the map's camera.

    python3 walk.py OUT_DIR [--preview] [--palettes=amber,forest] [--only=s01|sher]

Your Evochi walks in 8 directions. Each direction is a row of 9 frames: an idle stance, then an 8-frame
trot (diagonal pairs of feet: front-left with back-right, then the other pair), the body bobbing once
per step. The cycle is built in voxels (the feet move on the voxel grid, so the steps read chunky like
the rest of the art) and rendered with the flat renderer: same ink line, palette and face as the rest
of the Evochi art.

The map camera is fixed (orthographic, MAP_PITCH above the horizon, looking north). A direction is the
camera turned around the Evochi, with the light turned with it, so the light falls from the same side
of the screen whichever way it walks.

Sher (wilds_npcs.py) walks the same way on two legs.

Writes:
    walk_s01_<palette>.webp      the Eggling's sheets: rows = DIRS, columns = idle + 8 frames
    walk_sher_sher.webp          Sher's sheet
    wilds_walk.json              per walker: frame size, ground anchor, the waddle; plus directions, fps and
                                 the world-to-pixel scale
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image

from characters import build_eggling
from charrender import render_char
from voxel import Camera, Light, Fit, model_extent_points
from palettes import palette, VARIANT_ORDER

MAP_PITCH = 35.0
SCALE = 6.0                     # pixels per world unit in the sheets
DIRS = ['S', 'SE', 'E', 'NE', 'N', 'NW', 'W', 'SW']   # the way it faces on screen (S = toward you)
FACING = {d: i * 45.0 for i, d in enumerate(DIRS)}    # degrees from +z (toward you) toward +x (right)
FRAMES = 8
FPS = 14
STRIDE = 2.5                    # each foot swings STRIDE units ahead of and behind its rest spot
LIFT = 2.5
BOB = 1.0
WADDLE = 4.0                    # degrees of side-to-side roll (applied in the app, around the ground point)
PAD = 8


def q(v, res=2):
    """onto the voxel grid"""
    return round(v * res) / res


def smooth(u):
    return u * u * (3 - 2 * u)


def foot(s):
    """(dy, dz) of a foot at phase s: swing forward with a lift for the first half, then the stance (on
    the ground, sliding back as the body moves over it)."""
    if s < 0.5:
        u = s / 0.5
        return LIFT * math.sin(math.pi * u), -STRIDE + 2 * STRIDE * smooth(u)
    u = (s - 0.5) / 0.5
    return 0.0, STRIDE - 2 * STRIDE * u


def pose(i):
    """frame i (None = idle): the feet {(side, front): (dy, dz)} relative to the body, and the bob."""
    if i is None:
        return {}, 0.0
    t = i / FRAMES
    bob = q(BOB * math.sin(2 * math.pi * t) ** 2)
    feet = {}
    for (side, front), ph in (((-1, True), 0.0), ((1, False), 0.0), ((1, True), 0.5), ((-1, False), 0.5)):
        dy, dz = foot((t + ph) % 1.0)
        feet[(side, front)] = (q(dy) - bob, q(dz))
    return feet, bob


def light_for(yaw):
    """the default light, turned with the camera"""
    L = Light()
    lx, ly, lz = L.key
    y = math.radians(yaw)
    right = np.array([math.cos(y), 0.0, -math.sin(y)])
    dh = np.array([math.sin(y), 0.0, math.cos(y)])
    k = lx * right + lz * dh + np.array([0.0, ly, 0.0])
    L.key = tuple(float(v) for v in k)
    return L


def cam_for(d):
    # the Evochi turned by FACING[d] under a fixed camera = the camera turned the other way around it
    return Camera(yaw=-FACING[d], pitch=MAP_PITCH)


def frame_box(models, extra=None):
    """one frame size for every direction and frame, the ground (0,0,0) at the same pixel; `extra`:
    more points to keep in frame (whiskers)"""
    xs, ys = [], []
    for d in DIRS:
        cam = cam_for(d)
        for M, bob in models:
            P = model_extent_points(M)
            if extra is not None:
                P = np.concatenate([P, extra])
            sx, sy, _ = cam.project(P - np.array([0.0, -bob, 0.0]))
            xs += [sx.min(), sx.max()]
            ys += [sy.min(), sy.max()]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    half = max(-x0, x1)
    w = int(math.ceil(2 * half * SCALE + 2 * PAD))
    h = int(math.ceil((y1 - y0) * SCALE + 2 * PAD))
    w += w % 2
    h += h % 2
    gx, gy = w / 2, PAD - y0 * SCALE        # where the ground point lands
    return w, h, gx, gy


def sher_pose(i):
    """Sher on two legs: a boot swings forward with a lift while the other carries her, paws swinging
    against the legs; she bobs up as a leg passes under her."""
    if i is None:
        return {'legs': {}, 'arms': {}}, 0.0
    t = i / FRAMES
    bob = q(0.6 * math.sin(2 * math.pi * t) ** 2)
    legs, arms = {}, {}
    for side, ph in ((-1, 0.0), (1, 0.5)):
        s = (t + ph) % 1.0
        if s < 0.5:
            u = s / 0.5
            dy, dz = 1.6 * math.sin(math.pi * u), -2.0 + 4.0 * smooth(u)
        else:
            u = (s - 0.5) / 0.5
            dy, dz = 0.0, 2.0 - 4.0 * u
        legs[side] = (q(dy) - bob, q(dz))
        arms[-side] = dz * 0.9
    return {'legs': legs, 'arms': arms}, bob


def render_walker(out, key, base, chars, poses, variants, preview=False, roll=WADDLE, squash=0.03):
    """One sheet per variant (a palette name, or (name, palette dict) for a villager), and its meta."""
    wk = getattr(base, 'whiskers', None)
    extra = np.concatenate([x.points() for x in wk]) if wk else None
    w, h, gx, gy = frame_box([(c.model, b) for c, (_, b) in zip(chars, poses)], extra)
    print(key, 'frame', w, h, 'ground', gx, gy, flush=True)
    sheets = {}
    for var in variants:
        name, pal = (var, None) if isinstance(var, str) else var
        sheet = Image.new('RGBA', (w * len(poses), h * len(DIRS)), (0, 0, 0, 0))
        for r, d in enumerate(DIRS):
            cam = cam_for(d)
            light = light_for(cam.yaw)
            for c, (ch, (_, bob)) in enumerate(zip(chars, poses)):
                # the ground of this frame (the body's bob lifts it off the feet' reference) at (gx, gy)
                gpx, gpy, _ = cam.project(np.array([[0.0, -bob, 0.0]]))
                fit = Fit(SCALE, gx - gpx[0] * SCALE, gy - gpy[0] * SCALE, w, h)
                o = render_char(base, name, 'default', cam, w, h, fit=fit, light=light, extra_model=ch.model,
                                pal=pal, pal_key=name)
                sheet.paste(Image.fromarray(o.rgba), (c * w, r * h))
        fn = f'walk_{key}_{name}.webp'
        sheet.save(os.path.join(out, fn), quality=88, method=6)
        if preview:
            sheet.save(os.path.join(out, fn.replace('.webp', '.png')))
        sheets[name] = fn
        print(key, name, flush=True)
    return {
        'frameW': w, 'frameH': h, 'ground': [round(gx, 1), round(gy, 1)], 'sheets': sheets,
        # per frame (idle first): the waddle's roll in degrees, about the walker's own forward axis (the
        # app turns the sprite by roll x cos(facing), so it reads left-right from the front and not at all
        # side-on), and a squash (vertical scale) on each footfall
        'roll': [0.0] + [round(roll * math.sin(2 * math.pi * i / FRAMES), 2) for i in range(FRAMES)],
        'squash': [1.0] + [round(1.0 - squash * math.cos(2 * math.pi * i / FRAMES) ** 8, 3) for i in range(FRAMES)],
    }


def main(out, preview=False, palettes=None, only=None):
    os.makedirs(out, exist_ok=True)
    mpath = os.path.join(out, 'wilds_walk.json')
    meta = json.load(open(mpath)) if os.path.exists(mpath) else {}
    meta.update({'pitch': MAP_PITCH, 'scale': SCALE, 'fps': FPS, 'dirs': DIRS, 'frames': FRAMES})
    walkers = meta.setdefault('walkers', {})
    if only in (None, 's01'):
        base = build_eggling(2, lo_y=-3)
        poses = [pose(None)] + [pose(i) for i in range(FRAMES)]
        chars = [build_eggling(2, feet=f, lo_y=-3) for f, _ in poses]
        walkers['s01'] = render_walker(out, 's01', base, chars, poses, palettes or VARIANT_ORDER, preview)
        json.dump(meta, open(mpath, 'w'), indent=1)
    if only in (None, 'sher'):
        from wilds_npcs import build_sher
        from village_npc_render import npc_palette
        from village_npcs import INK
        base = build_sher(2, lo_y=-3)
        poses = [sher_pose(None)] + [sher_pose(i) for i in range(FRAMES)]
        chars = [build_sher(2, legs=p['legs'], arms=p['arms'], lo_y=-3) for p, _ in poses]
        walkers['sher'] = render_walker(out, 'sher', base, chars, poses, [('sher', npc_palette(base, INK))], preview,
                                        roll=2.5, squash=0.02)
        json.dump(meta, open(mpath, 'w'), indent=1)


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    pals, only = None, None
    for a in sys.argv[1:]:
        if a.startswith('--palettes='):
            pals = a.split('=', 1)[1].split(',')
        if a.startswith('--only='):
            only = a.split('=', 1)[1]
    main(args[0], preview='--preview' in sys.argv, palettes=pals, only=only)

"""The Lumen Wilds: walk and run cycles for the explorable map, seen from the map's camera.

    python3 walk.py OUT_DIR [--preview] [--only=s01,s02,s03,sher] [--palettes=amber,forest] [--gaits=walk,run]
    python3 walk.py OUT_DIR --wear [--only=s01,...]          (the wearables, see below)

Every walker has two gaits. Each gait is a sheet: rows are 8 directions (S, SE, E, NE, N, NW, W, SW),
columns an idle stance then 8 frames. The Evochi trot when they walk (diagonal pairs of feet: front-left
with back-right, then the other pair, the body bobbing once per step) and bound when they run (longer,
higher steps, a moment with every foot off the ground). Sher walks on two legs, paws swinging against
his legs; running, he leans into it and pumps his paws. The cycles are built in voxels (the feet move on
the voxel grid, so the steps read chunky like the rest of the art) and rendered with the flat renderer:
same ink line, palettes and faces as the rest of the art.

The map camera is fixed (orthographic, MAP_PITCH above the horizon, looking north). A direction is the
camera turned around the walker, with the light turned with it, so the light falls from the same side
of the screen whichever way it goes. All three stages share one on-screen size class: each is rendered
at its own pixel scale (STAGE_SCALE), so an Elder is a little bigger than an Eggling, not three times.

Writes:
    walk_<key>_<variant>.webp / run_<key>_<variant>.webp     the sheets
    wear_<key>_<item>.webp                                   a wearable over the idle body, one per direction
    wilds_walk.json                                          per walker: frame size, ground anchor,
                                                             footprint, per gait the waddle, squash, body
                                                             lift and stride; directions, fps, scales
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image

from characters import build
from charrender import render_char
from voxel import Camera, Light, Fit, model_extent_points
from palettes import VARIANT_ORDER

MAP_PITCH = 35.0
SCALE = 6.0                     # pixels per world unit on the map (the ground, props, Sher)
DIRS = ['S', 'SE', 'E', 'NE', 'N', 'NW', 'W', 'SW']   # the way it faces on screen (S = toward you)
FACING = {d: i * 45.0 for i, d in enumerate(DIRS)}    # degrees from +z (toward you) toward +x (right)
FRAMES = 8
FPS = 14
PAD = 8
STAGE_SCALE = {1: 6.0, 2: 4.6, 3: 3.5}                # px per unit for each Evochi stage's sheets
RADIUS = {1: 9.0, 2: 10.0, 3: 12.0, 'sher': 7.0}      # footprints on the map (world units)

# per gait: stride (each foot swings this far ahead of and behind its rest spot), lift, bob, flight (how
# much of the bob lifts the planted feet too: a moment airborne), waddle (roll, degrees), squash
QUAD = {
    'walk': dict(stride=2.5, lift=2.5, bob=1.0, flight=0.0, waddle=4.0, squash=0.03),
    'run': dict(stride=3.5, lift=3.5, bob=2.0, flight=1.0, waddle=6.0, squash=0.06),
}
QUAD_STAGE = {1: 1.0, 2: 1.15, 3: 1.4}               # bigger stages take longer steps (Flint's sheets)

# The Evochi's own gaits, a stage at a time: real strides (so the feet take the ground in a few steps
# rather than a shuffle of many), the bob and the waddle easing off as they grow heavier, and from the
# Sprout on a head that nods a beat behind the body and a tail that swings with the walk. Twelve frames
# a cycle, for the longer steps.
EVO_FRAMES = 12
EVO_GAITS = {
    1: {'walk': dict(stride=3.5, lift=2.4, bob=0.8, flight=0.0, waddle=5.0, squash=0.03, nod=0.0, tail=0.0),
        'run': dict(stride=5.0, lift=4.0, bob=1.6, flight=1.0, waddle=6.0, squash=0.06, nod=0.0, tail=0.0)},
    2: {'walk': dict(stride=6.0, lift=3.0, bob=0.6, flight=0.0, waddle=3.0, squash=0.02, nod=0.9, tail=2.2),
        'run': dict(stride=8.5, lift=5.0, bob=1.4, flight=1.0, waddle=3.5, squash=0.05, nod=1.4, tail=3.2)},
    3: {'walk': dict(stride=7.0, lift=4.0, bob=0.5, flight=0.0, waddle=1.8, squash=0.015, nod=1.0, tail=3.0),
        'run': dict(stride=10.5, lift=6.5, bob=1.4, flight=1.0, waddle=2.6, squash=0.04, nod=1.8, tail=4.5)},
}
BIPED = {
    'walk': dict(stride=2.0, lift=1.6, bob=0.6, flight=0.0, arms=0.9, lean=0.0, waddle=2.5, squash=0.02),
    'run': dict(stride=3.0, lift=2.8, bob=1.2, flight=0.6, arms=1.6, lean=1.5, waddle=3.0, squash=0.04),
}


def q(v, res=2):
    """onto the voxel grid"""
    return round(v * res) / res


def smooth(u):
    return u * u * (3 - 2 * u)


def swing(s, stride, lift):
    """(dy, dz) of a foot at phase s: swing forward with a lift for the first half, then the stance (on
    the ground, sliding back as the body moves over it)."""
    if s < 0.5:
        u = s / 0.5
        return lift * math.sin(math.pi * u), -stride + 2 * stride * smooth(u)
    u = (s - 0.5) / 0.5
    return 0.0, stride - 2 * stride * u


def quad_pose(gait, stage, frames=FRAMES, params=None):
    """A four-footed walk: [params] a gait's own numbers (EVO_GAITS), else the shared QUAD scaled by
    stage (Flint's sheets)."""
    if params is None:
        g, k = QUAD[gait], QUAD_STAGE[stage]
    else:
        g, k = params, 1.0

    def pose(i):
        """frame i (None = idle): the feet {(side, front): (dy, dz)} relative to the body, the head's
        offset and the tail's sideways swing (both from rest), and the bob."""
        if i is None:
            return {'feet': {}, 'head': (0.0, 0.0, 0.0), 'tail': 0.0}, 0.0
        t = i / frames
        bob = q(g['bob'] * k * math.sin(2 * math.pi * t) ** 2)
        air = q(max(0.0, bob - g['bob'] * k * (1 - g['flight'] * 0.6)))      # the planted feet leave the ground
        feet = {}
        for (side, front), ph in (((-1, True), 0.0), ((1, False), 0.0), ((1, True), 0.5), ((-1, False), 0.5)):
            dy, dz = swing((t + ph) % 1.0, g['stride'] * k, g['lift'] * k)
            feet[(side, front)] = (q(max(dy, air)) - bob, q(dz))
        # the head rides a beat behind the body's bob (so it reads as a nod, not a lift), reaching a
        # touch forward as a front foot swings; the tail swings side to side once a cycle
        nod = g.get('nod', 0.0)
        head = (0.0, -nod * math.sin(2 * math.pi * t - 0.9) ** 2, 0.35 * nod * math.sin(2 * math.pi * (t + 0.25)))
        tail = g.get('tail', 0.0) * math.sin(2 * math.pi * t)
        return {'feet': feet, 'head': head, 'tail': tail}, bob
    return pose


def sher_pose(gait='walk'):
    g = BIPED[gait]

    def pose(i):
        """Sher on two legs: a boot swings forward with a lift while the other carries him, paws swinging
        against the legs; he bobs up as a leg passes under him."""
        if i is None:
            return {'legs': {}, 'arms': {}, 'lean': 0.0}, 0.0
        t = i / FRAMES
        bob = q(g['bob'] * math.sin(2 * math.pi * t) ** 2)
        air = q(max(0.0, bob - g['bob'] * (1 - g['flight'] * 0.6)))
        legs, arms = {}, {}
        for side, ph in ((-1, 0.0), (1, 0.5)):
            dy, dz = swing((t + ph) % 1.0, g['stride'], g['lift'])
            legs[side] = (q(max(dy, air)) - bob, q(dz))
            arms[-side] = dz * g['arms'] / max(g['stride'], 1e-6) * 2.0 * 0.9
        return {'legs': legs, 'arms': arms, 'lean': g['lean']}, bob
    return pose


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
    # the walker turned by FACING[d] under a fixed camera = the camera turned the other way around it
    return Camera(yaw=-FACING[d], pitch=MAP_PITCH)


def frame_box(items, ground, scale, extra=None):
    """one frame size for every direction, gait and frame, the ground point at the same pixel"""
    G = np.asarray(ground, np.float64)
    xs, ys = [], []
    for d in DIRS:
        cam = cam_for(d)
        for M, bob in items:
            P = model_extent_points(M)
            if extra is not None:
                P = np.concatenate([P, extra])
            sx, sy, _ = cam.project(P - G + np.array([0.0, bob, 0.0]))
            xs += [sx.min(), sx.max()]
            ys += [sy.min(), sy.max()]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    half = max(-x0, x1)
    w = int(math.ceil(2 * half * scale + 2 * PAD))
    h = int(math.ceil((y1 - y0) * scale + 2 * PAD))
    w += w % 2
    h += h % 2
    return w, h, w / 2, PAD - y0 * scale


class Walker:
    """One kind of walker: how to build a pose, its gaits, the variants (palettes) to render."""

    def __init__(self, key, builder, poses, variants, scale, radius, gaits, stage_k=1.0, nframes=FRAMES):
        self.key, self.builder, self.poses, self.variants = key, builder, poses, variants
        self.scale, self.radius, self.gaits, self.stage_k = scale, radius, gaits, stage_k
        self.nframes = nframes  # frames a cycle (the sheet has one more: the idle stance first)

    def frames(self, gait):
        pose = self.poses[gait]
        ps = [pose(None)] + [pose(i) for i in range(self.nframes)]
        return [(self.builder(p), bob) for p, bob in ps]


def evochi(stage):
    gaits = EVO_GAITS[stage]

    def builder(p):
        return build(stage, 2, feet=p['feet'], head=p.get('head'), tail=p.get('tail', 0.0), lo_y=-3)
    return Walker(f's0{stage}', builder, {g: quad_pose(g, stage, EVO_FRAMES, gaits[g]) for g in gaits}, VARIANT_ORDER,
                  STAGE_SCALE[stage], RADIUS[stage], gaits, 1.0, EVO_FRAMES)


def sher():
    from wilds_npcs import build_sher
    from village_npc_render import npc_palette
    from village_npcs import INK

    def builder(p):
        return build_sher(2, legs=p['legs'], arms=p['arms'], lo_y=-3, lean=p['lean'])
    base = build_sher(2, lo_y=-3)
    return Walker('sher', builder, {g: sher_pose(g) for g in BIPED}, [('sher', npc_palette(base, INK))], SCALE,
                  RADIUS['sher'], BIPED)


WALKERS = {'s01': lambda: evochi(1), 's02': lambda: evochi(2), 's03': lambda: evochi(3), 'sher': sher}


def layout(wk: Walker, built):
    base = built['walk'][0][0]
    G = base.anchors.get('ground', (0, 0, 0))
    G = (G[0], 0.0, G[2])
    whisk = getattr(base, 'whiskers', None)
    extra = np.concatenate([x.points() for x in whisk]) if whisk else None
    w, h, gx, gy = frame_box([(c.model, b) for g in built for c, b in built[g]], G, wk.scale, extra)
    return G, w, h, gx, gy


def render_walker(out, wk: Walker, preview=False, palettes=None, gaits=None):
    gaits = list(wk.gaits) if gaits is None else gaits
    built = {g: wk.frames(g) for g in wk.gaits}
    G, w, h, gx, gy = layout(wk, built)
    print(wk.key, 'frame', w, h, 'ground', round(gx, 1), round(gy, 1), flush=True)
    nf = wk.nframes
    meta = {'frameW': w, 'frameH': h, 'ground': [round(gx, 1), round(gy, 1)], 'scale': wk.scale,
            'radius': wk.radius, 'frames': nf, 'gaits': {}}
    for gait, g in wk.gaits.items():
        bobs = [b for _, b in built[gait]]
        meta['gaits'][gait] = {
            'sheets': {},
            # per frame (idle first): the waddle's roll in degrees, about the walker's own forward axis (the
            # app turns the sprite by roll x cos(facing): it reads left-right from the front, not at all
            # side-on), a squash (vertical scale) on each footfall, and how far the body is lifted (px up),
            # for the wearables drawn over it
            'roll': [0.0] + [round(g['waddle'] * math.sin(2 * math.pi * i / nf), 2) for i in range(nf)],
            'squash': [1.0] + [round(1.0 - g['squash'] * math.cos(2 * math.pi * i / nf) ** 8, 3) for i in range(nf)],
            'lift': [round(b * math.cos(math.radians(MAP_PITCH)) * wk.scale, 1) for b in bobs],
            # world units covered per cycle without the feet sliding (the app paces the frames by it)
            'cycle': round(4 * g['stride'] * wk.stage_k, 2),
        }
    for gait in gaits:
        for var in wk.variants:
            name, pal = (var, None) if isinstance(var, str) else var
            if palettes and name not in palettes:
                continue
            sheet = Image.new('RGBA', (w * (nf + 1), h * len(DIRS)), (0, 0, 0, 0))
            for r, d in enumerate(DIRS):
                cam = cam_for(d)
                light = light_for(cam.yaw)
                for c, (ch, bob) in enumerate(built[gait]):
                    # the ground under this frame (the bob lifts the body off it) lands at (gx, gy)
                    gpx, gpy, _ = cam.project(np.array([[G[0], -bob, G[2]]]))
                    fit = Fit(wk.scale, gx - gpx[0] * wk.scale, gy - gpy[0] * wk.scale, w, h)
                    o = render_char(ch, name, 'default', cam, w, h, fit=fit, light=light, pal=pal, pal_key=name)
                    sheet.paste(Image.fromarray(o.rgba), (c * w, r * h))
            fn = f'{gait}_{wk.key}_{name}.webp'
            sheet.save(os.path.join(out, fn), quality=84, method=6)
            if preview:
                sheet.save(os.path.join(out, fn.replace('.webp', '.png')))
            meta['gaits'][gait]['sheets'][name] = fn
            print(wk.key, gait, name, os.path.getsize(os.path.join(out, fn)) // 1024, 'KB', flush=True)
    return meta


def render_wear(out, wk: Walker):
    """Each wearable over the walker's idle body, per direction (one row), cut out the way the hero
    overlays are (build_characters): only what shows in front of the body. The app lifts it by the gait's
    per-frame body lift and turns/squashes it with the body."""
    from accessories import wear, WEARABLES
    built = {g: wk.frames(g) for g in wk.gaits}
    G, w, h, gx, gy = layout(wk, built)
    base = built['walk'][0][0]
    items = {}
    for item, (slot, _) in WEARABLES.items():
        Mw = wear(base, item)
        row = Image.new('RGBA', (w * len(DIRS), h), (0, 0, 0, 0))
        for r, d in enumerate(DIRS):
            cam = cam_for(d)
            light = light_for(cam.yaw)
            gpx, gpy, _ = cam.project(np.array([[G[0], 0.0, G[2]]]))
            fit = Fit(wk.scale, gx - gpx[0] * wk.scale, gy - gpy[0] * wk.scale, w, h)
            body = render_char(base, 'amber', 'default', cam, w, h, fit=fit, light=light)
            comb = render_char(base, 'amber', 'default', cam, w, h, fit=fit, light=light, extra_model=Mw, cov_prefix='acc_')
            ab = body.rgba[..., 3] / 255.0
            ac = comb.rgba[..., 3] / 255.0
            extra = np.clip((ac - ab) / np.maximum(1 - ab, 1e-3), 0, 1)
            a = np.clip(np.maximum(comb.cov, extra) * 1.05, 0, 1)
            ov = comb.rgba.copy()
            ov[..., 3] = (a * 255).astype(np.uint8)
            row.paste(Image.fromarray(ov), (r * w, 0))
        fn = f'wear_{wk.key}_{item}.webp'
        row.save(os.path.join(out, fn), quality=88, method=6)
        items[item] = {'file': fn, 'slot': slot}
        print(wk.key, 'wear', item, flush=True)
    return items


def main(out, preview=False, palettes=None, only=None, gaits=None, wear=False):
    os.makedirs(out, exist_ok=True)
    mpath = os.path.join(out, 'wilds_walk.json')
    for key in (only or list(WALKERS)):
        wk = WALKERS[key]()
        if wear:
            items = render_wear(out, wk)
        else:
            m = render_walker(out, wk, preview, palettes, gaits)
        # merge into the meta on disk (another process may be writing other walkers)
        meta = json.load(open(mpath)) if os.path.exists(mpath) else {}
        meta.update({'pitch': MAP_PITCH, 'scale': SCALE, 'fps': FPS, 'dirs': DIRS, 'frames': FRAMES})
        walkers = meta.setdefault('walkers', {})
        old = walkers.get(key, {})
        if wear:
            old['wear'] = {**old.get('wear', {}), **items}     # the mining gear's entries (mining_gear.py) stay
            walkers[key] = old
        else:
            # keep sheets of variants/gaits not re-rendered this time, and the wearables
            for g, gm in old.get('gaits', {}).items():
                if g in m['gaits']:
                    for v, fn in gm.get('sheets', {}).items():
                        m['gaits'][g]['sheets'].setdefault(v, fn)
            if 'wear' in old and (old.get('frameW'), old.get('frameH')) == (m['frameW'], m['frameH']):
                m['wear'] = old['wear']
            walkers[key] = m
        json.dump(meta, open(mpath, 'w'), indent=1)


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = {a.split('=', 1)[0]: a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--') and '=' in a}
    main(args[0], preview='--preview' in sys.argv,
         palettes=opts['--palettes'].split(',') if '--palettes' in opts else None,
         only=opts['--only'].split(',') if '--only' in opts else None,
         gaits=opts['--gaits'].split(',') if '--gaits' in opts else None,
         wear='--wear' in sys.argv)

"""Your Evochi taking the guardian's roar in the Wilds' boss entrances: a continuous reaction, Shock -> Strain ->
Resolve, from keyframed rig poses (characters.build_*: the head turned rigidly with its face, the jaw opening in
the voxels (jaw.py), the torso crouching, the feet bracing and spreading, the tail countering) and the
Expression Style Kit's faces, timed with them.

  SHOCK    the blast hits: it recoils, the mouth opens, it loses its balance for a moment
  STRAIN   eyes squeezed shut, centre of gravity down, legs braced, resisting the force
  RESOLVE  it finds its footing, opens its eyes with determination and holds its ground

    python3 cine_react.py OUT_DIR [stage] [personality]   -> react_<stage>_keys.png, react_<stage>.mp4
"""
from __future__ import annotations

import os
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from characters import build                                      # noqa: E402
from charrender import render_char                                # noqa: E402
from voxel import Camera, fit_camera, model_extent_points         # noqa: E402
from turnarounds import font                                      # noqa: E402

GAME = Camera(yaw=-32, pitch=-7)                                  # the boss entrance's camera (cine_evochi.CAM)
VIEWS = [('front', Camera(yaw=0, pitch=0)), ('three-quarter (the game)', GAME), ('side', Camera(yaw=-90, pitch=0)),
         ('slightly below', Camera(yaw=-24, pitch=-30))]
FPS = 12
BG = (250, 240, 228)
INK = (52, 36, 30)
SUB = (120, 96, 82)

NEAR, FAR = -1, 1          # the Evochi's side nearest the game camera, and the other
FN, FF, BN, BF = (NEAR, True), (FAR, True), (NEAR, False), (FAR, False)

# keyframes per stage: (time s, rig pose, face). Rig: head (dx, dy, dz), head_rot (pitch up, yaw, roll), body
# (dy front, dy back), feet {foot: (dy, dz, dx out)}, tail (swing), tail_lift, jaw (degrees open)
KEYS = {
    2: [  # Juvenile: athletic; head, shoulders and legs react apart; a visible recovery
        (0.00, dict(), 'fierce'),
        (0.10, dict(head=(0.0, 0.8, -2.2), head_rot=(17, 0, -6), body=(0.9, -1.0), tail=2.5, tail_lift=3.2, jaw=26,
                    feet={FN: (1.5, 0.8, 0.0), FF: (0.0, 0.2, 0.0), BN: (0.0, -1.4, 0.0), BF: (0.0, -1.0, 0.0)}), 'shout'),
        (0.26, dict(head=(0.0, 0.4, -1.2), head_rot=(11, 0, -3), body=(0.2, -0.8), tail=1.5, tail_lift=2.0, jaw=22,
                    feet={FN: (0.4, 0.8, 0.0), FF: (0.0, 0.5, 0.0), BN: (0.0, -1.2, 0.0), BF: (0.0, -1.2, 0.0)}), 'shout'),
        (0.42, dict(head=(0.0, -1.4, 0.8), head_rot=(-10, 0, 3), body=(-1.8, -0.8), tail=-2.5, tail_lift=-1.0,
                    feet={FN: (0.0, 1.6, 0.6), FF: (0.0, 1.6, 0.6), BN: (0.0, -1.8, 0.4), BF: (0.0, -1.8, 0.4)}), 'strain'),
        (0.80, dict(head=(0.0, -1.7, 1.0), head_rot=(-12, 0, 2), body=(-2.0, -1.0), tail=-2.8, tail_lift=-1.2,
                    feet={FN: (0.0, 1.8, 0.6), FF: (0.0, 1.8, 0.6), BN: (0.0, -2.0, 0.4), BF: (0.0, -2.0, 0.4)}), 'strain'),
        (0.95, dict(head=(0.0, -0.3, 1.3), head_rot=(3, 0, 0), body=(-1.0, -0.6), tail=1.0, tail_lift=0.8,
                    feet={FN: (0.0, 1.4, 0.6), FF: (0.0, 1.4, 0.6), BN: (0.0, -1.4, 0.4), BF: (0.0, -1.4, 0.4)}), 'fierce'),
        (1.30, dict(head=(0.0, -0.6, 1.0), head_rot=(0, 0, 0), body=(-1.2, -0.6), tail=0.5, tail_lift=0.5,
                    feet={FN: (0.0, 1.4, 0.6), FF: (0.0, 1.4, 0.6), BN: (0.0, -1.4, 0.4), BF: (0.0, -1.4, 0.4)}), 'fierce'),
    ],
    3: [  # Elder: heavy and controlled; head and neck recoil apart from the torso, shoulders drop, front legs spread,
          # the tail counters; little bounce. The head is turned a little to the camera throughout, so both eyes read
        (0.00, dict(head_rot=(0, -10, 0)), 'fierce'),
        (0.14, dict(head=(0.0, 1.4, -2.6), head_rot=(13, -10, -3), body=(0.3, -0.5), tail=2.0, tail_lift=2.4, jaw=22,
                    feet={FN: (0.0, -0.6, 0.0), FF: (0.0, -0.3, 0.0), BN: (0.0, -0.6, 0.0), BF: (0.0, -0.6, 0.0)}), 'shout'),
        (0.32, dict(head=(0.0, 1.0, -2.0), head_rot=(9, -10, -2), body=(0.1, -0.5), tail=1.5, tail_lift=1.8, jaw=18,
                    feet={FN: (0.0, -0.6, 0.0), FF: (0.0, -0.3, 0.0), BN: (0.0, -0.6, 0.0), BF: (0.0, -0.6, 0.0)}), 'shout'),
        (0.52, dict(head=(0.0, -1.6, 1.0), head_rot=(-11, -10, 2), body=(-2.2, -0.9), tail=-3.0, tail_lift=-1.2,
                    feet={FN: (0.0, 1.2, 1.4), FF: (0.0, 1.2, 1.4), BN: (0.0, -1.0, 0.6), BF: (0.0, -1.0, 0.6)}), 'strain'),
        (0.90, dict(head=(0.0, -1.9, 1.2), head_rot=(-13, -10, 2), body=(-2.5, -1.0), tail=-3.2, tail_lift=-1.4,
                    feet={FN: (0.0, 1.2, 1.4), FF: (0.0, 1.2, 1.4), BN: (0.0, -1.0, 0.6), BF: (0.0, -1.0, 0.6)}), 'strain'),
        (1.10, dict(head=(0.0, -0.5, 1.2), head_rot=(2, -10, 0), body=(-1.2, -0.6), tail=1.0, tail_lift=0.6,
                    feet={FN: (0.0, 1.0, 1.4), FF: (0.0, 1.0, 1.4), BN: (0.0, -1.0, 0.6), BF: (0.0, -1.0, 0.6)}), 'fierce'),
        (1.50, dict(head=(0.0, -0.6, 1.0), head_rot=(0, -10, 0), body=(-1.2, -0.6), tail=0.4, tail_lift=0.3,
                    feet={FN: (0.0, 1.0, 1.4), FF: (0.0, 1.0, 1.4), BN: (0.0, -1.0, 0.6), BF: (0.0, -1.0, 0.6)}), 'fierce'),
    ],
}
BEATS = {'shout': 'Shock', 'strain': 'Strain', 'fierce': 'Resolve'}
KEY_POSES = {2: [(0.10, 'Shock: thrown back, mouth open, a front foot off the ground, tail up for balance'),
                 (0.80, 'Strain: head ducked into the blast, shoulders and centre of gravity down, legs braced'),
                 (1.30, 'Resolve: back on its feet, head level, planted wide, eyes open and set')],
             3: [(0.14, 'Shock: head and neck snap back, jaw drops, the body rocks back on planted feet, tail lifts'),
                 (0.90, 'Strain: shoulders down, front legs spread and braced, head pushed into the blast, tail low'),
                 (1.50, 'Resolve: head level, planted wide and still: controlled power')]}


def _ease(u):
    return u * u * (3 - 2 * u)


def _mix(a, b, u):
    if isinstance(a, dict) or isinstance(b, dict):
        a, b = a or {}, b or {}
        return {k: _mix(a.get(k, (0.0, 0.0, 0.0)), b.get(k, (0.0, 0.0, 0.0)), u) for k in set(a) | set(b)}
    if isinstance(a, (tuple, list)) or isinstance(b, (tuple, list)):
        n = max(len(a) if isinstance(a, (tuple, list)) else 0, len(b) if isinstance(b, (tuple, list)) else 0)
        a = tuple(a) + (0.0,) * (n - len(a)) if isinstance(a, (tuple, list)) else (a or 0.0,) * n
        b = tuple(b) + (0.0,) * (n - len(b)) if isinstance(b, (tuple, list)) else (b or 0.0,) * n
        return tuple(x + (y - x) * u for x, y in zip(a, b))
    return (a or 0.0) + ((b or 0.0) - (a or 0.0)) * u


def pose_at(stage, t):
    """the rig pose and the face at time t (s): keyframes eased into each other; the face cuts with its key"""
    keys = KEYS[stage]
    if t <= keys[0][0]:
        return keys[0][1], keys[0][2]
    for (t0, p0, f0), (t1, p1, f1) in zip(keys, keys[1:]):
        if t <= t1:
            u = _ease((t - t0) / (t1 - t0))
            names = set(p0) | set(p1)
            pose = {k: _mix(p0.get(k), p1.get(k), u) for k in names}
            face = f1 if u > 0.35 else f0
            return pose, face
    return keys[-1][1], keys[-1][2]


_built = {}


def character(stage, pose):
    key = (stage, repr(sorted((k, repr(v)) for k, v in pose.items())))
    if key not in _built:
        if len(_built) > 6:
            _built.clear()
        _built[key] = _character(stage, pose)
    return _built[key]


def _character(stage, pose):
    kw = dict(pose)
    feet = kw.pop('feet', None)
    if feet:
        kw['feet'] = {k: (v[0], v[1], v[2] if len(v) > 2 else 0.0) for k, v in feet.items()}
    if kw.get('jaw', 0) < 0.5:
        kw.pop('jaw', None)
    return build(stage, **kw)


def face_expr(face, pose, pers='brave'):
    if pose.get('jaw', 0) >= 3:                           # while the jaw is open the face is the open-mouthed one
        face = 'shout'
    if face == 'shout' and pose.get('jaw', 0) >= 3:
        return 'shout:%s:nomouth' % pers                 # the mouth is the jaw's: the face keeps eyes and brows
    if face == 'shout':
        return 'fierce' if pers == 'brave' else 'fierce:%s' % pers
    return face if pers == 'brave' else '%s:%s' % (face, pers)


def _frame(args):
    stage, t, cam_i, w, h, fit, pers = args
    pose, face = pose_at(stage, t)
    ch = character(stage, pose)
    cam = VIEWS[cam_i][1] if cam_i is not None else GAME
    r = render_char(ch, 'amber', face_expr(face, pose, pers), cam, w, h, fit=fit)
    im = Image.new('RGB', (w, h), BG)
    c = Image.fromarray(r.rgba)
    im.paste(c, (0, 0), c)
    return im


def _fits(stage, cams, w, h):
    models = [character(stage, pose_at(stage, t)[0]).model for t, _ in KEY_POSES[stage]] + [character(stage, {}).model]
    pts = np.concatenate([model_extent_points(m) for m in models])
    return [fit_camera(c, pts, w, h, margin=0.05) for c in cams]


def main(out, stage=2, pers='brave'):
    os.makedirs(out, exist_ok=True)
    name = {1: 'eggling', 2: 'juvenile', 3: 'elder'}[stage]
    cw, chh = 400, 340
    fits = _fits(stage, [c for _, c in VIEWS], cw, chh)
    jobs = [(stage, t, i, cw, chh, fits[i], pers) for t, _ in KEY_POSES[stage] for i in range(len(VIEWS))]
    with ProcessPoolExecutor(2) as ex:
        cells = list(ex.map(_frame, jobs))
    W = 40 + len(VIEWS) * (cw + 14) + 26
    img = Image.new('RGB', (W, 120 + 3 * (chh + 74)), BG)
    d = ImageDraw.Draw(img)
    d.text((40, 24), '%s: taking the roar (Shock, Strain, Resolve)' % name.capitalize(), font=font(38), fill=INK)
    d.text((40, 78), 'The model posed by its rig: head turned with its face, jaw opened in the voxels, torso, feet and '
           'tail. Amber, %s faces.' % pers.capitalize(), font=font(19, False), fill=SUB)
    for k, (t, note) in enumerate(KEY_POSES[stage]):
        y = 120 + k * (chh + 74)
        d.text((40, y), '%.2f s  %s' % (t, note), font=font(20), fill=INK)
        for i in range(len(VIEWS)):
            x = 40 + i * (cw + 14)
            img.paste(cells[k * len(VIEWS) + i], (x, y + 32))
            if k == 0:
                pass
            d.text((x + 6, y + 32 + chh - 24), VIEWS[i][0], font=font(15, False), fill=SUB)
    sheet = os.path.join(out, 'react_%s_keys.png' % name)
    img.save(sheet, optimize=True)
    print(sheet, flush=True)
    # the reaction, at the game's camera: a beat before, the reaction, a hold after
    vw, vh = 720, 600
    vfit = _fits(stage, [GAME], vw, vh)[0]
    end = KEYS[stage][-1][0]
    times = [0.0] * 4 + [i / FPS for i in range(int(end * FPS) + 1)] + [end] * 8
    with ProcessPoolExecutor(2) as ex:
        frames = list(ex.map(_frame, [(stage, t, None, vw, vh, vfit, pers) for t in times]))
    fdir = os.path.join(out, 'frames_%s' % name)
    os.makedirs(fdir, exist_ok=True)
    for i, f in enumerate(frames):
        f.save(os.path.join(fdir, '%03d.png' % i))
    mp4 = os.path.join(out, 'react_%s.mp4' % name)
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-framerate', str(FPS), '-i', os.path.join(fdir, '%03d.png'),
                    '-vf', 'fps=24,format=yuv420p', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '18', mp4], check=True)
    print(mp4, len(frames), 'frames')


if __name__ == '__main__':
    a = sys.argv
    main(a[1], int(a[2]) if len(a) > 2 else 2, a[3] if len(a) > 3 else 'brave')

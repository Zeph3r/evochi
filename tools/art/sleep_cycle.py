"""The sleep & wake cycle (the storyboards of Nov 2026, Juvenile and Elder): idle, a small circle with a sniff
at the chosen spot, the head and shoulders lowered, the front half down, the hind legs folding in and the body
curling round on itself after its tail (a cat settling), the sleep hold (breathing, z's), waking, the push-up
and back to standing. Built on the rig's own
knobs (characters.build: feet, body, head, head_rot, tail, tail_lift) and rendered with the game's renderer,
so it is on-model and what a sprite sheet of it would be.

    python3 sleep_cycle.py OUT_DIR [--stage=2,3] [--palette=amber] [--fps=10] [--mane=petal]

Writes OUT_DIR/sleep_sNN_<palette>/frame_NNNN.png, sleep_sNN_<palette>.gif (the animatic), and
sleep_sNN_<palette>_board.png (the twelve storyboard moments side by side, labelled).
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from characters import build, curl_body
from charrender import render_char
from voxel import Camera, Fit, save_rgba
from walk import EVO_FRAMES, EVO_GAITS, light_for, quad_pose

FN, FF, BN, BF = (-1, True), (1, True), (-1, False), (1, False)
BASE_YAW = {2: 36.0, 3: 36.0}
PITCH = 13.0
SCALE = {2: 8.0, 3: 6.0}
W, H = 560, 520

# ---- the poses (the storyboard's moments), per stage. body: (front drop, back drop); head: (dx, dy, dz);
# head_rot: (pitch, yaw, roll); feet: (dy, dz[, dx]); tail, tail_lift.
STAND = dict(body=(0.0, 0.0), head=(0.0, 0.0, 0.0), head_rot=(0.0, 0.0, 0.0), feet={}, tail=0.0, tail_lift=0.0, curl=0.0)

# the curl: the body bent round on itself behind the shoulders (characters.curl_body), toward the side the tail
# comes round (CURL_SIDE: -1, the model's -x, which is toward the camera at the base yaw), its radius per stage
CURL_SIDE = -1
CURL_R = {2: 12.0, 3: 16.0}


def poses(stage):
    if stage == 3:
        drop = 10.0
        return {
            'stand': STAND,
            'sniff': dict(body=(-1.5, 0.0), head=(0.0, -2.5, 1.5), head_rot=(-22.0, -6.0, 0.0), feet={}, tail=-3.0, tail_lift=1.0, curl=25.0),
            'lower': dict(body=(-6.0, -1.0), head=(0.0, -3.0, 1.0), head_rot=(-14.0, -10.0, 2.0),
                          feet={FN: (0.0, 3.0, 0.5), FF: (0.0, 3.5, 0.5)}, tail=-4.0, tail_lift=-1.0, curl=45.0),
            'front_down': dict(body=(-drop, -4.0), head=(0.8, -3.5, 1.0), head_rot=(-12.0, -16.0, 4.0),
                               feet={FN: (0.0, 5.5, 1.5), FF: (0.0, 7.0, 1.0), BN: (0.0, 1.5, 2.0), BF: (0.0, 1.0, 2.5)},
                               tail=-5.0, tail_lift=-2.0, curl=62.0),
            'settle': dict(body=(-drop, -9.5), head=(1.0, -4.0, 1.0), head_rot=(-11.0, -22.0, 6.0),
                           feet={FN: (0.0, 6.0, 1.5), FF: (0.0, 7.5, 1.0), BN: (0.0, 4.5, 4.0), BF: (0.0, 3.5, 4.5)},
                           tail=-6.0, tail_lift=-3.0, curl=82.0),
            'wake': dict(body=(-6.0, -9.0), head=(0.6, -1.0, 1.5), head_rot=(2.0, -12.0, 3.0),
                         feet={FN: (0.0, 5.0, 1.5), FF: (0.0, 6.0, 1.0), BN: (0.0, 4.0, 3.5), BF: (0.0, 3.0, 4.0)},
                         tail=-5.0, tail_lift=-2.0, curl=60.0),
            'push': dict(body=(-1.0, -6.0), head=(0.0, 0.5, 1.0), head_rot=(6.0, -4.0, 0.0),
                         feet={FN: (0.0, 2.0, 0.8), FF: (0.0, 2.5, 0.5), BN: (0.0, 2.0, 2.0), BF: (0.0, 1.5, 2.0)},
                         tail=-2.0, tail_lift=0.0, curl=20.0),
        }
    return {
        'stand': STAND,
        'sniff': dict(body=(-1.0, 0.0), head=(0.0, -2.0, 1.2), head_rot=(-20.0, -6.0, 0.0), feet={}, tail=-2.0, tail_lift=1.0, curl=25.0),
        'lower': dict(body=(-2.5, -0.5), head=(0.0, -2.2, 0.8), head_rot=(-14.0, -10.0, 2.0),
                      feet={FN: (0.0, 2.2, 0.5), FF: (0.0, 2.0, 0.4)}, tail=-3.0, tail_lift=-0.5, curl=45.0),
        'front_down': dict(body=(-3.0, -1.5), head=(0.6, -2.4, 0.6), head_rot=(-12.0, -16.0, 4.0),
                           feet={FN: (0.0, 3.0, 1.0), FF: (0.0, 2.4, 0.4), BN: (0.0, 1.2, 1.5), BF: (0.0, 0.8, 2.0)},
                           tail=-3.5, tail_lift=-1.5, curl=70.0),
        'settle': dict(body=(-3.0, -2.5), head=(0.8, -2.4, 0.4), head_rot=(-10.0, -22.0, 6.0),
                       feet={FN: (0.0, 3.2, 1.0), FF: (0.0, 2.4, 0.4), BN: (0.0, 2.0, 2.0), BF: (0.0, 1.4, 2.5)},
                       tail=-4.0, tail_lift=-2.0, curl=105.0),
        'wake': dict(body=(-2.0, -2.0), head=(0.5, -0.8, 1.0), head_rot=(2.0, -12.0, 3.0),
                     feet={FN: (0.0, 2.6, 1.0), FF: (0.0, 2.0, 0.4), BN: (0.0, 1.8, 1.8), BF: (0.0, 1.2, 2.2)},
                     tail=-3.0, tail_lift=-1.5, curl=70.0),
        'push': dict(body=(-0.8, -1.5), head=(0.0, 0.4, 0.8), head_rot=(6.0, -4.0, 0.0),
                     feet={FN: (0.0, 1.5, 0.6), FF: (0.0, 1.5, 0.4), BN: (0.0, 1.2, 1.2), BF: (0.0, 1.0, 1.5)},
                     tail=-1.5, tail_lift=0.0, curl=20.0),
    }


# ---- the timeline: (start s, end s, from pose, to pose, face, what the frame is doing), in order. The circle
# is walked (the walk cycle's feet over the turn) from 1.0 to 4.2 s; the sniff stops it at the spot.
def timeline():
    return [
        (0.0, 1.0, 'stand', 'stand', 'default', 'idle'),
        (1.0, 4.2, 'stand', 'stand', 'default', 'circle'),
        (4.2, 4.5, 'stand', 'sniff', 'curious', 'sniff'),
        (4.5, 5.2, 'sniff', 'sniff', 'curious', 'sniff'),
        (5.2, 6.0, 'sniff', 'lower', 'blink', 'lower'),
        (6.0, 6.9, 'lower', 'front_down', 'blink', 'front_down'),
        (6.9, 7.8, 'front_down', 'settle', 'cosy', 'settle'),
        (7.8, 11.3, 'settle', 'settle', 'cosy', 'sleep'),
        (11.3, 12.0, 'settle', 'wake', 'blink', 'wake'),
        (12.0, 12.4, 'wake', 'wake', 'default', 'wake'),
        (12.4, 13.2, 'wake', 'push', 'default', 'push'),
        (13.2, 13.9, 'push', 'stand', 'content', 'rise'),
        (13.9, 14.6, 'stand', 'stand', 'content', 'idle'),
    ]


BOARD = [  # the storyboard's twelve, as seconds into the cycle
    (0.5, '01 Idle'), (1.7, '02 Begins circle'), (2.8, '03 Circling'), (4.9, '04 Sniff'), (3.8, '05 Finishes circle'),
    (5.6, '06 Lowers head'), (6.6, '07 Front half down'), (7.5, '08 Settle'), (9.5, '09 Sleep hold'),
    (12.2, '10 Wake'), (12.9, '11 Push up'), (14.2, '12 Return to stand'),
]


def smooth(u):
    u = min(1.0, max(0.0, u))
    return u * u * (3 - 2 * u)


def lerp_pose(a, b, u):
    u = smooth(u)
    def l(x, y):
        return x + (y - x) * u
    feet = {}
    for k in set(a['feet']) | set(b['feet']):
        fa, fb = a['feet'].get(k, (0.0, 0.0, 0.0)), b['feet'].get(k, (0.0, 0.0, 0.0))
        fa, fb = tuple(fa) + (0.0,) * (3 - len(fa)), tuple(fb) + (0.0,) * (3 - len(fb))
        feet[k] = tuple(l(x, y) for x, y in zip(fa, fb))
    return dict(
        body=tuple(l(x, y) for x, y in zip(a['body'], b['body'])),
        head=tuple(l(x, y) for x, y in zip(a['head'], b['head'])),
        head_rot=tuple(l(x, y) for x, y in zip(a['head_rot'], b['head_rot'])),
        feet=feet, tail=l(a['tail'], b['tail']), tail_lift=l(a['tail_lift'], b['tail_lift']), curl=l(a['curl'], b['curl']))


def frame_at(stage, t, P):
    """the pose, face, turn (degrees of the circle walked) and circle position (0..1) at t seconds"""
    for t0, t1, a, b, face, what in timeline():
        if t0 <= t < t1 or (t1 == timeline()[-1][1] and t >= t1):
            u = (t - t0) / (t1 - t0) if t1 > t0 else 1.0
            pose = lerp_pose(P[a], P[b], u)
            turn, circ, walk = 0.0, 0.0, None
            if what == 'circle':
                turn = 360.0 * smooth(u)
                circ = smooth(u)
                pose['curl'] = 25.0 * smooth(max(0.0, (u - 0.7) / 0.3))   # following its tail round into the spot
                # the walk cycle's feet and nod over the turn (three strides), fading out at the end
                g = EVO_GAITS[stage]['walk']
                wp = quad_pose('walk', stage, EVO_FRAMES, g)
                k = 3 * EVO_FRAMES * u
                w, bob = wp(int(k) % EVO_FRAMES)
                ease = min(1.0, (1 - u) * 6) * min(1.0, u * 6)
                walk = (w, bob, ease)
            if what == 'sleep':
                # breathing: the body and head rise and fall a little, a slow 3 s wave
                b2 = math.sin(2 * math.pi * (t - t0) / 3.0)
                pose['body'] = (pose['body'][0] + 0.5 * b2, pose['body'][1] + 0.4 * b2)
                pose['head'] = (pose['head'][0], pose['head'][1] + 0.3 * b2, pose['head'][2])
                pose['head_rot'] = (pose['head_rot'][0] + 1.2 * b2, pose['head_rot'][1], pose['head_rot'][2])
                pose['tail_lift'] += 0.3 * b2
            if what == 'idle':
                b2 = math.sin(2 * math.pi * t / 2.4)
                pose['body'] = (pose['body'][0] + 0.25 * b2, pose['body'][1] + 0.25 * b2)
            return pose, face, turn, circ, walk, what
    raise ValueError(t)


def build_pose(stage, pose, walk, mane):
    feet = {k: tuple(v) for k, v in pose['feet'].items()}
    head = list(pose['head'])
    body = list(pose['body'])
    if walk is not None:
        w, bob, ease = walk
        for k, (dy, dz) in w['feet'].items():
            feet[k] = (dy * ease, dz * ease, 0.0)
        head = [head[0] + w['head'][0] * ease, head[1] + w['head'][1] * ease, head[2] + w['head'][2] * ease]
        body = [body[0] + bob * ease, body[1] + bob * ease]
        tail = pose['tail'] + w['tail'] * ease
    else:
        tail = pose['tail']
    kw = dict(feet=feet, head=tuple(head), head_rot=pose['head_rot'], body=tuple(body), tail=tail, tail_lift=pose['tail_lift'], lo_y=-12)
    if stage == 3 and mane:
        kw['mane'] = mane
    ch = build(stage, 2, **kw)
    return curl_body(ch, curl=pose.get('curl', 0.0), radius=CURL_R[stage], side=CURL_SIDE)


def ground_px(cam, ch, scale):
    sx, sy, _ = cam.project(np.asarray(ch.anchors['ground'], float).reshape(1, 3))
    return float(sx[0]) * scale, float(sy[0]) * scale


def render(out, stage, palette='amber', fps=10, mane='petal'):
    P = poses(stage)
    base_yaw = BASE_YAW[stage]
    scale = SCALE[stage]
    os.makedirs(out, exist_ok=True)
    key = f'sleep_s{stage:02d}_{palette}'
    fdir = os.path.join(out, key)
    os.makedirs(fdir, exist_ok=True)
    total = timeline()[-1][1]
    n = int(round(total * fps))
    # the ground point stays put (plus the circle's offset), whatever the pose and the turn
    stand = build_pose(stage, P['stand'], None, mane)
    gx0, gy0 = ground_px(Camera(yaw=base_yaw, pitch=PITCH), stand, scale)
    cx, cy = W / 2, H * 0.74
    R = scale * (9.0 if stage == 3 else 7.0)
    frames = []
    for i in range(n):
        t = i / fps
        pose, face, turn, circ, walk, what = frame_at(stage, t, P)
        ch = build_pose(stage, pose, walk, mane)
        yaw = base_yaw + turn
        cam = Camera(yaw=yaw, pitch=PITCH)
        # the circle: a small loop on the grass, back to where it started
        a = 2 * math.pi * circ
        off = (R * math.sin(a) * 0.9, R * (1 - math.cos(a)) * 0.32) if circ > 0 else (0.0, 0.0)
        gx, gy = ground_px(cam, ch, scale)
        fit = Fit(scale, cx + off[0] - gx, cy + off[1] - gy, W, H)
        o = render_char(ch, palette, face, cam, W, H, fit=fit, light=light_for(yaw))
        img = compose(o.rgba, (cx + off[0], cy + off[1]), what, t, stage)
        img.save(os.path.join(fdir, f'frame_{i:04d}.png'))
        frames.append(img)
        if i % 10 == 0:
            print(key, i, '/', n, what, flush=True)
    gif = os.path.join(out, key + '.gif')
    frames[0].save(gif, save_all=True, append_images=frames[1:], duration=int(1000 / fps), loop=0, optimize=False)
    board(out, key, fps, frames)
    print('wrote', gif, flush=True)


def compose(rgba, ground, what, t, stage):
    img = Image.new('RGBA', (W, H), (247, 240, 226, 255))
    d = ImageDraw.Draw(img)
    gx, gy = ground
    # the grass, a few flowers, a soft shadow under the creature
    d.ellipse((W * 0.08, H * 0.56, W * 0.92, H * 0.95), fill=(133, 186, 97, 255))
    d.ellipse((W * 0.12, H * 0.6, W * 0.88, H * 0.92), fill=(146, 199, 106, 255))
    for (fx, fy, col) in ((0.2, 0.74, (255, 250, 240)), (0.78, 0.7, (255, 250, 240)), (0.3, 0.9, (221, 170, 240)), (0.72, 0.9, (255, 250, 240))):
        d.ellipse((W * fx - 5, H * fy - 5, W * fx + 5, H * fy + 5), fill=col + (255,))
        d.ellipse((W * fx - 2, H * fy - 2, W * fx + 2, H * fy + 2), fill=(255, 214, 90, 255))
    sw = 26 * (1.3 if stage == 3 else 1.0)
    sh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse((gx - sw * 2.4, gy - sw * 0.5, gx + sw * 2.4, gy + sw * 0.6), fill=(40, 60, 30, 70))
    img.alpha_composite(sh)
    img.alpha_composite(Image.fromarray(rgba, 'RGBA'))
    if what == 'sleep':
        # the z's, rising and fading on their own clock
        for k in range(3):
            u = ((t * 0.5 + k * 0.33) % 1.0)
            s = 10 + 8 * k + 6 * u
            a = int(255 * (1 - u) * min(1.0, u * 4))
            zx, zy = gx + 70 + 22 * k + 18 * u, gy - 150 - 30 * k - 60 * u
            zi = Image.new('RGBA', (W, H), (0, 0, 0, 0))
            ImageDraw.Draw(zi).text((zx, zy), 'z', fill=(60, 40, 30, a), font=_font(s))
            img.alpha_composite(zi)
    return img


_fonts = {}


def _font(size):
    size = int(size)
    if size not in _fonts:
        try:
            _fonts[size] = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', size)
        except OSError:
            _fonts[size] = ImageFont.load_default()
    return _fonts[size]


def board(out, key, fps, frames):
    tiles = []
    for t, label in BOARD:
        i = min(len(frames) - 1, int(round(t * fps)))
        im = frames[i].copy().resize((W // 2, H // 2), Image.LANCZOS)
        d = ImageDraw.Draw(im)
        d.rectangle((0, 0, W // 2, 22), fill=(60, 40, 30, 255))
        d.text((6, 4), label, fill=(255, 245, 230, 255), font=_font(13))
        tiles.append(im)
    cols = 4
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new('RGBA', (cols * (W // 2 + 6), rows * (H // 2 + 6)), (250, 244, 232, 255))
    for i, im in enumerate(tiles):
        r, c = divmod(i, cols)
        sheet.alpha_composite(im, (c * (W // 2 + 6), r * (H // 2 + 6)))
    sheet.save(os.path.join(out, key + '_board.png'))


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = dict(a[2:].split('=', 1) for a in sys.argv[1:] if a.startswith('--') and '=' in a)
    out = args[0] if args else 'sleep_out'
    stages = [int(s) for s in opts.get('stage', '2,3').split(',')]
    for st in stages:
        render(out, st, opts.get('palette', 'amber'), int(opts.get('fps', '10')), opts.get('mane', 'petal'))

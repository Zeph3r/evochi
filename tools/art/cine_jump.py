"""Your Evochi's leap clear of the Forgotten Sentinel's beam (the boss entrance): an articulated jump from the rig,
not one pose carried along an arc. Seven phases, about 1.1 s:

  ANTICIPATION  it crouches and compresses, feet braced, weight forward on the front legs, tail drawn back
  TAKEOFF       the legs extend and drive it up and back, the front pushing off last, dust kicked forward
  ASCENT        the feet tuck under the body, the tail trails, the torso tips back
  APEX          at the top it levels out and looks down at the beam raking the ground, the tail flicks
  DESCENT       the legs extend toward the ground, the hind feet reaching back for it
  LANDING       hind feet first, then the front: the body compresses, it skids, dust scatters
  RECOVERY      it rises into its combat stance, eyes set

The rig (characters.build_juvenile) poses the head (turned rigidly with its face), the jaw (in the voxels), the
torso's crouch, each leg (lifted, shifted, spread and swung about its hip) and the tail; on top, the whole body
turns and squashes (turn_body). The body's path is ballistic in the air (a parabola: constant speed across,
gravity down); on the ground its lowest foot stands on the floor, so the push and the landing are its legs'.

    python3 cine_jump.py OUT_DIR           -> jump_compare.mp4 (current and improved, cinematic and side cameras),
                                              jump_phases.png (the seven phases, both cameras, current beside)
"""
from __future__ import annotations

import dataclasses
import math
import os
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import charrender                                                 # noqa: E402
import cine_react as CR                                           # noqa: E402
from characters import build, head_rotation                      # noqa: E402
from decals import Frame                                          # noqa: E402
from turnarounds import font                                      # noqa: E402
from voxel import Camera, Fit, Model, project_px                  # noqa: E402

CAM = Camera(yaw=-32, pitch=5)            # the entrance's camera (cine_react_export.CAM)
SIDE = Camera(yaw=-90, pitch=0)           # from its near side: the arc and the legs, flat on
VIEWS = [('Cinematic (three-quarter)', CAM), ('Side', SIDE)]
PAL = 'coral'
WORKERS = int(os.environ.get('JUMP_WORKERS', '1'))
FPS = 60                                  # sampled; the video plays real time at 30 and slowed at 0.5x
NEAR, FAR = -1, 1
FN, FF, BN, BF = (NEAR, True), (FAR, True), (NEAR, False), (FAR, False)
PIVOT = np.array([0.0, 9.5, -3.0])        # the body turns about its middle

# ---- the improved jump: keyframes (time s, pose). Pose: head (dx, dy, dz), head_rot (pitch up, yaw, roll), body
# (dy front, dy back: the crouch), feet {foot: (dy, dz, dx out, swing deg + forward)}, tail (swing), tail_lift, jaw
# (deg), and the whole body's pitch (+ nose up), roll, squash (height; volume kept)
STANCE = dict(head=(0.0, -0.6, 1.0), body=(-1.2, -0.6), tail=0.5, tail_lift=0.5,
              feet={FN: (0, 1.4, 0.6, 0), FF: (0, 1.4, 0.6, 0), BN: (0, -1.4, 0.4, 0), BF: (0, -1.4, 0.4, 0)})


def _f(front, back):
    return {FN: front, FF: front, BN: back, BF: back}


JUMP = [
    (0.00, STANCE),
    (0.07, dict(head=(0, -1.6, 0.6), head_rot=(-6, 0, 0), body=(-2.2, -2.0), tail=0.8, tail_lift=-0.4, pitch=-2,
                squash=0.97, feet=_f((0, 1.6, 0.9, 6), (0, -1.6, 0.6, -4)))),
    (0.15, dict(head=(0, -2.4, 0.2), head_rot=(-10, 0, 0), body=(-3.4, -3.6), tail=1.2, tail_lift=-1.6, pitch=-3,
                squash=0.93, feet=_f((0, 1.8, 1.2, 10), (0, -1.8, 0.9, -6)))),
    (0.21, dict(head=(0, 0.6, -0.4), head_rot=(10, 0, 0), body=(0.4, -0.4), tail=0.6, tail_lift=-2.4, pitch=9,
                squash=1.07, jaw=16, feet=_f((-1.8, 2.0, 0.8, 18), (-1.4, -1.0, 0.6, 8)))),
    (0.25, dict(head=(0, 0.8, -0.2), head_rot=(12, 0, -2), body=(0.4, -0.2), tail=0.2, tail_lift=-2.8, pitch=13,
                squash=1.06, jaw=22, feet=_f((-0.4, 2.0, 0.6, 24), (-2.0, -0.6, 0.5, 14)))),
    (0.34, dict(head=(0, 0.4, 0.6), head_rot=(6, 0, -4), body=(0.0, 0.0), tail=-1.0, tail_lift=-2.8, pitch=9, roll=-5,
                squash=1.02, jaw=24, feet=_f((2.2, 0.0, 0.3, -12), (2.0, 0.4, 0.3, 14)))),
    (0.49, dict(head=(0, 0.0, 1.0), head_rot=(-16, -12, 6), body=(0.6, 0.6), tail=-2.0, tail_lift=1.2, pitch=0, roll=4,
                jaw=20, feet=_f((2.8, -0.2, 0.2, -14), (2.8, 0.6, 0.2, 16)))),
    (0.62, dict(head=(0, 0.4, 0.4), head_rot=(4, -6, 0), body=(0.4, -0.2), tail=0.8, tail_lift=2.6, pitch=7,
                squash=1.04, jaw=14, feet=_f((-0.6, 1.0, 0.5, -6), (-1.6, -1.2, 0.6, -14)))),
    (0.74, dict(head=(0, 0.2, 0.6), head_rot=(2, -3, 0), body=(0.0, -0.4), tail=0.6, tail_lift=1.8, pitch=5,
                jaw=16, feet=_f((-0.4, 1.2, 0.6, -4), (-0.6, -1.4, 0.7, -10)))),
    (0.80, dict(head=(0, -2.6, 0.8), head_rot=(-12, 0, 3), body=(-3.4, -3.6), tail=-1.6, tail_lift=-2.0, pitch=-2,
                squash=0.88, jaw=18, feet=_f((0, 1.6, 1.4, 6), (0, -1.8, 1.2, -6)))),
    (0.88, dict(head=(0, -1.6, 0.8), head_rot=(-6, 0, 1), body=(-2.4, -2.2), tail=-0.6, tail_lift=-0.6, pitch=-1,
                squash=0.95, jaw=8, feet=_f((0, 1.5, 1.0, 3), (0, -1.6, 0.8, -3)))),
    (0.97, dict(head=(0, -0.2, 1.1), head_rot=(3, 0, 0), body=(-0.8, -0.4), tail=0.4, tail_lift=0.9, pitch=1,
                squash=1.03, feet=_f((0, 1.4, 0.7, 0), (0, -1.4, 0.5, 0)))),
    (1.10, STANCE),
]
T_OFF, T_LAND, END = 0.25, 0.74, 1.10    # the last foot leaves the ground; the first touches; the stance is held
H_APEX = 26.0                             # how high the body rises above where it left the ground (units)
Z_OFF, Z_LAND, SKID = -3.0, -40.0, 6.0    # where it is (across, away from the beam) as it leaves, lands, stops
# the face: (from time, state); each change crossfades over FADE s
FACES = [(0.0, 'fierce'), (0.17, 'shout'), (0.76, 'strain'), (0.89, 'fierce')]
FADE = 0.05
PHASES = [('Anticipation', 0.15), ('Takeoff', 0.22), ('Ascent', 0.36), ('Apex', 0.49), ('Descent', 0.64),
          ('Landing', 0.80), ('Recovery', 1.10)]
PHASE_SPANS = [('Anticipation', 0.0, 0.17), ('Takeoff', 0.17, 0.27), ('Ascent', 0.27, 0.44), ('Apex', 0.44, 0.55),
               ('Descent', 0.55, 0.74), ('Landing', 0.74, 0.88), ('Recovery', 0.88, 9.0)]

# ---- the beam: from the Sentinel's eyes (in front of the Evochi, high up) to the ground, where it stood just
# after it leaves, then raking after it and stopping a step short of where it lands
EYES = np.array([0.0, 150.0, 230.0])
BEAM_ON, BEAM_HIT, BEAM_OFF = 0.20, 0.27, 0.80
STRIKE0, STRIKE1 = np.array([0.0, 0.0, -1.0]), np.array([0.0, 0.0, -27.0])


# ---------------------------------------------------------------------------------------------------- the pose
SCHEMA = ([('head', i) for i in range(3)] + [('head_rot', i) for i in range(3)] + [('body', i) for i in range(2)]
          + [('feet', (k, i)) for k in (FN, FF, BN, BF) for i in range(4)]
          + [(k, None) for k in ('tail', 'tail_lift', 'jaw', 'pitch', 'roll', 'yaw', 'squash')])
REST1 = {'squash': 1.0}


def _vec(p):
    out = []
    for k, i in SCHEMA:
        if k == 'feet':
            foot, j = i
            v = (p.get('feet') or {}).get(foot, (0, 0, 0, 0))
            out.append(float(v[j]) if j < len(v) else 0.0)
        elif i is None:
            out.append(float(p.get(k, REST1.get(k, 0.0))))
        else:
            v = p.get(k) or (0.0,) * 3
            out.append(float(v[i]))
    return np.array(out)


def _pose(v):
    p = {'feet': {}}
    for (k, i), x in zip(SCHEMA, v):
        if k == 'feet':
            foot, j = i
            p['feet'].setdefault(foot, [0.0] * 4)[j] = x
        elif i is None:
            p[k] = x
        else:
            p.setdefault(k, [0.0] * (3 if k != 'body' else 2))[i] = x
    p['feet'] = {k: tuple(v) for k, v in p['feet'].items()}
    for k in ('head', 'head_rot', 'body'):
        p[k] = tuple(p[k])
    p['jaw'] = max(0.0, p['jaw'])
    return p


_KV = [(t, _vec(p)) for t, p in JUMP]


def pose_at(t):
    """the pose at t: a cubic (Catmull-Rom on the keys' times) through the keyframes, so the motion carries through
    them rather than stopping at each"""
    ts = [k[0] for k in _KV]
    t = min(max(t, ts[0]), ts[-1])
    i = max(0, min(len(ts) - 2, np.searchsorted(ts, t, side='right') - 1))
    t0, t1 = ts[i], ts[i + 1]
    p0, p1 = _KV[i][1], _KV[i + 1][1]
    pm = _KV[i - 1][1] if i > 0 else p0
    pp = _KV[i + 2][1] if i + 2 < len(_KV) else p1
    tm = ts[i - 1] if i > 0 else t0 - (t1 - t0)
    tp = ts[i + 2] if i + 2 < len(_KV) else t1 + (t1 - t0)
    m0 = (p1 - pm) / (t1 - tm) * (t1 - t0)
    m1 = (pp - p0) / (tp - t0) * (t1 - t0)
    if i == 0:
        m0 = m0 * 0                       # out of the held stance from rest
    if i + 2 >= len(_KV):
        m1 = m1 * 0                       # into the held stance, settling
    u = (t - t0) / (t1 - t0)
    h00, h10, h01, h11 = 2 * u ** 3 - 3 * u ** 2 + 1, u ** 3 - 2 * u ** 2 + u, -2 * u ** 3 + 3 * u ** 2, u ** 3 - u ** 2
    return _pose(h00 * p0 + h10 * m0 + h01 * p1 + h11 * m1)


def faces_at(t):
    """[(state, weight)]: the face, crossfading at each change"""
    cur = FACES[0][1]
    for (t0, f) in FACES[1:]:
        if t < t0:
            break
        if t < t0 + FADE:
            u = (t - t0) / FADE
            u = u * u * (3 - 2 * u)
            return [(cur, 1 - u), (f, u)]
        cur = f
    return [(cur, 1.0)]


def turn_body(ch, R, squash=1.0, pivot=PIVOT, pad=(-26, -14, -44, 26, 48, 40)):
    """the whole character turned by R and squashed (height, volume kept) about pivot, on a larger grid; the face,
    anchors and the head's rig follow"""
    M = ch.model
    S = np.diag([1 / math.sqrt(squash), squash, 1 / math.sqrt(squash)])
    A = np.asarray(R, float) @ S
    Ai = np.linalg.inv(A)
    N = Model(pad[:3], pad[3:], M.mats[1:], res=M.res)
    Q = np.stack([N.X, N.Y, N.Z], -1).reshape(-1, 3)
    src = pivot + (Q - pivot) @ Ai.T
    si = np.floor(src * M.res).astype(int) - M.lo
    ok = np.all((si >= 0) & (si < np.array(M.m.shape)), axis=1)
    flat = np.zeros(len(Q), np.int64)
    flat[ok] = np.ravel_multi_index(si[ok].T, M.m.shape)
    for k in ('m', 'glow', 'layer'):
        a = getattr(M, k).ravel()[flat]
        a[~ok] = 0
        setattr(N, k, a.reshape(N.m.shape).astype(getattr(M, k).dtype))

    def P(p):
        return tuple((pivot + A @ (np.asarray(p, float) - pivot)).tolist())

    def T(v, m):
        w = m @ np.asarray(v, float)
        return tuple((w / np.linalg.norm(w)).tolist())

    def Fr(fr):
        return Frame(center=P(fr.center), n=T(fr.n, Ai.T), up=T(fr.up, A), reach=fr.reach)
    out = dataclasses.replace(ch, model=N, face=Fr(ch.face),
                              pattern_decals=[(Fr(f), e, fn) for f, e, fn in ch.pattern_decals],
                              anchors={k: P(v) for k, v in ch.anchors.items()})
    out.face_squash = (1 / math.sqrt(squash), squash)
    rig = dict(getattr(ch, 'rig', {}))
    rig.pop('head', None)                 # (the old grid's masks)
    rig.pop('fused', None)
    rig['turn'] = (A, np.asarray(pivot, float))      # worn pieces ride the turn too (wear_pose.py)
    out.rig = rig
    return out


def character(p):
    kw = {k: p[k] for k in ('head', 'head_rot', 'body', 'tail', 'tail_lift')}
    kw['feet'] = p['feet']
    if p['jaw'] >= 0.5:
        kw['jaw'] = p['jaw']
    ch = build(2, lo_y=-9, **kw)
    R = head_rotation((p['pitch'], p['yaw'], p['roll']))
    if abs(p['pitch']) + abs(p['roll']) + abs(p['yaw']) > 1e-3 or abs(p['squash'] - 1) > 1e-3:
        ch = turn_body(ch, R, p['squash'])
    return ch


def _feet_pts(model):
    ids = [model.ids[n] for n in ('feet', 'feet_shade', 'claw') if n in model.ids]
    F = np.isin(model.m, ids)
    return np.stack([model.X[F], model.Y[F], model.Z[F]], -1)


def low_foot(model):
    """the lowest point of its feet (the bottom of the voxel), local units"""
    P = _feet_pts(model)
    return float(P[:, 1].min()) - 0.5 / model.res


# ----------------------------------------------------------------------------------------------- the body's path
def _z_at(t):
    """across (z, away from the beam is -): a lean forward as it loads, the push back, constant across in the air,
    a skid to a stop"""
    if t < 0.15:
        u = t / 0.15
        return 0.8 * (u * u * (3 - 2 * u))
    if t < T_OFF:
        u = (t - 0.15) / (T_OFF - 0.15)
        return 0.8 + (Z_OFF - 0.8) * u * u            # accelerating into the push
    if t < T_LAND:
        return Z_OFF + (Z_LAND - Z_OFF) * (t - T_OFF) / (T_LAND - T_OFF)
    v = (Z_LAND - Z_OFF) / (T_LAND - T_OFF)
    ts = 2 * SKID / -v                                 # friction: from its landing speed to rest in SKID
    a = min(t - T_LAND, ts)
    return Z_LAND + v * a - 0.5 * (v / ts) * a * a


_low = {}


def _ground_y(t):
    """how high the model's floor (y 0) is above the ground when its lowest foot stands on it"""
    k = round(t, 4)
    if k not in _low:
        _low[k] = -low_foot(character(pose_at(t)).model)
    return _low[k]


def root_at(t):
    """(x, y, z): where the model's origin is in the world at t"""
    if T_OFF < t < T_LAND:
        s = (t - T_OFF) / (T_LAND - T_OFF)
        y0, y1 = _ground_y(T_OFF), _ground_y(T_LAND)
        y = y0 + (y1 - y0) * s + 4 * H_APEX * s * (1 - s)   # a parabola in time: gravity
    else:
        y = _ground_y(t)
    return np.array([0.0, y, _z_at(t)])


# ------------------------------------------------------------------------------------------- the current jump
# boss_intro sentinel_intro.dart _dodgeReact: the reaction's braced, peak and end frames carried along the arc and
# turned flat on the screen
CUR_LEN = 1.4
CUR_FROM, CUR_TO, CUR_UP = 0.0, -36.0, 35.0
CUR_POSES = {'braced': 0.58, 'peak': 0.06, 'end': 1.80}


def cur_k(u):
    def eo(x):
        return 1 - (1 - x) ** 3

    def ei(x):
        return x ** 3
    if u < 0.12:
        return 0.0
    if u < 0.42:
        return 0.5 * eo((u - 0.12) / 0.3)
    if u < 0.75:
        return 0.5 + 0.12 * (u - 0.42) / 0.33
    if u < 0.95:
        return 0.62 + 0.38 * ei((u - 0.75) / 0.2)
    return 1.0


def cur_state(u):
    """(pose name, screen rotation rad, sx, sy, root (x, y, z))"""
    k = cur_k(u)
    air = 0.12 <= u < 0.95
    land = u - 0.95
    pose = 'braced' if u < 0.12 else ('peak' if air else ('braced' if land < 0.25 else 'end'))
    sx = sy = 1.0
    rot = 0.0
    if 0.12 <= u < 0.2:
        sx, sy = 0.94, 1.08
    elif air:
        rot = -0.32 * math.sin(math.pi * k)
    elif 0 <= land < 0.2:
        c = math.sin(land / 0.2 * math.pi)
        sx, sy = 1 + 0.08 * c, 1 - 0.1 * c
    root = np.array([0.0, CUR_UP * math.sin(math.pi * k), CUR_FROM + (CUR_TO - CUR_FROM) * k])
    return pose, rot, sx, sy, root


def cur_beam(u):
    """the current beam: (on 0..1, strike point)"""
    if u < 0.12 or u >= 1.1:
        return 0.0, STRIKE0
    on = (u - 0.12) / 0.08 if u < 0.2 else ((1.1 - u) / 0.15 if u > 0.95 else 1.0)
    x = min(max((u - 0.2) / 0.85, 0.0), 1.0)
    x = x * x * (3 - 2 * x)
    z = CUR_FROM + (CUR_TO * 0.625 - CUR_FROM) * x if u >= 0.2 else CUR_FROM
    return min(max(on, 0.0), 1.0), np.array([0.0, 0.0, z])


def new_beam(t):
    if t < BEAM_ON or t >= BEAM_OFF + 0.08:
        return 0.0, STRIKE0
    on = (t - BEAM_ON) / (BEAM_HIT - BEAM_ON) if t < BEAM_HIT else (1.0 if t < BEAM_OFF else 1 - (t - BEAM_OFF) / 0.08)
    x = min(max((t - BEAM_HIT) / (BEAM_OFF - BEAM_HIT), 0.0), 1.0)
    x = x * x * (3 - 2 * x)
    strike = STRIKE0 + (STRIKE1 - STRIKE0) * x if t >= BEAM_HIT else STRIKE0
    return min(max(on, 0.0), 1.0), strike


# -------------------------------------------------------------------------------------------------- drawing
CW, CH = 720, 560


def view_fit(cam):
    """one framing per camera for both jumps: the whole of both arcs in the cell"""
    from voxel import model_extent_points
    base = model_extent_points(character(_pose(_vec(STANCE))).model)
    pts = []
    for root in ([0, 0, 0], [0, 0, Z_LAND - SKID], [0, H_APEX + 6, (Z_OFF + Z_LAND) / 2], [0, CUR_UP, CUR_TO / 2],
                 [0, 0, CUR_TO]):
        pts.append(base + np.array(root, float))
    pts = np.concatenate(pts)
    sx, sy, _ = cam.project(pts)
    s = min(CW * 0.9 / (sx.max() - sx.min()), CH * 0.8 / (sy.max() - sy.min()))
    ox = CW / 2 - s * (sx.max() + sx.min()) / 2
    oy = CH * 0.47 - s * (sy.max() + sy.min()) / 2
    return Fit(scale=s, ox=ox, oy=oy, w=CW, h=CH)


def shifted(fit, cam, root):
    p = project_px(cam, fit, [root])[0] - project_px(cam, fit, [[0, 0, 0]])[0]
    return Fit(scale=fit.scale, ox=fit.ox + p[0], oy=fit.oy + p[1], w=fit.w, h=fit.h)


def P2(cam, fit, pts):
    return project_px(cam, fit, np.asarray(pts, float).reshape(-1, 3))


def render_layer(ch, face, cam, fit):
    charrender._surf_cache.clear()
    charrender._quad_cache.clear()
    r = charrender.render_char(ch, PAL, face, cam, fit.w, fit.h, fit=fit)
    return Image.fromarray(r.rgba)


def face_name(state, jaw):
    return '%s:brave:nomouth' % state if jaw >= 3 else state


def background(cam, fit):
    """the arena floor: dark flagstones, lit violet from the beam's side"""
    img = Image.new('RGB', (CW, CH), (28, 20, 44))
    d = ImageDraw.Draw(img)
    for i in range(CH):                                   # the far dark, a violet haze toward the top right
        c = (24 + int(14 * i / CH), 18 + int(8 * i / CH), 40 + int(16 * i / CH))
        d.line([(0, i), (CW, i)], fill=c)
    g = [[x, 0, z] for x in (-400, 400) for z in (-400, 400)]
    q = P2(cam, fit, [g[0], g[1], g[3], g[2]])
    d.polygon([tuple(p) for p in q], fill=(52, 42, 70))
    for v in range(-120, 121, 12):                       # the stones' joints
        a, b = P2(cam, fit, [[v, 0, -400], [v, 0, 400]])
        d.line([tuple(a), tuple(b)], fill=(40, 31, 56), width=2)
        a, b = P2(cam, fit, [[-400, 0, v], [400, 0, v]])
        d.line([tuple(a), tuple(b)], fill=(40, 31, 56), width=2)
    glow = Image.new('L', (CW, CH), 0)
    ImageDraw.Draw(glow).ellipse([CW * 0.55, -CH * 0.5, CW * 1.6, CH * 0.6], fill=80)
    glow = glow.filter(ImageFilter.GaussianBlur(90))
    img = Image.composite(Image.new('RGB', (CW, CH), (150, 110, 230)), img, glow)
    return img.convert('RGBA')


def soft(size, draw_fn, blur):
    L = Image.new('RGBA', size, (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(L))
    return L.filter(ImageFilter.GaussianBlur(blur)) if blur else L


def shadow_layer(cam, fit, root, model_feet, height):
    """its shadow on the floor under it, smaller and fainter the higher it is; and each foot's contact"""
    k = 1 / (1 + max(height, 0) / 22)
    c = P2(cam, fit, [[root[0], 0, root[2] - 3]])[0]
    rx = fit.scale * 15 * (0.55 + 0.45 * k)
    ry = rx * (0.28 if cam is CAM else 0.08)
    a = int(140 * k)

    def dr(d):
        d.ellipse([c[0] - rx, c[1] - ry, c[0] + rx, c[1] + ry], fill=(10, 6, 18, a))
        if model_feet is not None:
            for (x, y, z) in model_feet:
                if y < 1.2:
                    p = P2(cam, fit, [[x, 0, z]])[0]
                    r = fit.scale * 3.2
                    d.ellipse([p[0] - r, p[1] - r * 0.35, p[0] + r, p[1] + r * 0.35], fill=(6, 4, 12, int(170 * (1 - y / 1.2))))
    return soft((CW, CH), dr, 4)


def beam_layer(cam, fit, on, strike, scorch_from, glow_t):
    L = Image.new('RGBA', (CW, CH), (0, 0, 0, 0))
    if glow_t is not None:                                # the scorch it leaves
        a, b = P2(cam, fit, [scorch_from, strike])
        d = ImageDraw.Draw(L)
        d.line([tuple(a), tuple(b)], fill=(18, 10, 26, 200), width=max(3, int(fit.scale * 4)))
        g = soft((CW, CH), lambda d: d.line([tuple(a), tuple(b)], fill=(220, 170, 255, int(200 * glow_t)),
                                            width=max(2, int(fit.scale * 1.6))), 2)
        L = Image.alpha_composite(L, g)
    if on <= 0:
        return L
    e, s = P2(cam, fit, [EYES, strike])
    w = fit.scale * 5.0

    def wide(d):
        d.line([tuple(e), tuple(s)], fill=(160, 110, 255, int(120 * on)), width=int(w * 3.2))
        d.ellipse([s[0] - w * 2.6, s[1] - w * 1.1, s[0] + w * 2.6, s[1] + w * 1.1], fill=(200, 160, 255, int(160 * on)))

    def mid(d):
        d.line([tuple(e), tuple(s)], fill=(214, 180, 255, int(230 * on)), width=int(w * 1.3))

    def core(d):
        d.line([tuple(e), tuple(s)], fill=(255, 250, 255, int(255 * on)), width=max(2, int(w * 0.5)))
    for fn, b in ((wide, 14), (mid, 3), (core, 0)):
        L = Image.alpha_composite(L, soft((CW, CH), fn, b))
    return L


class Particles:
    """dust and chunks in the world: each (birth, life, p0, v, size, kind)"""

    def __init__(self, seed):
        self.rng = np.random.default_rng(seed)
        self.items = []

    def burst(self, t, at, n, speed, up, kind, size, spread_z=1.0, bias=(0, 0, 0), life=0.6):
        for _ in range(n):
            a = self.rng.uniform(0, 2 * math.pi)
            v = np.array([math.cos(a) * speed, up * self.rng.uniform(0.4, 1.0), math.sin(a) * speed * spread_z])
            v = v * self.rng.uniform(0.5, 1.0) + np.array(bias, float)
            p0 = np.asarray(at, float) + np.array([self.rng.uniform(-2, 2), 0.2, self.rng.uniform(-2, 2)])
            self.items.append((t + self.rng.uniform(0, 0.04), life * self.rng.uniform(0.7, 1.2), p0, v,
                               size * self.rng.uniform(0.6, 1.3), kind))

    def at(self, t):
        out = []
        for (b, life, p0, v, sz, kind) in self.items:
            a = t - b
            if a < 0 or a > life:
                continue
            if kind == 'rock':
                p = p0 + v * a + np.array([0, -260, 0]) * a * a / 2
                if p[1] < 0:
                    p[1] = 0
            else:                                          # dust: dragged to a stop, drifting up a little
                k = 5.0
                p = p0 + v * (1 - math.exp(-k * a)) / k + np.array([0, 6 * a, 0])
            out.append((p, a / life, sz, kind))
        return out


def particles_layer(cam, fit, parts):
    L = Image.new('RGBA', (CW, CH), (0, 0, 0, 0))
    D = Image.new('RGBA', (CW, CH), (0, 0, 0, 0))
    d, dd = ImageDraw.Draw(L), ImageDraw.Draw(D)
    for (p, f, sz, kind) in parts:
        q = P2(cam, fit, [p])[0]
        if kind == 'rock':
            r = fit.scale * sz
            d.rectangle([q[0] - r, q[1] - r, q[0] + r, q[1] + r * 0.8], fill=(70, 52, 96, int(255 * (1 - f ** 3))))
        else:
            r = fit.scale * sz * (0.6 + 1.4 * f)
            dd.ellipse([q[0] - r, q[1] - r, q[0] + r, q[1] + r], fill=(222, 206, 186, int(170 * (1 - f) ** 1.5)))
    return Image.alpha_composite(D.filter(ImageFilter.GaussianBlur(2)), L)


def new_particles():
    P = Particles(7)
    # takeoff: the push kicks dust forward from under the front feet, the hind feet's grit after it
    P.burst(0.19, (0, 0, 4), 14, 26, 10, 'dust', 2.2, bias=(0, 0, 18), life=0.7)
    P.burst(0.23, (0, 0, -7), 10, 22, 8, 'dust', 1.8, bias=(0, 0, 10), life=0.6)
    # the beam's strike: chunks of floor thrown up, a ring of dust
    P.burst(BEAM_HIT, STRIKE0, 16, 46, 120, 'rock', 0.9, life=0.9)
    P.burst(BEAM_HIT, STRIKE0, 18, 40, 12, 'dust', 2.6, life=0.8)
    # the landing: dust out from the hind feet, then the front, and a skid trail
    zl = Z_LAND
    P.burst(T_LAND, (0, 0, zl - 7), 14, 30, 9, 'dust', 2.2, life=0.7)
    P.burst(T_LAND + 0.04, (0, 0, zl + 2), 14, 30, 9, 'dust', 2.2, life=0.7)
    for i in range(6):
        P.burst(T_LAND + 0.02 * i, (0, 0, zl - 1.0 * i), 3, 10, 6, 'dust', 1.6, bias=(0, 0, 8), life=0.5)
    return P


def cur_particles():
    P = Particles(9)
    P.burst(0.2, (0, 0, CUR_FROM), 12, 40, 110, 'rock', 0.9, life=0.9)
    P.burst(0.2, (0, 0, CUR_FROM), 16, 40, 12, 'dust', 2.6, life=0.8)
    P.burst(0.95, (0, 0, CUR_TO), 9, 30, 8, 'dust', 2.2, life=0.8)
    return P


def flash_layer(cam, fit, t, at, t0):
    a = t - t0
    if a < 0 or a > 0.35:
        return None
    c = P2(cam, fit, [at])[0]
    r = fit.scale * (6 + 60 * a)
    al = int(200 * (1 - a / 0.35))

    def ring(d):
        d.ellipse([c[0] - r, c[1] - r * (0.3 if cam is CAM else 0.08), c[0] + r, c[1] + r * (0.3 if cam is CAM else 0.08)],
                  outline=(230, 200, 255, al), width=max(2, int(fit.scale * 1.5)))
        rr = fit.scale * 9 * (1 - a / 0.35)
        d.ellipse([c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr], fill=(255, 240, 255, al))
    return soft((CW, CH), ring, 3)


def label(img, text, sub=None):
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([12, 12, 22 + d.textlength(text, font=font(22)), 46], 8, fill=(20, 14, 30, 200))
    d.text((18, 14), text, font=font(22), fill=(238, 226, 255))
    if sub:
        d.text((18, CH - 34), sub, font=font(17, False), fill=(200, 186, 230))


# ------------------------------------------------------------------------------------------------ frames
def improved_frame(args):
    t, vi = args
    name, cam = VIEWS[vi]
    fit = view_fit(cam)
    p = pose_at(t)
    ch = character(p)
    root = root_at(t)
    fs = faces_at(t)
    lay = None
    for state, w in fs:
        L = render_layer(ch, face_name(state, p['jaw']), cam, shifted(fit, cam, root))
        lay = L if lay is None else Image.blend(lay, L, w)
    img = background(cam, fit)
    on, strike = new_beam(t)
    scorch = None if t < BEAM_HIT else max(0.0, 1 - (t - BEAM_OFF) / 0.5) if t > BEAM_OFF else 1.0
    img = Image.alpha_composite(img, beam_layer(cam, fit, 0.0, strike, STRIKE0, scorch) if scorch is not None else
                                Image.new('RGBA', (CW, CH), (0, 0, 0, 0)))
    fl = flash_layer(cam, fit, t, STRIKE0, BEAM_HIT)
    if fl:
        img = Image.alpha_composite(img, fl)
    feet = _feet_pts(ch.model) + root
    img = Image.alpha_composite(img, shadow_layer(cam, fit, root, feet[::7], root[1] + low_foot(ch.model)))
    parts = new_particles().at(t)
    depth = cam.project(np.array([root + PIVOT]))[2][0]
    behind = [q for q in parts if cam.project(np.array([q[0]]))[2][0] >= depth]
    front = [q for q in parts if cam.project(np.array([q[0]]))[2][0] < depth]
    img = Image.alpha_composite(img, particles_layer(cam, fit, behind))
    img = Image.alpha_composite(img, beam_layer(cam, fit, on, strike, STRIKE0, None))
    img = Image.alpha_composite(img, lay)
    img = Image.alpha_composite(img, particles_layer(cam, fit, front))
    ph = next(n for n, a, b in PHASE_SPANS if a <= t < b)
    label(img, 'Improved: ' + ph, '%s camera   t = %.2f s' % (name.split(' ')[0], t))
    return img.convert('RGB')


_cur_cache = {}


def cur_sprite(pose, cam, fit):
    k = (pose, id(cam))
    if k not in _cur_cache:
        t = CUR_POSES[pose]
        pp, face = CR.pose_at(2, t)
        ch = CR.character(2, pp)
        _cur_cache[k] = (render_layer(ch, CR.face_expr(face, pp), cam, fit), ch)
    return _cur_cache[k]


def current_frame(args):
    u, vi = args
    name, cam = VIEWS[vi]
    fit = view_fit(cam)
    pose, rot, sx, sy, root = cur_state(u)
    spr, ch = cur_sprite(pose, cam, fit)
    # the sprite turned and scaled flat on the screen about its feet, then carried to the arc
    o = P2(cam, fit, [[0, 0, 0]])[0]
    sh = P2(cam, fit, [root])[0] - o
    c, s = math.cos(rot), math.sin(rot)
    # forward: q = o + sh + Rot(Scale(p - o)); PIL wants the inverse: p = o + Scale^-1 Rot^-1 (q - o - sh)
    A = np.array([[c / sx, s / sx], [-s / sy, c / sy]])
    b = o - A @ (o + sh)
    lay = spr.transform((CW, CH), Image.AFFINE, (A[0, 0], A[0, 1], b[0], A[1, 0], A[1, 1], b[1]), Image.BICUBIC)
    img = background(cam, fit)
    on, strike = cur_beam(u)
    if u > 0.2:
        g = 1 - min(max((u - 1.05) / 0.4, 0.0), 1.0)
        img = Image.alpha_composite(img, beam_layer(cam, fit, 0.0, strike, np.array([0, 0, CUR_FROM]), g))
    fl = flash_layer(cam, fit, u, np.array([0, 0, CUR_FROM]), 0.2)
    if fl:
        img = Image.alpha_composite(img, fl)
    air = 0.12 <= u < 0.95
    feet = None if air else _feet_pts(ch.model) + root
    k = cur_k(u)
    img = Image.alpha_composite(img, shadow_layer(cam, fit, root, None if feet is None else feet[::7],
                                                  CUR_UP * math.sin(math.pi * k)))
    img = Image.alpha_composite(img, particles_layer(cam, fit, cur_particles().at(u)))
    img = Image.alpha_composite(img, beam_layer(cam, fit, on, strike, None, None))
    img = Image.alpha_composite(img, lay)
    label(img, 'Current', '%s camera   t = %.2f s' % (name.split(' ')[0], u))
    return img.convert('RGB')


def _cell(job):
    kind, t, vi = job
    return (improved_frame if kind == 'new' else current_frame)((t, vi))


def main(out):
    os.makedirs(out, exist_ok=True)
    fdir = os.path.join(out, 'cmp')
    os.makedirs(fdir, exist_ok=True)
    # the phase sheet first (the seven phases, both cameras; the current jump at the matching moments beside)
    cur_at = {'Anticipation': 0.08, 'Takeoff': 0.16, 'Ascent': 0.30, 'Apex': 0.58, 'Descent': 0.85, 'Landing': 1.02,
              'Recovery': 1.40}
    jobs = []
    for vi in range(2):
        for n, t in PHASES:
            jobs.append(('new', t, vi))
            jobs.append(('cur', cur_at[n], vi))
    with ProcessPoolExecutor(WORKERS) as ex:
        cells = list(ex.map(_cell, jobs))
    s = 0.5
    cw, chh = int(CW * s), int(CH * s)
    W, H = 30 + 7 * (cw + 8) + 22, 90 + 4 * (chh + 40) + 10
    sheet = Image.new('RGB', (W, H), (16, 12, 24))
    d = ImageDraw.Draw(sheet)
    d.text((30, 20), 'Juvenile: leaping the Sentinel\'s beam. Improved (articulated, ballistic) over current.',
           font=font(30), fill=(240, 230, 255))
    d.text((30, 58), 'Rows: cinematic camera improved, current; side camera improved, current. Coral, brave faces.',
           font=font(17, False), fill=(190, 176, 220))
    i = 0
    for vi in range(2):
        for j, (n, t) in enumerate(PHASES):
            for r, kind in enumerate(('Improved', 'Current')):
                y = 90 + (vi * 2 + r) * (chh + 40)
                x = 30 + j * (cw + 8)
                sheet.paste(cells[i].resize((cw, chh), Image.LANCZOS), (x, y + 30))
                if vi * 2 + r in (0, 2):
                    d.text((x, y + 4), '%d %s (%.2f s)' % (j + 1, n, t), font=font(18), fill=(240, 230, 255))
                i += 1
    p = os.path.join(out, 'jump_phases.png')
    sheet.save(p, optimize=True)
    print(p, flush=True)
    # the video: both jumps, both cameras; real time, then half speed
    n_new = int(END * FPS) + 1
    n_cur = int(CUR_LEN * FPS) + 1
    n = max(n_new, n_cur) + int(0.3 * FPS)
    jobs = [(k, round(min(i / FPS, END if k == 'new' else CUR_LEN), 4), vi) for i in range(n) for vi in range(2)
            for k in ('cur', 'new')]
    uniq = sorted(set(jobs), key=jobs.index)
    with ProcessPoolExecutor(WORKERS) as ex:
        done = dict(zip(uniq, ex.map(_cell, uniq, chunksize=4)))
    res = [done[j] for j in jobs]
    frames = []
    for i in range(n):
        g = Image.new('RGB', (CW * 2 + 6, CH * 2 + 6), (8, 6, 12))
        for vi in range(2):
            for c, k in enumerate(('cur', 'new')):
                g.paste(res[(i * 2 + vi) * 2 + c], (c * (CW + 6), vi * (CH + 6)))
        frames.append(g)
    order = [frames[i] for i in range(0, n, 2)] + [frames[i] for i in range(n)]
    hold = [frames[0]] * 12
    for k, f in enumerate(hold + order + [frames[-1]] * 20):
        f.save(os.path.join(fdir, '%04d.png' % k))
    mp4 = os.path.join(out, 'jump_compare.mp4')
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-framerate', '30', '-i', os.path.join(fdir, '%04d.png'),
                    '-vf', 'format=yuv420p', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '18', mp4], check=True)
    print(mp4, flush=True)


if __name__ == '__main__':
    main(sys.argv[1])

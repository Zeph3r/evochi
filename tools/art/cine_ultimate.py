"""An Elder's ultimate, the cut-in (the docs: Evochi ultimate cinematics). The middle of a five-beat performance,
pre-rendered: the hero close-up, the 180 degree orbit as the element gathers, the signature release; the
activation (the Wilds darkening, light at its paws) and the payoff (the effect on the battlefield) are the
game's own, live, round it. One sequence per ability; a personality changes the face, the head, the timing and
the size of the movement, never what the ability does.

The Elder is posed from its rig every frame (characters.build), turned and lifted as one body for the rear
(cine_jump.turn_body), and drawn by the game's own renderer from a camera that pushes in, orbits and cuts: the
voxels and colours are the model's own. The element is drawn over and under it in the same camera: ribbons and
droplets that wrap round the body (the half behind it drawn first), a pool of light on the floor, the
release's mist.

    python3 cine_ultimate.py OUT_DIR [ability] [personality,...] [--preview] [--sheet]

Writes ult_<ability>_<personality>.webp (opaque, animated: the game streams it full screen) and ultimates.json
(its rate, size, where the cut-in starts and ends in the ultimate's own time, the release marker). --preview:
also a side-by-side MP4 of the personalities; --sheet: a contact sheet of the beats.
"""
from __future__ import annotations

import json
import math
import os
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from characters import build, head_rotation        # noqa: E402
from voxel import Camera, Fit                       # noqa: E402

STAGE = 3
FPS = 30
W, H = 576, 1248                  # 9:19.5, portrait: the game covers the screen with it
T0, T1 = 0.15, 1.40               # the cut-in, in the ultimate's own time (0: the button)
RELEASE = 1.40                    # the marker: back to the Wilds, the effect resolves
CUT = 1.10                        # the orbit ends; the release is a new angle
FN, FF, BN, BF = (-1, True), (1, True), (-1, False), (1, False)
BODY_C = np.array([0.0, 12.0, -4.0])   # the Elder's middle (its turns, the element's centre)
HIND = np.array([0.0, 0.0, -14.0])      # where it rears from


def ease(u):
    u = min(max(u, 0.0), 1.0)
    return u * u * (3 - 2 * u)


def lerp(a, b, u):
    return a + (b - a) * u


def keyed(keys, t):
    """a value from (time, value) keys, eased between them"""
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, a), (t1, b) in zip(keys, keys[1:]):
        if t <= t1:
            u = ease((t - t0) / (t1 - t0))
            if isinstance(a, tuple):
                return tuple(lerp(x, y, u) for x, y in zip(a, b))
            return lerp(a, b, u)
    return keys[-1][1]


# ---------------------------------------------------------------------------------------------- the abilities
ABILITIES = {
    'healing_mist': dict(palette='ocean', name='Healing Mist',
                         sky=((10, 16, 46), (18, 40, 84)), light=(120, 200, 255), core=(225, 248, 255),
                         lanterns=(255, 196, 120)),
}

# ------------------------------------------------------------------------------- the personalities' performance
# the same beats, performed: amplitude (how big), pace (when the moves land: >1 later), faces (from, state, jaw)
PERFORM = {
    'brave': dict(amp=1.0, lift=1.0, rear=16, head=[(0.15, (6, 0, 0)), (0.55, (-4, 0, 0)), (1.10, (-6, 0, 0)), (1.4, (-10, 0, 0))],
                  faces=[(0.15, 'fierce:brave', 0), (0.60, 'shout:brave', 18), (CUT, 'fierce:brave', 0), (1.16, 'shout:brave', 24)],
                  pace=1.0),
    'calm': dict(amp=0.7, lift=0.85, rear=9, head=[(0.15, (2, 0, 0)), (0.7, (-8, 0, 4)), (1.10, (-6, 0, -2)), (1.4, (-12, 0, 0))],
                 faces=[(0.15, 'serene:calm', 0), (0.86, 'gaze:calm', 0), (CUT, 'serene:calm', 0), (1.18, 'soothe:calm', 8)],
                 pace=1.12),
}


def pose(pers, t):
    """the body at t: where it is (root), how it is turned (rear, about its hind feet), its rig"""
    P = PERFORM[pers]
    a, k = P['amp'], P['pace']
    tt = T0 + (t - T0) / k if t < CUT else t                      # a calm one gathers slower
    lift = keyed([(0.15, 0.0), (0.40, 1.5), (0.80, 7.0), (CUT, 9.0)], tt) * P['lift'] if t < CUT else \
        keyed([(CUT, 6.5), (1.22, 7.5), (1.40, 4.0)], t) * P['lift']
    crouch = keyed([(0.15, -3.4), (0.42, -1.0), (0.8, 0.0)], tt) * a
    tuck = keyed([(0.3, 0.0), (0.8, 2.2), (CUT, 2.6)], tt) * a if t < CUT else 0.0
    rear = keyed([(CUT, 4.0), (1.20, P['rear']), (1.40, P['rear'] * 0.8)], t) if t >= CUT else 0.0
    reach = keyed([(CUT, 1.0), (1.18, 5.5), (1.40, 4.5)], t) * a if t >= CUT else 0.0
    spread = keyed([(CUT, 0.5), (1.20, 2.5)], t) * a if t >= CUT else 0.0
    feet = {
        FN: (tuck + reach, -tuck * 0.6 + reach * 0.4, spread), FF: (tuck + reach, -tuck * 0.6 + reach * 0.4, spread),
        BN: (tuck * 0.7, tuck * 0.5, 0.0), BF: (tuck * 0.7, tuck * 0.5, 0.0),
    }
    head_rot = keyed(P['head'], t)
    tail = keyed([(0.15, 0.0), (0.6, 3.0), (1.0, -2.0), (1.3, 1.0)], t) * a
    tail_lift = keyed([(0.15, 0.0), (0.8, 4.0), (1.25, 6.0)], t) * a
    face, jaw = P['faces'][0][1], P['faces'][0][2]
    for t0, f, j in P['faces']:
        if t >= t0:
            face, jaw = f, j
    # the jaw eases open and shut a little round its keys, so the mouth never snaps
    return dict(root=(0.0, lift, 0.0), rear=rear, feet=feet, body=(crouch, crouch * 0.3), head_rot=head_rot,
                tail=tail, tail_lift=tail_lift, face=face, jaw=jaw)


def character(p):
    import cine_jump as J
    feet = {k: tuple(round(x * 2) / 2 for x in v) for k, v in p['feet'].items()}
    ch = build(STAGE, lo_y=-10, feet=feet, body=p['body'], head_rot=p['head_rot'], tail=p['tail'],
               tail_lift=p['tail_lift'], jaw=p['jaw'])
    if abs(p['rear']) > 0.2:
        ch = J.turn_body(ch, head_rotation((-p['rear'], 0, 0)), 1.0, pivot=HIND, pad=(-32, -16, -56, 32, 62, 46))
    return ch


def face_name(p):
    f = p['face']
    return f + ':nomouth' if p['jaw'] >= 3 and 'nomouth' not in f else f


# ------------------------------------------------------------------------------------------------ the camera
def camera(t):
    """(camera, px per voxel, the point it frames, where on screen): the close-up pushing in, the orbit pulling
    back as it rises, the release from low and in front"""
    if t < 0.40:
        u = (t - T0) / (0.40 - T0)
        return Camera(yaw=lerp(-30, -20, u), pitch=5), lerp(16.0, 18.5, ease(u)), np.array([0.0, 15.5, 26.0]), (0.5, 0.47)
    if t < CUT:
        u = ease((t - 0.40) / (CUT - 0.40))
        target = lerp(np.array([0.0, 15.5, 26.0]), BODY_C + [0, 4, 0], ease(min(1, u * 1.8)))
        return Camera(yaw=lerp(-20, 160, u), pitch=lerp(5, 15, u)), lerp(18.5, 10.5, ease(min(1, u * 1.6))), target, (0.5, lerp(0.47, 0.60, u))
    u = (t - CUT) / (T1 - CUT)
    return Camera(yaw=-14, pitch=lerp(1, 3, u)), lerp(13.0, 12.2, ease(u)), BODY_C + [0, 6, 0], (0.5, 0.56)


def fit_for(cam, scale, target, at, root):
    sx, sy, _ = cam.project(np.array([target + np.array(root) * 0.0], float))
    ox = W * at[0] - sx[0] * scale
    oy = H * at[1] - sy[0] * scale
    # the body rises in the frame (the camera frames its rest point, not the lifted body)
    d = cam.project(np.array([root], float))
    o = cam.project(np.array([[0.0, 0.0, 0.0]], float))
    return Fit(scale, ox + (d[0][0] - o[0][0]) * scale, oy + (d[1][0] - o[1][0]) * scale, W, H)


def px(cam, fit, P):
    sx, sy, z = cam.project(np.asarray(P, float).reshape(-1, 3))
    return np.stack([sx * fit.scale + fit.ox, sy * fit.scale + fit.oy], 1), z


# --------------------------------------------------------------------------------------------- the backdrop
_RUINS = None


def ruins():
    """the Wilds' ruins round the clearing, a ring of blocks (heights per degree) with lit windows"""
    global _RUINS
    if _RUINS is None:
        rng = np.random.default_rng(5)
        hs = np.zeros(360)
        a = 0
        while a < 360:
            w = int(rng.integers(6, 16))
            hs[a:a + w] = rng.uniform(0.16, 0.42) if rng.random() < 0.8 else rng.uniform(0.05, 0.1)
            a += w + int(rng.integers(0, 4))
        lamps = [(float(rng.uniform(0, 360)), float(rng.uniform(0.03, 0.3))) for _ in range(26)]
        _RUINS = hs, lamps
    return _RUINS


def backdrop(ab, cam, t):
    """night over the ruins, turning with the camera (they are far off, so they slide as it orbits)"""
    top, bot = np.array(ab['sky'][0], float), np.array(ab['sky'][1], float)
    v = np.linspace(0, 1, H)[:, None, None]
    img = np.broadcast_to(top + (bot - top) * v, (H, W, 3)).copy()
    hs, lamps = ruins()
    horizon = H * (0.60 - 0.004 * (cam.pitch - 5))
    deg_per_px = 70.0 / W
    xs = np.arange(W)
    ang = (cam.yaw * 1.0 + (xs - W / 2) * deg_per_px) % 360
    height = hs[ang.astype(int) % 360] * H * 0.5
    yy = np.arange(H)[:, None]
    mask = (yy > horizon - height[None, :]) & (yy < horizon + 4)
    ruin = np.array([14, 20, 44], float)
    img[mask] = img[mask] * 0.25 + ruin * 0.75
    glow = np.zeros((H, W, 3))
    for a, hgt in lamps:
        dx = ((a - cam.yaw + 180) % 360 - 180) / deg_per_px + W / 2
        if -20 < dx < W + 20:
            y = horizon - hgt * H * 0.5
            x0, y0 = int(dx), int(y)
            glow[max(0, y0 - 3):y0 + 3, max(0, x0 - 2):x0 + 2] += np.array(ab['lanterns'], float)
    img += ndimage.gaussian_filter(glow, (6, 6, 0)) * 3.0 + glow * 0.6
    # the water floor under the clearing: darker, with the sky's light along it
    floor = yy > horizon + 4
    img[np.broadcast_to(floor, (H, W))] *= 0.55
    if t < 0.40:                  # the close-up: everything behind it soft
        img = ndimage.gaussian_filter(img, (5, 5, 0))
    return img


def floor_light(ab, cam, fit, t, strength):
    """the pool of the element's light on the floor under it, and its ripples"""
    L = np.zeros((H, W, 3))
    c, _ = px(cam, fit, [[0, 0, -4]])
    cx, cy = c[0]
    s = fit.scale
    flat = max(0.12, math.sin(math.radians(max(cam.pitch, 2))) * 1.4)
    im = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(im)
    for k in range(3):
        r = (30 + ((t * 40 + k * 14) % 42)) * s * 0.9
        a = int(160 * (1 - ((t * 40 + k * 14) % 42) / 42))
        d.ellipse([cx - r, cy - r * flat, cx + r, cy + r * flat], outline=a, width=max(2, int(s * 0.5)))
    rings = np.asarray(im, float)[..., None] / 255.0
    yy, xx = np.mgrid[0:H, 0:W]
    pool = np.exp(-(((xx - cx) / (34 * s)) ** 2 + ((yy - cy) / (34 * s * flat)) ** 2) * 2.0)[..., None]
    L += (pool * 0.9 + rings * 0.7) * np.array(ab['light'], float) * strength
    return L


# ------------------------------------------------------------------------------------------- the element
def ribbons(ab, cam, fit, t, root, depth_c, front):
    """the water's ribbons, spiralling round the body as it gathers: drawn twice, behind then in front"""
    grow = keyed([(0.30, 0.0), (0.70, 1.0), (CUT, 1.0)], t) if t < CUT else keyed([(CUT, 1.0), (1.4, 1.0)], t)
    if grow <= 0.01:
        return None
    burst = keyed([(1.14, 0.0), (1.40, 1.0)], t) if t >= CUT else 0.0
    S = 2
    im = Image.new('RGB', (W * S, H * S), (0, 0, 0))
    d = ImageDraw.Draw(im)
    base = BODY_C + np.array(root)
    n = 70
    for k in range(3):
        s = np.linspace(0, 1, n) * grow
        th = t * 6.0 + k * 2 * math.pi / 3 + s * 4.2 * math.pi
        r = (24 + 5 * np.sin(s * 9 + k)) * (1 + burst * 1.4)
        y = -6 + 30 * s + 3 * np.sin(s * 7 + t * 4 + k)
        P = np.stack([base[0] + r * np.cos(th), base[1] + y, base[2] + r * 0.9 * np.sin(th)], 1)
        q, z = px(cam, fit, P)
        q = q * S
        for i in range(n - 1):
            if (z[i] < depth_c) != front:
                continue
            fade = (s[i] / max(grow, 1e-3)) ** 0.6 * (1 - burst * 0.85)
            wdt = (2 + 7 * math.sin(math.pi * s[i] / max(grow, 1e-3))) * fit.scale / 7 * S
            col = tuple(int(c * fade) for c in ab['light'])
            d.line([tuple(q[i]), tuple(q[i + 1])], fill=col, width=max(1, int(wdt)))
            core = tuple(int(c * fade) for c in ab['core'])
            d.line([tuple(q[i]), tuple(q[i + 1])], fill=core, width=max(1, int(wdt * 0.35)))
    return np.asarray(im.resize((W, H), Image.LANCZOS), float)


def droplets(ab, cam, fit, t, root, depth_c, front):
    grow = keyed([(0.25, 0.0), (0.6, 1.0)], t)
    if grow <= 0.01:
        return None
    burst = keyed([(1.14, 0.0), (1.40, 1.0)], t) if t >= CUT else 0.0
    im = Image.new('RGB', (W, H), (0, 0, 0))
    d = ImageDraw.Draw(im)
    rng = np.random.default_rng(9)
    base = BODY_C + np.array(root)
    for i in range(26):
        a0, rr, yy, sp = rng.uniform(0, 2 * math.pi), rng.uniform(18, 34), rng.uniform(-4, 30), rng.uniform(1.5, 3.2)
        a = a0 + t * sp
        r = rr * (1 + burst * 2.2)
        P = base + [r * math.cos(a), yy + burst * 10, r * 0.9 * math.sin(a)]
        q, z = px(cam, fit, [P])
        if (z[0] < depth_c) != front:
            continue
        rad = (0.6 + 0.5 * math.sin(i)) * fit.scale * 0.55 * grow
        x, y = q[0]
        f = 1 - burst * 0.7
        d.ellipse([x - rad, y - rad, x + rad, y + rad], fill=tuple(int(c * f * 0.8) for c in ab['light']))
        d.ellipse([x - rad * 0.35 - rad * 0.2, y - rad * 0.55, x + rad * 0.15, y - rad * 0.05], fill=tuple(int(c * f) for c in ab['core']))
    return np.asarray(im, float)


def release_mist(ab, cam, fit, t, root):
    """the release: mist rolling out toward the camera, and the healing light rising in it"""
    if t < 1.12:
        return None
    u = ease((t - 1.12) / (T1 - 1.12))
    L = np.zeros((H, W, 3))
    c, _ = px(cam, fit, [BODY_C + np.array(root)])
    cx, cy = c[0]
    yy, xx = np.mgrid[0:H, 0:W]
    R = (20 + 220 * u) * fit.scale / 7
    d = np.hypot(xx - cx, (yy - cy) * 1.2)
    ring = np.exp(-((d - R) / (20 + 40 * u)) ** 2)[..., None] * min(1.0, (R / (60 * fit.scale / 7)) ** 2)
    low = np.clip((yy - cy) / (H * 0.25), 0, 1)[..., None]           # the mist hugs the ground: clear over the face
    haze = np.exp(-(d / (R * 1.4 + 1)) ** 2)[..., None] * u * 0.35 * low
    L += (ring * (1 - u * 0.5) * 0.75 + haze) * np.array(ab['light'], float)
    # the healing light: small crosses rising through it
    im = Image.new('RGB', (W, H), (0, 0, 0))
    dr = ImageDraw.Draw(im)
    rng = np.random.default_rng(3)
    for i in range(16):
        x = cx + rng.uniform(-1, 1) * W * 0.45
        y0 = cy + rng.uniform(-0.3, 0.4) * H * 0.4
        y = y0 - u * rng.uniform(60, 180)
        s = rng.uniform(7, 15) * (0.6 + 0.4 * u)
        a = min(1.0, u * 3) * (1 - max(0, u - 0.7) / 0.3 * 0.6)
        col = tuple(int(cc * a) for cc in ab['core'])
        dr.rectangle([x - s * 0.3, y - s, x + s * 0.3, y + s], fill=col)
        dr.rectangle([x - s, y - s * 0.3, x + s, y + s * 0.3], fill=col)
    L += np.asarray(im, float)
    return L


def bloom(L):
    return L + ndimage.gaussian_filter(L, (5, 5, 0)) * 0.9 + ndimage.gaussian_filter(L, (18, 18, 0)) * 0.7


# --------------------------------------------------------------------------------------------- one frame
def frame(args):
    ability, pers, i, t = args
    import charrender
    ab = ABILITIES[ability]
    p = pose(pers, t)
    ch = character(p)
    cam, scale, target, at = camera(t)
    fit = fit_for(cam, scale, target, at, p['root'])
    r = charrender.render_char(ch, ab['palette'], face_name(p), cam, W, H, fit=fit)
    charrender._surf_cache.clear()
    charrender._quad_cache.clear()
    body = r.rgba.astype(float) / 255.0
    a = body[..., 3:4]
    img = backdrop(ab, cam, t) / 255.0
    gather = keyed([(0.15, 0.4), (0.7, 1.0), (CUT, 1.1), (1.25, 1.6), (1.4, 1.0)], t)
    _, depth_c = px(cam, fit, [BODY_C + np.array(p['root'])])
    behind = floor_light(ab, cam, fit, t, gather)
    for f in (ribbons, droplets):
        x = f(ab, cam, fit, t, p['root'], depth_c[0], False)
        if x is not None:
            behind += x
    # an aura round the body: its own light, in the element's colour
    aura = ndimage.gaussian_filter(a[..., 0], 9)[..., None] * np.array(ab['light'], float) * (0.25 + 0.2 * gather)
    img = img + bloom(behind + aura) / 255.0
    # the body: lit a little by its element (the side toward its light picks up the colour)
    tint = 1 + (np.array(ab['light'], float) / 255.0 - 0.5) * 0.12 * gather
    img = img * (1 - a) + np.clip(body[..., :3] * tint, 0, 1) * a
    front = np.zeros((H, W, 3))
    for f in (ribbons, droplets):
        x = f(ab, cam, fit, t, p['root'], depth_c[0], True)
        if x is not None:
            front += x
    m = release_mist(ab, cam, fit, t, p['root'])
    if m is not None:
        front += m
    img = img + bloom(front) / 255.0
    # the cut into the release: a flash of the element's light
    fl = max(0.0, 1 - abs(t - CUT) / 0.05) * 0.8 + max(0.0, 1 - (T1 - t) / 0.05) * 0.35
    if fl > 0:
        img = img + fl * np.array(ab['core'], float) / 255.0
    img = 1 - np.exp(-img * 1.15)                                     # a soft shoulder: light never clips flat
    img = img / (1 - math.exp(-1.15))
    return ability, pers, i, (np.clip(img, 0, 1) * 255).round().astype(np.uint8)


def times():
    n = int(round((T1 - T0) * FPS))
    return [round(T0 + k / FPS, 4) for k in range(n + 1)]


def main(out, ability='healing_mist', perss=('brave', 'calm'), preview=False, sheet=False):
    os.makedirs(out, exist_ok=True)
    ts = times()
    workers = int(os.environ.get('JOBS', '2'))
    jobs = [(ability, pr, i, t) for pr in perss for i, t in enumerate(ts)]
    with ProcessPoolExecutor(workers) as ex:
        res = list(ex.map(frame, jobs))
    frames = {pr: [None] * len(ts) for pr in perss}
    for ab, pr, i, img in res:
        frames[pr][i] = img
    mp = os.path.join(out, 'ultimates.json')
    meta = json.load(open(mp)) if os.path.exists(mp) else {}
    meta.update({'fps': FPS, 'w': W, 'h': H})
    a = meta.setdefault('abilities', {}).setdefault(ability, {})
    a.update({'palette': ABILITIES[ability]['palette'], 'name': ABILITIES[ability]['name'], 't0': T0, 't1': T1,
              'release': RELEASE, 'n': len(ts)})
    v = a.setdefault('variants', {})
    for pr in perss:
        fn = 'ult_%s_%s.webp' % (ability, pr)
        ims = [Image.fromarray(f) for f in frames[pr]]
        ims[0].save(os.path.join(out, fn), save_all=True, append_images=ims[1:], duration=int(round(1000 / FPS)),
                    loop=0, quality=80, method=6)
        v[pr] = fn
        print(fn, '%d KB' % (os.path.getsize(os.path.join(out, fn)) // 1024), flush=True)
    json.dump(meta, open(mp, 'w'), indent=1)
    if sheet:
        beats = [0.20, 0.36, 0.50, 0.70, 0.90, 1.06, 1.16, 1.26, 1.36]
        cw, chh = W // 3, H // 3
        S = Image.new('RGB', (cw * len(beats), chh * len(perss)))
        for r_, pr in enumerate(perss):
            for c_, b in enumerate(beats):
                i = min(range(len(ts)), key=lambda k: abs(ts[k] - b))
                S.paste(Image.fromarray(frames[pr][i]).resize((cw, chh), Image.LANCZOS), (c_ * cw, r_ * chh))
        S.save(os.path.join(out, 'ult_%s_sheet.png' % ability))
    if preview:
        side = os.path.join(out, 'ult_%s_preview.mp4' % ability)
        p = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s',
                              '%dx%d' % (W * len(perss) // 2 * 2, H), '-r', str(FPS), '-i', '-', '-vf', 'scale=-2:900',
                              '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', '-pix_fmt', 'yuv420p', side],
                             stdin=subprocess.PIPE)
        hold = [frames[pr][0] for pr in perss]
        dark = [(f.astype(float) * 0.25).astype(np.uint8) for f in hold]
        seq = [dark] * 6 + [[frames[pr][i] for pr in perss] for i in range(len(ts))] + [[frames[pr][-1] for pr in perss]] * 10
        for row in seq * 2:
            p.stdin.write(np.concatenate(row, 1).tobytes())
        p.stdin.close()
        p.wait()
        print(side, flush=True)


if __name__ == '__main__':
    a = [x for x in sys.argv[1:] if not x.startswith('--')]
    main(a[0], a[1] if len(a) > 1 else 'healing_mist', tuple(a[2].split(',')) if len(a) > 2 else ('brave', 'calm'),
         '--preview' in sys.argv, '--sheet' in sys.argv)

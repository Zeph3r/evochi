"""Pip and Mira acting their lines, frame by frame (flutter/lib/features/onboarding/posed_plate.dart plays them).

The poses before were a handful of stills cut in turn (a nod down, a nod up, back): heads that jumped. Here a
line is performed as motion: the body breathes, the head moves on the stressed words and settles, the mouth (Pip's
beak) shapes the syllables as the words type out, a warm close at the end, and a breathing idle that loops. The
shot is rendered once at rest (the plate) and then, in only the character's box, once per frame (cine_blender.
render_anim, on the PC's GPU); this grades each frame against the plate, cuts the box with a feathered edge and
writes each clip as an animated WebP beside the plate.

    python3 cine_anim.py RAW_DIR PACK_DIR ../../flutter/assets/art/cine pip_anim:pip mira_anim:mira
"""
from __future__ import annotations

import json
import math
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

FPS = 15
# the SpeechCard types about 38 characters a second after a short delay (cinematic_player.dart): the words are
# spoken over the same time, a little slower, as if read aloud
CPS = 34.0


def _syllables(text):
    """(start s, end s, vowel class) per syllable-ish chunk, and the pauses at punctuation, spoken at CPS"""
    out = []
    t = 0.0
    for word in re.findall(r"[A-Za-z']+|[,.!?]", text):
        if word in ',.!?':
            t += {',': 0.18, '.': 0.32, '!': 0.32, '?': 0.32}[word]
            out.append((None, t))
            continue
        chunks = re.findall(r"[^aeiouy]*[aeiouy]+(?:[^aeiouy]*$)?", word.lower()) or [word.lower()]
        dur = max(0.13, len(word) / CPS) / len(chunks)
        for c in chunks:
            v = re.search(r'[aeiouy]', c)
            cls = {'a': 'talk_a', 'o': 'talk_o', 'u': 'talk_o', 'e': 'talk_e', 'i': 'talk_e', 'y': 'talk_e'}[v.group(0)] if v else 'talk_e'
            out.append(((t, t + dur * 0.8, cls), None))
            t += dur
        t += 0.03
    return out, t


def _bump(t, at, rise=0.08, fall=0.28):
    """0 -> 1 at `at` over `rise`, back over `fall` (an accent)"""
    if t < at - rise or t > at + fall:
        return 0.0
    if t < at:
        u = (t - (at - rise)) / rise
        return u * u * (3 - 2 * u)
    u = (t - at) / fall
    return (1 - u) ** 2


def _ease(u):
    u = min(1.0, max(0.0, u))
    return u * u * (3 - 2 * u)


def _lerp3(a, b, k):
    return tuple(a[i] + (b[i] - a[i]) * k for i in range(3))


def _talk(text, start, face_end=None):
    """per time: the mouth shape at t (None: closed), and the accents (word starts) for the head"""
    syl, total = _syllables(text)
    spans = [(s + start, e + start, c) for item in syl if item[0] for (s, e, c) in [item[0]]]
    words = []
    t = start
    for item in syl:
        if item[0] and (not words or item[0][0] + start - words[-1] > 0.22):
            words.append(item[0][0] + start)

    def mouth(t):
        for s, e, c in spans:
            if s <= t < e:
                # open in the middle of the syllable, half open at its edges
                return c if (t - s) > 0.03 and (e - t) > 0.03 else 'talk_e'
        return None
    return mouth, words, start + total


def _key(t, keys):
    """a keyed value at t: keys [(time, value, ease)], value a number or a tuple; ease 'smooth' (in and out),
    'out' (decelerating), 'back' (past the mark and settling back: follow-through), 'hold' (a step)"""
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, v0, *_), (t1, v1, *e) in zip(keys, keys[1:]):
        if t <= t1:
            u = (t - t0) / max(1e-6, t1 - t0)
            ease = e[0] if e else 'smooth'
            if ease == 'hold':
                k = 0.0 if u < 1 else 1.0
            elif ease == 'out':
                k = 1 - (1 - u) ** 3
            elif ease == 'back':
                c = 1.9
                k = 1 + (c + 1) * (u - 1) ** 3 + c * (u - 1) ** 2
            else:
                k = u * u * (3 - 2 * u)
            if isinstance(v0, tuple):
                return tuple(a + (b - a) * k for a, b in zip(v0, v1))
            return v0 + (v1 - v0) * k
    return keys[-1][1]


def _add(*vs):
    return tuple(sum(x) for x in zip(*vs))


def perf_mira():
    """'I've been keeping these warm. One of them has been waiting for you.' Each beat led by the eyes, then the
    head, then the body, the pot settling last: at 'these warm' a look down at the eggs (eyes first), the pot
    offered toward them; back to you (eyes first again) for 'one of them', leaning in a little; a warm squint
    and a tilt at 'waiting for you'; settling back to rest"""
    rest = {'pose': {'head': (0.0, 8.0, 0.0), 'arm': (0.0, 0.0, 0.0)}, 'face': 'default', 'breath': 0.0}
    line = "I've been keeping these warm. One of them has been waiting for you."
    S = 0.25
    mouth, words, end = _talk(line, S)
    warm0 = S + _syllables("I've been keeping")[1]              # 'these warm'
    back0 = S + _syllables("I've been keeping these warm.")[1]  # 'One of them'
    wait0 = end - 0.95                                          # 'waiting for you'
    head_k = [(0.0, (0.0, 8.0, 0.0)), (warm0 + 0.05, (0.0, 8.0, 0.0)), (warm0 + 0.42, (12.0, 15.0, 6.0), 'back'),
              (back0 - 0.05, (11.0, 14.0, 5.0)), (back0 + 0.38, (-1.0, 7.0, -1.0), 'back'), (wait0, (0.0, 8.0, 0.0)),
              (wait0 + 0.35, (3.0, 10.0, 7.0), 'back'), (end + 0.45, (3.0, 10.0, 7.0)), (end + 0.95, (0.0, 8.0, 0.0))]
    arm_k = [(0.0, (0.0, 0.0, 0.0)), (warm0 + 0.15, (0.0, 0.0, 0.0)), (warm0 + 0.55, (-9.0, 0.0, -3.0), 'back'),
             (back0 + 0.1, (-8.0, 0.0, -3.0)), (back0 + 0.65, (0.0, 0.0, 0.0), 'back')]
    lean_k = [(0.0, (0.0, 0.0)), (warm0 + 0.1, (0.0, 0.0)), (warm0 + 0.5, (2.0, 1.5)), (back0, (2.0, 1.5)),
              (back0 + 0.45, (3.5, 0.0)), (end + 0.3, (3.0, -1.0)), (end + 0.95, (0.0, 0.0))]
    frames = []
    n = int(round((end + 1.0) * FPS))
    for i in range(n):
        t = i / FPS
        nod = sum(_bump(t, w, 0.07, 0.3) for w in words if not (warm0 - 0.05 < w < back0 + 0.3))
        head = _add(_key(t, head_k), (1.6 * nod + 0.5 * math.sin(t * 2.1), 0.8 * math.sin(t * 0.9), 0.8 * math.sin(t * 1.3 + 0.4)))
        m = mouth(t)
        if warm0 - 0.12 <= t < back0 - 0.12:
            face = 'look_dr' if not m else m      # eyes on the eggs (the words go on)
        elif t >= wait0 and t < end:
            face = 'talk_happy' if m else 'happy'
        elif end <= t < end + 0.5:
            face = 'happy'
        else:
            face = m or 'default'
        frames.append({'pose': {'head': head, 'arm': _key(t, arm_k)}, 'face': face, 'lean': _key(t, lean_k),
                       'breath': 0.012 * math.sin(t * 2 * math.pi / 3.2) + 0.005 * nod})
    idle = _idle(rest, 18, blink_at=None)
    return {'actor': 'mira', 'fps': FPS, 'rest': rest, 'clips': {'talk': frames, 'idle': idle},
            'faces': ['blink', 'happy', 'talk_a', 'talk_o', 'talk_e', 'talk_happy', 'look_dr'], 'speech_at': S}


def perf_pip():
    """'Pip the Courier, at your service! Where should I deliver your letters?' First the letter: his eyes go
    to it, then his head, he dips and lifts it high (the wing overshooting, the letter settling last), leans in
    and looks back at you; then he talks, a hop at 'service!', a curious tilt with the letter held out to you on
    the question, and settles"""
    rest = {'pose': {'head': (0.0, 0.0, 0.0), 'arm': (0.0, 0.0, 0.0), 'jaw': (0.0, 0.0, 0.0)}, 'face': 'default', 'breath': 0.0}
    line = 'Pip the Courier, at your service! Where should I deliver your letters?'
    S = 1.05
    mouth, words, end = _talk(line, S)
    serv = S + _syllables('Pip the Courier, at your')[1] + 0.12
    ask = S + _syllables('Pip the Courier, at your service! Where should I deliver your')[1]
    head_k = [(0.0, (0.0, 0.0, 0.0)), (0.18, (0.0, 0.0, 0.0)), (0.48, (-7.0, -11.0, -5.0), 'back'), (0.70, (-7.0, -11.0, -5.0)),
              (0.98, (1.0, 3.0, 1.0), 'back'), (ask - 0.25, (0.0, 2.0, 0.0)), (ask + 0.2, (-1.0, 6.0, 9.0), 'back'),
              (end + 0.25, (-1.0, 6.0, 9.0)), (end + 0.7, (0.0, 0.0, 0.0))]
    arm_k = [(0.0, (0.0, 0.0, 0.0)), (0.32, (0.0, 0.0, 2.0)), (0.62, (4.0, 0.0, -17.0), 'back'), (0.95, (3.0, 0.0, -13.0)),
             (S + 0.6, (1.0, 0.0, -5.0)), (ask - 0.2, (1.0, 0.0, -5.0)), (ask + 0.25, (11.0, 0.0, -13.0), 'back'),
             (end + 0.3, (10.0, 0.0, -12.0)), (end + 0.75, (0.0, 0.0, 0.0), 'back')]
    lean_k = [(0.0, (0.0, 0.0)), (0.30, (-1.5, 0.0)), (0.62, (-2.5, 1.0)), (0.95, (3.0, 0.0), 'back'), (S + 0.5, (1.0, 0.0)),
              (ask - 0.2, (1.0, 0.0)), (ask + 0.25, (4.5, -1.5), 'back'), (end + 0.3, (4.0, -1.5)), (end + 0.75, (0.0, 0.0))]
    frames = []
    n = int(round((end + 0.8) * FPS))
    for i in range(n):
        t = i / FPS
        nod = sum(_bump(t, w, 0.06, 0.24) for w in words)
        hop = _bump(t, serv, 0.12, 0.34)
        dip = _bump(t, 0.36, 0.12, 0.18)        # the little crouch before he lifts it
        head = _add(_key(t, head_k), (2.0 * nod - 3.0 * hop, 1.5 * math.sin(t * 1.7), 1.2 * math.sin(t * 2.3)))
        arm = _add(_key(t, arm_k), (1.5 * math.sin(t * 3.1) + 4.0 * hop, 0.0, -1.5 * math.sin(t * 3.1 + 0.6) - 6.0 * hop))
        m = mouth(t)
        jaw = {'talk_a': 18.0, 'talk_o': 14.0, 'talk_e': 11.0}.get(m, 0.0)
        if 0.10 <= t < 0.74:
            face = 'look_ul'        # his eyes on the letter first
        elif hop > 0.5:
            face = 'happy'
        else:
            face = 'default'
        frames.append({'pose': {'head': head, 'arm': arm, 'jaw': (jaw, 0.0, 0.0)}, 'face': face, 'lean': _key(t, lean_k),
                       'breath': 0.015 * math.sin(t * 2 * math.pi / 2.4) + 0.025 * hop - 0.03 * dip, 'lift': 0.9 * hop})
    idle = _idle(rest, 30, blink_at=1.2, arm_bob=True)
    return {'actor': 'pip', 'fps': FPS, 'rest': rest, 'clips': {'talk': frames, 'idle': idle}, 'faces': ['blink', 'happy', 'look_ul'],
            'speech_at': S}


def _idle(rest, n, blink_at=None, arm_bob=False):
    """a breathing loop of n frames (the end meets the start), the head drifting a little, a blink"""
    out = []
    period = n / FPS
    for i in range(n):
        t = i / FPS
        w = 2 * math.pi * t / period
        pose = {p: tuple(v) for p, v in rest['pose'].items()}
        h = pose.get('head', (0.0, 0.0, 0.0))
        pose['head'] = (h[0] + 0.8 * math.sin(w + 0.6), h[1] + 1.0 * math.sin(w), h[2] + 0.8 * math.sin(w + 1.7))
        if arm_bob and 'arm' in pose:
            a = pose['arm']
            pose['arm'] = (a[0] + 1.5 * math.sin(w + 0.3), a[1], a[2] - 1.5 * math.sin(w + 0.3))
        face = 'blink' if blink_at is not None and abs(t - blink_at) < 0.07 else 'default'
        out.append({'pose': pose, 'face': face, 'breath': 0.012 * math.sin(w)})
    return out


PERFS = {'mira': perf_mira, 'pip': perf_pip}

# ------------------------------------------------------------------------------------------------ assemble ----
FEATHER = 16   # packed px
INK = (59, 41, 35)    # village_npcs.INK: the line the villagers are drawn in everywhere else


def ink(mask, depth, unit_m, zmax):
    """the villagers' ink on an acted frame, as the game draws it round its sprites (charrender: an outline
    round the silhouette, thinner lines inside where a part stands in front of another): from the actor's own
    coverage `mask` (0-1) and the scene's depth (metres). The outline goes only onto what is behind them, never
    onto what stands in front (the eggs before Mira). Returns the ink's alpha (0-1)."""
    from scipy import ndimage
    act = mask > 0.5
    if not act.any():
        return np.zeros_like(mask)
    ys = np.nonzero(act.any(1))[0]
    w = max(2.0, 0.011 * (ys.max() - ys.min()))           # the outline: bold, as the small sprites read in the game
    dist, (iy, ix) = ndimage.distance_transform_edt(~act, return_indices=True)
    near = depth[iy, ix]                                    # the actor's depth at its nearest pixel
    behind = (depth > near + 0.6 * unit_m) | (depth >= zmax * 0.999)
    ring = np.clip(w + 0.5 - dist, 0, 1) * behind * (dist > 0)
    # inside: a step in depth (a part standing in front of another): between neighbouring pixels the depth jumps
    # by more than the surface's own slope carries it, by over ~2 model units (charrender's inner lines); the
    # line on the far side, a third of the outline's width
    inner = np.zeros(act.shape, bool)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        d1 = np.roll(depth, (dy, dx), (0, 1))          # the neighbour on the near side
        d2 = np.roll(depth, (2 * dy, 2 * dx), (0, 1))  # and the one past it (its slope)
        a1 = np.roll(act, (dy, dx), (0, 1))
        jump = (depth - d1) - np.maximum(0, d1 - d2)
        inner |= act & a1 & (jump > 2.2 * unit_m)
    r = max(1, int(round(w * 0.3)))
    inner = ndimage.binary_dilation(inner, iterations=max(0, r - 1)) & act if r > 1 else inner
    inner = ndimage.gaussian_filter(inner.astype(np.float32), 0.6) * 1.6
    a = np.maximum(ring, np.clip(inner, 0, 1) * 0.85)
    return np.clip(ndimage.gaussian_filter(a, 0.45), 0, 1)


def assemble(raw_dir, pack_dir, out_dir, scene, plate, cap):
    """grade the rest render (the plate) and every frame of every clip (pasted into the rest render, graded whole,
    so light and grain match), cut the box, write <plate>.webp, <plate>_<clip>.webp and the entries in cine.json
    and cine_poses.json"""
    from PIL import Image
    import cine_blender as CB
    import cine_pack
    vs = cine_pack.unpack(os.path.join(pack_dir, scene + '.npz'))
    meta = json.load(open(os.path.join(raw_dir, scene + '_meta.json')))
    an = meta['anim']
    x0, y0, x1, y1 = an['box']
    base = np.asarray(Image.open(os.path.join(raw_dir, scene + '_raw.png')).convert('RGBA')).astype(np.float32)
    H, W = base.shape[:2]
    zp0 = os.path.join(raw_dir, scene + '_z.exr')
    zb = CB.read_depth(zp0) if vs.grade.get('mist') and os.path.exists(zp0) else None   # (only the haze uses depth)
    k = min(1.0, cap / max(W, H))
    size = (round(W * k), round(H * k))

    inked = bool(an.get('ink'))

    def passes(fname, shape, at):
        """the frame's ink alpha, full size (the frame's own passes cover only its box at [at])"""
        mp, dp = os.path.join(raw_dir, fname + '_m.png'), os.path.join(raw_dir, fname + '_d.png')
        if not (inked and os.path.exists(mp) and os.path.exists(dp)):
            return None
        m = np.asarray(Image.open(mp).convert('F'), np.float32) / 255.0
        d = np.asarray(Image.open(dp), np.float32)
        d = d / (65535.0 if d.max() > 255 else 255.0) * an['zmax']
        a = ink(m, d, an['unit_m'], an['zmax'])
        out = np.zeros(shape, np.float32)
        hh, ww = min(a.shape[0], shape[0] - at[1]), min(a.shape[1], shape[1] - at[0])
        out[at[1]:at[1] + hh, at[0]:at[0] + ww] = a[:hh, :ww]
        return out

    def grade(rgba, z, a=None):
        g = CB.grade_image(rgba, z, vs.grade, W, H, sky=vs.sky, transparent=vs.transparent)[..., :3]
        if a is not None:
            g = g * (1 - a[..., None]) + np.array(INK, np.float32) * a[..., None]
        return Image.fromarray(np.clip(g, 0, 255).astype(np.uint8))
    plate_im = grade(base, zb, passes(scene, (H, W), (0, 0))).resize(size, Image.LANCZOS)
    plate_im.save(os.path.join(out_dir, plate + '.webp'), 'WEBP', quality=82, method=6)
    # the box in packed px, inside the picture
    bx0, by0 = int(x0 * k), int(y0 * k)
    bx1, by1 = min(size[0], int(math.ceil(x1 * k))), min(size[1], int(math.ceil(y1 * k)))
    bw, bh = bx1 - bx0, by1 - by0
    yy, xx = np.mgrid[0:bh, 0:bw].astype(np.float32)
    big = np.full_like(xx, 1e9)
    d = np.minimum(np.minimum(xx if bx0 > 0 else big, (bw - 1 - xx) if bx1 < size[0] else big),
                   np.minimum(yy if by0 > 0 else big, (bh - 1 - yy) if by1 < size[1] else big))
    a = np.clip(d / FEATHER, 0, 1)
    alpha = Image.fromarray((a * a * (3 - 2 * a) * 255).astype(np.uint8))
    anims = {}
    for clip, n in an['clips'].items():
        cells = []
        for i in range(n):
            fname = '%s_%s_%03d' % (scene, clip, i)
            im = np.asarray(Image.open(os.path.join(raw_dir, fname + '_raw.png')).convert('RGBA')).astype(np.float32)
            fr = base.copy()
            h_, w_ = min(im.shape[0], H - y0), min(im.shape[1], W - x0)
            fr[y0:y0 + h_, x0:x0 + w_] = im[:h_, :w_]
            z = None if zb is None else zb.copy()
            zp = os.path.join(raw_dir, fname + '_z.exr')
            if z is not None and os.path.exists(zp):
                zf = CB.read_depth(zp)
                if zf.shape == zb.shape:
                    z = zf
                else:
                    z[y0:y0 + min(zf.shape[0], h_), x0:x0 + min(zf.shape[1], w_)] = zf[:h_, :w_]
            cell = grade(fr, z, passes(fname, (H, W), (x0, y0))).resize(size, Image.LANCZOS).crop((bx0, by0, bx1, by1)).convert('RGBA')
            cell.putalpha(alpha)
            cells.append(cell)
        fn = '%s_%s.webp' % (plate, clip)
        cells[0].save(os.path.join(out_dir, fn), 'WEBP', save_all=True, append_images=cells[1:], duration=round(1000 / an['fps']),
                      loop=0, quality=80, method=4, minimize_size=False)
        anims[clip] = {'file': fn, 'n': n}
        print(f'{plate} {clip}: {n} frames -> {fn} {os.path.getsize(os.path.join(out_dir, fn)) // 1024} KB', flush=True)
    cj = os.path.join(out_dir, 'cine.json')
    cm = json.load(open(cj))
    kk = size[0] / meta['w']
    cm[plate] = {'w': size[0], 'h': size[1], 'anchors': {n: [round(v[0] * kk, 1), round(v[1] * kk, 1)] for n, v in meta.get('anchors', {}).items()},
                 'lines': {}, 'scale': 1.0}
    json.dump(cm, open(cj, 'w'), indent=1)
    pj = os.path.join(out_dir, 'cine_poses.json')
    pm = json.load(open(pj))
    opening_at = (pm.get(plate, {}).get('idle') or {}).get('opening_at', 0.3)
    pm[plate] = {'box': [bx0, by0, bw, bh], 'anims': anims, 'fps': an['fps'], 'idle': {'opening': 'talk', 'opening_at': opening_at}}
    json.dump(pm, open(pj, 'w'), indent=1)


if __name__ == '__main__':
    raw_dir, pack_dir, out_dir = sys.argv[1:4]
    caps = {'pip': 1800, 'mira': 1600}
    for spec in sys.argv[4:]:
        scene, plate = spec.split(':')
        assemble(raw_dir, pack_dir, out_dir, scene, plate, caps.get(plate, 1600))

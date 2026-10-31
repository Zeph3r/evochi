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


def perf_mira():
    """'I've been keeping these warm. One of them has been waiting for you.' turned to you, a nod on the words, the
    pot lifted a little at 'these warm', a warm squint and a tilt at 'waiting for you', settling back"""
    rest = {'pose': {'head': (0.0, 8.0, 0.0), 'arm': (0.0, 0.0, 0.0)}, 'face': 'default', 'breath': 0.0}
    line = "I've been keeping these warm. One of them has been waiting for you."
    mouth, words, end = _talk(line, 0.12)
    warm_at = end - 0.95       # 'waiting for you'
    frames = []
    n = int(round((end + 0.8) * FPS))
    for i in range(n):
        t = i / FPS
        nod = sum(_bump(t, w, 0.07, 0.3) for w in words[:-3])
        tilt = _ease((t - warm_at) / 0.35) * (1 - _ease((t - end - 0.45) / 0.5))
        head = (1.8 * nod + 0.6 * math.sin(t * 2.1) + 3.0 * tilt, 8.0 + 2.0 * math.sin(t * 0.9) + 2.0 * tilt,
                1.2 * math.sin(t * 1.3 + 0.4) + 6.0 * tilt)
        lift = _ease((t - 0.7) / 0.4) * (1 - _ease((t - 1.6) / 0.6))       # 'these warm': the pot a little up
        arm = (-5.0 * lift + 1.5 * tilt, 0.0, 0.0)
        m = mouth(t)
        if t >= warm_at and t < end:
            face = 'talk_happy' if m else 'happy'
        elif t >= end and tilt > 0.35:
            face = 'happy'
        else:
            face = m or 'default'
        frames.append({'pose': {'head': head, 'arm': arm}, 'face': face, 'breath': 0.012 * math.sin(t * 2 * math.pi / 3.2) + 0.006 * nod})
    # ease the last frames back to rest (the idle starts there)
    for k in range(6):
        f = frames[-6 + k]
        u = _ease((k + 1) / 6)
        f['pose'] = {p: _lerp3(v, rest['pose'][p], u) for p, v in f['pose'].items()}
        f['breath'] *= 1 - u
        if k >= 3:
            f['face'] = 'default'
    idle = _idle(rest, 18, blink_at=None)
    return {'actor': 'mira', 'fps': FPS, 'rest': rest, 'clips': {'talk': frames, 'idle': idle},
            'faces': ['blink', 'happy', 'talk_a', 'talk_o', 'talk_e', 'talk_happy']}


def perf_pip():
    """'Pip the Courier, at your service! Where should I deliver your letters?' bright and bouncy: a hop at
    'service!', the beak working, a curious tilt on the question with the letter held out to you"""
    rest = {'pose': {'head': (0.0, 0.0, 0.0), 'arm': (0.0, 0.0, 0.0), 'jaw': (0.0, 0.0, 0.0)}, 'face': 'default', 'breath': 0.0}
    line = 'Pip the Courier, at your service! Where should I deliver your letters?'
    mouth, words, end = _talk(line, 0.12)
    serv = 0.12 + _syllables('Pip the Courier, at your')[1] + 0.12    # the stress of 'service'
    ask = 0.12 + _syllables('Pip the Courier, at your service! Where should I deliver your')[1]
    frames = []
    n = int(round((end + 0.7) * FPS))
    for i in range(n):
        t = i / FPS
        nod = sum(_bump(t, w, 0.06, 0.24) for w in words)
        hop = _bump(t, serv, 0.12, 0.34)
        q = _ease((t - ask + 0.25) / 0.4) * (1 - _ease((t - end - 0.2) / 0.45))     # the question: tilt, letter out
        head = (2.2 * nod - 3.0 * hop - 1.0 * q, 2.0 * math.sin(t * 1.7) + 4.0 * q, 1.5 * math.sin(t * 2.3) + 8.0 * q)
        arm = (2.0 * math.sin(t * 3.1) + 10.0 * q + 4.0 * hop, 0.0, -2.0 * math.sin(t * 3.1 + 0.6) - 12.0 * q - 6.0 * hop)
        m = mouth(t)
        jaw = {'talk_a': 18.0, 'talk_o': 14.0, 'talk_e': 11.0}.get(m, 0.0)
        face = 'happy' if hop > 0.5 else 'default'
        frames.append({'pose': {'head': head, 'arm': arm, 'jaw': (jaw, 0.0, 0.0)}, 'face': face,
                       'breath': 0.015 * math.sin(t * 2 * math.pi / 2.4) + 0.025 * hop - 0.012 * _bump(t, serv - 0.2, 0.08, 0.1),
                       'lift': 0.9 * hop})
    for k in range(5):
        f = frames[-5 + k]
        u = _ease((k + 1) / 5)
        f['pose'] = {p: _lerp3(v, rest['pose'][p], u) for p, v in f['pose'].items()}
        f['breath'] *= 1 - u
        f['lift'] *= 1 - u
    idle = _idle(rest, 30, blink_at=1.2, arm_bob=True)
    return {'actor': 'pip', 'fps': FPS, 'rest': rest, 'clips': {'talk': frames, 'idle': idle}, 'faces': ['blink', 'happy']}


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
    zb = CB.read_depth(os.path.join(raw_dir, scene + '_z.exr'))
    k = min(1.0, cap / max(W, H))
    size = (round(W * k), round(H * k))

    def grade(rgba, z):
        g = CB.grade_image(rgba, z, vs.grade, W, H, sky=vs.sky, transparent=vs.transparent)
        return Image.fromarray(np.clip(g[..., :3], 0, 255).astype(np.uint8))
    plate_im = grade(base, zb).resize(size, Image.LANCZOS)
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
            z = zb.copy()
            zp = os.path.join(raw_dir, fname + '_z.exr')
            if os.path.exists(zp):
                zf = CB.read_depth(zp)
                if zf.shape == zb.shape:
                    z = zf
                else:
                    z[y0:y0 + min(zf.shape[0], h_), x0:x0 + min(zf.shape[1], w_)] = zf[:h_, :w_]
            cell = grade(fr, z).resize(size, Image.LANCZOS).crop((bx0, by0, bx1, by1)).convert('RGBA')
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

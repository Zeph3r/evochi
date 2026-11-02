"""Encode a long Shorts-recorder take (frames.rgba, meta.json, cues.json) in pieces, each short enough for one
call: video segments straight from the raw frames, the sound mix (as tools/shorts/encode.py lays it), then the
segments joined under the mix.

    python3 encode_parts.py seg   DIR I0 I1 OUT.mp4      frames [I0, I1) as H.264
    python3 encode_parts.py audio DIR GAME_ROOT OUT.f32  the game's sounds where they happened (48 kHz stereo f32)
    python3 encode_parts.py join  DIR OUT.mp4 SEG...     the segments in order, under DIR/mix.f32
"""
import json
import os
import subprocess
import sys

import numpy as np

SR = 48000


def meta(d):
    return json.load(open(os.path.join(d, 'meta.json')))


def seg(d, i0, i1, out):
    m = meta(d)
    w, h, fps = m['w'], m['h'], m['fps']
    size = w * h * 4
    i1 = min(int(i1), m['frames'])
    p = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', f'{w}x{h}', '-r', str(fps), '-i', '-',
                          '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '19', '-pix_fmt', 'yuv420p', '-r', str(fps), out], stdin=subprocess.PIPE)
    with open(os.path.join(d, 'frames.rgba'), 'rb') as f:
        f.seek(int(i0) * size)
        for _ in range(int(i0), i1):
            b = f.read(size)
            if len(b) < size:
                break
            p.stdin.write(b)
    p.stdin.close()
    p.wait()
    print(out, i1 - int(i0), 'frames')


def decode(path):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'], check=True, capture_output=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).copy()



def lay_score(mix, cues, sound, sr):
    """the score's cues (AudioService.cue): each plays from its moment, once or as a loop (a pass every 'loop' s,
    each ringing on), until the next cue fades it out over that cue's 'fade'; 'cueVol' moves its volume"""
    import numpy as np
    n = len(mix)
    # a cue asked for just before filming began (the cold open's, on its first tick) starts with the film
    ev = sorted([dict(c, t=max(0.0, c['t'])) for c in cues if ('cue' in c or 'cueVol' in c) and c.get('t', -1) >= -1.5],
                key=lambda c: c['t'])
    starts = [i for i, c in enumerate(ev) if 'cue' in c]
    for k, i in enumerate(starts):
        c = ev[i]
        if not c['cue']:
            continue
        s = sound(c['cue'])
        if s is None:
            continue
        t0 = c['t']
        nxt = ev[starts[k + 1]] if k + 1 < len(starts) else None
        t1 = nxt['t'] if nxt else n / sr
        fade = float(nxt.get('fade', 1.2)) if nxt else 0.0
        a, b = int(t0 * sr), min(n, int((t1 + fade) * sr))
        if b <= a:
            continue
        seg = np.zeros((b - a, 2), np.float32)
        loop = c.get('loop')
        passes = [0.0]
        if loop:
            while t0 + passes[-1] + loop < t1:
                passes.append(passes[-1] + loop)
        for p in passes:
            q = int(p * sr)
            m = min(len(s), len(seg) - q)
            if m > 0:
                seg[q:q + m] += s[:m]
        # its volume over time: the start, any changes, the fade in and out
        tt = np.arange(len(seg)) / sr + t0
        pts = [(t0, float(c.get('vol', 0.6)))]
        for e in ev[i + 1:starts[k + 1] if k + 1 < len(starts) else len(ev)]:
            pts += [(e['t'], pts[-1][1]), (e['t'] + float(e.get('fade', 1.0)), float(e['cueVol']))]
        g = np.interp(tt, [p[0] for p in pts], [p[1] for p in pts])
        fi = float(c.get('fadeIn') or 0)
        if fi > 0:
            g *= np.clip((tt - t0) / fi, 0, 1)
        if nxt and fade > 0:
            g *= np.clip(1 - (tt - t1) / fade, 0, 1)
        elif nxt:
            g *= tt < t1
        mix[a:b] += seg * g[:, None].astype(np.float32) * 0.9

def find(root, name):
    for sub in ('sfx', 'ambient', 'music'):
        for ext in ('.mp3', '.ogg', '.wav', '.m4a'):
            p = os.path.join(root, 'assets', 'audio', sub, name + ext)
            if os.path.exists(p):
                return p
    return None


def audio(d, root, out):
    m = meta(d)
    cues = json.load(open(os.path.join(d, 'cues.json')))
    dur = m['frames'] / m['fps'] + float(os.environ.get('TAIL', 0))   # TAIL: seconds held on the last frame
    n = int(dur * SR) + SR
    mix = np.zeros((n, 2), np.float32)
    cache = {}

    def sound(name):
        if name not in cache:
            p = find(root, name)
            cache[name] = decode(p) if p else None
        return cache[name]

    changes = [c for c in cues if 'music' in c and c['t'] >= 0]
    for i, c in enumerate(changes):
        if not c['music']:
            continue
        t0 = c['t']
        t1 = changes[i + 1]['t'] if i + 1 < len(changes) else dur
        s = sound(c['music'])
        if s is None:
            continue
        k = int((t1 - t0) * SR)
        bed = np.tile(s, (k // len(s) + 1, 1))[:k] * 0.42
        r = min(len(bed), int(0.6 * SR))
        bed[:r] *= np.linspace(0, 1, r)[:, None]
        bed[-r:] *= np.linspace(1, 0, r)[:, None]
        a = int(t0 * SR)
        mix[a:a + len(bed)] += bed[:max(0, n - a)]
    lay_score(mix, cues, sound, SR)
    used = 0
    for c in cues:
        if 'sfx' not in c or c['t'] < -0.05 or c['t'] > dur:
            continue
        s = sound(c['sfx'])
        if s is None:
            continue
        a = max(0, int(c['t'] * SR))
        x = s * float(c.get('vol', 0.8)) * 0.9
        mix[a:a + len(x)] += x[:max(0, n - a)]
        used += 1
    mix = mix[:int(dur * SR)]
    k = int(3 * SR)   # the end fades (the music would otherwise stop mid-phrase)
    mix[-k:] *= np.cos(np.linspace(0, np.pi / 2, k))[:, None] ** 2
    mix = np.tanh(mix * 1.15) / np.tanh(1.15)
    peak = float(np.abs(mix).max() or 1.0)
    mix *= 0.89 / peak
    mix.astype(np.float32).tofile(out)
    print(out, f'{dur:.2f}s', used, 'sounds', sorted({c.get('sfx') or c.get('music') or c.get('cue') for c in cues if c.get('t', -1) >= 0} - {None}))


def hold(d, secs, out):
    """the last frame held for [secs] (the music carrying on past the take)"""
    m = meta(d)
    w, h, fps = m['w'], m['h'], m['fps']
    size = w * h * 4
    with open(os.path.join(d, 'frames.rgba'), 'rb') as f:
        f.seek((m['frames'] - 1) * size)
        b = f.read(size)
    p = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', f'{w}x{h}', '-r', str(fps), '-i', '-',
                          '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '19', '-pix_fmt', 'yuv420p', '-r', str(fps), out], stdin=subprocess.PIPE)
    for _ in range(int(float(secs) * fps)):
        p.stdin.write(b)
    p.stdin.close()
    p.wait()
    print(out, 'held', secs, 's')


def join(d, out, segs):
    lst = os.path.join(d, 'segs.txt')
    with open(lst, 'w') as f:
        for s in segs:
            f.write(f"file '{os.path.abspath(s)}'\n")
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', lst, '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', os.path.join(d, 'mix.f32'),
                    '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-shortest', '-movflags', '+faststart', out], check=True)
    print(out, os.path.getsize(out) // 1024, 'KB')


if __name__ == '__main__':
    mode, a = sys.argv[1], sys.argv[2:]
    if mode == 'seg':
        seg(*a)
    elif mode == 'audio':
        audio(*a)
    elif mode == 'hold':
        hold(*a)
    elif mode == 'join':
        join(a[0], a[1], a[2:])

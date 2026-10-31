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
    dur = m['frames'] / m['fps']
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
    mix = np.tanh(mix * 1.15) / np.tanh(1.15)
    peak = float(np.abs(mix).max() or 1.0)
    mix *= 0.89 / peak
    mix.astype(np.float32).tofile(out)
    print(out, f'{dur:.2f}s', used, 'sounds', sorted({c.get('sfx') or c.get('music') for c in cues if c.get('t', -1) >= 0} - {None}))


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
    elif mode == 'join':
        join(a[0], a[1], a[2:])

"""Turn a recorded Short (flutter/tool/shorts/record_test.dart) into an MP4: the frames as H.264
1080x1920 at their rate, under the game's own sounds laid at the moments the game made them and a music
bed (the Short's loop, or the music the game asked for as it played).

    python3 encode.py SHORT_DIR GAME_ROOT OUT.mp4

SHORT_DIR has frames.rgba (raw RGBA frames, one after another) or f_00000.png..., meta.json and cues.json; GAME_ROOT is the Flutter project (its
assets/audio/sfx and assets/audio/ambient hold the sounds). Needs ffmpeg and numpy.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

import numpy as np

SR = 48000


def decode(path):
    """an audio file as float32 stereo at SR"""
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).copy()


def find(root, name):
    for sub in ('sfx', 'ambient', 'music'):
        for ext in ('.mp3', '.wav', '.ogg'):
            p = os.path.join(root, 'assets', 'audio', sub, name + ext)
            if os.path.exists(p):
                return p
    return None


def loop_to(sig, n):
    if len(sig) == 0:
        return np.zeros((n, 2), np.float32)
    reps = n // len(sig) + 1
    return np.tile(sig, (reps, 1))[:n]


def fade(sig, a=0.0, b=0.0):
    n = len(sig)
    if a > 0:
        k = min(n, int(a * SR))
        sig[:k] *= np.linspace(0, 1, k)[:, None]
    if b > 0:
        k = min(n, int(b * SR))
        sig[n - k:] *= np.linspace(1, 0, k)[:, None]
    return sig


def main(short_dir, root, out):
    meta = json.load(open(os.path.join(short_dir, 'meta.json')))
    cues = json.load(open(os.path.join(short_dir, 'cues.json')))
    fps, frames = meta['fps'], meta['frames']
    dur = frames / fps
    n = int(dur * SR) + SR
    mix = np.zeros((n, 2), np.float32)
    cache = {}

    def sound(name):
        if name not in cache:
            p = find(root, name)
            cache[name] = decode(p) if p else None
        return cache[name]

    # the music bed
    music = meta.get('music')
    if music:
        m = sound(music)
        if m is not None:
            bed = fade(loop_to(m, int(dur * SR)) * 0.42, 0.25, 1.6)
            mix[:len(bed)] += bed
    else:
        # follow the game: each change of music starts its loop there (with a short crossfade)
        changes = [c for c in cues if 'music' in c and c['t'] >= 0]
        for i, c in enumerate(changes):
            if not c['music']:
                continue
            t0 = c['t']
            t1 = changes[i + 1]['t'] if i + 1 < len(changes) else dur
            m = sound(c['music'])
            if m is None:
                continue
            seg = fade(loop_to(m, int((t1 - t0) * SR)) * 0.42, 0.6, 0.6)
            a = int(t0 * SR)
            mix[a:a + len(seg)] += seg[:max(0, n - a)]
    # the game's sounds, where they happened
    for c in cues:
        if 'sfx' not in c or c['t'] < 0 or c['t'] > dur:
            continue
        s = sound(c['sfx'])
        if s is None:
            continue
        a = int(c['t'] * SR)
        seg = s * float(c.get('vol', 0.8)) * 0.9
        mix[a:a + len(seg)] += seg[:max(0, n - a)]
    mix = mix[:int(dur * SR)]
    # a soft limiter, then to -1 dBFS
    mix = np.tanh(mix * 1.15) / np.tanh(1.15)
    peak = float(np.abs(mix).max() or 1.0)
    mix *= 0.89 / peak
    wav = os.path.join(short_dir, 'mix.f32')
    mix.astype(np.float32).tofile(wav)
    raw = os.path.join(short_dir, 'frames.rgba')
    if os.path.exists(raw):
        video = ['-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', f"{meta['w']}x{meta['h']}", '-r', str(fps), '-i', raw]
    else:
        video = ['-framerate', str(fps), '-i', os.path.join(short_dir, 'f_%05d.png')]
    scale = [] if meta.get('w', 1080) == 1080 else ['-vf', 'scale=1080:1920:flags=lanczos']
    subprocess.run([
        'ffmpeg', '-v', 'error', '-y',
        *video,
        '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', wav,
        *scale, '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '19', '-pix_fmt', 'yuv420p', '-r', str(fps),
        '-c:a', 'aac', '-b:a', '192k', '-shortest', '-movflags', '+faststart', out,
    ], check=True)
    print(out, f'{dur:.2f}s', os.path.getsize(out) // 1024, 'KB', len([c for c in cues if 'sfx' in c and c['t'] >= 0]), 'sounds')


if __name__ == '__main__':
    main(*sys.argv[1:4])

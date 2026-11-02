"""Turn a recorded Short (flutter/tool/shorts/record_test.dart) into an MP4: the frames as H.264
1080x1920 at their rate, under the game's own sounds laid at the moments the game made them and a music
bed (the Short's loop, or the music the game asked for as it played).

    python3 encode.py SHORT_DIR GAME_ROOT OUT.mp4 [SKIP_FRAMES]

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


def main(short_dir, root, out, skip='0'):
    """[skip]: frames to drop from the start (a take whose opening caption landed a frame or two late);
    the sounds move with them."""
    meta = json.load(open(os.path.join(short_dir, 'meta.json')))
    cues = json.load(open(os.path.join(short_dir, 'cues.json')))
    fps, frames = meta['fps'], meta['frames']
    skip = int(skip)
    cut = skip / fps
    cues = [dict(c, t=c['t'] - cut) if c.get('t', -1) >= 0 else c for c in cues]
    frames -= skip
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
    lay_score(mix, cues, sound, SR)
    # the game's sounds, where they happened
    for c in cues:
        if 'sfx' not in c or c['t'] < -0.05 or c['t'] > dur:
            continue
        s = sound(c['sfx'])
        if s is None:
            continue
        a = max(0, int(c['t'] * SR))
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
    vf = ([f'trim=start_frame={skip},setpts=PTS-STARTPTS'] if skip else []) + ([] if meta.get('w', 1080) == 1080 else ['scale=1080:1920:flags=lanczos'])
    scale = ['-vf', ','.join(vf)] if vf else []
    subprocess.run([
        'ffmpeg', '-v', 'error', '-y',
        *video,
        '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', wav,
        *scale, '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '19', '-pix_fmt', 'yuv420p', '-r', str(fps),
        '-c:a', 'aac', '-b:a', '192k', '-shortest', '-movflags', '+faststart', out,
    ], check=True)
    print(out, f'{dur:.2f}s', os.path.getsize(out) // 1024, 'KB', len([c for c in cues if 'sfx' in c and c['t'] >= 0]), 'sounds')


if __name__ == '__main__':
    main(*sys.argv[1:5])

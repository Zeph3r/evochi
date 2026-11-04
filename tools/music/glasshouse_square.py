"""Village Square (the ACE-Step take, its final loop) made Mira's Glasshouse piece, mus_glasshouse, and blended into
the soundtrack (VSCO 2 CE samples in a small soft room, about -21 LUFS):

  - its sound moved most of the way to the soundtrack's: the take carried a sub-bass rumble about 20 dB over the
    soundtrack's and a glossy top (8-16 kHz) 15-17 dB over it; a matching EQ takes three quarters of each gap
    (measured octave by octave against the place pieces)
  - a little of its squeeze undone (a gentle upward expander, so the phrases breathe), then the soundtrack's own hall
    under it, lightly, so it sits in the same room
  - the Evochi call in its rests, on the soundtrack's own instruments: the call's head on glockenspiel with pizzicato
    in bars 3 and 15 (where the take's tune rests); in the breakdown (bars 20-23, the band muffled) the whole call
    on clarinet (Mira's voice), then on flute with the glockenspiel an octave up as the band opens back up
  - levelled with the place pieces; it stays a seamless loop (everything that rings past the end wraps to the start)

The loop: D major, 108.26 BPM, 29 bars (64.29 s), bar 1 at 0 s (tools/music/masters/village/README.md).

    python3 tools/music/glasshouse_square.py tools/music/masters/village/mus_village.ogg flutter
"""
import json
import os
import subprocess
import sys

import numpy as np
from scipy.signal import fftconvolve, firwin2

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vsco  # noqa: E402

SR = vsco.SR
BPM = 108.26
BEAT = 60 / BPM
BAR = 4 * BEAT
HEAD = 'A4 .5 D5 .5 F#5 1.5 E5 .5 D5 1'
REST = 'B4 .5 D5 .5 E5 1.5 D5 .5 B4 1'

# the matching EQ: (Hz, dB), three quarters of the way from the take to the soundtrack
EQ = [(0, -24), (20, -18), (42, -16), (60, -8), (87, -2), (125, -0.5), (177, 0), (354, 1), (707, 2), (1414, -1.5),
      (2828, 1.2), (4000, -1.5), (5657, -4.5), (8000, -8), (9798, -10), (13856, -12), (17889, -14), (SR / 2, -16)]


def load(path):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).astype(np.float64)


def circular(x, h):
    """x convolved with h, round the loop (what rings past the end comes back at the start)"""
    n = len(x)
    y = np.stack([fftconvolve(x[:, c], h[:, c] if h.ndim == 2 else h) for c in range(2)], 1)
    out = y[:n].copy()
    k = len(y) - n
    while k > 0:
        seg = y[len(y) - k:len(y) - k + min(k, n)]
        out[:len(seg)] += seg
        k -= len(seg)
    return out


def match_eq(x):
    taps = 8191
    f, g = zip(*EQ)
    h = firwin2(taps, np.array(f) / (SR / 2), 10 ** (np.array(g) / 20))
    y = circular(x, h)
    return np.roll(y, -(taps // 2), axis=0)  # (its linear-phase delay)


def breathe(x, k=0.12):
    """a gentle upward expander: louder moments a touch louder, quieter a touch quieter (against the median)"""
    m = (x ** 2).mean(1)
    w = int(0.03 * SR)
    env = np.sqrt(np.convolve(np.concatenate([m[-w:], m, m[:w]]), np.ones(w) / w, 'same')[w:-w] + 1e-9)
    g = np.clip((env / np.median(env)) ** k, 0.75, 1.3)
    s = int(0.02 * SR)
    g = np.convolve(np.concatenate([g[-s:], g, g[:s]]), np.ones(s) / s, 'same')[s:-s]
    return x * g[:, None]


def notes(s, bar, octave=0):
    out, t = [], (bar - 1) * BAR
    tok = s.split()
    for n, d in zip(tok[::2], tok[1::2]):
        out.append((t, float(d) * BEAT, vsco.note_midi(n) + 12 * octave))
        t += float(d) * BEAT
    return out


# the call's voices: (instrument, notes, velocity, pan, level against the music in its bars (dB, RMS))
PARTS = {
    'answer_glock': ('glock', notes(HEAD, 3, 1) + notes(HEAD, 15, 1), 0.62, 0.25, -6.0),
    'answer_pizz': ('pizz', notes(HEAD, 3) + notes(HEAD, 15), 0.6, -0.2, -12.0),
    'clarinet': ('clarinet', notes(HEAD, 20, -1) + notes(REST, 21, -1), 0.55, -0.1, -4.0),
    'flute': ('flute', notes(HEAD, 22) + notes(REST, 23), 0.55, 0.1, -5.0),
    'flute_glock': ('glock', notes(HEAD, 22, 1) + notes(REST, 23, 1), 0.45, 0.3, -12.0),
}


def rms(x, bars):
    seg = np.concatenate([x[int((b - 1) * BAR * SR):int(b * BAR * SR)] for b in bars])
    return np.sqrt((seg ** 2).mean() + 1e-12)


def call(music):
    n = len(music)
    out = np.zeros_like(music)
    for name, (inst, ns, vel, pan, db) in PARTS.items():
        mx = vsco.Mix(n / SR + 6)
        for t, d, p in ns:
            mx.note(inst, t, d * (0.92 if inst in ('clarinet', 'flute') else 1), p, vel, pan=pan)
        y = mx.render(rt=2.3)
        tail = y[n:]
        y = y[:n].copy()
        y[:len(tail)] += tail[:n]  # (the loop's wrap)
        bars = sorted({int(t // BAR) + 1 for t, _, _ in ns})
        y *= 10 ** (db / 20) * rms(music, bars) / rms(y, bars)
        out += y
    return out


def build(src):
    x = load(src)
    x = match_eq(x)
    x = breathe(x)
    room = vsco.hall_ir(2.3)
    x = x + 0.1 * circular(x, room)
    return x + call(x)


if __name__ == '__main__':
    src, game = sys.argv[1], os.path.abspath(sys.argv[2])
    x = build(src)
    out = os.path.join(game, 'assets', 'audio', 'music', 'mus_glasshouse.mp3')
    path = vsco.master(x.astype(np.float32), out, lufs=-21.0, vbr=5)
    mp = os.path.join(game, 'assets', 'art', 'manifest.json')
    man = json.load(open(mp))
    man['audio']['mus_glasshouse'] = 'music/mus_glasshouse.mp3'
    json.dump(man, open(mp, 'w'), indent=1)
    print(path, '%.2f s' % (len(x) / SR), os.path.getsize(path) // 1024, 'KB')

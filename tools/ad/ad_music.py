"""A soft, playful instrumental for the Evochi ad, composed in code.

python3 ad_music.py OUT.wav TOTAL RISER_START REVEAL GROOVE_BACK END_START

Marimba arpeggios, a Karplus-Strong ukulele strum, a soft sub bass and a quiet shaker, in D major
at 108 BPM (I-V-vi-IV). Before the evolution reveal the groove thins out into a rising arpeggio and
shimmer; the reveal lands on a bright bell chord with a sparkle glissando, and the groove returns one
notch brighter until the end card, which gets a final chord and a long tail.
"""
import math
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import lfilter

SR = 48000
BPM = 108.0
BEAT = 60.0 / BPM
BAR = 4 * BEAT

out, TOTAL, RISER, REVEAL, BACK, END = sys.argv[1], *map(float, sys.argv[2:7])
rng = np.random.default_rng(7)
N = int((TOTAL + 2) * SR)
L = np.zeros(N)
R = np.zeros(N)

# ---------------------------------------------------------------- notes
def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)

D4, E4, Fs4, G4, A4, B4, Cs5, D5, E5, Fs5, G5, A5, B5, Cs6, D6, E6, Fs6, G6, A6, B6, D7 = \
    62, 64, 66, 67, 69, 71, 73, 74, 76, 78, 79, 81, 83, 85, 86, 88, 90, 91, 93, 95, 98
# I - V - vi - IV in D: D, A, Bm, G (root midi, chord tones for arpeggio)
CHORDS = [
    (50, [D4, Fs4, A4, D5]),
    (45, [A4 - 12 + 12, Cs5, E5, A5]),   # A major: A4 C#5 E5 A5
    (47, [B4 - 12, D4 + 12, Fs5, B5]),   # B minor: B3 D5 F#5 B5 -> voiced B4 D5 F#5 B5 below
    (43, [G4, B4, D5, G5]),
]
CHORDS[1] = (45, [A4, Cs5, E5, A5])
CHORDS[2] = (47, [B4, D5, Fs5, B5])


def add(sig, t, pan=0.0, gain=1.0):
    i0 = int(t * SR)
    if i0 < 0 or i0 >= N:
        return
    n = min(len(sig), N - i0)
    g = gain
    lg, rg = g * math.cos((pan + 1) * math.pi / 4), g * math.sin((pan + 1) * math.pi / 4)
    L[i0:i0 + n] += sig[:n] * lg
    R[i0:i0 + n] += sig[:n] * rg


def env(n, a=0.004, d=0.35, curve=5.0):
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / a) * np.exp(-curve * t / d)
    return e


def marimba(note, dur=0.5, vel=1.0):
    f = midi(note)
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 4.0 * t) * np.exp(-14 * t) + 0.12 * np.sin(2 * np.pi * f * 9.9 * t) * np.exp(-30 * t)
    s *= env(n, 0.003, dur * 0.8, 4.5)
    return s * 0.32 * vel


def bell(note, dur=1.6, vel=1.0):
    f = midi(note)
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) * np.exp(-3.0 * t) + 0.5 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-6 * t) + 0.25 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-9 * t)
    s *= np.minimum(1, t / 0.002)
    return s * 0.22 * vel


def pluck(note, dur=1.2, vel=1.0, bright=0.5):
    """Karplus-Strong string: a nylon-ish ukulele pluck."""
    f = midi(note)
    n = int(dur * SR)
    period = int(SR / f)
    buf = rng.uniform(-1, 1, period)
    buf = lfilter([1 - bright, bright], [1], buf)  # soften the excitation
    out_ = np.zeros(n)
    k = 0
    a = 0.5 + 0.49 * (1 - 0.15)
    for i in range(n):
        out_[i] = buf[k]
        nk = (k + 1) % period
        buf[k] = 0.996 * (a * buf[k] + (1 - a) * buf[nk])
        k = nk
    out_ *= np.exp(-2.2 * np.arange(n) / SR / dur)
    return out_ * 0.4 * vel


def sub(note, dur=0.6, vel=1.0):
    f = midi(note)
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) * (1 + 0.15 * np.sin(2 * np.pi * f * 2 * t))
    s *= np.minimum(1, t / 0.01) * np.exp(-3.5 * t / dur)
    return s * 0.5 * vel


def shaker(dur=0.09, vel=1.0):
    n = int(dur * SR)
    noise = rng.uniform(-1, 1, n)
    noise = lfilter([0.08, -0.08], [1, -0.84], noise)  # high-passed
    return noise * env(n, 0.004, dur, 4) * 0.5 * vel


def sweep(dur, f0=400, f1=6000, vel=1.0):
    """Rising filtered noise, the 'wind-up' under the riser."""
    n = int(dur * SR)
    noise = rng.uniform(-1, 1, n)
    t = np.arange(n) / SR
    fc = f0 * (f1 / f0) ** (t / dur)
    # one-pole band emphasis by modulating a resonant-ish filter crudely in blocks
    out_ = np.zeros(n)
    blk = 1024
    for i in range(0, n, blk):
        f = fc[min(i, n - 1)]
        w = 2 * math.pi * f / SR
        r = 0.985
        b = [1 - r]
        a = [1, -2 * r * math.cos(w), r * r]
        out_[i:i + blk] = lfilter(b, a, noise[i:i + blk]) * 6
    g = (t / dur) ** 2.2
    return out_ * g * 0.5 * vel


def splash(dur=1.8, vel=1.0):
    n = int(dur * SR)
    noise = rng.uniform(-1, 1, n)
    noise = lfilter([0.3, -0.3], [1, -0.7], noise)
    return noise * np.exp(-3.2 * np.arange(n) / SR) * 0.35 * vel


# ---------------------------------------------------------------- arrangement
def chord_at(bar):
    return CHORDS[bar % 4]


def groove(t0, t1, bright=0.0, melody=True, bass=True, perc=True):
    """Lay the pattern on the global bar grid between t0 and t1."""
    b0 = int(t0 // BAR)
    b1 = int(t1 // BAR) + 1
    for bar in range(b0, b1):
        root, tones = chord_at(bar)
        for k in range(8):  # 8th-note arpeggio
            t = bar * BAR + k * BEAT / 2
            if t < t0 or t >= t1:
                continue
            seq = [0, 1, 2, 3, 2, 1, 2, 3]
            note = tones[seq[k]] + (12 if bright > 0.5 else 0)
            vel = 0.75 if k % 2 == 0 else 0.55
            add(marimba(note, 0.45, vel), t, pan=-0.35 + 0.1 * k, gain=0.9)
        if bass:
            for k in (0, 2):
                t = bar * BAR + k * BEAT
                if t0 <= t < t1:
                    add(sub(root - 12, 0.7, 0.9), t, 0.0)
            t = bar * BAR + 3.5 * BEAT
            if t0 <= t < t1:
                add(sub(root - 12 + (7 if bar % 2 else 0), 0.35, 0.6), t, 0.0)
        # ukulele strum on 2 and 4 (and a light upstroke on the 'and' of 4)
        for k, vel in ((1, 0.8), (3, 0.8), (3.5, 0.45)):
            t = bar * BAR + k * BEAT
            if t0 <= t < t1:
                for j, note in enumerate(tones[:3]):
                    add(pluck(note, 0.9, vel * (0.9 - 0.15 * j), 0.5), t + j * 0.014, pan=0.35, gain=0.55)
        if perc:
            for k in range(8):
                t = bar * BAR + k * BEAT / 2
                if t0 <= t < t1:
                    add(shaker(0.08 if k % 2 else 0.06, 0.9 if k % 2 else 0.5), t, pan=0.55, gain=0.35 + 0.1 * bright)
        if melody and bar >= 1:
            # a two-bar call and answer on bells
            phrase = [(0, Fs5, 0.9), (1, A5, 0.8), (1.5, B5, 0.7), (2, A5, 0.8), (3, Fs5, 0.7)] if bar % 2 == 0 else \
                     [(0, E5, 0.9), (1, Fs5, 0.7), (2, D5, 0.9), (3, A4 + 12, 0.0)]
            for (beat, note, vel) in phrase:
                t = bar * BAR + beat * BEAT
                if vel > 0 and t0 <= t < t1:
                    add(bell(note + (12 if bright > 0.5 else 0), 1.3, vel * 0.8), t, pan=0.15, gain=0.7 + 0.2 * bright)


# 1. groove up to the riser (melody enters after the first bar)
groove(0.0, RISER, bright=0.0)

# 2. riser: arpeggio climbs, a pad swells, noise winds up, shaker rolls
dur = REVEAL - RISER
steps = 14
for i in range(steps):
    t = RISER + (dur * 0.92) * (i / steps) ** 0.85
    note = [D5, Fs5, A5, D6, Fs6, A6, D7][i % 7] + 12 * (i // 7)
    add(bell(note, 0.9, 0.45 + 0.4 * i / steps), t, pan=-0.3 + 0.6 * i / steps, gain=0.8)
add(sweep(dur, 300, 5000, 0.5), RISER, 0.0, gain=0.7)
for i in range(int(dur / (BEAT / 4))):
    t = RISER + i * BEAT / 4
    add(shaker(0.05, 0.3 + 0.7 * (t - RISER) / dur), t, pan=0.5, gain=0.3)
# a sustained D major pad under it (stacked soft sines with slow swell)
n = int(dur * SR)
tt = np.arange(n) / SR
pad = sum(np.sin(2 * np.pi * midi(m) * tt) * g for m, g in ((D4, 0.5), (A4, 0.35), (D5, 0.3), (Fs5, 0.22), (A5, 0.15)))
pad *= (tt / dur) ** 1.8 * 0.08
add(pad, RISER, 0.0)

# 3. the reveal: bright bell chord, sparkle glissando, splash, low thump
for j, note in enumerate((D5, Fs5, A5, D6, Fs6, A6)):
    add(bell(note, 3.2, 1.0 - 0.08 * j), REVEAL + j * 0.012, pan=-0.4 + 0.16 * j, gain=1.1)
add(sub(D4 - 24, 1.2, 1.0), REVEAL, 0.0, gain=0.9)
add(splash(2.0, 0.8), REVEAL, 0.0, gain=0.6)
gliss = [D6, E6, Fs6, A6, B6, D7, E6 + 12, Fs6 + 12, A6 + 12, D7 + 12]
for i in range(26):
    t = REVEAL + 0.05 + i * 0.045 + rng.uniform(0, 0.015)
    note = gliss[i % len(gliss)] + (12 if i > 17 else 0)
    add(bell(note, 1.2, 0.55 - 0.012 * i), t, pan=rng.uniform(-0.8, 0.8), gain=0.75)
# shimmer tail: random high bells fading out over 1.5 s
for i in range(22):
    t = REVEAL + 0.6 + rng.uniform(0, 1.6)
    add(bell(rng.choice([D7, Fs6 + 12, A6 + 12, E6 + 12]), 0.9, 0.25 * (1 - (t - REVEAL) / 2.4)), t, pan=rng.uniform(-0.9, 0.9), gain=0.7)

# 4. groove returns, brighter, until the end card
groove(BACK, END, bright=1.0)

# 5. end card: final chord and a long, warm tail, then silence
for j, note in enumerate((D4, A4, D5, Fs5, A5, D6)):
    add(bell(note, 3.4, 0.9 - 0.08 * j), END + j * 0.02, pan=-0.4 + 0.16 * j, gain=1.0)
add(sub(D4 - 24, 1.6, 0.9), END, 0.0)
for j, note in enumerate((D4, Fs4, A4)):
    add(pluck(note, 2.5, 0.8, 0.5), END + 0.02 + j * 0.03, pan=0.3, gain=0.6)
for i in range(10):
    t = END + 0.3 + rng.uniform(0, 1.4)
    add(bell(rng.choice([D7, A6, Fs6 + 12]), 0.9, 0.2), t, pan=rng.uniform(-0.8, 0.8), gain=0.6)

# ---------------------------------------------------------------- mix
mix = np.stack([L, R], 1)
# gentle high-shelf roll-off: this track sits under captions and SFX, so keep it soft
b, a = [0.5, 0.5], [1.0]
mix = lfilter(b, a, mix, axis=0)
# fade out across the last second
n_total = int(TOTAL * SR)
mix = mix[:n_total]
fade = np.ones(n_total)
f0 = int((TOTAL - 1.2) * SR)
fade[f0:] = np.linspace(1, 0, n_total - f0)
mix *= fade[:, None]
peak = np.abs(mix).max()
mix = mix / peak * 0.85
wavfile.write(out, SR, (mix * 32767).astype(np.int16))
print(f'wrote {out}: {TOTAL}s, peak normalised, riser {RISER}->{REVEAL}, groove back {BACK}, end {END}')

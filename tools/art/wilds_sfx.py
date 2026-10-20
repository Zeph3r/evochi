"""The Lumen Wilds' fight sounds, synthesised like the rest (soft, short, never harsh): a landed hit, your
Evochi hurt, a swing, a dodge, a glow bolt, a Thornling's roll, a spore puff, a creature calmed, the
guardian's roar and its crash. Writes WAVs; the packer turns them into mp3s for the app.

    python3 wilds_sfx.py OUT_DIR
"""
import os
import sys

import numpy as np

from sfx import SR, env, tone, bell, mix, pad_at, write, lowpass

rng = np.random.default_rng(9)


def noise(dur):
    return rng.uniform(-1, 1, int(dur * SR))


def sweep(f0, f1, dur, kind='sine'):
    n = int(dur * SR)
    f = np.geomspace(f0, f1, n)
    ph = 2 * np.pi * np.cumsum(f) / SR
    if kind == 'tri':
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if kind == 'saw':
        return ((ph / np.pi) % 2) - 1
    return np.sin(ph)


def bandpass(x, lo, hi):
    from scipy.signal import butter, lfilter
    b, a = butter(2, [lo / (SR / 2), hi / (SR / 2)], btype='band')
    return lfilter(b, a, x)


def sounds():
    s = {}
    # a landed hit: a soft thump with a little snap on top
    n = int(0.16 * SR)
    s['wild_hit'] = mix(sweep(180, 70, 0.16) * env(n, 0.002, 0.05, 0, 0.03) * 1.0,
                        bandpass(noise(0.06), 900, 3500) * env(int(0.06 * SR), 0.001, 0.015, 0, 0.01) * 0.6)
    # your Evochi hurt: a short "oof" falling, a soft knock
    n = int(0.2 * SR)
    s['wild_hurt'] = mix(sweep(560, 300, 0.2, 'tri') * env(n, 0.004, 0.08, 0, 0.05) * 0.7,
                         sweep(140, 60, 0.14) * env(int(0.14 * SR), 0.002, 0.05, 0, 0.03))
    # a swing: a quick airy swish
    n = int(0.14 * SR)
    sw = bandpass(noise(0.14), 700, 2600) * np.sin(np.linspace(0, np.pi, n)) ** 2
    s['wild_swing'] = sw
    # a dodge roll: a brighter, longer swish with a soft tumble under it
    n = int(0.24 * SR)
    s['wild_dodge'] = mix(bandpass(noise(0.24), 1200, 4200) * np.sin(np.linspace(0, np.pi, n)) ** 1.5 * 0.8,
                          sweep(220, 160, 0.24) * env(n, 0.02, 0.1, 0, 0.05) * 0.3)
    # a glow bolt: a rising shimmer
    n = int(0.22 * SR)
    s['wild_bolt'] = mix(sweep(620, 1500, 0.22) * env(n, 0.003, 0.12, 0, 0.05) * 0.6, bell(1320, 0.3, 0.2) * 0.25)
    # a Thornling rolling: a low crunchy rumble
    n = int(0.45 * SR)
    rum = lowpass(noise(0.45), 0.96) * (0.6 + 0.4 * np.sin(2 * np.pi * 22 * np.arange(n) / SR))
    s['wild_roll'] = rum * env(n, 0.03, 0.4, 0.3, 0.12)
    # a spore puff: a breathy pop
    n = int(0.3 * SR)
    s['wild_spore'] = mix(bandpass(noise(0.3), 300, 1600) * env(n, 0.005, 0.12, 0, 0.08),
                          sweep(320, 180, 0.08) * env(int(0.08 * SR), 0.001, 0.03, 0, 0.02) * 0.6)
    # a creature calmed: three rising bell notes and a sparkle
    s['wild_calm'] = mix(bell(784, 0.6, 0.3) * 0.6, pad_at(bell(988, 0.6, 0.3) * 0.5, 0.08),
                         pad_at(bell(1319, 0.8, 0.4) * 0.45, 0.16), pad_at(bandpass(noise(0.4), 4000, 9000) * env(int(0.4 * SR), 0.01, 0.15) * 0.15, 0.1))
    # the guardian's roar: a low bellow with a rasp (soft at the edges)
    n = int(1.1 * SR)
    t = np.arange(n) / SR
    base = sweep(110, 82, 1.1, 'saw') * (1 + 0.15 * np.sin(2 * np.pi * 7 * t))
    rasp = bandpass(noise(1.1), 200, 900) * 0.5
    s['wild_roar'] = lowpass(mix(base, rasp), 0.82) * env(n, 0.12, 0.8, 0.4, 0.3)
    # it crashes into stone: a heavy thud and a crack
    n = int(0.6 * SR)
    s['wild_crash'] = mix(sweep(90, 40, 0.6) * env(n, 0.002, 0.25, 0, 0.1) * 1.2,
                          bandpass(noise(0.25), 600, 3000) * env(int(0.25 * SR), 0.001, 0.06, 0, 0.05) * 0.7,
                          lowpass(noise(0.6), 0.97) * env(n, 0.01, 0.3, 0, 0.1) * 0.8)
    return s


VOLS = {'wild_hit': 0.55, 'wild_hurt': 0.5, 'wild_swing': 0.35, 'wild_dodge': 0.35, 'wild_bolt': 0.4, 'wild_roll': 0.5,
        'wild_spore': 0.45, 'wild_calm': 0.4, 'wild_roar': 0.6, 'wild_crash': 0.6}


def main(out):
    os.makedirs(out, exist_ok=True)
    for k, x in sounds().items():
        write(os.path.join(out, f'{k}.wav'), x, VOLS.get(k, 0.45))
        print(k, round(len(x) / SR, 2), 's')


if __name__ == '__main__':
    main(sys.argv[1])

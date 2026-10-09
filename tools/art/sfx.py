"""Synthesised sound effects for Evochi (soft, cozy, low-volume). Writes 16-bit mono WAVs."""
import os
import sys
import wave

import numpy as np

SR = 44100


def env(n, a=0.005, d=0.1, s=0.0, r=0.1):
    t = np.arange(n) / SR
    e = np.ones(n)
    na = int(a * SR)
    e[:na] = np.linspace(0, 1, max(na, 1))
    e *= np.exp(-np.maximum(t - a, 0) / max(d, 1e-4)) * (1 - s) + s
    nr = int(r * SR)
    if nr > 0 and nr < n:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def tone(freq, dur, kind='sine', vib=0.0):
    t = np.arange(int(dur * SR)) / SR
    f = freq * (1 + vib * np.sin(2 * np.pi * 6 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    if kind == 'sine':
        return np.sin(ph)
    if kind == 'tri':
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if kind == 'square':
        return np.sign(np.sin(ph)) * 0.5
    raise ValueError(kind)


def bell(freq, dur, decay=0.4):
    n = int(dur * SR)
    out = np.zeros(n)
    for k, amp in ((1, 1.0), (2.01, 0.45), (3.0, 0.2), (4.2, 0.12)):
        out += amp * tone(freq * k, dur) * env(n, 0.002, decay / k, 0, 0.05)
    return out / 1.8


def seq(parts, gap=0.0):
    out = []
    for p in parts:
        out.append(p)
        if gap:
            out.append(np.zeros(int(gap * SR)))
    return np.concatenate(out)


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = np.zeros(n)
    for t in tracks:
        out[:len(t)] += t
    return out


def pad_at(x, start):
    return np.concatenate([np.zeros(int(start * SR)), x])


def write(path, x, vol=0.5):
    x = x / max(1e-6, np.max(np.abs(x))) * vol
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def sounds():
    s = {}
    n = int(0.09 * SR)
    s['ui_tap'] = tone(660, 0.09, 'sine') * env(n, 0.002, 0.03, 0, 0.02)
    t = np.arange(int(0.25 * SR)) / SR
    s['pet_chirp'] = np.sin(2 * np.pi * np.cumsum(700 + 500 * np.sin(np.pi * t / 0.25)) / SR) * env(len(t), 0.01, 0.12, 0, 0.05)
    t = np.arange(int(0.35 * SR)) / SR
    boing = np.sin(2 * np.pi * np.cumsum(220 + 380 * np.exp(-t * 9)) / SR) * env(len(t), 0.003, 0.2, 0, 0.05)
    s['play_boing'] = boing
    s['reward_chime'] = mix(bell(784, 0.6), pad_at(bell(1175, 0.7), 0.09))
    s['coin'] = mix(bell(1568, 0.35, 0.18), pad_at(bell(2093, 0.4, 0.2), 0.06))
    s['purchase'] = mix(bell(659, 0.5), pad_at(bell(880, 0.5), 0.08), pad_at(bell(1319, 0.7), 0.16))
    s['error_bonk'] = tone(180, 0.18, 'tri') * env(int(0.18 * SR), 0.003, 0.07, 0, 0.04)
    s['level_up'] = seq([bell(f, 0.22, 0.2) for f in (523, 659, 784)] + [bell(1047, 0.8, 0.5)])
    # evolution: rising shimmer arpeggio + sustained chord
    arp = np.zeros(int(3.2 * SR))
    for i, f in enumerate((392, 494, 587, 784, 988, 1175, 1568)):
        b = bell(f, 0.6, 0.35) * (0.6 + i * 0.06)
        st = int((0.15 + i * 0.16) * SR)
        arp[st:st + len(b)] += b[:len(arp) - st]
    chord = mix(*(tone(f, 2.0, 'sine') * env(int(2.0 * SR), 0.2, 1.2, 0.0, 0.6) * 0.35
                  for f in (523, 659, 784, 1047)))
    s['evolve_fanfare'] = mix(arp, pad_at(chord, 1.3))
    # gentle memorial tone
    s['memorial'] = mix(*(tone(f, 3.0, 'sine') * env(int(3.0 * SR), 0.6, 2.0, 0, 1.0) * 0.4 for f in (220, 277, 330)))
    # ambient meadow loop (soft wind + sparse birds), 16 s, seamless
    L = 16.0
    nL = int(L * SR)
    rng = np.random.default_rng(3)
    noise = rng.standard_normal(nL)
    from scipy.signal import lfilter
    wind = lfilter([0.02], [1, -0.98], noise)
    wind *= 0.6 + 0.4 * np.sin(2 * np.pi * np.arange(nL) / nL * 2)
    birds = np.zeros(nL)
    for k in range(7):
        st = rng.uniform(0.5, L - 1.5)
        f0 = rng.uniform(2200, 3400)
        for j in range(rng.integers(2, 5)):
            d = 0.07
            tt = np.arange(int(d * SR)) / SR
            chirp = np.sin(2 * np.pi * np.cumsum(f0 + 900 * np.sin(np.pi * tt / d)) / SR) * env(len(tt), 0.005, 0.03, 0, 0.01)
            i0 = int((st + j * 0.11) * SR)
            birds[i0:i0 + len(chirp)] += chirp[:max(0, nL - i0)] * 0.25
    s['ambient_meadow_loop'] = wind / np.max(np.abs(wind)) * 0.5 + birds
    return s


def main(out):
    os.makedirs(out, exist_ok=True)
    vols = {'ambient_meadow_loop': 0.25, 'evolve_fanfare': 0.5, 'memorial': 0.35}
    for k, x in sounds().items():
        write(os.path.join(out, f'sfx_{k}.wav'), x, vols.get(k, 0.45))
        print(k)


if __name__ == '__main__':
    main(sys.argv[1])

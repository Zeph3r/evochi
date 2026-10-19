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
    s.update(encounter_sounds())
    return s


def lowpass(x, a):
    from scipy.signal import lfilter
    return lfilter([1 - a], [1, -a], x)


def loop_fade(x, fade=0.05):
    # tiny crossfade of the tail into the head so a loop has no click
    n = int(fade * SR)
    x = x.copy()
    x[:n] = x[:n] * np.linspace(0, 1, n) + x[-n:] * np.linspace(1, 0, n)
    return x[:-n]


def encounter_sounds():
    """Lumen Trails encounters: two music loops (wild, boss), the Sentinel's awakening (rumble + sting)
    and short cues for abilities and the creature's replies."""
    s = {}
    rng = np.random.default_rng(11)
    # --- wild encounter loop: 8 bars of a gentle, curious pentatonic pluck over a soft pad (A minor-ish)
    bpm = 96
    beat = 60 / bpm
    L = beat * 16
    nL = int(L * SR)
    out = np.zeros(nL + SR)
    notes = [440, 523, 587, 659, 784, 880]
    pattern = [0, 2, 4, 2, 1, 3, 5, 3, 0, 2, 4, 5, 3, 2, 1, 0]
    for i, k in enumerate(pattern):
        f = notes[k]
        n = int(beat * 1.6 * SR)
        pl = (tone(f, beat * 1.6, 'tri') * 0.6 + tone(f * 2, beat * 1.6, 'sine') * 0.15) * env(n, 0.004, 0.22, 0, 0.05)
        st = int(i * beat * SR)
        out[st:st + n] += pl * (0.9 if i % 4 == 0 else 0.65)
    for ch, t0 in (((220, 262, 330), 0), ((196, 247, 294), 8)):
        n = int(beat * 8 * SR)
        pad = mix(*(tone(f, beat * 8, 'sine', vib=0.003) for f in ch)) * env(n, 0.8, 9.0, 0.6, 0.8) * 0.25
        st = int(t0 * beat * SR)
        out[st:st + n] += pad
    # soft shaker on the off-beats
    for i in range(32):
        n = int(0.05 * SR)
        st = int((i + 0.5) * beat / 2 * SR)
        out[st:st + n] += lowpass(rng.standard_normal(n), 0.3) * env(n, 0.002, 0.02, 0, 0.01) * 0.08
    s['enc_wild_loop'] = loop_fade(out[:nL + int(0.05 * SR)])
    # --- boss loop: a low heartbeat drone in D minor with distant bells, tense but not scary
    bpm = 72
    beat = 60 / bpm
    L = beat * 16
    nL = int(L * SR)
    out = np.zeros(nL + SR)
    drone = mix(tone(73.4, L + 0.2, 'tri', vib=0.002) * 0.5, tone(110, L + 0.2, 'sine') * 0.25, tone(146.8, L + 0.2, 'sine', vib=0.004) * 0.12)
    out[:len(drone)] += lowpass(drone, 0.6) * 0.9
    for i in range(16):
        for k, off in ((0, 0.0), (1, 0.28)):
            n = int(0.25 * SR)
            hb = tone(55, 0.25, 'sine') * env(n, 0.005, 0.08, 0, 0.05) * (0.9 if k == 0 else 0.55)
            st = int((i * beat + off) * SR)
            out[st:st + n] += hb
    for i, f in enumerate((587, 698, 523, 587, 880, 698, 659, 587)):
        b = bell(f, 1.6, 0.6) * 0.18
        st = int((i * 2 + 1) * beat * SR)
        out[st:st + len(b)] += b[:max(0, len(out) - st)]
    s['enc_boss_loop'] = loop_fade(out[:nL + int(0.05 * SR)])
    # --- the Sentinel stirs: a long low rumble with grit
    n = int(3.4 * SR)
    t = np.arange(n) / SR
    noise = lowpass(lowpass(rng.standard_normal(n), 0.985), 0.97)
    rum = noise / np.max(np.abs(noise)) * (0.6 + 0.4 * np.sin(2 * np.pi * 3.1 * t) ** 2)
    rum += tone(38, 3.4, 'sine') * 0.5 + tone(57, 3.4, 'tri') * 0.15
    for k in range(9):
        st = int(rng.uniform(0.4, 3.0) * SR)
        m = int(0.06 * SR)
        rum[st:st + m] += lowpass(rng.standard_normal(m), 0.5) * env(m, 0.001, 0.02, 0, 0.01) * 0.5
    s['enc_rumble'] = rum * env(n, 0.6, 9.0, 0.0, 0.9)
    # --- the eyes open: a rising, minor swell that lands on a low chord
    n = int(4.0 * SR)
    sw = np.zeros(n)
    for f in (146.8, 174.6, 207.7, 293.7):
        fr = f * (0.94 + 0.06 * np.clip(t[:n] / 2.2 if len(t) >= n else np.arange(n) / SR / 2.2, 0, 1))
        ph = 2 * np.pi * np.cumsum(fr) / SR
        sw += (np.sin(ph) * 0.6 + 2 / np.pi * np.arcsin(np.sin(ph * 2.002)) * 0.2)
    sw *= np.clip(np.arange(n) / SR / 2.4, 0, 1) ** 1.6
    hit = int(2.4 * SR)
    boom = tone(41, 1.6, 'sine') * env(int(1.6 * SR), 0.004, 0.6, 0, 0.3) * 1.4
    sw[hit:hit + len(boom)] += boom[:n - hit]
    s['enc_awaken'] = lowpass(sw, 0.4) * env(n, 0.01, 9.0, 0.0, 0.8)
    # --- ability cues
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    sh = np.sin(2 * np.pi * np.cumsum(900 + 1400 * t / 0.7) / SR) * 0.25
    s['enc_glow'] = mix(sh * env(n, 0.05, 0.4, 0, 0.1), pad_at(bell(1319, 0.6, 0.3) * 0.7, 0.35), pad_at(bell(1760, 0.6, 0.3) * 0.5, 0.42))
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    s['enc_whoosh'] = lowpass(rng.standard_normal(n), 0.7) * np.sin(np.pi * t / 0.35) ** 2 * 0.7
    s['enc_soothe'] = mix(*(pad_at(bell(f, 0.9, 0.5) * 0.5, i * 0.12) for i, f in enumerate((523, 659, 784))))
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    s['enc_surge'] = mix(np.sin(2 * np.pi * np.cumsum(320 * np.exp(-t * 2.4) + 60) / SR) * env(n, 0.01, 0.5, 0, 0.2) * 0.8,
                         lowpass(rng.standard_normal(n), 0.8) * env(n, 0.005, 0.25, 0, 0.1) * 0.5)
    return s


def main(out):
    os.makedirs(out, exist_ok=True)
    vols = {'ambient_meadow_loop': 0.25, 'evolve_fanfare': 0.5, 'memorial': 0.35, 'enc_wild_loop': 0.3, 'enc_boss_loop': 0.32,
            'enc_rumble': 0.5, 'enc_awaken': 0.5, 'enc_glow': 0.4, 'enc_whoosh': 0.3, 'enc_soothe': 0.4, 'enc_surge': 0.42}
    for k, x in sounds().items():
        write(os.path.join(out, f'sfx_{k}.wav'), x, vols.get(k, 0.45))
        print(k)


if __name__ == '__main__':
    main(sys.argv[1])

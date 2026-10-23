"""Mining sounds (MINES_PLAN.md): every ore known by its sound, three strengths each (the chip of an early
hit, the crack of a later one, the break), plus the collect tick as ore lands in the satchel and the clink
of a node too hard for your gear. Synthesised like the rest of the game's sounds: soft, short, never harsh.

    copper    dry stone cracks with a small metallic note
    iron      a deep thunk with a faint ring
    lumen     rising bells, crystal chimes
    obsidian  a glassy fracture and small falling fragments

    python3 mining_sfx.py OUT_DIR        # WAVs; then mp3 them into flutter/assets/audio/sfx/ (--mp3)
"""
import os
import subprocess
import sys

import numpy as np

from sfx import SR, env, bell, mix, pad_at, write, lowpass
from wilds_sfx import bandpass, sweep

rng = np.random.default_rng(23)
SFX = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'flutter', 'assets', 'audio', 'sfx')


def noise(dur):
    return rng.uniform(-1, 1, int(dur * SR))


def burst(dur, lo, hi, decay):
    n = int(dur * SR)
    return bandpass(noise(dur), lo, hi) * env(n, 0.001, decay, 0, min(0.02, dur / 3))


def crackle(dur, n, lo, hi, each=0.012, fall=1.0):
    """n tiny crunches scattered over dur, getting quieter (rubble settling)."""
    out = np.zeros(int(dur * SR))
    for i in range(n):
        t = rng.uniform(0, dur * 0.85) * (i / max(n - 1, 1)) ** fall if fall != 1.0 else rng.uniform(0, dur * 0.85)
        b = burst(each * rng.uniform(0.7, 1.4), lo, hi, each * 0.4) * rng.uniform(0.4, 1.0) * (1 - 0.6 * t / dur)
        s = int(t * SR)
        out[s:s + len(b)] += b[:len(out) - s]
    return out


def thump(f0, f1, dur, decay):
    return sweep(f0, f1, dur) * env(int(dur * SR), 0.002, decay, 0, 0.03)


def sounds():
    s = {}
    # copper: warm, crunchy rock; a small metallic note on top
    for i, k in enumerate(('chip', 'crack', 'break')):
        dur = (0.16, 0.24, 0.5)[i]
        body = burst(min(dur, 0.12), 1300 - 250 * i, 5200 - 600 * i, 0.03 + 0.015 * i) * (0.8 + 0.2 * i)
        parts = [body, thump(150 - 20 * i, 70, 0.12 + 0.04 * i, 0.04 + 0.02 * i) * (0.5 + 0.25 * i),
                 pad_at(bell(2350 - 150 * i, 0.25, 0.07 + 0.02 * i) * (0.16 + 0.04 * i), 0.004)]
        if i >= 1:
            parts.append(crackle(0.12 + 0.2 * (i - 1), 3 + 6 * (i - 1), 1500, 5000) * 0.5)
        if i == 2:
            parts.append(pad_at(lowpass(noise(0.4), 0.95) * env(int(0.4 * SR), 0.005, 0.15, 0, 0.1) * 0.5, 0.02))
        s[f'mine_copper_{k}'] = mix(*parts)
    # iron: dense; a deep thunk and a faint ring, the last one heavier
    for i, k in enumerate(('chip', 'crack', 'break')):
        parts = [thump(125 - 10 * i, 60, 0.16 + 0.05 * i, 0.05 + 0.025 * i) * (1.0 + 0.2 * i),
                 burst(0.05, 600, 2400, 0.012) * 0.45,
                 pad_at(bell(1720 - 60 * i, 0.5, 0.18 + 0.05 * i) * (0.12 + 0.03 * i), 0.006)]
        if i == 2:
            parts += [crackle(0.35, 8, 700, 3000) * 0.5, pad_at(thump(90, 45, 0.3, 0.12) * 0.8, 0.05)]
        s[f'mine_iron_{k}'] = mix(*parts)
    # lumen crystal: clear and ringing; chimes that rise with each hit
    base = (1046, 1318, 1568)
    for i, k in enumerate(('chip', 'crack', 'break')):
        parts = [burst(0.03, 3000, 9000, 0.008) * 0.35, bell(base[i], 0.5, 0.22) * 0.35,
                 pad_at(bell(base[i] * 1.5, 0.45, 0.18) * 0.2, 0.03)]
        if i == 2:
            parts += [pad_at(bell(2093, 0.7, 0.3) * 0.28, 0.07), pad_at(bell(2637, 0.8, 0.35) * 0.22, 0.12),
                      pad_at(bandpass(noise(0.5), 5000, 11000) * env(int(0.5 * SR), 0.01, 0.2) * 0.12, 0.04)]
        s[f'mine_lumen_{k}'] = mix(*parts)
    # obsidian: sharp and brittle; a glassy snap, small fragments falling after
    for i, k in enumerate(('chip', 'crack', 'break')):
        parts = [burst(0.035, 2800, 9500, 0.008) * (0.6 + 0.2 * i), thump(220, 120, 0.06, 0.015) * 0.35,
                 pad_at(bell(3150, 0.18, 0.04) * 0.14, 0.003)]
        if i >= 1:
            parts.append(pad_at(crackle(0.15 + 0.25 * (i - 1), 4 + 8 * (i - 1), 3500, 9000, each=0.006) * 0.45, 0.03))
        if i == 2:
            parts.append(burst(0.06, 1500, 6000, 0.02) * 0.6)
        s[f'mine_obsidian_{k}'] = mix(*parts)
    # ore into the satchel: a soft pop and a small tick
    s['mine_collect'] = mix(thump(420, 620, 0.06, 0.02) * 0.35, pad_at(bell(2640, 0.2, 0.05) * 0.3, 0.02))
    # too hard for your gear: a short clink and a bounce, nothing breaks
    s['mine_clink'] = mix(bell(2980, 0.3, 0.06) * 0.4, pad_at(bell(2980 * 1.33, 0.2, 0.04) * 0.15, 0.002),
                          thump(260, 180, 0.08, 0.02) * 0.35, pad_at(thump(300, 220, 0.06, 0.02) * 0.2, 0.12))
    return s


VOLS = {'mine_collect': 0.4, 'mine_clink': 0.45}


def register(names):
    """List the sounds in the Flutter art manifest (AssetManifest.audio), so AudioService.play finds them."""
    import json
    mp = os.path.join(SFX, '..', '..', 'art', 'manifest.json')
    with open(mp) as f:
        man = json.load(f)
    for k in names:
        man['audio'][k] = f'sfx/{k}.mp3'
    with open(mp, 'w') as f:
        json.dump(man, f, indent=1)


def main(out, mp3=False):
    os.makedirs(out, exist_ok=True)
    s = sounds()
    if mp3:
        register(s)
    for k, x in s.items():
        wav = os.path.join(out, f'{k}.wav')
        write(wav, x, VOLS.get(k, 0.5 if k.endswith('break') else 0.45))
        if mp3:
            subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-ac', '1', '-ar', '44100', '-b:a', '64k',
                            os.path.join(SFX, f'{k}.mp3')], check=True)
        print(k, round(len(x) / SR, 2), 's')


if __name__ == '__main__':
    main(sys.argv[1], '--mp3' in sys.argv)

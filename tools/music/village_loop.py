"""Village Square (mus_village_v3_take3, the clearer mix) made the game's loop: restructured on its own bar grid.

The take (D major, 108.26 BPM, first downbeat 0.113 s, bars of 2.217 s) runs: bars 1-2 the lead alone (odd on its
own), 3-8 the tune, 9-10 a near-silent break, 11-12 the band without the tune, 13-24 the tune, 25-26 the second
break, 27-28 the band again, 29-34 the tune, 35 the lead alone and the fade. The loop:

    [bloom]  3-8  13-24  29-34  -> back to [bloom]   (the bloom from bar 4's groove)

  - the two breaks go, with the tune-less bars after each: every join is an Em-A bar into a D bar, as the song
    itself moves, crossfaded over 25 ms just before the downbeat
  - the bloom (one bar): the band itself, its Em-A groove bar (bar 4, no tune), muffled and a little quieter,
    opening up to full across the bar, with a light shimmer (a short reverb, a soft octave above) and a gentle
    reverse swell into the first downbeat, where the tune comes in
  - the last bar leans toward it: its top eases off a little and a touch of shimmer comes in, so the wrap flows;
    what rang on past it in the take is folded onto the start

    python3 village_loop.py SRC.mp3 OUT_DIR       -> mus_village.ogg (the game's loop) and mus_village.mp3
"""
import json
import os
import subprocess
import sys

import numpy as np
from scipy.signal import fftconvolve, butter, sosfilt

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rework_village import EQ, BPM, PHASE  # noqa: E402

SR = 48000
BAR = 4 * 60 / BPM
KEEP = [(3, 8), (13, 24), (29, 34)]   # bar ranges kept, 1-based, inclusive


def at(bar):
    """sample index of bar's downbeat (1-based)"""
    return int(round((PHASE + (bar - 1) * BAR) * SR))


def load(src):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', src, '-af', EQ, '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).astype(np.float64)


def splice(parts, xf=int(0.025 * SR), pre=int(0.015 * SR)):
    """join segments (each from a downbeat to a downbeat): an equal-power crossfade over the (xf - pre) samples before
    the join, from the outgoing bar into what led up to the incoming one, so the incoming downbeat lands whole"""
    out = parts[0][0][parts[0][1]:parts[0][2]].copy()
    for x, a, b in parts[1:]:
        seg = x[a - xf + pre:b].copy()
        k = np.linspace(0, np.pi / 2, xf)[:, None]
        n = len(out)
        # the outgoing side: the last (xf - pre) samples of out, plus pre samples of what followed it in the source
        out = np.vstack([out[:n - (xf - pre)], out[n - (xf - pre):] * np.cos(k[:xf - pre]) + seg[:xf - pre] * np.sin(k[:xf - pre]),
                         seg[xf - pre:]])
    return out


def reverb(x, secs=3.6, seed=3):
    """a soft, dark hall: decaying stereo noise as the impulse"""
    rng = np.random.default_rng(seed)
    n = int(secs * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal((n, 2)) * np.exp(-6.9 * t / secs)[:, None]
    ir = sosfilt(butter(2, 6000, 'low', fs=SR, output='sos'), ir, axis=0)
    ir[:int(0.02 * SR)] *= np.linspace(0, 1, int(0.02 * SR))[:, None]
    ir /= np.sqrt((ir ** 2).sum(axis=0))
    return np.stack([fftconvolve(x[:, c], ir[:, c]) for c in (0, 1)], axis=1)


def shimmer(x, octave=0.8, secs=3.6):
    """x as a wash: the octave above layered in ([octave] of it), low end out, a reverb of [secs]"""
    import librosa
    hi = np.stack([librosa.effects.pitch_shift(x[:, c].astype(np.float32), sr=SR, n_steps=12) for c in (0, 1)], axis=1)
    w = sosfilt(butter(2, 350, 'high', fs=SR, output='sos'), 0.6 * x + octave * hi, axis=0)
    return reverb(w, secs=secs)


def rms(x):
    return np.sqrt((x ** 2).mean())


def build(src):
    x = load(src)
    nb = int(round(BAR * SR))
    body = splice([(x, at(a), at(b + 1)) for a, b in KEEP])
    level = rms(x[at(5):at(9)])   # the band with the tune

    # the bloom: the band itself, from bar 4 (Em-A, the groove without the tune, which leads into D as the song does),
    # heard muffled and quieter and opening up to full across the bar; a light shimmer over it and a soft swell into
    # the downbeat, where the tune comes in
    dry = x[at(4):at(4) + nb]
    c = (np.linspace(0, 1, nb) ** 1.5)[:, None]
    muffled = sosfilt(butter(2, 1300, 'low', fs=SR, output='sos'), dry, axis=0)
    bloom = (muffled * (1 - c) + dry * c) * (0.82 + 0.18 * c)
    wash = shimmer(dry, octave=0.35, secs=2.2)
    wash *= 0.18 * level / rms(wash[:nb])
    bloom += wash[:nb] * (0.3 + 0.7 * c)
    beat = nb // 4
    rev = reverb(x[at(3):at(3) + beat] * 0.8, secs=1.2)[::-1]
    rev = rev[-beat:] if len(rev) >= beat else np.vstack([np.zeros((beat - len(rev), 2)), rev])
    rev *= 0.2 * level / (rms(rev) + 1e-9)
    env = np.linspace(0, 1, beat) ** 2
    f = int(0.03 * SR)
    env[-f:] *= np.linspace(1, 0, f) ** 2   # it swells, then gets out of the way of the real downbeat
    bloom[-beat:] += rev * env[:, None]
    # the shimmer's tail lingers a moment under bar 3
    glow = wash[nb:nb + nb // 2] * (np.linspace(1, 0, len(wash[nb:nb + nb // 2])) ** 2)[:, None]
    body[:len(glow)] += glow

    # the last bar leans toward the bloom: its top eases off a little over the last two beats, a touch of shimmer
    last = body[-nb:].copy()
    soft = sosfilt(butter(2, 3000, 'low', fs=SR, output='sos'), last, axis=0)
    ramp = np.clip((np.arange(nb) - nb / 2) / (nb / 2), 0, 1)[:, None]
    body[-nb:] = last * (1 - 0.3 * ramp) + soft * 0.3 * ramp
    tail_wash = shimmer(x[at(34):at(35)], octave=0.35, secs=2.2)
    tail_wash *= 0.15 * level / rms(tail_wash[:nb])
    body[-nb:] += tail_wash[:nb] * (np.linspace(0, 1, nb) ** 2)[:, None]

    # hand over to the band's first downbeat the way the joins do: the bloom's last 10 ms crossfade into what led up
    # to bar 3 in the take
    L = int(0.01 * SR)
    k = np.linspace(0, np.pi / 2, L)[:, None]
    bloom[-L:] = bloom[-L:] * np.cos(k) + x[at(3) - L:at(3)] * np.sin(k)
    loop = np.vstack([bloom, body])
    # what rang on past the last bar (the take's next 1.5 s, eased, and the tail's wash) folds onto the start
    ring = x[at(35):at(35) + int(1.0 * SR)] * 0.35 * np.linspace(1, 0, int(1.0 * SR))[:, None] ** 2
    ring = sosfilt(butter(2, 2500, 'low', fs=SR, output='sos'), ring, axis=0)
    loop[:len(ring)] += ring
    spill = tail_wash[nb:nb + 2 * nb]
    loop[:len(spill)] += spill * np.linspace(1, 0, len(spill))[:, None]
    # the wrap itself: an 8 ms ease on each side, so the last sample never jumps to the first
    e = int(0.008 * SR)
    loop[:e] *= np.linspace(0, 1, e)[:, None]
    loop[-e:] *= np.linspace(1, 0, e)[:, None]
    return loop


def master(loop, out):
    tmp = os.path.join(out, 'village_loop.f32')
    loop.astype(np.float32).tofile(tmp)
    src = ['-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', tmp]
    bus = 'acompressor=threshold=-20dB:ratio=2:attack=20:release=200:makeup=1.5'
    meas = subprocess.run(['ffmpeg', '-hide_banner', *src, '-af', bus + ',loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json',
                           '-f', 'null', '-'], capture_output=True, text=True).stderr
    m = json.loads(meas[meas.rindex('{'):meas.rindex('}') + 1])
    ln = ('loudnorm=I=-16:TP=-1.5:LRA=11:measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:offset=%s:linear=true'
          % (m['input_i'], m['input_tp'], m['input_lra'], m['input_thresh'], m['target_offset']))
    paths = []
    for ext, codec in (('ogg', ['-c:a', 'libvorbis', '-q:a', '6']), ('mp3', ['-c:a', 'libmp3lame', '-q:a', '2'])):
        p = os.path.join(out, 'mus_village.' + ext)
        subprocess.run(['ffmpeg', '-v', 'error', '-y', *src, '-af', bus + ',' + ln, *codec, p], check=True)
        paths.append(p)
    os.remove(tmp)
    return paths


if __name__ == '__main__':
    os.makedirs(sys.argv[2], exist_ok=True)
    lp = build(sys.argv[1])
    print('%.2f s, %d bars' % (len(lp) / SR, round(len(lp) / SR / BAR)), master(lp, sys.argv[2]))

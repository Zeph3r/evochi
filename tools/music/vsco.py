"""A small sampler over the Versilian Community Sample Library 2 (VSCO 2 Community Edition, CC0: public domain;
https://github.com/sgossner/VSCO-2-CE): the instruments the onboarding score uses, played note by note with numpy.

Each sample's pitch is checked by ear (the library names some instruments an octave off): its fundamental is measured and
the instrument's octave offset is the one most of its samples agree on. Velocity layers are levelled to one loudness, so
a note's velocity picks its timbre (a soft or a hard bow, a light or a firm pluck) and its gain separately. A note longer
than its sample is held by crossfading the sample's middle over itself.

    import vsco
    mx = vsco.Mix(10)
    mx.note('harp', 0.5, 2.0, 62, 0.6, pan=-0.3)
    vsco.master(mx.render(), '/tmp/x.wav', lufs=-18)
"""
from __future__ import annotations

import glob
import math
import os
import re
import subprocess

import numpy as np
import soundfile as sf
from scipy.signal import butter, fftconvolve, sosfilt

SR = 44100
ROOT = os.environ.get('VSCO', '/home/claude/sgossner/vsco-2-ce')
_PC = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def note_midi(n):
    """'F#5' -> 78 (sharps only, as the library names them)"""
    m = re.match(r'([A-G])(#?)(-?\d)$', n)
    return 12 * (int(m.group(3)) + 1) + _PC[m.group(1)] + (1 if m.group(2) else 0)


# name: (glob under ROOT, regex giving (note, layer) or a key-number map, kind, attack s, release s)
INSTRUMENTS = {
    'harp': ('Strings/Harp/KSHarp_*.wav', r'KSHarp_([A-G]#?\d)_(\w+)\.wav', 'pluck', 0.0, 0.6),
    'glock': ('Percussion/Glock/glock_medium_*.wav', r'glock_medium_([A-G]#?\d)()\.wav', 'pluck', 0.0, 0.8),
    'flute': ('Woodwinds/Flute/susNV/*.wav', r'susNV_([A-G]#?\d)_v(\d)', 'sus', 0.04, 0.35),
    'clarinet': ('Woodwinds/Clarinet/susLong/*.wav', r'susLong_([A-G]#?\d)_v(\d)', 'sus', 0.03, 0.3),
    'violins': ('Strings/Violin Section/susVib/*.wav', r'susVib_([A-G]#?\d)_v(\d)', 'sus', 0.09, 0.55),
    'violas': ('Strings/Viola Section/susvib/*.wav', r'susvib_([A-G]#?\d)_v(\d)', 'sus', 0.09, 0.55),
    'celli': ('Strings/Cello Section/susvib/*.wav', r'susvib_([A-G]#?\d)_v(\d)', 'sus', 0.08, 0.55),
    'bass': ('Strings/Solo Contrabass/SusNV/*.wav', r'SusNV_([A-G]#?\d)_v(\d)', 'sus', 0.08, 0.5),
    'pizz': ('Strings/Violin Section/Pizz/*_rr1.wav', r'Pizz_([A-G]#?\d)_v(\d)', 'pluck', 0.0, 0.25),
    # tremolo sections (the Hollow's shiver)
    'vln_trem': ('Strings/Violin Section/Trem/*.wav', r'Trem_([A-G]#?\d)_v(\d)', 'sus', 0.05, 0.4),
    'vla_trem': ('Strings/Viola Section/trem/*_rr1.wav', r'trem_([A-G]#?\d)_v(\d)', 'sus', 0.05, 0.4),
    'vc_trem': ('Strings/Cello Section/trem/*.wav', r'trem_([A-G]#?\d)_v(\d)', 'sus', 0.05, 0.45),
    'cb_trem': ('Strings/Solo Contrabass/Trem/*_rr1.wav', r'Trem_([A-G]#?\d)_v(\d)', 'sus', 0.05, 0.45),
    'piano': ('Keys/Upright Piano/Player_dyn*_rr1_*.wav', 'piano', 'pluck', 0.0, 0.5),
}

# one-off sounds: name -> path under ROOT
SOUNDS = {
    'cym_roll': 'VSCO 1 Percussion/varMetal/Cymbals/susp/susp_hit_softmall_roll2_cresc.wav',
    'cym_soft': 'VSCO 1 Percussion/varMetal/Cymbals/susp/susp_hit_softmall_mp.wav',
    'cym_hit': 'VSCO 1 Percussion/varMetal/Cymbals/susp/susp_hit_softmall_f.wav',
    'timp_roll': 'Percussion/Timpani/Rolls/Timpani1_Roll_v5_rr1_Sum.wav',      # ~F#2: shifted to taste
    'timp_roll_soft': 'Percussion/Timpani/Rolls/Timpani1_Roll_v3_rr1_Sum.wav',
    'glock_up': 'Miscellania Raw/Misc 2/glock_glisses/glock_fx_up_pentatonic_med_01.wav',
    'glock_up_fast': 'Miscellania Raw/Misc 2/glock_glisses/glock_fx_up_chromatic_fast_01.wav',
    'triangle': 'VSCO 1 Percussion/varMetal/triangle/3/triangle3_hit_pp.wav',
    'triangle_roll': 'VSCO 1 Percussion/varMetal/triangle/3/triangle3_roll.wav',
}


def _read(path):
    x, sr = sf.read(path, always_2d=True, dtype='float32')
    if x.shape[1] == 1:
        x = np.repeat(x, 2, axis=1)
    x = x[:, :2]
    if sr != SR:
        import librosa
        x = np.stack([librosa.resample(x[:, c], orig_sr=sr, target_sr=SR) for c in range(2)], 1)
    return x


def _onset(x, db=-42):
    m = np.abs(x).max(1)
    thr = m.max() * 10 ** (db / 20)
    i = int(np.argmax(m > thr))
    return max(0, i - 64)


def _speak(x, db=-9.0, pre=0.03):
    """a bowed or blown sample starts where it speaks (within [db] of its first second's peak), not at its first
    breath: the slow swell of a soft bow would put every note of a tune late"""
    env = np.convolve(np.abs(x).max(1), np.ones(441) / 441, 'same')[:int(1.2 * SR)]
    i = int(np.argmax(env > env.max() * 10 ** (db / 20)))
    a = max(0, i - int(pre * SR))
    y = x[a:].copy()
    k = int(pre * SR)
    y[:k] *= np.sin(np.linspace(0, np.pi / 2, k))[:, None] ** 2
    return y


def _f0(x):
    """the fundamental (Hz) a little way into the note, by autocorrelation"""
    a = int(0.12 * SR)
    seg = x[a:a + int(0.25 * SR)].mean(1)
    if len(seg) < 2048:
        seg = x[:int(0.25 * SR)].mean(1)
    seg = seg - seg.mean()
    n = 1 << int(math.ceil(math.log2(len(seg) * 2)))
    F = np.fft.rfft(seg * np.hanning(len(seg)), n)
    ac = np.fft.irfft(F * np.conj(F))[:len(seg)]
    lo, hi = int(SR / 2500), int(SR / 30)
    k = lo + int(np.argmax(ac[lo:hi]))
    # prefer the shortest lag that is nearly as strong (avoid the octave below)
    for div in (4, 3, 2):
        kk = int(round(k / div))
        if kk > lo and ac[kk - 2:kk + 3].max() > 0.85 * ac[k]:
            k = kk + int(np.argmax(ac[kk - 2:kk + 3])) - 2
            break
    return SR / k


class Layer:
    __slots__ = ('data', 'gain')

    def __init__(self, data, gain):
        self.data, self.gain = data, gain


class Instrument:
    def __init__(self, name):
        pattern, rx, self.kind, self.att, self.rel = INSTRUMENTS[name]
        self.name = name
        files = sorted(glob.glob(os.path.join(ROOT, pattern)))
        assert files, 'no samples for %s under %s' % (name, ROOT)
        keymap = None
        if rx == 'piano':
            keymap = {}
            for line in open(os.path.join(ROOT, 'Keys/Upright Piano/MappingChart.txt')):
                if '=' in line and line[:3].isdigit():
                    a, b = line.strip().split('=')
                    keymap[a] = int(b)
        raw = {}   # named midi -> [(layer key, data)]
        for f in files:
            base = os.path.basename(f)
            if keymap is not None:
                m = re.search(r'dyn(\d+)_rr1_(\d+)\.wav', base)
                if not m or m.group(2) not in keymap:
                    continue
                named, layer = keymap[m.group(2)], m.group(1)
            else:
                m = re.search(rx, base)
                if not m:
                    continue
                named, layer = note_midi(m.group(1)), m.group(2)
            x = _read(f)
            x = x[_onset(x):]
            if self.kind == 'sus':
                x = _speak(x, db=-5.0 if name in ('violins', 'violas', 'celli') else -9.0)
            raw.setdefault(named, []).append((layer, x))
        # the octave the library's names are off by, by majority
        votes = {}
        for named, lst in list(raw.items())[::max(1, len(raw) // 8)]:
            x = lst[-1][1]
            try:
                d = 69 + 12 * math.log2(_f0(x) / 440) - named
            except Exception:
                continue
            k = int(round(d / 12))
            if abs(d - 12 * k) < 0.7:
                votes[k] = votes.get(k, 0) + 1
        self.offset = 12 * max(votes, key=votes.get) if votes else 0
        self.roots = {}
        for named, lst in raw.items():
            layers = []
            for _, x in lst:
                n = min(len(x), int(0.7 * SR))
                rms = float(np.sqrt((x[:n] ** 2).mean()) + 1e-9)
                layers.append((rms, x))
            layers.sort(key=lambda r: r[0])
            self.roots[named + self.offset] = [Layer(x, 0.1 / rms) for rms, x in layers]
        self.keys = np.array(sorted(self.roots))

    def pick(self, pitch, vel):
        # the nearest sample, from above on a tie (pitched down sounds kinder than up)
        d = self.keys - pitch
        i = int(np.argmin(np.abs(d) - 0.01 * (d > 0)))
        root = int(self.keys[i])
        layers = self.roots[root]
        j = min(len(layers) - 1, int(vel * len(layers) * 0.999))
        return root, layers[j]


_CACHE = {}


def inst(name):
    if name not in _CACHE:
        _CACHE[name] = Instrument(name)
    return _CACHE[name]


_SOUNDS = {}


def sound(name):
    if name not in _SOUNDS:
        p = SOUNDS.get(name, name)
        x = _read(p if os.path.isabs(p) else os.path.join(ROOT, p))
        _SOUNDS[name] = x[_onset(x):]
    return _SOUNDS[name]


def decode(path):
    """any audio file (an mp3 from the game's assets) as float32 stereo at SR"""
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).copy()


def _extend(x, n):
    """hold a sustained sample longer than it was recorded: crossfade its middle over itself"""
    if len(x) >= n:
        return x
    a, b = int(len(x) * 0.35), int(len(x) * 0.8)
    xf = min(int(0.4 * SR), (b - a) // 3)
    out = x[:b].copy()
    seg = x[a:b]
    w = np.linspace(0, 1, xf)[:, None]
    while len(out) < n:
        head = out[-xf:] * np.cos(w * np.pi / 2) + seg[:xf] * np.sin(w * np.pi / 2)
        out = np.concatenate([out[:-xf], head, seg[xf:]])
    return out


def vel_gain(v):
    return 10 ** (-30 * (1 - max(0.0, min(1.0, v))) ** 1.25 / 20)


def play(name, pitch, dur, vel, bend=None, att=None, rel=None, ring=None, start=0.0):
    """one note as stereo float32: [pitch] in MIDI (fractions allowed); [bend](t) adds semitones over the note;
    a pluck rings [ring] s past [dur] (default: as long as it sounds) before its release"""
    I = inst(name)
    root, L = I.pick(int(round(pitch)), vel)
    att = I.att if att is None else att
    rel = I.rel if rel is None else rel
    x = L.data[int(start * SR):]
    if I.kind == 'sus':
        hold = dur
    else:
        hold = dur + (ring if ring is not None else 30.0)
    n = int((hold + rel) * SR)
    base = 2 ** ((pitch - root) / 12)
    if bend is None:
        ratio = np.full(n, base)
    else:
        t = np.arange(n) / SR
        ratio = base * 2 ** (np.asarray(bend(t), float) / 12)
    pos = np.concatenate([[0.0], np.cumsum(ratio[:-1])])
    need = int(pos[-1]) + 2
    if I.kind == 'sus':
        x = _extend(x, need)
    pos = pos[pos < len(x) - 1]
    i0 = pos.astype(np.int64)
    fr = (pos - i0)[:, None]
    y = x[i0] * (1 - fr) + x[i0 + 1] * fr
    m = len(y)
    env = np.ones(m, np.float32)
    if att > 0:
        k = min(m, int(att * SR))
        env[:k] = np.sin(np.linspace(0, np.pi / 2, k)) ** 2
    h = int(hold * SR)
    if h < m:
        k = min(m - h, int(rel * SR))
        env[h:h + k] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
        env[h + k:] = 0
    y = y * env[:, None]
    # trim the silent end
    nz = np.nonzero(np.abs(y).max(1) > 1e-5)[0]
    y = y[:nz[-1] + 1] if len(nz) else y[:1]
    return (y * (L.gain * vel_gain(vel))).astype(np.float32)


def pan_stereo(y, pan):
    """constant power, -1 left .. 1 right"""
    a = (pan + 1) * np.pi / 4
    return y * np.array([math.cos(a), math.sin(a)], np.float32) * math.sqrt(2)


def hall_ir(rt=2.4, length=3.6, pre=0.02, seed=3):
    n = int(length * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    out = np.zeros((n, 2), np.float32)
    lo = butter(2, 450, 'low', fs=SR, output='sos')
    mid = butter(2, [450, 3800], 'band', fs=SR, output='sos')
    hi = butter(2, 3800, 'high', fs=SR, output='sos')
    for c in range(2):
        w = rng.standard_normal(n)
        y = (sosfilt(lo, w) * np.exp(-6.91 * t / (rt * 1.2)) + sosfilt(mid, w) * np.exp(-6.91 * t / rt)
             + 0.6 * sosfilt(hi, w) * np.exp(-6.91 * t / (rt * 0.4)))
        y *= 1 - np.exp(-t / 0.015)
        out[:, c] = y
    k = int(pre * SR)
    out = np.concatenate([np.zeros((k, 2), np.float32), out[:-k]])
    return out / np.sqrt((out ** 2).sum() / 2)


class Mix:
    """buses of stereo audio; each has a reverb send and an optional effect, summed by render()"""

    def __init__(self, seconds, seed=5):
        self.n = int(seconds * SR)
        self.bus = {}
        self.send = {}
        self.fx = {}
        self.env = {}
        self.rng = np.random.default_rng(seed)

    def _b(self, name):
        if name not in self.bus:
            self.bus[name] = np.zeros((self.n, 2), np.float32)
            self.send.setdefault(name, 0.28)
        return self.bus[name]

    def put(self, t, y, bus='main', pan=0.0, gain=1.0):
        b = self._b(bus)
        a = int(round(t * SR))
        if a >= self.n or len(y) == 0:
            return
        if a < 0:
            y, a = y[-a:], 0
        y = pan_stereo(y, pan) * gain
        m = min(len(y), self.n - a)
        b[a:a + m] += y[:m]

    def note(self, name, t, dur, pitch, vel=0.6, pan=0.0, bus='main', gain=1.0, human=0.006, **kw):
        if human:
            t += float(self.rng.uniform(-human, human))
        self.put(t, play(name, pitch, dur, vel, **kw), bus, pan, gain)

    def sfx(self, name, t, gain=1.0, pan=0.0, bus='main', rate=1.0, reverse=False, end=None, fade_out=0.0):
        x = sound(name)
        if reverse:
            x = x[::-1].copy()
        if rate != 1.0:
            pos = np.arange(0, len(x) - 1, rate)
            i0 = pos.astype(np.int64)
            fr = (pos - i0)[:, None]
            x = x[i0] * (1 - fr) + x[i0 + 1] * fr
        if end is not None:
            x = x[:int(end * SR)].copy()
        if fade_out > 0:
            k = min(len(x), int(fade_out * SR))
            x[-k:] *= np.cos(np.linspace(0, np.pi / 2, k))[:, None] ** 2
        self.put(t, x.astype(np.float32), bus, pan, gain)

    def ramp(self, bus, points):
        """a gain envelope over a bus (applied as it is mixed): [(t, gain), ...] linear between points"""
        self._b(bus)
        self.env[bus] = points

    def render(self, rt=2.4, wet=1.0):
        dry = np.zeros((self.n, 2), np.float32)
        sendsum = np.zeros((self.n, 2), np.float32)
        for name, b in self.bus.items():
            if name in self.env:
                ts, gs = zip(*self.env[name])
                b = b * np.interp(np.arange(self.n) / SR, ts, gs).astype(np.float32)[:, None]
            if name in self.fx:
                b = self.fx[name](b)
            dry += b
            sendsum += b * self.send[name]
        ir = hall_ir(rt)
        w = np.stack([fftconvolve(sendsum[:, c], ir[:, c])[:self.n] for c in range(2)], 1).astype(np.float32)
        return dry + w * wet


def darken(x, points, cutoff=520):
    """crossfade a bus into a muffled copy of itself: [(t, 0..1)] how dark"""
    sos = butter(3, cutoff, 'low', fs=SR, output='sos')
    d = np.stack([sosfilt(sos, x[:, c]) for c in range(2)], 1).astype(np.float32)
    t = np.arange(len(x)) / SR
    ts, ks = zip(*points)
    k = np.interp(t, ts, ks).astype(np.float32)[:, None]
    return x * (1 - k) + d * k * 1.25


def master(x, path, lufs=-18.0, peak_db=-1.2, fade_in=0.0, fade_out=0.0, mp3=True):
    """level to [lufs] (integrated), a soft limit under [peak_db], and write an MP3 at [path] (or, mp3=False, a WAV)"""
    import pyloudnorm as pyln
    x = x.astype(np.float64)
    sos = butter(2, 28, 'high', fs=SR, output='sos')
    x = np.stack([sosfilt(sos, x[:, c]) for c in range(2)], 1)
    if fade_in > 0:
        k = int(fade_in * SR)
        x[:k] *= np.linspace(0, 1, k)[:, None]
    if fade_out > 0:
        k = int(fade_out * SR)
        x[-k:] *= np.cos(np.linspace(0, np.pi / 2, k))[:, None] ** 2
    meter = pyln.Meter(SR)
    try:
        cur = meter.integrated_loudness(x)
    except Exception:
        cur = -30.0
    if not np.isfinite(cur):
        cur = -40.0
    x *= 10 ** ((lufs - cur) / 20)
    ceil = 10 ** (peak_db / 20)
    # a soft knee above 70% of the ceiling
    k0 = 0.7 * ceil
    a = np.abs(x)
    over = a > k0
    x[over] = np.sign(x[over]) * (k0 + (ceil - k0) * np.tanh((a[over] - k0) / (ceil - k0)))
    if not mp3:
        sf.write(path, x.astype(np.float32), SR, subtype='FLOAT')
        return path
    import tempfile
    fd, wav = tempfile.mkstemp(suffix='.wav')
    os.close(fd)
    try:
        sf.write(wav, x.astype(np.float32), SR, subtype='FLOAT')
        out = os.path.splitext(path)[0] + '.mp3'
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', wav, '-c:a', 'libmp3lame', '-q:a', '3', out], check=True)
    finally:
        os.remove(wav)
    return out

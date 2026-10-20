"""Place ambiences for Evochi: one seamless loop per kind of place, synthesised (no samples).

Every loop is built to be exactly periodic: noise beds are shaped in the frequency domain (an inverse
FFT of a random-phase spectrum repeats by construction), modulations run a whole number of cycles per
loop, one-shot sounds wrap around the end, and the room reverb is a circular convolution. The client
still crossfades between passes (lib/core/services/audio_service.dart), so a codec's padding never
leaves a gap.

    python3 tools/art/ambience.py OUT_DIR     # writes amb_*.mp3 (needs ffmpeg with libmp3lame)
    python3 tools/art/ambience.py OUT_DIR --wav   # also keeps the wavs, for listening

Loops: amb_home (Home Map, Garden, the Cottage outside), amb_village, amb_kitchen, amb_apothecary,
amb_workshop, amb_lodge, amb_glasshouse, amb_forest (Mossy Ruins), amb_hollow (the ruins while the
Hollow holds them), amb_dusk (Sentinel Gate), amb_market. The Nest keeps ambient_meadow_loop.
"""
import os
import subprocess
import sys
import wave

import numpy as np

SR = 32000
L = 40.0
N = int(L * SR)
T = np.arange(N) / SR


# ------------------------------------------------------------------------- building blocks ----
def spectrum_noise(rng, shape):
    """Periodic noise whose magnitude spectrum is shape(f), unit RMS."""
    f = np.fft.rfftfreq(N, 1 / SR)
    mag = shape(np.maximum(f, 1.0))
    mag[0] = 0
    ph = rng.uniform(0, 2 * np.pi, len(f))
    x = np.fft.irfft(mag * np.exp(1j * ph), n=N)
    return x / (np.std(x) + 1e-12)


def band(lo, hi, tilt=0.0, order=4):
    """A soft band-pass shape between lo and hi Hz, with a spectral tilt (f**tilt)."""
    return lambda f: (1 / (1 + (lo / f) ** order)) * (1 / (1 + (f / hi) ** order)) * f ** tilt


def periodic_env(rng, maxc=24, rough=1.0, lo=0.0, hi=1.0):
    """A smooth random curve that repeats every loop, scaled to [lo, hi]."""
    x = np.zeros(N)
    for k in range(1, maxc + 1):
        x += rng.standard_normal() / k ** rough * np.sin(2 * np.pi * k * T / L + rng.uniform(0, 2 * np.pi))
    x = (x - x.min()) / (x.max() - x.min() + 1e-12)
    return lo + (hi - lo) * x


def fast_env(rng, lo_hz, hi_hz, count=40):
    """A quicker random modulation (whole cycles per loop), 0..1."""
    x = np.zeros(N)
    for _ in range(count):
        c = int(rng.uniform(lo_hz, hi_hz) * L)
        x += rng.uniform(0.3, 1) * np.sin(2 * np.pi * c * T / L + rng.uniform(0, 2 * np.pi))
    return (x - x.min()) / (x.max() - x.min() + 1e-12)


def place(out, ev, at):
    """Add a one-shot at time `at` (s), wrapping round the loop's end."""
    i0 = int(at * SR) % N
    idx = (i0 + np.arange(len(ev))) % N
    np.add.at(out, idx, ev)


def env_ad(n, a, d):
    t = np.arange(n) / SR
    return (1 - np.exp(-t / max(a, 1e-4))) * np.exp(-t / max(d, 1e-4))


def sweep(f, n):
    """A sine following the frequency curve f (array, Hz)."""
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def fft_filter(x, shape):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X * shape(np.maximum(f, 1.0)), n=len(x))


def circ_reverb(x, rng, rt=0.6, wet=0.25, tone=4000):
    """A room: an exponentially decaying noise tail, convolved circularly so the loop stays seamless."""
    n = int(rt * 1.5 * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-6.9 * t / rt)
    ir = fft_filter(ir, band(80, tone, order=2))
    ir[:int(0.008 * SR)] = 0  # a little pre-delay
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    h = np.zeros(N)
    h[:n] = ir
    y = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(h), n=N)
    return x * (1 - wet) + y * wet * (np.std(x) / (np.std(y) + 1e-12))


def norm(x):
    return x / (np.std(x) + 1e-12)


# --------------------------------------------------------------------------------- sounds ----
def bird(rng):
    kind = rng.choice(['chip', 'whistle', 'trill', 'warble'], p=[0.35, 0.25, 0.2, 0.2])
    if kind == 'chip':
        parts = []
        f0 = rng.uniform(2600, 3600)
        for _ in range(rng.integers(2, 5)):
            d = rng.uniform(0.05, 0.085)
            n = int(d * SR)
            t = np.arange(n) / SR
            parts.append(sweep(f0 + 900 * np.sin(np.pi * t / d), n) * env_ad(n, 0.004, d / 3))
            parts.append(np.zeros(int(rng.uniform(0.04, 0.09) * SR)))
        return np.concatenate(parts) * 0.8
    if kind == 'whistle':
        f1, f2 = rng.uniform(2700, 3400), rng.uniform(2100, 2700)
        out = []
        for f in (f1, f2) if rng.random() < 0.7 else (f1, f2, f2):
            n = int(rng.uniform(0.12, 0.18) * SR)
            t = np.arange(n) / SR
            e = np.clip(np.sin(np.pi * t / t[-1]), 0, None) ** 0.6
            out += [sweep(f * (1 + 0.01 * np.sin(2 * np.pi * 22 * t)), n) * e, np.zeros(int(0.05 * SR))]
        return np.concatenate(out) * 0.7
    if kind == 'trill':
        f0 = rng.uniform(4000, 5000)
        k = rng.integers(6, 13)
        out = []
        for i in range(k):
            n = int(0.022 * SR)
            t = np.arange(n) / SR
            out += [sweep(f0 * (1 - 0.06 * i / k) - 400 * t / 0.022, n) * np.sin(np.pi * t / t[-1]), np.zeros(int(0.022 * SR))]
        return np.concatenate(out) * 0.55
    n = int(rng.uniform(0.3, 0.5) * SR)
    t = np.arange(n) / SR
    f0 = rng.uniform(2200, 3000)
    return sweep(f0 + 550 * np.sin(2 * np.pi * rng.uniform(9, 14) * t), n) * np.clip(np.sin(np.pi * t / t[-1]), 0, None) ** 1.5 * 0.6


def birds(rng, count, level=1.0, muffle=None):
    out = np.zeros(N)
    for _ in range(count):
        b = bird(rng) * rng.uniform(0.35, 1.0)
        place(out, b, rng.uniform(0, L))
        if rng.random() < 0.4:  # an answer
            place(out, bird(rng) * rng.uniform(0.2, 0.5), rng.uniform(0, L))
    if muffle:
        out = fft_filter(out, band(200, muffle, order=3))
    return out * level


def crackle(rng, bright=True):
    n = int(rng.uniform(0.002, 0.009) * SR)
    t = np.arange(n) / SR
    e = rng.standard_normal(n) * np.exp(-t / rng.uniform(0.0008, 0.003))
    if bright:
        e = np.diff(e, prepend=0)
    return e * rng.lognormal(0, 0.6)


def pop(rng):
    n = int(0.03 * SR)
    t = np.arange(n) / SR
    e = rng.standard_normal(n) * np.exp(-t / 0.006)
    e = fft_filter(e, band(300, 2500))
    return e * rng.uniform(1.5, 3.0)


def fire(rng, roar=1.0, rate=3.0, pops=4, bright=1.0, crack=0.55):
    """A wood fire: a low breathing roar, a hiss, and crackles in clusters."""
    flick = periodic_env(rng, 60, 0.7, 0.55, 1.0)
    bed = spectrum_noise(rng, band(40, 380, -0.6)) * flick * roar
    hiss = spectrum_noise(rng, band(2500, 9000)) * periodic_env(rng, 40, 0.8, 0.1, 0.6) * 0.06 * bright
    cr = np.zeros(N)
    # clusters: a fire crackles in fits, not like a metronome
    busy = periodic_env(rng, 30, 0.6, 0.15, 1.0)
    k = int(rate * L)
    for _ in range(k * 2):
        at = rng.uniform(0, L)
        if rng.random() > busy[int(at * SR) % N]:
            continue
        c = crackle(rng, bright=rng.random() < 0.8)
        place(cr, c, at)
        if rng.random() < 0.35:  # a sputter: a couple more right after
            for j in range(rng.integers(1, 4)):
                place(cr, crackle(rng) * 0.6, at + 0.01 + j * rng.uniform(0.008, 0.03))
    for _ in range(pops):
        place(cr, pop(rng), rng.uniform(0, L))
    cr = fft_filter(cr, band(600, 7000 * bright + 1000, order=2))
    return bed * 0.5 + hiss + norm(cr) * crack


def bubble(rng, f0=None, tau=None):
    f0 = f0 or rng.uniform(280, 900)
    tau = tau or rng.uniform(0.012, 0.04)
    n = int(tau * 6 * SR)
    t = np.arange(n) / SR
    f = f0 * (1 + 0.9 * t / (tau * 6))
    return sweep(f, n) * (1 - np.exp(-t / 0.0015)) * np.exp(-t / tau)


def bubbling(rng, rate=8.0, deep=6):
    out = np.zeros(N)
    busy = periodic_env(rng, 40, 0.5, 0.3, 1.0)
    for _ in range(int(rate * L * 1.6)):
        at = rng.uniform(0, L)
        if rng.random() > busy[int(at * SR) % N]:
            continue
        place(out, bubble(rng) * rng.uniform(0.3, 1.0), at)
    for _ in range(deep):  # a big, slow blub
        at = rng.uniform(0, L)
        place(out, bubble(rng, rng.uniform(140, 220), rng.uniform(0.05, 0.09)) * 1.6, at)
        place(out, bubble(rng, rng.uniform(300, 420), 0.03) * 0.8, at + 0.07)
    return out


def drip(rng):
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    f = 900 + 600 * np.exp(-t / 0.012)
    x = sweep(f, n) * (1 - np.exp(-t / 0.001)) * np.exp(-t / 0.035)
    echo = np.zeros(int(0.35 * SR))
    echo[:n] += x
    echo[int(0.11 * SR):int(0.11 * SR) + n] += x * 0.25
    echo[int(0.23 * SR):int(0.23 * SR) + n] += x * 0.08
    return echo


def bell(rng, f, decay=0.6, partials=(1, 2.76, 5.4, 8.93), amps=(1, 0.5, 0.25, 0.12)):
    n = int(decay * 4 * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for p, a in zip(partials, amps):
        x += a * np.sin(2 * np.pi * f * p * t + rng.uniform(0, 6.28)) * np.exp(-t / (decay / p ** 0.6))
    return x * (1 - np.exp(-t / 0.0008))


def chimes(rng, clusters, level=1.0):
    out = np.zeros(N)
    notes = [1568, 1760, 2093, 2349, 2637, 3136]
    for _ in range(clusters):
        at = rng.uniform(0, L)
        for j in range(rng.integers(2, 6)):
            place(out, bell(rng, rng.choice(notes), 1.2, (1, 2.0, 3.01, 4.2), (1, 0.3, 0.12, 0.05)) * rng.uniform(0.3, 1), at + j * rng.uniform(0.12, 0.4))
    return out * level


def tick(rng, f):
    n = int(0.03 * SR)
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * f * t) + 0.6 * np.sin(2 * np.pi * f * 1.73 * t)) * np.exp(-t / 0.004) + rng.standard_normal(n) * np.exp(-t / 0.0015) * 0.4


def stream(rng):
    """Babbling water: band noise with a quick, bubbly modulation, and little plinks."""
    bed = spectrum_noise(rng, band(250, 3500, -0.3)) * (0.5 + 0.5 * fast_env(rng, 2, 9, 60))
    hi = spectrum_noise(rng, band(1500, 7000)) * fast_env(rng, 4, 16, 60) * 0.25
    pl = np.zeros(N)
    for _ in range(int(L * 6)):
        place(pl, bubble(rng, rng.uniform(600, 1600), rng.uniform(0.006, 0.015)) * rng.uniform(0.1, 0.5), rng.uniform(0, L))
    return bed + hi + pl * 0.8


def waterfall(rng, near=False):
    x = spectrum_noise(rng, band(60, 2600 if near else 1200, -0.45))
    return x * periodic_env(rng, 30, 1.2, 0.85, 1.0)


def wind(rng, gusty=1.0, top=700):
    g = periodic_env(rng, 14, 1.0, 0.25, 1.0) ** (1 + gusty)
    x = spectrum_noise(rng, band(70, top, -0.5)) * g
    # a faint whistle that comes with the gusts
    wh = spectrum_noise(rng, band(500, 900, order=8)) * g ** 2 * 0.12
    return x + wh, g


def leaves(rng, g):
    """Rustling foliage, louder in the gusts."""
    return spectrum_noise(rng, band(2000, 8000, order=2)) * (0.15 + 0.85 * g ** 1.5) * fast_env(rng, 3, 12, 50)


def room(rng):
    return spectrum_noise(rng, band(40, 300, -1.0))


def bee(rng):
    d = rng.uniform(1.5, 3.0)
    n = int(d * SR)
    t = np.arange(n) / SR
    f = rng.uniform(190, 240) * (1 + 0.04 * np.sin(2 * np.pi * 7 * t) + 0.06 * np.sin(np.pi * t / d))
    ph = 2 * np.pi * np.cumsum(f) / SR
    saw = sum(np.sin(k * ph) / k for k in range(1, 9))
    return fft_filter(saw, band(150, 1800)) * np.clip(np.sin(np.pi * t / d), 0, None) ** 2


def crickets(rng, voices=4):
    out = np.zeros(N)
    for v in range(voices):
        fc = rng.uniform(4100, 4900)
        period = rng.uniform(0.45, 0.9)
        k = int(L / period)
        period = L / k  # a whole number per loop
        pulses = rng.integers(2, 5)
        n = int(0.016 * SR)
        t = np.arange(n) / SR
        p = np.sin(2 * np.pi * fc * t) * np.clip(np.sin(np.pi * t / t[-1]), 0, None) ** 2
        lvl = rng.uniform(0.4, 1.0)
        rest = periodic_env(rng, 6, 1, 0, 1)  # each cricket pauses now and then
        off = rng.uniform(0, period)
        for i in range(k):
            at = off + i * period
            if rest[int(at * SR) % N] < 0.3:
                continue
            for j in range(pulses):
                place(out, p * lvl, at + j * 0.03)
    return out


def flaps(rng, g, count=8):
    out = np.zeros(N)
    for _ in range(count * 3):
        at = rng.uniform(0, L)
        if g[int(at * SR) % N] < 0.55:
            continue
        d = rng.uniform(0.3, 0.9)
        n = int(d * SR)
        t = np.arange(n) / SR
        am = (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * rng.uniform(11, 17) * t))) * np.sin(np.pi * t / d)
        out_ev = fft_filter(rng.standard_normal(n), band(200, 2500)) * am
        place(out, out_ev, at)
    return out


def hoot(rng):
    out = []
    for f, d in ((rng.uniform(380, 420), 0.35), (0, 0.18), (rng.uniform(340, 370), 0.5)):
        n = int(d * SR)
        t = np.arange(n) / SR
        out.append(np.zeros(n) if f == 0 else np.sin(2 * np.pi * f * t) * np.clip(np.sin(np.pi * t / d), 0, None) ** 1.5 * (1 + 0.2 * np.sin(2 * np.pi * 5 * t)))
    return np.concatenate(out)


def shimmer(rng):
    """A crystal's hum: soft sines that beat slowly, with a glassy top."""
    x = np.zeros(N)
    for f in (220.0, 330.0, 440.0, 660.0):
        for det in (-0.25, 0.25):  # whole-loop beat: a cycle every 2 s at 0.5 Hz difference
            x += np.sin(2 * np.pi * (f + det) * T) * (0.5 if f < 400 else 0.2)
    return x * periodic_env(rng, 8, 1, 0.4, 1.0)


def whoosh(rng):
    d = rng.uniform(1.0, 1.6)
    n = int(d * SR)
    t = np.arange(n) / SR
    return fft_filter(rng.standard_normal(n), band(150, 900)) * np.clip(np.sin(np.pi * t / d), 0, None) ** 2


# --------------------------------------------------------------------------------- scenes ----
def scene(name, rng):
    if name == 'amb_home':
        w, g = wind(rng, 1.0, 650)
        x = norm(w) * 0.42 + norm(leaves(rng, g)) * 0.14 + norm(waterfall(rng)) * 0.16 + birds(rng, 14, 0.75)
        bz = np.zeros(N)
        for _ in range(2):
            place(bz, bee(rng), rng.uniform(0, L))
        return circ_reverb(x + bz * 0.12, rng, 1.0, 0.12)
    if name == 'amb_village':
        w, g = wind(rng, 0.8, 600)
        x = norm(stream(rng)) * 0.22 + norm(waterfall(rng)) * 0.1 + norm(w) * 0.2 + norm(leaves(rng, g)) * 0.08
        x += birds(rng, 16, 0.9) + chimes(rng, 3, 0.2)
        cl = np.zeros(N)  # Bram, somewhere, tapping metal
        for _ in range(2):
            at = rng.uniform(0, L)
            for j in range(3):
                place(cl, bell(rng, rng.uniform(1500, 1900), 0.25) * (0.8 if j == 0 else 0.5), at + j * 0.55)
        x += fft_filter(cl, band(300, 3000)) * 0.08
        return circ_reverb(x, rng, 1.2, 0.15)
    if name == 'amb_kitchen':
        x = norm(room(rng)) * 0.12 + norm(fire(rng, roar=1.0, rate=2.2, pops=3, bright=0.7, crack=0.3)) * 0.6
        return circ_reverb(x, rng, 0.45, 0.28, 3500)
    if name == 'amb_apothecary':
        simmer = spectrum_noise(rng, band(100, 900, -0.5)) * periodic_env(rng, 30, 0.7, 0.6, 1.0)
        x = norm(room(rng)) * 0.1 + norm(simmer) * 0.14 + norm(bubbling(rng, 7.0, 6)) * 0.5
        x += norm(fire(rng, roar=0.7, rate=1.4, pops=1, bright=0.6, crack=0.22)) * 0.25
        gl = np.zeros(N)
        for _ in range(2):
            place(gl, bell(rng, rng.uniform(2600, 3400), 0.35, (1, 2.32, 4.1), (1, 0.4, 0.15)), rng.uniform(0, L))
        x += gl * 0.05
        return circ_reverb(x, rng, 0.5, 0.3, 4000)
    if name == 'amb_workshop':
        x = norm(room(rng)) * 0.1 + norm(fire(rng, roar=1.3, rate=4.0, pops=5, bright=0.9, crack=0.45)) * 0.6
        bl = np.zeros(N)
        for i in range(4):  # the bellows breathe on the forge now and then
            place(bl, whoosh(rng), i * L / 4 + rng.uniform(0, 3))
        x += norm(bl) * 0.12
        return circ_reverb(x, rng, 0.55, 0.3, 3500)
    if name == 'amb_lodge':
        w, g = wind(rng, 1.2, 400)
        x = norm(room(rng)) * 0.18 + norm(fft_filter(w, band(40, 300))) * 0.22
        tk = np.zeros(N)
        for i in range(int(L)):
            place(tk, tick(rng, 2100 if i % 2 == 0 else 1700) * 0.5, i + 0.0)
        x += norm(fft_filter(tk, band(700, 4500))) * 0.035 + birds(rng, 5, 0.3, muffle=1500)
        rs = np.zeros(N)  # someone turns a page
        for _ in range(2):
            n = int(0.25 * SR)
            t = np.arange(n) / SR
            place(rs, fft_filter(rng.standard_normal(n), band(1500, 6000)) * np.clip(np.sin(np.pi * t / t[-1]), 0, None) ** 3, rng.uniform(0, L))
        x += rs * 0.04
        return circ_reverb(x, rng, 0.7, 0.3, 3000)
    if name == 'amb_glasshouse':
        x = norm(room(rng)) * 0.08 + birds(rng, 11, 0.35, muffle=2400) + norm(stream(rng)) * 0.06
        dr = np.zeros(N)
        for _ in range(16):
            place(dr, drip(rng) * rng.uniform(0.4, 1.0), rng.uniform(0, L))
        bz = np.zeros(N)
        for _ in range(3):
            place(bz, bee(rng), rng.uniform(0, L))
        x += dr * 0.18 + bz * 0.1
        return circ_reverb(x, rng, 0.8, 0.3, 5000)
    if name == 'amb_forest':
        w, g = wind(rng, 1.0, 700)
        x = norm(waterfall(rng, near=True)) * 0.4 + norm(leaves(rng, g)) * 0.2 + norm(w) * 0.2 + birds(rng, 16, 0.6)
        return circ_reverb(x, rng, 1.4, 0.18)
    if name == 'amb_hollow':
        w, g = wind(rng, 1.4, 500)
        drone = np.sin(2 * np.pi * 110 * T) + np.sin(2 * np.pi * 110.5 * T) + 0.4 * np.sin(2 * np.pi * 164.75 * T)
        x = norm(w) * 0.4 + norm(waterfall(rng)) * 0.15 + norm(drone * periodic_env(rng, 6, 1, 0.3, 1.0)) * 0.08 + birds(rng, 3, 0.25)
        return circ_reverb(x, rng, 1.8, 0.25)
    if name == 'amb_dusk':
        w, g = wind(rng, 0.8, 500)
        x = norm(crickets(rng, 5)) * 0.3 + norm(w) * 0.25 + norm(waterfall(rng)) * 0.1 + norm(shimmer(rng)) * 0.06
        ho = np.zeros(N)
        for _ in range(2):
            place(ho, hoot(rng), rng.uniform(0, L))
        x += ho * 0.07
        return circ_reverb(x, rng, 1.6, 0.22)
    if name == 'amb_market':
        w, g = wind(rng, 1.1, 650)
        x = norm(w) * 0.38 + norm(flaps(rng, g, 9)) * 0.16 + birds(rng, 8, 0.4) + chimes(rng, 2, 0.12)
        return circ_reverb(x, rng, 1.0, 0.12)
    raise SystemExit(name)


SCENES = ['amb_home', 'amb_village', 'amb_kitchen', 'amb_apothecary', 'amb_workshop', 'amb_lodge', 'amb_glasshouse',
          'amb_forest', 'amb_hollow', 'amb_dusk', 'amb_market']


def finish(x):
    # loudness: a quiet bed (-26 dBFS RMS), peaks tamed by a soft knee
    x = x - np.mean(x)
    x = x / (np.sqrt(np.mean(x ** 2)) + 1e-12) * 10 ** (-26 / 20)
    return np.tanh(x * 1.6) / 1.6


def write_wav(path, x):
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def main():
    out = sys.argv[1]
    keep = '--wav' in sys.argv
    only = [a for a in sys.argv[2:] if a.startswith('amb_')]
    os.makedirs(out, exist_ok=True)
    for i, name in enumerate(SCENES):
        if only and name not in only:
            continue
        rng = np.random.default_rng(101 + i)
        x = finish(scene(name, rng))
        wav = os.path.join(out, name + '.wav')
        write_wav(wav, x)
        mp3 = os.path.join(out, name + '.mp3')
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-codec:a', 'libmp3lame', '-b:a', '80k', '-ac', '1', mp3], check=True)
        if not keep:
            os.remove(wav)
        print(name, f'{os.path.getsize(mp3) / 1024:.0f} KB', f'peak {np.max(np.abs(x)):.2f}')


if __name__ == '__main__':
    main()

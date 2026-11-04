"""Evochi's soundtrack in the game, from the same Evochi call as the onboarding (onboarding_score.py) and on the same
VSCO 2 CE samples (vsco.py, CC0): one piece for each place, the two encounter loops, and the stings for a level and
an evolution. Each piece is the call (or a turn of it: the Royal Road, Pip's hop, the bridge, the call in Dorian)
in the place's own key, tempo and band, so the world sounds like one score. The places' pieces play once and
then leave a quiet stretch (AudioService's playlists); the encounters loop.

    python3 evochi_score.py GAME_ROOT [piece ...]      (GAME_ROOT: flutter/; writes assets/audio/{music,ambient,sfx})

The plan it follows is the "Evochi Soundtrack" doc's: the toy box (glockenspiel, marimba, harp, pizzicato) with a
small orchestra behind it.
"""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import vsco                                      # noqa: E402
import onboarding_score as OS                    # noqa: E402
from evochi_themes import (BRIDGE, CH_A, CH_A2, CH_B, RR_A, RR_A2, ROYAL, THEME_A, THEME_A2, chord, melody, midi,
                           voicing)               # noqa: E402

TAIL = 3.0
NAMES = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B']
DORIAN = {6: -1, 1: -1}            # D major's F# and C# down: D Dorian


def tc(sym, k):
    """a chord symbol moved k semitones ('D/F#' + 5 -> 'G/B')"""
    bass = None
    if '/' in sym:
        sym, bass = sym.split('/')
    i = 1 + (1 if sym[1:2] in ('#', 'b') else 0)
    root, q = sym[:i], sym[i:]
    r = (NAMES.index(root) if root in NAMES else NAMES.index({'Db': 'C#', 'D#': 'Eb', 'G#': 'Ab', 'A#': 'Bb', 'Gb': 'F#'}[root]))
    out = NAMES[(r + k) % 12] + q
    if bass:
        b = bass if bass in NAMES else {'Db': 'C#', 'D#': 'Eb', 'G#': 'Ab', 'A#': 'Bb', 'Gb': 'F#'}[bass]
        out += '/' + NAMES[(NAMES.index(b) + k) % 12]
    return out


def bars_of(bars, k=0):
    """[['D'], ['A7sus4', 'A7']] -> [(sym, beats)], moved k semitones; bars of 4 beats unless a chord says ':3'"""
    out = []
    for bar in bars:
        n = 4
        for c in bar:
            if ':' in c:
                n = int(c.split(':')[1])
        for c in bar:
            out.append((tc(c.split(':')[0], k), n / len(bar)))
    return out


def notes(text, k=0, octave=0, beats=4, mode=None, bar0=0):
    out = []
    for b, d, p in melody(text, bar0=bar0, beats=beats):
        if mode:
            p += mode.get(p % 12, 0)
        out.append((b, d, p + k + 12 * octave))
    return out


def lead(mx, name, t0, bpm, ns, vel=0.5, pan=0.0, bus='lead', legato=1.0, **kw):
    sp = 60.0 / bpm
    for b, d, p in ns:
        mx.note(name, t0 + b * sp, d * sp * legato, p, vel, pan=pan, bus=bus, **kw)


def span(chs):
    return sum(L for _, L in chs)


# ------------------------------------------------------------------------------------------- the band's parts
def bass_line(mx, t0, bpm, chs, name='cello_pizz', vel=0.45, style='two', octave=2, bus='low', **kw):
    """the bass: 'two' (root on 1, fifth on 3), 'one' (a root a chord), 'walk' (quarters through the chord)"""
    sp, t = 60.0 / bpm, t0
    for sym, L in chs:
        r, iv, b = chord(sym)
        root = 12 * (octave + 1) + b
        if root > 12 * (octave + 1) + 7:
            root -= 12
        fifth = root + 7 if root + 7 <= 12 * (octave + 1) + 11 else root - 5
        if style == 'one' or L < 2:
            mx.note(name, t, L * sp * 0.95, root, vel, bus=bus, pan=-0.15, **kw)
        elif style == 'two':
            for k in range(0, int(L), 2):
                mx.note(name, t + k * sp, sp * 1.6, root if k % 4 == 0 else fifth, vel * (1 if k % 4 == 0 else 0.85), bus=bus, pan=-0.15, **kw)
        else:
            steps = [root, root + iv[1], fifth, root + iv[1] + 12 if root + iv[1] < fifth else root + iv[1]]
            for k in range(int(L)):
                mx.note(name, t + k * sp, sp * 0.9, steps[k % 4], vel * (1 if k % 2 == 0 else 0.85), bus=bus, pan=-0.15, **kw)
        t += L * sp
    return t


def chick(mx, t0, bpm, chs, name='pizz', vel=0.24, low=64, beats=(1, 3), n=3, bus='perc', pan=0.35, **kw):
    """the chord on the off beats (boom-chick: 2 and 4; a waltz: 2 and 3)"""
    sp, t = 60.0 / bpm, t0
    for sym, L in chs:
        v = voicing(sym, low, n)
        for b in beats:
            if b < L:
                for q, p in enumerate(v):
                    mx.note(name, t + b * sp + q * 0.008, 0.25, p, vel, bus=bus, pan=pan, **kw)
        t += L * sp


def arps(mx, t0, bpm, chs, name='harp', vel=0.28, low=57, step=0.5, shape=(0, 1, 2, 3, 2, 1, 2, 3), bus='harp', pan=0.15, **kw):
    sp, t = 60.0 / bpm, t0
    for sym, L in chs:
        v = voicing(sym, low, 4)
        for j in range(int(round(L / step))):
            mx.note(name, t + j * step * sp, step * sp * 2, v[shape[j % len(shape)] % len(v)], vel * (1.0 if j % 2 == 0 else 0.85),
                    bus=bus, pan=pan, **kw)
        t += L * sp


def pads(mx, t0, bpm, chs, vel=0.2, low=50, att=0.6, rel=0.6, bass=False, n=3, bus='strings'):
    sp, t = 60.0 / bpm, t0
    for sym, L in chs:
        OS.pad(mx, t, L * sp, sym, low=low, vel=vel, att=att, rel=rel, bass=bass, n=n, bus=bus)
        t += L * sp


def groove(mx, t0, bpm, beats, style, vel=1.0, bus='kit', beat=4):
    """light percussion over [beats] beats: shaker eighths, tambourine on 2 and 4, claves, brushes, a march,
    a log-drum figure, the triangle on each bar"""
    sp = 60.0 / bpm
    for k in range(int(beats * 2)):
        t = t0 + k * 0.5 * sp
        on = k % 2 == 0
        bt = (k // 2) % beat
        if 'shaker' in style:
            mx.sfx('shaker', t, gain=(0.22 if on else 0.14) * vel, pan=0.3, bus=bus)
        if 'tamb' in style and on and bt in (1, 3):
            mx.sfx('tamb', t, gain=0.2 * vel, pan=-0.3, bus=bus)
        if 'claves' in style and k % 16 in (0, 3, 6, 10, 12):
            mx.sfx('claves', t, gain=0.16 * vel, pan=0.4, bus=bus)
        if 'brush' in style and on and bt in (1, 3):
            mx.sfx('snare', t, gain=0.16 * vel, pan=0.1, bus=bus)
        if 'click' in style and on and bt in (1, 3):
            mx.sfx('click', t, gain=0.2 * vel, pan=0.1, bus=bus)
        if 'march' in style:
            if on and bt in (1, 3):
                mx.sfx('snare_mf', t, gain=0.18 * vel, bus=bus)
            elif not on:
                mx.sfx('snare', t, gain=0.08 * vel, bus=bus)
            if on and bt == 0:
                mx.sfx('bdrum_soft', t, gain=0.4 * vel, bus=bus)
        if 'log' in style and k % 8 in (0, 3, 6):
            mx.sfx('log', t, gain=0.22 * vel, pan=-0.2, bus=bus)
        if 'tri' in style and on and bt == 0 and (k // 2) % (beat * 2) == 0:
            mx.sfx('tri', t, gain=0.14 * vel, pan=0.45, bus=bus)
        if 'kick' in style and on and bt in (0, 2):
            mx.sfx('bdrum_soft', t, gain=0.35 * vel, bus=bus)


def glints(mx, t0, t1, n, k=0, vel=0.12, seed=1):
    """a few glockenspiel notes of the key's pentatonic, high and soft"""
    rng = np.random.default_rng(seed)
    scale = [midi(x) + k for x in ('D6', 'E6', 'F#6', 'A6', 'B6', 'D7')]
    for t in np.sort(rng.uniform(t0, t1, n)):
        mx.note('glock', float(t), 0.1, int(rng.choice(scale)), vel * float(rng.uniform(0.7, 1.1)), pan=float(rng.uniform(-0.6, 0.6)),
                bus='sparkle', ring=2.5, human=0)


def ending(mx, t, bpm, sym, k=0, vel=0.26, bass='celli'):
    """a held chord and a harp rolled up through it, to ring out on"""
    sp = 60.0 / bpm
    OS.pad(mx, t, 4 * sp, sym, low=50, vel=vel, att=0.3, rel=2.0, bass=False, n=3)
    r, iv, b = chord(sym)
    mx.note(bass, t, 4 * sp, 36 + b + (12 if b < 4 else 0), vel, rel=2.0, bus='low')
    OS.roll(mx, t, [p for p in voicing(sym, 50, 7)], vel=0.24, gap=0.07, dur=5)


# ================================================================================================ the pieces ===
def nest():
    """The Nest (the home screen): the Main Theme slowed to a lullaby. The call on celesta and flute over a harp,
    the answer on the violins, a breath of the bridge, the call once more on a music box, home."""
    bpm, sp = 80, 60 / 80
    k = 0
    A, A2 = bars_of(CH_A, k), bars_of(CH_A2, k)
    total = 18 * 4 * sp
    mx = OS.new_mix(total + TAIL + 2)
    t = 0.0
    # 1-2 a harp alone
    intro = bars_of([['Dmaj7'], ['Gmaj7']], k)
    arps(mx, t, bpm, intro, vel=0.24)
    pads(mx, t, bpm, intro, vel=0.14)
    t += 8 * sp
    # 3-6 the call, celesta (bell) and flute
    for b, d, p in notes(THEME_A, k):
        OS.bell(mx, t + b * sp, p, 0.34, bus='lead', ring=2.0)
    lead(mx, 'flute', t, bpm, notes(THEME_A, k), vel=0.34, pan=-0.1)
    arps(mx, t, bpm, A, vel=0.24)
    pads(mx, t, bpm, A, vel=0.16)
    bass_line(mx, t, bpm, A, name='celli', vel=0.24, style='one', att=0.3, rel=0.5)
    t += 16 * sp
    # 7-10 the answer on violins
    lead(mx, 'violins', t, bpm, notes(THEME_A2, k), vel=0.36, pan=0.2, att=0.08)
    arps(mx, t, bpm, A2, vel=0.24)
    pads(mx, t, bpm, A2, vel=0.16)
    bass_line(mx, t, bpm, A2, name='celli', vel=0.24, style='one', att=0.3, rel=0.5)
    t += 16 * sp
    # 11-14 the bridge's first half, clarinet, softly
    B = bars_of(CH_B[:4], k)
    lead(mx, 'clarinet', t, bpm, notes(' | '.join(BRIDGE.split('|')[:4]), k), vel=0.32, pan=-0.15)
    arps(mx, t, bpm, B, vel=0.22)
    pads(mx, t, bpm, B, vel=0.15)
    bass_line(mx, t, bpm, B, name='celli', vel=0.22, style='one', att=0.3, rel=0.5)
    t += 16 * sp
    # 15-18 the call again on the music box (glockenspiel high and soft), home on Dadd9
    for b, d, p in notes(THEME_A2.rsplit('|', 1)[0], k):
        mx.note('glock', t + b * sp, 0.1, p + 12, 0.24, bus='sparkle', ring=2.0, human=0)
        OS.bell(mx, t + b * sp, p, 0.22, bus='lead', ring=1.5)
    arps(mx, t, bpm, A2[:3], vel=0.22)
    pads(mx, t, bpm, A2[:3], vel=0.15)
    ending(mx, t + 12 * sp, bpm, tc('Dadd9', k), vel=0.22)
    glints(mx, 2, total, 8, k, seed=3)
    return mx, dict(lufs=-21.0)


def nest_road():
    """The Nest's other tune: the Royal Road (IV-V-iii-vi, never quite home) on marimba and flute, a soft piano
    under it, until its last phrase finds the way to D."""
    bpm, sp = 88, 60 / 88
    road = bars_of(ROYAL)
    home = bars_of([['Gmaj7'], ['A7sus4', 'A7'], ['D/F#', 'Bm7'], ['Em7', 'A7']])
    total = 16 * 4 * sp
    mx = OS.new_mix(total + TAIL + 4)
    t = 0.0
    for sec, mel, inst, ch in ((0, RR_A, 'marimba', road), (1, RR_A2, 'flute', home), (2, RR_A, 'flute', road), (3, RR_A2, 'marimba', home)):
        lead(mx, inst, t, bpm, notes(mel), vel=0.42 if inst == 'marimba' else 0.36, pan=-0.1)
        if sec >= 2:
            lead(mx, 'violins', t, bpm, notes(mel, octave=-1), vel=0.2, pan=0.25, att=0.08)
        # the soft piano: a low note, the chord rolled under the tune
        tt = t
        for sym, L in ch:
            r, iv, b = chord(sym)
            mx.note('piano', tt, L * sp, 36 + b + (12 if b < 4 else 0), 0.3, ring=0, rel=0.6, bus='harp')
            for i, p in enumerate(voicing(sym, 55, 3)):
                mx.note('piano', tt + 0.5 * sp + i * 0.12, L * sp - 0.5 * sp, p, 0.22, ring=0, rel=0.6, bus='harp')
            tt += L * sp
        bass_line(mx, t, bpm, ch, name='cello_pizz', vel=0.3, style='two')
        if sec in (1, 2):
            groove(mx, t, bpm, 16, 'shaker', vel=0.6)
        t += 16 * sp
    ending(mx, t, bpm, 'Dadd9', vel=0.2)
    glints(mx, 1, total, 6, seed=8)
    return mx, dict(lufs=-21.0)


def home():
    """Home grounds (the garden, the cottage path): the call in G with a skip in its step, clarinet staccato and
    marimba, pizzicato boom-chick, a shaker."""
    bpm, sp, k = 104, 60 / 104, 5
    A, A2 = bars_of(CH_A, k), bars_of(CH_A2, k)
    total = 16 * 4 * sp
    mx = OS.new_mix(total + TAIL + 3)
    t = 0.0
    for sec in range(4):
        mel, ch = (THEME_A, A) if sec % 2 == 0 else (THEME_A2, A2)
        if sec == 3:
            ch = A2[:3]
        inst = 'clar_stac' if sec < 2 else 'marimba'
        lead(mx, inst, t, bpm, notes(mel, k), vel=0.5 if inst == 'clar_stac' else 0.46, pan=-0.1, ring=0.3 if inst == 'clar_stac' else None)
        if sec >= 1:
            lead(mx, 'flute', t, bpm, notes(mel, k, octave=1 if sec == 2 else 0), vel=0.24, pan=0.2)
        bass_line(mx, t, bpm, ch, name='cello_pizz', vel=0.42, style='two')
        chick(mx, t, bpm, ch, vel=0.22)
        groove(mx, t, bpm, 16 if sec < 3 else 12, 'shaker tri', vel=0.8)
        t += 16 * sp
    ending(mx, t - 4 * sp, bpm, tc('Dadd9', k), vel=0.24)
    glints(mx, 2, total, 5, k, seed=5)
    return mx, dict(lufs=-20.5)


def village():
    """The Square: friendly, the call in D on flute and clarinet over harp and pizzicato, the bridge on the
    clarinet, everyone on the call to finish."""
    bpm, sp = 96, 60 / 96
    A, A2, B = bars_of(CH_A), bars_of(CH_A2), bars_of(CH_B)
    total = 24 * 4 * sp
    mx = OS.new_mix(total + TAIL + 3)
    t = 0.0
    lead(mx, 'flute', t, bpm, notes(THEME_A), vel=0.42, pan=-0.1)
    arps(mx, t, bpm, A, vel=0.26)
    bass_line(mx, t, bpm, A, vel=0.4)
    chick(mx, t, bpm, A, vel=0.2)
    groove(mx, t, bpm, 16, 'shaker', vel=0.6)
    t += 16 * sp
    lead(mx, 'clarinet', t, bpm, notes(THEME_A2), vel=0.42, pan=-0.15)
    lead(mx, 'flute', t, bpm, notes(THEME_A2, octave=1), vel=0.2, pan=0.15)
    arps(mx, t, bpm, A2, vel=0.26)
    bass_line(mx, t, bpm, A2, vel=0.4)
    chick(mx, t, bpm, A2, vel=0.2)
    groove(mx, t, bpm, 16, 'shaker tri', vel=0.7)
    t += 16 * sp
    lead(mx, 'clarinet', t, bpm, notes(BRIDGE), vel=0.4, pan=-0.15)
    pads(mx, t, bpm, B, vel=0.18)
    arps(mx, t, bpm, B, vel=0.22, step=1.0, shape=(0, 2, 1, 3))
    bass_line(mx, t, bpm, B, name='celli', vel=0.28, style='one', att=0.1, rel=0.4)
    t += 32 * sp
    lead(mx, 'violins', t, bpm, notes(THEME_A), vel=0.44, pan=0.2, att=0.05)
    lead(mx, 'flute', t, bpm, notes(THEME_A, octave=1), vel=0.3, pan=-0.15)
    lead(mx, 'xylo', t, bpm, notes(THEME_A), vel=0.18, pan=0.4)
    arps(mx, t, bpm, A, vel=0.28)
    bass_line(mx, t, bpm, A, vel=0.44)
    chick(mx, t, bpm, A, vel=0.22)
    pads(mx, t, bpm, A, vel=0.16)
    groove(mx, t, bpm, 16, 'shaker tamb', vel=0.8)
    t += 16 * sp
    ending(mx, t, bpm, 'Dadd9', vel=0.24)
    return mx, dict(lufs=-21.5)


def market():
    """Market day: bustling, the Royal Road in A on xylophone and marimba, a walking pizzicato bass,
    tambourine and claves."""
    bpm, sp, k = 116, 60 / 116, 7
    road = bars_of(ROYAL, k)
    home_ = bars_of([['Gmaj7'], ['A7sus4', 'A7'], ['D/F#', 'Bm7'], ['Em7', 'A7']], k)
    total = 16 * 4 * sp
    mx = OS.new_mix(total + TAIL + 3)
    t = 0.0
    for sec, (mel, ch) in enumerate(((RR_A, road), (RR_A2, home_), (RR_A, road), (RR_A2, home_))):
        lead(mx, 'xylo' if sec % 2 == 0 else 'marimba', t, bpm, notes(mel, k), vel=0.42 if sec % 2 else 0.36, pan=-0.1)
        if sec >= 2:
            lead(mx, 'clar_stac', t, bpm, notes(mel, k - 12), vel=0.34, pan=0.2)
        bass_line(mx, t, bpm, ch, name='cello_pizz', vel=0.42, style='walk')
        chick(mx, t, bpm, ch, vel=0.2, beats=(1, 2.5, 3), low=60)
        groove(mx, t, bpm, 16, 'tamb claves shaker' if sec else 'claves shaker', vel=0.8)
        t += 16 * sp
    ending(mx, t, bpm, tc('Dadd9', k), vel=0.22)
    return mx, dict(lufs=-21.0)


def kitchen():
    """The cottage kitchen: homely, Mira's 3/4 turn of the call in F on the piano, the clarinet answering, a
    waltz under them, a wood block now and then."""
    bpm, sp, k = 96, 60 / 96, 3
    mel = OS.MIRA[:16]
    ch = [(tc(c, k), 3) for c in OS.MIRA_CH[:16]]
    total = 16 * 3 * sp * 2
    mx = OS.new_mix(total + TAIL + 3)
    t = 0.0
    for sec in range(2):
        ns = notes(' | '.join(mel), k, beats=3)
        if sec == 0:
            for b, d, p in ns:
                mx.note('piano', t + b * sp, d * sp, p, 0.36, ring=0.6, rel=0.4, bus='lead', pan=-0.05)
        else:
            lead(mx, 'clarinet', t, bpm, ns, vel=0.38, pan=-0.15)
            for b, d, p in ns:
                mx.note('piano', t + b * sp, d * sp, p - 12, 0.18, ring=0.4, rel=0.4, bus='lead', pan=0.1)
        bass_line(mx, t, bpm, ch, name='cello_pizz', vel=0.36, style='one')
        chick(mx, t, bpm, ch, vel=0.2, beats=(1, 2), low=60)
        for i in range(16):
            if i % 2 == 1:
                mx.sfx('wood', t + (i * 3 + 2.5) * sp, gain=0.12, pan=0.4, bus='kit')
        t += 16 * 3 * sp
    ending(mx, t - 3 * sp, bpm, tc('Dadd9', k), vel=0.2)
    return mx, dict(lufs=-21.5)


def apothecary():
    """The apothecary: curious, the call in D Dorian on celesta and staccato clarinet over a marimba
    ostinato and a bassoon, pizzicato tiptoeing."""
    bpm, sp = 88, 60 / 88
    CH = bars_of([['Dm9'], ['G/D'], ['Dm9'], ['C', 'A7sus4']])
    CH2 = bars_of([['Dm9'], ['Bbmaj7'], ['C', 'A7sus4'], ['Dm9']])
    total = 16 * 4 * sp
    mx = OS.new_mix(total + TAIL + 3)
    t = 0.0
    ost = 'D4 .5 A4 .5 C5 .5 E5 .5 D4 .5 A4 .5 C5 .5 F5 .5'
    for sec in range(4):
        ch = CH if sec % 2 == 0 else CH2
        for bar in range(4):
            lead(mx, 'marimba', t + bar * 4 * sp, bpm, notes(ost), vel=0.3, pan=0.35, bus='harp')
        if sec > 0:
            mel = THEME_A if sec % 2 == 0 else THEME_A2.replace('B4 .5 D5 .5 G5', 'Bb4 .5 D5 .5 G5')
            ns = notes(mel, mode=DORIAN)
            if sec == 1:
                for b, d, p in ns:
                    OS.bell(mx, t + b * sp, p, 0.32, bus='lead', ring=1.5)
            else:
                lead(mx, 'clar_stac', t, bpm, ns, vel=0.42, pan=-0.15)
                lead(mx, 'flute', t, bpm, ns, vel=0.2, pan=0.1, octave=1 if sec == 3 else 0)
        bass_line(mx, t, bpm, ch, name='bassoon', vel=0.34, style='two', att=0.02, rel=0.2)
        if sec >= 2:
            groove(mx, t, bpm, 16, 'click', vel=0.6)
        t += 16 * sp
    ending(mx, t - 4 * sp, bpm, 'Dm9', vel=0.2, bass='bassoon')
    return mx, dict(lufs=-21.5)


def lodge():
    """The Guild Lodge: Pip's hop of the call, warm, in C: clarinet and flute, the horn under them, a bassoon
    bass, harp."""
    bpm, sp, k = 100, 60 / 100, -2
    A = OS.PIP_A[1:]
    B = OS.PIP_B[:6]
    chA = bars_of(OS.PIP_CH[1:9], k)
    chB = bars_of(OS.PIP_CH[9:15], k)
    total = 14 * 4 * sp + 4 * sp
    mx = OS.new_mix(total + TAIL + 3)
    t = 0.0
    lead(mx, 'clarinet', t, bpm, notes(' | '.join(A), k), vel=0.46, pan=-0.12, legato=0.9)
    lead(mx, 'horn', t, bpm, [(b, d, p) for b, d, p in notes(' | '.join(A), k - 12) if d >= 1], vel=0.26, pan=0.25)
    bass_line(mx, t, bpm, chA, name='bassoon', vel=0.34, style='two', att=0.02, rel=0.25)
    arps(mx, t, bpm, chA, vel=0.22, step=1.0, shape=(0, 1, 2, 3))
    t += 8 * 4 * sp
    lead(mx, 'flute', t, bpm, notes(' | '.join(B), k), vel=0.44, pan=0.1, legato=0.9)
    pads(mx, t, bpm, chB, vel=0.18)
    bass_line(mx, t, bpm, chB, name='bassoon', vel=0.32, style='two', att=0.02, rel=0.25)
    chick(mx, t, bpm, chB, vel=0.2)
    t += 6 * 4 * sp
    ending(mx, t, bpm, tc('Dadd9', k), vel=0.22)
    return mx, dict(lufs=-21.0)


def workshop():
    """Bram's workshop: sturdy, the call in E Dorian on low strings and the bassoon, a marimba ostinato, the
    anvil on the downbeats."""
    bpm, sp, k = 100, 60 / 100, 2
    CH = bars_of([['Dm9'], ['G/D'], ['Dm9'], ['C', 'A7sus4']], k)
    CH2 = bars_of([['Dm9'], ['Bbmaj7'], ['C', 'A7sus4'], ['Dm9']], k)
    total = 16 * 4 * sp
    mx = OS.new_mix(total + TAIL + 3)
    t = 0.0
    ost = 'D3 .5 D4 .5 A3 .5 D4 .5 C4 .5 D4 .5 A3 .5 G3 .5'
    for sec in range(4):
        ch = CH if sec % 2 == 0 else CH2
        for bar in range(4):
            lead(mx, 'marimba', t + bar * 4 * sp, bpm, notes(ost, k), vel=0.3, pan=0.3, bus='harp')
            if sec >= 1:
                mx.sfx('anvil_soft' if bar % 2 else 'anvil', t + bar * 4 * sp, gain=0.16, pan=-0.35, bus='kit')
        if sec >= 1:
            mel = THEME_A if sec % 2 == 1 else THEME_A2.replace('B4 .5 D5 .5 G5', 'Bb4 .5 D5 .5 G5')
            ns = notes(mel, k - 12, mode=None)
            ns = [(b, d, p + DORIAN.get((p - k) % 12, 0)) for b, d, p in ns]
            lead(mx, 'celli', t, bpm, ns, vel=0.42, pan=-0.15, att=0.04)
            if sec == 3:
                lead(mx, 'violas', t, bpm, ns, vel=0.3, pan=0.2, att=0.04, octave=1)
        bass_line(mx, t, bpm, ch, name='bassoon', vel=0.36, style='two', att=0.02, rel=0.2)
        groove(mx, t, bpm, 16, 'kick', vel=0.7)
        t += 16 * sp
    ending(mx, t - 4 * sp, bpm, tc('Dm9', k), vel=0.22, bass='bassoon')
    return mx, dict(lufs=-21.0)


def dusk():
    """Evening at the gate: reflective, the call slowly on the flute in Bb, the horn answering, harp and strings."""
    bpm, sp, k = 66, 60 / 66, -4
    A, A2 = bars_of(CH_A, k), bars_of(CH_A2, k)
    total = 8 * 4 * sp + 4 * sp
    mx = OS.new_mix(total + TAIL + 4)
    t = 0.0
    lead(mx, 'flute', t, bpm, notes(THEME_A, k), vel=0.36, pan=-0.1)
    arps(mx, t, bpm, A, vel=0.22, low=53)
    pads(mx, t, bpm, A, vel=0.17, att=1.0)
    bass_line(mx, t, bpm, A, name='celli', vel=0.22, style='one', att=0.4, rel=0.6)
    t += 16 * sp
    lead(mx, 'horn', t, bpm, notes(THEME_A2, k - 12), vel=0.3, pan=0.2)
    lead(mx, 'flute', t, bpm, notes(THEME_A2, k), vel=0.22, pan=-0.15)
    arps(mx, t, bpm, A2, vel=0.22, low=53)
    pads(mx, t, bpm, A2, vel=0.18, att=1.0)
    bass_line(mx, t, bpm, A2, name='celli', vel=0.22, style='one', att=0.4, rel=0.6)
    t += 16 * sp
    ending(mx, t - 4 * sp, bpm, tc('Dadd9', k), vel=0.2)
    glints(mx, 3, total, 4, k, seed=11)
    return mx, dict(lufs=-22.0)


def forest():
    """Out in the wilds (the wood, the trails, a raid's quiet stretches): wondrous, the call in D Dorian on the
    flute over a marimba ostinato and a cello drone, a clearing of D major, back into the trees."""
    bpm, sp = 92, 60 / 92
    CH = bars_of([['Dm9'], ['G/D'], ['Dm9'], ['C', 'A7sus4']])
    CH2 = bars_of([['Dm9'], ['Bbmaj7'], ['C', 'A7sus4'], ['Dm9']])
    clear = bars_of([['Dmaj7'], ['G6'], ['Em7'], ['A7sus4', 'A']])
    total = 20 * 4 * sp
    mx = OS.new_mix(total + TAIL + 3)
    t = 0.0
    ost = 'D4 .5 A4 .5 C5 .5 E5 .5 D4 .5 A4 .5 C5 .5 F5 .5'
    for sec, ch in enumerate((CH, CH2, clear, CH, CH2)):
        for bar in range(4):
            if sec != 2:
                lead(mx, 'marimba', t + bar * 4 * sp, bpm, notes(ost), vel=0.28, pan=0.35, bus='harp')
        if sec == 2:
            arps(mx, t, bpm, ch, vel=0.26)
            for b, d, p in notes(THEME_A, 12):
                mx.note('glock', t + b * sp, 0.1, p, 0.22, bus='sparkle', ring=2.0, human=0)
            pads(mx, t, bpm, ch, vel=0.18)
        else:
            mx.note('celli', t, 16 * sp, midi('D2'), 0.26, att=1.0, rel=0.8, bus='low')
            mx.note('bass', t, 16 * sp, midi('D2') - 12, 0.22, att=1.0, rel=0.8, bus='low')
        if sec in (1, 3, 4):
            mel = THEME_A if sec != 4 else THEME_A2.replace('B4 .5 D5 .5 G5', 'Bb4 .5 D5 .5 G5')
            if sec == 3:
                lead(mx, 'clarinet', t, bpm, notes(mel, mode=DORIAN, octave=-1), vel=0.4, pan=0.15)
                lead(mx, 'flute', t, bpm, notes(mel, mode=DORIAN), vel=0.2, pan=-0.15)
            else:
                lead(mx, 'flute', t, bpm, notes(mel, mode=DORIAN), vel=0.4, pan=-0.1)
                if sec == 4:
                    lead(mx, 'clarinet', t, bpm, notes(mel, mode=DORIAN, octave=-1), vel=0.26, pan=0.2)
        if sec >= 3:
            groove(mx, t, bpm, 16, 'log', vel=0.7)
        t += 16 * sp
    ending(mx, t - 4 * sp, bpm, 'Dm9', vel=0.2)
    return mx, dict(lufs=-21.5)


def trail():
    """The Old Trail: adventurous, the call in G striding out, the horn and clarinet, a light march, pizzicato."""
    bpm, sp, k = 108, 60 / 108, 5
    A, A2 = bars_of(CH_A, k), bars_of(CH_A2, k)
    total = 16 * 4 * sp
    mx = OS.new_mix(total + TAIL + 3)
    t = 0.0
    for sec in range(4):
        mel, ch = (THEME_A, A) if sec % 2 == 0 else (THEME_A2, A2)
        if sec == 3:
            ch = A2[:3]
        if sec < 2:
            lead(mx, 'clarinet', t, bpm, notes(mel, k), vel=0.44, pan=-0.12)
        else:
            lead(mx, 'horn', t, bpm, notes(mel, k - 12), vel=0.4, pan=0.15)
            lead(mx, 'flute', t, bpm, notes(mel, k), vel=0.3, pan=-0.15)
        bass_line(mx, t, bpm, ch, name='cello_pizz', vel=0.42, style='two')
        chick(mx, t, bpm, ch, vel=0.2)
        groove(mx, t, bpm, 16 if sec < 3 else 12, 'march' if sec >= 1 else 'shaker', vel=0.7)
        t += 16 * sp
    ending(mx, t - 4 * sp, bpm, tc('Dadd9', k), vel=0.24)
    return mx, dict(lufs=-21.0)


# the encounters: loops (the game plays them round and round); the Hollow's own motif against the call
HOLLOW = 'D3 1 Eb3 2 D3 1 | A2 1 Bb2 3'


def wild():
    """A wild Hollow (a skirmish): playful but on edge, D minor at 132; the Hollow's motif in the low pizzicato
    and bassoon, the call's head darting over it on xylophone and staccato flute, log drum and snare."""
    bpm, sp = 132, 60 / 132
    bars = 16
    loop = bars * 4 * sp
    mx = OS.new_mix(loop + TAIL + 1)
    CH = bars_of([['Dm'], ['Bb', 'A7'], ['Dm'], ['Gm', 'A7']])
    for rep in range(4):
        t = rep * 16 * sp
        for half in range(2):
            lead(mx, 'cello_pizz', t + half * 8 * sp, bpm, notes(HOLLOW), vel=0.5, pan=-0.15, bus='low')
            lead(mx, 'bassoon', t + half * 8 * sp, bpm, notes(HOLLOW), vel=0.28, pan=-0.1, bus='low', att=0.02, rel=0.15)
        # sixteenths of pizzicato on the chord, pushing it along
        tt = t
        for sym, L in CH:
            v = voicing(sym, 62, 3)
            for j in range(int(L * 2)):
                mx.note('pizz', tt + j * 0.5 * sp, 0.2, v[j % 3], 0.2 if j % 2 else 0.26, pan=0.35, bus='perc')
            tt += L * sp
        if rep in (1, 3):
            call = 'A4 .5 D5 .5 F5 .75 E5 .25 D5 1 r 1 | A4 .5 C5 .5 E5 .75 D5 .25 C#5 1 r 1 | ' \
                   'D5 .5 E5 .5 F5 .5 G5 .5 A5 1 r 1 | Bb5 .5 A5 .5 G5 .5 F5 .5 E5 1 r 1'
            lead(mx, 'xylo', t, bpm, notes(call, -12), vel=0.4, pan=0.1)
            lead(mx, 'flute_stac', t, bpm, notes(call), vel=0.32, pan=-0.2)
        elif rep == 2:
            lead(mx, 'violins', t, bpm, notes('D5 2 Eb5 2 | D5 4 | A4 2 Bb4 2 | A4 4'), vel=0.3, pan=0.25, att=0.1)
        groove(mx, t, bpm, 16, 'log brush' if rep else 'log', vel=0.9)
        mx.sfx('timp_d', t, gain=0.3, bus='kit')
    return mx, dict(lufs=-19.0, loop=loop)


def boss():
    """A Hollow guardian: big but bouncy, the motif on the horn and the low strings at full height, timpani on
    the downbeats, the violins shivering, and the call answering it in the brass."""
    bpm, sp = 120, 60 / 120
    bars = 16
    loop = bars * 4 * sp
    mx = OS.new_mix(loop + TAIL + 1)
    CH = bars_of([['Dm'], ['Bb', 'A7'], ['Dm'], ['Gm', 'A7']])
    for rep in range(4):
        t = rep * 16 * sp
        for half in range(2):
            ns = notes(HOLLOW)
            lead(mx, 'celli', t + half * 8 * sp, bpm, ns, vel=0.5, pan=-0.2, bus='low', att=0.02, rel=0.2)
            lead(mx, 'bass', t + half * 8 * sp, bpm, notes(HOLLOW, -12), vel=0.44, pan=-0.1, bus='low', att=0.02, rel=0.2)
            if rep >= 1:
                lead(mx, 'horn', t + half * 8 * sp, bpm, notes(HOLLOW, 12), vel=0.36, pan=0.2, att=0.03)
        for b in range(4):
            mx.sfx('timp_d' if b % 2 == 0 else 'timp_a', t + b * 4 * sp, gain=0.5, bus='kit')
            mx.sfx('timp_d', t + (b * 4 + 2.5) * sp, gain=0.3, bus='kit')
        if rep >= 2:
            for p, pan in ((midi('D5'), 0.3), (midi('A5'), 0.45)):
                mx.note('vln_trem', t, 16 * sp, p, 0.24, att=0.4, rel=0.3, bus='strings', pan=pan, human=0)
        if rep == 3:
            call = 'A4 .5 D5 .5 F5 1.5 E5 .5 D5 1 | C5 .5 E5 .5 F5 1.5 E5 .5 C#5 1 | D5 .5 E5 .5 F5 1 A5 1 G5 .5 E5 .5 | D5 2 A4 2'
            lead(mx, 'horn', t, bpm, notes(call, -12), vel=0.44, pan=0.1)
            lead(mx, 'violins', t, bpm, notes(call), vel=0.4, pan=0.3, att=0.04)
        tt = t
        for sym, L in CH:
            v = voicing(sym, 60, 3)
            for j in range(int(L * 2)):
                mx.note('pizz', tt + j * 0.5 * sp, 0.2, v[j % 3], 0.22, pan=0.35, bus='perc')
            tt += L * sp
        groove(mx, t, bpm, 16, 'march', vel=1.0)
    return mx, dict(lufs=-18.0, loop=loop)


def level_up():
    """A level: the call's first three notes, quick and bright, a harp up, the glockenspiel on top."""
    mx = OS.new_mix(3.2)
    for i, p in enumerate(('A4', 'D5', 'F#5', 'A5')):
        OS.bell(mx, 0.02 + 0.11 * i, p, 0.46, bus='lead', ring=1.6)
        mx.note('pizz', 0.02 + 0.11 * i, 0.2, midi(p), 0.34, bus='perc', human=0)
    OS.roll(mx, 0.0, ['D4', 'F#4', 'A4', 'D5', 'F#5', 'A5', 'D6'], vel=0.3, gap=0.035, dur=2)
    mx.note('glock', 0.5, 0.1, midi('D7'), 0.3, bus='sparkle', ring=2.0, human=0)
    return mx, dict(lufs=-17.0, fade_out=0.8)


def evolve():
    """An evolution: the call as a fanfare: horn and strings over a timpani roll, the glockenspiel and harp
    sweeping up into D."""
    mx = OS.new_mix(6.5)
    mx.sfx('timp_roll', 0.0, gain=0.4, rate=2 ** (-4 / 12), end=1.2, fade_out=0.1, bus='kit')
    mx.sfx('glock_up', 0.6, gain=0.3, pan=0.3, bus='sparkle')
    mx.sfx('cym_soft', 1.2, gain=0.22, bus='kit')
    bpm = 104
    for name, oc, vel, pan in (('horn', -1, 0.46, 0.15), ('violins', 0, 0.44, 0.3), ('flute', 1, 0.3, -0.2)):
        lead(mx, name, 1.2, bpm, notes('A4 .5 D5 .5 F#5 1.5 E5 .5 D5 1', octave=oc) + notes('A5 4', octave=oc, bar0=1), vel=vel, pan=pan)
    OS.pad(mx, 1.2, 4.0, 'Dadd9', low=50, vel=0.36, att=0.1, rel=1.6)
    mx.note('bass', 1.2, 4.0, midi('D2'), 0.4, rel=1.6, bus='low')
    mx.sfx('timp_d', 1.2, gain=0.5, bus='kit')
    OS.roll(mx, 3.4, ['D3', 'A3', 'D4', 'F#4', 'A4', 'D5', 'F#5', 'A5', 'D6'], vel=0.3, gap=0.04, dur=3)
    return mx, dict(lufs=-17.0, fade_out=1.5)


# name: (function, folder under assets/audio)
PIECES = {
    'mus_nest': (nest, 'music'), 'mus_nest_road': (nest_road, 'music'), 'mus_home': (home, 'music'),
    'mus_village': (village, 'music'), 'mus_market': (market, 'music'), 'mus_kitchen': (kitchen, 'music'),
    'mus_apothecary': (apothecary, 'music'), 'mus_lodge': (lodge, 'music'), 'mus_workshop': (workshop, 'music'),
    'mus_dusk': (dusk, 'music'), 'mus_forest': (forest, 'music'), 'mus_trail': (trail, 'music'),
    'enc_wild_loop': (wild, 'ambient'), 'enc_boss_loop': (boss, 'ambient'),
    'level_up': (level_up, 'sfx'), 'evolve_fanfare': (evolve, 'sfx'),
}


def render(name, game):
    fn, folder = PIECES[name]
    mx, opt = fn()
    x = mx.render(rt=2.3)
    loop = opt.get('loop')
    if loop:
        # a seamless loop: what rings on past its end is laid back over its start
        n, k = int(loop * vsco.SR), int(TAIL * vsco.SR)
        x[:k] += x[n:n + k]
        x = x[:n]
    else:
        nz = np.nonzero(np.abs(x).max(1) > 1e-4)[0]
        x = x[:min(len(x), (nz[-1] if len(nz) else len(x)) + int(0.3 * vsco.SR))]
    out = os.path.join(game, 'assets', 'audio', folder, name + '.mp3')
    path = vsco.master(x, out, lufs=opt['lufs'], fade_out=0.0 if loop else opt.get('fade_out', 1.5), vbr=5)
    print('%-16s %5.1fs  %4.0f KB  %s' % (name, len(x) / vsco.SR, os.path.getsize(path) / 1024, path), flush=True)
    return folder


def register(game, names):
    import json
    mp = os.path.join(game, 'assets', 'art', 'manifest.json')
    man = json.load(open(mp))
    for n in names:
        man['audio'][n] = PIECES[n][1] + '/' + n + '.mp3'
    json.dump(man, open(mp, 'w'), indent=1)


if __name__ == '__main__':
    game = os.path.abspath(sys.argv[1])
    names = sys.argv[2:] or list(PIECES)
    for n in names:
        render(n, game)
    register(game, names)

"""The onboarding's score, from the Evochi call (evochi_themes.py) and nothing else, played on the VSCO 2 Community
Edition samples (vsco.py, CC0). Written to the picture: the cold open's cues land on its shots (onboarding_cine.py), the
hatch's on hatch.json's beats, so each file starts when its screen says and needs no other sync.

    python3 onboarding_score.py OUT_DIR [cue ... | voices]   (OUT_DIR: flutter/assets/audio/music; the voices go
                                                              to its sibling sfx/)

The story the theme tells: the call's first note alone in the dark (the footprint); the call as the paths light; it
falters and goes out with the Hollow; the first note again, warmer, as Lumen answers a footstep; the village in the day,
where the phrase stops on its question (the dominant) as the picture fades. The title answers it. Pip and Mira get
their own turns of the call (a courier's hop, a glasshouse lullaby in 3/4). Waiting for the egg is near silence: each
crack your steps open plays the call's next note (A, D, F#). The hatch builds, holds its breath, bursts into the call.
Naming is a quiet harp. Only when its name is said does the whole Main Theme play, through to "home" (bar 8), carrying
into the Nest.

Loops (pip, mira, wait, naming) are LOOP s of music and TAIL s of ring-out after it: the game starts the next pass at
LOOP while the last one rings (audio_service.dart _Loop), so each loop ends on a held chord and begins on a downbeat.
"""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import vsco                               # noqa: E402
from evochi_themes import (THEME_A, THEME_A2, BRIDGE, chord, midi, melody, voicing)  # noqa: E402

GAME = os.path.normpath(os.path.join(HERE, '..', '..', 'flutter'))
TAIL = 3.0
D_PENTA = [midi(n) for n in ('D6', 'E6', 'F#6', 'A6', 'B6', 'D7', 'E7', 'F#7')]


def m(n):
    return midi(n) if isinstance(n, str) else n


def line(mx, name, t0, bpm, text, vel=0.55, beats=4, octave=0, legato=1.0, pan=0.0, bus='main', **kw):
    """a melody (evochi_themes' bar notation) from t0 at bpm"""
    sp = 60.0 / bpm
    for b, d, p in melody(text, beats=beats):
        mx.note(name, t0 + b * sp, d * sp * legato, p + 12 * octave, vel, pan=pan, bus=bus, **kw)


def bell(mx, t, p, vel=0.5, pan=0.0, bus='main', ring=6.0):
    """the celesta-ish bell the call's single notes ring on: soft piano with a glockenspiel an octave up"""
    p = m(p)
    mx.note('piano', t, 0.1, p, vel * 0.9, pan=pan, bus=bus, ring=ring, human=0)
    mx.note('glock', t, 0.1, p + 12, vel * 0.55, pan=pan + 0.1, bus=bus, ring=ring, human=0)


def roll(mx, t, notes, vel=0.45, gap=0.06, dur=3.0, pan=0.0, bus='main', name='harp'):
    for i, p in enumerate(notes):
        mx.note(name, t + i * gap, dur, m(p), vel * (0.9 + 0.1 * (i % 2)), pan=pan + 0.08 * (i % 3 - 1), bus=bus)


def pad(mx, t, dur, sym, low=50, vel=0.3, att=1.2, rel=1.0, bass=True, bus='strings', n=4, **kw):
    """the string section on a chord: celli the bass, violas and violins the voicing"""
    r, iv, b = chord(sym)
    if bass:
        root = 36 + b
        mx.note('celli', t, dur, root + (12 if root < 38 else 0), vel * 0.9, pan=-0.25, att=att, rel=rel, bus=bus, **kw)
    for i, p in enumerate(voicing(sym, low + 5, n)):
        name = 'violas' if p < 64 else 'violins'
        mx.note(name, t, dur, p, vel * (0.85 if name == 'violas' else 0.8), pan=(0.25 if name == 'violas' else 0.4) - 0.2 * i,
                att=att, rel=rel, bus=bus, **kw)


def harp_arp(mx, t0, bpm, chords, low=50, vel=0.32, step=0.5, shape=(0, 1, 2, 3, 2, 1), bus='harp', beats=4, bass=True):
    """chords [(sym, beats)] picked as eighths (a low root on the downbeat)"""
    sp = 60.0 / bpm
    t = t0
    for sym, L in chords:
        v = voicing(sym, low + 7, 4)
        r, iv, b = chord(sym)
        if bass:
            mx.note('harp', t, L * sp, 36 + b + (12 if 36 + b < 40 else 0), vel * 1.15, pan=-0.2, bus=bus)
        k = int(round(L / step))
        for j in range(k):
            if bass and j == 0:
                continue
            mx.note('harp', t + j * step * sp, step * sp * 2, v[shape[j % len(shape)] % len(v)], vel * (1.0 if j % 2 == 0 else 0.85),
                    pan=0.15, bus=bus)
        t += L * sp
    return t


def sparkle(mx, t0, t1, n, vel=0.18, seed=1, bus='sparkle'):
    rng = np.random.default_rng(seed)
    for t in np.sort(rng.uniform(t0, t1, n)):
        mx.note('glock', float(t), 0.1, int(rng.choice(D_PENTA)), vel * float(rng.uniform(0.7, 1.1)), pan=float(rng.uniform(-0.7, 0.7)),
                bus=bus, human=0)


def chords_of(bars):
    """[['D'], ['A7sus4', 'A7']] -> [(sym, beats)] splitting each 4-beat bar evenly"""
    out = []
    for bar in bars:
        for c in bar:
            out.append((c, 4 / len(bar)))
    return out


def new_mix(seconds, sends=None, seed=5):
    mx = vsco.Mix(seconds, seed=seed)
    for b, s in {'main': 0.3, 'strings': 0.42, 'harp': 0.36, 'sparkle': 0.55, 'lead': 0.32, 'perc': 0.35, 'world': 0.4,
                 'amb': 0.0, 'low': 0.3, **(sends or {})}.items():
        mx._b(b)
        mx.send[b] = s
    return mx


# =============================================================================================== the cold open ===
# shots (onboarding_cine.py): black_print 0-1.4 | map_lit 1.4-4.6 | map_walkers 4.6-7.6 | map_hollow 7.6-12.2 |
# map_reignite 12.2-15.2 | village_live 15.2-20.8 (fades to black from 20.2)
def cold_open():
    mx = new_mix(25.0)
    # the footprint (0.4, with its sound): the call's first note, alone
    bell(mx, 0.42, 'A4', 0.42)
    mx.note('harp', 0.42, 3, m('A3'), 0.22, pan=-0.1)
    mx.note('violins', 0.2, 1.4, m('A5'), 0.12, att=1.0, rel=1.2, pan=0.2, bus='strings')
    # "Once, every path was lit." the call, as the trails light (1.55 -> 4.0)
    line(mx, 'piano', 1.55, 75, 'A4 .5 D5 .5 F#5 1.5 E5 .5 D5 1', vel=0.42, pan=0.05, bus='lead', ring=3.5, human=0.004)
    line(mx, 'glock', 1.55, 75, 'A4 .5 D5 .5 F#5 1.5 E5 .5 D5 1', vel=0.26, octave=1, pan=0.2, bus='lead', ring=3.0, human=0.004)
    roll(mx, 1.5, ['D2', 'A2', 'D3', 'F#3', 'A3', 'D4'], vel=0.36, gap=0.07)
    pad(mx, 1.55, 3.2, 'D', low=50, vel=0.27, att=1.6, rel=0.8)
    mx.note('bass', 1.55, 3.2, m('D2'), 0.2, att=1.8, rel=0.8, bus='low')
    sparkle(mx, 2.1, 4.3, 6, vel=0.16, seed=2)
    # "The Evochi watched over them." the call's second bar on the flute; pizzicato footsteps wander across
    line(mx, 'flute', 4.6, 80, 'B4 .5 D5 .5 E5 1.5 D5 .5 B4 1', vel=0.42, pan=-0.05, bus='lead')
    line(mx, 'piano', 4.6, 80, 'B4 .5 D5 .5 E5 1.5 D5 .5 B4 1', vel=0.2, pan=0.1, bus='lead', ring=2.0)
    roll(mx, 4.58, ['G2', 'D3', 'G3', 'B3', 'E4'], vel=0.3, gap=0.06)
    pad(mx, 4.6, 3.0, 'G6', low=50, vel=0.27, att=0.8, rel=0.8)
    mx.note('bass', 4.6, 3.0, m('G2'), 0.2, att=0.6, rel=0.8, bus='low')
    for i, p in enumerate(['D4', 'G4', 'B4', 'G4', 'D4', 'A4', 'B4', 'D5']):
        mx.note('pizz', 4.6 + 0.375 * i, 0.3, m(p), 0.26 + 0.03 * (i % 2), pan=-0.6 + 1.2 * i / 7, bus='perc')
    # "Time and the Hollow dimmed them." the climb (bar 3) starts, falters, sags and goes out; a low drone and the
    # Hollow's swell take the room; only a far glint is left (the village)
    def sag(t0, t1, depth):
        return lambda t: np.clip((t - t0) / (t1 - t0), 0, 1) ** 1.5 * depth
    sp = 60 / 80
    for k, (b, d, p) in enumerate(melody('G4 .5 B4 .5 D5 1 E5 .5 F#5 .5 G5 1')):
        t = 7.6 + b * sp
        # each later note sags further, and the last one falls away
        mx.note('flute', t, d * sp + (0.9 if k == 5 else 0), p, 0.44 - 0.04 * k, pan=-0.05, bus='world',
                bend=(lambda tt, k=k: -0.22 * max(0, k - 1) - (tt * 1.6 if k >= 4 else tt * 0.25 * (k >= 2))))
    pad(mx, 7.6, 3.3, 'Em7', low=50, vel=0.26, att=0.5, rel=1.2, bus='world', bend=sag(0.8, 3.3, -1.2))
    mx.fx['world'] = lambda x: vsco.darken(x, [(0, 0), (8.6, 0), (10.4, 0.85), (25, 0.85)])
    # the drone and the rub
    mx.note('bass', 8.2, 4.6, m('D1') + 12, 0.42, att=1.6, rel=1.4, bus='low')
    mx.note('celli', 8.4, 4.2, m('D2'), 0.4, att=1.4, rel=1.4, bus='low')
    mx.note('violas', 8.8, 2.4, 51, 0.26, att=1.2, rel=0.8, bus='low')
    mx.note('violins', 9.0, 2.0, 63, 0.2, att=1.0, rel=0.8, pan=0.3, bus='low')
    mx.note('violins', 9.2, 1.9, 62, 0.2, att=1.0, rel=0.8, pan=0.4, bus='low')
    mx.sfx('timp_roll', 8.3, gain=0.5, rate=2 ** (-4 / 12), end=2.8, fade_out=0.5, bus='hollow')
    mx.ramp('hollow', [(0, 0.15), (8.3, 0.15), (10.6, 1.0), (11.2, 0.25), (25, 0.25)])
    cr = vsco.sound('cym_soft')[::-1]
    mx.put(10.75 - len(cr) / vsco.SR, cr * 0.55 / 0.9, 'hollow', pan=0.1)
    mx.ramp('low', [(0, 1), (8.2, 1), (10.6, 1.3), (11.6, 0.55), (12.9, 0.35), (13.6, 0.0), (25, 0)])
    mx.note('glock', 11.95, 0.1, m('D7'), 0.2, pan=0.15, bus='sparkle', ring=3.0)
    # "But Lumen still answers to footsteps." the first note again, warmer, with the footstep (13.1); the call's head
    # rises as the trail lights behind the steps
    for t, p, v in ((13.1, 'A4', 0.46), (13.85, 'D5', 0.5), (14.55, 'F#5', 0.54)):
        bell(mx, t, p, v, bus='lead', ring=4.0)
        mx.note('harp', t, 2.0, m(p) - 12, v * 0.6, pan=-0.15)
    mx.note('violins', 13.1, 0.8, m('A4'), 0.26, att=0.5, rel=0.5, pan=0.35, bus='strings')
    mx.note('violins', 13.85, 0.75, m('D5'), 0.3, att=0.3, rel=0.5, pan=0.35, bus='strings')
    mx.note('violins', 14.55, 1.6, m('F#5'), 0.36, att=0.3, rel=0.6, pan=0.35, bus='strings')
    pad(mx, 13.2, 2.2, 'D', low=48, vel=0.3, att=1.5, rel=0.9, n=3)
    mx.note('bass', 13.4, 2.0, m('D2'), 0.26, att=1.4, rel=0.9, bus='low2')
    sparkle(mx, 13.4, 15.2, 5, vel=0.14, seed=4)
    # "And something here is still glowing." the village in the day: the call carries on (E5 D5), reaches higher
    # (bar 6) and stops on its question (bar 4) as the picture fades; the village's own sounds under it
    bpm = 90
    sp = 60 / bpm
    lead = [(15.30, 'E5 .5 D5 1.5', 2), (16.30, 'B4 .5 D5 .5 G5 1.5 F#5 .5 E5 1', 4), (18.97, 'F#5 1 E5 1 r 2', 4)]
    for t0, txt, beats in lead:
        line(mx, 'violins', t0, bpm, txt, vel=0.44, beats=beats, pan=0.2, bus='lead', att=0.06, rel=0.4)
        line(mx, 'flute', t0, bpm, txt, vel=0.36, beats=beats, pan=-0.1, bus='lead')
    # the question, held as the picture goes
    mx.note('flute', 20.30, 1.9, m('A4'), 0.34, bus='lead', rel=1.0, pan=-0.1)
    mx.note('violins', 20.30, 1.9, m('A4'), 0.4, bus='lead', att=0.06, rel=1.0, pan=0.2)
    harp_arp(mx, 15.2, bpm, [('D', 1.65), ('Gmaj7', 4), ('A7sus4', 1), ('A7', 1)], vel=0.3, low=50)
    # the arpeggio runs out into one held A as the picture goes
    roll(mx, 20.3, ['A2', 'E3', 'A3', 'C#4', 'E4'], vel=0.26, gap=0.08, dur=4)
    for t, d, sym in ((15.2, 1.1, 'D'), (16.3, 2.67, 'Gmaj7'), (18.97, 1.33, 'A7sus4'), (20.3, 2.2, 'A')):
        pad(mx, t, d, sym, low=50, vel=0.28, att=0.35, rel=1.1 if t > 20 else 0.4)
    for i in range(16):
        t = 15.2 + 0.667 * i + 0.333
        if t > 20.2:
            break
        c = 'D' if t < 16.3 else 'Gmaj7' if t < 18.97 else 'A7sus4' if t < 19.63 else 'A7'
        for j, p in enumerate(voicing(c, 67, 2)):
            mx.note('pizz', t + j * 0.01, 0.2, p, 0.2, pan=0.45, bus='perc')
    for t, p in ((18.4, 'F#6'), (18.75, 'A6'), (19.1, 'D7'), (19.6, 'E7')):
        mx.note('glock', t, 0.1, m(p), 0.17, pan=0.35, bus='sparkle', ring=3)
    amb = vsco.decode(os.path.join(GAME, 'assets/audio/ambient/amb_village.mp3'))[:int(6.6 * vsco.SR)].copy()
    env = np.interp(np.arange(len(amb)) / vsco.SR, [0, 0.9, 5.0, 5.9, 6.6], [0, 1, 1, 0.15, 0])
    mx.put(15.0, (amb * env[:, None]).astype(np.float32), 'amb', gain=0.9)
    return mx, dict(lufs=-18.5, fade_out=1.2)


# ================================================================================================== the title ===
def title():
    """Welcome: the question answered. A harp sweep up into D, the call's head, held, settling."""
    mx = new_mix(8.0)
    sweep = [midi(n) for n in ('D3', 'F#3', 'A3', 'D4', 'E4', 'F#4', 'A4', 'B4', 'D5', 'E5', 'F#5', 'A5', 'D6')]
    for i, p in enumerate(sweep):
        mx.note('harp', 0.02 + i * 0.035, 3, p, 0.32 + 0.02 * i, pan=-0.4 + 0.06 * i, bus='harp', human=0)
    mx.sfx('glock_up', 0.0, gain=0.28, pan=0.3, bus='sparkle')
    mx.sfx('cym_soft', 0.5, gain=0.18, bus='perc')
    bpm = 96
    for name, vel, oc, pan in (('flute', 0.5, 0, -0.1), ('violins', 0.48, 0, 0.25), ('glock', 0.3, 1, 0.3)):
        kw = dict(ring=4) if name == 'glock' else {}
        line(mx, name, 0.5, bpm, 'A4 .5 D5 .5 F#5 3', vel=vel, octave=oc, pan=pan, bus='lead', **kw)
    mx.note('bass', 0.5, 3.4, m('D2'), 0.42, att=0.05, rel=1.6, bus='low')
    mx.note('celli', 0.5, 3.4, m('D3'), 0.4, att=0.05, rel=1.6, bus='strings', pan=-0.25)
    pad(mx, 0.5, 3.0, 'Dadd9', low=55, vel=0.36, att=0.15, rel=1.8, bass=False)
    roll(mx, 2.6, ['D3', 'A3', 'E4', 'F#4', 'A4', 'D5'], vel=0.24, gap=0.12, dur=4)
    mx.note('glock', 3.4, 0.1, m('A6'), 0.16, bus='sparkle', ring=3)
    return mx, dict(lufs=-18.0, fade_out=1.5)


# ================================================================================================= Pip's loop ===
PIP_BPM = 108
PIP_A = ['r 4',
         'A4 .5 D5 .5 F#5 .75 E5 .25 D5 1 r .5 A4 .5',
         'B4 .5 D5 .5 E5 .75 D5 .25 B4 1 r .5 G4 .5',
         'G4 .5 B4 .5 D5 .5 E5 .5 F#5 .5 G5 .5 A5 .75 F#5 .25',
         'E5 1 A4 .5 C#5 .5 E5 1 r 1',
         'A4 .5 D5 .5 F#5 .75 E5 .25 D5 1 r .5 A4 .5',
         'B4 .5 D5 .5 G5 .75 F#5 .25 E5 1 r .5 E5 .5',
         'D5 .5 E5 .5 F#5 .5 A5 .5 G5 .5 E5 .5 C#5 .5 E5 .5',
         'D5 1 A4 .5 F#4 .5 D4 1 r 1']
PIP_B = ['D5 .5 G5 .5 B5 .75 A5 .25 G5 1 r 1',
         'C#5 .5 E5 .5 A5 .75 G5 .25 E5 1 r 1',
         'C#5 .5 E5 .5 A5 .75 F#5 .25 E5 1 C#5 1',
         'D5 .5 F#5 .5 B5 .75 A5 .25 F#5 1 D5 1',
         'E5 .5 G5 .5 B5 .5 A5 .5 G5 .5 E5 .5 D5 .5 B4 .5',
         'C#5 .5 E5 .5 G5 .5 E5 .5 A5 2',
         'r 4']
PIP_CH = [['D'], ['D'], ['G6'], ['Em7'], ['A7sus4', 'A7'], ['D'], ['Gmaj7'], ['D/F#', 'A7'], ['D'],
          ['Gmaj7'], ['A7'], ['F#m7'], ['Bm7'], ['Em7'], ['A7'], ['A7sus4']]


def pip():
    """Welcome, under Pip's Lodge: the call as a courier's hop. A vamp bar, the call on clarinet (A, A'), the flute
    on a brighter turn (IV-V-iii-vi), and a held A7sus4 that falls back into the vamp."""
    bpm, sp = PIP_BPM, 60 / PIP_BPM
    bars = len(PIP_CH)
    loop = bars * 4 * sp
    mx = new_mix(loop + TAIL, seed=9)
    mel = ' | '.join(PIP_A)
    line(mx, 'clarinet', 0, bpm, mel, vel=0.5, pan=-0.12, bus='lead', legato=0.92)
    line(mx, 'flute', 9 * 4 * sp, bpm, ' | '.join(PIP_B[:6]), vel=0.5, pan=0.1, bus='lead', legato=0.9)
    line(mx, 'clarinet', 9 * 4 * sp, bpm, ' | '.join(PIP_B[:6]), vel=0.26, octave=-1, pan=-0.2, bus='lead', legato=0.9)
    # glockenspiel winks at the ends of phrases
    for bar, notes in ((4, ('E6', 'A6')), (8, ('A6', 'D7')), (14, ('A6', 'C#7'))):
        for k, p in enumerate(notes):
            mx.note('glock', (bar * 4 + 2.5 + k * 0.5) * sp, 0.1, m(p), 0.17, pan=0.35, bus='sparkle', ring=2)
    # boom (harp, low) - chick (pizzicato chords)
    for i, bar in enumerate(PIP_CH):
        L = 4 / len(bar)
        for j, c in enumerate(bar):
            r, iv, b = chord(c)
            t0 = (i * 4 + j * L) * sp
            root = 38 + (b - 2) % 12
            if i == bars - 1:
                # the held turn back: one long A7sus4, a pizzicato hop up at its end
                mx.note('harp', t0, 4 * sp, root, 0.44, pan=-0.2, bus='harp')
                roll(mx, t0, voicing(c, 57, 4), vel=0.28, gap=0.05, dur=4 * sp, bus='harp')
                pad(mx, t0, 4 * sp - 0.2, c, low=52, vel=0.26, att=0.3, rel=0.6)
                for k, p in enumerate(('A4', 'C#5', 'E5')):
                    mx.note('pizz', t0 + (3 + k / 3) * sp, 0.2, m(p), 0.3, pan=0.4, bus='perc')
                continue
            mx.note('harp', t0, L * sp, root, 0.46, pan=-0.2, bus='harp')
            if L >= 4:
                mx.note('harp', t0 + 2 * sp, 2 * sp, root + 7 - (12 if root + 7 > 50 else 0), 0.38, pan=-0.2, bus='harp')
            for k in [x for x in (1, 3) if x < L]:
                for q, p in enumerate(voicing(c, 62, 3)):
                    mx.note('pizz', t0 + k * sp + q * 0.008, 0.25, p, 0.26, pan=0.35, bus='perc')
    # strings under the brighter turn
    for i in range(9, bars - 1):
        pad(mx, i * 4 * sp, 4 * sp, PIP_CH[i][0], low=50, vel=0.2, att=0.6, rel=0.5, bass=False)
    return mx, dict(lufs=-20.0, loop=loop)


# ================================================================================================ Mira's loop ===
MIRA_BPM = 76
MIRA = ['A4 1 D5 1 F#5 1', 'F#5 1.5 E5 .5 D5 1', 'B4 1 D5 1 E5 1', 'E5 1.5 D5 .5 B4 1',
        'G4 1 B4 1 D5 1', 'E5 1 F#5 1 G5 1', 'F#5 2 E5 1', 'A4 3',
        'A4 1 D5 1 F#5 1', 'F#5 1.5 E5 .5 D5 1', 'B4 1 D5 1 G5 1', 'G5 1.5 F#5 .5 E5 1',
        'D5 1 E5 1 F#5 1', 'A5 1.5 G5 .5 E5 1', 'D5 3', 'D5 2 r 1',
        'F#5 1.5 E5 .5 D5 1', 'C#5 1 B4 1 A4 1', 'B4 1.5 C#5 .5 D5 1', 'E5 3',
        'F#5 1.5 E5 .5 D5 1', 'B4 1 G4 1 B4 1', 'A4 1.5 B4 .5 C#5 1', 'E5 2 r 1']
MIRA_CH = ['D', 'D', 'G6', 'Em7', 'Em7', 'A7sus4', 'A7sus4', 'A7',
           'D', 'D', 'Gmaj7', 'Gmaj7', 'D/F#', 'A7', 'D', 'Dadd9',
           'Bm7', 'F#m7', 'Gmaj7', 'A7sus4', 'Bm7', 'Em7', 'A7sus4', 'A7']


def mira():
    """The Glasshouse, Mira and the eggs: the call as a lullaby in 3/4. Flute (A), violins (A'), and Mira's own
    B section low on the clarinet, ending on a held A7 that rocks back to D."""
    bpm, sp = MIRA_BPM, 60 / MIRA_BPM
    loop = len(MIRA) * 3 * sp
    mx = new_mix(loop + TAIL, seed=13)
    A, A2, B = ' | '.join(MIRA[:8]), ' | '.join(MIRA[8:16]), ' | '.join(MIRA[16:])
    line(mx, 'flute', 0, bpm, A, vel=0.4, beats=3, pan=-0.1, bus='lead')
    line(mx, 'violins', 8 * 3 * sp, bpm, A2, vel=0.38, beats=3, pan=0.2, bus='lead', att=0.12, rel=0.6)
    line(mx, 'flute', 8 * 3 * sp, bpm, A2, vel=0.2, beats=3, octave=1, pan=-0.2, bus='lead')
    line(mx, 'clarinet', 16 * 3 * sp, bpm, B, vel=0.4, beats=3, octave=-1, pan=-0.1, bus='lead')
    line(mx, 'flute', 20 * 3 * sp, bpm, ' | '.join(MIRA[20:]), vel=0.18, beats=3, pan=0.15, bus='lead')
    for i, c in enumerate(MIRA_CH):
        t0 = i * 3 * sp
        r, iv, b = chord(c)
        v = voicing(c, 57, 4)
        last = i == len(MIRA_CH) - 1
        mx.note('harp', t0, 3 * sp, 38 + (b - 2) % 12, 0.4, pan=-0.2, bus='harp')
        if last:
            roll(mx, t0 + 0.5 * sp, v, vel=0.24, gap=0.1, dur=3 * sp, bus='harp')
        else:
            for k, idx in enumerate((0, 1, 2, 3, 2, 1)[1:]):
                mx.note('harp', t0 + (k + 1) * 0.5 * sp, sp, v[idx], 0.26 if k % 2 else 0.3, pan=0.15, bus='harp')
        pad(mx, t0, 3 * sp, c, low=50, vel=0.19 if i < 8 else 0.23, att=0.8, rel=0.7, bass=i >= 8, n=3)
    for bar, notes in ((7, ('A6', 'E7')), (15, ('D7', 'A6', 'F#6')), (19, ('E7',))):
        for k, p in enumerate(notes):
            mx.note('glock', (bar * 3 + 1 + k * 0.67) * sp, 0.1, m(p), 0.15, pan=0.4, bus='sparkle', ring=2.5)
    return mx, dict(lufs=-21.0, loop=loop)


# ================================================================================================ the waiting ===
def wait():
    """Waiting for the egg while you walk: nearly nothing. A faint D pad high in the violins, a slow heartbeat on the
    harp's lowest D, a glint now and then. The cracks (crack_1..3) play the call's notes over it."""
    loop = 32.0
    mx = new_mix(loop + TAIL, seed=17)
    for t0, d in ((0.0, 17.0), (15.5, 16.5)):
        for p, v, name in ((m('A5'), 0.16, 'violins'), (m('D5'), 0.14, 'violins'), (m('F#4'), 0.14, 'violas'), (m('D3'), 0.14, 'celli')):
            mx.note(name, t0, d, p, v, att=4.0, rel=3.0, bus='strings', pan=0.2 if name == 'violins' else -0.2, human=0)
    for k in range(int(loop / 4.0)):
        t = 0.4 + 4.0 * k
        mx.note('harp', t, 1.2, m('D2'), 0.36, pan=-0.1, bus='low', human=0)
        mx.note('harp', t + 0.3, 1.2, m('D2'), 0.24, pan=-0.1, bus='low', human=0)
    sparkle(mx, 2, loop - 3, 7, vel=0.1, seed=21)
    mx.fx['low'] = lambda x: vsco.darken(x, [(0, 0.7), (99, 0.7)], cutoff=380)
    return mx, dict(lufs=-28.0, loop=loop)


def crack(stage):
    """A crack your steps opened: the call's next note (A, D, F#), a string swell under it; the last one opens out
    into the whole chord, ready."""
    p = ('A4', 'D5', 'F#5')[stage - 1]
    mx = new_mix(7.0, seed=30 + stage)
    bell(mx, 0.0, p, 0.5 + 0.06 * stage, bus='lead')
    mx.note('harp', 0.0, 3, m(p) - 12, 0.4, pan=-0.15, human=0)
    mx.note('violins', 0.02, 1.6 + 0.4 * stage, m(p), 0.3 + 0.04 * stage, att=0.25, rel=1.6, pan=0.3, bus='strings', human=0)
    mx.note('celli', 0.02, 2.0, m('D3'), 0.22 + 0.03 * stage, att=0.4, rel=1.6, pan=-0.3, bus='strings', human=0)
    if stage >= 2:
        mx.note('violas', 0.05, 2.2, m('A4') if stage == 2 else m('A4'), 0.24, att=0.4, rel=1.6, bus='strings', human=0)
    if stage == 3:
        mx.sfx('glock_up', 0.0, gain=0.25, pan=0.3, bus='sparkle')
        roll(mx, 0.05, ['D3', 'A3', 'D4', 'F#4', 'A4', 'D5', 'F#5', 'A5'], vel=0.28, gap=0.05)
        mx.note('violins', 0.3, 2.6, m('D6'), 0.2, att=0.8, rel=1.8, pan=0.4, bus='strings')
        mx.note('bass', 0.1, 2.6, m('D2'), 0.25, att=0.6, rel=1.6, bus='low')
    return mx, dict(lufs=-21.0 + stage, fade_out=0.8)


# ================================================================================================== the hatch ===
# hatch.json, seconds from the tap: shakes .52 .74 .9 | cracks 1.35 1.62 2.05 | a held breath | burst 2.5 |
# out 2.6 | looks round 3.6 | its own act 4.1 | the name card 4.9
HATCH_THEN = 14.75


def hatch():
    mx = new_mix(HATCH_THEN + TAIL + 0.6, seed=41)
    # the build: a low D drone and a timpani roll rising under the shakes and cracks
    mx.note('bass', 0.0, 2.05, m('D2'), 0.34, att=1.4, rel=0.15, bus='build', human=0)
    mx.note('celli', 0.1, 1.95, m('D3'), 0.32, att=1.2, rel=0.15, bus='build', human=0)
    mx.note('violas', 0.6, 1.45, m('A3'), 0.26, att=0.9, rel=0.15, bus='build', human=0)
    mx.sfx('timp_roll', 0.15, gain=0.55, rate=2 ** (-4 / 12), end=1.95, fade_out=0.12, bus='build')
    mx.ramp('build', [(0, 0.2), (1.3, 0.6), (2.0, 1.2), (2.06, 1.2), (2.2, 0.0), (99, 0)])
    mx.send['build'] = 0.25
    for t, v in ((0.52, 0.26), (0.74, 0.42), (0.9, 0.22)):
        mx.note('harp', t, 0.25, m('D2'), v, pan=-0.1, rel=0.2, bus='harp', human=0)
    # the cracks: the call's first three notes, closer each time, the strings stacking them into D
    for t, p, v in ((1.35, 'A4', 0.46), (1.62, 'D5', 0.52), (2.05, 'F#5', 0.6)):
        bell(mx, t, p, v, bus='lead', ring=1.2)
        mx.note('harp', t, 0.5, m(p) - 12, v * 0.7, pan=-0.15, bus='harp', human=0)
        mx.note('violins', t, 2.12 - t, m(p), v * 0.7, att=0.04, rel=0.12, pan=0.3, bus='build', human=0)
    # the held breath (2.1-2.5): the light swells inside, a cymbal drawn backwards into the break
    cr = vsco.sound('cym_soft')[::-1][-int(0.9 * vsco.SR):].copy()
    cr *= np.linspace(0, 1, len(cr))[:, None] ** 2
    mx.put(2.5 - len(cr) / vsco.SR, cr * 0.5, 'perc', pan=0.1)
    # the burst (2.5): everyone on D, a harp sweep and the glockenspiel up
    B = 2.5
    mx.sfx('cym_hit', B, gain=0.32, bus='perc')
    mx.sfx('glock_up_fast', B, gain=0.24, pan=0.3, bus='sparkle')
    for i, p in enumerate(('D3', 'F#3', 'A3', 'D4', 'F#4', 'A4', 'D5', 'F#5', 'A5', 'D6')):
        mx.note('harp', B + i * 0.03, 3, m(p), 0.42, pan=-0.3 + 0.07 * i, bus='harp', human=0)
    mx.note('bass', B, 2.6, m('D2'), 0.5, att=0.02, rel=1.2, bus='low', human=0)
    pad(mx, B, 0.35, 'D', low=52, vel=0.52, att=0.02, rel=0.9)
    # the call, out in the world (bars 1-2), and on to its question, softer, as the name card comes up
    bpm = 80
    T = 2.75
    sp = 60 / bpm
    bars = 'A4 .5 D5 .5 F#5 1.5 E5 .5 D5 1 | B4 .5 D5 .5 E5 1.5 D5 .5 B4 1'
    line(mx, 'flute', T, bpm, bars, vel=0.5, pan=-0.1, bus='lead')
    line(mx, 'violins', T, bpm, bars, vel=0.46, pan=0.25, bus='lead', att=0.05)
    line(mx, 'glock', T, bpm, bars, vel=0.2, octave=1, pan=0.3, bus='sparkle', ring=2)
    t2 = T + 8 * sp
    line(mx, 'flute', t2, bpm, 'G4 .5 B4 .5 D5 1 E5 .5 F#5 .5 G5 1 | F#5 1 E5 1 A4 2', vel=0.36, pan=-0.1, bus='lead')
    line(mx, 'violins', t2, bpm, 'G4 .5 B4 .5 D5 1 E5 .5 F#5 .5 G5 1 | F#5 1 E5 1 A4 2', vel=0.28, octave=-1, pan=0.25, bus='lead')
    ch = [('D', 4), ('G6', 4), ('Em7', 4), ('A7sus4', 2), ('A7', 2)]
    harp_arp(mx, T, bpm, ch, vel=0.32)
    t = T
    for sym, L in ch:
        pad(mx, t, L * sp, sym, low=50, vel=0.34 if t < t2 else 0.26, att=0.25, rel=0.6)
        t += L * sp
    for k in range(8):
        tt = T + (2 * k + 1) * sp
        c = 'D' if k < 2 else 'G6' if k < 4 else 'Em7' if k < 6 else 'A7'
        for q, p in enumerate(voicing(c, 66, 2)):
            mx.note('pizz', tt + q * 0.01, 0.2, p, 0.22, pan=0.4, bus='perc')
    return mx, dict(lufs=-17.5, fade_out=TAIL - 0.5)


NAMING_BPM = 66


def naming():
    """While you choose its name: a harp, a breath of strings, the flute on two fragments; a held A7sus4 at the end
    rocks back to D."""
    bpm, sp = NAMING_BPM, 60 / NAMING_BPM
    ch = ['D', 'Gmaj7', 'Em7', 'A7sus4', 'D', 'Gmaj7', 'Bm7', 'A7sus4']
    loop = len(ch) * 4 * sp
    mx = new_mix(loop + TAIL, seed=51)
    for i, c in enumerate(ch):
        t0 = i * 4 * sp
        if i == len(ch) - 1:
            mx.note('harp', t0, 4 * sp, 38 + (chord(c)[2] - 2) % 12, 0.3, pan=-0.2, bus='harp')
            roll(mx, t0 + 0.5 * sp, voicing(c, 57, 4), vel=0.2, gap=0.14, dur=4 * sp, bus='harp')
        else:
            harp_arp(mx, t0, bpm, [(c, 4)], vel=0.24, shape=(0, 1, 2, 3, 2, 1, 2, 3))
        pad(mx, t0, 4 * sp, c, low=50, vel=0.16, att=1.2, rel=1.0, n=3)
    line(mx, 'flute', 2 * 4 * sp, bpm, 'F#5 2 E5 2', vel=0.26, pan=-0.1, bus='lead')
    line(mx, 'flute', 6 * 4 * sp, bpm, 'D5 2 B4 1 A4 1', vel=0.24, pan=-0.1, bus='lead')
    sparkle(mx, 1, loop - 2, 5, vel=0.1, seed=53)
    return mx, dict(lufs=-24.0, loop=loop)


# ================================================================================================ "is home" ===
# from the name said (HatchScreen._confirmName): 0 the name rises in gold | 1.5 it flies to the map and lights the
# grove trail | 5.7 "<name> is home", and the Main Theme, start to "home", into the Nest
HOME_AT = 5.7
HOME_BPM = 92


def home():
    sp = 60 / HOME_BPM
    bar = 4 * sp
    total = HOME_AT + 24 * bar + 6.0
    mx = new_mix(total, seed=61)
    # the name heard: a sparkle up and the call's peak, held on high A
    mx.sfx('glock_up', 0.0, gain=0.26, pan=0.3, bus='sparkle')
    for k, p in enumerate(('D5', 'E5', 'F#5', 'A5')):
        bell(mx, 0.05 + 0.15 * k, p, 0.4 + 0.04 * k, bus='lead', ring=3 if k == 3 else 0.6)
    mx.note('violins', 0.5, 1.2, m('A5'), 0.24, att=0.5, rel=0.6, pan=0.3, bus='strings')
    roll(mx, 0.05, ['D3', 'A3', 'D4', 'F#4'], vel=0.24, gap=0.08)
    # the name flies to the map in Lumen and the grove trail lights: a long swell D - G - A, the call's head echoing
    mx.note('bass', 1.5, 4.0, m('D2'), 0.3, att=1.5, rel=0.4, bus='low')
    for t, d, c in ((1.5, 1.5, 'D'), (3.0, 1.4, 'Gmaj7'), (4.4, 1.3, 'A7sus4')):
        pad(mx, t, d, c, low=50, vel=0.26 + 0.05 * (t > 3), att=0.6, rel=0.5)
    for t, p in ((1.9, 'A4'), (2.5, 'D5'), (3.1, 'F#5'), (4.4, 'E5'), (4.9, 'A5')):
        bell(mx, t, p, 0.36, bus='lead', ring=2)
    for i in range(12):
        mx.note('harp', 1.6 + 0.33 * i, 1.0, [62, 66, 69, 74, 67, 71, 74, 79, 69, 74, 76, 81][i], 0.22 + 0.01 * i, pan=0.2, bus='harp')
    mx.sfx('timp_roll_soft', 4.3, gain=0.4, rate=2 ** (-4 / 12), end=1.4, fade_out=0.2, bus='perc')
    mx.sfx('cym_roll', HOME_AT - 1.6, gain=0.2, end=1.6, bus='perc')
    # the Main Theme
    T = HOME_AT
    chA = [['D'], ['G6'], ['Em7'], ['A7sus4', 'A7']]
    chA2 = [['D'], ['Gmaj7'], ['D/F#', 'A7'], ['Dadd9']]
    chB = [['Bm7'], ['Gmaj7'], ['Em7', 'F#7'], ['F#7'], ['Bm'], ['Em7', 'A'], ['Gmaj7', 'Em7'], ['A7sus4', 'A7']]
    mx.sfx('cym_soft', T, gain=0.2, bus='perc')

    def bed(t0, bars, vel, pizz=True, arp_vel=0.3):
        ch = chords_of(bars)
        harp_arp(mx, t0, HOME_BPM, ch, vel=arp_vel)
        t = t0
        for sym, L in ch:
            pad(mx, t, L * sp, sym, low=50, vel=vel, att=0.2, rel=0.5)
            r, iv, b = chord(sym)
            mx.note('bass', t, L * sp * 0.95, 28 + (b - 4) % 12, vel * 1.1, att=0.03, rel=0.4, bus='low')
            if pizz:
                for k in [x for x in (1, 3) if x < L]:
                    for q, p in enumerate(voicing(sym, 66, 2)):
                        mx.note('pizz', t + k * sp + q * 0.01, 0.2, p, 0.22, pan=0.4, bus='perc')
            t += L * sp

    # 1-4 the call: flute, a bell an octave up
    line(mx, 'flute', T, HOME_BPM, THEME_A, vel=0.5, pan=-0.1, bus='lead')
    line(mx, 'glock', T, HOME_BPM, THEME_A, vel=0.2, octave=1, pan=0.3, bus='sparkle', ring=2)
    bed(T, chA, 0.28)
    # 5-8 the answer: the violins take it, the flute above
    t = T + 4 * bar
    line(mx, 'violins', t, HOME_BPM, THEME_A2, vel=0.48, pan=0.25, bus='lead', att=0.05)
    line(mx, 'flute', t, HOME_BPM, THEME_A2, vel=0.3, octave=1, pan=-0.15, bus='lead')
    bed(t, chA2, 0.32)
    # 9-16 the bridge, in B minor, on the clarinet over the strings; it leans on A7 back into the call
    t = T + 8 * bar
    line(mx, 'clarinet', t, HOME_BPM, BRIDGE, vel=0.48, pan=-0.1, bus='lead')
    line(mx, 'violins', t + 4 * bar, HOME_BPM, ' | '.join(BRIDGE.split('|')[4:]), vel=0.26, octave=1, pan=0.3, bus='lead')
    bed(t, chB, 0.3, pizz=False, arp_vel=0.27)
    mx.sfx('timp_roll', t + 7.5 * bar - 0.1, gain=0.42, rate=2 ** (3 / 12), end=0.5 * bar + 0.1, fade_out=0.08, bus='perc')
    # 17-20 everyone on the call: violins and flute in octaves, the bell on top
    t = T + 16 * bar
    mx.sfx('cym_hit', t, gain=0.22, bus='perc')
    line(mx, 'violins', t, HOME_BPM, THEME_A, vel=0.54, pan=0.25, bus='lead', att=0.04)
    line(mx, 'flute', t, HOME_BPM, THEME_A, vel=0.44, octave=1, pan=-0.15, bus='lead')
    line(mx, 'clarinet', t, HOME_BPM, THEME_A, vel=0.3, octave=-1, pan=-0.3, bus='lead')
    line(mx, 'glock', t, HOME_BPM, THEME_A, vel=0.22, octave=1, pan=0.35, bus='sparkle', ring=2)
    bed(t, chA, 0.38, arp_vel=0.34)
    # 21-24 home: the answer, gentler, and its last D held under a harp sweep and the glockenspiel
    t = T + 20 * bar
    line(mx, 'violins', t, HOME_BPM, THEME_A2.rsplit('|', 1)[0], vel=0.44, pan=0.25, bus='lead', att=0.05)
    line(mx, 'flute', t, HOME_BPM, THEME_A2.rsplit('|', 1)[0], vel=0.36, pan=-0.15, bus='lead')
    bed(t, chA2[:3], 0.32)
    h = t + 3 * bar
    for name, vel in (('violins', 0.4), ('flute', 0.3)):
        mx.note(name, h, 4 * sp + 1.5, m('D5'), vel, rel=2.0, pan=0.2 if name == 'violins' else -0.15, bus='lead')
    pad(mx, h, 5.0, 'Dadd9', low=50, vel=0.32, att=0.3, rel=2.2)
    mx.note('bass', h, 5.0, m('D2'), 0.34, rel=2.2, bus='low')
    for i, p in enumerate(('D3', 'A3', 'D4', 'E4', 'F#4', 'A4', 'D5', 'E5', 'F#5', 'A5', 'D6')):
        mx.note('harp', h + 0.04 * i, 4, m(p), 0.3, pan=-0.3 + 0.06 * i, bus='harp', human=0)
    for k, p in enumerate(('F#6', 'A6', 'E7')):
        mx.note('glock', h + 0.6 + 0.5 * k, 0.1, m(p), 0.16, pan=0.35, bus='sparkle', ring=3)
    return mx, dict(lufs=-17.5, fade_out=2.5)


def voices(out_dir):
    """the speakers' voices as their lines write out (AudioService.voice): five soft notes of D major each, Pip a
    quick pizzicato, Mira a damped harp, low and warm"""
    from scipy.signal import butter, sosfilt
    for who, name, notes, hold, cut in (('pip', 'pizz', ('D5', 'E5', 'F#5', 'A5', 'B5'), 0.07, 5200),
                                        ('mira', 'harp', ('A4', 'B4', 'D5', 'E5', 'F#5'), 0.13, 2600)):
        for i, n in enumerate(notes):
            mx = new_mix(0.6, seed=70 + i)
            mx.note(name, 0.0, hold, m(n), 0.55, ring=0, rel=0.08 if who == 'pip' else 0.12, human=0)
            x = mx.render(rt=0.8, wet=0.35)
            sos = butter(2, cut, 'low', fs=vsco.SR, output='sos')
            x = np.stack([sosfilt(sos, x[:, c]) for c in range(2)], 1)
            x *= 0.3 / (np.abs(x).max() + 1e-9)
            k = int(0.15 * vsco.SR)
            x[-k:] *= np.linspace(1, 0, k)[:, None]
            wav = os.path.join(out_dir, 'voice_%s_%d.wav' % (who, i + 1))
            import soundfile as sf
            sf.write(wav, x.astype(np.float32), vsco.SR, subtype='FLOAT')
            import subprocess
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', wav, '-c:a', 'libmp3lame', '-q:a', '4', wav[:-4] + '.mp3'], check=True)
            os.remove(wav)
            print(wav[:-4] + '.mp3')


CUES = {'onb_cold_open': cold_open, 'onb_title': title, 'onb_pip': pip, 'onb_mira': mira, 'onb_wait': wait,
        'onb_crack_1': lambda: crack(1), 'onb_crack_2': lambda: crack(2), 'onb_crack_3': lambda: crack(3),
        'onb_hatch': hatch, 'onb_naming': naming, 'onb_home': home}


def render(name, out_dir):
    mx, opt = CUES[name]()
    x = mx.render(rt=2.3)
    loop = opt.get('loop')
    if loop:
        # one pass: LOOP s of music then its TAIL ringing out (the game starts the next pass at LOOP)
        n, k = int(loop * vsco.SR), int(TAIL * vsco.SR)
        x = x[:n + k].copy()
        x[n + k - int(0.6 * vsco.SR):] *= np.cos(np.linspace(0, np.pi / 2, int(0.6 * vsco.SR)))[:, None] ** 2
    path = vsco.master(x, os.path.join(out_dir, name + '.mp3'), lufs=opt['lufs'], fade_out=opt.get('fade_out', 0.0))
    print('%-16s %5.1fs  %s' % (name, len(x) / vsco.SR, path), flush=True)
    return path


def register(names):
    """list the files in the game's asset manifest (its audio map: name -> path under assets/audio)"""
    import json
    mp = os.path.join(GAME, 'assets', 'art', 'manifest.json')
    man = json.load(open(mp))
    for n in names:
        man['audio'][n] = ('sfx/' if n.startswith('voice_') else 'music/') + n + '.mp3'
    json.dump(man, open(mp, 'w'), indent=1)


if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    game = os.path.abspath(out) == os.path.join(GAME, 'assets', 'audio', 'music')
    done = []
    for n in (sys.argv[2:] or list(CUES) + ['voices']):
        if n == 'voices':
            voices(os.path.join(out, '..', 'sfx') if game else out)
            done += ['voice_%s_%d' % (w, i) for w in ('pip', 'mira') for i in range(1, 6)]
        else:
            render(n, out)
            done.append(n)
    if game:
        register(done)

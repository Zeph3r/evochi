"""Evochi's soundtrack, melody first: one leitmotif (the "Evochi call"), written out note by note, and four
arrangements of it (Main Theme, the Nest, the Deep Wilds, Hatching). Writes a MIDI file per piece (open it in
FL Studio, GarageBand or any DAW) and renders it with a General MIDI soundfont through fluidsynth, then levels it
(-16 LUFS, -1.5 dBTP) and, for the looping pieces, folds the reverb tail back onto the start so the loop is seamless.

    python3 evochi_themes.py OUT_DIR [--sf2 path.sf2]

The theme (D major, 4/4). Bars 1-8 are the leitmotif; every piece reuses them.
  1  A4 D5 F#5-- E5 D5      the call: up a 4th, up a 3rd, a step back   (D)
  2  B4 D5 E5--  D5 B4      the same rhythm, lower                       (G6)
  3  G4 B4 D5 E5 F#5 G5     climbing                                     (Em7)
  4  F#5 E5 A4---           a question: it stops on the dominant         (A7sus4 A7)
  5  the call again                                                      (D)
  6  B4 D5 G5-- F#5 E5      reaching higher                              (Gmaj7)
  7  D5 E5 F#5 A5 G5 E5     the peak                                     (D/F# A7)
  8  D5---                  home                                         (Dadd9)
"""
import math
import os
import random
import subprocess
import sys

import mido

SF2 = '/usr/share/sounds/sf2/FluidR3_GM.sf2'
PPQ = 480

# ------------------------------------------------------------------------------------------- notes, chords
_PC = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def midi(n):
    """'F#5' -> 78"""
    p = _PC[n[0]]
    i = 1
    while i < len(n) and n[i] in '#b':
        p += 1 if n[i] == '#' else -1
        i += 1
    return 12 * (int(n[i:]) + 1) + p


QUAL = {'': (0, 4, 7), 'm': (0, 3, 7), '7': (0, 4, 7, 10), 'maj7': (0, 4, 7, 11), 'm7': (0, 3, 7, 10), '6': (0, 4, 7, 9),
        'm6': (0, 3, 7, 9), 'm9': (0, 3, 7, 10, 14), 'maj9': (0, 4, 7, 11, 14), 'add9': (0, 4, 7, 14), 'sus4': (0, 5, 7),
        '7sus4': (0, 5, 7, 10), 'sus2': (0, 2, 7), 'dim': (0, 3, 6), '9': (0, 4, 7, 10, 14), '6/9': (0, 4, 7, 9, 14)}


def chord(sym):
    """'D/F#' -> (root pc, intervals, bass pc)"""
    bass = None
    if '/' in sym and not sym.endswith('6/9'):
        sym, b = sym.split('/')
        bass = _PC[b[0]] + (1 if b[1:2] == '#' else -1 if b[1:2] == 'b' else 0)
    r = _PC[sym[0]]
    q = sym[1:]
    if q[:1] in ('#', 'b'):
        r += 1 if q[0] == '#' else -1
        q = q[1:]
    return r % 12, QUAL[q], (bass if bass is not None else r) % 12


def voicing(sym, low=55, n=4):
    """close voicing of the chord's tones starting at or above `low`"""
    r, iv, _ = chord(sym)
    pcs = [(r + i) % 12 for i in iv]
    notes, p = [], low
    while len(notes) < n:
        if p % 12 in pcs and p not in notes:
            notes.append(p)
        p += 1
    return notes


def melody(text, bar0=0, beats=4):
    """'A4 .5 D5 .5 F#5 1.5 E5 .5 D5 1 | ...' -> [(beat, dur, pitch)]; r = rest. Each bar must fill `beats`."""
    out = []
    for b, bar in enumerate(text.split('|')):
        tok = bar.split()
        t = 0.0
        for name, d in zip(tok[::2], tok[1::2]):
            d = float(d)
            if name != 'r':
                out.append(((bar0 + b) * beats + t, d, midi(name)))
            t += d
        assert abs(t - beats) < 1e-6, 'bar %d of %r has %s beats' % (b + 1, text[:40], t)
    return out


# the leitmotif and its bridge, as written in the docstring
THEME_A = ('A4 .5 D5 .5 F#5 1.5 E5 .5 D5 1 | B4 .5 D5 .5 E5 1.5 D5 .5 B4 1 | G4 .5 B4 .5 D5 1 E5 .5 F#5 .5 G5 1 | '
           'F#5 1 E5 1 A4 2')
THEME_A2 = ('A4 .5 D5 .5 F#5 1.5 E5 .5 D5 1 | B4 .5 D5 .5 G5 1.5 F#5 .5 E5 1 | D5 .5 E5 .5 F#5 1 A5 1 G5 .5 E5 .5 | '
            'D5 3 r 1')
CH_A = [['D'], ['G6'], ['Em7'], ['A7sus4', 'A7']]
CH_A2 = [['D'], ['Gmaj7'], ['D/F#', 'A7'], ['Dadd9']]
# the bridge: B minor, tension that leans back into the call
BRIDGE = ('F#5 1 E5 .5 D5 .5 C#5 1 B4 1 | D5 1.5 C#5 .5 B4 1 A4 1 | G4 .5 A4 .5 B4 1 D5 1 C#5 1 | F#4 2 A#4 1 C#5 1 | '
          'B4 .5 D5 .5 F#5 1.5 E5 .5 D5 1 | G4 .5 B4 .5 E5 1.5 D5 .5 C#5 1 | D5 .5 C#5 .5 B4 .5 A4 .5 G4 1 E4 1 | '
          'A4 1 G4 .5 F#4 .5 E4 1 r 1')
CH_B = [['Bm7'], ['Gmaj7'], ['Em7', 'F#7'], ['F#7'], ['Bm'], ['Em7', 'A'], ['Gmaj7', 'Em7'], ['A7sus4', 'A7']]


def transpose_mode(notes, table):
    """swap pitch classes (for the minor / Dorian version of the call)"""
    return [(t, d, p + table.get(p % 12, 0)) for t, d, p in notes]


# ------------------------------------------------------------------------------------------- the score
class Score:
    GM = {'flute': 73, 'clarinet': 71, 'bassoon': 70, 'glock': 9, 'celesta': 8, 'musicbox': 10, 'vibes': 11,
          'marimba': 12, 'xylo': 13, 'kalimba': 108, 'nylon': 24, 'uke': (8, 24), 'pizz': 45, 'harp': 46,
          'strings': 49, 'bass': 32, 'tuba': 58, 'piano': 0, 'rhodes': 4, 'cello': 42, 'contrabass': 43,
          'warmpad': 89, 'halo': 94, 'whistle': 78, 'ocarina': 79, 'timpani': 47, 'mtrumpet': 59}

    def __init__(self, bpm, beats=4, swing=0.0, seed=7):
        self.bpm, self.beats, self.swing = bpm, beats, swing
        self.parts = {}   # name -> dict(ch, prog, vol, pan, rev, notes[])
        self.rnd = random.Random(seed)
        self.drum_kit = 40

    def part(self, name, inst, vol=96, pan=64, rev=50):
        if name not in self.parts:
            ch = len([p for p in self.parts.values() if p['ch'] != 9])
            ch = ch if ch < 9 else ch + 1
            self.parts[name] = dict(ch=9 if inst == 'drums' else ch, inst=inst, vol=vol, pan=pan, rev=rev, notes=[])
        return self.parts[name]['notes']

    def add(self, name, notes, vel=80, inst=None, octave=0, human=True, **kw):
        lst = self.part(name, inst or name, **kw)
        for t, d, p in notes:
            v = vel + (self.rnd.randint(-6, 6) if human else 0)
            lst.append((t, d, p + 12 * octave, max(1, min(127, v))))

    def hit(self, name, beat, note, vel=70, dur=0.25):
        self.part(name, 'drums', vol=90, rev=30).append((beat, dur, note, vel))

    def bar_len(self):
        return self.beats

    # ---- write MIDI
    def save(self, path, total_beats):
        mf = mido.MidiFile(ticks_per_beat=PPQ)
        meta = mido.MidiTrack()
        meta.append(mido.MetaMessage('set_tempo', tempo=mido.bpm2tempo(self.bpm)))
        meta.append(mido.MetaMessage('time_signature', numerator=self.beats, denominator=4))
        meta.append(mido.MetaMessage('end_of_track', time=int(total_beats * PPQ)))
        mf.tracks.append(meta)
        for name, p in self.parts.items():
            tr = mido.MidiTrack()
            tr.append(mido.MetaMessage('track_name', name=name))
            ch = p['ch']
            if p['inst'] == 'drums':
                tr.append(mido.Message('program_change', channel=9, program=self.drum_kit))
            else:
                prog = self.GM[p['inst']]
                bank, prog = prog if isinstance(prog, tuple) else (0, prog)
                tr.append(mido.Message('control_change', channel=ch, control=0, value=bank))
                tr.append(mido.Message('program_change', channel=ch, program=prog))
            for cc, v in ((7, p['vol']), (10, p['pan']), (91, p['rev']), (93, 0)):
                tr.append(mido.Message('control_change', channel=ch, control=cc, value=v))
            ev = []
            for t, d, n, v in p['notes']:
                # swing: off-beat eighths lean late; a breath of timing looseness
                frac = t % 1.0
                if self.swing and abs(frac - 0.5) < 1e-6:
                    t += self.swing
                if p['inst'] != 'drums' or True:
                    t += self.rnd.uniform(-0.008, 0.008)
                t = max(0.0, t)
                ev.append((int(t * PPQ), 1, n, v))
                ev.append((int((t + d * 0.97) * PPQ), 0, n, 0))
            ev.sort(key=lambda e: (e[0], e[1]))
            now = 0
            for tick, on, n, v in ev:
                msg = 'note_on' if on else 'note_off'
                tr.append(mido.Message(msg, channel=ch, note=n, velocity=v if on else 0, time=tick - now))
                now = tick
            mf.tracks.append(tr)
        mf.save(path)


# ------------------------------------------------------------------------------------------- accompaniment
def per_beat(chords_by_bar, bar0, beats=4):
    """[(start beat, length, chord symbol)] from a list of bars, each bar a list of chords sharing it equally"""
    out = []
    for i, bar in enumerate(chords_by_bar):
        L = beats / len(bar)
        for j, c in enumerate(bar):
            out.append(((bar0 + i) * beats + j * L, L, c))
    return out


def bass_two(chs, octave=2):
    out = []
    for t, L, c in chs:
        r, iv, b = chord(c)
        root = 12 * (octave + 1) + b
        if L >= 4:
            out += [(t, 1.5, root), (t + 2, 1.0, 12 * (octave + 1) + (r + 7) % 12 + (12 if (r + 7) % 12 < b else 0)),
                    (t + 3.5, 0.5, root)]
        else:
            out += [(t, L * 0.75, root)]
    return out


def bass_walk(chs, octave=2):
    out = []
    for t, L, c in chs:
        r, iv, b = chord(c)
        base = 12 * (octave + 1)
        steps = [b, (r + iv[1]) % 12, (r + 7) % 12, (r + iv[1]) % 12]
        for k in range(int(L)):
            pc = steps[k % 4]
            out.append((t + k, 0.9, base + pc + (12 if pc < b and k else 0)))
    return out


def comp_offbeat(chs, low=57, dur=0.35):
    """boom-chick: the chord on 2 and 4 (and the "and" of 4)"""
    out = []
    for t, L, c in chs:
        v = voicing(c, low, 3)
        for k in [x for x in (1, 3) if x < L]:
            out += [(t + k, dur, p) for p in v]
        if L >= 4:
            out += [(t + 3.5, dur * 0.7, p) for p in v]
    return out


def strum(chs, low=55, pattern=(0, 1, 1.5, 2.5, 3, 3.5)):
    out = []
    for t, L, c in chs:
        v = voicing(c, low, 4)
        for k in [x for x in pattern if x < L]:
            for i, p in enumerate(v):
                out.append((t + k + i * 0.025, 0.45, p))
    return out


def arp(chs, low=62, step=0.5, shape=(0, 1, 2, 3, 2, 1, 0, 1)):
    out = []
    for t, L, c in chs:
        v = voicing(c, low, 4)
        n = int(L / step)
        for k in range(n):
            out.append((t + k * step, step * 0.9, v[shape[k % len(shape)] % len(v)]))
    return out


def pad(chs, low=55, n=4):
    out = []
    for t, L, c in chs:
        out += [(t, L, p) for p in voicing(c, low, n)]
    return out


def brushes(s, bar0, bars, full=True, beats=4, vel=1.0):
    for b in range(bars):
        t0 = (bar0 + b) * beats
        s.hit('drums', t0, 36, int(62 * vel))
        if beats == 4:
            s.hit('drums', t0 + 2, 36, int(50 * vel))
        for k in range(1, beats, 2):
            s.hit('drums', t0 + k, 38, int(58 * vel))
        if full:
            for k in range(beats * 2):
                s.hit('drums', t0 + k * 0.5, 44 if k % 2 else 42, int((34 if k % 2 else 42) * vel), 0.2)
            for k in range(beats * 2):
                s.hit('drums', t0 + k * 0.5 + 0.25, 70, int(26 * vel), 0.1)


# ------------------------------------------------------------------------------------------- the pieces
def main_theme():
    """Title screen, 100 BPM, 36 bars (86 s), loops. Hook at 0 s; develop 10-29 s; bridge 29-48 s; payoff
    48-67 s; resolve 67-86 s, ending so it rolls straight back into the call."""
    s = Score(100, swing=0.04)
    A, A2 = melody(THEME_A, 0), melody(THEME_A2, 4)
    # 1-4 the hook: flute and glockenspiel, marimba boom-chick, bass, light brushes
    s.add('flute', melody(THEME_A, 0), 92, vol=100, pan=64, rev=55)
    s.add('glock', melody(THEME_A, 0), 64, inst='glock', octave=1, vol=70, pan=74, rev=60)
    chs = per_beat(CH_A, 0) + per_beat(CH_A2, 4)
    # 5-8 the answer
    s.add('flute', melody(THEME_A2, 4), 92)
    s.add('glock', melody(THEME_A2, 4), 60, inst='glock', octave=1)
    s.add('marimba', comp_offbeat(chs, 57), 70, vol=88, pan=44, rev=45)
    s.add('bass', bass_two(chs), 84, vol=100, pan=64, rev=20)
    brushes(s, 0, 8, full=False, vel=0.8)
    # 9-12 the call again, richer: clarinet takes it, flute answers a sixth below, ukulele strums
    chs2 = per_beat([['Dmaj7'], ['G6/9'], ['Em9' if False else 'Em7'], ['A7sus4', 'A7']], 8)
    s.add('clarinet', melody(THEME_A, 8), 88, vol=96, pan=58, rev=55)
    s.add('flute', [(t, d, p - 9 + (1 if (p - 9) % 12 in (0, 3, 5, 8, 10) else 0)) for t, d, p in melody(THEME_A, 8)], 62)
    s.add('uke', strum(chs2, 55), 58, inst='uke', vol=86, pan=84, rev=40)
    s.add('pizz', arp(chs2, 62), 54, inst='pizz', vol=80, pan=96, rev=50)
    s.add('marimba', comp_offbeat(chs2, 57), 64)
    s.add('bass', bass_walk(chs2), 82)
    brushes(s, 8, 4)
    # 13-20 the bridge: B minor, vibraphone and clarinet, thinner, then building
    chb = per_beat(CH_B, 12)
    br = melody(BRIDGE, 12)
    s.add('vibes', br, 80, inst='vibes', vol=96, pan=60, rev=65)
    s.add('clarinet', [(t, d, p) for t, d, p in br if t >= 16 * 4], 70)
    s.add('pizz', arp(chb, 59, shape=(0, 2, 1, 3)), 50)
    s.add('bass', bass_two(chb), 78)
    s.add('strings', pad(per_beat(CH_B[4:], 16), 54), 46, inst='strings', vol=80, pan=64, rev=70)
    brushes(s, 12, 4, full=False, vel=0.7)
    brushes(s, 16, 4, full=True, vel=0.9)
    for k in range(8):   # a lift into the payoff
        s.hit('drums', 19 * 4 + 2 + k * 0.25, 38, 40 + k * 7, 0.2)
    s.add('timpani', [(19 * 4 + 3, 1, midi('A2'))], 70, inst='timpani', vol=90, rev=40)
    # 21-28 the payoff: everyone, the call doubled in octaves
    chp = per_beat(CH_A, 20) + per_beat(CH_A2, 24)
    for name, vel, octv in (('flute', 98, 0), ('glock', 66, 1), ('xylo', 58, 0), ('clarinet', 70, -1)):
        s.add(name, melody(THEME_A, 20) + melody(THEME_A2, 24), vel, inst=name, octave=octv,
              **({'vol': 80, 'pan': 30, 'rev': 50} if name == 'xylo' else {}))
    s.add('uke', strum(chp, 55), 66, inst='uke')
    s.add('marimba', comp_offbeat(chp, 57), 72)
    s.add('pizz', arp(chp, 62), 58)
    s.add('bass', bass_walk(chp), 88)
    s.add('strings', pad(chp, 57), 50, inst='strings')
    s.hit('drums', 20 * 4, 49, 64, 2)
    brushes(s, 20, 8, vel=1.05)
    # 29-32 resolve: the answer, softly, music box on top
    chr_ = per_beat(CH_A2, 28)
    s.add('flute', melody(THEME_A2, 28), 76)
    s.add('musicbox', melody(THEME_A2, 28), 58, inst='musicbox', octave=1, vol=80, pan=70, rev=70)
    s.add('marimba', comp_offbeat(chr_, 57), 60)
    s.add('bass', bass_two(chr_), 76)
    brushes(s, 28, 4, full=False, vel=0.7)
    # 33-36 the tag: the call's first bar twice, then a turn that leads back to bar 1
    tag = melody('A4 .5 D5 .5 F#5 1.5 E5 .5 D5 1 | r 4 | A4 .5 D5 .5 F#5 1.5 E5 .5 D5 1 | E5 1 F#5 1 E5 1 r 1', 32)
    s.add('glock', tag, 62, inst='glock', octave=1)
    s.add('flute', tag, 70)
    cht = per_beat([['Dmaj9'], ['Gmaj7'], ['Dmaj9'], ['A7sus4', 'A7']], 32)
    s.add('rhodes', pad(cht, 54), 50, inst='rhodes', vol=84, pan=50, rev=60)
    s.add('bass', bass_two(cht), 72)
    s.add('pizz', arp(cht, 62), 46)
    brushes(s, 32, 4, full=False, vel=0.6)
    return s, 36 * 4, True


def nest():
    """The home screen, 84 BPM with a lazy swing, 26 bars (74 s), loops. Rhodes and kalimba, the call slowed
    down and warm; a gentle B section; music box on the last answer."""
    s = Score(84, swing=0.09, seed=11)
    warmA = [['Dmaj9'], ['G6/9'], ['Em7'], ['A7sus4', 'A7']]
    warmA2 = [['Dmaj9'], ['Gmaj9'], ['D/F#', 'A7sus4'], ['Dadd9']]
    intro = per_beat([['Dmaj9'], ['Gmaj9']], 0)
    s.add('rhodes', pad(intro, 52), 52, inst='rhodes', vol=96, pan=58, rev=60)
    s.add('nylon', arp(intro, 50, shape=(0, 2, 1, 3, 2, 1, 3, 2)), 50, inst='nylon', vol=84, pan=40, rev=50)
    s.add('bass', [(t, L, 12 * 3 + chord(c)[2]) for t, L, c in intro], 70, vol=92, rev=20)
    # 3-10 the call on kalimba (A, A'), Rhodes chords, nylon guitar picking, upright bass, soft brushes
    chs = per_beat(warmA, 2) + per_beat(warmA2, 6)
    s.add('kalimba', melody(THEME_A, 2) + melody(THEME_A2, 6), 86, inst='kalimba', vol=104, pan=66, rev=55)
    s.add('rhodes', pad(chs, 52), 48)
    s.add('nylon', arp(chs, 50, shape=(0, 2, 1, 3, 2, 1, 3, 2)), 46)
    s.add('bass', bass_two(chs), 70)
    brushes(s, 2, 8, full=False, vel=0.55)
    # 11-18 the bridge, gentled: felt-soft vibraphone, no tension chords, resolving to the dominant
    soft_b = ('F#5 1 E5 .5 D5 .5 C#5 1 B4 1 | D5 1.5 C#5 .5 B4 1 A4 1 | G4 .5 A4 .5 B4 1 D5 1 E5 1 | F#5 2 E5 2 | '
              'B4 .5 D5 .5 F#5 1.5 E5 .5 D5 1 | G4 .5 B4 .5 E5 1.5 D5 .5 C#5 1 | D5 1 B4 1 A4 1 G4 1 | A4 3 r 1')
    chb = per_beat([['Bm7'], ['Gmaj7'], ['Em7'], ['A7sus4'], ['Bm7'], ['Em7', 'A'], ['Gmaj7', 'Em7'], ['A7sus4', 'A7']], 10)
    s.add('vibes', melody(soft_b, 10), 74, inst='vibes', vol=92, pan=60, rev=70)
    s.add('rhodes', pad(chb, 52), 44)
    s.add('nylon', arp(chb, 50, shape=(0, 2, 1, 3, 2, 1, 3, 2)), 42)
    s.add('bass', bass_two(chb), 66)
    brushes(s, 10, 8, full=False, vel=0.5)
    # 19-22 the answer, music box over kalimba
    cha = per_beat(warmA2, 18)
    s.add('kalimba', melody(THEME_A2, 18), 80, inst='kalimba')
    s.add('musicbox', melody(THEME_A2, 18), 54, inst='musicbox', octave=1, vol=80, pan=76, rev=75)
    s.add('rhodes', pad(cha, 52), 46)
    s.add('nylon', arp(cha, 50, shape=(0, 2, 1, 3, 2, 1, 3, 2)), 44)
    s.add('bass', bass_two(cha), 66)
    brushes(s, 18, 4, full=False, vel=0.5)
    # 23-26 a resting tag: the call's head, echoed, then the turn back to the intro
    tag = melody('A4 .5 D5 .5 F#5 3 | r 4 | B4 .5 D5 .5 E5 3 | r 4', 22)
    cht = per_beat([['Dmaj9'], ['Dmaj9'], ['Gmaj9'], ['A7sus4']], 22)
    s.add('kalimba', tag, 70, inst='kalimba')
    s.add('rhodes', pad(cht, 52), 46)
    s.add('nylon', arp(cht, 50, shape=(0, 2, 1, 3, 2, 1, 3, 2)), 40)
    s.add('bass', bass_two(cht), 62)
    return s, 26 * 4, True


def deep_wilds():
    """Exploring deeper, 92 BPM, 28 bars (73 s), loops. The call in D Dorian over a cello drone and a kalimba
    ostinato; halfway through it turns briefly major (a clearing of light), then back into the dark."""
    s = Score(92, seed=21)
    minor = {6: -1, 11: 0, 1: -1}      # F# -> F, C# -> C (B stays natural: Dorian)
    dorA = transpose_mode(melody(THEME_A, 0), minor)
    dorA2 = transpose_mode(melody(THEME_A2.replace('B4 .5 D5 .5 G5', 'Bb4 .5 D5 .5 G5'), 0), minor)
    CH_D = [['Dm9'], ['G/D'], ['Dm9'], ['C', 'A7sus4']]
    CH_D2 = [['Dm9'], ['Bbmaj7'], ['C', 'A7sus4'], ['Dm9']]

    def ostinato(bar0, bars, vel):
        pat = melody('D4 .5 A4 .5 C5 .5 E5 .5 D4 .5 A4 .5 C5 .5 F5 .5', 0)
        for b in range(bars):
            s.add('kalimba', [(t + (bar0 + b) * 4, d, p) for t, d, p in pat], vel, inst='kalimba', vol=92, pan=40, rev=70)

    def drone(bar0, bars, vel=52):
        s.add('cello', [((bar0 + b) * 4, 4, midi('D2')) for b in range(bars)] + [((bar0 + b) * 4, 4, midi('A2')) for b in range(bars)],
              vel, inst='contrabass', vol=96, pan=64, rev=60)

    def toms(bar0, bars, vel=1.0):
        for b in range(bars):
            t0 = (bar0 + b) * 4
            for k, n, v in ((0, 41, 60), (1.5, 45, 44), (2, 41, 52), (3.5, 45, 40)):
                s.hit('drums', t0 + k, n, int(v * vel), 0.4)
            s.hit('drums', t0 + 1, 76, int(30 * vel), 0.1)
            s.hit('drums', t0 + 3, 77, int(28 * vel), 0.1)

    # 1-4 the woods: ostinato and drone
    ostinato(0, 4, 56)
    drone(0, 4)
    s.add('halo', pad(per_beat(CH_D, 0), 50, 3), 34, inst='halo', vol=72, pan=64, rev=90)
    # 5-12 the call in Dorian, celesta, then flute low; marimba chords; soft toms
    ostinato(4, 8, 52)
    drone(4, 8)
    s.add('celesta', [(t + 16, d, p) for t, d, p in dorA], 84, inst='celesta', vol=100, pan=70, rev=75)
    s.add('flute', [(t + 32, d, p - 12) for t, d, p in dorA2], 80, inst='flute', vol=92, pan=60, rev=70)
    chs = per_beat(CH_D, 4) + per_beat(CH_D2, 8)
    s.add('marimba', [(t, L, p) for t, L, c in chs for p in voicing(c, 50, 3)], 50, inst='marimba', vol=78, pan=84, rev=60)
    s.add('halo', pad(chs, 50, 3), 32, inst='halo')
    toms(4, 8, 0.8)
    # 13-16 a clearing: the call in D major, glockenspiel and harp, the drone lifts
    clr = per_beat([['Dmaj7'], ['G6'], ['Em7'], ['A7sus4', 'A']], 12)
    s.add('glock', [(t + 48, d, p + 12) for t, d, p in melody(THEME_A, 0)], 66, inst='glock', vol=80, pan=76, rev=80)
    s.add('harp', arp(clr, 57, step=0.5, shape=(0, 1, 2, 3, 2, 3, 1, 2)), 58, inst='harp', vol=90, pan=50, rev=70)
    s.add('halo', pad(clr, 52, 4), 40, inst='halo')
    s.add('cello', [(t, L, 12 * 2 + chord(c)[2]) for t, L, c in clr], 46, inst='contrabass')
    # 17-24 back into the dark, fuller: the call on clarinet over the ostinato, toms building
    ostinato(16, 8, 58)
    drone(16, 8, 56)
    s.add('clarinet', [(t + 64, d, p - 12) for t, d, p in dorA] + [(t + 80, d, p - 12) for t, d, p in dorA2], 84,
          inst='clarinet', vol=96, pan=58, rev=65)
    s.add('celesta', [(t + 80, d, p) for t, d, p in dorA2], 60, inst='celesta')
    chs = per_beat(CH_D, 16) + per_beat(CH_D2, 20)
    s.add('marimba', [(t, L, p) for t, L, c in chs for p in voicing(c, 50, 3)], 54, inst='marimba')
    s.add('pizz', arp(chs, 57, shape=(0, 2, 1, 3)), 48, inst='pizz', vol=80, pan=96, rev=60)
    toms(16, 8, 1.0)
    # 25-28 fading back to the ostinato and drone, a last echo of the call on celesta
    ostinato(24, 4, 50)
    drone(24, 4, 48)
    s.add('celesta', [(t + 96, d, p) for t, d, p in transpose_mode(melody('A4 .5 D5 .5 F#5 3', 0), minor)], 58, inst='celesta')
    s.add('halo', pad(per_beat(CH_D, 24), 50, 3), 30, inst='halo')
    toms(24, 2, 0.5)
    return s, 28 * 4, True


def hatching():
    """The egg hatching, 72 BPM, 10 bars + ring-out (~38 s), one shot. The call's head on a music box over a
    heartbeat; the egg wobbles (marimba trills), cracks (pizzicato, woodblocks), a breath; then the answer
    blooms with everyone, ending IV-I on a held D with chimes."""
    s = Score(72, seed=31)
    # 1-2 hush: music box plays the call's head, slowly; a heartbeat on kalimba
    s.add('musicbox', melody('A4 1 D5 1 F#5 2 | E5 1 D5 1 A4 2', 0), 74, inst='musicbox', octave=1, vol=96, pan=64, rev=75)
    for b in range(4):
        s.add('kalimba', [(b * 4, 0.4, midi('D3')), (b * 4 + 0.5, 0.4, midi('D3'))], 58 + b * 4, inst='kalimba', vol=90, rev=40)
    s.add('halo', pad(per_beat([['Dadd9'], ['Gmaj7']], 0), 52, 3), 34, inst='halo', vol=76, pan=64, rev=90)
    # 2-4 the wobbles: marimba trills that swell, each a step higher
    for k, (a, b_, t0) in enumerate((('D5', 'E5', 5.0), ('F#5', 'G5', 9.0), ('A5', 'B5', 12.0))):
        n = 12 + 4 * k
        s.add('marimba', [(t0 + i * 0.125, 0.12, midi(a if i % 2 == 0 else b_)) for i in range(n)], 40 + 8 * k,
              inst='marimba', vol=88, pan=80, rev=60, human=False)
    # the cracks: a pizzicato snap and woodblocks, then a big one and a breath
    for t, n in ((8.0, 76), (11.5, 77), (13.75, 76), (14.0, 77)):
        s.hit('drums', t, n, 80, 0.1)
    s.add('pizz', [(8.0, 0.2, midi('A5')), (11.5, 0.2, midi('B5')), (14.0, 0.25, midi('D6'))], 92, inst='pizz', vol=96, pan=40, rev=50)
    s.add('kalimba', [(12.0, 0.4, midi('D3')), (12.5, 0.4, midi('D3')), (13.0, 0.4, midi('D3')), (13.5, 0.4, midi('D3'))], 70, inst='kalimba')
    # (beat 15: silence)
    # 5-8 the bloom: the answer, everyone, harp sweep in
    s.add('harp', [(15.5 + i * 0.0625, 0.5, p) for i, p in enumerate(voicing('Dmaj9', 50, 8))], 70, inst='harp', vol=96, pan=50, rev=70, human=False)
    bloom = [(t + 16, d, p) for t, d, p in melody(THEME_A2, 0)]
    # the last bar holds: the answer's final D lasts through the IV-I cadence
    bloom = [(t, (12 if t >= 28 else d), p) for t, d, p in bloom]
    for name, vel, octv in (('flute', 94, 0), ('celesta', 70, 1), ('glock', 60, 1)):
        s.add(name, bloom, vel, inst=name, octave=octv, vol=96 if name == 'flute' else 82, pan=64, rev=70)
    chs = per_beat([['Dadd9'], ['Gmaj7'], ['D/F#', 'A7sus4'], ['Gmaj7', 'Em7'], ['Dadd9'], ['Dadd9']], 4)
    s.add('strings', pad(chs, 54), 58, inst='strings', vol=92, pan=64, rev=75)
    s.add('pizz', arp(chs[:5], 62), 52, inst='pizz')
    s.add('rhodes', pad(chs, 50, 4), 46, inst='rhodes', vol=80, pan=40, rev=60)
    s.add('bass', [(t, L, 12 * 3 + chord(c)[2]) for t, L, c in chs], 70, inst='bass', vol=96, rev=30)
    s.hit('drums', 16.0, 49, 48, 4)
    for k in range(16):           # a cymbal swell into the home chord
        s.hit('drums', 30 + k * 0.125, 51, 20 + k * 2, 0.1)
    # the wind chimes on the final chord
    for k in range(10):
        s.hit('drums', 32 + k * 0.18, 81 if k % 2 else 80, 60 - k * 3, 0.5)
    s.add('timpani', [(32, 2, midi('D2'))], 66, inst='timpani', vol=90, rev=50)
    return s, 11 * 4, False


PIECES = {'evochi_main_theme': main_theme, 'evochi_nest': nest, 'evochi_deep_wilds': deep_wilds, 'evochi_hatching': hatching}


# ------------------------------------------------------------------------------------------- render, master
def render(name, out, sf2):
    s, total, loop = PIECES[name]()
    mid = os.path.join(out, name + '.mid')
    s.save(mid, total + (8 if loop else 4) * s.beats)
    wav = os.path.join(out, name + '_raw.wav')
    subprocess.run(['fluidsynth', '-ni', '-q', '-g', '0.5', '-r', '48000', '-o', 'synth.reverb.room-size=0.45',
                    '-o', 'synth.reverb.width=0.9', '-o', 'synth.reverb.level=0.6', '-o', 'synth.chorus.active=0',
                    '-F', wav, sf2, mid], check=True, capture_output=True)
    import numpy as np
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', wav, '-f', 'f32le', '-ac', '2', '-ar', '48000', '-'],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.float32).reshape(-1, 2).copy()
    sec = 60.0 / s.bpm * total
    n = int(round(sec * 48000))
    if loop:
        # the loop: cut on the last bar line and lay the ring-out over the start, so it rolls straight round
        tail = x[n:n + 48000 * 4]
        x = x[:n].copy()
        x[:len(tail)] += tail
    else:
        x = x[:n + 48000 * 4]
        k = 48000 * 2
        x[-k:] *= np.linspace(1, 0, k)[:, None] ** 2
    tmp = os.path.join(out, name + '_cut.wav')
    x.astype(np.float32).tofile(tmp + '.f32')
    master = os.path.join(out, name + '.mp3')
    tone = ('highpass=f=40,equalizer=f=320:t=q:w=1.2:g=-1.5,equalizer=f=9000:t=h:w=1:g=1.5,'
            'acompressor=threshold=-20dB:ratio=2.2:attack=15:release=180:makeup=2')
    if not loop:   # a one-shot ends where its ring-out falls quiet, with a short fade
        tone += ',areverse,silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.3,afade=t=in:d=0.3,areverse'
    src = ['-f', 'f32le', '-ar', '48000', '-ac', '2', '-i', tmp + '.f32']
    # two-pass loudness: measure, then a linear gain to -16 LUFS / -1.5 dBTP (every piece at the same level)
    import json as _json
    meas = subprocess.run(['ffmpeg', '-v', 'info', '-hide_banner', *src, '-af', tone + ',loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json',
                           '-f', 'null', '-'], capture_output=True, text=True).stderr
    m = _json.loads(meas[meas.rindex('{'):meas.rindex('}') + 1])
    ln = ('loudnorm=I=-16:TP=-1.5:LRA=11:measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:offset=%s:linear=true'
          % (m['input_i'], m['input_tp'], m['input_lra'], m['input_thresh'], m['target_offset']))
    subprocess.run(['ffmpeg', '-v', 'error', '-y', *src, '-af', tone + ',' + ln,
                    '-ar', '48000', '-c:a', 'libmp3lame', '-q:a', '2', master], check=True)
    os.remove(tmp + '.f32')
    os.remove(wav)
    return master, mid, sec, loop


if __name__ == '__main__':
    out = sys.argv[1]
    sf2 = sys.argv[sys.argv.index('--sf2') + 1] if '--sf2' in sys.argv else SF2
    only = [a for a in sys.argv[2:] if a in PIECES] or list(PIECES)
    os.makedirs(out, exist_ok=True)
    for name in only:
        m, mid, sec, loop = render(name, out, sf2)
        print('%-20s %5.1fs %s -> %s' % (name, sec, 'loop' if loop else 'one-shot', m))

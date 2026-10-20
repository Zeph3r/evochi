"""Place music for Evochi: gentle arrangements of public-domain traditional airs.

The melodies come from "O'Neill's Music of Ireland" (Chicago, 1850 edition), whose tunes have
long been public domain, as encoded in the music21 corpus (pip install music21; transcribed by
Norbert Paap). Aird's 1778 "Selection of Scotch, English, Irish and Foreign Airs" is in the same
corpus if more are wanted. Only the melody notes are taken. The harmony, accompaniment, instruments, form and
mix are written here, so every arrangement is our own.

For each tune the script:
- harmonises the melody (diatonic triads chosen per bar, or per half bar in 4/4, by a small Viterbi
  pass that weighs melody notes by beat and prefers the usual folk progressions);
- arranges it for a cozy palette: a harp, guitar or marimba accompaniment, a soft pad and bass, and
  a melody that changes instrument on each pass, with a sprinkle of celesta on the last;
- adds a two-bar intro and a held final chord with a ritardando;
- renders it with FluidSynth and the FluidR3 GM soundfont (MIT; apt install fluidsynth
  fluid-soundfont-gm);
- levels it quietly (it plays under the place's ambience) and encodes a stereo mp3.

    python3 tools/art/music.py OUT_DIR [track ids...] [--mid] [--wav]

Tracks play once, then the game leaves a quiet gap before the next one, so nothing needs to loop.
"""
import os
import re
import subprocess
import sys
import wave

import mido
import numpy as np
from music21 import converter, corpus, key as m21key, meter

CORPUS = os.path.dirname(corpus.__file__)
SF2 = '/usr/share/sounds/sf2/FluidR3_GM.sf2'
TPB = 480  # ticks per quarter note

# General MIDI programs
HARP, NYLON, MARIMBA, PIANO, CELESTA, MUSICBOX, VIBES, GLOCK = 46, 24, 12, 0, 8, 10, 11, 9
FLUTE, RECORDER, PANFLUTE, OCARINA, CLARINET, OBOE, WHISTLE = 73, 74, 75, 79, 71, 68, 78
STRINGS_SLOW, WARMPAD, CHOIR, CELLO, ACBASS, PIZZ, ACCORDION = 49, 89, 52, 42, 32, 45, 21

# where a melody instrument sits best (median MIDI note of the tune after octave shifting)
SWEET = {FLUTE: 79, RECORDER: 79, PANFLUTE: 76, OCARINA: 76, CLARINET: 69, OBOE: 74, WHISTLE: 81,
         CELESTA: 72, MUSICBOX: 79, VIBES: 74, HARP: 74, PIANO: 74, GLOCK: 79, ACCORDION: 72, MARIMBA: 74}

# id: (collection file, X number, quarter-note tempo, accompaniment, melody passes, pad, bass, title)
TRACKS = {
    # the Nest
    'skylark': ('oneills1850/0101-0200.abc', 187, 92, NYLON, [FLUTE, CELESTA, FLUTE], STRINGS_SLOW, ACBASS, 'The Skylark'),
    'red_lark': ('oneills1850/0051-0100.abc', 72, 96, HARP, [RECORDER, VIBES, RECORDER], WARMPAD, None, 'The Little Red Lark'),
    # Home: the map, the garden, the cottage
    'fair_maid': ('oneills1850/0001-0050.abc', 38, 96, NYLON, [OCARINA, CLARINET, OCARINA], STRINGS_SLOW, ACBASS, 'Good Morning Fair Maid'),
    'summer_morning': ('oneills1850/0101-0200.abc', 148, 66, HARP, [FLUTE, CELESTA, FLUTE], STRINGS_SLOW, None, "'Twas on a Summer Morning"),
    # the Square
    'my_love': ('oneills1850/0101-0200.abc', 125, 100, NYLON, [RECORDER, CLARINET, RECORDER], STRINGS_SLOW, PIZZ, 'Of My Love I Was Thinking'),
    'black_rose': ('oneills1850/0101-0200.abc', 137, 92, HARP, [CLARINET, FLUTE, CLARINET], STRINGS_SLOW, CELLO, 'The Bright Black Rose'),
    # the Kitchen
    'old_mill': ('oneills1850/0101-0200.abc', 159, 84, NYLON, [VIBES, CLARINET, VIBES], WARMPAD, ACBASS, 'Down by the Old Mill'),
    # the Apothecary
    'enchanted_valley': ('oneills1850/0001-0050.abc', 1, 52, HARP, [CELESTA, FLUTE, CELESTA], CHOIR, CELLO, 'The Enchanted Valley'),
    # Bram's Workshop
    'bench_of_rushes': ('oneills1850/0101-0200.abc', 136, 88, NYLON, [CLARINET, OBOE, CLARINET], STRINGS_SLOW, ACBASS, 'The Little Bench of Rushes'),
    # the Trail Guild
    'seaside': ('oneills1850/0201-0300.abc', 287, 88, NYLON, [WHISTLE, OBOE, WHISTLE], STRINGS_SLOW, CELLO, 'Down at the Seaside'),
    # Mira's Glasshouse
    'fairy_boy': ('oneills1850/0201-0300.abc', 243, 90, HARP, [FLUTE, CELESTA, FLUTE], STRINGS_SLOW, None, 'The Fairy Boy'),
    'lullaby': ('oneills1850/0301-0350.abc', 346, 72, HARP, [MUSICBOX, FLUTE, MUSICBOX], WARMPAD, None, 'An Irish Lullaby'),
    # the Mossy Ruins
    'young_mans_dream': ('oneills1850/0351-0400.abc', 382, 72, HARP, [PANFLUTE, CELESTA, PANFLUTE], STRINGS_SLOW, CELLO, "The Young Man's Dream"),
    'fair_child': ('oneills1850/0001-0050.abc', 7, 84, NYLON, [FLUTE, CLARINET, FLUTE], STRINGS_SLOW, None, 'The Little Fair Child'),
    # dusk: the Sentinel Gate, and the ruins while the Hollow holds them
    'dark_woman': ('oneills1850/0001-0050.abc', 6, 76, HARP, [CELESTA, PANFLUTE, CELESTA], CHOIR, CELLO, 'The Dark Woman of the Glen'),
    # the Market
    'good_ship': ('oneills1850/0401-0486.abc', 435, 104, MARIMBA, [RECORDER, VIBES, RECORDER], STRINGS_SLOW, PIZZ, 'The Good Ship Planet'),
}


# --------------------------------------------------------------------------------- reading ----
def load(rel, x):
    text = open(os.path.join(CORPUS, rel), encoding='latin-1').read()
    for blk in re.split(r'\n(?=X:)', text):
        if re.match(r'X:\s*%d\s*$' % x, blk.split('\n')[0]):
            return converter.parse(blk, format='abc')
    raise SystemExit(f'{rel}: no X:{x}')


def melody(score):
    """The tune as (offset, duration, midi) in quarter notes, its measures as (offset, length), its
    key and its bar length."""
    part = score.parts[0] if hasattr(score, 'parts') and score.parts else score
    try:
        part = part.expandRepeats()
    except Exception:
        pass
    part = part.stripTies()
    ks = list(part.recurse().getElementsByClass(m21key.Key))
    k = ks[0] if ks else part.analyze('key')
    ts = list(part.recurse().getElementsByClass(meter.TimeSignature))
    ts = ts[0] if ts else meter.TimeSignature('4/4')
    bar = float(ts.barDuration.quarterLength)
    notes, measures = [], []
    for m in part.getElementsByClass('Measure'):
        mo = float(m.offset)
        length = float(m.duration.quarterLength)
        if length <= 0:
            continue
        measures.append((mo, length))
        for n in m.recurse().notes:
            if n.duration.isGrace or float(n.duration.quarterLength) <= 0:
                continue
            p = max(n.pitches, key=lambda q: q.midi) if n.isChord else n.pitch
            notes.append((mo + float(n.offset), float(n.duration.quarterLength), p.midi))
    notes.sort()
    return notes, measures, k, ts, bar


# ------------------------------------------------------------------------------- harmonising ----
def triads(k):
    """The key's diatonic triads as (degree name, root pc, pcs). Minor keys also get a major V."""
    sc = [p.pitchClass for p in k.getScale(k.mode if k.mode in ('major', 'minor') else 'major').getPitches()[:7]] \
        if k.mode in ('major', 'minor') else None
    if sc is None:  # modal: build the mode from its tonic
        steps = {'dorian': [0, 2, 3, 5, 7, 9, 10], 'mixolydian': [0, 2, 4, 5, 7, 9, 10], 'phrygian': [0, 1, 3, 5, 7, 8, 10],
                 'lydian': [0, 2, 4, 6, 7, 9, 11], 'aeolian': [0, 2, 3, 5, 7, 8, 10], 'locrian': [0, 1, 3, 5, 6, 8, 10]}.get(k.mode, [0, 2, 4, 5, 7, 9, 11])
        sc = [(k.tonic.pitchClass + s) % 12 for s in steps]
    names = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII']
    out = []
    for d in range(7):
        pcs = (sc[d], sc[(d + 2) % 7], sc[(d + 4) % 7])
        out.append((names[d], sc[d], pcs))
    if k.mode == 'minor':
        out.append(('V+', sc[4], (sc[4], (sc[4] + 4) % 12, (sc[4] + 7) % 12)))
    return out


PRIOR = {'I': 0.35, 'IV': 0.2, 'V': 0.2, 'V+': 0.18, 'VI': 0.08, 'II': 0.02, 'III': -0.1, 'VII': -0.05}
MOVE = {('V', 'I'): 0.4, ('V+', 'I'): 0.45, ('IV', 'I'): 0.2, ('IV', 'V'): 0.3, ('IV', 'V+'): 0.3, ('II', 'V'): 0.3,
        ('VI', 'IV'): 0.2, ('VI', 'II'): 0.15, ('I', 'IV'): 0.1, ('I', 'V'): 0.1, ('I', 'VI'): 0.08, ('V', 'VI'): 0.12,
        ('V', 'IV'): -0.3, ('V+', 'IV'): -0.3, ('VII', 'I'): 0.15, ('III', 'VI'): 0.1}


def strength(pos, bar, compound):
    if abs(pos) < 1e-6:
        return 1.0
    if abs(pos - bar / 2) < 1e-6 and not compound:
        return 0.75
    beat = 1.5 if compound else 1.0
    if abs(pos / beat - round(pos / beat)) < 1e-6:
        return 0.55 if not compound else 0.75
    return 0.28


def harmonise(notes, slots, k, bar, compound):
    """One chord per slot (a pickup gets none), by a Viterbi pass over the diatonic triads."""
    ch = triads(k)
    n = len(slots)
    score = np.full((n, len(ch)), -1e9)
    back = np.zeros((n, len(ch)), int)
    local = []
    for s0, s1, mo in slots:
        row = []
        for name, root, pcs in ch:
            v = PRIOR.get(name, 0)
            for (o, d, m) in notes:
                a, b = max(o, s0), min(o + d, s1)
                if b <= a:
                    continue
                w = (b - a) * strength(round((a - mo) % bar, 6), bar, compound) * (1.6 if o >= s0 - 1e-6 else 0.6)
                v += w * (1.0 if m % 12 in pcs else (-1.0 if w > 0.5 else -0.45))
            row.append(v)
        local.append(row)
    local = np.array(local)
    local[-1] += [3.0 if c[0] == 'I' else 0 for c in ch]
    if n > 1:
        local[-2] += [0.8 if c[0] in ('V', 'V+') else 0 for c in ch]
    score[0] = local[0]
    for i in range(1, n):
        for j, cj in enumerate(ch):
            best, arg = -1e9, 0
            for p, cp in enumerate(ch):
                v = score[i - 1][p] + MOVE.get((cp[0], cj[0]), 0) + (0.12 if p == j else 0)
                if v > best:
                    best, arg = v, p
            score[i][j] = best + local[i][j]
            back[i][j] = arg
    path = [int(np.argmax(score[-1]))]
    for i in range(n - 1, 0, -1):
        path.append(back[i][path[-1]])
    path.reverse()
    return [ch[j] for j in path]


# -------------------------------------------------------------------------------- arranging ----
class Song:
    def __init__(self, bpm):
        self.events = {c: [] for c in range(16)}  # channel -> (tick, msg)
        self.bpm = bpm
        self.tempo_map = []  # (tick, bpm)

    def note(self, ch, start_ql, dur_ql, midi, vel, jitter=0.0, rng=None):
        if midi < 21 or midi > 108:
            return
        t0 = int(round(start_ql * TPB + (rng.normal(0, jitter) if rng is not None and jitter else 0)))
        t1 = int(round((start_ql + dur_ql) * TPB))
        t0 = max(0, t0)
        if t1 <= t0 + 10:
            t1 = t0 + 10
        vel = int(np.clip(vel, 1, 127))
        self.events[ch].append((t0, mido.Message('note_on', channel=ch, note=midi, velocity=vel)))
        self.events[ch].append((t1, mido.Message('note_off', channel=ch, note=midi, velocity=0)))

    def setup(self, ch, program, volume, pan=64, reverb=60, chorus=0):
        for cc, v in ((7, volume), (10, pan), (91, reverb), (93, chorus)):
            self.events[ch].append((0, mido.Message('control_change', channel=ch, control=cc, value=v)))
        self.events[ch].append((0, mido.Message('program_change', channel=ch, program=program)))

    def save(self, path):
        mf = mido.MidiFile(ticks_per_beat=TPB)
        meta = mido.MidiTrack()
        last = 0
        for tick, bpm in sorted(self.tempo_map or [(0, self.bpm)]):
            meta.append(mido.MetaMessage('set_tempo', tempo=mido.bpm2tempo(bpm), time=tick - last))
            last = tick
        mf.tracks.append(meta)
        for ch, evs in self.events.items():
            if not evs:
                continue
            tr = mido.MidiTrack()
            evs.sort(key=lambda e: (e[0], 0 if e[1].type in ('control_change', 'program_change') else (1 if e[1].type == 'note_off' else 2)))
            last = 0
            for tick, msg in evs:
                tr.append(msg.copy(time=tick - last))
                last = tick
            mf.tracks.append(tr)
        mf.save(path)


def near(pc, lo, hi, target):
    """The MIDI note of pitch class pc in [lo, hi] closest to target."""
    best = None
    for m in range(lo, hi + 1):
        if m % 12 == pc and (best is None or abs(m - target) < abs(best - target)):
            best = m
    return best


def arrange(tid, spec, rng):
    rel, x, bpm, acc, passes, pad, bass, title = spec
    notes, measures, k, ts, bar = melody(load(rel, x))
    compound = ts.numerator in (6, 9, 12) and ts.denominator == 8
    split = (ts.numerator == 4 and ts.denominator == 4) or ts.ratioString in ('2/2',)
    slot_len = bar / 2 if split else bar
    # harmonic slots: a pickup (a short first measure) has none
    slots = []
    for i, (mo, length) in enumerate(measures):
        if length < bar - 1e-6 and i == 0:
            continue
        if slots and length < slot_len * 0.5 - 1e-6:
            # a sliver of a bar (a split bar at a repeat, a fermata): the chord before carries on
            a, b, m0 = slots[-1]
            slots[-1] = (a, mo + length, m0)
            continue
        t = 0.0
        while t < length - 1e-6:
            slots.append((mo + t, mo + min(t + slot_len, length), mo))
            t += slot_len
    chords = harmonise(notes, slots, k, bar, compound)
    tune_len = measures[-1][0] + measures[-1][1]
    pickup = measures[0][1] if measures and measures[0][1] < bar - 1e-6 else 0.0
    # octave placement per instrument
    med = float(np.median([m for _, _, m in notes]))

    def shift(prog):
        return int(round((SWEET.get(prog, 74) - med) / 12)) * 12

    song = Song(bpm)
    MEL_A, MEL_B, ACC, BASS, PAD, SPARK = 0, 1, 2, 3, 4, 5
    song.setup(MEL_A, passes[0], 100, 64, 70)
    song.setup(MEL_B, passes[1], 96, 70, 72)
    song.setup(ACC, acc, 92 if acc != MARIMBA else 80, 50, 64)
    if bass is not None:
        song.setup(BASS, bass, 78 if bass != PIZZ else 84, 64, 40)
    song.setup(PAD, pad, 54 if pad != CHOIR else 46, 82, 80)
    song.setup(SPARK, CELESTA, 70, 76, 85)
    tonic = triads(k)[0]
    # two or three passes, whichever lands nearer two minutes
    one = (np.ceil(tune_len / bar - 1e-6) * bar) * 60 / bpm
    if len(passes) > 2 and abs(2 * one - 120) < abs(3 * one - 120):
        passes = passes[:2]
    intro = 2 * bar
    start = intro - pickup  # the tune's offset 0 lands here, so its first full bar follows the intro
    cursor = 0.0

    def accomp(s0, length, chord, strong=1.0):
        name, root, pcs = chord
        third, fifth = pcs[1], pcs[2]
        r_lo = near(root, 40, 52, 45)
        tones = [r_lo, near(fifth, r_lo + 1, r_lo + 12, r_lo + 7), near(root, r_lo + 10, r_lo + 14, r_lo + 12),
                 near(third, r_lo + 13, r_lo + 19, r_lo + 16)]
        top = near(fifth, r_lo + 17, r_lo + 24, r_lo + 19)
        eighth = 0.5
        if acc == MARIMBA:
            pattern = [tones[0], tones[2], tones[1], tones[3], tones[2], tones[1]]
            step = eighth
            dur_k = 0.9
        else:
            pattern = [tones[0], tones[1], tones[2], tones[3], top, tones[3]] if compound or abs(length - 3) < 1e-6 else \
                [tones[0], tones[1], tones[2], tones[3]]
            step = eighth
            dur_k = 3.0  # let them ring (a harp or guitar)
        t = 0.0
        i = 0
        while t < length - 1e-6:
            m = pattern[i % len(pattern)]
            vel = (60 if i == 0 else 47 + 4 * ((i + 1) % 2)) * strong + rng.normal(0, 3)
            song.note(ACC, s0 + t, min(step * dur_k, length - t + 0.5), m, vel, 6, rng)
            t += step
            i += 1
        if bass is not None:
            b = near(root, 33 if bass in (CELLO, ACBASS, PIZZ) else 36, 47, 40)
            song.note(BASS, s0, length * (0.45 if bass == PIZZ else 0.95), b, 64 * strong + rng.normal(0, 2))
        return root, third, fifth

    prev_pad = None

    def pad_chord(s0, length, chord, vel=34):
        nonlocal prev_pad
        name, root, pcs = chord
        target = prev_pad or [55, 60, 64]
        voice = sorted(near(pc, 52, 74, t) for pc, t in zip(sorted(pcs, key=lambda p: (p - root) % 12), target))
        for m in voice:
            song.note(PAD, s0, length + 0.05, m, vel + rng.normal(0, 2))
        prev_pad = voice

    # intro: two bars on the tonic (the accompaniment alone, the pad sneaking in)
    for b in range(2):
        for j in range(int(round(bar / slot_len))):
            s0 = b * bar + j * slot_len
            accomp(s0, slot_len, tonic, 0.85)
            pad_chord(s0, slot_len, tonic, 26 + 4 * b)
    # the passes: each starts on a whole bar (a pickup tucks into the bar before it)
    period = float(np.ceil(tune_len / bar - 1e-6)) * bar
    for pi, prog in enumerate(passes):
        base = start + pi * period
        if pi > 0 and base + pickup - cursor > 1e-6:  # a breath bar between passes: keep the tonic going
            g0 = cursor
            while g0 < base + pickup - 1e-6:
                ln = min(slot_len, base + pickup - g0)
                accomp(g0, ln, tonic, 0.8)
                pad_chord(g0, ln, tonic, 30)
                g0 += ln
        ch = MEL_A if pi % 2 == 0 else MEL_B
        sh = shift(prog)
        last = len(passes) - 1
        for si, ((s0, s1, mo), chord) in enumerate(zip(slots, chords)):
            accomp(base + s0, s1 - s0, chord, 0.9 if pi == 0 else 1.0)
            pad_chord(base + s0, s1 - s0, chord, 30 if pi == 0 else 36)
        ordered = notes
        for ni, (o, d, m) in enumerate(ordered):
            nxt = ordered[ni + 1][0] if ni + 1 < len(ordered) else o + d
            legato = max(d, min(nxt - o, d * 1.15)) - 0.04  # a breath between notes
            phrase = ((o - pickup) % (4 * bar)) / (4 * bar)
            vel = 74 + 12 * np.sin(np.pi * phrase) + (6 if d >= 1 else 0) + rng.normal(0, 3)
            if prog in (CELESTA, MUSICBOX, VIBES, GLOCK):
                vel += 6
                legato = d  # struck: no legato
            song.note(ch, base + o, legato, m + sh, vel, 8, rng)
            # the last pass: a celesta glint on the long downbeat notes, an octave up
            if pi == last and prog not in (CELESTA, MUSICBOX) and d >= 1 and abs(((o - pickup) % bar)) < 1e-6:
                song.note(SPARK, base + o, min(d, 1.5), m + shift(CELESTA) + 12, 52 + rng.normal(0, 3))
        cursor = base + tune_len
    # the end: the tonic, rolled on the harp, held under a ritardando
    end = cursor
    name, root, pcs = tonic
    roll = [near(root, 40, 52, 45), near(pcs[2], 47, 59, 52), near(root, 52, 64, 57), near(pcs[1], 55, 67, 64), near(pcs[2], 59, 71, 67), near(root, 64, 76, 69)]
    for i, m in enumerate(roll):
        song.note(ACC, end + i * 0.12, 2 * bar, m, 58 - i * 2)
    pad_chord(end, 2 * bar, tonic, 34)
    if bass is not None:
        song.note(BASS, end, 2 * bar, near(root, 33, 47, 40), 60)
    top_note = notes[-1][2] + shift(passes[-1])
    song.note(MEL_A if (len(passes) - 1) % 2 == 0 else MEL_B, end, 2 * bar - 0.2, near(root, top_note - 6, top_note + 6, top_note), 66)
    # ritardando over the last bar of the tune and the held chord
    rit0 = int((end - bar) * TPB)
    song.tempo_map = [(0, bpm)] + [(rit0 + int(i * bar * TPB / 4), bpm * (1 - 0.06 * (i + 1))) for i in range(4)]
    total_ql = end + 2 * bar
    return song, chords, k, ts, total_ql


# ------------------------------------------------------------------------------- rendering ----
def render(mid, wav):
    subprocess.run(['fluidsynth', '-ni', '-q', '-g', '0.5', '-r', '44100',
                    '-o', 'synth.reverb.room-size=0.72', '-o', 'synth.reverb.damp=0.35', '-o', 'synth.reverb.width=0.9',
                    '-o', 'synth.reverb.level=0.65', '-o', 'synth.chorus.active=0',
                    '-F', wav, SF2, mid], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def finish(wav_in, wav_out):
    with wave.open(wav_in) as w:
        sr, ch = w.getframerate(), w.getnchannels()
        x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32).reshape(-1, ch) / 32768
    level = np.abs(x).max(axis=1)
    on = np.nonzero(level > 10 ** (-55 / 20))[0]
    a, b = on[0], min(len(x), on[-1] + int(0.4 * sr))
    x = x[max(0, a - int(0.05 * sr)):b]
    fade = int(1.2 * sr)
    x[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 2
    rms = np.sqrt(np.mean(x ** 2))
    x *= 10 ** (-23 / 20) / max(rms, 1e-9)
    peak = np.abs(x).max()
    if peak > 0.89:
        x *= 0.89 / peak
    with wave.open(wav_out, 'wb') as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    return len(x) / sr


def main():
    args = sys.argv[1:]
    out = args[0]
    keep_mid, keep_wav = '--mid' in args, '--wav' in args
    want = [a for a in args[1:] if not a.startswith('--')] or list(TRACKS)
    os.makedirs(out, exist_ok=True)
    for i, tid in enumerate(want):
        rng = np.random.default_rng(1000 + list(TRACKS).index(tid))
        song, chords, k, ts, ql = arrange(tid, TRACKS[tid], rng)
        mid = os.path.join(out, f'mus_{tid}.mid')
        raw = os.path.join(out, f'mus_{tid}.raw.wav')
        wav = os.path.join(out, f'mus_{tid}.wav')
        mp3 = os.path.join(out, f'mus_{tid}.mp3')
        song.save(mid)
        render(mid, raw)
        secs = finish(raw, wav)
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-codec:a', 'libmp3lame', '-b:a', '80k', mp3], check=True)
        os.remove(raw)
        if not keep_wav:
            os.remove(wav)
        if not keep_mid:
            os.remove(mid)
        prog = ' '.join(c[0] for c in chords)
        print(f'{tid:18} {TRACKS[tid][7]:30} {k.tonic.name}{"m" if k.mode == "minor" else "" if k.mode == "major" else " " + k.mode} {ts.ratioString:4} '
              f'{secs:5.1f}s {os.path.getsize(mp3) // 1024:5d} KB | {prog}')


if __name__ == '__main__':
    main()

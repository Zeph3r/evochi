"""Village Square, take 3 (ACE-Step, mus_village_v3_take3) reworked: a clearer, brighter mix, and the Evochi call
woven into the gaps where the take's own tune rests.

The take, analysed (librosa): D major, a steady 108.26 BPM, the first downbeat at 0.113 s. It mostly turns
Dmaj7-F#m | Em-A(sus), with two quiet breaks (bars 9-10 and 25-26) that borrow an F-natural chord, so the call
stays out of those. Its tune rests in bars 4, 12, 20 and 27-28 (little energy at 0.7-3 kHz there):
  bars 4, 12, 20   the call's head (A D F# E D) on glockenspiel, an answer to the phrase before
  bars 27-28       the whole two-bar call on flute with the glockenspiel an octave up, the re-entry after the break
The mix: the take carried a sub-bass rumble about 15 dB over the Main Theme's and a dip in the body (0.5-1 kHz) and
presence (2-4 kHz), which read as flat. The rumble is trimmed and the body and presence lifted.

    python3 rework_village.py SRC.mp3 OUT_DIR [glock|marimba|take|none]
"""
import os
import subprocess
import sys

import mido
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from evochi_themes import melody, _synth  # noqa: E402

SF2 = '/usr/share/sounds/sf2/FluidR3_GM.sf2'
BPM, PHASE = 108.26, 0.113   # from the analysis: the grid every bar of the take sits on
SR = 48000
HEAD = 'A4 .5 D5 .5 F#5 1.5 E5 .5 D5 1'
CALL = HEAD + ' | B4 .5 D5 .5 E5 1.5 D5 .5 B4 1'

# the call's voicings. (part, GM program, notes, velocity, octave), each part's level against the music in its own
# bars (dB, RMS) and those bars
ANSWERS = melody(HEAD, 3) + melody(HEAD, 11) + melody(HEAD, 19)
VOICES = {
    # glockenspiel answers, the flute (glockenspiel above) for the whole call
    'glock': ([('glock', 9, ANSWERS, 74, 1), ('flute', 73, melody(CALL, 26), 92, 0), ('glock2', 9, melody(CALL, 26), 56, 1)],
              {'glock': -10.0, 'flute': -8.0, 'glock2': -15.0}, {'glock': (4, 12, 20), 'flute': (27, 28), 'glock2': (27, 28)}),
    # the take's own lead, the marimba (short, fast-fading notes around A4), for every reference; the whole call
    # in octaves for the re-entry
    'marimba': ([('marimba', 12, ANSWERS, 96, 0), ('marimba_call', 12, melody(CALL, 26), 100, 0),
                 ('marimba_oct', 12, melody(CALL, 26), 84, 1)],
                {'marimba': -8.0, 'marimba_call': -6.0, 'marimba_oct': -12.0},
                {'marimba': (4, 12, 20), 'marimba_call': (27, 28), 'marimba_oct': (27, 28)}),
}
VOICES['none'] = ([], {}, {})   # the take on its own: only the clearer mix
PARTS, TARGET, BARS = VOICES['glock']

# the take's own lead, sampled: in the intro (0-3.7 s) it plays alone, so its notes are cut from there (onset to the
# next onset, from the mixed and EQ'd take) and replayed as the call, each note from the nearest cut one (F#5 from
# its G5, E5 from its D5), everything retuned to the take's own tuning
TAKE_NOTES = {'A4': 2.29, 'D5': 2.87, 'B4': 3.23, 'G5': 1.74}
# the whole call, with one note changed: bar 28's D on beat 3.5 sat against the take's G# (a tritone), so it holds E
CALL_FIT = HEAD + ' | B4 .5 D5 .5 E5 2 B4 1'
TAKE_PARTS = {'take_answers': ((4, 12, 20), [(b, HEAD) for b in (3, 11, 19)], -3.0),
              'take_call': ((27, 28), [(26, CALL_FIT)], -3.0),
              # a second voice a third (or a sixth) below, softer: harmony fitted to the chord under every note
              'take_harm': ((4, 12, 20, 27, 28), 'harmony', -8.0)}
# the lead as it sounds in the body of the song (bars 5-7, 13-15, 21-23, 29-31): its harmonics re the fundamental
# (dB) and its share of the mix there (about -1.4 dB, so the call sits at -3 dB: as strong as the take's own tune).
# The intro's notes are played softer (H2 -8 there against +1 here) and carry the bass under them, which read muddy.
LEAD_SHAPE = [0, 1, -14, -10, -34, -27, -35, -27]


def clean(seg, hz):
    """one cut note made the lead alone, at its body-of-the-song tone: only its own harmonics kept (everything
    between, the bass and pads under it, down 24 dB), each harmonic set to LEAD_SHAPE; the first 12 ms (the strike)
    kept whole above the fundamental"""
    import librosa
    n_fft, hop = 2048, 256
    fr = librosa.fft_frequencies(sr=SR, n_fft=n_fft)
    out = []
    for c in (0, 1):
        S = librosa.stft(seg[:, c], n_fft=n_fft, hop_length=hop)
        A = np.abs(S).mean(axis=1)
        mask = np.full(len(fr), 10 ** (-24 / 20))
        own = []
        for k in range(1, 9):
            j = np.abs(fr - hz * k) < max(14.0, hz * k * 0.03)
            own.append(A[j].max() if j.any() else 1e-9)
        own = 20 * np.log10(np.array(own) / own[0])
        for k in range(1, 9):
            j = np.abs(fr - hz * k) < max(14.0, hz * k * 0.03)
            mask[j] = 10 ** (np.clip(LEAD_SHAPE[k - 1] - own[k - 1], -6, 15) / 20)
        y = librosa.istft(S * mask[:, None], hop_length=hop, length=len(seg))
        hp = np.where(fr > hz * 0.7, 1.0, 0.0)
        strike = librosa.istft(S * hp[:, None], hop_length=hop, length=len(seg))
        k = int(0.012 * SR)
        w = np.ones(len(seg)); w[:k] = 0; w[k:k + k] = np.linspace(0, 1, k)
        out.append(y * w + strike * (1 - w))
    return np.stack(out, axis=1).astype(np.float32)

# the take's tone: rumble out, body and presence up, the very top left alone
EQ = ('highpass=f=38:poles=2,equalizer=f=55:t=q:w=1.0:g=-8,equalizer=f=800:t=o:w=1.0:g=2.5,'
      'equalizer=f=3000:t=o:w=1.2:g=3.5,equalizer=f=250:t=o:w=0.8:g=-1')


def overlay(out, only):
    PPQ = 480
    mf = mido.MidiFile(ticks_per_beat=PPQ)
    meta = mido.MidiTrack()
    meta.append(mido.MetaMessage('set_tempo', tempo=int(round(60e6 / BPM))))
    mf.tracks.append(meta)
    lead = PHASE * BPM / 60   # the take's first downbeat, in beats
    for ch, (name, prog, notes, vel, octv) in enumerate(p for p in PARTS if p[0] == only):
        tr = mido.MidiTrack()
        tr.append(mido.Message('program_change', channel=ch, program=prog))
        tr.append(mido.Message('control_change', channel=ch, control=7, value=110))
        tr.append(mido.Message('control_change', channel=ch, control=91, value=70))
        ev = []
        for t, d, p in notes:
            ev.append((int((t + lead) * PPQ), 1, p + 12 * octv))
            ev.append((int((t + lead + d * 0.95) * PPQ), 0, p + 12 * octv))
        ev.sort(key=lambda e: (e[0], e[1]))
        now = 0
        for tick, on, p in ev:
            tr.append(mido.Message('note_on' if on else 'note_off', channel=ch, note=p, velocity=vel if on else 0, time=tick - now))
            now = tick
        mf.tracks.append(tr)
    mid = os.path.join(out, 'village_call_%s.mid' % only)
    mf.save(mid)
    return _synth(mid, os.path.join(out, 'village_call.wav'), SF2, room=(0.5, 0.55, 0.8))


D_MAJOR = {2, 4, 6, 7, 9, 11, 1}


def harmony(x):
    """the harmony line under every call note: from the D major notes a third or a sixth below the melody, one that is
    a chord tone of what the take plays as the note starts (its chroma) and never a semitone from one, moving as
    smoothly as it can from the note before"""
    import librosa
    mono = x.mean(axis=1)
    hop = 512
    C = librosa.feature.chroma_cqt(y=librosa.effects.harmonic(mono[:int(80 * SR)]), sr=SR, hop_length=hop, bins_per_octave=36)
    ft = librosa.frames_to_time(np.arange(C.shape[1]), sr=SR, hop_length=hop)
    beat = 60 / BPM
    notes = []
    for bar0, text in [(3, HEAD), (11, HEAD), (19, HEAD), (26, CALL_FIT)]:
        prev, phrase = None, len(notes)
        for t, d, p in melody(text, bar0):
            a = PHASE + t * beat
            v = C[:, (ft >= a) & (ft < a + min(d, 1.0) * beat)].mean(axis=1)   # the chord as the note starts
            v = v / v.max()
            tones = {i for i in range(12) if v[i] > 0.5}
            best = None
            for down, pref in ((3, 0), (4, 0), (8, 1), (9, 1)):
                h = p - down
                pc = h % 12
                if pc not in D_MAJOR:
                    continue
                if any(min((pc - c) % 12, (c - pc) % 12) == 1 for c in tones if c != pc):
                    continue
                leap = 0 if prev is None else abs(h - prev)
                score = (0 if pc in tones else 1, leap > 4, pref, leap)   # a chord tone; then a smooth line
                if best is None or score < best[0]:
                    best = (score, h)
            if best:
                notes.append((t, d, best[1]))
                prev = best[1]
        # a first note that would leap to the second: the melody starts alone, the harmony joins on its second note
        if len(notes) - phrase > 1 and abs(notes[phrase][2] - notes[phrase + 1][2]) > 5:
            del notes[phrase]
    return notes


def sampled(x, part):
    """[part] played by the take's own lead: its notes cut from the intro, placed on the grid"""
    import librosa
    mono = x.mean(axis=1)
    cuts = {}
    on = librosa.onset.onset_detect(y=mono[:int(4.6 * SR)], sr=SR, hop_length=256, units='time', backtrack=True)
    for name, t in TAKE_NOTES.items():
        a = on[np.argmin(abs(on - t))]
        b = on[on > a + 0.05][0] if np.any(on > a + 0.05) else a + 0.4
        seg = x[int(a * SR):int(b * SR)].copy()
        f = int(0.03 * SR)
        seg[-f:] *= np.linspace(1, 0, f)[:, None]
        f0, vf, _ = librosa.pyin(seg.mean(axis=1), fmin=150, fmax=1500, sr=SR, frame_length=4096, hop_length=256)
        hz = float(np.nanmedian(f0[:12]))
        cuts[name] = (clean(seg, hz), hz)
    tuning = librosa.estimate_tuning(y=mono[:int(80 * SR)], sr=SR)   # the take's offset from A440, in semitone fractions
    y = np.zeros_like(x)
    beat = 60 / BPM
    plan = TAKE_PARTS[part][1]
    plays = harmony(x) if plan == 'harmony' else [n for bar0, text in plan for n in melody(text, bar0)]
    have = {librosa.note_to_midi(k): k for k in TAKE_NOTES}
    for t, d, p in plays:
        seg, hz = cuts[have[min(have, key=lambda m: (abs(m - p), m > p))]]   # the nearest cut note
        want = librosa.midi_to_hz(p + tuning)
        r = want / hz
        if abs(12 * np.log2(r)) > 0.15:   # retune (by resampling, as a played note would sound)
            seg = np.stack([librosa.resample(seg[:, c], orig_sr=SR, target_sr=int(SR / r)) for c in (0, 1)], axis=1)
        i = int((PHASE + t * beat) * SR)
        y[i:i + len(seg)] += seg[:max(0, len(y) - i)]
    return y


def main(src, out, voice='glock'):
    global PARTS, TARGET, BARS
    if voice == 'take':
        PARTS, TARGET, BARS = [], {k: v[2] for k, v in TAKE_PARTS.items()}, {k: v[0] for k, v in TAKE_PARTS.items()}
    else:
        PARTS, TARGET, BARS = VOICES[voice]
    os.makedirs(out, exist_ok=True)
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', src, '-af', EQ, '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.float32).reshape(-1, 2).copy()
    bar = 4 * 60 / BPM
    music = x.copy()
    for name in TARGET:
        y = (sampled(music, name) if voice == 'take' else overlay(out, name))[:len(x)]
        idx = np.concatenate([np.arange(int((PHASE + (b - 1) * bar) * SR), int((PHASE + b * bar) * SR)) for b in BARS[name]])
        idx = idx[idx < len(y)]
        g = 10 ** (TARGET[name] / 20) * np.sqrt((music[idx] ** 2).mean()) / np.sqrt((y[idx] ** 2).mean())
        x[:len(y)] += y * g
        print('%-7s gain %+.1f dB' % (name, 20 * np.log10(g)))
    tmp = os.path.join(out, 'village.f32')
    x.tofile(tmp)
    src_in = ['-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', tmp]
    bus = 'acompressor=threshold=-20dB:ratio=2:attack=20:release=200:makeup=1.5'
    import json
    meas = subprocess.run(['ffmpeg', '-hide_banner', *src_in, '-af', bus + ',loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json',
                           '-f', 'null', '-'], capture_output=True, text=True).stderr
    m = json.loads(meas[meas.rindex('{'):meas.rindex('}') + 1])
    ln = ('loudnorm=I=-16:TP=-1.5:LRA=11:measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:offset=%s:linear=true'
          % (m['input_i'], m['input_tp'], m['input_lra'], m['input_thresh'], m['target_offset']))
    mp3 = os.path.join(out, 'mus_village_v3_take3_mix.mp3' if voice == 'none' else 'mus_village_v3_take3_call%s.mp3' % ('' if voice == 'glock' else '_' + voice))
    subprocess.run(['ffmpeg', '-v', 'error', '-y', *src_in, '-af', bus + ',' + ln, '-c:a', 'libmp3lame', '-q:a', '2', mp3], check=True)
    os.remove(tmp)
    return mp3


if __name__ == '__main__':
    print(main(sys.argv[1], sys.argv[2], *sys.argv[3:4]))

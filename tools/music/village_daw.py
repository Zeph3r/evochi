"""The Village Square loop (village_loop.py) as a package to open and tweak in a DAW (FL Studio, Ableton, Logic,
Reaper...): 24-bit WAVs at the song's tempo, every file starting on bar 1, plus a MIDI file with the tempo, the
section markers and the chords.

    python3 village_daw.py SRC_TAKE.mp3 OUT_DIR [--flac]

  mus_village_loop.wav           the finished loop, mastered (what the game plays), 29 bars
  sections/01_bloom.wav ...      the loop cut at its sections, on bar lines: lay them end to end to rebuild it,
                                 or rearrange, repeat and drop sections
  stems/band.wav                 the take as arranged, with the bloom's and breakdown's filter sweeps
  stems/band_unfiltered.wav      the same without the sweeps (to draw your own filter automation)
  stems/shimmer.wav              the shimmer washes (the bloom, the glow under bar 2, the end leaning into the loop)
  stems/swells.wav               the two reverse swells (into bar 2 and into the tune's return after the breakdown)
                                 band + shimmer + swells = the mix before mastering (stems at the master's gain)
  source_take.flac               the untouched ACE-Step take (its first downbeat at 0.113 s, 108.26 BPM)
  mus_village_tempo_chords.mid   tempo 108.26, 4/4, section markers, the chords (half-bar, voiced) on one track
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import village_loop as VL   # noqa: E402

SR = VL.SR
BPM = VL.BPM
SECTIONS = [('01_bloom', 'Bloom', 1, 1), ('02_tune_a', 'Tune A', 2, 7), ('03_tune_b', 'Tune B', 8, 19),
            ('04_breakdown', 'Breakdown', 20, 23), ('05_tune_c', 'Tune C', 24, 29)]   # loop bars, 1-based, inclusive
BUS = 'acompressor=threshold=-20dB:ratio=2:attack=20:release=200:makeup=1.5'


def with_fx(src, **fx):
    old = dict(VL.FX)
    VL.FX.update(fx)
    try:
        return VL.build(src)
    finally:
        VL.FX.update(old)


def master_wav(x, path):
    tmp = path + '.f32'
    x.astype(np.float32).tofile(tmp)
    src = ['-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', tmp]
    meas = subprocess.run(['ffmpeg', '-hide_banner', *src, '-af', BUS + ',loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json',
                           '-f', 'null', '-'], capture_output=True, text=True).stderr
    m = json.loads(meas[meas.rindex('{'):meas.rindex('}') + 1])
    ln = ('loudnorm=I=-16:TP=-1.5:LRA=11:measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:offset=%s:linear=true'
          % (m['input_i'], m['input_tp'], m['input_lra'], m['input_thresh'], m['target_offset']))
    subprocess.run(['ffmpeg', '-v', 'error', '-y', *src, '-af', BUS + ',' + ln, '-ar', str(SR), '-c:a', 'pcm_s24le', path], check=True)
    os.remove(tmp)
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 'f32le', '-ac', '2', '-'], capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).astype(np.float64)


def write(path, x, flac=False):
    import soundfile as sf
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if flac:
        path = path[:-4] + '.flac'
    sf.write(path, np.clip(x, -1, 1).astype(np.float32), SR, subtype='PCM_24')
    return path


def chords(x):
    """the chord in each half bar of the loop (chroma against triad / seventh / sus templates)"""
    import librosa
    y = librosa.effects.harmonic(x.mean(axis=1).astype(np.float32))
    C = librosa.feature.chroma_cqt(y=y, sr=SR, hop_length=1024, bins_per_octave=36)
    ft = librosa.frames_to_time(np.arange(C.shape[1]), sr=SR, hop_length=1024)
    names = 'C C# D D# E F F# G G# A A# B'.split()
    T = {}
    for r in range(12):
        for q, iv in (('', (0, 4, 7)), ('m', (0, 3, 7)), ('maj7', (0, 4, 7, 11)), ('m7', (0, 3, 7, 10)), ('7', (0, 4, 7, 10)),
                      ('sus4', (0, 5, 7)), ('7sus4', (0, 5, 7, 10))):
            v = np.zeros(12)
            v[[(r + i) % 12 for i in iv]] = 1
            v[r] += 0.5
            T[names[r] + q] = (r, iv, v / np.linalg.norm(v))
    half = VL.BAR / 2
    out = []
    for k in range(int(round(len(x) / SR / half))):
        m = (ft >= k * half) & (ft < (k + 1) * half)
        v = C[:, m].mean(axis=1)
        v /= np.linalg.norm(v) + 1e-9
        name, (r, iv, _) = max(T.items(), key=lambda kv: float(v @ kv[1][2]))
        out.append((name, r, iv))
    return out


def midi(path, chs):
    import mido
    PPQ = 480
    mf = mido.MidiFile(ticks_per_beat=PPQ)
    meta = mido.MidiTrack()
    meta.append(mido.MetaMessage('track_name', name='Village Square: tempo and sections'))
    meta.append(mido.MetaMessage('set_tempo', tempo=int(round(60e6 / BPM))))
    meta.append(mido.MetaMessage('time_signature', numerator=4, denominator=4))
    meta.append(mido.MetaMessage('key_signature', key='D'))
    now = 0
    for _, title, a, b in SECTIONS:
        t = (a - 1) * 4 * PPQ
        meta.append(mido.MetaMessage('marker', text=title, time=t - now))
        now = t
    meta.append(mido.MetaMessage('end_of_track', time=29 * 4 * PPQ - now))
    mf.tracks.append(meta)
    tr = mido.MidiTrack()
    tr.append(mido.MetaMessage('track_name', name='Chords (as heard)'))
    tr.append(mido.Message('program_change', channel=0, program=0))
    ev = []
    for k, (name, r, iv) in enumerate(chs):
        t0, t1 = k * 2 * PPQ, (k + 1) * 2 * PPQ - 10
        ev.append((t0, 1, 36 + r + (12 if r < 4 else 0), 70))              # the root, low
        for i in iv:
            ev.append((t0, 1, 60 + (r + i) % 12 - (12 if (r + i) % 12 > 7 else 0), 62))
        for _, _, n, _ in [e for e in ev if e[0] == t0]:
            ev.append((t1, 0, n, 0))
    ev.sort(key=lambda e: (e[0], e[1]))
    now = 0
    for t, on, n, v in ev:
        tr.append(mido.Message('note_on' if on else 'note_off', channel=0, note=n, velocity=v, time=t - now))
        now = t
    mf.tracks.append(tr)
    lyr = mido.MidiTrack()
    lyr.append(mido.MetaMessage('track_name', name='Chord names'))
    now = 0
    for k, (name, _, _) in enumerate(chs):
        t = k * 2 * PPQ
        lyr.append(mido.MetaMessage('text', text=name, time=t - now))
        now = t
    mf.tracks.append(lyr)
    mf.save(path)


README = """Village Square: the DAW package
================================

Key D major, tempo 108.26 BPM, 4/4, 29 bars (64.29 s), loops seamlessly (the end runs straight into bar 1).
Every audio file starts exactly on bar 1 at 108.26 BPM, so they all line up.

Sections (bars):  Bloom 1 | Tune A 2-7 | Tune B 8-19 | Breakdown 20-23 | Tune C 24-29

FL Studio
---------
1. New project. Set the tempo to 108.260 (right-click the tempo, or type it in) and 4/4.
2. Drag mus_village_tempo_chords.mid onto the Playlist first: it brings the tempo, the section markers and a chord
   track (the chords as heard, two per bar) to play your own instruments over.
3. Drag the WAVs onto the Playlist at bar 1 (hold Shift while dragging to drop several, one per track). With the
   tempo set, they sit on the grid.
   - Just want to rearrange? Use sections/: lay 01 to 05 end to end, then repeat, shorten or reorder them.
   - Want to rebalance the effects? Use stems/: band + shimmer + swells is the mix before mastering. Turn the
     shimmer or swells up or down, or mute them. band_unfiltered.wav has no filter sweeps, so you can draw your own
     (a low-pass on the bloom, bar 1, and on the breakdown, bars 20-23).
   - Want the instruments apart? FL Studio 21.2 or newer can split any of these WAVs into drums, bass and the rest:
     right-click the clip in the Playlist and choose the stem separator.
4. Export as WAV, then the game wants Ogg Vorbis at -16 LUFS for a gapless loop: send it back and it goes in
   (or export OGG from FL directly). Keep the length a whole number of bars so it still loops.

The game's loop is mus_village_loop.wav (= mus_village.ogg one folder up). source_take.flac is the untouched
ACE-Step take it was cut from (first downbeat at 0.113 s), as FLAC (lossless; FL Studio opens it). Rebuild everything with
tools/music/village_daw.py; the loop itself is built by tools/music/village_loop.py.
"""


def main(src, out, flac=False):
    os.makedirs(out, exist_ok=True)
    full = with_fx(src)
    no_sh = with_fx(src, shimmer=False)
    no_sw = with_fx(src, swells=False)
    band = with_fx(src, shimmer=False, swells=False)
    raw = with_fx(src, shimmer=False, swells=False, filters=False)
    shim, swell = full - no_sh, full - no_sw
    err = np.abs(band + shim + swell - full).max()
    print('stems add up to the mix within %.2e' % err, flush=True)
    m = master_wav(full, os.path.join(out, 'mus_village_loop.wav'))
    g = float((m * full).sum() / (full * full).sum())            # the master's gain (its compression is gentle)
    peak = max(np.abs(s * g).max() for s in (band, raw, shim, swell))
    if peak > 0.99:
        g *= 0.99 / peak
    print('master gain %.3f (%.1f dB)' % (g, 20 * np.log10(g)), flush=True)
    files = ['mus_village_loop.wav']
    if flac:
        p = write(os.path.join(out, 'mus_village_loop.wav'), m, True)
        os.remove(os.path.join(out, 'mus_village_loop.wav'))
        files = [os.path.basename(p)]
    for name, s in (('band', band), ('band_unfiltered', raw), ('shimmer', shim), ('swells', swell)):
        files.append(os.path.relpath(write(os.path.join(out, 'stems', name + '.wav'), s * g, flac), out))
    nb = len(m) / 29
    for key, title, a, b in SECTIONS:
        seg = m[int(round((a - 1) * nb)):int(round(b * nb))]
        files.append(os.path.relpath(write(os.path.join(out, 'sections', key + '.wav'), seg, flac), out))
    rawsrc = subprocess.run(['ffmpeg', '-v', 'error', '-i', src, '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                            capture_output=True, check=True).stdout
    files.append(os.path.relpath(write(os.path.join(out, 'source_take.wav'),          # FLAC: lossless, half the size
                                       np.frombuffer(rawsrc, np.float32).reshape(-1, 2).astype(np.float64), True), out))
    chs = chords(raw * g)
    midi(os.path.join(out, 'mus_village_tempo_chords.mid'), chs)
    files.append('mus_village_tempo_chords.mid')
    open(os.path.join(out, 'README.txt'), 'w').write(README if not flac else README.replace('.wav', '.flac'))
    print('chords:', ' '.join(c[0] for c in chs[:16]), '...', flush=True)
    for f in files:
        print('  ', f, '%.1f MB' % (os.path.getsize(os.path.join(out, f)) / 1e6))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], '--flac' in sys.argv)

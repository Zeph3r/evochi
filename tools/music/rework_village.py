"""Village Square, take 3 (ACE-Step, mus_village_v3_take3) reworked: a clearer, brighter mix, and the Evochi call
woven into the gaps where the take's own tune rests.

The take, analysed (librosa): D major, a steady 108.26 BPM, the first downbeat at 0.113 s. It mostly turns
Dmaj7-F#m | Em-A(sus), with two quiet breaks (bars 9-10 and 25-26) that borrow an F-natural chord, so the call
stays out of those. Its tune rests in bars 4, 12, 20 and 27-28 (little energy at 0.7-3 kHz there):
  bars 4, 12, 20   the call's head (A D F# E D) on glockenspiel, an answer to the phrase before
  bars 27-28       the whole two-bar call on flute with the glockenspiel an octave up, the re-entry after the break
The mix: the take carried a sub-bass rumble about 15 dB over the Main Theme's and a dip in the body (0.5-1 kHz) and
presence (2-4 kHz), which read as flat. The rumble is trimmed and the body and presence lifted.

    python3 rework_village.py SRC.mp3 OUT_DIR [glock|marimba]
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
PARTS, TARGET, BARS = VOICES['glock']

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


def main(src, out, voice='glock'):
    global PARTS, TARGET, BARS
    PARTS, TARGET, BARS = VOICES[voice]
    os.makedirs(out, exist_ok=True)
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', src, '-af', EQ, '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.float32).reshape(-1, 2).copy()
    bar = 4 * 60 / BPM
    music = x.copy()
    for name in TARGET:
        y = overlay(out, name)[:len(x)]
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
    mp3 = os.path.join(out, 'mus_village_v3_take3_call%s.mp3' % ('' if voice == 'glock' else '_' + voice))
    subprocess.run(['ffmpeg', '-v', 'error', '-y', *src_in, '-af', bus + ',' + ln, '-c:a', 'libmp3lame', '-q:a', '2', mp3], check=True)
    os.remove(tmp)
    return mp3


if __name__ == '__main__':
    print(main(sys.argv[1], sys.argv[2], *sys.argv[3:4]))

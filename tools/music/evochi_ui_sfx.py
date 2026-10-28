"""The game's button sounds, played on the soundtrack's own instruments so a tap sounds like part of the band:
the marimba (the toy box's backbone) for taps and screen changes, the glockenspiel for a reward. Everything in
D major, the key of the whole score, so no sound ever clashes with the music under it.

    ui_tap        a single soft marimba D5
    ui_open       A4 then D5: the first two notes of the Evochi call, a screen opening
    ui_back       D5 then A4: the call's head turned round, a screen closing
    reward_chime  glockenspiel F#6 and A6 over a marimba D5 (the Dadd9 touch from the Main Theme)
    error_bonk    a low, muted wooden knock (D3 and A3, damped at once): "not yet", never a wrong note

Rendered with the same soundfont and a small room like the soundtrack's piano, mono 44.1 kHz MP3s at the level
of the sounds they replace.

    python3 evochi_ui_sfx.py [OUT_DIR]     # default: flutter/assets/audio/sfx, and listed in the art manifest
"""
import json
import os
import subprocess
import sys
import tempfile

import mido
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SFX = os.path.join(HERE, '..', '..', 'flutter', 'assets', 'audio', 'sfx')
SF2 = '/usr/share/sounds/sf2/FluidR3_GM.sf2'
SR = 44100
MARIMBA, GLOCK = 12, 9


def n(name):
    names = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
    p = names[name[0]] + (1 if '#' in name else 0)
    return 12 * (int(name[-1]) + 1) + p


# name: ([(seconds, program, note, velocity, held)], length s, peak dBFS, lowpass Hz or None)
SOUNDS = {
    'ui_tap': ([(0.0, MARIMBA, n('D5'), 84, 0.10)], 0.32, -12.0, None),
    'ui_open': ([(0.0, MARIMBA, n('A4'), 70, 0.08), (0.065, MARIMBA, n('D5'), 90, 0.14)], 0.45, -10.5, None),
    'ui_back': ([(0.0, MARIMBA, n('D5'), 80, 0.08), (0.065, MARIMBA, n('A4'), 70, 0.14)], 0.42, -11.5, None),
    'reward_chime': ([(0.0, MARIMBA, n('D5'), 62, 0.3), (0.0, GLOCK, n('F#6'), 78, 0.5), (0.075, GLOCK, n('A6'), 84, 0.7)],
                     0.95, -6.0, None),
    'error_bonk': ([(0.0, MARIMBA, n('D3'), 96, 0.05), (0.0, MARIMBA, n('A3'), 74, 0.05)], 0.22, -9.0, 1400),
}


def render(events, length, peak_db, lowpass):
    with tempfile.TemporaryDirectory() as d:
        mf = mido.MidiFile(ticks_per_beat=480)
        tr = mido.MidiTrack()
        mf.tracks.append(tr)
        tr.append(mido.MetaMessage('set_tempo', tempo=500000))   # 120 BPM: a beat is 0.5 s, 960 ticks a second
        progs = sorted({p for _, p, _, _, _ in events})
        ch = {p: i for i, p in enumerate(progs)}
        for p in progs:
            tr.append(mido.Message('program_change', channel=ch[p], program=p))
            tr.append(mido.Message('control_change', channel=ch[p], control=91, value=40))
            tr.append(mido.Message('control_change', channel=ch[p], control=93, value=0))
        ev = []
        for t, p, note, vel, held in events:
            ev.append((t, 1, ch[p], note, vel))
            ev.append((t + held, 0, ch[p], note, 0))
        ev.sort(key=lambda e: (e[0], e[1]))
        now = 0
        for t, on, c, note, vel in ev:
            tick = int(round(t * 960))
            tr.append(mido.Message('note_on' if on else 'note_off', channel=c, note=note, velocity=vel, time=tick - now))
            now = tick
        tr.append(mido.MetaMessage('end_of_track', time=int(2 * 960)))
        mid, wav = os.path.join(d, 's.mid'), os.path.join(d, 's.wav')
        mf.save(mid)
        subprocess.run(['fluidsynth', '-ni', '-q', '-g', '0.6', '-r', str(SR), '-o', 'synth.reverb.room-size=0.22',
                        '-o', 'synth.reverb.level=0.4', '-o', 'synth.reverb.width=0.6', '-o', 'synth.chorus.active=0',
                        '-F', wav, SF2, mid], check=True, capture_output=True)
        raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', wav, '-f', 'f32le', '-ac', '1', '-ar', str(SR), '-'],
                             capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.float32).astype(np.float64)
    # start on the first transient, keep [length], ease out over the last third
    i0 = int(np.argmax(np.abs(x) > 1e-4))
    x = x[max(0, i0 - 16):][:int(length * SR)]
    k = len(x) // 3
    x[-k:] *= np.linspace(1, 0, k) ** 2
    x[:16] *= np.linspace(0, 1, 16)
    if lowpass:   # a damped, woody knock: the ring taken off the top
        a = np.exp(-2 * np.pi * lowpass / SR)
        y = np.zeros_like(x)
        for _ in range(2):
            acc = 0.0
            for j, v in enumerate(x):
                acc = (1 - a) * v + a * acc
                y[j] = acc
            x = y.copy()
    return x / np.max(np.abs(x)) * 10 ** (peak_db / 20)


def main(out):
    os.makedirs(out, exist_ok=True)
    for name, (events, length, peak, lp) in SOUNDS.items():
        x = render(events, length, peak, lp)
        path = os.path.join(out, name + '.mp3')
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f64le', '-ar', str(SR), '-ac', '1', '-i', '-',
                        '-c:a', 'libmp3lame', '-b:a', '96k', path], input=x.tobytes(), check=True)
        print('%-13s %.2fs -> %s' % (name, len(x) / SR, path))
    if os.path.abspath(out) == os.path.abspath(SFX):   # list them where AudioService.play looks
        mp = os.path.join(SFX, '..', '..', 'art', 'manifest.json')
        with open(mp) as f:
            man = json.load(f)
        for k in SOUNDS:
            man['audio'][k] = 'sfx/%s.mp3' % k
        with open(mp, 'w') as f:
            json.dump(man, f, indent=1)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else SFX)

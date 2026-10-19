"""Soundtrack for the week-43 Shorts (seven 14 s cuts in comp_wk.html): the meadow ambience under
everything, the marimba bed (ad_music.py) and the game's own sounds. The encounter cuts read the sound
cues of the recorded footage from each clip's log.json, so they always match the frames; the composed
shots get hand-placed sounds. Then the MP4.

python3 mix_wk.py CUT FRAMES_DIR AUDIO_DIR MUSIC.wav CLIPS_DIR OUT.mp4

Music cues for ad_music.py (total, riser, reveal, groove back, end) are in MUSIC below;
`python3 mix_wk.py --music CUT` prints them.
"""
import json
import os
import subprocess
import sys

MUSIC = {
    'now14': '14 7.6 8.6 9.3 12.4',
    'day30_14': '14 9.3 10.22 10.9 12.6',
    'watch14': '14 9.3 10.4 11.0 12.4',
    'hurt14': '14 9.0 10.1 11.0 12.4',
    'gate14': '14 9.8 10.9 11.8 12.6',
    'week2_14': '14 10.9 11.95 12.4 12.6',
    'waits': '14 5.6 6.7 7.4 11.6',
}
if sys.argv[1] == '--music':
    print(MUSIC[sys.argv[2]])
    raise SystemExit

cut, frames, audio, music, clips, out = sys.argv[1:7]
FPS = 30
CRF = os.environ.get('CRF', '18')
TOTAL = 14.0
GAIN = {'enc_glow': -4, 'reward_chime': -8, 'play_boing': -6, 'pet_chirp': -7, 'enc_soothe': -5, 'enc_whoosh': -9, 'enc_surge': -4,
        'evolve_fanfare': -2, 'ui_tap': -16, 'enc_rumble': -2, 'enc_awaken': -1}


def log(q):
    return json.load(open(os.path.join(clips, q, 'log.json')))['events']


def marks(q, what):
    return [e['t'] for e in log(q) if e['what'] == what]


def segment(q, start, length, at, skip=()):
    """The game's sound cues inside a window of the clip, moved onto the video's timeline."""
    res = []
    for e in log(q):
        if e['what'].startswith('sfx:') and start <= e['t'] < start + length:
            name = e['what'][4:]
            if name not in skip:
                res.append((name, e['t'] - start + at, GAIN.get(name, -8)))
    return res


duck = None
if cut == 'now14':
    cues = [('pet_chirp', 1.65, -3), ('pet_chirp', 3.0, -5)] + [('coin', a, -9) for a in (4.55, 5.2, 5.8)] + \
           [('evolve_fanfare', 6.6, -1), ('evolve_fanfare', 8.6, 0), ('reward_chime', 10.95, -3), ('pet_chirp', 11.05, -4), ('pet_chirp', 12.55, -5)]
elif cut == 'day30_14':
    ticks = [('ui_tap', 2.825 + (d - 1) * 0.255, -17) for d in range(1, 30) if d != 7]
    cues = [('pet_chirp', 0.6, -4)] + ticks + [('evolve_fanfare', 4.355, -1), ('evolve_fanfare', 10.22, 0), ('reward_chime', 11.62, -3),
                                               ('pet_chirp', 11.71, -4), ('pet_chirp', 13.1, -6)]
elif cut == 'watch14':
    g = marks('eq01', 'act:lumen_glow'); item = marks('eq01', 'act:item:sunberry_tart')[0]
    begin = marks('eq01', 'begin')[0]; res = marks('eq01', 'result')[0]
    cues = [('pet_chirp', 0.6, -4), ('pet_chirp', 1.75, -6), ('reward_chime', 3.4, -9)]
    cues += segment('eq01', 0.85, 0.9, 4.0) + segment('eq01', begin - 1.0, 0.9, 4.9)
    cues += segment('eq01', g[0] - 0.1, 2.0, 5.8) + segment('eq01', item + 0.05, 2.0, 7.8)
    cues += segment('eq01', g[-1] + 0.6, 1.6, 9.8) + segment('eq01', res + 0.5, 1.0, 11.4)
    cues += [('pet_chirp', 12.6, -4), ('ui_tap', 12.7, -12), ('ui_tap', 12.84, -12), ('ui_tap', 12.98, -12)]
elif cut == 'hurt14':
    g = marks('eq02', 'act:lumen_glow'); so = marks('eq02', 'act:soothe')[0]
    hush = marks('eq02', 'act:petal_hush')[0]; res = marks('eq02', 'result')[0]
    cues = [('reward_chime', 0.15, -8), ('pet_chirp', 0.5, -4)]
    cues += segment('eq02', g[0] + 1.35, 2.0, 2.2) + segment('eq02', so - 0.05, 2.2, 4.2)
    cues += segment('eq02', g[1] + 0.15, 2.2, 6.4) + segment('eq02', hush + 0.05, 1.2, 8.6)
    cues += segment('eq02', g[-1] + 0.75, 1.2, 9.8) + segment('eq02', res + 0.45, 1.4, 11.0)
    cues += [('pet_chirp', 13.2, -4)]
elif cut == 'gate14':
    g = marks('eq03', 'act:lumen_glow'); begin = marks('eq03', 'begin')[0]; res = marks('eq03', 'result')[0]
    cues = [('pet_chirp', 0.2, -6), ('reward_chime', 3.77, -9), ('enc_rumble', 4.7, 0), ('enc_awaken', 5.2, -1), ('enc_rumble', 6.5, -3)]
    cues += segment('eq03', 3.9, 0.9, 7.4) + segment('eq03', begin - 0.8, 0.7, 8.3)
    cues += segment('eq03', g[1] + 0.55, 1.4, 9.0) + segment('eq03', g[-1] + 0.8, 1.4, 10.4)
    cues += segment('eq03', res + 0.45, 0.8, 11.8)
    cues += [('pet_chirp', 12.9, -6)]
    duck = (2.0, 7.4)   # the marimba steps aside for the awakening
elif cut == 'week2_14':
    nudge = marks('eq01', 'act:gentle_nudge')[0]; item = marks('eq01', 'act:item:sunberry_tart')[0]
    begin = marks('eq01', 'begin')[0]; res = marks('eq01', 'result')[0]
    cues = [('pet_chirp', 0.6, -4), ('coin', 2.8, -9), ('level_up', 3.5, -6), ('reward_chime', 4.3, -6), ('coin', 5.0, -9), ('coin', 5.5, -9), ('reward_chime', 5.9, -9)]
    cues += segment('eq01', 0.85, 0.9, 7.6) + segment('eq01', begin - 0.8, 0.7, 8.5)
    cues += segment('eq01', nudge + 0.1, 1.2, 9.2) + segment('eq01', item + 0.05, 1.4, 10.4) + segment('eq01', res + 0.4, 0.8, 11.8)
    cues += [('pet_chirp', 12.85, -4), ('ui_tap', 12.95, -12), ('ui_tap', 13.09, -12)]
elif cut == 'waits':
    cues = [('pet_chirp', 0.25, -6), ('ui_tap', 2.5, -14), ('reward_chime', 6.7, -5), ('level_up', 7.02, -6), ('pet_chirp', 7.15, -5),
            ('pet_chirp', 7.75, -7), ('pet_chirp', 9.05, -8)]
else:
    raise SystemExit('unknown cut ' + cut)

inputs = ['-stream_loop', '-1', '-i', os.path.join(audio, 'ambient_meadow_loop.mp3'), '-i', music]
mvol = 'volume=-7dB'
if duck:
    mvol += f",volume=enable='between(t,{duck[0]},{duck[1]})':volume=0.12"
filters = [f'[1:a]atrim=0:{TOTAL},asetpts=PTS-STARTPTS,volume=-21dB,afade=t=in:st=0:d=0.3,afade=t=out:st={TOTAL - 0.6}:d=0.6[bed]',
           f'[2:a]atrim=0:{TOTAL},asetpts=PTS-STARTPTS,{mvol}[music]']
mix = ['[bed]', '[music]']
k = 3
for name, t, gain in cues:
    f = os.path.join(audio, f'{name}.mp3')
    if not os.path.exists(f):
        print('missing sound', name)
        continue
    inputs += ['-i', f]
    ms = max(0, int(round(t * 1000)))
    filters.append(f'[{k}:a]volume={gain}dB,adelay={ms}|{ms}[s{k}]')
    mix.append(f'[s{k}]')
    k += 1
filters.append(''.join(mix) + f'amix=inputs={len(mix)}:normalize=0:duration=longest,atrim=0:{TOTAL},volume=5dB,alimiter=limit=0.95[mix]')
cmd = ['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-framerate', str(FPS), '-i', os.path.join(frames, 'f%05d.png')] + inputs + [
    '-filter_complex', ';'.join(filters), '-map', '0:v', '-map', '[mix]',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', CRF, '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-level', '4.1',
    '-movflags', '+faststart', '-r', str(FPS), '-t', str(TOTAL), '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', out]
subprocess.run(cmd, check=True)
print('wrote', out, 'cues', len(cues))

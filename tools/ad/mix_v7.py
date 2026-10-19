"""Soundtrack for the encounter Shorts (v7): the meadow ambience under everything, the marimba bed
(ad_music.py) and the game's own sounds at the beats of the recorded footage, read from each clip's
log.json so the cues always match the frames. Then the MP4.

python3 mix_v7.py CUT FRAMES_DIR AUDIO_DIR MUSIC.wav CLIPS_DIR OUT.mp4

Music cue times for ad_music.py (total, riser, reveal, groove back, end):
  watch 17 11.4 12.55 13.2 14.4 · hurt 17.5 11.0 12.35 13.0 14.8 · gate 18 13.0 14.3 15.0 15.6 · week2 17.5 12.6 13.75 14.3 14.8
"""
import json
import os
import subprocess
import sys

cut, frames, audio, music, clips, out = sys.argv[1:7]
FPS = 30
CRF = os.environ.get('CRF', '18')


def log(q):
    return json.load(open(os.path.join(clips, q, 'log.json')))['events']


def marks(q, what):
    return [e['t'] for e in log(q) if e['what'] == what]


def sfx_between(q, t0, t1, shift, skip=()):
    """The game's sound cues inside a window of the clip, moved onto the video's timeline."""
    out = []
    for e in log(q):
        if e['what'].startswith('sfx:') and t0 <= e['t'] < t1:
            name = e['what'][4:]
            if name in skip:
                continue
            gain = {'enc_glow': -4, 'reward_chime': -8, 'play_boing': -6, 'pet_chirp': -7, 'enc_soothe': -5, 'enc_whoosh': -9, 'enc_surge': -4,
                    'evolve_fanfare': -2, 'ui_tap': -16, 'enc_rumble': -2, 'enc_awaken': -1}.get(name, -8)
            out.append((name, e['t'] - t0 + shift, gain))
    return out


def segment(q, start, length, at, skip=()):
    return sfx_between(q, start, start + length, at, skip)


# --- the cues per cut: the composed shots get hand-placed sounds, the footage brings its own
if cut == 'watch':
    TOTAL = 17.0
    g0 = marks('eq01', 'act:lumen_glow')[0]
    item = marks('eq01', 'act:item:sunberry_tart')[0]
    glast = marks('eq01', 'act:lumen_glow')[-1]
    res = marks('eq01', 'result')[0]
    cues = [('pet_chirp', 1.0, -4), ('pet_chirp', 4.4, -6), ('reward_chime', 4.45, -9)]
    cues += segment('eq01', 0.25, 2.2, 5.0)
    cues += segment('eq01', g0 - 0.1, 2.4, 7.2)
    cues += segment('eq01', item + 0.05, 2.4, 9.6)
    cues += segment('eq01', glast + 0.6, 1.5, 12.0)
    cues += [('pet_chirp', 15.0, -4), ('ui_tap', 15.0, -12), ('ui_tap', 15.14, -12), ('ui_tap', 15.28, -12)]
    duck = None
elif cut == 'hurt':
    TOTAL = 17.5
    g = marks('eq02', 'act:lumen_glow')
    so = marks('eq02', 'act:soothe')[0]
    hush = marks('eq02', 'act:petal_hush')[0]
    res = marks('eq02', 'result')[0]
    cues = [('pet_chirp', 0.6, -4), ('reward_chime', 0.15, -8)]
    cues += segment('eq02', g[0] + 1.35, 2.4, 2.4)
    cues += segment('eq02', so - 0.05, 2.8, 4.8)
    cues += segment('eq02', g[1] + 0.15, 2.8, 7.6)
    cues += segment('eq02', hush + 0.05, 1.4, 10.4)
    cues += segment('eq02', g[-1] + 0.75, 1.4, 11.8)
    cues += [('pet_chirp', 15.2, -4)]
    duck = None
elif cut == 'gate':
    TOTAL = 18.0
    item = marks('eq03', 'act:item:lantern_tonic')[0]
    g = marks('eq03', 'act:lumen_glow')
    res = marks('eq03', 'result')[0]
    # the awakening on the plate: the game's rumble and sting, hand-placed
    cues = [('pet_chirp', 0.8, -6), ('enc_rumble', 5.4, 0), ('enc_rumble', 7.2, -3), ('enc_awaken', 6.0, -1)]
    cues += segment('eq03', 3.72, 2.0, 8.6)
    cues += segment('eq03', item - 0.05, 1.3, 10.6)
    cues += segment('eq03', g[1] + 0.55, 1.5, 11.9)
    cues += segment('eq03', g[-1] + 0.8, 1.2, 13.4)
    cues += [('pet_chirp', 16.2, -6)]
    duck = (2.2, 10.6)   # the marimba steps aside for the awakening
elif cut == 'week2':
    TOTAL = 17.5
    nudge = marks('eq01', 'act:gentle_nudge')[0]
    item = marks('eq01', 'act:item:sunberry_tart')[0]
    res = marks('eq01', 'result')[0]
    cues = [('pet_chirp', 1.0, -4), ('coin', 3.3, -9), ('level_up', 4.1, -6), ('reward_chime', 5.15, -6), ('coin', 6.2, -9), ('coin', 6.7, -9), ('reward_chime', 7.1, -9)]
    cues += segment('eq01', 0.3, 1.2, 9.8)
    cues += segment('eq01', nudge + 0.1, 1.2, 11.0)
    cues += segment('eq01', item + 0.05, 1.3, 12.2)
    cues += [('pet_chirp', 15.1, -4), ('ui_tap', 15.3, -12), ('ui_tap', 15.44, -12)]
    duck = None
else:
    raise SystemExit('unknown cut ' + cut)

inputs = ['-stream_loop', '-1', '-i', os.path.join(audio, 'ambient_meadow_loop.mp3'), '-i', music]
mvol = f'volume=-7dB'
if duck:
    mvol += f",volume=enable='between(t,{duck[0]},{duck[1]})':volume=0.12"
filters = [f'[1:a]atrim=0:{TOTAL},asetpts=PTS-STARTPTS,volume=-21dB,afade=t=in:st=0:d=0.3,afade=t=out:st={TOTAL - 0.6}:d=0.6[bed]',
           f'[2:a]atrim=0:{TOTAL},asetpts=PTS-STARTPTS,{mvol}[music]']
mix = ['[bed]', '[music]']
for k, (name, t, gain) in enumerate(cues, start=3):
    f = os.path.join(audio, f'{name}.mp3')
    if not os.path.exists(f):
        print('missing sound', name)
        continue
    inputs += ['-i', f]
    ms = max(0, int(round(t * 1000)))
    filters.append(f'[{k}:a]volume={gain}dB,adelay={ms}|{ms}[s{k}]')
    mix.append(f'[s{k}]')
filters.append(''.join(mix) + f'amix=inputs={len(mix)}:normalize=0:duration=longest,atrim=0:{TOTAL},volume=5dB,alimiter=limit=0.95[mix]')
cmd = ['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-framerate', str(FPS), '-i', os.path.join(frames, 'f%05d.png')] + inputs + [
    '-filter_complex', ';'.join(filters), '-map', '0:v', '-map', '[mix]',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', CRF, '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-level', '4.1',
    '-movflags', '+faststart', '-r', str(FPS), '-t', str(TOTAL), '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', out]
subprocess.run(cmd, check=True)
print('wrote', out, 'cues', len(cues))

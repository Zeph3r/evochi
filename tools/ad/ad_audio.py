"""Builds the ad soundtrack from the game's own SFX and ambience, then muxes it with the frames.

python3 ad_audio.py FRAMES_DIR AUDIO_DIR OUT.mp4 [--no-video]
"""
import os
import subprocess
import sys

frames, audio, out = sys.argv[1], sys.argv[2], sys.argv[3]
TOTAL = 27.0
FPS = 30

# (file, time in seconds, gain dB)
CUES = [
    ('ui_tap', 0.0, -9), ('ui_tap', 2.9, -9), ('ui_tap', 5.1, -9), ('ui_tap', 8.1, -9), ('ui_tap', 10.6, -9),
    ('ui_tap', 14.4, -9), ('ui_tap', 19.3, -9), ('ui_tap', 21.2, -9),
    ('pet_chirp', 0.9, -2), ('play_boing', 2.6, -3), ('pet_chirp', 4.8, -4),
    ('coin', 8.26, -4), ('coin', 8.93, -4), ('coin', 9.61, -4), ('reward_chime', 9.82, -3),
    ('purchase', 12.8, -3), ('pet_chirp', 13.1, -6),
    ('level_up', 14.95, -8),            # the Evolve button tap
    ('evolve_fanfare', 16.75, 0),       # the reveal
    ('ui_tap', 17.2, -6),
    ('pet_chirp', 20.6, -3),
    ('reward_chime', 23.8, -4),
]

inputs = ['-stream_loop', '-1', '-i', os.path.join(audio, 'ambient_meadow_loop.mp3')]
filters = [f'[1:a]atrim=0:{TOTAL},asetpts=PTS-STARTPTS,volume=-17dB,afade=t=in:st=0:d=0.6,afade=t=out:st={TOTAL - 1.2}:d=1.2[bed]']
mix = ['[bed]']
for k, (name, t, gain) in enumerate(CUES, start=2):
    inputs += ['-i', os.path.join(audio, f'{name}.mp3')]
    filters.append(f'[{k}:a]volume={gain}dB,adelay={int(t * 1000)}|{int(t * 1000)}[s{k}]')
    mix.append(f'[s{k}]')
n = len(mix)
filters.append(''.join(mix) + f'amix=inputs={n}:normalize=0:duration=longest,atrim=0:{TOTAL},volume=5.5dB,alimiter=limit=0.95[mix]')
fc = ';'.join(filters)

cmd = ['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error',
       '-framerate', str(FPS), '-i', os.path.join(frames, 'f%05d.png')] + inputs + [
       '-filter_complex', fc, '-map', '0:v', '-map', '[mix]',
       '-c:v', 'libx264', '-preset', 'slow', '-crf', '18', '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-level', '4.1',
       '-movflags', '+faststart', '-r', str(FPS), '-t', str(TOTAL),
       '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', out]
print(' '.join(cmd)[:300], '...')
subprocess.run(cmd, check=True)
print('wrote', out)

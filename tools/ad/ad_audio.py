"""Mixes the ad soundtrack (music bed + the game's own SFX at the cue times) and encodes the MP4.

python3 ad_audio.py CUT FRAMES_DIR AUDIO_DIR MUSIC.wav OUT.mp4      (CUT = long | short)
"""
import os
import subprocess
import sys

cut, frames, audio, music, out = sys.argv[1:6]
CRF = os.environ.get('CRF', '18')
if cut == 'rv2':
    cut = 'rv1'
FPS = 30

# (sfx file, time in seconds, gain dB) for each cut. Times come from the composition timeline.
CUES = {
    'long': {
        'total': 27.0,
        'cues': [
            ('ui_tap', 0.0, -9), ('ui_tap', 2.9, -9), ('ui_tap', 5.1, -9), ('ui_tap', 8.1, -9), ('ui_tap', 10.6, -9),
            ('ui_tap', 14.4, -9), ('ui_tap', 19.3, -9), ('ui_tap', 21.2, -9),
            ('pet_chirp', 0.9, -2), ('play_boing', 2.6, -3), ('pet_chirp', 4.8, -4),
            ('coin', 8.26, -4), ('coin', 8.93, -4), ('coin', 9.61, -4), ('reward_chime', 9.82, -3),
            ('purchase', 12.8, -3), ('pet_chirp', 13.1, -6),
            ('level_up', 14.95, -8),
            ('evolve_fanfare', 16.75, 0),
            ('ui_tap', 17.2, -6),
            ('pet_chirp', 20.6, -3),
            ('reward_chime', 23.8, -6),
        ],
    },
    'short': {
        'total': 19.0,
        'cues': [
            ('ui_tap', 0.0, -9), ('ui_tap', 2.4, -9), ('ui_tap', 4.3, -9), ('ui_tap', 6.5, -9), ('ui_tap', 8.3, -9),
            ('ui_tap', 11.2, -9), ('ui_tap', 15.3, -9),
            ('pet_chirp', 0.9, -2), ('play_boing', 2.6, -3),
            ('coin', 6.59, -4), ('coin', 7.17, -4), ('coin', 7.75, -4), ('reward_chime', 7.9, -3),
            ('purchase', 10.12, -3), ('pet_chirp', 10.45, -6),
            ('level_up', 11.8, -8),
            ('evolve_fanfare', 13.3, 0),
            ('ui_tap', 13.75, -6),
            ('pet_chirp', 16.55, -3),
            ('reward_chime', 16.6, -6),
        ],
    },
    'dev': {
        'total': 20.0,
        'cues': [
            ('ui_tap', 0.0, -9), ('ui_tap', 3.0, -9), ('ui_tap', 6.0, -9), ('ui_tap', 9.4, -9), ('ui_tap', 13.0, -9),
            ('pet_chirp', 2.5, -3), ('ui_tap', 3.3, -14), ('ui_tap', 3.6, -14), ('ui_tap', 3.9, -14), ('ui_tap', 4.2, -14), ('ui_tap', 4.5, -14), ('ui_tap', 4.8, -14), ('ui_tap', 5.1, -14), ('ui_tap', 5.4, -14), ('ui_tap', 5.7, -14),
            ('play_boing', 9.25, -6), ('play_boing', 9.85, -6), ('level_up', 10.45, -6),
            ('pet_chirp', 13.4, -3), ('evolve_fanfare', 14.9, -4),
            ('reward_chime', 16.0, -6),
        ],
    },
    'pick': {
        'total': 18.0,
        'cues': [
            ('ui_tap', 0.0, -9), ('ui_tap', 3.6, -9), ('ui_tap', 7.0, -9), ('ui_tap', 9.6, -9), ('ui_tap', 12.6, -9),
            ('ui_tap', 0.4, -12), ('ui_tap', 0.97, -12), ('ui_tap', 1.53, -12), ('ui_tap', 2.1, -12), ('ui_tap', 2.67, -12), ('ui_tap', 3.23, -12),
            ('ui_tap', 3.8, -12), ('ui_tap', 5.3, -10),
            ('evolve_fanfare', 6.45, -3), ('pet_chirp', 7.8, -3),
            ('play_boing', 10.6, -8), ('play_boing', 10.95, -8), ('play_boing', 11.3, -8), ('play_boing', 11.65, -8), ('play_boing', 12.0, -8), ('play_boing', 12.35, -8),
            ('reward_chime', 14.6, -6),
        ],
    },
    'crown': {
        'total': 17.0,
        'cues': [
            ('ui_tap', 0.0, -9), ('ui_tap', 2.9, -9), ('ui_tap', 5.0, -9), ('ui_tap', 9.0, -9),
            ('reward_chime', 2.6, -1), ('pet_chirp', 2.75, -3),
            ('play_boing', 4.95, -8), ('play_boing', 5.35, -8), ('play_boing', 5.75, -8),
            ('pet_chirp', 9.05, -6), ('pet_chirp', 9.35, -7), ('pet_chirp', 9.65, -8),
            ('reward_chime', 12.0, -6),
        ],
    },
    'hatch': {
        'total': 18.0,
        'cues': [
            ('ui_tap', 0.0, -9), ('ui_tap', 3.5, -9), ('ui_tap', 8.1, -9), ('ui_tap', 11.0, -9),
            ('evolve_fanfare', 7.75, -5), ('pet_chirp', 7.95, -2),
            ('pet_chirp', 11.95, -7), ('pet_chirp', 12.85, -8), ('pet_chirp', 13.75, -8),
            ('reward_chime', 14.0, -6),
        ],
    },
    'elder': {
        'total': 18.0,
        'cues': [
            ('ui_tap', 0.0, -9), ('ui_tap', 2.4, -9), ('ui_tap', 5.0, -9), ('ui_tap', 7.2, -9), ('ui_tap', 9.9, -9), ('ui_tap', 13.0, -9),
            ('pet_chirp', 2.05, -3), ('play_boing', 3.2, -8), ('play_boing', 4.2, -8),
            ('level_up', 6.6, -6), ('level_up', 8.0, -4),
            ('evolve_fanfare', 9.6, 0), ('pet_chirp', 13.3, -4),
            ('reward_chime', 15.5, -6),
        ],
    },
    'miss': {
        'total': 18.0,
        'cues': [
            ('ui_tap', 0.0, -9), ('ui_tap', 3.4, -9), ('ui_tap', 5.6, -9), ('ui_tap', 8.4, -9), ('ui_tap', 11.0, -9), ('ui_tap', 13.2, -9), ('ui_tap', 15.6, -9),
            ('pet_chirp', 1.15, -3), ('play_boing', 1.7, -8),
            ('ui_tap', 3.6, -14), ('ui_tap', 3.9, -14), ('ui_tap', 4.2, -14), ('ui_tap', 4.5, -14), ('ui_tap', 4.8, -14), ('pet_chirp', 4.95, -3),
            ('evolve_fanfare', 6.45, -3), ('pet_chirp', 7.3, -5),
            ('play_boing', 8.75, -6), ('play_boing', 9.35, -6), ('level_up', 9.95, -6),
            ('reward_chime', 13.2, -1), ('pet_chirp', 13.35, -2),
            ('play_boing', 15.65, -7), ('play_boing', 16.05, -7), ('pet_chirp', 16.4, -4),
        ],
    },
    'grow': {
        'total': 16.0,
        'cues': [
            ('ui_tap', 0.0, -9), ('ui_tap', 2.6, -9), ('ui_tap', 5.0, -9), ('ui_tap', 8.0, -9), ('ui_tap', 11.0, -9), ('ui_tap', 13.7, -9),
            ('pet_chirp', 0.5, -4), ('play_boing', 3.1, -8), ('play_boing', 4.1, -8),
        ] + [('ui_tap', round(5.0 + i * 0.4, 2), -16) for i in range(15)] + [
            ('level_up', 7.2, -6), ('evolve_fanfare', 9.4, -2),
            ('play_boing', 11.6, -8), ('play_boing', 11.9, -8), ('play_boing', 12.6, -8), ('play_boing', 12.9, -8),
            ('pet_chirp', 13.75, -3),
        ],
    },
    'rv1': {
        'total': 12.0,
        'cues': [
            ('ui_tap', 0.0, -9), ('ui_tap', 3.5, -9), ('ui_tap', 6.0, -9), ('ui_tap', 9.9, -9),
            ('play_boing', 0.6, -12), ('play_boing', 1.3, -11), ('play_boing', 1.85, -10), ('play_boing', 2.3, -9), ('play_boing', 2.65, -8), ('play_boing', 2.95, -7), ('play_boing', 3.2, -6),
            ('evolve_fanfare', 3.35, 0), ('pet_chirp', 3.9, -3),
            ('play_boing', 9.85, -8), ('play_boing', 10.3, -8), ('pet_chirp', 10.6, -4),
        ],
    },
    'rv3': {
        'total': 12.0,
        'cues': [
            ('ui_tap', 0.0, -9), ('ui_tap', 3.5, -9), ('ui_tap', 6.0, -9), ('ui_tap', 9.9, -9),
            ('play_boing', 0.9, -10), ('play_boing', 1.5, -10), ('play_boing', 2.0, -9), ('play_boing', 2.4, -9), ('play_boing', 2.75, -8), ('play_boing', 3.05, -8),
            ('ui_tap', 1.2, -6), ('ui_tap', 1.9, -6),
            ('reward_chime', 3.4, 0), ('purchase', 3.4, -4), ('pet_chirp', 3.9, -3),
            ('play_boing', 6.0, -8), ('play_boing', 6.4, -8), ('play_boing', 6.8, -8),
            ('play_boing', 9.85, -8), ('play_boing', 10.3, -8), ('pet_chirp', 10.6, -4),
        ],
    },
}[cut]
TOTAL = CUES['total']

inputs = ['-stream_loop', '-1', '-i', os.path.join(audio, 'ambient_meadow_loop.mp3'), '-i', music]
filters = [
    f'[1:a]atrim=0:{TOTAL},asetpts=PTS-STARTPTS,volume=-21dB,afade=t=in:st=0:d=0.6,afade=t=out:st={TOTAL - 1.2}:d=1.2[bed]',
    f'[2:a]atrim=0:{TOTAL},asetpts=PTS-STARTPTS,volume=-7dB,afade=t=in:st=0:d=0.3[music]',
]
mix = ['[bed]', '[music]']
for k, (name, t, gain) in enumerate(CUES['cues'], start=3):
    inputs += ['-i', os.path.join(audio, f'{name}.mp3')]
    filters.append(f'[{k}:a]volume={gain}dB,adelay={int(t * 1000)}|{int(t * 1000)}[s{k}]')
    mix.append(f'[s{k}]')
filters.append(''.join(mix) + f'amix=inputs={len(mix)}:normalize=0:duration=longest,atrim=0:{TOTAL},volume=5dB,alimiter=limit=0.95[mix]')

cmd = ['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error',
       '-framerate', str(FPS), '-i', os.path.join(frames, 'f%05d.png')] + inputs + [
       '-filter_complex', ';'.join(filters), '-map', '0:v', '-map', '[mix]',
       '-c:v', 'libx264', '-preset', 'slow', '-crf', CRF, '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-level', '4.1',
       '-movflags', '+faststart', '-r', str(FPS), '-t', str(TOTAL),
       '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', out]
subprocess.run(cmd, check=True)
print('wrote', out)

"""Mixes the ad soundtrack (music bed + the game's own SFX at the cue times) and encodes the MP4.

python3 ad_audio.py CUT FRAMES_DIR AUDIO_DIR MUSIC.wav OUT.mp4      (CUT = long | short)
"""
import os
import subprocess
import sys

cut, frames, audio, music, out = sys.argv[1:6]
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
       '-c:v', 'libx264', '-preset', 'slow', '-crf', '18', '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-level', '4.1',
       '-movflags', '+faststart', '-r', str(FPS), '-t', str(TOTAL),
       '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', out]
subprocess.run(cmd, check=True)
print('wrote', out)

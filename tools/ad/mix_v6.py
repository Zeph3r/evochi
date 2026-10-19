"""Music bed + game SFX for the v6 recipe Shorts, then encode the MP4.
python3 mix_v6.py CUT FRAMES_DIR AUDIO_DIR MUSIC.wav OUT.mp4"""
import os, subprocess, sys
cut, frames, audio, music, out = sys.argv[1:6]
FPS = 30
day_ticks = [('ui_tap', 2.9 + (d - 1) * 0.3, -17) for d in range(1, 31) if d not in (7, 30)]
CUES = {
    'now': (16.5, [('pet_chirp', 1.65, -3), ('pet_chirp', 3.2, -5)] + [('coin', a, -9) for a in (5.1, 5.75, 6.35, 7.0, 7.6)] +
                  [('evolve_fanfare', 8.4, -1), ('evolve_fanfare', 10.6, 0), ('reward_chime', 12.95, -3), ('pet_chirp', 13.05, -4), ('pet_chirp', 14.55, -5)]),
    'village': (17.5, [('pet_chirp', 0.5, -4)] + [('coin', a, -9) for a in (8.9, 9.5, 10.1, 10.6)] +
                      [('reward_chime', 10.95, -2), ('level_up', 11.9, -2), ('pet_chirp', 12.0, -4), ('pet_chirp', 15.0, -6)]),
    'day30': (16.0, [('pet_chirp', 0.6, -4)] + day_ticks +
                    [('evolve_fanfare', 4.7, -1), ('evolve_fanfare', 11.6, 0), ('reward_chime', 13.25, -3), ('pet_chirp', 13.35, -4), ('pet_chirp', 14.9, -6)]),
}
TOTAL, cues = CUES[cut]
inputs = ['-stream_loop', '-1', '-i', os.path.join(audio, 'ambient_meadow_loop.mp3'), '-i', music]
filters = [f'[1:a]atrim=0:{TOTAL},asetpts=PTS-STARTPTS,volume=-21dB,afade=t=in:st=0:d=0.3,afade=t=out:st={TOTAL - 0.6}:d=0.6[bed]',
           f'[2:a]atrim=0:{TOTAL},asetpts=PTS-STARTPTS,volume=-7dB[music]']
mix = ['[bed]', '[music]']
for k, (name, t, gain) in enumerate(cues, start=3):
    inputs += ['-i', os.path.join(audio, f'{name}.mp3')]
    filters.append(f'[{k}:a]volume={gain}dB,adelay={int(t * 1000)}|{int(t * 1000)}[s{k}]')
    mix.append(f'[s{k}]')
filters.append(''.join(mix) + f'amix=inputs={len(mix)}:normalize=0:duration=longest,atrim=0:{TOTAL},volume=5dB,alimiter=limit=0.95[mix]')
cmd = ['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-framerate', str(FPS), '-i', os.path.join(frames, 'f%05d.png')] + inputs + [
    '-filter_complex', ';'.join(filters), '-map', '0:v', '-map', '[mix]',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '18', '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-level', '4.1',
    '-movflags', '+faststart', '-r', str(FPS), '-t', str(TOTAL), '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', out]
subprocess.run(cmd, check=True)
print('wrote', out)

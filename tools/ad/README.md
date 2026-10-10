# Evochi ad pipeline

Makes the 27-second vertical ad (1080x1920, 30 fps) from real gameplay in the web build.

1. **Record gameplay.** `ad_record.mjs` drives the web build in headless Chromium under a
   virtual clock, so every frame is an exact 1/30 s step at full resolution. It stages a pet
   called Mochi (Ocean) and records five clips: tap, walk, shop, evolve, grown.
   ```bash
   python3 -m http.server 8765 -d ../../web/dist &
   node ad_record.mjs ../../ad_clips
   ```
2. **Compose.** `comp.html` is the timeline: segments with camera moves, captions, tap
   ripples, the meadow vista and the end card. Edit `SEG` and `CAPS` to change the cut.
3. **Render.** `ad_render.mjs` steps through the composition and saves a PNG per frame.
   ```bash
   python3 -m http.server 8766 &          # from a folder that contains ad/ (comp.html + clips/, site/, audio/ symlinks)
   node ad_render.mjs ../../ad_frames
   ```
4. **Music.** `ad_music.py` composes the soft marimba-and-ukulele bed in code (D major, 108 BPM),
   with the riser, sparkle chord and final chord placed at the times you pass in.
   ```bash
   python3 ad_music.py music_long.wav 27 14.44 16.82 17.78 23.89     # total, riser start, reveal, groove back, end card
   python3 ad_music.py music_short.wav 19 11.11 13.37 14.44 16.67
   ```
5. **Mix and encode.** `ad_audio.py` lays the music and the game's own SFX at the cue times for
   the chosen cut and encodes H.264 + AAC.
   ```bash
   python3 ad_audio.py long  ../../ad_frames       ../../web/public/assets/audio music_long.wav  evochi_ad_27s.mp4
   python3 ad_audio.py short ../../ad_frames_short ../../web/public/assets/audio music_short.wav evochi_ad_19s.mp4
   ```

Two cuts live in `comp.html` (`?cut=long` and `?cut=short`); `ad_render.mjs --cut short` renders
the 19-second one.

`evochi_ad_voiceover_script.txt` has the VO lines with timestamps for both cuts, and the
`evochi_ad_captions_*.srt` files carry the burned-in caption text as subtitles.

Needs Node 18+, `puppeteer-core`, `@sparticuz/chromium` (or any Chromium), ffmpeg and Python 3.

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
4. **Mix and encode.** `ad_audio.py` lays the game's own SFX on the ambient loop at the cue
   times and encodes H.264 + AAC.
   ```bash
   python3 ad_audio.py ../../ad_frames ../../web/public/assets/audio evochi_ad.mp4
   ```

`evochi_ad_voiceover_script.txt` has the VO lines with timestamps, and
`evochi_ad_captions.srt` the burned-in caption text as a subtitle file.

Needs Node 18+, `puppeteer-core`, `@sparticuz/chromium` (or any Chromium), ffmpeg and Python 3.

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

## Waitlist campaign (four videos)

`comp_wl.html` holds four more cuts for the beta waitlist: `dev` (dev diary), `pick` (pick your egg),
`crown` (Founder's Crown) and `hatch` (community hatch goal). They use `waitlist_assets.py` output
(voxel build-up, expressions, turnaround, the rose-gold Founder's Crown, the night vista) and two
extra gameplay clips from `ad_record_pick.mjs` (the Create screen and the hatching).

```bash
python3 waitlist_assets.py ../../ad/wl
node ad_record_pick.mjs ../../ad_clips_pick            # web/dist on :8765
node ad_render.mjs ../../wl_frames/dev --cut dev --comp comp_wl.html
python3 ad_music.py music_dev.wav 20 7.78 9.0 10.0 16.0
python3 ad_audio.py dev ../../wl_frames/dev ../../web/public/assets/audio music_dev.wav evochi_wl1.mp4
```

Music cue times per cut (total, riser, reveal, groove back, end card):
dev 20 7.78 9.0 10.0 16.0 · pick 18 5.56 6.5 7.78 14.6 · crown 17 1.2 2.6 3.9 12.0 · hatch 18 5.56 7.8 8.9 14.0.
`evochi_waitlist_ads_scripts.txt` has the VO lines, post copy and the landing-page checklist.

## v3: evolved-first, nostalgia hooks and the Evolution Reveal series

`comp_v3.html` holds six more cuts built on the "how to go viral" notes: `elder` (open on the fully
evolved Mochi, cut to day one), `miss` ("I miss the games where you actually cared…", ends on a
question), `grow` ("What if your childhood virtual pet grew up with you?", ends on a question) and
`rv1`..`rv3`, the first three Evolution Reveal episodes (Amethyst, the secret Aurora colour, the
autumn outfit) made from one `revealCut()` template. `series_assets.py` renders the Elder turntables
(36 views), the Elder expression sheets, the Aurora forms and the outfit composites into `ad/wl3`.

```bash
python3 series_assets.py ../../ad/wl3                      # ~6 min, needs tools/art
node ad_render.mjs ../../v3_frames/rv1 --cut rv1 --comp comp_v3.html
python3 ad_music.py music_rv.wav 15 2.8 4.2 5.2 12.3
python3 ad_audio.py rv1 ../../v3_frames/rv1 ../../web/public/assets/audio music_rv.wav evochi_v3_04_reveal_ep01_amethyst_15s.mp4
python3 v3_pack.py VIDEO_DIR OUT_DIR                        # per-video folders with scripts, captions and post copy
```

Music cue times (total, riser, reveal, groove back, end): elder 22 10.6 11.74 12.7 18.5 · miss 22 15.1 16.0 16.8 18.8 ·
grow 20 10.7 11.6 12.5 16.8 · rv1/rv2/rv3 15 2.8 4.2 5.2 12.3. `rv2` reuses `rv1`'s sound cues; `CRF=22` on
`ad_audio.py` makes smaller delivery files. `v3_pack.py` also writes `HOW_TO_MAKE_MORE_EPISODES.txt`.

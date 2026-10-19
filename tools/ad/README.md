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

## v4: Mochi in the world (character-first hooks)

`comp_v4.html` drops the cream-card openings: every cut starts with Mochi already moving in the meadow
(the hero vista used as a panning camera, the 3/4 sprites mirrored to walk right with a hop-walk, a
ground shadow, the step-counter pill, and an in-world evolution with a charge glow). Cuts: `care`
("I thought I was taking care of him", 19 s), `evolves` (evolution in second one, then the real hatch
and evolution footage, 18 s), `week1` (series: egg to level 10 in seven days, 20 s), `missB` (the live
"I miss the games" video with only the first 4.2 s replaced, for an A/B test; the body is copied
verbatim from `CUTS.miss`), `part` ("that little part of you never went away", 18 s) and `moods`
(15.5 s).

```bash
python3 v4_assets.py ../../ad/wl4          # Mochi's egg (whole, cracked once, cracked twice); copy the
                                           # meadow nest to wl4/nest.webp and its front rim to nest_front.webp
node ad_render.mjs ../../v4_frames/care --cut care --comp comp_v4.html
python3 ad_music.py music_v4_care.wav 19 8.6 9.95 10.6 15.0
python3 ad_audio.py care ../../v4_frames/care ../../web/public/assets/audio music_v4_care.wav evochi_v4_01_taking_care_of_him_19s.mp4
python3 v4_pack.py VIDEO_DIR OUT_DIR
```

Music cues (total, riser, reveal, groove back, end): care 19 8.6 9.95 10.6 15.0 · evolves 18 13.0 14.6 15.3
16.9 · week1 20 13.6 14.6 15.3 16.6 · part 18 7.0 8.6 9.6 14.4 · moods 15.5 11.8 12.6 13.2 14.6. `missB`
reuses `music_miss.wav` and the live video's sound cues from 4.2 s on, so the opening is the only change.

## v5 and v6: hook-first, then the recipe

`comp_v5.html` adds three hook-first re-cuts of "care" (`grows`, `steps`, `pov`: Mochi big in frame and
already mid-event at frame 0, the twist by 10 s, the last second leading back into the first).
`comp_v6.html` is the recipe the later batches follow: **result first (something viewers haven't seen)
→ before → one mechanic → proof in motion → one human line → a one-word question that loops back into
frame 0; captions of seven words or fewer, fully on screen at frame 0.** Cuts: `now` (the crowned Elder
spinning in, then day 1 to day 30), `village` (the lit Square, then Mira's ask and 2,000 steps) and
`day30` (a split screen, then a month fills in). `mix_v6.py` lays the meadow ambience, the marimba bed
and the game's sounds and encodes.

## v7: the encounters

Four Shorts about the encounters, cut to the v6 recipe (`comp_v7.html`: `watch`, `hurt`, `gate`, `week2`).

- **Footage:** `enc_record.mjs` records an encounter from the web build frame-exactly at 1080 px wide:
  timers, rAF, Date and every CSS animation follow one virtual clock, so each JPEG is exactly 1/30 s
  after the last. It stages Mochi (Ocean Juvenile), the quest ready for its encounter and the items, plays
  the attempt (the player ids were chosen so the seeded replies match the scripts: a skitter, a head tilt,
  the lash, the Sentinel's phase-two wake) and writes `log.json` with the scene time of every action, sound
  cue and phase change. The cuts place their windows by those marks (`mark('eq01', 'act:lumen_glow')`).
  The canvas effects (`web/src/ui/fx.js`) run on the same clock, and a hit-stop on the stage
  (`.enc-stage.hitstop`) freezes the CSS animations in the recording too, so the footage is exactly what
  players see.
- **Plates:** `tools/art/shorts_scenes.py` renders the cinematic plates in Blender (portrait, 1296x2304):
  `short_trail` (the trail up to the ruins), `short_gate` (dusk, the dormant Sentinel modelled into the
  gateway) and `short_gate_lit` (night, restored, the trail beyond glowing). Anchors (eyes, chest, path) are
  projected to pixels, so the eye glows and Mochi's walk sit on the plate.
- **Sound:** `mix_v7.py` reads each clip's `log.json` and lays the game's own sounds at the recorded times,
  plus the marimba bed (`ad_music.py`) and the meadow ambience; `gate` ducks the music for the awakening.
- **Pack:** `v7_pack.py` writes the per-video folders, the README posting plan and the results tracker.

```bash
python3 -m http.server 8765 -d ../../web/dist &                      # the game, for the recorder
node enc_record.mjs CLIPS/eq01 eq01 && node enc_record.mjs CLIPS/eq02 eq02 && node enc_record.mjs CLIPS/eq03 eq03
<bpy-python> ../art/village_blender.py ../../assets/shorts short_trail short_gate short_gate_lit --meta scenes.json --raw /tmp/shorts_raw   # ~45 min on 2 cores
# the comp folder needs: clips7 -> CLIPS, plates -> ../../assets/shorts, v7/ (the creature + back-view sprites, items, icons, manifest excerpts)
node ad_render.mjs FRAMES/watch --cut watch --comp comp_v7.html
python3 ad_music.py music_watch.wav 17 11.4 12.55 13.2 14.4
python3 mix_v7.py watch FRAMES/watch ../../web/public/assets/audio music_watch.wav CLIPS evochi_v7_01_she_followed_us_home_17s.mp4
python3 v7_pack.py VIDEO_DIR OUT_DIR
```

Music cues (total, riser, reveal, groove back, end): watch 17 11.4 12.55 13.2 14.4 · hurt 17.5 11.0 12.35 13.0 14.8 ·
gate 18 13.0 14.3 15.0 15.6 · week2 17.5 12.6 13.75 14.3 14.8.

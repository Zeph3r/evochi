EVOCHI VIDEO PACK v7: the encounters
====================================

Four Shorts about the new encounters, cut to the v6 recipe: result first (something nobody has seen),
then before, one mechanic, proof in motion (real encounter footage recorded frame-exactly from the
game), one human line, and a question you can answer in a word or a number that loops back into
frame 0. Captions are seven words or fewer and fully on screen at frame 0. Mochi is the Ocean
Juvenile, where week 1 left him.

New cinematics in this batch
----------------------------
- The trail up to the Mossy Ruins at morning, Mochi walking away from the camera (the new back view).
- The old bridge and the gate at dusk with the Forgotten Sentinel modelled into the scene, slumped in
  the gateway and lit only by the crystals, so it reads as rubble until its eyes light.
- The same gate at night, restored: mint runes, the trail beyond it glowing again.
- A composed battle shot of the restored Sprout and Mochi in golden light.
- The game's own intro cinematics, turns and results, recorded at 1080 px wide under a frame-exact
  clock (tools/ad/enc_record.mjs), so the camera moves and effects are exactly what players see.

The videos
----------
01_she_followed_us_home_17s     Petalune. "You don't fight it." Ends: tart, stew or bun? (1/2/3)
02_nobody_gets_hurt_17s         The design hook. The Hollow Sprout. Ends: your name for Soothe?
03_i_woke_something_up_18s      The Sentinel's awakening. Ends: what was it guarding?
04_week2_he_made_a_friend_17s   Series, days 8-14. Ends: should he go to the gate? yes / no

Each folder: the MP4 (1080x1920, 30 fps, music + the game's sounds), voiceover.txt (the lines with
timings if you want to record yourself), captions.srt, post_copy.txt (YouTube title + description,
TikTok, Instagram, X, the pinned comment, and which frame to use as the cover).

Posting plan
------------
Friday
  12:00   02  Nobody gets hurt           the design hook; the broadest one
  19:00   04  Week 2: he made a friend   the series slot; asks the yes/no vote
Saturday
  11:00   01  She followed us home       (01 and 04 both show Petalune, so a day apart)
Tuesday
  18:00   03  I woke something up        frame it as "you voted yes" in the pinned comment

Reply to every comment in the first hour, ideally with a question back. The pinned comments are
written so the first reply is easy ("2, carrot stew", "I almost called it Nap", "wrong answers only",
"votes close Sunday").

How to read the results (after 48 hours, not before)
----------------------------------------------------
YouTube Studio > the Short > Analytics > Engagement:
  - Stayed to watch: the opening's score. These four all open on a result; compare them with v6.
  - Average percentage viewed: the body's score. The loop-back ending should lift it.
  - Comments per 100 views: the question's score. 01 and 04 should lead (numbered / yes-no).
results_tracker.csv has a row per video and platform; fill it in on Sunday.

Don't judge on views. One lucky test batch can triple a number.

Making more
-----------
tools/ad/README.md (v7 section) has the commands: enc_record.mjs records any encounter frame-exactly,
shorts_scenes.py renders the plates in Blender, comp_v7.html holds the four cuts, mix_v7.py lays the
game's own sounds at the recorded times. A new encounter video is: record the encounter, pick the
moments in the cut by the action marks in its log.json, and write seven captions.

EVOCHI VIDEO PACK v8: the Wilds in action
=========================================

Four action Shorts recorded straight from the game (the beta build) by the Shorts recorder
(flutter/tool/shorts): the game runs on a frame-exact clock, an autopilot plays, and the game's own
sounds and music are mixed in at the moments they happen. Nothing is mocked up. 1080x1920, 30 fps.
Each ends on an end card: the Evochi wordmark, a line, "Join the beta waitlist", "link in bio",
"@evochigame".

The videos
----------
01_i_walked_3000_steps_26s       The Forgotten Sentinel: its cinematic (roar, beam, Mochi's leap, the
                                 title card), the fight, a Lantern Tonic through its Hollow shield, and
                                 "It remembered who it was." Ends: how many steps did you get today?
02_step_counter_boss_fights_25s  The Briarback: its cinematic, Sunflare, a perfect dodge, "Calmed, not
                                 beaten." The broadest hook. Ends: would this get you walking? yes / no
03_every_floor_is_new_18s        The Deep Wilds: fresh floors, the way down, F2 to F5, a Hollow Surge
                                 and its reward. Ends: what floor would you reach in week one?
04_which_one_is_yours_17s        All six Elder signature moves back to back. Ends: which one is yours?
                                 (one word: the colour)

Each folder: the MP4 and post_copy.txt (YouTube title + description, TikTok, Instagram, X, the pinned
comment, and which frame to use as the cover). The captions are burned into the video, so there is
no .srt this time; leave the platforms' auto-captions off.

Posting plan (your time)
------------------------
Thursday Oct 22
  18:00   02  A step counter with boss fights?   the broadest one; the yes/no is an easy first comment
Friday Oct 23
  19:00   04  Which one is yours?                 the one-word answer; reply to every colour
Saturday Oct 24
  11:00   01  I walked 3,000 steps to find this   the cinematic; ask for step counts in the replies
Monday Oct 26
  18:00   03  Every floor is made fresh           the depth question; reply with "realistic?" banter

Before the first one: check the bio link on every platform goes to evochigame.com (the end cards
say "link in bio" and "@evochigame").

Reply to every comment in the first hour, ideally with a question back.

How to read the results (after 48 hours, not before)
----------------------------------------------------
YouTube Studio > the Short > Analytics > Engagement:
  - Stayed to watch: the opening's score.
  - Average percentage viewed: the body's score. 01 and 02 are longer (25-26 s), so expect a lower
    percentage there than for 03 and 04; compare them with each other, not with 03 and 04.
  - Comments per 100 views: the question's score. 04 (one word) should lead.
results_tracker.csv has a row per video and platform; fill it in the Sunday after.

Don't judge on views. One lucky test batch can triple a number.

Making more
-----------
tools/shorts/README.md: write a Short in flutter/tool/shorts/shorts.dart (clips, beats, captions, end
card), record it on the PC (it takes about 3 minutes), encode it with tools/shorts/encode.py.

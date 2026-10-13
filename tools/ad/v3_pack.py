"""Assembles the v3 video pack: one folder per video with the MP4, voice-over script, captions (.srt)
and post copy for TikTok, Instagram Reels, YouTube Shorts and X, plus a README and the series guide.

python3 v3_pack.py VIDEO_DIR OUT_DIR      (VIDEO_DIR holds evochi_v3_*.mp4)
"""
import os
import shutil
import sys

VID, OUT = sys.argv[1], sys.argv[2]


def srt_time(t):
    ms = int(round(t * 1000))
    return '%02d:%02d:%02d,%03d' % (ms // 3600000, ms // 60000 % 60, ms // 1000 % 60, ms % 1000)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text.strip('\n') + '\n')


VIDEOS = [
    {
        'slug': '01_elder_first_18s', 'file': 'evochi_v3_01_elder_first_18s.mp4', 'cut': 'elder', 'len': 18,
        'title': 'Elder first (the evolved-first opener)',
        'answers': 'Recommendation 1: show the most exciting visual first. Opens on the fully evolved Mochi doing a full turn, hard-cuts to day one, then explains how steps did it. This is the conversion version: it still ends on the waitlist card, so use it as the paid/boosted ad and as the pinned video.',
        'vo': [
            (0.0, 2.4, 'This is Mochi.'),
            (2.4, 5.0, 'This was Mochi on day one.'),
            (5.0, 7.2, 'The only thing I did was walk.'),
            (7.2, 9.3, 'Steps are XP. At level ten and level twenty-five, he changes.'),
            (9.9, 13.0, 'And you pick the moment.'),
            (13.0, 15.5, 'Your steps. Your Evochi.'),
            (15.5, 18.0, 'Hatch it first. Beta waitlist, link in bio.'),
        ],
        'caps': [
            (0.0, 2.4, 'this is Mochi.'), (2.4, 5.0, 'this was Mochi on day one'), (5.0, 7.2, 'the only thing I did was walk'),
            (7.2, 9.3, 'steps are XP. level 10, level 25: he changes'), (9.9, 13.0, 'and you pick the moment'), (13.0, 15.5, 'your steps. your Evochi.'),
            (15.5, 18.0, 'Evochi (beta). Hatch it first. Join the beta waitlist. Link in bio. First 1,000 get the Founder\'s Crown.'),
        ],
        'ending': 'waitlist card',
        'tiktok': 'this is Mochi. this was Mochi on day one. the only thing I did was walk 🚶\n\nbeta waitlist in bio. first 1,000 get the Founder\'s Crown 👑\n\n#evochi #virtualpet #steps #walking #indiegame #cozygame #tamagotchi #gamedev',
        'ig': 'This is Mochi. This was Mochi on day one. The only thing I did was walk.\n\nEvochi is a virtual pet that grows from your real step count. Steps are XP; at level 10 and level 25 it evolves, and you pick the moment.\n\nBeta waitlist is open, link in bio. The first 1,000 get the Founder\'s Crown.\n\n#evochi #virtualpet #steppet #walking #cozygame #indiegame #tamagotchi #gamedev #indiedev #wellness',
        'yt_title': 'This is Mochi. This was Mochi on day one. The only thing I did was walk.',
        'yt_desc': 'Evochi is a virtual pet raised by your real step count. Steps are XP; at level 10 and level 25 it evolves, and you pick the moment.\n\nBeta waitlist: https://evochigame.com (the first 1,000 get the Founder\'s Crown)\n\n#evochi #virtualpet #walking #cozygame #indiegame',
        'x': 'this is Mochi. this was Mochi on day one. the only thing I did was walk.\n\nbeta waitlist: evochigame.com',
        'pin': 'Beta waitlist: evochigame.com. Pick your egg colour, first 1,000 get the Founder\'s Crown 👑',
    },
    {
        'slug': '02_i_miss_the_games_18s', 'file': 'evochi_v3_02_i_miss_the_games_18s.mp4', 'cut': 'miss', 'len': 18,
        'title': 'I miss the games where you actually cared (nostalgia hook, ends on a question)',
        'answers': 'Recommendations 2 and 3: the nostalgia hook, dev-diary voice, no waitlist screen. Ends on Mochi looking at the camera and the question "what was yours called?", which asks people to comment their Tamagotchi / Neopet / Nintendog names. The waitlist goes in the pinned comment and the bio, not in the video.',
        'vo': [
            (0.0, 3.4, 'I miss the games where you actually cared about your little creature.'),
            (3.4, 5.6, "So I'm making one."),
            (5.6, 8.4, 'It hatches from an egg you pick.'),
            (8.4, 11.0, 'It grows when you walk.'),
            (11.0, 13.2, 'It gets sleepy when you stop...'),
            (13.2, 15.6, "...and so happy when you're back."),
            (15.6, 18.0, 'What was yours called?'),
        ],
        'caps': [
            (0.0, 3.4, 'I miss the games where you actually cared about your little creature'), (3.4, 5.6, "so I'm making one."),
            (5.6, 8.4, 'it hatches from an egg you pick'), (8.4, 11.0, 'it grows when you walk'), (11.0, 13.2, 'it gets sleepy when you stop…'),
            (13.2, 15.6, "…and so happy when you're back"), (15.6, 18.0, 'what was yours called?'),
        ],
        'ending': 'question (comment bait), no CTA on screen',
        'tiktok': 'what was yours called? mine was a Tamagotchi named Pip 🥚\n\n#evochi #tamagotchi #virtualpet #nostalgia #90skids #2000skids #indiegame #gamedev #cozygame',
        'ig': 'I miss the games where you actually cared about your little creature. So I\'m making one.\n\nWhat was yours called? 👇\n\n#evochi #tamagotchi #virtualpet #nostalgia #90skids #2000skids #cozygame #indiegame #gamedev #digitalpet',
        'yt_title': "I miss the games where you actually cared about your little creature, so I'm making one",
        'yt_desc': 'What was yours called? Tell me in the comments.\n\nEvochi is a virtual pet raised by your real steps. Beta waitlist: https://evochigame.com\n\n#evochi #tamagotchi #virtualpet #nostalgia #indiegame',
        'x': "I miss the games where you actually cared about your little creature, so I'm making one.\n\nwhat was yours called?",
        'pin': 'mine was a Tamagotchi called Pip. he died on a school trip 🪦 (Evochi is gentler, I promise: evochigame.com)',
    },
    {
        'slug': '03_grew_up_with_you_16s', 'file': 'evochi_v3_03_grew_up_with_you_16s.mp4', 'cut': 'grow', 'len': 16,
        'title': 'What if your childhood virtual pet grew up with you? (nostalgia hook, ends on a question)',
        'answers': 'Recommendations 1, 2 and 3: opens big on the Elder, cuts to the tiny day-one egg, then a scrolling walk log shows weeks passing while Mochi grows. Ends on Mochi looking at the camera and "would you walk for him?" instead of a waitlist screen.',
        'vo': [
            (0.0, 2.6, 'What if your childhood virtual pet...'),
            (2.6, 5.0, '...grew up with you?'),
            (5.0, 8.0, 'Every walk is XP.'),
            (8.0, 11.0, 'Level ten, level twenty-five... and he changes.'),
            (11.0, 13.5, 'Same colour. Same name. All grown up.'),
            (13.7, 16.0, 'Would you walk for him?'),
        ],
        'caps': [
            (0.0, 2.6, 'what if your childhood virtual pet'), (2.6, 5.0, '…grew up with you?'), (5.0, 8.0, 'every walk is XP'),
            (8.0, 11.0, 'level 10… level 25… and he changes'), (11.0, 13.5, 'same colour. same name. all grown up.'), (13.7, 16.0, 'would you walk for him?'),
        ],
        'ending': 'question (comment bait), no CTA on screen',
        'tiktok': 'what if your childhood virtual pet grew up with you? 🥚➡️🦎\n\nwould you walk for him?\n\n#evochi #virtualpet #tamagotchi #walking #steps #cozygame #indiegame #gamedev #nostalgia',
        'ig': 'What if your childhood virtual pet grew up with you?\n\nEvery walk is XP. At level 10 and level 25 he changes. Same colour, same name, all grown up.\n\nWould you walk for him? 👇\n\n#evochi #virtualpet #tamagotchi #walking #10ksteps #cozygame #indiegame #gamedev #nostalgia #wellness',
        'yt_title': 'What if your childhood virtual pet grew up with you?',
        'yt_desc': 'Every walk is XP. At level 10 and level 25 he changes. Would you walk for him?\n\nEvochi beta waitlist: https://evochigame.com\n\n#evochi #virtualpet #walking #cozygame #indiegame',
        'x': 'what if your childhood virtual pet grew up with you?\n\nwould you walk for him?',
        'pin': 'if yes: evochigame.com (pick your egg colour, the first 1,000 get the Founder\'s Crown)',
    },
    {
        'slug': '04_reveal_ep01_amethyst_12s', 'file': 'evochi_v3_04_reveal_ep01_amethyst_12s.mp4', 'cut': 'rv1', 'len': 12,
        'title': 'Evolution Reveal 01: the Amethyst Elder',
        'answers': 'Recommendation 4: the first episode of a recurring series. Charging egg, flash, reveal, a full 360-degree turn, then "which colour next?" so the comments pick episode 04. Same stamp, same structure every time, so people recognise it in the feed.',
        'vo': [
            (0.0, 3.3, "Nobody's seen the Amethyst Elder yet."),
            (3.5, 6.0, 'Amethyst Elder.'),
            (6.0, 9.7, 'Full turn, because someone will ask.'),
            (9.9, 12.0, 'Which colour next?'),
        ],
        'caps': [
            (0.0, 3.3, "nobody's seen the Amethyst Elder yet"), (3.5, 6.0, 'Amethyst Elder'), (6.0, 9.7, 'full turn, because someone will ask'), (9.9, 12.0, 'which colour next?'),
        ],
        'ending': 'question (comment bait), no CTA on screen',
        'tiktok': 'Evolution Reveal 01: Amethyst 💜 which colour next?\n\n#evochi #evolutionreveal #virtualpet #voxel #indiegame #gamedev #cozygame #amethyst',
        'ig': 'Evolution Reveal 01: the Amethyst Elder. Full turn, because someone will ask.\n\nWhich colour next? Amber, Forest, Coral, Ocean or Obsidian 👇\n\n#evochi #evolutionreveal #virtualpet #voxelart #indiegame #gamedev #cozygame #characterdesign',
        'yt_title': 'Evolution Reveal 01: the Amethyst Elder (full turn)',
        'yt_desc': 'Episode 1 of the Evolution Reveal series. Which colour next? Amber, Forest, Coral, Ocean or Obsidian.\n\nEvochi beta waitlist: https://evochigame.com\n\n#evochi #evolutionreveal #virtualpet #voxelart #indiegame',
        'x': 'Evolution Reveal 01: the Amethyst Elder. full turn, because someone will ask.\n\nwhich colour next?',
        'pin': 'the colour with the most comments gets episode 04 💜 (Amber / Forest / Coral / Ocean / Obsidian)',
    },
    {
        'slug': '05_reveal_ep02_aurora_secret_12s', 'file': 'evochi_v3_05_reveal_ep02_aurora_secret_12s.mp4', 'cut': 'rv2', 'len': 12,
        'title': 'Evolution Reveal 02: Aurora, the secret seventh colour',
        'answers': 'Recommendations 2 and 4: an "unexpected evolution". Aurora is a seventh colour that is NOT in the game yet (mint shell, lavender spots, teal crest). The video says so on screen and ends on "should it be in the game? yes / no", which is the kind of question people answer. If the answer is yes, the palette is one line in tools/art/palettes.py (see the series guide).',
        'vo': [
            (0.0, 3.3, "There's a seventh colour I haven't shown anyone."),
            (3.5, 6.0, 'Aurora.'),
            (6.0, 9.7, 'Mint shell, teal crest. Not in the game... yet.'),
            (9.9, 12.0, 'Should it be in the game? Yes or no.'),
        ],
        'caps': [
            (0.0, 3.3, "there's a 7th colour I haven't shown anyone"), (3.5, 6.0, 'Aurora'), (6.0, 9.7, 'mint shell. teal crest. not in the game… yet'), (9.9, 12.0, 'should it be in the game? yes / no'),
        ],
        'ending': 'yes/no question (comment bait), no CTA on screen',
        'tiktok': 'Evolution Reveal 02: Aurora. a 7th colour that isn\'t in the game yet. should it be? yes / no\n\n#evochi #evolutionreveal #virtualpet #voxel #indiegame #gamedev #cozygame #secret',
        'ig': 'Evolution Reveal 02: Aurora. Mint shell, lavender spots, teal crest. It\'s not in the game… yet.\n\nShould it be? Yes or no 👇\n\n#evochi #evolutionreveal #virtualpet #voxelart #indiegame #gamedev #cozygame #characterdesign',
        'yt_title': 'Evolution Reveal 02: Aurora, the secret seventh colour (should it be in the game?)',
        'yt_desc': 'A seventh colour that isn\'t in Evochi yet. Yes or no in the comments decides.\n\nEvochi beta waitlist: https://evochigame.com\n\n#evochi #evolutionreveal #virtualpet #voxelart #indiegame',
        'x': "Evolution Reveal 02: Aurora. a 7th colour that isn't in the game yet.\n\nshould it be? yes / no",
        'pin': 'if Aurora gets in, beta testers hatch it first 🥚 evochigame.com',
    },
    {
        'slug': '06_reveal_ep03_autumn_fit_12s', 'file': 'evochi_v3_06_reveal_ep03_autumn_fit_12s.mp4', 'cut': 'rv3', 'len': 12,
        'title': 'Evolution Reveal 03: the autumn fit (seasonal outfit)',
        'answers': 'Recommendation 4: a seasonal-costume episode. The Forest Elder gets the leaf scarf and explorer hat (both real Market wearables), shown on all three forms because every wearable fits every form. Ends on "what should the winter one be?".',
        'vo': [
            (0.0, 3.3, 'I made him an autumn outfit.'),
            (3.5, 6.0, 'Leaf scarf, plus explorer hat.'),
            (6.0, 9.7, 'Fits every form. Every wearable does.'),
            (9.9, 12.0, 'What should the winter one be?'),
        ],
        'caps': [
            (0.0, 3.3, 'I made him an autumn outfit'), (3.5, 6.0, 'leaf scarf + explorer hat'), (6.0, 9.7, 'fits every form. (every wearable does)'), (9.9, 12.0, 'what should the winter one be?'),
        ],
        'ending': 'question (comment bait), no CTA on screen',
        'tiktok': 'Evolution Reveal 03: autumn fit 🍂 what should the winter one be?\n\n#evochi #evolutionreveal #virtualpet #cozygame #indiegame #gamedev #autumn #fallfits',
        'ig': 'Evolution Reveal 03: the autumn fit. Leaf scarf and explorer hat, and every wearable fits every form.\n\nWhat should the winter one be? 👇\n\n#evochi #evolutionreveal #virtualpet #cozygame #indiegame #gamedev #autumn #cozyseason #characterdesign',
        'yt_title': 'Evolution Reveal 03: the autumn fit (what should the winter one be?)',
        'yt_desc': 'Leaf scarf and explorer hat on the Forest Elder. Every wearable fits every form. What should the winter one be?\n\nEvochi beta waitlist: https://evochigame.com\n\n#evochi #evolutionreveal #virtualpet #cozygame #indiegame',
        'x': 'Evolution Reveal 03: autumn fit 🍂\n\nwhat should the winter one be?',
        'pin': 'scarf and hat are both in the Market for EvoCoins (no real money). winter ideas below 👇',
    },
]

README = """
EVOCHI VIDEO PACK v3: six videos built on the "how to go viral" notes
=====================================================================

What changed from the first two packs
-------------------------------------
1. The most exciting visual comes first. Videos 01 and 03 open on the fully evolved Elder (video 01
   with a full 360-degree turn), then cut to the day-one egg, then explain how steps did it.
2. Fewer ad endings. Only video 01 ends on the waitlist card. Videos 02 to 06 end on a cute animation
   plus a question, with just a small @evochigame tag in the corner. The waitlist link goes in the
   PINNED COMMENT and your bio instead (post_copy.txt has the pinned comment for each video).
3. Nostalgia hooks, word for word: "I miss the games where you actually cared about your little
   creature, so I'm making one" (video 02) and "What if your childhood virtual pet grew up with you?"
   (video 03).
4. The Evolution Reveal series. Videos 04, 05 and 06 are episodes 01 to 03 of a repeatable format
   (charging egg, flash, reveal, full turn, "which colour next?"). The stamp in the top-right corner
   is the series brand. HOW_TO_MAKE_MORE_EPISODES.txt explains how to make 04 onwards in about
   twenty minutes each.

The videos
----------
01_elder_first_18s            Elder first. Conversion version (ends on the waitlist). Boost this one.
02_i_miss_the_games_18s       Nostalgia hook 1. Ends on "what was yours called?"
03_grew_up_with_you_16s       Nostalgia hook 2. Ends on "would you walk for him?"
04_reveal_ep01_amethyst_12s   Evolution Reveal 01. Ends on "which colour next?"
05_reveal_ep02_aurora_12s     Evolution Reveal 02. The secret seventh colour. Ends on "should it be in the game? yes / no"
06_reveal_ep03_autumn_fit_12s Evolution Reveal 03. Seasonal outfit. Ends on "what should the winter one be?"

Each folder has: the MP4 (1080x1920, 30 fps, music and game sound effects mixed in), voiceover.txt
(the lines with timestamps, if you want to record a voice over the captions), captions.srt (the
on-screen text as subtitles, for platforms that want a caption file) and post_copy.txt (TikTok
caption, Instagram caption, YouTube Shorts title and description, X post, and the pinned comment).

About video 05 (Aurora)
-----------------------
Aurora is NOT in the game. The video says so ("not in the game... yet") and asks yes / no. If the
comments say yes, adding it is one line in tools/art/palettes.py plus a rebuild of the sprites;
the exact colours are in HOW_TO_MAKE_MORE_EPISODES.txt. If you'd rather not promise anything,
post it as a "would you want this?" and leave it there. Don't put Aurora on the website until it
exists.

How to post (two weeks)
-----------------------
Day 1   01 Elder first                 pin it on TikTok and Instagram
Day 2   02 I miss the games            pinned comment = your own Tamagotchi story
Day 4   04 Reveal 01 Amethyst          pinned comment = "most comments picks episode 04"
Day 6   03 Grew up with you
Day 8   05 Reveal 02 Aurora            pinned comment = "if it gets in, beta testers hatch it first"
Day 10  06 Reveal 03 autumn fit
Day 12  Reveal 04: whichever colour won the comments on episode 01 (make it with the guide)
Then keep the series going every three or four days. Re-post 01 as a paid ad once the organic
numbers tell you which hook (02 or 03) wins; use that hook's first line as the ad's text overlay.

Post the same video to TikTok, Instagram Reels, YouTube Shorts and X. Post natively on each
(don't share a TikTok link to Instagram; the watermark gets the reach cut). Reply to the first
twenty comments on every video within the hour; the question endings only work if the comments
get answered.

What to measure
---------------
Discovery (02 to 06): completion rate, shares, comments per 1,000 views, follows per 1,000 views.
Conversion (01): profile visits and waitlist sign-ups on the day it's posted (your admin export,
see site/DEPLOY.md). The live counter on evochigame.com is the public scoreboard; mention the
number in the comments when it moves ("1,200 of 5,000, Mochi's egg is warming up").

Series rules (keep the brand consistent)
----------------------------------------
- Stamp always reads "EVOLUTION REVEAL · NN" in the same corner.
- Structure: charge (3 s) > flash > reveal with the name (2.5 s) > full turn or "fits every form" (4 s) > question (2 s).
- Always end on a question the audience can answer with one word.
- One reveal per episode. If you have two ideas, that's two episodes.
"""

SERIES = """
HOW TO MAKE MORE EVOLUTION REVEAL EPISODES
==========================================

Everything is in tools/ad/ of the Evochi repo (the pipeline that made these videos).

1. Pick the episode. Ideas, roughly in the order the audience will ask for them:
   04  Obsidian Elder (the dark one with the light eyes)         colour reveal, full turn
   05  Coral Elder                                                colour reveal, full turn
   06  Amber Elder                                                colour reveal, full turn
   07  Forest Elder                                               colour reveal, full turn
   08  Ocean Elder's ten moods (happy, curious, sleepy...)        moods, no turn
   09  Winter fit (whatever the comments chose)                  outfit on all three forms
   10  The Founder's Crown on the Aurora Elder                    rare + crown, full turn
   11  "Yes, I modelled the back" (back and top views only)      turn
   12  All six Elders side by side                                line-up, "pick yours"
   Also: the Juvenile reveals (same template with the s02 sprites), a night-vista episode,
   and "level 10 vs level 25" comparisons.

2. Make the art (once per colour). From tools/ad:
      python3 series_assets.py ../../ad/wl3 --turn
   edit the `pals=` list in turntables() to add the colour (coral, amber, obsidian, forest).
   For an outfit episode, edit outfit() to pick the items (any of: leaf_scarf, blue_scarf,
   explorer_hat, tiny_crown, golden_crest_crown, butterfly_clip, red_backpack, explorer_pack).

3. Add the episode to comp_v3.html, next to rv1..rv3:
      CUTS.rv4 = revealCut({ ep: '04', pal: 'obsidian', label: 'Obsidian · Elder',
        intro: 'you asked for the<br><span class="g">dark one</span>',
        revealCap: 'Obsidian<br>Elder',
        midCap: 'light eyes. red crest.<br>full turn.',
        question: 'which colour <span class="g">next</span>?' });
   Keep the four captions short: they are the only text on screen. Use the colour's own
   accent class for its name (.g gold, .p pink, .b blue, .m mint).

4. Render, mix, encode (about ten minutes):
      node ad_render.mjs ../../v3_frames/rv4 --cut rv4 --comp comp_v3.html       # web server on :8766 serving the ad/ folder
      python3 ad_audio.py rv1 ../../v3_frames/rv4 ../../web/public/assets/audio ../../ad_music/music_rv.wav evochi_v3_reveal_ep04.mp4
   (rv1's sound cues fit every colour episode; copy the rv3 cues for outfit episodes.)

5. Post with the same caption shape: "Evolution Reveal 04: Obsidian. which colour next?" and
   pin a comment that tells people the next episode is decided by them.

The Aurora palette (if the comments say yes)
--------------------------------------------
tools/art/palettes.py, add to _VARIANTS:
   'aurora': ('#F2F4FB', '#C3B2F2', '#48C9C4', '#F4A6C6', '#5F6E80', '#44505E', '#282725', '#F6F3FF'),
(shell, pattern, crest, cheeks, feet, foot shadow, eyes, claws), add it to VARIANT_ORDER and
VARIANT_NAMES, then rebuild the character sprites and the web assets. The egg picker in the game
shows six eggs; a seventh means a small layout change on the Create screen.
"""


def main():
    if os.path.exists(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    write(os.path.join(OUT, 'README.txt'), README)
    write(os.path.join(OUT, 'HOW_TO_MAKE_MORE_EPISODES.txt'), SERIES)
    for v in VIDEOS:
        d = os.path.join(OUT, v['slug'])
        os.makedirs(d)
        src = os.path.join(VID, v['file'])
        if os.path.exists(src):
            shutil.copy(src, os.path.join(d, v['file']))
        vo = [f"{v['title']}\nLength: {v['len']} s. Ending: {v['ending']}.\n\nWhy this video exists:\n{v['answers']}\n",
              'VOICE-OVER (optional; the captions carry the lines, so the video works muted)',
              'Record in a plain, slightly amused dev-diary voice. No announcer energy. Pause where the dots are.\n']
        for t0, t1, line in v['vo']:
            vo.append(f'{t0:5.1f}s - {t1:5.1f}s   {line}')
        write(os.path.join(d, 'voiceover.txt'), '\n'.join(vo))
        srt = []
        for i, (t0, t1, text) in enumerate(v['caps'], 1):
            srt.append(f'{i}\n{srt_time(t0)} --> {srt_time(t1)}\n{text}\n')
        write(os.path.join(d, 'captions.srt'), '\n'.join(srt))
        pc = f"""{v['title']}

TIKTOK caption
--------------
{v['tiktok']}

INSTAGRAM REELS caption
-----------------------
{v['ig']}

YOUTUBE SHORTS
--------------
Title: {v['yt_title']}
Description:
{v['yt_desc']}

X (Twitter) post
----------------
{v['x']}

PINNED COMMENT (post it yourself right after uploading, on every platform that allows it)
-----------------------------------------------------------------------------------------
{v['pin']}

Notes
-----
- Post natively on each platform (upload the MP4 file, don't cross-share links).
- Sound: the video has its own music and game sound effects. On TikTok, don't replace it with a
  trending sound unless you keep the original at 100% and the trend at 0%; the hatch and evolve
  sounds are part of the hook.
- Cover frame: TikTok and Instagram let you choose one. Use the reveal moment (the big Elder with
  the sparkle) rather than the first frame.
"""
        write(os.path.join(d, 'post_copy.txt'), pc)
    print('pack written to', OUT)


if __name__ == '__main__':
    main()

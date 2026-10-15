"""Assembles the v4 video pack: one folder per video with the MP4, voice-over script, captions (.srt)
and post copy for YouTube Shorts, TikTok, Instagram Reels and X, plus a README with the posting plan,
the A/B test and a results tracker.

python3 v4_pack.py VIDEO_DIR OUT_DIR      (VIDEO_DIR holds evochi_v4_*.mp4)
"""
import os
import shutil
import sys

VID, OUT = sys.argv[1], sys.argv[2]


def srt_time(t):
    ms = int(round(max(0.0, t) * 1000))
    return '%02d:%02d:%02d,%03d' % (ms // 3600000, ms // 60000 % 60, ms // 1000 % 60, ms % 1000)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text.strip('\n') + '\n')


LINK = 'evochigame.com'
TAGS = '#evochi #virtualpet #tamagotchi #walking #cozygame #indiegame #gamedev'

VIDEOS = [
    {
        'slug': '01_taking_care_of_him_19s', 'file': 'evochi_v4_01_taking_care_of_him_19s.mp4', 'len': 19, 'day': 'Fri',
        'title': '"I thought I was taking care of him" (your line; the emotional payoff tied to the mechanic)',
        'why': 'Mochi is walking in the meadow from frame 0 with the step counter ticking, so the first second shows a creature and the mechanic at once. The middle shows care (a poke, a berry), a week of walk days and his first evolution; the turn ("turns out... he\'s helping me take care of myself too") lands on a dusk walk as the counter passes the daily goal. Ends on a question anyone can answer with a number.',
        'vo': [
            (0.0, 3.6, 'I made a little creature that grows when I walk.'),
            (3.6, 7.4, 'I thought I was taking care of him.'),
            (7.4, 10.6, 'Turns out...'),
            (10.6, 15.0, "he's helping me take care of myself too."),
            (15.0, 19.0, 'How many steps did you get today?'),
        ],
        'ending': 'question ("how many steps did you get today?")',
        'yt_title': 'I thought I was taking care of him. Turns out he\'s taking care of me',
        'yt_desc': f'I made a little creature that grows when I walk. How many steps did you get today?\n\nEvochi is a cozy virtual pet raised by your real step count. Beta waitlist: https://{LINK}\n\n{TAGS}',
        'tiktok': f'I thought I was taking care of him 🥲 how many steps did you get today?\n\n{TAGS} #selfcare #hotgirlwalk',
        'ig': f'I made a little creature that grows when I walk. I thought I was taking care of him. Turns out, he\'s helping me take care of myself too.\n\nHow many steps did you get today? 👇\n\n{TAGS} #selfcare #wellness #digitalpet',
        'x': "I made a little creature that grows when I walk.\n\nI thought I was taking care of him. turns out he's helping me take care of myself too.\n\nhow many steps did you get today?",
        'pin': f'today: 8,214 steps (Mochi made me take the long way home). beta waitlist: {LINK}',
        'cover': 'the dusk walk with the counter on "7,000 ✓" (about 12.6 s)',
    },
    {
        'slug': '02_evolves_when_i_walk_18s', 'file': 'evochi_v4_02_evolves_when_i_walk_18s.mp4', 'len': 18, 'day': 'Fri',
        'title': '"I made a virtual pet that evolves when I walk" (analyst hook + your "when I was a kid" lines)',
        'why': 'The evolution happens in the first second: Mochi is already glowing at frame 0 and becomes the Elder at 0.95 s. Then your lines over the game\'s real hatch and real evolution footage, and it ends on one more evolution, as you asked. This is the "show the evolution immediately" test.',
        'vo': [
            (0.0, 3.0, 'I made a virtual pet that evolves when I walk.'),
            (3.0, 6.6, 'When I was a kid, I loved raising virtual pets.'),
            (6.6, 10.0, "Now I'm making one that grows alongside you."),
            (10.0, 14.2, 'Every walk helps him become something new.'),
            (14.6, 18.0, 'What would you name yours?'),
        ],
        'ending': 'evolution, then question ("what would you name yours?")',
        'yt_title': 'I made a virtual pet that evolves when I go on walks',
        'yt_desc': f'When I was a kid I loved raising virtual pets. Now I\'m making one that grows alongside you. What would you name yours?\n\nBeta waitlist: https://{LINK}\n\n{TAGS}',
        'tiktok': f'I made a virtual pet that evolves when I go on walks 🥚➡️🦎 what would you name yours?\n\n{TAGS} #nostalgia',
        'ig': f'I made a virtual pet that evolves when I walk.\n\nWhen I was a kid, I loved raising virtual pets. Now I\'m making one that grows alongside you. Every walk helps him become something new.\n\nWhat would you name yours? 👇\n\n{TAGS} #nostalgia #digitalpet',
        'x': 'I made a virtual pet that evolves when I walk.\n\nwhat would you name yours?',
        'pin': f'mine is called Mochi (obviously). the egg you pick decides his colour. beta waitlist: {LINK}',
        'cover': 'the first second, the glow right before the evolution (0.6 s)',
    },
    {
        'slug': '03_week1_7_days_of_walking_20s', 'file': 'evochi_v4_03_week1_7_days_of_walking_20s.mp4', 'len': 20, 'day': 'Fri',
        'title': '"Mochi\'s Walk, Week 1" (a weekly series: the same Mochi, one week older each episode)',
        'why': 'The analyst\'s second hook made into a series, which gives people a reason to follow. Day 1 the egg wobbles, day 2 it cracks, day 3 it hatches, days 4 and 5 he walks, day 6 is a protected rest day, day 7 he evolves. The stamp in the corner ("WEEK 1 · DAY 3") is the series brand. Week 2 next Friday ends on the Elder, or keep it slower and make him evolve at week 4.',
        'vo': [
            (0.0, 3.2, 'This little guy started as an egg.'),
            (3.2, 6.6, "Here's seven days of walking."),
            (6.6, 10.4, 'He grows with every step.'),
            (10.4, 13.6, 'Day six: rest day. He napped. No penalty.'),
            (13.6, 16.6, 'Day seven: level ten.'),
            (16.6, 20.0, 'Week two is next Friday. What does he become?'),
        ],
        'ending': 'series cliffhanger ("week 2 is next friday. what does he become?")',
        'yt_title': "This little guy started as an egg. Here's 7 days of walking (Week 1)",
        'yt_desc': f'Mochi\'s Walk, week 1: egg on day 1, hatched on day 3, a rest day on day 6, level 10 on day 7. Week 2 next Friday. What does he become?\n\nBeta waitlist: https://{LINK}\n\n{TAGS}',
        'tiktok': f'7 days of walking with Mochi 🥚 week 2 next friday. what does he become?\n\n{TAGS} #series #part1',
        'ig': f'This little guy started as an egg. Here\'s 7 days of walking.\n\nDay 6 was a rest day (he napped, no penalty). Day 7: level 10.\n\nWeek 2 is next Friday. What does he become? 👇\n\n{TAGS} #digitalpet',
        'x': "this little guy started as an egg. here's 7 days of walking.\n\nweek 2 next friday. what does he become?",
        'pin': f'guesses for week 2? (hint: there are three forms.) beta waitlist: {LINK}',
        'cover': 'the cracked, glowing egg (4.3 s)',
    },
    {
        'slug': '04_i_miss_the_games_B_22s', 'file': 'evochi_v4_04_i_miss_the_games_B_22s.mp4', 'len': 22, 'day': 'Fri',
        'title': '"I miss the games..." re-cut: the controlled test against the video that\'s already live',
        'why': 'Seconds 4.2 to 22 are frame-for-frame the same as the live version (same captions, same music, same sound). Only the first 4.2 seconds change: instead of Mochi sitting on a cream card, he evolves in the meadow under the same first line. If "Stayed to watch" goes up from 42%, the opening was the problem; the body was already holding (69% average viewed).',
        'vo': [
            (0.0, 4.2, 'I miss the games where you actually cared about your little creature.'),
            (4.2, 7.0, "So I'm making one."),
            (7.0, 10.2, 'It hatches from an egg you pick.'),
            (10.2, 13.4, 'It grows when you walk.'),
            (13.4, 16.0, 'It gets sleepy when you stop...'),
            (16.0, 18.8, "...and so happy when you're back."),
            (18.8, 22.0, 'What was yours called?'),
        ],
        'ending': 'question ("what was yours called?"), same as the live version',
        'yt_title': "I miss the games where you actually cared about your little creature, so I'm making one",
        'yt_desc': f'What was yours called? Tell me in the comments.\n\nEvochi is a virtual pet raised by your real steps. Beta waitlist: https://{LINK}\n\n#evochi #tamagotchi #virtualpet #nostalgia #indiegame',
        'tiktok': 'what was yours called? mine was a Tamagotchi named Pip 🥚\n\n#evochi #tamagotchi #virtualpet #nostalgia #90skids #2000skids #indiegame #gamedev #cozygame',
        'ig': 'I miss the games where you actually cared about your little creature. So I\'m making one.\n\nWhat was yours called? 👇\n\n#evochi #tamagotchi #virtualpet #nostalgia #90skids #2000skids #cozygame #indiegame #gamedev #digitalpet',
        'x': "I miss the games where you actually cared about your little creature, so I'm making one.\n\nwhat was yours called?",
        'pin': 'mine was a Tamagotchi called Pip. he died on a school trip 🪦 (Evochi is gentler, I promise: evochigame.com)',
        'cover': 'same cover as the live version, so only the opening differs',
    },
    {
        'slug': '05_never_went_away_18s', 'file': 'evochi_v4_05_never_went_away_18s.mp4', 'len': 18, 'day': 'Sat',
        'title': '"That little part of you never really went away" (your line; nostalgia, slow reveal)',
        'why': 'Your three lines over a night meadow with Mochi asleep in his nest (so there\'s a creature on screen from frame 0). On "never really went away" the sun comes up and he wakes. Then your reveal: Mochi walking around the meadow, "this is Mochi, he grows when you walk." Ends on a three-way choice, which is the easiest comment there is.',
        'vo': [
            (0.0, 3.6, 'You used to take care of little virtual pets.'),
            (3.6, 6.8, 'Somewhere along the way, you grew up.'),
            (6.8, 10.6, 'But that little part of you never really went away.'),
            (10.6, 14.4, 'This is Mochi. He grows when you walk.'),
            (14.4, 18.0, 'Tamagotchi, Neopets, or Nintendogs?'),
        ],
        'ending': 'question ("Tamagotchi, Neopets or Nintendogs?")',
        'yt_title': 'That little part of you never really went away',
        'yt_desc': f'You used to take care of little virtual pets. Somewhere along the way, you grew up. Tamagotchi, Neopets or Nintendogs?\n\nEvochi is a cozy virtual pet raised by your real step count. Beta waitlist: https://{LINK}\n\n{TAGS} #nostalgia',
        'tiktok': f'tamagotchi, neopets or nintendogs? 🥚\n\n{TAGS} #nostalgia #90skids #2000skids',
        'ig': f'You used to take care of little virtual pets. Somewhere along the way, you grew up. But that little part of you never really went away.\n\nTamagotchi, Neopets or Nintendogs? 👇\n\n{TAGS} #nostalgia #90skids #2000skids',
        'x': 'you used to take care of little virtual pets. somewhere along the way, you grew up.\n\nbut that little part of you never really went away.\n\ntamagotchi, neopets or nintendogs?',
        'pin': f'Tamagotchi. every time. (Mochi is the grown-up version: {LINK})',
        'cover': 'sunrise as Mochi wakes (about 9.3 s)',
    },
    {
        'slug': '06_mochi_has_moods_15s', 'file': 'evochi_v4_06_mochi_has_moods_15s.mp4', 'len': 15.5, 'day': 'Sat',
        'title': '"Mochi has moods" (character personality, fast cuts)',
        'why': 'Five two-second moods (goal hit, rest day, poked, snack time, you came back), each a real thing the game does, then a numbered 2x2 grid: "which one are you today?" Comments become numbers, and the rewatch to pick one helps average viewed.',
        'vo': [
            (0.0, 2.6, 'Mochi has moods.'),
            (2.6, 4.6, 'Goal hit.'),
            (4.6, 6.6, 'Rest day.'),
            (6.6, 8.6, 'You poked him.'),
            (8.6, 10.6, 'Snack time.'),
            (10.6, 12.6, 'You came back.'),
            (12.6, 15.5, 'Which one are you today?'),
        ],
        'ending': 'question with a numbered grid ("which one are you today?")',
        'yt_title': 'Mochi has moods. Which one are you today?',
        'yt_desc': f'Goal hit, rest day, poked, snack time, you came back. 1, 2, 3 or 4?\n\nEvochi is a cozy virtual pet raised by your real step count. Beta waitlist: https://{LINK}\n\n{TAGS}',
        'tiktok': f'which one are you today? 1, 2, 3 or 4 👇\n\n{TAGS} #mood #relatable',
        'ig': f'Mochi has moods. Which one are you today? 1, 2, 3 or 4 👇\n\n{TAGS} #mood #digitalpet',
        'x': 'Mochi has moods.\n\nwhich one are you today? 1, 2, 3 or 4',
        'pin': f'it\'s a 2 for me today. beta waitlist: {LINK}',
        'cover': 'the 2x2 mood grid (14 s)',
    },
]

README = f"""
EVOCHI VIDEO PACK v4: Mochi in the world
========================================

What the first two Shorts told us
---------------------------------
Shorts counts every swipe-past as a view, and "engaged views" are the people who stayed, so
engaged / views is roughly the "Stayed to watch" number:
  "This is Mochi"     98 / 332 = 30% stayed
  "I miss the games"  19 / 46  = 41% stayed (Studio says 42.2%), and those who stayed watched 69%
Healthy Shorts keep 60 to 80%. Both openings lose most people in the first second or two, and both
open the same way: a model on a plain cream card, which reads as a product render, not a living
thing. The bodies hold. The first video's extra distribution is mostly that it went up first and
has had longer; the evolution in it is a plausible second reason, which video 04 tests.

What changed
------------
1. Mochi is in the meadow and moving at frame 0 of every video. No cream cards in the opening.
2. Evolutions and hatches happen early (video 02 at 0.95 s, video 04 at 0.9 s).
3. Your three lines are in (01 and 05 word for word; your "when I was a kid" line is merged into 02).
4. A weekly series (03, "Mochi's Walk, week N") so there's a reason to follow.
5. Every ending is a question you can answer in one word or one number. No waitlist card: the link
   goes in the pinned comment and the bio.

The videos
----------
01_taking_care_of_him_19s      Your favourite. "I thought I was taking care of him."
02_evolves_when_i_walk_18s     Analyst hook + your "when I was a kid". Evolution in second one.
03_week1_7_days_of_walking_20s Series ep. 1. Egg on day 1, level 10 on day 7.
04_i_miss_the_games_B_22s      The A/B test: the live video with only the first 4.2 s changed.
05_never_went_away_18s         Your nostalgia line. Night, sunrise, Mochi wakes, then walks.
06_mochi_has_moods_15s         Personality. Five moods, then "which one are you today? 1-4".

Each folder: the MP4 (1080x1920, 30 fps, music + game sounds), voiceover.txt (lines with timings if
you want to record yourself), captions.srt, post_copy.txt (YouTube title + description, TikTok,
Instagram, X, the pinned comment, and which frame to use as the cover).

Posting plan
------------
Friday (tomorrow), at least three hours apart:
   9:00   04  I miss the games (B)   POST AT THE SAME HOUR THE ORIGINAL WENT UP if you can; same title
                                     and description as the original, so the opening is the only
                                     difference
  12:00   01  Taking care of him
  15:00   02  Evolves when I walk
  19:00   03  Week 1                 (Fridays are the series slot from now on)
Saturday:
  11:00   05  Never went away
  17:00   06  Mochi has moods

Don't delete or re-upload the two live videos. Shorts can pick up a second wave days later.

How to read the results (after 48 hours, not before)
----------------------------------------------------
YouTube Studio > the Short > Analytics > Engagement:
  - Stayed to watch (the % who didn't swipe away). This is the opening's score.
  - Average percentage viewed. This is the body's score.
  - Comments, and subscribers gained.
The test: 04 vs the live "I miss the games". Same body, so any difference in Stayed to watch is the
opening. If 04 is clearly higher (say 55%+ vs 42%), every future video opens in the world.
Then compare 01, 02, 03, 05, 06 on Stayed to watch: the winner's hook style is what the next batch
leans on. results_tracker.csv has a row per video; fill it in on Sunday.

Don't judge on views. With two subscribers, views are mostly YouTube's test batch, and one lucky
batch can triple a number.

Reply to every comment in the first hour, ideally with a question back. Two comments on 46 views
was the best signal so far.

Week 2 of the series
--------------------
Same template, next Friday: day 8 to 14, ending on whatever you want to reveal (the Elder at
level 25, or keep him a Juvenile and save the Elder for week 4). Ask me for "Week 2" and it's an
hour of work; the comp has a cut per week.
"""

TRACKER = 'video,platform,posted_at,views,engaged_views,stayed_to_watch_pct,avg_pct_viewed,avg_view_duration_s,comments,likes,shares,subs_gained,waitlist_signups_that_day,notes\n'
for v in VIDEOS:
    for p in ('YouTube', 'TikTok', 'Instagram'):
        TRACKER += f"{v['slug']},{p},,,,,,,,,,,,\n"
TRACKER += 'v3_02_i_miss_the_games (live original),YouTube,,46,19,42.2,68.9,15,2,,,0,,baseline for 04\n'
TRACKER += 'v3_01_this_is_mochi (live),YouTube,,332,98,,,,,,,1,,baseline\n'


def main():
    if os.path.exists(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    write(os.path.join(OUT, 'README.txt'), README)
    write(os.path.join(OUT, 'results_tracker.csv'), TRACKER)
    for v in VIDEOS:
        d = os.path.join(OUT, v['slug'])
        os.makedirs(d)
        src = os.path.join(VID, v['file'])
        if os.path.exists(src):
            shutil.copy(src, os.path.join(d, v['file']))
        else:
            print('missing video', src)
        vo = [f"{v['title']}\nLength: {v['len']} s. Ending: {v['ending']}. Post: {v['day']}.\n\nWhy this video exists:\n{v['why']}\n",
              'VOICE-OVER (optional; the captions carry the lines, so the video works muted)',
              'Record in a plain, warm dev-diary voice. No announcer energy. Leave the pauses in.\n']
        for t0, t1, line in v['vo']:
            vo.append(f'{t0:5.1f}s - {t1:5.1f}s   {line}')
        write(os.path.join(d, 'voiceover.txt'), '\n'.join(vo))
        srt = []
        for i, (t0, t1, text) in enumerate(v['vo'], 1):
            srt.append(f'{i}\n{srt_time(t0)} --> {srt_time(t1)}\n{text}\n')
        write(os.path.join(d, 'captions.srt'), '\n'.join(srt))
        pc = f"""{v['title']}

YOUTUBE SHORTS
--------------
Title: {v['yt_title']}
Description:
{v['yt_desc']}

TIKTOK caption
--------------
{v['tiktok']}

INSTAGRAM REELS caption
-----------------------
{v['ig']}

X (Twitter) post
----------------
{v['x']}

PINNED COMMENT (post it yourself right after uploading, on every platform that allows it)
-----------------------------------------------------------------------------------------
{v['pin']}

COVER FRAME (TikTok and Instagram let you pick one)
---------------------------------------------------
{v['cover']}

Notes
-----
- Upload the MP4 natively on each platform (don't cross-share links or watermarked downloads).
- Keep the original sound. The hatch and evolve sounds are part of the hook.
- No waitlist card in the video on purpose: the link lives in the pinned comment and your bio.
"""
        write(os.path.join(d, 'post_copy.txt'), pc)
    print('pack written to', OUT)


if __name__ == '__main__':
    main()

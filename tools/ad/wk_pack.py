"""Assembles the week-43 upload pack: one folder per day with the MP4 (named as in the tracker's upload
plan), captions.srt and post_copy.txt (YouTube title, description, pinned comment, cover frame), plus a
README with the schedule and what to send back.

python3 wk_pack.py VIDEO_DIR OUT_DIR      (VIDEO_DIR holds evochi_wk43_*.mp4)
"""
import os
import shutil
import sys

VID, OUT = sys.argv[1], sys.argv[2]
LINK = 'evochigame.com'
TAGS = '#cozygames #evochi #virtualpet #walking #indiegame'


def srt_time(t):
    ms = int(round(max(0.0, t) * 1000))
    return '%02d:%02d:%02d,%03d' % (ms // 3600000, ms // 60000 % 60, ms // 1000 % 60, ms % 1000)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text.strip('\n') + '\n')


VIDEOS = [
    {
        'folder': '1_Tue_Oct20_she_followed_me_home', 'file': 'evochi_wk43_01_she_followed_me_home.mp4', 'when': 'Tue Oct 20, 12:00 ET',
        'title': 'I walked 1,500 steps and she followed me home 🌸 #cozygames #evochi',
        'desc': f"I walked 1,500 steps to some old ruins and something was watching me. You don't fight it, you earn its trust. It has a favourite snack.\n\nTart, stew or bun? 1, 2 or 3 👇\n\nEvochi is a cozy virtual pet that only grows when you walk. Beta waitlist: https://{LINK}\n\n{TAGS} #petalune",
        'pin': f"1, 2 or 3? (she's picky.) beta waitlist: {LINK}",
        'cover': 'Petalune beside the nest at dusk (about 1.0 s)',
        'caps': [(0.0, 2.2, 'she followed me home.'), (2.2, 4.0, 'I walked 1,500 steps to old ruins'), (4.0, 4.9, 'something was watching me'),
                 (5.8, 7.8, "you don't fight it."), (7.8, 9.8, 'it has a favourite snack.'), (9.8, 11.4, 'and then she trusted me.'), (12.4, 14.0, 'tart, stew or bun?')],
    },
    {
        'folder': '2_Wed_Oct21_mochi_now', 'file': 'evochi_wk43_02_mochi_now_14s.mp4', 'when': 'Wed Oct 21, 12:00 ET',
        'title': 'All I did was walk. This is Mochi now 👑 #cozygames',
        'desc': f"30 days of walking, nothing else. Day 1 he was a tiny Eggling, day 30 he's an Elder at level 25, and he waited for me every single day.\n\nHow many steps did you walk today? 👇\n\nEvochi is a cozy virtual pet that only grows when you walk. Beta waitlist: https://{LINK}\n\n{TAGS}",
        'pin': f"I'm on 4,800 so far today. you? beta waitlist: {LINK}",
        'cover': 'the crowned Elder on parchment (about 1.5 s)',
        'caps': [(0.0, 2.2, '30 days of walking did this.'), (2.2, 4.0, 'this was him on day 1'), (4.0, 6.6, "I didn't train him. I just walked."),
                 (6.6, 8.4, 'day 7: level 10'), (8.4, 10.4, 'day 30: level 25'), (10.4, 12.4, 'he waited for me every single day'),
                 (12.4, 14.0, 'how many steps did you walk today?')],
    },
    {
        'folder': '3_Thu_Oct22_walk_to_them', 'file': 'evochi_wk43_03_walk_to_them.mp4', 'when': 'Thu Oct 22, 12:00 ET',
        'title': "In my game you don't fight monsters. You walk to them 🌿 #cozygames #evochi",
        'desc': f"Nobody gets hurt in my battles. When Mochi's tired he just sits down for a bit. The thing in the vines isn't a monster, it's a sprout that forgot the sun, so you bring it back. Nobody faints, nobody loses.\n\nHow far would you walk for one? 👇\n\nBeta waitlist: https://{LINK}\n\n{TAGS} #gamedesign",
        'pin': f"this one was 1,500 steps away. beta waitlist: {LINK}",
        'cover': 'the restored Sprout and Mochi in golden light (about 1.2 s)',
        'caps': [(0.0, 2.2, 'nobody gets hurt in my battles.'), (2.2, 4.2, 'he just gets tired.'), (4.2, 6.4, 'so he sits down for a bit.'),
                 (6.4, 8.6, "it's a sprout that forgot the sun."), (8.6, 9.8, 'so you bring it back.'), (9.8, 11.0, 'nobody faints. nobody loses.'),
                 (12.4, 14.0, 'how far would you walk for one?')],
    },
    {
        'folder': '4_Fri_Oct23_pov_woke_something_up', 'file': 'evochi_wk43_04_pov_woke_something_up.mp4', 'when': 'Fri Oct 23, 12:00 ET',
        'title': 'POV: you walked 3,000 steps and woke something up 👀 #cozygames',
        'desc': f"At the end of the trail there's an old gate, and something asleep in it. It remembers you. It isn't a monster, it's a guardian that forgot its light, so you help it remember.\n\nWhat was it guarding? 👇\n\nBeta waitlist: https://{LINK}\n\n{TAGS} #bossfight",
        'pin': f"wrong answers only. beta waitlist: {LINK}",
        'cover': 'both eyes lit in the dark gate, dust falling (about 6.6 s)',
        'caps': [(0.0, 2.2, 'POV: you walked 3,000 steps…'), (2.2, 4.4, '…and found an old gate'), (4.4, 7.4, 'and something woke up.'),
                 (7.4, 8.3, 'it remembers you.'), (9.0, 10.4, 'it forgot its light.'), (10.4, 11.8, 'so you help it remember.'),
                 (12.6, 14.0, 'what was it guarding?')],
    },
    {
        'folder': '5_Sat_Oct24_week2_friend', 'file': 'evochi_wk43_05_week2_friend.mp4', 'when': 'Sat Oct 24, 12:00 ET',
        'title': 'Week 2 of walking: he made a friend 🌸 #cozygames #evochi',
        'desc': f"Mochi's Walk, days 8 to 14. He's a Juvenile now and walks further, the Trail Guild had a job for us, and the ruins found us. Day 12: she liked the tart.\n\nWeek 3: the old gate. Should he go? Yes or no 👇\n\nBeta waitlist: https://{LINK}\n\n{TAGS} #mochiswalk",
        'pin': f"yes or no? (if you saw Friday's video: no spoilers.) beta waitlist: {LINK}",
        'cover': 'Petalune beside the nest with the WEEK 2 stamp (about 1.0 s)',
        'caps': [(0.0, 2.2, 'week 2: he made a friend.'), (2.2, 4.2, "he's a Juvenile now. he walks further."), (4.2, 6.0, 'the Guild had a job for us'),
                 (6.0, 7.6, 'day 11: we found the ruins'), (7.6, 8.5, 'and the ruins found us.'), (9.2, 10.4, 'she was shy at first.'), (10.4, 11.8, 'day 12: she liked the tart.'),
                 (12.6, 14.0, 'week 3: the gate. should he go?')],
    },
    {
        'folder': '6_Sun_Oct25_day1_vs_day30', 'file': 'evochi_wk43_06_day1_vs_day30.mp4', 'when': 'Sun Oct 25, 12:00 ET',
        'title': 'Day 1 vs day 30. All I did was walk 🥚→👑 #cozygames',
        'desc': f"Same pet, 30 days apart. I just walked. I skipped a few days and he didn't mind.\n\nWhich day are you on? 👇\n\nEvochi is a cozy virtual pet that only grows when you walk. Beta waitlist: https://{LINK}\n\n{TAGS}",
        'pin': f"I skipped days 19 to 21. he didn't mind. beta waitlist: {LINK}",
        'cover': 'the day 1 / day 30 split (about 1.0 s)',
        'caps': [(0.0, 2.4, 'day 1 vs day 30'), (2.4, 4.36, 'same pet. I just walked.'), (4.36, 6.6, 'day 7: level 10'),
                 (6.6, 9.5, "skipped a few days. he didn't mind."), (10.22, 12.6, 'day 30: level 25'), (12.6, 14.0, 'which day are you on?')],
    },
    {
        'folder': '7_Mon_Oct26_pov_waits_up', 'file': 'evochi_wk43_07_pov_waits_up.mp4', 'when': 'Mon Oct 26, 12:00 ET',
        'title': "POV: he waits up when you're late from your walk 🌙 #cozygames",
        'desc': f"11:48 PM, 900 steps short, and he's still up. So you go out one more time. 7,000. Now he can sleep.\n\nDid you finish your walk today? 👇\n\nEvochi is a cozy virtual pet that only grows when you walk. Beta waitlist: https://{LINK}\n\n{TAGS}",
        'pin': f"how many steps short are you right now? beta waitlist: {LINK}",
        'cover': 'Mochi awake in the nest at night (about 0.8 s)',
        'caps': [(0.0, 2.4, "POV: it's late and he's still up"), (2.4, 4.6, "you didn't finish your walk yet"), (4.6, 7.0, 'so you go out one more time'),
                 (7.0, 9.0, '7,000. he was waiting for this.'), (9.0, 11.6, 'now he can sleep.'), (11.6, 14.0, 'did you finish your walk today?')],
    },
]

README = f"""
EVOCHI: A WEEK OF SHORTS (Tue Oct 20 to Mon Oct 26)
===================================================

Seven Shorts, 14 seconds each, one a day at 12:00 ET. They follow what your first week's numbers said:
short (your 14-15 s videos held 79-87%), walking in the title, a result or a POV in the first frame,
and a question at the end that loops back to the start (the looping "This is Mochi now" was watched
3.6 times over on average). The encounter footage is from the redesigned
encounter screens and fights.

Each folder has the MP4 (1080x1920, 30 fps, with music and the game's sounds), post_copy.txt (title,
description, pinned comment, cover frame) and captions.srt (optional: the captions are already burned
into the video).

Schedule
--------
""" + '\n'.join(f"{v['when']:<24} {v['title']}" for v in VIDEOS) + """

Uploading
---------
- Upload from the YouTube app or Studio as a Short; paste the title and description from post_copy.txt.
- Post the pinned comment yourself right after it goes up, and pin it.
- Reply to comments in the first hour, ideally with a question back.

Send me your next YouTube Studio export (Analytics > Advanced mode > Export > CSV, or the zip) whenever
you like. I'll add it to the tracker and mark each of these as posted once it shows up.
"""


def main():
    if os.path.exists(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    write(os.path.join(OUT, 'README.txt'), README)
    for v in VIDEOS:
        d = os.path.join(OUT, v['folder'])
        os.makedirs(d)
        src = os.path.join(VID, v['file'])
        if os.path.exists(src):
            shutil.copy(src, os.path.join(d, v['file']))
        else:
            print('missing video', src)
        write(os.path.join(d, 'captions.srt'), '\n'.join(f'{i}\n{srt_time(a)} --> {srt_time(b)}\n{text}\n' for i, (a, b, text) in enumerate(v['caps'], 1)))
        write(os.path.join(d, 'post_copy.txt'), f"""POST: {v['when']}

TITLE (YouTube Shorts)
{v['title']}

DESCRIPTION
{v['desc']}

PINNED COMMENT (post it yourself right after uploading)
{v['pin']}

COVER FRAME (pick it in the YouTube app when uploading)
{v['cover']}
""")
    print('packed', OUT)


main()

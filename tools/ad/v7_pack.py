"""Assembles the v7 video pack (the encounters, cut to the v6 recipe): one folder per video with the
MP4, voice-over script, captions (.srt) and post copy for YouTube Shorts, TikTok, Instagram Reels and
X, plus a README with the posting plan and a results tracker.

python3 v7_pack.py VIDEO_DIR OUT_DIR      (VIDEO_DIR holds evochi_v7_*.mp4)
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
        'slug': '01_she_followed_us_home_17s', 'file': 'evochi_v7_01_she_followed_us_home_17s.mp4', 'len': 17, 'day': 'Sat 11:00',
        'title': '"She followed us home" (the first encounter: Petalune, befriended)',
        'why': 'Result first: frame 0 is Petalune asleep beside Mochi\'s nest at dusk, which nobody has seen. Then the trail up to the ruins (a new cinematic), the game\'s own intro ("something was watching us"), the one mechanic in six words ("you don\'t fight it"), the snack as proof, the trust as the human line, and a question with three answers that loops back into the opening frame.',
        'vo': [
            (0.0, 2.6, 'She followed us home.'),
            (2.6, 5.0, 'The trail ended at some old ruins.'),
            (5.0, 7.2, 'Something was watching us.'),
            (7.2, 9.6, "You don't fight it."),
            (9.6, 12.0, 'It has a favourite snack.'),
            (12.0, 14.4, 'And then she trusted us.'),
            (14.4, 17.0, 'Tart, stew or bun?'),
        ],
        'ending': 'question with three numbered answers ("tart, stew or bun?")',
        'yt_title': 'Something was watching us on the trail. Now she follows us home',
        'yt_desc': f'The first Evochi encounter: you don\'t fight it, you earn its trust. Tart, stew or bun?\n\nEvochi is a cozy virtual pet raised by your real step count. Beta waitlist: https://{LINK}\n\n{TAGS} #petalune',
        'tiktok': f'something was watching us 👀 you don\'t fight it, you earn its trust. tart, stew or bun?\n\n{TAGS} #cozygaming #wholesome',
        'ig': f'The trail ended at some old ruins, and something was watching us.\n\nYou don\'t fight it. You earn its trust. It has a favourite snack. And then she followed us home.\n\nTart, stew or bun? 1, 2 or 3 👇\n\n{TAGS} #cozygaming #wholesome #digitalpet',
        'x': "something was watching us on the trail.\n\nyou don't fight it. you earn its trust.\n\ntart, stew or bun?",
        'pin': f'2, carrot stew. she\'s picky. beta waitlist: {LINK}',
        'cover': 'the tart in mid-air, Petalune\'s eyes on it (about 10.1 s)',
    },
    {
        'slug': '02_nobody_gets_hurt_17s', 'file': 'evochi_v7_02_nobody_gets_hurt_17s.mp4', 'len': 17.5, 'day': 'Fri 12:00',
        'title': '"Nobody gets hurt in my battles" (the design hook: the Hollow Sprout, restored)',
        'why': 'The contradiction hook. Frame 0 is the restored Sprout glowing green beside Mochi (the result), the caption says nobody gets hurt, and the next three seconds show a tendril hitting Mochi and resolve it: he just gets tired, so he sits down. The Hollow line is the lore in seven words, the restoration is the proof, "nobody faints, nobody loses" is the human line, and the question asks for one word.',
        'vo': [
            (0.0, 2.4, 'Nobody gets hurt in my battles.'),
            (2.4, 4.8, 'He just gets tired.'),
            (4.8, 7.6, 'So he sits down for a bit.'),
            (7.6, 10.4, "It's a sprout that forgot the sun."),
            (10.4, 13.2, 'So you bring it back.'),
            (13.2, 14.8, 'Nobody faints. Nobody loses.'),
            (14.8, 17.5, "It's called Soothe. What would you call it?"),
        ],
        'ending': 'one-word question ("your name for Soothe?")',
        'yt_title': 'I made a battle system where nobody gets hurt',
        'yt_desc': f'When your Evochi is tired, he sits down for a bit. The thing in the vines isn\'t a monster, it\'s a sprout that forgot the sun. The sitting-down move is called Soothe. What would you call it?\n\nBeta waitlist: https://{LINK}\n\n{TAGS} #gamedesign',
        'tiktok': f'I made a battle system where nobody gets hurt 🌱 the sitting-down move is called Soothe. what would you call it?\n\n{TAGS} #gamedesign #cozygaming',
        'ig': f'Nobody gets hurt in my battles. When he\'s tired, he sits down for a bit.\n\nThe thing in the vines isn\'t a monster. It\'s a sprout that forgot the sun. So you bring it back. Nobody faints, nobody loses.\n\nThe sitting-down move is called Soothe. What would you call it? 👇\n\n{TAGS} #gamedesign #cozygaming #wholesome',
        'x': "I made a battle system where nobody gets hurt.\n\nwhen he's tired, he sits down for a bit. the move is called Soothe.\n\nwhat would you call it?",
        'pin': f'I almost called it "Nap". beta waitlist: {LINK}',
        'cover': 'Mochi sitting with the hearts and "+30 Energy" (about 5.5 s)',
    },
    {
        'slug': '03_i_woke_something_up_18s', 'file': 'evochi_v7_03_i_woke_something_up_18s.mp4', 'len': 18, 'day': 'Tue 18:00',
        'title': '"I woke something up" (the Sentinel\'s awakening: the story boss)',
        'why': 'The cinematic one, and the answer to the yes/no that video 04 asks. Frame 0 is the restored guardian lit mint at night (the result). Then the gate at dusk with the Sentinel slumped in it like rubble, the rumble, the dust, its eyes lighting one by one (a new Blender plate with the Sentinel modelled into the scene), the game\'s own awakening with Mochi\'s flinch, the Lantern Tonic and the phase-two lash, the restoration, and the question. The marimba steps aside for the awakening: only the rumble and the sting.',
        'vo': [
            (0.0, 2.4, 'I woke something up.'),
            (2.4, 5.0, 'It was asleep in the old gate.'),
            (5.0, 8.6, 'For a very long time.'),
            (8.6, 10.6, 'And it remembers you.'),
            (10.6, 13.4, "It's a guardian that forgot its light."),
            (13.4, 15.6, 'So you help it remember.'),
            (15.6, 18.0, 'What do you think it was guarding?'),
        ],
        'ending': 'open question ("what was it guarding?")',
        'yt_title': 'I woke something up at the end of the trail',
        'yt_desc': f'It was asleep in the old gate for a very long time, and it remembers you. It isn\'t a monster, it\'s a guardian that forgot its light. What do you think it was guarding?\n\nBeta waitlist: https://{LINK}\n\n{TAGS} #bossfight',
        'tiktok': f'I woke something up at the end of the trail 👁️👁️ what do you think it was guarding?\n\n{TAGS} #bossfight #cozygaming',
        'ig': f'There\'s something at the end of the trail. It\'s been asleep in the old gate for a very long time, and it remembers you.\n\nIt isn\'t a monster. It\'s a guardian that forgot its light. So you help it remember.\n\nWhat do you think it was guarding? 👇\n\n{TAGS} #bossfight #cozygaming #indiedev',
        'x': "I woke something up at the end of the trail.\n\nit isn't a monster. it's a guardian that forgot its light.\n\nwhat do you think it was guarding?",
        'pin': f'wrong answers only. (the real answer is in week 4.) beta waitlist: {LINK}',
        'cover': 'both eyes lit in the dark gate, dust falling (about 8.0 s)',
    },
    {
        'slug': '04_week2_he_made_a_friend_17s', 'file': 'evochi_v7_04_week2_he_made_a_friend_17s.mp4', 'len': 17.5, 'day': 'Fri 19:00',
        'title': '"Mochi\'s Walk, week 2: he made a friend" (the series)',
        'why': 'The Friday series slot, days 8 to 14 in the stamp. Result first: Petalune at the nest on day 14. Then the Juvenile walking further, the first Trail Guild job, the trail up to the ruins, the encounter (the nudge, the head tilt, the tart) and the nest again, with a yes/no vote that sets up the Sentinel. If week 2 already went up, this is week 3 with no other change.',
        'vo': [
            (0.0, 2.6, 'Week two. He made a friend.'),
            (2.6, 5.0, "He's a Juvenile now, and he walks further."),
            (5.0, 7.4, 'The Trail Guild had a job for us.'),
            (7.4, 9.8, 'Day eleven: we found the ruins.'),
            (9.8, 12.2, 'And the ruins found us.'),
            (12.2, 14.8, 'Day twelve: she liked the tart.'),
            (14.8, 17.5, "Week three: there's something at the old gate. Should he go?"),
        ],
        'ending': 'yes / no vote ("should he go?")',
        'yt_title': "Mochi's Walk, week 2: he made a friend",
        'yt_desc': f'Days 8 to 14: he\'s a Juvenile now, the Trail Guild had a job for us, and the ruins found us. Week 3: there\'s something at the old gate. Should he go? Yes or no.\n\nBeta waitlist: https://{LINK}\n\n{TAGS} #mochiswalk',
        'tiktok': f'week 2: he made a friend 🌸 week 3: there\'s something at the old gate. should he go? yes or no\n\n{TAGS} #mochiswalk #cozygaming',
        'ig': f'Mochi\'s Walk, week 2. He\'s a Juvenile now and he walks further. The Trail Guild had a job for us: something shy in the old ruins. Day 11 we found the ruins, and the ruins found us. Day 12, she liked the tart. Day 14, she visits the nest.\n\nWeek 3: there\'s something at the old gate. Should he go? Yes or no 👇\n\n{TAGS} #mochiswalk #cozygaming #digitalpet',
        'x': "Mochi's Walk, week 2: he made a friend.\n\nweek 3: there's something at the old gate. should he go? yes or no",
        'pin': f'votes close Sunday. beta waitlist: {LINK}',
        'cover': 'Petalune beside the nest with the DAY 14 stamp (about 1.5 s)',
    },
]

README = f"""
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
"""

TRACKER = 'video,platform,posted_at,views,engaged_views,stayed_to_watch_pct,avg_pct_viewed,avg_view_duration_s,comments,likes,shares,subs_gained,waitlist_signups_that_day,notes\n'
for v in VIDEOS:
    for p in ('YouTube', 'TikTok', 'Instagram'):
        TRACKER += f"{v['slug']},{p},,,,,,,,,,,,\n"


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
- Keep the original sound: the game's own sounds are in the mix at the moments they happen.
- No waitlist card in the video on purpose: the link lives in the pinned comment and your bio.
"""
        write(os.path.join(d, 'post_copy.txt'), pc)
    print('packed', OUT)


main()

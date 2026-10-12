"""Assembles the hand-holding social pack: one folder per platform, a README in every folder, and a
text file of exact verbiage next to every image or video.

python3 make_social_pack.py RENDERED_IMAGES_DIR REPLY_IMAGES_DIR OUT_DIR [VIDEOS_DIR]
"""
import os
import shutil
import sys

SRC, REPLIES, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
VIDEOS = sys.argv[4] if len(sys.argv) > 4 else None

LINK = '[WAITLIST LINK]'


def put(path, text):
    full = os.path.join(OUT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, 'w') as f:
        f.write(text.strip('\n') + '\n')


def cp(src_name, dest_path, src_dir=None):
    src = os.path.join(src_dir or SRC, src_name)
    full = os.path.join(OUT, dest_path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    shutil.copyfile(src, full)


# ====================================================================== 00 start here
put('README.txt', f"""
EVOCHI SOCIAL PACK
==================
Start here. Everything is sorted by platform, and every image or video has a text file with the
same name that holds the exact words to paste. Every folder has its own README that says what each
file is for and where it goes.

Replace {LINK} with your waitlist page URL everywhere it appears. Nothing else needs editing.

FOLDERS
  00_brand/              voice rules, colours, fonts, and the bios for all platforms in one place
  01_instagram/          profile, highlight covers, 8 feed posts, the carousel, Stories, Reels captions
  02_tiktok/             profile, video captions, photo posts, pinned comment, reply images
  03_youtube/            channel art, description, Shorts titles + descriptions + tags, thumbnails
  04_x_twitter/          profile, header, pinned thread, image posts
  05_calendar/           the four-week posting plan and posting rules
  06_hashtags_replies/   hashtag sets and comment reply templates (shared by all platforms)

ORDER OF OPERATIONS (about an hour)
  1. Register the same handle on all four platforms. Try @evochigame, then @playevochi.
  2. Set up each profile from its profile/ folder: picture, banner, bio, link.
  3. Upload the pinned items first (listed in each platform README).
  4. Follow 05_calendar/four_week_calendar.txt from Monday.
  5. Keep 06_hashtags_replies/reply_templates.txt open while replying to comments.

VIDEOS
  The six videos (two ads, four waitlist videos) are in the separate videos zip, or in the files sent
  earlier in our chat. Their captions, titles and descriptions are in each platform folder under
  videos/. Upload the same MP4 to all four platforms; the words change, the file doesn't.
""")

# ====================================================================== 00 brand
put('00_brand/README.txt', """
00_brand
========
Read this once before writing anything in Evochi's voice.

FILES
  voice_and_rules.txt    how Evochi talks, and the handful of things never to post
  colours_and_fonts.txt  the hex codes and font names if you make your own posts
  bios_all_platforms.txt every bio, display name and link, in one place (also in each platform folder)
""")
put('00_brand/voice_and_rules.txt', """
THE ONE-LINE PITCH
  Every step brings your Evochi to life.

THE LONGER PITCH (profiles, press, descriptions)
  Hatch a little voxel lizard, walk to help it grow, and raise it from Eggling to Elder.
  Rest days are protected, it never guilt-trips you, and it only ever reads your step count.

VOICE
  - A friend showing you their pet, never a fitness coach.
  - Lowercase and casual on TikTok and X. Sentence case on Instagram and YouTube.
  - Mochi is "he", and a character. Features show up as things Mochi does.
  - Specific numbers beat adjectives: 7,000 steps, three forms, six colours, 74,856 voxels,
    two rest days a week, first 1,000 get the crown.
  - Short sentences. One idea per post. The call to action is always the waitlist.

NEVER
  - "burn calories", "get fit", "lose weight", or anything that sounds like health advice.
  - Post a sign-up, follower or spots-left number that isn't real.
  - Show the gem icon or mention gems. The game has one currency: EvoCoins.
  - Use the Apple or Google store badges before the listings are live. Say "link in bio".
  - Reply to a health question with advice. The line is: "It's a game, not a doctor."

RECURRING CHARACTERS
  Mochi: the Ocean (blue) Eggling in the videos. Keep him Ocean everywhere.
  The Amber Eggling: the app icon and every profile picture.
""")
put('00_brand/colours_and_fonts.txt', """
COLOURS (from the Evochi style guide)
  Buttons, highlights, profile tile     gold-500        #F4B84E
  Button bevel, gold outline            gold-700        #C8832C
  Dark text, caption outlines           ink-900         #3B2923
  Secondary text                        ink-700         #684C3C
  Card backgrounds                      cream-50        #FFF9F0
  Parchment backgrounds                 parchment-100   #F8EBDD
  Meadow green accents                  meadow-500      #82B75E
  Meadow green text                     meadow-700      #477B3A
  Sky                                   sky-400         #84C4E8
  Founder's Crown rose gold (campaign)  rose            #E7A8BC

FONTS (free on Google Fonts)
  Headlines: Nunito, weight 800 or 900
  Body: Lato, weight 400 or 700

CAPTION STYLE ON VIDEO AND PHOTO POSTS
  White Nunito 900 with a thick #3B2923 outline, centred, never in the bottom 20% of the frame
  (TikTok and Reels put their own buttons there).
""")

BIOS = f"""
HANDLE (same on all four)
  First choice: @evochigame     Fallback: @playevochi
  Display name on every platform: Evochi

INSTAGRAM (150 characters max)
  Name: Evochi
  Category: Video Game (switch to a Creator account)
  Bio:
    Every step brings your Evochi to life.
    A cozy voxel pet that grows when you walk.
    Beta waitlist below.
  Link: {LINK}
  (If you use a link page, order it: Join the beta waitlist / Play the browser preview / Privacy)

TIKTOK (80 characters max)
  Name: Evochi
  Bio:
    a lizard egg that grows when you walk. beta waitlist in the link.
  Link: {LINK}
  Note: TikTok hides bio links on new accounts until 1,000 followers. Until then the pinned
  comment under every video says where the link is.

YOUTUBE
  Channel name: Evochi
  Handle: @evochigame
  Description:
    Evochi is a cozy walking pet for iPhone and Android. Hatch a little voxel lizard, walk to
    help it grow, and raise it from Eggling to Elder. Every step your phone counts becomes XP,
    coins and evolutions. Rest days are protected, it never guilt-trips you, and it only ever
    reads your step count. Beta waitlist in the links below.
  Links (in this order): Join the beta waitlist / Play the browser preview / Website / Privacy policy
  Channel keywords: walking pet game, step counter pet, cozy game, virtual pet, voxel

X / TWITTER (160 characters max)
  Name: Evochi
  Bio:
    A cozy walking pet. Hatch a voxel lizard, walk to help it grow, raise it from Eggling to
    Elder. It only reads steps. Beta waitlist open.
  Location: Sunlit Meadow
  Link: {LINK}
"""
put('00_brand/bios_all_platforms.txt', BIOS)

# ====================================================================== 01 instagram
put('01_instagram/README.txt', """
01_instagram
============
Instagram is the album. The grid should look like a cozy game the moment someone lands on it.
Post sizes: feed 1080 x 1350 (4:5). Stories 1080 x 1920. Highlight covers 1080 x 1080.

SET UP (10 minutes)
  1. profile/pfp_main.png as the profile picture. Bio and link from profile/bio.txt.
  2. Post the three pinned items first, in this order, and pin each one from its "..." menu:
       posts/01_ig_waitlist.jpg, carousel/ (all five slides as one post), posts/03_ig_pick.jpg
  3. Upload highlight covers from highlights/ and name them as that README says.

FOLDERS
  profile/      profile picture + bio.txt
  posts/        8 feed posts. Each .jpg has a .txt with the caption (paste as the caption) and the
                hashtags (paste as the FIRST COMMENT, not in the caption). Numbered in posting order.
  carousel/     5 slides for one carousel post, plus caption.txt
  stories/      three 1080 x 1920 images for Stories, with the sticker to add on each
  reels/        captions for the six videos when you post them as Reels
  highlights/   six round cover images + the highlight names

TIPS
  - Post Reels between 6 and 9 pm in your audience's time zone; feed posts in the morning.
  - Turn on auto-captions for every Reel. Most people watch muted.
  - Reply to every comment in the first hour. A comment reply counts more than a like.
""")
cp('pfp_main.png', '01_instagram/profile/pfp_main.png')
put('01_instagram/profile/bio.txt', f"""
PROFILE PICTURE: pfp_main.png (the Amber Eggling face on gold; it matches the app icon)

Name: Evochi
Username: @evochigame (fallback @playevochi)
Category: Video Game
Account type: Creator

Bio (paste exactly, three lines):
Every step brings your Evochi to life.
A cozy voxel pet that grows when you walk.
Beta waitlist below.

Link: {LINK}
""")
IG_POSTS = [
    ('ig_waitlist', '01', "Beta opens soon.\n\nYour steps. Your Evochi. Pick your egg, hatch it first: waitlist in bio.\n\nThe first 1,000 get the Founder's Crown.",
     '#evochi #walkingpet #cozygames #virtualpet #indiegame #stepcounter #tamagotchi #gamedev #beta #waitlist', 'PIN THIS POST. It is the first tile people see.'),
    ('ig_meet', '02', "This is Mochi.\n\nHe's an Eggling, he's Ocean, and he only grows when I walk. 7,000 steps a day and he'll be a Juvenile in about a week.\n\nSay hi.",
     '#evochi #cozygames #virtualpet #voxelart #indiegame #walkingpet #cozygaming #wholesomegames', ''),
    ('ig_pick', '03', "Which egg is yours?\n\nAmber, Forest, Coral, Ocean, Amethyst or Obsidian. Comment your colour.\n\nWaitlist members pick first.",
     '#evochi #pickyouregg #cozygames #virtualpet #indiegame #tamagotchi #cozygaming #walkingpet', 'PIN THIS POST. Reply to every colour comment with that colour\'s Eggling image from 02_tiktok/replies/.'),
    ('ig_forms', '04', "One friend, three forms.\n\nEggling on day one. Juvenile at level 10. Elder at level 25.\n\nSame name, same colour, same crown. Just bigger.",
     '#evochi #evolution #cozygames #voxelart #indiegame #virtualpet #characterdesign #gamedev', ''),
    ('ig_rest', '05', "Rest days are protected.\n\nTwo low-step days a week never cost vitality. Late watch data gets 48 hours. No data means pending, never lazy.\n\nHe's a pet, not a doctor.",
     '#evochi #cozygames #gentlegaming #walkingpet #wholesomegames #virtualpet #indiegame #selfcare', ''),
    ('ig_crown', '06', "The Founder's Crown.\n\nFirst 1,000 on the waitlist. Fits every form, forever. Never sold in the Market.\n\nWaitlist in bio.",
     '#evochi #founders #beta #cozygames #indiegame #virtualpet #waitlist #comingsoon', 'Post this the week the Founder\'s Crown video runs. Swap the profile picture to pfp_crown.png for that week if you like.'),
    ('ig_wardrobe', '07', "Dress him up.\n\nScarves, hats, crowns and backpacks, and every one fits all three forms.\n\nBought with coins you earn by walking. Nothing else.",
     '#evochi #cozygames #virtualpet #voxelart #characterdesign #indiegame #cozygaming #walkingpet', ''),
    ('ig_voxels', '08', "74,856 voxels. One Eggling.\n\nHand-built in a voxel editor, then grown one step at a time.",
     '#evochi #voxelart #gamedev #indiedev #madewithvoxels #indiegame #screenshotsaturday #cozygames', 'Good for a Saturday; the #screenshotsaturday crowd looks for workshop posts.'),
]
for key, n, cap, tags, note in IG_POSTS:
    cp(f'{key}.jpg', f'01_instagram/posts/{n}_{key}.jpg')
    put(f'01_instagram/posts/{n}_{key}.txt', f"""
IMAGE: {n}_{key}.jpg   (1080 x 1350, post to the feed)
{('NOTE: ' + note) if note else ''}

CAPTION (paste this as the caption):
{cap}

FIRST COMMENT (post this as your own first comment, right after publishing):
{tags}
""")
put('01_instagram/posts/README.txt', """
posts/
======
Eight feed posts, numbered in the order to post them (one every two or three days; see the calendar).
Each image has a text file with the same name: the CAPTION goes in the caption box, the HASHTAGS go
in your own first comment under the post. Keeping hashtags out of the caption keeps the post clean.

Pin 01, the carousel and 03 so they stay at the top of the grid.
""")
for i in range(1, 6):
    cp(f'car_{i}.jpg', f'01_instagram/carousel/slide_{i}.jpg')
put('01_instagram/carousel/caption.txt', """
POST TYPE: one carousel post with the five slides in order (slide_1 is the cover).

CAPTION (paste as the caption):
How it works, in four swipes.

Hatch, walk, earn, evolve. That's the whole game.

Beta waitlist in bio.

FIRST COMMENT (hashtags):
#evochi #cozygames #walkingpet #virtualpet #indiegame #howitworks #stepcounter #cozygaming

NOTE: Pin this post. Carousels get shown a second time to people who didn't swipe, so re-share it
every two weeks.
""")
put('01_instagram/carousel/README.txt', """
carousel/
=========
Five slides for one post. Upload slide_1 through slide_5 in that order; slide_1 is the cover that
shows in the grid. The caption and hashtags are in caption.txt.
""")
for key in ('tt_pick', 'tt_forms', 'tt_crown'):
    cp(f'{key}.jpg', f'01_instagram/stories/{key.replace("tt_", "story_")}.jpg')
put('01_instagram/stories/README.txt', f"""
stories/
========
Three 1080 x 1920 images for Stories. Add the stickers below in the Instagram app, then save each
Story to the matching highlight.

story_pick.jpg    Add a POLL sticker: "Ocean or Coral?"  Add a LINK sticker to {LINK} labelled
                  "Join the waitlist". Save to the Mochi highlight.
story_forms.jpg   Add a LINK sticker labelled "Join the waitlist". Save to the Forms highlight.
story_crown.jpg   Add a LINK sticker labelled "Claim your crown". Save to the Crown highlight.

Also share every feed post to your Story the day it goes up (tap the paper-plane icon, "Add post to
your story"). That is free reach.
""")
put('01_instagram/reels/README.txt', """
reels/
======
The six videos go up as Reels (same MP4s as TikTok). Captions are in captions.txt. Set the cover to
the first frame (the hook line is on it). Turn on auto-captions.
""")
put('01_instagram/reels/captions.txt', """
REEL: evochi_ad_v2_19s_1080x1920.mp4
  Caption:  My step counter has a face now. Beta waitlist in bio.
  Hashtags (first comment): #evochi #cozygames #walkingpet #virtualpet #indiegame

REEL: evochi_ad_v2_27s_1080x1920.mp4
  Caption:  Day 7. Beta waitlist in bio.
  Hashtags: #evochi #cozygames #tamagotchi #indiegame #virtualpet

REEL: evochi_wl1_dev_diary_20s.mp4
  Caption:  I'm making a game where your step count raises a little lizard. Day 1.
  Hashtags: #evochi #indiegame #gamedev #cozygames #walkingpet

REEL: evochi_wl2_pick_your_egg_18s.mp4
  Caption:  Which egg would you pick? Comment your colour. Waitlist members pick first.
  Hashtags: #evochi #pickyouregg #cozygames #virtualpet #indiegame

REEL: evochi_wl3_founders_crown_17s.mp4
  Caption:  1,000 crowns. Founders only. Waitlist in bio.
  Hashtags: #evochi #founders #beta #cozygames #indiegame

REEL: evochi_wl4_help_hatch_18s.mp4   (only once the live counter exists)
  Caption:  The egg hatches at 5,000 sign-ups. We're at [REAL NUMBER]. Waitlist in bio.
  Hashtags: #evochi #cozygames #walkingpet #indiegame #beta
""")
HL = [('hl_beta', 'Beta', 'waitlist and crown Stories'), ('hl_mochi', 'Mochi', "his daily life, the pick-your-egg poll"),
      ('hl_forms', 'Forms', 'evolutions'), ('hl_market', 'Market', 'outfits and nest decor'),
      ('hl_faq', 'FAQ', 'rest days, privacy, steps-only'), ('hl_crown', 'Crown', "Founder's Crown Stories")]
for key, name, what in HL:
    cp(f'{key}.png', f'01_instagram/highlights/{key}.png')
put('01_instagram/highlights/README.txt', """
highlights/
===========
Round covers for the Story highlights under your bio. Upload each as the highlight cover and name
the highlight exactly as below (short names fit under the circle).

  hl_beta.png     name: Beta      holds: waitlist and crown Stories
  hl_mochi.png    name: Mochi     holds: his daily life, the pick-your-egg poll
  hl_forms.png    name: Forms     holds: evolutions
  hl_market.png   name: Market    holds: outfits and nest decor
  hl_faq.png      name: FAQ       holds: rest days, privacy, steps-only
  hl_crown.png    name: Crown     holds: Founder's Crown Stories

Order them left to right: Beta, Mochi, Forms, Market, FAQ, Crown.
""")

# ====================================================================== 02 tiktok
put('02_tiktok/README.txt', """
02_tiktok
=========
TikTok is where the waitlist fills. Videos go here first; the other platforms follow a day later.
Everything is lowercase. Answer comments within the first hour of every post.

SET UP (5 minutes)
  1. profile/pfp_main.png as the profile picture. Bio from profile/bio.txt.
  2. Post videos/01 (dev diary) first and pin it. Paste pinned_comment.txt as your first comment and
     pin that comment. Do the same pinned comment on every video.

FOLDERS
  profile/       picture + bio.txt
  videos/        a text file per video: caption, hashtags, pinned comment, and which MP4 to upload
  photo_posts/   three swipeable photo posts (TikTok "photo mode") with captions
  replies/       the six Eggling images and the crown to drop into comment replies, plus templates

KEEP IN MIND
  - New accounts can't show a bio link until 1,000 followers. The pinned comment does that job.
  - Three to five hashtags, never more. No store badges until the listings are live.
  - Once video 01 works, film a real "day N" follow-up every week on your own phone.
""")
cp('pfp_main.png', '02_tiktok/profile/pfp_main.png')
cp('pfp_mochi.png', '02_tiktok/profile/pfp_mochi_alternate.png')
put('02_tiktok/profile/bio.txt', f"""
PROFILE PICTURE: pfp_main.png. (pfp_mochi_alternate.png if you want the account to feel like Mochi's own.)

Name: Evochi
Username: @evochigame (fallback @playevochi)

Bio (80 characters max, paste exactly):
a lizard egg that grows when you walk. beta waitlist in the link.

Link (shows once you have 1,000 followers): {LINK}
""")
TT_VIDEOS = [
    ('01_dev_diary', 'evochi_wl1_dev_diary_20s.mp4', "day 1 of showing you the game I've been building. it's a walking pet. you're going to love him.", '#indiegame #cozygames #gamedev #walkingpet', 'PIN THIS VIDEO.'),
    ('02_pick_your_egg', 'evochi_wl2_pick_your_egg_18s.mp4', 'amber, forest, coral, ocean, amethyst or obsidian? comment yours. waitlist picks first.', '#cozygames #virtualpet #pickyouregg', 'Reply to every colour comment with that colour\'s image from replies/.'),
    ('03_ad_19s', 'evochi_ad_v2_19s_1080x1920.mp4', 'my step counter has a face now', '#cozygames #walkingpet #virtualpet', ''),
    ('04_founders_crown', 'evochi_wl3_founders_crown_17s.mp4', "1,000 crowns. that's it. founders only.", '#indiegame #cozygames #beta', 'Run this in week 2, after people already want the game.'),
    ('05_ad_27s', 'evochi_ad_v2_27s_1080x1920.mp4', 'day 7.', '#cozygames #tamagotchi #indiegame', ''),
    ('06_help_hatch', 'evochi_wl4_help_hatch_18s.mp4', "we're at [REAL NUMBER] / 5,000. when it hatches, beta opens.", '#cozygames #walkingpet #indiegame', 'ONLY once the live counter exists on the waitlist page. Replace [REAL NUMBER] with the real one.'),
]
for key, mp4, cap, tags, note in TT_VIDEOS:
    put(f'02_tiktok/videos/{key}.txt', f"""
UPLOAD: {mp4}
{('NOTE: ' + note) if note else ''}

CAPTION (paste exactly, hashtags included):
{cap} {tags}

PINNED COMMENT (post as your own first comment, then pin it):
beta first, store after. waitlist in bio. founders get the crown.

SETTINGS: allow comments, allow duets and stitches, auto-captions on, cover = first frame.
""")
put('02_tiktok/videos/README.txt', """
videos/
=======
One text file per video, numbered in posting order. Each says which MP4 to upload, the exact caption
(hashtags are part of the caption on TikTok) and the pinned comment. The MP4s are in the videos zip.
""")
put('02_tiktok/pinned_comment.txt', """
Post this as your own first comment on EVERY video, then tap and hold it and choose "Pin comment":

beta first, store after. waitlist in bio. founders get the crown.
""")
TT_PHOTOS = [
    ('tt_pick', 'which egg is yours? comment your colour. waitlist picks first.', '#cozygames #virtualpet #pickyouregg'),
    ('tt_forms', 'one friend. three forms. same name, same colour, same crown.', '#cozygames #indiegame #virtualpet'),
    ('tt_crown', "the first 1,000 on the waitlist get the founder's crown. never sold.", '#indiegame #cozygames #beta'),
]
for key, cap, tags in TT_PHOTOS:
    cp(f'{key}.jpg', f'02_tiktok/photo_posts/{key}.jpg')
    put(f'02_tiktok/photo_posts/{key}.txt', f"""
IMAGE: {key}.jpg  (upload as a TikTok photo post; one image is fine, or add the other two as swipes)

CAPTION (paste exactly):
{cap} {tags}

PINNED COMMENT:
beta first, store after. waitlist in bio. founders get the crown.
""")
put('02_tiktok/photo_posts/README.txt', """
photo_posts/
============
TikTok "photo mode" posts get their own run in the feed, separate from videos. Post tt_pick the day
after the Pick your egg video; the comments ask the same question so replies carry over.
Each image has a .txt with its caption.
""")
for p in ('amber', 'forest', 'coral', 'ocean', 'amethyst', 'obsidian'):
    cp(f'eggling_{p}.png', f'02_tiktok/replies/eggling_{p}.png', REPLIES)
cp('founders_crown.png', '02_tiktok/replies/founders_crown.png', REPLIES)
put('02_tiktok/replies/README.txt', """
replies/
========
Save these to your phone. When someone comments a colour, reply with that colour's Eggling image and
"[colour], reserved. waitlist in bio." When someone asks about the crown, reply with founders_crown.png.
The full set of reply templates is in 06_hashtags_replies/reply_templates.txt.
""")

# ====================================================================== 03 youtube
put('03_youtube/README.txt', """
03_youtube
==========
YouTube is the long-tail home: Shorts bring people in, and the channel page is where a journalist or
a store reviewer checks that the game is real. Fill every description; YouTube search reads them.

SET UP (15 minutes)
  1. channel/pfp_main.png as the picture, channel/yt_banner.jpg as the banner (it fits the safe area
     for phones and TVs), and channel/channel_description.txt for the description, links and keywords.
  2. Upload evochi_ad_v2_27s_1080x1920.mp4 as a normal video (not a Short) with videos/00_trailer.txt
     and thumbnails/yt_trailer.jpg. Set it as the channel trailer under Customize channel.
  3. Upload the rest as Shorts using their text files and thumbnails.
  4. Create the three playlists in playlists.txt.

FOLDERS
  channel/      profile picture, banner, description
  videos/       one text file per upload: title, description, tags, thumbnail to use
  thumbnails/   1280 x 720 thumbnails
""")
cp('pfp_main.png', '03_youtube/channel/pfp_main.png')
cp('yt_banner.jpg', '03_youtube/channel/yt_banner.jpg')
put('03_youtube/channel/channel_description.txt', f"""
PICTURE: pfp_main.png
BANNER: yt_banner.jpg (2560 x 1440; the words sit inside YouTube's safe area, so don't crop it)

Channel name: Evochi
Handle: @evochigame (fallback @playevochi)

Description (paste exactly):
Evochi is a cozy walking pet for iPhone and Android. Hatch a little voxel lizard, walk to help it grow, and raise it from Eggling to Elder. Every step your phone counts becomes XP, coins and evolutions. Rest days are protected, it never guilt-trips you, and it only ever reads your step count. Beta waitlist in the links below.

Links (Customize channel > Basic info > Links), in this order:
  Join the beta waitlist     {LINK}
  Play the browser preview   [BROWSER PREVIEW LINK]
  Website                    [WEBSITE LINK]
  Privacy policy             [WEBSITE LINK]/privacy.html

Channel keywords (Settings > Channel > Basic info):
walking pet game, step counter pet, cozy game, virtual pet, voxel, indie game, tamagotchi
""")
YT = [
    ('00_trailer', 'evochi_ad_v2_27s_1080x1920.mp4', 'Evochi: Every step brings your Evochi to life', 'yt_trailer.jpg', 'Upload as a normal video, then set as the channel trailer.',
     "Evochi is a cozy walking pet for iPhone and Android. Hatch a little voxel lizard, walk to help it grow, and raise it from Eggling to Elder. Every step your phone counts becomes XP, coins and evolutions. Rest days are protected, it never guilt-trips you, and it only ever reads your step count.\n\nJoin the beta waitlist: " + LINK + "\nThe first 1,000 get the Founder's Crown.\n\nFree to download when it ships. Everything in the Market costs coins you earn by walking."),
    ('01_short_dev_diary', 'evochi_wl1_dev_diary_20s.mp4', "I'm making a game where your step count raises a lizard", 'yt_making.jpg', '',
     "Day 1 of the Evochi dev diary: 74,856 voxels, ten moods, three forms. It's playable, just not in the store yet.\n\nBeta waitlist: " + LINK),
    ('02_short_pick_your_egg', 'evochi_wl2_pick_your_egg_18s.mp4', 'Which egg would you pick?', 'yt_pick.jpg', '',
     "Six colours, one Evochi. Comment your colour; waitlist members pick first.\n\nBeta waitlist: " + LINK),
    ('03_short_ad_19s', 'evochi_ad_v2_19s_1080x1920.mp4', 'My step counter has a face now', 'yt_trailer.jpg', '',
     "Evochi is a walking pet that grows from the steps your phone already counts.\n\nBeta waitlist: " + LINK),
    ('04_short_founders_crown', 'evochi_wl3_founders_crown_17s.mp4', 'Only 1,000 people will ever get this', 'yt_crown.jpg', '',
     "The Founder's Crown: first 1,000 beta testers, fits every form forever, never sold.\n\nBeta waitlist: " + LINK),
    ('05_short_ad_27s', 'evochi_ad_v2_27s_1080x1920.mp4', 'Day 7: he evolved', 'yt_trailer.jpg', 'The same file as the trailer, uploaded again as a Short.',
     "Hatch an egg, walk, and watch it become a Juvenile. Every step brings your Evochi to life.\n\nBeta waitlist: " + LINK),
    ('06_short_help_hatch', 'evochi_wl4_help_hatch_18s.mp4', 'The egg hatches at 5,000 sign-ups', 'yt_trailer.jpg', 'Only once the live counter exists.',
     "Every sign-up warms the nest. Bring a friend and you both move up the line.\n\nBeta waitlist: " + LINK),
]
TAGS = 'evochi, walking pet game, step counter pet, cozy game, virtual pet, tamagotchi, voxel, indie game, mobile game, pedometer game, health connect, apple health'
for key, mp4, title, thumb, note, desc in YT:
    put(f'03_youtube/videos/{key}.txt', f"""
UPLOAD: {mp4}
THUMBNAIL: thumbnails/{thumb}
{('NOTE: ' + note) if note else ''}

TITLE (paste exactly):
{title}

DESCRIPTION (paste exactly):
{desc}

TAGS (paste into the tags box):
{TAGS}

SETTINGS: made for kids = NO (it's a general audience game, not kids' content); category = Gaming;
game title = Evochi; comments on; add to the playlist named in playlists.txt.
""")
put('03_youtube/videos/README.txt', """
videos/
=======
One text file per upload with the title, description, tags and thumbnail. 00_trailer is a normal
upload (set it as the channel trailer); 01 to 06 are Shorts. The MP4s are in the videos zip.
""")
for t in ('yt_trailer', 'yt_making', 'yt_pick', 'yt_crown'):
    cp(f'{t}.jpg', f'03_youtube/thumbnails/{t}.jpg')
put('03_youtube/thumbnails/README.txt', """
thumbnails/
===========
1280 x 720 thumbnails. Shorts don't show them on the Shorts shelf but do on the channel page and in
search, so upload them anyway. Each videos/*.txt says which one to use.
""")
put('03_youtube/playlists.txt', """
Create these three playlists (Content > Playlists > New):

  Dev diary          01_short_dev_diary, and every day-N follow-up you film
  Meet the Evochi    02_short_pick_your_egg, 04_short_founders_crown, 06_short_help_hatch
  How it works       00_trailer, 03_short_ad_19s, 05_short_ad_27s
""")

# ====================================================================== 04 x / twitter
put('04_x_twitter/README.txt', """
04_x_twitter
============
X is for the indie game and gamedev crowd, who follow developers rather than games. Post from the
Evochi account but write like the person making it. Images are 1600 x 900 so they show whole.

SET UP (10 minutes)
  1. profile/pfp_main.png as the picture, profile/x_header.jpg as the header, bio from profile/bio.txt.
  2. Post the thread in pinned_thread.txt (each line as a reply to the previous, with its image),
     then pin the first post.

FOLDERS
  profile/   picture, header, bio
  posts/     five image posts with the exact text in matching .txt files
  pinned_thread.txt   the six-post thread, with which image goes on each

RULES HERE
  - One or two hashtags at most, in the text. More reads as spam on X.
  - Saturdays: post a workshop image with #screenshotsaturday.
  - Quote-post people who reply with a colour, attaching that colour's Eggling from 02_tiktok/replies/.
""")
cp('pfp_main.png', '04_x_twitter/profile/pfp_main.png')
cp('x_header.jpg', '04_x_twitter/profile/x_header.jpg')
put('04_x_twitter/profile/bio.txt', f"""
PICTURE: pfp_main.png
HEADER: x_header.jpg (1500 x 500; the bottom-left stays clear for the avatar)

Name: Evochi
Username: @evochigame (fallback @playevochi)

Bio (160 characters max, paste exactly):
A cozy walking pet. Hatch a voxel lizard, walk to help it grow, raise it from Eggling to Elder. It only reads steps. Beta waitlist open.

Location: Sunlit Meadow
Website: {LINK}
""")
put('04_x_twitter/pinned_thread.txt', f"""
Post 1 first, then each next post as a REPLY to the one before. Attach the image named on each line.
When done, open post 1 and choose "Pin to your profile".

1/ (image: posts/x_announce.jpg)
I'm making a walking pet game. You hatch a voxel lizard, your phone's step count raises it, and it grows from Eggling to Elder. Beta waitlist is open. A thread on what it is and what it isn't.

2/ (image: posts/x_forms.jpg)
One friend, three forms. Level 10 and seven active days for a Juvenile, level 25 and twenty-one for an Elder. You choose the moment it evolves. Nothing is lost on the way: same name, same colour, same outfit.

3/ (image: posts/x_rest.jpg)
It never guilt-trips you. Two low-step days a week are protected, late watch data gets 48 hours to arrive, and missing data is "pending", never "lazy". It's a pet, not a doctor, and it never reads heart rate.

4/ (image: posts/x_pick.jpg)
Six colours. Which egg is yours? Reply with it; waitlist members pick first.

5/ (image: posts/x_crown.jpg)
The first 1,000 on the waitlist get the Founder's Crown: fits every form, forever, never sold in the Market. After that it's gone.

6/ (no image)
Waitlist: {LINK}
Free to download when it ships; everything in the Market costs coins you earn by walking. iPhone and Android, same day.
""")
XP = [
    ('x_announce', f"Every step brings your Evochi to life. A cozy walking pet for iPhone and Android. Beta waitlist open: {LINK} #indiegame", 'Also the first image of the pinned thread.'),
    ('x_pick', 'Amber, Forest, Coral, Ocean, Amethyst or Obsidian? Reply with yours. Waitlist members pick first. #cozygames', 'Reply to every colour with that colour\'s Eggling image.'),
    ('x_crown', f"1,000 crowns. Founders only. Waitlist: {LINK}", 'Week 2.'),
    ('x_forms', 'Day 1, level 10, level 25. Same Mochi. #cozygames', ''),
    ('x_rest', 'A walking game that gives you rest days. Two a week, protected. #cozygames', ''),
]
for key, text, note in XP:
    cp(f'{key}.jpg', f'04_x_twitter/posts/{key}.jpg')
    put(f'04_x_twitter/posts/{key}.txt', f"""
IMAGE: {key}.jpg (1600 x 900)
{('NOTE: ' + note) if note else ''}

POST (paste exactly):
{text}
""")
put('04_x_twitter/posts/README.txt', """
posts/
======
Five standalone image posts. Each .jpg has a .txt with the exact text. x_announce, x_forms, x_rest,
x_pick and x_crown are also the images for the pinned thread (see ../pinned_thread.txt).

Extra posts that need no image:
  "my step counter has a face now" with the 19-second video attached.
  "74,856 voxels. One Eggling. Built in a voxel editor, grown one step at a time. #screenshotsaturday"
  with 01_instagram/posts/08_ig_voxels.jpg attached (4:5 shows fine on X).
""")

# ====================================================================== 05 calendar
put('05_calendar/README.txt', """
05_calendar
===========
four_week_calendar.txt is the day-by-day plan. TikTok leads; the other three follow a day behind so
each platform gets its own first look. posting_rules.txt is the short list of habits that matter.
""")
put('05_calendar/four_week_calendar.txt', """
FOUR-WEEK CALENDAR (TikTok and Reels 6 to 9 pm local; YouTube and X in the morning)

WEEK 1
  Mon  TikTok: videos/01_dev_diary          Instagram: posts/01_ig_waitlist (pin)
       YouTube: 00_trailer (set as trailer)  X: pinned_thread.txt
  Wed  TikTok: videos/02_pick_your_egg       Instagram: posts/02_ig_meet
       YouTube: 01_short_dev_diary           X: posts/x_pick
  Fri  TikTok: videos/03_ad_19s              Instagram: posts/03_ig_pick (pin) + stories/story_pick
       YouTube: 02_short_pick_your_egg       X: reply to every colour with its Eggling
  Sat  TikTok: photo_posts/tt_pick           Instagram: carousel (pin)
       X: posts/08_ig_voxels image with #screenshotsaturday

WEEK 2
  Mon  TikTok: film a real "day N" diary on your phone   Instagram: posts/04_ig_forms
       YouTube: 03_short_ad_19s              X: posts/x_forms
  Wed  TikTok: videos/04_founders_crown      Instagram: posts/06_ig_crown (swap pfp to pfp_crown this week)
       YouTube: 04_short_founders_crown      X: posts/x_crown
  Fri  TikTok: photo_posts/tt_crown          Instagram: posts/07_ig_wardrobe
       X: a short note on what the crown is made of
  Sat  TikTok: videos/05_ad_27s              Instagram: stories/story_forms
       X: wardrobe image with #screenshotsaturday

WEEK 3
  Mon  TikTok: videos/06_help_hatch (ONLY if the live counter exists)   Instagram: posts/05_ig_rest
       YouTube: 06_short_help_hatch          X: posts/x_rest
  Wed  TikTok: day-N diary                   Instagram: Reel: dev diary
       YouTube: 05_short_ad_27s              X: counter update with the real number
  Fri  TikTok: photo_posts/tt_forms          Instagram: Reel: pick your egg
       X: re-post the thread's crown post
  Sat  TikTok: reply video to the best comment   Instagram: re-share the carousel
       X: #screenshotsaturday

WEEK 4
  Mon  TikTok: counter update video (real number)   Instagram: posts/08_ig_voxels
       YouTube: counter update Short         X: counter update
  Wed  TikTok: day-N diary                   Instagram: Reel: Founder's Crown
       X: dev note
  Fri  TikTok: re-cut the best performer with a new first line   Instagram: re-share posts/01_ig_waitlist
       X: thread on what's left before beta
  Sat  TikTok: thank-you video from Mochi    Instagram: refresh the highlights
       X: #screenshotsaturday

AFTER WEEK 4
  Keep the weekly day-N diary and a counter update. Retire anything under a 30% 3-second hold rate on
  TikTok. When the egg hatches (5,000), post the hatch on all four platforms in the same hour.
""")
put('05_calendar/posting_rules.txt', """
POSTING RULES
  - One video a day is plenty. Replies in the first hour matter more than a second post.
  - Never post a number that isn't real: sign-ups, followers, spots left.
  - Every video: auto-captions on, cover = first frame, pinned comment with the link line.
  - Every image post on Instagram: hashtags in the first comment, not the caption.
  - Keep the Apple and Google badges off everything until the store listings are live.
  - Save the best comments; they are next week's video hooks.
""")

# ====================================================================== 06 hashtags + replies
put('06_hashtags_replies/README.txt', """
06_hashtags_replies
===================
Shared by all platforms. hashtag_sets.txt has three sets to rotate; reply_templates.txt is the
script for the comments. Keep reply_templates.txt open while you reply.
""")
put('06_hashtags_replies/hashtag_sets.txt', """
Always include #evochi. Rotate the sets so the same ten tags aren't on every post.
TikTok: 3 to 5 tags in the caption. Instagram: 8 to 10 in the first comment. X: 1 or 2 in the text.

COZY (character and lifestyle posts)
  #evochi #cozygames #cozygaming #virtualpet #walkingpet #tamagotchi #wholesomegames

DEV (workshop and dev-diary posts)
  #evochi #indiegame #gamedev #indiedev #voxelart #screenshotsaturday #madewithvoxels

LAUNCH (waitlist and crown posts)
  #evochi #beta #waitlist #comingsoon #mobilegame #pickyouregg
""")
put('06_hashtags_replies/reply_templates.txt', """
REPLY TEMPLATES (paste and adjust; same friendly voice everywhere)

Colour comment ("ocean!", "amethyst", ...)
  [Colour], reserved. Waitlist in bio and he's yours first.
  (attach that colour's Eggling image from 02_tiktok/replies/)

"When does it come out?"
  Beta first for the waitlist, then the stores. No date yet, I'd rather it be good than early.

"Is it free?"
  Free to download. Market items cost EvoCoins, which you earn by walking. No gems.

"Android?"
  iPhone and Android, same day.

"I have a disability" / "I can't walk much"
  Rest days are protected, manual entry counts for XP, and he never judges you. If something about
  that should work better, tell me, I'm listening.

"Does it track me?"
  Steps only, read from Apple Health or Health Connect. No location, no heart rate, never sold,
  never used for ads.

"Is this like Pokemon Go?"
  No GPS and no catching. It's a pet that grows from your step count, more Tamagotchi than Pokemon Go.

"This is just a step counter"
  (don't argue; reply with the hatch video or "he'd disagree" and the chirp)

Praise
  Mochi says thank you. (or a 3-second reply video of Mochi chirping)

"Can I name mine ___?"
  Yes. Twelve characters, anything you like.

"What's the Founder's Crown?"
  A rose-gold crown for the first 1,000 on the waitlist. Fits every form, forever, and it's never
  sold in the Market.
  (attach founders_crown.png)
""")

# ====================================================================== videos (optional, separate zip)
if VIDEOS:
    os.makedirs(os.path.join(OUT, '..', 'videos'), exist_ok=True)

print('pack written to', OUT)

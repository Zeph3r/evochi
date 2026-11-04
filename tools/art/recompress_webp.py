"""Re-encode the app's lossy WebP art a notch smaller (the download was nearing Google Play's 200 MB limit):
quality 74 instead of the 82-86 it was packed at. Lossless pictures, and any that wouldn't shrink by at least 8%,
are left as they are. Animations keep every frame's own duration and loop.

    python3 recompress_webp.py DIR [DIR ...]          (in place; prints what it saved)
"""
from __future__ import annotations

import io
import os
import sys
from multiprocessing import Pool

from PIL import Image, ImageSequence

Q = 74


def one(path):
    raw = open(path, 'rb').read()
    if b'VP8L' in raw[:200000] and b'VP8 ' not in raw[:200000]:
        return path, len(raw), len(raw)       # lossless: leave it
    im = Image.open(path)
    out = io.BytesIO()
    n = getattr(im, 'n_frames', 1)
    if n > 1:
        frames, durs = [], []
        for fr in ImageSequence.Iterator(im):
            frames.append(fr.convert('RGBA').copy())
            durs.append(int(fr.info.get('duration', im.info.get('duration', 33))))
        frames[0].save(out, 'WEBP', save_all=True, append_images=frames[1:], duration=durs, loop=im.info.get('loop', 0),
                       quality=Q, method=4, minimize_size=False, allow_mixed=False)
    else:
        mode = 'RGBA' if im.mode in ('RGBA', 'LA', 'P', 'PA') else 'RGB'
        im.convert(mode).save(out, 'WEBP', quality=Q, method=6)
    data = out.getvalue()
    if len(data) > len(raw) * 0.92:
        return path, len(raw), len(raw)
    open(path, 'wb').write(data)
    return path, len(raw), len(data)


if __name__ == '__main__':
    files = [os.path.join(d, f) for d in sys.argv[1:] for f in sorted(os.listdir(d)) if f.endswith('.webp')]
    before = after = 0
    with Pool(2) as pool:
        for i, (p, a, b) in enumerate(pool.imap_unordered(one, files, chunksize=4)):
            before += a
            after += b
            if i % 50 == 0:
                print(i, len(files), '%.1f -> %.1f MB' % (before / 1e6, after / 1e6), flush=True)
    print('done %d files: %.1f -> %.1f MB' % (len(files), before / 1e6, after / 1e6), flush=True)

"""The Forest Juvenile's expressions on its map sprite: the walkable maps' sheet has one face, so its portrait's
faces (chars/s02_forest_hero.webp, 15 expressions) are carried onto the map sprite where its face shows (toward
you, row 0, and down-left, row 7): its own face is lifted off (eyes, mouth, blush) and each portrait face laid on
by a similarity fitted on the two pairs of eyes.

    python3 tools/art/walker_faces.py flutter      -> assets/art/home/helper_faces_s02_forest.webp (+ .json)
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as nd

ROWS = (0, 7)
# where each row's face is, in its frame (x0, y0, x1, y1): toward you, and turned down-left (the far eye high)
FACE_BOX = {0: (0, 69, 234, 172), 7: (25, 108, 100, 176)}
EXPRS = ['blink', 'happy', 'curious', 'surprised', 'determined', 'sleepy', 'excited', 'affectionate']


def features(a, box):
    """the face's marks inside [box] (x0, y0, x1, y1): eyes, mouth, blush, tears (and the eyes' highlights)"""
    rgb = a[..., :3].astype(float)
    al = a[..., 3] > 128
    lum = rgb.mean(-1)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    dark = (lum < 110) & al
    blush = (r > 190) & (r - g > 45) & (r - b > 40) & al
    tear = (b > 170) & (b - r > 40) & al
    m = dark | blush | tear
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    x0, y0, x1, y1 = box
    m &= (xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1)
    # not the outline round the body: only marks with body all round them
    body = al & ~m
    inner = nd.binary_erosion(al, iterations=3)
    m &= inner
    m = nd.binary_fill_holes(m)  # (the white highlights in the eyes)
    return m


def eyes(a, m):
    """the two biggest dark marks (left, right), centres"""
    lum = a[..., :3].astype(float).mean(-1)
    dark = m & (lum < 110) | (m & nd.binary_fill_holes(m & (lum < 110)))
    lab, n = nd.label(dark)
    sizes = nd.sum(dark, lab, range(1, n + 1))
    keep = np.argsort(sizes)[::-1][:2] + 1
    cs = [nd.center_of_mass(lab == k) for k in keep]
    cs = sorted([(c[1], c[0]) for c in cs])  # (x, y), left to right
    return np.array(cs)


def similarity(src, dst):
    """scale, rotation and shift taking the src pair to the dst pair (2x3)"""
    s0, s1 = src
    d0, d1 = dst
    vs, vd = s1 - s0, d1 - d0
    k = np.linalg.norm(vd) / np.linalg.norm(vs)
    ang = np.arctan2(vd[1], vd[0]) - np.arctan2(vs[1], vs[0])
    c, s = k * np.cos(ang), k * np.sin(ang)
    R = np.array([[c, -s], [s, c]])
    t = d0 - R @ s0
    return np.hstack([R, t[:, None]])


def warp(img, A, size):
    """img (PIL RGBA) under the 2x3 A, onto a canvas of size"""
    M = np.vstack([A, [0, 0, 1]])
    inv = np.linalg.inv(M)
    return img.transform(size, Image.AFFINE, data=tuple(inv[:2].ravel()), resample=Image.BICUBIC)


def inpaint(a, hole):
    out = a.astype(float)
    known = ~hole
    for _ in range(60):
        if known.all():
            break
        k = known.astype(float)
        acc = np.stack([nd.uniform_filter(out[..., c] * k, 3) for c in range(3)], -1)
        w = nd.uniform_filter(k, 3)
        new = (w > 0.05) & ~known
        out[new, :3] = acc[new] / w[new][:, None]
        known |= new
    return out


if __name__ == '__main__':
    game = sys.argv[1]
    art = os.path.join(game, 'assets', 'art')
    man = json.load(open(os.path.join(art, 'manifest.json')))
    ch = man['chars']['s02']
    at = ch['atlas']['forest']
    hero = Image.open(os.path.join(art, at['file'])).convert('RGBA')
    names = ch['expressions']

    def hero_frame(e):
        x, y, w, h = at['rects'][names.index(e)]
        return hero.crop((x, y, x + w, y + h))

    walk = json.load(open(os.path.join(art, 'wilds', 'wilds_walk.json')))['walkers']['s02']
    fw, fh = walk['frameW'], walk['frameH']
    sheet = Image.open(os.path.join(art, 'wilds', walk['gaits']['walk']['sheets']['forest'])).convert('RGBA')
    hd = np.array(hero_frame('default'))
    fx, fy = ch['anchors']['face']
    hbox = (int(fx - 95), int(fy - 75), int(fx + 115), int(fy + 70))
    hm = features(hd, hbox)
    he = eyes(hd, hm)
    out = Image.new('RGBA', (fw * len(EXPRS), fh * len(ROWS)))
    for ri, row in enumerate(ROWS):
        fr = sheet.crop((0, row * fh, fw, row * fh + fh))
        a = np.array(fr)
        # its own face, found in the head (above the feet, below the crest)
        wm = features(a, FACE_BOX[row])
        we = eyes(a, wm)
        A = similarity(he, we)
        base = inpaint(a, nd.binary_dilation(wm, iterations=1))
        base[..., 3] = a[..., 3]
        for ei, e in enumerate(EXPRS):
            ha = np.array(hero_frame(e))
            m = features(ha, hbox)
            layer = ha.copy()
            layer[..., 3] = (m * 255).astype(np.uint8)
            wl = np.array(warp(Image.fromarray(layer), A, (fw, fh))).astype(float)
            k = (wl[..., 3:] / 255) * (a[..., 3:] / 255)
            px = base.copy()
            px[..., :3] = base[..., :3] * (1 - k) + wl[..., :3] * k
            out.paste(Image.fromarray(px.clip(0, 255).astype(np.uint8)), (ei * fw, ri * fh))
        print('row', row, 'eyes', we.round(1).tolist(), 'from', he.round(1).tolist(), flush=True)
    dst = os.path.join(art, 'home', 'helper_faces_s02_forest')
    out.save(dst + '.webp', 'WEBP', quality=92, method=6)
    json.dump({'w': fw, 'h': fh, 'rows': list(ROWS), 'exprs': EXPRS}, open(dst + '.json', 'w'))

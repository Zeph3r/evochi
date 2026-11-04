# The garden helper's telekinesis props, as pixel art (the game's pixel-icon look): a watering can (spout to the
# left, a leaf on its side), a wicker basket and a seed pouch. Drawn on a 24 px grid, outlined, scaled x6 without
# smoothing.   python3 tools/art/garden_props.py flutter
import os, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as nd

N, K = 24, 6


def finish(im, outline):
    a = np.array(im)
    al = a[..., 3] > 0
    ring = nd.binary_dilation(al, iterations=1) & ~al
    a[ring] = outline + (255,)
    return Image.fromarray(a).resize((N * K, N * K), Image.NEAREST)


def can():
    im = Image.new('RGBA', (N, N)); d = ImageDraw.Draw(im)
    lt, md, dk, rim = (206, 216, 224, 255), (156, 172, 184, 255), (108, 122, 136, 255), (228, 234, 238, 255)
    d.line([(9, 16), (3, 10)], fill=md, width=2)                 # spout
    d.rectangle([1, 8, 3, 10], fill=dk); d.point([(2, 8)], fill=lt)  # its rose
    d.rectangle([9, 10, 19, 20], fill=md)                        # body
    d.rectangle([9, 10, 11, 20], fill=lt)
    d.rectangle([17, 10, 19, 20], fill=dk)
    d.rectangle([9, 20, 19, 20], fill=dk)
    d.rectangle([9, 9, 19, 9], fill=rim)                         # rim
    d.line([(14, 9), (14, 5), (20, 5), (21, 6), (21, 12), (19, 13)], fill=dk, width=2)  # handle
    d.polygon([(13, 17), (14, 13), (16, 12), (15, 16)], fill=(108, 178, 72, 255))       # the leaf
    d.line([(13, 17), (15, 13)], fill=(70, 130, 48, 255))
    return finish(im, (46, 54, 64))


def basket():
    im = Image.new('RGBA', (N, N)); d = ImageDraw.Draw(im)
    w1, w2, w3 = (226, 176, 102, 255), (196, 140, 72, 255), (150, 100, 48, 255)
    d.arc([5, 3, 18, 20], 180, 360, fill=w3, width=2)            # handle
    d.polygon([(3, 12), (20, 12), (18, 21), (5, 21)], fill=w2)   # body
    for y in range(13, 21, 2):
        for x in range(4 + (y // 2) % 2, 20, 3):
            d.point([(x, y)], fill=w3)
    d.rectangle([3, 11, 20, 12], fill=w1)                        # rim
    d.line([(5, 21), (18, 21)], fill=w3)
    return finish(im, (88, 54, 22))


def pouch():
    im = Image.new('RGBA', (N, N)); d = ImageDraw.Draw(im)
    lt, md, dk = (238, 212, 162, 255), (214, 182, 128, 255), (172, 138, 88, 255)
    d.ellipse([5, 9, 19, 22], fill=md)                           # sack
    d.ellipse([6, 10, 11, 17], fill=lt)
    d.arc([5, 9, 19, 22], 300, 80, fill=dk, width=2)
    d.polygon([(8, 9), (10, 5), (12, 7), (14, 4), (16, 9)], fill=md)  # ruffled top
    d.line([(8, 9), (16, 9)], fill=(140, 84, 44, 255), width=2)  # its tie
    for x, y in ((11, 3), (14, 2), (12, 1)):
        d.point([(x, y)], fill=(120, 80, 40, 255))               # seeds
    return finish(im, (92, 62, 32))


if __name__ == '__main__':
    out = os.path.join(sys.argv[1], 'assets', 'art', 'home')
    for name, fn in (('prop_watering_can', can), ('prop_basket', basket), ('prop_seed_pouch', pouch)):
        fn().save(os.path.join(out, name + '.webp'), 'WEBP', lossless=True)

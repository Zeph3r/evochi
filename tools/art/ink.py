"""Inking a rendered map so it sits with the characters (who are drawn with dark ink outlines and crisp
flat shading): a line wherever one surface stands in front of another (a wall against the ground behind
it, a roof's eave over its wall, a canopy over the grass, a post against the path), found from the
render's own depth (world z) and height per pixel, and a touch more contrast and colour.

    ink(rgb, z, alpha, height) -> rgb          (uint8 arrays, the same size)
"""
import numpy as np
from scipy import ndimage

INK = np.array([59, 41, 35], np.float32)       # the characters' outline colour (#3B2923)


def edges(z, a, y, dz=1.0, dy=0.9):
    """Pixels on the near side of a step in depth or height (the surface in front)."""
    z = np.where(a > 0.5, z, -1e3)
    e = np.zeros(z.shape, bool)
    for sh in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        zn = np.roll(z, sh, (0, 1))
        yn = np.roll(y, sh, (0, 1))
        e |= (z - zn > dz)                      # the neighbour is farther: this pixel's surface stands in front
        e |= (y - yn > dy) & (z >= zn - 0.25)   # or it stands higher than its neighbour at about the same depth
    e[:1] = e[-1:] = False
    e[:, :1] = e[:, -1:] = False
    return e & (a > 0.5)


def ink(rgb, z, a, y, width=3, strength=0.72, pop=0.08, sharpen=True):
    rgb = rgb.astype(np.float32)
    e = edges(z, a, y)
    if width > 1:
        e = ndimage.binary_dilation(e, iterations=width - 1) & (a > 0.5)
    soft = ndimage.gaussian_filter(e.astype(np.float32), 0.6)
    k = np.clip(soft * 1.4, 0, 1)[..., None] * strength
    out = rgb * (1 - k) + INK * k
    # a little more contrast and colour, so the world reads as crisply as the sprites on it
    lum = out.mean(-1, keepdims=True)
    out = lum + (out - lum) * (1 + pop * 1.6)
    out = (out - 128) * (1 + pop) + 128
    out = np.clip(out + 0.5, 0, 255).astype(np.uint8)
    if sharpen:                                  # the render's soft edges, crisp like the sprites'
        from PIL import Image, ImageFilter
        out = np.asarray(Image.fromarray(out).filter(ImageFilter.UnsharpMask(radius=1.4, percent=60, threshold=2)))
    return out

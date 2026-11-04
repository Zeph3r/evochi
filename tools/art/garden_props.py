"""The garden helper's telekinesis props, modelled in voxels and drawn with the crops' own camera, light and
outline (home_items.py's CROP_CAM: looking down at about 40 degrees), so they sit in the Garden like the crops
and the Evochi do:
  prop_watering_can   a tin can, its spout to the left (toward the bed), a sprinkler rose, a hoop handle at
                      the back, a leaf on its side
  prop_basket         a woven basket with a rim and a bent-wood handle
  prop_seed_pouch     a burlap pouch, tied at the neck, a few seeds at its mouth

    python3 tools/art/garden_props.py flutter      -> flutter/assets/art/home/prop_*.webp
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from voxel import render, save_rgba, fit_camera  # noqa: E402
from items import M_, ell, cyl  # noqa: E402
from build_items import LIGHT  # noqa: E402
from home_items import CROP_CAM, put, LEAF, LEAF_HI, LEAF_LO  # noqa: E402

TIN, TIN_HI, TIN_LO, TIN_DK = '#A9C2C6', '#DDEBEA', '#7F9AA2', '#556970'
WICK, WICK_HI, WICK_LO, WICK_DK = '#D29A55', '#EDBD78', '#AE7437', '#6E4424'
SACK, SACK_HI, SACK_LO, TIE = '#D9B98A', '#EED7AC', '#B8946A', '#9A5E34'


def along(M, a, b, r):
    """a round rod from a to b"""
    a, b = np.array(a, float), np.array(b, float)
    d = b - a
    L = np.linalg.norm(d)
    P = np.stack([M.X - a[0], M.Y - a[1], M.Z - a[2]], -1)
    t = np.clip((P @ d) / (L * L), 0, 1)
    q = P - t[..., None] * d
    return (q ** 2).sum(-1) <= r * r


def can():
    M = M_((-5, 0, -2), (4, 5, 2), res=6)  # (whole units: the grid snaps to them)
    body = cyl(M, (0, 1.15, 0), 1.25, 2.3)
    put(M, body, TIN)
    put(M, body & (M.X < -0.45) & (M.Z > -0.2), TIN_HI)             # the light side
    put(M, body & (M.X > 0.7), TIN_LO)
    put(M, body & (np.abs(M.Y - 0.35) < 0.12), TIN_LO)               # a seam round its foot
    put(M, cyl(M, (0, 2.32, 0), 1.33, 0.18), TIN_HI)                 # the rim
    put(M, cyl(M, (0, 2.36, 0), 1.0, 0.2), TIN_DK)                   # its mouth
    # the spout, out to the left and up, and its rose
    put(M, along(M, (-0.9, 0.7, 0), (-3.3, 2.5, 0), 0.26), TIN)
    put(M, along(M, (-0.9, 0.7, 0), (-3.3, 2.5, 0), 0.26) & (M.Y > 1.3 - 0.0 * M.X) & (M.Z > 0.05), TIN_HI)
    rose = along(M, (-3.25, 2.45, 0), (-3.75, 2.85, 0), 0.5)
    put(M, rose, TIN_LO)
    put(M, rose & (np.abs(M.Z) < 0.42) & ((np.round(M.Z * 4) + np.round(M.Y * 4)) % 2 == 0) & (M.X < -3.6), TIN_DK)
    # the hoop handle at the back
    for k in np.linspace(-np.pi / 2, np.pi / 2, 28):
        cx, cy = 1.25 + 0.95 * np.cos(k), 1.45 + 0.95 * np.sin(k)
        put(M, ell(M, (cx, cy, 0), (0.24, 0.24, 0.24)), TIN_LO)
    # a leaf on its side
    leaf = (M.Z > 1.0) & body & ((((M.X + 0.05) / 0.5) ** 2 + ((M.Y - 1.25) / 0.75) ** 2) <= 1) & (np.abs(M.X + 0.05 - (M.Y - 1.25) * 0.35) < 0.5)
    put(M, leaf, LEAF)
    put(M, leaf & (M.X < -0.1), LEAF_HI)
    put(M, leaf & (np.abs(M.X + 0.05 - (M.Y - 1.25) * 0.3) < 0.06), LEAF_LO)
    return M


def basket():
    M = M_((-3, 0, -2), (3, 5, 2), res=6)
    r = np.sqrt((M.X / 1.8) ** 2 + (M.Z / 1.35) ** 2)
    taper = 0.84 + 0.16 * np.clip(M.Y / 1.7, 0, 1)           # wider at the top
    shell = (r <= taper) & (r >= taper - 0.3) & (M.Y >= 0) & (M.Y < 1.7)
    floor = (r <= taper) & (M.Y >= 0) & (M.Y < 0.18)
    # woven: bands round it, crossed by upright stakes
    band = (np.floor(M.Y / 0.25) % 2 == 0)
    ang = np.arctan2(M.Z, M.X)
    stake = (np.abs(((ang / (np.pi / 9)) % 1) - 0.5) < 0.13)
    put(M, shell | floor, WICK)
    put(M, shell & ~band, WICK_LO)
    put(M, shell & stake, WICK_DK)
    put(M, shell & band & (M.X < -0.4) & ~stake, WICK_HI)
    put(M, floor & (r < taper - 0.3) & (M.Y > 0.08), WICK_DK)      # inside, in shadow
    # the rim, a rolled edge
    put(M, (np.abs(r - 0.92) < 0.17) & (M.Y >= 1.62) & (M.Y < 1.88), WICK_HI)
    # the handle: a thin bent-wood hoop standing up over it, left to right
    for k in np.linspace(0, np.pi, 48):
        put(M, ell(M, (1.62 * np.cos(k), 1.75 + 2.5 * np.sin(k), 0), (0.19, 0.19, 0.22)), WICK_DK if abs(np.cos(k)) < 0.93 else WICK_LO)
    return M


def pouch():
    M = M_((-2, 0, -2), (2, 4, 2), res=6)
    # a pear of a sack, pinched at the neck, its mouth flaring open
    yy = np.clip(M.Y / 2.0, 0, 1)
    rad = 1.2 - 0.75 * yy ** 1.6
    sack = ((M.X ** 2 + (M.Z / 0.9) ** 2) <= rad ** 2) & (M.Y >= 0) & (M.Y < 2.0)
    sack &= ~((M.Y < 0.25) & ((M.X ** 2 + (M.Z / 0.9) ** 2) > (rad * 0.8) ** 2))  # a rounded foot
    frill = ((M.X ** 2 + (M.Z / 0.9) ** 2) <= (0.42 + 0.5 * np.clip((M.Y - 2.0) / 0.7, 0, 1)) ** 2) & (M.Y >= 2.0) & (M.Y < 2.7)
    put(M, sack, SACK)
    put(M, sack & (M.X < -0.3) & (M.Y > 0.5), SACK_HI)
    put(M, sack & (M.X > 0.55), SACK_LO)
    put(M, frill, SACK_HI)
    put(M, frill & (M.Y > 2.55) & ((M.X ** 2 + (M.Z / 0.9) ** 2) < 0.6 ** 2), '#6E4C2E')   # its open mouth
    put(M, ((M.X ** 2 + (M.Z / 0.9) ** 2) <= 0.52 ** 2) & (np.abs(M.Y - 2.02) < 0.11), TIE)  # the tie
    put(M, along(M, (0.45, 2.0, 0.45), (0.85, 1.45, 0.75), 0.1), TIE)                        # its end
    for (x, z) in ((0.12, 0.15), (-0.2, -0.05), (0.02, -0.25)):
        put(M, ell(M, (x, 2.72, z), (0.13, 0.11, 0.13)), '#C9A46A')                          # seeds
    return M


def draw(M, size=288):
    filled = M.m > 0
    pts = np.stack([M.X[filled], M.Y[filled], M.Z[filled]], -1)
    fit = fit_camera(CROP_CAM, pts, size, size, margin=0.07)
    o = render(M, {}, CROP_CAM, size, size, fit=fit, light=LIGHT, ss=3, outline_px=2.6, outline_col='#3B2923',
               inner_thresh=2.0, inner_alpha=0.45, inner_px=0.7)
    return o.rgba


if __name__ == '__main__':
    out = os.path.join(sys.argv[1], 'assets', 'art', 'home')
    for name, fn in (('prop_watering_can', can), ('prop_basket', basket), ('prop_seed_pouch', pouch)):
        rgba = draw(fn())
        tmp = os.path.join(out, name + '.png')
        save_rgba(rgba, tmp)
        Image.open(tmp).save(os.path.join(out, name + '.webp'), 'WEBP', quality=90, method=6)
        os.remove(tmp)
        print(name, flush=True)

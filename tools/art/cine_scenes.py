"""The onboarding's cinematic scenes (rendered by cine_blender.py): the Fading Paths cold open and the
beats after it, built in the village's voxel language (village_scenes.py) at a finer grain, because the
camera gets close.

  lumen_print        the golden Lumen footprint: the one motif the whole onboarding shares (the black
                     opening, the step screen, the egg's cracks, the lit path after naming)
  map_lit            Alder's map as a diorama on his desk, every trail lit in gold
  map_faded          the same map with the trails faded to old ink
  map_hollow         the faded map with the Hollow's violet crystals and vines creeping in from its edges
                     (the app reveals it from the edges over map_faded)

Each map state is the same camera, so the app crossfades and reveals between them; cine.json carries the
trails as polylines in plate pixels, so the app can light them up along their length.
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from voxel import Model                                                        # noqa: E402
import village_scenes as V                                                     # noqa: E402
from village_scenes import (VScene, CPainter, box, ball, cyl_y, lantern, OAK, OAK_DARK, WALNUT, HONEY,   # noqa: E402
                            BRASS, IRON, COPPER, PLASTER, STONE, STONE_LT, LEAF, SAGE, CLEAR_GLASS, PARCH, ROOF,
                            GRASS, WATERC, TERRACOTTA, FLOWERS, MINT)

# ------------------------------------------------------------------------------------------------ colours ----
LUMEN = ['#FFC24E', '#FFCB5E', '#F9B53E']          # the trails' gold
LUMEN_HI = ['#FFF3C0']
INK_OLD = ['#A88A66', '#9C7E5B']                    # the trails as faded ink
PARCH_MAP = ['#DCC79C', '#D6C094', '#E1CDA4', '#D1BB8E']
PARCH_EDGE = ['#B89E74', '#AE946C']
HOLLOW_V = ['#8A5FD6', '#9A70E4', '#7A52C4']
HOLLOW_HI = ['#C9A8FF', '#E0C8FF']
HOLLOW_DK = ['#4A3570', '#3E2C5E', '#56407E']
HOLLOW_VINE = ['#5D4A86', '#6B5698']
MOSS_MAP = ['#6F9A52', '#7CA75E', '#659148', '#88B268']
GRASS_MAP = ['#7FAA5C', '#76A153', '#88B465', '#6E9A4E', '#8DB868']
AUTUMN = ['#D9A24A', '#E0B35C', '#C98A3C']
SNOW = ['#F6F4EE', '#ECEAE3']
SAND = ['#E8D7A8', '#DFCC9B']
WATER_MAP = ['#5FAFD2', '#55A3C8', '#6DBBDC', '#4F9ABF']
GLASS_WARM = ['#FFF0D2', '#FBE8C4']                 # the Glasshouse's panes at night, lit from inside

# The cast in close-up: the game's own models at twice its voxel grain (the same shapes, finer steps), so a
# character that fills the screen doesn't break into blocks. Faces and markings are painted decals, so they
# don't change. The renderer gives every actor a smooth shadow stand-in (cine_blender.actor_arrays).
CAST_RES = 4

# ------------------------------------------------------------------------------------------------ grades ----
GRADES = {
    'map': {'bloom': 0.5, 'bloom_threshold': 175.0, 'bloom_wide': 0.22, 'glow': 0.16, 'warm': 0.05,
            'split': {'highlights': '#FFD9A0', 'shadows': '#4E4C8C', 'amount': 0.10}, 'saturation': 1.08,
            'vignette': 0.30, 'vignette_start': 0.30, 'grain': 0.012,
            'mist': {'start': 5.0, 'end': 10.0, 'amount': 0.18, 'color': '#3B2E4A', 'power': 1.2}},
}


# ------------------------------------------------------------------------------------------- small tools ----
def catmull(pts, n=240):
    """a smooth curve through 2D control points"""
    P = np.asarray(pts, np.float64)
    if len(P) < 3:
        return P
    P = np.vstack([P[0], P, P[-1]])
    out = []
    per = max(2, n // (len(P) - 3))
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for t in np.linspace(0, 1, per, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(P[-2])
    return np.array(out)


def dist2d(X2, Z2, poly):
    """distance from every (x, z) grid point to a polyline, and the parameter (0-1 along it) of the nearest point"""
    d = np.full(X2.shape, 1e9)
    tbest = np.zeros(X2.shape)
    seg = np.linalg.norm(np.diff(poly, axis=0), axis=1)
    cum = np.concatenate([[0], np.cumsum(seg)])
    L = cum[-1]
    for i in range(len(poly) - 1):
        a, b = poly[i], poly[i + 1]
        ab = b - a
        l2 = ab @ ab
        if l2 < 1e-9:
            continue
        t = np.clip(((X2 - a[0]) * ab[0] + (Z2 - a[1]) * ab[1]) / l2, 0, 1)
        dd = np.sqrt((X2 - (a[0] + t * ab[0])) ** 2 + (Z2 - (a[1] + t * ab[1])) ** 2)
        better = dd < d
        d = np.where(better, dd, d)
        tbest = np.where(better, (cum[i] + t * seg[i]) / L, tbest)
    return d, tbest


def noise2(X2, Z2, seed=1, scale=6.0, octaves=3):
    """cheap value noise on a grid, 0..1"""
    rng = np.random.default_rng(seed)
    out = np.zeros(X2.shape)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        f = (2 ** o) / scale
        ph = rng.uniform(0, 100, 4)
        out += amp * (0.5 + 0.25 * (np.sin(X2 * f * 1.7 + ph[0]) * np.cos(Z2 * f * 1.3 + ph[1]) +
                                    np.sin((X2 + Z2) * f * 0.9 + ph[2]) * np.sin((X2 - Z2) * f * 1.1 + ph[3])))
        tot += amp
        amp *= 0.5
    return out / tot


def column(M, cx, cz, r, y0, y1, p=2.0):
    return ((np.abs(M.X - cx) / r) ** p + (np.abs(M.Z - cz) / r) ** p <= 1.0) & (M.Y >= y0) & (M.Y < y1)


class Local:
    """evaluate a small shape only inside its bounding box: `with Local(M, lo, hi) as L:` gives L.X, L.Y, L.Z
    (the slices of the grid) and L.full(mask) lifts a local mask to the full grid"""

    def __init__(self, M, lo, hi):
        self.M = M
        r = M.res
        i0 = np.clip(np.floor(np.asarray(lo, float) * r).astype(int) - M.lo, 0, np.array(M.m.shape))
        i1 = np.clip(np.ceil(np.asarray(hi, float) * r).astype(int) - M.lo, 0, np.array(M.m.shape))
        self.sl = tuple(slice(int(a), int(b)) for a, b in zip(i0, i1))
        self.X, self.Y, self.Z = M.X[self.sl], M.Y[self.sl], M.Z[self.sl]
        self.m = M.m[self.sl]

    def full(self, mask):
        out = np.zeros(self.M.m.shape, bool)
        out[self.sl] = mask
        return out

    def ball(self, c, r, sy=1.0):
        return (self.X - c[0]) ** 2 + ((self.Y - c[1]) / sy) ** 2 + (self.Z - c[2]) ** 2 <= r * r

    def column(self, cx, cz, r, y0, y1, p=2.0):
        return ((np.abs(self.X - cx) / r) ** p + (np.abs(self.Z - cz) / r) ** p <= 1.0) & (self.Y >= y0) & (self.Y < y1)

    def box(self, lo, hi):
        return ((self.X >= lo[0]) & (self.X < hi[0]) & (self.Y >= lo[1]) & (self.Y < hi[1]) & (self.Z >= lo[2]) & (self.Z < hi[2]))


def tiny_tree(M, P, x, z, y, r, h, pal, top):
    L = Local(M, (x - r - 0.5, y - 0.2, z - r - 0.5), (x + r + 0.5, y + h + r * 2.2, z + r + 0.5))
    P.fill(L.full(L.column(x, z, max(0.16, r * 0.3), y, y + h + r * 0.6)), ['#6E4A2E', '#7A5234'], cell=9)
    can = L.ball((x, y + h + r * 0.7, z), r, 1.05) & (L.m == 0)
    P.fill(L.full(can), pal, cell=0.5)
    P.fill(L.full(can & (L.Y > y + h + r * 1.05)), top, cell=0.5)


def crystal(M, P, base, tip, r, cols, hi, glow=1.0):
    """a tapered crystal spike from base to tip (both (x, y, z)), r at the base"""
    base, tip = np.asarray(base, float), np.asarray(tip, float)
    L_ = Local(M, np.minimum(base, tip) - r - 0.5, np.maximum(base, tip) + r + 0.5)
    d = tip - base
    L = np.linalg.norm(d)
    d = d / max(L, 1e-6)
    Pv = np.stack([L_.X - base[0], L_.Y - base[1], L_.Z - base[2]], -1)
    t = Pv @ d
    perp = Pv - t[..., None] * d
    rr = np.linalg.norm(perp, axis=-1)
    tn = np.clip(t / L, 0, 1)
    m = (t >= 0) & (t <= L) & (rr <= r * (1 - 0.85 * tn))
    P.fill(L_.full(m & (L_.m == 0)), cols, glow=glow, cell=0.5)
    P.fill(L_.full(m & (rr <= r * 0.35 * (1 - 0.85 * tn))), hi, glow=glow * 1.4, cell=9)
    return m


# ---------------------------------------------------------------------------------- the Lumen footprint ----
def lumen_print_mask(M, pos, heading=0.0, s=1.0):
    """the Eggling's foot as a print on the ground: a rounded pad and three claws, heading in degrees (0 = +z)"""
    x, y, z = pos
    a = math.radians(heading)
    dx, dz = M.X - x, M.Z - z
    u = dx * math.cos(a) - dz * math.sin(a)          # across
    v = dx * math.sin(a) + dz * math.cos(a)          # along (toward the toes)
    pad = ((np.abs(u) / (3.1 * s)) ** 3 + (np.abs(v + 0.4 * s) / (3.2 * s)) ** 3) <= 1.0
    toes = np.zeros(M.m.shape, bool)
    for tu in (-2.0, 0.0, 2.0):
        toes |= ((u - tu * s) ** 2 / (0.75 * s) ** 2 + (v - 3.9 * s) ** 2 / (1.1 * s) ** 2) <= 1.0
    return (pad | toes) & (M.Y >= y) & (M.Y < y + 0.5 * s)


def foot_mask2d(M, x, z, heading=0.0, s=1.0):
    """the Eggling's foot on the ground plane (every height): the same pad and three claws as lumen_print_mask"""
    a = math.radians(heading)
    dx, dz = M.X - x, M.Z - z
    u = dx * math.cos(a) - dz * math.sin(a)
    v = dx * math.sin(a) + dz * math.cos(a)
    pad = ((np.abs(u) / (3.1 * s)) ** 3 + (np.abs(v + 0.4 * s) / (3.2 * s)) ** 3) <= 1.0
    toes = np.zeros(M.m.shape, bool)
    for tu in (-2.0, 0.0, 2.0):
        toes |= ((u - tu * s) ** 2 / (0.75 * s) ** 2 + (v - 3.9 * s) ** 2 / (1.1 * s) ** 2) <= 1.0
    return pad | toes


def press_print(P, M, x, z, heading=0.0, s=1.0, glow=0.3, ground_top=0.0, depth=1, colors=('#E3A146', '#D9963E'), rim=0.0):
    """a footprint pressed into the ground, not stood on it: the top [depth] voxel layers under the foot taken
    out, and the floor of the dent lit faintly from within (Lumen left in the step). Faint by design: a trail of
    them reads as footsteps left behind."""
    foot = foot_mask2d(M, x, z, heading, s)
    cell = 1.0 / M.res
    dent = foot & (M.Y < ground_top) & (M.Y >= ground_top - depth * cell)
    M.m[dent] = 0
    M.glow[dent] = 0.0
    floor = foot & (M.Y < ground_top - depth * cell) & (M.Y >= ground_top - (depth + 1) * cell)
    P.fill(floor, list(colors), glow=glow, cell=9)
    # the light pools toward the middle of the step and thins at its edges
    r = np.sqrt((M.X - x) ** 2 + (M.Z - z) ** 2) / (4.2 * s)
    M.glow[floor] = (glow * np.clip(1.15 - 0.6 * r, 0.45, 1.0))[floor]
    if rim > 0:
        # the pressed edge catching a little of it, on the ground around the dent
        from scipy import ndimage
        top = (M.Y < ground_top) & (M.Y >= ground_top - cell)
        edge = ndimage.binary_dilation(foot & top, iterations=1) & top & ~foot & (M.m > 0)
        M.glow[edge] = np.maximum(M.glow[edge], rim)
    return foot


def scene_lumen_print():
    """the footprint alone, glowing on black: an additive sprite (the app draws it with a plus / screen blend) for
    the black opening, the step screen, the egg's cracks and the lit path after naming. The plate is square; the
    print heads up the picture, its glow fading into the black around it."""
    cam = {'pos': (0.0, 26.0, 12.0), 'target': (0.0, 0.0, 0.4), 'fov': 32.0}
    S = VScene('lumen_print', 720, 720, cam, world=((0.0, 0.0, 0.0), 0.0), samples=64, transparent=False)
    M = Model((-10, -2, -10), (10, 3, 10), [], res=4)
    P = CPainter(M, 5)
    # dark ground, the footprint pressed into it two voxels deep, the light pooled in the dent (and spilling
    # onto its walls), not a raised stamp
    P.fill((M.Y >= -1.5) & (M.Y < 0.0), ['#2A2530', '#26212C'], cell=0.5)
    press_print(P, M, 0.0, 0.0, 180.0, 1.0, glow=0.95, depth=2, colors=('#F4A83A', '#FAB446'), rim=0.16)
    S.models.append((M, ()))
    S.exposure = -0.8
    S.grade = {'bloom': 0.7, 'bloom_threshold': 120.0, 'bloom_wide': 0.5, 'glow': 0.2, 'lift': (-0.08, -0.08, -0.08)}
    S.zmax = 10.0
    return S


# ----------------------------------------------------------------------------------------- Alder's map ----
MAP_X0, MAP_X1, MAP_Z0, MAP_Z1 = -27.0, 27.0, -19.0, 19.0       # the parchment
MAP_RES = 4

# where the trails go (map coordinates x, z; z grows toward the viewer, so the village sits at the bottom)
PLACES = {
    'village': (0.0, 9.5), 'ruins': (17.0, -8.5), 'gate': (-2.0, -14.0), 'cliffs': (-19.0, -4.0),
    'cove': (20.0, 6.0), 'grove': (-14.0, 11.0), 'lake': (12.0, -1.0),
}
TRAILS = {
    'ruins': [(2.5, 8.0), (7.0, 5.5), (10.5, 1.0), (13.5, -4.0), (17.0, -8.5)],
    'gate': [(-1.0, 7.0), (-2.5, 2.0), (-1.0, -4.0), (-3.5, -9.0), (-2.0, -14.0)],
    'cliffs': [(-2.5, 8.5), (-7.0, 6.0), (-11.0, 2.0), (-15.5, -1.0), (-19.0, -4.0)],
    'cove': [(3.0, 10.0), (8.0, 9.5), (13.0, 8.5), (17.0, 7.5), (20.0, 6.0)],
    'grove': [(-3.0, 10.5), (-7.0, 11.5), (-10.5, 12.5), (-14.0, 11.0)],
}
REIGNITE = 'grove'   # the stretch near the village that flickers back


def map_height(X2, Z2):
    """the relief on the parchment (units above the sheet), 0 off the sheet"""
    h = np.zeros(X2.shape)
    # rolling hills
    for (cx, cz, r, hh) in ((-9.0, 4.0, 7.5, 0.9), (9.0, 3.0, 6.0, 0.8), (-16.0, 12.0, 6.5, 0.9), (16.0, 12.0, 5.0, 0.6),
                            (4.0, -8.0, 7.0, 0.8), (-10.0, -12.0, 6.0, 0.7), (22.0, -5.0, 5.0, 0.6)):
        d = np.sqrt((X2 - cx) ** 2 + (Z2 - cz) ** 2) / r
        h += hh * np.clip(1 - d * d, 0, 1) ** 1.3
    # the mountains, top left
    for (cx, cz, r, hh) in ((-19.0, -14.0, 4.6, 3.6), (-14.5, -16.0, 3.6, 2.8), (-23.0, -10.5, 3.2, 2.4), (-10.0, -16.5, 2.6, 1.9),
                            (-21.5, -16.5, 3.0, 2.2)):
        d = np.sqrt((X2 - cx) ** 2 + (Z2 - cz) ** 2) / r
        h = np.maximum(h, hh * np.clip(1 - d, 0, 1) ** 0.8 * (1 + 0.25 * np.sin(np.arctan2(Z2 - cz, X2 - cx) * 5)))
    h += 0.22 * noise2(X2, Z2, seed=4, scale=5.0)
    return h


def scene_map(state='lit'):
    """Alder's map: a diorama on his desk. state: 'lit' | 'faded' | 'hollow'"""
    cam = {'pos': (0.0, 62.0, 30.0), 'target': (0.0, 0.5, -2.0), 'fov': 56.0, 'focus': (0.0, 1.0, 4.0), 'fstop': 1.4}
    S = VScene('map_' + state, 1400, 1800, cam, world=((0.14, 0.12, 0.22), 0.22), samples=160, transparent=False)
    S.lights.append({'type': 'area', 'pos': (-30.0, 50.0, -30.0), 'aim': (0.0, 0.0, 0.0), 'size': (40.0, 40.0),
                     'power': 420.0, 'color': (0.5, 0.62, 1.0)})             # cool window light from the top left
    S.lights.append({'type': 'area', 'pos': (14.0, 36.0, 44.0), 'aim': (0.0, 0.0, 4.0), 'size': (30.0, 30.0),
                     'power': 150.0, 'color': (1.0, 0.8, 0.6)})              # a soft warm fill from the viewer's side
    S.grade = dict(GRADES['map'])
    S.zmax = 12.0
    rng = np.random.default_rng(23 + hash(state) % 7)
    M = Model((-52, -4, -36), (52, 16, 44), [], res=MAP_RES)
    P = CPainter(M, 23)
    X2, Z2 = M.X[:, 0, :], M.Z[:, 0, :]
    # ---- the desk: dark walnut planks, a grain line every plank
    desk = (M.Y >= -3.0) & (M.Y < 0.0)
    P.fill(desk, ['#5B3A24', '#54351F', '#633F28', '#4E3220'], cell=(5.0, 9, 60.0))
    P.fill(desk & (M.Y >= -0.25) & ((((M.X + 100) % 5.0) < 0.2)), ['#3E2616'], cell=9)
    P.fill(desk & (M.Y >= -0.25) & (noise2(M.X[:, 0, :], M.Z[:, 0, :], 9, 2.0, 2)[:, None, :] > 0.62), ['#684428'], cell=(0.5, 9, 3.0))
    # ---- the parchment: torn edges, curled corners, a faint grid and compass rose drawn in ink
    edge_n = noise2(X2, Z2, 11, 2.2, 3)
    inx = np.minimum(X2 - MAP_X0, MAP_X1 - X2)
    inz = np.minimum(Z2 - MAP_Z0, MAP_Z1 - Z2)
    inset = np.minimum(inx, inz)
    sheet2 = (inset > -0.4 + 0.9 * (edge_n - 0.5)) & (inx > -0.5) & (inz > -0.5)
    curl = np.clip(1.0 - inset / 6.0, 0, 1) ** 2.2 * 1.6 * (edge_n > 0.35)
    curl = curl * np.clip(1.0 - np.minimum(inx, inz) / 9.0, 0, 1)
    sheet_y0 = 0.0 + curl
    sheet = sheet2[:, None, :] & (M.Y >= sheet_y0[:, None, :]) & (M.Y < sheet_y0[:, None, :] + 0.5)
    P.fill(sheet, PARCH_MAP, cell=(1.5, 9, 1.5))
    P.fill(sheet & (inset[:, None, :] < 1.2), PARCH_EDGE, cell=(0.5, 9, 0.5))
    stain = noise2(X2, Z2, 17, 7.0, 2)
    P.fill(sheet & (stain[:, None, :] > 0.64), ['#DCC79C', '#D6C094'], cell=(1.0, 9, 1.0))
    # ink: a border line and a compass rose in the bottom right corner of the sheet
    top = sheet & (M.Y >= sheet_y0[:, None, :] + 0.25)
    border = (np.abs(inset - 1.8) < 0.18)[:, None, :]
    P.fill(top & border, ['#7A5A3C'], cell=9)
    rx, rz = 21.5, 14.0
    rr = np.sqrt((X2 - rx) ** 2 + (Z2 - rz) ** 2)
    ang = np.arctan2(Z2 - rz, X2 - rx)
    rose = ((np.abs(rr - 2.6) < 0.18) | ((rr < 2.5) & (np.abs(np.sin(2 * ang)) < 0.06 + 0.25 * (1 - rr / 2.5))))[:, None, :]
    P.fill(top & rose, ['#7A5A3C'], cell=9)
    P.fill(top & ((rr < 2.5) & (np.abs(np.sin(2 * ang + math.pi / 2)) < 0.03 + 0.18 * (1 - rr / 2.5)))[:, None, :], ['#B5533C'], cell=9)
    # ---- the land: a relief of grass over the sheet, a margin of bare parchment around it
    land2 = sheet2 & (inset > 3.2 + 0.8 * (noise2(X2, Z2, 19, 3.0, 2) - 0.5))
    H = map_height(X2, Z2)
    # the land thins to a painted edge: its thickness fades out over the last few units
    fade = np.clip((inset - 3.2) / 3.0, 0, 1)
    H = H * fade
    Hs = np.where(land2, 0.15 + 0.2 * fade + H, 0.0)
    ground_top = (sheet_y0 + Hs)[:, None, :]
    land = land2[:, None, :] & (M.Y >= sheet_y0[:, None, :] + 0.5) & (M.Y < ground_top)
    P.fill(land, GRASS_MAP, cell=(0.75, 0.75, 0.75))
    gn = noise2(X2, Z2, 31, 2.5, 3)[:, None, :]
    P.fill(land & (gn > 0.6), MOSS_MAP, cell=0.5)
    P.fill(land & (gn < 0.36), ['#9CC76E', '#A6CF7A'], cell=0.5)
    # the land's cut edge shows soil
    soil_edge = land2 & ~(np.roll(land2, 2, 0) & np.roll(land2, -2, 0) & np.roll(land2, 2, 1) & np.roll(land2, -2, 1))
    P.fill(land & soil_edge[:, None, :], ['#A07A52', '#946F48'], cell=0.5)
    # mountains: stone, snow on top
    mtn = land & (H[:, None, :] > 1.3) & (X2[:, None, :] < -5.0) & (Z2[:, None, :] < -6.0)
    P.fill(mtn, ['#9C968C', '#8E887E', '#A8A297', '#837D74'], cell=0.5)
    P.fill(mtn & (M.Y > sheet_y0[:, None, :] + 0.5 + 2.9), SNOW, cell=0.5)
    # ---- the lake and the river (water material), sandy rims
    lx, lz = PLACES['lake']
    lake2 = (((X2 - lx) / 5.2) ** 2 + ((Z2 - lz) / 3.4) ** 2 + 0.25 * (noise2(X2, Z2, 41, 2.0, 2) - 0.5)) < 1.0
    riv = catmull([(-16.0, -12.0), (-12.0, -8.5), (-8.0, -4.5), (-3.5, -1.5), (1.5, -1.0), (6.5, -0.5), (lx - 3.0, lz)], 140)
    dr, _ = dist2d(X2, Z2, riv)
    river2 = (dr < 0.85 + 0.25 * np.sin(Z2 * 1.3)) & land2 & ~lake2
    water2 = lake2 | river2
    wy = (sheet_y0 + Hs - 0.45)[:, None, :]
    M.m[land & water2[:, None, :] & (M.Y >= wy)] = 0
    P.fill(land2[:, None, :] & water2[:, None, :] & (M.Y >= wy - 0.5) & (M.Y < wy), WATER_MAP, cell=(1.0, 9, 1.0))
    rim2 = (lake2 | river2)
    rim2 = (np.roll(rim2, 1, 0) | np.roll(rim2, -1, 0) | np.roll(rim2, 1, 1) | np.roll(rim2, -1, 1) |
            np.roll(rim2, 2, 0) | np.roll(rim2, -2, 0) | np.roll(rim2, 2, 1) | np.roll(rim2, -2, 1)) & ~water2
    P.fill(land & rim2[:, None, :] & (M.Y >= ground_top - 0.5), SAND, cell=0.5)
    # the trails' distance field, so groves keep off the paths
    dtrail = np.full(X2.shape, 1e9)
    for key, ctrl in TRAILS.items():
        d, _ = dist2d(X2, Z2, catmull(ctrl, 160))
        dtrail = np.minimum(dtrail, d)
    # ---- groves: hundreds of tiny trees in woods, a few in autumn colour, none on the paths or at the places
    trees = []
    wood = noise2(X2, Z2, 53, 4.0, 3)
    for _ in range(2400):
        x, z = rng.uniform(MAP_X0 + 4, MAP_X1 - 4), rng.uniform(MAP_Z0 + 4, MAP_Z1 - 4)
        ix, iz = int((x - M.lo[0] / M.res) * M.res), int((z - M.lo[2] / M.res) * M.res)
        if not land2[ix, iz] or water2[ix, iz] or H[ix, iz] > 2.0 or dtrail[ix, iz] < 1.3:
            continue
        if wood[ix, iz] < 0.56 and rng.random() > 0.12:
            continue
        if any(math.hypot(x - px, z - pz) < 3.2 for px, pz in PLACES.values()):
            continue
        if any(math.hypot(x - tx, z - tz) < 0.55 for tx, tz, _ in trees[-60:]):
            continue
        trees.append((x, z, Hs[ix, iz] + sheet_y0[ix, iz]))
        if len(trees) >= 520:
            break
    for (x, z, y) in trees:
        r = rng.uniform(0.3, 0.62)
        h = rng.uniform(0.35, 0.8)
        pal = LEAF if rng.random() > 0.07 else AUTUMN
        tiny_tree(M, P, x, z, y, r, h, pal, [pal[0], '#86C56A' if pal is LEAF else '#E5BE68'])
    # bushes and flowers in the open
    for _ in range(260):
        x, z = rng.uniform(MAP_X0 + 4, MAP_X1 - 4), rng.uniform(MAP_Z0 + 4, MAP_Z1 - 4)
        ix, iz = int((x - M.lo[0] / M.res) * M.res), int((z - M.lo[2] / M.res) * M.res)
        if not land2[ix, iz] or water2[ix, iz] or H[ix, iz] > 2.0:
            continue
        y = Hs[ix, iz] + sheet_y0[ix, iz]
        L = Local(M, (x - 1, y - 0.3, z - 1), (x + 1, y + 1.2, z + 1))
        if rng.random() < 0.55:
            P.fill(L.full(L.ball((x, y + 0.2, z), rng.uniform(0.3, 0.6), 0.7) & (L.m == 0)), MOSS_MAP, cell=0.5)
        else:
            P.fill(L.full(L.box((x - 0.15, y, z - 0.15), (x + 0.15, y + 0.45, z + 0.15))), [FLOWERS[rng.integers(5)]], cell=9)
    # ---- the places
    def ground_at(x, z):
        ix, iz = int((x - M.lo[0] / M.res) * M.res), int((z - M.lo[2] / M.res) * M.res)
        return float(Hs[ix, iz] + sheet_y0[ix, iz])

    def tiny_house(x, z, w, d, wall_h, roof_h, walls, roof, ridge='x', win=True):
        y = ground_at(x, z)
        V.gable(P, M, x - w / 2, x + w / 2, z - d / 2, z + d / 2, wall_h, roof_h, walls, roof, oh=0.35, ridge=ridge, y0=y,
                wall_cell=(0.75, 0.75, 0.75))
        if win:
            P.fill(box(M, (x - 0.35, y + 0.8, z + d / 2 - 0.3), (x + 0.35, y + 1.4, z + d / 2 + 0.3)), V.WIN_LIT, glow=0.9, cell=9)
        return y

    vx, vz = PLACES['village']
    tiny_house(vx - 2.6, vz - 0.4, 2.6, 2.2, 1.6, 1.2, PLASTER, ROOF, 'x')
    tiny_house(vx + 2.6, vz - 0.6, 2.4, 2.0, 1.4, 1.1, V.BRICK, ROOF, 'z')
    tiny_house(vx, vz - 3.6, 3.2, 2.2, 2.0, 1.4, PLASTER, ROOF, 'x')
    yv = ground_at(vx, vz)
    # the Waystone in the square and the Glasshouse by it
    P.fill(column(M, vx, vz + 0.6, 0.45, yv, yv + 0.3), STONE_LT, cell=9)
    P.fill(column(M, vx, vz + 0.6, 0.28, yv + 0.3, yv + 1.9), ['#D4C894', '#C9BC86'], cell=0.5)
    P.fill(column(M, vx, vz + 0.6, 0.1, yv + 0.9, yv + 1.7) & (M.Z > vz + 0.75), MINT, glow=1.0, cell=9)
    gh = box(M, (vx - 5.2, yv, vz + 0.4), (vx - 2.4, yv + 1.4, vz + 2.6))
    P.fill(gh, CLEAR_GLASS, cell=50)
    P.fill(gh & ((((M.X - vx + 5.2) % 0.7) < 0.2) | (np.abs(M.Y - yv - 0.7) < 0.12)), SAGE, cell=9)
    P.fill(box(M, (vx - 5.0, yv + 1.4, vz + 0.6), (vx - 2.6, yv + 2.0, vz + 2.4)) & (M.Y < yv + 2.0 - np.abs(M.Z - vz - 1.5) * 0.5), CLEAR_GLASS, cell=50)
    P.fill(box(M, (vx - 4.6, yv + 0.2, vz + 0.8), (vx - 3.0, yv + 0.9, vz + 2.2)), ['#FFD46A', '#FFE08A'], glow=1.1, cell=9)
    S.lights.append({'type': 'point', 'pos': (vx - 3.8, yv + 0.9, vz + 1.5), 'power': 2.5, 'color': 2700, 'radius': 0.6})
    # the Mossy Ruins: a broken arch and fallen stones in moss
    rx_, rz_ = PLACES['ruins']
    yr = ground_at(rx_, rz_)
    for sx in (-1.0, 1.0):
        P.fill(column(M, rx_ + sx, rz_, 0.35, yr, yr + 2.0), STONE, cell=0.5)
    P.fill(box(M, (rx_ - 1.3, yr + 1.9, rz_ - 0.3), (rx_ + 0.4, yr + 2.4, rz_ + 0.3)), STONE, cell=0.5)
    for (dx, dz, r) in ((1.6, 1.2, 0.5), (-1.8, 0.8, 0.4), (0.4, 1.9, 0.35)):
        P.fill(ball(M, (rx_ + dx, yr + 0.1, rz_ + dz), r, 0.6), STONE_LT, cell=0.5)
    P.fill(ball(M, (rx_ - 1.0, yr + 1.6, rz_), 0.6, 0.6) & (M.m == 0), MOSS_MAP, cell=0.5)
    # the Sentinel's Gate: two tall pillars with a lintel, a stone figure slumped between them
    gx, gz = PLACES['gate']
    yg = ground_at(gx, gz)
    for sx in (-1.4, 1.4):
        P.fill(box(M, (gx + sx - 0.4, yg, gz - 0.4), (gx + sx + 0.4, yg + 3.2, gz + 0.4)), STONE, cell=0.5)
    P.fill(box(M, (gx - 1.9, yg + 3.1, gz - 0.4), (gx + 1.9, yg + 3.7, gz + 0.4)), STONE, cell=0.5)
    P.fill(ball(M, (gx, yg + 0.8, gz + 0.6), 0.9, 0.9), ['#6E6A62', '#625E57'], cell=0.5)
    P.fill(ball(M, (gx, yg + 1.9, gz + 0.5), 0.5), ['#6E6A62'], cell=0.5)
    # Skyline Cliffs: a rock shelf with a little shrine lantern
    cx_, cz_ = PLACES['cliffs']
    yc = ground_at(cx_, cz_)
    P.fill(box(M, (cx_ - 1.8, yc, cz_ - 1.2), (cx_ + 1.8, yc + 1.2, cz_ + 1.2)), STONE, cell=0.75)
    P.fill(box(M, (cx_ - 0.3, yc + 1.2, cz_ - 0.3), (cx_ + 0.3, yc + 2.0, cz_ + 0.3)), IRON, cell=9)
    P.fill(box(M, (cx_ - 0.4, yc + 2.0, cz_ - 0.4), (cx_ + 0.4, yc + 2.6, cz_ + 0.4)), ['#FFD46A'], glow=0.8, cell=9)
    # the cove: a dock of planks into the lake's inlet and a boat
    ox, oz = PLACES['cove']
    yo = ground_at(ox, oz)
    P.fill(box(M, (ox - 2.4, yo + 0.1, oz - 0.5), (ox + 0.6, yo + 0.4, oz + 0.5)), HONEY, cell=(0.6, 9, 9))
    P.fill(ball(M, (ox + 1.4, yo + 0.3, oz + 0.9), 0.8, 0.5), ['#8D5D3B', '#7E5133'], cell=0.5)
    # the grove: a ring of old trees around a stump
    fx, fz = PLACES['grove']
    yf = ground_at(fx, fz)
    P.fill(column(M, fx, fz, 0.6, yf, yf + 0.5), ['#8D5D3B'], cell=0.5)
    for k in range(6):
        a = k * math.pi / 3
        tx, tz = fx + 2.0 * math.cos(a), fz + 2.0 * math.sin(a)
        ty = ground_at(tx, tz)
        P.fill(column(M, tx, tz, 0.3, ty, ty + 1.6), ['#6E4A2E'], cell=9)
        P.fill(ball(M, (tx, ty + 2.1, tz), 1.1, 1.0) & (M.m == 0), ['#5E9646', '#6FA552', '#4F8A3C'], cell=0.5)
    # ---- the trails: inlaid lines along the terrain, gold and glowing or faded to old ink
    S.polylines = {}
    lit = state == 'lit'
    for key, ctrl in TRAILS.items():
        poly = catmull(ctrl, 160)
        d, t = dist2d(X2, Z2, poly)
        core2 = (d < 0.5) & land2
        halo2 = (d < 0.85) & land2
        for name, m2, gl in (('halo', halo2 & ~core2, 1.0), ('core', core2, 2.4)):
            m = m2[:, None, :] & (M.Y >= ground_top - 0.5) & (M.Y < ground_top + 0.35)
            m &= ~water2[:, None, :]
            if lit:
                P.fill(m, LUMEN if name == 'core' else ['#E8A93E', '#D99A33'], glow=gl if name == 'core' else 0.7, cell=9)
            else:
                P.fill(m, INK_OLD if name == 'core' else ['#B59A76'], cell=9)
        # the trail over water: little stepping stones
        over = (d < 0.5) & water2
        P.fill(over[:, None, :] & (M.Y >= wy - 0.2) & (M.Y < wy + 0.35) & ((np.floor(t * 40) % 2 == 0)[:, None, :]), STONE_LT, cell=9)
        S.polylines[key] = [(float(p[0]), ground_at(p[0], p[1]) + 0.2, float(p[1])) for p in poly[::6]]
    if lit:
        for key, ctrl in TRAILS.items():
            poly = catmull(ctrl, 10)
            for p in poly[1:-1:2]:
                S.lights.append({'type': 'point', 'pos': (float(p[0]), ground_at(p[0], p[1]) + 1.0, float(p[1])),
                                 'power': 1.6, 'color': (1.0, 0.8, 0.4), 'radius': 1.2})
    # ---- the Hollow: violet crystals and vines creeping in from the sheet's edges, the land under them drained
    if state == 'hollow':
        # the creep comes in from the far side and the right, in tongues, and leaves the village's corner alone
        far = np.clip((MAP_Z1 - Z2) / (MAP_Z1 - MAP_Z0), 0, 1)                      # 1 at the top edge
        right = np.clip((X2 - 8.0) / 20.0, 0, 1)
        field = 0.55 * far ** 1.6 + 0.35 * right ** 1.5 + 0.55 * noise2(X2, Z2, 71, 5.5, 3) - 0.08
        field -= 0.45 * np.clip(1 - np.hypot(X2 - PLACES['village'][0], Z2 - PLACES['village'][1]) / 16.0, 0, 1)
        creep2 = (field > 0.62) & land2
        deep2 = (field > 0.80) & land2
        drained = creep2[:, None, :] & (M.m > 0) & (M.Y >= 0.0) & (M.Y < ground_top + 6.0)
        ids_grass = [M.mid(c) for c in GRASS_MAP + MOSS_MAP + ['#9CC76E', '#A6CF7A']]
        ids_leaf = [M.mid(c) for c in LEAF + AUTUMN + ['#86C56A', '#E5BE68', '#5E9646', '#6FA552', '#4F8A3C']]
        P.fill(drained & np.isin(M.m, ids_grass), ['#5C5078', '#54486E', '#665A84'], cell=0.75)
        P.fill(drained & np.isin(M.m, ids_leaf), HOLLOW_DK, cell=0.5)
        P.fill(drained & np.isin(M.m, ids_leaf) & (noise2(X2, Z2, 77, 1.5, 2)[:, None, :] > 0.6), HOLLOW_VINE, cell=0.5)
        pts = np.argwhere(deep2 & (dtrail > 1.0))
        rng2 = np.random.default_rng(5)
        pick = pts[rng2.choice(len(pts), size=min(110, len(pts)), replace=False)] if len(pts) else []
        for (ix, iz) in pick:
            x, z = X2[ix, iz], Z2[ix, iz]
            y = ground_at(x, z)
            h = rng2.uniform(0.9, 2.4) * (1.0 + 0.5 * (field[ix, iz] > 0.95))
            tilt = rng2.uniform(-0.3, 0.3, 2)
            crystal(M, P, (x, y - 0.2, z), (x + tilt[0] * h, y + h, z + tilt[1] * h), rng2.uniform(0.28, 0.5), HOLLOW_V, HOLLOW_HI, glow=1.1)
            if rng2.random() < 0.5:
                crystal(M, P, (x + 0.5, y - 0.2, z - 0.3), (x + 0.8, y + h * 0.5, z - 0.6), 0.22, HOLLOW_V, HOLLOW_HI, glow=0.9)
        # vines: dark tendrils along the ground, reaching inward from the creep
        edge_pts = np.argwhere(creep2 & ~deep2)
        for _ in range(70):
            ix, iz = edge_pts[rng2.integers(len(edge_pts))]
            x, z = X2[ix, iz], Z2[ix, iz]
            toward = np.array([PLACES['village'][0] - x, PLACES['village'][1] - z])
            toward /= np.linalg.norm(toward) + 1e-6
            pth = [(x, z)]
            for k in range(5):
                a = rng2.uniform(-0.8, 0.8)
                ca, sa = math.cos(a), math.sin(a)
                dd = np.array([toward[0] * ca - toward[1] * sa, toward[0] * sa + toward[1] * ca]) * rng2.uniform(1.2, 2.4)
                pth.append((pth[-1][0] + dd[0], pth[-1][1] + dd[1]))
            vp = catmull(pth, 40)
            dv, tv = dist2d(X2, Z2, vp)
            vm = (dv < 0.3 * (1 - 0.6 * tv)) & land2
            vm3 = vm[:, None, :] & (M.Y >= ground_top - 0.3) & (M.Y < ground_top + 0.35)
            P.fill(vm3, HOLLOW_VINE, cell=9)
            P.fill(vm3 & ((np.floor(tv * 12) % 3 == 0)[:, None, :]), HOLLOW_V, glow=0.6, cell=9)
        for (ix, iz) in pick[::6]:
            x, z = X2[ix, iz], Z2[ix, iz]
            S.lights.append({'type': 'point', 'pos': (float(x), ground_at(x, z) + 2.0, float(z)), 'power': 1.0,
                             'color': (0.6, 0.35, 1.0), 'radius': 1.5})
        S.world = ((0.1, 0.09, 0.2), 0.3)
        S.grade = dict(GRADES['map'], split={'highlights': '#E8C8FF', 'shadows': '#3A2E6E', 'amount': 0.16}, warm=-0.02,
                       saturation=1.0, mist={'start': 5.0, 'end': 10.0, 'amount': 0.3, 'color': '#2A2140', 'power': 1.2})
    # ---- on the desk: Alder's lantern (the key light), a brass compass, an inkpot and quill, map pins, his hand
    lantern(S, P, M, (30.0, 2.6, -19.0), s=1.7, lit=True, power=720.0 * (0.55 if state == 'hollow' else 1.0), kelvin=2400)
    P.fill(column(M, 30.0, -19.0, 2.4, 0.0, 0.6), IRON, cell=9)
    S.lights.append({'type': 'point', 'pos': (24.0, 9.0, -12.0), 'power': 140.0, 'color': 2400, 'radius': 3.0})
    # compass: a brass case with a glass face and a red needle
    P.fill(column(M, -33.0, -20.0, 2.4, 0.0, 1.2), BRASS, cell=9)
    P.fill(column(M, -33.0, -20.0, 2.0, 1.2, 1.5), CLEAR_GLASS, cell=50)
    P.fill(column(M, -33.0, -20.0, 1.8, 0.9, 1.2), PARCH, cell=9)
    P.fill(box(M, (-33.2, 1.0, -21.6), (-32.8, 1.3, -20.0)), ['#C0392B'], cell=9)
    P.fill(box(M, (-33.2, 1.0, -20.0), (-32.8, 1.3, -18.4)), ['#3B2923'], cell=9)
    # inkpot and quill
    P.fill(column(M, 36.0, 24.0, 1.6, 0.0, 2.4), ['#2E3A4E', '#263142'], cell=9)
    P.fill(column(M, 36.0, 24.0, 1.1, 2.4, 2.9), BRASS, cell=9)
    quill = np.stack([M.X - 36.0, M.Y - 2.9, M.Z - 24.0], -1)
    qd = np.array([0.35, 0.72, -0.6])
    qd /= np.linalg.norm(qd)
    qt = quill @ qd
    qperp = np.linalg.norm(quill - qt[..., None] * qd, axis=-1)
    P.fill((qt > 0) & (qt < 9.0) & (qperp < 0.22), ['#F3E5C9'], cell=9)
    P.fill((qt > 3.0) & (qt < 9.0) & (qperp < 0.9 * np.clip((qt - 3.0) / 4.0, 0, 1) * np.clip((9.0 - qt) / 2.0, 0, 1) + 0.2) &
           (np.abs(quill[..., 1] - qt * qd[1]) < 0.35), ['#F3E5C9', '#EADBB8'], cell=0.5)
    # map pins at the far places (brass pin, a red head)
    for key in ('ruins', 'gate', 'cliffs', 'cove'):
        px, pz = PLACES[key]
        py = ground_at(px, pz)
        P.fill(column(M, px + 1.2, pz + 1.0, 0.1, py, py + 1.6), BRASS, cell=9)
        P.fill(ball(M, (px + 1.2, py + 1.8, pz + 1.0), 0.4), ['#D85F51'], cell=9)
    # Alder's hand resting on the near left corner of the map: pale green, a linen cuff, three thick fingers
    hx, hz = -21.5, 13.5
    SKIN = ['#C3D1A0', '#B9C797']
    palm = ball(M, (hx, 1.2, hz), 3.2, 0.55)
    P.fill(palm & (M.Y >= 0.3), SKIN, cell=0.5)
    for k, (fx_, fz_, ln) in enumerate(((-2.2, -2.6, 4.2), (0.2, -3.0, 4.8), (2.4, -2.4, 4.0))):
        a = np.array([hx + fx_ * 0.5, 1.3, hz + fz_ * 0.3])
        b = np.array([hx + fx_, 0.9, hz + fz_ - ln])
        d = b - a
        L = np.linalg.norm(d)
        d /= L
        Pv = np.stack([M.X - a[0], M.Y - a[1], M.Z - a[2]], -1)
        t = Pv @ d
        rr = np.linalg.norm(Pv - t[..., None] * d, axis=-1)
        P.fill((t > -0.5) & (t < L) & (rr < 1.05) & (M.Y >= 0.3), SKIN, cell=0.5)
        P.fill(ball(M, tuple(b), 1.05) & (M.Y >= 0.3), SKIN, cell=0.5)
        P.fill(ball(M, tuple(b + d * 0.6), 0.5) & (M.Y >= 0.3), ['#5E6B48'], cell=9)
    P.fill(box(M, (hx - 3.6, 0.3, hz + 2.2), (hx + 3.6, 3.4, hz + 6.0)) & ((M.X - hx) ** 2 / 3.6 ** 2 + (M.Y - 1.8) ** 2 / 1.7 ** 2 < 1.0), ['#EFE6D0', '#E6DCC4'], cell=(0.5, 0.5, 9))
    P.fill(box(M, (hx - 3.6, 0.3, hz + 3.4), (hx + 3.6, 3.4, hz + 3.8)) & ((M.X - hx) ** 2 / 3.6 ** 2 + (M.Y - 1.8) ** 2 / 1.7 ** 2 < 1.0), ['#7F9871'], cell=9)
    S.models.append((M, CLEAR_GLASS, {'water': tuple(WATER_MAP)}))
    S.anchors = {k: (x, ground_at(x, z) + 0.5, z) for k, (x, z) in PLACES.items()}
    S.anchors['lantern'] = (30.0, 2.6, -19.0)
    S.anchors['hand'] = (hx, 1.5, hz)
    return S



# ------------------------------------------------------------------------------------ Sunlit Village ----
DUSK = dict(sun=dict(dir=(-0.72, -0.26, -0.52), power=0.9, color=2400, angle=3.0),
            sky=('#2E3A7A', '#F0A878'), ground='#1E1C36', strength=0.32)
NIGHT = dict(sun=dict(dir=(-0.5, -0.6, -0.4), power=0.35, color=9000, angle=3.0),
             sky=('#1E2650', '#5B4C86'), ground='#171527', strength=0.45)


def glasshouse_model(S, P, M, x0, x1, z0, z1, h_wall=8.0, h_ridge=14.0, lit=True, power=60.0, fine=False):
    """Mira's Glasshouse from outside: a low stone base, sage-framed glass walls, a gabled glass roof with a
    ridge along x, a door on the +x end under a lantern, pots and flowers along the front. Warm light inside."""
    zc, half = (z0 + z1) / 2, (z1 - z0) / 2 + 0.6
    P.fill(box(M, (x0, 0, z0), (x1, 1.8, z1)), STONE_LT, cell=(1.5, 0.75, 1.5))
    pane = GLASS_WARM if lit else CLEAR_GLASS
    walls = box(M, (x0, 1.8, z0), (x1, h_wall, z1)) & ~box(M, (x0 + 0.6, 1.8, z0 + 0.6), (x1 - 0.6, h_wall, z1 - 0.6))
    P.fill(walls, pane, cell=50)
    mull = ((((M.X - x0) % 3.25) < 0.45) & ((M.Z >= z1 - 0.6) | (M.Z < z0 + 0.6))) | \
           ((((M.Z - z0) % 3.0) < 0.45) & ((M.X >= x1 - 0.6) | (M.X < x0 + 0.6))) | (np.abs(M.Y - 5.0) < 0.3) | (M.Y < 2.3) | (M.Y >= h_wall - 0.5)
    P.fill(walls & mull, SAGE, cell=9)
    topy = h_wall + (h_ridge - h_wall) * (1 - np.abs(M.Z - zc) / half)
    roof = (M.X >= x0 - 0.7) & (M.X < x1 + 0.7) & (np.abs(M.Z - zc) <= half) & (M.Y >= topy - 0.7) & (M.Y < topy) & (M.Y >= h_wall - 0.2)
    P.fill(roof, pane, cell=50)
    P.fill(roof & ((((M.X - x0) % 3.25) < 0.5) | (np.abs(M.Z - zc) < 0.5) | (np.abs(np.abs(M.Z - zc) - half) < 0.6) | (M.Y < h_wall + 0.5)), ['#8FA883', '#86A07A'], cell=9)
    P.fill(box(M, (x0 - 0.8, h_wall - 0.6, z0 - 0.8), (x1 + 0.8, h_wall + 0.1, z1 + 0.8)) & ~box(M, (x0 + 0.6, 0, z0 + 0.6), (x1 - 0.6, 20, z1 - 0.6)), ['#43523D'], cell=9)
    # gable ends: glass in a fan of sage ribs
    for gz in (z0 - 0.2, z1 - 0.5):
        gab = (M.Z >= gz) & (M.Z < gz + 0.7) & (M.X >= x0) & (M.X < x1) & (M.Y >= h_wall) & (M.Y < topy)
        P.fill(gab, pane, cell=50)
        P.fill(gab & ((((M.X - x0) % 2.6) < 0.5) | (np.abs(M.Y - h_wall - 2.8) < 0.3)), SAGE, cell=9)
    # ridge finial
    P.fill(box(M, (x1 - 0.3, h_ridge, zc - 0.3), (x1 + 0.3, h_ridge + 2.2, zc + 0.3)), IRON, cell=9)
    P.fill(ball(M, (x1, h_ridge + 2.5, zc), 0.6), ['#E8B956'])
    # inside: tiers of pots and tall plants seen through the glass, a warm lantern hanging from the ridge
    rng = np.random.default_rng(abs(int(x0 * 3 + z0)))
    for px in np.arange(x0 + 1.8, x1 - 1.2, 2.2):
        for pz in (z0 + 1.8, z1 - 2.0):
            P.fill(cyl_y(M, (px, pz), 0.7, 1.8, 3.0), TERRACOTTA, cell=9)
            P.fill(ball(M, (px, 4.2, pz), 1.3, 0.9) & (M.m == 0), LEAF, cell=0.5)
            P.fill(ball(M, (px + 0.4, 5.2, pz + 0.3), 0.45), [FLOWERS[int(abs(px * 3)) % 5]])
    for k in range(4):
        tx = x0 + 2.5 + k * (x1 - x0 - 5) / 3
        P.fill(cyl_y(M, (tx, zc), 0.25, 1.8, 7.5 + k % 2), ['#5EA046'], cell=9)
        P.fill(ball(M, (tx, 8.0 + k % 2, zc), 1.4, 0.7) & (M.m == 0), ['#86C56A', '#6FB24E'], cell=0.5)
    if lit:
        for lx in (x0 + (x1 - x0) * 0.3, x0 + (x1 - x0) * 0.7):
            lantern(S, P, M, (lx, h_ridge - 3.0, zc), s=0.9, lit=True, power=power, kelvin=2400, hang_to=h_ridge - 0.5)
        P.fill(box(M, (x0 + 0.8, 0.2, z0 + 0.8), (x1 - 0.8, 1.8, z1 - 0.8)), ['#FFD46A', '#FFC24E'], glow=0.9, cell=9)
        # the far wall glows warm inside, so the plants stand dark against gold (the storyboard's window)
        P.fill(box(M, (x0 + 0.7, 1.8, z0 + 0.6), (x1 - 0.7, h_wall - 0.4, z0 + 0.95)), ['#FFE2A0', '#FFD98A', '#FFE9B4'], glow=0.75, cell=(1.5, 1.5, 9))
        S.lights.append({'type': 'point', 'pos': ((x0 + x1) / 2, h_wall * 0.6, z0 + 2.0), 'power': power * 2.6, 'color': 2700, 'radius': 2.5})
        S.lights.append({'type': 'point', 'pos': (x0 + (x1 - x0) * 0.25, h_wall * 0.5, z0 + 2.4), 'power': power * 1.2, 'color': 2400, 'radius': 2.0})
    # the door on the +x end, a lantern post by it, flowers and pots along the front
    door = box(M, (x1 - 0.4, 0, zc - 1.6), (x1 + 0.5, 5.0, zc + 1.6))
    if fine:
        # the door stands open (swung out along +z), the doorway a warm slot of light
        M.m[door & (M.m > 0) & (M.X >= x1 - 0.6)] = 0
        door = box(M, (x1 + 0.4, 0, zc + 1.6), (x1 + 1.0, 5.0, zc + 4.6))
        P.fill(door, ['#7F9871', '#6E8762'], cell=9)
        S.lights.append({'type': 'point', 'pos': (x1 + 1.5, 2.6, zc), 'power': power * 0.5, 'color': 2400, 'radius': 1.0})
    else:
        P.fill(door, ['#7F9871', '#6E8762'], cell=9)
    P.fill(door & (np.abs(M.Z - zc) < 0.25) & (M.Y > 1.0) & (M.Y < 4.6) & (M.X >= x1), ['#43523D'], cell=9)
    P.fill(box(M, (x1 + 0.3, 2.6, zc + 0.8), (x1 + 0.7, 2.9, zc + 1.1)), BRASS, cell=9)
    for (px, pz) in ((x1 + 1.8, zc + 2.8), (x1 + 1.8, zc - 3.0), (x0 + 2.0, z1 + 1.6), (x0 + 6.0, z1 + 1.6), (x0 + 10.0, z1 + 1.6)):
        P.fill(cyl_y(M, (px, pz), 0.85, 0, 1.3), TERRACOTTA, cell=9)
        P.fill(ball(M, (px, 2.1, pz), 1.25, 0.85) & (M.m == 0), LEAF, cell=0.5)
        P.fill(ball(M, (px + 0.4, 2.9, pz + 0.4), 0.45), [FLOWERS[int(abs(px * pz)) % 5]])
    V.flower_patch(P, M, (x0 + x1) / 2, z1 + 4.2, (x1 - x0) / 2 - 1, 1.6, rng, n=22)
    V.outdoor_lantern(S, P, M, x1 + 2.4, zc + 0.2, 5.4, lit=lit, power=power * 0.45, s=0.75, kelvin=2400)
    # vines climbing the near corner and the ridge end
    for (vx, vz) in ((x0 + 0.3, z1 - 0.2), (x1 - 0.3, z1 - 0.2)):
        vine = (np.abs(M.X - vx - 0.6 * np.sin(M.Y * 0.9)) < 0.35) & (np.abs(M.Z - vz) < 0.5) & (M.Y > 1.5) & (M.Y < h_wall + 1.5)
        P.fill(vine, ['#5EA046', '#4F9C3E'], cell=0.5)
        for ly in np.arange(2.5, h_wall + 1.0, 1.3):
            P.fill(ball(M, (vx + 0.6 * math.sin(ly * 0.9) + 0.5, ly, vz + 0.4), 0.5, 0.6) & (M.m == 0), ['#86C56A', '#6FB24E'], cell=0.5)
    return {'window': ((x0 + x1) / 2, h_wall - 2.0, z1), 'door': (x1 + 0.4, 2.5, zc), 'ridge': ((x0 + x1) / 2, h_ridge, zc)}


def village_set(S, P, M, rng, lit=True, night=True, fine=False):
    """Sunlit Village as the Square shows it (village_scenes.scene_square), at dusk: every window lit, the lamps
    on, the Glasshouse glowing. Returns the anchors."""
    from village_scenes import (gable, win_front, outdoor_lantern, tree2, fence_line, flower_patch, bunting, crate, barrel,
                                waystone_model, lantern as lant, PATHC, COBBLE, SLATE, MOSSROOF, BRICK, NAVY, CREAM, TREE_LEAVES)
    X2, Z2 = M.X[:, 0, :], M.Z[:, 0, :]
    R = np.sqrt(M.X ** 2 + M.Z ** 2)
    ground = (M.Y >= -1) & (M.Y < 0)
    P.fill((M.Y >= -4) & (M.Y < -1), ['#B98955', '#A97C4B'], cell=1)
    P.fill(ground, GRASS, cell=1.0)
    P.fill(ground & (np.sin(M.X * 0.37) * np.cos(M.Z * 0.29) > 0.55), ['#79A85A', '#73A255'], cell=1.0)
    # stream across the top with a bridge on the Lodge path
    sz = -15.0 + 1.6 * np.sin(M.X * 0.18)
    water = (np.abs(M.Z - sz) < 2.0) & (M.Y >= -1.4) & (M.Y < -0.4)
    bank = (np.abs(M.Z - sz) >= 2.0) & (np.abs(M.Z - sz) < 2.8) & (M.Y >= -1.0) & (M.Y < 0)
    M.m[(np.abs(M.Z - sz) < 2.0) & (M.Y >= -1.0) & (M.Y < 0)] = 0
    P.fill(bank, ['#C9C2AE', '#BDB5A0', '#B0A993'], cell=1.0)
    P.fill(water, WATERC, cell=1.0)
    bridge = (np.abs(M.X) < 3.0) & (np.abs(M.Z - (-15.0)) < 3.6) & (M.Y >= 0) & (M.Y < 0.6 + 0.6 * np.cos((M.Z + 15.0) / 3.6 * 1.4))
    P.fill(bridge & (M.Y >= 0.2 * np.cos((M.Z + 15.0) / 3.6 * 1.4)), HONEY, cell=(9, 1, 1.0))
    for bx in (-3.0, 2.6):
        P.fill((np.abs(M.X - bx - 0.2) < 0.3) & (np.abs(M.Z + 15.0) < 3.6) & (np.abs(M.Y - 1.8 - 0.6 * np.cos((M.Z + 15.0) / 3.6 * 1.4)) < 0.3), WALNUT, cell=9)
        for pz in (-18.2, -15.0, -11.8):
            P.fill(box(M, (bx, 0, pz - 0.3), (bx + 0.6, 2.4, pz + 0.3)), WALNUT, cell=9)
    pathm = ground & (((np.abs(M.X - 0.15 * M.Z) < 2.4) & (M.Z > 8)) | ((np.abs(M.X) < 2.4) & (M.Z < -8) & (M.Z > -24)) |
                      ((np.abs(M.Z + 1.0) < 2.2) & (np.abs(M.X) > 9) & (np.abs(M.X) < 13.5)))
    P.fill(pathm, PATHC, cell=(1.0, 1, 1.0))
    plaza = ground & (R < 10.0)
    P.fill(plaza, COBBLE, cell=(1.5, 1, 1.0))
    P.fill(plaza & ((np.abs((R % 2.5) - 1.25) > 1.0)), ['#B1A893'], cell=9)
    P.fill(ground & (R >= 9.4) & (R < 10.4), ['#A89F8C', '#B4AB97'], cell=9)
    for k, a in enumerate((0.785, 2.356, 3.927, 5.498)):
        bx_, bz_ = 12.0 * math.cos(a), 12.0 * math.sin(a)
        if bz_ < -6:
            continue
        bed = ((M.X - bx_) ** 2 + (M.Z - bz_) ** 2 <= 4.0) & (M.Y >= 0) & (M.Y < 0.7)
        P.fill(bed, STONE_LT, cell=9)
        P.fill(bed & (((M.X - bx_) ** 2 + (M.Z - bz_) ** 2) < 2.6) & (M.Y >= 0.4), ['#5B4334'], cell=0.5)
        flower_patch(P, M, bx_, bz_, 1.2, 1.2, rng, n=6)
    for (lx, lz) in [(9.5, 7.0), (-9.5, 7.0), (-9.5, -7.5), (9.5, -7.5)]:
        outdoor_lantern(S, P, M, lx, lz, 6.0, lit=lit, power=22.0, s=0.75, kelvin=2400)
    S.models.append((waystone_model(S, False, glimmer=True, power=10.0), ()))
    # ---- Mira's Glasshouse (left)
    gh = glasshouse_model(S, P, M, -24.0, -11.0, -10.0, 2.0, h_wall=8.0, h_ridge=13.5, lit=lit, power=55.0, fine=fine)
    fence_line(P, M, (-25.0, 9.4), (-10.5, 9.4))
    # ---- Bram's Workshop (right)
    wx0, wx1, wz0, wz1 = 11.0, 24.0, -11.0, 1.0
    body = gable(P, M, wx0, wx1, wz0, wz1, 7.0, 5.0, BRICK, ROOF, oh=1.0, ridge='z', wall_cell=(2.0, 1.0, 2.0))
    for (px, pz) in ((wx0, wz0), (wx0, wz1 - 0.6), (wx1 - 0.6, wz1 - 0.6)):
        P.fill(box(M, (px, 0, pz), (px + 0.6, 7.0, pz + 0.6)), WALNUT, cell=9)
    win_front(P, M, wx0, 3.6, -7.6, 2.4, 2.2, lit=True, face='-x', glow=0.8)
    win_front(P, M, 19.6, 3.8, wz1, 2.4, 2.2, lit=True, glow=0.8)
    S.lights.append({'type': 'point', 'pos': (wx0 - 1.2, 3.6, -7.6), 'power': 18.0, 'color': 1900, 'radius': 1.0})
    S.lights.append({'type': 'point', 'pos': (19.6, 3.8, wz1 + 1.2), 'power': 14.0, 'color': 1900, 'radius': 1.0})
    P.fill(box(M, (wx0 - 0.5, 0, -3.8), (wx0 + 0.2, 5.0, -1.0)), WALNUT, cell=9)
    chim = box(M, (19.0, 7.0, -8.6), (21.4, 15.6, -6.2))
    P.fill(chim, STONE, cell=(1.0, 1.0, 1.0))
    P.fill(box(M, (19.4, 15.4, -8.2), (21.0, 15.8, -6.6)), ['#FF9A4A', '#FFB65C'], glow=1.0, cell=9)
    for k in range(4):
        P.fill(ball(M, (20.2 + k * 0.6, 17.2 + k * 1.6, -7.4 - k * 0.3), 0.8 + 0.25 * k) & (M.m == 0), ['#8E8A94', '#7E7A86'], cell=0.5)
    awn = (M.X >= wx0 - 3.0) & (M.X < wx0) & (M.Z >= -10.0) & (M.Z < -5.0) & (np.abs(M.Y - (5.6 + (M.X - wx0) * 0.35)) < 0.3)
    P.fill(awn, ['#B76B4D'], cell=9)
    P.fill(awn & (((M.Z + 10.0) % 2.0) < 1.0), ['#F3E5C9'], cell=9)
    for (cx_, cz_, s_) in ((wx0 - 1.8, 3.4, 0.9), (wx0 - 1.6, 5.2, 0.7), (wx1 + 1.6, -2.0, 1.0)):
        crate(P, M, cx_, cz_, s_)
    barrel(P, M, wx1 + 1.8, 1.6, 1.1, 2.4)
    outdoor_lantern(S, P, M, wx0 - 1.4, -1.0, 4.4, lit=lit, power=12.0, s=0.6, kelvin=2400)
    # ---- the Trail Guild Lodge (top)
    lx0, lx1, lz0, lz1 = -10.0, 10.0, -34.0, -24.0
    body = gable(P, M, lx0, lx1, lz0, lz1, 10.0, 6.0, PLASTER, ROOF, oh=1.2, ridge='x', wall_cell=(3, 3, 3))
    fr = body & (M.Z >= lz1 - 0.5) & ((((M.X - lx0) % 5.0) < 0.6) | (np.abs(M.Y - 5.0) < 0.35) | (M.Y < 0.6) | (M.Y >= 9.4))
    P.fill(fr, WALNUT, cell=9)
    P.fill(box(M, (-1.8, 0, lz1 - 0.4), (1.8, 4.4, lz1 + 0.3)), ['#5E3A24', '#6E4529'], cell=9)
    for wx in (-6.5, 6.5):
        win_front(P, M, wx, 2.6, lz1, 2.4, 2.0, lit=lit)
        win_front(P, M, wx, 7.4, lz1, 2.4, 2.0, lit=lit)
        S.lights.append({'type': 'point', 'pos': (wx, 2.6, lz1 + 1.5), 'power': 10.0, 'color': 2400, 'radius': 1.0})
    win_front(P, M, 0.0, 7.4, lz1, 2.0, 2.0, lit=lit)
    P.fill(box(M, (-3.6, 4.6, lz1), (3.6, 5.0, lz1 + 2.6)), WALNUT, cell=9)
    for px in (-3.2, 3.0):
        P.fill(box(M, (px, 0, lz1 + 2.0), (px + 0.5, 4.6, lz1 + 2.5)), WALNUT, cell=9)
    for wx in (-2.6, 2.6):
        lant(S, P, M, (wx, 3.6, lz1 + 2.3), s=0.55, lit=lit, power=8.0)
    for bx in (-9.2, 9.2):
        ban = (np.abs(M.X - bx) <= 1.1) & (M.Y >= 3.4) & (M.Y < 9.0) & (M.Z >= lz1 + 0.1) & (M.Z < lz1 + 0.6)
        ban &= ~((M.Y < 4.4) & (np.abs(M.X - bx) < 0.5))
        P.fill(ban, NAVY, cell=9)
        P.fill(ban & (np.abs(M.Y - 7.0) < 0.5) & (np.abs(M.X - bx) < 0.6), CREAM)
    pole = box(M, (8.6, 16.0, -29.2), (9.0, 21.0, -28.8))
    P.fill(pole, IRON, cell=9)
    P.fill(box(M, (9.0, 18.8, -29.0), (12.6, 20.8, -28.8)), NAVY, cell=9)
    # ---- cottages, every window lit
    cottages = [(-34.0, -26.0, -36.0, -26.0, SLATE, PLASTER), (22.0, 34.0, -38.0, -28.0, MOSSROOF, ['#E9D7B8', '#E2CEAC']),
                (26.0, 36.0, 10.0, 20.0, ROOF, PLASTER), (-38.0, -30.0, -8.0, 2.0, SLATE, ['#D9C8A8', '#E2D2B4'])]
    for (cx0, cx1, cz0, cz1, rf, wl) in cottages:
        gable(P, M, cx0, cx1, cz0, cz1, 6.0, 4.5, wl, rf, ridge='x', wall_cell=(3, 3, 3))
        mid = (cx0 + cx1) / 2
        P.fill(box(M, (mid - 1.0, 0, cz1 - 0.3), (mid + 1.0, 3.6, cz1 + 0.3)), ['#6E4529'], cell=9)
        win_front(P, M, mid - 3.0, 3.0, cz1, 1.6, 1.6, lit=lit)
        win_front(P, M, mid + 3.0, 3.0, cz1, 1.6, 1.6, lit=lit)
        S.lights.append({'type': 'point', 'pos': (mid, 3.0, cz1 + 1.4), 'power': 9.0, 'color': 2400, 'radius': 1.2})
        P.fill(box(M, (cx1 - 2.6, 6.0, cz0 + 2.0), (cx1 - 1.2, 11.0, cz0 + 3.4)), STONE, cell=9)
    # ---- the market corner (not in the close shot, where it would sit in front of the Glasshouse), the gate, benches, trees
    mx_, mz_ = -21.0, 12.0
    if not fine:
        P.fill(box(M, (mx_ - 3.6, 2.4, mz_ - 1.6), (mx_ + 3.6, 3.0, mz_ + 1.6)), HONEY, cell=(1.5, 1, 9))
        for (px, pz) in ((mx_ - 3.4, mz_ - 1.4), (mx_ + 3.0, mz_ - 1.4), (mx_ - 3.4, mz_ + 1.0), (mx_ + 3.0, mz_ + 1.0)):
            P.fill(box(M, (px, 0, pz), (px + 0.5, 6.4, pz + 0.5)), WALNUT, cell=9)
        canopy = (np.abs(M.X - mx_) <= 4.2) & (np.abs(M.Z - mz_) <= 2.6) & (np.abs(M.Y - (6.8 - (M.Z - mz_) * 0.35)) < 0.35)
        P.fill(canopy, ['#D85F51'], cell=9)
        P.fill(canopy & ((((M.X - mx_) % 2.0) + 2.0) % 2.0 < 1.0), CREAM, cell=9)
    for gx in (-3.6, 3.4):
        P.fill(box(M, (gx - 0.4 + 2.1, 0, 15.6), (gx + 0.4 + 2.1, 4.6, 16.4)), HONEY, cell=9)
    arch = (np.abs(M.Z - 16.0) <= 0.4) & (np.abs(M.Y - 4.4 - 0.6 * np.cos((M.X - 2.1) / 3.8 * 1.4)) <= 0.35) & (np.abs(M.X - 2.1) <= 4.2)
    P.fill(arch, HONEY, cell=9)
    fence_line(P, M, (-38.0, 17.0), (-2.4, 16.0))
    fence_line(P, M, (6.6, 16.0), (38.0, 17.0))
    outdoor_lantern(S, P, M, 8.0, 12.0, 6.0, lit=lit, power=28.0, s=0.95, kelvin=2400)
    for (bx_, bz_) in ((-6.0, 7.6), (6.2, -7.8)):
        P.fill(box(M, (bx_ - 1.8, 1.0, bz_ - 0.6), (bx_ + 1.8, 1.5, bz_ + 0.6)), HONEY, cell=(1.5, 1, 9))
    trees = [(-30.0, -16.0, 7, 4.8), (-28.0, 8.0, 5, 3.8), (30.0, -18.0, 8, 5.0), (33.0, -4.0, 6, 4.0),
             (-16.0, -26.0, 6, 4.2), (16.0, -24.0, 7, 4.2), (-36.0, 22.0, 6, 4.5), (35.0, 26.0, 6, 4.5),
             (-14.0, 24.0, 5, 3.6), (18.0, 24.0, 5, 3.4), (-34.0, -40.0, 8, 5), (36.0, -42.0, 8, 5),
             (-40.0, 10.0, 7, 4.6), (40.0, 8.0, 7, 4.6), (-42.0, -30.0, 8, 5.2), (42.0, -28.0, 8, 5.2)]
    for (tx, tz, th_, tr) in trees:
        tree2(P, M, tx, tz, th_, tr)
    for _ in range(30):
        fx, fz = rng.uniform(-36, 36), rng.uniform(-40, 30)
        rr = math.hypot(fx, fz)
        if rr < 12 or (abs(fx) > 9 and abs(fx) < 26 and -12 < fz < 4) or (abs(fx) < 12 and -36 < fz < -22) or abs(fx - 0.15 * fz) < 3.4 and fz > 6 \
                or abs(fz - (-15.0)) < 4.0:
            continue
        flower_patch(P, M, fx, fz, 1.4, 1.0, rng, n=4)
    for (a, b) in (((-9.5, 7.6, 7.0), (9.5, 7.6, 7.0)), ((-9.5, 7.6, -7.5), (-3.2, 4.6, lz1 + 2.2)), ((9.5, 7.6, -7.5), (3.5, 4.6, lz1 + 2.2))):
        bunting(P, M, a, b, sag=1.4)
    if night:
        V.fireflies2(S, P, M, np.random.default_rng(9), 50, (-30, 30), (2.0, 10.0), (-30, 24), light_every=10, power=0.5)
    return {'glasshouse_window': gh['window'], 'glasshouse_door': gh['door'], 'glasshouse_ridge': gh['ridge'],
            'waystone': (0.0, 6.0, 0.0), 'lodge': (0.0, 12.0, -24.0), 'workshop': (17.5, 10.0, -2.0)}


def scene_village_dusk():
    """The cold open's last shot, where the push-in starts: Sunlit Village from above at dusk, every window lit,
    the Glasshouse glowing on the left, the terraces and the waterfall behind. Portrait, so the phone can
    push in on the Glasshouse."""
    st = DUSK
    cam = {'pos': (4.0, 56.0, 104.0), 'target': (-5.0, 3.0, -22.0), 'fov': 44.0, 'focus': (-17.0, 6.0, -4.0), 'fstop': 5.6}
    S = VScene('village_dusk', 1400, 2100, cam, world=((0.3, 0.3, 0.5), 0.5), samples=192, transparent=True, sky=st['sky'])
    S.sky_world = {'sky': st['sky'], 'ground': st['ground'], 'strength': st['strength']}
    S.lights.append({'type': 'sun', **st['sun']})
    S.zmax = 40.0
    rng = np.random.default_rng(41)
    M = Model((-52, -4, -48), (52, 30, 72), [], res=2)
    P = CPainter(M, 41)
    anchors = village_set(S, P, M, rng, lit=True, night=True)
    # the meadow in front of the gate, down to the camera: grass, a few trees and flowers
    for (tx, tz, th_, tr) in ((-30.0, 40.0, 7, 4.8), (28.0, 44.0, 8, 5.2), (-44.0, 56.0, 9, 6.0), (46.0, 58.0, 9, 6.0), (8.0, 62.0, 6, 4.2)):
        V.tree2(P, M, tx, tz, th_, tr)
    for _ in range(24):
        fx, fz = rng.uniform(-48, 48), rng.uniform(20, 68)
        if abs(fx - 0.15 * fz) < 4.0:
            continue
        V.flower_patch(P, M, fx, fz, 1.6, 1.2, rng, n=5)
    pathm = (M.Y >= -1) & (M.Y < 0) & (np.abs(M.X - 0.15 * M.Z - 0.3 * np.sin(M.Z * 0.1)) < 2.6) & (M.Z > 16)
    P.fill(pathm, V.PATHC, cell=(1.0, 1, 1.0))
    S.models.append((M, CLEAR_GLASS + GLASS_WARM, {'water': WATERC}))
    S.models.append((V.far_terrain(seed=41), (), {'water': WATERC}))
    S.anchors = anchors
    S.grade = {'bloom': 0.55, 'bloom_threshold': 160.0, 'bloom_wide': 0.3, 'glow': 0.14, 'saturation': 1.05,
               'split': {'highlights': '#FFD2A0', 'shadows': '#3E4090', 'amount': 0.14}, 'vignette': 0.3, 'grain': 0.01,
               'lift': (0.0, 0.0, 0.03), 'gain': (1.0, 0.98, 1.02),
               'mist': {'start': 9.0, 'end': 26.0, 'amount': 0.62, 'color': '#6A64A8', 'power': 1.2}, 'sky_mix': 0.42}
    return S


def scene_glasshouse_night():
    """Where the push-in lands: Mira's Glasshouse from the square at dusk, close, its windows glowing warm, the
    door under its lantern. Portrait. The camera matches the dusk aerial's direction, so the push-in reads as
    one move."""
    st = DUSK
    cam = {'pos': (-1.0, 14.0, 36.0), 'target': (-13.5, 6.5, -3.0), 'fov': 42.0, 'focus': (-11.0, 4.0, -2.0), 'fstop': 2.6}
    S = VScene('glasshouse_night', 1400, 2100, cam, world=((0.3, 0.3, 0.5), 0.5), samples=192, transparent=True, sky=st['sky'])
    S.sky_world = {'sky': st['sky'], 'ground': st['ground'], 'strength': st['strength']}
    S.lights.append({'type': 'sun', **st['sun']})
    S.zmax = 30.0
    rng = np.random.default_rng(43)
    M = Model((-46, -4, -48), (46, 30, 44), [], res=3)
    P = CPainter(M, 43)
    anchors = village_set(S, P, M, rng, lit=True, night=True, fine=True)
    S.models.append((M, CLEAR_GLASS + GLASS_WARM, {'water': WATERC}))
    S.models.append((V.far_terrain(seed=41), (), {'water': WATERC}))
    # Mira in the open doorway with her pot, looking up the path toward us
    from cine_blender import Actor
    from village_npcs import build_mira, INK
    from village_npc_render import npc_palette
    chm = build_mira(res=CAST_RES)
    S.actors = [Actor('mira', chm, npc_palette(chm, INK), 'mira', expr='happy', pos=(-8.2, 0.0, -0.9), yaw=math.radians(18), scale=0.17)]
    anchors['mira'] = (-8.2, 0.17 * 19.6, -0.9)
    S.anchors = anchors
    S.grade = {'bloom': 0.55, 'bloom_threshold': 160.0, 'bloom_wide': 0.3, 'glow': 0.16, 'saturation': 1.05,
               'split': {'highlights': '#FFD2A0', 'shadows': '#4A4C9A', 'amount': 0.12}, 'vignette': 0.3, 'grain': 0.01,
               'mist': {'start': 8.0, 'end': 28.0, 'amount': 0.35, 'color': '#6E6AA8', 'power': 1.3}, 'sky_mix': 0.5}
    return S



# ------------------------------------------------------------------------------------------ the eggs ----
EGG_MATS = ('feet', 'feet_shade', 'claw')


def egg_character(crack=0.0, seed=0, res=CAST_RES):
    """An unhatched Evochi egg: the Eggling's own body (characters.build_eggling) without its feet, claws and face,
    so the crest, ear plates, scale squares and the diamond markings are exactly the game's. `crack` 0..1 carves
    glowing cracks into the shell: fine lines from the crown at 0.3, spreading over the egg at 0.7, and at 1.0 a
    shell about to burst (light through every seam)."""
    import dataclasses
    from characters import build_eggling, egg_mask
    ch = build_eggling(res=res)
    M = ch.model.copy()
    for mat in EGG_MATS:
        if mat in M.ids:
            M.m[M.m == M.ids[mat]] = 0
    # the egg sits a little lower without its feet: drop it onto the ground
    idx = np.argwhere(M.m > 0)
    y0 = (idx[:, 1].min() + M.lo[1]) / M.res
    anchors = {k: (v[0], v[1] - y0, v[2]) for k, v in ch.anchors.items()}
    if crack > 0:
        # each crack is a line traced on the shell: a jagged path from the crown down (angle round the egg, height),
        # found on the egg's surface by a ray from its axis, then every outer shell voxel within a hair of the line
        # becomes crack (light through the shell); branches fork off the longer ones. Continuous at any voxel grain.
        from scipy.spatial import cKDTree
        rng = np.random.default_rng(31 + seed)
        shell = np.isin(M.m, [M.ids[k] for k in ('shell', 'belly', 'pattern') if k in M.ids]) & M.surface()
        filled = M.m > 0
        sidx = np.argwhere(shell)
        spts = (sidx + M.lo + 0.5) / M.res
        tree = cKDTree(spts)
        cy0, cy1 = 0.6, 24.0                                          # the shell's height range (the crown above)

        def on_shell(a, y):
            """the outermost filled point at angle a, height y (a ray out from the axis)"""
            d = np.array([math.sin(a), 0.0, math.cos(a)])
            last = None
            for rr in np.arange(4.0, 16.0, 0.5 / M.res):
                q = np.array([0.0, y, 0.0]) + d * rr
                ii = np.floor(q * M.res).astype(int) - M.lo
                if np.any(ii < 0) or np.any(ii >= np.array(M.m.shape)):
                    break
                if filled[tuple(ii)]:
                    last = q
            return last

        def trace(path, width):
            pts = []
            for (a0, y0), (a1, y1) in zip(path[:-1], path[1:]):
                for t in np.linspace(0, 1, 12, endpoint=False):
                    q = on_shell(a0 + (a1 - a0) * t, y0 + (y1 - y0) * t)
                    if q is not None:
                        pts.append(q)
            if not pts:
                return np.zeros(len(spts), bool)
            dd, _ = cKDTree(np.array(pts)).query(spts, distance_upper_bound=width + 0.01)
            return dd <= width

        hit = np.zeros(len(spts), bool)
        n_cracks = 3 + int(crack * 6)
        w = max(0.32, 0.9 / M.res)                                     # about a voxel and a bit wide
        # the first cracks fan across the side that faces the camera (angle 0 is the egg's front), so every crack
        # stage reads from the hero angle; only the extras of a shell about to burst run round the back
        n_front = min(n_cracks, 5)
        front = np.linspace(-1.15, 1.15, n_front) + rng.uniform(-0.12, 0.12, n_front)
        starts = list(rng.permutation(front)) + list(rng.uniform(1.6, 2 * math.pi - 1.6, n_cracks - n_front))
        for k in range(n_cracks):
            a0 = float(starts[k])
            ytop = cy1 - rng.uniform(0.5, 3.5)
            ybot = ytop - (cy1 - cy0) * crack * rng.uniform(0.45, 0.9)
            steps = 9
            path = [(a0 + rng.uniform(-0.28, 0.28) * (j > 0) + 0.12 * math.sin(j * 2.1 + k), ytop - (ytop - ybot) * j / steps) for j in range(steps + 1)]
            hit |= trace(path, w)
            if crack > 0.5:
                for j in rng.choice(np.arange(2, steps), 2, replace=False):
                    a, y = path[j]
                    sgn = 1 if (j + k) % 2 else -1
                    br = [(a + sgn * 0.42 * t, y - 3.2 * t) for t in np.linspace(0, 1, 5)]
                    hit |= trace(br, w * 0.8)
        cid = M.mid('crack')
        ii = sidx[hit]
        M.m[ii[:, 0], ii[:, 1], ii[:, 2]] = cid
        M.glow[ii[:, 0], ii[:, 1], ii[:, 2]] = 0.22 + 0.4 * crack
        if crack >= 0.95:
            # the seams open: light leaks round every crack
            from scipy import ndimage
            cr = M.m == cid
            wide = ndimage.binary_dilation(cr, iterations=1) & shell & ~cr
            M.m[wide] = M.mid('crack_rim')
            M.glow[wide] = 0.3
    out = dataclasses.replace(ch, model=M, anchors=anchors)
    out.ground_shift = y0
    return out


def egg_palette(variant):
    from palettes import palette
    pal = dict(palette(variant))
    pal['crack'] = '#FFD35C'                  # Lumen gold, so the light reads against the cream shell
    pal['crack_rim'] = '#FFD56A' if variant != 'obsidian' else '#7A6A5A'
    return pal


def egg_actor(name, variant, pos, yaw=0.0, scale=1.0, crack=0.0, seed=0, camera=True, rot=(0.0, 0.0, 0.0)):
    from cine_blender import Actor
    ch = egg_character(crack, seed)
    return Actor(name, ch, egg_palette(variant), variant, expr=None, pos=(pos[0], pos[1] - ch.ground_shift * scale, pos[2]),
                 yaw=yaw, scale=scale, camera=camera, rot=rot, glow_k=4.0)


# ------------------------------------------------------------------------------------- the Glasshouse nest ----
EGG_ORDER = ['amber', 'forest', 'coral', 'ocean', 'amethyst', 'obsidian']


def nest_model(S, P, M, cx, cz, r=9.0):
    """a mossy nest: a ring of woven straw and twigs around a bed of moss, on the Glasshouse floor"""
    ang = np.arctan2(M.Z - cz, M.X - cx)
    rr = np.sqrt((M.X - cx) ** 2 + (M.Z - cz) ** 2)
    ring = (rr > r - 3.2) & (rr < r + 0.4) & (M.Y >= 0) & (M.Y < 2.4 + 0.6 * np.sin(ang * 7) - 0.5 * np.clip((rr - r + 3.2) / 3.6, 0, 1) ** 2 * 3)
    P.fill(ring, ['#D8B56A', '#C9A35C', '#E0C07A', '#B9924E'], cell=(0.75, 0.5, 0.75))
    # twigs woven through
    for k in range(18):
        a = k * 2 * math.pi / 18 + 0.2
        tw = (np.abs(((ang - a + math.pi) % (2 * math.pi)) - math.pi) < 0.06) & (rr > r - 3.6) & (rr < r + 0.8) & (M.Y >= 0.3 + 0.4 * k % 2) & (M.Y < 1.0 + 0.4 * (k % 2) + 0.6)
        P.fill(tw, ['#8D5D3B', '#7A4E2E'], cell=9)
    moss = (rr < r - 2.6) & (M.Y >= 0) & (M.Y < 1.1 + 0.3 * np.sin(M.X * 1.3) * np.cos(M.Z * 1.1))
    P.fill(moss, ['#7CA75E', '#6F9A52', '#88B268', '#659148'], cell=0.5)
    for _ in range(26):
        a, d = np.random.uniform(0, 2 * math.pi), np.random.uniform(0, r - 3.0)
        x, z = cx + d * math.cos(a), cz + d * math.sin(a)
        P.fill(ball(M, (x, 1.1, z), 0.55, 0.6), ['#9CC76E', '#8DB868'], cell=0.5)
    for k in range(5):
        a = k * 1.26 + 0.4
        x, z = cx + (r - 1.4) * math.cos(a), cz + (r - 1.4) * math.sin(a)
        P.fill(box(M, (x - 0.2, 2.0, z - 0.2), (x + 0.2, 3.2, z + 0.2)), ['#5EA046'], cell=9)
        P.fill(ball(M, (x, 3.4, z), 0.5), [FLOWERS[k % 5]])


def glasshouse_interior(S, P, M, rng, evening=True):
    """the Glasshouse inside, as village_scenes.scene_glasshouse builds it, with evening light: a low gold sun
    through the glass and lanterns lit"""
    import village_scenes as VS
    R = VS.ROOM
    fl = box(M, (R['x0'] - 1, -1, R['back'] - 1), (R['x1'] + 1, 0, R['near']))
    P.fill(fl, TERRACOTTA, cell=(2.0, 1, 2.0))
    P.fill(fl & ((((M.X - R['x0']) % 2.0) < 0.26) | (((M.Z - R['back']) % 2.0) < 0.26)), ['#E6D5BF'], cell=9)
    for k, zz in enumerate(np.arange(R['back'] + 3.0, R['near'], 2.6)):
        xx = 1.0 + 0.15 * (zz - 2) + 0.6 * math.sin(k * 1.9)
        st_ = ((M.X - xx) ** 2 / 2.4 + (M.Z - zz) ** 2 / 1.0 <= 1.0) & (M.Y >= -0.5) & (M.Y < 0.25)
        P.fill(st_, ['#B5A68C', '#AA9A80', '#BDAF96'], cell=(1.0, 1, 1.0))
    P.fill(box(M, (R['x0'] - 1, 0, R['back'] - 1), (R['x1'] + 1, 2.5, R['back'])), STONE_LT, cell=(1.5, 0.75, 9))
    for sx in (R['x0'] - 1, R['x1']):
        P.fill(box(M, (sx, 0, R['back']), (sx + 1, 2.5, R['front'])), STONE_LT, cell=(9, 0.75, 1.5))
    VS.glass_wall_x(P, M, R['x0'] - 1, R['x1'] + 1, 2.5, 17.0, R['back'] - 1, R['back'], step=3.0, rows=(7.5, 12.5))
    for sx in (R['x0'] - 1, R['x1']):
        VS.glass_wall_z(P, M, sx, sx + 1, 2.5, 17.0, R['back'], R['front'], step=3.0, rows=(7.5, 12.5))
    ridge_y, eave_y = 22.0, 17.0
    slope = (ridge_y - eave_y) / R['x1']
    roof_y = ridge_y - np.abs(M.X) * slope
    roof = (M.Y >= roof_y) & (M.Y < roof_y + 0.8) & (np.abs(M.X) <= R['x1'] + 1) & (M.Z >= R['back'] - 1) & (M.Z < R['near'])
    P.fill(roof, CLEAR_GLASS, cell=50)
    P.fill(roof & ((((M.Z - R['back']) % 4.0) < 0.6) | (((np.abs(M.X)) % 4.5) < 0.6) | (np.abs(M.X) < 0.6)), SAGE, cell=9)
    P.fill(box(M, (R['x0'] - 1, eave_y - 0.6, R['back'] - 1), (R['x1'] + 1, eave_y, R['near'])) & (np.abs(M.X) > R['x1'] - 0.5), ['#43523D'])
    if evening:
        S.models.append((VS.surround(-26.0, 22.0, 24.0, seed=5, sky=('#5A5C9C', '#F0B080')), (), {'shadow': False}))
        S.lights.append({'type': 'sun', 'dir': (-0.75, -0.3, 0.45), 'power': 2.2, 'color': 2400, 'angle': 2.5})
        S.lights.append({'type': 'area', 'pos': (0.0, 18.0, 22.0), 'aim': (0.0, 4.0, -6.0), 'size': (30.0, 8.0), 'power': 40.0, 'color': 9000})
        for (lx, lz) in ((-8.0, -4.0), (8.0, -4.0), (0.0, 8.0)):
            lantern(S, P, M, (lx, 14.0, lz), s=0.8, lit=True, power=38.0, kelvin=2400, hang_to=ridge_y - abs(lx) * slope - 0.4)
    else:
        S.models.append((VS.surround(-26.0, 22.0, 24.0, seed=5), (), {'shadow': False}))
        S.lights.append({'type': 'sun', 'dir': (0.5, -0.8, 0.45), 'power': 2.7, 'color': 5500, 'angle': 2.5})
        S.lights.append({'type': 'area', 'pos': (0.0, 18.0, 22.0), 'aim': (0.0, 4.0, -6.0), 'size': (30.0, 8.0), 'power': 90.0, 'color': 6500})
    # tiered plant stand (back left)
    for i, (ty, tz) in enumerate(((2.2, -10.4), (4.4, -11.4), (6.6, -12.0))):
        P.fill(box(M, (-17.0, ty - 0.5, tz - 0.6), (-6.0, ty, tz + 1.2)), OAK, cell=(1.5, 1, 9))
        for j, px in enumerate(np.arange(-16.2, -6.5, 1.75)):
            VS.flower_pot(P, M, px, ty, tz + 0.3, 0.62, FLOWERS[(i + j) % len(FLOWERS)], rng)
    for lx in (-16.8, -6.6):
        P.fill(box(M, (lx, 0, -11.9), (lx + 0.5, 6.6, -9.0)), OAK_DARK, cell=9)
    # potting bench (back right) with seedling trays and the Lumenbud
    VS.table(P, M, 3.0, 14.5, R['back'] + 0.4, R['back'] + 4.6, 5.0, cols=['#C69469', '#B9875C', '#D2A176'])
    P.fill(box(M, (3.4, 1.2, R['back'] + 0.6), (14.1, 1.7, R['back'] + 4.2)), OAK_DARK, cell=(1.5, 1, 9))
    for (tx, tz) in ((4.6, -9.4), (7.6, -9.6)):
        tray = box(M, (tx - 1.3, 5.0, tz - 1.0), (tx + 1.3, 5.6, tz + 1.0))
        P.fill(tray, ['#8D5D3B'], cell=9)
        P.fill(tray & (M.Y >= 5.4), ['#5B4334', '#4F3A2D'], cell=0.5)
        for sx_ in np.arange(tx - 0.9, tx + 1.0, 0.6):
            for sz_ in (tz - 0.5, tz + 0.3):
                P.fill(box(M, (sx_ - 0.12, 5.6, sz_ - 0.12), (sx_ + 0.12, 6.2, sz_ + 0.12)), ['#86C56A'])
    lb = (11.6, 5.0, -9.4)
    P.fill(cyl_y(M, (lb[0], lb[2]), 0.9, 5.0, 5.6), TERRACOTTA, cell=9)
    P.fill(box(M, (lb[0] - 0.15, 5.6, lb[2] - 0.15), (lb[0] + 0.15, 8.0, lb[2] + 0.15)), ['#4C6B45'])
    for (dx, dy) in ((-0.5, 7.2), (0.5, 7.6), (0.0, 8.2)):
        P.fill(ball(M, (lb[0] + dx, dy, lb[2]), 0.32), V.GLASS_AMBER, glow=1.0)
    S.lights.append({'type': 'point', 'pos': (lb[0], 7.6, lb[2] + 0.4), 'power': 4.0, 'color': 2700, 'radius': 0.4})
    # vines up the back frames, hanging baskets
    for vx in (-16.5, -4.5, 1.5, 16.0):
        vine = (np.abs(M.X - vx - 0.7 * np.sin(M.Y * 0.8 + vx)) < 0.35) & (M.Z >= R['back'] - 0.2) & (M.Z < R['back'] + 0.4) & (M.Y > 2.5) & (M.Y < 16.5)
        P.fill(vine, ['#5EA046', '#4F9C3E'], cell=0.5)
        for ly in np.arange(3.5, 16.0, 1.5):
            lf = (np.abs(M.X - vx - 0.7 * np.sin(ly * 0.8 + vx) - 0.6) < 0.5) & (np.abs(M.Y - ly) < 0.35) & (M.Z >= R['back'] - 0.2) & (M.Z < R['back'] + 0.6)
            P.fill(lf & (M.m == 0) | lf & np.isin(M.m, [M.mid(c) for c in CLEAR_GLASS]), ['#86C56A', '#6FB24E'], cell=0.5)
    for (hx, hy, hz) in ((-9.0, 13.0, -2.0), (0.0, 14.5, 3.0), (9.0, 13.0, -1.0)):
        VS.hanging_plant(P, M, hx, hy, hz, ridge_y - abs(hx) * slope, 1.0)
        for k in range(3):
            P.fill(ball(M, (hx + math.cos(k * 2.1) * 1.0, hy + 1.3, hz + math.sin(k * 2.1) * 1.0), 0.3), [FLOWERS[k + 1]])
    for (x, z, s_, kind) in ((15.2, 8.8, 1.7, 1), (-17.0, 2.0, 1.5, 0), (16.6, 1.0, 1.2, 0), (-16.2, 11.0, 1.3, 1)):
        VS.flower_pot(P, M, x, 0.0, z, s_, FLOWERS[int(abs(x)) % 5], rng, kind)
    VS.barrel(P, M, 12.2, 3.0, 1.5, 3.0)
    P.fill(cyl_y(M, (12.2, 3.0), 1.3, 2.6, 2.9), ['#7FB8CF', '#8EC4D9'], cell=0.5)
    bed = box(M, (-5.4, 0, R['back']), (2.6, 2.2, R['back'] + 2.6))
    P.fill(bed, OAK_DARK, cell=(1.5, 0.75, 9))
    P.fill(bed & (M.Y >= 1.8), ['#5B4334', '#4F3A2D'], cell=0.5)
    for k, fx_ in enumerate(np.arange(-4.8, 2.4, 1.1)):
        hh = 4.0 + 1.6 * math.sin(k * 1.7) + 1.0
        P.fill(box(M, (fx_ - 0.2, 2.2, -10.8 - 0.2), (fx_ + 0.2, 2.2 + hh, -10.8 + 0.2)), ['#5EA046'])
        P.fill(ball(M, (fx_, 2.2 + hh * 0.45, -10.8), 0.9, 0.45), ['#86C56A', '#6FB24E'], cell=0.5)
        head = ball(M, (fx_, 2.2 + hh + 0.3, -10.5), 0.9, 0.55)
        P.fill(head, ['#F4C04E', '#FFFDF6', '#F5A3B5', '#E8E0FF'][k % 4], cell=0.5)
    lp = box(M, (R['x0'], 0, -10.0), (R['x0'] + 2.4, 1.8, 6.0))
    P.fill(lp, OAK, cell=(9, 0.6, 1.5))
    for fz in np.arange(-9.2, 5.6, 1.4):
        VS.flower_pot(P, M, R['x0'] + 1.2, 1.2, fz, 0.6, FLOWERS[int(fz * 3) % 5], rng, kind=0)
    for sy in (4.4, 8.0):
        P.fill(box(M, (R['x1'] - 2.2, sy - 0.5, -9.0), (R['x1'], sy, 3.0)), OAK_DARK, cell=(9, 1, 1.5))
        for fz in np.arange(-8.2, 2.6, 1.5):
            VS.flower_pot(P, M, R['x1'] - 1.1, sy, fz, 0.55, FLOWERS[int(fz * 7 + sy) % 5], rng)
    return slope, ridge_y


def _nest_scene(name, cam, eggs='all', mira=True, w=1400, h=2100, lift=None, mira_expr='happy', mira_pose=None):
    """the Glasshouse at evening with the nest of six eggs in the aisle and Mira beside it. eggs: 'all' | 'none' | a
    variant (that egg alone in the picture; the others still light and shadow)"""
    import village_scenes as VS
    S = VScene(name, w, h, cam, world=((0.5, 0.45, 0.6), 0.25), samples=160, transparent=(eggs not in ('all', 'none')))
    S.keep_alpha = S.transparent
    M = Model((-20, -2, -14), (20, 24, 29), [], res=4)
    P = CPainter(M, 51)
    rng = np.random.default_rng(51)
    glasshouse_interior(S, P, M, rng, evening=True)
    nx, nz = 0.5, 8.0
    nest_model(S, P, M, nx, nz, r=13.0)
    S.models.append((M, CLEAR_GLASS + ['#E2F5F8'], {'water': ['#7FB8CF', '#8EC4D9'], 'camera': eggs in ('all', 'none')}))
    S.actors = []
    slots = {}
    for k, v in enumerate(EGG_ORDER):
        # two gentle rows: four in front, two behind between them
        if k < 4:
            ex, ez = nx - 9.9 + k * 6.6, nz + 3.6 + (0.8 if k in (1, 2) else 0.0)
        else:
            ex, ez = nx - 3.3 + (k - 4) * 6.6, nz - 3.4
        slots[v] = (ex, 1.0, ez)
        if eggs == 'none':
            continue
        if lift and lift == v:
            pos = (ex, 0.9 + 1.6, ez)
        else:
            pos = (ex, 0.9, ez)
        S.actors.append(egg_actor('egg_' + v, v, pos, yaw=math.radians(rng.uniform(-25, 25)), scale=0.21,
                                  camera=(eggs == 'all' or eggs == v), rot=(rng.uniform(-6, 6), rng.uniform(-6, 6), 0)))
    if mira:
        from cine_blender import Actor
        from village_npcs import build_mira, INK
        from village_npc_render import npc_palette
        chm = build_mira(res=CAST_RES)
        S.actors.append(Actor('mira', chm, npc_palette(chm, INK), 'mira', expr=mira_expr, pos=(-11.0, 0.0, -5.0),
                              yaw=math.radians(18 if cam is MIRA_CAM else -30), scale=0.42, camera=eggs in ('all', 'none'),
                              pose=mira_pose))
    if eggs not in ('all', 'none'):
        S.models = [(m[0], m[1], dict(m[2] if len(m) > 2 else {}, camera=False)) for m in S.models]
    S.anchors = dict(slots)
    S.anchors['nest'] = (nx, 1.0, nz)
    S.anchors['mira_face'] = (-11.0, 0.42 * 19.6, -5.0 + 0.42 * 8.4)
    S.grade = {'bloom': 0.42, 'bloom_threshold': 170.0, 'glow': 0.14, 'warm': 0.05, 'saturation': 1.05, 'vignette': 0.26,
               'split': {'highlights': '#FFD9A0', 'shadows': '#5A5A9A', 'amount': 0.1}, 'grain': 0.01, 'keep_alpha': S.transparent}
    S.zmax = 8.0
    return S


NEST_CAM = {'pos': (0.5, 20.0, 46.0), 'target': (0.0, 4.5, 3.0), 'fov': 48.0, 'focus': (0.5, 3.0, 10.0), 'fstop': 3.2}
MIRA_CAM = {'pos': (-3.0, 10.5, 27.0), 'target': (-10.0, 7.5, -5.0), 'fov': 40.0, 'focus': (-11.0, 8.2, -1.5), 'fstop': 2.2}
AISLE_CAM = {'pos': (2.0, 10.0, 30.0), 'target': (-3.0, 5.5, -4.0), 'fov': 54.0, 'focus': (-9.0, 6.0, -1.0), 'fstop': 2.4}


def scene_nest():
    return _nest_scene('nest', NEST_CAM, 'all', mira=True)


def scene_nest_empty():
    return _nest_scene('nest_empty', NEST_CAM, 'none', mira=True)


# Mira beside the nest in motion: the same shot rendered in a few poses, the app cuts her out of each (a feathered
# box round her) and plays them over the plate: a blink, a lean to look down at the eggs, a little lift of what she
# holds, a look back at you. (pitch, yaw, roll) per part, degrees; yaw + turns her face to her left (toward the
# eggs in this shot)
MIRA_POSES = {
    'nest_m0': ('happy', None),
    'nest_m1': ('blink', None),
    'nest_m2': ('happy', {'head': (4.0, 6.0, 3.0)}),
    'nest_m3': ('happy', {'head': (8.0, 12.0, 6.0)}),
    'nest_m4': ('proud', {'head': (10.0, 15.0, 7.0), 'arm': (7.0, 0.0, 0.0)}),
    'nest_m5': ('happy', {'head': (-3.0, -5.0, -4.0)}),
}


def scene_nest_pose(name):
    expr, pose = MIRA_POSES[name]
    return _nest_scene(name, NEST_CAM, 'none', mira=True, mira_expr=expr, mira_pose=pose)


def scene_nest_egg(v):
    return _nest_scene('nest_egg_' + v, NEST_CAM, v, mira=True)


def scene_mira():
    return _nest_scene('mira', MIRA_CAM, 'all', mira=True)


def scene_aisle():
    return _nest_scene('aisle', AISLE_CAM, 'all', mira=True)


# ------------------------------------------------------------------------------------- the steps screen ----
def scene_steps(matte=False):
    """Beat 3, the steps screen: the Ocean Eggling (Mochi) walking toward us through dawn grass down a clean sandy
    path. Its steps are the app's: each print lands, glows and fades on the path behind it (onboarding_screens.dart),
    placed by the anchors here (print<k>: the foot's centre, print<k>_x / _y: where one unit across and one unit
    back from the toes land, so the app draws each print in the ground's perspective). No real-world props (they
    break the world). [matte]: Mochi alone on transparent (the rest hidden from the camera), the same frame, so the
    app can draw Mochi back over the prints: a step behind it never lands on it."""
    cam = {'pos': (-3.0, 20.0, 50.0), 'target': (-1.5, 1.2, 0.5), 'fov': 36.0, 'focus': (-6.5, 1.5, 11.5), 'fstop': 3.6}
    S = VScene('steps_matte' if matte else 'steps', 1400, 1400, cam, world=((0.9, 0.85, 0.75), 0.4), samples=24 if matte else 160,
               transparent=True, sky=('#8FB8D8', '#F7D7A8'))
    S.sky_world = {'sky': ('#8FB8D8', '#F7D7A8'), 'ground': '#6F8F5A', 'strength': 0.3}
    S.lights.append({'type': 'sun', 'dir': (0.55, -0.42, -0.72), 'power': 1.5, 'color': 3200, 'angle': 2.5})
    S.zmax = 30.0
    rng = np.random.default_rng(61)
    M = Model((-40, -3, -40), (40, 22, 44), [], res=3)
    P = CPainter(M, 61)
    ground = (M.Y >= -1) & (M.Y < 0)
    P.fill((M.Y >= -3) & (M.Y < -1), ['#8E6A48', '#7E5C3E'], cell=1)
    P.fill(ground, GRASS, cell=0.75)
    P.fill(ground & (noise2(M.X[:, 0, :], M.Z[:, 0, :], 3, 3.0, 2)[:, None, :] > 0.6), ['#79A85A', '#73A255'], cell=0.75)
    # a sandy path from the back right to the front left, the way Mochi walks
    X2, Z2 = M.X[:, 0, :], M.Z[:, 0, :]
    path = catmull([(14.0, -34.0), (6.0, -16.0), (0.0, -2.0), (-6.0, 13.0), (-14.0, 26.0), (-24.0, 42.0)], 120)
    dpath, tpath = dist2d(X2, Z2, path)
    P.fill(ground & (dpath < 4.2 + 1.0 * np.sin(Z2 * 0.5))[:, None, :], ['#E6D5B4', '#DCC9A4', '#EBDCBE'], cell=0.75)
    # grass tufts and flowers either side of the path
    for _ in range(520):
        x, z = rng.uniform(-36, 36), rng.uniform(-36, 40)
        ix, iz = int((x - M.lo[0] / M.res) * M.res), int((z - M.lo[2] / M.res) * M.res)
        if dpath[ix, iz] < 4.8:
            continue
        L = Local(M, (x - 1.5, -0.5, z - 1.5), (x + 1.5, 4.5, z + 1.5))
        if rng.random() < 0.7:
            h = rng.uniform(0.8, 2.6)
            for k in range(3):
                dx, dz = rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6)
                P.fill(L.full(L.box((x + dx - 0.17, 0, z + dz - 0.17), (x + dx + 0.17, h - 0.3 * k, z + dz + 0.17))), ['#6FA552', '#86C56A', '#5E9646'], cell=9)
        else:
            P.fill(L.full(L.box((x - 0.17, 0, z - 0.17), (x + 0.17, 1.6, z + 0.17))), ['#5EA046'], cell=9)
            P.fill(L.full(L.ball((x, 1.9, z), 0.5)), [FLOWERS[rng.integers(5)]])
    for (tx, tz, h, r) in ((-30.0, -24.0, 9, 6), (26.0, -30.0, 10, 7), (34.0, 10.0, 8, 5.5), (-34.0, 2.0, 7, 5)):
        V.tree2(P, M, tx, tz, h, r)
    # the Eggling (Ocean) mid-waddle, walking toward us and to the left; its Lumen prints trail back up the path
    mpos = np.array([-7.0, 0.0, 12.0])
    mdir = np.array([-0.4, 0.0, 0.92])
    mdir /= np.linalg.norm(mdir)
    hd = math.degrees(math.atan2(mdir[0], mdir[2]))
    across = np.array([mdir[2], 0.0, -mdir[0]])
    prints = []
    s_ = 0.46  # the foot's size (foot_mask2d's units)
    for k in range(7):
        side = 1.0 if k % 2 == 0 else -1.0
        q = mpos - mdir * (3.4 + k * 3.4) + across * side * 1.2
        # the app's foot (FootTrail, one unit long, toes toward -y) scaled to this foot: K world units a unit
        K = 10.0 * s_
        c = q + mdir * 0.7 * s_
        prints.append({'pos': (float(c[0]), 0.0, float(c[2])),
                       'x': tuple(float(v) for v in (c + across * K)),
                       'y': tuple(float(v) for v in (c - mdir * K))})
    S.models.append((M, (), {'camera': False} if matte else {}))
    from cine_blender import Actor
    from characters import build_eggling
    from palettes import palette
    ch = build_eggling(res=CAST_RES, lean=6.0, feet={(1, True): (1.2, 1.0), (-1, False): (0.6, -0.6)})
    S.actors = [Actor('mochi', ch, dict(palette('ocean')), 'ocean', expr='happy', pos=tuple(mpos.tolist()), yaw=math.radians(hd + 12), scale=0.26)]
    S.anchors = {'mochi': (float(mpos[0]), 6.0 * 0.26, float(mpos[2]))}
    for k, pr in enumerate(prints):
        S.anchors['print%d' % k] = pr['pos']
        S.anchors['print%d_x' % k] = (pr['x'][0], 0.0, pr['x'][2])
        S.anchors['print%d_y' % k] = (pr['y'][0], 0.0, pr['y'][2])
    if matte:
        S.keep_alpha = True
        S.grade = {'keep_alpha': True}
        return S
    S.grade = {'bloom': 0.4, 'bloom_threshold': 185.0, 'bloom_wide': 0.15, 'glow': 0.14, 'warm': 0.05, 'saturation': 1.08,
               'split': {'highlights': '#FFE0B0', 'shadows': '#6A6A9A', 'amount': 0.08}, 'vignette': 0.22, 'grain': 0.008,
               'mist': {'start': 18.0, 'end': 44.0, 'amount': 0.22, 'color': '#F4E2C4', 'power': 1.2}, 'sky_mix': 0.6}
    return S


# ------------------------------------------------------------------------------------------ Pip's letter ----
def scene_pip(gold=False, expr='happy', pose=None, name=None):
    """Beat 4: Pip the Courier up close, holding out the letter (his courier model, the letter in his wing). The
    gold-sealed founders' letter is the same shot with the seal recoloured. Rendered over the Lodge's counter in
    evening lantern light."""
    import village_scenes as VS
    from cine_blender import Actor
    from village_npcs import build_pip, INK
    from village_npc_render import npc_palette
    sc_ = 0.42
    ppos = (0.5, 0.0, 2.0)
    face = (ppos[0], sc_ * 19.2, ppos[2] + sc_ * 8.6)
    cam = {'pos': (4.0, 9.5, 31.0), 'target': (-0.5, 8.6, 2.0), 'fov': 40.0, 'focus': face, 'fstop': 2.0}
    S = VScene(name or ('pip_gold' if gold else 'pip'), 1400, 1800, cam, world=((0.88, 0.84, 0.78), 0.16), samples=160)
    M = Model((-20, -2, -14), (20, 22, 29), [], res=3)
    P = CPainter(M, 71)
    rng = np.random.default_rng(71)
    R = VS.ROOM
    VS.room_shell(P, M, OAK, PLASTER, side_cols=['#E6D9B0', '#DED0A6'], wall_cell=(3, 3, 3))
    # the sorting desk beside him (solid, panelled), pigeonholes of letters behind, a lantern, parcels
    VS.table(P, M, 6.5, 16.0, -4.0, 1.5, 6.0, cols=['#C69469', '#B9875C', '#D2A176'])
    P.fill(box(M, (6.7, 0.4, 1.0), (15.8, 5.4, 1.5)), OAK_DARK, cell=(2.4, 9, 9))
    P.fill(box(M, (6.7, 0.4, 1.3), (15.8, 5.4, 1.6)) & ((((M.X - 6.7) % 3.1) < 0.35) | (np.abs(M.Y - 2.9) < 0.2)), WALNUT, cell=9)
    for k, lx in enumerate(np.arange(7.4, 15.0, 1.6)):
        VS.letter(P, M, lx, 6.3, -1.0 + 0.4 * (k % 2), w=1.3, h=0.2, seal=None)
    for (x0, x1, y0, y1) in ((-15.0, -2.0, 7.0, 15.0),):
        P.fill(box(M, (x0, y0, R['back']), (x1, y1, R['back'] + 1.4)), OAK_DARK, cell=(9, 9, 9))
        for cx in np.arange(x0 + 0.3, x1, 2.2):
            for cy in np.arange(y0 + 0.3, y1, 2.0):
                hole = box(M, (cx, cy, R['back']), (cx + 1.9, cy + 1.7, R['back'] + 1.4))
                M.m[hole] = 0
                if rng.random() < 0.7:
                    VS.letter(P, M, cx + 1.0, cy + 0.7, R['back'] + 0.3, w=1.4, h=0.9, seal='#D85F51' if rng.random() < 0.4 else None)
    for (px, pz, s_) in ((10.0, 4.6, 1.5), (13.4, 5.4, 1.1), (-11.0, 5.0, 1.3)):
        VS.parcel(P, M, px, 0.0, pz, s_, s_ * 0.6, s_)
    lantern(S, P, M, (9.0, 14.5, 0.0), s=0.9, lit=True, power=38.0, kelvin=2400, hang_to=R['h'])
    lantern(S, P, M, (-13.0, 9.0, 8.5), s=0.7, lit=True, power=16.0, kelvin=2400)
    S.lights.append({'type': 'area', 'pos': (4.0, 14.0, 26.0), 'aim': (0.0, 7.0, 2.0), 'size': (20.0, 12.0), 'power': 45.0, 'color': 5500})
    S.models.append((M, (), {}))
    chp = build_pip(res=CAST_RES)
    pal = npc_palette(chp, INK)
    if gold:
        # the founders' letter: a gold seal and a gold-edged envelope
        Mp = chp.model
        for src, dst in (('#B8402F', '#E8B956'), ('#E6D3AE', '#F2D27A')):
            if src in Mp.ids:
                Mp.m[Mp.m == Mp.ids[src]] = Mp.mid(dst)
        pal['#E8B956'] = '#E8B956'
        pal['#F2D27A'] = '#F2D27A'
    S.actors = [Actor('pip', chp, pal, 'pip', expr=expr, pos=ppos, yaw=math.radians(10), scale=sc_, pose=pose)]
    S.anchors = {'letter': (ppos[0] - sc_ * 9.0, sc_ * 24.0, ppos[2] + sc_ * 4.0), 'face': face}
    S.grade = {'bloom': 0.4, 'bloom_threshold': 175.0, 'glow': 0.14, 'warm': 0.05, 'saturation': 1.05, 'vignette': 0.26,
               'split': {'highlights': '#FFD9A0', 'shadows': '#5A5A9A', 'amount': 0.1}, 'grain': 0.01}
    S.zmax = 8.0
    return S



# Pip in motion: the same shot in a few poses (the app cuts him out of each and plays them over the plate): a
# blink, a tilt of the head toward you, and his wing lifting the letter toward you. (pitch, yaw, roll) per part,
# degrees: yaw + turns his face toward the camera, roll - raises the letter wing, pitch + tips it toward you
PIP_POSES = {
    'pip_p0': ('happy', None),
    'pip_p1': ('blink', None),
    'pip_p2': ('happy', {'head': (0.0, 4.0, 3.0)}),
    'pip_p3': ('happy', {'head': (-1.0, 8.0, 6.0)}),
    'pip_p4': ('happy', {'head': (-2.0, 11.0, 9.0)}),
    'pip_p5': ('happy', {'arm': (4.0, 0.0, -5.0)}),
    'pip_p6': ('happy', {'arm': (8.0, 0.0, -10.0), 'head': (0.0, -3.0, -2.0)}),
    'pip_p7': ('proud', {'arm': (12.0, 0.0, -14.0), 'head': (0.0, -5.0, -4.0)}),
}


def scene_pip_pose(name):
    expr, pose = PIP_POSES[name]
    return scene_pip(False, expr, pose, name)


# ------------------------------------------------------------------------------------- egg sprites, hatch ----
EGG_CRACKS = {'0': 0.0, '1': 0.35, '2': 0.7, '3': 1.0}


def orbit_cam(yaw, pitch, dist, target=(0.0, 14.0, 0.0), fov=22.0, fstop=None):
    """a camera the way the flat renderer frames things: yaw turns it toward +x, pitch raises it (degrees)"""
    y, p = math.radians(yaw), math.radians(pitch)
    d = np.array([math.sin(y) * math.cos(p), math.sin(p), math.cos(y) * math.cos(p)])
    pos = np.asarray(target) + d * dist
    cam = {'pos': tuple(pos.tolist()), 'target': tuple(target), 'fov': fov}
    if fstop:
        cam['focus'] = tuple(target)
        cam['fstop'] = fstop
    return cam


def scene_egg_sprite(variant, crack_key='0'):
    """one egg as a sprite for the Home nest (the hatch beats): the Eggling's hero angle (build_characters.HERO_CAM
    for stage 1: yaw 18, pitch 13), lit like the meadow at golden hour, its cracks glowing, over a shadow catcher,
    on a transparent film"""
    crack = EGG_CRACKS[crack_key]
    cam = orbit_cam(18.0, 13.0, 130.0, target=(0.0, 15.0, 0.0), fov=20.0)
    S = VScene('egg_%s_%s' % (variant, crack_key), 700, 760, cam, world=((0.9, 0.86, 0.8), 0.5), samples=128, transparent=True)
    S.keep_alpha = True
    # a step dimmer than with the voxels shading themselves: the smooth stand-in leaves the cream shell its full light
    S.sky_world = {'sky': ('#B9D6EA', '#FFE3BE'), 'ground': '#7F9F6A', 'strength': 0.45}
    S.lights.append({'type': 'sun', 'dir': (0.42, -0.78, -0.48), 'power': 2.2, 'color': 4500, 'angle': 4.0})
    S.lights.append({'type': 'area', 'pos': (-30.0, 30.0, 40.0), 'aim': (0.0, 12.0, 0.0), 'size': (30.0, 30.0), 'power': 95.0, 'color': 6500})
    # a shadow catcher under it
    G = Model((-30, -2, -30), (30, 0, 30), [], res=1)
    G.set(G.box((-30, -2, -30), (30, 0, 30)), '#9CC76E')
    S.models.append((G, (), {'shadow_catcher': True}))
    S.actors = [egg_actor('egg', variant, (0.0, 0.0, 0.0), yaw=0.0, scale=1.0, crack=crack, seed=EGG_ORDER.index(variant))]
    if crack >= 0.7:
        # the cracks' light spilling onto the grass in front (outside the shell: the smooth stand-in, not the voxels,
        # is what blocks light now, and a light inside would shine straight through)
        S.lights.append({'type': 'point', 'pos': (0.0, 4.0, 17.0), 'power': 6.0 * crack, 'color': (1.0, 0.8, 0.42), 'radius': 3.0})
    S.anchors = {'ground': (0.0, 0.0, 0.0), 'top': (0.0, 31.5, 0.0)}
    S.grade = {'bloom': 0.3 if crack > 0 else 0.1, 'bloom_threshold': 190.0, 'warm': 0.02, 'keep_alpha': True}
    S.zmax = 20.0
    return S


def scene_egg_shards(variant):
    """the shell in pieces for the hatch burst: the egg cut by four planes, each piece flung a little apart, as one
    sprite sheet the app cuts up (cine.json carries each piece's box)"""
    cam = orbit_cam(18.0, 13.0, 130.0, target=(0.0, 15.0, 0.0), fov=20.0)
    S = VScene('egg_shards_%s' % variant, 900, 760, cam, world=((0.9, 0.86, 0.8), 0.5), samples=96, transparent=True)
    S.keep_alpha = True
    S.sky_world = {'sky': ('#B9D6EA', '#FFE3BE'), 'ground': '#7F9F6A', 'strength': 0.65}
    S.lights.append({'type': 'sun', 'dir': (0.42, -0.78, -0.48), 'power': 2.6, 'color': 4500, 'angle': 4.0})
    from cine_blender import Actor
    import dataclasses
    ch = egg_character(0.0)
    M = ch.model
    S.actors = []
    pieces = []
    # cutting planes through the egg's centre: (normal, offset); a piece is what lies on the + side of each of its planes
    cuts = [((0.0, 1.0, 0.0), 8.0), ((1.0, 0.3, 0.4), 2.0), ((-1.0, 0.3, 0.4), 2.0), ((0.0, 0.2, -1.0), 1.0)]
    specs = [([0], 'cap'), ([1], 'right'), ([2], 'left'), ([3], 'back')]
    for k, (which, label) in enumerate(specs):
        Mk = M.copy()
        keep = np.ones(M.m.shape, bool)
        for ci in which:
            n, off = cuts[ci]
            keep &= (M.X * n[0] + (M.Y - 15.0) * n[1] + M.Z * n[2]) > off
            # the cap is only what is above the top cut; the sides exclude the cap
        if label != 'cap':
            n, off = cuts[0]
            keep &= (M.X * n[0] + (M.Y - 15.0) * n[1] + M.Z * n[2]) <= off
        Mk.m[~keep] = 0
        Mk.glow[~keep] = 0
        chk = dataclasses.replace(ch, model=Mk)
        chk.ground_shift = 0.0
        spread = {'cap': (0.0, 6.0, 0.0), 'right': (14.0, 1.0, 4.0), 'left': (-14.0, 1.0, 4.0), 'back': (0.0, 2.0, -12.0)}[label]
        S.actors.append(Actor('shard_' + label, chk, egg_palette(variant), variant, expr=None, pos=spread, yaw=0.0, scale=1.0,
                              rot=(10.0 if label == 'cap' else 0.0, 0.0, 0.0)))
        pieces.append(label)
    S.anchors = {label: {'cap': (0.0, 27.0, 0.0), 'right': (18.0, 10.0, 4.0), 'left': (-18.0, 10.0, 4.0), 'back': (0.0, 12.0, -12.0)}[label] for label in pieces}
    S.grade = {'keep_alpha': True}
    S.zmax = 20.0
    return S


# ------------------------------------------------------------------------------------- the Elder teaser ----
ELDER_ORBIT_FRAMES = 36
AFFINITY_OF = {'amber': 'lumen', 'forest': 'nature', 'coral': 'ember', 'ocean': 'water', 'obsidian': 'stone', 'amethyst': 'celestial'}
AFFINITY_GLOW = {'lumen': '#F4B84E', 'nature': '#5FA046', 'ember': '#EC7A4A', 'water': '#4C9BCC', 'stone': '#8E887E', 'celestial': '#9975C9'}


def scene_elder_orbit(variant, frames=ELDER_ORBIT_FRAMES, res=4, expr='default'):
    """the three-second glimpse of what the egg becomes: the Stage-3 Elder (characters.build_elder, as the game
    draws it) standing on a ring of its affinity's light while the camera orbits it: one scene, a camera per
    frame (rendered as elder_<variant>_00 .. _35)"""
    from cine_blender import Actor
    from characters import build
    from palettes import palette
    # the Elder at twice the game's voxel grain (the same model, finer steps: it fills the screen here), its
    # default face; the camera aims at the body's middle at one distance for the whole orbit, the one its widest
    # angle needs, so it never pumps in and out as it turns and the whole Elder and its ring stay in frame
    ch = build(3, res=res)
    idx = np.argwhere(ch.model.m > 0)
    lo = (idx.min(0) + ch.model.lo) / ch.model.res
    hi = (idx.max(0) + 1 + ch.model.lo) / ch.model.res
    cx, cz = float(lo[0] + hi[0]) / 2, float(lo[2] + hi[2]) / 2
    hx, hz = float(hi[0] - lo[0]) / 2, float(hi[2] - lo[2]) / 2
    # a landscape frame (the long body turns side-on), shown as a wide panel on the pick card
    W, H = 1000, 720
    fov, aspect = 24.0, W / H
    tan_h = math.tan(math.radians(fov / 2)) * aspect
    yaws = [36.0 + 360.0 * f / frames for f in range(frames)]
    dist = max(max(1.1 * (hx * abs(math.cos(math.radians(y))) + hz * abs(math.sin(math.radians(y)))) / tan_h for y in yaws),
               1.25 * float(hi[1]) / 2 / math.tan(math.radians(fov / 2)))
    cams = [orbit_cam(yaw, 11.0, dist, target=(cx, 13.5, cz), fov=fov, fstop=5.6) for yaw in yaws]   # a little low: the ring's near side stays in
    S = VScene('elder_%s' % variant, W, H, cams[0], world=((0.08, 0.07, 0.12), 0.35), samples=96, transparent=True)
    S.cameras = cams
    S.keep_alpha = True
    col = AFFINITY_GLOW[AFFINITY_OF[variant]]
    rgb = tuple(int(col[i:i + 2], 16) / 255 for i in (1, 3, 5))
    S.lights.append({'type': 'area', 'pos': (-40.0, 70.0, 50.0), 'aim': (0.0, 20.0, 0.0), 'size': (40.0, 40.0), 'power': 900.0, 'color': (1.0, 0.9, 0.78)})
    S.lights.append({'type': 'area', 'pos': (50.0, 40.0, -40.0), 'aim': (0.0, 20.0, 0.0), 'size': (30.0, 30.0), 'power': 500.0, 'color': rgb})
    S.lights.append({'type': 'point', 'pos': (0.0, 2.0, 0.0), 'power': 220.0, 'color': rgb, 'radius': 6.0})
    G = Model((-50, -2, -58), (50, 1, 42), [], res=4)
    P = CPainter(G, 3)
    rr = np.sqrt((G.X - cx) ** 2 + ((G.Z - cz) * 0.62) ** 2)      # an oval under the long body
    P.fill((np.abs(rr - 26.0) < 1.4) & (G.Y >= -0.2) & (G.Y < 0.5), [col], glow=1.6, cell=9)
    Gc = Model((-60, -2, -60), (60, 0, 60), [], res=1)
    Gc.set(Gc.box((-60, -2, -60), (60, 0, 60)), '#2A2638')
    S.models.append((Gc, (), {'shadow_catcher': True}))
    P.fill((np.abs(rr - 30.0) < 0.5) & (G.Y >= -0.2) & (G.Y < 0.3), [col], glow=0.8, cell=9)
    for k in range(5):
        a = k * 1.26
        m = lumen_print_mask(G, (cx + 30.0 * math.cos(a), 0.0, cz + 30.0 / 0.62 * math.sin(a) * 0.75), k * 72.0, 0.9)
        P.fill(m, [col], glow=1.2, cell=9)
    S.models.append((G, (), {}))
    S.actors = [Actor('elder', ch, dict(palette(variant)), variant, expr=expr, pos=(0.0, 0.0, 0.0), yaw=0.0, scale=1.0)]
    S.anchors = {'ground': (0.0, 0.0, 0.0), 'head': ch.anchors.get('head_top', (0, 40, 0))}
    S.grade = {'bloom': 0.5, 'bloom_threshold': 170.0, 'bloom_wide': 0.3, 'keep_alpha': True}
    S.zmax = 40.0
    return S


SCENES = {
    'lumen_print': scene_lumen_print,
    'map_lit': lambda: scene_map('lit'),
    'map_faded': lambda: scene_map('faded'),
    'map_hollow': lambda: scene_map('hollow'),
    'village_dusk': scene_village_dusk,
    'glasshouse_night': scene_glasshouse_night,
    'nest': scene_nest, 'nest_empty': scene_nest_empty, 'mira': scene_mira, 'aisle': scene_aisle,
    'steps': scene_steps, 'steps_matte': lambda: scene_steps(True), 'pip': scene_pip,
    **{n: (lambda n=n: scene_pip_pose(n)) for n in PIP_POSES},
    **{n: (lambda n=n: scene_nest_pose(n)) for n in MIRA_POSES}, 'pip_gold': lambda: scene_pip(True),
}
for _v in EGG_ORDER:
    SCENES['nest_egg_' + _v] = (lambda v=_v: scene_nest_egg(v))
    SCENES['egg_shards_' + _v] = (lambda v=_v: scene_egg_shards(v))
    for _k in EGG_CRACKS:
        SCENES['egg_%s_%s' % (_v, _k)] = (lambda v=_v, k=_k: scene_egg_sprite(v, k))
    SCENES['elder_' + _v] = (lambda v=_v: scene_elder_orbit(v))

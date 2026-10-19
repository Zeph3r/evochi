"""Village Tales, Chapter 1 scenes: dense voxel sets lit in Blender (rendered by village_blender.py).

Same voxel language as the rest of the pack (Model + Painter fills), with two changes:
 - colours vary per block, plank or brick instead of per voxel, so surfaces read as built things
   rather than noise;
 - every scene carries real lights (lanterns, furnace, sun through windows) for Cycles.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np
from PIL import Image, ImageFilter

from voxel import Model

# ---------------------------------------------------------------- palette (Quest Bible §2) ----
OAK = ['#B98955', '#AD7E4C', '#C4925E', '#B3834F']
OAK_DARK = ['#8D5D3B', '#7E5133', '#986642']
WALNUT = ['#6E4529', '#5E3A24', '#7A4E2E']
HONEY = ['#C69469', '#B9875C', '#D2A176']
BRICK = ['#B76B4D', '#A95F43', '#C27658', '#B06548', '#9E5A40']
MORTAR = ['#D8C6A8']
PLASTER = ['#F3E5C9', '#EEDDBD', '#F7ECD8']
STONE = ['#9C968C', '#8E887E', '#A8A297', '#837D74']
STONE_LT = ['#C9C2AE', '#BDB5A0', '#D3CCB9']
IRON = ['#4A3F3A', '#3F3531', '#554943']
COPPER = ['#C9874E', '#B8773F', '#D9985E']
BRASS = ['#E8B956', '#D9A845']
GLASS_AMBER = ['#FFD46A', '#FFE08A']
GLASS_MINT = ['#9FE3CF', '#BDF2E2']
GLASS_ROSE = ['#F5A3B5', '#F8B9C6']
PARCH = ['#FBF5E8', '#F1E6CF']
NAVY = ['#203B50', '#284A63']
SAGE = ['#7F9871', '#76906A']
LEAF = ['#6FB24E', '#5EA046', '#86C56A', '#4F9C3E']
CREAM = ['#F3E5C9']
CLEAR_GLASS = ['#E8F7F9', '#DDF3F6']


class CPainter:
    """Colour fills that vary per block (cell) instead of per voxel."""

    def __init__(self, M: Model, seed=1):
        self.M = M
        self.seed = seed
        self.rng = np.random.default_rng(seed)

    def fill(self, mask, cols, glow=None, cell=(1.0, 1.0, 1.0), offset=(0.0, 0.0, 0.0)):
        if isinstance(cols, str):
            cols = [cols]
        if not mask.any():
            return mask
        M = self.M
        if isinstance(cell, (int, float)):
            cell = (cell, cell, cell)
        cx = np.floor((M.X[mask] + offset[0]) / cell[0]).astype(np.int64)
        cy = np.floor((M.Y[mask] + offset[1]) / cell[1]).astype(np.int64)
        cz = np.floor((M.Z[mask] + offset[2]) / cell[2]).astype(np.int64)
        h = (cx * 73856093) ^ (cy * 19349663) ^ (cz * 83492791) ^ (self.seed * 2654435761)
        h = (h ^ (h >> 13)) * 1274126177
        k = np.abs(h ^ (h >> 16)) % len(cols)
        ids = np.array([M.mid(c) for c in cols], np.uint8)
        M.m[mask] = ids[k]
        if glow is not None:
            M.glow[mask] = glow
        return mask


def box(M, lo, hi):
    return (M.X >= lo[0]) & (M.X < hi[0]) & (M.Y >= lo[1]) & (M.Y < hi[1]) & (M.Z >= lo[2]) & (M.Z < hi[2])


def cyl_y(M, c, r, y0, y1):
    return ((M.X - c[0]) ** 2 + (M.Z - c[1]) ** 2 <= r * r) & (M.Y >= y0) & (M.Y < y1)


def ball(M, c, r, sy=1.0):
    return (M.X - c[0]) ** 2 + ((M.Y - c[1]) / sy) ** 2 + (M.Z - c[2]) ** 2 <= r * r


@dataclass
class VScene:
    name: str
    w: int
    h: int
    cam: dict
    models: list = field(default_factory=list)       # (Model, glass colour names)
    lights: list = field(default_factory=list)
    world: tuple = ((0.6, 0.55, 0.5), 0.3)
    anchors: dict = field(default_factory=dict)
    samples: int = 160
    transparent: bool = False
    view: str = 'Khronos PBR Neutral'
    look: str = ''
    exposure: float = 0.0
    sky: tuple = None                                  # (top, horizon) hex for transparent renders
    grade: dict = field(default_factory=dict)


# ------------------------------------------------------------------ props ----
def lantern(S, P, M, c, s=1.0, lit=True, glass=GLASS_AMBER, power=18.0, kelvin=2400, hang_to=None):
    """Iron-framed lantern; lit ones glow and carry a point light. `hang_to` = ceiling y for a chain."""
    x, y, z = c
    body = (np.maximum(np.abs(M.X - x), np.abs(M.Z - z)) <= 0.9 * s) & (M.Y >= y - 1.1 * s) & (M.Y < y + 1.1 * s)
    P.fill(body, glass if lit else ['#8C8A78', '#7D7B6A'], glow=0.75 if lit else None)
    frame = body & ((np.abs(np.abs(M.X - x) - 0.9 * s) < 0.3) & (np.abs(np.abs(M.Z - z) - 0.9 * s) < 0.3) |
                    (M.Y >= y + 0.75 * s) | (M.Y < y - 0.75 * s))
    P.fill(frame, IRON)
    cap = (np.maximum(np.abs(M.X - x), np.abs(M.Z - z)) <= 1.2 * s - (M.Y - y - 1.1 * s) * 0.9) & (M.Y >= y + 1.1 * s) & (M.Y < y + 1.9 * s)
    P.fill(cap, IRON)
    P.fill(box(M, (x - 0.25, y + 1.9 * s, z - 0.25), (x + 0.25, y + 2.4 * s, z + 0.25)), BRASS)
    if hang_to is not None:
        P.fill(box(M, (x - 0.2, y + 2.4 * s, z - 0.2), (x + 0.2, hang_to, z + 0.2)), IRON)
    if lit:
        S.lights.append({'type': 'point', 'pos': (x, y, z), 'power': power * s * s, 'color': kelvin, 'radius': 0.5 * s})


def shelf_board(P, M, x0, x1, y, z0, z1, cols=OAK_DARK, brackets=True):
    P.fill(box(M, (x0, y - 0.5, z0), (x1, y, z1)), cols, cell=(2.0, 1, 4))
    if brackets:
        for bx in (x0 + 0.6, x1 - 1.0):
            P.fill(box(M, (bx, y - 1.5, z0), (bx + 0.5, y - 0.5, z0 + 0.6)), IRON)


def jar(P, M, x, y, z, h=1.6, r=0.6, cols=GLASS_MINT, lid=COPPER, glow=None):
    P.fill(cyl_y(M, (x, z), r, y, y + h), cols, glow=glow)
    P.fill(cyl_y(M, (x, z), r * 0.75, y + h, y + h + 0.5), lid)


def books(P, M, x0, x1, y, z0, z1, rng):
    x = x0
    pal = ['#B76B4D', '#203B50', '#7F9871', '#E8B956', '#8D5D3B', '#5A7C9A', '#C27658']
    while x < x1 - 0.4:
        wdt = rng.choice([0.5, 0.5, 1.0])
        hh = rng.uniform(1.4, 2.4)
        P.fill(box(M, (x, y, z0), (min(x + wdt, x1), y + hh, z1)), [pal[rng.integers(len(pal))]], cell=9)
        x += wdt
    return x


def crate(P, M, x, z, s, y=0.0):
    c = box(M, (x - s, y, z - s), (x + s, y + 2 * s, z + s))
    P.fill(c, HONEY, cell=(2 * s, 0.5, 2 * s))
    edge = c & ((np.abs(np.abs(M.X - x) - s) < 0.5) & (np.abs(np.abs(M.Z - z) - s) < 0.5) |
                (M.Y >= y + 2 * s - 0.5) | (M.Y < y + 0.5) | (np.abs(M.Y - y - s) < 0.25))
    P.fill(edge, OAK_DARK, cell=8)
    return c


def barrel(P, M, x, z, r=1.6, h=3.4, y=0.0):
    b = ((M.X - x) ** 2 + (M.Z - z) ** 2 <= (r * (1 + 0.12 * np.sin(np.clip((M.Y - y) / h, 0, 1) * math.pi))) ** 2) & (M.Y >= y) & (M.Y < y + h)
    ang = np.arctan2(M.Z - z, M.X - x)
    P.fill(b, OAK, cell=8)
    P.fill(b & (np.abs(((ang + math.pi) / (2 * math.pi) * 14) % 1 - 0.5) > 0.42), OAK_DARK, cell=8)
    P.fill(b & ((np.abs(M.Y - y - 0.7) < 0.3) | (np.abs(M.Y - y - h + 0.7) < 0.3)), IRON, cell=9)
    return b


def table(P, M, x0, x1, z0, z1, top_y, cols=OAK, leg=WALNUT):
    P.fill(box(M, (x0, top_y - 0.6, z0), (x1, top_y, z1)), cols, cell=(1.5, 1, 9))
    for lx in (x0 + 0.4, x1 - 0.9):
        for lz in (z0 + 0.4, z1 - 0.9):
            P.fill(box(M, (lx, 0, lz), (lx + 0.5, top_y - 0.6, lz + 0.5)), leg)


def rug(P, M, cx, cz, rx, rz, cols, border):
    r = ((M.X - cx) / rx) ** 2 + ((M.Z - cz) / rz) ** 2
    m = (r <= 1.0) & (M.Y >= 0) & (M.Y < 0.5)
    P.fill(m, cols, cell=1)
    P.fill(m & (r > 0.78), border, cell=1)
    P.fill(m & (np.abs(r - 0.45) < 0.06), border, cell=1)


def pot_plant(P, M, x, y, z, s=1.0, flower=None):
    P.fill(cyl_y(M, (x, z), 0.85 * s, y, y + 1.2 * s), ['#B76B4D', '#A95F43'], cell=9)
    P.fill(cyl_y(M, (x, z), 0.95 * s, y + 0.95 * s, y + 1.3 * s), ['#C9805F'], cell=9)
    leaf = ball(M, (x, y + 2.1 * s, z), 1.3 * s, 0.85) & (M.m == 0)
    P.fill(leaf, LEAF, cell=0.5)
    if flower:
        for k in range(3):
            a = k * 2.1
            P.fill(ball(M, (x + 0.8 * s * math.cos(a), y + 2.6 * s, z + 0.8 * s * math.sin(a)), 0.35 * s), [flower])


def hanging_plant(P, M, x, y, z, ceil, s=1.0):
    P.fill(box(M, (x - 0.15, y + 1.0, z - 0.15), (x + 0.15, ceil, z + 0.15)), ['#B98A3E'])
    pot = ball(M, (x, y + 0.4, z), 1.1 * s, 0.7) & (M.Y < y + 0.9)
    P.fill(pot, ['#C99B5A', '#B98A4A'], cell=0.5)
    P.fill(ball(M, (x, y + 1.0, z), 1.2 * s, 0.6) & (M.m == 0), LEAF, cell=0.5)
    for k, (dx, dz, ln) in enumerate(((0.9, 0.2, 3.0), (-0.8, -0.3, 2.2), (0.1, 0.9, 2.6))):
        P.fill(box(M, (x + dx - 0.25, y - ln, z + dz - 0.25), (x + dx + 0.25, y + 0.4, z + dz + 0.25)), LEAF, cell=0.5)


def window_back(S, P, M, x0, x1, y0, y1, z, glass=CLEAR_GLASS, frame=WALNUT, arch=False, mull=(2, 2)):
    """Window cut through a back wall at depth z (wall spans z-1..z). Glass panes on mullions."""
    hole = box(M, (x0, y0, z - 1.2), (x1, y1, z + 0.2))
    if arch:
        cx, r = (x0 + x1) / 2, (x1 - x0) / 2
        top = (M.Y > y1 - r) & ((M.X - cx) ** 2 + (M.Y - (y1 - r)) ** 2 > r * r)
        hole &= ~top
    M.m[hole] = 0
    pane = hole & (M.Z >= z - 0.7) & (M.Z < z - 0.2)
    P.fill(pane, glass, cell=50)
    nx, ny = mull
    bars = np.zeros_like(pane)
    for i in range(1, nx):
        bx = x0 + (x1 - x0) * i / nx
        bars |= np.abs(M.X - bx) < 0.3
    for j in range(1, ny):
        by = y0 + (y1 - y0) * j / ny
        bars |= np.abs(M.Y - by) < 0.3
    P.fill(pane & bars, frame)
    rim = box(M, (x0 - 0.6, y0 - 0.6, z - 0.2), (x1 + 0.6, y1 + 0.6, z + 0.4)) & ~box(M, (x0, y0, z - 2), (x1, y1, z + 2))
    if arch:
        cx, r = (x0 + x1) / 2, (x1 - x0) / 2
        dd = np.sqrt((M.X - cx) ** 2 + (M.Y - (y1 - r)) ** 2)
        rim = (box(M, (x0 - 0.6, y0 - 0.6, z - 0.2), (x1 + 0.6, y1 - r, z + 0.4)) & ~box(M, (x0, y0, z - 2), (x1, y1 - r, z + 2))) | \
              ((M.Y >= y1 - r) & (dd >= r) & (dd < r + 0.6) & (M.Z >= z - 0.2) & (M.Z < z + 0.4))
    P.fill(rim, frame)
    P.fill(box(M, (x0 - 1.0, y0 - 1.0, z - 0.2), (x1 + 1.0, y0 - 0.4, z + 0.9)), frame)   # sill
    return hole


def tools_on_board(P, M, x0, x1, y0, y1, z, rng):
    board = box(M, (x0, y0, z), (x1, y1, z + 0.4))
    P.fill(board, ['#A8703F', '#9A6538'], cell=(9, 1.0, 9))
    x = x0 + 0.8
    while x < x1 - 0.8:
        kind = rng.integers(4)
        top = y1 - 0.8 - rng.uniform(0, 0.6)
        if kind == 0:      # hammer
            P.fill(box(M, (x - 0.2, top - 3.0, z + 0.4), (x + 0.2, top, z + 0.8)), HONEY)
            P.fill(box(M, (x - 0.7, top - 0.6, z + 0.4), (x + 0.7, top, z + 0.9)), IRON)
        elif kind == 1:    # pliers / tongs
            P.fill(box(M, (x - 0.5, top - 3.2, z + 0.4), (x - 0.2, top, z + 0.7)), IRON)
            P.fill(box(M, (x + 0.2, top - 3.2, z + 0.4), (x + 0.5, top, z + 0.7)), IRON)
        elif kind == 2:    # wrench ring
            ring = (np.abs(np.sqrt((M.X - x) ** 2 + (M.Y - top + 0.6) ** 2) - 0.55) < 0.25) & (M.Z >= z + 0.4) & (M.Z < z + 0.7)
            P.fill(ring, ['#A39D94'])
            P.fill(box(M, (x - 0.2, top - 3.0, z + 0.4), (x + 0.2, top - 1.1, z + 0.7)), ['#A39D94'])
        else:              # coil of copper wire
            ring = (np.abs(np.sqrt((M.X - x) ** 2 + (M.Y - top + 1.0) ** 2) - 0.75) < 0.3) & (M.Z >= z + 0.4) & (M.Z < z + 0.9)
            P.fill(ring, COPPER)
        P.fill(box(M, (x - 0.15, top, z + 0.4), (x + 0.15, top + 0.3, z + 0.7)), BRASS)
        x += rng.uniform(1.4, 1.9)


def gear(P, M, cx, cy, z, r, cols=BRASS, teeth=8, th=0.5):
    d = np.sqrt((M.X - cx) ** 2 + (M.Y - cy) ** 2)
    a = np.arctan2(M.Y - cy, M.X - cx)
    tooth = (np.cos(a * teeth) > 0.3) & (d < r + 0.45)
    g = ((d < r) | tooth) & (d > r * 0.35) & (M.Z >= z) & (M.Z < z + th)
    P.fill(g, cols, cell=9)


# ------------------------------------------------------------------ rooms ----
ROOM = dict(x0=-18.0, x1=18.0, back=-12.0, front=16.0, h=20.0, near=28.0)   # floor/ceiling run on to `near`
# Interiors are framed tall for phones: the room fills the top of the screen and the villagers stand on
# the floor in front, where the dialogue box overlaps it.
INTERIOR_W, INTERIOR_H = 1170, 1500


def interior_cam():
    # gentle depth of field, focused where the villagers stand: the busy back wall softens a touch
    return {'pos': (0.0, 11.0, 40.0), 'target': (0.0, 4.5, -6.0), 'fov': 58.0, 'focus': (0.0, 4.0, 9.0), 'fstop': 1.4}


def room_shell(P, M, floor_cols, wall_cols, side_cols=None, floor_cell=(1.5, 1, 7), wall_cell=(1, 1, 1),
               ceiling=WALNUT, beams=True):
    R = ROOM
    P.fill(box(M, (R['x0'] - 1, -1, R['back'] - 1), (R['x1'] + 1, 0, R['near'])), floor_cols, cell=floor_cell)
    # plank seams
    P.fill(box(M, (R['x0'], -0.5, R['back']), (R['x1'], 0, R['near'])) & (((M.X - R['x0']) % floor_cell[0]) < 0.3),
           ['#6E4A30'], cell=9)
    # staggered plank ends
    P.fill(box(M, (R['x0'], -0.5, R['back']), (R['x1'], 0, R['near'])) &
           (((M.Z + 3.0 * np.floor((M.X - R['x0']) / floor_cell[0])) % floor_cell[2]) < 0.3), ['#6E4A30'], cell=9)
    P.fill(box(M, (R['x0'] - 1, 0, R['back'] - 1), (R['x1'] + 1, R['h'], R['back'])), wall_cols, cell=wall_cell)
    for sx in (R['x0'] - 1, R['x1']):
        P.fill(box(M, (sx, 0, R['back']), (sx + 1, R['h'], R['front'])), side_cols or wall_cols, cell=wall_cell)
    P.fill(box(M, (R['x0'] - 1, R['h'], R['back'] - 1), (R['x1'] + 1, R['h'] + 1, R['near'])), ceiling, cell=(9, 1, 2))
    if beams:
        for bz in (-9.0, -2.0, 5.0, 12.0, 19.0, 26.0):
            P.fill(box(M, (R['x0'], R['h'] - 1.4, bz - 0.7), (R['x1'], R['h'], bz + 0.7)), WALNUT, cell=(9, 9, 9))
        for bx in (R['x0'] + 0.1, R['x1'] - 1.0):
            pass


def scene_workshop():
    """Bram's Lampwright Workshop: a wall of finished lanterns, the forge, the long workbench."""
    S = VScene('workshop', INTERIOR_W, INTERIOR_H, interior_cam(), world=((0.85, 0.82, 0.78), 0.12), samples=192)
    M = Model((-20, -2, -14), (20, 22, 29), [], res=4)
    P = CPainter(M, 61)
    rng = np.random.default_rng(61)
    R = ROOM
    room_shell(P, M, OAK, BRICK, side_cols=['#A56F47', '#B07A50', '#9E6A43'], wall_cell=(2.0, 1.0, 2.0))
    # brick courses: offset every other row, mortar lines
    back = box(M, (R['x0'], 0, R['back'] - 0.5), (R['x1'], R['h'], R['back']))
    row = np.floor(M.Y / 1.0).astype(int)
    bx = (M.X + (row % 2) * 1.0) / 2.0
    P.fill(back, BRICK, cell=(2.0, 1.0, 9), offset=(0, 0, 0))
    P.fill(back & (((M.Y % 1.0) < 0.26) | ((bx % 1.0) < 0.13)), MORTAR, cell=9)
    # side walls: vertical planks
    for sx in (R['x0'] - 0.5, R['x1']):
        side = box(M, (sx, 0, R['back']), (sx + 0.5, R['h'], R['front']))
        P.fill(side, ['#A56F47', '#B07A50', '#9E6A43', '#AA744B'], cell=(9, 30, 1.5))
        P.fill(side & (((M.Z - R['back']) % 1.5) < 0.26), ['#6E4529'], cell=9)
    # timber frame on the back wall
    for px in (-12.0, 2.5, 12.5):
        P.fill(box(M, (px - 0.7, 0, R['back'] - 0.1), (px + 0.7, R['h'], R['back'] + 0.6)), WALNUT, cell=9)
    P.fill(box(M, (R['x0'], 15.0, R['back'] - 0.1), (R['x1'], 16.2, R['back'] + 0.6)), WALNUT, cell=9)
    P.fill(box(M, (R['x0'], 0, R['back'] - 0.1), (R['x1'], 1.0, R['back'] + 0.4)), WALNUT, cell=9)

    # round window between the lantern wall and the bench: daylight in
    window_back(S, P, M, 3.6, 9.0, 8.6, 14.4, R['back'], arch=True, mull=(2, 2))
    # daylight outside the window: an emissive sky and sunny hedge that cast no shadow
    S.models.append((backdrop(-24.0, -16.0, 22.0, seed=6), (), {'shadow': False}))
    S.lights.append({'type': 'sun', 'dir': (-0.3, -0.55, 1.0), 'power': 4.0, 'color': 5500, 'angle': 3.0})
    for (px, s_) in ((4.4, 0.55), (6.2, 0.5), (7.9, 0.6)):
        pot_plant(P, M, px, 8.0, R['back'] + 0.6, s_, flower='#F4C04E' if px < 5 else None)

    # ---- the lantern wall (left): four shelves of finished lanterns, a few lit
    for i, sy in enumerate((2.6, 6.4, 10.2, 14.0)):
        shelf_board(P, M, -17.6, -12.6, sy, R['back'], R['back'] + 2.2)
        for j, lx in enumerate((-16.6, -14.9, -13.4)):
            if (i, j) in ((3, 2),):
                continue
            k = (i * 3 + j) % 5
            lit = k in (0, 2, 3)
            g = [GLASS_AMBER, GLASS_MINT, GLASS_AMBER, GLASS_ROSE, GLASS_AMBER][k]
            lantern(S, P, M, (lx, sy + 1.2, R['back'] + 1.1), s=0.55, lit=lit, glass=g, power=2.0,
                    kelvin={0: 2400, 1: 6500, 3: 3200}.get(k % 4, 2400))
    # upright of the lantern rack
    P.fill(box(M, (-12.8, 0, R['back']), (-12.2, 15.0, R['back'] + 2.4)), WALNUT, cell=9)

    # ---- the long workbench (centre back) with lanterns in progress
    table(P, M, -2.6, 9.8, R['back'] + 0.6, R['back'] + 5.2, 5.4, cols=['#9A6538', '#A8703F', '#8F5E33'])
    P.fill(box(M, (-2.2, 1.4, R['back'] + 0.8), (9.4, 1.9, R['back'] + 4.8)), OAK_DARK, cell=(1.5, 1, 9))  # lower shelf
    for (cx, cz, s) in ((0.0, -9.0, 0.8), (6.2, -9.8, 0.6)):
        crate(P, M, cx, cz + 1.0, s, y=1.9)
    # frame cages (unglazed), a lit test lantern, a lens on an arm, copper spools
    for fx in (-1.0, 1.4):
        cage = (np.maximum(np.abs(M.X - fx), np.abs(M.Z + 9.0)) <= 0.8) & (M.Y >= 5.4) & (M.Y < 7.6)
        P.fill(cage & ((np.abs(np.abs(M.X - fx) - 0.8) < 0.3) & (np.abs(np.abs(M.Z + 9.0) - 0.8) < 0.3) | (M.Y >= 7.2) | (M.Y < 5.8)), IRON)
    lantern(S, P, M, (4.0, 6.8, -9.2), s=0.75, lit=True, glass=GLASS_MINT, power=4.0, kelvin=6500)
    P.fill(box(M, (6.4, 5.4, -10.6), (6.8, 9.6, -10.2)), BRASS)          # lens arm
    P.fill(box(M, (6.4, 9.2, -10.6), (8.4, 9.6, -10.2)), BRASS)
    lens = ((M.X - 8.2) ** 2 + (M.Y - 8.0) ** 2 <= 1.1) & (M.Z >= -10.2) & (M.Z < -9.7)
    P.fill(lens, ['#BFE6F5', '#D7F0FA'])
    P.fill(lens & ((M.X - 8.2) ** 2 + (M.Y - 8.0) ** 2 > 0.6), BRASS)
    for (sx_, sz_) in ((8.8, -8.0), (9.3, -9.6)):
        P.fill(cyl_y(M, (sx_, sz_), 0.55, 5.4, 6.4), COPPER, cell=9)
    gear(P, M, -1.8, 5.6, -7.6, 0.6, teeth=6, th=0.4)
    # pegboard of tools and blueprints over the bench
    tools_on_board(P, M, -10.6, 1.6, 8.0, 13.0, R['back'], rng)
    for (x, y, ww, hh) in ((10.8, 10.4, 2.4, 3.2), (-5.0, 14.4, 3.4, 1.4)):
        sheet = box(M, (x - ww / 2, y - hh / 2, R['back']), (x + ww / 2, y + hh / 2, R['back'] + 0.3))
        P.fill(sheet, ['#E6EEF3', '#D9E4EC'], cell=9)
        P.fill(sheet & ((np.abs(M.Y - y) < 0.12) | (np.abs(M.X - x) < 0.12) | (np.abs(np.sqrt((M.X - x) ** 2 + (M.Y - y) ** 2) - 0.6) < 0.12)), ['#5A7C9A'], cell=9)
    gear(P, M, 13.6, 13.6, R['back'], 1.2, cols=COPPER, teeth=8)
    gear(P, M, 15.6, 12.2, R['back'], 0.8, cols=BRASS, teeth=6)

    # ---- the forge (right): stone body, copper hood, glowing mouth, anvil, bellows
    fx0, fx1, fz0, fz1 = 11.0, 17.8, R['back'], R['back'] + 6.0
    body = box(M, (fx0, 0, fz0), (fx1, 6.0, fz1))
    P.fill(body, STONE, cell=(1.5, 1.0, 1.5))
    P.fill(body & (((M.Y % 1.0) < 0.2)), ['#77716A'], cell=9)
    mouth = box(M, (12.6, 1.6, fz1 - 0.6), (16.4, 4.6, fz1 + 0.1))
    M.m[mouth] = 0
    P.fill(box(M, (12.6, 1.6, fz1 - 1.6), (16.4, 4.6, fz1 - 0.6)), ['#FF9A4A', '#FFB65C', '#FF8A3A'], glow=1.0, cell=0.5)
    P.fill(box(M, (12.8, 1.6, fz1 - 0.8), (16.2, 2.3, fz1)), ['#FFD46A', '#FFC24E'], glow=1.0, cell=0.5)
    S.lights.append({'type': 'area', 'pos': (14.5, 3.2, fz1 + 0.4), 'aim': (12.0, 2.0, 12.0), 'size': (4.0, 3.0), 'power': 28.0, 'color': 1900})
    S.lights.append({'type': 'point', 'pos': (14.5, 3.0, fz1 - 1.2), 'power': 3.0, 'color': 1900, 'radius': 1.2})
    hood = (M.Y >= 6.0) & (M.Y < 11.0) & (np.abs(M.X - 14.4) <= 3.6 - (M.Y - 6.0) * 0.45) & (M.Z >= fz0) & (M.Z < fz0 + 5.2 - (M.Y - 6.0) * 0.5)
    P.fill(hood, COPPER, cell=(1.0, 0.5, 9))
    P.fill(hood & (np.abs(M.Y - 6.4) < 0.4), BRASS)
    P.fill(box(M, (13.4, 11.0, fz0), (15.4, R['h'], fz0 + 2.0)), STONE, cell=(1.5, 1.0, 1.5))
    # glazed teal tiles behind the forge
    tiles = box(M, (fx0 - 1.4, 6.0, R['back'] - 0.1), (fx1, 15.0, R['back'] + 0.3)) & ~hood
    P.fill(tiles, ['#4E8C8A', '#5A9C98', '#467F7D', '#6AAAA5'], cell=(1.0, 1.0, 9))
    P.fill(tiles & ((((M.Y - 6.0) % 1.0) < 0.26) | (((M.X - fx0) % 1.0) < 0.26)), ['#E9DFC8'], cell=9)
    # anvil and a quench bucket
    anv = box(M, (7.6, 2.2, -1.6), (11.0, 3.4, 0.0)) | box(M, (8.4, 0, -1.2), (10.2, 2.2, -0.4)) | box(M, (7.8, 0, -1.6), (10.8, 0.6, 0.0))
    P.fill(anv, ['#5E5A56', '#54504C'], cell=9)
    P.fill(box(M, (6.6, 2.6, -1.2), (7.6, 3.2, -0.4)), ['#5E5A56'])
    P.fill(cyl_y(M, (12.6, 1.4), 1.0, 0, 1.8), OAK_DARK, cell=9)
    P.fill(cyl_y(M, (12.6, 1.4), 0.8, 1.4, 1.8), ['#5A7C9A'], cell=9)
    # bellows leaning on the forge
    bel = ((M.X - 10.4) ** 2 / 1.0 + (M.Y - 2.0) ** 2 / 1.6 <= 1.0) & (M.Z >= -5.4) & (M.Z < -3.6)
    P.fill(bel, ['#8D5D3B', '#7E5133'], cell=9)
    P.fill(box(M, (10.2, 3.2, -4.8), (10.6, 5.0, -4.2)), HONEY)

    # ---- floor: rag rug, crates and a barrel at the right front, sacks, a stool
    rug(P, M, 1.5, 5.5, 6.5, 4.0, ['#B76B4D', '#C27658'], ['#E8B956'])
    crate(P, M, 15.6, 9.6, 1.4)
    crate(P, M, 15.6, 9.6, 1.0, y=2.8)
    crate(P, M, 12.6, 11.8, 1.1)
    barrel(P, M, 16.0, 4.0, 1.4, 3.2)
    P.fill(ball(M, (11.4, 1.1, 7.6), 1.3, 0.85) & (M.Y >= 0), ['#D8C39A', '#CDB689'], cell=0.5)   # sand sack
    P.fill(cyl_y(M, (5.6, 1.2), 1.0, 2.0, 2.5), OAK, cell=9)                                     # stool
    for (lx, lz) in ((4.9, 0.5), (6.3, 0.5), (5.6, 1.9)):
        P.fill(cyl_y(M, (lx, lz), 0.25, 0, 2.0), WALNUT)
    # coal scuttle by the forge
    P.fill(cyl_y(M, (9.6, 3.4), 0.9, 0, 1.4), IRON, cell=9)
    P.fill(cyl_y(M, (9.6, 3.4), 0.75, 1.0, 1.5), ['#2E2A28', '#3A3532'], cell=0.5)

    # Bram's navy apron on a peg, a potted fern by the crates
    apron = box(M, (10.2, 6.0, R['back'] + 0.3), (11.6, 10.2, R['back'] + 0.7)) & ~((M.Y > 9.2) & (np.abs(M.X - 10.9) < 0.4))
    P.fill(apron, NAVY, cell=9)
    P.fill(apron & (np.abs(M.Y - 7.4) < 0.3), BRASS)
    pot_plant(P, M, 13.6, 0.0, 6.4, 1.1)
    hanging_plant(P, M, -15.0, 15.0, 6.0, R['h'] - 1.4, 1.0)
    # ---- left wall: a tall cupboard of jars and a coil of rope
    cup = box(M, (R['x0'], 0, -6.0), (R['x0'] + 2.2, 11.0, 0.0))
    P.fill(cup, WALNUT, cell=9)
    for sy in (3.0, 6.0, 9.0):
        M.m[box(M, (R['x0'] + 1.0, sy - 2.6, -5.4), (R['x0'] + 2.2, sy - 0.4, -0.6))] = 0
        for jz in (-4.6, -3.0, -1.4):
            jar(P, M, R['x0'] + 1.6, sy - 2.6, jz, h=1.2, r=0.45, cols=[GLASS_MINT, GLASS_AMBER, ['#C9E7F2']][int(abs(jz)) % 3],
                glow=None)

    # ---- ceiling: hanging lanterns (the shop's own lights), copper pipe, a drying rack of chains
    for (x, y, z, s, g, k) in ((-7.0, 14.6, -4.0, 0.9, GLASS_AMBER, 2400), (0.5, 15.8, 1.5, 0.8, GLASS_AMBER, 2400),
                               (7.0, 14.2, -5.0, 0.9, GLASS_AMBER, 2600), (12.0, 15.4, 3.0, 0.8, GLASS_ROSE, 3000),
                               (-12.5, 15.8, 4.0, 0.8, GLASS_MINT, 6500), (-3.0, 13.2, 7.0, 0.7, GLASS_AMBER, 2400)):
        lantern(S, P, M, (x, y, z), s=s, lit=True, glass=g, power=9.0, kelvin=k, hang_to=R['h'] - 1.4)
    P.fill(box(M, (R['x0'], 17.0, R['back'] + 0.4), (R['x1'], 17.6, R['back'] + 1.0)), COPPER, cell=9)
    # soft fill from the open front (the "camera side" of the diorama)
    S.lights.append({'type': 'area', 'pos': (0.0, 18.0, 22.0), 'aim': (0.0, 4.0, -6.0), 'size': (30.0, 8.0), 'power': 120.0, 'color': 5000})
    S.models.append((M, CLEAR_GLASS))
    S.grade = {'vignette': 0.22, 'warm': 0.03, 'bloom': 0.45}
    return S


def backdrop(z_sky, z_near, top, seed=3, sky=('#BFE3F2', '#E8F5F5'), hills=('#9CC97F', '#8FBE72')):
    """What you see through a window: sky panel, a far hill line, a near hedge. Emissive, no shadows."""
    B = Model((-30, -2, int(z_sky) - 2), (30, int(top) + 4, int(z_near) + 1), [], res=1)
    P = CPainter(B, seed)
    P.fill(box(B, (-30, -2, z_sky - 1), (30, top + 4, z_sky)) & (B.Y >= 7.0), [sky[0]], glow=0.85, cell=9)
    P.fill(box(B, (-30, -2, z_sky - 1), (30, top + 4, z_sky)) & (B.Y < 9.0), [sky[1]], glow=0.85, cell=9)
    hill = box(B, (-30, -2, z_sky + 1), (30, top, z_sky + 2)) & (B.Y < 9.5 + 1.8 * np.sin(B.X * 0.35 + seed))
    P.fill(hill, list(hills), glow=0.55, cell=2)
    hedge = box(B, (-30, -2, z_near - 1), (30, top, z_near)) & (B.Y < 7.5 + 1.2 * np.sin(B.X * 0.9 + seed * 2))
    P.fill(hedge, ['#7FB35F', '#6FA552', '#88BC67'], glow=0.45, cell=1)
    return B


# ------------------------------------------------------------------ Mira's Glasshouse ----
TERRACOTTA = ['#C98B6B', '#BF7F60', '#D29676', '#C4866A']
FLOWERS = ['#FFFDF6', '#F5A3B5', '#F4C04E', '#E8E0FF', '#FF9E7A']


def glass_wall_x(P, M, x0, x1, y0, y1, z0, z1, step=3.0, rows=(4.0,), frame=SAGE):
    """A wall of glass panes (between z0..z1 thickness) with frame mullions."""
    w = box(M, (x0, y0, z0), (x1, y1, z1))
    P.fill(w, CLEAR_GLASS, cell=50)
    bars = (((M.X - x0) % step) < 0.5) | (M.Y < y0 + 0.5) | (M.Y >= y1 - 0.5)
    for ry in rows:
        bars |= np.abs(M.Y - ry) < 0.25
    P.fill(w & bars, frame, cell=9)
    return w


def glass_wall_z(P, M, x0, x1, y0, y1, z0, z1, step=3.0, rows=(4.0,), frame=SAGE):
    w = box(M, (x0, y0, z0), (x1, y1, z1))
    P.fill(w, CLEAR_GLASS, cell=50)
    bars = (((M.Z - z0) % step) < 0.5) | (M.Y < y0 + 0.5) | (M.Y >= y1 - 0.5)
    for ry in rows:
        bars |= np.abs(M.Y - ry) < 0.25
    P.fill(w & bars, frame, cell=9)
    return w


def surround(z_back, x_side, top, seed=4, sky=('#BFE3F2', '#E8F5F5')):
    """Daylight outside a glass room: sky panels behind and to both sides, hills and hedges."""
    B = Model((-int(x_side) - 3, -2, int(z_back) - 2), (int(x_side) + 3, int(top) + 4, 26), [], res=1)
    P = CPainter(B, seed)
    sx = x_side
    panels = box(B, (-sx - 3, -2, z_back - 1), (sx + 3, top + 4, z_back)) | \
        box(B, (-sx - 3, -2, z_back), (-sx - 2, top + 4, 26)) | box(B, (sx + 2, -2, z_back), (sx + 3, top + 4, 26))
    P.fill(panels & (B.Y >= 8.0), [sky[0]], glow=0.9, cell=9)
    P.fill(panels & (B.Y < 10.0), [sky[1]], glow=0.9, cell=9)
    hills = (box(B, (-sx - 3, -2, z_back), (sx + 3, top, z_back + 1)) & (B.Y < 9.0 + 2.0 * np.sin(B.X * 0.3 + seed))) | \
        (box(B, (-sx - 2, -2, z_back), (-sx - 1, top, 26)) & (B.Y < 9.0 + 2.0 * np.sin(B.Z * 0.3))) | \
        (box(B, (sx + 1, -2, z_back), (sx + 2, top, 26)) & (B.Y < 9.0 + 2.0 * np.sin(B.Z * 0.3 + 1)))
    P.fill(hills, ['#9CC97F', '#8FBE72', '#A6D18A'], glow=0.5, cell=2)
    hedge = (box(B, (-sx - 3, -2, z_back + 3), (sx + 3, top, z_back + 4)) & (B.Y < 6.0 + 1.5 * np.sin(B.X * 0.8 + seed))) | \
        (box(B, (-sx + 1.5, -2, z_back), (-sx + 2.5, top, 26)) & (B.Y < 6.0 + 1.5 * np.sin(B.Z * 0.8))) | \
        (box(B, (sx - 2.5, -2, z_back), (sx - 1.5, top, 26)) & (B.Y < 6.0 + 1.5 * np.sin(B.Z * 0.8 + 2)))
    P.fill(hedge, ['#7FB35F', '#6FA552', '#88BC67'], glow=0.42, cell=1)
    return B


def flower_pot(P, M, x, y, z, s, col, rng, kind=None):
    kind = kind if kind is not None else rng.integers(3)
    P.fill(cyl_y(M, (x, z), 0.7 * s, y, y + 1.0 * s), TERRACOTTA, cell=9)
    P.fill(cyl_y(M, (x, z), 0.82 * s, y + 0.8 * s, y + 1.1 * s), ['#D9A07E'], cell=9)
    if kind == 0:     # round bush with blooms
        P.fill(ball(M, (x, y + 1.8 * s, z), 1.0 * s, 0.8) & (M.m == 0), LEAF, cell=0.5)
        for k in range(5):
            a = k * 1.3 + x
            P.fill(ball(M, (x + 0.75 * s * math.cos(a), y + 2.1 * s + 0.2 * math.sin(a * 3), z + 0.75 * s * math.sin(a)), 0.3 * s), [col])
    elif kind == 1:   # upright leaves
        for k, (dx, dz, hh) in enumerate(((0, 0, 2.6), (0.5, 0.2, 2.0), (-0.4, 0.3, 2.2), (0.1, -0.5, 1.8))):
            P.fill(box(M, (x + dx * s - 0.22, y + 1.0 * s, z + dz * s - 0.22), (x + dx * s + 0.22, y + hh * s, z + dz * s + 0.22)), LEAF, cell=0.5)
        P.fill(ball(M, (x, y + 2.7 * s, z), 0.35 * s), [col])
    else:             # trailing succulent
        P.fill(ball(M, (x, y + 1.3 * s, z), 0.9 * s, 0.5) & (M.m == 0), ['#8FC7A0', '#7DB892', '#A2D3B0'], cell=0.5)


def scene_glasshouse():
    """Mira's Glasshouse: sunlight through a glass roof, tiers of pots, vines, the Lumenbud bench."""
    S = VScene('glasshouse', INTERIOR_W, INTERIOR_H, interior_cam(), world=((0.75, 0.88, 1.0), 0.45), samples=160)
    M = Model((-20, -2, -14), (20, 24, 29), [], res=4)
    P = CPainter(M, 51)
    rng = np.random.default_rng(51)
    R = ROOM
    # terracotta tile floor with grout and a pale stone aisle
    fl = box(M, (R['x0'] - 1, -1, R['back'] - 1), (R['x1'] + 1, 0, R['near']))
    P.fill(fl, TERRACOTTA, cell=(2.0, 1, 2.0))
    P.fill(fl & ((((M.X - R['x0']) % 2.0) < 0.26) | (((M.Z - R['back']) % 2.0) < 0.26)), ['#E6D5BF'], cell=9)
    for k, zz in enumerate(np.arange(R['back'] + 3.0, R['near'], 2.6)):
        xx = 1.0 + 0.15 * (zz - 2) + 0.6 * math.sin(k * 1.9)
        st_ = ((M.X - xx) ** 2 / 2.4 + (M.Z - zz) ** 2 / 1.0 <= 1.0) & (M.Y >= -0.5) & (M.Y < 0.25)
        P.fill(st_, ['#B5A68C', '#AA9A80', '#BDAF96'], cell=(1.0, 1, 1.0))
    # low stone base walls and glass walls on sage frames
    P.fill(box(M, (R['x0'] - 1, 0, R['back'] - 1), (R['x1'] + 1, 2.5, R['back'])), STONE_LT, cell=(1.5, 0.75, 9))
    for sx in (R['x0'] - 1, R['x1']):
        P.fill(box(M, (sx, 0, R['back']), (sx + 1, 2.5, R['front'])), STONE_LT, cell=(9, 0.75, 1.5))
    glass_wall_x(P, M, R['x0'] - 1, R['x1'] + 1, 2.5, 17.0, R['back'] - 1, R['back'], step=3.0, rows=(7.5, 12.5))
    for sx in (R['x0'] - 1, R['x1']):
        glass_wall_z(P, M, sx, sx + 1, 2.5, 17.0, R['back'], R['front'], step=3.0, rows=(7.5, 12.5))
    # pitched glass roof, ridge along z
    ridge_y, eave_y = 22.0, 17.0
    slope = (ridge_y - eave_y) / R['x1']
    roof_y = ridge_y - np.abs(M.X) * slope
    roof = (M.Y >= roof_y) & (M.Y < roof_y + 0.8) & (np.abs(M.X) <= R['x1'] + 1) & (M.Z >= R['back'] - 1) & (M.Z < R['near'])
    P.fill(roof, CLEAR_GLASS, cell=50)
    P.fill(roof & ((((M.Z - R['back']) % 4.0) < 0.6) | (((np.abs(M.X)) % 4.5) < 0.6) | (np.abs(M.X) < 0.6)), SAGE, cell=9)
    P.fill(box(M, (R['x0'] - 1, eave_y - 0.6, R['back'] - 1), (R['x1'] + 1, eave_y, R['near'])) & (np.abs(M.X) > R['x1'] - 0.5), ['#43523D'])
    S.models.append((surround(-26.0, 22.0, 24.0, seed=5), (), {'shadow': False}))
    S.lights.append({'type': 'sun', 'dir': (0.5, -0.8, 0.45), 'power': 2.7, 'color': 5500, 'angle': 2.5})
    S.lights.append({'type': 'area', 'pos': (0.0, 18.0, 22.0), 'aim': (0.0, 4.0, -6.0), 'size': (30.0, 8.0), 'power': 90.0, 'color': 6500})

    # ---- tiered plant stand (back left): three steps of pots
    for i, (ty, tz) in enumerate(((2.2, -10.4), (4.4, -11.4), (6.6, -12.0))):
        P.fill(box(M, (-17.0, ty - 0.5, tz - 0.6), (-6.0, ty, tz + 1.2)), OAK, cell=(1.5, 1, 9))
        for j, px in enumerate(np.arange(-16.2, -6.5, 1.75)):
            flower_pot(P, M, px, ty, tz + 0.3, 0.62, FLOWERS[(i + j) % len(FLOWERS)], rng)
    for lx in (-16.8, -6.6):
        P.fill(box(M, (lx, 0, -11.9), (lx + 0.5, 6.6, -9.0)), OAK_DARK, cell=9)

    # ---- potting bench (back right) with seedling trays and the Lumenbud
    table(P, M, 3.0, 14.5, R['back'] + 0.4, R['back'] + 4.6, 5.0, cols=['#C69469', '#B9875C', '#D2A176'])
    P.fill(box(M, (3.4, 1.2, R['back'] + 0.6), (14.1, 1.7, R['back'] + 4.2)), OAK_DARK, cell=(1.5, 1, 9))
    for (tx, tz) in ((4.6, -9.4), (7.6, -9.6)):
        tray = box(M, (tx - 1.3, 5.0, tz - 1.0), (tx + 1.3, 5.6, tz + 1.0))
        P.fill(tray, ['#8D5D3B'], cell=9)
        P.fill(tray & (M.Y >= 5.4), ['#5B4334', '#4F3A2D'], cell=0.5)
        for sx_ in np.arange(tx - 0.9, tx + 1.0, 0.6):
            for sz_ in (tz - 0.5, tz + 0.3):
                P.fill(box(M, (sx_ - 0.12, 5.6, sz_ - 0.12), (sx_ + 0.12, 6.2, sz_ + 0.12)), ['#86C56A'])
                P.fill(box(M, (sx_ - 0.25, 6.1, sz_ - 0.12), (sx_ + 0.25, 6.3, sz_ + 0.12)), ['#9CD47E'])
    # the Lumenbud: three golden buds on a dark-sage stem, glowing softly under a bell jar
    lb = (11.6, 5.0, -9.4)
    P.fill(cyl_y(M, (lb[0], lb[2]), 0.9, 5.0, 5.6), TERRACOTTA, cell=9)
    P.fill(box(M, (lb[0] - 0.15, 5.6, lb[2] - 0.15), (lb[0] + 0.15, 8.0, lb[2] + 0.15)), ['#4C6B45'])
    for (dx, dy) in ((-0.5, 7.2), (0.5, 7.6), (0.0, 8.2)):
        P.fill(ball(M, (lb[0] + dx, dy, lb[2]), 0.32), GLASS_AMBER, glow=1.0)
    jar_ = cyl_y(M, (lb[0], lb[2]), 1.2, 5.6, 9.0) & ~cyl_y(M, (lb[0], lb[2]), 0.95, 5.6, 8.8) | (ball(M, (lb[0], 9.0, lb[2]), 1.2, 0.5) & (M.Y >= 9.0) & ~ball(M, (lb[0], 9.0, lb[2]), 0.95, 0.4))
    P.fill(jar_ & (M.m == 0), ['#E2F5F8'], cell=50)
    S.lights.append({'type': 'point', 'pos': (lb[0], 7.6, lb[2] + 0.4), 'power': 2.5, 'color': 2700, 'radius': 0.4})
    # watering can, trowel, seed packets
    can = cyl_y(M, (13.6, -8.6), 0.8, 5.0, 6.6)
    P.fill(can, COPPER, cell=9)
    P.fill(box(M, (12.0, 5.8, -8.8), (12.9, 6.2, -8.4)), COPPER)
    for k, px in enumerate((5.2, 6.4, 9.4)):
        P.fill(box(M, (px, 5.0, -8.0), (px + 0.9, 5.2, -7.0)), [['#F5A3B5'], ['#F4C04E'], ['#9CD47E']][k], cell=9)

    # ---- vines up the back frames, hanging baskets from the roof
    for vx in (-16.5, -4.5, 1.5, 16.0):
        vine = (np.abs(M.X - vx - 0.7 * np.sin(M.Y * 0.8 + vx)) < 0.35) & (M.Z >= R['back'] - 0.2) & (M.Z < R['back'] + 0.4) & (M.Y > 2.5) & (M.Y < 16.5)
        P.fill(vine, ['#5EA046', '#4F9C3E'], cell=0.5)
        for ly in np.arange(3.5, 16.0, 1.5):
            lf = (np.abs(M.X - vx - 0.7 * np.sin(ly * 0.8 + vx) - 0.6) < 0.5) & (np.abs(M.Y - ly) < 0.35) & (M.Z >= R['back'] - 0.2) & (M.Z < R['back'] + 0.6)
            P.fill(lf & (M.m == 0) | lf & np.isin(M.m, [M.mid(c) for c in CLEAR_GLASS]), ['#86C56A', '#6FB24E'], cell=0.5)
    for (hx, hy, hz) in ((-9.0, 13.0, -2.0), (0.0, 14.5, 3.0), (9.0, 13.0, -1.0)):
        hanging_plant(P, M, hx, hy, hz, ridge_y - abs(hx) * slope, 1.0)
        for k in range(3):
            P.fill(ball(M, (hx + math.cos(k * 2.1) * 1.0, hy + 1.3, hz + math.sin(k * 2.1) * 1.0), 0.3), [FLOWERS[k + 1]])

    # ---- big plants and the rain barrel
    for (x, z, s_, kind) in ((15.2, 8.8, 1.7, 1), (-17.0, 2.0, 1.5, 0), (16.6, 1.0, 1.2, 0), (-16.2, 11.0, 1.3, 1)):
        flower_pot(P, M, x, 0.0, z, s_, FLOWERS[int(abs(x)) % 5], rng, kind)
    barrel(P, M, 12.2, 3.0, 1.5, 3.0)
    P.fill(cyl_y(M, (12.2, 3.0), 1.3, 2.6, 2.9), ['#7FB8CF', '#8EC4D9'], cell=0.5)
    # seed sacks and stacked pots
    P.fill(ball(M, (8.6, 1.1, 9.4), 1.3, 0.85) & (M.Y >= 0), ['#D8C39A', '#CDB689'], cell=0.5)
    for k in range(4):
        P.fill(cyl_y(M, (10.8, 10.8), 0.8 - 0.05 * k, 0.6 * k, 0.6 * k + 0.6), TERRACOTTA, cell=9)
    # a little stone path of moss tufts along the aisle
    for _ in range(8):
        mx, mz = rng.uniform(-14, 14), rng.uniform(-6, 13)
        if abs(mx - 1.0 - 0.15 * (mz - 2)) < 3.0:
            continue
        P.fill(ball(M, (mx, 0.1, mz), 0.45, 0.5) & (M.Y >= 0), ['#8FBE72', '#7FB35F'], cell=0.5)
    # raised bed of tall flowers between the stand and the bench
    bed = box(M, (-5.4, 0, R['back']), (2.6, 2.2, R['back'] + 2.6))
    P.fill(bed, OAK_DARK, cell=(1.5, 0.75, 9))
    P.fill(bed & (M.Y >= 1.8), ['#5B4334', '#4F3A2D'], cell=0.5)
    for k, fx_ in enumerate(np.arange(-4.8, 2.4, 1.1)):
        hh = 4.0 + 1.6 * math.sin(k * 1.7) + 1.0
        P.fill(box(M, (fx_ - 0.2, 2.2, -10.8 - 0.2), (fx_ + 0.2, 2.2 + hh, -10.8 + 0.2)), ['#5EA046'])
        P.fill(ball(M, (fx_, 2.2 + hh * 0.45, -10.8), 0.9, 0.45), ['#86C56A', '#6FB24E'], cell=0.5)
        head = ball(M, (fx_, 2.2 + hh + 0.3, -10.5), 0.9, 0.55)
        P.fill(head, ['#F4C04E', '#FFFDF6', '#F5A3B5', '#E8E0FF'][k % 4], cell=0.5)
        P.fill(head & ball(M, (fx_, 2.2 + hh + 0.3, -10.3), 0.25), ['#8D5D3B'] if k % 4 == 0 else ['#F4C04E'])
    # planter along the left wall, pot shelves on the right wall
    lp = box(M, (R['x0'], 0, -10.0), (R['x0'] + 2.4, 1.8, 6.0))
    P.fill(lp, OAK, cell=(9, 0.6, 1.5))
    for fz in np.arange(-9.2, 5.6, 1.4):
        flower_pot(P, M, R['x0'] + 1.2, 1.2, fz, 0.6, FLOWERS[int(fz * 3) % 5], rng, kind=0)
    for sy in (4.4, 8.0):
        P.fill(box(M, (R['x1'] - 2.2, sy - 0.5, -9.0), (R['x1'], sy, 3.0)), OAK_DARK, cell=(9, 1, 1.5))
        for fz in np.arange(-8.2, 2.6, 1.5):
            flower_pot(P, M, R['x1'] - 1.1, sy, fz, 0.55, FLOWERS[int(fz * 7 + sy) % 5], rng)
    for (x, z, s_, kind) in ((9.8, 11.6, 1.1, 0), (13.6, 12.6, 0.9, 2), (4.6, 12.8, 0.8, 0)):
        flower_pot(P, M, x, 0.0, z, s_, FLOWERS[int(x) % 5], rng, kind)
    # stone birdbath with water, a dragonfly of light
    P.fill(cyl_y(M, (6.4, 5.6), 1.0, 0, 0.5) | cyl_y(M, (6.4, 5.6), 0.5, 0.5, 2.6), STONE_LT, cell=0.75)
    bowl = cyl_y(M, (6.4, 5.6), 2.0, 2.6, 3.4) & ~cyl_y(M, (6.4, 5.6), 1.5, 3.0, 3.4)
    P.fill(bowl, STONE_LT, cell=0.75)
    P.fill(cyl_y(M, (6.4, 5.6), 1.5, 3.0, 3.2), ['#7FB8CF', '#8EC4D9'], cell=0.5)
    # butterflies
    for (bx, by, bz, col) in ((-2.0, 9.0, 2.0, '#F4C04E'), (5.0, 11.0, -3.0, '#F5A3B5')):
        P.fill(box(M, (bx - 0.6, by, bz - 0.1), (bx - 0.1, by + 0.5, bz + 0.1)) | box(M, (bx + 0.1, by, bz - 0.1), (bx + 0.6, by + 0.5, bz + 0.1)), [col])
    S.models.append((M, CLEAR_GLASS + ['#E2F5F8'], {'water': ['#7FB8CF', '#8EC4D9']}))
    S.grade = {'vignette': 0.18, 'warm': 0.02, 'bloom': 0.3}
    return S


# ------------------------------------------------------------------ Trail Guild Lodge ----
def letter(P, M, x, y, z, w=0.9, h=0.6, col=PARCH, seal='#D85F51', face='z'):
    if face == 'z':
        e = box(M, (x - w / 2, y - h / 2, z), (x + w / 2, y + h / 2, z + 0.25))
        sl = box(M, (x - 0.15, y - 0.15, z + 0.25), (x + 0.15, y + 0.15, z + 0.4))
    else:
        e = box(M, (x - 0.25, y - h / 2, z - w / 2), (x, y + h / 2, z + w / 2))
        sl = box(M, (x, y - 0.15, z - 0.15), (x + 0.15, y + 0.15, z + 0.15))
    P.fill(e, col, cell=9)
    if seal:
        P.fill(sl, [seal])


def parcel(P, M, x, y, z, sx, sy, sz, col=['#C9A26E', '#BF976A'], string='#8D5D3B'):
    b = box(M, (x - sx, y, z - sz), (x + sx, y + 2 * sy, z + sz))
    P.fill(b, col, cell=9)
    P.fill(b & ((np.abs(M.X - x) < 0.15) | (np.abs(M.Z - z) < 0.15)), [string])


def scene_lodge():
    """The Trail Guild Lodge: Pip's courier counter (left), Alder's map desk (right), the trail map."""
    S = VScene('lodge', INTERIOR_W, INTERIOR_H, interior_cam(), world=((0.88, 0.84, 0.78), 0.14), samples=160)
    M = Model((-20, -2, -14), (20, 22, 29), [], res=4)
    P = CPainter(M, 71)
    rng = np.random.default_rng(71)
    R = ROOM
    room_shell(P, M, ['#B98955', '#AD7E4C', '#C4925E'], PLASTER, wall_cell=(3.0, 3.0, 3.0))
    # plaster with a timber frame (posts, rails and braces) on back and sides
    back = box(M, (R['x0'], 0, R['back'] - 0.4), (R['x1'], R['h'], R['back'] + 0.4))
    frame = back & ((np.abs(((M.X - R['x0']) % 9.0) - 0.0) < 0.7) | (np.abs(M.Y - 7.0) < 0.6) | (np.abs(M.Y - 14.0) < 0.6) | (M.Y < 1.0))
    P.fill(frame, WALNUT, cell=9)
    for bx0 in (R['x0'], R['x0'] + 27.0):
        brace = back & (np.abs((M.Y - 7.0) - (M.X - bx0) * 0.78) < 0.55) & (M.X >= bx0) & (M.X < bx0 + 9.0) & (M.Y >= 7.0) & (M.Y < 14.0)
        P.fill(brace, WALNUT, cell=9)
    for sx in (R['x0'] - 0.4, R['x1']):
        side = box(M, (sx, 0, R['back']), (sx + 0.4, R['h'], R['front']))
        P.fill(side & ((((M.Z - R['back']) % 8.0) < 1.2) | (np.abs(M.Y - 7.0) < 0.6) | (np.abs(M.Y - 14.0) < 0.6)), WALNUT, cell=9)

    # ---- the great trail map on the back wall, with the compass emblem above
    mx0, mx1, my0, my1 = -4.6, 5.6, 7.8, 13.4
    mp = box(M, (mx0, my0, R['back'] + 0.4), (mx1, my1, R['back'] + 0.7))
    P.fill(mp, ['#F1E2C2', '#EAD8B4', '#F5E9CF'], cell=1.5)
    P.fill(box(M, (mx0 - 0.5, my0 - 0.5, R['back'] + 0.3), (mx1 + 0.5, my1 + 0.5, R['back'] + 0.6)) & ~mp, OAK_DARK, cell=9)
    ridge = mp & (M.Y > my0 + 3.6 + 0.9 * np.sin(M.X * 0.8)) & (M.Y < my0 + 4.2 + 0.9 * np.sin(M.X * 0.8))
    P.fill(ridge, ['#9CB487'], cell=9)
    river = mp & (np.abs(M.Y - (my0 + 1.6) - 0.7 * np.sin(M.X * 0.6 + 1.0)) < 0.25)
    P.fill(river, ['#6FA6C4'], cell=9)
    trail = mp & (np.abs(M.Y - (my0 + 2.6) - 1.4 * np.sin(M.X * 0.45)) < 0.15) & (((M.X * 2).astype(int) % 2) == 0)
    P.fill(trail, ['#B76B4D'], cell=9)
    for (tx, ty) in ((-3.0, my0 + 4.8), (-1.6, my0 + 4.5), (3.6, my0 + 4.9), (4.4, my0 + 4.6)):
        P.fill(mp & (np.abs(M.X - tx) < 0.35 - (M.Y - ty) * 0.3) & (M.Y >= ty) & (M.Y < ty + 1.1), ['#5E9646'], cell=9)
    P.fill(mp & ((M.X - 3.2) ** 2 + (M.Y - (my0 + 2.0)) ** 2 < 0.2), ['#D85F51'])
    comp = (np.sqrt(M.X ** 2 + (M.Y - 16.3) ** 2) <= 1.4) & (M.Z >= R['back'] + 0.3) & (M.Z < R['back'] + 0.8)
    P.fill(comp, COPPER, cell=9)
    P.fill(comp & ((np.abs(M.X) < 0.22) | (np.abs(M.Y - 16.3) < 0.22)), BRASS)
    P.fill(comp & (np.sqrt(M.X ** 2 + (M.Y - 16.3) ** 2) < 0.4), NAVY)
    # navy Guild banners either side of the map
    for fx in (-8.0, 9.0):
        flag = (np.abs(M.X - fx) <= 1.7) & (M.Y >= 6.0) & (M.Y < 13.6) & (M.Z >= R['back'] + 0.4) & (M.Z < R['back'] + 0.8)
        flag &= ~((M.Y < 7.4) & (np.abs(M.X - fx) < 1.7 - (M.Y - 6.0) * 1.2))
        P.fill(flag, NAVY, cell=9)
        P.fill(flag & (np.abs(np.abs(M.X - fx) - 1.45) < 0.25), BRASS)
        wing = flag & (np.abs(M.Y - 10.4 - np.abs(M.X - fx) * 0.55) < 0.35) & (np.abs(M.X - fx) < 1.2)
        P.fill(wing, CREAM)
        P.fill(flag & (np.abs(M.Y - 9.6) < 0.3) & (np.abs(M.X - fx) < 0.3), CREAM)
        P.fill(box(M, (fx - 2.1, 13.6, R['back'] + 0.4), (fx + 2.1, 14.0, R['back'] + 1.0)), WALNUT)
        P.fill(ball(M, (fx - 2.1, 13.8, R['back'] + 0.7), 0.3) | ball(M, (fx + 2.1, 13.8, R['back'] + 0.7), 0.3), BRASS)
    # window on the right wall section: daylight in
    window_back(S, P, M, 12.0, 16.4, 8.0, 13.2, R['back'], mull=(2, 2))
    S.models.append((backdrop(-24.0, -16.0, 22.0, seed=8), (), {'shadow': False}))
    S.lights.append({'type': 'sun', 'dir': (-0.25, -0.5, 1.0), 'power': 3.5, 'color': 5500, 'angle': 3.0})

    # ---- Pip's courier counter (left): pigeonholes full of letters, parcels, the bell
    ph = box(M, (-17.6, 3.2, R['back'] + 0.4), (-10.4, 12.6, R['back'] + 2.4))
    P.fill(ph, OAK_DARK, cell=9)
    holes = ph & (((M.X + 17.6) % 1.2) > 0.3) & (((M.Y - 3.2) % 1.55) > 0.35) & (M.Z > R['back'] + 1.0)
    M.m[holes] = 0
    for i in range(6):
        for j in range(6):
            if rng.random() < 0.62:
                cx = -17.6 + 0.3 + j * 1.2 + 0.45
                cy = 3.2 + 0.35 + i * 1.55 + 0.35
                col = [PARCH, ['#E6EEF3'], ['#F5D6A8'], ['#E8D9F2']][rng.integers(4)]
                letter(P, M, cx, cy, R['back'] + 1.6, w=0.7, h=0.5, col=col, seal=['#D85F51', '#203B50', None][rng.integers(3)])
    counter = box(M, (-17.8, 0, -4.6), (-7.6, 4.4, -2.0))
    P.fill(counter, ['#A8703F', '#9A6538'], cell=(1.5, 0.75, 9))
    P.fill(counter & (M.Y >= 3.9), ['#C98C57', '#BF8350'], cell=(2.0, 1, 9))
    P.fill(counter & (M.Z >= -2.4) & (((M.X + 17.8) % 2.5) < 0.4), OAK_DARK, cell=9)
    bell = ball(M, (-8.8, 4.8, -3.4), 0.5, 0.9) & (M.Y >= 4.4)
    P.fill(bell, BRASS)
    P.fill(box(M, (-8.9, 5.2, -3.5), (-8.7, 5.6, -3.3)), BRASS)
    for (lx, lz, rot) in ((-15.6, -3.4, 0), (-14.0, -3.0, 1), (-12.4, -3.6, 0)):
        letter(P, M, lx, 4.5, lz, w=1.0, h=0.7, col=PARCH if rot else ['#E6EEF3'])
    P.fill(box(M, (-16.2, 4.4, -4.2), (-14.8, 4.6, -2.6)) , ['#F1E6CF'], cell=9)
    parcel(P, M, -15.8, 0.0, 1.6, 1.3, 0.8, 1.0)
    parcel(P, M, -15.6, 1.6, 1.6, 0.9, 0.6, 0.8, col=['#D9B98A'])
    parcel(P, M, -12.4, 0.0, 2.8, 1.0, 0.7, 0.9, col=['#B99368'])
    # Pip's postbag on a peg
    bag = ball(M, (-17.0, 6.0, 4.0), 1.2, 1.1) & (M.X < -16.0)
    P.fill(bag, ['#8D5D3B', '#7E5133'], cell=9)
    P.fill(bag & (np.abs(M.Y - 6.4) < 0.25), BRASS)

    # ---- Alder's map desk (right): rolled maps, globe, telescope, bookshelf
    table(P, M, 4.0, 13.6, -6.6, -2.0, 4.4, cols=['#9A6538', '#A8703F'])
    sheet = box(M, (5.0, 4.4, -6.0), (11.6, 4.6, -2.6))
    P.fill(sheet, ['#F1E2C2', '#EAD8B4'], cell=1.5)
    P.fill(sheet & (np.abs(M.Z + 4.2 - 0.8 * np.sin(M.X * 1.3)) < 0.2), ['#9CB487'], cell=9)
    P.fill(sheet & (np.abs(M.X - 8.0 - 0.6 * np.sin(M.Z * 1.6)) < 0.18), ['#6FA6C4'], cell=9)
    for (sx_, sz_) in ((12.6, -5.6), (12.0, -3.2)):
        P.fill(((((M.Y - 4.9) ** 2 + (M.Z - sz_) ** 2) <= 0.25) & (np.abs(M.X - sx_) < 1.4)), PARCH, cell=9)
    globe = ball(M, (6.2, 6.0, -5.4), 1.1)
    P.fill(globe, ['#6FA6C4', '#5F96B4'], cell=0.75)
    P.fill(globe & (np.sin(M.X * 2.4) + np.cos(M.Y * 2.0 + M.Z) > 0.9), ['#8FBE72', '#7FB35F'], cell=0.5)
    P.fill(box(M, (6.0, 4.4, -5.6), (6.4, 4.9, -5.2)), BRASS)
    ring = (np.abs(np.sqrt((M.X - 6.2) ** 2 + (M.Y - 6.0) ** 2) - 1.35) < 0.15) & (np.abs(M.Z + 5.4) < 0.15)
    P.fill(ring, BRASS)
    tele = (np.abs((M.Y - 5.0) - (M.X - 9.0) * 0.45) < 0.32) & (M.X >= 9.0) & (M.X < 12.0) & (np.abs(M.Z + 5.0) < 0.32)
    P.fill(tele, BRASS, cell=9)
    P.fill(tele & (M.X < 9.6), COPPER)
    # bookshelf against the right wall
    bs = box(M, (14.6, 0, -11.6), (17.8, 12.0, -6.4))
    P.fill(bs, WALNUT, cell=9)
    for sy in (0.6, 3.4, 6.2, 9.0):
        M.m[box(M, (14.6, sy, -11.0), (17.2, sy + 2.5, -7.0))] = 0
        P.fill(box(M, (14.6, sy - 0.1, -11.0), (17.2, sy, -7.0)), OAK_DARK, cell=9)
        zz = -11.0
        while zz < -7.4:
            wdt = rng.choice([0.5, 0.75])
            hh = rng.uniform(1.4, 2.3)
            P.fill(box(M, (15.2, sy, zz), (17.0, sy + hh, min(zz + wdt, -7.0))),
                   [['#B76B4D', '#203B50', '#7F9871', '#E8B956', '#8D5D3B', '#5A7C9A'][rng.integers(6)]], cell=9)
            zz += wdt
    # barrel of rolled maps
    barrel(P, M, 14.8, 2.4, 1.2, 2.6)
    for k in range(5):
        a = k * 1.25
        P.fill(cyl_y(M, (14.8 + 0.6 * math.cos(a), 2.4 + 0.6 * math.sin(a)), 0.32, 1.0, 4.4 + 0.3 * (k % 2)), PARCH, cell=9)
    # travel cloak and hat on wall pegs beside the window
    for (cx, col) in ((10.6, ['#4E8C8A', '#467F7D']),):
        P.fill(box(M, (cx - 0.2, 10.6, R['back'] + 0.4), (cx + 0.2, 11.0, R['back'] + 1.2)), BRASS)
        cloak = box(M, (cx - 0.9, 5.2, R['back'] + 0.6), (cx + 0.9, 10.8, R['back'] + 1.3)) & ~((M.Y < 6.0) & (np.abs(M.X - cx) < 0.3))
        P.fill(cloak, col, cell=(9, 0.5, 9))
    P.fill(cyl_y(M, (10.6, R['back'] + 1.4), 1.0, 11.0, 11.3) | cyl_y(M, (10.6, R['back'] + 1.4), 0.55, 11.3, 12.1), ['#8D5D3B'], cell=9)

    # ---- floor: navy rug with a compass rose, a bench, lanterns
    rug(P, M, 0.5, 4.5, 7.0, 4.2, ['#203B50', '#284A63'], ['#E8B956'])
    star = (M.Y >= 0) & (M.Y < 0.6) & ((np.abs(M.X - 0.5) < 0.35) & (np.abs(M.Z - 4.5) < 3.0) | (np.abs(M.Z - 4.5) < 0.35) & (np.abs(M.X - 0.5) < 4.6))
    P.fill(star, CREAM)
    for (x, y, z, s_, k) in ((-9.0, 14.8, -3.0, 0.9, 2400), (0.5, 15.6, 2.0, 0.9, 2400), (10.0, 14.6, -2.0, 0.9, 2600),
                             (-14.0, 15.4, 6.0, 0.8, 2400), (14.0, 15.2, 7.0, 0.8, 2700)):
        lantern(S, P, M, (x, y, z), s=s_, lit=True, power=8.0, kelvin=k, hang_to=R['h'] - 1.4)
    hanging_plant(P, M, -3.5, 15.4, -6.0, R['h'] - 1.4, 0.8)
    pot_plant(P, M, -6.2, 0.0, -9.6, 1.0)
    pot_plant(P, M, 3.4, 0.0, -10.2, 0.8, flower='#F4C04E')
    S.lights.append({'type': 'area', 'pos': (0.0, 18.0, 22.0), 'aim': (0.0, 4.0, -6.0), 'size': (30.0, 8.0), 'power': 85.0, 'color': 5000})
    S.models.append((M, CLEAR_GLASS))
    S.grade = {'vignette': 0.2, 'warm': 0.03, 'bloom': 0.4}
    return S


# ------------------------------------------------------------------ outdoors ----
GRASS = ['#86B566', '#7FAE5F', '#8DBD6C', '#79A85A']
PATHC = ['#E6D5B4', '#DCC9A4', '#EBDCBE', '#D6C39C']
COBBLE = ['#BDB4A0', '#B0A792', '#C6BEAA', '#A59C87']
ROOF = ['#B76B4D', '#A95F43', '#C27658']
SLATE = ['#5E7286', '#546779', '#687D92']
MOSSROOF = ['#7F9871', '#76906A', '#8AA37C']
TREE_LEAVES = ['#6FA552', '#7FB35F', '#5E9646', '#88BC67']
WATERC = ['#6FB7D4', '#62AACA', '#7CC2DE']
WIN_DAY = ['#A9C9D6', '#9DBFCD']
WIN_LIT = ['#FFD46A', '#FFC24E']
MINT = ['#9FE3CF', '#BDF2E2']
STATE_LIGHT = {
    'day': dict(sun=dict(dir=(0.42, -0.78, -0.48), power=2.7, color=5500, angle=5.0), world=((0.72, 0.84, 0.97), 0.62),
                sky=('#9CCBD6', '#E2F1EE')),
    'golden': dict(sun=dict(dir=(0.78, -0.42, -0.46), power=3.4, color=3200, angle=3.0), world=((0.98, 0.8, 0.64), 0.5),
                   sky=('#8FB8D8', '#F7D7A8')),
    'dusk': dict(sun=dict(dir=(-0.82, -0.18, -0.42), power=1.1, color=2400, angle=3.0), world=((0.36, 0.4, 0.66), 0.75),
                 sky=('#4B5D8C', '#F2B98A')),
}


def tree2(P, M, x, z, h=6.0, r=4.0, y=0.0, leaves=TREE_LEAVES, fruit=None, rng=None):
    rng = rng or np.random.default_rng(int(abs(x * 31 + z * 7)))
    P.fill(box(M, (x - 0.75, y, z - 0.75), (x + 0.75, y + h, z + 0.75)), ['#7A4E2E', '#8A5A34'], cell=(9, 1, 9))
    can = np.zeros(M.m.shape, bool)
    for _ in range(6):
        c = np.array([x, y + h + r * 0.35, z]) + rng.uniform(-1, 1, 3) * np.array([r * 0.55, r * 0.35, r * 0.55])
        rr = r * rng.uniform(0.6, 0.9)
        can |= ball(M, c, rr, 0.85)
    can &= (M.m == 0)
    P.fill(can, leaves, cell=1.0)
    top = can & ~shift_mask(can, 1)
    P.fill(top, [leaves[-1], leaves[1]], cell=1.0)
    if fruit:
        f = can & ~shift_mask(can, 2, -1) & (rng.random(M.m.shape) < 0.04)
        P.fill(f, fruit, cell=0.5)


def shift_mask(a, axis, sign=1):
    b = np.zeros_like(a)
    if sign > 0:
        sl_d = [slice(None)] * 3; sl_s = [slice(None)] * 3
        sl_d[axis] = slice(0, -1); sl_s[axis] = slice(1, None)
    else:
        sl_d = [slice(None)] * 3; sl_s = [slice(None)] * 3
        sl_d[axis] = slice(1, None); sl_s[axis] = slice(0, -1)
    b[tuple(sl_d)] = a[tuple(sl_s)]
    return b


def gable(P, M, x0, x1, z0, z1, wall_h, roof_h, walls, roof, oh=1.0, ridge='x', y0=0.0, wall_cell=(1, 1, 1)):
    body = box(M, (x0, y0, z0), (x1, y0 + wall_h, z1))
    P.fill(body, walls, cell=wall_cell)
    if ridge == 'x':
        c, half = (z0 + z1) / 2, (z1 - z0) / 2 + oh
        top = y0 + wall_h + roof_h * (1 - np.abs(M.Z - c) / half)
        r = (M.X >= x0 - oh) & (M.X < x1 + oh) & (np.abs(M.Z - c) <= half) & (M.Y >= y0 + wall_h - 0.5) & (M.Y < top)
        gab = (M.X >= x0) & (M.X < x1) & (np.abs(M.Z - c) <= half - oh) & (M.Y >= y0 + wall_h) & (M.Y < top - 1.0)
        rows = (np.floor((np.abs(M.Z - c)) / 1.0).astype(int) % 2 == 0)
    else:
        c, half = (x0 + x1) / 2, (x1 - x0) / 2 + oh
        top = y0 + wall_h + roof_h * (1 - np.abs(M.X - c) / half)
        r = (M.Z >= z0 - oh) & (M.Z < z1 + oh) & (np.abs(M.X - c) <= half) & (M.Y >= y0 + wall_h - 0.5) & (M.Y < top)
        gab = (M.Z >= z0) & (M.Z < z1) & (np.abs(M.X - c) <= half - oh) & (M.Y >= y0 + wall_h) & (M.Y < top - 1.0)
        rows = (np.floor((np.abs(M.X - c)) / 1.0).astype(int) % 2 == 0)
    P.fill(gab, walls, cell=wall_cell)
    shell = r & ~gab & (M.Y >= top - 1.2)
    P.fill(shell, roof, cell=(1.0, 0.5, 1.0))
    P.fill(shell & rows, [roof[1], roof[2]], cell=(2.0, 0.5, 2.0))
    ridge_line = shell & (M.Y >= top - 0.6) & (np.abs((M.Z if ridge == 'x' else M.X) - c) < 0.6)
    P.fill(ridge_line, [roof[1]], cell=9)
    return body


def win_front(P, M, x, y, z, w, h, lit, frame=WALNUT, face='+z', glow=0.9):
    """A window on a wall facing +z (or +x/-x) at plane `z` (or x)."""
    if face == '+z':
        fr = (np.abs(M.X - x) <= w / 2 + 0.5) & (np.abs(M.Y - y) <= h / 2 + 0.5) & (M.Z >= z - 0.5) & (M.Z < z + 0.5)
        pane = (np.abs(M.X - x) <= w / 2) & (np.abs(M.Y - y) <= h / 2) & (M.Z >= z - 0.5) & (M.Z < z + 0.5)
        bar = pane & ((np.abs(M.X - x) < 0.3) | (np.abs(M.Y - y) < 0.3))
    else:
        sg = 1 if face == '+x' else -1
        fr = (np.abs(M.Z - z) <= w / 2 + 0.5) & (np.abs(M.Y - y) <= h / 2 + 0.5) & (sg * (M.X - x) >= -0.5) & (sg * (M.X - x) < 0.5)
        pane = (np.abs(M.Z - z) <= w / 2) & (np.abs(M.Y - y) <= h / 2) & (sg * (M.X - x) >= -0.5) & (sg * (M.X - x) < 0.5)
        bar = pane & ((np.abs(M.Z - z) < 0.3) | (np.abs(M.Y - y) < 0.3))
    P.fill(fr & ~pane, frame, cell=9)
    P.fill(pane, WIN_LIT if lit else WIN_DAY, glow=glow if lit else None, cell=9)
    P.fill(bar, frame, cell=9)


def outdoor_lantern(S, P, M, x, z, h, lit, power=22.0, s=0.8, kelvin=2700):
    P.fill(box(M, (x - 0.35, 0, z - 0.35), (x + 0.35, h, z + 0.35)), IRON, cell=9)
    P.fill(box(M, (x - 0.6, 0, z - 0.6), (x + 0.6, 0.6, z + 0.6)), IRON, cell=9)
    lantern(S, P, M, (x, h + 1.0 * s, z), s=s, lit=lit, power=power, kelvin=kelvin)


def flower_patch(P, M, cx, cz, rx, rz, rng, n=10, cols=('#FFFDF6', '#F5A3B5', '#F4C04E', '#E8E0FF')):
    for _ in range(n):
        a = rng.uniform(0, 2 * math.pi)
        rr = math.sqrt(rng.uniform(0, 1))
        x, z = cx + rx * rr * math.cos(a), cz + rz * rr * math.sin(a)
        P.fill(box(M, (x - 0.25, 0, z - 0.25), (x + 0.25, 0.75, z + 0.25)), ['#5EA046'], cell=9)
        P.fill(box(M, (x - 0.5, 0.75, z - 0.5), (x + 0.5, 1.25, z + 0.5)), [cols[rng.integers(len(cols))]], cell=9)


def fence_line(P, M, a, b, h=2.4):
    a, b = np.array(a, float), np.array(b, float)
    d = (b - a) / np.linalg.norm(b - a)
    L = np.linalg.norm(b - a)
    rx, rz = M.X - a[0], M.Z - a[1]
    t = rx * d[0] + rz * d[1]
    perp = np.abs(-rx * d[1] + rz * d[0])
    on = (t >= 0) & (t <= L)
    for ry in (0.9, 1.9):
        P.fill(on & (perp <= 0.3) & (np.abs(M.Y - ry) <= 0.3), HONEY, cell=9)
    P.fill(on & (perp <= 0.45) & ((t % 3.0) < 0.9) & (M.Y >= 0) & (M.Y < h), ['#B9875C', '#A9784E'], cell=9)


def bunting(P, M, a, b, sag=1.6, cols=('#203B50', '#E8B956', '#F5A3B5', '#7F9871', '#B76B4D')):
    """A string of little pennants between two points (x, y, z)."""
    a, b = np.array(a, float), np.array(b, float)
    n = int(np.linalg.norm(b - a) / 0.5)
    for i in range(n + 1):
        t = i / n
        p = a + (b - a) * t
        p[1] -= sag * 4 * t * (1 - t)
        P.fill(box(M, (p[0] - 0.15, p[1] - 0.15, p[2] - 0.15), (p[0] + 0.15, p[1] + 0.15, p[2] + 0.15)), ['#F3E5C9'], cell=9)
        if i % 3 == 1:
            col = cols[(i // 3) % len(cols)]
            P.fill(box(M, (p[0] - 0.45, p[1] - 1.1, p[2] - 0.2), (p[0] + 0.45, p[1] - 0.15, p[2] + 0.2)) &
                   (np.abs(M.X - p[0]) <= 0.45 - (p[1] - 0.15 - M.Y) * 0.4), [col], cell=9)


def fireflies2(S, P, M, rng, n, xr, yr, zr, light_every=6, power=0.6):
    for i in range(n):
        x, y, z = rng.uniform(*xr), rng.uniform(*yr), rng.uniform(*zr)
        f = box(M, (x - 0.25, y - 0.25, z - 0.25), (x + 0.25, y + 0.25, z + 0.25)) & (M.m == 0)
        P.fill(f, ['#FFF3B0', '#FFE7A0'], glow=1.0, cell=9)
        if i % light_every == 0:
            S.lights.append({'type': 'point', 'pos': (x, y, z), 'power': power, 'color': 3200, 'radius': 0.3})


def waystone_model(S, restored, glimmer=True, cx=0.0, cz=0.0, power=8.0, seed=7):
    """Plinth and standing stone with three grooves and three brass notches (Quest Bible §2).
    Its own fine (res 4) model so the grooves read as three channels."""
    W = Model((int(cx) - 5, 0, int(cz) - 5), (int(cx) + 5, 11, int(cz) + 5), [], res=4)
    P = CPainter(W, seed)
    X, Z = W.X - cx, W.Z - cz
    plinth = (np.maximum(np.abs(X), np.abs(Z)) <= 3.0) & (W.Y < 0.9)
    P.fill(plinth, STONE_LT, cell=(1.0, 9, 1.0))
    P.fill((np.maximum(np.abs(X), np.abs(Z)) <= 2.4) & (W.Y >= 0.9) & (W.Y < 1.4), STONE_LT, cell=(1.0, 9, 1.0))
    stone = (np.abs(X) <= 2.0 - np.clip(W.Y - 7.2, 0, None) * 0.55) & (np.abs(Z) <= 1.15) & (W.Y >= 1.4) & (W.Y < 9.4)
    P.fill(stone, ['#D4C894', '#C9BC86', '#DCD19E', '#CFC28C'], cell=0.75)
    rng = np.random.default_rng(seed)
    P.fill(stone & (W.Y < 3.4) & (X < -0.6) & (rng.random(W.m.shape) > 0.35), SAGE, cell=0.5)
    P.fill(stone & (W.Y > 8.0) & (X > 0.4) & (rng.random(W.m.shape) > 0.55), SAGE, cell=0.5)
    front = stone & (Z > 0.8)
    gr = front & ((np.abs(X + 0.9) < 0.2) | (np.abs(X) < 0.2) | (np.abs(X - 0.9) < 0.2)) & (W.Y > 2.8) & (W.Y < 7.4)
    if restored:
        P.fill(gr, MINT, glow=0.9, cell=9)
        S.lights.append({'type': 'point', 'pos': (cx, 4.6, cz + 3.4), 'power': power, 'color': (0.55, 1.0, 0.85), 'radius': 1.0})
        halo = (np.abs(np.sqrt(X ** 2 + Z ** 2) - 3.6) < 0.3) & (W.Y < 0.5)
        P.fill(halo, MINT, glow=0.6, cell=9)
    else:
        P.fill(gr, ['#5F5D4B', '#55533F'], cell=9)
        if glimmer:
            P.fill(gr & (np.abs(X - 0.9) < 0.2) & (W.Y > 6.4), ['#E8D99A'], glow=0.8, cell=9)
    for nx in (-0.9, 0.0, 0.9):
        P.fill((np.abs(X - nx) < 0.32) & (np.abs(W.Y - 8.2) < 0.32) & (Z > 0.9) & (Z < 1.5), BRASS, cell=9)
    return W


def scene_waystone(restored=False):
    st = STATE_LIGHT['dusk' if restored else 'day']
    cam = {'pos': (0.0, 8.0, 29.0), 'target': (0.0, 5.2, 0.0), 'fov': 38.0, 'focus': (0.0, 5.0, 0.8), 'fstop': 4.0}
    S = VScene('waystone_restored' if restored else 'waystone_dormant', 1000, 1000, cam, world=st['world'], samples=160,
               transparent=True, sky=st['sky'])
    S.lights.append({'type': 'sun', **st['sun']})
    M = Model((-40, -2, -70), (40, 30, 20), [], res=2)
    P = CPainter(M, 81)
    rng = np.random.default_rng(81)
    # cobbled plaza with joint rings, grass beyond
    R2 = np.sqrt(M.X ** 2 + M.Z ** 2)
    ground = (M.Y >= -1) & (M.Y < 0)
    P.fill(ground, GRASS, cell=1.0)
    plaza = ground & (R2 < 16.0)
    P.fill(plaza, COBBLE, cell=(1.5, 1, 1.0), offset=(0.0, 0, 0.0))
    P.fill(plaza & ((np.abs((R2 % 3.0) - 1.5) > 1.32)), ['#B1A893'], cell=9)
    P.fill(ground & (np.abs(M.X - 0.0) < 3.0) & (M.Z < -15), PATHC, cell=(1.2, 1, 1.2))
    S.models.append((waystone_model(S, restored, power=5.0), ()))
    # Mira's old lantern post and flower tubs
    outdoor_lantern(S, P, M, 7.0, -2.5, 8.6, lit=True, power=30.0 if restored else 10.0, s=0.95)
    for (tx, tz) in ((-6.4, -1.6), (-9.6, 2.6), (6.0, 4.0)):
        tub = box(M, (tx - 1.3, 0, tz - 1.3), (tx + 1.3, 1.5, tz + 1.3))
        P.fill(tub, HONEY, cell=(9, 0.5, 9))
        P.fill(tub & (M.Y >= 1.1), OAK_DARK, cell=9)
        P.fill(ball(M, (tx, 2.2, tz), 1.5, 0.8) & (M.m == 0), LEAF, cell=0.5)
        for k in range(4):
            a = k * 1.6 + tx
            P.fill(ball(M, (tx + 1.0 * math.cos(a), 2.8, tz + 1.0 * math.sin(a)), 0.4), [FLOWERS[k % 4]])
    # bench, a barrel and a crate by the plaza edge
    P.fill(box(M, (-13.0, 1.4, -6.0), (-8.0, 1.9, -4.6)), HONEY, cell=(1.5, 1, 9))
    for lx in (-12.6, -8.6):
        P.fill(box(M, (lx, 0, -5.8), (lx + 0.5, 1.4, -4.8)), WALNUT)
    barrel(P, M, 11.6, -6.0, 1.3, 2.8)
    crate(P, M, 13.8, -4.0, 1.0)
    # the village behind: Lodge, Workshop, Glasshouse, cottages, trees
    gable(P, M, -9.0, 9.0, -48.0, -38.0, 9.0, 6.0, PLASTER, ROOF, ridge='x', wall_cell=(3, 3, 3))
    for wx in (-5.0, 5.0):
        win_front(P, M, wx, 5.0, -38.0, 2.0, 2.0, lit=restored)
    P.fill(box(M, (-1.6, 0, -38.5), (1.6, 5.0, -37.8)), WALNUT, cell=9)
    gable(P, M, 14.0, 28.0, -34.0, -24.0, 7.0, 5.0, BRICK, ROOF, ridge='x', wall_cell=(2, 1, 9))
    win_front(P, M, 18.0, 4.0, -24.0, 2.2, 2.0, lit=True)
    P.fill(box(M, (24.0, 7.0, -32.0), (26.0, 16.0, -30.0)), STONE, cell=9)
    gb = box(M, (-28.0, 0, -32.0), (-15.0, 2.0, -24.0))
    P.fill(gb, STONE_LT, cell=9)
    gl = box(M, (-28.0, 2.0, -32.0), (-15.0, 8.0, -24.0))
    P.fill(gl, CLEAR_GLASS, cell=50)
    P.fill(gl & ((((M.X + 28) % 2.5) < 0.5) | (np.abs(M.Y - 5.0) < 0.3)), SAGE, cell=9)
    for (tx, tz, h, r) in ((-34.0, -44.0, 8, 6), (-20.0, -52.0, 9, 6.5), (20.0, -50.0, 8, 6), (34.0, -40.0, 7, 5.5),
                           (-36.0, -20.0, 6, 5), (36.0, -18.0, 6, 5)):
        tree2(P, M, tx, tz, h, r)
    P.fill(box(M, (-40, 0, -70), (40, 14, -64)) & (M.Y < 9 + 3 * np.sin(M.X * 0.2)), TREE_LEAVES, cell=1.5)
    if restored:
        fireflies2(S, P, M, rng, 40, (-14, 14), (2.0, 13.0), (-12, 8), light_every=5, power=0.5)
    S.models.append((M, CLEAR_GLASS))
    S.grade = {'bloom': 0.35 if restored else 0.2, 'vignette': 0.15}
    return S


SQUARE_ANCHORS = {
    'glasshouse': (-17.5, 9.0, -3.0), 'workshop': (17.5, 10.0, -2.0), 'lodge': (0.0, 12.0, -24.0),
    'waystone': (0.0, 10.0, 0.0), 'lamp': (8.0, 7.0, 12.0), 'market': (-21.0, 4.0, 12.0),
}


def scene_square(state='day_dim'):
    lamp = state in ('lamp_lit', 'waystone_restored')
    restored = state == 'waystone_restored'
    st = STATE_LIGHT[{'day_dim': 'day', 'lamp_lit': 'golden', 'waystone_restored': 'dusk'}[state]]
    cam = {'pos': (0.0, 63.0, 63.0), 'target': (0.0, 0.0, -8.0), 'fov': 36.0}
    S = VScene('square_' + state, 1170, 1300, cam, world=st['world'], samples=128, transparent=True, sky=st['sky'])
    S.lights.append({'type': 'sun', **st['sun']})
    S.anchors = dict(SQUARE_ANCHORS)
    rng = np.random.default_rng(41)
    M = Model((-40, -4, -46), (40, 30, 36), [], res=2)
    P = CPainter(M, 41)
    X2, Z2 = M.X[:, 0, :], M.Z[:, 0, :]
    R = np.sqrt(M.X ** 2 + M.Z ** 2)
    ground = (M.Y >= -1) & (M.Y < 0)
    P.fill((M.Y >= -4) & (M.Y < -1), ['#B98955', '#A97C4B'], cell=1)
    P.fill(ground, GRASS, cell=1.0)
    # darker grass patches for texture
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
    # paths and the cobbled plaza
    pathm = ground & (((np.abs(M.X - 0.15 * M.Z) < 2.4) & (M.Z > 8)) | ((np.abs(M.X) < 2.4) & (M.Z < -8) & (M.Z > -24)) |
                      ((np.abs(M.Z + 1.0) < 2.2) & (np.abs(M.X) > 9) & (np.abs(M.X) < 13.5)))
    P.fill(pathm, PATHC, cell=(1.0, 1, 1.0))
    plaza = ground & (R < 10.0)
    P.fill(plaza, COBBLE, cell=(1.5, 1, 1.0))
    P.fill(plaza & ((np.abs((R % 2.5) - 1.25) > 1.0)), ['#B1A893'], cell=9)
    P.fill(ground & (R >= 9.4) & (R < 10.4), ['#A89F8C', '#B4AB97'], cell=9)
    # flower beds around the plaza (diagonals) and lamp posts
    for k, a in enumerate((0.785, 2.356, 3.927, 5.498)):
        bx_, bz_ = 12.0 * math.cos(a), 12.0 * math.sin(a)
        if bz_ < -6:
            continue
        bed = ((M.X - bx_) ** 2 + (M.Z - bz_) ** 2 <= 4.0) & (M.Y >= 0) & (M.Y < 0.7)
        P.fill(bed, STONE_LT, cell=9)
        P.fill(bed & (((M.X - bx_) ** 2 + (M.Z - bz_) ** 2) < 2.6) & (M.Y >= 0.4), ['#5B4334'], cell=0.5)
        flower_patch(P, M, bx_, bz_, 1.2, 1.2, rng, n=6)
    lamp_posts = [(9.5, 7.0), (-9.5, 7.0), (-9.5, -7.5), (9.5, -7.5)]
    for (lx, lz) in lamp_posts:
        outdoor_lantern(S, P, M, lx, lz, 6.0, lit=lamp, power=14.0, s=0.75)
    S.models.append((waystone_model(S, restored, glimmer=False, power=14.0), ()))

    # ---- Mira's Glasshouse (left)
    gx0, gx1, gz0, gz1 = -24.0, -11.0, -10.0, 2.0
    P.fill(box(M, (gx0, 0, gz0), (gx1, 2.0, gz1)), STONE_LT, cell=(1.5, 0.75, 1.5))
    walls = box(M, (gx0, 2.0, gz0), (gx1, 8.0, gz1)) & ~box(M, (gx0 + 0.5, 2.0, gz0 + 0.5), (gx1 - 0.5, 8.0, gz1 - 0.5))
    P.fill(walls, CLEAR_GLASS, cell=50)
    P.fill(walls & (((((M.X - gx0) % 2.5) < 0.5) & ((M.Z >= gz1 - 0.5) | (M.Z < gz0 + 0.5))) | (((M.Z - gz0) % 2.5) < 0.5) & ((M.X >= gx1 - 0.5) | (M.X < gx0 + 0.5)) | (np.abs(M.Y - 5.0) < 0.3)), SAGE, cell=9)
    zc, half = (gz0 + gz1) / 2, (gz1 - gz0) / 2 + 0.6
    topy = 8.0 + 4.0 * (1 - np.abs(M.Z - zc) / half)
    groof = (M.X >= gx0 - 0.6) & (M.X < gx1 + 0.6) & (np.abs(M.Z - zc) <= half) & (M.Y >= topy - 0.6) & (M.Y < topy) & (M.Y >= 8.0)
    P.fill(groof, CLEAR_GLASS, cell=50)
    P.fill(groof & ((((M.X - gx0) % 2.6) < 0.6) | (np.abs(M.Z - zc) < 0.6)), SAGE, cell=9)
    P.fill(box(M, (gx0 - 0.6, 7.6, gz0 - 0.6), (gx1 + 0.6, 8.2, gz1 + 0.6)) & ~box(M, (gx0 + 0.5, 7.0, gz0 + 0.5), (gx1 - 0.5, 9.0, gz1 - 0.5)), ['#43523D'], cell=9)
    # plants inside, seen through the glass
    for px in np.arange(gx0 + 1.6, gx1 - 1.0, 2.2):
        for pz in (gz0 + 1.6, gz1 - 1.8):
            P.fill(cyl_y(M, (px, pz), 0.6, 2.0, 3.0), TERRACOTTA, cell=9)
            P.fill(ball(M, (px, 4.0, pz), 1.1, 0.9) & (M.m == 0), LEAF, cell=0.5)
            P.fill(ball(M, (px + 0.4, 4.8, pz + 0.4), 0.4), [FLOWERS[int(px * 3) % 5]])
    door = box(M, (gx1 - 0.2, 0, -5.4), (gx1 + 0.4, 5.0, -2.6))
    P.fill(door, ['#7F9871', '#6E8762'], cell=9)
    for (px, pz) in ((gx1 + 1.6, 0.6), (gx1 + 1.6, -8.0), (gx0 + 2.0, gz1 + 1.6), (gx0 + 6.0, gz1 + 1.6), (gx0 + 10.0, gz1 + 1.6)):
        P.fill(cyl_y(M, (px, pz), 0.8, 0, 1.2), TERRACOTTA, cell=9)
        P.fill(ball(M, (px, 2.0, pz), 1.2, 0.85) & (M.m == 0), LEAF, cell=0.5)
        P.fill(ball(M, (px + 0.4, 2.8, pz + 0.4), 0.45), [FLOWERS[int(abs(px * pz)) % 5]])
    flower_patch(P, M, gx0 + 6.0, gz1 + 5.0, 5.0, 1.6, rng, n=18)
    fence_line(P, M, (gx0 - 1.0, gz1 + 7.4), (gx1 + 0.5, gz1 + 7.4))
    vane = box(M, (-17.6, 12.0, zc - 0.2), (-17.2, 14.6, zc + 0.2))
    P.fill(vane, IRON, cell=9)
    P.fill(ball(M, (-17.4, 15.0, zc), 0.8), ['#FFFDF6'])
    P.fill(ball(M, (-17.4, 15.0, zc + 0.4), 0.35), ['#F4C04E'])
    outdoor_lantern(S, P, M, gx1 + 1.2, -1.4, 4.4, lit=lamp, power=8.0, s=0.6)

    # ---- Bram's Workshop (right): brick and timber, chimney, awning, crates
    wx0, wx1, wz0, wz1 = 11.0, 24.0, -11.0, 1.0
    body = gable(P, M, wx0, wx1, wz0, wz1, 7.0, 5.0, BRICK, ROOF, oh=1.0, ridge='z', wall_cell=(2.0, 1.0, 2.0))
    P.fill(body & ((((M.Y) % 1.0) < 0.5) & ((M.X < wx0 + 0.5) | (M.Z >= wz1 - 0.5))) & ((np.floor(M.Y) % 2) == 0), ['#9E5A40'], cell=9)
    for (px, pz) in ((wx0, wz0), (wx0, wz1 - 0.6), (wx1 - 0.6, wz1 - 0.6)):
        P.fill(box(M, (px, 0, pz), (px + 0.6, 7.0, pz + 0.6)), WALNUT, cell=9)
    P.fill(box(M, (wx0, 6.4, wz0), (wx1, 7.0, wz1)) & ((M.X < wx0 + 0.6) | (M.Z >= wz1 - 0.6)), WALNUT, cell=9)
    win_front(P, M, wx0, 3.6, -7.6, 2.4, 2.2, lit=True, face='-x', glow=0.7)
    win_front(P, M, 19.6, 3.8, wz1, 2.4, 2.2, lit=True, glow=0.7)
    S.lights.append({'type': 'point', 'pos': (wx0 + 1.6, 3.6, -7.6), 'power': 10.0, 'color': 1900, 'radius': 1.0})
    P.fill(box(M, (wx0 - 0.5, 0, -3.8), (wx0 + 0.2, 5.0, -1.0)), WALNUT, cell=9)
    chim = box(M, (19.0, 7.0, -8.6), (21.4, 15.6, -6.2))
    P.fill(chim, STONE, cell=(1.0, 1.0, 1.0))
    P.fill(box(M, (19.4, 15.4, -8.2), (21.0, 15.8, -6.6)), ['#FF9A4A', '#FFB65C'], glow=1.0, cell=9)
    for k in range(4):
        P.fill(ball(M, (20.2 + k * 0.6, 17.2 + k * 1.6, -7.4 - k * 0.3), 0.8 + 0.25 * k) & (M.m == 0), ['#F2F2EE', '#E6E6E2'], cell=0.5)
    awn = (M.X >= wx0 - 3.0) & (M.X < wx0) & (M.Z >= -10.0) & (M.Z < -5.0) & (np.abs(M.Y - (5.6 + (M.X - wx0) * 0.35)) < 0.3)
    P.fill(awn, ['#B76B4D'], cell=9)
    P.fill(awn & (((M.Z + 10.0) % 2.0) < 1.0), ['#F3E5C9'], cell=9)
    for (cx_, cz_, s_) in ((wx0 - 1.8, 3.4, 0.9), (wx0 - 1.6, 5.2, 0.7), (wx1 + 1.6, -2.0, 1.0)):
        crate(P, M, cx_, cz_, s_)
    barrel(P, M, wx1 + 1.8, 1.6, 1.1, 2.4)
    sign = box(M, (wx0 - 2.2, 5.2, 0.2), (wx0 - 1.8, 6.8, 2.2))
    P.fill(sign, HONEY, cell=9)
    P.fill(box(M, (wx0 - 2.0, 6.8, 1.0), (wx0 - 0.4, 7.2, 1.4)), IRON)
    outdoor_lantern(S, P, M, wx0 - 1.4, -1.0, 4.4, lit=lamp, power=8.0, s=0.6)

    # ---- the Trail Guild Lodge (top): timber frame, two storeys, banners, flag
    lx0, lx1, lz0, lz1 = -10.0, 10.0, -34.0, -24.0
    body = gable(P, M, lx0, lx1, lz0, lz1, 10.0, 6.0, PLASTER, ROOF, oh=1.2, ridge='x', wall_cell=(3, 3, 3))
    fr = body & (M.Z >= lz1 - 0.5) & ((((M.X - lx0) % 5.0) < 0.6) | (np.abs(M.Y - 5.0) < 0.35) | (M.Y < 0.6) | (M.Y >= 9.4))
    P.fill(fr, WALNUT, cell=9)
    P.fill(body & (M.X < lx0 + 0.6) & ((((M.Z - lz0) % 5.0) < 0.6) | (np.abs(M.Y - 5.0) < 0.35)), WALNUT, cell=9)
    P.fill(box(M, (-1.8, 0, lz1 - 0.4), (1.8, 4.4, lz1 + 0.3)), ['#5E3A24', '#6E4529'], cell=9)
    for wx in (-6.5, 6.5):
        win_front(P, M, wx, 2.6, lz1, 2.4, 2.0, lit=lamp)
        win_front(P, M, wx, 7.4, lz1, 2.4, 2.0, lit=lamp or restored)
    win_front(P, M, 0.0, 7.4, lz1, 2.0, 2.0, lit=restored)
    comp = (np.sqrt(M.X ** 2 + (M.Y - 12.4) ** 2) <= 1.1) & (M.Z >= lz1 - 1.0) & (M.Z < lz1 + 0.6)
    P.fill(comp, COPPER, cell=9)
    P.fill(comp & ((np.abs(M.X) < 0.25) | (np.abs(M.Y - 12.4) < 0.25)), BRASS)
    for bx in (-9.2, 9.2):
        ban = (np.abs(M.X - bx) <= 1.1) & (M.Y >= 3.4) & (M.Y < 9.0) & (M.Z >= lz1 + 0.1) & (M.Z < lz1 + 0.6)
        ban &= ~((M.Y < 4.4) & (np.abs(M.X - bx) < 0.5))
        P.fill(ban, NAVY, cell=9)
        P.fill(ban & (np.abs(M.Y - 7.0) < 0.5) & (np.abs(M.X - bx) < 0.6), CREAM)
    P.fill(box(M, (-3.6, 4.6, lz1), (3.6, 5.0, lz1 + 2.6)), WALNUT, cell=9)          # porch roof
    for px in (-3.2, 3.0):
        P.fill(box(M, (px, 0, lz1 + 2.0), (px + 0.5, 4.6, lz1 + 2.5)), WALNUT, cell=9)
    for wx in (-2.6, 2.6):
        lantern(S, P, M, (wx, 3.6, lz1 + 2.3), s=0.55, lit=lamp, power=5.0)
    pole = box(M, (8.6, 16.0, -29.2), (9.0, 21.0, -28.8))
    P.fill(pole, IRON, cell=9)
    P.fill(box(M, (9.0, 18.8, -29.0), (12.6, 20.8, -28.8)), NAVY, cell=9)
    P.fill(box(M, (9.0, 19.6, -29.0), (12.6, 20.0, -28.8)), CREAM, cell=9)

    # ---- cottages filling out the village
    cottages = [(-34.0, -26.0, -36.0, -26.0, SLATE, PLASTER), (22.0, 34.0, -38.0, -28.0, MOSSROOF, ['#E9D7B8', '#E2CEAC']),
                (26.0, 36.0, 10.0, 20.0, ROOF, PLASTER), (-38.0, -30.0, -8.0, 2.0, SLATE, ['#D9C8A8', '#E2D2B4'])]
    for (cx0, cx1, cz0, cz1, rf, wl) in cottages:
        gable(P, M, cx0, cx1, cz0, cz1, 6.0, 4.5, wl, rf, ridge='x', wall_cell=(3, 3, 3))
        P.fill(box(M, (cx0, 0, cz1 - 0.5), (cx1, 0.6, cz1)), WALNUT, cell=9)
        mid = (cx0 + cx1) / 2
        P.fill(box(M, (mid - 1.0, 0, cz1 - 0.3), (mid + 1.0, 3.6, cz1 + 0.3)), ['#6E4529'], cell=9)
        win_front(P, M, mid - 3.0, 3.0, cz1, 1.6, 1.6, lit=restored or (lamp and cx0 > 0))
        win_front(P, M, mid + 3.0, 3.0, cz1, 1.6, 1.6, lit=restored)
        P.fill(box(M, (cx1 - 2.6, 6.0, cz0 + 2.0), (cx1 - 1.2, 11.0, cz0 + 3.4)), STONE, cell=9)
    # ---- the market corner (bottom left): striped stall with produce, barrels
    mx_, mz_ = -21.0, 12.0
    P.fill(box(M, (mx_ - 3.6, 2.4, mz_ - 1.6), (mx_ + 3.6, 3.0, mz_ + 1.6)), HONEY, cell=(1.5, 1, 9))
    for (px, pz) in ((mx_ - 3.4, mz_ - 1.4), (mx_ + 3.0, mz_ - 1.4), (mx_ - 3.4, mz_ + 1.0), (mx_ + 3.0, mz_ + 1.0)):
        P.fill(box(M, (px, 0, pz), (px + 0.5, 6.4, pz + 0.5)), WALNUT, cell=9)
    canopy = (np.abs(M.X - mx_) <= 4.2) & (np.abs(M.Z - mz_) <= 2.6) & (np.abs(M.Y - (6.8 - (M.Z - mz_) * 0.35)) < 0.35)
    P.fill(canopy, ['#D85F51'], cell=9)
    P.fill(canopy & ((((M.X - mx_) % 2.0) + 2.0) % 2.0 < 1.0), CREAM, cell=9)
    for k, (fx_, col) in enumerate(((-2.4, ['#D85F51', '#C94C40']), (-0.6, ['#F4C04E', '#E8B04A']), (1.2, ['#86C56A', '#6FB24E']), (2.8, ['#FF9E5A']))):
        P.fill(ball(M, (mx_ + fx_, 3.4, mz_), 0.9, 0.6) & (M.Y >= 3.0), col, cell=0.5)
    barrel(P, M, mx_ + 5.4, mz_ + 1.0, 1.1, 2.4)
    crate(P, M, mx_ - 5.0, mz_ + 1.6, 0.9)
    # ---- the gate, fences, the nursery lamp
    for gx in (-3.6, 3.4):
        P.fill(box(M, (gx - 0.4 + 2.1, 0, 15.6), (gx + 0.4 + 2.1, 4.6, 16.4)), HONEY, cell=9)
    arch = (np.abs(M.Z - 16.0) <= 0.4) & (np.abs(M.Y - 4.4 - 0.6 * np.cos((M.X - 2.1) / 3.8 * 1.4)) <= 0.35) & (np.abs(M.X - 2.1) <= 4.2)
    P.fill(arch, HONEY, cell=9)
    fence_line(P, M, (-38.0, 17.0), (-2.4, 16.0))
    fence_line(P, M, (6.6, 16.0), (38.0, 17.0))
    outdoor_lantern(S, P, M, 8.0, 12.0, 6.0, lit=lamp, power=30.0 if lamp else 0.0, s=0.95, kelvin=2400)
    if lamp:
        fireflies2(S, P, M, np.random.default_rng(3), 8, (6.0, 10.0), (6.0, 10.0), (10.0, 14.0), light_every=99)
    # ---- benches, signpost, hay, trees, flowers
    for (bx_, bz_) in ((-6.0, 7.6), (6.2, -7.8)):
        P.fill(box(M, (bx_ - 1.8, 1.0, bz_ - 0.6), (bx_ + 1.8, 1.5, bz_ + 0.6)), HONEY, cell=(1.5, 1, 9))
        for lx in (bx_ - 1.4, bx_ + 1.0):
            P.fill(box(M, (lx, 0, bz_ - 0.5), (lx + 0.5, 1.0, bz_ + 0.5)), WALNUT)
    P.fill(box(M, (-4.4, 0, 10.4), (-4.0, 5.6, 10.8)), WALNUT, cell=9)
    for k, (yy, dx) in enumerate(((4.8, 1.0), (3.8, -1.0))):
        P.fill(box(M, (-4.2 + (0 if dx > 0 else -2.4), yy - 0.35, 10.4), (-4.2 + (2.4 if dx > 0 else 0), yy + 0.35, 10.8)), HONEY, cell=9)
    for (hx, hz) in ((27.0, 4.0), (29.0, 5.4)):
        P.fill(cyl_y(M, (hx, hz), 1.2, 0, 1.6), ['#E8C766', '#DDBA58'], cell=0.5)
    trees = [(-30.0, -16.0, 7, 4.8), (-28.0, 8.0, 5, 3.8), (30.0, -18.0, 8, 5.0), (33.0, -4.0, 6, 4.0),
             (-16.0, -26.0, 6, 4.2), (16.0, -24.0, 7, 4.2), (-36.0, 22.0, 6, 4.5), (35.0, 26.0, 6, 4.5),
             (-14.0, 24.0, 5, 3.6), (18.0, 24.0, 5, 3.4), (-34.0, -40.0, 8, 5), (36.0, -42.0, 8, 5)]
    for (tx, tz, th_, tr) in trees:
        tree2(P, M, tx, tz, th_, tr, fruit=['#D85F51'] if (tx > 0 and tz > 20) else None)
    for _ in range(26):
        fx, fz = rng.uniform(-36, 36), rng.uniform(-40, 30)
        rr = math.hypot(fx, fz)
        if rr < 12 or (abs(fx) > 9 and abs(fx) < 26 and -12 < fz < 4) or (abs(fx) < 12 and -36 < fz < -22) or abs(fx - 0.15 * fz) < 3.4 and fz > 6 \
                or abs(fz - (-15.0)) < 4.0:
            continue
        flower_patch(P, M, fx, fz, 1.4, 1.0, rng, n=4)
    # bunting across the plaza, from the lamp posts to the Lodge porch
    for (a, b) in (((-9.5, 7.6, 7.0), (9.5, 7.6, 7.0)), ((-9.5, 7.6, -7.5), (-3.2, 4.6, lz1 + 2.2)),
                   ((9.5, 7.6, -7.5), (3.5, 4.6, lz1 + 2.2))):
        bunting(P, M, a, b, sag=1.4)
    if restored:
        fireflies2(S, P, M, np.random.default_rng(9), 60, (-30, 30), (2.0, 12.0), (-30, 20), light_every=10, power=0.8)
    S.models.append((M, CLEAR_GLASS, {'water': WATERC}))
    S.models.append((far_terrain(seed=41), (), {'water': WATERC}))
    S.grade = {'bloom': {'day_dim': 0.12, 'lamp_lit': 0.3, 'waystone_restored': 0.4}[state], 'vignette': 0.12}
    return S


def far_terrain(seed=41):
    """Terraces, a waterfall and forest behind the village (what the top of the Square shows)."""
    F = Model((-130, -2, -150), (130, 60, -44), [], res=1)
    P = CPainter(F, seed)
    rng = np.random.default_rng(seed)
    xs, zs = F.X[:, 0, 0], F.Z[0, 0, :]
    X2, Z2 = np.meshgrid(xs, zs, indexing='ij')
    t = np.clip((-46.0 - Z2) / 90.0, 0, 1)
    H = 2.0 + 30.0 * np.floor(t * 5 + 0.6 * np.sin(X2 * 0.09) + 0.4 * np.cos(X2 * 0.23 + 1.0)) / 5
    H = np.maximum(H, 0)
    solid = (F.Y < H[:, None, :]) & (F.Y >= -2)
    top = solid & (F.Y >= H[:, None, :] - 1.0)
    P.fill(solid & ~top, ['#B9A889', '#A99877', '#C4B597', '#9E8E70'], cell=(3.0, 2.0, 3.0))
    P.fill(top, ['#7FAE5F', '#86B566', '#8DBD6C'], cell=2.0)
    # waterfall and pool
    fx = -24.0
    P.fill((np.abs(F.X - fx) <= 3.0) & (F.Z >= -64.0) & (F.Z < -62.5) & (F.Y < 20.0), ['#BFE6F5', '#D7F0FA', '#EAF8FF'], cell=1.0)
    pool = ((F.X - fx) ** 2 / 64 + (F.Z + 56.0) ** 2 / 25 <= 1.0) & (F.Y >= 1.0) & (F.Y < 2.5)
    P.fill(pool, WATERC, cell=1.0)
    for _ in range(70):
        tx, tz = rng.uniform(-125, 125), rng.uniform(-145, -50)
        i, j = np.argmin(np.abs(xs - tx)), np.argmin(np.abs(zs - tz))
        ty = H[i, j]
        if abs(tx - fx) < 7 and tz > -70:
            continue
        r = rng.uniform(3.0, 5.5)
        P.fill(box(F, (tx - 0.6, ty, tz - 0.6), (tx + 0.6, ty + 4.0, tz + 0.6)), ['#7A4E2E'], cell=9)
        P.fill(ball(F, (tx, ty + 4.0 + r * 0.6, tz), r, 0.85) & (F.m == 0), TREE_LEAVES, cell=1.5)
    return F


def finish(vs: VScene, raw_path, out_path, preview=False):
    """Light grading: a soft vignette and a touch of warmth, then RGB PNG (or sky composite)."""
    im = Image.open(raw_path).convert('RGBA')
    a = np.asarray(im).astype(np.float32)
    if vs.transparent and vs.sky:
        h, w = a.shape[:2]
        top = np.array([int(vs.sky[0][i:i + 2], 16) for i in (1, 3, 5)], np.float32)
        hor = np.array([int(vs.sky[1][i:i + 2], 16) for i in (1, 3, 5)], np.float32)
        t = np.clip(np.linspace(0, 1, h)[:, None] / 0.55, 0, 1) ** 1.2
        sky = top * (1 - t[..., None]) + hor * t[..., None]
        al = a[..., 3:4] / 255.0
        a[..., :3] = a[..., :3] * al + sky * (1 - al)
    rgb = a[..., :3]
    g = vs.grade
    if g.get('bloom'):
        h, w = rgb.shape[:2]
        lum = rgb.mean(-1)
        hi = np.clip((lum - 175.0) / 80.0, 0, 1)[..., None] * rgb
        im_hi = Image.fromarray(np.clip(hi, 0, 255).astype(np.uint8))
        b1 = np.asarray(im_hi.filter(ImageFilter.GaussianBlur(w * 0.006))).astype(np.float32)
        b2 = np.asarray(im_hi.filter(ImageFilter.GaussianBlur(w * 0.022))).astype(np.float32)
        rgb = rgb + g['bloom'] * (0.6 * b1 + 0.8 * b2)
    if g.get('warm'):
        rgb = rgb * np.array([1 + g['warm'], 1.0, 1 - g['warm']], np.float32)
    if g.get('vignette'):
        h, w = rgb.shape[:2]
        yy, xx = np.mgrid[0:h, 0:w]
        d = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2) / math.sqrt(2)
        rgb = rgb * (1 - g['vignette'] * np.clip(d - 0.35, 0, 1) ** 1.5)[..., None]
    if getattr(vs, 'keep_alpha', False):
        # a layer to composite (e.g. a battle foreground): keep the alpha, premultiplied edges stay soft
        rgba = np.concatenate([np.clip(rgb, 0, 255), a[..., 3:4]], -1).astype(np.uint8)
        Image.fromarray(rgba, 'RGBA').save(out_path)
        return
    Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).save(out_path)


SCENES = {'workshop': scene_workshop, 'glasshouse': scene_glasshouse, 'lodge': scene_lodge,
          'waystone_dormant': lambda: scene_waystone(False), 'waystone_restored': lambda: scene_waystone(True),
          'square_day_dim': lambda: scene_square('day_dim'), 'square_lamp_lit': lambda: scene_square('lamp_lit'),
          'square_waystone_restored': lambda: scene_square('waystone_restored')}

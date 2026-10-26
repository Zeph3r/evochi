"""Inside the Cottage, laid out to walk through: one warm room seen from the walking camera (orthographic,
35 degrees above the horizon, looking north), the front wall and the roof left off so you look in as
into a dollhouse. The kitchen along the west wall (a stove with its hood, a counter, shelves of jars,
herbs hanging), the apothecary along the east (a cauldron on a tripod over embers, shelves of bottles
that glow a little, a worktable with a mortar and a candle), the hearth in the back wall with a mantel,
a rug before it, a basket bed in the front-left corner and a writing desk with a bookcase front-right.
The door is in the front, on +z.

    python3 cottage_walk.py OUT [--quick] [--depth]

World: x east, z toward you, y up. The room is ROOM; everything inside it is walkable save what stands
knee-high or taller (village_walk_pack.walk_grid).
"""
import math
import os
import sys

import numpy as np

import village_walk as VW
from home_scenes import hashmask
from village_scenes import (BRASS, COPPER, CPainter, GLASS_AMBER, GLASS_MINT, GLASS_ROSE, HONEY, IRON, OAK, PARCH, STONE, STONE_LT,
                            STATE_LIGHT, VScene, WALNUT, WIN_DAY, ball, box, cyl_y, lantern)
from voxel import Model

X0, X1, Z0, Z1 = -16.0, 16.0, -14.0, 14.0
ROOM = (-12.0, 12.0, -10.0, 10.0)           # x0, x1, z0, z1 (the door on z1)
WALL_H, WALL_T = 7.0, 0.8
DOOR_W = 4.2
HEARTH = (0.0, -10.0)                       # the middle of the back wall
STOVE = (-10.2, -5.5)                       # the kitchen's stove, against the west wall
COUNTER = (-11.4, -9.4, -2.6, 4.6)          # x0, x1, z0, z1
CAULDRON = (9.8, -5.6)
WORKTABLE = (9.6, 11.6, -0.8, 3.8)
DESK = (8.2, 11.4, 5.4, 7.6)
BED = (-7.2, 6.2)
TABLE = (3.4, 1.8)
PLUM = ['#B98BFF', '#A27BE0', '#CBA6FF']
TEAL = ['#9FF0DA', '#7FD8C0', '#C8FFF0']
RUG = ['#B8584A', '#C96A58', '#A94E42']
RUG_LT = ['#E0B07A', '#E8BE8C']
LINEN = ['#FBF5E8', '#F1E6CF']
EMBER = ['#FF9A3C', '#FFC561', '#FF6A2A']
BOOKS = ['#B8584A', '#5E7A9C', '#7F9871', '#C9A24A', '#8E5A33', '#6E4FA0']


def _jar(P, M, x, y, z, r, h, cols, glow=None):
    P.fill(cyl_y(M, (x, z), r, y, y + h), cols, glow=glow, cell=9)
    P.fill(cyl_y(M, (x, z), r * 0.55, y + h, y + h + 0.35), WALNUT, cell=9)


def scene_cottage_walk():
    st = STATE_LIGHT['day']
    # the sky here is the dark round the dollhouse: what shows past the walls
    S = VScene('cottage_walk', 1374, 1000, {}, world=((0.98, 0.9, 0.78), 0.55), samples=96, transparent=True, sky=('#2C2019', '#1F1611'))
    # a softer sun than outdoors, from the open front: the room is lit mostly by its own lamps
    S.lights.append({'type': 'sun', 'dir': (0.3, -0.72, -0.62), 'power': 1.6, 'color': 4600, 'angle': 6.0})
    rng = np.random.default_rng(93)
    M = Model((X0, -4, Z0), (X1, 14, Z1), [], res=2)
    P = CPainter(M, 93)
    X, Y, Z = M.X, M.Y, M.Z
    rx0, rx1, rz0, rz1 = ROOM
    inside = (X >= rx0) & (X < rx1) & (Z >= rz0) & (Z < rz1)
    ground = (Y >= -1) & (Y < 0)
    # ---- outside the walls there is nothing (the picture's edge; the screen shows a dark ground there),
    # save the flagstones at the door
    P.fill(box(M, (-3.4, -1, rz1 + WALL_T), (3.4, 0, rz1 + 3.6)), ['#BDB4A0', '#B0A792', '#C6BEAA', '#A59C87'], cell=(1.0, 1, 1.0))
    # ---- the floor: oak boards running east-west, a darker seam between them
    P.fill(ground & inside, OAK, cell=(3.0, 1, 0.6))
    P.fill(ground & inside & ((Z % 0.6) < 0.08), ['#8D5D3B'], cell=9)
    P.fill(ground & inside & (hashmask(M, 0.06, seed=4, cell=1.0)), ['#986642'], cell=9)
    # ---- the walls: plaster over a stone footing, timber posts; the back and sides full height, the front
    # a knee-high sill either side of the door (so you look in)
    back = box(M, (rx0 - WALL_T, 0, rz0 - WALL_T), (rx1 + WALL_T, WALL_H, rz0))
    west = box(M, (rx0 - WALL_T, 0, rz0 - WALL_T), (rx0, WALL_H, rz1 + WALL_T))
    east = box(M, (rx1, 0, rz0 - WALL_T), (rx1 + WALL_T, WALL_H, rz1 + WALL_T))
    sill = box(M, (rx0 - WALL_T, 0, rz1), (rx1 + WALL_T, 0.7, rz1 + WALL_T)) & ~box(M, (-DOOR_W / 2, 0, rz1 - 1), (DOOR_W / 2, 2, rz1 + 2))
    walls = back | west | east
    P.fill(walls, ['#F1E2C6', '#EBDBBC', '#F5E9D2'], cell=(2.0, 2.0, 2.0))
    P.fill(walls & (Y < 1.2), STONE, cell=(1.0, 0.6, 1.0))
    P.fill(sill, STONE, cell=(1.0, 0.6, 1.0))
    # timber posts and the wall plate
    for px in np.arange(rx0, rx1 + 0.1, 6.0):
        P.fill(back & (np.abs(X - px) < 0.35), WALNUT, cell=9)
    for pz in np.arange(rz0, rz1 + 0.1, 5.0):
        P.fill((west | east) & (np.abs(Z - pz) < 0.35), WALNUT, cell=9)
    P.fill(walls & (Y >= WALL_H - 0.6), WALNUT, cell=9)
    # the doorway: short stone posts either side of the gap (nothing tall in front: it would hide the room), the step outside
    for sx in (-1, 1):
        P.fill(box(M, (sx * DOOR_W / 2 - 0.5, 0, rz1 - 0.2), (sx * DOOR_W / 2 + 0.5, 0.85, rz1 + WALL_T + 0.2)), STONE_LT, cell=(0.6, 0.4, 0.6))
    P.fill(box(M, (-DOOR_W / 2 - 0.6, -1, rz1 + WALL_T), (DOOR_W / 2 + 0.6, 0.3, rz1 + 2.4)), STONE_LT, cell=(1.5, 1, 1.5))
    P.fill(box(M, (-DOOR_W / 2, -1, rz1), (DOOR_W / 2, 0.0, rz1 + WALL_T)), STONE_LT, cell=(1.5, 1, 1.5))      # the threshold
    # (the door stands open out of the picture: anything tall in front of the doorway would hide it)
    # windows: a round one in the back wall west of the hearth, square ones east and on the side walls
    def window(cx, cy, w, h, face, round_=False):
        if face == 'back':
            plane = (Z >= rz0 - WALL_T) & (Z < rz0)
            u, v = X - cx, Y - cy
        elif face == 'west':
            plane = (X >= rx0 - WALL_T) & (X < rx0)
            u, v = Z - cx, Y - cy
        else:
            plane = (X >= rx1) & (X < rx1 + WALL_T)
            u, v = Z - cx, Y - cy
        if round_:
            pane = plane & ((u / (w / 2)) ** 2 + (v / (h / 2)) ** 2 <= 1.0)
            frame = plane & ((u / (w / 2 + 0.5)) ** 2 + (v / (h / 2 + 0.5)) ** 2 <= 1.0) & ~pane
        else:
            pane = plane & (np.abs(u) <= w / 2) & (np.abs(v) <= h / 2)
            frame = plane & (np.abs(u) <= w / 2 + 0.5) & (np.abs(v) <= h / 2 + 0.5) & ~pane
        P.fill(frame, WALNUT, cell=9)
        P.fill(pane, WIN_DAY, glow=0.08, cell=9)
        P.fill(pane & ((np.abs(u) < 0.2) | (np.abs(v) < 0.2)), WALNUT, cell=9)
    window(-7.0, 4.6, 2.6, 2.6, 'back', round_=True)
    window(6.5, 4.4, 2.6, 2.2, 'back')
    window(6.4, 4.2, 2.4, 2.2, 'west')
    window(7.6, 4.2, 2.2, 2.0, 'east')
    # daylight in through the windows
    for (lx, ly, lz) in ((-7.0, 4.6, rz0 + 0.6), (6.5, 4.4, rz0 + 0.6), (rx0 + 0.6, 4.2, 6.4), (rx1 - 0.6, 4.2, 7.6)):
        S.lights.append({'type': 'point', 'pos': (lx, ly, lz), 'power': 4.0, 'color': 6200, 'radius': 1.0})

    # ---- the hearth: a stone fireplace in the back wall, logs and a fire, a mantel with a candle and an
    # egg-shaped stone on it, a pair of fire irons
    hx, hz = HEARTH
    P.fill(box(M, (hx - 3.2, 0, rz0 - WALL_T), (hx + 3.2, 5.6, rz0 + 1.4)), STONE, cell=(1.2, 0.7, 1.2))
    P.fill(box(M, (hx - 3.2, 0, rz0 - WALL_T), (hx + 3.2, 5.6, rz0 + 1.4)) & hashmask(M, 0.25, seed=7, cell=1.2), STONE_LT, cell=(1.2, 0.7, 1.2))
    mouth = box(M, (hx - 1.9, 0, rz0 - 0.3), (hx + 1.9, 3.3, rz0 + 1.5))
    M.m[mouth] = 0
    P.fill(box(M, (hx - 1.9, 0, rz0 - 0.3), (hx + 1.9, 3.3, rz0)), ['#2B211D', '#231B18'], cell=9)        # the back of the firebox
    P.fill(box(M, (hx - 1.9, 0, rz0 - 0.3), (hx + 1.9, 0.2, rz0 + 1.5)), ['#2B211D'], cell=9)
    for k, (lx, ly) in enumerate(((-0.9, 0.2), (0.7, 0.2), (-0.1, 0.9))):
        P.fill(box(M, (hx + lx - 0.4, ly, rz0 + 0.1), (hx + lx + 0.4, ly + 0.7, rz0 + 1.2)), ['#6E4529', '#5E3A24'], cell=9)
    fire = ball(M, (hx, 1.4, rz0 + 0.6), 0.9, 1.3) & (Y >= 0.8)
    P.fill(fire, EMBER, glow=0.3, cell=0.5)
    P.fill(ball(M, (hx, 1.1, rz0 + 0.6), 0.4, 1.2) & (Y >= 0.8), ['#FFE6A0'], glow=0.45, cell=9)
    S.lights.append({'type': 'point', 'pos': (hx, 1.6, rz0 + 1.6), 'power': 12.0, 'color': 2100, 'radius': 1.0})
    P.fill(box(M, (hx - 3.6, 5.6, rz0 - WALL_T), (hx + 3.6, 6.0, rz0 + 1.8)), WALNUT, cell=(9, 9, 9))       # the mantel
    P.fill(cyl_y(M, (hx - 2.2, rz0 + 0.8), 0.25, 6.0, 7.2), LINEN, cell=9)                              # a candle
    P.fill(ball(M, (hx - 2.2, 7.4, rz0 + 0.8), 0.25), ['#FFE08A'], glow=0.5, cell=9)
    S.lights.append({'type': 'point', 'pos': (hx - 2.2, 7.4, rz0 + 1.2), 'power': 3.0, 'color': 2300, 'radius': 0.3})
    P.fill(ball(M, (hx + 2.0, 6.7, rz0 + 0.8), 0.6, 1.25) & (Y >= 6.0), ['#C9B6E8', '#B8A0E0'], cell=9)   # the egg stone
    P.fill(box(M, (hx + 3.6, 0, rz0 + 0.2), (hx + 3.9, 2.8, rz0 + 0.5)), IRON, cell=9)                   # fire irons
    P.fill(box(M, (hx + 4.0, 0, rz0 + 0.2), (hx + 4.3, 2.4, rz0 + 0.5)), IRON, cell=9)
    # candle sconces on the back wall either side
    for sx in (-4.4, 4.4):
        P.fill(box(M, (hx + sx - 0.4, 3.9, rz0 - 0.1), (hx + sx + 0.4, 4.1, rz0 + 0.6)), IRON, cell=9)
        P.fill(cyl_y(M, (hx + sx, rz0 + 0.35), 0.22, 4.1, 5.0), LINEN, cell=9)
        P.fill(ball(M, (hx + sx, 5.2, rz0 + 0.35), 0.22), ['#FFE08A'], glow=0.5, cell=9)
        S.lights.append({'type': 'point', 'pos': (hx + sx, 5.2, rz0 + 0.8), 'power': 4.0, 'color': 2300, 'radius': 0.3})

    # ---- the rug before the hearth, two cushions
    rr = ((X - 0.0) ** 2 / 5.2 ** 2 + (Z + 3.4) ** 2 / 3.3 ** 2)
    P.fill(ground & (rr <= 1.0) & (Y >= -0.3), RUG, cell=(0.5, 1, 0.5))
    P.fill(ground & (rr <= 1.0) & (rr > 0.78) & (Y >= -0.3), RUG_LT, cell=(0.5, 1, 0.5))
    P.fill(ground & (rr <= 0.36) & (Y >= -0.3), RUG_LT, cell=(0.5, 1, 0.5))
    P.fill(ground & (rr <= 0.36) & (rr > 0.22) & (Y >= -0.3), RUG, cell=(0.5, 1, 0.5))
    for (cx_, cz_, col) in ((-3.4, -1.2, ['#F5C4CF', '#F0B4C2']), (3.0, -5.6, ['#C9E6F5', '#B8DAEC'])):
        P.fill(ball(M, (cx_, 0.0, cz_), 1.1, 0.45) & (Y >= 0), col, cell=9)

    # ---- the kitchen: the stove and its hood, the counter with a pot, a bowl and a loaf, shelves of jars,
    # herbs hanging from a rail, a flour sack and a barrel
    sx_, sz_ = STOVE
    P.fill(box(M, (sx_ - 1.2, 0, sz_ - 2.0), (sx_ + 1.2, 3.0, sz_ + 2.0)), STONE, cell=(1.0, 0.7, 1.0))
    P.fill(box(M, (sx_ - 1.3, 3.0, sz_ - 2.1), (sx_ + 1.3, 3.3, sz_ + 2.1)), IRON, cell=9)                 # the top plate
    P.fill(box(M, (sx_ + 1.2, 0.6, sz_ - 1.0), (sx_ + 1.4, 2.2, sz_ + 1.0)), IRON, cell=9)                 # the oven door
    P.fill(box(M, (sx_ + 1.2, 1.0, sz_ - 0.6), (sx_ + 1.4, 1.8, sz_ + 0.6)), EMBER, glow=0.4, cell=9)       # the fire behind its grate
    S.lights.append({'type': 'point', 'pos': (sx_ + 2.0, 1.4, sz_), 'power': 5.0, 'color': 2000, 'radius': 0.5})
    hood = (X >= rx0) & (X < sx_ + 1.4 - (Y - 3.3) * 0.25) & (Y >= 4.2) & (Y < WALL_H) & (np.abs(Z - sz_) < 2.1 - (Y - 4.2) * 0.3)
    P.fill(hood, IRON, cell=(1.0, 0.5, 1.0))
    P.fill(cyl_y(M, (sx_ + 0.3, sz_ - 0.6), 0.9, 3.3, 4.3), COPPER, cell=9)                             # a pot on the stove
    P.fill(cyl_y(M, (sx_ + 0.3, sz_ - 0.6), 0.7, 4.1, 4.3), ['#D9B36A', '#C9A24A'], cell=9)
    P.fill(cyl_y(M, (sx_ + 0.2, sz_ + 1.0), 0.55, 3.3, 3.8), IRON, cell=9)                               # a kettle
    cx0, cx1, cz0, cz1 = COUNTER
    P.fill(box(M, (cx0, 0, cz0), (cx1, 2.4, cz1)), WALNUT, cell=(9, 0.8, 1.2))
    P.fill(box(M, (cx0 - 0.1, 2.4, cz0 - 0.1), (cx1 + 0.2, 2.7, cz1 + 0.1)), OAK, cell=(9, 9, 0.6))
    P.fill(box(M, (cx0 + 0.3, 0.9, cz0 + 0.4), (cx1 - 0.3, 1.0, cz1 - 0.4)) & ((Z - cz0) % 2.0 < 0.1), HONEY, cell=9)   # drawer lines
    P.fill(cyl_y(M, (cx1 - 0.9, cz0 + 1.2), 0.7, 2.7, 3.1), ['#F5A3B5', '#F8B9C6'], cell=9)              # a bowl
    P.fill(ball(M, (cx1 - 1.0, 3.1, cz0 + 3.2), 0.7, 0.6) & (Y >= 2.7), ['#D9A05A', '#C98E4A'], cell=9)   # a loaf
    P.fill(box(M, (cx0 + 0.3, 2.7, cz1 - 1.8), (cx1 - 0.3, 2.85, cz1 - 0.3)), HONEY, cell=9)             # a board
    for k in range(3):                                                                               # carrots
        P.fill(box(M, (cx0 + 0.5 + k * 0.5, 2.85, cz1 - 1.6), (cx0 + 0.8 + k * 0.5, 3.05, cz1 - 0.5)), ['#F08A3A'], cell=9)
    for (sy, zs) in ((4.3, (-2.0, 4.4)), (5.6, (-2.0, 4.4))):                                           # the shelves and their jars
        P.fill(box(M, (rx0, sy, zs[0]), (rx0 + 1.3, sy + 0.25, zs[1])), WALNUT, cell=9)
        for k, jz in enumerate(np.arange(zs[0] + 0.7, zs[1] - 0.4, 1.1)):
            cols = (GLASS_AMBER, GLASS_ROSE, GLASS_MINT, ['#C98B6B', '#BF7F60'], PARCH)[(k + int(sy)) % 5]
            _jar(P, M, rx0 + 0.65, sy + 0.25, jz, 0.38, 0.7 + 0.2 * (k % 2), cols)
    P.fill(box(M, (rx0, 6.3, -2.4), (rx0 + 1.2, 6.5, -1.4)), IRON, cell=9)                             # the herb rail
    for k, hz_ in enumerate((-1.2, -0.2, 0.9, 1.9)):
        P.fill(box(M, (rx0 + 0.6, 5.2, hz_ - 0.1), (rx0 + 0.8, 6.4, hz_ + 0.1)), ['#8D5D3B'], cell=9)
        P.fill(ball(M, (rx0 + 0.7, 5.0, hz_), 0.55, 1.3) & (Y < 5.6), [['#5E9646', '#6FA552'], ['#7F9871', '#86C56A'], ['#C9A24A', '#D9B36A'], ['#F5A3B5', '#E8E0FF']][k], cell=9)
    P.fill(cyl_y(M, (rx0 + 1.4, 6.6), 1.0, 0, 2.2), WALNUT, cell=(9, 0.5, 9))                           # a barrel
    P.fill(cyl_y(M, (rx0 + 1.4, 6.6), 1.05, 0.5, 0.7) | cyl_y(M, (rx0 + 1.4, 6.6), 1.05, 1.6, 1.8), IRON, cell=9)
    P.fill(ball(M, (rx0 + 1.6, 0.7, 8.8), 1.0, 0.8) & (Y >= 0), LINEN, cell=9)                           # a flour sack
    P.fill(box(M, (rx0 + 1.3, 1.3, 8.6), (rx0 + 1.9, 1.7, 9.0)), ['#C9A24A'], cell=9)

    # ---- the apothecary: a cauldron on a tripod over embers, its brew glowing; shelves of bottles; a
    # worktable with a mortar, an open book and a candle; bunches of dried flowers hanging
    kx, kz = CAULDRON
    for a in (0.5, 2.6, 4.7):
        P.fill(box(M, (kx + 1.3 * math.cos(a) - 0.18, 0, kz + 1.3 * math.sin(a) - 0.18), (kx + 1.3 * math.cos(a) + 0.18, 1.5, kz + 1.3 * math.sin(a) + 0.18)), IRON, cell=9)
    P.fill(ball(M, (kx, 0.5, kz), 0.9, 0.5) & (Y >= 0), EMBER, glow=0.35, cell=0.5)
    P.fill((ball(M, (kx, 2.3, kz), 1.6, 0.85) & ~ball(M, (kx, 2.3, kz), 1.3, 0.85)) & (Y >= 1.2) & (Y < 3.0), IRON, cell=9)
    P.fill(cyl_y(M, (kx, kz), 1.75, 2.8, 3.1), IRON, cell=9)
    P.fill(cyl_y(M, (kx, kz), 1.3, 2.6, 2.9), PLUM, glow=0.4, cell=0.5)                                   # the brew
    P.fill(cyl_y(M, (kx, kz), 1.3, 2.6, 2.9) & hashmask(M, 0.3, seed=11, cell=0.5), TEAL, glow=0.55, cell=9)
    S.lights.append({'type': 'point', 'pos': (kx, 3.6, kz), 'power': 7.0, 'color': (0.72, 0.56, 1.0), 'radius': 0.9})
    S.lights.append({'type': 'point', 'pos': (kx, 0.9, kz + 1.0), 'power': 5.0, 'color': 2000, 'radius': 0.5})
    P.fill(box(M, (kx - 0.2, 3.1, kz - 0.2), (kx + 0.2, WALL_H - 0.6, kz + 0.2)) & (np.abs(Y % 0.8 - 0.4) < 0.25), IRON, cell=9)   # the chain
    for (sy, zs) in ((3.6, (-8.6, -1.6)), (5.0, (-8.6, -1.6)), (6.2, (-8.6, -3.6))):
        P.fill(box(M, (rx1 - 1.3, sy, zs[0]), (rx1, sy + 0.25, zs[1])), WALNUT, cell=9)
        for k, jz in enumerate(np.arange(zs[0] + 0.6, zs[1] - 0.3, 0.95)):
            cols, gl = ((GLASS_MINT, 0.35), (PLUM, 0.45), (GLASS_ROSE, None), (TEAL, 0.5), (GLASS_AMBER, None), (['#5E7A9C', '#6C8AAE'], None))[(k + int(sy * 2)) % 6]
            _jar(P, M, rx1 - 0.65, sy + 0.25, jz, 0.3, 0.55 + 0.25 * (k % 3), cols, glow=gl)
    S.lights.append({'type': 'point', 'pos': (rx1 - 1.2, 5.0, -5.0), 'power': 4.0, 'color': (0.62, 0.94, 0.85), 'radius': 1.2})
    wx0, wx1, wz0, wz1 = WORKTABLE
    P.fill(box(M, (wx0 + 0.2, 0, wz0 + 0.2), (wx0 + 0.6, 2.2, wz0 + 0.6)) | box(M, (wx0 + 0.2, 0, wz1 - 0.6), (wx0 + 0.6, 2.2, wz1 - 0.2)) |
           box(M, (wx1 - 0.6, 0, wz0 + 0.2), (wx1 - 0.2, 2.2, wz0 + 0.6)) | box(M, (wx1 - 0.6, 0, wz1 - 0.6), (wx1 - 0.2, 2.2, wz1 - 0.2)), WALNUT, cell=9)
    P.fill(box(M, (wx0, 2.2, wz0), (wx1, 2.5, wz1)), OAK, cell=(9, 9, 0.6))
    P.fill(cyl_y(M, (wx0 + 0.9, wz0 + 1.0), 0.6, 2.5, 3.1), STONE_LT, cell=9)                             # the mortar
    P.fill(box(M, (wx0 + 0.7, 3.0, wz0 + 0.9), (wx0 + 1.5, 3.2, wz0 + 1.1)), WALNUT, cell=9)
    P.fill(box(M, (wx0 + 0.3, 2.5, wz1 - 2.0), (wx0 + 1.9, 2.65, wz1 - 0.6)), PARCH, cell=9)             # an open book
    P.fill(box(M, (wx0 + 1.05, 2.5, wz1 - 2.0), (wx0 + 1.15, 2.7, wz1 - 0.6)), ['#8D5D3B'], cell=9)
    P.fill(cyl_y(M, (wx1 - 0.6, wz0 + 0.8), 0.22, 2.5, 3.5), LINEN, cell=9)                              # a candle
    P.fill(ball(M, (wx1 - 0.6, 3.7, wz0 + 0.8), 0.22), ['#FFE08A'], glow=0.5, cell=9)
    S.lights.append({'type': 'point', 'pos': (wx1 - 0.9, 3.7, wz0 + 0.8), 'power': 3.5, 'color': 2300, 'radius': 0.3})
    for k, jz in enumerate((wz0 + 2.3, wz0 + 3.0)):
        _jar(P, M, wx1 - 0.7, 2.5, jz, 0.28, 0.6, (PLUM, TEAL)[k], glow=0.4)
    P.fill(box(M, (rx1 - 1.2, 6.3, 0.0), (rx1, 6.5, 1.0)), IRON, cell=9)                                # dried flowers hanging
    for k, hz_ in enumerate((0.2, 0.8)):
        P.fill(box(M, (rx1 - 0.7, 5.3, hz_ - 0.1), (rx1 - 0.5, 6.4, hz_ + 0.1)), ['#8D5D3B'], cell=9)
        P.fill(ball(M, (rx1 - 0.6, 5.1, hz_), 0.5, 1.2) & (Y < 5.6), [['#B8A0E0', '#C9B6E8'], ['#F5A3B5', '#F4C04E']][k], cell=9)

    # ---- the bed: a round basket with a blanket and a pillow, a little rug beside it, a lantern on a stool
    bx, bz = BED
    br = np.sqrt((X - bx) ** 2 + (Z - bz) ** 2)
    P.fill((np.sqrt((br - 2.4) ** 2 + (Y - 0.6) ** 2) <= 0.7) & (Y >= 0), ['#C9A24A', '#D4AE4E', '#B8923E'], cell=0.5)
    P.fill((br < 1.9) & (Y >= 0) & (Y < 0.5), LINEN, cell=0.5)
    P.fill((br < 1.9) & (Y >= 0.3) & (Y < 0.5) & ((np.floor((X - bx) / 0.8) + np.floor((Z - bz) / 0.8)) % 2 == 0), ['#C9E6F5'], cell=9)
    P.fill(ball(M, (bx - 0.8, 0.7, bz - 0.9), 0.8, 0.5) & (Y >= 0.3), ['#FFFDF6', '#F7F1E4'], cell=0.5)
    P.fill(box(M, (bx + 3.0, 0, bz - 0.5), (bx + 4.0, 1.4, bz + 0.5)), WALNUT, cell=9)                   # the stool
    lantern(S, P, M, (bx + 3.5, 2.5, bz), s=0.45, lit=True, power=5.0)

    # ---- the writing desk and bookcase: skills are learned here
    dx0, dx1, dz0, dz1 = DESK
    P.fill(box(M, (dx0 + 0.2, 0, dz0 + 0.2), (dx0 + 0.6, 2.3, dz0 + 0.6)) | box(M, (dx1 - 0.6, 0, dz0 + 0.2), (dx1 - 0.2, 2.3, dz0 + 0.6)) |
           box(M, (dx0 + 0.2, 0, dz1 - 0.6), (dx0 + 0.6, 2.3, dz1 - 0.2)) | box(M, (dx1 - 0.6, 0, dz1 - 0.6), (dx1 - 0.2, 2.3, dz1 - 0.2)), WALNUT, cell=9)
    P.fill(box(M, (dx0, 2.3, dz0), (dx1, 2.6, dz1)), HONEY, cell=(9, 9, 0.6))
    P.fill(box(M, (dx0 + 0.6, 2.6, dz0 + 0.5), (dx0 + 2.2, 2.75, dz1 - 0.5)), PARCH, cell=9)             # an open book
    P.fill(box(M, (dx0 + 1.35, 2.6, dz0 + 0.5), (dx0 + 1.45, 2.8, dz1 - 0.5)), ['#8D5D3B'], cell=9)
    P.fill(cyl_y(M, (dx1 - 0.8, dz0 + 0.7), 0.3, 2.6, 3.1), ['#203B50'], cell=9)                          # the inkwell
    P.fill((np.abs(X - (dx1 - 0.8) - (Y - 3.1) * 0.25) < 0.1) & (np.abs(Z - dz0 - 0.7) < 0.1) & (Y >= 3.1) & (Y < 4.4), ['#FFFDF6'], cell=9)   # the quill
    P.fill(box(M, (dx0 + 0.8, 0, dz0 - 1.5), (dx0 + 1.8, 1.5, dz0 - 0.5)), WALNUT, cell=9)               # a stool, pushed in at its north side
    P.fill(box(M, (rx1 - 1.5, 0, 7.2), (rx1, 5.4, 9.6)), WALNUT, cell=(9, 1.3, 9))                        # the bookcase
    for sy in (0.4, 1.7, 3.0, 4.3):
        P.fill(box(M, (rx1 - 1.3, sy, 7.4), (rx1 - 0.1, sy + 0.1, 9.4)), HONEY, cell=9)
        for k, bz_ in enumerate(np.arange(7.5, 9.3, 0.3)):
            if rng.random() < 0.15:
                continue
            P.fill(box(M, (rx1 - 1.2, sy + 0.1, bz_), (rx1 - 0.25, sy + 0.9 + 0.2 * (k % 3), bz_ + 0.26)), [BOOKS[(k + int(sy * 3)) % len(BOOKS)]], cell=9)

    # ---- a low round table with a teapot and cups, a potted fern by the door, a lantern by the door
    tx, tz = TABLE
    P.fill(cyl_y(M, (tx, tz), 0.35, 0, 1.6), WALNUT, cell=9)
    P.fill(cyl_y(M, (tx, tz), 1.5, 1.6, 1.85), HONEY, cell=9)
    P.fill(ball(M, (tx - 0.3, 2.4, tz - 0.2), 0.55) & (Y >= 1.85), ['#7FA8C8', '#6E98B8'], cell=9)        # the teapot
    P.fill(box(M, (tx + 0.2, 2.3, tz - 0.3), (tx + 0.7, 2.45, tz - 0.1)), ['#7FA8C8'], cell=9)
    P.fill(cyl_y(M, (tx - 0.25, tz - 0.2), 0.12, 2.9, 3.4), ['#6E98B8'], cell=9)
    for (ux, uz) in ((tx + 0.8, tz + 0.6), (tx - 0.9, tz + 0.7)):
        P.fill(cyl_y(M, (ux, uz), 0.28, 1.85, 2.3), ['#F5C4CF'], cell=9)
    P.fill(cyl_y(M, (-3.6, 8.6), 0.8, 0, 1.3), ['#C98B6B', '#BF7F60'], cell=9)                           # the fern's pot
    P.fill(ball(M, (-3.6, 2.0, 8.6), 1.3, 0.75) & (Y >= 1.2), ['#5E9646', '#6FA552', '#4F9C3E'], cell=0.5)
    lantern(S, P, M, (6.6, 3.8, rz1 - 0.8), s=0.5, lit=True, power=7.0, hang_to=None)
    P.fill(box(M, (6.45, 0, rz1 - 0.95), (6.75, 2.9, rz1 - 0.65)), IRON, cell=9)

    S.models.append((M, (), {}))
    S.grade = {'bloom': 0.14, 'vignette': 0.08}
    return S


# the walking camera's view of the room (2x: 45.8 px a unit)
VW.VIEWS['cottage'] = ((0.0, -1.2), 30.0, (1374, 1000))

if __name__ == '__main__':
    import json

    import village_scenes as VSC
    args = sys.argv[1:]
    out = args[0]
    quick = '--quick' in args
    os.makedirs(out, exist_ok=True)
    vs = scene_cottage_walk()
    if '--depth' in args:
        VW.render_ortho(vs, 'cottage', os.path.join(out, 'village_walk_cottage_depth.exr'), quick, depth=True)
        sys.exit(0)
    raw = os.path.join(out, 'village_walk_cottage_raw.png')
    proj = VW.render_ortho(vs, 'cottage', raw, quick)
    VSC.finish(vs, raw, os.path.join(out, 'village_walk_cottage.png'), quick)
    json.dump(proj, open(os.path.join(out, 'village_walk_cottage.json'), 'w'), indent=1)

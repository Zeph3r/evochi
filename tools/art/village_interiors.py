"""Inside the village's three houses, laid out to walk through (the walking camera, the front wall and
roof left off as in cottage_walk.py): Bram's Workshop (the forge, the anvil, his lantern wall), Mira's
Glasshouse (glass walls, raised beds down two aisles, her potting bench) and the Guild Lodge (the long
table, the notice board, Alder's desk, the fire). The villagers walk their rooms (village_walk.dart's
routines); the door in the front leads back out to the Square.

    python3 village_interiors.py OUT lodge|glasshouse|workshop [--quick] [--depth]

World: x east, z toward you, y up. ROOM is the same for all three (so the camera is too).
"""
import math
import os
import sys

import numpy as np

import village_walk as VW
from home_scenes import GRAVEL, SOIL, hashmask, soil_plot, sprouts, tuft
from village_scenes import (BRASS, BRICK, CLEAR_GLASS, COBBLE, COPPER, CPainter, GLASS_AMBER, GLASS_MINT, GLASS_ROSE, HONEY, IRON, LEAF, NAVY,
                            OAK, PARCH, PLASTER, SAGE, STONE, STONE_LT, TERRACOTTA, VScene, WALNUT, WATERC, WIN_DAY, ball, barrel, box, crate,
                            cyl_y, flower_patch, lantern)
from voxel import Model

X0, X1, Z0, Z1 = -16.0, 16.0, -14.0, 14.0
ROOM = (-12.0, 12.0, -10.0, 10.0)
WALL_T, DOOR_W = 0.8, 4.2
EMBER = ['#FF9A3C', '#FFC561', '#FF6A2A']
LINEN = ['#FBF5E8', '#F1E6CF']
CORK = ['#C9A676', '#BE9A6A', '#D2B084']
RUG = ['#5E7A9C', '#54708F', '#6C8AAE']
RUG_LT = ['#C9C2AE', '#D3CCB9']
ORE_COPPER = ['#C9874E', '#8E5A33', '#D9985E']
ORE_IRON = ['#7A8088', '#5E666E', '#9099A2']

# where the stations stand (the pack and the villagers' routines use them)
ANVIL = (-3.0, -3.5)
FORGE = (-6.0, -10.0)          # the hearth's middle, in the back wall
BENCH_W = (9.6, 11.6, -8.5, -0.5)   # Bram's workbench along the east wall: x0, x1, z0, z1
POT_BENCH = (-6.0, 6.0, -9.2, -7.6)  # Mira's potting bench along the back wall
BEDS_G = [(-10.5, -3.0, -4.4, -1.8), (-10.5, -3.0, 1.4, 4.0), (3.0, 10.5, -4.4, -1.8), (3.0, 10.5, 1.4, 4.0)]
TABLE_L = (-9.5, -1.5, -3.0, -0.6)   # the Lodge's long table
DESK_L = (3.0, 9.0, -8.6, -6.6)      # Alder's desk, by the back wall
BOARD_L = (-9.0, -1.5)               # the notice board on the back wall: x0, x1
FIRE_L = (12.0, -1.0)                # the fireplace in the east wall: its middle z
MAP_TABLE = (6.0, 2.0)


class Room:
    """The shell every house shares: a floor, three walls (plaster, brick or glass), the knee-high sill
    in front with the doorway and its step; windows where asked."""

    def __init__(self, name, sky, world=((0.98, 0.9, 0.78), 0.55), sun=(0.3, -0.72, -0.62), sun_power=1.6):
        self.S = VScene(name, 1374, 1000, {}, world=world, samples=96, transparent=True, sky=sky)
        self.S.lights.append({'type': 'sun', 'dir': sun, 'power': sun_power, 'color': 4600, 'angle': 6.0})
        self.M = Model((X0, -4, Z0), (X1, 14, Z1), [], res=2)
        self.P = CPainter(self.M, 17)
        self.X, self.Y, self.Z = self.M.X, self.M.Y, self.M.Z
        rx0, rx1, rz0, rz1 = ROOM
        self.inside = (self.X >= rx0) & (self.X < rx1) & (self.Z >= rz0) & (self.Z < rz1)
        self.ground = (self.Y >= -1) & (self.Y < 0)
        self.glass = []

    def floor(self, cols, cell=(3.0, 1, 0.6), seams=None):
        P, M = self.P, self.M
        P.fill(self.ground & self.inside, cols, cell=cell)
        if seams:
            P.fill(self.ground & self.inside & ((self.Z % cell[2]) < 0.08), seams, cell=9)

    def walls(self, cols, h=7.0, footing=STONE, posts=WALNUT, post_every=6.0, plate=True, cell=(2.0, 2.0, 2.0), glass=False):
        P, M, X, Y, Z = self.P, self.M, self.X, self.Y, self.Z
        rx0, rx1, rz0, rz1 = ROOM
        back = box(M, (rx0 - WALL_T, 0, rz0 - WALL_T), (rx1 + WALL_T, h, rz0))
        west = box(M, (rx0 - WALL_T, 0, rz0 - WALL_T), (rx0, h, rz1 + WALL_T))
        east = box(M, (rx1, 0, rz0 - WALL_T), (rx1 + WALL_T, h, rz1 + WALL_T))
        self.wall = back | west | east
        self.h = h
        if glass:
            P.fill(self.wall, CLEAR_GLASS, cell=50)
            self.glass = list(CLEAR_GLASS)
            P.fill(self.wall & (Y < 1.6), footing, cell=(1.0, 0.6, 1.0))
            frame = (((X - rx0) % 3.0) < 0.5) | (((Z - rz0) % 3.0) < 0.5) | (np.abs(Y - 4.4) < 0.25) | (Y >= h - 0.5)
            P.fill(self.wall & frame & (Y >= 1.6), posts, cell=9)
        else:
            P.fill(self.wall, cols, cell=cell)
            P.fill(self.wall & (Y < 1.2), footing, cell=(1.0, 0.6, 1.0))
            if posts is not None:
                for px in np.arange(rx0, rx1 + 0.1, post_every):
                    P.fill(back & (np.abs(X - px) < 0.35), posts, cell=9)
                for pz in np.arange(rz0, rz1 + 0.1, post_every * 5 / 6):
                    P.fill((west | east) & (np.abs(Z - pz) < 0.35), posts, cell=9)
                if plate:
                    P.fill(self.wall & (Y >= h - 0.6), posts, cell=9)
        # the front: a knee-high sill with the doorway, its threshold and step
        sill = box(M, (rx0 - WALL_T, 0, rz1), (rx1 + WALL_T, 0.7, rz1 + WALL_T)) & ~box(M, (-DOOR_W / 2, 0, rz1 - 1), (DOOR_W / 2, 2, rz1 + 2))
        P.fill(sill, footing, cell=(1.0, 0.6, 1.0))
        for sx in (-1, 1):
            P.fill(box(M, (sx * DOOR_W / 2 - 0.5, 0, rz1 - 0.2), (sx * DOOR_W / 2 + 0.5, 0.85, rz1 + WALL_T + 0.2)), STONE_LT, cell=(0.6, 0.4, 0.6))
        P.fill(box(M, (-DOOR_W / 2, -1, rz1), (DOOR_W / 2, 0.0, rz1 + WALL_T)), STONE_LT, cell=(1.5, 1, 1.5))
        P.fill(box(M, (-DOOR_W / 2 - 0.6, -1, rz1 + WALL_T), (DOOR_W / 2 + 0.6, 0.3, rz1 + 2.4)), STONE_LT, cell=(1.5, 1, 1.5))
        P.fill(box(M, (-3.4, -1, rz1 + WALL_T), (3.4, 0, rz1 + 3.6)), COBBLE, cell=(1.0, 1, 1.0))

    def window(self, cx, cy, w, h, face, round_=False, light=4.0):
        P, M, X, Y, Z = self.P, self.M, self.X, self.Y, self.Z
        rx0, rx1, rz0, rz1 = ROOM
        if face == 'back':
            plane = (Z >= rz0 - WALL_T) & (Z < rz0)
            u, v = X - cx, Y - cy
            lp = (cx, cy, rz0 + 0.6)
        elif face == 'west':
            plane = (X >= rx0 - WALL_T) & (X < rx0)
            u, v = Z - cx, Y - cy
            lp = (rx0 + 0.6, cy, cx)
        else:
            plane = (X >= rx1) & (X < rx1 + WALL_T)
            u, v = Z - cx, Y - cy
            lp = (rx1 - 0.6, cy, cx)
        if round_:
            pane = plane & ((u / (w / 2)) ** 2 + (v / (h / 2)) ** 2 <= 1.0)
            frame = plane & ((u / (w / 2 + 0.5)) ** 2 + (v / (h / 2 + 0.5)) ** 2 <= 1.0) & ~pane
        else:
            pane = plane & (np.abs(u) <= w / 2) & (np.abs(v) <= h / 2)
            frame = plane & (np.abs(u) <= w / 2 + 0.5) & (np.abs(v) <= h / 2 + 0.5) & ~pane
        P.fill(frame, WALNUT, cell=9)
        P.fill(pane, WIN_DAY, glow=0.08, cell=9)
        P.fill(pane & ((np.abs(u) < 0.2) | (np.abs(v) < 0.2)), WALNUT, cell=9)
        self.S.lights.append({'type': 'point', 'pos': lp, 'power': light, 'color': 6200, 'radius': 1.0})

    def candle(self, x, y, z, power=3.0):
        P, M = self.P, self.M
        P.fill(cyl_y(M, (x, z), 0.22, y, y + 0.9), LINEN, cell=9)
        P.fill(ball(M, (x, y + 1.1, z), 0.22), ['#FFE08A'], glow=0.5, cell=9)
        self.S.lights.append({'type': 'point', 'pos': (x, y + 1.1, z + 0.4), 'power': power, 'color': 2300, 'radius': 0.3})

    def jar(self, x, y, z, r, h, cols, glow=None):
        P, M = self.P, self.M
        P.fill(cyl_y(M, (x, z), r, y, y + h), cols, glow=glow, cell=9)
        P.fill(cyl_y(M, (x, z), r * 0.55, y + h, y + h + 0.35), WALNUT, cell=9)

    def done(self, grade=None):
        self.S.models.append((self.M, tuple(self.glass), {'water': WATERC}))
        self.S.grade = grade or {'bloom': 0.14, 'vignette': 0.08}
        return self.S


# ----------------------------------------------------------------------------------- Bram's Workshop
def scene_workshop():
    R = Room('workshop_walk', ('#2A1C16', '#1C120E'), world=((0.95, 0.82, 0.7), 0.5))
    P, M, X, Y, Z = R.P, R.M, R.X, R.Y, R.Z
    rng = np.random.default_rng(42)
    rx0, rx1, rz0, rz1 = ROOM
    R.floor(COBBLE, cell=(1.0, 1, 1.0))
    P.fill(R.ground & R.inside & hashmask(M, 0.08, seed=3, cell=1.0), ['#8E887E'], cell=9)
    R.walls(BRICK, h=7.0, footing=STONE, posts=WALNUT, post_every=8.0, cell=(2.0, 1.0, 2.0))
    P.fill(R.wall & ((Y % 1.0) < 0.12) & (Y >= 1.2) & (Y < 6.4), ['#D8C6A8'], cell=9)   # mortar lines
    R.window(5.5, 4.4, 2.6, 2.2, 'back')
    R.window(5.0, 4.2, 2.4, 2.2, 'west')
    # ---- the forge: a brick hearth in the back wall, coals, a chimney hood, the bellows beside it
    fx_, fz_ = FORGE
    P.fill(box(M, (fx_ - 3.4, 0, rz0 - WALL_T), (fx_ + 3.4, 7.0, rz0 + 2.2)), BRICK, cell=(1.0, 0.5, 1.0))
    P.fill(box(M, (fx_ - 3.4, 0, rz0 - WALL_T), (fx_ + 3.4, 7.0, rz0 + 2.2)) & ((Y % 1.0) < 0.12), ['#D8C6A8'], cell=9)
    mouth = box(M, (fx_ - 2.2, 1.2, rz0 - 0.3), (fx_ + 2.2, 4.0, rz0 + 2.3))
    M.m[mouth] = 0
    P.fill(box(M, (fx_ - 2.2, 1.2, rz0 - 0.3), (fx_ + 2.2, 4.0, rz0)), ['#2B211D', '#231B18'], cell=9)
    P.fill(box(M, (fx_ - 2.2, 1.2, rz0 - 0.3), (fx_ + 2.2, 1.4, rz0 + 2.3)), ['#2B211D'], cell=9)
    coals = ball(M, (fx_, 1.6, rz0 + 1.0), 1.5, 0.45) & (Y >= 1.4)
    P.fill(coals, EMBER, glow=0.4, cell=0.5)
    P.fill(coals & hashmask(M, 0.35, seed=5, cell=0.5), ['#3A2A22', '#2B211D'], cell=9)
    P.fill(ball(M, (fx_, 1.6, rz0 + 1.0), 0.6, 0.5) & (Y >= 1.4), ['#FFE6A0'], glow=0.6, cell=9)
    R.S.lights.append({'type': 'point', 'pos': (fx_, 2.4, rz0 + 2.0), 'power': 18.0, 'color': 1900, 'radius': 1.2})
    hood = (np.abs(X - fx_) < 3.0 - (Y - 4.0) * 0.45) & (Y >= 4.0) & (Y < 7.0) & (Z >= rz0 - 0.3) & (Z < rz0 + 2.4 - (Y - 4.0) * 0.5)
    P.fill(hood, IRON, cell=(1.0, 0.5, 1.0))
    P.fill(box(M, (fx_ + 2.6, 1.0, rz0 + 2.4), (fx_ + 4.8, 1.3, rz0 + 4.2)), WALNUT, cell=9)              # the bellows
    P.fill(box(M, (fx_ + 2.8, 1.3, rz0 + 2.6), (fx_ + 4.6, 2.4, rz0 + 4.0)), ['#8D5D3B', '#7E5133'], cell=(9, 0.4, 9))
    P.fill(box(M, (fx_ + 2.6, 2.4, rz0 + 2.4), (fx_ + 4.8, 2.7, rz0 + 4.2)), WALNUT, cell=9)
    P.fill(box(M, (fx_ + 4.8, 2.3, rz0 + 3.1), (fx_ + 6.4, 2.6, rz0 + 3.5)), WALNUT, cell=9)
    P.fill(box(M, (fx_ + 1.6, 1.8, rz0 + 3.0), (fx_ + 2.6, 2.2, rz0 + 3.6)), IRON, cell=9)
    P.fill(box(M, (fx_ - 0.6, 0, rz0 + 2.4), (fx_ + 0.6, 0.8, rz0 + 3.0)), IRON, cell=9)                   # a poker and tongs leant by it
    # ---- the anvil on its stump, the quench barrel, a rack of bars
    ax, az = ANVIL
    P.fill(cyl_y(M, (ax, az), 1.3, 0, 1.6), WALNUT, cell=(9, 0.4, 9))
    P.fill(box(M, (ax - 1.6, 1.6, az - 0.9), (ax + 1.9, 2.5, az + 0.9)), IRON, cell=9)
    P.fill(box(M, (ax - 0.9, 1.0, az - 0.6), (ax + 1.0, 1.6, az + 0.6)), IRON, cell=9)
    horn = ((Z - az) ** 2 + (Y - 2.2) ** 2 <= (0.55 - (X - ax - 1.9) * 0.3) ** 2) & (X >= ax + 1.9) & (X < ax + 3.4)
    P.fill(horn, IRON, cell=9)
    P.fill(box(M, (ax - 1.6, 2.5, az - 0.9), (ax + 1.9, 2.7, az + 0.9)), ['#6E7680', '#7A838C'], cell=9)
    P.fill(box(M, (ax - 0.3, 2.7, az - 0.25), (ax + 1.4, 3.0, az + 0.25)), ['#FF9A4A', '#FFC27A'], glow=0.5, cell=9)   # a bar, still hot
    P.fill(box(M, (ax - 1.4, 2.7, az + 1.2), (ax - 0.2, 3.0, az + 1.5)), WALNUT, cell=9)                             # the hammer laid by
    P.fill(box(M, (ax - 0.6, 2.6, az + 1.0), (ax - 0.1, 3.3, az + 1.7)), IRON, cell=9)
    barrel(P, M, ax + 4.4, az - 0.6, 1.2, 2.6)
    P.fill(cyl_y(M, (ax + 4.4, az - 0.6), 1.0, 2.3, 2.6), WATERC, cell=9)
    # ---- the workbench along the east wall, the vice, the tool wall above it
    wx0, wx1, wz0, wz1 = BENCH_W
    P.fill(box(M, (wx0, 0, wz0), (wx1, 2.4, wz1)), WALNUT, cell=(9, 0.8, 1.2))
    P.fill(box(M, (wx0 - 0.2, 2.4, wz0 - 0.1), (wx1, 2.7, wz1 + 0.1)), OAK, cell=(9, 9, 0.6))
    P.fill(box(M, (wx0 - 0.4, 2.7, wz1 - 2.4), (wx0 + 0.8, 3.6, wz1 - 1.4)), IRON, cell=9)                     # the vice
    P.fill(box(M, (wx0 - 0.9, 3.0, wz1 - 2.0), (wx0 - 0.4, 3.2, wz1 - 1.8)), IRON, cell=9)
    for k, (bz_, col) in enumerate(((wz0 + 1.0, ORE_COPPER), (wz0 + 2.2, ORE_IRON), (wz0 + 3.3, ORE_COPPER))):   # bars and bits on the bench
        P.fill(box(M, (wx0 + 0.3, 2.7, bz_), (wx1 - 0.5, 2.95, bz_ + 0.5)), col, cell=9)
    P.fill(ball(M, (wx1 - 0.7, 3.0, wz0 + 4.6), 0.5), ORE_IRON, cell=9)
    for k, tz_ in enumerate(np.arange(wz0 + 0.6, wz1 - 0.2, 1.3)):                                               # hammers and tongs on hooks
        P.fill(box(M, (rx1 - 0.25, 3.6, tz_ - 0.12), (rx1, 5.6, tz_ + 0.12)), WALNUT, cell=9)
        if k % 2 == 0:
            P.fill(box(M, (rx1 - 0.6, 5.3, tz_ - 0.5), (rx1, 5.9, tz_ + 0.5)), IRON, cell=9)
        else:
            P.fill(box(M, (rx1 - 0.35, 3.3, tz_ - 0.3), (rx1, 3.9, tz_ + 0.3)), IRON, cell=9)
    P.fill(box(M, (rx1 - 1.2, 6.1, wz0), (rx1, 6.3, wz1)), WALNUT, cell=9)                                     # a shelf of oil cans
    for k, sz_ in enumerate(np.arange(wz0 + 0.6, wz1 - 0.3, 1.5)):
        R.jar(rx1 - 0.6, 6.3, sz_, 0.32, 0.7, (COPPER, IRON, BRASS)[k % 3])
    # ---- the grindstone, crates of ore by the west wall, coal sacks
    gx, gz = 7.5, 5.5
    P.fill(box(M, (gx - 1.0, 0, gz - 0.5), (gx + 1.0, 1.4, gz + 0.5)), WALNUT, cell=9)
    P.fill(((X - gx) ** 2 + (Y - 2.2) ** 2 <= 1.3 ** 2) & (np.abs(Z - gz) < 0.35), STONE, cell=(0.5, 0.5, 9))
    P.fill(((X - gx) ** 2 + (Y - 2.2) ** 2 <= 0.25 ** 2) & (np.abs(Z - gz) < 0.6), IRON, cell=9)
    for (cx_, cz_, s_, ore) in ((rx0 + 1.8, 3.2, 1.0, ORE_COPPER), (rx0 + 1.6, 5.8, 0.9, ORE_IRON), (rx0 + 4.0, 4.4, 0.8, ORE_COPPER)):
        crate(P, M, cx_, cz_, s_)
        for k in range(4):
            P.fill(ball(M, (cx_ + (rng.random() - 0.5) * s_, 1.0 * s_ * 2 + 0.3, cz_ + (rng.random() - 0.5) * s_), 0.4 + 0.15 * (k % 2)), ore, cell=9)
    for (sx_, sz_) in ((rx0 + 1.6, 8.6), (rx0 + 3.4, 8.9)):
        P.fill(ball(M, (sx_, 0.7, sz_), 1.0, 0.8) & (Y >= 0), ['#4A4040', '#3F3535'], cell=9)
    # ---- the lantern wall: Bram's finished lanterns on hooks along the back wall east of the forge
    for k, lx in enumerate(np.arange(0.5, 9.5, 1.8)):
        if 4.0 < lx < 7.0:
            continue   # the window
        P.fill(box(M, (lx - 0.15, 5.4, rz0 - 0.1), (lx + 0.15, 6.0, rz0 + 0.4)), IRON, cell=9)
        lantern(R.S, P, M, (lx, 4.6, rz0 + 0.7), s=0.4, lit=(k % 2 == 0), glass=(GLASS_AMBER, GLASS_MINT, GLASS_ROSE)[k % 3], power=3.0)
    P.fill(box(M, (rx1 - 2.2, 0, rz0 + 0.4), (rx1 - 0.2, 2.6, rz0 + 1.6)), WALNUT, cell=9)                   # a chest of fittings
    P.fill(box(M, (rx1 - 2.3, 2.6, rz0 + 0.3), (rx1 - 0.1, 2.9, rz0 + 1.7)), ['#8D5D3B'], cell=9)
    P.fill(box(M, (rx1 - 1.3, 1.6, rz0 + 1.6), (rx1 - 1.1, 2.0, rz0 + 1.75)), BRASS, cell=9)
    # a rag rug by the door, a stool, and the lantern on its post by the door
    rr = ((X - 0.0) ** 2 / 3.0 ** 2 + (Z - 6.2) ** 2 / 1.6 ** 2)
    P.fill(R.ground & (rr <= 1.0) & (Y >= -0.3), ['#8E5A33', '#7E5133', '#A97C4B'], cell=(0.5, 1, 0.5))
    P.fill(box(M, (-7.4, 0, -1.2), (-6.4, 1.4, -0.2)), WALNUT, cell=9)
    lantern(R.S, P, M, (6.6, 3.8, rz1 - 0.8), s=0.5, lit=True, power=7.0)
    P.fill(box(M, (6.45, 0, rz1 - 0.95), (6.75, 2.9, rz1 - 0.65)), IRON, cell=9)
    return R.done()


# ---------------------------------------------------------------------------------- Mira's Glasshouse
def scene_glasshouse():
    R = Room('glasshouse_walk', ('#2A2E22', '#1A1D15'), world=((0.9, 0.96, 0.9), 0.7), sun_power=2.2)
    P, M, X, Y, Z = R.P, R.M, R.X, R.Y, R.Z
    rng = np.random.default_rng(41)
    rx0, rx1, rz0, rz1 = ROOM
    # terracotta tiles, a gravel path down the middle and across
    R.floor(TERRACOTTA, cell=(1.2, 1, 1.2))
    P.fill(R.ground & R.inside & (((X % 1.2) < 0.1) | ((Z % 1.2) < 0.1)), ['#A86F55'], cell=9)
    path = (np.abs(X) < 2.2) | (np.abs(Z + 0.2) < 1.3) | (np.abs(Z - 6.2) < 1.2) | (np.abs(Z + 6.0) < 1.2)
    P.fill(R.ground & R.inside & path, GRAVEL, cell=(1.0, 1, 1.0))
    R.walls(None, h=7.0, footing=STONE_LT, posts=SAGE, glass=True)
    # the roof's beams (no roof: the beams carry the baskets)
    for bz_ in (-4.2, 2.4):
        P.fill(box(M, (rx0, 6.4, bz_ - 0.25), (rx1, 6.9, bz_ + 0.25)), SAGE, cell=9)
    # ---- the raised beds, two down each side, planted differently
    kinds = ['leafy', 'berry', 'sprout', 'wheat']
    for (bx0, bx1, bz0, bz1), kind in zip(BEDS_G, kinds):
        soil_plot(P, M, bx0, bx1, bz0, bz1, top=1.0)
        sprouts(P, M, bx0 + 0.4, bx1 - 0.4, bz0 + 0.4, bz1 - 0.4, 1.0, rng, kind)
    for (bx0, bx1, bz0, bz1) in BEDS_G:                                                        # the beds stand on brick
        P.fill(box(M, (bx0 - 0.2, 0, bz0 - 0.2), (bx1 + 0.2, 1.0, bz1 + 0.2)) & ~box(M, (bx0, 0, bz0), (bx1, 1.2, bz1)), BRICK, cell=(1.0, 0.5, 1.0))
    # ---- the potting bench along the back wall: pots, seed trays, a trowel, a watering can, jars of seed
    px0, px1, pz0, pz1 = POT_BENCH
    P.fill(box(M, (px0 + 0.2, 0, pz0 + 0.2), (px0 + 0.6, 2.4, pz1 - 0.2)) | box(M, (px1 - 0.6, 0, pz0 + 0.2), (px1 - 0.2, 2.4, pz1 - 0.2)) |
           box(M, ((px0 + px1) / 2 - 0.2, 0, pz0 + 0.2), ((px0 + px1) / 2 + 0.2, 2.4, pz1 - 0.2)), WALNUT, cell=9)
    P.fill(box(M, (px0, 2.4, pz0), (px1, 2.7, pz1)), OAK, cell=(9, 9, 0.6))
    P.fill(box(M, (px0 + 0.3, 1.0, pz0 + 0.3), (px1 - 0.3, 1.2, pz1 - 0.3)), OAK, cell=(9, 9, 0.6))      # a lower shelf
    for k, tx_ in enumerate(np.arange(px0 + 0.8, px1 - 0.6, 1.3)):
        if k % 3 == 2:
            P.fill(box(M, (tx_ - 0.5, 2.7, pz0 + 0.3), (tx_ + 0.5, 2.9, pz1 - 0.3)), WALNUT, cell=9)         # a seed tray
            for j in range(3):
                tuft(P, M, tx_ - 0.3 + 0.3 * j, pz0 + 0.8, 0.5, ['#5EA046'], y=2.9, r=0.1)
        else:
            P.fill(cyl_y(M, (tx_, (pz0 + pz1) / 2), 0.45, 2.7, 3.5), TERRACOTTA, cell=9)
            if k % 3 == 0:
                P.fill(ball(M, (tx_, 3.9, (pz0 + pz1) / 2), 0.55, 0.8), LEAF, cell=0.5)
                P.fill(ball(M, (tx_ + 0.2, 4.4, (pz0 + pz1) / 2), 0.25), [['#F5A3B5'], ['#F4C04E'], ['#E8E0FF']][k % 3], cell=9)
    for j, pz_ in enumerate(np.arange(px0 + 0.8, px1 - 0.6, 1.1)):                                     # pots stacked below
        P.fill(cyl_y(M, (pz_, (pz0 + pz1) / 2), 0.4, 1.2, 1.9), TERRACOTTA, cell=9)
    P.fill(cyl_y(M, (px1 + 1.4, pz0 + 0.8), 0.7, 0, 1.4), ['#7F9871', '#76906A'], cell=9)              # the watering can
    P.fill(box(M, (px1 + 1.4, 0.8, pz0 + 0.6), (px1 + 2.6, 1.0, pz0 + 1.0)), ['#7F9871'], cell=9)
    P.fill(box(M, (px1 + 0.9, 1.4, pz0 + 0.6), (px1 + 1.9, 1.6, pz0 + 1.0)), ['#7F9871'], cell=9)
    for k, sx_ in enumerate((px0 - 2.2, px0 - 1.4)):                                                    # sacks of soil
        P.fill(ball(M, (sx_, 0.7, pz0 + 1.0 + 0.6 * k), 0.8, 0.8) & (Y >= 0), ['#A8906E', '#9C8462'], cell=9)
    # ---- hanging baskets from the beams, climbing beans up the east wall, a bench, a birdbath
    for (hx_, hz_) in ((-7.0, -4.2), (-2.5, -4.2), (2.5, -4.2), (7.0, -4.2), (-8.0, 2.4), (0.0, 2.4), (8.0, 2.4)):
        P.fill(box(M, (hx_ - 0.1, 5.4, hz_ - 0.1), (hx_ + 0.1, 6.4, hz_ + 0.1)), IRON, cell=9)
        P.fill(ball(M, (hx_, 5.0, hz_), 0.9, 0.7) & (Y < 5.5), ['#A86F55', '#B97E62'], cell=9)
        P.fill(ball(M, (hx_, 5.3, hz_), 1.1, 0.8) & (Y >= 5.0) & (M.m == 0), LEAF, cell=0.5)
        for j in range(3):
            P.fill(ball(M, (hx_ + 0.7 * math.cos(j * 2.1), 5.6, hz_ + 0.7 * math.sin(j * 2.1)), 0.28), [['#F5A3B5', '#FF9E7A', '#FFFDF6'][(j + int(hx_)) % 3]], cell=9)
    for k in range(5):
        vine = (np.abs(Z - (3.0 + k * 1.2) - 0.5 * np.sin(Y * 1.3 + k)) < 0.3) & (X >= rx1 - 0.6) & (X < rx1 + 0.1) & (Y >= 1.6) & (Y < 6.2)
        P.fill(vine, ['#5EA046', '#4F9C3E', '#6FB24E'], cell=0.5)
        P.fill(box(M, (rx1 - 0.3, 2.0 + k * 0.8, 3.0 + k * 1.2 - 0.2), (rx1, 2.5 + k * 0.8, 3.0 + k * 1.2 + 0.2)), ['#E8513F'], cell=9)
    P.fill(box(M, (-10.6, 1.0, 6.6), (-7.0, 1.5, 7.8)), HONEY, cell=(1.5, 1, 9))                          # a bench by the door
    for lx in (-10.2, -7.9):
        P.fill(box(M, (lx, 0, 6.7), (lx + 0.5, 1.0, 7.7)), WALNUT)
    P.fill(cyl_y(M, (8.6, 7.8), 0.5, 0, 1.6) | cyl_y(M, (8.6, 7.8), 1.3, 1.6, 2.0), STONE, cell=9)         # the birdbath
    P.fill(cyl_y(M, (8.6, 7.8), 1.0, 1.75, 2.0), WATERC, cell=9)
    flower_patch(P, M, -8.5, 8.6, 1.6, 0.8, rng, n=5)
    flower_patch(P, M, 5.0, 8.6, 1.4, 0.8, rng, n=4)
    lantern(R.S, P, M, (-4.4, 3.8, rz1 - 0.8), s=0.5, lit=True, power=6.0)
    P.fill(box(M, (-4.55, 0, rz1 - 0.95), (-4.25, 2.9, rz1 - 0.65)), IRON, cell=9)
    R.S.lights.append({'type': 'point', 'pos': (0.0, 6.0, -1.0), 'power': 14.0, 'color': 5800, 'radius': 2.0})
    return R.done(grade={'bloom': 0.16, 'vignette': 0.06})


# -------------------------------------------------------------------------------------- the Guild Lodge
def scene_lodge():
    R = Room('lodge_walk', ('#241A14', '#17100C'))
    P, M, X, Y, Z = R.P, R.M, R.X, R.Y, R.Z
    rng = np.random.default_rng(43)
    rx0, rx1, rz0, rz1 = ROOM
    R.floor(OAK, cell=(3.0, 1, 0.6), seams=['#8D5D3B'])
    R.walls(PLASTER, h=8.0, footing=STONE, posts=WALNUT, post_every=6.0, cell=(2.0, 2.0, 2.0))
    R.window(-10.5, 5.2, 2.2, 2.4, 'back')
    R.window(5.0, 5.0, 2.4, 2.4, 'west')
    R.window(6.0, 5.0, 2.4, 2.4, 'east')
    # ---- the notice board on the back wall: a cork board in a walnut frame, papers pinned, a red thread
    bx0, bx1 = BOARD_L
    P.fill(box(M, (bx0 - 0.4, 2.2, rz0 - 0.1), (bx1 + 0.4, 6.4, rz0 + 0.5)), WALNUT, cell=9)
    P.fill(box(M, (bx0, 2.6, rz0 - 0.1), (bx1, 6.0, rz0 + 0.55)), CORK, cell=(0.5, 0.5, 9))
    for k in range(9):
        px_, py_ = rng.uniform(bx0 + 0.6, bx1 - 1.4), rng.uniform(2.9, 5.0)
        w_, h_ = rng.uniform(0.8, 1.4), rng.uniform(0.9, 1.3)
        P.fill(box(M, (px_, py_, rz0 + 0.5), (px_ + w_, py_ + h_, rz0 + 0.7)), PARCH if k % 3 else ['#F5C4CF', '#F8B9C6'], cell=9)
        P.fill(box(M, (px_ + w_ / 2 - 0.12, py_ + h_ - 0.25, rz0 + 0.6), (px_ + w_ / 2 + 0.12, py_ + h_, rz0 + 0.85)), ['#E8513F', '#5E7A9C', '#F4C04E'][k % 3:k % 3 + 1], cell=9)
    for k in range(3):
        y0_, y1_ = rng.uniform(3.0, 5.4), rng.uniform(3.0, 5.4)
        x0_, x1_ = rng.uniform(bx0 + 0.5, bx1 - 0.5), rng.uniform(bx0 + 0.5, bx1 - 0.5)
        thread = (np.abs((Y - y0_) - (y1_ - y0_) * np.clip((X - x0_) / max(1e-3, x1_ - x0_), 0, 1)) < 0.12) & (X >= min(x0_, x1_)) & (X < max(x0_, x1_)) & (Z >= rz0 + 0.7) & (Z < rz0 + 0.85)
        P.fill(thread, ['#E8513F'], cell=9)
    P.fill(box(M, (bx0 + 1.0, 6.5, rz0 - 0.1), (bx1 - 1.0, 7.3, rz0 + 0.4)), NAVY, cell=9)                  # the Guild's banner over it
    P.fill(box(M, (bx0 + 2.6, 6.7, rz0 + 0.3), (bx1 - 2.6, 7.1, rz0 + 0.45)), ['#F3E5C9'], cell=9)
    # ---- the long table with its benches, candles, mugs and a map unrolled on it
    tx0, tx1, tz0, tz1 = TABLE_L
    for (lx, lz) in ((tx0 + 0.4, tz0 + 0.3), (tx1 - 0.8, tz0 + 0.3), (tx0 + 0.4, tz1 - 0.7), (tx1 - 0.8, tz1 - 0.7)):
        P.fill(box(M, (lx, 0, lz), (lx + 0.4, 2.2, lz + 0.4)), WALNUT, cell=9)
    P.fill(box(M, (tx0, 2.2, tz0), (tx1, 2.5, tz1)), OAK, cell=(9, 9, 0.6))
    for bz_ in (tz0 - 1.5, tz1 + 0.6):
        P.fill(box(M, (tx0 + 0.6, 1.1, bz_), (tx1 - 0.6, 1.4, bz_ + 0.9)), HONEY, cell=(1.5, 1, 9))
        for lx in (tx0 + 1.0, tx1 - 1.4):
            P.fill(box(M, (lx, 0, bz_ + 0.2), (lx + 0.4, 1.1, bz_ + 0.7)), WALNUT)
    R.candle(tx0 + 2.0, 2.5, (tz0 + tz1) / 2, 2.5)
    R.candle(tx1 - 2.0, 2.5, (tz0 + tz1) / 2, 2.5)
    P.fill(box(M, (tx0 + 3.0, 2.5, tz0 + 0.4), (tx1 - 3.0, 2.6, tz1 - 0.4)), PARCH, cell=9)                # the map
    P.fill(box(M, (tx0 + 3.4, 2.6, tz0 + 0.7), (tx1 - 3.4, 2.65, tz1 - 0.7)) & hashmask(M, 0.4, seed=8, cell=0.5), ['#7F9871', '#5E7A9C', '#C9A24A'], cell=9)
    for (mx_, mz_) in ((tx0 + 1.0, tz0 + 0.5), (tx1 - 1.2, tz1 - 0.6)):
        P.fill(cyl_y(M, (mx_, mz_), 0.3, 2.5, 3.0), TERRACOTTA, cell=9)
    # ---- Alder's desk by the back wall: a ledger, an inkwell, rolled maps in a rack behind
    dx0, dx1, dz0, dz1 = DESK_L
    P.fill(box(M, (dx0, 0, dz0), (dx1, 2.3, dz1)), WALNUT, cell=(9, 0.8, 1.2))
    P.fill(box(M, (dx0 - 0.2, 2.3, dz0 - 0.1), (dx1 + 0.2, 2.6, dz1 + 0.2)), OAK, cell=(9, 9, 0.6))
    P.fill(box(M, (dx0 + 0.6, 2.6, dz0 + 0.4), (dx0 + 2.4, 2.75, dz1 - 0.3)), PARCH, cell=9)
    P.fill(box(M, (dx0 + 1.45, 2.6, dz0 + 0.4), (dx0 + 1.55, 2.8, dz1 - 0.3)), ['#8D5D3B'], cell=9)
    P.fill(cyl_y(M, (dx1 - 1.0, dz0 + 0.6), 0.3, 2.6, 3.1), ['#203B50'], cell=9)
    P.fill(ball(M, (dx1 - 2.2, 2.9, dz0 + 0.7), 0.3), BRASS, cell=9)                                      # the bell
    R.candle(dx1 - 0.6, 2.6, dz1 - 0.6, 2.5)
    P.fill(box(M, (dx0, 0, rz0 - 0.1), (dx1, 5.6, rz0 + 1.3)) & (Z >= rz0), WALNUT, cell=(9, 1.4, 9))       # the map rack
    for j in range(4):
        for i in range(4):
            P.fill(((Y - (0.7 + j * 1.4)) ** 2 + (X - (dx0 + 0.75 + i * 1.5)) ** 2 <= 0.45 ** 2) & (Z >= rz0 + 0.2) & (Z < rz0 + 1.5), PARCH if (i + j) % 3 else ['#C9A24A'], cell=9)
    P.fill(box(M, (dx0 - 1.6, 0, dz1 + 0.4), (dx0 - 0.6, 1.5, dz1 + 1.4)), WALNUT, cell=9)                  # his stool
    # ---- the map table (round, with a map and a compass), the fireplace in the east wall, its rug
    mx_, mz_ = MAP_TABLE
    P.fill(cyl_y(M, (mx_, mz_), 0.35, 0, 1.8), WALNUT, cell=9)
    P.fill(cyl_y(M, (mx_, mz_), 1.7, 1.8, 2.1), HONEY, cell=9)
    P.fill(cyl_y(M, (mx_, mz_), 1.3, 2.1, 2.2), PARCH, cell=9)
    P.fill(cyl_y(M, (mx_ + 0.6, mz_ - 0.4), 0.3, 2.2, 2.45), COPPER, cell=9)
    fz_ = FIRE_L[1]
    P.fill(box(M, (rx1 - 1.6, 0, fz_ - 3.0), (rx1 + WALL_T, 5.4, fz_ + 3.0)), STONE, cell=(1.2, 0.7, 1.2))
    P.fill(box(M, (rx1 - 1.6, 0, fz_ - 3.0), (rx1 + WALL_T, 5.4, fz_ + 3.0)) & hashmask(M, 0.25, seed=7, cell=1.2), STONE_LT, cell=(1.2, 0.7, 1.2))
    mouth = box(M, (rx1 - 1.7, 0, fz_ - 1.8), (rx1 + 0.3, 3.2, fz_ + 1.8))
    M.m[mouth] = 0
    P.fill(box(M, (rx1, 0, fz_ - 1.8), (rx1 + 0.3, 3.2, fz_ + 1.8)), ['#2B211D', '#231B18'], cell=9)
    P.fill(box(M, (rx1 - 1.7, 0, fz_ - 1.8), (rx1 + 0.3, 0.2, fz_ + 1.8)), ['#2B211D'], cell=9)
    for (lz_, ly_) in ((-0.8, 0.2), (0.7, 0.2), (0.0, 0.9)):
        P.fill(box(M, (rx1 - 1.4, ly_, fz_ + lz_ - 0.4), (rx1 - 0.1, ly_ + 0.7, fz_ + lz_ + 0.4)), ['#6E4529', '#5E3A24'], cell=9)
    fire = ball(M, (rx1 - 0.7, 1.4, fz_), 0.9, 1.3) & (Y >= 0.8)
    P.fill(fire, EMBER, glow=0.3, cell=0.5)
    P.fill(ball(M, (rx1 - 0.7, 1.1, fz_), 0.4, 1.2) & (Y >= 0.8), ['#FFE6A0'], glow=0.45, cell=9)
    R.S.lights.append({'type': 'point', 'pos': (rx1 - 1.8, 1.6, fz_), 'power': 12.0, 'color': 2100, 'radius': 1.0})
    P.fill(box(M, (rx1 - 2.0, 5.4, fz_ - 3.4), (rx1 + WALL_T, 5.8, fz_ + 3.4)), WALNUT, cell=9)               # the mantel
    R.candle(rx1 - 1.0, 5.8, fz_ - 2.4, 2.0)
    P.fill(ball(M, (rx1 - 1.0, 6.4, fz_ + 2.0), 0.5), BRASS, cell=9)                                          # a trophy cup
    P.fill(cyl_y(M, (rx1 - 1.0, fz_ + 2.0), 0.2, 5.8, 6.1), BRASS, cell=9)
    rr = ((X - (rx1 - 4.6)) ** 2 / 2.6 ** 2 + (Z - fz_) ** 2 / 3.4 ** 2)
    P.fill(R.ground & (rr <= 1.0) & (Y >= -0.3), RUG, cell=(0.5, 1, 0.5))
    P.fill(R.ground & (rr <= 1.0) & (rr > 0.76) & (Y >= -0.3), RUG_LT, cell=(0.5, 1, 0.5))
    P.fill(box(M, (rx1 - 6.8, 1.0, fz_ - 0.6), (rx1 - 4.4, 1.5, fz_ + 0.6)), HONEY, cell=(1.5, 1, 9))         # an armchair-bench facing the fire
    for lz_ in (fz_ - 0.5, fz_ + 0.1):
        P.fill(box(M, (rx1 - 6.6, 0, lz_), (rx1 - 6.1, 1.0, lz_ + 0.4)), WALNUT)
        P.fill(box(M, (rx1 - 4.9, 0, lz_), (rx1 - 4.4, 1.0, lz_ + 0.4)), WALNUT)
    P.fill(box(M, (rx1 - 6.8, 1.5, fz_ - 0.6), (rx1 - 6.5, 2.8, fz_ + 0.6)), HONEY, cell=(9, 1.5, 9))
    # ---- banners, antlers over the fire, shelves of scrolls on the west wall, Pip's pack and crates by the door
    for bx_ in (rx0 + 2.0, rx1 - 2.0):
        ban = box(M, (bx_ - 0.9, 3.6, rz0 - 0.1), (bx_ + 0.9, 7.4, rz0 + 0.4)) & ~((Y < 4.4) & (np.abs(X - bx_) < 0.4))
        P.fill(ban, NAVY, cell=9)
        P.fill(ban & (np.abs(Y - 6.0) < 0.4) & (np.abs(X - bx_) < 0.5), ['#F3E5C9'], cell=9)
    for sy in (3.2, 4.6, 6.0):
        P.fill(box(M, (rx0, sy, -4.0), (rx0 + 1.3, sy + 0.25, 3.0)), WALNUT, cell=9)
        for k, sz_ in enumerate(np.arange(-3.6, 2.8, 0.8)):
            if k % 4 == 3:
                R.jar(rx0 + 0.65, sy + 0.25, sz_, 0.3, 0.6, GLASS_AMBER if k % 2 else GLASS_MINT)
            else:
                P.fill(((Y - (sy + 0.6)) ** 2 + (Z - sz_) ** 2 <= 0.3 ** 2) & (X >= rx0 + 0.1) & (X < rx0 + 1.2), PARCH if k % 3 else ['#C9A24A'], cell=9)
    crate(P, M, rx0 + 1.8, 6.2, 0.9)
    crate(P, M, rx0 + 1.6, 8.4, 0.7)
    P.fill(ball(M, (-3.6, 0.9, 8.4), 0.9, 0.9) & (Y >= 0), ['#8D5D3B', '#7E5133'], cell=9)                   # Pip's pack
    P.fill(box(M, (-4.0, 1.6, 8.0), (-3.2, 1.9, 8.8)), ['#C9A24A'], cell=9)
    lantern(R.S, P, M, (-6.4, 3.8, rz1 - 0.8), s=0.5, lit=True, power=7.0)
    P.fill(box(M, (-6.55, 0, rz1 - 0.95), (-6.25, 2.9, rz1 - 0.65)), IRON, cell=9)
    lantern(R.S, P, M, (0.0, 6.2, -1.0), s=0.55, lit=True, power=9.0, hang_to=9.5)                           # a lamp over the table
    return R.done()


SCENES = {'workshop': scene_workshop, 'glasshouse': scene_glasshouse, 'lodge': scene_lodge}
for _k in SCENES:
    VW.VIEWS[_k] = ((0.0, -1.2), 30.0, (1374, 1000))

if __name__ == '__main__':
    import json

    import village_scenes as VSC
    args = sys.argv[1:]
    out, key = args[0], args[1]
    quick = '--quick' in args
    os.makedirs(out, exist_ok=True)
    vs = SCENES[key]()
    if '--depth' in args:
        VW.render_ortho(vs, key, os.path.join(out, f'village_walk_{key}_depth.exr'), quick, depth=True)
        sys.exit(0)
    raw = os.path.join(out, f'village_walk_{key}_raw.png')
    proj = VW.render_ortho(vs, key, raw, quick)
    VSC.finish(vs, raw, os.path.join(out, f'village_walk_{key}.png'), quick)
    json.dump(proj, open(os.path.join(out, f'village_walk_{key}.json'), 'w'), indent=1)

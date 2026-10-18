"""Home scenes: the Home Area Map (the Cottage in ruins / restored), the Garden close-up, the Cottage
Kitchen and the Apothecary. Same building blocks and Blender path as village_scenes.py.

  home_map_ruined / home_map_restored   1170x1300, the Square's camera; anchors: nest, garden, cottage, gate
  garden                                1170x1300, closer; anchors: p1..p4 (plot centres) + p1l/p1r.. (edges)
  kitchen / apothecary                  1170x1500 interiors (interior_cam), the Evochi stands front-left
  cottage_ruined / cottage_restored     1170x810 close-ups of the cottage for its screen
"""
from __future__ import annotations

import math

import numpy as np

from voxel import Model
from village_scenes import (
    VScene, CPainter, box, cyl_y, ball, gable, win_front, outdoor_lantern, flower_patch, fence_line, tree2,
    far_terrain, lantern, table, jar, shelf_board, barrel, crate, rug, hanging_plant, room_shell, interior_cam,
    flower_pot, shift_mask, ROOM, INTERIOR_W, INTERIOR_H, STATE_LIGHT, GRASS, PATHC, ROOF, MOSSROOF, WATERC, LEAF,
    OAK, OAK_DARK, WALNUT, HONEY, BRICK, PLASTER, STONE, STONE_LT, IRON, COPPER, BRASS, GLASS_AMBER, GLASS_MINT,
    GLASS_ROSE, CLEAR_GLASS, TERRACOTTA, FLOWERS, SAGE, CREAM, PARCH, WIN_DAY, WIN_LIT, TREE_LEAVES,
)

STRAW = ['#E8C766', '#DDBA58', '#D4AE4E', '#F0D27A']
SOIL = ['#6B4A34', '#5E412E', '#74513A']
SOIL_DK = ['#4F3726', '#46301F']
GRAVEL = ['#D9CDB4', '#CFC2A6', '#E2D7C0']
SPROUT = ['#7FC45E', '#6FB24E', '#8FD06C']
VIOLET = ['#AA8BCF', '#9975C9']
GLASS_VIOLET = ['#C9B3EE', '#D8C7F5']


def seg(M, a, b, w):
    """Ground mask within distance w of the segment a-b (x, z)."""
    a, b = np.array(a, float), np.array(b, float)
    d = b - a
    L2 = float(d @ d)
    t = np.clip(((M.X - a[0]) * d[0] + (M.Z - a[1]) * d[1]) / L2, 0, 1)
    px, pz = a[0] + t * d[0], a[1] + t * d[1]
    return (M.X - px) ** 2 + (M.Z - pz) ** 2 <= w * w


def noise2(M, sx=0.37, sz=0.29, ph=0.0):
    return np.sin(M.X * sx + ph) * np.cos(M.Z * sz - ph * 0.7) + 0.5 * np.sin(M.X * sx * 2.3 + M.Z * sz * 1.7 + ph)


def hashmask(M, p, seed=1, cell=1.0):
    """Deterministic per-cell coin flip with probability p."""
    cx = np.floor(M.X / cell).astype(np.int64)
    cy = np.floor(M.Y / cell).astype(np.int64)
    cz = np.floor(M.Z / cell).astype(np.int64)
    h = (cx * 73856093) ^ (cy * 19349663) ^ (cz * 83492791) ^ (seed * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    return (np.abs(h ^ (h >> 16)) % 1000) < p * 1000


def soil_plot(P, M, x0, x1, z0, z1, top=0.7, border=WALNUT, furrows='x'):
    """A raised bed: timber border, dark soil with furrows."""
    outer = box(M, (x0, 0, z0), (x1, top + 0.3, z1))
    inner = box(M, (x0 + 0.6, 0, z0 + 0.6), (x1 - 0.6, top + 0.3, z1 - 0.6))
    P.fill(outer & ~inner, border, cell=(9, 9, 9))
    P.fill(outer & ~inner & (M.Y >= top), [border[0]], cell=9)
    soil = inner & (M.Y < top)
    P.fill(soil, SOIL, cell=0.5)
    if furrows == 'x':
        P.fill(soil & (M.Y >= top - 0.35) & ((((M.Z - z0) % 1.8) < 0.6)), SOIL_DK, cell=0.5)
    else:
        P.fill(soil & (M.Y >= top - 0.35) & ((((M.X - x0) % 1.8) < 0.6)), SOIL_DK, cell=0.5)
    return soil


def tuft(P, M, x, z, h, cols, y=0.0, r=0.3):
    P.fill(box(M, (x - r, y, z - r), (x + r, y + h, z + r)), cols, cell=9)


def sprouts(P, M, x0, x1, z0, z1, y, rng, kind='sprout'):
    """Rows of little plants on a plot (the map's generic crops)."""
    for zz in np.arange(z0 + 1.0, z1 - 0.6, 1.8):
        for xx in np.arange(x0 + 1.2, x1 - 0.8, 1.6):
            jx, jz = rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2)
            if kind == 'sprout':
                tuft(P, M, xx + jx, zz + jz, 0.8, ['#5EA046'], y=y, r=0.18)
                P.fill(ball(M, (xx + jx, y + 0.9, zz + jz), 0.45, 0.55), SPROUT, cell=0.5)
            elif kind == 'leafy':
                P.fill(ball(M, (xx + jx, y + 0.7, zz + jz), 0.75, 0.9) & (M.Y >= y), ['#5EA046', '#6FB24E', '#4F9C3E'], cell=0.5)
            elif kind == 'berry':
                P.fill(ball(M, (xx + jx, y + 0.8, zz + jz), 0.8, 0.85) & (M.Y >= y), ['#4F9C3E', '#5EA046'], cell=0.5)
                for k in range(2):
                    P.fill(ball(M, (xx + jx + (k - 0.5) * 0.6, y + 1.2, zz + jz + 0.4), 0.28), ['#E8513F', '#F06A4E'], cell=9)
            elif kind == 'wheat':
                for k in range(3):
                    sx_ = xx + jx + (k - 1) * 0.35
                    tuft(P, M, sx_, zz + jz, 1.6 + 0.2 * k, ['#C9B05A', '#BFA650'], y=y, r=0.12)
                    P.fill(box(M, (sx_ - 0.18, y + 1.5 + 0.2 * k, zz + jz - 0.18), (sx_ + 0.18, y + 2.3 + 0.2 * k, zz + jz + 0.18)), ['#F0C95A', '#E8BC48'], cell=9)
            elif kind == 'weeds':
                if rng.random() < 0.8:
                    tuft(P, M, xx + jx, zz + jz, rng.uniform(0.8, 2.0), ['#6FA552', '#5E9646', '#88BC67'], y=y, r=0.25)


def cottage(S, P, M, rng, x0, x1, z0, z1, restored):
    """The player's Cottage: plaster and timber, front door on +z. Ruined: holed mossy roof, bare
    rafters, boarded windows, an empty doorway, vines; restored: tiled roof, chimney smoke, lit
    windows, flower boxes and a porch lantern."""
    wall_h, roof_h = 6.5, 5.0
    walls = PLASTER if restored else ['#E2D2B2', '#D8C6A4', '#CDBB98']
    roof = ROOF if restored else ['#8AA37C', '#7F9871', '#9C8C6E']
    body = gable(P, M, x0, x1, z0, z1, wall_h, roof_h, walls, roof, oh=1.0, ridge='x', wall_cell=(3, 3, 3))
    # stone footing and timber frame on the front wall
    P.fill(box(M, (x0 - 0.3, 0, z0 - 0.3), (x1 + 0.3, 1.0, z1 + 0.3)) & ~box(M, (x0, 0, z0), (x1, 1.0, z1 - 0.5)), STONE, cell=(1.5, 1, 1.5))
    front = body & (M.Z >= z1 - 0.5)
    P.fill(front & ((((M.X - x0) % 4.0) < 0.6) | (np.abs(M.Y - wall_h + 0.3) < 0.3)), WALNUT, cell=9)
    P.fill(body & ((M.X < x0 + 0.6) | (M.X >= x1 - 0.6)) & ((((M.Z - z0) % 4.0) < 0.6) | (np.abs(M.Y - wall_h + 0.3) < 0.3)), WALNUT, cell=9)
    mid = (x0 + x1) / 2
    zc = (z0 + z1) / 2
    half = (z1 - z0) / 2 + 1.0
    roof_top = wall_h + roof_h * (1 - np.abs(M.Z - zc) / half)
    roof_shell = (M.X >= x0 - 1.0) & (M.X < x1 + 1.0) & (np.abs(M.Z - zc) <= half) & (M.Y >= roof_top - 1.2) & (M.Y < roof_top) & (M.Y >= wall_h - 0.5)
    door = box(M, (mid - 1.4, 1.0, z1 - 0.6), (mid + 1.4, 4.8, z1 + 0.4))
    if restored:
        P.fill(door, ['#7A4E2E', '#6E4529'], cell=(9, 9, 9))
        P.fill(door & (np.abs(M.X - mid) < 0.25), WALNUT, cell=9)
        P.fill(box(M, (mid + 0.8, 2.6, z1 + 0.2), (mid + 1.1, 2.9, z1 + 0.5)), BRASS)
        # porch canopy and step
        P.fill(box(M, (mid - 2.6, 5.2, z1), (mid + 2.6, 5.6, z1 + 2.2)), ROOF, cell=(1.0, 0.5, 1.0))
        P.fill(box(M, (mid - 2.0, 0, z1), (mid + 2.0, 0.5, z1 + 1.6)), STONE_LT, cell=(1.5, 1, 1.5))
        for wx in (x0 + 3.5, x1 - 3.5):
            win_front(P, M, wx, 3.4, z1, 2.4, 2.0, lit=True, glow=0.55)
            box_ = box(M, (wx - 1.6, 1.8, z1), (wx + 1.6, 2.4, z1 + 0.9))
            P.fill(box_, HONEY, cell=9)
            for k in range(4):
                P.fill(ball(M, (wx - 1.2 + k * 0.8, 2.7, z1 + 0.5), 0.4), [FLOWERS[(k + int(wx)) % 5]], cell=9)
        win_front(P, M, mid, 8.6, z1 - 1.5, 1.6, 1.4, lit=True, glow=0.5)
        S.lights.append({'type': 'point', 'pos': (mid, 3.0, z1 - 2.0), 'power': 22.0, 'color': 2200, 'radius': 1.5})
        lantern(S, P, M, (mid + 2.3, 4.0, z1 + 1.0), s=0.55, lit=True, power=5.0)
        # chimney with smoke
        cx_, cz_ = x1 - 3.0, z0 + 2.5
        P.fill(box(M, (cx_ - 1.1, 4.0, cz_ - 1.1), (cx_ + 1.1, 14.0, cz_ + 1.1)), STONE, cell=(1.0, 1.0, 1.0))
        P.fill(box(M, (cx_ - 1.4, 13.6, cz_ - 1.4), (cx_ + 1.4, 14.2, cz_ + 1.4)), ['#837D74'], cell=9)
        for k in range(5):
            P.fill(ball(M, (cx_ + 0.5 * k, 15.2 + k * 1.5, cz_ - 0.3 * k), 0.75 + 0.22 * k) & (M.m == 0), ['#F7F5F0', '#ECEBE6'], cell=0.5)
    else:
        # roof holes with the rafters showing through
        holes = roof_shell & hashmask(M, 0.42, seed=5, cell=2.0) & (np.abs(M.Z - zc) < half - 1.4)
        M.m[holes] = 0
        rafter = roof_shell & holes & ((((M.X - x0) % 2.5) < 0.6)) & (M.Y >= roof_top - 1.2)
        P.fill(rafter, WALNUT, cell=9)
        P.fill(roof_shell & ~holes & hashmask(M, 0.3, seed=9, cell=1.0) & (M.m != 0), ['#6E8762', '#5E7A55'], cell=1.0)   # moss
        M.m[door] = 0
        P.fill(box(M, (mid - 1.4, 1.0, z1 - 1.0), (mid + 1.4, 4.8, z1 - 0.6)), ['#3B2923'], cell=9)    # dark inside
        P.fill(box(M, (mid + 2.0, 0, z1 + 1.2), (mid + 4.8, 0.4, z1 + 2.6)), ['#7A4E2E', '#6E4529'], cell=9)  # fallen door
        for wx in (x0 + 3.5, x1 - 3.5):
            win_front(P, M, wx, 3.4, z1, 2.4, 2.0, lit=False)
            P.fill(box(M, (wx - 1.4, 3.4 - 1.0, z1 - 0.6), (wx + 1.4, 3.4 + 1.0, z1 + 0.5)) & (M.Z >= z1 - 0.6), ['#3B2923'], cell=9)
            for k, dy in enumerate((-0.6, 0.5)):
                plank = (np.abs(M.Y - 3.4 - dy - (M.X - wx) * (0.25 if k else -0.2)) < 0.3) & (np.abs(M.X - wx) <= 1.8) & (M.Z >= z1 + 0.4) & (M.Z < z1 + 0.9)
                P.fill(plank, ['#A97C4B', '#9C7044'], cell=9)
        # vines up the front wall
        for vx in (x0 + 1.2, mid + 3.0, x1 - 1.0):
            vine = (np.abs(M.X - vx - 0.6 * np.sin(M.Y * 0.9 + vx)) < 0.45) & (M.Z >= z1 - 0.1) & (M.Z < z1 + 0.6) & (M.Y < 6.5)
            P.fill(vine, ['#5EA046', '#4F9C3E', '#6FB24E'], cell=0.5)
        # the broken chimney stump and a pile of old planks
        cx_, cz_ = x1 - 3.0, z0 + 2.5
        P.fill(box(M, (cx_ - 1.1, 4.0, cz_ - 1.1), (cx_ + 1.1, 9.5, cz_ + 1.1)) & hashmask(M, 0.85, seed=3, cell=1.0), STONE, cell=(1.0, 1.0, 1.0))
        for k in range(5):
            y = 0.25 + k * 0.4
            ang = 0.25 * (k % 3) - 0.25
            pl = (np.abs((M.Z - (z1 + 4.5)) - (M.X - (x1 + 3.0)) * ang) < 0.5) & (np.abs(M.X - (x1 + 3.0)) < 2.4 - 0.2 * k) & (M.Y >= y - 0.2) & (M.Y < y + 0.2)
            P.fill(pl, ['#B98955', '#A97C4B', '#8D5D3B'], cell=9)
        for _ in range(16):
            gx, gz = rng.uniform(x0 - 2, x1 + 2), rng.uniform(z1 + 0.5, z1 + 3.5)
            tuft(P, M, gx, gz, rng.uniform(0.8, 1.8), ['#6FA552', '#5E9646', '#88BC67'], r=0.3)
    return body


HOME_ANCHORS = {'nest': (-11.0, 3.0, 13.0), 'garden': (13.0, 6.0, -1.0), 'cottage': (-16.0, 13.5, -25.5),
                'gate': (16.0, 9.5, -33.0)}


def scene_home_map(restored=False):
    st = STATE_LIGHT['day']
    cam = {'pos': (0.0, 63.0, 63.0), 'target': (0.0, 0.0, -8.0), 'fov': 36.0}
    S = VScene('home_map_' + ('restored' if restored else 'ruined'), 1170, 1300, cam, world=st['world'], samples=128,
               transparent=True, sky=st['sky'])
    S.lights.append({'type': 'sun', **st['sun']})
    S.anchors = dict(HOME_ANCHORS)
    rng = np.random.default_rng(71)
    M = Model((-40, -4, -46), (40, 30, 36), [], res=2)
    P = CPainter(M, 71)
    ground = (M.Y >= -1) & (M.Y < 0)
    P.fill((M.Y >= -4) & (M.Y < -1), ['#B98955', '#A97C4B'], cell=1)
    P.fill(ground, GRASS, cell=1.0)
    P.fill(ground & (noise2(M) > 0.75), ['#79A85A', '#73A255'], cell=1.0)
    # paths: nest -> crossroads -> garden gate / cottage door / village gate (off the top)
    hub = (-1.0, 2.0)
    path = (seg(M, (-11.0, 8.0), hub, 2.0) | seg(M, hub, (2.5, 0.0), 2.0) | seg(M, hub, (-16.0, -18.0), 2.0) |
            seg(M, hub, (9.0, -22.0), 2.0) | seg(M, (9.0, -22.0), (16.0, -33.0), 2.0) | seg(M, (16.0, -33.0), (17.0, -46.0), 2.2))
    P.fill(ground & path, PATHC, cell=(1.0, 1, 1.0))
    P.fill(ground & path & (noise2(M, 0.9, 0.8, 1.3) > 0.9), ['#CDBB94'], cell=1.0)
    # pond with a stone rim and lily pads (left)
    pr = ((M.X + 30.0) ** 2 / 36.0 + (M.Z + 3.0) ** 2 / 16.0)
    M.m[(pr <= 1.0) & (M.Y >= -1.0) & (M.Y < 0)] = 0
    P.fill((pr <= 1.0) & (M.Y >= -1.6) & (M.Y < -0.6), WATERC, cell=1.0)
    P.fill((pr > 1.0) & (pr <= 1.35) & (M.Y >= -1.0) & (M.Y < 0.2), STONE_LT, cell=1.0)
    for (lx, lz) in ((-32.0, -4.0), (-28.5, -1.5), (-30.5, -5.2)):
        P.fill(cyl_y(M, (lx, lz), 0.9, -0.7, -0.4), ['#5EA046', '#6FB24E'], cell=9)
    P.fill(ball(M, (-28.3, -0.3, -1.3), 0.35), ['#F5A3B5'], cell=9)

    # ---- the Nest (bottom left): a woven straw ring with a blanket and a little sign
    ncx, ncz = -11.0, 13.0
    r = np.sqrt((M.X - ncx) ** 2 + (M.Z - ncz) ** 2)
    ring = np.sqrt((r - 4.4) ** 2 + (M.Y - 0.9) ** 2) <= 1.4
    ring &= M.Y >= 0
    P.fill(ring, STRAW, cell=0.5)
    P.fill(ring & ((np.floor(np.degrees(np.arctan2(M.Z - ncz, M.X - ncx)) / 12) % 2) == 0) & (M.Y > 1.4), ['#C9A24A', '#D4AE4E'], cell=0.5)
    P.fill((r < 3.3) & (M.Y >= 0) & (M.Y < 0.6), ['#FBF5E8', '#F1E6CF'], cell=0.5)
    P.fill((r < 3.3) & (M.Y >= 0.4) & (M.Y < 0.6) & ((np.floor((M.X - ncx) / 1.0) + np.floor((M.Z - ncz) / 1.0)) % 2 == 0), ['#F5C4CF'], cell=9)
    P.fill(ball(M, (ncx - 1.4, 0.9, ncz - 1.6), 1.0, 0.55) & (M.Y >= 0.4), ['#FFFDF6', '#F7F1E4'], cell=0.5)   # pillow
    P.fill(box(M, (ncx + 5.4, 0, ncz - 3.4), (ncx + 5.8, 3.6, ncz - 3.0)), WALNUT, cell=9)
    P.fill(box(M, (ncx + 4.4, 2.6, ncz - 3.4), (ncx + 7.4, 4.2, ncz - 3.0)), HONEY, cell=9)
    for a in np.linspace(0.3, 2 * math.pi, 9):
        flower_patch(P, M, ncx + 7.2 * math.cos(a), ncz + 6.4 * math.sin(a), 0.9, 0.8, rng, n=2)

    # ---- the Garden (right middle): fenced, four raised beds, a shed and a scarecrow
    gx0, gx1, gz0, gz1 = 2.0, 24.0, -10.0, 9.0
    fence_line(P, M, (gx0, gz0), (gx1, gz0))
    fence_line(P, M, (gx1, gz0), (gx1, gz1))
    fence_line(P, M, (gx0, gz1), (gx1, gz1))
    fence_line(P, M, (gx0, gz0), (gx0, -2.6))
    fence_line(P, M, (gx0, 2.6), (gx0, gz1))
    P.fill(ground & box(M, (gx0, -1, gz0), (gx1, 0, gz1)), GRAVEL, cell=(1.0, 1, 1.0))
    beds = [(4.0, 12.0, -8.0, -1.6, 'berry'), (14.0, 22.0, -8.0, -1.6, 'leafy'), (4.0, 12.0, 1.4, 7.6, 'wheat'), (14.0, 22.0, 1.4, 7.6, 'weeds')]
    for (bx0, bx1, bz0, bz1, kind) in beds:
        soil_plot(P, M, bx0, bx1, bz0, bz1, top=0.7)
        sprouts(P, M, bx0 + 0.6, bx1 - 0.6, bz0 + 0.6, bz1 - 0.6, 0.7, rng, kind)
    # scarecrow between the beds
    P.fill(box(M, (12.8, 0, -0.1), (13.2, 5.4, 0.3)), WALNUT, cell=9)
    P.fill(box(M, (11.1, 3.6, -0.1), (14.9, 4.0, 0.3)), WALNUT, cell=9)
    P.fill(box(M, (11.9, 2.2, -0.4), (14.1, 4.4, 0.6)), ['#7F9871', '#76906A'], cell=9)
    P.fill(ball(M, (13.0, 5.4, 0.1), 0.9), ['#F0D27A', '#E8C766'], cell=9)
    P.fill(cyl_y(M, (13.0, 0.1), 1.4, 6.0, 6.3) | cyl_y(M, (13.0, 0.1), 0.8, 6.3, 7.1), ['#D9B36A', '#C9A24A'], cell=9)
    # tool shed outside the top-right corner
    gable(P, M, 18.0, 25.0, -17.5, -12.5, 4.5, 3.0, ['#B98955', '#AD7E4C'], ['#7F9871', '#76906A', '#8AA37C'], oh=0.6,
          ridge='x', wall_cell=(1.0, 9, 9))
    P.fill(box(M, (20.6, 0, -12.6), (22.6, 3.6, -12.2)), ['#6E4529'], cell=9)
    # watering can and a basket of produce at the garden gate
    P.fill(cyl_y(M, (0.4, 4.6), 0.8, 0, 1.4), COPPER, cell=9)
    P.fill(box(M, (1.1, 0.9, 4.4), (2.2, 1.2, 4.8)), COPPER)
    P.fill(cyl_y(M, (0.4, -4.4), 1.0, 0, 1.0), ['#C69469', '#B9875C'], cell=9)
    for k in range(4):
        P.fill(ball(M, (0.1 + 0.5 * (k % 2), 1.2, -4.6 + 0.5 * (k // 2)), 0.35), [['#E8513F'], ['#F08A3A'], ['#E8513F'], ['#F4C04E']][k], cell=9)

    # ---- the Cottage (upper left)
    cottage(S, P, M, rng, -24.0, -8.0, -31.0, -19.5, restored)
    if restored:
        flower_patch(P, M, -23.0, -16.6, 2.4, 1.2, rng, n=8)
        flower_patch(P, M, -9.0, -16.6, 2.4, 1.2, rng, n=8)
        fence_line(P, M, (-26.0, -15.5), (-18.6, -15.5))
        fence_line(P, M, (-13.4, -15.5), (-6.0, -15.5))
    else:
        # broken fence: a few posts and one leaning rail
        for px in (-25.0, -22.0, -10.0):
            P.fill(box(M, (px, 0, -16.2), (px + 0.6, 1.8 + 0.4 * (px % 2), -15.6)), ['#9C7044', '#8D5D3B'], cell=9)
        P.fill((np.abs(M.Y - 0.6 - (M.X + 25.0) * 0.18) < 0.3) & (M.X > -25.0) & (M.X < -19.0) & (np.abs(M.Z + 15.4) < 0.3), ['#A97C4B'], cell=9)

    # ---- the Village Gate (top right): a stone arch, a sign and a lantern, the path running on
    gcx, gcz = 16.0, -33.0
    for px in (gcx - 4.0, gcx + 4.0):
        P.fill(box(M, (px - 0.9, 0, gcz - 0.9), (px + 0.9, 6.4, gcz + 0.9)), STONE, cell=(1.0, 1.0, 1.0))
        P.fill(box(M, (px - 1.1, 6.4, gcz - 1.1), (px + 1.1, 7.0, gcz + 1.1)), STONE_LT, cell=9)
    arch = (np.abs(M.Z - gcz) <= 0.9) & (np.abs(M.Y - 7.4 - 1.2 * np.cos((M.X - gcx) / 4.6 * 1.45)) <= 0.7) & (np.abs(M.X - gcx) <= 4.9)
    P.fill(arch, STONE_LT, cell=(1.0, 1.0, 1.0))
    P.fill(box(M, (gcx - 2.0, 5.2, gcz + 0.9), (gcx + 2.0, 6.6, gcz + 1.3)), HONEY, cell=9)
    P.fill(box(M, (gcx - 1.4, 5.7, gcz + 1.2), (gcx + 1.4, 6.1, gcz + 1.4)), ['#8D5D3B'], cell=9)
    outdoor_lantern(S, P, M, gcx + 6.0, gcz + 1.6, 4.4, lit=restored, power=8.0, s=0.6)
    fence_line(P, M, (-40.0, -38.0), (gcx - 5.0, gcz - 0.5))
    fence_line(P, M, (gcx + 5.0, gcz - 0.5), (40.0, -36.0))
    # far village roofs peeking over the hedge beyond the gate
    for (vx, vz, w_) in ((6.0, -43.0, 6.0), (24.0, -44.0, 7.0), (34.0, -42.0, 5.0)):
        gable(P, M, vx - w_ / 2, vx + w_ / 2, vz - 2.0, vz + 2.0, 3.0, 2.6, PLASTER, ROOF, oh=0.5, ridge='x', wall_cell=(3, 3, 3))

    # ---- trees, flowers, rocks
    trees = [(-36.0, -40.0, 8, 5.0), (-34.0, 12.0, 6, 4.4), (-22.0, 26.0, 5, 3.8), (2.0, 28.0, 5, 3.4),
             (34.0, 20.0, 6, 4.6), (35.0, -24.0, 7, 4.4), (-6.0, -36.0, 7, 4.6), (-38.0, -18.0, 6, 4.2),
             (30.0, 30.0, 5, 3.6), (-1.0, -12.0, 5, 3.4), (31.0, -4.0, 6, 4.2)]
    for (tx, tz, th_, tr) in trees:
        tree2(P, M, tx, tz, th_, tr, fruit=['#D85F51'] if tx > 30 else None)
    for _ in range(30):
        fx, fz = rng.uniform(-38, 38), rng.uniform(-30, 32)
        if (gx0 - 2 < fx < gx1 + 2 and gz0 - 2 < fz < gz1 + 2) or (-27 < fx < -5 and -34 < fz < -13) or math.hypot(fx - ncx, fz - ncz) < 8.5 \
                or (-38 < fx < -22 and -9 < fz < 3) or path[min(int((fx + 40) * 2), M.m.shape[0] - 1), 0, min(int((fz + 46) * 2), M.m.shape[2] - 1)]:
            continue
        flower_patch(P, M, fx, fz, 1.3, 1.0, rng, n=4)
    for (rx, rz, rr) in ((-24.0, 6.0, 1.3), (30.0, 12.0, 1.1), (0.0, 20.0, 0.9), (-36.0, 4.0, 1.2)):
        P.fill(ball(M, (rx, 0.2, rz), rr, 0.7) & (M.Y >= 0), STONE, cell=0.5)
    S.models.append((M, CLEAR_GLASS, {'water': WATERC}))
    S.models.append((far_terrain(seed=43), (), {'water': WATERC}))
    S.grade = {'bloom': 0.18 if restored else 0.1, 'vignette': 0.12}
    return S


# ------------------------------------------------------------------ the Garden ----
GARDEN_PLOTS = {'p1': (-7.6, -6.0), 'p2': (7.6, -6.0), 'p3': (-7.6, 6.0), 'p4': (7.6, 6.0)}
PLOT_W, PLOT_D, PLOT_TOP = 13.0, 9.0, 0.8


def scene_garden():
    st = STATE_LIGHT['day']
    cam = {'pos': (0.0, 34.0, 40.0), 'target': (0.0, 0.0, -1.0), 'fov': 40.0}
    S = VScene('garden', 1170, 1300, cam, world=st['world'], samples=128, transparent=True, sky=st['sky'])
    S.lights.append({'type': 'sun', **st['sun']})
    anchors = {}
    for k, (px, pz) in GARDEN_PLOTS.items():
        anchors[k] = (px, PLOT_TOP, pz)
        anchors[k + 'l'] = (px - PLOT_W / 2, PLOT_TOP, pz)
        anchors[k + 'r'] = (px + PLOT_W / 2, PLOT_TOP, pz)
    S.anchors = anchors
    rng = np.random.default_rng(73)
    M = Model((-36, -3, -40), (36, 24, 30), [], res=3)
    P = CPainter(M, 73)
    ground = (M.Y >= -1) & (M.Y < 0)
    P.fill((M.Y >= -3) & (M.Y < -1), ['#B98955', '#A97C4B'], cell=1)
    P.fill(ground, GRASS, cell=1.0)
    P.fill(ground & (noise2(M, 0.5, 0.4) > 0.8), ['#79A85A', '#73A255'], cell=1.0)
    # gravel yard between the beds
    yard = box(M, (-17.0, -1, -13.5), (17.0, 0, 13.0))
    P.fill(ground & yard, GRAVEL, cell=(0.75, 1, 0.75))
    P.fill(ground & yard & (noise2(M, 1.7, 1.3, 0.4) > 1.0), ['#C4B595'], cell=9)
    for k, (px, pz) in GARDEN_PLOTS.items():
        soil_plot(P, M, px - PLOT_W / 2, px + PLOT_W / 2, pz - PLOT_D / 2, pz + PLOT_D / 2, top=PLOT_TOP)
        # a little wooden marker stake at each bed's front-left corner
        sx_, sz_ = px - PLOT_W / 2 + 0.3, pz + PLOT_D / 2 + 0.3
        P.fill(box(M, (sx_, 0, sz_), (sx_ + 0.4, 2.2, sz_ + 0.4)), HONEY, cell=9)
        P.fill(box(M, (sx_ - 0.4, 1.4, sz_ + 0.3), (sx_ + 0.8, 2.3, sz_ + 0.5)), ['#FBF5E8'], cell=9)
    # stepping stones down the middle
    for zz in np.arange(-12.0, 14.0, 2.2):
        P.fill(((M.X ** 2) / 1.2 + (M.Z - zz) ** 2 / 0.6 <= 1.0) & (M.Y >= -0.3) & (M.Y < 0.15), STONE_LT, cell=(0.75, 1, 0.75))
    # back fence with climbing beans and sunflowers, the shed on the left, a rain barrel
    fence_line(P, M, (-34.0, -16.0), (34.0, -16.0), h=3.0)
    for k, fx in enumerate(np.arange(-30.0, 31.0, 4.4)):
        if -24 < fx < -12:
            continue
        hh = 6.0 + 1.5 * math.sin(k * 1.3)
        P.fill(box(M, (fx - 0.25, 0, -17.2), (fx + 0.25, hh, -16.7)), ['#5EA046'], cell=9)
        P.fill(ball(M, (fx, hh * 0.5, -17.0), 1.0, 0.5), ['#6FB24E', '#86C56A'], cell=0.5)
        if k % 2 == 0:
            P.fill(cyl_y(M, (fx, -16.6), 1.3, hh, hh + 0.6), ['#F4C04E', '#F0B83C'], cell=9)
            P.fill(cyl_y(M, (fx, -16.4), 0.55, hh + 0.1, hh + 0.75), ['#8D5D3B'], cell=9)
        else:
            for yy in np.arange(1.5, hh - 0.5, 1.4):
                P.fill(ball(M, (fx + 0.6, yy, -16.6), 0.45, 0.8), ['#86C56A', '#9CD47E'], cell=9)
    gable(P, M, -26.0, -14.0, -24.0, -17.0, 5.0, 3.4, ['#B98955', '#AD7E4C', '#C4925E'], ['#7F9871', '#76906A', '#8AA37C'],
          oh=0.7, ridge='x', wall_cell=(1.0, 9, 9))
    P.fill(box(M, (-21.6, 0, -17.2), (-18.4, 4.0, -16.8)), ['#6E4529', '#7A4E2E'], cell=9)
    for k, tx in enumerate((-25.0, -24.2)):
        P.fill(box(M, (tx, 0, -16.6), (tx + 0.3, 4.0 - k * 0.4, -16.3)), WALNUT, cell=9)    # rake and hoe handles
    barrel(P, M, 20.0, -14.0, 1.6, 3.2)
    P.fill(cyl_y(M, (20.0, -14.0), 1.35, 2.8, 3.1), ['#7FB8CF', '#8EC4D9'], cell=0.5)
    # front: watering can, a basket, a wheelbarrow, flowers
    P.fill(cyl_y(M, (19.0, 12.0), 1.0, 0, 1.8), COPPER, cell=9)
    P.fill(box(M, (19.9, 1.0, 11.8), (21.6, 1.4, 12.2)), COPPER)
    P.fill(box(M, (18.2, 1.8, 11.9), (19.8, 2.2, 12.1)) & (np.abs(M.Y - 2.0 - 0.0) < 0.3), COPPER)
    P.fill(cyl_y(M, (-19.0, 11.0), 1.4, 0, 1.3), ['#C69469', '#B9875C'], cell=9)
    for k in range(5):
        P.fill(ball(M, (-19.6 + 0.6 * (k % 3), 1.5, 10.6 + 0.6 * (k // 3)), 0.42), [['#E8513F'], ['#F08A3A'], ['#E8513F'], ['#F4C04E'], ['#E8513F']][k], cell=9)
    for _ in range(14):
        fx, fz = rng.uniform(-34, 34), rng.uniform(-14, 26)
        if -18 < fx < 18 and -15 < fz < 14:
            continue
        flower_patch(P, M, fx, fz, 1.4, 1.0, rng, n=4)
    for (tx, tz, th_, tr) in ((-32.0, -28.0, 7, 4.6), (31.0, -27.0, 7, 4.4), (-33.0, 6.0, 5, 3.8), (33.0, 4.0, 5, 3.8)):
        tree2(P, M, tx, tz, th_, tr)
    # a hedge and meadow behind
    hedge = box(M, (-36.0, 0, -38.0), (36.0, 4.0 + 1.5 * np.sin(M.X * 0.4), -32.0))
    P.fill(hedge & (M.m == 0), ['#5E9646', '#6FA552', '#4F8A3C'], cell=1.0)
    S.models.append((M, CLEAR_GLASS, {'water': ['#7FB8CF', '#8EC4D9']}))
    S.grade = {'bloom': 0.1, 'vignette': 0.14}
    return S


# ------------------------------------------------------------------ the Cottage Kitchen ----
def scene_kitchen():
    """The restored Cottage's kitchen: a brick oven with a live fire, a long counter of ingredients,
    hanging herbs and copper pots, a sunny window."""
    S = VScene('kitchen', INTERIOR_W, INTERIOR_H, interior_cam(), world=((0.92, 0.86, 0.78), 0.16), samples=192)
    M = Model((-20, -2, -14), (20, 22, 29), [], res=4)
    P = CPainter(M, 81)
    rng = np.random.default_rng(81)
    R = ROOM
    room_shell(P, M, OAK, PLASTER, side_cols=['#EADBC0', '#E4D3B4'], wall_cell=(3, 3, 3))
    # wainscot along the walls
    P.fill(box(M, (R['x0'] - 1, 0, R['back'] - 1), (R['x1'] + 1, 3.0, R['back'] + 0.2)), ['#C69469', '#B9875C'], cell=(1.2, 9, 9))
    for sx in (R['x0'] - 1, R['x1']):
        P.fill(box(M, (sx - 0.2, 0, R['back']), (sx + 1.2, 3.0, R['front'])), ['#C69469', '#B9875C'], cell=(9, 9, 1.2))
    # ---- the oven: brick dome with an arched mouth and a fire inside, a chimney hood to the ceiling
    ox, oz = -9.0, R['back'] + 3.0
    base = box(M, (ox - 6.0, 0, R['back']), (ox + 6.0, 3.0, oz + 2.5))
    P.fill(base, STONE, cell=(1.5, 1.0, 1.5))
    dome = ball(M, (ox, 3.0, oz - 0.5), 5.6, 0.85) & (M.Y >= 3.0) & (M.Z >= R['back'])
    P.fill(dome, BRICK, cell=(1.2, 0.8, 1.2))
    mouth = (np.abs(M.X - ox) <= 2.2) & (M.Y >= 3.0) & (M.Y < 6.2 - ((M.X - ox) / 2.2) ** 2 * 1.4) & (M.Z >= oz - 1.0)
    M.m[mouth & dome] = 0
    P.fill((np.abs(M.X - ox) <= 2.0) & (M.Y >= 3.0) & (M.Y < 3.4) & (M.Z >= oz - 2.0) & (M.Z < oz + 0.5), ['#3B2923'], cell=9)
    fire = ball(M, (ox, 3.6, oz - 1.6), 1.4, 0.8) & (M.Y >= 3.2)
    P.fill(fire, ['#FF9A4A', '#FFB65C', '#FFD46A'], glow=1.0, cell=0.5)
    for k in range(3):
        P.fill(box(M, (ox - 1.6 + k * 1.1, 3.2, oz - 2.6), (ox - 1.0 + k * 1.1, 3.6, oz - 0.6)), ['#6E4529'], cell=9)
    S.lights.append({'type': 'point', 'pos': (ox, 4.4, oz + 0.6), 'power': 60.0, 'color': 1900, 'radius': 1.2})
    hood = (np.abs(M.X - ox) <= 3.4 - (M.Y - 8.0) * 0.25) & (M.Y >= 8.0) & (M.Y < R['h']) & (M.Z >= R['back']) & (M.Z < R['back'] + 3.4 - (M.Y - 8.0) * 0.2)
    P.fill(hood & (M.m == 0), BRICK, cell=(1.2, 0.8, 1.2))
    P.fill(box(M, (ox - 4.2, 7.8, R['back']), (ox + 4.2, 8.4, R['back'] + 4.0)), WALNUT, cell=9)      # mantel
    for k, (jx, col) in enumerate(((-3.2, GLASS_AMBER), (-2.0, ['#F5A3B5']), (2.6, GLASS_MINT))):
        jar(P, M, ox + jx, 8.4, R['back'] + 2.4, h=1.4, r=0.5, cols=col)
    # peel and logs beside the oven
    P.fill(box(M, (ox + 6.4, 0, R['back'] + 1.0), (ox + 6.8, 9.0, R['back'] + 1.4)), HONEY, cell=9)
    P.fill(box(M, (ox + 5.8, 8.6, R['back'] + 0.8), (ox + 7.4, 10.4, R['back'] + 1.6)), HONEY, cell=9)
    for k in range(5):
        lx = ox - 8.4 + (k % 3) * 1.1
        ly = 0.5 + (k // 3) * 0.9
        P.fill(cyl_y(M, (lx, R['back'] + 3.5), 0.5, 0, 0.1) | (((M.X - lx) ** 2 + (M.Y - ly) ** 2 <= 0.25) & (M.Z >= R['back'] + 0.8) & (M.Z < R['back'] + 4.4)),
               ['#8D5D3B', '#7A4E2E'], cell=9)

    # ---- the long counter (back right) with ingredients
    cx0, cx1 = 1.0, 17.0
    table(P, M, cx0, cx1, R['back'] + 0.2, R['back'] + 4.4, 5.0, cols=OAK)
    P.fill(box(M, (cx0 + 0.4, 0, R['back'] + 0.4), (cx1 - 0.4, 4.6, R['back'] + 4.2)), ['#C69469', '#B9875C'], cell=(1.6, 9, 9))
    for dx in np.arange(cx0 + 2.0, cx1 - 1.0, 3.2):
        P.fill(box(M, (dx - 0.3, 3.4, R['back'] + 4.2), (dx + 0.3, 3.7, R['back'] + 4.5)), BRASS)
    top = 5.0
    # mixing bowl with a wooden spoon
    bowl = cyl_y(M, (4.0, -9.4), 1.6, top, top + 1.4) & ~cyl_y(M, (4.0, -9.4), 1.2, top + 0.4, top + 1.6)
    P.fill(bowl, ['#FBF5E8', '#F1E6CF'], cell=9)
    P.fill(cyl_y(M, (4.0, -9.4), 1.2, top + 0.4, top + 0.9), ['#F7EBD0'], cell=9)
    P.fill((np.abs(M.Y - (top + 1.0) - (M.X - 4.0) * 0.6) < 0.25) & (M.X > 4.0) & (M.X < 6.4) & (np.abs(M.Z + 9.2) < 0.25), HONEY, cell=9)
    # basket of sunberries
    P.fill(cyl_y(M, (8.6, -9.6), 1.4, top, top + 1.1), ['#C69469', '#B9875C'], cell=9)
    for k in range(7):
        a = k * 0.9
        P.fill(ball(M, (8.6 + 0.8 * math.cos(a) * (k > 0), top + 1.3 + 0.2 * (k == 0), -9.6 + 0.8 * math.sin(a) * (k > 0)), 0.42), ['#E8513F', '#F06A4E'], cell=9)
    # carrots and a wheat sheaf
    for k in range(3):
        cxk = 11.6 + k * 0.7
        P.fill((np.abs(M.Y - top - 0.35) < 0.35) & (np.abs(M.Z - (-8.6 - 0.3 * k)) < 0.35) & (M.X > cxk) & (M.X < cxk + 2.4 - np.abs(M.Y - top - 0.35)), ['#F08A3A', '#E8792E'], cell=9)
        P.fill(ball(M, (cxk - 0.2, top + 0.5, -8.6 - 0.3 * k), 0.45, 1.2), ['#6FB24E'], cell=9)
    for k in range(7):
        wx_ = 15.0 + (k - 3) * 0.22
        P.fill(box(M, (wx_ - 0.1, top, -10.4), (wx_ + 0.1, top + 3.0, -10.2)), ['#E0C068'], cell=9)
        P.fill(box(M, (wx_ - 0.2, top + 2.6, -10.5), (wx_ + 0.2, top + 3.6, -10.1)), ['#F0C95A', '#E8BC48'], cell=9)
    P.fill(box(M, (14.2, top + 1.2, -10.6), (15.8, top + 1.5, -10.0)), ['#C9874E'], cell=9)
    # a fresh tart on a stand
    P.fill(cyl_y(M, (6.6, -7.2), 0.25, top, top + 0.8) | cyl_y(M, (6.6, -7.2), 1.4, top + 0.8, top + 1.0), ['#FBF5E8'], cell=9)
    tart = cyl_y(M, (6.6, -7.2), 1.2, top + 1.0, top + 1.6)
    P.fill(tart, ['#E3B26A', '#D9A35A'], cell=9)
    P.fill(tart & (M.Y >= top + 1.4) & (((M.X - 6.6) ** 2 + (M.Z + 7.2) ** 2) < 0.8), ['#E8513F', '#D84535'], cell=9)
    # shelves above the counter with plates and jars, copper pots on a rail
    for sy in (9.0, 12.4):
        shelf_board(P, M, cx0 + 1.0, cx1 - 1.0, sy, R['back'], R['back'] + 1.6)
        for k, jx in enumerate(np.arange(cx0 + 2.0, cx1 - 1.5, 1.6)):
            if (k + int(sy)) % 3 == 0:
                P.fill(((M.X - jx) ** 2 + (M.Y - sy - 1.0) ** 2 <= 1.0) & (M.Z >= R['back'] + 0.2) & (M.Z < R['back'] + 0.6), ['#FBF5E8', '#BFE4FA'], cell=9)
            else:
                jar(P, M, jx, sy, R['back'] + 0.8, h=1.2 + 0.2 * (k % 2), r=0.5, cols=[GLASS_AMBER, GLASS_ROSE, GLASS_MINT, ['#F3E5C9']][k % 4])
    P.fill(box(M, (cx0 + 1.0, 15.6, R['back'] + 1.6), (cx1 - 1.0, 15.9, R['back'] + 1.9)), IRON, cell=9)
    for k, px in enumerate(np.arange(cx0 + 2.5, cx1 - 1.5, 2.8)):
        r_ = 0.9 + 0.2 * (k % 2)
        P.fill(box(M, (px - 0.1, 14.0, R['back'] + 1.6), (px + 0.1, 15.6, R['back'] + 1.9)), IRON, cell=9)
        P.fill(((M.X - px) ** 2 + (M.Y - 13.2) ** 2 <= r_ * r_) & (M.Z >= R['back'] + 1.4) & (M.Z < R['back'] + 2.4), COPPER, cell=9)
    # hanging herb bundles and garlic from a beam over the room
    for k, hx in enumerate(np.arange(-14.0, 15.0, 3.2)):
        hz = 2.0 + (k % 2) * 3.0
        P.fill(box(M, (hx - 0.18, 16.0, hz - 0.18), (hx + 0.18, R['h'] - 1.4, hz + 0.18)), ['#8D5D3B'], cell=9)
        P.fill(ball(M, (hx, 15.4, hz), 0.8, 1.4), [['#6FB24E', '#5EA046'], ['#FBF5E8', '#EFE6D2'], ['#86C56A', '#7F9871']][k % 3], cell=0.5)
    # the window on the right wall, with sun coming through
    wz0, wz1, wy0, wy1 = -6.0, 3.0, 6.0, 12.5
    win = box(M, (R['x1'] - 0.2, wy0, wz0), (R['x1'] + 1.2, wy1, wz1))
    M.m[win] = 0
    P.fill(win & ((((M.Z - wz0) % 3.0) < 0.5) | (np.abs(M.Y - (wy0 + wy1) / 2) < 0.3) | (M.Z >= wz1 - 0.5) | (M.Y < wy0 + 0.5) | (M.Y >= wy1 - 0.5)), WALNUT, cell=9)
    P.fill(win & (M.m == 0) & (M.X >= R['x1'] + 0.6), CLEAR_GLASS, cell=50)
    P.fill(box(M, (R['x1'] - 1.0, wy0 - 0.4, wz0), (R['x1'], wy0, wz1)), HONEY, cell=9)
    for k, fz in enumerate((-4.6, -1.6, 1.4)):
        flower_pot(P, M, R['x1'] - 0.5, wy0, fz, 0.5, FLOWERS[k + 1], rng)
    S.lights.append({'type': 'sun', 'dir': (-0.75, -0.55, -0.2), 'power': 3.0, 'color': 5200, 'angle': 2.0})
    S.lights.append({'type': 'area', 'pos': (0.0, 18.0, 22.0), 'aim': (0.0, 4.0, -6.0), 'size': (30.0, 8.0), 'power': 70.0, 'color': 5600})
    # a small round table front right with a teapot, a rug on the floor
    table(P, M, 9.0, 15.0, 4.0, 9.0, 4.4, cols=HONEY)
    P.fill(ball(M, (11.5, 5.4, 6.4), 1.0, 0.85) & (M.Y >= 4.4), ['#BFE4FA', '#A9D6F2'], cell=9)
    P.fill(box(M, (12.4, 5.2, 6.2), (13.4, 5.6, 6.6)), ['#BFE4FA'], cell=9)
    P.fill(cyl_y(M, (13.6, 7.4), 0.5, 4.4, 5.2), ['#FBF5E8'], cell=9)
    rug(P, M, -2.0, 8.0, 7.0, 4.2, ['#D85F51', '#C94C40'], ['#F4C04E'])
    lantern(S, P, M, (-1.0, 15.0, 4.0), s=0.8, lit=True, power=18.0, hang_to=R['h'] - 1.4)
    for (x, z, s_, kind) in ((-16.0, 8.0, 1.4, 1), (16.4, 12.0, 1.1, 0)):
        flower_pot(P, M, x, 0.0, z, s_, FLOWERS[int(abs(x)) % 5], rng, kind)
    barrel(P, M, -16.4, -4.0, 1.4, 3.0)
    for k in range(3):
        P.fill(ball(M, (-16.8 + 0.6 * k, 3.4, -4.0 + 0.3 * k), 0.5, 0.8), [['#F0C95A'], ['#E3B26A'], ['#F0C95A']][k], cell=9)   # loaves
    S.models.append((M, CLEAR_GLASS))
    S.grade = {'vignette': 0.16, 'warm': 0.03, 'bloom': 0.32}
    return S


# ------------------------------------------------------------------ the Apothecary ----
def scene_apothecary():
    """The Cottage's back room: a bubbling cauldron, shelves of glowing bottles, drying herbs, a
    workbench with a mortar and an open recipe book, a round window."""
    S = VScene('apothecary', INTERIOR_W, INTERIOR_H, interior_cam(), world=((0.72, 0.8, 0.9), 0.14), samples=192)
    M = Model((-20, -2, -14), (20, 22, 29), [], res=4)
    P = CPainter(M, 91)
    rng = np.random.default_rng(91)
    R = ROOM
    room_shell(P, M, STONE_LT, ['#E7E0CC', '#DDD4BD', '#E2DAC4'], side_cols=['#DCD3BB', '#D4CAB0'], floor_cell=(1.5, 1, 1.5),
               wall_cell=(3, 3, 3))
    fl = box(M, (R['x0'] - 1, -1, R['back'] - 1), (R['x1'] + 1, 0, R['near']))
    P.fill(fl, ['#D3CCB9', '#C9C2AE', '#DCD6C4', '#CFC8B4'], cell=(3.0, 1, 3.0))     # stone flags over the shell's planks
    P.fill(fl & (M.Y >= -0.3) & ((((M.X - R['x0']) % 3.0) < 0.22) | (((M.Z - R['back']) % 3.0) < 0.22)), ['#B4AC98'], cell=9)
    # sage-green wainscot
    P.fill(box(M, (R['x0'] - 1, 0, R['back'] - 1), (R['x1'] + 1, 4.0, R['back'] + 0.2)), ['#7F9871', '#76906A'], cell=(1.4, 9, 9))
    for sx in (R['x0'] - 1, R['x1']):
        P.fill(box(M, (sx - 0.2, 0, R['back']), (sx + 1.2, 4.0, R['front'])), ['#7F9871', '#76906A'], cell=(9, 9, 1.4))
    # ---- the cauldron on a little stone fire ring (back left of centre)
    cx, cz = -6.5, -5.5
    P.fill(cyl_y(M, (cx, cz), 3.4, 0, 0.8) & ~cyl_y(M, (cx, cz), 2.4, 0, 0.8), STONE, cell=0.75)
    P.fill(ball(M, (cx, 0.9, cz), 1.6, 0.5) & (M.Y >= 0), ['#FF9A4A', '#FFB65C'], glow=1.0, cell=0.5)
    pot = ball(M, (cx, 3.6, cz), 3.0, 0.9) & ~ball(M, (cx, 3.6, cz), 2.5, 0.9) & (M.Y < 5.6) & (M.Y >= 1.2)
    P.fill(pot, IRON, cell=0.75)
    P.fill(cyl_y(M, (cx, cz), 2.75, 5.4, 6.0) & ~cyl_y(M, (cx, cz), 2.2, 5.4, 6.0), ['#554943'], cell=9)    # rim
    brew = cyl_y(M, (cx, cz), 2.3, 4.6, 5.3)
    P.fill(brew, ['#9FE3CF', '#BDF2E2', '#86D9C0'], glow=0.9, cell=0.5)
    for (bx, bz, br) in ((-0.8, 0.4, 0.45), (0.9, -0.5, 0.35), (0.2, 1.0, 0.3)):
        P.fill(ball(M, (cx + bx, 5.6, cz + bz), br), ['#D6F7EC'], glow=1.0, cell=9)
    for k in range(4):
        P.fill(ball(M, (cx + 0.4 * math.sin(k * 1.7), 7.0 + k * 1.3, cz + 0.3 * k), 0.6 + 0.18 * k) & (M.m == 0), ['#E8FBF4', '#D6F7EC'], cell=0.5)
    for lx in (cx - 2.2, cx + 2.0):
        P.fill(box(M, (lx - 0.3, 0.8, cz - 0.3), (lx + 0.3, 2.2, cz + 0.3)), IRON, cell=9)
    S.lights.append({'type': 'point', 'pos': (cx, 6.2, cz + 0.5), 'power': 26.0, 'color': 6500, 'radius': 1.0})
    S.lights.append({'type': 'point', 'pos': (cx, 1.2, cz + 2.0), 'power': 14.0, 'color': 1900, 'radius': 0.8})
    # ---- tall shelves of glowing bottles (back right)
    sx0, sx1 = 2.0, 16.5
    P.fill(box(M, (sx0, 0, R['back']), (sx1, 15.0, R['back'] + 2.2)) & ~box(M, (sx0 + 0.5, 0.5, R['back'] + 0.3), (sx1 - 0.5, 14.5, R['back'] + 2.2)),
           WALNUT, cell=(9, 9, 9))
    cols_ = [GLASS_MINT, GLASS_ROSE, GLASS_AMBER, GLASS_VIOLET, ['#BFE4FA', '#A9D6F2']]
    for i, sy in enumerate((0.5, 4.0, 7.5, 11.0)):
        P.fill(box(M, (sx0 + 0.5, sy, R['back'] + 0.3), (sx1 - 0.5, sy + 0.4, R['back'] + 2.2)), OAK_DARK, cell=9)
        for k, bx in enumerate(np.arange(sx0 + 1.4, sx1 - 0.8, 1.35)):
            h_ = 1.4 + 0.6 * ((k * 7 + i * 3) % 3) / 2
            col = cols_[(k + i * 2) % len(cols_)]
            if (k + i) % 5 == 4:
                books_x = bx
                for b in range(3):
                    P.fill(box(M, (books_x - 0.5 + b * 0.35, sy + 0.4, R['back'] + 0.6), (books_x - 0.2 + b * 0.35, sy + 2.4 - 0.2 * b, R['back'] + 1.9)),
                           [['#203B50'], ['#B76B4D'], ['#7F9871']][b], cell=9)
                continue
            glow = 0.55 if (k + i) % 2 == 0 else None
            P.fill(cyl_y(M, (bx, R['back'] + 1.2), 0.5, sy + 0.4, sy + 0.4 + h_), col, glow=glow, cell=9)
            P.fill(cyl_y(M, (bx, R['back'] + 1.2), 0.22, sy + 0.4 + h_, sy + 0.9 + h_), ['#C69469'], cell=9)
    S.lights.append({'type': 'area', 'pos': (9.0, 9.0, -6.5), 'aim': (9.0, 7.0, -12.0), 'size': (12.0, 10.0), 'power': 18.0, 'color': 5000})
    # ---- the round window (back left) with daylight
    wcx, wcy = -12.0, 11.0
    rw = np.sqrt((M.X - wcx) ** 2 + (M.Y - wcy) ** 2)
    win = (rw <= 3.4) & (M.Z >= R['back'] - 1.0) & (M.Z < R['back'] + 0.2)
    M.m[win] = 0
    P.fill(win & ((rw > 2.8) | (np.abs(M.X - wcx) < 0.3) | (np.abs(M.Y - wcy) < 0.3)), WALNUT, cell=9)
    P.fill(win & (M.m == 0) & (M.Z < R['back'] - 0.5), CLEAR_GLASS, cell=50)
    S.models.append((surround(-26.0, 22.0, 24.0, seed=6), (), {'shadow': False}))
    S.lights.append({'type': 'sun', 'dir': (0.35, -0.6, 0.7), 'power': 2.6, 'color': 5600, 'angle': 2.0})
    # ---- drying rack with herb bundles hanging from the ceiling
    P.fill(box(M, (-16.0, 15.2, 1.0), (14.0, 15.6, 1.4)), HONEY, cell=9)
    for k, hx in enumerate(np.arange(-15.0, 13.5, 2.0)):
        P.fill(box(M, (hx - 0.08, 13.6, 1.1), (hx + 0.08, 15.2, 1.3)), ['#C9A26E'], cell=9)
        cols_h = [['#6FB24E', '#5EA046'], ['#AA8BCF', '#9975C9'], ['#86C56A', '#7F9871'], ['#F4C04E', '#E8B04A']][k % 4]
        P.fill(ball(M, (hx, 12.8, 1.2), 0.75, 1.5), cols_h, cell=0.5)
    # ---- the workbench (front right): mortar and pestle, an open book, candles, scales
    table(P, M, 6.0, 16.0, 4.0, 9.4, 4.6, cols=OAK)
    mort = cyl_y(M, (8.4, 6.0), 1.1, 4.6, 5.8) & ~cyl_y(M, (8.4, 6.0), 0.7, 5.2, 5.9)
    P.fill(mort, STONE_LT, cell=9)
    P.fill(cyl_y(M, (8.4, 6.0), 0.7, 5.2, 5.5), ['#86C56A'], cell=9)
    P.fill((np.abs(M.Y - 5.6 - (M.X - 8.6) * 1.2) < 0.25) & (M.X > 8.6) & (M.X < 9.6) & (np.abs(M.Z - 6.0) < 0.25), STONE, cell=9)
    book = box(M, (10.6, 4.6, 5.0), (14.4, 4.9, 7.6))
    P.fill(book, PARCH, cell=9)
    P.fill(book & (np.abs(M.X - 12.5) < 0.15), ['#C9A26E'], cell=9)
    P.fill(box(M, (10.4, 4.5, 4.8), (14.6, 4.7, 7.8)), ['#B76B4D'], cell=9)
    for (lx, lz) in ((15.2, 5.0), (15.4, 8.4)):
        P.fill(cyl_y(M, (lx, lz), 0.35, 4.6, 6.0), ['#FBF5E8'], cell=9)
        P.fill(ball(M, (lx, 6.3, lz), 0.25, 1.4), ['#FFD46A'], glow=1.0, cell=9)
        S.lights.append({'type': 'point', 'pos': (lx, 6.6, lz), 'power': 3.0, 'color': 2000, 'radius': 0.2})
    P.fill(box(M, (6.8, 4.6, 8.2), (7.2, 6.8, 8.6)), BRASS, cell=9)
    P.fill(box(M, (6.0, 6.6, 8.3), (8.0, 6.8, 8.5)), BRASS, cell=9)
    for sxx in (6.1, 7.9):
        P.fill(cyl_y(M, (sxx, 8.4), 0.6, 5.6, 5.8), BRASS, cell=9)
    # a big star chart on the left wall, potted herbs, a stool
    chart = (M.X >= R['x0']) & (M.X < R['x0'] + 0.3) & (M.Y >= 6.0) & (M.Y < 13.0) & (M.Z >= -2.0) & (M.Z < 6.0)
    P.fill(chart, ['#203B50', '#284A63'], cell=9)
    for k in range(9):
        P.fill(box(M, (R['x0'], 6.5 + rng.uniform(0, 6), -1.6 + rng.uniform(0, 7)), (R['x0'] + 0.5, 6.8 + 0.3, 0.0)) & chart &
               (np.abs(M.Z - (-1.6 + (k * 0.83))) < 0.2) & (np.abs(M.Y - (7.0 + (k * 0.71) % 5.5)) < 0.2), ['#FFE5A2'], glow=0.9, cell=9)
    for (x, z, s_, kind) in ((-16.4, 9.0, 1.3, 1), (16.4, 12.0, 1.0, 2), (-16.0, -9.0, 1.1, 0)):
        flower_pot(P, M, x, 0.0, z, s_, FLOWERS[int(abs(x)) % 5], rng, kind)
    P.fill(cyl_y(M, (3.0, 10.0), 1.0, 2.4, 2.8), HONEY, cell=9)
    for (dx, dz) in ((-0.6, -0.6), (0.6, 0.6), (-0.6, 0.6), (0.6, -0.6)):
        P.fill(box(M, (3.0 + dx - 0.15, 0, 10.0 + dz - 0.15), (3.0 + dx + 0.15, 2.4, 10.0 + dz + 0.15)), WALNUT, cell=9)
    rug(P, M, -3.0, 9.0, 6.0, 3.6, ['#7F9871', '#76906A'], ['#E8B956'])
    lantern(S, P, M, (2.0, 15.0, 6.0), s=0.75, lit=True, power=14.0, hang_to=R['h'] - 1.4)
    S.lights.append({'type': 'area', 'pos': (0.0, 18.0, 22.0), 'aim': (0.0, 4.0, -6.0), 'size': (30.0, 8.0), 'power': 60.0, 'color': 5200})
    S.models.append((M, CLEAR_GLASS))
    S.grade = {'vignette': 0.18, 'bloom': 0.4}
    return S


def surround(*a, **k):
    from village_scenes import surround as _s
    return _s(*a, **k)


def scene_cottage(restored=False):
    """Close-up of the cottage for its own screen: the Home Map's world, a lower camera in front of the door."""
    S = scene_home_map(restored)
    S.name = 'cottage_' + ('restored' if restored else 'ruined')
    S.w, S.h = 1170, 810
    S.cam = {'pos': (-15.0, 19.0, 4.0), 'target': (-15.6, 2.6, -24.5), 'fov': 44.0}
    S.anchors = {'door': (-16.0, 2.0, -19.5)}
    return S


SCENES = {'home_map_ruined': lambda: scene_home_map(False), 'home_map_restored': lambda: scene_home_map(True),
          'garden': scene_garden, 'kitchen': scene_kitchen, 'apothecary': scene_apothecary,
          'cottage_ruined': lambda: scene_cottage(False), 'cottage_restored': lambda: scene_cottage(True)}

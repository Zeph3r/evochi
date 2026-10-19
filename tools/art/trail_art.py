"""Lumen Trails art drawn with the flat item renderer: the three forest creatures (with their
encounter states), the new items and the UI icons for discoveries, encounters and affinities.

  python3 trail_art.py ASSETS_DIR [creatures|items|icons ...]
    ASSETS/trails/creature_<id>_<state>.png   sprites (one shared fit per creature) + ASSETS/trails/creatures.json
    ASSETS/items/item_<id>_icon.png           256px item icons (picked up by the web packer)
    ASSETS/ui_icons/icon_<k>.png              192px UI icons

Creatures face front-left like the player's Evochi; the game flips the wild side with CSS.
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from scipy import ndimage

from voxel import Camera, render, save_rgba, fit_camera, project_px, model_extent_points
from items import M_, ell, cyl, flower, LEAF, LEAF_HI, LEAF_LO, WHITE, GOLD
from characters import spike
from build_items import render_model, LIGHT
from home_items import put, box, ycyl, glowleaf, mushroom, MINT, MINT_HI, MINT_LO, CREAM

# ------------------------------------------------------------------ palette
CREAM_BODY, CREAM_LO = '#F4F7E8', '#E2E8CF'
SOFT_GREEN, SOFT_GREEN_HI = '#A5CD82', '#C4E2A6'
PINK, PINK_HI, PINK_LO = '#F5A3B5', '#FBC6D1', '#E0849A'
INK, EYE_HI = '#282725', '#FFFFFF'
BLUSH = '#F2A58F'
FEET_G, FEET_G_LO = '#7F9871', '#5E7F4A'
HOLLOW_BODY, HOLLOW_BODY_LO, HOLLOW_BODY_HI = '#54407A', '#3F2E62', '#6B5594'
VIOLET, VIOLET_HI, VIOLET_LO = '#9975C9', '#C8B1E4', '#6E4FA3'
VINE_H, VINE_H_HI = '#43306B', '#5A4388'
GLOW_V = '#D9C2FF'
STONE_B, STONE_B_LO, STONE_B_HI = '#A8A297', '#837D74', '#C4BEB1'
MOSS_B, MOSS_B_HI = '#6E9A4C', '#8ABB66'
RUNE_LIT = '#BDF7E4'
AMBER, AMBER_HI = '#F4B84E', '#FFE5A2'
COPPER = '#C9874E'
IRON = '#4A3F3A'
GLASS = '#CDEBF5'


def shell(M, body, depth=1):
    """The outer `depth` voxels of a filled region (where faces get painted)."""
    er = ndimage.binary_erosion(body, structure=ndimage.generate_binary_structure(3, 1), iterations=depth, border_value=0)
    return body & ~er


def front(M, body, cx, cy, u, v, w, h, zmin=None, depth=2, p=2.0):
    """Voxels on the front of `body` inside an ellipse at face coordinates (u right, v up) from (cx, cy)."""
    sh = shell(M, body, depth)
    e = (np.abs((M.X - cx - u) / w) ** p + np.abs((M.Y - cy - v) / h) ** p) <= 1.0
    m = sh & e & (M.Z > (zmin if zmin is not None else 0))
    return m


def eye(M, body, cx, cy, u, v, w, h, kind='round', col=INK, hi=True):
    """Eyes on the front face: round, happy (an arc), wary (big with a worried lid) or slit (glowing)."""
    if kind == 'happy':
        m = front(M, body, cx, cy, u, v, w * 1.1, h * 0.75)
        inner = front(M, body, cx, cy, u, v - h * 0.45, w * 0.9, h * 0.6)
        put(M, m & ~inner, col)
        return m
    if kind == 'wary':
        m = front(M, body, cx, cy, u, v, w * 1.25, h * 1.1)
        put(M, m, EYE_HI)
        put(M, front(M, body, cx, cy, u + w * 0.15, v - h * 0.1, w * 0.62, h * 0.55), col)
        if hi:
            put(M, front(M, body, cx, cy, u - w * 0.05, v + h * 0.1, w * 0.2, h * 0.2), EYE_HI)
        return m
    if kind == 'slit':
        m = front(M, body, cx, cy, u, v, w * 1.1, h * 0.55)
        put(M, m, col, glow=0.9)
        return m
    if kind == 'calm':
        m = front(M, body, cx, cy, u, v, w, h * 0.7)
        put(M, m, col)
        if hi:
            put(M, front(M, body, cx, cy, u - w * 0.3, v + h * 0.1, w * 0.3, h * 0.25), EYE_HI)
        return m
    m = front(M, body, cx, cy, u, v, w, h)
    put(M, m, col)
    if hi:
        put(M, front(M, body, cx, cy, u - w * 0.35, v + h * 0.3, w * 0.32, h * 0.3), EYE_HI)
    return m


def mouth(M, body, cx, cy, v, w, kind='smile', col=INK):
    if kind == 'smile':
        m = front(M, body, cx, cy, 0, v, w, w * 0.6) & ~front(M, body, cx, cy, 0, v + w * 0.35, w * 0.85, w * 0.55)
    elif kind == 'open':
        m = front(M, body, cx, cy, 0, v, w * 0.7, w * 0.5)
    elif kind == 'worry':
        m = front(M, body, cx, cy, 0, v, w, w * 0.6) & ~front(M, body, cx, cy, 0, v - w * 0.35, w * 0.85, w * 0.55)
    else:
        m = front(M, body, cx, cy, 0, v, w * 0.6, w * 0.12)
    put(M, m, col)


# ------------------------------------------------------------------ Petalune (Nature)
def petalune(state='neutral'):
    M = M_((-14, -1, -14), (14, 26, 14), res=2)
    crouch = 0.92 if state == 'wary' else 1.0
    body = ell(M, (0, 8.6 * crouch, 0), (8.2, 7.6 * crouch, 7.6), p=2.3)
    put(M, body, CREAM_BODY)
    # soft green back and a leafy "cape" down the spine
    put(M, body & (M.Z < -1.5) & (M.Y > 6.0 * crouch), SOFT_GREEN)
    put(M, body & (M.Z < -3.5) & (M.Y > 9.0 * crouch) & (M.X < 0), SOFT_GREEN_HI)
    put(M, shell(M, body, 1) & (M.Y < 4.2 * crouch), CREAM_LO)
    # belly oval
    put(M, front(M, body, 0, 5.8 * crouch, 0, 0, 4.2, 3.0, depth=1), '#FBFCF3')
    # leaf ears: a pair of big leaves, swept back when wary
    for s in (-1, 1):
        if state == 'wary':
            d = (s * 0.55, 0.35, -0.85)
        elif state == 'happy':
            d = (s * 0.6, 0.95, -0.15)
        else:
            d = (s * 0.65, 0.8, -0.3)
        lf = spike(M, (s * 4.6, 13.0 * crouch, -1.0), d, 8.0, 2.6, 0.5, twist=0.3 * s)
        put(M, lf & (M.m == 0), LEAF if s > 0 else LEAF_HI)
        vein = spike(M, (s * 4.6, 13.0 * crouch, -1.0), d, 7.0, 0.55, 0.4, twist=0.3 * s) & lf
        put(M, vein, LEAF_LO)
    # flower crest
    fy = 15.2 * crouch
    put(M, ycyl(M, (0.4, 0.6), 0.45, fy - 0.5, fy + 1.4), LEAF_LO)
    flower(M, (0.4, fy + 2.0, 0.9), n=(0.1, 0.9, 0.45), size=1.6 if state != 'happy' else 1.9, petal=PINK, centre=GOLD)
    if state == 'happy':
        put(M, ell(M, (0.4, fy + 2.0, 0.9), (0.6, 0.6, 0.6)), AMBER_HI, glow=0.9)
    # leaf tail
    tl = spike(M, (-1.0, 4.5 * crouch, -6.0), (-0.3, 0.55, -0.9), 6.5, 2.0, 0.4, twist=0.2)
    put(M, tl & (M.m == 0), LEAF)
    # feet
    for s in (-1, 1):
        f = box(M, (s * 4.6 - 2.2, 0, 1.0), (s * 4.6 + 2.2, 2.4, 5.6))
        put(M, f & (M.m == 0) | (f & body & (M.Y < 1.6)), FEET_G)
        put(M, f & (M.Y < 0.8), FEET_G_LO)
        for c in np.linspace(s * 4.6 - 1.3, s * 4.6 + 1.3, 3):
            put(M, box(M, (c - 0.45, 0, 5.4), (c + 0.45, 1.2, 6.4)), CREAM)
    # face
    cy = 9.4 * crouch
    kind = {'wary': 'wary', 'happy': 'happy', 'neutral': 'round', 'shy': 'calm'}[state]
    for s in (-1, 1):
        eye(M, body, 0, cy, s * 3.4, 0.6, 1.5, 2.2, kind=kind)
        put(M, front(M, body, 0, cy, s * 5.6, -1.9, 1.3, 0.8), BLUSH)
    mouth(M, body, 0, cy, -2.4, 1.3, kind={'wary': 'worry', 'happy': 'open', 'neutral': 'smile', 'shy': 'smile'}[state])
    if state == 'happy':
        put(M, front(M, body, 0, cy, 0, -2.6, 0.8, 0.35), PINK_LO)
    anchors = {'ground': (0, 0, 0), 'top': (0, fy + 3.8, 0), 'face': (0, cy, 7.6)}
    return M, anchors


# ------------------------------------------------------------------ Hollow Sprout (Hollow -> Nature)
def hollow_sprout(state='hollow'):
    M = M_((-14, -1, -14), (14, 28, 14), res=2)
    hollow = state == 'hollow'
    body_col, lo, hi = (HOLLOW_BODY, HOLLOW_BODY_LO, HOLLOW_BODY_HI) if hollow else (LEAF, LEAF_LO, LEAF_HI)
    # a bulb: wide at the bottom, narrowing to a sprout on top
    bulb = (np.sqrt(M.X ** 2 + M.Z ** 2) <= 7.4 * np.sqrt(np.clip(1 - ((M.Y - 5.0) / 9.5) ** 2, 0, 1)) + 0.6) & (M.Y >= 0) & (M.Y < 14.0)
    put(M, bulb, body_col)
    put(M, shell(M, bulb, 1) & (M.Y < 3.0), lo)
    put(M, shell(M, bulb, 1) & (M.Y > 8.0) & (M.X < -1.0) & (M.Z > 0), hi)
    # scales / ridges around the bulb
    ridge = shell(M, bulb, 1) & ((np.floor((np.arctan2(M.Z, M.X) + math.pi) / (math.pi / 4)) + np.floor(M.Y / 3.0)) % 2 == 0) & (M.Y > 2.0) & (M.Y < 11.0) & (M.Z < 4.0)
    put(M, ridge, lo if hollow else '#6FA552')
    # the sprout on top
    put(M, ycyl(M, (0, 0), 0.9, 13.0, 16.5), lo if hollow else LEAF_LO)
    for s in (-1, 1):
        if hollow:
            d = (s * 0.9, 0.15, 0.1)     # wilted, drooping
            lf = spike(M, (0, 16.0, 0), d, 6.0, 2.2, 0.4, twist=0.4 * s)
            put(M, lf & (M.m == 0), '#6B5594' if s > 0 else '#7D68A6')
        else:
            d = (s * 0.7, 0.85, 0.1)
            lf = spike(M, (0, 16.0, 0), d, 7.0, 2.6, 0.5, twist=0.3 * s)
            put(M, lf & (M.m == 0), LEAF if s > 0 else LEAF_HI)
            vein = spike(M, (0, 16.0, 0), d, 6.2, 0.5, 0.4, twist=0.3 * s) & lf
            put(M, vein, LEAF_LO)
    if not hollow:
        put(M, ycyl(M, (0, 0), 0.4, 16.0, 19.0), LEAF_LO)
        flower(M, (0, 19.8, 0.4), n=(0, 0.95, 0.3), size=1.5, petal=WHITE, centre=GOLD)
    # roots / little feet
    for s in (-1, 1):
        for (dz, ln) in ((2.5, 3.0), (-2.5, 2.4)):
            r = spike(M, (s * 4.5, 1.0, dz), (s * 0.9, -0.3, 0.3 * np.sign(dz)), ln, 1.1, 0.35)
            put(M, r & (M.m == 0), lo if hollow else '#8D6A4B')
    if hollow:
        # Hollow vines wrapped around the bulb, and crystals pushing out of its back
        for k in range(3):
            for t in np.linspace(0, 1, 40):
                a = t * 2 * math.pi * 1.2 + k * 2.1
                y = 2.0 + t * 9.0 + k * 0.8
                rr = 7.4 * math.sqrt(max(0.0, 1 - ((y - 5.0) / 9.5) ** 2)) + 0.9
                if math.sin(a) > 0.55 and 4.0 < y < 11.0:
                    continue   # never across the face
                put(M, ell(M, (rr * math.cos(a), y, rr * math.sin(a)), (0.75, 0.6, 0.75)), VINE_H if k % 2 else VINE_H_HI)
                if int(t * 40) % 9 == 4:
                    put(M, ell(M, (rr * math.cos(a), y + 0.6, rr * math.sin(a)), (0.5, 0.5, 0.5)), GLOW_V, glow=0.9)
        for (cx, cz, h) in ((-3.0, -5.5, 4.5), (2.5, -6.0, 3.6), (5.5, -3.0, 2.8)):
            for t in np.linspace(0, 1, 12):
                r = 1.0 * (1 - t * 0.8) + 0.2
                put(M, ell(M, (cx + t * 0.4, 8.0 + t * h, cz - t * 1.2), (r, r * 0.9, r)), VIOLET if t < 0.7 else VIOLET_HI, glow=0.5 + 0.4 * t)
        for s in (-1, 1):
            put(M, front(M, bulb, 0, 7.6, s * 3.0, 0.4, 2.1, 1.9, depth=2), HOLLOW_BODY_LO)
            eye(M, bulb, 0, 7.6, s * 3.0, 0.4, 1.7, 1.6, kind='slit', col=GLOW_V, hi=False)
        mouth(M, bulb, 0, 7.6, -2.4, 1.3, kind='worry', col=GLOW_V)
        # a sad little crack across the front
        put(M, front(M, bulb, 0, 4.0, 2.5, 0, 0.4, 1.8, depth=1), HOLLOW_BODY_LO)
    else:
        for s in (-1, 1):
            eye(M, bulb, 0, 7.6, s * 3.0, 0.4, 1.4, 1.9, kind='calm')
            put(M, front(M, bulb, 0, 7.6, s * 5.0, -1.5, 1.2, 0.7), BLUSH)
        mouth(M, bulb, 0, 7.6, -2.0, 1.2, kind='smile')
        # a few flowers where the vines were
        for (fx, fy, fz) in ((-5.5, 6.0, 4.0), (5.8, 4.0, 3.6), (-4.0, 10.0, 2.5)):
            flower(M, (fx, fy, fz), n=(fx / 7.0, 0.3, 0.9), size=0.9, petal=PINK, centre=GOLD)
    anchors = {'ground': (0, 0, 0), 'top': (0, 21.5 if not hollow else 18.5, 0), 'face': (0, 7.6, 7.5)}
    return M, anchors


# ------------------------------------------------------------------ Forgotten Sentinel (Hollow -> Celestial)
def sentinel(state='hollow'):
    M = M_((-22, -1, -18), (22, 40, 18), res=2)
    dormant = state == 'dormant'          # before it wakes (the awakening cinematic): eyes and cracks dark
    hollow = state in ('hollow', 'waking', 'dormant')
    waking = state == 'waking'
    glowc = GLOW_V if hollow else RUNE_LIT
    crystal_col = (VIOLET, VIOLET_HI) if hollow else (MINT, MINT_HI)
    # a hunched body of stacked stones: hips, torso, shoulders, head
    hips = ell(M, (0, 6.0, 0), (10.5, 5.5, 8.0), p=2.6)
    torso = ell(M, (0, 14.0, -0.5), (12.5, 7.5, 9.0), p=2.6)
    shoulders = ell(M, (0, 20.5, -1.5), (14.5, 4.5, 8.5), p=2.8)
    head = ell(M, (0, 27.0, 1.0), (7.5, 6.0, 6.5), p=2.4)
    body = hips | torso | shoulders | head
    put(M, body, STONE_B)
    # stone courses: horizontal seams and a slightly darker lower half
    seams = shell(M, body, 1) & ((np.floor((M.Y + 0.4) / 3.2) % 2) == 0) & ((np.floor((M.X + M.Y * 0.3) / 4.0) % 2) == 0)
    put(M, seams, STONE_B_LO)
    put(M, shell(M, body, 1) & (M.Y < 3.0), STONE_B_LO)
    put(M, shell(M, body, 1) & (M.X < -4.0) & (M.Z > 0) & (M.Y > 10), STONE_B_HI)
    # arms: a big resting arm on the right, a raised one on the left
    arm_r = ell(M, (13.0, 7.0, 4.0), (4.6, 7.0, 4.6), p=2.4) | ell(M, (16.0, 2.0, 6.0), (5.0, 2.4, 4.6), p=2.4)
    arm_l = ell(M, (-14.5, 15.0, 2.0), (4.2, 7.5, 4.2), p=2.4) | ell(M, (-15.5, 8.0, 5.0), (4.6, 2.6, 4.4), p=2.4)
    for a in (arm_r, arm_l):
        put(M, a & (M.m == 0), STONE_B)
        put(M, shell(M, a, 1) & (M.Y < 1.2), STONE_B_LO)
        for k in range(3):
            put(M, box(M, (-30, k * 1.0 - 0.2, 0), (30, k * 1.0 + 0.3, 20)) & a & (M.Y < 3.5) & (M.Z > 7.0), STONE_B_LO)
    body = body | arm_r | arm_l
    # moss on shoulders and head, flowers when restored
    moss = shell(M, body, 1) & (M.Y > 17.0) & (M.Z < 3.0) & (np.sin(M.X * 0.9) + np.cos(M.Z * 1.3) > 0.5)
    put(M, moss, MOSS_B)
    put(M, moss & (M.X < 0) & (M.Y > 22), MOSS_B_HI)
    put(M, shell(M, head, 1) & (M.Y > 31.0) & (np.sin(M.X * 1.7) > 0.2), MOSS_B)
    # crystals from the back and shoulders
    for (cx, cz, h, lean) in ((-6.0, -7.0, 9.0, (-0.08, -0.05)), (0.5, -8.5, 11.0, (0.0, -0.06)), (7.0, -7.0, 7.5, (0.08, -0.05)),
                              (-12.0, -3.0, 5.0, (-0.1, 0.0)), (12.5, -3.5, 4.5, (0.1, 0.0))):
        for t in np.linspace(0, 1, 16):
            r = 1.5 * (1 - t * 0.85) + 0.25
            y = 20.0 + t * h
            put(M, ell(M, (cx + lean[0] * t * h * 4, y, cz + lean[1] * t * h * 4), (r, r * 0.8, r)),
                crystal_col[0] if t < 0.7 else crystal_col[1], glow=0.08 if dormant else (0.45 if hollow else 0.35) + 0.4 * t)
    # chest rune and arm runes
    rune = front(M, torso, 0, 14.0, 0, 0.5, 2.2, 3.4, depth=2) & ~front(M, torso, 0, 14.0, 0, 0.5, 1.2, 2.3, depth=2)
    put(M, rune, glowc if (not hollow or waking) else STONE_B_LO, glow=0.8 if (not hollow or waking) else 0.0)
    put(M, front(M, torso, 0, 14.0, 0, 0.5, 0.5, 1.4, depth=2), STONE_B_LO if dormant else glowc, glow=0.0 if dormant else 0.9 if (not hollow or waking) else 0.35)
    for s in (-1, 1):
        band = shell(M, arm_r if s > 0 else arm_l, 1) & (np.abs(M.Y - (9.0 if s > 0 else 15.0)) < 0.5)
        put(M, band, glowc if not hollow else VIOLET_LO, glow=0.6 if not hollow else 0.25)
    # cracks glowing with Hollow energy
    if hollow:
        for (x0, y0, dx, dy) in ((4.0, 9.0, 0.6, 1.0), (-7.0, 12.0, -0.3, 1.0), (2.0, 22.0, 0.8, -0.5)):
            for t in np.linspace(0, 1, 14):
                put(M, front(M, body, 0, 0, x0 + dx * t * 5.0, y0 + dy * t * 5.0, 0.45, 0.45, depth=1), VIOLET_LO if dormant else VIOLET, glow=0.0 if dormant else 0.7)
    # face: two deep eye sockets with a glow inside
    for s in (-1, 1):
        sock = front(M, head, 0, 27.0, s * 3.2, 0.3, 2.0, 1.6, depth=3, p=2.4)
        put(M, sock, STONE_B_LO)
        M.clear(sock & (M.Z > 6.2))
        inner = front(M, head, 0, 27.0, s * 3.2, 0.3, 1.2 if state != 'hollow' else 0.9, 0.9 if hollow else 0.7, depth=4)
        if dormant:
            put(M, inner, '#2E2638')
        else:
            put(M, inner, '#F1E6FF' if waking else glowc, glow=1.0 if waking else 0.95 if not hollow else 0.55)
    if not hollow:
        # a gentle smile line and flowers in the moss
        mouth(M, head, 0, 27.0, -2.6, 2.0, kind='smile', col=STONE_B_LO)
        for (fx, fy, fz) in ((-9.0, 24.0, -2.0), (8.5, 24.5, -1.5), (-2.0, 32.5, -1.0), (3.5, 33.0, 0.5)):
            flower(M, (fx, fy, fz), n=(fx / 12.0, 0.9, 0.2), size=1.1, petal=WHITE if fx > 0 else PINK, centre=GOLD)
        glowleaf(M, (-13.0, 19.5, -1.0), s=0.6, glow=0.6, n=4)
    anchors = {'ground': (0, 0, 0), 'top': (0, 33.5, 0), 'face': (0, 27.0, 7.5),
               'eye_l': (-3.2, 27.3, 6.6), 'eye_r': (3.2, 27.3, 6.6), 'chest': (0, 14.5, 9.0)}
    return M, anchors


CREATURES = {
    'petalune': {'states': ['neutral', 'wary', 'happy'], 'build': petalune},
    'hollow_sprout': {'states': ['hollow', 'restored'], 'build': hollow_sprout},
    'sentinel': {'states': ['hollow', 'waking', 'restored'], 'build': sentinel},
}
# encounter views: turned toward your Evochi (in the lower left of the battle shot), seen from the battle
# camera's height: a touch above the small ones, from below for the Sentinel
BATTLE_STATES = {'sentinel': ['dormant', 'hollow', 'waking', 'restored']}
BATTLE_SCALE = 18.0          # px per unit: big on the encounter stage
BATTLE_CAM = {'petalune': Camera(yaw=26, pitch=7), 'hollow_sprout': Camera(yaw=26, pitch=7), 'sentinel': Camera(yaw=22, pitch=-6)}
CREATURE_CAM = Camera(yaw=18, pitch=12)
CREATURE_SCALE = 11.0          # px per unit (the Evochi hero sprites use 14): the Sentinel still towers


def creatures(out, only=None):
    d = os.path.join(out, 'trails')
    os.makedirs(d, exist_ok=True)
    mp = os.path.join(d, 'creatures.json')
    meta = json.load(open(mp)) if os.path.exists(mp) else {}
    for cid, spec in CREATURES.items():
        if only and cid not in only:
            continue
        models = {st: spec['build'](st) for st in spec['states']}
        pts = np.concatenate([model_extent_points(m) for m, _ in models.values()])
        sx, sy, _ = CREATURE_CAM.project(pts)
        pad = 14
        w = int(math.ceil((sx.max() - sx.min()) * CREATURE_SCALE + 2 * pad))
        h = int(math.ceil((sy.max() - sy.min()) * CREATURE_SCALE + 2 * pad))
        w += w % 2
        h += h % 2
        from voxel import Fit
        fit = Fit(CREATURE_SCALE, pad - sx.min() * CREATURE_SCALE, pad - sy.min() * CREATURE_SCALE, w, h)
        anchors = None
        for st, (M, anc) in models.items():
            o = render(M, {}, CREATURE_CAM, w, h, fit=fit, light=LIGHT, ss=3, outline_px=max(2.0, CREATURE_SCALE * 0.22),
                       outline_col='#3B2923', inner_thresh=2.0, inner_alpha=0.55, inner_px=0.8)
            save_rgba(o.rgba, os.path.join(d, f'creature_{cid}_{st}.png'))
            anchors = {k: project_px(CREATURE_CAM, fit, v)[0].round(1).tolist() for k, v in anc.items()}
            print('creature', cid, st, w, h, flush=True)
        meta[cid] = {'w': w, 'h': h, 'states': spec['states'], 'anchors': anchors}
        json.dump(meta, open(mp, 'w'), indent=1)


def creatures_battle(out, only=None):
    """The encounter sprites: turned toward your Evochi, no CSS flip; one fit per creature. Writes
    trails/creature_<id>_<state>_battle.png and trails/creatures_battle.json (w, h, states, anchors)."""
    d = os.path.join(out, 'trails')
    os.makedirs(d, exist_ok=True)
    mp = os.path.join(d, 'creatures_battle.json')
    meta = json.load(open(mp)) if os.path.exists(mp) else {}
    from voxel import Fit
    for cid, spec in CREATURES.items():
        if only and cid not in only:
            continue
        cam = BATTLE_CAM[cid]
        states = BATTLE_STATES.get(cid, spec['states'])
        models = {st: spec['build'](st) for st in states}
        pts = np.concatenate([model_extent_points(m) for m, _ in models.values()])
        sx, sy, _ = cam.project(pts)
        pad = 14
        w = int(math.ceil((sx.max() - sx.min()) * BATTLE_SCALE + 2 * pad))
        h = int(math.ceil((sy.max() - sy.min()) * BATTLE_SCALE + 2 * pad))
        w += w % 2
        h += h % 2
        fit = Fit(BATTLE_SCALE, pad - sx.min() * BATTLE_SCALE, pad - sy.min() * BATTLE_SCALE, w, h)
        anchors = None
        for st, (M, anc) in models.items():
            o = render(M, {}, cam, w, h, fit=fit, light=LIGHT, ss=3, outline_px=max(2.0, BATTLE_SCALE * 0.2),
                       outline_col='#3B2923', inner_thresh=2.0, inner_alpha=0.55, inner_px=0.8)
            save_rgba(o.rgba, os.path.join(d, f'creature_{cid}_{st}_battle.png'))
            anchors = {k: project_px(cam, fit, v)[0].round(1).tolist() for k, v in anc.items()}
            print('battle creature', cid, st, w, h, flush=True)
        meta[cid] = {'w': w, 'h': h, 'states': states, 'anchors': anchors}
        json.dump(meta, open(mp, 'w'), indent=1)


# ------------------------------------------------------------------ items
def ancient_relic():
    M = M_((-8, -1, -8), (8, 16, 8), res=2)
    tab = box(M, (-4.5, 0, -1.6), (4.5, 12.5, 1.6)) & ~(((M.Y > 10.5) & ((np.abs(M.X) - 2.5) > (12.5 - M.Y) * 1.0)))
    put(M, tab, STONE_B)
    put(M, tab & (M.Y < 1.0), STONE_B_LO)
    put(M, tab & (M.X < -2.5) & (M.Z > 0), STONE_B_HI)
    # chipped corner
    M.clear(box(M, (2.0, 9.0, -2), (5, 13, 2)) & tab & ((M.X - 2.0) > (12.5 - M.Y) * 0.9))
    # three trail grooves and a ring, glowing softly
    for gx in (-1.8, 0.0, 1.8):
        put(M, box(M, (gx - 0.35, 3.0, 1.2), (gx + 0.35, 8.0, 2.0)), MINT, glow=0.7)
    ring = (np.abs(np.sqrt(M.X ** 2 + (M.Y - 5.5) ** 2) - 3.2) < 0.45) & (M.Z > 1.2) & (M.Z < 2.0)
    put(M, ring & (M.m == 0), MINT_LO, glow=0.4)
    put(M, box(M, (-3.6, 0, -0.9), (3.6, 1.6, 2.2)), MOSS_B)
    return M, Camera(yaw=-18, pitch=14)


def lumen_shard():
    M = M_((-8, -1, -8), (8, 18, 8), res=2)
    for (cx, cz, h, r0, lean) in ((0.0, 0.0, 14.0, 2.6, (0.05, 0.0)), (3.2, 1.8, 7.0, 1.4, (0.25, 0.1)), (-3.0, 1.2, 5.5, 1.2, (-0.25, 0.1))):
        for t in np.linspace(0, 1, 18):
            r = r0 * (1 - t * 0.85) + 0.2
            put(M, ell(M, (cx + lean[0] * t * h, t * h, cz + lean[1] * t * h), (r, r * 0.9, r)),
                MINT if t < 0.6 else MINT_HI, glow=0.5 + 0.5 * t)
    put(M, box(M, (-4.0, 0, -3.0), (4.5, 1.0, 3.5)), STONE_B_LO)
    return M, Camera(yaw=-15, pitch=14)


def lantern_tonic():
    M = M_((-8, -1, -8), (8, 18, 8), res=2)
    body = box(M, (-3.4, 1.0, -3.4), (3.4, 10.0, 3.4))
    put(M, body, GLASS)
    liq = body & (M.Y < 8.0)
    put(M, liq, AMBER, glow=0.55)
    put(M, liq & (M.Y > 6.6), AMBER_HI, glow=0.7)
    for sx in (-1, 1):
        for sz in (-1, 1):
            put(M, box(M, (sx * 3.4 - 0.6, 0.6, sz * 3.4 - 0.6), (sx * 3.4 + 0.6, 10.6, sz * 3.4 + 0.6)), IRON)
    put(M, box(M, (-4.2, 0, -4.2), (4.2, 1.0, 4.2)), IRON)
    put(M, box(M, (-4.2, 10.0, -4.2), (4.2, 11.0, 4.2)) & ~box(M, (-2.6, 10.0, -2.6), (2.6, 11.0, 2.6)), IRON)
    put(M, box(M, (-2.6, 10.0, -2.6), (2.6, 11.0, 2.6)), AMBER_HI, glow=0.5)
    put(M, cyl(M, (0, 12.0, 0), 1.6, 2.0), COPPER)
    put(M, (np.abs(np.sqrt(M.X ** 2 + (M.Y - 13.6) ** 2) - 1.6) < 0.5) & (np.abs(M.Z) < 0.5) & (M.Y > 13.0), IRON)
    return M, Camera(yaw=-18, pitch=12)


def trail_badge():
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    r = np.sqrt(M.X ** 2 + M.Y ** 2)
    disc = (r <= 7.6) & (np.abs(M.Z) <= 1.4)
    put(M, disc, AMBER)
    put(M, disc & (r > 6.6), '#C8832C')
    put(M, disc & (r < 7.2) & (M.X < 0) & (M.Y > 0) & (M.Z > 0.6), AMBER_HI)
    a = np.arctan2(M.X, M.Y)
    star = (r <= 1.2 + 5.2 * np.clip(np.cos(4 * a), 0, 1) ** 2.2) & (M.Z > 0.8) & (M.Z <= 2.2)
    put(M, star, '#203B50')
    put(M, star & (M.X < 0.3) & (M.Y > -0.3), '#3C5F7E')
    put(M, (r <= 1.3) & (M.Z > 0.8) & (M.Z <= 2.4), MINT, glow=0.6)
    return M, Camera(yaw=-10, pitch=8)


def q_mossy_clue():
    # a scrap of paper with a pressed pink flower and a tuft of green fur
    M = M_((-9, -1, -9), (9, 12, 9), res=2)
    paper = box(M, (-6.0, 0, -5.0), (6.0, 0.8, 5.0)) & ~(box(M, (4.5, 0, 3.0), (7, 1, 6)))
    put(M, paper, '#FBF5E8')
    put(M, paper & ((M.X + M.Z) % 4.0 < 0.5) & (M.X > -5.0), '#E9DCC0')
    flower(M, (-1.8, 1.4, 0.4), n=(0, 1, 0.05), size=1.9, petal=PINK, centre=GOLD)
    for (fx, fz, h) in ((3.0, -2.2, 2.0), (3.8, -1.4, 2.6), (2.4, -1.0, 1.7), (3.4, -0.2, 2.2)):
        put(M, ycyl(M, (fx, fz), 0.35, 0.8, 0.8 + h), SOFT_GREEN if h > 2.1 else LEAF)
    put(M, ell(M, (3.2, 1.3, -1.3), (1.4, 0.6, 1.3)), SOFT_GREEN_HI)
    return M, Camera(yaw=-20, pitch=38)


def q_lumen_trace():
    # a corked jar of glowing dust
    M = M_((-8, -1, -8), (8, 16, 8), res=2)
    jar = ycyl(M, (0, 0), 4.2, 0.5, 9.5)
    put(M, jar, GLASS)
    dust = jar & (M.Y < 6.5)
    put(M, dust, MINT, glow=0.45)
    put(M, dust & ((M.X * 1.7 + M.Y * 2.3 + M.Z * 1.1) % 3.0 < 0.6), MINT_HI, glow=0.9)
    put(M, dust & (M.Y > 5.6), MINT_HI, glow=0.6)
    put(M, ycyl(M, (0, 0), 4.6, 0.0, 0.6), STONE_B_LO)
    put(M, ycyl(M, (0, 0), 3.0, 9.5, 10.5), GLASS)
    put(M, ycyl(M, (0, 0), 3.4, 10.5, 12.5), '#C69469')
    put(M, ycyl(M, (0, 0), 3.4, 12.0, 12.5), '#A97C4B')
    return M, Camera(yaw=-15, pitch=14)


def q_old_trail_map():
    # a rolled map, half open, with a red route and the gate marked
    M = M_((-10, -1, -8), (10, 10, 8), res=2)
    sheet = box(M, (-7.0, 0, -4.5), (5.0, 0.6, 4.5))
    put(M, sheet, '#EAD9B6')
    put(M, sheet & ((M.X + 7.0) % 3.0 < 0.4), '#DCC9A4')
    # a winding route and a bridge mark
    for t in np.linspace(0, 1, 30):
        x = -6.0 + t * 10.0
        z = 2.0 * math.sin(t * 5.0) + (t - 0.5) * 3.0
        put(M, box(M, (x - 0.35, 0.6, z - 0.35), (x + 0.35, 1.0, z + 0.35)), '#D85F51')
    put(M, box(M, (-1.0, 0.6, -0.6), (1.0, 1.1, 0.6)), '#8D5D3B')
    put(M, ell(M, (3.8, 1.1, 2.2), (0.9, 0.5, 0.9)), MINT, glow=0.6)
    for (sx, sz) in ((-5.0, -3.2), (2.0, -3.4), (-3.0, 3.2)):
        put(M, ell(M, (sx, 0.9, sz), (1.0, 0.35, 0.8)), MOSS_B)
    # the rolled end
    put(M, cyl(M, (6.2, 1.6, 0), 1.6, 9.5, axis=2), '#EAD9B6')
    put(M, cyl(M, (6.2, 1.6, 0), 0.7, 9.6, axis=2), '#C9B48A')
    return M, Camera(yaw=-20, pitch=34)


ITEMS = {'ancient_relic': ancient_relic, 'lumen_shard': lumen_shard, 'lantern_tonic': lantern_tonic, 'trail_badge': trail_badge,
         'q_mossy_clue': q_mossy_clue, 'q_lumen_trace': q_lumen_trace, 'q_old_trail_map': q_old_trail_map}


# ------------------------------------------------------------------ UI icons
def ic_discover():
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    # a footprint with a sparkle
    put(M, ell(M, (-1.5, -2.0, 0), (3.0, 4.2, 1.2)), '#7A5A44')
    for i, (dx, dy) in enumerate(((-4.4, 2.6), (-2.2, 3.6), (0.2, 3.8), (2.2, 2.6))):
        put(M, ell(M, (dx, dy, 0), (1.1, 1.3, 1.2)), '#7A5A44')
    a = np.arctan2(M.X - 4.5, M.Y - 4.5)
    r = np.sqrt((M.X - 4.5) ** 2 + (M.Y - 4.5) ** 2)
    put(M, (r <= 0.8 + 3.0 * np.clip(np.cos(2 * a), 0, 1) ** 1.5) & (np.abs(M.Z) <= 1.5), AMBER_HI, glow=0.6)
    return M, Camera(yaw=-10, pitch=8)


def ic_encounter():
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    # two creatures meeting: a cream dot and a green dot joined by a heart
    put(M, ell(M, (-4.6, -1.5, 0), (3.2, 3.4, 1.4)), CREAM_BODY)
    put(M, ell(M, (4.6, -1.5, 0), (3.2, 3.4, 1.4)), SOFT_GREEN)
    for (x, c) in ((-4.6, INK), (4.6, INK)):
        put(M, ell(M, (x - 0.9, -0.8, 1.2), (0.5, 0.8, 0.6)), c)
        put(M, ell(M, (x + 0.9, -0.8, 1.2), (0.5, 0.8, 0.6)), c)
    x, y = M.X / 3.2, (M.Y - 4.0) / 3.2 + 0.1
    h = ((x ** 2 + y ** 2 - 1) ** 3 - x ** 2 * y ** 3 <= 0) & (np.abs(M.Z) <= 1.4)
    put(M, h, '#E0524A')
    put(M, h & (M.X < -0.6) & (M.Y > 4.5) & (M.Z > 0.3), '#F58C82')
    return M, Camera(yaw=-8, pitch=6)


def ic_affinity(kind):
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    r = np.sqrt(M.X ** 2 + M.Y ** 2)
    disc = (r <= 7.8) & (np.abs(M.Z) <= 1.2)
    bg = {'nature': '#E5F2CF', 'ember': '#FFE3CF', 'water': '#D6EDFB', 'stone': '#EEE7DA', 'celestial': '#EBDFFB'}[kind]
    edge = {'nature': '#82B75E', 'ember': '#EC7A4A', 'water': '#4C9BCC', 'stone': '#9C968C', 'celestial': '#AA8BCF'}[kind]
    put(M, disc, bg)
    put(M, disc & (r > 6.8), edge)
    if kind == 'nature':
        d = np.array([0.7, 0.7, 0]) / math.sqrt(0.98)
        t = M.X * d[0] + M.Y * d[1]
        perp = np.abs(M.X * -d[1] + M.Y * d[0])
        leaf = (perp <= 2.6 * np.sqrt(np.clip(1 - (t / 5.0) ** 2, 0, 1))) & (M.Z > 1.0) & (M.Z <= 2.6)
        put(M, leaf, '#5DAA45')
        put(M, leaf & (perp < 0.4), '#3F7D35')
    elif kind == 'ember':
        yy = M.Y + 0.5
        w = np.where(yy < 0, 3.4 * np.sqrt(np.clip(1 - (yy / 4.2) ** 2, 0, 1)), 3.4 * np.clip(1 - yy / 6.0, 0, 1) ** 1.4)
        fl = (np.abs(M.X - np.clip(yy, 0, None) * 0.18) <= w) & (yy > -4.2) & (yy < 6.0) & (M.Z > 1.0) & (M.Z <= 2.6)
        put(M, fl, '#F08A3A', glow=0.4)
        w2 = np.where(yy < -0.5, 1.7 * np.sqrt(np.clip(1 - ((yy + 0.5) / 2.6) ** 2, 0, 1)), 1.7 * np.clip(1 - (yy + 0.5) / 3.6, 0, 1) ** 1.4)
        put(M, fl & (np.abs(M.X - 0.1) <= w2) & (yy > -3.1) & (yy < 3.1), '#FFD46A', glow=0.7)
    elif kind == 'water':
        dr = (np.abs(M.X) <= 3.2 * np.sqrt(np.clip(1 - ((M.Y + 1.5) / 3.6) ** 2, 0, 1)) + 0.0) & (M.Y > -5.0) & (M.Y < 1.5)
        tip = (np.abs(M.X) <= (5.5 - M.Y) * 0.6) & (M.Y >= 1.5) & (M.Y < 5.5)
        put(M, (dr | tip) & (M.Z > 1.0) & (M.Z <= 2.6), '#5BAFE0')
        put(M, (dr) & (M.X < -1.2) & (M.Y < -1.0) & (M.Z > 1.6), '#E4F4FF')
    elif kind == 'stone':
        st = (np.abs(M.X) + np.abs(M.Y) * 0.8 <= 5.0) & (M.Z > 1.0) & (M.Z <= 2.6)
        put(M, st, '#9C968C')
        put(M, st & (M.X < -0.5) & (M.Y > 0.5), '#C9C2AE')
        put(M, st & (np.abs(M.X - M.Y * 0.4 - 1.0) < 0.4) & (M.Y > -3), '#837D74')
    else:
        a = np.arctan2(M.X, M.Y)
        put(M, (r <= 2.2 + 3.2 * np.clip(np.cos(5 * a), 0, 1) ** 1.5) & (M.Z > 1.0) & (M.Z <= 2.6), '#F7C33F', glow=0.5)
        put(M, (np.sqrt((M.X - 4.6) ** 2 + (M.Y - 4.4) ** 2) <= 1.0) & (M.Z > 1.0) & (M.Z <= 2.6), '#FFE590', glow=0.6)
    return M, Camera(yaw=-8, pitch=6)


def ic_hollow():
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    for (cx, h, r0, lean) in ((0.0, 15.0, 3.0, 0.0), (4.2, 8.0, 1.6, 0.2), (-4.0, 6.5, 1.4, -0.2)):
        for t in np.linspace(0, 1, 16):
            r = r0 * (1 - t * 0.85) + 0.2
            put(M, ell(M, (cx + lean * t * h, -8.0 + t * h, 0), (r, r * 0.9, 1.6)), VIOLET if t < 0.6 else VIOLET_HI, glow=0.5 + 0.5 * t)
    return M, Camera(yaw=-10, pitch=8)


def ic_calm():
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    x, y = M.X / 6.8, M.Y / 6.8 + 0.1
    h = ((x ** 2 + y ** 2 - 1) ** 3 - x ** 2 * y ** 3 <= 0) & (np.abs(M.Z) <= 1.5)
    put(M, h, '#7FD9B8')
    put(M, h & (M.X < -1.0) & (M.Y > 0.5) & (M.Z > 0.4), '#C9F5E4')
    a = np.arctan2(M.X - 0.5, M.Y - 0.5)
    r = np.sqrt((M.X - 0.5) ** 2 + (M.Y - 0.5) ** 2)
    put(M, (r <= 0.6 + 2.6 * np.clip(np.cos(2 * a), 0, 1) ** 1.5) & (M.Z > 1.2) & (M.Z <= 2.4), WHITE, glow=0.5)
    return M, Camera(yaw=-10, pitch=8)


def ic_energy():
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    # upper half leans left of the kink, lower half leans right; both taper to a point
    top = (M.Y >= 0) & (M.Y < 8) & (M.X > -4.0 + M.Y * 0.55) & (M.X < 2.2 + M.Y * 0.15)
    bot = (M.Y < 0) & (M.Y > -8) & (M.X > -2.2 + M.Y * 0.15) & (M.X < 4.0 + M.Y * 0.55)
    bolt = (top | bot) & (np.abs(M.Z) <= 1.4)
    put(M, bolt, '#F7C33F', glow=0.5)
    put(M, bolt & (M.X < -0.5 + M.Y * 0.3) & (M.Z > 0.4), '#FFE590', glow=0.6)
    return M, Camera(yaw=-10, pitch=8)


def ic_trail():
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    r = np.sqrt(M.X ** 2 + M.Y ** 2)
    disc = (r <= 7.8) & (np.abs(M.Z) <= 1.2)
    put(M, disc, '#FBF5E8')
    put(M, disc & (r > 6.6), COPPER)
    a = np.arctan2(M.X, M.Y)
    star = (r <= 1.0 + 5.4 * np.clip(np.cos(2 * a), 0, 1) ** 2.4) & (M.Z > 1.0) & (M.Z <= 2.6)
    put(M, star, '#203B50')
    put(M, star & (M.Y > 0) & (np.abs(M.X) < 1.2), '#D85F51')
    put(M, (r <= 1.0 + 3.6 * np.clip(np.cos(2 * a + math.pi / 2), 0, 1) ** 2.4) & (M.Z > 1.0) & (M.Z <= 2.2), '#8E7462')
    put(M, (r <= 1.0) & (M.Z > 1.0) & (M.Z <= 2.8), MINT, glow=0.5)
    return M, Camera(yaw=-10, pitch=8)


def ic_sun():
    """Lumen Glow: a warm sun with chunky rays."""
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    r = np.sqrt(M.X ** 2 + M.Y ** 2)
    a = np.arctan2(M.X, M.Y)
    rays = (r > 5.0) & (r <= 8.4) & (np.cos(8 * a) > 0.55) & (np.abs(M.Z) <= 1.0)
    put(M, rays, '#F2A93B', glow=0.3)
    disc = (r <= 4.6) & (np.abs(M.Z) <= 1.6)
    put(M, disc, '#F7C33F', glow=0.4)
    put(M, disc & (M.X < -0.8) & (M.Y > 0.8) & (M.Z > 0.6), '#FFE590', glow=0.6)
    put(M, (r > 3.6) & disc & (M.Z > 0.6) & (M.X > 0.5) & (M.Y < -0.5), '#E89A30', glow=0.3)
    return M, Camera(yaw=-8, pitch=6)


def ic_purify():
    """The Hollow-side light: a four-point sparkle in a lilac disc."""
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    r = np.sqrt(M.X ** 2 + M.Y ** 2)
    disc = (r <= 7.8) & (np.abs(M.Z) <= 1.2)
    put(M, disc, '#E6D9FA')
    put(M, disc & (r > 6.6), '#9975C9')
    a = np.arctan2(M.X, M.Y)
    star = (r <= 1.3 + 4.6 * np.abs(np.cos(2 * a)) ** 3) & (M.Z > 1.0) & (M.Z <= 2.8)
    put(M, star, '#7B48C4', glow=0.4)
    put(M, star & (M.X < 0) & (M.Y > 0), '#B48CF0', glow=0.6)
    for (x, y) in ((4.2, 4.0), (-4.4, -4.0)):
        put(M, (np.abs(M.X - x) + np.abs(M.Y - y) <= 1.0) & (M.Z > 1.0) & (M.Z <= 2.4), '#FFFFFF', glow=0.8)
    return M, Camera(yaw=-8, pitch=6)


def ic_nudge():
    """Gentle Nudge: a round red berry with a leaf (an offered treat and a playful bump)."""
    M = M_((-9, -9, -3), (9, 9, 4), res=2)
    b = ell(M, (0, -1.2, 0), (6.0, 5.8, 3.0))
    put(M, b, '#D9473F')
    put(M, b & (M.X < -1.5) & (M.Y > 0.5) & (M.Z > 1.0), '#F0706A')
    put(M, b & (M.X > 2.5) & (M.Y < -3.0), '#B73A34')
    for (x, y) in ((-2.4, 0.4), (1.6, -2.2), (2.8, 1.4), (-1.0, -3.6)):
        put(M, ell(M, (x, y, 2.6), (0.5, 0.6, 0.6)), '#FFE3A8')
    put(M, ell(M, (-2.6, 1.8, 2.4), (1.1, 0.8, 0.6)), '#FFFFFF')
    lf = ell(M, (2.6, 6.0, 0), (3.2, 1.5, 1.0)) & (M.Y > 4.2)
    put(M, lf, '#5DAA45')
    put(M, ell(M, (-1.8, 5.8, 0), (2.4, 1.2, 1.0)) & (M.Y > 4.4), '#7FC25C')
    put(M, box(M, (-0.5, 3.8, -0.6), (0.5, 7.2, 0.6)), '#6B4A2E')
    return M, Camera(yaw=-8, pitch=6)


def ic_moon():
    """The Hollow badge: a crescent moon in a deep violet disc."""
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    r = np.sqrt(M.X ** 2 + M.Y ** 2)
    disc = (r <= 7.8) & (np.abs(M.Z) <= 1.2)
    put(M, disc, '#3F2E62')
    put(M, disc & (r > 6.6), '#7B48C4')
    moon = (r <= 4.6) & (np.sqrt((M.X - 2.2) ** 2 + (M.Y - 1.6) ** 2) > 3.8) & (M.Z > 1.0) & (M.Z <= 2.6)
    put(M, moon, '#D9C2FF', glow=0.7)
    return M, Camera(yaw=-8, pitch=6)


def ic_swirl():
    """Your Evochi's badge on the encounter card: a warm swirl in a peach disc."""
    M = M_((-9, -9, -3), (9, 9, 3), res=2)
    r = np.sqrt(M.X ** 2 + M.Y ** 2)
    disc = (r <= 7.8) & (np.abs(M.Z) <= 1.2)
    put(M, disc, '#FBE0CC')
    put(M, disc & (r > 6.6), '#E7744E')
    a = np.arctan2(M.Y, M.X)
    # an Archimedean spiral: r = k * (a + 2 pi n)
    sp = np.zeros(M.m.shape, bool)
    for n in range(3):
        rr = 0.62 * (np.mod(a, 2 * math.pi) + 2 * math.pi * n)
        sp |= np.abs(r - rr) < 0.75
    put(M, sp & (r <= 5.6) & (M.Z > 1.0) & (M.Z <= 2.6), '#E7744E')
    return M, Camera(yaw=-8, pitch=6)


ICONS = {
    'sun': ic_sun, 'purify': ic_purify, 'nudge': ic_nudge, 'moon': ic_moon, 'swirl': ic_swirl,
    'discover': ic_discover, 'encounter': ic_encounter, 'hollow': ic_hollow, 'calm': ic_calm, 'energy': ic_energy,
    'trail': ic_trail,
    'aff_nature': lambda: ic_affinity('nature'), 'aff_ember': lambda: ic_affinity('ember'),
    'aff_water': lambda: ic_affinity('water'), 'aff_stone': lambda: ic_affinity('stone'),
    'aff_celestial': lambda: ic_affinity('celestial'),
}


def items(out):
    os.makedirs(os.path.join(out, 'items'), exist_ok=True)
    for k, b in ITEMS.items():
        M, cam = b()
        save_rgba(render_model(M, cam, 256), os.path.join(out, 'items', f'item_{k}_icon.png'))
        print('item', k, flush=True)


def icons(out, only=None):
    os.makedirs(os.path.join(out, 'ui_icons'), exist_ok=True)
    for k, b in ICONS.items():
        if only and k not in only:
            continue
        M, cam = b()
        save_rgba(render_model(M, cam, 192, outline=2.6), os.path.join(out, 'ui_icons', f'icon_{k}.png'))
        print('icon', k, flush=True)


if __name__ == '__main__':
    out = sys.argv[1]
    parts = sys.argv[2:] or ['creatures', 'items', 'icons']
    if 'creatures' in parts:
        creatures(out, only=[p for p in parts if p in CREATURES] or None)
    if 'items' in parts:
        items(out)
    if 'icons' in parts:
        icons(out, only=[p for p in parts if p in ICONS] or None)
    if 'battle' in parts:
        creatures_battle(out, only=[p for p in parts if p in CREATURES] or None)

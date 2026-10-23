"""Flint, the old Obsidian Elder who keeps the mines: an Obsidian Elder built on the Evochi Elder,
bigger (FLINT_SCALE), in a miner's hard hat with a glowing headlamp, round brass spectacles, bushy grey
brows, a red bandana, a tool belt with pouches and a pickaxe strapped across his back, and dust on his feet.

    python3 flint.py OUT_DIR          (concept sheet: Flint beside an ordinary Obsidian Elder, a few faces)
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from voxel import Camera, save_rgba
from characters import build, shell_region, tube, spike, local_frame
from charrender import render_char
from palettes import palette, ACCESSORY
from accessories import HEAD, core_mask, ACC_MATS_PREFIX as A

FLINT_SCALE = 1.4
GEAR = {
    'hat': '#F2B33D', 'hat_hi': '#FFD27A', 'hat_lo': '#C9852A', 'hat_band': '#3B3A40',
    'lamp': '#B98A3E', 'lamp_lens': '#FFF2B8', 'brass': '#D9A84E',
    'bandana': '#C8443C', 'bandana_hi': '#E2645A', 'bandana_dot': '#F7F3EA',
    'belt': '#6E4529', 'belt_hi': '#8A5634', 'pouch': '#9A6538', 'pouch_hi': '#B98955',
    'haft': '#A8703F', 'haft_lo': '#7A4E2E', 'pick': '#8E959E', 'pick_hi': '#C4CAD2',
    'brow': '#C9C4BC', 'brow_hi': '#E6E2DA', 'dust': '#8D8579',
}


def _s(M, mask, name, empty=True, glow=None):
    if empty:
        mask = mask & (M.m == 0)
    M.set(mask, A + name, glow=glow)


def gear_up(ch):
    M = ch.model
    p = HEAD[3]
    c = np.array(p['c'], float)                  # the crest's base, on top of the head
    # the crest goes (the hat sits there)
    crest = np.isin(M.m, [i for i, n in enumerate(M.mats) if n.startswith('crest')])
    M.m[crest & (M.Y >= c[1] - 3.0) & ((M.X - c[0]) ** 2 + (M.Z - c[2]) ** 2 <= 11.0 ** 2)] = 0
    # hard hat: a helmet over the top of the head, a short brim all round, a peak at the front
    hc = np.array([0.0, 21.4, 16.6])
    dome = ((M.X - hc[0]) ** 2 / 9.4 ** 2 + (M.Z - hc[2]) ** 2 / 9.6 ** 2 + (M.Y - hc[1]) ** 2 / 6.4 ** 2 <= 1) & (M.Y >= hc[1])
    brim = ((M.X - hc[0]) ** 2 / 10.6 ** 2 + (M.Z - hc[2]) ** 2 / 10.6 ** 2 <= 1) & (M.Y >= hc[1] - 0.3) & (M.Y < hc[1] + 0.8)
    peak = ((M.X - hc[0]) ** 2 / 8.4 ** 2 + (M.Z - hc[2] - 3.6) ** 2 / 10.4 ** 2 <= 1) & (M.Z > hc[2]) & (M.Y >= hc[1] - 0.3) & (M.Y < hc[1] + 0.8)
    ridge = dome & (np.abs(M.X - hc[0]) < 1.0) & (M.Y > hc[1] + 3.2)
    M.m[(dome | brim | peak) & (M.m > 0)] = 0
    _s(M, dome, 'hat', empty=False)
    _s(M, dome & (M.Y > hc[1] + 4.4), 'hat_hi', empty=False)
    _s(M, ridge, 'hat_hi', empty=False)
    _s(M, brim | peak, 'hat_lo', empty=False)
    _s(M, dome & (M.Y >= hc[1] + 0.8) & (M.Y < hc[1] + 2.0), 'hat_band', empty=False)
    # the headlamp on the front: a brass cup with a big bright lens
    lc = np.array([hc[0], hc[1] + 3.0, hc[2] + 8.4])
    cup = ((M.X - lc[0]) ** 2 + (M.Y - lc[1]) ** 2 <= 2.6 ** 2) & (M.Z >= lc[2] - 1.2) & (M.Z < lc[2] + 1.6)
    _s(M, cup, 'lamp', empty=False)
    lens = ((M.X - lc[0]) ** 2 + (M.Y - lc[1]) ** 2 <= 1.9 ** 2) & (M.Z >= lc[2] + 1.0) & (M.Z < lc[2] + 1.9)
    _s(M, lens, 'lamp_lens', empty=False, glow=1.0)
    # bushy grey brows over the eyes (on the head, just above where the face paints the eyes)
    f = ch.face
    for sx in (-1, 1):
        b0 = np.array([sx * (ch.eye_u + 0.6), 20.2, 24.6])
        brow = ((M.X - b0[0]) ** 2 / 3.4 ** 2 + (M.Y - b0[1]) ** 2 / 1.3 ** 2 + (M.Z - b0[2]) ** 2 / 2.2 ** 2 <= 1)
        _s(M, brow, 'brow')
        _s(M, brow & (M.Y > b0[1] + 0.3), 'brow_hi', empty=False)
    # a grey chin tuft under the snout
    tuft = ((M.X) ** 2 / 2.6 ** 2 + (M.Y - 9.6) ** 2 / 2.0 ** 2 + (M.Z - 24.6) ** 2 / 2.2 ** 2 <= 1)
    _s(M, tuft, 'brow')
    # a red bandana round the neck, knotted at the side
    core = core_mask(M)
    shell = shell_region(M, core, 3)
    band = shell & (M.Y >= 7.6) & (M.Y < 12.8) & (M.Z >= 5.0) & (M.Z < 12.0)
    _s(M, band, 'bandana')
    _s(M, band & ((np.floor(M.X * 0.9) + np.floor(M.Y * 0.9)) % 3 == 0), 'bandana_dot', empty=False)
    knot = ((M.X - 9.4) ** 2 + (M.Y - 11.4) ** 2 + (M.Z - 8.6) ** 2 <= 1.6 ** 2)
    _s(M, knot, 'bandana_hi')
    for k in range(2):
        tail_ = spike(M, (9.8, 11.0, 8.4), (0.5, -1.0, -0.4 + 0.8 * k), 3.6, 0.9, 0.5, square=False)
        _s(M, tail_, 'bandana')
    # a tool belt round the middle with two pouches
    belt = shell_region(M, core, 2) & (np.abs(M.Z + 4.5) < 1.6) & (M.Y < 19)
    _s(M, belt, 'belt')
    _s(M, belt & (np.abs(M.Z + 4.5) < 0.5), 'belt_hi', empty=False)
    for sx in (-1, 1):
        pc = np.array([sx * 10.6, 8.6, -4.5])
        pouch = (np.abs(M.X - pc[0]) <= 1.4) & (np.abs(M.Y - pc[1]) <= 2.0) & (np.abs(M.Z - pc[2]) <= 2.0)
        _s(M, pouch, 'pouch')
        _s(M, pouch & (M.Y > pc[1] + 1.0), 'pouch_hi', empty=False)
    # a pickaxe slung over the right shoulder: the haft rises behind, the iron head above the back
    a, b = np.array([8.0, 14.0, 2.0]), np.array([10.5, 31.0, -11.0])
    haft = tube(M, [tuple(a), tuple(b)], [0.85, 0.85], p=2.0)
    _s(M, haft, 'haft', empty=False)
    head_ = tube(M, [(b[0], b[1] - 1.2, b[2] - 6.0), (b[0], b[1] + 0.8, b[2]), (b[0], b[1] - 1.6, b[2] + 5.6)],
                 [0.7, 1.5, 0.6], p=2.2)
    _s(M, head_, 'pick', empty=False)
    _s(M, head_ & (M.Y > b[1] + 0.6), 'pick_hi', empty=False)
    for z in (-10.0, -2.0):
        strap = shell_region(M, core, 1) & (np.abs(M.Z - z) < 0.6) & (M.Y > 14)
        _s(M, strap, 'belt')
    # dust on the feet
    feet_ids = [M.ids[n] for n in M.mats if n.startswith('feet')]
    dusty = np.isin(M.m, feet_ids) & (M.Y < 2.2) & (np.random.default_rng(5).random(M.m.shape) < 0.45)
    M.set(dusty, A + 'dust')

    # older eyes: heavy upper lids that droop a little at the outer corners, soft bags under them and
    # crow's feet, in a grey that reads on his dark face (no spectacles)
    eu, ev, ew, eh = ch.eye_u, ch.eye_v, ch.eye_w, ch.eye_h
    line = '#8D8696'

    def extras(cv, pal, expr):
        import numpy as np
        open_eyes = expr in ('default', 'neutral', 'thinking', 'curious', 'surprised', 'worried', 'determined', 'sad')
        lw = max(0.42, ew * 0.24)
        for s_ in (-1, 1):
            cu = s_ * eu
            t = (cv.U - cu) * s_                       # toward the outer corner
            if open_eyes:
                drop = 0.0 if expr == 'surprised' else (0.32 if expr == 'thinking' else 0.18)
                lid = ev + eh * (0.5 - 0.5 - drop) + eh * 0.5 * (1 - drop) - 0.22 * np.clip(t, 0, None) - eh * 0.25
                eye = cv.m_rect(cu, ev, ew * 1.25, eh * 1.15, ew * 0.3)
                cv.a[eye & (cv.V > lid)] = 0.0
                pts = [(cu - s_ * ew * 0.75, ev + eh * 0.25 - eh * drop), (cu + s_ * ew * 0.85, ev + eh * 0.25 - eh * drop - 0.22 * ew * 0.85)]
                cv.paint(cv.m_stroke(pts, lw * 1.15), pal['eye'], lit=0.0)
            # no blush: he is old
            cv.a[cv.m_rect(s_ * ch.cheek_u, ch.cheek_v, ch.cheek_w * 1.35, ch.cheek_h * 1.5, 0.25)] = 0.0
            # bags and crow's feet
            cv.paint(cv.m_arc(cu, ev - eh * 0.62, ew * 0.75, eh * 0.16, 200, 340, lw * 0.7), line, lit=0.2)
            ox = cu + s_ * (ew * 1.25)
            for k, dv in enumerate((0.35, -0.05, -0.45)):
                cv.paint(cv.m_stroke([(ox, ev + dv), (ox + s_ * 0.9, ev + dv * 1.6 + 0.1 * k - 0.1)], lw * 0.6), line, lit=0.2)
    ch.face_extra = extras
    return ch


def flint():
    return gear_up(build(3))


def flint_palette():
    pal = dict(palette('obsidian'))
    for k, v in GEAR.items():
        pal[A + k] = v
    pal['crest_hi'] = '#EADBD2'          # frosted spike tips: he is old
    pal['crest_mid'] = '#D9A49A'
    return pal


if __name__ == '__main__':
    from build_characters import HERO_CAM, fit_for, SCALE_HERO
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    cam = HERO_CAM[3]
    plain = build(3)
    fl = flint()
    pal = flint_palette()
    scale = SCALE_HERO * 1.0
    fit_p = fit_for([plain.model], cam, scale)
    fit_f = fit_for([fl.model], cam, scale * FLINT_SCALE)
    shots = {}
    for e in ('default', 'happy', 'thinking', 'surprised'):
        o = render_char(fl, 'obsidian', e, cam, fit_f.w, fit_f.h, fit=fit_f, pal=pal, pal_key='flint')
        shots[e] = Image.fromarray(o.rgba, 'RGBA')
        shots[e].save(os.path.join(out, f'flint_{e}.png'))
    op = render_char(plain, 'obsidian', 'default', cam, fit_p.w, fit_p.h, fit=fit_p)
    pimg = Image.fromarray(op.rgba, 'RGBA')
    pimg.save(os.path.join(out, 'elder_obsidian.png'))
    print('flint', shots['default'].size, 'elder', pimg.size)

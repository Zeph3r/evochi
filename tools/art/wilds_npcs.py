"""The Lumen Wilds' people. Sher: an orange-and-white cat standing on two legs, from the original
drawing. Built like the villagers (village_npcs.py): voxels, the shared ink line and face rig, parts
tagged for the villagers' idle/talk animation (body, head, his right arm), five expressions. No brows.
Three whiskers each side of his muzzle are real 3D strands that reach past his head (whiskers.py).

His markings follow the drawing: an orange head with a white blaze from the crown down between the
eyes, the eyes in orange, outer cheeks orange, the lower face and chin white with a little orange patch
at the mouth under a pink nose; white fluff and a pink rim in orange ears; a white chest and inner
legs, orange flanks and outer legs; orange arms ending in big white mitts; cuffed maroon boots.

His gear is modelled on top of him (its own `acc_` materials, like the Evochi wearables): the maroon
neckerchief (a thick collar with folds, a triangle draping off the chest, the knot and its two ends on
his right), a canvas backpack with a leather flap, buckles, a pocket and a bedroll, its straps over his
shoulders, and a utility belt with a buckle, two pouches and a vial.

`legs` / `arms` move a boot or a paw relative to the body: the walk (walk.py).
"""
from __future__ import annotations

import math

import numpy as np

from voxel import Model
from decals import Frame
from characters import Character, egg_mask, shell_region, tube
from village_npcs import face_palette, box, ball, put, recolor, tag, slab, unit, BODY, HEAD, ARM
from whiskers import Whisker

ORANGE, ORANGE_LO = '#EE9C47', '#DB863C'
WHITE, WHITE_LO = '#FBF4E6', '#EADCC6'
PINK = '#EFA3B4'
MAROON, MAROON_LO, MAROON_HI = '#7A2B36', '#5C1F29', '#94404A'
SOLE = '#3E1A1E'

GEAR = {
    'acc_scarf': MAROON, 'acc_scarf_lo': MAROON_LO, 'acc_scarf_hi': MAROON_HI,
    'acc_pack': '#B08F5E', 'acc_pack_lo': '#977747', 'acc_leather': '#6E4529', 'acc_leather_lo': '#57351F',
    'acc_buckle': '#E8B956', 'acc_roll': '#EFE3C8', 'acc_roll_lo': '#D8C8A6',
    'acc_belt': '#5E3B24', 'acc_pouch': '#8D5D3B', 'acc_pouch_lo': '#734A2E',
    'acc_vial': '#86D3C9', 'acc_vial_hi': '#C4F0EA', 'acc_cork': '#B98A5A',
}

U = 2.2     # everything above the legs sits this much higher: orange legs show above the boots


def gear(M, mask, name, empty=True):
    if empty:
        mask = mask & (M.m == 0)
    M.set(mask, name)
    return mask


def build_sher(res=2, legs=None, arms=None, lo_y=-1, lean=0.0) -> Character:
    """legs: {side: (dy, dz)} lifts/moves a boot and its leg; arms: {side: dz} swings a paw forward/back.
    Sides are x signs: +1 is the viewer's right (his left). lean: how far (units) his head leans forward
    over his hips, a shear of everything above them (running)."""
    legs = legs or {}
    arms = arms or {}
    M = Model((-17, lo_y, -18), (17, 40, 15), [], res=res)
    HY = 22.0 + U          # head centre

    # ---- head: wide and round, the biggest part of him
    head = egg_mask(M, (0, HY, 0.4), 8.9, 7.0, 6.4, 7.3, p=2.45)
    put(M, head, ORANGE, empty=False)
    ax = np.abs(M.X)
    eye_bottom = HY - 1.85
    # the white blaze: narrow at the crown, widening down between the eyes
    blaze = head & (M.Y >= eye_bottom) & (ax < 0.75 + np.maximum(0, HY + 7.0 - M.Y) * 0.2) & (M.Z > -2.5)
    # the lower face: white below the eyes, widening fast, the outer cheeks staying orange to the mouth
    lower = head & (M.Y < eye_bottom) & (ax < 2.2 + (eye_bottom - M.Y) * 2.6) & (M.Z > 1.0)
    chin = head & (M.Y < HY - 4.6) & (M.Z > -2.5)
    recolor(M, blaze | lower | chin, WHITE)
    # the orange patch at the mouth, under the nose (two little lobes, like the drawing's)
    mouth = head & (M.Z > 4.0) & (M.Y > HY - 3.9) & (M.Y < HY - 2.5) & (ax < 1.9 - 0.25 * (np.abs(M.Y - (HY - 3.2)) > 0.5))
    recolor(M, mouth, ORANGE)
    nose = ball(M, (0, HY - 2.25, 7.35), (1.0, 0.7, 0.6)) & ~head
    put(M, nose, PINK)
    # ears: tall triangles tipped outward; inside a pink rim round white fluff
    for s in (-1, 1):
        base = np.array([s * 5.4, HY + 4.6, 0.2])
        up = unit([s * 0.42, 0.91, 0.0])
        P = np.stack([M.X - base[0], M.Y - base[1], M.Z - base[2]], -1)
        v = P @ up
        u = P @ np.array([up[1], -up[0], 0.0])      # across the ear, + toward its outer edge on both sides
        u = u * s
        H, W = 7.6, 6.6
        half = (W / 2) * (1 - np.clip(v, 0, H) / H)
        tri = (v >= -1.5) & (v <= H) & (np.abs(u) <= half + 0.35)
        put(M, tri & (np.abs(M.Z - 0.2) <= 1.4) & ~head, ORANGE)
        face = (np.abs(M.Z - 1.4) < 0.3) & ~head
        inner = tri & (v >= -0.3) & (v <= H - 0.9) & (np.abs(u) <= half - 0.5)
        recolor(M, inner & face, PINK)
        # the fluff sits toward the head (the inner edge) and the base, ragged on its outer side
        rag = 0.35 * np.sin(v * 4.1) + 0.25 * np.sin(v * 7.3 + 1.0)
        fluff = inner & (u < (half - 0.5) * 0.05 + rag) & (v < H - 2.2)
        recolor(M, fluff & face, WHITE)
        # a few tufts poking out over the rim near the base
        tuft = (v > 0.4) & (v < 2.6) & (np.abs(u + 0.6) < 0.5) & (np.abs(M.Z - 1.9) < 0.25) & ~head
        put(M, tuft & tri, WHITE)
    head_all = (M.m > 0) & (M.Y > 15.4 + U)

    # ---- body: a white chest and belly, orange flanks and back
    BY = 10.6 + U
    body = egg_mask(M, (0, BY, 0), 6.4, 5.6, 4.6, 5.4, p=2.3)
    put(M, body, ORANGE)
    chest = body & (M.Z > 0.6) & (((M.X / 4.9) ** 2 + ((M.Y - BY + 0.4) / 6.0) ** 2) < 1.0)
    recolor(M, chest, WHITE)

    # ---- legs (orange outside, white inside) and cuffed boots: the walk moves these
    for s in (-1, 1):
        dy, dz = legs.get(s, (0.0, 0.0))
        x = s * 3.0
        leg = tube(M, [(x, 7.2 + U, 0.0), (x, 3.6 + dy, dz)], [2.0, 1.75])
        put(M, leg, ORANGE)
        recolor(M, leg & (M.X * s < 2.6) & (M.Z > -0.6), WHITE)
        y0 = dy
        bt = box(M, (x - 2.0, y0, dz - 2.0), (x + 2.0, y0 + 3.4, dz + 2.0))
        toe = ball(M, (x, y0 + 1.25, dz + 2.2), (2.0, 1.3, 1.6)) & (M.Y >= y0)
        put(M, bt | toe, MAROON, empty=False)
        put(M, (bt | toe) & (M.Y < y0 + 0.6), SOLE, empty=False)
        cuff = box(M, (x - 2.45, y0 + 3.0, dz - 2.45), (x + 2.45, y0 + 4.5, dz + 2.45))
        cuff &= ((M.X - x) ** 2 / 2.45 ** 2 + (M.Z - dz) ** 2 / 2.45 ** 2) <= 1.15
        put(M, cuff, MAROON_LO, empty=False)
        put(M, cuff & (M.Y > y0 + 4.0), MAROON_HI, empty=False)

    # ---- arms: orange from the shoulder, then big round white mitts
    right_arm = np.zeros(M.m.shape, bool)
    for s in (-1, 1):
        dz = arms.get(s, 0.0)
        sh = np.array([s * 5.6, 13.4 + U, 0.4])
        paw = np.array([s * 7.7, 8.4 + U + abs(dz) * 0.25, 1.0 + dz])
        mid = (sh + paw) / 2 + np.array([s * 0.5, 0, 0])
        a = tube(M, [sh, mid, paw], [1.75, 1.7, 1.8]) & ~body
        am = put(M, a, ORANGE)
        recolor(M, am & (M.Y < mid[1] - 0.4), WHITE)
        p = ball(M, paw + np.array([s * 0.25, -0.7, 0.25]), (2.35, 2.25, 2.3))
        pm = put(M, p, WHITE)
        toes = p & (M.Y < paw[1] - 1.6) & (np.floor((M.X - paw[0]) * 1.5) % 2 == 0) & (M.Z > paw[2] + 0.4)
        recolor(M, toes, WHITE_LO)
        if s > 0:
            right_arm = am | pm      # the viewer's right arm: the villagers' animated arm

    # ---- tail: curls up behind him, white tip
    t = tube(M, [(0.0, 7.4 + U, -4.0), (1.6, 6.4 + U, -7.6), (3.6, 8.4 + U, -10.6), (4.6, 12.6 + U, -11.8),
                 (3.8, 16.6 + U, -11.4)], [1.7, 1.6, 1.5, 1.45, 1.4])
    put(M, t, ORANGE)
    recolor(M, t & (M.Y > 14.6 + U) & (M.Z < -9.0), WHITE)
    core = M.m > 0

    # ================= gear, modelled on top =================
    # ---- the neckerchief: a thick collar round the neck, folded
    NY0, NY1 = 14.3 + U, 16.3 + U
    ring = ((M.X / 6.3) ** 2 + (M.Z / 5.9) ** 2 <= 1.0) & (M.Y >= NY0) & (M.Y < NY1)
    collar = gear(M, ring & ~core, 'acc_scarf')
    ang = np.arctan2(M.X, M.Z)
    folds = collar & (np.floor(ang * 5.0 + (M.Y - NY0) * 0.5) % 3 == 0)
    M.set(folds, 'acc_scarf_lo')
    M.set(collar & (M.Y >= NY1 - 0.5), 'acc_scarf_hi')
    # the triangle drapes off the chest, its point a little to his left and standing away from him
    along = unit([0.14, -0.94, 0.3])
    nrm = unit([0.0, 0.3, 1.0])
    top = np.array([0.4, NY0 + 0.5, 5.3])
    L = 7.0
    tri, a, w = slab(M, top + along * (L / 2) + nrm * 0.6, along, nrm, L, 9.6, 1.2, taper=1.0, round_=False)
    tri &= ~core
    tm = gear(M, tri, 'acc_scarf')
    # its folds: two raised creases running toward the point
    crease = tri & ((np.abs(w - a * 0.18 + 1.2) < 0.45) | (np.abs(w + a * 0.22 - 1.6) < 0.45))
    M.set(crease, 'acc_scarf_lo')
    lip, _, _ = slab(M, top + along * (L / 2) + nrm * 1.3, along, nrm, L, 9.6, 0.5, taper=1.0, round_=False)
    gear(M, lip & crease & ~core, 'acc_scarf_lo')
    # the knot on his right (the viewer's left) and its two loose ends
    kc = np.array([-5.7, NY0 + 1.0, 3.5])
    gear(M, ball(M, kc, (1.8, 1.6, 1.5)), 'acc_scarf_hi', empty=False)
    for d, ln, wd in (((-0.85, -0.45, 0.25), 3.6, 2.2), ((-0.45, -0.88, 0.3), 4.0, 2.0)):
        dv = unit(d)
        e, ea, ew = slab(M, kc + dv * (ln / 2 + 0.8), dv, (0.2, 0.15, 1.0), ln, wd, 0.9, taper=-0.35, round_=False)
        em = gear(M, e & ~core, 'acc_scarf')
        M.set(em & (ea > ln / 2 - 0.7), 'acc_scarf_lo')

    # ---- the utility belt: a leather band round the waist, a gold buckle, pouches and a vial
    WY0, WY1 = 8.0 + U, 9.6 + U
    waist = ((M.X / 6.0) ** 2 + (M.Z / 5.4) ** 2 <= 1.0) & (M.Y >= WY0) & (M.Y < WY1)
    belt = gear(M, waist & ~core, 'acc_belt')
    core = M.m > 0
    buckle = box(M, (-1.3, WY0 - 0.2, 4.6), (1.3, WY1 + 0.2, 5.9)) & ~((np.abs(M.X) < 0.6) & (np.abs(M.Y - (WY0 + WY1) / 2) < 0.45))
    gear(M, buckle, 'acc_buckle', empty=False)
    for s, angd in ((-1, 52), (1, 50)):
        th = math.radians(angd)
        c = np.array([s * 5.2 * math.sin(th), WY0 - 0.6, 4.8 * math.cos(th)])
        n = unit([s * math.sin(th), 0, math.cos(th)])
        P = np.stack([M.X - c[0], M.Y - c[1], M.Z - c[2]], -1)
        across = unit(np.cross([0, 1, 0], n))
        pu, pv, pn = P @ across, P @ np.array([0, 1.0, 0]), P @ n
        pouch = (np.abs(pu) <= 1.5) & (pv >= -1.6) & (pv <= 1.8) & (pn >= -0.6) & (pn <= 1.8)
        pouch &= (np.abs(pu) / 1.5) ** 6 + (np.abs(pv - 0.1) / 1.75) ** 6 <= 1.2
        pm = gear(M, pouch & ~core, 'acc_pouch')
        M.set(pm & (pv > 0.7), 'acc_pouch_lo')
        gear(M, (np.abs(pu) <= 0.35) & (np.abs(pv - 0.6) <= 0.35) & (pn > 1.6) & (pn <= 2.2), 'acc_buckle')
    # a little vial of tonic on his left hip, toward the back
    vc = np.array([5.5, WY0 - 1.0, -2.6])
    vr = np.hypot(M.X - vc[0], M.Z - vc[2])
    vial = (vr <= 1.05) & (M.Y >= vc[1] - 1.6) & (M.Y <= vc[1] + 1.3)
    vm = gear(M, vial & ~core, 'acc_vial')
    M.set(vm & (M.X > vc[0] + 0.3) & (M.Y > vc[1]), 'acc_vial_hi')
    gear(M, (vr <= 0.6) & (M.Y > vc[1] + 1.3) & (M.Y <= vc[1] + 2.1), 'acc_cork')
    core = M.m > 0

    # ---- the backpack: canvas with a leather flap, two buckles, a pocket, a bedroll on top
    pc = np.array([0.0, 13.6 + U, -5.0])
    P = np.stack([M.X - pc[0], M.Y - pc[1], M.Z - pc[2]], -1)
    pu, pv, pn = P[..., 0], P[..., 1], -P[..., 2]     # across, up, outward (behind him)
    w, h, d = 4.4, 4.6, 4.0
    pack = (np.abs(pu) <= w) & (np.abs(pv) <= h) & (pn >= -1.5) & (pn <= d)
    pack &= ((np.abs(pu) / w) ** 6 + (np.abs(pv) / h) ** 6 + (np.abs(pn - d / 2) / (d / 2 + 1.5)) ** 6) <= 1.25
    pk = gear(M, pack & ~core, 'acc_pack')
    M.set(pk & (pn > d - 0.6) & (pv < -h * 0.2) & (np.abs(pu) < w * 0.85), 'acc_pack_lo')
    flap = pk & (pv > h * 0.15) & ((pn > d - 1.0) | (pv > h * 0.55))
    M.set(flap, 'acc_leather')
    M.set(flap & (pv < h * 0.22), 'acc_leather_lo')
    for bu in (-w * 0.45, w * 0.45):
        gear(M, (np.abs(pu - bu) <= 0.6) & (np.abs(pv - h * 0.12) <= 0.55) & (pn > d - 0.5) & (pn <= d + 0.6), 'acc_buckle')
        gear(M, (np.abs(pu - bu) <= 0.45) & (pv > h * 0.18) & (pv < h * 0.45) & (pn > d - 0.6) & (pn <= d + 0.45), 'acc_leather_lo')
    pocket = (np.abs(pu) <= w * 0.55) & (pv > -h * 0.85) & (pv < -h * 0.12) & (pn > d - 0.2) & (pn <= d + 1.0)
    pm = gear(M, pocket, 'acc_pack')
    M.set(pm & (pv > -h * 0.3), 'acc_leather')
    r = 1.8
    roll = ((pv - (h + 1.2)) ** 2 + (pn - d * 0.45) ** 2 <= r * r) & (np.abs(pu) <= w + 0.9)
    rm = gear(M, roll, 'acc_roll')
    M.set(rm & (np.abs(np.abs(pu) - w * 0.62) < 0.5), 'acc_leather')
    M.set(rm & (np.floor(pu * 1.1) % 3 == 0) & (np.abs(np.abs(pu) - w * 0.62) >= 0.5), 'acc_roll_lo')
    core = M.m > 0
    # straps: from the pack's top, over the shoulders, down the chest to the belt
    strap_band = shell_region(M, body | head_all, 1) & (M.m == 0)
    for s in (-1, 1):
        st = strap_band & (np.abs(M.X - s * 3.5) <= 0.65) & (M.Y > WY1 - 0.2) & (M.Y < NY0 + 0.4)
        gear(M, st, 'acc_leather')
        over = (np.abs(M.X - s * 3.5) <= 0.65) & (M.Y >= NY0 - 2.0) & (M.Y < NY0 + 1.6) & (M.Z > -5.6) & (M.Z < 1.0)
        over &= ((M.X / 7.0) ** 2 + (M.Z / 6.6) ** 2 <= 1.0)
        gear(M, over & ~(M.m > 0), 'acc_leather')

    tag(M, M.m > 0, BODY)
    tag(M, head_all, HEAD)
    tag(M, right_arm, ARM)
    y0, y1 = 7.2 + U, 34.0 + U

    def lean_at(y):
        return lean * min(1.0, max(0.0, (y - y0) / (y1 - y0)))
    if lean:
        ys = (np.arange(M.lo[1], M.hi[1]) + 0.5) / M.res
        for j, y in enumerate(ys):
            k = int(round(lean_at(y) * M.res))
            if k:
                for arr in (M.m, M.layer, M.glow):
                    arr[:, j, :] = np.roll(arr[:, j, :], k, axis=1)
    fy = 21.4 + U
    face = Frame(center=(0, fy, 0.4 + round(lean_at(fy) * M.res) / M.res), n=(0, 0.02, 1), reach=20)
    ch = Character(stage=0, model=M, face=face, eye_u=3.45, eye_v=0.75, eye_w=2.55, eye_h=3.9,
                   cheek_u=5.0, cheek_v=-1.9, cheek_w=1.7, cheek_h=1.1, mouth_v=-3.2,
                   face_extent=(-10, 10, -6.5, 6.5), scale_ref=32.0)
    ch.anchors = {'ground': (0, 0, 0), 'head_top': (0, 34 + U, 0), 'face': (0, 21.4 + U, 7.8)}
    ch.palette = dict(face_palette('#F2B8B0', brow='#1E1A1A', eye='#1E1A1A'), **GEAR)
    ch.no_mouth = True
    ch.face_extra = sher_face
    ch.whiskers = sher_whiskers()
    if lean:
        for wk in ch.whiskers:
            r = wk.root
            wk.root = (r[0], r[1], r[2] + round(lean_at(r[1]) * M.res) / M.res)
    ch.pivots = {'head': (0, 15.6 + U, 0.4), 'arm': (5.6, 13.4 + U, 0.4)}
    ch.size = 0.9
    return ch


def sher_face(cv, pal, expr):
    """His little cat mouth under the nose. No brows: the shared expressions that paint brows have them
    wiped. His whiskers are 3D strands (sher_whiskers)."""
    ink = '#2A2422'
    lw = 0.26
    mv = -3.2
    cv.a[(cv.V > 0.75 + 3.9 / 2 + 0.12) & (np.abs(cv.U) < 7.0)] = 0.0
    if expr in ('happy', 'proud'):
        m = cv.m_ellipse(0, mv - 0.55, 0.9, 0.85) & (cv.V <= mv - 0.2)
        cv.paint(m, pal['mouth_in'], lit=0.0)
    xs = np.linspace(-1.2, 1.2, 9)
    ys = mv - 0.38 * np.abs(np.sin(xs / 1.2 * math.pi))
    cv.paint(cv.m_stroke(list(zip(xs, ys)), lw), ink, lit=0.0)
    cv.paint(cv.m_stroke([(0, mv), (0, mv + 0.6)], lw), ink, lit=0.0)


def sher_whiskers():
    """Three long whiskers each side of the muzzle, fanning out and drooping a little."""
    HY = 22.0 + U
    out = []
    for s in (-1, 1):
        for (ry, rz, dy, length) in ((-2.55, 6.85, 0.30, 9.6), (-2.95, 6.7, 0.04, 10.0), (-3.35, 6.5, -0.24, 9.2)):
            out.append(Whisker(root=(s * 2.2, HY + ry, rz), direction=(s * 1.0, dy, 0.30), length=length, sag=0.55))
    return out

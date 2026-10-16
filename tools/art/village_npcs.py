"""Village Tales, Chapter 1 villagers: Mira, Bram, Pip and Alder (Quest Bible §3).

Built with the same voxel pipeline, outline and face-decal rig as the Evochi, so they share a family
look, but with their own silhouettes (none of them uses the Eggling's crest, egg body or four-foot
stance). Expressions use the shared face painter: neutral -> 'default', happy, worried, thinking, proud.
"""
from __future__ import annotations

import numpy as np

from voxel import Model
from decals import Frame
from characters import Character, egg_mask, shell_region, tube, spike, local_frame
from items import flower

NPC_EXPRESSIONS = {'neutral': 'default', 'happy': 'happy', 'worried': 'worried', 'thinking': 'thinking', 'proud': 'proud'}

INK = '#3B2923'


def face_palette(cheek, brow='#4A3328', eye='#282725'):
    return {
        'eye': eye, 'eye_hi': '#FFFFFF', 'mouth': '#5B3A31', 'mouth_in': '#8C3B36', 'tongue': '#F2A79A',
        'cheek': cheek, 'sweat': '#9BD3F0', 'outline': INK, 'brow': brow, 'tear': '#84C4E8',
    }


def box(M, lo, hi):
    return M.box(lo, hi)


def ball(M, c, r, p=2.2):
    if np.isscalar(r):
        r = (r, r, r)
    return (np.abs((M.X - c[0]) / r[0]) ** p + np.abs((M.Y - c[1]) / r[1]) ** p + np.abs((M.Z - c[2]) / r[2]) ** p) <= 1


def put(M, mask, col, empty=True):
    if empty:
        mask = mask & (M.m == 0)
    M.set(mask, col)
    return mask


def recolor(M, mask, col):
    M.set(mask & (M.m > 0), col)


def ring(M, c, n, r_out, r_in, depth):
    u, v, nn = local_frame(n)
    P = np.stack([M.X - c[0], M.Y - c[1], M.Z - c[2]], -1)
    U, V, N = P @ u, P @ v, P @ nn
    rr = np.maximum(np.abs(U), np.abs(V))
    return (rr <= r_out) & (rr >= r_in) & (np.abs(N) <= depth)


# ----------------------------------------------------------------------------
# Mira the Gardener: tanuki-like, split-leaf hood, single daisy, copper watering can
# ----------------------------------------------------------------------------
def build_mira(res=2) -> Character:
    M = Model((-18, -1, -16), (20, 40, 16), [], res=res)
    CREAM, CREAM_LO, CREAM_HI = '#F3E5C9', '#DCC8A6', '#FBF3E2'
    SAGE, SAGE_HI, SAGE_DK = '#7F9871', '#9CB58C', '#43523D'
    TERRA, MOSS, MOSS_HI = '#B76B4D', '#5E7F4A', '#76985E'
    COPPER, COPPER_HI, COPPER_LO = '#C9874E', '#E3A86E', '#9A5E34'
    body = egg_mask(M, (0, 8.2, 0), 8.4, 7.0, 7.4, 7.6, p=2.3)
    head = egg_mask(M, (0, 19.8, 0.6), 9.4, 8.2, 7.6, 8.4, p=2.5)
    core = body | head
    put(M, core, CREAM, empty=False)
    put(M, core & (M.Y < 3.2), CREAM_LO, empty=False)
    # muzzle and nose
    muz = egg_mask(M, (0, 17.4, 7.6), 3.6, 2.0, 2.2, 2.4, p=2.2)
    put(M, muz, CREAM_HI)
    put(M, box(M, (-1.0, 18.6, 9.3), (1.0, 19.8, 10.3)), INK)
    # tanuki tail (striped) behind
    tail = tube(M, [(0, 5.5, -6.0), (0.6, 7.5, -10.0), (1.2, 11.0, -12.5)], [3.0, 3.4, 2.8], p=2.4) & ~core
    put(M, tail, CREAM)
    for ty in (7.2, 10.2):
        recolor(M, tail & (np.abs(M.Y - ty) < 0.7), '#8D6B4A')
    # split-leaf hood: a thick shell over the head that leaves the face open
    hood = shell_region(M, head, 3) & ~core
    face_open = (M.Z > 1.0) & (((M.X / 7.4) ** 2 + ((M.Y - 18.6) / 6.6) ** 2) < 1.0)
    hood &= ~face_open & (M.Y > 13.5)
    put(M, hood, SAGE)
    rim = hood & shell_region(M, face_open & (M.Z > 2.0), 2)
    recolor(M, rim, SAGE_DK)
    recolor(M, hood & (M.Y > 25.5) & (M.X < 0), SAGE_HI)
    # the split-leaf hood: two broad leaf blades rising from the crown, leaning apart
    for sg in (-1, 1):
        a = np.radians(48) * sg
        base = np.array([sg * 2.2, 24.6, 0.4])
        ax = np.array([np.sin(a), np.cos(a), 0.0])
        ac = np.array([np.cos(a), -np.sin(a), 0.0])
        P = np.stack([M.X - base[0], M.Y - base[1], M.Z - base[2]], -1)
        al, cr, dz = P @ ax, P @ ac, M.Z - base[2]
        L, W = 13.5, 7.4
        taper = np.clip(1.15 - (al / L) ** 2 * 0.95, 0.05, 1)  # wide near the base, pointed tip
        blade = ((((al - L / 2) / (L / 2)) ** 2 + (cr / (W / 2 * taper)) ** 2) <= 1) & (np.abs(dz) <= 1.3) & (al > 0)
        put(M, blade, '#93B47C')
        recolor(M, blade & (cr * sg < -1.2), '#A9C691')
        edge = blade & ~((((al - L / 2) / (L / 2 - 0.6)) ** 2 + (cr / (W / 2 * taper - 0.6)) ** 2) <= 1)
        recolor(M, edge, '#5E7F4A')
        vein = (np.abs(cr) < 0.55) & (al > 0.5) & (al < L - 1.6)
        side = (np.abs(np.abs(cr) - (al - 2.0) * 0.0 - np.abs(((al - 1.5) % 3.0) - 1.5) * 0.9) < 0.45) & (al > 2.0) & (al < L - 2.5)
        recolor(M, blade & (vein | side) & (dz > 0.2), '#5E7F4A')
    # a single daisy above her left ear (the side she turns to you)
    occ = M.m > 0
    d = np.array([0.62, 0.42, 0.66]); d /= np.linalg.norm(d)
    pt = None
    for tt in np.arange(0, 20, 0.25):
        q = np.array([0, 20.0, 0.6]) + d * tt
        idx = np.floor(q * M.res - M.lo).astype(int)
        if np.any(idx < 0) or np.any(idx >= np.array(M.m.shape)):
            break
        if occ[tuple(idx)]:
            pt = q
    flower(M, pt + d * 0.6, n=tuple(d), size=1.7, petal='#FFFDF6', centre='#E8B956')
    # moss-green apron with a bib, straps and a pocket
    apron = shell_region(M, body, 2) & (M.Z > 1.5) & (M.Y > 2.0) & (M.Y < 13.5) & ~core
    apron &= (np.abs(M.X) < 7.2) | (M.Y < 9.0)
    put(M, apron, MOSS)
    pocket = apron & (np.abs(M.X) < 2.6) & (M.Y > 4.5) & (M.Y < 7.5)
    recolor(M, pocket, MOSS_HI)
    recolor(M, apron & (np.abs(M.Y - 9.0) < 0.5) & (np.abs(M.X) > 3.0), '#4C6A3B')
    # arms with terracotta cuffs
    for s in (-1, 1):
        arm = tube(M, [(s * 7.0, 12.0, 1.5), (s * 9.2, 9.0, 3.0), (s * 9.8, 7.2, 3.8)], [2.0, 1.8, 1.8], p=2.3) & ~core
        put(M, arm, CREAM)
        recolor(M, arm & (M.Y < 9.4) & (M.Y > 8.0), TERRA)
        put(M, ball(M, (s * 9.9, 6.4, 4.0), 1.7), CREAM)
    # copper watering can in her left hand (viewer's right)
    cx, cy, cz = 12.6, 4.6, 4.6
    can = ((M.X - cx) ** 2 + (M.Z - cz) ** 2 <= 2.4 ** 2) & (M.Y > cy - 2.6) & (M.Y < cy + 2.0)
    put(M, can, COPPER)
    recolor(M, can & (M.Y > cy + 1.3), COPPER_HI)
    recolor(M, can & (M.Y < cy - 2.0), COPPER_LO)
    spout = tube(M, [(cx + 1.8, cy - 0.5, cz + 0.6), (cx + 4.4, cy + 1.6, cz + 1.4), (cx + 5.4, cy + 2.6, cz + 1.6)], [0.8, 0.6, 0.9], p=2.0)
    put(M, spout, COPPER)
    handle = ring(M, (cx - 1.0, cy + 2.8, cz), (0, 0, 1), 2.0, 1.2, 0.45) & (M.Y > cy + 2.0)
    put(M, handle, COPPER_LO)
    # feet
    for s in (-1, 1):
        f = box(M, (s * 1.2 if s > 0 else -5.6, 0, 0.8), (5.6 if s > 0 else -1.2, 2.4, 5.6))
        f &= ~((M.Y > 1.6) & (M.Z > 4.6))
        put(M, f, '#C9B48F')
    face = Frame(center=(0, 19.6, 0.6), n=(0, 0.04, 1), reach=20)
    ch = Character(stage=0, model=M, face=face, eye_u=3.6, eye_v=1.4, eye_w=1.75, eye_h=3.2,
                   cheek_u=5.0, cheek_v=-1.5, cheek_w=1.9, cheek_h=1.4, mouth_v=-3.6,
                   face_extent=(-9, 9, -7, 7), scale_ref=30.0)
    ch.anchors = {'ground': (0, 0, 0), 'head_top': (0, 35, 1), 'face': (0, 19.6, 8.4)}
    ch.palette = face_palette('#E69878', brow='#43523D')
    return ch


# ----------------------------------------------------------------------------
# Bram the Lanternkeeper: squat badger-bear, wool apron, brass lens, lantern wrench
# ----------------------------------------------------------------------------
def build_bram(res=2) -> Character:
    M = Model((-20, -1, -16), (22, 36, 16), [], res=res)
    COAT, COAT_LO, COAT_HI = '#8D5D3B', '#6E4529', '#A2704A'
    CREAM = '#F3E5C9'
    APRON, APRON_LO = '#CDB78F', '#B39D74'
    COPPER, COPPER_HI = '#C69469', '#E2B488'
    GOLD = '#E8B956'
    body = egg_mask(M, (0, 8.6, 0), 10.6, 7.6, 7.8, 8.6, p=2.4)
    head = egg_mask(M, (0, 19.6, 1.0), 9.8, 7.4, 7.0, 8.2, p=2.6)
    core = body | head
    put(M, core, COAT, empty=False)
    put(M, core & (M.Y < 3.0), COAT_LO, empty=False)
    # badger stripe from the snout over the crown, and the cream muzzle block
    stripe = core & (np.abs(M.X) < 1.7) & (M.Y > 21.0) & (M.Z > -6)
    recolor(M, stripe, CREAM)
    snout = box(M, (-4.4, 15.2, 6.4), (4.4, 19.6, 10.8))
    snout &= ((np.abs(M.X) / 4.4) ** 6 + (np.abs(M.Y - 17.4) / 2.2) ** 6) <= 1.0
    put(M, snout, CREAM)
    put(M, box(M, (-1.4, 18.4, 10.4), (1.4, 19.8, 11.4)), INK)
    # round ears
    for s in (-1, 1):
        e = ball(M, (s * 7.2, 26.0, -0.5), (2.6, 2.6, 1.6)) & ~core
        put(M, e, COAT)
        recolor(M, e & (M.Z > 0.2) & (np.abs(M.X - s * 7.2) < 1.3) & (np.abs(M.Y - 26.0) < 1.3), '#D9B48E')
    # heavy wool apron with a gold hammer
    apron = shell_region(M, body, 2) & (M.Z > 1.0) & (M.Y > 1.5) & (M.Y < 15.5) & ~core
    apron &= (np.abs(M.X) < 7.8) | (M.Y < 10.0)
    put(M, apron, APRON)
    recolor(M, apron & (M.Y < 3.0), APRON_LO)
    ham = apron & (((np.abs(M.X) < 0.6) & (M.Y > 7.5) & (M.Y < 11.5)) | ((np.abs(M.X) < 2.0) & (M.Y > 10.6) & (M.Y < 12.2)))
    recolor(M, ham, GOLD)
    # leather tool belt
    belt = shell_region(M, body, 2) & ~core & (np.abs(M.Y - 7.0) < 0.8) & (M.Z <= 1.0)
    put(M, belt, '#5E3A24')
    # arms with oversized gloves
    for s in (-1, 1):
        arm = tube(M, [(s * 9.0, 12.0, 1.0), (s * 11.0, 8.6, 2.8)], [2.6, 2.4], p=2.3) & ~core
        put(M, arm, COAT)
        glove = ball(M, (s * 11.6, 6.4, 3.6), (2.6, 2.4, 2.4)) & ~core
        put(M, glove, '#6B4A35')
    # copper lantern wrench in the left hand (viewer's right)
    wx, wz = 13.8, 4.4
    shaft = box(M, (wx - 0.55, 2.0, wz - 0.55), (wx + 0.55, 14.0, wz + 0.55))
    put(M, shaft, COPPER)
    rr = np.sqrt((M.X - wx) ** 2 + (M.Y - 15.6) ** 2)
    jaw = (rr <= 2.3) & (rr >= 1.05) & (np.abs(M.Z - wz) <= 0.6) & ~((M.Y > 16.2) & (np.abs(M.X - wx) < 0.8))
    put(M, jaw, COPPER_HI)
    # short feet
    for s in (-1, 1):
        f = box(M, (s * 1.6 if s > 0 else -7.0, 0, 0.5), (7.0 if s > 0 else -1.6, 2.2, 6.4))
        put(M, f, '#553B2E')
    face = Frame(center=(0, 19.8, 1.0), n=(0, 0.06, 1), reach=20)
    ch = Character(stage=0, model=M, face=face, eye_u=3.8, eye_v=1.9, eye_w=1.7, eye_h=2.7,
                   cheek_u=5.6, cheek_v=-0.6, cheek_w=1.8, cheek_h=1.2, mouth_v=-3.9,
                   face_extent=(-9, 9, -7, 7), scale_ref=30.0)
    ch.anchors = {'ground': (0, 0, 0), 'head_top': (0, 29, 1), 'face': (0, 19.8, 9.0)}
    ch.palette = face_palette('#C9785A', brow='#3E2A1E')
    eu, ev, ew, eh = ch.eye_u, ch.eye_v, ch.eye_w, ch.eye_h

    def extras(cv, pal, expr):
        # thick eyebrows (raised on worried, one cocked when thinking) and the brass lens rim
        for s in (-1, 1):
            lift = 0.5 if expr in ('worried', 'happy') else 0.0
            tilt = 0.4 * s if expr == 'worried' else -0.25 * s if expr == 'proud' else 0.0
            if expr == 'thinking' and s > 0:
                lift, tilt = 0.7, 0.3
            y = ev + eh * 0.72 + lift
            cv.paint(cv.m_stroke([(s * eu - ew * 1.05, y + tilt), (s * eu + ew * 1.05, y - tilt)], 0.85), pal['brow'], lit=0.0)
        r = cv.m_rect(eu, ev, ew * 2.5, eh * 1.6, 0.9) & ~cv.m_rect(eu, ev, ew * 1.8, eh * 1.2, 0.6)
        cv.paint(r, '#C69469', lit=0.4)
    ch.face_extra = extras
    return ch


# ----------------------------------------------------------------------------
# Pip the Courier: upright rust sparrow, navy post cap, messenger satchel
# ----------------------------------------------------------------------------
def build_pip(res=2) -> Character:
    M = Model((-18, -1, -16), (18, 38, 16), [], res=res)
    FEATH, STRIPE, BELLY = '#D9954D', '#AD652F', '#F3E5C9'
    NAVY, NAVY_HI, GOLD = '#203B50', '#2F5571', '#E8B956'
    body = egg_mask(M, (0, 10.0, 0), 9.0, 8.6, 8.2, 8.4, p=2.2)
    head = egg_mask(M, (0, 19.4, 1.0), 8.2, 7.2, 6.6, 7.6, p=2.3)
    core = body | head
    put(M, core, FEATH, empty=False)
    # cream face and belly
    belly = core & (M.Z > 3.0) & (((M.X / 6.0) ** 2 + ((M.Y - 9.0) / 7.0) ** 2) < 1.0)
    recolor(M, belly, BELLY)
    facep = core & (M.Z > 3.5) & (((M.X / 6.4) ** 2 + ((M.Y - 18.6) / 4.6) ** 2) < 1.0)
    recolor(M, facep, BELLY)
    # darker streaks on the back
    streak = core & (M.Z < -2.0) & (np.floor((M.Y + M.X * 0.4) / 2.2).astype(int) % 3 == 0)
    recolor(M, streak, STRIPE)
    # short pointed beak
    bz = M.Z - 7.4
    beak = (bz > 0) & (bz < 3.2) & (np.abs(M.X) < 1.6 * (1 - bz / 3.4)) & (np.abs(M.Y - 17.4) < 1.2 * (1 - bz / 3.6))
    put(M, beak, '#E0A23A')
    recolor(M, beak & (M.Y < 17.2), '#B9762A')
    # oversized wings: three layered feather slabs on each side, sweeping back and down
    for sg in (-1, 1):
        for i, (y0, z0, L, W, col) in enumerate(((13.0, 2.0, 11.0, 5.0, FEATH), (11.4, 0.2, 11.5, 4.2, STRIPE), (9.6, -1.6, 10.5, 3.4, '#8A4E24'))):
            dvec = np.array([0.0, -0.62, -0.78])
            P = np.stack([M.X * 0, M.Y - y0, M.Z - z0], -1)
            al = P @ dvec
            cr = (M.Y - y0) * 0.78 - (M.Z - z0) * 0.62
            xin = sg * M.X
            x0 = 7.6 + i * 0.7
            w = (al >= 0) & (al <= L) & (np.abs(cr) <= W / 2 * (1 - al / (L * 1.15))) & (xin >= x0) & (xin <= x0 + 1.6)
            put(M, w, col)
    # tail tuft
    for (y, z, h) in ((7.0, -9.5, 3.0), (8.6, -11.0, 2.4), (10.2, -12.2, 2.0)):
        put(M, box(M, (-2.2, y, z - 1.0), (2.2, y + h, z + 1.0)), STRIPE)
    # thin legs and feet
    for s in (-1, 1):
        leg = box(M, (s * 2.6 - 0.45, 0.5, 0.6), (s * 2.6 + 0.45, 3.2, 1.6))
        put(M, leg, '#C98A4A')
        put(M, box(M, (s * 2.6 - 1.4, 0, 0.0), (s * 2.6 + 1.4, 0.8, 3.4)), '#C98A4A')
    # navy post cap with a visor and a cream wing badge
    cap = shell_region(M, head, 2) & ~core & (M.Y > 22.0) & ~((M.Z > 4.5) & (M.Y < 24.0))
    put(M, cap, NAVY)
    put(M, box(M, (-5.2, 25.2, -4.8), (5.2, 27.6, 5.0)) & ~core, NAVY)
    recolor(M, cap & (M.Y > 25.0) & (M.X < -1.0), NAVY_HI)
    visor = box(M, (-5.4, 22.6, 3.8), (5.4, 23.6, 9.2)) & ~core
    put(M, visor, '#152A3A')
    badge = (M.m > 0) & (M.Z > 4.0) & (np.abs(M.Y - 25.2) < 1.1) & (np.abs(M.X) < 2.2) & ~core
    recolor(M, badge, '#F3E5C9')
    recolor(M, badge & (np.abs(M.X) < 0.6), GOLD)
    # cross-body strap and a parchment satchel at the hip, rolled letter peeking out
    strap = shell_region(M, body, 1) & ~core & (np.abs((M.Y - 10.5) - M.X * 0.95) < 0.75) & (M.Z > -1)
    put(M, strap, '#6E4529')
    sx = 7.6
    sat = box(M, (sx - 1.6, 4.0, -0.5), (sx + 2.0, 9.0, 6.4)) & ~core
    put(M, sat, '#E9D9B5')
    recolor(M, sat & (M.Y > 7.4), '#8D5D3B')
    roll = ((M.Y - 9.2) ** 2 + (M.X - (sx + 0.4)) ** 2 <= 0.9 ** 2) & (M.Z > 1.0) & (M.Z < 5.6)
    put(M, roll, '#FBF5E8')
    put(M, roll & (np.abs(M.Z - 3.3) < 0.5), '#203B50', empty=False)
    face = Frame(center=(0, 19.2, 1.0), n=(0, 0.02, 1), reach=20)
    ch = Character(stage=0, model=M, face=face, eye_u=3.4, eye_v=1.5, eye_w=1.6, eye_h=3.0,
                   cheek_u=4.9, cheek_v=-1.0, cheek_w=1.6, cheek_h=1.2, mouth_v=-4.4,
                   face_extent=(-8, 8, -6, 6), scale_ref=30.0)
    ch.anchors = {'ground': (0, 0, 0), 'head_top': (0, 28, 1), 'face': (0, 19.2, 8.6)}
    ch.palette = face_palette('#E69878', brow='#7A4E2E')
    return ch


# ----------------------------------------------------------------------------
# Alder the Mapmaker: upright sage tortoise, map-etched shell, square spectacles, parchment tube
# ----------------------------------------------------------------------------
def build_alder(res=2) -> Character:
    M = Model((-18, -1, -18), (20, 36, 16), [], res=res)
    SHELL, EDGE, SKIN, SKIN_LO = '#7F9871', '#43523D', '#C3D1A0', '#A8B985'
    PLAS, LINEN, BRASS = '#E6D9B0', '#EFE6D0', '#E8B956'
    shell = egg_mask(M, (0, 11.2, -2.6), 11.4, 9.8, 8.8, 8.4, p=2.2)
    plastron = egg_mask(M, (0, 9.6, 1.4), 7.6, 7.6, 7.0, 5.2, p=2.3)
    head = egg_mask(M, (0, 21.6, 2.4), 7.4, 6.4, 6.0, 7.0, p=2.4)
    neck = tube(M, [(0, 15.0, 1.6), (0, 18.0, 2.2)], [3.6, 3.8], p=2.2)
    put(M, shell, SHELL, empty=False)
    put(M, plastron & ~shell | (plastron & (M.Z > 2.8)), PLAS, empty=False)
    put(M, neck | head, SKIN, empty=False)
    # scute lines: an angular map grid etched into the dome, plus the rim
    rimz = shell & ~egg_mask(M, (0, 11.2, -2.6), 10.4, 8.8, 7.8, 7.4, p=2.2)
    grid = rimz & ((np.abs(((M.X + 30) % 6.2) - 3.1) > 2.6) | (np.abs(((M.Y + 30) % 5.6) - 2.8) > 2.3)) & (M.Z < 2.6)
    recolor(M, grid, EDGE)
    recolor(M, shell & (M.Y < 3.4), EDGE)
    path = rimz & (np.abs(M.Y - 11.0 - 2.4 * np.sin(M.X * 0.55)) < 0.45) & (M.Z < 2.0)
    recolor(M, path, BRASS)
    # broad soft snout
    snout = egg_mask(M, (0, 20.0, 7.6), 4.4, 2.4, 2.4, 2.4, p=2.3)
    put(M, snout, SKIN)
    for s in (-1, 1):
        put(M, box(M, (s * 1.0 - 0.4, 20.8, 9.8), (s * 1.0 + 0.4, 21.6, 10.4)), '#5E6B48')
    # linen scarf with a copper compass pendant
    scarf = shell_region(M, neck | plastron, 2) & ~(shell | plastron | neck | head) & (M.Y > 14.6) & (M.Y < 17.6)
    put(M, scarf, LINEN)
    tailsc = box(M, (2.0, 10.0, 6.0), (4.6, 15.0, 7.4)) & ~(shell | plastron)
    put(M, tailsc, LINEN)
    comp = ring(M, (-1.8, 13.2, 6.9), (0, 0.2, 1), 1.5, 0.0, 0.5)
    put(M, comp, '#C69469')
    put(M, box(M, (-2.2, 12.8, 7.2), (-1.4, 13.6, 7.8)), '#FBF5E8', empty=False)
    # stubby arms and legs
    for s in (-1, 1):
        arm = tube(M, [(s * 7.2, 13.0, 1.8), (s * 9.6, 10.0, 4.0), (s * 9.8, 8.2, 5.2)], [2.0, 1.9, 1.9], p=2.3) & ~(shell | plastron)
        put(M, arm, SKIN)
        leg = box(M, (s * 2.4 - 2.2, 0, -1.0), (s * 2.4 + 2.2, 3.2, 4.4))
        put(M, leg, SKIN_LO)
    # parchment tube with brass caps, tucked under his left arm (viewer's right)
    t = tube(M, [(8.4, 4.2, 7.6), (11.6, 14.0, 4.0)], [1.25, 1.25], p=2.0)
    put(M, t, '#FBF5E8')
    for e in ((8.4, 4.2, 7.6), (11.6, 14.0, 4.0)):
        put(M, ball(M, e, 1.5) & ~t, BRASS)
    face = Frame(center=(0, 21.8, 2.4), n=(0, 0.05, 1), reach=20)
    ch = Character(stage=0, model=M, face=face, eye_u=3.0, eye_v=1.3, eye_w=1.5, eye_h=2.6,
                   cheek_u=4.4, cheek_v=-1.6, cheek_w=1.5, cheek_h=1.1, mouth_v=-3.8,
                   face_extent=(-8, 8, -6, 6), scale_ref=30.0)
    ch.anchors = {'ground': (0, 0, 0), 'head_top': (0, 28, 2), 'face': (0, 21.8, 9.4)}
    ch.palette = face_palette('#E1A68C', brow='#43523D')
    eu, ev, ew, eh = ch.eye_u, ch.eye_v, ch.eye_w, ch.eye_h

    def extras(cv, pal, expr):
        # little square spectacles
        for s in (-1, 1):
            r = cv.m_rect(s * eu, ev, ew * 2.7, eh * 1.55, 0.25) & ~cv.m_rect(s * eu, ev, ew * 2.05, eh * 1.15, 0.15)
            cv.paint(r, BRASS, lit=0.5)
        cv.paint(cv.m_stroke([(-eu + ew * 1.3, ev + 0.4), (eu - ew * 1.3, ev + 0.4)], 0.45), BRASS, lit=0.5)
    ch.face_extra = extras
    return ch


NPC_BUILDERS = {'mira': build_mira, 'bram': build_bram, 'pip': build_pip, 'alder': build_alder}

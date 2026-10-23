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


# animatable parts: every voxel belongs to one (Model.layer); pivots live on the Character
BODY, HEAD, ARM = 0, 1, 2
PART_NAMES = ('body', 'head', 'arm')


def tag(M, mask, part):
    M.layer[mask & (M.m > 0)] = part


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def slab(M, c, along, normal, length, width, thick, taper=0.0, round_=True):
    """A flat blade/sheet centred on c: `length` along `along`, `width` across, `thick` along `normal`.
    Returns (mask, a, w) with a, w the in-plane coordinates (a from -length/2 .. length/2)."""
    a_ = unit(along)
    n_ = unit(np.asarray(normal, float) - a_ * (np.dot(normal, a_)))
    w_ = np.cross(n_, a_)
    P = np.stack([M.X - c[0], M.Y - c[1], M.Z - c[2]], -1)
    a, w, n = P @ a_, P @ w_, P @ n_
    half_w = width / 2 * (1 - taper * np.clip((a + length / 2) / length, 0, 1))
    if round_:
        inside = (a / (length / 2)) ** 2 + (w / np.maximum(half_w, 1e-3)) ** 2 <= 1
    else:
        inside = (np.abs(a) <= length / 2) & (np.abs(w) <= half_w)
    return inside & (np.abs(n) <= thick / 2), a, w


def wrench(M, a, b, col, hi, r=0.75, jaw=2.8, toward=(0, 0, 1)):
    """A long lantern wrench from a to b with an open square jaw past b, the jaw facing `toward`."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    d = unit(b - a)
    shaft = tube(M, [a, b], [r, r], p=3.0)
    put(M, shaft, col)
    n = unit(np.asarray(toward, float) - d * np.dot(toward, d))
    c = b + d * jaw * 0.8
    w = np.cross(n, d)
    P = np.stack([M.X - c[0], M.Y - c[1], M.Z - c[2]], -1)
    pa, pw, pn = P @ d, P @ w, P @ n
    rr = np.sqrt(pa ** 2 + pw ** 2)
    jawm = (rr <= jaw) & (rr >= jaw * 0.42) & (np.abs(pn) <= 0.75) & ~((pa > jaw * 0.1) & (np.abs(pw) < jaw * 0.42))
    jawm |= (rr <= jaw * 0.62) & (pa < -jaw * 0.3) & (np.abs(pn) <= 0.75)      # solid throat into the shaft
    put(M, jawm, hi)
    return shaft | jawm


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
    m0 = M.m.copy()
    flower(M, pt + d * 0.6, n=tuple(d), size=1.7, petal='#FFFDF6', centre='#E8B956')
    daisy = M.m != m0
    # the head part stops where it meets the body, so the layer has nothing hidden inside the body
    tag(M, (head | muz | hood | daisy | (M.Y > 25.0) | box(M, (-1.2, 18.4, 9.0), (1.2, 20.0, 10.6))) & ~body, HEAD)
    # moss-green apron with a bib, straps and a pocket
    apron = shell_region(M, body, 2) & (M.Z > 1.5) & (M.Y > 2.0) & (M.Y < 13.5) & ~core
    apron &= (np.abs(M.X) < 7.2) | (M.Y < 9.0)
    put(M, apron, MOSS)
    pocket = apron & (np.abs(M.X) < 2.6) & (M.Y > 4.5) & (M.Y < 7.5)
    recolor(M, pocket, MOSS_HI)
    recolor(M, apron & (np.abs(M.Y - 9.0) < 0.5) & (np.abs(M.X) > 3.0), '#4C6A3B')
    tag(M, apron, BODY)
    # both arms forward, cradling a terracotta pot with a seedling she keeps checking on
    held = np.zeros(M.m.shape, bool)
    pcx, pcy, pcz = 0.0, 8.4, 10.8
    potm = ((M.X - pcx) ** 2 + (M.Z - pcz) ** 2 <= 2.7 ** 2) & (M.Y > pcy - 2.2) & (M.Y < pcy + 1.4)
    held |= put(M, potm, TERRA)
    rim_ = ((M.X - pcx) ** 2 + (M.Z - pcz) ** 2 <= 3.15 ** 2) & (M.Y >= pcy + 1.0) & (M.Y < pcy + 2.0)
    held |= put(M, rim_, '#C97B5A', empty=False)
    soil = ((M.X - pcx) ** 2 + (M.Z - pcz) ** 2 <= 2.5 ** 2) & (np.abs(M.Y - (pcy + 1.75)) < 0.3)
    recolor(M, soil, '#5B3A2A')
    stem = tube(M, [(pcx, pcy + 1.8, pcz), (pcx + 0.3, pcy + 4.6, pcz + 0.2), (pcx + 0.1, pcy + 6.0, pcz + 0.4)], [0.45, 0.4, 0.35], p=2.0)
    held |= put(M, stem, '#5E7F4A')
    for sgn in (-1, 1):
        lf, _, _ = slab(M, (pcx + sgn * 1.5, pcy + 3.8 + (0.6 if sgn > 0 else 0.0), pcz + 0.3), (sgn, 0.55, 0.0), (0, 0.2, 1), 3.0, 1.6, 0.6)
        held |= put(M, lf, '#76985E')
    m0 = M.m.copy()
    flower(M, (pcx + 0.1, pcy + 6.6, pcz + 0.6), n=(0.0, 0.45, 1.0), size=1.05, petal='#F6C9D3', centre='#E8B956')
    held |= M.m != m0
    for s_ in (-1, 1):
        arm = tube(M, [(s_ * 7.0, 12.0, 1.5), (s_ * 7.6, 8.6, 5.4), (s_ * 4.2, 8.2, 8.6)], [2.0, 1.8, 1.7], p=2.3) & ~core
        held |= put(M, arm, CREAM)
        recolor(M, arm & (np.abs(M.X) > 6.0) & (M.Y < 10.2) & (M.Y > 8.8), TERRA)
        held |= put(M, ball(M, (s_ * 3.4, 8.4, 9.4), 1.6), CREAM)
    tag(M, held, ARM)
    # feet
    for s_ in (-1, 1):
        f = box(M, (s_ * 1.2 if s_ > 0 else -5.6, 0, 0.8), (5.6 if s_ > 0 else -1.2, 2.4, 5.6))
        f &= ~((M.Y > 1.6) & (M.Z > 4.6))
        put(M, f, '#C9B48F')
    face = Frame(center=(0, 19.6, 0.6), n=(0, 0.04, 1), reach=20)
    ch = Character(stage=0, model=M, face=face, eye_u=3.6, eye_v=1.4, eye_w=1.75, eye_h=3.2,
                   cheek_u=5.0, cheek_v=-1.5, cheek_w=1.9, cheek_h=1.4, mouth_v=-3.6,
                   face_extent=(-9, 9, -7, 7), scale_ref=30.0)
    ch.anchors = {'ground': (0, 0, 0), 'head_top': (0, 35, 1), 'face': (0, 19.6, 8.4)}
    ch.palette = face_palette('#E69878', brow='#43523D')
    ch.pivots = {'head': (0, 14.0, 0.8), 'arm': (0, 11.4, 3.0)}
    ch.size = 1.0
    return ch


# ----------------------------------------------------------------------------
# Bram the Lanternkeeper: squat badger-bear, wool apron, brass lens, lantern wrench
# ----------------------------------------------------------------------------
def build_bram(res=2) -> Character:
    M = Model((-24, -1, -16), (22, 36, 16), [], res=res)
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
    tag(M, (head | snout | box(M, (-1.4, 18.4, 10.4), (1.4, 19.8, 11.4)) | (M.Y > 23.5)) & ~body, HEAD)
    GLOVE = '#6B4A35'
    # left fist on his hip, elbow out (viewer's right)
    arm = tube(M, [(9.0, 12.2, 0.8), (13.8, 9.8, -0.4), (11.0, 7.0, 1.8)], [2.6, 2.3, 2.2], p=2.3) & ~core
    put(M, arm, COAT)
    put(M, ball(M, (10.6, 6.8, 2.6), (2.3, 2.1, 2.2)) & ~core, GLOVE)
    # right arm up at the shoulder, steadying the big lantern wrench he carries everywhere
    held = np.zeros(M.m.shape, bool)
    held |= put(M, tube(M, [(-9.0, 12.6, 1.0), (-12.0, 10.6, 3.8), (-11.6, 13.4, 6.4)], [2.6, 2.4, 2.3], p=2.3) & ~core, COAT)
    held |= put(M, ball(M, (-11.2, 14.2, 7.0), (2.5, 2.4, 2.4)) & ~core, GLOVE)
    held |= wrench(M, (-10.0, 9.4, 8.4), (-16.6, 26.4, 0.6), COPPER, COPPER_HI, r=0.8, jaw=2.9, toward=(-0.35, 0.1, 1.0))
    tag(M, held, ARM)
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
    ch.pivots = {'head': (0, 14.6, 1.0), 'arm': (-9.6, 12.8, 1.4)}
    ch.size = 1.12
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
    for sg in (1,):
        for i, (y0, z0, L, W, col) in enumerate(((13.0, 2.0, 11.0, 5.0, FEATH), (11.4, 0.2, 11.5, 4.2, STRIPE), (9.6, -1.6, 10.5, 3.4, '#8A4E24'))):
            dvec = np.array([0.0, -0.62, -0.78])
            P = np.stack([M.X * 0, M.Y - y0, M.Z - z0], -1)
            al = P @ dvec
            cr = (M.Y - y0) * 0.78 - (M.Z - z0) * 0.62
            xin = sg * M.X
            x0 = 7.6 + i * 0.7
            w = (al >= 0) & (al <= L) & (np.abs(cr) <= W / 2 * (1 - al / (L * 1.15))) & (xin >= x0) & (xin <= x0 + 1.6)
            put(M, w, col)
    # the other wing (viewer's left) raised high, holding up a sealed letter for whoever is next
    held = np.zeros(M.m.shape, bool)
    base = np.array([-7.4, 13.6, 1.4])
    for i, (ang, L, W, col) in enumerate(((0.0, 10.5, 4.6, FEATH), (16.0, 9.6, 3.8, STRIPE), (32.0, 8.4, 3.0, '#8A4E24'))):
        a = np.radians(ang)
        dvec = unit(np.array([-0.52 - 0.5 * np.sin(a), 0.84 - 0.4 * np.sin(a), 0.22]))
        c = base + dvec * (L / 2) + np.array([0.0, 0.0, -0.9 * i])
        bl, _, _ = slab(M, c, dvec, (-0.45, 0.0, 1.0), L, W, 1.3, taper=0.55)
        held |= put(M, bl & ~core, col)
    tip = base + unit(np.array([-0.52, 0.84, 0.22])) * 10.0
    letter, la, lw = slab(M, tip + np.array([-0.2, 1.2, 1.4]), (0.97, -0.22, 0.0), (-0.3, 0.05, 1.0), 7.6, 5.2, 0.6, round_=False)
    held |= put(M, letter, '#FBF5E8', empty=False)
    flap = letter & (np.abs((2.6 - lw) - np.abs(la) * 0.68) < 0.4)
    recolor(M, flap, '#C9B48F')
    recolor(M, letter & ((np.abs(la) > 3.4) | (lw < -2.2) | (lw > 2.2)), '#E6D3AE')
    recolor(M, letter & ((la ** 2 + (lw + 0.1) ** 2) < 1.05 ** 2), '#B8402F')
    tag(M, held, ARM)
    # tail tuft
    for (y, z, h) in ((7.0, -9.5, 3.0), (8.6, -11.0, 2.4), (10.2, -12.2, 2.0)):
        put(M, box(M, (-2.2, y, z - 1.0), (2.2, y + h, z + 1.0)), STRIPE)
    # thin legs and feet
    for s in (-1, 1):
        leg = box(M, (s * 2.6 - 0.45, 0.5, 0.6), (s * 2.6 + 0.45, 3.2, 1.6))
        put(M, leg, '#C98A4A')
        put(M, box(M, (s * 2.6 - 1.4, 0, 0.0), (s * 2.6 + 1.4, 0.8, 3.4)), '#C98A4A')
    # navy post cap with a visor and a cream wing badge. The cap wraps the whole crown down to the
    # visor's line (it used to stop short at the front, so his feathers showed between visor and cap),
    # and the crown under it is navy too, so nothing orange can poke through. His face is painted on
    # him without the cap (decal_model), so no paint lands on the visor
    bare = M.copy()
    cap = shell_region(M, head, 2) & ~core & (M.Y > 21.6) & ~((M.Z > 4.5) & (M.Y < 22.6) & (np.abs(M.X) < 5.6))
    recolor(M, core & (M.Y > 22.6), NAVY)
    put(M, cap, NAVY)
    put(M, box(M, (-5.2, 25.2, -4.8), (5.2, 27.6, 5.0)) & ~core, NAVY)
    recolor(M, cap & (M.Y > 25.0) & (M.X < -1.0), NAVY_HI)
    # the visor juts out past the cap's front (which now comes down to meet it)
    zf = float(M.Z[(M.m > 0) & (np.abs(M.X) < 1.0) & (M.Y > 22.6) & (M.Y < 23.6)].max())
    visor = box(M, (-5.4, 22.6, 3.8), (5.4, 23.6, zf + 2.4)) & ~core
    put(M, visor, '#152A3A', empty=False)
    badge = (M.m > 0) & (M.Z > 4.0) & (np.abs(M.Y - 25.2) < 1.1) & (np.abs(M.X) < 2.2) & ~core
    recolor(M, badge, '#F3E5C9')
    recolor(M, badge & (np.abs(M.X) < 0.6), GOLD)
    hat = (M.m > 0) & (bare.m == 0)
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
    tag(M, (head | beak | cap | visor | (M.Y > 22.0)) & ~held & ~body, HEAD)
    face = Frame(center=(0, 19.2, 1.0), n=(0, 0.02, 1), reach=20)
    ch = Character(stage=0, model=M, face=face, eye_u=3.4, eye_v=1.5, eye_w=1.6, eye_h=3.0,
                   cheek_u=4.9, cheek_v=-1.0, cheek_w=1.6, cheek_h=1.2, mouth_v=-4.4,
                   face_extent=(-8, 8, -6, 6), scale_ref=30.0)
    ch.anchors = {'ground': (0, 0, 0), 'head_top': (0, 28, 1), 'face': (0, 19.2, 8.6)}
    ch.palette = face_palette('#E69878', brow='#7A4E2E')
    ch.no_mouth = True
    ch.decal_model, ch.no_decal = bare, hat
    ch.pivots = {'head': (0, 14.6, 0.6), 'arm': (-7.4, 13.6, 1.4)}
    ch.size = 0.84
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
    tag(M, (head | snout | ((M.Y > 18.6) & (M.Z > 6.0))) & ~neck, HEAD)
    # stubby legs; arms forward, holding his newest map open for you to see
    held = np.zeros(M.m.shape, bool)
    for s_ in (-1, 1):
        leg = box(M, (s_ * 2.4 - 2.2, 0, -1.0), (s_ * 2.4 + 2.2, 3.2, 4.4))
        put(M, leg, SKIN_LO)
    mx, my0, my1 = 6.4, 7.4, 15.2
    mz = 9.6 - 0.035 * M.X ** 2 - (M.Y - 11.3) * 0.22
    sheet = (np.abs(M.X) <= mx) & (M.Y >= my0) & (M.Y <= my1) & (np.abs(M.Z - mz) <= 0.3)
    held |= put(M, sheet, '#F2E6C4')
    # the map itself: a river, forest, hills, a dashed trail and the next X
    river = sheet & (np.abs(M.Y - (9.4 + 1.6 * np.sin(M.X * 0.55) + 0.18 * M.X)) < 0.45)
    recolor(M, river, '#6FA8C8')
    for fx, fy in ((-3.8, 13.2), (-2.6, 13.8), (-4.6, 12.4), (3.6, 9.0), (4.6, 8.6)):
        recolor(M, sheet & ((M.X - fx) ** 2 + (M.Y - fy) ** 2 < 0.8 ** 2), '#7F9871')
    for hx in (1.4, 3.4):
        recolor(M, sheet & (M.Y > 12.2) & (M.Y < 14.4) & (np.abs(M.X - hx) < (14.4 - M.Y) * 0.55), '#A08A6A')
    trail = sheet & (np.abs(M.Y - (8.6 + (M.X + 5.5) * 0.42)) < 0.35) & (((M.X + 30) % 1.6) < 0.9)
    recolor(M, trail, '#B5533C')
    xm = sheet & ((np.abs((M.X - 4.2) - (M.Y - 13.4)) < 0.38) | (np.abs((M.X - 4.2) + (M.Y - 13.4)) < 0.38)) & (np.abs(M.X - 4.2) < 0.9)
    recolor(M, xm, '#C0392B')
    recolor(M, sheet & ((np.abs(M.X) > mx - 0.5) | (M.Y < my0 + 0.5) | (M.Y > my1 - 0.5)), '#D9C79C')
    for s_ in (-1, 1):
        rx = s_ * (mx + 0.5)
        rz = 9.6 - 0.035 * (mx + 0.5) ** 2
        held |= put(M, ((M.X - rx) ** 2 + (M.Z - (rz - 0.2)) ** 2 <= 0.85 ** 2) & (M.Y >= my0 - 0.3) & (M.Y <= my1 + 0.3), '#E6D9B0')
        arm = tube(M, [(s_ * 7.2, 13.0, 1.8), (s_ * 9.8, 10.8, 4.8), (s_ * 7.8, 11.2, 7.6)], [2.0, 1.9, 1.8], p=2.3) & ~(shell | plastron)
        held |= put(M, arm, SKIN)
        held |= put(M, ball(M, (s_ * 7.4, 11.4, 8.4), 1.6), SKIN)
    tag(M, held, ARM)
    face = Frame(center=(0, 21.8, 2.4), n=(0, 0.05, 1), reach=20)
    ch = Character(stage=0, model=M, face=face, eye_u=3.0, eye_v=1.3, eye_w=1.5, eye_h=2.6,
                   cheek_u=4.4, cheek_v=-1.6, cheek_w=1.5, cheek_h=1.1, mouth_v=-3.8,
                   face_extent=(-8, 8, -6, 6), scale_ref=30.0)
    ch.anchors = {'ground': (0, 0, 0), 'head_top': (0, 28, 2), 'face': (0, 21.8, 9.4)}
    ch.palette = face_palette('#E1A68C', brow='#43523D')
    eu, ev, ew, eh = ch.eye_u, ch.eye_v, ch.eye_w, ch.eye_h

    # little square spectacles, built in 3D and standing off his face (they used to be painted on):
    # two rims in one plane just in front of the face, a bridge, and arms back along his head to the
    # ears. The face is painted on the head without them (decal_model), and none of the paint lands
    # on them (no_decal)
    ch.decal_model = M.copy()
    glasses = spectacles(M, (eu, 21.8 + ev), (ew * 1.03, eh * 0.58), BRASS, (0, 21.6, 2.4), (7.4, 7.0))
    tag(M, glasses, HEAD)
    ch.no_decal = glasses
    ch.pivots = {'head': (0, 16.8, 2.2), 'arm': (0, 12.4, 3.0)}
    ch.size = 1.0
    return ch


def spectacles(M, eye, half, col, head_c, head_r, rim=0.5, gap=0.0):
    """Square spectacles as voxels on a face looking down +z: lenses centred on (+-eye[0], eye[1]),
    [half] the lens opening's half-size (u, v); [rim] thick. The frame stands [gap] in front of the
    face round the eyes (its lower rims may rest on the snout); the arms run straight back from the
    top outer corners, then along the sides of the head (centre [head_c], radii x/z [head_r]) to the
    ears. Returns the mask of what it added."""
    eu, ey = eye
    hu, hv = half
    filled = M.m > 0
    xs, ys = M.X[:, 0, 0], M.Y[0, :, 0]
    zcol = np.where(filled, M.Z, -np.inf).max(axis=2)            # the front-most voxel of each (x, y) column
    behind = (np.abs(np.abs(xs[:, None]) - eu) <= hu) & (ys[None, :] >= ey - hv * 0.3) & (ys[None, :] <= ey + hv + rim)
    zp = float(zcol[behind].max()) + 0.5 / M.res + gap               # back of the frame
    slab = (M.Z >= zp) & (M.Z < zp + rim)
    du, dv = np.abs(np.abs(M.X) - eu), np.abs(M.Y - ey)
    rims = slab & (du <= hu + rim) & (dv <= hv + rim) & ~((du < hu) & (dv < hv))
    bridge = slab & (np.abs(M.X) < eu - hu) & (np.abs(M.Y - (ey + hv * 0.4)) < rim * 0.5 + 1e-6)
    ay = (M.Y >= ey + hv) & (M.Y < ey + hv + rim)
    hx, hz = head_r
    side = np.abs(M.X) / hx >= np.abs(M.Z - head_c[2]) / hz * 0.85              # where the head faces sideways
    hug = ay & shell_region(M, filled, 1) & side & (M.Z < zp) & (M.Z > head_c[2] - 1.0)
    xo = eu + hu + rim * 0.5
    z_side = float(M.Z[hug].max()) if hug.any() else zp - 3.0
    hinge = ay & (np.abs(np.abs(M.X) - xo) < rim * 0.5 + 1e-6) & (M.Z < zp + rim) & (M.Z >= z_side - 0.5) & ~filled
    # join the hinge to the side arm along the head's outline at that height
    reach = ay & shell_region(M, filled, 1) & (np.abs(M.X) >= xo - 1e-6) & (M.Z >= z_side - 0.5) & (M.Z < zp + rim)
    g = (rims | bridge | hinge | hug | reach) & ~filled
    put(M, g, col)
    return g


NPC_BUILDERS = {'mira': build_mira, 'bram': build_bram, 'pip': build_pip, 'alder': build_alder}


# ----------------------------------------------------------------------------
# Idle / talk / listen animation for the layered villagers (played by the web and Flutter apps).
# Each state loops over `dur` ms. Tracks key a part: [t, rotate deg, dx, dy] with dx/dy as a fraction
# of the sprite's width/height (the part turns about its pivot); the 'all' track is
# [t, squash, dy]: the whole villager squashes (scaleY = squash, scaleX = 2 - squash) about the feet.
# `listen` plays while the other villager in the room is talking: they react to each other.
# ----------------------------------------------------------------------------
_BREATHE = [[0, 1, 0], [0.25, 0.988, 0], [0.5, 1, 0], [0.75, 0.99, 0], [1, 1, 0]]
_TALK_ALL = [[0, 1, 0], [0.2, 0.975, 0], [0.4, 1.012, -0.008], [0.6, 0.985, 0], [0.8, 1.006, -0.004], [1, 1, 0]]

NPC_ANIM = {
    'bram': {
        # now and then he lifts the wrench off his shoulder, eyes it, and settles it back
        'idle': {'dur': 7600, 'tracks': {
            'all': _BREATHE,
            'arm': [[0, 0, 0, 0], [0.5, 0, 0, 0], [0.57, -9, 0, -0.016], [0.63, -6, 0, -0.01], [0.67, -9, 0, -0.016],
                    [0.74, 2, 0, 0], [0.78, 0, 0, 0], [1, 0, 0, 0]],
            'head': [[0, 0, 0, 0], [0.5, 0, 0, 0], [0.57, -5, 0, 0], [0.72, -5, 0, 0], [0.8, 0, 0, 0], [1, 0, 0, 0]]}},
        'talk': {'dur': 1700, 'tracks': {
            'all': _TALK_ALL,
            'head': [[0, 0, 0, 0], [0.25, 3, 0, 0], [0.5, 0, 0, 0], [0.75, -2, 0, 0], [1, 0, 0, 0]],
            'arm': [[0, 0, 0, 0], [0.3, -4, 0, -0.006], [0.6, 1, 0, 0], [1, 0, 0, 0]]}},
    },
    'mira': {
        # she lifts the seedling to her face to check on it, head tipped toward it
        'idle': {'dur': 7000, 'tracks': {
            'all': _BREATHE,
            'arm': [[0, 0, 0, 0], [0.32, 0, 0, 0], [0.42, -2, 0, -0.034], [0.66, -2, 0, -0.034], [0.76, 0, 0, 0], [1, 0, 0, 0]],
            'head': [[0, 0, 0, 0], [0.34, 0, 0, 0], [0.44, 6, 0, 0.008], [0.52, 3, 0, 0.008], [0.6, 7, 0, 0.008],
                     [0.68, 6, 0, 0.008], [0.78, 0, 0, 0], [1, 0, 0, 0]]}},
        'talk': {'dur': 1800, 'tracks': {
            'all': _TALK_ALL,
            'head': [[0, 0, 0, 0], [0.3, -3, 0, 0], [0.6, 2, 0, 0], [1, 0, 0, 0]],
            'arm': [[0, 0, 0, 0], [0.4, 0, 0, -0.01], [0.8, 0, 0, 0], [1, 0, 0, 0]]}},
    },
    'pip': {
        # waves the letter, hops; perks up whenever Alder speaks
        'idle': {'dur': 5600, 'tracks': {
            'all': [[0, 1, 0], [0.56, 1, 0], [0.6, 0.94, 0], [0.65, 1.04, -0.05], [0.7, 0.96, 0], [0.74, 1, 0], [1, 1, 0]],
            'arm': [[0, 0, 0, 0], [0.08, -10, 0, 0], [0.16, 5, 0, 0], [0.24, -8, 0, 0], [0.32, 0, 0, 0], [1, 0, 0, 0]],
            'head': [[0, 0, 0, 0], [0.8, 0, 0, 0], [0.85, 6, 0, 0], [0.95, 6, 0, 0], [1, 0, 0, 0]]}},
        'talk': {'dur': 1300, 'tracks': {
            'all': [[0, 1, 0], [0.25, 0.96, 0], [0.5, 1.03, -0.02], [0.75, 0.98, 0], [1, 1, 0]],
            'head': [[0, 0, 0, 0], [0.25, 4, 0, 0], [0.5, -2, 0, 0], [0.75, 3, 0, 0], [1, 0, 0, 0]],
            'arm': [[0, 0, 0, 0], [0.25, -7, 0, 0], [0.5, 3, 0, 0], [0.75, -5, 0, 0], [1, 0, 0, 0]]}},
        'listen': {'dur': 2600, 'tracks': {
            'all': [[0, 1, 0], [0.08, 0.95, 0], [0.16, 1.03, -0.035], [0.24, 1, 0], [1, 1, 0]],
            'head': [[0, 7, 0, 0], [0.4, 7, 0, 0], [0.5, 9, 0, 0.006], [0.6, 7, 0, 0], [0.8, 9, 0, 0.006], [0.9, 7, 0, 0], [1, 7, 0, 0]],
            'arm': [[0, 8, 0, 0.01], [1, 8, 0, 0.01]]}},
    },
    'sher': {
        # Sher (wilds_npcs.py): bounces on his toes, glances back down the trail, tugs his neckerchief
        'idle': {'dur': 6400, 'tracks': {
            'all': [[0, 1, 0], [0.12, 0.97, 0], [0.18, 1.03, -0.03], [0.24, 1, 0], [0.62, 1, 0], [0.66, 0.98, 0],
                    [0.7, 1.02, -0.02], [0.74, 1, 0], [1, 1, 0]],
            'head': [[0, 0, 0, 0], [0.3, 0, 0, 0], [0.36, -7, 0, 0], [0.5, -7, 0, 0], [0.56, 3, 0, 0], [0.62, 0, 0, 0], [1, 0, 0, 0]],
            'arm': [[0, 0, 0, 0], [0.78, 0, 0, 0], [0.83, -24, 0, -0.01], [0.88, -18, 0, -0.01], [0.92, -24, 0, -0.01],
                    [0.97, 0, 0, 0], [1, 0, 0, 0]]}},
        'talk': {'dur': 1500, 'tracks': {
            'all': [[0, 1, 0], [0.25, 0.975, 0], [0.5, 1.015, -0.012], [0.75, 0.985, 0], [1, 1, 0]],
            'head': [[0, 0, 0, 0], [0.25, 4, 0, 0], [0.5, -2, 0, 0], [0.75, 3, 0, 0], [1, 0, 0, 0]],
            'arm': [[0, 0, 0, 0], [0.3, -10, 0, 0], [0.6, 2, 0, 0], [0.85, -6, 0, 0], [1, 0, 0, 0]]}},
        'listen': {'dur': 2800, 'tracks': {
            'all': [[0, 1, 0], [1, 1, 0]],
            'head': [[0, 5, 0, 0], [0.4, 5, 0, 0], [0.5, 8, 0, 0.005], [0.6, 5, 0, 0], [1, 5, 0, 0]],
            'arm': [[0, 0, 0, 0], [1, 0, 0, 0]]}},
    },
    'alder': {
        # slow nods over his map, lowering it to peek at you; turns to Pip when Pip chatters
        'idle': {'dur': 8200, 'tracks': {
            'all': [[0, 1, 0], [0.5, 0.992, 0], [1, 1, 0]],
            'head': [[0, 0, 0, 0], [0.2, -3, 0, 0], [0.32, 1, 0, 0], [0.44, -3, 0, 0], [0.56, 0, 0, 0], [1, 0, 0, 0]],
            'arm': [[0, 0, 0, 0], [0.5, 0, 0, 0], [0.58, 0, 0, 0.03], [0.82, 0, 0, 0.03], [0.9, 0, 0, 0], [1, 0, 0, 0]]}},
        'talk': {'dur': 2000, 'tracks': {
            'all': _TALK_ALL,
            'head': [[0, 0, 0, 0], [0.25, -3, 0, 0], [0.5, 1, 0, 0], [0.75, -2, 0, 0], [1, 0, 0, 0]],
            'arm': [[0, 0, 0, 0], [0.5, 0, 0, 0.012], [1, 0, 0, 0]]}},
        'listen': {'dur': 3000, 'tracks': {
            'all': [[0, 1, 0], [1, 1, 0]],
            'head': [[0, 6, 0, 0], [0.3, 6, 0, 0], [0.4, 3, 0, 0.006], [0.5, 6, 0, 0], [0.7, 3, 0, 0.006], [0.8, 6, 0, 0], [1, 6, 0, 0]],
            'arm': [[0, 0, 0, 0.028], [1, 0, 0, 0.028]]}},
    },
}

"""Evochi lizard family voxel models (Eggling, Juvenile, Elder) and face rigs."""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np
from scipy import ndimage

from voxel import Model
from decals import Surface, Frame, Canvas, project_canvas, mix

MATS = ['shell', 'belly', 'pattern', 'crest', 'crest_hi', 'feet', 'feet_shade', 'claw']


# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------
def egg_mask(M: Model, c, rx, ry_top, ry_bot, rz, p=2.2):
    cx, cy, cz = c
    ry = np.where(M.Y >= cy, ry_top, ry_bot)
    return (np.abs((M.X - cx) / rx) ** p + np.abs((M.Y - cy) / ry) ** p
            + np.abs((M.Z - cz) / rz) ** p) <= 1.0


def shell_region(M: Model, body_mask, thickness_vox=1):
    st = ndimage.generate_binary_structure(3, 1)
    d = ndimage.binary_dilation(body_mask, st, iterations=thickness_vox)
    return d & ~body_mask


def local_frame(n, up=(0, 1, 0)):
    n = np.asarray(n, float)
    n = n / np.linalg.norm(n)
    up = np.asarray(up, float)
    u = np.cross(up, n)
    if np.linalg.norm(u) < 1e-6:
        u = np.array([1.0, 0, 0])
    u /= np.linalg.norm(u)
    v = np.cross(n, u)
    return u, v, n


def stamp(M: Model, region, center, normal, shape_fn, mat, up=(0, 1, 0), depth=3.0):
    """Assign `mat` to voxels in `region` whose local (u,v) around center satisfies shape_fn."""
    u, v, n = local_frame(normal, up)
    P = np.stack([M.X - center[0], M.Y - center[1], M.Z - center[2]], -1)
    U = P @ u
    V = P @ v
    N = P @ n
    m = region & shape_fn(U, V) & (np.abs(N) < depth)
    M.set(m, mat)
    return m


def surface_point(M: Model, body_mask, origin, direction, tmax=40):
    """Ray-march from origin along direction, return the last point inside body_mask."""
    origin = np.asarray(origin, float)
    d = np.asarray(direction, float)
    d /= np.linalg.norm(d)
    last = None
    for t in np.arange(0, tmax, 0.1):
        p = origin + d * t
        idx = np.floor(p * M.res - M.lo).astype(int)
        if np.any(idx < 0) or np.any(idx >= np.array(M.m.shape)):
            break
        if body_mask[tuple(idx)]:
            last = p
        elif last is not None:
            break
    return last


def sph(theta_deg, phi_deg):
    """Direction from spherical angles: theta = azimuth from +z toward +x, phi = elevation."""
    t, p = math.radians(theta_deg), math.radians(phi_deg)
    return np.array([math.sin(t) * math.cos(p), math.sin(p), math.cos(t) * math.cos(p)])


def plus_shape(arm_w, arm_l):
    return lambda U, V: ((np.abs(U) <= arm_w / 2) & (np.abs(V) <= arm_l / 2)) | (
        (np.abs(V) <= arm_w / 2) & (np.abs(U) <= arm_l / 2))


def square_shape(w, h=None):
    h = h or w
    return lambda U, V: (np.abs(U) <= w / 2) & (np.abs(V) <= h / 2)


def diamond_shape(r):
    return lambda U, V: (np.abs(U) + np.abs(V)) <= r


# ----------------------------------------------------------------------------
# Character definition container
# ----------------------------------------------------------------------------
@dataclass
class Character:
    stage: int
    model: Model
    face: Frame
    eye_u: float              # horizontal offset of each eye centre
    eye_v: float              # vertical offset of eye centre
    eye_w: float
    eye_h: float
    cheek_u: float
    cheek_v: float
    cheek_w: float
    cheek_h: float
    mouth_v: float
    face_extent: tuple        # canvas extent (u0,u1,v0,v1)
    scale_ref: float          # reference size for consistent scaling
    pattern_decals: list = field(default_factory=list)   # (Frame, painter fn)
    anchors: dict = field(default_factory=dict)          # named 3D anchor points
    ground_y: float = 0.0


# ----------------------------------------------------------------------------
# Stage 1: Eggling
# ----------------------------------------------------------------------------
def build_eggling(res=2, feet=None, lo_y=-1, head=None, tail=0.0) -> Character:
    """feet: {(side, front): (dy, dz)} moves a foot (side -1/+1, front True/False) relative to the body,
    in world units (multiples of 1/res keep it on the voxel grid): the walk cycle (walk.py). An Eggling
    is all one egg: [head] and [tail] (the bigger stages' nod and tail swing) do nothing here."""
    feet = feet or {}
    M = Model((-18, lo_y, -16), (18, 35, 18), MATS, res=res)
    body = egg_mask(M, (0, 11.2, 0), 13.0, 13.2, 9.8, 11.6, p=2.25)
    M.set(body, 'shell')

    # snout bump (slightly lighter cream)
    sh = shell_region(M, body, 2 * res)
    sh = shell_region(M, body, res)
    snout = sh & (M.Z > 6)
    # rounded-rectangle footprint
    snout &= ((np.abs(M.X) / 3.0) ** 4 + (np.abs(M.Y - 7.9) / 2.1) ** 4) <= 1.0
    M.set(snout, 'belly')
    body_full = M.m > 0

    # crest: stepped gold blocks running front-top to back
    crest_boxes = [
        ((-2.0, 21.5, -1.5), (2.0, 31.5, 3.0)),      # tall front block
        ((-2.0, 20.5, -4.5), (2.0, 29.0, -1.5)),
        ((-2.0, 19.0, -7.5), (2.0, 26.5, -4.5)),
        ((-1.5, 15.5, -10.0), (1.5, 23.0, -7.5)),
        # flanking front blocks
        ((2.0, 20.5, -1.0), (4.8, 28.0, 2.6)),
        ((-4.8, 20.5, -1.0), (-2.0, 28.0, 2.6)),
        ((4.8, 19.5, -0.5), (7.0, 25.0, 2.2)),
        ((-7.0, 19.5, -0.5), (-4.8, 25.0, 2.2)),
        # flanking rear blocks
        ((2.0, 19.0, -6.0), (4.2, 25.5, -2.0)),
        ((-4.2, 19.0, -6.0), (-2.0, 25.5, -2.0)),
        ((4.2, 17.5, -5.0), (6.2, 22.5, -1.5)),
        ((-6.2, 17.5, -5.0), (-4.2, 22.5, -1.5)),
    ]
    for i, (lo, hi) in enumerate(crest_boxes):
        b = M.box(lo, hi) & ~body & (M.m == 0)
        M.set(b, 'crest.%d' % i)
    # highlight caps on the tallest crest blocks
    for lo, hi in crest_boxes[:1] + crest_boxes[6:8]:
        cap = M.box((lo[0], hi[1] - 0.5, lo[2]), (hi[0], hi[1], hi[2])) & (M.m > 0)
        M.set(cap, 'crest_hi')

    # ear plates (side gold plates, stacked)
    for s in (-1, 1):
        for (cy, ry, rz, ox, zoff) in ((9.6, 2.6, 2.2, 0.6, 0.3), (13.9, 1.6, 1.8, 0.0, -0.2),
                                        (5.6, 1.5, 1.8, -0.2, 0.8)):
            ear = M.box((s * 12.5 - 1.9 + s * ox, cy - ry, zoff - rz), (s * 12.5 + 1.9 + s * ox, cy + ry, zoff + rz))
            ear = ear & ~body
            ear &= ((np.abs(M.Y - cy) / ry) ** 6 + (np.abs(M.Z - zoff) / rz) ** 6) <= 1.0
            M.set(ear & (M.m == 0), 'crest.e%d' % (int(cy)))

    # feet
    for s in (-1, 1):
        for (z0, z1, h) in ((3.0, 10.0, 4.2), (-9.5, -3.5, 3.6)):
            dy, dz = feet.get((s, z0 > 0), (0.0, 0.0))
            z0, z1, y0, h = z0 + dz, z1 + dz, dy, h + dy
            x0, x1 = (4.0, 10.8) if s > 0 else (-10.8, -4.0)
            f = M.box((x0, y0, z0), (x1, h, z1))
            # chamfer top-front edge
            f &= ~((M.Y > h - 1.0) & (M.Z > z1 - 1.0))
            M.set(f & (M.m == 0) | (f & (M.m > 0) & (M.Y < 4.0 + dy)), 'feet')
            M.set(M.box((x0, y0, z0), (x1, y0 + 1.0, z1)) & f, 'feet_shade')
            if z0 > dz:
                # claws: three cream nubs on the front edge
                cx = np.linspace(x0 + 1.1, x1 - 1.1, 3)
                for c in cx:
                    cl = M.box((c - 0.6, y0, z1 - 0.5), (c + 0.6, y0 + 1.6, z1 + 1.2))
                    M.set(cl, 'claw')

    body_mask = (M.m > 0)
    shl = shell_region(M, body, 1)
    # scattered raised scale squares on upper body
    patches = [
        (sph(-35, 42), square_shape(2.0)), (sph(38, 40), square_shape(2.0)),
        (sph(-60, 25), square_shape(1.6)), (sph(62, 22), square_shape(1.6)),
        (sph(-20, 58), square_shape(1.6)), (sph(22, 60), square_shape(1.8)),
        (sph(-95, 38), square_shape(2.2)), (sph(98, 36), square_shape(2.0)),
        (sph(-140, 40), square_shape(1.8)), (sph(140, 42), square_shape(1.8)),
        (sph(-120, 10), square_shape(1.6)), (sph(122, 8), square_shape(1.6)),
        (sph(-75, 52), square_shape(1.4)), (sph(78, 50), square_shape(1.4)),
    ]
    centre = np.array([0, 11.2, 0])
    for d, shp in patches:
        p = surface_point(M, body, centre, d)
        if p is not None:
            stamp(M, shl, p, d, shp, 'pattern')
    # side crosses toward the back
    for s in (-1, 1):
        d = sph(s * 118, 18)
        p = surface_point(M, body, centre, d)
        stamp(M, shl, p, d, plus_shape(1.7, 5.4), 'pattern')

    face = Frame(center=(0, 11.2, 0), n=(0, 0, 1), reach=20)

    def back_pattern(cv: Canvas, pal):
        # vertical chain of diamonds down the back
        for (cu, cvv, r) in ((0, 3.2, 1.9), (-2.7, 0.5, 1.9), (2.7, 0.5, 1.9), (0, 0.5, 1.9),
                             (0, -2.2, 1.9), (0, -5.0, 1.5)):
            cv.bevel_diamond(cu, cvv, r, pal['pattern'], pal['pattern_hi'], pal['crest_lo'], 0.4)

    def forehead(cv: Canvas, pal):
        for (cu, cvv) in ((0, 2.55), (-2.55, 0), (2.55, 0), (0, -2.55)):
            cv.bevel_diamond(cu, cvv, 1.95, pal['crest'], pal['crest_hi'], pal['crest_lo'], 0.45)

    pattern_decals = [
        (Frame(center=(0, 19.0, 0), n=(0, 0.25, 1), reach=22), (-5, 5, -5, 5), forehead),
        (Frame(center=(0, 10.0, 0), n=(0, 0.05, -1), reach=22), (-5, 5, -7.5, 5.5), back_pattern),
    ]

    ch = Character(stage=1, model=M, face=face,
                   eye_u=6.3, eye_v=2.5, eye_w=2.35, eye_h=5.7,
                   cheek_u=9.0, cheek_v=-1.6, cheek_w=2.5, cheek_h=1.9,
                   mouth_v=-3.55, face_extent=(-12, 12, -7, 8), scale_ref=34.0,
                   pattern_decals=pattern_decals)
    ch.anchors = {
        'head_top': (0, 31.5, 0.5), 'neck': (0, 5.0, 6.0), 'back': (0, 13.0, -10.5),
        'ground': (0, 0, 0), 'face': (0, 11.2, 11.6), 'hand': (11.0, 7.0, 4.0),
    }
    return ch


# ----------------------------------------------------------------------------
# Face painting (expressions)
# ----------------------------------------------------------------------------
EXPRESSIONS = ['default', 'blink', 'happy', 'curious', 'surprised', 'determined', 'sad',
               'sleepy', 'excited', 'neutral', 'sick', 'memorial']


def paint_face(ch: Character, cv: Canvas, pal: dict, expr: str):
    eu, ev, ew, eh = ch.eye_u, ch.eye_v, ch.eye_w, ch.eye_h
    E, H = pal['eye'], pal['eye_hi']
    mouth = pal['mouth']
    mv = ch.mouth_v
    lw = max(0.42, ew * 0.24)   # line weight for closed eyes / mouth strokes
    r = ew * 0.26

    def cheeks(alpha=1.0, w=1.0):
        for s in (-1, 1):
            cv.paint(cv.m_rect(s * ch.cheek_u, ch.cheek_v, ch.cheek_w * w, ch.cheek_h, 0.25),
                     pal['cheek'], alpha, lit=0.5)

    def eyes(h=eh, dv=0.0, hl=(-0.25, 0.32), w=ew):
        for s in (-1, 1):
            cu = s * eu
            cv.paint(cv.m_rect(cu, ev + dv, w, h, r), E, lit=0.0)
            hw = w * 0.38
            cv.paint(cv.m_rect(cu + hl[0] * w, ev + dv + h / 2 - h * hl[1] + 0.05, hw, hw * 1.1, hw * 0.2),
                     H, lit=0.0)

    def smile(width=1.3, depth=0.55):
        cv.paint(cv.m_arc(0, mv + depth, width / 2, depth, 200, 340, lw * 0.85), mouth, lit=0.0)

    def open_mouth(w=2.4, h=1.9, tongue=True, dv=0.0):
        c0 = mv - 0.2 + dv
        # D shape: flat top, round bottom
        m = cv.m_ellipse(0, c0, w / 2, h) & (cv.V <= c0)
        cv.paint(m, pal['mouth_in'], lit=0.0)
        if tongue:
            t = cv.m_ellipse(0, c0 - h * 0.78, w * 0.3, h * 0.42) & m
            cv.paint(t, pal['tongue'], lit=0.0)

    def teeth(w, h, dv=0.0):
        # a gritted row of teeth (the cinematics)
        c0 = mv - 0.3 + dv
        cv.paint(cv.m_rect(0, c0, w + lw * 0.9, h + lw * 0.9, h * 0.48), pal['mouth_in'], lit=0.0)
        cv.paint(cv.m_rect(0, c0, w, h, h * 0.42), '#FFFDF6', lit=0.0)
        cv.paint(cv.m_stroke([(-w / 2, c0), (w / 2, c0)], lw * 0.42), pal['mouth_in'], lit=0.0)
        for x in (-w * 0.24, w * 0.24):
            cv.paint(cv.m_stroke([(x, c0 - h / 2), (x, c0 + h / 2)], lw * 0.38), pal['mouth_in'], lit=0.0)

    def sweat():
        su = eu + ew * 1.6
        cv.paint(cv.m_ellipse(su, ev + eh * 0.25, 0.55, 0.7) | cv.m_poly(
            [(su - 0.48, ev + eh * 0.32), (su + 0.48, ev + eh * 0.32), (su, ev + eh * 0.32 + 1.2)]),
                 pal['sweat'], lit=0.0)

    def brows(lift=1.0, inner=0.64, weight=1.25):
        # pinched toward the middle: cross, set
        for s in (-1, 1):
            cu = s * eu
            cv.paint(cv.m_stroke([(cu + s * ew * 0.95, ev + eh * lift), (cu - s * ew * 0.62, ev + eh * inner)], lw * weight),
                     E, lit=0.0)

    if expr == 'default':
        cheeks(); eyes(); smile()
    elif expr == 'blink':
        cheeks()
        for s in (-1, 1):
            cv.paint(cv.m_arc(s * eu, ev - eh * 0.1, ew * 0.7, 0.7, 200, 340, lw), E, lit=0.0)
        smile()
    elif expr == 'happy':
        cheeks(w=1.1)
        for s in (-1, 1):
            cv.paint(cv.m_arc(s * eu, ev - eh * 0.25, ew * 0.85, eh * 0.38, 15, 165, lw * 1.25), E, lit=0.0)
        open_mouth(2.6, 1.9)
    elif expr == 'curious':
        cheeks()
        eyes(hl=(0.12, 0.30))
        cv.paint(cv.m_ellipse(0.6, mv - 0.15, 0.55, 0.5), pal['mouth_in'], lit=0.0)
    elif expr == 'surprised':
        cheeks()
        eyes(h=eh * 1.08)
        cv.paint(cv.m_ellipse(0, mv - 0.45, 0.85, 1.0), pal['mouth_in'], lit=0.0)
    elif expr == 'determined':
        cheeks(0.85)
        for s in (-1, 1):
            cu = s * eu
            m = cv.m_rect(cu, ev - 0.3, ew, eh * 0.78, r)
            # angled lid: cut the inner-top corner
            inner = -s
            cut = (cv.V - (ev - 0.3 + eh * 0.39)) > -((cv.U - cu) * inner + ew / 2) * 0.9
            cv.paint(m & ~cut, E, lit=0.0)
            cv.paint(cv.m_stroke([(cu - s * ew * 1.0, ev + eh * 0.62), (cu + s * ew * 0.75, ev + eh * 0.32)],
                                 lw * 1.15), E, lit=0.0)
            hw = ew * 0.36
            cv.paint(cv.m_rect(cu - 0.2 * ew, ev - 0.3 + eh * 0.12, hw, hw, 0.1), H, lit=0.0)
        cv.paint(cv.m_stroke([(-0.7, mv - 0.1), (0.7, mv - 0.1)], lw * 0.85), mouth, lit=0.0)
    elif expr == 'sad':
        cheeks(0.7)
        for s in (-1, 1):
            cu = s * eu
            m = cv.m_rect(cu, ev - 0.4, ew, eh * 0.7, r)
            outer = s
            cut = (cv.V - (ev - 0.4 + eh * 0.35)) > -((cv.U - cu) * outer + ew / 2) * 0.8
            cv.paint(m & ~cut, E, lit=0.0)
            cv.paint(cv.m_stroke([(cu + s * ew * 0.9, ev + eh * 0.42), (cu - s * ew * 0.6, ev + eh * 0.66)],
                                 lw), E, lit=0.0)
            hw = ew * 0.34
            cv.paint(cv.m_rect(cu - 0.2 * ew, ev - 0.4 + eh * 0.05, hw, hw, 0.1), H, lit=0.0)
        cv.paint(cv.m_arc(0, mv - 0.75, 0.7, 0.5, 25, 155, lw * 0.85), mouth, lit=0.0)
    elif expr == 'sleepy':
        cheeks(0.9)
        for s in (-1, 1):
            cv.paint(cv.m_arc(s * eu, ev - eh * 0.05, ew * 0.75, 0.75, 195, 345, lw), E, lit=0.0)
        cv.paint(cv.m_ellipse(0.5, mv - 0.2, 0.45, 0.4), pal['mouth_in'], lit=0.0)
    elif expr == 'excited':
        cheeks(w=1.1)
        for s in (-1, 1):
            cu = s * eu
            a = 0.95 * ew
            pts = [(cu - s * a, ev + eh * 0.32), (cu + s * a * 0.6, ev - eh * 0.05),
                   (cu - s * a, ev - eh * 0.42)]
            cv.paint(cv.m_stroke(pts, lw * 1.25), E, lit=0.0)
        open_mouth(3.0, 2.3)
    elif expr == 'neutral':
        cheeks(0.6)
        eyes(h=eh * 0.82, dv=-0.3)
        cv.paint(cv.m_stroke([(-0.6, mv), (0.6, mv)], lw * 0.8), mouth, lit=0.0)
    elif expr == 'sick':
        cheeks(0.35)
        for s in (-1, 1):
            cu = s * eu
            # half-closed droopy eyes
            m = cv.m_rect(cu, ev - eh * 0.28, ew, eh * 0.42, r * 0.8)
            cv.paint(m, E, lit=0.0)
            cv.paint(cv.m_stroke([(cu - ew * 0.75, ev - eh * 0.02), (cu + ew * 0.75, ev - eh * 0.02)], lw),
                     E, lit=0.0)
        # wavy mouth
        xs = np.linspace(-0.95, 0.95, 7)
        ys = mv - 0.2 + 0.22 * np.array([0, 1, 0, -1, 0, 1, 0])
        cv.paint(cv.m_stroke(list(zip(xs, ys)), lw * 0.8), mouth, lit=0.0)
        # sweat drop on the side of the head
        su = eu + ew * 1.6
        cv.paint(cv.m_ellipse(su, ev + eh * 0.25, 0.55, 0.7) | cv.m_poly(
            [(su - 0.48, ev + eh * 0.32), (su + 0.48, ev + eh * 0.32), (su, ev + eh * 0.32 + 1.2)]),
                 pal['sweat'], lit=0.0)
    elif expr == 'memorial':
        for s in (-1, 1):
            cv.paint(cv.m_arc(s * eu, ev - eh * 0.05, ew * 0.75, 0.6, 195, 345, lw), E, lit=0.0)
        smile(1.0, 0.4)
    # ---- the cinematics only (the Wilds' boss entrance; not in the sprite sheets): the Expression Style Kit's
    # faces (face_kit.py), 'shout' / 'strain' / 'fierce', or with a personality, 'fierce:calm'
    elif expr.split(':')[0] in ('shout', 'strain', 'fierce'):
        from face_kit import paint_kit, parse
        paint_kit(ch, cv, pal, *parse(expr))
    # ---- villager-only expressions (Village Tales NPCs; Evochi sprites never use these)
    elif expr == 'worried':
        cheeks(0.6)
        eyes(h=eh * 0.9, dv=-0.2)
        for s in (-1, 1):
            cu = s * eu
            cv.paint(cv.m_stroke([(cu - s * ew * 0.9, ev + eh * 0.62), (cu + s * ew * 0.7, ev + eh * 0.86)], lw * 1.1),
                     pal.get('brow', E), lit=0.0)
        xs = np.linspace(-0.8, 0.8, 5)
        ys = mv - 0.1 + 0.18 * np.array([0, 1, 0, 1, 0])
        cv.paint(cv.m_stroke(list(zip(xs, ys)), lw * 0.8), mouth, lit=0.0)
    elif expr == 'thinking':
        cheeks(0.8)
        eyes(h=eh * 0.86, hl=(0.18, 0.18))
        cu = -eu
        cv.paint(cv.m_stroke([(cu - ew * 0.7, ev + eh * 0.66), (cu + ew * 0.7, ev + eh * 0.78)], lw), pal.get('brow', E), lit=0.0)
        cv.paint(cv.m_stroke([(0.1, mv), (0.9, mv + 0.25)], lw * 0.85), mouth, lit=0.0)
    elif expr == 'proud':
        cheeks(w=1.1)
        for s in (-1, 1):
            cv.paint(cv.m_arc(s * eu, ev - eh * 0.2, ew * 0.8, eh * 0.32, 15, 165, lw * 1.2), E, lit=0.0)
        smile(1.9, 0.75)
    else:
        raise ValueError(expr)
    if getattr(ch, 'no_mouth', False):
        # beaked villagers (Pip): the beak is the mouth, so no painted mouth below it
        gone = (np.abs(cv.U) < 2.8) & (cv.V < mv + 1.4) & (cv.V > mv - 3.2)
        cv.a[gone] = 0.0
    extra = getattr(ch, 'face_extra', None)
    if extra:
        extra(cv, pal, expr)


# ----------------------------------------------------------------------------
# shape utilities for the larger forms
# ----------------------------------------------------------------------------
def tube(M: Model, pts, radii, p=2.2, squash=(1.0, 1.0)):
    """Union of super-ellipsoids along a polyline (radius interpolated)."""
    pts = np.asarray(pts, float)
    radii = np.asarray(radii, float)
    mask = np.zeros(M.m.shape, bool)
    seglen = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    total = seglen.sum()
    n = max(2, int(total * M.res * 1.5))
    cum = np.concatenate([[0], np.cumsum(seglen)])
    for t in np.linspace(0, total, n):
        i = min(np.searchsorted(cum, t, side='right') - 1, len(seglen) - 1)
        f = (t - cum[i]) / max(seglen[i], 1e-9)
        c = pts[i] * (1 - f) + pts[i + 1] * f
        r = radii[i] * (1 - f) + radii[i + 1] * f
        rx, ry = r * squash[0], r * squash[1]
        lo = np.floor((c - max(rx, ry, r) - 1) * M.res - M.lo).astype(int)
        hi = np.ceil((c + max(rx, ry, r) + 1) * M.res - M.lo).astype(int)
        lo = np.maximum(lo, 0)
        hi = np.minimum(hi, M.m.shape)
        sl = tuple(slice(a, b) for a, b in zip(lo, hi))
        X, Y, Z = M.X[sl], M.Y[sl], M.Z[sl]
        mask[sl] |= (np.abs((X - c[0]) / rx) ** p + np.abs((Y - c[1]) / ry) ** p
                     + np.abs((Z - c[2]) / r) ** p) <= 1
    return mask


def spike(M: Model, base, direction, length, r0, r1=0.25, square=True, twist=0.0):
    """Tapered crystal spike from base along direction (square cross-section = faceted)."""
    base = np.asarray(base, float)
    d = np.asarray(direction, float)
    d /= np.linalg.norm(d)
    P = np.stack([M.X - base[0], M.Y - base[1], M.Z - base[2]], -1)
    t = P @ d
    radial = P - t[..., None] * d
    u, v, _ = local_frame(d, up=(0, 0, 1) if abs(d[1]) > 0.9 else (0, 1, 0))
    if twist:
        ca, sa = math.cos(twist), math.sin(twist)
        u, v = u * ca + v * sa, -u * sa + v * ca
    ru = np.abs(radial @ u)
    rv = np.abs(radial @ v)
    f = np.clip(t / length, 0, 1)
    rad = r0 * (1 - f) + r1 * f
    if square:
        inside = (np.maximum(ru, rv) <= rad)
    else:
        inside = np.sqrt(ru ** 2 + rv ** 2) <= rad
    return inside & (t >= -0.3) & (t <= length)


def fluff(M: Model, center, size, rng, n=7, spread=None):
    """Cluster of jittered small boxes - the juvenile's fluffy scale tufts."""
    center = np.asarray(center, float)
    spread = spread if spread is not None else size * 0.6
    mask = np.zeros(M.m.shape, bool)
    for _ in range(n):
        c = center + rng.uniform(-1, 1, 3) * spread
        s = size * rng.uniform(0.45, 0.8)
        mask |= M.box(c - s / 2, c + s / 2)
    return mask


# ----------------------------------------------------------------------------
# Stage 2: Juvenile
# ----------------------------------------------------------------------------
class HeadView:
    """the voxel grid seen from the head: each voxel's position in the head's rest pose (the head turned by R about
    pivot, then moved by t, undone), so a head part built in rest coordinates lands turned and moved with it"""

    def __init__(self, M, pivot, R, t):
        P = np.stack([M.X, M.Y, M.Z], -1) - (np.asarray(pivot, float) + np.asarray(t, float))
        L = P @ np.asarray(R, float) + np.asarray(pivot, float)       # R^T (p - pivot - t) + pivot
        self.X, self.Y, self.Z = L[..., 0], L[..., 1], L[..., 2]
        self.m = M.m
        self.res, self.lo = M.res, M.lo

    def box(self, lo, hi):
        return ((self.X >= lo[0]) & (self.X < hi[0]) & (self.Y >= lo[1]) & (self.Y < hi[1])
                & (self.Z >= lo[2]) & (self.Z < hi[2]))


def head_rotation(rot):
    """(pitch, yaw, roll) in degrees -> R: pitch lifts the face (+z) up, yaw turns it toward +x, roll tips +y
    toward +x"""
    p, y, r = (math.radians(v) for v in (rot or (0.0, 0.0, 0.0)))
    Rx = np.array([[1, 0, 0], [0, math.cos(p), math.sin(p)], [0, -math.sin(p), math.cos(p)]])
    Ry = np.array([[math.cos(y), 0, math.sin(y)], [0, 1, 0], [-math.sin(y), 0, math.cos(y)]])
    Rz = np.array([[math.cos(r), math.sin(r), 0], [-math.sin(r), math.cos(r), 0], [0, 0, 1]])
    return Ry @ Rx @ Rz


def _lerp_z(z, z_front, z_back, a_front, a_back):
    """a body offset along the torso: a_front at z_front, a_back at z_back, held beyond"""
    f = np.clip((np.asarray(z, float) - z_back) / (z_front - z_back), 0, 1)
    return a_back + (a_front - a_back) * f


def build_juvenile(res=2, feet=None, lo_y=-1, head=None, tail=0.0, head_rot=None, body=None, tail_lift=0.0,
                   jaw=0.0) -> Character:
    """feet: {(side, front): (dy, dz) or (dy, dz, dx)}, as for the Eggling (walk.py); dx spreads the foot outward.
    head: (dx, dy, dz) moves the head (and what sits on it) from rest, a nod in the walk. head_rot: (pitch, yaw,
    roll) degrees turns it rigidly about the neck (face, crest and jaw with it). body: (dy_front, dy_back) lowers
    the torso (a crouch; more at the front drops the shoulders): the head rides on it, the legs take it, the back
    ridge and markings move with it. tail: how far the tail's tip swings sideways; tail_lift: how far it rises.
    jaw: degrees the mouth opens (jaw.py: the lower head swings down about a hinge)."""
    feet = feet or {}
    bf, bb = body or (0.0, 0.0)
    hd = np.array(head or (0.0, 0.0, 0.0), float) + np.array([0.0, bf, 0.0])
    rotated = bool(head_rot) and any(abs(v) > 1e-9 for v in head_rot)
    R = head_rotation(head_rot)
    PIVOT = np.array([0.0, 12.0, 3.0])                                  # the neck joint, at rest
    Hw = lambda p: tuple(PIVOT + R @ (np.array(p, float) - PIVOT) + hd)  # noqa: E731  a head point, in the world
    B = lambda p: (p[0], p[1] + float(_lerp_z(p[2], 2.0, -9.5, bf, bb)), p[2])  # noqa: E731  a point on the torso
    T = lambda p, f: (p[0] + tail * f ** 1.6, p[1] + bb + tail_lift * f ** 1.4, p[2])  # noqa: E731  along the tail
    rng = np.random.default_rng(22)
    M = Model((-17, lo_y, -32), (17, 36, 28), MATS, res=res)
    # head parts: in the head's rest coordinates, seen through its turn and move (with no turn, the world, as before)
    if rotated:
        HL, HC = HeadView(M, PIVOT, R, hd), (lambda p: tuple(np.array(p, float)))
    else:
        HL, HC = M, (lambda p: tuple(np.array(p, float) + hd))
    head = egg_mask(HL, HC((0, 17.4, 7.0)), 11.4, 10.0, 9.8, 9.6, p=2.9)
    body_m = tube(M, [B((0, 9.4, 2.0)), B((0, 9.0, -5.0)), B((0, 9.2, -9.5))], [8.2, 8.0, 6.8], p=2.5,
                  squash=(1.0, 0.84))
    tpath = [T(p, f) for p, f in zip([(0, 9.2, -10.5), (0, 10.0, -15.5), (0, 12.3, -19.5), (0, 15.6, -22.0), (0, 19.0, -23.0)],
                                     (0.0, 0.3, 0.6, 0.85, 1.0))]
    tail_m = tube(M, tpath, [6.0, 5.0, 4.3, 3.8, 3.4], p=2.4)
    core = head | body_m | tail_m
    M.set(core, 'shell')
    dyz = _lerp_z(M.Z, 2.0, -9.5, bf, bb) if (bf or bb) else 0.0
    belly = core & (M.Y - dyz < 7.5) & (M.Z > -12) & ~head
    belly |= head & (HL.Y < HC((0, 11.5, 0))[1]) & (HL.Z > HC((0, 0, 11))[2])
    M.set(belly, 'belly')

    for s in (-1, 1):
        for z in (1.6, -7.6):
            f = feet.get((s, z > 0), (0.0, 0.0))
            dy, dz = f[0], f[1]
            dx = s * f[2] if len(f) > 2 else 0.0
            z += dz
            x0, x1 = (3.4 + dx, 9.8 + dx) if s > 0 else (-9.8 + dx, -3.4 + dx)
            box = M.box((x0, dy, z - 2.8), (x1, 4.2 + max(0.0, -dy), z + 2.8))
            box &= ~((M.Y > 3.2 + dy) & (M.Z > z + 1.8))
            leg = box & ~(core & (M.Y >= 4.2 + max(0.0, dy)))
            M.set(leg, 'feet')
            M.set(leg & (M.Y < 1.1 + dy), 'feet_shade')
            for cx in np.linspace(x0 + 1.2, x1 - 1.2, 3):
                M.set(M.box((cx - 0.55, dy, z + 2.6), (cx + 0.55, 1.2 + dy, z + 3.6)), 'claw')

    shl = shell_region(M, core, res)
    crest = np.zeros(M.m.shape, bool)
    path = [(0, 26.8, 10.5), (0, 28.4, 6.5), (0, 28.0, 2.5), (0, 26.0, -1.0), (0, 22.5, -3.2)]
    sizes = [5.0, 6.2, 5.6, 4.8, 4.0]
    for (p, s) in zip(path, sizes):
        crest |= fluff(HL, HC(p), s, rng, n=8, spread=(s * 0.55, s * 0.35, s * 0.4))
    crest |= HL.box(HC((-2.5, 25.0, 7.5)), HC((2.5, 31.5, 12.0)))
    crest |= HL.box(HC((-4.5, 24.5, 8.5)), HC((0.0, 29.5, 13.0)))
    crest &= ~core & (HL.Y > HC((0, 23.0, 0))[1])
    M.set(crest, 'crest.0')
    for s in (-1, 1):
        t = fluff(HL, HC((s * 11.0, 17.5, 2.5)), 3.4, rng, n=6, spread=(0.8, 2.0, 1.6)) & ~core
        M.set(t, 'crest.1')
        t = fluff(HL, HC((s * 9.6, 23.0, 0.5)), 3.0, rng, n=5, spread=(0.8, 1.2, 1.4)) & ~core & (M.m == 0)
        M.set(t, 'crest.2')
    ridge = [(0, 16.0, -2.5, 4.2), (0, 15.6, -6.5, 4.4), (0, 15.2, -10.5, 4.0),
             (0, 15.0, -14.5, 3.6), (0, 16.5, -18.5, 3.2), (0, 19.0, -21.0, 3.0)]
    for i, (x, y, z, s) in enumerate(ridge):
        f = max(0.0, (-10.5 - z) / 12.5)  # along the tail, the ridge swings with it
        p = T((x, y - bb, z), f) if f > 0 else B((x, y, z))
        t = fluff(M, p, s, rng, n=6, spread=(s * 0.5, s * 0.3, s * 0.4)) & ~core & (M.m == 0)
        M.set(t, 'crest.%d' % (3 + i % 3))
    for s in (-1, 1):
        for (y, z, sz) in ((10.5, -0.5, 5.0), (11.0, -7.0, 4.2), (11.5, -13.5, 3.4)):
            f = max(0.0, (-10.5 - z) / 12.5)
            p = T((s * 8.2, y - bb, z), f) if f > 0 else B((s * 8.2, y, z))
            t = fluff(M, p, sz, rng, n=7, spread=(0.7, sz * 0.45, sz * 0.5))
            t &= ~core & (M.m == 0)
            M.set(t, 'crest.%d' % (6 + int(-z) % 2))
        for (y, z) in ((6.8, -3.5), (6.5, -10.0), (13.0, -4.0), (9.0, -16.0)):
            f = max(0.0, (-10.5 - z) / 12.5)
            p = T((s * 7.6, y - bb, z), f) if f > 0 else B((s * 7.6, y, z))
            stamp(M, shl, p, (s, 0.2, 0), square_shape(2.2, 1.8), 'pattern')
    tip = fluff(M, T((0, 20.5 - bb, -23.5), 1.0), 5.4, rng, n=10, spread=(1.8, 2.2, 1.8)) & (M.m == 0)
    M.set(tip, 'crest.8')
    tip2 = fluff(M, T((0, 15.5 - bb, -24.0), 1.0), 3.6, rng, n=6, spread=(1.2, 1.6, 1.0)) & (M.m == 0)
    M.set(tip2, 'crest.6')

    two_tone(M, seed=21, thresh=0.35)
    face = Frame(center=Hw((0, 17.0, 7.0)), n=tuple(R @ np.array([0.0, 0.0, 1.0])),
                 up=tuple(R @ np.array([0.0, 1.0, 0.0])), reach=20)
    ch = Character(stage=2, model=M, face=face,
                   eye_u=5.4, eye_v=0.9, eye_w=2.2, eye_h=5.0,
                   cheek_u=7.4, cheek_v=-2.5, cheek_w=2.4, cheek_h=2.0,
                   mouth_v=-3.3, face_extent=(-11, 11, -8, 8), scale_ref=44.0)
    ch.anchors = {
        'head_top': Hw((0, 29.5, 7.0)), 'neck': B((0, 9.0, 9.0)), 'back': B((0, 15.5, -5.0)),
        'ground': (0, 0, -3.0), 'face': Hw((0, 17.0, 16.6)), 'tail': T((0, 20.5 - bb, -23.0), 1.0),
    }
    # what the jaw needs (jaw.py): the head's volume, what it is fused with, and its turn
    ch.rig = dict(head=head, fused=body_m | tail_m, pivot=PIVOT, R=R, t=hd)
    if jaw:
        from jaw import open_jaw
        ch = open_jaw(ch, jaw)
    return ch


# ----------------------------------------------------------------------------
# Stage 3: Elder
# ----------------------------------------------------------------------------
def build_elder(res=2, feet=None, lo_y=-1, head=None, tail=0.0, head_rot=None, body=None, tail_lift=0.0,
                jaw=0.0) -> Character:
    """feet: {(side, front): (dy, dz) or (dy, dz, dx)}: the foot moves, the leg bends to follow (walk.py); dx spreads
    it outward. head: (dx, dy, dz) moves the head, snout and mane from rest (the neck follows), a nod in the walk.
    head_rot: (pitch, yaw, roll) degrees turns them rigidly about the top of the neck (face and jaw with them).
    body: (dy_front, dy_back) lowers the torso (front: the shoulders): the neck, legs, mane plumes, dorsal spikes
    and markings move with it. tail: how far the tail's curl swings sideways; tail_lift: how far it rises.
    jaw: degrees the mouth opens (jaw.py)."""
    feet = feet or {}
    bf, bb = body or (0.0, 0.0)
    hd = np.array(head or (0.0, 0.0, 0.0), float) + np.array([0.0, bf, 0.0])
    rotated = bool(head_rot) and any(abs(v) > 1e-9 for v in head_rot)
    R = head_rotation(head_rot)
    PIVOT = np.array([0.0, 15.0, 10.0])                                 # where the head meets the neck, at rest
    Hw = lambda p: tuple(PIVOT + R @ (np.array(p, float) - PIVOT) + hd)  # noqa: E731  a head point, in the world
    rng = np.random.default_rng(33)
    M = Model((-22, lo_y, -48), (22, 46, 34), MATS, res=res)
    if rotated:
        HL, HC = HeadView(M, PIVOT, R, hd), (lambda p: tuple(np.array(p, float)))
    else:
        HL, HC = M, (lambda p: tuple(np.array(p, float) + hd))
    B = lambda p: (p[0], p[1] + float(_lerp_z(p[2], 5.0, -19.0, bf, bb)), p[2])  # noqa: E731  a point on the torso
    head = egg_mask(HL, HC((0, 17.0, 16.0)), 9.8, 8.4, 7.6, 10.2, p=2.7)
    snout = egg_mask(HL, HC((0, 15.0, 23.0)), 7.4, 5.4, 5.0, 5.8, p=2.6)
    neck = tube(M, [Hw((0, 15.0, 10.0)), B((0, 12.5, 5.0))], [7.6, 8.2], p=2.4)
    body_m = tube(M, [B((0, 11.8, 5.0)), B((0, 11.6, -4.0)), B((0, 11.4, -13.0)), B((0, 11.0, -19.0))],
                  [9.0, 9.6, 9.2, 7.6], p=2.5, squash=(1.05, 0.88))
    tpath = [(0, 10.5, -20.0), (0, 9.6, -26.5), (0, 10.4, -32.5), (0, 13.6, -37.5), (0, 18.6, -40.0),
             (0, 23.6, -39.2), (0, 26.8, -36.2), (0, 27.4, -32.6), (0, 25.6, -30.2)]
    # the swing: nothing at the root, all of it from the curl on; the lift likewise; the root rides on the back
    tpath = [(tail * min(1.0, i / 4.0) ** 1.5, y + bb + tail_lift * min(1.0, i / 4.0) ** 1.5, z)
             for i, (_, y, z) in enumerate(tpath)]
    trad = [6.8, 6.0, 5.4, 4.9, 4.5, 4.1, 3.7, 3.2, 2.8]
    tail_m = tube(M, tpath, trad, p=2.3)
    core = head | snout | neck | body_m | tail_m
    M.set(core, 'shell')
    dyz = _lerp_z(M.Z, 5.0, -19.0, bf, bb) if (bf or bb) else 0.0
    belly = core & (M.Y - dyz < 9.0) & (M.Z > -19)
    belly |= (head | snout) & (HL.Y < HC((0, 12.2, 0))[1]) & (HL.Z > HC((0, 0, 14))[2])
    M.set(belly, 'belly')

    for s in (-1, 1):
        for z in (7.0, -12.5):
            f = feet.get((s, z > 0), (0.0, 0.0))
            dy, dz = f[0], f[1]
            dx = s * f[2] if len(f) > 2 else 0.0
            hip = B((s * 6.0, 9.5, z))
            leg = tube(M, [hip, (s * 9.4 + dx * 0.6, 5.2 + dy * 0.6 + (hip[1] - 9.5) * 0.5, z + 0.5 + dz * 0.6),
                           (s * 10.6 + dx, 2.6 + dy, z + 1.0 + dz)], [4.4, 3.9, 3.6], p=2.6) & ~core
            M.set(leg, 'shell')
            zf = z + dz
            fx = s * 10.6 + dx
            foot = M.box((fx - 4.2, dy, zf - 3.2), (fx + 4.2, 3.8 + dy, zf + 5.4))
            foot &= ~((M.Y > 2.6 + dy) & (M.Z > zf + 3.8))
            M.set(foot, 'feet')
            M.set(foot & (M.Y < 1.1 + dy), 'feet_shade')
            for cx in np.linspace(fx - 2.8, fx + 2.8, 3):
                M.set(M.box((cx - 0.7, dy, zf + 5.0), (cx + 0.7, 1.5 + dy, zf + 6.8)), 'claw')
            pl = fluff(M, B((s * 10.0, 10.0, z)), 5.4, rng, n=8, spread=(1.0, 2.0, 2.2)) & (M.m == 0)
            M.set(pl, 'crest.7')
            pl = fluff(M, (s * 10.4 + dx * 0.6, 5.5 + dy * 0.6 + (hip[1] - 9.5) * 0.5, z + 1.0 + dz * 0.6), 3.6, rng, n=5,
                       spread=(0.8, 1.2, 1.6)) & (M.m == 0)
            M.set(pl, 'crest.8')

    # crystalline mane: big angular spikes radiating up and back from the head
    spikes = [
        ((0, 22.5, 17.5), (0, 0.92, -0.25), 13.5, 4.0),
        ((-4.0, 22.0, 14.0), (-0.3, 0.85, -0.45), 14.5, 4.0),
        ((4.0, 22.0, 14.0), (0.3, 0.85, -0.45), 14.5, 4.0),
        ((0, 21.5, 10.5), (0, 0.75, -0.65), 12.5, 3.8),
        ((-7.5, 19.5, 11.5), (-0.7, 0.6, -0.4), 11.0, 3.5),
        ((7.5, 19.5, 11.5), (0.7, 0.6, -0.4), 11.0, 3.5),
        ((-5.5, 20.0, 7.0), (-0.45, 0.65, -0.6), 10.0, 3.4),
        ((5.5, 20.0, 7.0), (0.45, 0.65, -0.6), 10.0, 3.4),
        ((-9.0, 15.0, 12.5), (-0.95, 0.25, -0.2), 7.5, 3.0),
        ((9.0, 15.0, 12.5), (0.95, 0.25, -0.2), 7.5, 3.0),
        ((-8.5, 11.5, 13.0), (-0.9, -0.25, -0.2), 5.6, 2.6),
        ((8.5, 11.5, 13.0), (0.9, -0.25, -0.2), 5.6, 2.6),
        ((-8.5, 16.5, 6.0), (-0.85, 0.4, -0.35), 7.0, 3.0),
        ((8.5, 16.5, 6.0), (0.85, 0.4, -0.35), 7.0, 3.0),
    ]
    for i, (bpt, d, L, r) in enumerate(spikes):
        bpt = HC(bpt)
        sp = spike(HL, bpt, d, L, r, 0.45, twist=0.35 * (i % 3)) & (M.m == 0)
        M.set(sp, 'crest.%d' % (i % 6))
        tip = spike(HL, np.array(bpt) + np.array(d) / np.linalg.norm(d) * L * 0.55, d, L * 0.45,
                    r * 0.48, 0.45, twist=0.35 * (i % 3)) & sp
        M.set(tip, 'crest_mid.%d' % (i % 6))
    # mane base fluff to hide spike roots
    for s in (-1, 0, 1):
        f = fluff(HL, HC((s * 6.0, 20.0, 11.0)), 5.0, rng, n=8, spread=(1.6, 1.2, 2.0)) & (M.m == 0)
        M.set(f, 'crest.%d' % (s + 2))
    dorsal = [((0, 18.5, 1.0), 7.5, 3.2), ((0, 18.5, -5.5), 8.0, 3.4), ((0, 18.5, -12.0), 7.4, 3.2),
              ((0, 17.0, -18.0), 6.4, 2.8), ((0, 15.0, -24.0), 5.4, 2.4), ((0, 14.0, -29.5), 4.6, 2.0)]
    for i, (bpt, L, r) in enumerate(dorsal):
        if bpt[2] < -20:  # on the tail: swings with it
            f = min(1.0, (-20 - bpt[2]) / 26.0) ** 1.5
            bpt = (tail * f, bpt[1] + bb + tail_lift * f, bpt[2])
        else:
            bpt = B(bpt)
        sp = spike(M, bpt, (0, 0.85, -0.5), L, r, 0.35, twist=0.6) & (M.m == 0)
        M.set(sp, 'crest.%d' % (i % 6))
    shl = shell_region(M, core, res)
    for s in (-1, 1):
        for (y, z, w, h) in ((12.0, 0.0, 4.6, 3.4), (15.0, -7.0, 5.0, 3.2), (9.0, -8.5, 3.8, 3.0),
                             (13.5, -15.5, 4.0, 3.0), (9.5, -21.0, 3.4, 2.6), (8.5, -28.5, 3.0, 2.6),
                             (9.0, 15.0, 2.6, 2.0)):
            stamp(M, shl, B((s * 8.6, y, z)), (s, 0.25, 0), square_shape(w, h), 'pattern')
        pl = fluff(M, B((s * 8.4, 15.5, -3.0)), 4.6, rng, n=7, spread=(0.8, 1.6, 2.4)) & (M.m == 0)
        M.set(pl, 'crest.8')
        pl = fluff(M, B((s * 8.0, 14.5, -14.0)), 4.0, rng, n=6, spread=(0.8, 1.4, 2.0)) & (M.m == 0)
        M.set(pl, 'crest.7')
    # gold plates covering the outside of the tail curl
    for i in range(1, len(tpath)):
        p = np.array(tpath[i], float)
        prev = np.array(tpath[i - 1], float)
        d = p - prev
        d /= np.linalg.norm(d)
        out = np.cross(d, np.array([1.0, 0, 0]))
        if out[1] < 0 and i < 4:
            out = -out
        cen = np.array([tail, 25.0 + bb + tail_lift, -34.5])
        if i >= 4:
            out = p - cen
            out[0] = 0
            out /= max(np.linalg.norm(out), 1e-6)
        for side in (-1, 1):
            c2 = p + out * trad[i] * 0.75 + np.array([side * trad[i] * 0.55, 0, 0])
            pl = fluff(M, c2, trad[i] * 1.15, rng, n=5, spread=trad[i] * 0.35) & (M.m == 0)
            M.set(pl, 'crest.%d' % ((i + side) % 6))

    two_tone(M, seed=31, thresh=0.55)
    face = Frame(center=Hw((0, 16.2, 17.0)), n=tuple(R @ np.array([0.0, 0.05, 1.0])),
                 up=tuple(R @ np.array([0.0, 1.0, 0.0])), reach=22)
    ch = Character(stage=3, model=M, face=face,
                   eye_u=5.3, eye_v=1.6, eye_w=2.2, eye_h=4.3,
                   cheek_u=6.6, cheek_v=-1.6, cheek_w=2.1, cheek_h=1.7,
                   mouth_v=-3.2, face_extent=(-11, 11, -7, 7), scale_ref=58.0)
    ch.anchors = {
        'head_top': Hw((0, 25.0, 16.0)), 'neck': B((0, 10.5, 10.5)), 'back': B((0, 19.0, -5.0)),
        'ground': (0, 0, -5.0), 'face': Hw((0, 15.0, 28.8)), 'tail': (tail, 27.0 + bb + tail_lift, -34.0),
    }
    ch.rig = dict(head=head | snout, fused=neck | body_m | tail_m, pivot=PIVOT, R=R, t=hd)
    if jaw:
        from jaw import open_jaw
        ch = open_jaw(ch, jaw)
    return ch


def two_tone(M: Model, seed=5, scale=1.6, thresh=0.25, light_mat='pattern', spike_tips=None):
    """Break up large gold masses with lighter scale highlights (soft noise pattern)."""
    rng = np.random.default_rng(seed)
    noise = ndimage.gaussian_filter(rng.standard_normal(M.m.shape).astype(np.float32), scale * M.res)
    noise /= noise.std() + 1e-6
    crest_ids = [i for i, n in enumerate(M.mats) if n.startswith('crest.')]
    cm = np.isin(M.m, crest_ids)
    # favour upward / outward facing voxels so highlights read as lit plates
    up = np.zeros_like(cm)
    up[:, :-1, :] = cm[:, :-1, :] & ~cm[:, 1:, :] & (M.m[:, 1:, :] == 0)
    sel = cm & ((noise > thresh) | (up & (noise > -0.4)))
    keep = M.m.copy()
    for cid in crest_ids:
        name = M.mats[cid]
        nm = 'crest_mid.' + name.split('.')[1]
        M.set(sel & (keep == cid), nm)
    return sel


def build(stage: int, res=2, **kw) -> Character:
    return {1: build_eggling, 2: build_juvenile, 3: build_elder}[stage](res, **kw)

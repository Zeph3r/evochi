"""The cinematic faces (the Wilds' boss entrance), drawn to the "Evochi Combat Expressions (Improved)" sheet:

  shout   tall black eyes cut by thick angry brows (\\ /), a big open mouth: dark inside, two little white fangs
          up top (the Elder's roar adds two below), a pink tongue
  strain  squeezed shut in thick chevrons (> <), gritted teeth (white, a red outline, a crooked row), a bead of sweat
  fierce  the eyes narrowed under the brows, a white glint, a small frown

Each stage acts its own way (the brief): the Eggling the most exaggerated (the biggest war cry, a stubborn little
pout with puffed cheeks), the Juvenile the most energetic, the Elder the most controlled (a commanding roar, one
eye almost open against the blast, calm level brows when it stands its ground). The rosy cheeks stay in all.

Every expression has three takes (expr.0, expr, expr.2) for the close-ups and the cinematic's transitions:
  shout.0   the mouth opening          shout     the yell          shout.2   all out
  strain.0  bracing, mouth shut        strain    teeth gritted     strain.2  the Eggling and Juvenile crooked and
                                                                             sweating; the Elder peeking, eye opening
  fierce.0  eyes narrowing             fierce    set               fierce.2  eyes snapping open

Called from characters.paint_face. NEAR is the eye nearest the camera in the cinematic view (the Evochi faces
right, toward the guardian), where the asymmetries go so they read.
"""
from __future__ import annotations

import numpy as np

NEAR = -1
TEETH = '#FFFDF6'
CINE = ('shout', 'strain', 'fierce')


def is_cine(expr):
    return expr.split('.')[0] in CINE


def paint_cine(ch, cv, pal, expr):
    base, _, take = expr.partition('.')
    take = int(take) if take else 1
    st = ch.stage
    # the sheet's features are bigger and set a little closer than the sprites'
    EW, EH, EU = ch.eye_w * 1.55, ch.eye_h * 1.02, ch.eye_u * 0.84
    if st == 3:                          # the Elder's head is small for its body: its face reads bigger
        EW, EH, EU = EW * 1.1, EH * 1.1, EU * 0.9
    ev = ch.eye_v
    E, HI = pal['eye'], pal['eye_hi']
    MI, MO = pal['mouth_in'], pal['mouth']
    mv = ev - EH / 2 - EW * 0.32          # the mouth's top: just under the eyes
    BW = EW * 0.36                       # brow and chevron weight

    def paint(m, c):
        cv.paint(m, c, lit=0.0)

    def cheeks(w=1.0, h=1.0, alpha=1.0):
        for s in (-1, 1):
            cv.paint(cv.m_rect(s * (EU + EW * 0.55), ev - EH * 0.5 - EW * 0.02, EW * 0.82 * w, EW * 0.44 * h, EW * 0.12),
                     pal['cheek'], alpha, lit=0.5)

    def eye(s, cut_o, cut_i, scale=1.0, brow=True, glint=True, gap=0.32, du=0.0, dv=0.0, bw=1.0):
        """a tall black eye, its top cut from [cut_o] (outer) down to [cut_i] (inner), fractions of the eye's height,
        and a thick brow sitting on the cut"""
        w, h = EW * scale, EH * scale
        cu, cy = s * EU + du, ev + dv
        t = cy + h / 2
        xo, xi = cu + s * w / 2, cu - s * w / 2
        yo, yi = t - cut_o * h, t - cut_i * h
        k = (yi - yo) / (xi - xo)
        line = lambda U: yo + (U - xo) * k
        m = cv.m_rect(cu, cy, w, h, w / 2) & (cv.V <= line(cv.U))
        paint(m, E)
        if brow:
            g = BW * gap
            b0 = (xo + s * w * 0.22, line(xo + s * w * 0.22) + g + BW * 0.5)
            b1 = (xi - s * w * 0.12, line(xi - s * w * 0.12) + g + BW * 0.5)
            paint(cv.m_stroke([b0, b1], BW * bw), E)
        if glint:
            gw = w * 0.3
            gx = cu - w * 0.16
            gy = min(line(gx) - gw * 0.75, cy + h * 0.2)
            paint(cv.m_rect(gx, gy, gw, gw * 1.1, gw * 0.35), HI)

    def shut(s, size=1.0, du=0.0, dv=0.0, w=1.0):
        """squeezed shut: a thick chevron pointing in, > <"""
        cu, cy = s * EU + du, ev + dv - EH * 0.04
        a, b = EW * 0.62 * size, EH * 0.27 * size
        pts = [(cu + s * a, cy + b), (cu - s * a * 0.75, cy), (cu + s * a, cy - b)]
        paint(cv.m_stroke(pts, BW * 1.05 * w), E)

    def slit(s, du=0.0):
        """almost open: a sliver of eye under a heavy brow, a glint"""
        eye(s, 0.52, 0.62, dv=-EH * 0.06, du=du, gap=0.25, bw=1.05)

    def drop(u, v, size=1.0):
        sz = EW * 0.2 * size
        paint(cv.m_ellipse(u, v, sz, sz * 1.2) |
              cv.m_poly([(u - sz * 0.86, v + sz * 0.3), (u + sz * 0.86, v + sz * 0.3), (u, v + sz * 2.3)]), pal['sweat'])

    def yell(W, H, lower=False, tongue=True, dv=0.0, tilt=0.0):
        """the open mouth: a wide top (a little higher on the NEAR side when [tilt]), round below, fangs, tongue"""
        top = mv + dv
        o = EW * 0.12
        inner = cv.m_ellipse(0, top, W / 2, H) & (cv.V <= top + tilt * NEAR * cv.U / W * 2)
        outer = cv.m_ellipse(0, top, W / 2 + o, H + o) & (cv.V <= top + o + tilt * NEAR * cv.U / W * 2)
        paint(outer, MO)
        paint(inner, MI)
        if tongue:
            paint(cv.m_ellipse(0, top - H * 0.98, W * 0.3, H * 0.42) & inner, pal['tongue'])
        fz = EW * 0.2 * (1.15 if st == 1 else 1.0)
        for s in (-1, 1):
            x = s * W * 0.27
            y = top + tilt * NEAR * x / W * 2
            paint(cv.m_poly([(x - fz, y + o), (x + fz, y + o), (x + s * fz * 0.15, y - fz * 1.9)]) & inner, TEETH)
            if lower:
                yb = top - H * np.sqrt(max(0.0, 1 - (2 * x / W) ** 2)) * 0.97
                paint(cv.m_poly([(x - fz * 0.8, yb - o), (x + fz * 0.8, yb - o), (x, yb + fz * 1.5)]) & inner, TEETH)

    def grit(W, H, lift=0.0, dv=0.0, gaps=3):
        """gritted teeth: a white row in a red outline, one corner pushed up by [lift]"""
        c0 = mv - H * 0.6 + dv
        xs = np.linspace(-W / 2, W / 2, 9)
        tt = (xs * NEAR + W / 2) / W
        mid = c0 + lift * tt * tt

        def shape(p):
            up = [(x, y + H / 2 + p) for x, y in zip(xs, mid)]
            dn = [(x, y - H / 2 - p) for x, y in zip(xs[::-1], mid[::-1])]
            return up + [(xs[-1] + p * 0.9, mid[-1])] + dn + [(xs[0] - p * 0.9, mid[0])]
        o = EW * 0.1
        paint(cv.m_poly(shape(o)), MO)
        paint(cv.m_poly(shape(0)), TEETH)
        line = EW * 0.075
        paint(cv.m_stroke(list(zip(xs, mid)), line), MO)
        for i in range(1, gaps):
            x = -W / 2 + W * i / gaps
            y = float(np.interp(x, xs, mid))
            paint(cv.m_stroke([(x, y - H / 2), (x, y + H / 2)], line), MO)

    def frown(W, dv=0.0, depth=None, weight=1.0, du=0.0):
        """a small downturned arc"""
        d = EW * 0.26 if depth is None else depth
        th = np.linspace(np.radians(20), np.radians(160), 20)
        pts = np.stack([du + W / 2 * np.cos(th), mv - EW * 0.28 + dv - d + d * np.sin(th)], 1)
        paint(cv.m_stroke(pts, EW * 0.2 * weight), MO)

    if base == 'shout':
        mouth = {0: 0.78, 1: 1.0, 2: 1.12}[take]
        cut = {0: 0.16, 1: 0.22, 2: 0.3}[take]
        if st == 1:       # an oversized, adorable war cry
            cheeks(1.05)
            for s in (-1, 1):
                eye(s, 0.02, cut + 0.04)
            yell(EW * 1.75 * mouth, EW * 1.55 * mouth)
        elif st == 2:     # a confident, energetic battle yell
            cheeks()
            for s in (-1, 1):
                eye(s, 0.02, cut)
            yell(EW * 1.45 * mouth, EW * 1.7 * mouth, tilt=EW * 0.12)
        else:             # a commanding, powerful roar
            cheeks(0.95)
            for s in (-1, 1):
                eye(s, 0.06, cut + 0.1, bw=1.15)
            yell(EW * 1.95 * mouth, EW * 1.6 * mouth, lower=True)
    elif base == 'strain':
        if st == 3 and take == 2:     # the Elder opening an eye against the blast: watching it, jaw set
            cheeks()
            eye(NEAR, 0.18, 0.5, bw=1.1)
            shut(-NEAR, 0.95)
            frown(EW * 0.95, depth=EW * 0.34, weight=1.1, dv=-EW * 0.05)
            drop(-NEAR * (EU + EW * 0.85), ev + EH * 0.36, 0.9)
            return
        cheeks(1.1)
        if st == 3 and take == 1:     # intense resistance: one eye squeezed shut, the other almost open
            shut(-NEAR, 1.0)
            slit(NEAR)
        else:
            sq = {0: 0.92, 1: 1.0, 2: 1.06}[take]
            for s in (-1, 1):
                shut(s, sq * (1.06 if (st == 1 and s == NEAR) else 1.0))
        if take == 0:
            frown(EW * 0.8, depth=EW * 0.3)
        else:
            lift = {1: 0.0, 2: EW * 0.22}[take] + (EW * 0.12 if st == 2 else 0.0)
            W = EW * (1.4 if st == 1 else 1.3 if st == 2 else 1.45)
            grit(W, EW * 0.62, lift=lift)
        drop(NEAR * (EU + EW * 0.72), ev + EH * 0.42, 1.0)
        if st == 1 or take == 2:
            drop(-NEAR * (EU + EW * 0.9), ev + EH * 0.2, 0.75)
    elif base == 'fierce':
        cut = {0: 0.52, 1: 0.44, 2: 0.3}[take]
        scale = {0: 1.0, 1: 1.0, 2: 1.04}[take]
        if st == 1:       # a tiny, stubborn glare: narrowed, cheeks puffed, a pout
            cheeks(1.12, 1.15)
            for s in (-1, 1):
                eye(s, 0.1, cut + 0.04, scale=scale)
            frown(EW * 0.62, depth=EW * 0.22, weight=1.05)
        elif st == 2:     # an aggressive, focused stare
            cheeks()
            for s in (-1, 1):
                eye(s, 0.08, cut + 0.06, scale=scale)
            frown(EW * 0.78, depth=EW * 0.26)
        else:             # calm, composed, intimidating: lower lids, level brows, a set mouth
            cheeks(0.95)
            for s in (-1, 1):
                eye(s, 0.24, cut + 0.02, scale=scale, bw=1.15)
            frown(EW * 0.85, depth=EW * 0.12, weight=1.05)

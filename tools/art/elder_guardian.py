"""The Elder, redesigned to the "Guardian Build" concept: the Eggling grown into a sturdy, friendly crystalline
guardian. The original Elder (characters.build_elder) is untouched, the baseline; this replaces it once the
shape is approved. Built like the other stages (characters.py): the same materials, palettes and face rig.

The anatomy hangs off a torso frame (TY, ZF, ZB, DEPTH: see the code), everything placed from it:
  torso     horizontal, deep and rounded (a broad chest, a soft belly, a full rump), on shoulder and haunch
            masses the legs grow out of
  head      big, round and plush, carried at the front of the shoulders, nearly level: its centre a touch under
            the back line, the chin a third of a head below it, the chest under the chin: no neck, no mark
  legs      long enough that every step shows, thick at the top; brown boots, the light toes
  mane      broad faceted crystals in two layers round the back of the head: the tallest at the crown, the big
            side ones sweeping up, out and back, the small ones framing the cheeks; the face always clear
  back      a ridge of small petals down the spine into the tail's, whose outer curl is clad in petals (a ridge
            and a smaller pair either side); chunky amber patches on the flanks

    from elder_guardian import build_elder_guardian      # build(3, ...)'s replacement, once it's chosen
"""
from __future__ import annotations

import numpy as np

from voxel import Model
from characters import (Character, Frame, HeadView, MATS, _lerp_z, egg_mask, surface_point, head_rotation, local_frame, shell_region, square_shape, stamp, tube,
                        two_tone)


def _unit(v):
    v = np.asarray(v, float)
    return v / max(np.linalg.norm(v), 1e-9)


def crystal(M, base, direction, length, width, thick, tangent, gem=False, flat=0.45, tip=0.15):
    """A faceted crystal: broad at its base, tapering to a tip; [width] across [tangent], [thick] through it; the
    ridge down its middle (returned apart, to be lit as a facet). [gem]: the sides run parallel for [flat] of its
    length and then close to a point [tip] of the width across (the mane's chunky form), rather than tapering from
    the base."""
    base = np.asarray(base, float)
    d = _unit(direction)
    t_ax = np.asarray(tangent, float)
    t_ax = _unit(t_ax - (t_ax @ d) * d)
    n_ax = np.cross(d, t_ax)
    P = np.stack([M.X - base[0], M.Y - base[1], M.Z - base[2]], -1)
    t = P @ d
    u = np.abs(P @ t_ax)
    v = np.abs(P @ n_ax)
    f = np.clip(t / length, 0, 1)
    if gem:
        hw = width * np.where(f < flat, 0.95 + 0.1 * f, 1.0 - (1.0 - tip) * (f - flat) / (1.0 - flat))
        ht = thick * (1 - 0.5 * f)
    else:
        hw = width * (1 - f) ** 0.6 * (0.92 + 0.4 * f * (1 - f))
        ht = thick * (1 - f) ** 0.5
    inside = (u <= hw) & (v <= ht) & (t >= -1.5) & (t <= length)
    ridge = inside & (u <= hw * (0.38 if gem else 0.32)) & (f > 0.12)
    return inside, ridge


def petal(M, base, direction, length, hw, ht, breadth, roll=0.0, bend=0.0, back=(0.0, 0.0, -1.0)):
    """One mane crystal, shaped as a petal: narrow at its root, full-sided (an almond, widest just short of halfway), closing
    to a point;
    a diamond section (|u|/hw + |v|/ht <= 1: two facets a side and a ridge down its middle). [breadth] sets which
    way its width lies, [roll] (radians) turns the section about its axis, [bend] curls it toward [back] along its
    length (a fraction of the length, reached at the tip). Returns (inside, ridge)."""
    base = np.asarray(base, float)
    d = _unit(direction)
    u_ax = np.asarray(breadth, float)
    u_ax = _unit(u_ax - (u_ax @ d) * d)
    v_ax = np.cross(d, u_ax)
    if roll:
        u_ax, v_ax = u_ax * np.cos(roll) + v_ax * np.sin(roll), -u_ax * np.sin(roll) + v_ax * np.cos(roll)
    P = np.stack([M.X - base[0], M.Y - base[1], M.Z - base[2]], -1)
    t = P @ d
    f = np.clip(t / length, 0, 1)
    if bend:
        bk = np.asarray(back, float)
        bk = _unit(bk - (bk @ d) * d)
        P = P - (bend * length * f ** 2)[..., None] * bk
    u = np.abs(P @ u_ax)
    v = np.abs(P @ v_ax)
    s = np.maximum(np.sin(np.pi * f ** 0.85) ** 0.6, 0.45 * (f < 0.5))     # an almond: full sides, a point
    q = u / (hw * s) + v / (ht * np.maximum(s, 0.35))
    inside = (q <= 1.0) & (t >= -1.5) & (t <= length)
    ridge = inside & (u <= hw * s * 0.26) & (f > 0.12)
    return inside, ridge

def build_elder_guardian(res=2, feet=None, lo_y=-1, head=None, tail=0.0, head_rot=None, body=None, tail_lift=0.0,
                         jaw=0.0, plain=False, stretch=0.0) -> Character:
    """The same arguments as characters.build_elder: feet {(side, front): (dy, dz) or (dy, dz, dx)}, head (dx, dy,
    dz) a nod, head_rot (pitch, yaw, roll) degrees about the neck, body (dy_front, dy_back) a crouch, tail the
    curl's sideways swing, tail_lift its rise, jaw (degrees) the mouth open. plain: the large forms only (no
    mane, plates, patches or marks), to judge the silhouette."""
    feet = feet or {}
    bf, bb = body or (0.0, 0.0)
    hd = np.array(head or (0.0, 0.0, 0.0), float) + np.array([0.0, bf, 0.0])
    rotated = bool(head_rot) and any(abs(v) > 1e-9 for v in head_rot)
    R = head_rotation(head_rot)

    # ---- the torso's frame: everything else is placed from it. World units; x to its right, y up from the ground
    # (y = 0), z forward, toward its face. The v2 baseline's torso ran at y = 16; the tail, back plates and patches
    # it carried are re-hung from the new frame (DT) without changing their shapes.
    LEG_DROP = 2.5                          # how much shorter than the Guardian Build's legs (the body sits lower)
    TY = 20.5 - LEG_DROP                    # the torso's centreline height
    ZF, ZB = 6.5 + 0.5 * stretch, -12.0 - 0.5 * stretch   # the shoulders' z and the hips' z: its length is ZF - ZB
    # (stretch: the body lengthened (or, below 0, gathered) by that much, the front half forward, the back half back,
    # for a run's stretch and gather)
    DEPTH = 9.6                             # the chest's half-depth (its top at TY + DEPTH, its belly at TY - DEPTH)
    SHOULDER = (7.0, TY - 2.0, ZF - 1.0)    # a shoulder's mass, per side (x mirrored): the forelegs grow out of it
    HIP = (7.4, TY - 2.5, ZB + 1.5)         # a haunch's, the hindlegs out of it
    DT = TY - 16.0
    # the head (the baseline's: the same size, radii and face) is carried at the front of the shoulders, nearly
    # level: its centre a touch under the back line (the eyes at the back's height, as the concept has them), the
    # chin a third of a head below it, the chest's front under the eyes; no neck, the chest under the chin
    HEAD_R = (14.1, 10.5, 10.0, 11.6)       # x, up, down, z: broad and plush (wider than tall), full in the cheeks
    HCEN = (0.0, TY + DEPTH - 1.0, ZF + 7.0)
    PIVOT = np.array([0.0, TY + 4.0, ZF + 2.5])   # where the head meets the shoulders (what a head turn is about)
    Hw = lambda p: tuple(PIVOT + R @ (np.array(p, float) - PIVOT) + hd)  # noqa: E731
    M = Model((-27, lo_y, -47), (27, 54, 30), MATS, res=res)
    if rotated:
        HL, HC = HeadView(M, PIVOT, R, hd), (lambda p: tuple(np.array(p, float)))
    else:
        HL, HC = M, (lambda p: tuple(np.array(p, float) + hd))
    B = lambda p: (p[0], p[1] + float(_lerp_z(p[2], ZF, ZB, bf, bb)), p[2])  # noqa: E731  a point on the torso

    # ---- the large forms: the head; a deep, rounded torso (a broad chest, a soft belly, a full rump); the
    # shoulder and haunch masses at its corners; the curled tail from the rump
    head = egg_mask(HL, HC(HCEN), *HEAD_R, p=2.15)
    zm = (ZF + ZB) / 2
    # (the chest's front is set back under the head, as the Juvenile's is: the head's round underside overhangs it,
    # so a crease parts the two instead of the chest swelling up into a second chin)
    body_m = tube(M, [B((0, TY - 0.2, ZF - 2.5)), B((0, TY + 0.3, zm + 2.0)), B((0, TY, ZB + 3.0)), B((0, TY - 0.6, ZB))],
                  [DEPTH - 0.6, DEPTH + 0.3, DEPTH, DEPTH - 1.6], p=2.4, squash=(1.0, 1.0))
    for s_ in (-1, 1):
        body_m |= egg_mask(M, B((s_ * SHOULDER[0], SHOULDER[1], SHOULDER[2])), 5.4, 6.4, 6.2, 5.8, p=2.3)   # the shoulders
        body_m |= egg_mask(M, B((s_ * HIP[0], HIP[1], HIP[2])), 6.8, 7.8, 7.4, 7.6, p=2.3)                   # the haunches
    # the lower chest and belly carry a little more (about 7%)
    body_m |= tube(M, [B((0, TY - 1.0, ZF - 4.0)), B((0, TY - 0.8, zm + 1.0)), B((0, TY - 1.0, ZB + 2.0))],
                   [DEPTH * 1.07, DEPTH * 1.08, DEPTH * 1.02], p=2.4) & (M.Y < TY + 1.0)
    # the tail: the original Elder's long sweep (low and back from the rump before it curls up), on a shorter body
    # (0.9 of its run) and thick as the Juvenile's
    TROOT = np.array([15.7, ZB])
    sweep_ = [(0.0, 0.0), (-0.9, -6.5), (-0.1, -12.5), (3.1, -17.5), (8.1, -20.0), (13.1, -19.2), (16.3, -16.2),
              (16.9, -12.6), (15.1, -10.2)]
    tpath = [(0.0, TROOT[0] + 0.9 * dy, TROOT[1] + 0.9 * dz) for dy, dz in sweep_]
    tpath = [(tail * min(1.0, i / 4.0) ** 1.5, y + DT + bb + tail_lift * min(1.0, i / 4.0) ** 1.5, z) for i, (_, y, z) in enumerate(tpath)]
    trad = [7.8, 7.3, 6.8, 6.2, 5.6, 5.0, 4.5, 4.0, 3.6]
    TCEN = (TROOT[0] + 0.9 * 10.5, TROOT[1] - 0.9 * 15.0)     # the curl's middle (y, z, before the lift)
    tail_m = tube(M, tpath, trad, p=2.4)
    core = head | body_m | tail_m
    M.set(core, 'shell')
    dyz = _lerp_z(M.Z, ZF, ZB, bf, bb) if (bf or bb) else 0.0
    belly = core & (M.Y - dyz < TY - 3.0) & (M.Z > ZB - 1) & ~head
    M.set(belly, 'belly')

    # ---- the legs: long (every step shows), thick at the top where they grow out of the shoulders and haunches
    for s in (-1, 1):
        for z in (SHOULDER[2] + 0.5, HIP[2] - 1.0):
            f = feet.get((s, z > 0), (0.0, 0.0))
            dy, dz = f[0], f[1]
            dx = s * f[2] if len(f) > 2 else 0.0
            hip = B((s * 7.4, 13.5 - LEG_DROP, z))
            knee = (s * 8.2 + dx * 0.5, 7.2 - LEG_DROP * 0.45 + dy * 0.55 + (hip[1] - 13.5 + LEG_DROP) * 0.5, z + 0.4 + dz * 0.55)
            leg = tube(M, [hip, knee, (s * 8.6 + dx, 3.0 + dy, z + 0.8 + dz)], [6.0, 4.9, 4.4], p=2.5) & ~core
            leg &= M.Y >= dy
            M.set(leg, 'shell')
            zf, fx = z + dz, s * 8.6 + dx
            foot = M.box((fx - 4.4, dy, zf - 3.4), (fx + 4.4, 3.8 + dy, zf + 5.2))
            foot &= ~((M.Y > 2.6 + dy) & (M.Z > zf + 3.6))
            # the paw's brown runs up the leg to a flat line past the ankle (the reference's sturdy paws), the leg
            # itself unchanged
            M.set(foot | (leg & (M.Y < 7.0 - LEG_DROP * 0.55 + dy)), 'feet')
            M.set(foot & (M.Y < 1.1 + dy), 'feet_shade')
            for cx in np.linspace(fx - 2.9, fx + 2.9, 3):
                M.set(M.box((cx - 0.8, dy, zf + 4.8), (cx + 0.8, 1.6 + dy, zf + 6.6)), 'claw')

    cx, cy, cz = HCEN
    if plain:
        return _finish(M, R, Hw, B, HCEN, TY, DEPTH, ZF, ZB, DT, PIVOT, hd, head, body_m, tail_m, tail, bb, tail_lift, bf, jaw, [])

    # ---- the crystal mane, grown the Evochi way: the Eggling wears scale squares, the Juvenile a ridge of soft
    # tufts, and the Elder's tufts harden into crystals and bloom outward from that ridge into a halo around the
    # back of the head. So:
    #   lineage   each crystal rises out of a small amber tuft (the Juvenile's fluff), not straight off the skin
    #   one root  every crystal's axis runs back through one point, ahead of and below the head's centre, so the
    #             whole mane reads as one burst sweeping up, out and back (the flow continues down the spine)
    #   rhythm    two rows, the back row set between the front row's crystals and longer, so tips alternate and
    #             there is sky between them; the crown is the largest, and they shrink toward the cheeks
    #   form      faceted (diamond section, each rolled a little differently, so facets catch the light apart),
    #             thick at the root and blunt at the tip: chunky and friendly rather than sharp
    #   face      every root sits behind the head's centre, so nothing crosses the face; the cheek ones frame it
    rx, ryt, ryb, rz = HEAD_R
    #        angle (0 = out to the side, 90 = the top), row (0 front, 1 back), length, half-width
    mane = [(90, 0, 19.5, 5.6), (62, 0, 13.8, 4.6), (34, 0, 14.0, 4.5), (6, 0, 12.0, 4.2), (-22, 0, 10.0, 3.7),
            (-48, 0, 7.5, 3.0),
            (76, 1, 14.2, 4.2), (48, 1, 14.5, 4.0), (20, 1, 13.0, 3.7), (-8, 1, 11.0, 3.4),
            # behind them, two rows of shorter petals lying back over the head like shingles, down to the nape, so
            # the back of the head is clad too and the mane runs on into the spine's crystals
            (90, 2, 15.0, 4.8), (62, 2, 14.5, 4.6), (34, 2, 13.5, 4.4), (6, 2, 12.0, 4.0), (-22, 2, 10.0, 3.5)]
    crest_ids = [k for k, nm in enumerate(M.mats) if nm.startswith('crest')]
    n = 0
    for ang, row, L, hw in mane:
        a = np.radians(ang)
        z0, zk, sweep = ((1.5, 5.5, 16.0), (-2.5, 5.5, 26.0), (-5.0, 1.0, 54.0), (-7.5, 0.5, 64.0))[row]
        zr = z0 + zk * max(np.sin(a), 0.0)      # the front rows rooted forward, toward the forehead
        sweep += 8.0 * abs(np.sin(a))      # the crown and the cheeks lie back more; the temples reach out
        if ang == 90:
            sweep = 24.0 if row == 0 else sweep   # but the crown's centre stands tallest: the eye goes to it first
        s_ = (1 - abs(zr / rz) ** 2.15) ** (1 / 2.15) * 0.78      # under the surface at that depth
        for side in ((0,) if ang == 90 else (-1, 1)):
            sd = side or 1
            radial = np.array([sd * np.cos(a), np.sin(a), 0.0]) if side else np.array([0.0, 1.0, 0.0])
            loc = np.array([side * rx * np.cos(a) * s_, (ryt if a >= 0 else ryb) * np.sin(a) * s_, zr])
            sw = np.radians(sweep)
            d = radial * np.cos(sw) + np.array([0.0, 0.0, -1.0]) * np.sin(sw)
            ring = np.array([-np.sin(a) * sd, np.cos(a), 0.0])     # along the halo: the petal's breadth faces front
            roll = (0.0, 0.25, -0.25)[n % 3]
            base = HC(tuple(np.array(HCEN) + loc))
            c, ridge = petal(HL, base, d, L, hw, hw * 0.5, ring, roll, bend=0.12)
            c &= ((M.m == 0) | (np.isin(M.m, crest_ids) if row < 2 else False)) & ~core   # the rear rows tuck behind
            k = n % 6
            M.set(c, 'crest.%d' % k)
            M.set(ridge & c, 'crest_mid.%d' % k)
            n += 1

    # ---- down the spine: a ridge of small petals from behind the mane to the tail's root, so the mane, the back and
    # the tail read as one line (as the concept's do); each sits on the back's top line, leaning back
    torso_top = body_m & (np.abs(M.X) < 0.6)
    zs = np.arange(1.0, ZB - 0.6, -2.4)
    for i, z in enumerate(zs):
        col = torso_top & (np.abs(M.Z - z) < 0.6)
        if not col.any():
            continue
        y = float(M.Y[col].max())
        f = i / max(len(zs) - 1, 1)
        L, hw = 10.5 - 3.0 * f, 3.5 - 0.7 * f
        sx = 2.0 * (1 if i % 2 else -1)         # two rows, staggered either side of the spine
        c, ridge = petal(M, (sx, y - 1.2, z), (sx * 0.12, 1.0, -0.5), L, hw, hw * 0.55, (0.0, 0.0, -1.0), 0.0,
                         bend=0.1)
        c &= (M.m == 0)
        M.set(c, 'crest.%d' % (i % 6))
        M.set(ridge & c, 'crest_mid.%d' % (i % 6))
    # ---- the tail's ridge: petals like the mane's (as the Juvenile's tufts run on down its tail), set closer than
    # the blocks were, standing out from the curl and leaning toward the tip, smaller as the tail thins
    cen = np.array([tail, TCEN[0] + DT + bb + tail_lift, TCEN[1]])
    pts = np.array(tpath, float)
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    ts = list(np.arange(cum[1] - 1.0, cum[-1] - 0.8, 3.0))
    for k, t in enumerate(ts):
        i = min(int(np.searchsorted(cum, t, side='right')) - 1, len(seg) - 1)
        f = (t - cum[i]) / max(seg[i], 1e-9)
        p = pts[i] * (1 - f) + pts[i + 1] * f
        r = trad[i] * (1 - f) + trad[i + 1] * f
        tang = _unit(pts[i + 1] - pts[i])
        out = p - cen
        out[0] = 0
        out = _unit(out) if t >= cum[3] else _unit(np.array([0.0, 1.0, 0.0]) - 0.3 * tang)
        out = _unit(out - (out @ tang) * tang)
        d = _unit(out * 0.8 + tang * 0.6)
        L, hw = r * 1.75 + 1.5, r * 0.6 + 0.6
        c, ridge = petal(M, p + out * r * 0.7, d, L, hw, hw * 0.55, tang, 0.0, bend=0.1, back=tuple(tang))
        c &= (M.m == 0)
        M.set(c, 'crest.%d' % (k % 6))
        M.set(ridge & c, 'crest_mid.%d' % (k % 6))
        # and a smaller pair either side of the ridge, set between its petals (the concept's tail is clad all round
        # its outer curl)
        if k >= 1:
            side_ax = np.cross(tang, out)
            for sd in (-1, 1):
                o2 = _unit(out * 0.8 + side_ax * sd * 0.6)
                c, ridge = petal(M, p - tang * 1.5 + o2 * r * 0.7, _unit(o2 * 0.75 + tang * 0.66), L * 0.62, hw * 0.7,
                                 hw * 0.42, tang, 0.0, bend=0.1, back=tuple(tang))
                c &= (M.m == 0)
                M.set(c, 'crest.%d' % ((k + 2 + sd) % 6))
                M.set(ridge & c, 'crest_mid.%d' % ((k + 2 + sd) % 6))

    # ---- the amber markings: clusters of chunky blocks that run from the mane down the body to the tail (the
    # shoulders, the upper back, the mid-torso, the haunches, the tail's root), each a
    # few blocks round a centre on the body's surface; the belly stays white
    shl = shell_region(M, core, res)
    flank = DEPTH - 0.5
    clusters = [
        # centre (x, y, z: x per side), normal, the blocks round it: (du, dv, w, h)
        ((flank, TY + 4.0, ZF - 2.5), (1, 0.25, 0), ((0, 0, 4.4, 4.0), (3.2, -3.4, 3.0, 2.8), (-3.0, 3.0, 2.6, 2.4))),            # shoulders
        ((4.8, TY + DEPTH - 0.6, -5.0), (0.35, 1, 0), ((0, 0, 3.8, 3.4), (3.2, 3.2, 2.8, 2.6))),                                   # the upper back
        ((flank, TY + 0.5, -4.0), (1, 0.15, 0), ((0, 0, 4.6, 4.0), (-3.4, 3.2, 2.8, 2.6), (3.2, -3.0, 2.8, 2.4))),               # mid-torso
        ((flank, TY - 1.0, ZB + 2.0), (1, 0.2, 0), ((0, 0, 4.4, 3.8), (3.0, 3.4, 3.0, 2.8), (-3.2, -2.6, 2.6, 2.4))),            # the haunches
        ((trad[0] - 0.6, 15.7 + DT + 1.5, -13.0), (1, 0.3, 0), ((0, 0, 3.4, 3.2), (2.8, 3.0, 2.6, 2.4))),         # the tail's root
    ]
    GROW = 1.0      # (toned down: the spikes carry the amber now; these are accents)
    # each block is a raised cube, half sunk into the body (the concept's chunky amber, not paint), found by casting
    # in along the cluster's normal to the body's surface
    nb = 0
    for s in (-1, 1):
        for ci, ((x, y, z), (nx, ny, nz), blocks) in enumerate(clusters):
            nrm = _unit((s * nx, ny, nz))
            up_ax = (0, 0, 1) if ny > 0.9 else (0, 1, 0)
            u_ax, v_ax, _ = local_frame(tuple(nrm), up_ax)
            ctr = np.array(B((s * x, y, z)), float)
            for du, dv, w, h in blocks:
                c = ctr + (u_ax * du + v_ax * dv) * GROW * 1.15
                sp = surface_point(M, core, c - nrm * 5.0, nrm, tmax=12)
                if sp is None:
                    continue
                size = (w + h) / 2 * GROW * 0.75
                half = np.full(3, size / 2)
                half[int(np.argmax(np.abs(nrm)))] = size * 0.3
                blk = M.box(sp + nrm * 0.2 - half, sp + nrm * 0.2 + half)
                M.set(blk & ((M.m == 0) | core), 'crest.%d' % (nb % 6))
                nb += 1

    two_tone(M, seed=43, thresh=0.6)
    # (no forehead mark: the Juvenile has none, and the mane carries the Elder's identity)
    return _finish(M, R, Hw, B, HCEN, TY, DEPTH, ZF, ZB, DT, PIVOT, hd, head, body_m, tail_m, tail, bb, tail_lift, bf, jaw, [])


def _finish(M, R, Hw, B, HCEN, TY, DEPTH, ZF, ZB, DT, PIVOT, hd, head, body_m, tail_m, tail, bb, tail_lift, bf, jaw, pattern_decals):
    """The face rig and the anchors, all placed from the head's centre and the torso's frame."""
    cx, cy, cz = HCEN
    face = Frame(center=Hw((cx, cy - 0.8, cz)), n=tuple(R @ np.array([0.0, 0.0, 1.0])), up=tuple(R @ np.array([0.0, 1.0, 0.0])), reach=22)
    ch = Character(stage=3, model=M, face=face,
                   eye_u=6.6, eye_v=1.1, eye_w=2.5, eye_h=5.6,
                   cheek_u=9.2, cheek_v=-2.5, cheek_w=2.8, cheek_h=2.1,
                   mouth_v=-3.7, face_extent=(-13, 13, -8, 8), scale_ref=46.0, pattern_decals=pattern_decals)
    ch.anchors = {
        'head_top': Hw((cx, cy + 10.0, cz - 3.5)), 'neck': B((0, TY + 2.0, ZF + 1.5)), 'back': B((0, TY + DEPTH, -3.0)),
        'ground': (0, 0, -1.5), 'face': Hw((cx, cy - 0.8, cz + 11.6)), 'tail': (tail, 31.0 + DT + bb + tail_lift, -26.0),
    }
    ch.rig = dict(head=head, fused=body_m | tail_m, pivot=PIVOT, R=R, t=hd, torso=(ZF, ZB, bf, bb))
    if jaw:
        from jaw import open_jaw
        ch = open_jaw(ch, jaw)
    return ch

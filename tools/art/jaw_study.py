"""A geometry study of the Juvenile's and Elder's heads for an opening mouth, before anything changes in the rig:

  1. every existing voxel of the model by part (the same shapes characters.build_* makes the model from):
     upper head (skull), the lower head that would become the jaw (underside and chin included), where head and
     neck or body overlap (the throat), neck, torso, legs, tail, crest
  2. a section down the middle (x = 0): the whole head volume, underside included, the mouth plane, the hinge
  3. a prototype of the open mouth made from those voxels: the lower head swings down about the hinge (rigidly at
     the chin, blending to nothing at the hinge so the throat stretches rather than tears), the space it opens is a
     mouth with depth (palate, inner cheeks, back wall, a tongue on the jaw's floor, two fangs on the upper lip,
     lips along both edges), and nothing new is bolted on
  4. the numbers: existing voxels reused, voxels added, whether the jaw runs into the neck or chest, and that
     jawOpen = 0 is the original model voxel for voxel

    python3 jaw_study.py OUT_DIR [stage ...]
"""
from __future__ import annotations

import dataclasses
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from characters import build, egg_mask, tube                      # noqa: E402
import charrender as CR                                           # noqa: E402
from palettes import palette                                      # noqa: E402
from voxel import Camera, fit_camera, model_extent_points         # noqa: E402
from turnarounds import font                                      # noqa: E402

BG = (250, 240, 228)
INK = (52, 36, 30)
SUB = (120, 96, 82)
PART_COL = {'skull': '#79A5DB', 'jaw': '#F29A4A', 'stretch': '#F7CFA0', 'cheek': '#A9C6EA', 'throat': '#B58CDB', 'neck': '#6FC285', 'torso': '#CFC8BE',
            'legs': '#9A7A64', 'tail': '#E2DBD0', 'crest': '#EADDB4'}
PART_NAME = {'skull': 'upper head (stays)', 'jaw': 'jaw: swings', 'stretch': 'blends: the skin stretches',
             'cheek': 'lower cheeks (stay)', 'throat': 'head and neck/chest overlap',
             'neck': 'neck', 'torso': 'torso', 'legs': 'legs and feet', 'tail': 'tail', 'crest': 'crest / mane'}
MOUTH = {'mouth_in': '#712E37', 'mouth_deep': '#4A1E26', 'tongue': '#E98D87', 'teeth': '#FFFBF2', 'lip': '#8E4444'}
VIEWS = [('front', Camera(yaw=0, pitch=0)), ('three-quarter', Camera(yaw=-32, pitch=-7)),
         ('side', Camera(yaw=-90, pitch=0)), ('slightly below', Camera(yaw=-24, pitch=-34))]

# the jaw per stage, in the model's units (y up, z forward, the face looks along +z):
#   hinge   (y, z) the jaw's pivot, behind the mouth and below the eyes (an axis across the head, along x)
#   lip     (y, z) where the mouth plane meets the front of the face: the closed mouth's line
#   width   the mouth's half-width at the front (it narrows to 55% at the back)
#   depth   how far back the open mouth's back wall sits, as a share of hinge-to-lip
#   skin    the share of the jaw (from the hinge) over which the swing blends in: the throat stretches there
#   open    the Shock opening, degrees
JAW = {2: dict(hinge=(14.4, 8.5), lip=(15.0, 16.6), width=3.2, xfull=4.2, xzero=8.6, depth=0.4, skin=0.3, open=30.0),
       3: dict(hinge=(14.8, 19.0), lip=(14.2, 28.6), width=3.0, xfull=3.8, xzero=7.2, depth=0.38, skin=0.28, open=22.0)}
#   xfull / xzero: across the face, the jaw swings fully within xfull of the middle and not at all beyond xzero:
#   the cheeks stay, the mouth's corners close


def _smooth(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def parts(ch):
    """each voxel of the model by part, from the shapes characters.build_* makes the model from"""
    M = ch.model
    st = ch.stage
    filled = M.m > 0
    names = np.array(M.mats)
    mat = names[M.m]
    crest = np.char.startswith(mat, 'crest')
    legs = np.isin(mat, ['feet', 'feet_shade', 'claw'])
    flesh = filled & ~crest & ~legs
    if st == 2:
        head = egg_mask(M, (0, 17.4, 7.0), 11.4, 10.0, 9.8, 9.6, p=2.9)
        body = tube(M, [(0, 9.4, 2.0), (0, 9.0, -5.0), (0, 9.2, -9.5)], [8.2, 8.0, 6.8], p=2.5, squash=(1.0, 0.84))
        neck = np.zeros_like(head)
        tail = tube(M, [(0, 9.2, -10.5), (0, 10.0, -15.5), (0, 12.3, -19.5), (0, 15.6, -22.0), (0, 19.0, -23.0)],
                    [6.0, 5.0, 4.3, 3.8, 3.4], p=2.4)
    else:
        head = egg_mask(M, (0, 17.0, 16.0), 9.8, 8.4, 7.6, 10.2, p=2.7) | egg_mask(M, (0, 15.0, 23.0), 7.4, 5.4, 5.0, 5.8, p=2.6)
        neck = tube(M, [(0, 15.0, 10.0), (0, 12.5, 5.0)], [7.6, 8.2], p=2.4)
        body = tube(M, [(0, 11.8, 5.0), (0, 11.6, -4.0), (0, 11.4, -13.0), (0, 11.0, -19.0)], [9.0, 9.6, 9.2, 7.6], p=2.5,
                    squash=(1.05, 0.88))
        tp = [(0, 10.5, -20.0), (0, 9.6, -26.5), (0, 10.4, -32.5), (0, 13.6, -37.5), (0, 18.6, -40.0), (0, 23.6, -39.2),
              (0, 26.8, -36.2), (0, 27.4, -32.6), (0, 25.6, -30.2)]
        tail = tube(M, tp, [6.8, 6.0, 5.4, 4.9, 4.5, 4.1, 3.7, 3.2, 2.8], p=2.3)
    J = JAW[st]
    below = M.Y < _plane_y(J, M.Z)
    out = {}
    hb = flesh & head
    other = body | neck
    out['throat'] = hb & other
    out['jaw'] = hb & ~other & below & (M.Z > J['hinge'][1])
    out['skull'] = hb & ~other & ~out['jaw']
    out['neck'] = flesh & neck & ~head
    out['torso'] = flesh & body & ~head & ~neck
    out['tail'] = flesh & tail & ~head & ~body & ~neck
    out['legs'] = (flesh & ~head & ~body & ~neck & ~tail) | legs
    out['crest'] = crest
    out['head_shape'] = head
    return out


def _plane_y(J, Z):
    """the mouth plane's height at depth Z: through the hinge and the closed mouth's line"""
    (yh, zh), (yl, zl) = J['hinge'], J['lip']
    return yh + (Z - zh) * (yl - yh) / (zl - zh)


def part_model(ch, P):
    """the model with every voxel coloured by its part"""
    M = ch.model
    N = M.__class__.__new__(M.__class__)
    N.__dict__.update(M.__dict__)
    N.m = np.zeros_like(M.m)
    N.mats = ['empty']
    N.ids = {'empty': 0}
    J = JAW[ch.stage]
    (yh, zh), (yl, zl) = J['hinge'], J['lip']
    wt = _smooth((M.Z - zh) / (J['skin'] * (zl - zh))) * (1 - _smooth((np.abs(M.X) - J['xfull']) / (J['xzero'] - J['xfull'])))
    for k, col in PART_COL.items():
        if k in ('jaw', 'stretch', 'cheek'):
            continue
        N.m[P[k]] = N.mid(col)
    N.m[P['jaw'] & (wt >= 0.6)] = N.mid(PART_COL['jaw'])
    N.m[P['jaw'] & (wt > 0.02) & (wt < 0.6)] = N.mid(PART_COL['stretch'])
    N.m[P['jaw'] & (wt <= 0.02)] = N.mid(PART_COL['cheek'])
    return N


def open_jaw(ch, P, deg, J=None):
    """the model with the lower head swung open [deg] degrees and the mouth it opens: a Character, and its numbers"""
    J = J or JAW[ch.stage]
    M = ch.model
    st = ch.stage
    (yh, zh), (yl, zl) = J['hinge'], J['lip']
    L = zl - zh
    th = math.radians(deg)
    N = M.__class__.__new__(M.__class__)
    N.__dict__.update(M.__dict__)
    N.m = M.m.copy()
    N.glow = M.glow.copy()
    N.layer = M.layer.copy()
    N.mats = list(M.mats)
    N.ids = dict(M.ids)
    jaw = P['jaw']
    N.m[jaw] = 0
    N.glow[jaw] = 0

    def w(Z, X):
        return _smooth((Z - zh) / (J['skin'] * L)) * (1 - _smooth((np.abs(X) - J['xfull']) / (J['xzero'] - J['xfull'])))
    # every voxel in reach of the swing: where did it come from? (the angle depends on the source: settle it)
    box = (M.Z > zh - 2) & (M.Y < yh + 4) & (np.abs(M.X) < 16)
    qi = np.argwhere(box)
    Q = np.stack([M.X[box], M.Y[box], M.Z[box]], 1)
    p = Q.copy()
    for _ in range(4):
        a = th * w(p[:, 2], p[:, 0])
        dz, dy = Q[:, 2] - zh, Q[:, 1] - yh
        p = np.stack([Q[:, 0], yh + dz * np.sin(a) + dy * np.cos(a), zh + dz * np.cos(a) - dy * np.sin(a)], 1)
    si = np.floor(p * M.res).astype(int) - M.lo
    ok = np.all((si >= 0) & (si < np.array(M.m.shape)), 1)
    src_jaw = np.zeros(len(Q), bool)
    src_jaw[ok] = jaw[tuple(si[ok].T)]
    dst = tuple(qi[src_jaw].T)
    srcv = tuple(si[src_jaw].T)
    other = P['torso'] | P['neck'] | P['throat'] | P['legs']
    collide = other[dst]
    keep = ~collide                                           # the neck and chest win where the jaw meets them
    N.m[tuple(d[keep] for d in dst)] = M.m[tuple(s[keep] for s in srcv)]
    jaw_after = np.zeros(M.m.shape, bool)
    jaw_after[tuple(d[keep] for d in dst)] = True
    # the space the jaw left inside the head: the mouth
    skull = P['skull'] | P['throat']
    W = P['head_shape'] & ~skull & ~jaw_after & ~other & (M.Y < _plane_y(J, M.Z) + 0.6) & (M.Z > zh - 0.5) & (N.m == 0)
    t = np.clip((M.Z - zh) / L, 0, 1)
    half = J['width'] * (0.55 + 0.45 * t)
    zback = zh + J['depth'] * L
    hole = W & (np.abs(M.X) < half) & (M.Z > zback)
    walls = W & ~hole
    near = ndimage.binary_dilation(hole, iterations=3)
    skin = walls & ~near                                  # the stretch's gaps away from the mouth: skin again
    walls = walls & near
    if deg > 0:
        N.m[walls & (M.Z <= zback + 1.0)] = N.mid('mouth_deep')
        N.m[walls & (M.Z > zback + 1.0)] = N.mid('mouth_in')
        N.m[skin] = M.m[skin]
    # surfaces round the hole: palate above, the jaw's floor and tongue below, lips at the front edges
    up = np.roll(hole, -1, axis=1)          # the voxel above is hole
    dn = np.roll(hole, 1, axis=1)           # the voxel below is hole
    side = np.roll(hole, 1, axis=0) | np.roll(hole, -1, axis=0)
    filled = N.m > 0
    outside = ~filled & ~hole & ~P['head_shape']
    front_open = np.roll(outside, -1, axis=2) | np.roll(~filled & ~hole, -1, axis=2)
    palate = filled & dn & ~jaw_after
    floor = filled & up & jaw_after
    cheek_in = filled & side & ~palate & ~floor
    N.m[cheek_in] = N.mid('mouth_in')
    N.m[palate] = N.mid('mouth_in')
    tongue_zone = (np.abs(M.X) < half * 0.62) & (M.Z > zback + 0.5) & (M.Z < zl - 1.0)
    N.m[floor & tongue_zone] = N.mid('tongue')
    N.m[floor & ~tongue_zone] = N.mid('mouth_in')
    lip = ((palate | floor) & front_open)
    N.m[lip] = N.mid('lip')
    # two fangs on the upper lip, inside the opening
    fangs = np.zeros(M.m.shape, bool)
    if deg > 0:
        for sgn in (-1, 1):
            x = sgn * J['width'] * 0.58
            col = palate & (np.abs(M.X - x) < 0.6)
            if col.any():
                zf = M.Z[col].max()
                yp = M.Y[col & (M.Z > zf - 0.6)].min()
                # a small fang: two voxels wide at the lip, one at the tip, three long
                for k, (hw, dy) in enumerate(((0.5, 0.0), (0.5, -0.5), (0.25, -1.0))):
                    fangs |= hole & (np.abs(M.X - x) < hw) & (M.Z > zf - 1.1) & (M.Z <= zf + 0.3) & (np.abs(M.Y - (yp - 0.5 + dy)) < 0.26)
        N.m[fangs] = N.mid('teeth')
    stats = dict(jaw_voxels=int(jaw.sum()), jaw_moved=int(keep.sum()), collide=int(collide.sum()),
                 added=int((walls.sum() if deg > 0 else 0) + fangs.sum()), hole=int(hole.sum()),
                 recoloured=int((palate | floor | cheek_in).sum()), fangs=int(fangs.sum()))
    out = dataclasses.replace(ch, model=N)
    return out, stats, dict(hole=hole, walls=walls, jaw_after=jaw_after)


def section(ch, P, extra=None, scale=14, region=None):
    """the model cut down the middle (x = 0), coloured by part, the head region"""
    M = ch.model
    xi = int(round((0.25 - M.lo[0] / M.res) * M.res))     # the slice nearest x = 0
    xi = np.argmin(np.abs(M.X[:, 0, 0] - 0.25))
    y0, y1, z0, z1 = region
    js = np.where((M.Y[0, :, 0] >= y0) & (M.Y[0, :, 0] <= y1))[0]
    ks = np.where((M.Z[0, 0, :] >= z0) & (M.Z[0, 0, :] <= z1))[0]
    img = np.full((len(js), len(ks), 3), BG, np.uint8)
    def put(mask, col):
        sl = mask[xi][np.ix_(js, ks)]
        img[sl] = np.array([int(col[i:i + 2], 16) for i in (1, 3, 5)], np.uint8)
    for k in ('torso', 'neck', 'legs', 'tail', 'crest', 'throat', 'skull', 'jaw'):
        put(P[k], PART_COL[k])
    if extra is not None:
        for name, col in extra:
            put(name, col)
    img = img[::-1]                                   # y up
    im = Image.fromarray(img).resize((len(ks) * scale // M.res, len(js) * scale // M.res), Image.NEAREST)
    def to_px(y, z):
        return ((z - M.Z[0, 0, ks[0]]) * scale + scale / 2 / M.res, (M.Y[0, js[-1], 0] - y) * scale + scale / 2 / M.res)
    return im, to_px


def render_set(ch, expr, pal, w=380, h=340, fits=None):
    if expr == 'none':                                  # no face: the parts alone
        CR._quad_cache[(id(ch.model), 'amber', 'none')] = []
    out = []
    for i, (name, cam) in enumerate(VIEWS):
        fit = fits[i] if fits else None
        r = CR.render_char(ch, 'amber', expr, cam, w, h, fit=fit, pal=pal)
        im = Image.new('RGB', (w, h), BG)
        c = Image.fromarray(r.rgba)
        im.paste(c, (0, 0), c)
        out.append(im)
    return out


def study(stage, out_dir):
    ch = build(stage)
    P = parts(ch)
    J = JAW[stage]
    opened, stats, geo = open_jaw(ch, P, J['open'])
    zero, st0, _ = open_jaw(ch, P, 0.0)
    same = int((zero.model.m != ch.model.m).sum())
    pal = dict(palette('amber'))
    pal.update(MOUTH)
    partpal = dict(pal)
    pch = dataclasses.replace(ch, model=part_model(ch, P))
    # the same framing for both rows: the open model's extent
    fits = [fit_camera(cam, np.concatenate([model_extent_points(opened.model)]), 380, 340, margin=0.06) for _, cam in VIEWS]
    row_parts = render_set(pch, 'none', partpal, fits=fits)
    row_open = render_set(opened, 'shout:brave:nomouth', pal, fits=fits)
    row_closed = render_set(ch, 'shout:brave:nomouth', pal, fits=fits)
    region = (2, 30, -4, 20) if stage == 2 else (4, 28, 4, 32)
    sec0, px0 = section(ch, P, region=region)
    mouth_masks = [(geo['walls'], MOUTH['mouth_deep']), (geo['jaw_after'], PART_COL['jaw'])]
    P_open = dict(P)
    P_open['jaw'] = np.zeros_like(P['jaw'])
    sec1, px1 = section(opened, P_open, extra=mouth_masks + [(geo['hole'], '#FFFFFF')], region=region)
    name = {2: 'Juvenile', 3: 'Elder'}[stage]
    # ---- the sheet
    cw, chh = 380, 340
    W = 60 + 4 * (cw + 16) + 20
    sw = sec0.width
    H = 150 + 3 * (chh + 64) + sec0.height + 260
    img = Image.new('RGB', (W, H), BG)
    d = ImageDraw.Draw(img)
    d.text((40, 24), '%s: the head as a volume, and a mouth made from it' % name, font=font(40), fill=INK)
    d.text((40, 80), 'A study. Nothing in the game\'s rig has changed. Amber; the Brave kit face for the eyes, brows and '
           'cheeks (its painted mouth off).', font=font(19, False), fill=SUB)
    y = 130
    for label, row in (('1. The existing model by part (jaw closed: this is the original model)', row_parts),
                       ('2. The original, closed, with the kit eyes', row_closed),
                       ('3. Jaw open %d degrees (Shock): the same voxels, the lower head swung down' % J['open'], row_open)):
        d.text((40, y), label, font=font(22), fill=INK)
        for i, im in enumerate(row):
            x = 40 + i * (cw + 16)
            img.paste(im, (x, y + 34))
            d.text((x + 6, y + 34 + chh - 26), VIEWS[i][0], font=font(16, False), fill=SUB)
        y += chh + 64
    # legend
    lx = 40
    for k in ('skull', 'jaw', 'stretch', 'cheek', 'throat', 'neck', 'torso', 'legs', 'crest'):
        if stage == 2 and k == 'neck':
            continue
        c = PART_COL[k]
        d.rectangle((lx, y - 20, lx + 18, y - 2), fill=c, outline=INK)
        d.text((lx + 24, y - 22), PART_NAME[k], font=font(15, False), fill=SUB)
        lx += 34 + d.textlength(PART_NAME[k], font=font(15, False))
    y += 14
    d.text((40, y), '4. Cut down the middle (x = 0): closed, and open', font=font(22), fill=INK)
    y += 36
    img.paste(sec0, (40, y))
    img.paste(sec1, (60 + sw, y))
    dd = ImageDraw.Draw(img)
    (yh, zh), (yl, zl) = J['hinge'], J['lip']
    for k, (px, ox) in enumerate(((px0, 40), (px1, 60 + sw))):
        hx, hy = px(yh, zh)
        lx_, ly_ = px(yl, zl)
        ex, ey = px(yl + (yl - yh) / (zl - zh) * 2.0, zl + 2.0)
        dd.line((ox + hx, y + hy, ox + ex, y + ey), fill=INK, width=2)
        dd.ellipse((ox + hx - 9, y + hy - 9, ox + hx + 9, y + hy + 9), outline=INK, width=3)
        dd.ellipse((ox + hx - 3, y + hy - 3, ox + hx + 3, y + hy + 3), fill=INK)
        dd.text((ox + hx - 60, y + hy - 34), 'hinge', font=font(16), fill=INK)
        if k == 0:
            dd.text((ox + lx_ - 120, y + ly_ - 30), 'mouth plane', font=font(16), fill=INK)
        else:
            a = math.radians(J['open'])
            r = (zl - zh) * 14 * 0.85
            dd.arc((ox + hx - r, y + hy - r, ox + hx + r, y + hy + r), 0, J['open'], fill=INK, width=2)
            dd.text((ox + hx + r * 0.6, y + hy + 8), '%d deg' % J['open'], font=font(15), fill=INK)
    tx = 80 + 2 * sw
    notes = [
        'In the section (front to the right, up is up): blue skull, orange lower head, purple where the head',
        'and the neck or chest overlap, grey torso, green neck. Open: white is the mouth\'s air, dark red its',
        'back wall and inner cheeks.',
        '',
        'Existing voxels that become the jaw: %d (all of them reused; %d stay inside the neck/chest)' % (stats['jaw_voxels'], stats['collide']),
        'Added: %d voxels (the mouth\'s back wall and inner cheeks: %d, fangs: %d)' % (stats['added'], stats['added'] - stats['fangs'], stats['fangs']),
        'Recoloured surfaces (palate, tongue, inner cheeks): %d voxels; the mouth\'s air: %d' % (stats['recoloured'], stats['hole']),
        'jawOpen = 0 against the original model: %d voxels differ' % same,
    ]
    for i, t in enumerate(notes):
        dd.text((tx, y + i * 24), t, font=font(16, i >= 4), fill=INK if i >= 4 else SUB)
    img = img.crop((0, 0, W, max(y + sec0.height, y + len(notes) * 24) + 30))
    path = os.path.join(out_dir, 'jaw_study_%s.png' % name.lower())
    img.save(path, optimize=True)
    print(path, stats, 'jawOpen=0 differs by', same)
    return path


if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for s in (sys.argv[2:] or ['2', '3']):
        study(int(s), out)

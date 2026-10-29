"""Where a face lands on the model: each piece of the painted face is projected along the face's normal onto the
first surface it meets (decals.project_canvas), and nothing stops that being the neck, chest or a leg. This tints
every piece of the face that lands off the head red and renders it front, three-quarter (the cinematic camera) and
side, and counts it.

    python3 face_spill.py OUT.png [expr] [stage ...]
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import charrender as CR                                           # noqa: E402
from characters import build                                      # noqa: E402
from palettes import palette                                      # noqa: E402
from voxel import Camera                                          # noqa: E402
from turnarounds import font                                      # noqa: E402

# the head's own volume per stage (the egg shapes characters.build_* makes it from), a little grown
HEADS = {2: [((0, 17.4, 7.0), 11.4, 10.0, 9.8, 9.6, 2.9)],
         3: [((0, 17.0, 16.0), 9.8, 8.4, 7.6, 10.2, 2.7), ((0, 15.0, 23.0), 7.4, 5.4, 5.0, 5.8, 2.6)]}
VIEWS = [('front', Camera(yaw=0, pitch=0)), ('three-quarter (the cinematic)', Camera(yaw=-32, pitch=-7)),
         ('side', Camera(yaw=-90, pitch=0))]
RED = np.array([0.93, 0.1, 0.1], np.float32)


def on_head(stage, P, grow=0.8):
    ok = np.zeros(len(P), bool)
    for (cx, cy, cz), rx, ryt, ryb, rz, p in HEADS[stage]:
        ry = np.where(P[:, 1] >= cy, ryt + grow, ryb + grow)
        ok |= (np.abs((P[:, 0] - cx) / (rx + grow)) ** p + np.abs((P[:, 1] - cy) / ry) ** p
               + np.abs((P[:, 2] - cz) / (rz + grow)) ** p) <= 1.0
    return ok


def probe_quads(ch, big=None):
    """the whole face canvas (or, with [big], the kit face with its mouth scaled up by [big] about the mouth's
    top), projected the way faces are"""
    import face_kit as FK
    from decals import Canvas, project_canvas
    u0, u1, v0, v1 = FK.extent(ch)
    cv = Canvas(u0, u1, v0 - 6, v1, cell=0.07)
    if big is None:
        chk = ((np.floor(cv.U) + np.floor(cv.V)) % 2).astype(bool)
        cv.paint(np.ones(cv.U.shape, bool), (217.0, 217.0, 217.0), lit=0.0)
        cv.paint(chk, (180.0, 180.0, 180.0), lit=0.0)
    else:
        from characters import paint_face
        cv2 = Canvas(u0, u1, v0 - 6, v1, cell=0.07)
        paint_face(ch, cv2, palette('amber'), 'shout')
        cols = cv2.rgb.reshape(-1, 3)
        mi = np.array([int(palette('amber')['mouth_in'][i:i + 2], 16) for i in (1, 3, 5)], np.float32)
        isd = lambda c: (np.abs(c - np.array([0x71, 0x2E, 0x37], np.float32) / (1 if cv2.rgb.max() > 1.5 else 255)).sum(-1) < 0.2 * (255 if cv2.rgb.max() > 1.5 else 1))
        # the mouth: the kit's mouth colours, wherever they are
        mouth = np.zeros(cv2.U.shape, bool)
        for hexc in ('#712E37', '#963C42', '#8E4444', '#E98D87', '#FFFBF2'):
            c = np.array([int(hexc[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / (1 if cv2.rgb.max() > 1.5 else 255)
            mouth |= (np.abs(cv2.rgb - c).sum(-1) < (6 if cv2.rgb.max() > 1.5 else 0.03)) & (cv2.a > 0)
        top = cv2.V[mouth].max()
        # scale the mouth about its top centre
        for j in range(cv.U.shape[0]):
            pass
        U, V = cv.U, cv.V
        su, sv = U / big, top - (top - V) / big
        iu = np.clip(((su - u0) / 0.07).astype(int), 0, cv2.U.shape[1] - 1)
        iv = np.clip(((sv - (v0 - 6)) / 0.07).astype(int), 0, cv2.U.shape[0] - 1)
        cv.rgb[:] = cv2.rgb
        cv.a[:] = cv2.a
        cv.lit[:] = cv2.lit
        cv.a[mouth] = 0
        mm = mouth[iv, iu]
        cv.rgb[mm] = cv2.rgb[iv, iu][mm]
        cv.a[mm] = 1.0
        cv.lit[mm] = 0.0
    kit_surf = CR.surface_for(ch, CR.KIT_ISO)
    return project_canvas(kit_surf, ch.face, cv, CR.FACE_MID, lift=CR.KIT_LIFT)


def main(out, expr='shout', stages=(2, 3)):
    pal = palette('amber')
    rows = []
    for st in stages:
        ch = build(st)
        if expr == 'probe':
            q = probe_quads(ch)
        elif expr.startswith('big'):
            q = probe_quads(ch, float(expr[3:]))
        else:
            q = CR.face_quads(ch, pal, 'amber', expr)
        CR._quad_cache[(id(ch.model), 'amber', expr)] = q
        cen = np.array([d.center for d in q])
        off = ~on_head(st, cen)
        scale = 255 if max(np.max(d.color) for d in q) > 1.5 else 1
        for d, o in zip(q, off):
            if o:
                d.color = RED.copy() * scale
            elif expr == 'probe':
                d.color = np.array([0.35, 0.78, 0.4], np.float32) * scale * (0.85 + 0.15 * (np.mean(d.color) / scale > 0.75))
        n_off = int(off.sum())
        print('stage %d %s: %d of %d face pieces land off the head (%.0f%%); lowest landing at y=%.1f (head bottom ~%.1f)'
              % (st, expr, n_off, len(q), 100 * n_off / len(q), cen[off][:, 1].min() if n_off else float('nan'),
                 HEADS[st][0][0][1] - HEADS[st][0][3]))
        cells = []
        for name, cam in VIEWS:
            r = CR.render_char(ch, 'amber', expr, cam, 460, 460)   # (the face from the cache above)
            im = Image.new('RGB', (460, 460), (250, 240, 228))
            c = Image.fromarray(r.rgba)
            im.paste(c, (0, 0), c)
            cells.append((name, im, n_off))
        rows.append((st, cells))
    W, H = 60 + 3 * 480, 120 + len(rows) * 540
    img = Image.new('RGB', (W, H), (250, 240, 228))
    d = ImageDraw.Draw(img)
    d.text((40, 24), 'Where the open-mouth face lands (red: off the head)', font=font(36), fill=(52, 36, 30))
    d.text((40, 76), 'Kit "%s" face on the unchanged models, Amber. Projected along the face normal onto the first '
           'surface it meets.' % expr, font=font(19, False), fill=(120, 96, 82))
    for i, (st, cells) in enumerate(rows):
        y = 120 + i * 540
        d.text((40, y), {2: 'Juvenile', 3: 'Elder'}[st], font=font(28), fill=(52, 36, 30))
        for j, (name, im, n_off) in enumerate(cells):
            img.paste(im, (40 + j * 480, y + 44))
            d.text((40 + j * 480, y + 44 + 466), name, font=font(18, False), fill=(120, 96, 82))
    img.save(out)
    print(out)


if __name__ == '__main__':
    a = sys.argv
    main(a[1], a[2] if len(a) > 2 else 'shout', tuple(int(s) for s in a[3:]) or (2, 3))

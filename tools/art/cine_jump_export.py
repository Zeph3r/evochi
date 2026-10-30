"""Your Evochi's leap clear of the Sentinel's beam (cine_jump.py) as game art: per stage, the leap at 30 fps from
the entrance's camera, in every colour, with the restored Brave faces; each worn piece over every frame (worn as
posed, wear_pose.py); and wilds_jump.json with where the body is over the ground each frame, its shadow, each foot's
contact, where the beam lands and when.

    python3 cine_jump_export.py OUT_DIR [stage ...]

Positions in the JSON are cell pixels measured from where the Evochi stood at the start (its ground point, `ground`
in a cell): a frame's cell is drawn with its ground point at `root[i]` from there; the shadow, the feet's footprints
and the beam's strike likewise. The game draws a cell at  from + (root[i] - ground) * k  for a cell scale k.
"""
from __future__ import annotations

import json
import math
import os
import sys
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cine_jump as J                                             # noqa: E402
from palettes import VARIANT_ORDER                                # noqa: E402
from voxel import Fit, model_extent_points, project_px            # noqa: E402

FPS = 30
CELL_H = 480
COLS = 6
FACES = 'restored'
CAM = J.CAM


def times():
    return [round(i / FPS, 4) for i in range(int(J.END * FPS) + 1)]


def _fit(stage):
    """one framing for every frame: the posed body at its own origin, all of its frames"""
    J.use_stage(stage)
    pts = []
    for t in times()[::3] + [J.T_LAND, 0.77, 0.83]:
        p = J.pose_at(t)
        pts.append(model_extent_points(J.character(p).model))
    pts = np.concatenate(pts)
    sx, sy, _ = CAM.project(pts)
    s = CELL_H * 0.94 / (sy.max() - sy.min())
    w = int(math.ceil((sx.max() - sx.min()) * s / 0.94 / 2) * 2) + 8
    ox = w / 2 - s * (sx.max() + sx.min()) / 2
    oy = CELL_H / 2 - s * (sy.max() + sy.min()) / 2
    return Fit(scale=s, ox=ox, oy=oy, w=w, h=CELL_H)


def _px(fit, pts):
    return project_px(CAM, fit, np.asarray(pts, float).reshape(-1, 3))


def _frame(args):
    """one frame in every colour: (stage, i, t, fit) -> {palette: rgba}"""
    stage, i, t, fit = args
    import charrender
    import face_kit
    J.use_stage(stage)
    p = J.pose_at(t)
    p['jaw'] = J.jaw_at(t, FACES, p['jaw'])
    ch = J.character(p)
    out = {}
    for v in VARIANT_ORDER:
        lay = None
        for state, w in J.faces_at(t, FACES):
            charrender._quad_cache.clear()
            r = charrender.render_char(ch, v, J.face_name(state, p['jaw']), CAM, fit.w, fit.h, fit=fit)
            L = r.rgba.astype(np.float32)
            lay = L if lay is None else lay * (1 - w) + L * w
        out[v] = lay.astype(np.uint8)
    charrender._surf_cache.clear()
    charrender._quad_cache.clear()
    face_kit._raster.cache_clear()
    return stage, i, out


def _wear(args):
    """every worn piece over one frame (only what shows of it), as posed"""
    stage, i, t, fit = args
    import charrender
    import face_kit
    from accessories import WEARABLES
    from wear_pose import posed_wear
    J.use_stage(stage)
    p = J.pose_at(t)
    p['jaw'] = J.jaw_at(t, FACES, p['jaw'])
    ch = J.character(p)
    face = J.face_name(J.faces_at(t, FACES)[-1][0], p['jaw'])
    body = charrender.render_char(ch, 'amber', face, CAM, fit.w, fit.h, fit=fit)
    ab = body.rgba[..., 3] / 255.0
    out = {}
    for k in WEARABLES:
        comb = charrender.render_char(ch, 'amber', face, CAM, fit.w, fit.h, fit=fit, extra_model=posed_wear(ch, k), cov_prefix='acc_')
        ac = comb.rgba[..., 3] / 255.0
        extra = np.clip((ac - ab) / np.maximum(1 - ab, 1e-3), 0, 1)
        a = np.clip(np.maximum(comb.cov, extra) * 1.05, 0, 1)
        ov = comb.rgba.copy()
        ov[..., 3] = (a * 255).astype(np.uint8)
        out[k] = ov
        charrender._quad_cache.clear()
    charrender._surf_cache.clear()
    face_kit._raster.cache_clear()
    return stage, i, out


def _motion(stage, fit):
    """per frame: the body's place, its shadow, its feet on the ground; where the beam lands"""
    J.use_stage(stage)
    G = _px(fit, [[0, 0, 0]])[0]
    root, shadow, feet = [], [], []
    for t in times():
        r = J.root_at(t)
        root.append((_px(fit, [r])[0] - G).round(1).tolist())
        p = J.pose_at(t)
        M = J.character(p).model
        # the shadow: under the body's middle, on the ground; how high the body is over it
        piv = J.PIVOT + r
        low = J.low_foot(M) + r[1]
        shadow.append((_px(fit, [[piv[0], 0.0, piv[2]]])[0] - G).round(1).tolist() + [round(float(max(0.0, low)), 2)])
        P = J._feet_pts(M) + r
        zmid = (P[:, 2].min() + P[:, 2].max()) / 2
        fl = []
        for front in (True, False):
            for side in (-1, 1):
                sel = ((P[:, 2] > zmid) == front) & ((P[:, 0] > 0) == (side > 0))
                if not sel.any():
                    fl.append([0, 0, 0, 0, 99])
                    continue
                Q = P[sel]
                c = np.array([Q[:, 0].mean(), 0.0, Q[:, 2].mean()])
                a, b = _px(fit, [c + [-(np.ptp(Q[:, 0]) / 2 + 0.6), 0, 0], c + [np.ptp(Q[:, 0]) / 2 + 0.6, 0, 0]])
                e, f = _px(fit, [c + [0, 0, -(np.ptp(Q[:, 2]) / 2 + 0.6)], c + [0, 0, np.ptp(Q[:, 2]) / 2 + 0.6]])
                cc = _px(fit, [c])[0] - G
                rx = max(abs(b[0] - a[0]), abs(f[0] - e[0])) / 2
                ry = max(abs(b[1] - a[1]), abs(f[1] - e[1])) / 2
                fl.append([round(float(cc[0]), 1), round(float(cc[1]), 1), round(float(rx), 1), round(float(ry), 1),
                           round(float(Q[:, 1].min() - 0.5 / M.res), 2)])
        feet.append(fl)
    strike = (_px(fit, [J.STRIKE0])[0] - G).round(1).tolist()
    d = _px(fit, [J.EYES])[0] - _px(fit, [J.STRIKE0])[0]
    d = (d / np.linalg.norm(d)).round(4).tolist()
    return G, root, shadow, feet, strike, d


def _sheet(cells, w, h):
    rows = (len(cells) + COLS - 1) // COLS
    A = np.zeros((rows * h, COLS * w, 4), np.uint8)
    for i, c in enumerate(cells):
        r, k = divmod(i, COLS)
        A[r * h:(r + 1) * h, k * w:(k + 1) * w] = c
    return Image.fromarray(A, 'RGBA')


def main(out, stages):
    from accessories import WEARABLES
    os.makedirs(out, exist_ok=True)
    mp = os.path.join(out, 'wilds_jump.json')
    meta = json.load(open(mp)) if os.path.exists(mp) else {}
    ts = times()
    meta.update({'cols': COLS, 'fps': FPS, 'yaw': CAM.yaw, 'pitch': CAM.pitch,
                 'beam': {'aim': J.AIM_ON, 'on': J.BEAM_ON, 'hit': J.BEAM_HIT, 'off': J.BEAM_OFF},
                 'land': J.T_LAND, 'off': J.T_OFF})
    workers = int(os.environ.get('JOBS', '2'))
    for stage in stages:
        sid = 's%02d' % stage
        fit = _fit(stage)
        G, root, shadow, feet, strike, beam_dir = _motion(stage, fit)
        jobs = [(stage, i, t, fit) for i, t in enumerate(ts)]
        with ProcessPoolExecutor(workers) as ex:
            frames = sorted(ex.map(_frame, jobs), key=lambda r: r[1])
        st = {'w': fit.w, 'h': fit.h, 'n': len(ts), 'times': ts, 'end': J.END, 'ground': G.round(1).tolist(),
              'root': root, 'shadow': shadow, 'feet': feet, 'strike': strike, 'beamDir': beam_dir,
              'apex': J.H_APEX, 'sheets': {}, 'wear': {}}
        for v in VARIANT_ORDER:
            fn = 'jump_%s_%s.webp' % (sid, v)
            _sheet([f[2][v] for f in frames], fit.w, fit.h).save(os.path.join(out, fn), quality=88, method=6)
            st['sheets'][v] = fn
            print(fn, os.path.getsize(os.path.join(out, fn)) // 1024, 'KB', flush=True)
        del frames
        with ProcessPoolExecutor(workers) as ex:
            wears = sorted(ex.map(_wear, jobs), key=lambda r: r[1])
        for k in WEARABLES:
            fn = 'jump_%s_wear_%s.webp' % (sid, k)
            _sheet([w[2][k] for w in wears], fit.w, fit.h).save(os.path.join(out, fn), quality=88, method=6)
            st['wear'][k] = fn
        print(sid, 'wear done', flush=True)
        meta[sid] = st
        json.dump(meta, open(mp, 'w'), indent=1)
    print(mp, flush=True)


if __name__ == '__main__':
    a = [x for x in sys.argv[1:] if not x.startswith('--')]
    main(a[0], [int(x) for x in a[1:]] or [1, 2, 3])

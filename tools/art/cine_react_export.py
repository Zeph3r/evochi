"""The boss entrances' Evochi reaction (cine_react.py: Shock -> Strain -> Resolve) as game art: per stage, 17-19
frames sampled where the motion is, from the entrance's camera (a touch higher, so it stands on the ground), in
every colour; and the Evochi from behind
(over its shoulder, looking at the guardian) for the wide shots.

    python3 cine_react_export.py OUT_DIR [stage ...]

Writes OUT_DIR/react_sNN_<palette>.webp (the frames in a grid, COLS across), react_sNN_back_<palette>.webp and
wilds_react.json: per stage the cell size, each frame's time (s), the reaction's length, where the ground is in
a cell, where each foot meets the ground in each frame (for its contact shadows), the sheets; the same for the
back view.
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
import cine_react as CR                                           # noqa: E402
from charrender import render_char                                # noqa: E402
from palettes import VARIANT_ORDER                                # noqa: E402
from voxel import Camera, fit_camera, model_extent_points, project_px   # noqa: E402

CELL_H = 560
COLS = 5
# the entrance's camera, but from a touch above its feet (cine_react.GAME looks up from below the ground, which
# shows the soles and leaves it no floor to stand on)
CAM = Camera(yaw=-32, pitch=5)
BACK = Camera(yaw=-145, pitch=-6)        # behind it and to its left: over its shoulder, toward the guardian
TIMES = {1: [0.0, 0.03, 0.05, 0.09, 0.13, 0.18, 0.24, 0.32, 0.40, 0.46, 0.53, 0.80, 1.05, 1.12, 1.18, 1.24, 1.30, 1.42, 1.70],
         2: [0.0, 0.03, 0.06, 0.10, 0.15, 0.20, 0.26, 0.32, 0.40, 0.50, 0.58, 0.85, 1.15, 1.24, 1.32, 1.40, 1.52, 1.80],
         3: [0.0, 0.04, 0.08, 0.13, 0.19, 0.26, 0.32, 0.38, 0.48, 0.58, 0.66, 0.95, 1.30, 1.40, 1.50, 1.62, 2.00]}


def _fit(cam, models, h):
    pts = np.concatenate([m if isinstance(m, np.ndarray) else model_extent_points(m) for m in models])
    sx, sy, _ = cam.project(pts)
    aspect = (sx.max() - sx.min()) / max(sy.max() - sy.min(), 1e-6)
    w = int(math.ceil(h * aspect * 1.0 / 2) * 2) + 8
    return fit_camera(cam, pts, w, h, margin=0.04)


def _feet(model, cam, fit):
    """where each foot meets the ground, in the cell's pixels: per foot (near front, far front, near back, far back)
    [x, y, rx, ry, lift]: the footprint's centre on the ground and its radii as seen, and how far the foot is off
    the ground (world units; 0 planted)"""
    ids = [model.ids[n] for n in ('feet', 'feet_shade', 'claw') if n in model.ids]
    F = np.isin(model.m, ids)
    X, Y, Z = model.X[F], model.Y[F], model.Z[F]
    zmid = (Z.min() + Z.max()) / 2
    out = []
    for front in (True, False):
        for near in (True, False):
            k = ((X < 0) == near) & ((Z > zmid) == front)
            if not k.any():
                out.append(None)
                continue
            cx, cz = (X[k].min() + X[k].max()) / 2, (Z[k].min() + Z[k].max()) / 2
            r = max(X[k].max() - X[k].min(), Z[k].max() - Z[k].min()) / 2
            a = np.linspace(0, 2 * np.pi, 16, endpoint=False)
            ring = np.stack([cx + r * np.cos(a), np.zeros_like(a), cz + r * np.sin(a)], -1)
            px = project_px(cam, fit, ring)[:, :2]
            c = project_px(cam, fit, np.array([[cx, 0.0, cz]]))[0][:2]
            out.append([round(float(c[0]), 1), round(float(c[1]), 1), round(float(np.ptp(px[:, 0]) / 2), 1),
                        round(float(np.ptp(px[:, 1]) / 2), 1), round(float(max(0.0, Y[k].min() - 0.25)), 2)])
    return out


def _frame(args):
    stage, t, fit, cam = args
    pose, face = CR.pose_at(stage, t)
    ch = CR.character(stage, pose)
    expr = CR.face_expr(face, pose)
    out = [render_char(ch, v, expr, cam, fit.w, fit.h, fit=fit).rgba for v in VARIANT_ORDER]
    feet = _feet(ch.model, cam, fit)
    # every frame is a new model: let its surface and face pieces go (the renderer would keep them all)
    import charrender
    import face_kit
    charrender._surf_cache.clear()
    charrender._quad_cache.clear()
    face_kit._raster.cache_clear()      # the face rasters too: a squashed body's face is a new one each frame
    CR._built.clear()
    return out, feet


def main(out, stages):
    os.makedirs(out, exist_ok=True)
    mp = os.path.join(out, 'wilds_react.json')
    meta = json.load(open(mp)) if os.path.exists(mp) else {}
    meta['cols'] = COLS
    for stage in stages:
        sid = 's%02d' % stage
        times = TIMES[stage]
        # each pose's extent, one model at a time (holding them all runs out of memory)
        ext = []
        for t in times:
            ext.append(model_extent_points(CR.character(stage, CR.pose_at(stage, t)[0]).model))
            CR._built.clear()
        fit = _fit(CAM, ext, CELL_H)
        rest = CR.character(stage, {})
        bfit = _fit(BACK, [rest.model], CELL_H)
        CR._built.clear()
        with ProcessPoolExecutor(2) as ex:
            done = list(ex.map(_frame, [(stage, t, fit, CAM) for t in times]))
            back = list(ex.map(_frame, [(stage, 0.0, bfit, BACK)]))[0][0]
        frames = [f for f, _ in done]
        feet = [ft for _, ft in done]
        rows = (len(times) + COLS - 1) // COLS
        st = {'w': fit.w, 'h': fit.h, 'n': len(times), 'times': times, 'end': CR.KEYS[stage][-1][0],
              'ground': project_px(CAM, fit, rest.anchors['ground'])[0].round(1).tolist(), 'feet': feet, 'sheets': {},
              'back': {'w': bfit.w, 'h': bfit.h, 'ground': project_px(BACK, bfit, rest.anchors['ground'])[0].round(1).tolist(),
                       'sheets': {}}}
        for vi, v in enumerate(VARIANT_ORDER):
            grid = np.zeros((rows * fit.h, COLS * fit.w, 4), np.uint8)
            for i, fr in enumerate(frames):
                r, c = divmod(i, COLS)
                grid[r * fit.h:(r + 1) * fit.h, c * fit.w:(c + 1) * fit.w] = fr[vi]
            fn = f'react_{sid}_{v}.webp'
            Image.fromarray(grid, 'RGBA').save(os.path.join(out, fn), quality=86, method=6)
            st['sheets'][v] = fn
            bn = f'react_{sid}_back_{v}.webp'
            Image.fromarray(back[vi], 'RGBA').save(os.path.join(out, bn), quality=86, method=6)
            st['back']['sheets'][v] = bn
            print(fn, os.path.getsize(os.path.join(out, fn)) // 1024, 'KB', bn, os.path.getsize(os.path.join(out, bn)) // 1024, 'KB', flush=True)
        meta[sid] = st
        json.dump(meta, open(mp, 'w'), indent=1)


if __name__ == '__main__':
    main(sys.argv[1], [int(a) for a in sys.argv[2:]] or [1, 2, 3])

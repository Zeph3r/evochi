"""Whiskers: thin 3D strands growing out of a character (Sher's muzzle and brows). Voxels are too coarse
for them, so they are curves in model space drawn as thin anti-aliased lines after the voxels render,
each bit depth-tested against the rendered model: they emerge from the skin, cross in front of the
face, pass behind the head when it turns away, and reach past the silhouette like the drawing's.

A character opts in with `ch.whiskers = [Whisker(...), ...]`; charrender.render_char and the villager
pipeline (village_npc_render.finish_npc, head layers) draw them; wilds_blend.py turns them into curves.
"""
from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

from voxel import hexrgb


@dataclass
class Whisker:
    root: tuple          # model units, a little inside the skin (the strand emerges from it)
    direction: tuple     # where it points
    length: float
    sag: float = 0.4     # how far the tip droops (model units)
    width: float = 0.11  # x the fit scale, at the root (it thins to half at the tip)
    color: str = '#3E3230'
    alpha: float = 0.95

    def points(self, n=16):
        d = np.asarray(self.direction, np.float64)
        d /= np.linalg.norm(d)
        t = np.linspace(0, 1, n)[:, None]
        return np.asarray(self.root, np.float64) + d * self.length * t - np.array([0.0, self.sag, 0.0]) * t ** 2


def coverage(whiskers, depth, cam, fit, ss=4, eps=0.35):
    """Per pixel: how much whisker covers it (0..1) and its colour, depth-tested against `depth` (the
    rendered model's final-resolution depth, inf where empty)."""
    h, w = depth.shape
    cov = np.zeros((h * ss, w * ss), np.float32)
    col = np.zeros((h * ss, w * ss, 3), np.float32)
    dfull = np.repeat(np.repeat(depth, ss, 0), ss, 1)
    for wk in whiskers:
        P = wk.points()
        sx, sy, z = cam.project(P)
        px = (sx * fit.scale + fit.ox) * ss
        py = (sy * fit.scale + fit.oy) * ss
        c = hexrgb(wk.color)
        n = len(P)
        for i in range(n - 1):
            t = i / (n - 1)
            th = max(1, int(round(wk.width * fit.scale * ss * (1 - 0.5 * t))))
            x0, y0, x1, y1 = px[i], py[i], px[i + 1], py[i + 1]
            bx0, by0 = int(max(0, min(x0, x1) - th - 2)), int(max(0, min(y0, y1) - th - 2))
            bx1, by1 = int(min(w * ss, max(x0, x1) + th + 3)), int(min(h * ss, max(y0, y1) + th + 3))
            if bx1 <= bx0 or by1 <= by0:
                continue
            tmp = np.zeros((by1 - by0, bx1 - bx0), np.uint8)
            cv2.line(tmp, (int(round(x0 - bx0)), int(round(y0 - by0))), (int(round(x1 - bx0)), int(round(y1 - by0))),
                     255, th, cv2.LINE_AA)
            m = tmp.astype(np.float32) / 255.0
            # depth along the segment, against the model's
            yy, xx = np.mgrid[by0:by1, bx0:bx1]
            ab = np.array([x1 - x0, y1 - y0])
            L2 = max(ab @ ab, 1e-9)
            u = np.clip(((xx - x0) * ab[0] + (yy - y0) * ab[1]) / L2, 0, 1)
            zl = z[i] + (z[i + 1] - z[i]) * u
            dm = dfull[by0:by1, bx0:bx1]
            vis = (zl < dm + eps) | ~np.isfinite(dm)
            m = m * vis * wk.alpha
            sl = cov[by0:by1, bx0:bx1]
            upd = m > sl
            sl[upd] = m[upd]
            col[by0:by1, bx0:bx1][upd] = c
    a = cov.reshape(h, ss, w, ss).mean((1, 3))
    cs = (col * cov[..., None]).reshape(h, ss, w, ss, 3).sum((1, 3)) / np.maximum(cov.reshape(h, ss, w, ss).sum((1, 3))[..., None], 1e-6)
    return a, cs


def over(rgba, a, c):
    """whiskers over an RGBA image (uint8 0..255 or float 0..1), same type back"""
    is8 = rgba.dtype == np.uint8
    f = rgba.astype(np.float32) / (255.0 if is8 else 1.0)
    cc = c / 255.0
    base_a = f[..., 3]
    out_a = a + base_a * (1 - a)
    out_c = (cc * a[..., None] + f[..., :3] * (base_a * (1 - a))[..., None]) / np.maximum(out_a[..., None], 1e-6)
    out = np.dstack([out_c, out_a])
    return np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8) if is8 else out.astype(np.float32)


def draw(rgba, depth, cam, fit, whiskers):
    if not whiskers:
        return rgba
    a, c = coverage(whiskers, depth, cam, fit)
    return over(rgba, a, c)

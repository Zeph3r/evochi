"""Surface decals: painted features (eyes, mouths, cheeks, scale patterns)
projected onto a smoothed version of a voxel model's surface.

Decals are authored on a small 2D canvas in "face space" (u = right, v = up,
units = model design units) and projected along -n onto the surface. Each run
of identically coloured cells becomes one quad, so a decal stays crisp at any
render size and camera angle.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
from scipy import ndimage

from voxel import Model, Camera, Light, Poly, hexrgb


class Surface:
    def __init__(self, model: Model, sigma=0.9, iso=0.5):
        self.model = model
        occ = (model.m > 0).astype(np.float32)
        self.b = ndimage.gaussian_filter(occ, sigma * model.res, mode='constant')
        g = np.gradient(self.b)
        self.g = [x.astype(np.float32) for x in g]
        self.iso = iso

    def idx(self, P):
        P = np.asarray(P, np.float64)
        return (P * self.model.res - self.model.lo - 0.5).T

    def sample(self, P):
        return ndimage.map_coordinates(self.b, self.idx(P), order=1, mode='constant')

    def normal(self, P):
        ii = self.idx(P)
        n = -np.stack([ndimage.map_coordinates(g, ii, order=1, mode='constant') for g in self.g], -1)
        return n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)

    def cast(self, O, D, tmax=30.0, step=0.05):
        """March from O along D until the field reaches iso. Returns hit points (NaN if miss)."""
        O = np.asarray(O, np.float64)
        D = np.asarray(D, np.float64)
        n = len(O)
        hit = np.full((n, 3), np.nan)
        t = np.zeros(n)
        prev = self.sample(O)
        active = np.ones(n, bool)
        steps = int(tmax / step)
        for _ in range(steps):
            if not active.any():
                break
            ia = np.where(active)[0]
            t[ia] += step
            P = O[ia] + D[ia] * t[ia, None]
            v = self.sample(P)
            crossed = v >= self.iso
            if crossed.any():
                ic = ia[crossed]
                # linear refine between previous and current sample
                pv = prev[ic]
                cv = v[crossed]
                frac = np.clip((self.iso - pv) / np.maximum(cv - pv, 1e-6), 0, 1)
                tt = t[ic] - step + frac * step
                hit[ic] = O[ic] + D[ic] * tt[:, None]
                active[ic] = False
            prev[ia[~crossed]] = v[~crossed]
        return hit


@dataclass
class Frame:
    center: tuple          # point inside the model (rays start at center + n*reach)
    n: tuple               # outward direction of the face
    up: tuple = (0, 1, 0)
    reach: float = 20.0

    def basis(self):
        n = np.array(self.n, np.float64)
        n /= np.linalg.norm(n)
        up = np.array(self.up, np.float64)
        u = np.cross(up, n)
        if np.linalg.norm(u) < 1e-6:
            u = np.array([1.0, 0, 0])
        u /= np.linalg.norm(u)
        v = np.cross(n, u)
        return u, v, n


class Canvas:
    """RGBA paint canvas in face space."""

    def __init__(self, u0, u1, v0, v1, cell=0.1):
        self.u0, self.v0, self.cell = u0, v0, cell
        nu = int(math.ceil((u1 - u0) / cell))
        nv = int(math.ceil((v1 - v0) / cell))
        us = u0 + (np.arange(nu) + 0.5) * cell
        vs = v0 + (np.arange(nv) + 0.5) * cell
        self.U, self.V = np.meshgrid(us, vs, indexing='xy')   # shape (nv, nu)
        self.rgb = np.zeros((nv, nu, 3), np.float32)
        self.a = np.zeros((nv, nu), np.float32)
        self.lit = np.zeros((nv, nu), np.float32)  # 1 = apply body lighting

    def paint(self, mask, col, alpha=1.0, lit=1.0):
        c = hexrgb(col) if isinstance(col, str) else np.asarray(col, np.float32)
        if np.ndim(c) == 1:
            self.rgb[mask] = c
        else:
            self.rgb[mask] = c[mask]
        self.a[mask] = alpha
        self.lit[mask] = lit

    # shape masks -------------------------------------------------------
    def m_rect(self, cu, cv, w, h, r=0.0):
        du = np.abs(self.U - cu) - (w / 2 - r)
        dv = np.abs(self.V - cv) - (h / 2 - r)
        out = np.sqrt(np.maximum(du, 0) ** 2 + np.maximum(dv, 0) ** 2)
        return out <= r + 1e-9

    def m_ellipse(self, cu, cv, ru, rv):
        return ((self.U - cu) / ru) ** 2 + ((self.V - cv) / rv) ** 2 <= 1

    def m_poly(self, pts):
        from matplotlib.path import Path
        p = Path(np.asarray(pts))
        flat = np.stack([self.U.ravel(), self.V.ravel()], 1)
        return p.contains_points(flat).reshape(self.U.shape)

    def m_stroke(self, pts, width):
        pts = np.asarray(pts, np.float64)
        m = np.zeros(self.U.shape, bool)
        r = width / 2
        for a, b in zip(pts[:-1], pts[1:]):
            ab = b - a
            L2 = max(ab @ ab, 1e-9)
            t = np.clip(((self.U - a[0]) * ab[0] + (self.V - a[1]) * ab[1]) / L2, 0, 1)
            px = a[0] + t * ab[0]
            py = a[1] + t * ab[1]
            m |= (self.U - px) ** 2 + (self.V - py) ** 2 <= r * r
        return m

    def m_arc(self, cu, cv, ru, rv, a0, a1, width, n=24):
        th = np.linspace(math.radians(a0), math.radians(a1), n)
        pts = np.stack([cu + ru * np.cos(th), cv + rv * np.sin(th)], 1)
        return self.m_stroke(pts, width)

    def m_diamond(self, cu, cv, r):
        return np.abs(self.U - cu) + np.abs(self.V - cv) <= r

    def bevel_diamond(self, cu, cv, r, col, hi, lo, bevel=0.35, lit=1.0):
        """Faceted gem-like diamond: lighter upper-left facets, darker lower-right."""
        du, dv = self.U - cu, self.V - cv
        d = np.abs(du) + np.abs(dv)
        m = d <= r
        self.paint(m, col, lit=lit)
        edge = m & (d > r - bevel)
        tl = edge & (dv > 0) & (du <= 0)
        tr = edge & (dv > 0) & (du > 0)
        bl = edge & (dv <= 0) & (du <= 0)
        br = edge & (dv <= 0) & (du > 0)
        self.paint(tl, hi, lit=lit)
        self.paint(tr, mix(col, hi, 0.5), lit=lit)
        self.paint(bl, mix(col, lo, 0.5), lit=lit)
        self.paint(br, lo, lit=lit)

    def bevel_rect(self, cu, cv, w, h, col, hi, lo, bevel=0.3, lit=1.0):
        du, dv = self.U - cu, self.V - cv
        m = (np.abs(du) <= w / 2) & (np.abs(dv) <= h / 2)
        self.paint(m, col, lit=lit)
        top = m & (dv > h / 2 - bevel)
        left = m & (du < -w / 2 + bevel)
        right = m & (du > w / 2 - bevel)
        bot = m & (dv < -h / 2 + bevel)
        self.paint(left, mix(col, hi, 0.6), lit=lit)
        self.paint(top, hi, lit=lit)
        self.paint(right, mix(col, lo, 0.6), lit=lit)
        self.paint(bot, lo, lit=lit)


def mix(a, b, t):
    a = hexrgb(a) if isinstance(a, str) else np.asarray(a, np.float32)
    b = hexrgb(b) if isinstance(b, str) else np.asarray(b, np.float32)
    return a * (1 - t) + b * t


def to_hex(c):
    c = np.clip(np.round(np.asarray(c)), 0, 255).astype(int)
    return '#%02X%02X%02X' % tuple(c)


@dataclass
class DecalQuad:
    pts: np.ndarray       # (4,3)
    color: np.ndarray
    lit: float
    alpha: float
    center: np.ndarray
    normal: np.ndarray
    mid: int


def project_canvas(surf: Surface, frame: Frame, canvas: Canvas, mid: int, lift=0.04):
    """Convert painted canvas into 3D quads lying on the surface."""
    u_ax, v_ax, n_ax = frame.basis()
    c = np.array(frame.center, np.float64)
    rows = []
    nv, nu = canvas.a.shape
    cell = canvas.cell
    quads = []
    for j in range(nv):
        row_a = canvas.a[j]
        if not (row_a > 0).any():
            continue
        i = 0
        while i < nu:
            if row_a[i] <= 0:
                i += 1
                continue
            k = i
            key = (tuple(canvas.rgb[j, i]), row_a[i], canvas.lit[j, i])
            while k + 1 < nu and row_a[k + 1] > 0 and (tuple(canvas.rgb[j, k + 1]), row_a[k + 1],
                                                       canvas.lit[j, k + 1]) == key:
                k += 1
            u0 = canvas.U[j, i] - cell / 2
            u1 = canvas.U[j, k] + cell / 2
            v0 = canvas.V[j, i] - cell / 2
            v1 = canvas.V[j, i] + cell / 2
            quads.append((u0, u1, v0, v1, canvas.rgb[j, i].copy(), row_a[i], canvas.lit[j, i]))
            i = k + 1
    if not quads:
        return []
    # corner sampling: subdivide long runs so they follow curvature
    out_pts = []
    meta = []
    for (u0, u1, v0, v1, col, a, lit) in quads:
        nseg = max(1, int(math.ceil((u1 - u0) / 0.6)))
        us = np.linspace(u0, u1, nseg + 1)
        for s in range(nseg):
            out_pts.append([(us[s], v0), (us[s + 1], v0), (us[s + 1], v1), (us[s], v1)])
            meta.append((col, a, lit))
    UV = np.array(out_pts).reshape(-1, 2)
    O = c[None, :] + UV[:, :1] * u_ax + UV[:, 1:2] * v_ax + n_ax * frame.reach
    D = np.repeat(-n_ax[None, :], len(O), 0)
    H = surf.cast(O, D, tmax=frame.reach * 1.6, step=0.04)
    H = H.reshape(-1, 4, 3)
    res = []
    for q, (col, a, lit) in zip(H, meta):
        if np.isnan(q).any():
            continue
        cen = q.mean(0)
        nrm = surf.normal(cen[None])[0]
        q = q + nrm * lift
        res.append(DecalQuad(q, col, lit, a, cen, nrm, mid))
    return res


def quads_to_polys(quads, cam: Camera, light: Light, bias=0.35):
    d, _, _ = cam.basis()
    L = np.array(light.key, np.float64)
    L /= np.linalg.norm(L)
    polys = []
    if cam.persp:
        cam_pos = np.array(cam.target) + d * cam.persp
    for q in quads:
        if cam.persp:
            tocam = cam_pos - q.center
            if q.normal @ (tocam / np.linalg.norm(tocam)) < 0.08:
                continue
            depth = np.linalg.norm(tocam) - bias
        else:
            if q.normal @ d < 0.08:
                continue
            depth = -(q.center - np.array(cam.target)) @ d - bias
        col = np.asarray(q.color, np.float32)
        if q.lit > 0:
            diff = max(0.0, float(q.normal @ L))
            hemi = 0.5 + 0.5 * q.normal[1]
            shade = (light.ambient * (0.82 + 0.18 * hemi) * np.array(light.fill_col)
                     + light.key_amt * diff * np.array(light.key_col))
            col = col * (1 - q.lit) + np.clip(col * shade, 0, 255) * q.lit
        polys.append(Poly(q.pts, col, depth, q.mid, q.alpha))
    return polys

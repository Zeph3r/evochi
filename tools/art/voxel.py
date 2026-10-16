"""Evochi voxel renderer.

A small painter's-algorithm voxel renderer used to produce every piece of
character, item, icon and habitat art in the Evochi asset pack.

Coordinate system: x = right, y = up, z = front (characters face +z).
A model is a dense uint8 grid of material ids (0 = empty). Each material id
maps to a slot name, and a palette maps slot names to sRGB colours, so the
same model can be rendered in any of the six canonical colourways.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import cv2
import numpy as np
from scipy import ndimage


def hexrgb(h: str) -> np.ndarray:
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32)


# ----------------------------------------------------------------------------
# Model
# ----------------------------------------------------------------------------
class Model:
    """Dense voxel grid. Voxel (i,j,k) has its centre at origin + (i,j,k) + .5"""

    def __init__(self, lo, hi, mats: list[str], res: int = 1):
        self.res = int(res)
        self.lo = np.array(lo, np.int32) * self.res     # voxel index space
        self.hi = np.array(hi, np.int32) * self.res
        shape = tuple(int(v) for v in (self.hi - self.lo))
        self.m = np.zeros(shape, np.uint8)
        self.mats = ['empty'] + list(mats)
        self.ids = {n: i for i, n in enumerate(self.mats)}
        # per-voxel extra attributes
        self.glow = np.zeros(shape, np.float32)      # emissive amount 0..1
        self.layer = np.zeros(shape, np.uint8)       # used for parallax layers
        r = float(self.res)
        xs = (np.arange(self.lo[0], self.hi[0]) + 0.5) / r
        ys = (np.arange(self.lo[1], self.hi[1]) + 0.5) / r
        zs = (np.arange(self.lo[2], self.hi[2]) + 0.5) / r
        self.X, self.Y, self.Z = np.meshgrid(xs, ys, zs, indexing='ij')

    def mid(self, name):
        if name not in self.ids:
            self.ids[name] = len(self.mats)
            self.mats.append(name)
        return self.ids[name]

    def set(self, mask, mat, only_filled=False, only_empty=False, glow=None, layer=None):
        mid = self.mid(mat) if isinstance(mat, str) else mat
        if only_filled:
            mask = mask & (self.m > 0)
        if only_empty:
            mask = mask & (self.m == 0)
        self.m[mask] = mid
        if glow is not None:
            self.glow[mask] = glow
        if layer is not None:
            self.layer[mask] = layer
        return mask

    def clear(self, mask):
        self.m[mask] = 0

    # convenience shape helpers -------------------------------------------
    def ellipsoid(self, c, r, p=2.0):
        cx, cy, cz = c
        rx, ry, rz = r
        return (np.abs((self.X - cx) / rx) ** p + np.abs((self.Y - cy) / ry) ** p
                + np.abs((self.Z - cz) / rz) ** p) <= 1.0

    def box(self, lo, hi):
        return ((self.X >= lo[0]) & (self.X < hi[0]) & (self.Y >= lo[1]) & (self.Y < hi[1])
                & (self.Z >= lo[2]) & (self.Z < hi[2]))

    def surface(self, mask=None):
        """Filled voxels with at least one empty 6-neighbour."""
        filled = self.m > 0
        er = ndimage.binary_erosion(filled, structure=ndimage.generate_binary_structure(3, 1),
                                    border_value=0)
        s = filled & ~er
        if mask is not None:
            s &= mask
        return s

    def copy(self):
        o = Model.__new__(Model)
        o.res = self.res
        o.lo, o.hi = self.lo.copy(), self.hi.copy()
        o.m = self.m.copy()
        o.mats = list(self.mats)
        o.ids = dict(self.ids)
        o.glow = self.glow.copy()
        o.layer = self.layer.copy()
        o.X, o.Y, o.Z = self.X, self.Y, self.Z
        return o


# ----------------------------------------------------------------------------
# Camera
# ----------------------------------------------------------------------------
@dataclass
class Camera:
    yaw: float = 0.0          # degrees, + rotates camera toward +x
    pitch: float = 15.0       # degrees above horizon
    target: tuple = (0, 0, 0)
    persp: float = 0.0        # 0 = orthographic, otherwise camera distance
    fov: float = 40.0

    def basis(self):
        y, p = math.radians(self.yaw), math.radians(self.pitch)
        d = np.array([math.sin(y) * math.cos(p), math.sin(p), math.cos(y) * math.cos(p)])
        right = np.array([math.cos(y), 0.0, -math.sin(y)])
        up = np.cross(d, right)
        return d, right, up

    def project(self, P):
        """P (...,3) world -> (sx, sy, depth) in camera units (before fit)."""
        d, r, u = self.basis()
        Q = P - np.array(self.target, np.float64)
        x = Q @ r
        y = Q @ u
        z = -(Q @ d)          # bigger = farther from camera
        if self.persp:
            zc = z + self.persp
            zc = np.maximum(zc, 0.05)
            f = 1.0 / math.tan(math.radians(self.fov) / 2)
            return x * f / zc, -y * f / zc, zc
        return x, -y, z


# ----------------------------------------------------------------------------
# Lighting
# ----------------------------------------------------------------------------
@dataclass
class Light:
    key: tuple = (-0.55, 0.75, 0.62)        # warm daylight from upper left/front
    key_col: tuple = (1.0, 0.98, 0.93)
    fill_col: tuple = (0.97, 0.94, 0.91)    # warm-neutral fill (matches the model sheets)
    ambient: float = 0.86
    key_amt: float = 0.28
    ao_amt: float = 0.14
    jitter: float = 0.015
    smooth: float = 0.90                    # blend of smooth vs face normal
    smooth_sigma: float = 1.6
    rim: tuple = None                       # optional back light: direction the light comes from
    rim_col: tuple = (1.0, 0.86, 0.66)
    rim_amt: float = 0.0
    rim_pow: float = 1.6


FACES = [  # normal, 4 corner offsets (relative to voxel min corner) CCW from outside
    ((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
    ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
    ((0, 1, 0), [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]),
    ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
    ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
    ((0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)]),
]


@dataclass
class Poly:
    pts: np.ndarray        # (n,3) world
    color: np.ndarray      # rgb float
    depth: float
    mid: int               # material id / pass id
    alpha: float = 1.0


@dataclass
class Fit:
    scale: float
    ox: float
    oy: float
    w: int
    h: int


def smooth_normals(model: Model, sigma: float):
    occ = (model.m > 0).astype(np.float32)
    b = ndimage.gaussian_filter(occ, sigma, mode='constant')
    gx, gy, gz = np.gradient(b)
    n = -np.stack([gx, gy, gz], -1)
    ln = np.linalg.norm(n, axis=-1, keepdims=True)
    return n / np.maximum(ln, 1e-6)


def collect_faces(model: Model, palette: dict, cam: Camera, light: Light,
                  layers=None, seed=7, mat_alpha=None):
    """Return list of visible faces as (corners(N,4,3), rgb(N,3), depth(N), mid(N))."""
    m = model.m
    filled = m > 0
    if layers is not None:
        sel = np.isin(model.layer, layers) & filled
    else:
        sel = filled
    d, _, _ = cam.basis()
    cam_pos = None
    if cam.persp:
        cam_pos = np.array(cam.target) + d * cam.persp
    sn = smooth_normals(model, light.smooth_sigma * model.res)
    L = np.array(light.key, np.float32)
    L /= np.linalg.norm(L)
    ao_off = max(1, int(round(1.5 * model.res)))
    aob = ndimage.gaussian_filter(filled.astype(np.float32), 1.6 * model.res, mode='constant')
    rng = np.random.default_rng(seed)
    jit = (rng.random(m.shape).astype(np.float32) - 0.5) * 2 * light.jitter

    # occupancy padded for neighbour tests
    pad = np.pad(filled, 1)
    allc, allcol, alld, allm, alla = [], [], [], [], []
    lo = model.lo
    for normal, corners in FACES:
        nx, ny, nz = normal
        neigh = pad[1 + nx:1 + nx + m.shape[0], 1 + ny:1 + ny + m.shape[1], 1 + nz:1 + nz + m.shape[2]]
        vis = sel & ~neigh
        if not cam.persp:
            if np.dot(normal, d) <= 1e-6:
                continue
        idx = np.argwhere(vis)
        if len(idx) == 0:
            continue
        base = idx + lo  # min corner world coords
        if cam.persp:
            centers = (base + 0.5 + 0.5 * np.array(normal)) / float(model.res)
            tocam = cam_pos - centers
            keep = (tocam @ np.array(normal)) > 0
            idx, base = idx[keep], base[keep]
            if len(idx) == 0:
                continue
        C = (base[:, None, :] + np.array(corners)[None, :, :]) / float(model.res)
        # shading
        fn = np.array(normal, np.float32)
        s = sn[idx[:, 0], idx[:, 1], idx[:, 2]]
        nrm = light.smooth * s + (1 - light.smooth) * fn
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-6)
        diff = np.clip(nrm @ L, 0, 1)
        hemi = 0.5 + 0.5 * nrm[:, 1]
        # soft ambient occlusion from a blurred occupancy field sampled in front of the face
        q = idx + np.array(normal) * ao_off
        q = np.clip(q, 0, np.array(m.shape) - 1)
        occf = aob[q[:, 0], q[:, 1], q[:, 2]]
        ao = np.clip(1.0 - light.ao_amt * np.clip(occf - 0.12, 0, 1) * 2.2, 0.55, 1.0)
        mids = m[idx[:, 0], idx[:, 1], idx[:, 2]]
        alb = np.zeros((len(idx), 3), np.float32)
        for mid in np.unique(mids):
            name = model.mats[mid]
            col = palette.get(name)
            if col is None:
                bname = name.split('.')[0]
                col = bname if bname.startswith('#') else palette.get(bname, '#ff00ff')
            alb[mids == mid] = hexrgb(col) if isinstance(col, str) else np.array(col, np.float32)
        shade = (light.ambient * (0.82 + 0.18 * hemi)[:, None] * np.array(light.fill_col)
                 + light.key_amt * diff[:, None] * np.array(light.key_col))
        shade *= ao[:, None]
        if light.rim is not None and light.rim_amt > 0:
            Rv = np.array(light.rim, np.float32)
            Rv /= np.linalg.norm(Rv)
            if cam.persp:
                vd = cam_pos - (base + 0.5) / float(model.res)
                vd /= np.maximum(np.linalg.norm(vd, axis=1, keepdims=True), 1e-6)
                ndv = np.sum(nrm * vd, 1)
            else:
                ndv = nrm @ d.astype(np.float32)
            fres = (1.0 - np.clip(ndv, 0, 1)) ** light.rim_pow
            rterm = np.clip(nrm @ Rv + 0.35, 0, 1) * fres
            shade += light.rim_amt * rterm[:, None] * np.array(light.rim_col) * ao[:, None]
        shade *= (1 + jit[idx[:, 0], idx[:, 1], idx[:, 2]])[:, None]
        g = model.glow[idx[:, 0], idx[:, 1], idx[:, 2]]
        shade = shade * (1 - g[:, None]) + 1.12 * g[:, None]
        col = np.clip(alb * shade, 0, 255)
        cen = (base + 0.5) / float(model.res)
        if cam.persp:
            depth = np.linalg.norm(cen - cam_pos, axis=1)
        else:
            depth = -(cen - np.array(cam.target)) @ d
        a = np.ones(len(idx), np.float32)
        if mat_alpha:
            for mid in np.unique(mids):
                if model.mats[mid] in mat_alpha:
                    a[mids == mid] = mat_alpha[model.mats[mid]]
        allc.append(C)
        allcol.append(col)
        alld.append(depth)
        allm.append(mids)
        alla.append(a)
    if not allc:
        return (np.zeros((0, 4, 3)), np.zeros((0, 3)), np.zeros(0), np.zeros(0, np.int32), np.zeros(0))
    return (np.concatenate(allc), np.concatenate(allcol), np.concatenate(alld),
            np.concatenate(allm).astype(np.int32), np.concatenate(alla))


def fit_camera(cam: Camera, points: np.ndarray, w: int, h: int, margin=0.08, scale=None,
               anchor=None):
    sx, sy, _ = cam.project(points)
    x0, x1, y0, y1 = sx.min(), sx.max(), sy.min(), sy.max()
    if scale is None:
        scale = min(w * (1 - 2 * margin) / max(x1 - x0, 1e-6), h * (1 - 2 * margin) / max(y1 - y0, 1e-6))
    if anchor is None:
        ox = w / 2 - (x0 + x1) / 2 * scale
        oy = h / 2 - (y0 + y1) / 2 * scale
    else:
        # anchor = (world point, (px, py)) - place world point at pixel
        ax, ay, _ = cam.project(np.array([anchor[0]], np.float64))
        ox = anchor[1][0] - ax[0] * scale
        oy = anchor[1][1] - ay[0] * scale
    return Fit(scale, ox, oy, w, h)


def model_extent_points(model: Model):
    filled = np.argwhere(model.m > 0)
    if len(filled) == 0:
        return np.zeros((1, 3))
    lo = filled.min(0) + model.lo
    hi = filled.max(0) + model.lo + 1
    # use surface voxel corners for a tight fit
    s = np.argwhere(model.surface()) + model.lo
    pts = np.concatenate([s + np.array(c) for c in [(0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1),
                                                         (1, 1, 0), (1, 0, 1), (0, 1, 1), (1, 1, 1)]])
    return pts.astype(np.float64) / float(model.res)


@dataclass
class RenderOut:
    rgba: np.ndarray       # final HxWx4 uint8
    depth: np.ndarray      # final-res depth (inf = empty)
    ids: np.ndarray        # final-res material id (0 empty)
    fit: Fit
    cov: np.ndarray = None  # coverage of `cov_ids` materials (0..1) at final res


def rasterize(polys_pts, cols, depths, mids, alphas, cam: Camera, fit: Fit, ss=3,
              decals=None, edge_lines=True):
    """Painter's algorithm raster at ss x supersampling."""
    W, H = fit.w * ss, fit.h * ss
    img = np.zeros((H, W, 3), np.float32)
    alpha = np.zeros((H, W), np.float32)
    idb = np.zeros((H, W), np.int32)
    dep = np.full((H, W), np.inf, np.float32)

    # merge decals
    allp = list(polys_pts)
    allc = list(cols)
    alld = list(depths)
    allm = list(mids)
    alla = list(alphas)
    if decals:
        for dc in decals:
            allp.append(dc.pts)
            allc.append(dc.color)
            alld.append(dc.depth)
            allm.append(dc.mid)
            alla.append(dc.alpha)
    n = len(allp)
    order = np.argsort(-np.array(alld, np.float64), kind='stable')
    shift = 4
    mul = float(1 << shift)
    # pre-project everything at once when they share shape
    for oi in order:
        P = np.asarray(allp[oi], np.float64)
        sx, sy, sz = cam.project(P)
        px = (sx * fit.scale + fit.ox) * ss
        py = (sy * fit.scale + fit.oy) * ss
        pts = np.stack([px, py], 1)
        ipts = np.round(pts * mul).astype(np.int32)
        c = allc[oi]
        a = alla[oi]
        x0, y0 = int(max(0, np.floor(px.min()) - 1)), int(max(0, np.floor(py.min()) - 1))
        x1, y1 = int(min(W, np.ceil(px.max()) + 2)), int(min(H, np.ceil(py.max()) + 2))
        if x1 <= x0 or y1 <= y0:
            continue
        mask = np.zeros((y1 - y0, x1 - x0), np.uint8)
        loc = ipts - np.array([x0, y0]) * int(mul)
        cv2.fillConvexPoly(mask, loc, 1, lineType=cv2.LINE_8, shift=shift)
        # close cracks between neighbouring faces
        cv2.polylines(mask, [loc], True, 1, 1, lineType=cv2.LINE_8, shift=shift)
        mk = mask.astype(bool)
        if not mk.any():
            continue
        sub = img[y0:y1, x0:x1]
        if a >= 0.999:
            sub[mk] = c
            alpha[y0:y1, x0:x1][mk] = 1.0
        else:
            sub[mk] = sub[mk] * (1 - a) + np.array(c) * a
            al = alpha[y0:y1, x0:x1]
            al[mk] = al[mk] * (1 - a) + a
        idb[y0:y1, x0:x1][mk] = allm[oi]
        dep[y0:y1, x0:x1][mk] = alld[oi]
    return img, alpha, idb, dep


def fast_rasterize(C, cols, depths, mids, alphas, cam, fit, ss=3, decals=None):
    """Vectorised projection + per-face cv2 fill. C: (N,4,3)."""
    W, H = fit.w * ss, fit.h * ss
    img = np.zeros((H, W, 3), np.float32)
    alpha = np.zeros((H, W), np.float32)
    idb = np.zeros((H, W), np.int32)
    dep = np.full((H, W), np.inf, np.float32)

    items = []  # (depth, kind, index)
    N = len(C)
    if N:
        flat = C.reshape(-1, 3)
        sx, sy, _ = cam.project(flat)
        px = ((sx * fit.scale + fit.ox) * ss).reshape(N, 4)
        py = ((sy * fit.scale + fit.oy) * ss).reshape(N, 4)
    dlist = list(depths)
    kinds = [0] * N
    dec_proj = []
    if decals:
        for j, dc in enumerate(decals):
            sx2, sy2, _ = cam.project(np.asarray(dc.pts, np.float64))
            dec_proj.append(((sx2 * fit.scale + fit.ox) * ss, (sy2 * fit.scale + fit.oy) * ss))
            dlist.append(dc.depth)
            kinds.append(1)
    dl = np.array(dlist, np.float64)
    order = np.argsort(-dl, kind='stable')
    shift = 4
    mul = 1 << shift
    for oi in order:
        if oi < N:
            xs, ys = px[oi], py[oi]
            c, a, mid, dd = cols[oi], alphas[oi], mids[oi], depths[oi]
        else:
            dc = decals[oi - N]
            xs, ys = dec_proj[oi - N]
            c, a, mid, dd = dc.color, dc.alpha, dc.mid, dc.depth
        x0, y0 = int(max(0, math.floor(xs.min()) - 1)), int(max(0, math.floor(ys.min()) - 1))
        x1, y1 = int(min(W, math.ceil(xs.max()) + 2)), int(min(H, math.ceil(ys.max()) + 2))
        if x1 <= x0 or y1 <= y0:
            continue
        loc = np.stack([np.round((xs - x0) * mul), np.round((ys - y0) * mul)], 1).astype(np.int32)
        mask = np.zeros((y1 - y0, x1 - x0), np.uint8)
        cv2.fillConvexPoly(mask, loc, 1, lineType=cv2.LINE_8, shift=shift)
        if oi < N:
            cv2.polylines(mask, [loc], True, 1, 1, lineType=cv2.LINE_8, shift=shift)
        mk = mask.view(bool)
        if a >= 0.999:
            img[y0:y1, x0:x1][mk] = c
            alpha[y0:y1, x0:x1][mk] = 1.0
        else:
            s = img[y0:y1, x0:x1]
            s[mk] = s[mk] * (1 - a) + np.asarray(c, np.float32) * a
            al = alpha[y0:y1, x0:x1]
            al[mk] = al[mk] * (1 - a) + a
        idb[y0:y1, x0:x1][mk] = mid
        dep[y0:y1, x0:x1][mk] = dd
    return img, alpha, idb, dep


def downsample(img, alpha, ss):
    H, W = alpha.shape
    h, w = H // ss, W // ss
    a = alpha[:h * ss, :w * ss].reshape(h, ss, w, ss).mean((1, 3))
    premul = (img * alpha[..., None])[:h * ss, :w * ss].reshape(h, ss, w, ss, 3).mean((1, 3))
    col = premul / np.maximum(a[..., None], 1e-6)
    return col, a


def edges_from_depth(dep, ids, thresh, id_edges=None):
    """Return boolean edge mask at the given resolution from depth discontinuities."""
    d = dep.copy()
    finite = np.isfinite(d)
    big = np.nanmax(np.where(finite, d, np.nan)) if finite.any() else 0
    d[~finite] = big + 1000
    e = np.zeros(d.shape, bool)
    for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
        sh = np.roll(np.roll(d, -dy, 0), -dx, 1)
        diff = sh - d
        # mark the farther pixel side? mark the nearer pixel so line sits on object
        m1 = diff > thresh   # neighbour is farther -> this pixel is the near edge
        m2 = diff < -thresh
        e |= m1
        e |= np.roll(np.roll(m2, dy, 0), dx, 1)
    if id_edges is not None:
        # id_edges: lookup table mid -> group; lines drawn where groups differ (and one is >0)
        lut = np.asarray(id_edges, np.int32)
        g = lut[np.clip(ids, 0, len(lut) - 1)]
        for dy, dx in ((0, 1), (1, 0)):
            sh = np.roll(np.roll(g, -dy, 0), -dx, 1)
            diff = (sh != g) & ((sh > 0) | (g > 0))
            e |= diff & finite & np.roll(np.roll(finite, -dy, 0), -dx, 1)
    e &= finite
    return e


def compose(img, alpha, idb, dep, fit: Fit, ss: int, outline_px=2.5, outline_col='#3B2923',
            inner_lines=True, inner_thresh=1.6, inner_alpha=0.75, inner_px=1.0, id_edges=None,
            outline_alpha=1.0):
    """Downsample and add cartoon outline + depth-edge inner lines."""
    # inner depth edges computed at ss resolution, then thickened
    col, a = downsample(img, alpha, ss)
    oc = hexrgb(outline_col)
    if inner_lines:
        e = edges_from_depth(dep, idb, inner_thresh, id_edges)
        k = max(1, int(round(inner_px * ss)))
        e = cv2.dilate(e.astype(np.uint8), np.ones((k, k), np.uint8)).astype(np.float32)
        e *= (alpha > 0)
        h, w = a.shape
        em = e[:h * ss, :w * ss].reshape(h, ss, w, ss).mean((1, 3)) * inner_alpha
        col = col * (1 - em[..., None]) + oc * em[..., None]
    # silhouette outline (computed at supersampled resolution for antialiasing)
    if outline_px > 0:
        H2, W2 = alpha.shape
        inv = (alpha < 0.5).astype(np.uint8)
        dist = cv2.distanceTransform(inv, cv2.DIST_L2, 5)
        ol = np.clip(outline_px * ss + 0.5 - dist, 0, 1).astype(np.float32)
        h, w = a.shape
        dil = ol[:h * ss, :w * ss].reshape(h, ss, w, ss).mean((1, 3)) * outline_alpha
        dil = np.maximum(dil, a * 0)
        out_a = a + dil * (1 - a)
        out_c = (col * a[..., None] + oc * (dil * (1 - a))[..., None]) / np.maximum(out_a[..., None], 1e-6)
        col, a = out_c, out_a
    rgba = np.dstack([np.clip(col, 0, 255), np.clip(a * 255, 0, 255)]).astype(np.uint8)
    # final-res depth/id (nearest sample)
    h, w = a.shape
    dd = dep[ss // 2::ss, ss // 2::ss][:h, :w]
    ii = idb[ss // 2::ss, ss // 2::ss][:h, :w]
    return RenderOut(rgba, dd, ii, fit)


def render(model: Model, palette: dict, cam: Camera, w: int, h: int, fit: Fit | None = None,
           light: Light | None = None, ss=3, decals=None, outline_px=2.5, outline_col='#3B2923',
           inner_lines=True, inner_thresh=1.6, inner_alpha=0.75, layers=None, margin=0.08,
           id_edges=None, mat_alpha=None, inner_px=1.0, outline_alpha=1.0, cov_ids=None):
    light = light or Light()
    if fit is None:
        fit = fit_camera(cam, model_extent_points(model), w, h, margin)
    C, cols, deps, mids, alps = collect_faces(model, palette, cam, light, layers, mat_alpha=mat_alpha)
    img, alpha, idb, dep = fast_rasterize(C, cols, deps, mids, alps, cam, fit, ss, decals)
    out = compose(img, alpha, idb, dep, fit, ss, outline_px, outline_col, inner_lines,
                  inner_thresh * 1.0, inner_alpha, inner_px, id_edges, outline_alpha)
    if cov_ids is not None:
        h, w = out.rgba.shape[:2]
        c = np.isin(idb, cov_ids).astype(np.float32)[:h * ss, :w * ss]
        out.cov = c.reshape(h, ss, w, ss).mean((1, 3))
    return out


def save_rgba(arr, path):
    from PIL import Image
    Image.fromarray(arr, 'RGBA').save(path, optimize=True)


def project_px(cam: Camera, fit: Fit, P):
    sx, sy, _ = cam.project(np.asarray(P, np.float64).reshape(-1, 3))
    return np.stack([sx * fit.scale + fit.ox, sy * fit.scale + fit.oy], 1)

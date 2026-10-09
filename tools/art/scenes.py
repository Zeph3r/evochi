"""Layered 2.5D voxel habitat scenes (Sunlit Meadow, Market, Welcome vista, habitat thumbs).

Each scene is a set of voxel layers rendered with one shared perspective camera.
Layers are exported separately (sky / far / mid / near) for parallax, plus a
flattened composite. Decoration slots are projected into scene pixel space so
placed items line up with the scene perspective.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import cv2
import numpy as np
from PIL import Image, ImageFilter

from voxel import Model, Camera, Light, Fit, render, project_px, hexrgb
from items import flower as _flower

SCENE_LIGHT = Light(ambient=0.80, key_amt=0.36, ao_amt=0.30, jitter=0.05, smooth=0.25,
                    smooth_sigma=1.0, key=(-0.55, 0.85, 0.45))

GRASS = ['#7CC155', '#86C95B', '#73B84E', '#8FCF61', '#6AAE47']
GRASS_DK = ['#5E9E40', '#4F8E38']
DIRT = ['#C99A66', '#B98955', '#D7AB76']
STONE = ['#B8B2A8', '#A39D94', '#CCC6BC', '#948E86']
CLIFF = ['#C9A27A', '#B88F66', '#D6B188', '#A97F59']
WOOD_PL = ['#A8703F', '#9A6538', '#B87D49', '#8C5A31']
WATER = ['#7CC7EA', '#8FD3F2', '#6BB9E0']
FALL = ['#DFF4FC', '#BFE8FA', '#FFFFFF', '#A9DDF5']
LEAVES = ['#5EAE47', '#6BBB50', '#4F9C3E', '#78C45A']


def pick(rng, cols, shape):
    idx = rng.integers(0, len(cols), shape)
    return np.array(cols)[idx]


class Painter:
    """Helper to write coloured voxels (colour stored as literal hex material names)."""

    def __init__(self, M: Model, rng):
        self.M = M
        self.rng = rng

    def fill(self, mask, cols, glow=None):
        if isinstance(cols, str):
            cols = [cols]
        if not mask.any():
            return
        idx = np.argwhere(mask)
        choice = self.rng.integers(0, len(cols), len(idx))
        for ci, c in enumerate(cols):
            sel = idx[choice == ci]
            if len(sel) == 0:
                continue
            mid = self.M.mid(c)
            self.M.m[sel[:, 0], sel[:, 1], sel[:, 2]] = mid
            if glow is not None:
                self.M.glow[sel[:, 0], sel[:, 1], sel[:, 2]] = glow


def heightmap_fill(M: Model, H, top_cols, side_cols, P: Painter, top_th=1.0, base=-4):
    """H: 2D array over (x,z) grid of terrain heights (design units)."""
    Y = M.Y
    h3 = H[:, None, :]
    solid = (Y < h3) & (Y >= base)
    top = solid & (Y >= h3 - top_th)
    P.fill(solid & ~top, side_cols)
    P.fill(top, top_cols)


def tree(M, P, base, trunk_h=6.0, r=4.0, rng=None, leaves=LEAVES):
    x, y, z = base
    trunk = (np.abs(M.X - x) <= 0.8) & (np.abs(M.Z - z) <= 0.8) & (M.Y >= y) & (M.Y < y + trunk_h)
    P.fill(trunk, ['#7A4E2E', '#8A5A34'])
    rng = rng or np.random.default_rng(1)
    can = np.zeros(M.m.shape, bool)
    for _ in range(5):
        c = np.array([x, y + trunk_h + r * 0.4, z]) + rng.uniform(-1, 1, 3) * np.array([r * 0.6, r * 0.4, r * 0.6])
        s = r * rng.uniform(0.6, 0.95)
        can |= (np.abs(M.X - c[0]) <= s) & (np.abs(M.Y - c[1]) <= s * 0.8) & (np.abs(M.Z - c[2]) <= s)
    P.fill(can, leaves)


def daisy(M, P, c, size=0.9, petal='#FFFDF6', centre='#F4C04E', stem=True):
    _flower(M, c, n=(0, 0.6, 1), size=size, petal=petal, centre=centre)
    if stem:
        st = (np.abs(M.X - c[0]) <= 0.25) & (np.abs(M.Z - c[2]) <= 0.25) & (M.Y < c[1] - 0.4) & (M.Y >= c[1] - 2.5)
        P.fill(st & (M.m == 0), '#4F8E38')


def grass_tufts(M, P, H, region, density, rng, max_h=2.5, cols=None):
    """Random 1-voxel wide tufts standing on the terrain."""
    cols = cols or ['#8FD064', '#7CC155', '#9BD86E', '#6AAE47']
    xs = M.X[:, 0, 0]
    zs = M.Z[0, 0, :]
    nx, nz = len(xs), len(zs)
    for i in range(nx):
        for k in range(nz):
            if not region[i, k] or rng.random() > density:
                continue
            h = H[i, k]
            th = rng.uniform(0.8, max_h)
            j0 = int((h - M.lo[1] / M.res) * M.res)
            j1 = int((h + th - M.lo[1] / M.res) * M.res)
            j0, j1 = max(0, j0), min(M.m.shape[1], j1)
            if j1 > j0:
                c = cols[rng.integers(0, len(cols))]
                M.m[i, j0:j1, k] = M.mid(c)


@dataclass
class Layer:
    name: str
    model: Model
    blur: float = 0.0          # gaussian sigma in output px (depth of field)
    haze: float = 0.0          # blend toward sky colour
    haze_col: str = '#CFE8F5'
    inner_alpha: float = 0.25
    outline: float = 0.0
    light: Light = None


@dataclass
class Scene:
    name: str
    cam: Camera
    w: int
    h: int
    target_px: tuple           # where cam.target lands (fraction of w,h)
    sky: tuple                 # (top colour, horizon colour)
    layers: list
    slots: dict = field(default_factory=dict)     # name -> world point
    pet: tuple = (0, 0, 0)
    clouds: int = 6
    seed: int = 1
    sky_extra: object = None   # callable(img) for extra sky painting


def make_fit(sc: Scene):
    return Fit(scale=sc.h / 2.0, ox=sc.w * sc.target_px[0], oy=sc.h * sc.target_px[1], w=sc.w, h=sc.h)


def sky_image(sc: Scene):
    w, h = sc.w, sc.h
    top, hor = hexrgb(sc.sky[0]), hexrgb(sc.sky[1])
    t = np.linspace(0, 1, h)[:, None]
    t = np.clip(t / 0.55, 0, 1) ** 1.2
    g = top * (1 - t[..., None]) + hor * t[..., None]
    img = np.repeat(g, w, axis=1).astype(np.float32)
    rng = np.random.default_rng(sc.seed)
    cl = np.zeros((h, w), np.float32)
    for _ in range(sc.clouds):
        cx = rng.uniform(0.0, 1.0) * w
        cy = rng.uniform(0.04, 0.32) * h
        s = rng.uniform(0.06, 0.13) * w
        for _ in range(7):
            ox = cx + rng.uniform(-1.4, 1.4) * s
            oy = cy + rng.uniform(-0.3, 0.25) * s
            r = s * rng.uniform(0.35, 0.7)
            # blocky (voxel) cloud puffs
            x0, x1 = int(ox - r), int(ox + r)
            y0, y1 = int(oy - r * 0.6), int(oy + r * 0.45)
            cv2.rectangle(cl, (x0, y0), (x1, y1), 1.0, -1)
    cl = cv2.GaussianBlur(cl, (0, 0), w * 0.006)
    img = img * (1 - cl[..., None] * 0.92) + np.array([255, 255, 255]) * cl[..., None] * 0.92
    if sc.sky_extra:
        img = sc.sky_extra(img, sc)
    a = np.full((h, w, 1), 255, np.float32)
    return np.dstack([np.clip(img, 0, 255), a]).astype(np.uint8)


def render_layer(sc: Scene, L: Layer, fit: Fit):
    light = L.light or SCENE_LIGHT
    o = render(L.model, {}, sc.cam, sc.w, sc.h, fit=fit, light=light, ss=2,
               outline_px=L.outline, outline_col='#3B2923', inner_thresh=0.9, inner_alpha=L.inner_alpha,
               inner_px=0.7)
    rgba = o.rgba.astype(np.float32)
    if L.haze > 0:
        hc = hexrgb(L.haze_col)
        rgba[..., :3] = rgba[..., :3] * (1 - L.haze) + hc * L.haze
    if L.blur > 0:
        # premultiplied blur keeps edges clean
        a = rgba[..., 3:4] / 255.0
        pm = rgba[..., :3] * a
        pm = cv2.GaussianBlur(pm, (0, 0), L.blur)
        a2 = cv2.GaussianBlur(a[..., 0], (0, 0), L.blur)[..., None]
        rgba[..., :3] = pm / np.maximum(a2, 1e-4)
        rgba[..., 3:4] = a2 * 255
    return np.clip(rgba, 0, 255).astype(np.uint8), o


def composite(layers):
    base = layers[0].astype(np.float32)
    for l in layers[1:]:
        a = l[..., 3:4].astype(np.float32) / 255.0
        base[..., :3] = base[..., :3] * (1 - a) + l[..., :3] * a
        base[..., 3:4] = np.maximum(base[..., 3:4], l[..., 3:4])
    return base.astype(np.uint8)


# ----------------------------------------------------------------------------
# Shared terrain pieces
# ----------------------------------------------------------------------------
def terrace_cliffs(M, P, rng, x_range, z_range, base_h, top_h, steps=4, falls=(), trees=6,
                   grass=GRASS, sides=CLIFF):
    xs = M.X[:, 0, 0]
    zs = M.Z[0, 0, :]
    X2, Z2 = np.meshgrid(xs, zs, indexing='ij')
    # stepped plateau height increasing with distance, broken into blocky columns
    t = np.clip((z_range[1] - Z2) / (z_range[1] - z_range[0]), 0, 1)
    noise = cv2.resize(rng.random((max(2, len(xs) // 6), max(2, len(zs) // 6))).astype(np.float32),
                       (len(zs), len(xs)), interpolation=cv2.INTER_NEAREST)
    H = base_h + (top_h - base_h) * np.floor(t * steps + noise * 0.8) / steps
    xn = cv2.resize(rng.random((max(2, len(xs) // 10), 1)).astype(np.float32), (1, len(xs)),
                    interpolation=cv2.INTER_NEAREST)[:, 0]
    H = H + (xn[:, None] - 0.5) * (top_h - base_h) * 0.35
    H = np.round(H)
    inside = (X2 >= x_range[0]) & (X2 <= x_range[1]) & (Z2 >= z_range[0]) & (Z2 <= z_range[1])
    H = np.where(inside, H, -100)
    Y = M.Y
    solid = (Y < H[:, None, :]) & (Y >= -2)
    top = solid & (Y >= H[:, None, :] - 1.0)
    # horizontal strata on the cliff sides
    strata = (np.floor(Y / 2).astype(int) % 3)
    for s, col in zip(range(3), (sides[0], sides[1], sides[2])):
        P.fill(solid & ~top & (strata == s), [col, sides[3]] if s == 1 else [col])
    P.fill(top, grass)
    # waterfalls: vertical sheets in front of the cliff face
    for (fx, fw, fz) in falls:
        col_h = H[np.argmin(np.abs(xs - fx)), np.argmin(np.abs(zs - fz))]
        if col_h < 0:
            continue
        sheet = (np.abs(M.X - fx) <= fw / 2) & (M.Z >= fz) & (M.Z < fz + 1.5) & (M.Y < col_h) & (M.Y >= -1)
        P.fill(sheet, FALL)
        foam = (np.abs(M.X - fx) <= fw / 2 + 1.5) & (M.Z >= fz) & (M.Z < fz + 3.5) & (M.Y < 1.5) & (M.Y >= -1)
        P.fill(foam, ['#FFFFFF', '#EAF8FF'])
    # trees on top of terraces
    for _ in range(trees):
        tx = rng.uniform(*x_range)
        tz = rng.uniform(z_range[0] + 4, z_range[1] - 2)
        ty = H[np.argmin(np.abs(xs - tx)), np.argmin(np.abs(zs - tz))]
        if ty > 0:
            tree(M, P, (tx, ty, tz), trunk_h=rng.uniform(3, 6), r=rng.uniform(2.5, 4.5), rng=rng)
    return H


def ground(M, P, rng, H, grass=GRASS, sides=DIRT, path=None):
    heightmap_fill(M, H, grass, sides, P, top_th=1.0 / M.res, base=-6)
    if path is not None:
        xs = M.X[:, 0, 0]
        zs = M.Z[0, 0, :]
        X2, Z2 = np.meshgrid(xs, zs, indexing='ij')
        pm = path(X2, Z2)
        topband = (M.Y < H[:, None, :]) & (M.Y >= H[:, None, :] - 1.0 / M.res) & pm[:, None, :]
        P.fill(topband, DIRT)


# ----------------------------------------------------------------------------
# Scene: Sunlit Meadow (Home / Bag / Create)
# ----------------------------------------------------------------------------
def portrait_cam(pitch=13, target=(0, 4.5, 0), dist=37):
    return Camera(yaw=0, pitch=pitch, target=target, persp=dist, fov=60)


def meadow_far(rng, falls=((-15, 8, -60), (11, 7, -64), (34, 6, -60), (-40, 6, -70)), z_lake=(-58, -30)):
    F = Model((-110, -2, -190), (110, 80, -28), [], res=1)
    PF = Painter(F, rng)
    lake = (F.Y >= -1) & (F.Y < 0) & (F.Z >= z_lake[0]) & (F.Z < z_lake[1])
    PF.fill(lake, WATER)
    terrace_cliffs(F, PF, rng, (-110, 110), (-160, -58), 5, 40, steps=5, falls=falls, trees=34)
    far2 = (F.Z < -165) & (F.Y < 58 + 10 * np.sin(F.X / 13.0)) & (F.Y >= 0)
    PF.fill(far2, ['#9DBF8F', '#A7C79A'])
    return Layer('far', F, blur=7.0, haze=0.26, haze_col='#CBE6F2', inner_alpha=0.15)


def meadow_ground(rng, Mm, P, clear_r=4.5):
    xs = Mm.X[:, 0, 0]
    zs = Mm.Z[0, 0, :]
    X2, Z2 = np.meshgrid(xs, zs, indexing='ij')
    Hn = cv2.resize(rng.random((24, 20)).astype(np.float32), (len(zs), len(xs)), interpolation=cv2.INTER_NEAREST)
    H = np.round((Hn - 0.5) * 1.0) / 2
    H = np.where(np.sqrt(X2 ** 2 + Z2 ** 2) < clear_r + 1.5, 0, H)
    H = np.where(Z2 < -27, -0.5, H)
    ground(Mm, P, rng, H, path=lambda X, Z: (np.sqrt((X * 0.9) ** 2 + (Z * 1.25) ** 2) < clear_r) |
           ((np.abs(X - Z * 0.3 - 1.5) < 1.1) & (Z > 2)))
    region = (np.sqrt(X2 ** 2 + Z2 ** 2) > clear_r + 1.2)
    grass_tufts(Mm, P, H, region, 0.10, rng, max_h=0.9)
    return H, xs, zs


def scene_meadow(w=1170, h=2532, seed=4):
    rng = np.random.default_rng(seed)
    cam = portrait_cam()
    layers = [meadow_far(rng)]

    Mm = Model((-26, -6, -30), (26, 34, 10), [], res=2)
    P = Painter(Mm, rng)
    H, xs, zs = meadow_ground(rng, Mm, P)
    # fence receding on the left
    p0, p1 = np.array([-15.0, 0, 1.0]), np.array([-7.0, 0, -15.0])
    for k in range(6):
        q = p0 + (p1 - p0) * k / 5
        post = (np.abs(Mm.X - q[0]) <= 0.4) & (np.abs(Mm.Z - q[2]) <= 0.4) & (Mm.Y >= 0) & (Mm.Y < 3.4)
        P.fill(post, ['#8A5A34'])
        P.fill(post & (Mm.Y >= 3.0), ['#A8703F'])
    d = (p1 - p0) / np.linalg.norm(p1 - p0)
    rx, rz = Mm.X - p0[0], Mm.Z - p0[2]
    t = rx * d[0] + rz * d[2]
    perp = np.abs(-rx * d[2] + rz * d[0])
    for ry in (1.3, 2.6):
        rail = (perp <= 0.25) & (t >= 0) & (t <= np.linalg.norm(p1 - p0)) & (np.abs(Mm.Y - ry) <= 0.3)
        P.fill(rail, WOOD_PL[:3])
    # rocks (left, near the pet)
    for (rx_, rz_, rs) in ((-8.6, 1.5, 1.5), (-10.2, -0.6, 1.0), (-7.0, 3.4, 0.8), (-12.5, -6, 1.4), (12.5, 4.0, 0.9)):
        rk = ((np.abs(Mm.X - rx_) / rs) ** 4 + (np.abs(Mm.Y) / (rs * 1.1)) ** 4 + (np.abs(Mm.Z - rz_) / (rs * 0.85)) ** 4) <= 1.3
        rk &= Mm.Y >= -0.5
        P.fill(rk, STONE)
    # cabin wall on the right, facing the pet
    wall = (Mm.X >= 10.0) & (Mm.X < 12.0) & (Mm.Z >= -26) & (Mm.Z < -3.5) & (Mm.Y >= 0) & (Mm.Y < 34)
    plank = (np.floor(Mm.Z / 1.1).astype(int) + np.floor(Mm.Y / 5).astype(int)) % 4
    for k in range(4):
        P.fill(wall & (plank == k), [WOOD_PL[k]])
    P.fill(wall & ((Mm.Y % 9) < 0.6), ['#6E4529'])
    corner = (Mm.X >= 9.4) & (Mm.X < 12.4) & (Mm.Z >= -4.4) & (Mm.Z < -2.6) & (Mm.Y >= 0) & (Mm.Y < 34)
    P.fill(corner, ['#6E4529', '#7A4E2E'])
    side = (Mm.X >= 12) & (Mm.X < 26) & (Mm.Z >= -4.4) & (Mm.Z < -2.6) & (Mm.Y >= 0) & (Mm.Y < 34)
    pl2 = (np.floor(Mm.X / 1.1).astype(int) + np.floor(Mm.Y / 5).astype(int)) % 4
    for k in range(4):
        P.fill(side & (pl2 == k), [WOOD_PL[(k + 1) % 4]])
    # lantern on a bracket
    lx, ly, lz = 8.2, 12.5, -6.5
    br = (Mm.X >= lx - 0.3) & (Mm.X < 10.0) & (np.abs(Mm.Y - 15.2) <= 0.3) & (np.abs(Mm.Z - lz) <= 0.3)
    P.fill(br, ['#4A3328'])
    chain = (np.abs(Mm.X - lx) <= 0.2) & (Mm.Y >= ly + 1.4) & (Mm.Y < 15.2) & (np.abs(Mm.Z - lz) <= 0.2)
    P.fill(chain, ['#4A3328'])
    lf = (np.maximum(np.abs(Mm.X - lx), np.abs(Mm.Z - lz)) <= 0.8) & (Mm.Y >= ly - 1.2) & (Mm.Y < ly + 1.4)
    lin = (np.maximum(np.abs(Mm.X - lx), np.abs(Mm.Z - lz)) <= 0.45) & (Mm.Y >= ly - 0.8) & (Mm.Y < ly + 1.0)
    P.fill(lf & ~lin, ['#4A3328'])
    win = lf & ~lin & (np.minimum(np.abs(Mm.X - lx), np.abs(Mm.Z - lz)) <= 0.45) & (Mm.Y >= ly - 0.7) & (Mm.Y < ly + 0.9)
    P.fill(win, ['#FFD46A', '#FFE08A'], glow=0.95)
    P.fill(lin, ['#FFE7A0'], glow=1.0)
    cap = (np.maximum(np.abs(Mm.X - lx), np.abs(Mm.Z - lz)) <= 1.1 - (Mm.Y - ly - 1.4) * 0.8) & (Mm.Y >= ly + 1.4) & (Mm.Y < ly + 2.4)
    P.fill(cap, ['#5A3B2A'])
    # red banner on the wall
    ban = (Mm.X >= 9.4) & (Mm.X < 10.0) & (Mm.Z >= -14) & (Mm.Z < -9) & (Mm.Y >= 8) & (Mm.Y < 17)
    ban &= ~((Mm.Y < 9.2) & (np.abs(Mm.Z + 11.5) < 0.9))
    P.fill(ban, ['#B9473F', '#C4503F'])
    emb = ban & (((Mm.Z + 11.5) ** 2 / 2.2 + (Mm.Y - 12.8) ** 2 / 5.0) <= 1) & (np.abs(Mm.Z + 11.5) > 0.3)
    P.fill(emb, ['#E9C46A'])
    rod = (Mm.X >= 9.2) & (Mm.X < 10.0) & (Mm.Z >= -14.6) & (Mm.Z < -8.4) & (np.abs(Mm.Y - 17.2) <= 0.3)
    P.fill(rod, ['#5A3B2A'])
    # crates & stump by the cabin
    crate = (Mm.X >= 7.0) & (Mm.X < 10.0) & (Mm.Z >= -2.4) & (Mm.Z < 0.6) & (Mm.Y >= 0) & (Mm.Y < 2.8)
    P.fill(crate, ['#B07A48', '#A06C3E'])
    P.fill(crate & ((Mm.Y >= 2.4) | (np.abs(Mm.X - 8.5) < 0.25)), ['#7A4E2E'])
    crate2 = (Mm.X >= 7.6) & (Mm.X < 9.6) & (Mm.Z >= -2.0) & (Mm.Z < 0.0) & (Mm.Y >= 2.8) & (Mm.Y < 4.6)
    P.fill(crate2, ['#B98552'])
    stump = ((Mm.X - 9.0) ** 2 + (Mm.Z - 3.8) ** 2 <= 1.2 ** 2) & (Mm.Y >= 0) & (Mm.Y < 1.6)
    P.fill(stump, ['#9A6538'])
    P.fill(stump & (Mm.Y >= 1.2), ['#D9B07A'])
    # daisies scattered in the grass
    for _ in range(46):
        fx = rng.uniform(-20, 20)
        fz = rng.uniform(-26, 8)
        if math.hypot(fx, fz * 1.2) < 6.5 or (fx > 9 and fz < -2):
            continue
        hh = H[np.argmin(np.abs(xs - fx)), np.argmin(np.abs(zs - fz))]
        daisy(Mm, P, (fx, hh + rng.uniform(0.6, 1.2), fz), size=rng.uniform(0.38, 0.52))
    # framing tree on the left
    tree(Mm, P, (-14, 0, -12), trunk_h=13, r=5.5, rng=rng)
    trunk = ((Mm.X + 14) ** 2 + (Mm.Z + 12) ** 2 <= 1.3 ** 2) & (Mm.Y >= 0) & (Mm.Y < 14)
    P.fill(trunk, ['#7A4E2E', '#8A5A34', '#6E4529'])
    layers.append(Layer('mid', Mm, blur=0.0, inner_alpha=0.28, outline=0.0))

    # near: foreground tufts and flowers (soft focus)
    N = Model((-16, -6, 8), (16, 10, 26), [], res=2)
    PN = Painter(N, rng)
    xsn = N.X[:, 0, 0]
    zsn = N.Z[0, 0, :]
    X2, Z2 = np.meshgrid(xsn, zsn, indexing='ij')
    Hn = np.round((cv2.resize(rng.random((16, 10)).astype(np.float32), (len(zsn), len(xsn)),
                              interpolation=cv2.INTER_NEAREST) - 0.5)) / 2
    ground(N, PN, rng, Hn)
    grass_tufts(N, PN, Hn, np.abs(X2) > 2.5, 0.28, rng, max_h=1.8)
    for _ in range(14):
        fx = rng.choice([-1, 1]) * rng.uniform(4, 11)
        fz = rng.uniform(9, 18)
        daisy(N, PN, (fx, rng.uniform(1.2, 2.0), fz), size=rng.uniform(0.55, 0.75))
    layers.append(Layer('near', N, blur=3.5, inner_alpha=0.15))

    sc = Scene('meadow', cam, w, h, (0.5, 0.29), ('#5FB1E6', '#CFEAF7'), layers, seed=seed, clouds=5)
    sc.slots = {'nest': (0, 0, 0), 'left': (-5.6, 0, 2.6), 'right': (5.8, 0, 1.8), 'back': (-3.0, 0, -6.5)}
    return sc


# ----------------------------------------------------------------------------
# Scene: Market (Shop)
# ----------------------------------------------------------------------------
def scene_market(w=1170, h=2532, seed=7):
    rng = np.random.default_rng(seed)
    cam = portrait_cam(pitch=10, target=(0, 4.8, 0))
    layers = []
    F = Model((-110, -2, -190), (110, 80, -34), [], res=1)
    PF = Painter(F, rng)
    terrace_cliffs(F, PF, rng, (-110, 110), (-160, -50), 8, 46, steps=5,
                   falls=((-6, 7, -56), (26, 6, -62)), trees=26)
    layers.append(Layer('far', F, blur=8.0, haze=0.3, inner_alpha=0.12))

    Mm = Model((-24, -6, -34), (24, 40, 12), [], res=2)
    P = Painter(Mm, rng)
    xs = Mm.X[:, 0, 0]
    zs = Mm.Z[0, 0, :]
    H = np.zeros((len(xs), len(zs)))
    heightmap_fill(Mm, H, ['#C9A27A', '#BE966D', '#D3AE87', '#B48A60'], DIRT, P, top_th=0.5, base=-6)
    # back row of timber stalls with striped canopies
    for i, sx in enumerate((-15, 0, 15)):
        z0 = -24 - (i % 2) * 2
        body = (np.abs(Mm.X - sx) <= 6.0) & (Mm.Z >= z0) & (Mm.Z < z0 + 6) & (Mm.Y >= 0) & (Mm.Y < 6)
        P.fill(body, WOOD_PL)
        P.fill(body & (Mm.Y >= 5.5), ['#C98C57'])
        for px in (sx - 5.6, sx + 5.6):
            post = (np.abs(Mm.X - px) <= 0.5) & (np.abs(Mm.Z - (z0 + 5.4)) <= 0.5) & (Mm.Y >= 0) & (Mm.Y < 14)
            P.fill(post, ['#6E4529'])
        can = (np.abs(Mm.X - sx) <= 6.8) & (Mm.Y >= 12.5) & (Mm.Y < 15) & (Mm.Z >= z0 - 1) & (Mm.Z < z0 + 8)
        stripe = (np.floor((Mm.X - sx + 6.8) / 1.7).astype(int) % 2 == 0)
        c1 = '#C9443B' if i % 2 == 0 else '#D98C3B'
        P.fill(can & stripe, [c1])
        P.fill(can & ~stripe, ['#F7EBD6'])
        for gx in np.linspace(sx - 4, sx + 4, 4):
            g = ((Mm.X - gx) ** 2 + (Mm.Y - 6.8) ** 2 + (Mm.Z - (z0 + 3.5)) ** 2) <= 1.0
            P.fill(g, [rng.choice(['#D93A48', '#F3B83A', '#6CB25A', '#E9C46A'])])
    # bunting across the top
    for (y0, zz, span) in ((24, -12, 26), (19, -4, 20)):
        n = 18
        xsx = np.linspace(-span, span, n + 1)
        for k in range(n):
            cx = (xsx[k] + xsx[k + 1]) / 2
            sag = y0 - 2.0 * (1 - ((cx / span) ** 2))
            hw = (xsx[1] - xsx[0]) * 0.42
            tri = (np.abs(Mm.X - cx) <= hw * (1 - (sag - Mm.Y) / 2.0)) & (Mm.Y <= sag) & (Mm.Y > sag - 2.0) & \
                (np.abs(Mm.Z - zz) <= 0.3)
            P.fill(tri, [['#C9443B', '#F3C14E', '#F7EBD6', '#D9763B'][k % 4]])
            line = (np.abs(Mm.X - cx) <= hw * 1.25) & (np.abs(Mm.Y - sag - 0.15) <= 0.2) & (np.abs(Mm.Z - zz) <= 0.2)
            P.fill(line, ['#6E4529'])
    # banners with crown emblems
    for bx in (-8.5, 8.5):
        ban = (np.abs(Mm.X - bx) <= 2.6) & (Mm.Y >= 9) & (Mm.Y < 20) & (np.abs(Mm.Z + 9) <= 0.3)
        ban &= ~((Mm.Y < 10.4) & (np.abs(Mm.X - bx) < 1.0))
        P.fill(ban, ['#B9473F', '#C4503F'])
        cr = ban & (np.abs(Mm.X - bx) <= 1.5) & (Mm.Y >= 13.6) & (Mm.Y < 16.2) & \
            ~((Mm.Y > 15.2) & ((np.floor((Mm.X - bx + 1.5) * 2).astype(int) % 2) == 1))
        P.fill(cr, ['#E9C46A'])
        rod = (np.abs(Mm.X - bx) <= 3.2) & (np.abs(Mm.Y - 20.2) <= 0.3) & (np.abs(Mm.Z + 9) <= 0.4)
        P.fill(rod, ['#5A3B2A'])
    # timber frames close on both sides
    for sx in (-14.5, 14.5):
        fr = (np.abs(Mm.X - sx) <= 2.2) & (Mm.Z >= -10) & (Mm.Z < 2) & (Mm.Y >= 0) & (Mm.Y < 40)
        pl = (np.floor(Mm.Z / 1.1).astype(int) + np.floor(Mm.Y / 5).astype(int)) % 4
        for k in range(4):
            P.fill(fr & (pl == k), [WOOD_PL[k]])
        P.fill(fr & ((Mm.Y % 9) < 0.6), ['#6E4529'])
    # hanging lanterns
    for (lx, ly, lz) in ((-9.5, 16.5, -2), (9.5, 16.5, -2)):
        lf = (np.maximum(np.abs(Mm.X - lx), np.abs(Mm.Z - lz)) <= 0.9) & (Mm.Y >= ly - 1.4) & (Mm.Y < ly + 1.4)
        P.fill(lf, ['#FFD46A', '#FFE08A'], glow=0.95)
        P.fill(lf & ((Mm.Y >= ly + 1.0) | (Mm.Y < ly - 1.0)), ['#4A3328'])
        chain = (np.abs(Mm.X - lx) <= 0.2) & (Mm.Y >= ly + 1.4) & (Mm.Y < ly + 8) & (np.abs(Mm.Z - lz) <= 0.2)
        P.fill(chain, ['#4A3328'])
    # standing mirror on the left
    mx, mz = -7.6, -1.5
    frame = (np.abs(Mm.X - mx) <= 2.1) & (Mm.Y >= 0.3) & (Mm.Y < 9.0) & (np.abs(Mm.Z - mz) <= 0.4)
    glass = (np.abs(Mm.X - mx) <= 1.5) & (Mm.Y >= 0.9) & (Mm.Y < 8.4) & (np.abs(Mm.Z - mz) <= 0.5)
    P.fill(frame, ['#B8873C', '#A87A34'])
    P.fill(glass & (Mm.Z > mz), ['#CFE3EA', '#BFD7E0', '#DCEEF3'])
    # red carpet stage for the pet
    stage = (np.abs(Mm.X) <= 5.4) & (np.abs(Mm.Z) <= 3.6) & (Mm.Y >= 0) & (Mm.Y < 1.6)
    P.fill(stage, ['#7A4E2E', '#8A5A34'])
    carpet = (np.abs(Mm.X) <= 5.0) & (np.abs(Mm.Z) <= 3.2) & (Mm.Y >= 1.6) & (Mm.Y < 2.0)
    P.fill(carpet, ['#C0453C', '#B63F37'])
    trim = carpet & ((np.abs(np.abs(Mm.X) - 4.4) < 0.3) | (np.abs(np.abs(Mm.Z) - 2.6) < 0.3))
    P.fill(trim, ['#E9C46A'])
    step = (np.abs(Mm.X) <= 4.4) & (Mm.Z > 3.6) & (Mm.Z < 5.0) & (Mm.Y >= 0) & (Mm.Y < 0.8)
    P.fill(step, ['#C0453C'])
    # flowers / pots
    for (fx, fz) in ((-5.2, 6.0), (6.2, 5.5)):
        pot = ((Mm.X - fx) ** 2 + (Mm.Z - fz) ** 2 <= 1.0) & (Mm.Y >= 0) & (Mm.Y < 1.4)
        P.fill(pot, ['#C9734A'])
        bush = ((Mm.X - fx) ** 2 + (Mm.Y - 2.2) ** 2 + (Mm.Z - fz) ** 2) <= 1.5 ** 2
        P.fill(bush & (Mm.m == 0), LEAVES)
        daisy(Mm, P, (fx + 0.3, 3.4, fz + 0.8), size=0.55, stem=False)
    layers.append(Layer('mid', Mm, blur=0.0, inner_alpha=0.28))

    sc = Scene('market', cam, w, h, (0.5, 0.29), ('#5FB1E6', '#CFEAF7'), layers, seed=seed, clouds=4)
    sc.pet = (0, 2.0, 0)
    sc.slots = {'stage': (0, 2.0, 0)}
    return sc


# ----------------------------------------------------------------------------
# Scene: Welcome vista (floating islands, big tree, lantern post)
# ----------------------------------------------------------------------------
def floating_islands(img, sc):
    rng = np.random.default_rng(sc.seed + 50)
    h, w = img.shape[:2]
    for (cx, cy, s) in ((0.80, 0.045, 0.085), (0.95, 0.10, 0.05), (0.16, 0.06, 0.05), (0.58, 0.11, 0.035)):
        x, y, r = int(cx * w), int(cy * h), int(s * w)
        top = np.array([110, 185, 90], float)
        dirt = np.array([186, 150, 110], float)
        for k in range(5):
            ww = int(r * (1 - k * 0.18))
            y0 = y + k * int(r * 0.22)
            cv2.rectangle(img, (x - ww, y0), (x + ww, y0 + int(r * 0.22)), (dirt * (0.95 - k * 0.04)).tolist(), -1)
        cv2.rectangle(img, (x - r, y - int(r * 0.18)), (x + r, y), top.tolist(), -1)
        # tiny trees
        for t in range(2):
            tx = x + int(rng.uniform(-0.6, 0.6) * r)
            cv2.rectangle(img, (tx - int(r * 0.18), y - int(r * 0.55)), (tx + int(r * 0.18), y - int(r * 0.18)),
                          (90, 165, 75), -1)
        # waterfall thread
        cv2.rectangle(img, (x + int(r * 0.35), y + int(r * 0.6)), (x + int(r * 0.45), y + int(r * 1.6)),
                      (230, 245, 252), -1)
    return cv2.GaussianBlur(img, (0, 0), 2.0)


def scene_welcome(w=1170, h=2532, seed=11):
    sc = scene_meadow(w, h, seed=seed)
    sc.name = 'welcome'
    sc.cam = portrait_cam(pitch=7, target=(0, 5.0, 0), dist=40)
    sc.target_px = (0.5, 0.42)
    sc.sky_extra = floating_islands
    F = [l for l in sc.layers if l.name == 'far'][0].model
    F.m[(F.Z < -160) & (F.Y > 20)] = 0
    # replace the house wall with a big tree + lantern post on the right, and a large tree left
    Mm = [l for l in sc.layers if l.name == 'mid'][0].model
    rng = np.random.default_rng(seed + 3)
    P = Painter(Mm, rng)
    cabin = (Mm.X >= 7.0) & (Mm.Z >= -27) & (Mm.Z < 1.0) & (Mm.Y >= 0.5)
    Mm.m[cabin] = 0
    # lantern post on the right
    px, pz = 10.0, -11.0
    post = (np.abs(Mm.X - px) <= 0.6) & (np.abs(Mm.Z - pz) <= 0.6) & (Mm.Y >= 0) & (Mm.Y < 22)
    P.fill(post, ['#6E4529', '#7A4E2E'])
    arm = (Mm.X >= px - 4) & (Mm.X < px) & (np.abs(Mm.Y - 21.5) <= 0.4) & (np.abs(Mm.Z - pz) <= 0.4)
    P.fill(arm, ['#6E4529'])
    lx, ly, lz = px - 3.4, 18.6, pz
    lf = (np.maximum(np.abs(Mm.X - lx), np.abs(Mm.Z - lz)) <= 1.2) & (Mm.Y >= ly - 1.6) & (Mm.Y < ly + 2)
    P.fill(lf, ['#FFD46A', '#FFE08A'], glow=1.0)
    P.fill(lf & ((Mm.Y >= ly + 1.5) | (Mm.Y < ly - 1.1)), ['#4A3328'])
    # pedestal block for the hero eggling (grass-topped dirt cube)
    ped = (np.abs(Mm.X) <= 5.2) & (np.abs(Mm.Z) <= 4.2) & (Mm.Y >= 0) & (Mm.Y < 3.0)
    P.fill(ped, DIRT)
    P.fill(ped & (Mm.Y >= 2.3), GRASS)
    edge = (np.abs(Mm.X) <= 5.6) & (np.abs(Mm.Z) <= 4.6) & (Mm.Y >= 1.8) & (Mm.Y < 3.0) & ~ped
    P.fill(edge & (np.random.default_rng(2).random(Mm.m.shape) > 0.5), GRASS)
    sc.pet = (0, 3.0, 0)
    sc.slots = {'pedestal': (0, 3.0, 0)}
    return sc


# ----------------------------------------------------------------------------
# Habitat thumbnails (landscape)
# ----------------------------------------------------------------------------
def scene_forest(w=720, h=480, seed=21):
    rng = np.random.default_rng(seed)
    cam = Camera(yaw=0, pitch=10, target=(0, 6, 0), persp=70, fov=36)
    M = Model((-50, -2, -80), (50, 40, 60), [], res=1)
    P = Painter(M, rng)
    xs = M.X[:, 0, 0]
    zs = M.Z[0, 0, :]
    H = np.round(cv2.resize(rng.random((12, 10)).astype(np.float32), (len(zs), len(xs)),
                            interpolation=cv2.INTER_NEAREST) * 1.5)
    ground(M, P, rng, H, grass=['#5E9E40', '#6AAE47', '#4F8E38'], path=lambda X, Z: np.abs(X - Z * 0.1) < 3)
    for _ in range(26):
        tx, tz = rng.uniform(-48, 48), rng.uniform(-78, -6)
        if abs(tx) < 6 and tz > -30:
            continue
        tree(M, P, (tx, 0, tz), trunk_h=rng.uniform(8, 14), r=rng.uniform(4, 7), rng=rng,
             leaves=['#3E8A3A', '#4A9A41', '#357A33', '#5AA84A'])
    for _ in range(10):
        mx, mz = rng.uniform(-30, 30), rng.uniform(-30, 8)
        cap = ((M.X - mx) ** 2 + (M.Z - mz) ** 2 <= 2.0 ** 2) & (M.Y >= 2.0) & (M.Y < 3.2)
        P.fill(cap, ['#D8434A'])
        stem = ((M.X - mx) ** 2 + (M.Z - mz) ** 2 <= 0.6 ** 2) & (M.Y >= 0) & (M.Y < 2.0)
        P.fill(stem, ['#F4E6D2'])
    sc = Scene('forest', cam, w, h, (0.5, 0.5), ('#7FC5A8', '#D5EFD9'), [Layer('mid', M, inner_alpha=0.2)],
               seed=seed, clouds=2)
    return sc


def scene_cliffs(w=720, h=480, seed=31):
    rng = np.random.default_rng(seed)
    cam = Camera(yaw=0, pitch=8, target=(0, 16, 0), persp=80, fov=40)
    M = Model((-70, -2, -120), (70, 60, 70), [], res=1)
    P = Painter(M, rng)
    near = (M.Z > -10) & (M.Y < 2) & (M.Y >= -2)
    P.fill(near, CLIFF)
    P.fill(near & (M.Y >= 1), GRASS)
    terrace_cliffs(M, P, rng, (-70, 70), (-110, -10), 2, 40, steps=6,
                   falls=((-14, 5, -20), (20, 4, -30)), trees=16)
    for (cx, cy, cz, r) in ((-30, 34, -10, 6), (26, 40, -6, 5), (0, 46, -30, 4)):
        isl = ((M.X - cx) ** 2 + (M.Z - cz) ** 2 <= r ** 2) & (M.Y < cy) & (M.Y >= cy - (r - np.sqrt(np.maximum(0, (M.X - cx) ** 2 + (M.Z - cz) ** 2))) * 1.4)
        P.fill(isl, CLIFF)
        P.fill(isl & (M.Y >= cy - 1), GRASS)
    sc = Scene('cliffs', cam, w, h, (0.5, 0.55), ('#4FA6E3', '#D2ECF9'), [Layer('mid', M, inner_alpha=0.2)],
               seed=seed, clouds=6)
    return sc


def scene_meadow_thumb(w=720, h=480):
    sc = scene_meadow(w, int(w * 2532 / 1170))
    return sc

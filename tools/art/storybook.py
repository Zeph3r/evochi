"""Storybook nature: the small growing and lying things of a scene (bushes, ferns, stones, mushrooms, logs,
stumps, flowers, grass tufts, reeds, lily pads, pebbles) and tiered pines, to go with the puff trees
(village_scenes.puff_tree). Fine voxels (a model at res 6, lit as rounded shapes: model_mesh smooth), each
thing's colour painted along a ramp, dark to light, by where the light falls on it, not picked at random per
block. Every function paints only in its own corner of the grid (a scene has hundreds of these) and only
where the grid is still empty.

  L     the light, pointing toward the sun (unit vector); rng a numpy Generator
"""
import math

import numpy as np

from village_scenes import BARK, _crown, _limb, _local, _ramp

GRASS_R = ['#386F3F', '#427C42', '#4D8945', '#59974A', '#67A54E', '#77B253', '#8ABF5A', '#9FCB66']
PATH_R = ['#80532F', '#8E5E38', '#9C6A41', '#AA774B', '#B78455', '#C39260', '#CEA06C', '#D8AE7B']
SAND_R = ['#A08760', '#B39B72', '#C4AD84', '#D3BE96', '#DFCCA8']
EARTH_R = ['#4E3526', '#5C3F2D', '#6A4934', '#79553C', '#886245']
POND_R = ['#2A6399', '#3270A6', '#3B7EB3', '#478DC0', '#559CCB', '#68ACD5', '#7EBCDD']
BROOK_R = ['#3271A3', '#3C7FB0', '#478DBC', '#559CC8', '#66ABD2', '#7BBADB']
FALLS_R = ['#A9DDF5', '#BFE8FA', '#DFF4FC', '#FFFFFF']
STONE_R = ['#56524D', '#66625A', '#77736A', '#88837A', '#99948A', '#AAA59A', '#BCB7AC']
MOSS_R = ['#365F30', '#416E36', '#4D7E3C', '#5A8E43', '#699E4A', '#7BAE53', '#8FBD5E']
FERN_R = ['#2B6232', '#337238', '#3D823E', '#489245', '#55A14C', '#65AF55', '#79BD60']
BUSH_R = ['#26513A', '#2D623F', '#367343', '#428548', '#51974E', '#64A856', '#7BB960']
PINE_R = ['#183C35', '#1E4A3C', '#255844', '#2D674B', '#377753', '#43885B', '#539964']
REED_R = ['#3F6A31', '#4A7837', '#56873E', '#639646', '#72A44F']
PAD_R = ['#356F33', '#3F7F39', '#4B8F40', '#589D48', '#67AB51', '#79B85C']
STEM_R = ['#C9BEA8', '#D9CFBC', '#E6DDCC', '#F1EADD', '#F8F3EA']
GILL_R = ['#B9A585', '#C8B595', '#D5C3A5']
CAP_RED = ['#7E2420', '#982E27', '#B23A2F', '#C9483A', '#DB5B47', '#E87459']
CAP_BROWN = ['#5E3E25', '#71492C', '#845635', '#97653F', '#A9764B', '#B98858']
RINGS_R = ['#9C774D', '#B08A5E', '#C29C6E', '#D1AD80', '#DDBC91']
CATTAIL_R = ['#4A2F1D', '#5A3A24', '#6B472C', '#7C5535']
FOAM_R = ['#CFEAF6', '#E4F4FB', '#F4FBFE', '#FFFFFF']


def tint(c, f):
    """[c] lightened (f > 0, toward a warm white) or darkened (f < 0, toward a cool shade)"""
    r, g, b = (int(c[i:i + 2], 16) for i in (1, 3, 5))
    if f >= 0:
        t = (255, 250, 232)
        r, g, b = (v + (w - v) * f for v, w in zip((r, g, b), t))
    else:
        t = (26, 30, 52)
        r, g, b = (v + (w - v) * -f for v, w in zip((r, g, b), t))
    return '#%02X%02X%02X' % tuple(int(round(min(255, max(0, v)))) for v in (r, g, b))


def ramp_of(c):
    return [tint(c, -0.4), tint(c, -0.22), c, tint(c, 0.18), tint(c, 0.38)]


def noise2(X, Z, scale, seed, n=7):
    """smooth patches, about -1..1: a few long waves at random angles, added"""
    rng = np.random.default_rng(seed)
    out = 0.0
    for _ in range(n):
        a = rng.uniform(0, math.tau)
        f = rng.uniform(0.6, 1.4) / scale
        out = out + np.sin((X * math.cos(a) + Z * math.sin(a)) * f + rng.uniform(0, math.tau))
    return out / math.sqrt(n / 2) * 0.5


def noise3(X, Y, Z, scale, seed, n=6):
    rng = np.random.default_rng(seed)
    out = 0.0
    for _ in range(n):
        u = rng.normal(size=3)
        u /= np.linalg.norm(u)
        out = out + np.sin((X * u[0] + Y * u[1] + Z * u[2]) * rng.uniform(0.6, 1.4) / scale + rng.uniform(0, math.tau))
    return out / math.sqrt(n / 2) * 0.5


def seg_dist(X, Z, pts):
    """distance from each (X, Z) to a polyline"""
    d = np.full(np.broadcast(X, Z).shape, 1e9)
    for (ax, az), (bx, bz) in zip(pts, pts[1:]):
        vx, vz = bx - ax, bz - az
        t = np.clip(((X - ax) * vx + (Z - az) * vz) / max(1e-9, vx * vx + vz * vz), 0, 1)
        d = np.minimum(d, np.hypot(X - ax - t * vx, Z - az - t * vz))
    return d


def _grid(M, lo, hi):
    sl = _local(M, lo, hi)
    return sl, M.X[sl], M.Y[sl], M.Z[sl], M.m[sl] == 0


def _blobs(Xs, Ys, Zs, blobs):
    """the union of ellipsoids [(centre, (rx, ry, rz))]: how far inside (of its size), and each voxel's normal from
    the one it is deepest in"""
    dep = np.full(Xs.shape, -9.0)
    nx, ny, nz = np.zeros(Xs.shape), np.zeros(Xs.shape), np.zeros(Xs.shape)
    for (c, (rx, ry, rz)) in blobs:
        dx, dy, dz = (Xs - c[0]) / rx, (Ys - c[1]) / ry, (Zs - c[2]) / rz
        dist = np.sqrt(dx * dx + dy * dy + dz * dz) + 1e-6
        d = 1 - dist
        better = d > dep
        dep = np.where(better, d, dep)
        g = np.stack([dx / rx, dy / ry, dz / rz])
        g /= np.linalg.norm(g, axis=0) + 1e-9
        nx, ny, nz = np.where(better, g[0], nx), np.where(better, g[1], ny), np.where(better, g[2], nz)
    return dep, nx, ny, nz


def _lit(nx, ny, nz, L):
    return np.clip(nx * L[0] + ny * L[1] + nz * L[2], -1, 1)


def _side(dx, dz, L, up=0.0):
    """light on a round thing's side, from its axis out (dx, dz), tipped up by [up]"""
    n = np.sqrt(dx * dx + dz * dz + up * up) + 1e-6
    return _lit(dx / n, up / n + 0 * dx, dz / n, L)


def bush(M, x, z, r, L, rng, leaves=BUSH_R, accent=None):
    """a round leafy bush: low puffs, leaf clusters over them, [accent] berries or blossoms on its sunny side"""
    sl, Xs, Ys, Zs, free = _grid(M, (x - 2.3 * r, -0.4, z - 2.3 * r), (x + 2.3 * r, 2.4 * r, z + 2.3 * r))
    puffs = [(np.array([x, r * 0.5, z]), r, 0.78)]
    n = int(rng.integers(3, 6))
    a0 = rng.uniform(0, math.tau)
    for k in range(n):
        a = a0 + k * math.tau / n + rng.uniform(-0.3, 0.3)
        d = r * rng.uniform(0.65, 0.9)
        puffs.append((np.array([x + math.cos(a) * d, r * rng.uniform(0.3, 0.5), z + math.sin(a) * d * 0.85]), r * rng.uniform(0.55, 0.72), 0.78))
    if rng.random() < 0.6:
        puffs.append((np.array([x + rng.uniform(-0.3, 0.3) * r, r * 1.05, z]), r * 0.55, 0.8))
    m = _crown(M, sl, Xs, Ys, Zs, free & (Ys > -0.2), puffs, r * 2.2, leaves, L, rng, accent, 0.0, (x, z),
               cluster=(0.1, 0.14), density=0.9, under=0.95)
    return m


def fern(M, x, z, s, a0, L, rng, leaves=FERN_R):
    """a fan of fronds arching out and drooping, each a rib with leaflets either side, shorter toward its tip"""
    reach = 2.3 * s
    sl, Xs, Ys, Zs, free = _grid(M, (x - reach, -0.2, z - reach), (x + reach, 0.5 + 1.25 * s, z + reach))
    mask = np.zeros(Xs.shape, bool)
    v = np.zeros(Xs.shape)
    nf = int(rng.integers(7, 10))
    top = 0.15 + s * 1.05
    for k in range(nf):
        a = a0 + k * math.tau / nf + rng.uniform(-0.2, 0.2)
        ca, sa = math.cos(a), math.sin(a)
        Lf = s * rng.uniform(1.45, 1.95)
        lift = s * rng.uniform(0.85, 1.1)
        for t in np.linspace(0.05, 1.0, 22):
            px, pz = x + ca * Lf * t, z + sa * Lf * t
            py = 0.12 + lift * math.sin(math.pi * t * 0.82)
            ll = s * 0.4 * (1 - t * 0.75) * (min(1, t * 6))
            for side in (-1, 1):
                if ll < 0.08:
                    continue
                # a leaflet: out to the side, drooping a touch at its end
                mx, mz = px - sa * side * ll * 0.5, pz + ca * side * ll * 0.5
                b = _local(M, (mx - ll * 0.6 - 0.2, py - 0.35, mz - ll * 0.6 - 0.2), (mx + ll * 0.6 + 0.2, py + 0.2, mz + ll * 0.6 + 0.2))
                bb = tuple(slice(max(b[i].start - sl[i].start, 0), max(0, b[i].stop - sl[i].start)) for i in range(3))
                xs, ys, zs = Xs[bb], Ys[bb], Zs[bb]
                u = (xs - mx) * -sa * side + (zs - mz) * ca * side        # along the leaflet
                w = (xs - mx) * ca + (zs - mz) * sa                        # along the rib
                yy = ys - (py - 0.12 * (u / ll + 0.5))
                inside = (u / (ll * 0.5)) ** 2 + (w / 0.13) ** 2 + (yy / 0.1) ** 2 <= 1
                mask[bb] |= inside
                v[bb] = np.where(inside, 0.25 + 0.45 * (py / top) + 0.25 * t + 0.1 * (u / ll), v[bb])
            # the rib
            b = _local(M, (px - 0.15, py - 0.15, pz - 0.15), (px + 0.15, py + 0.15, pz + 0.15))
            bb = tuple(slice(max(b[i].start - sl[i].start, 0), max(0, b[i].stop - sl[i].start)) for i in range(3))
            rib = (Xs[bb] - px) ** 2 + (Ys[bb] - py) ** 2 + (Zs[bb] - pz) ** 2 <= 0.1 ** 2
            mask[bb] |= rib
            v[bb] = np.where(rib, 0.15 + 0.4 * t, v[bb])
    _ramp(M, sl, mask & free, np.clip(v, 0, 1), leaves, rng, 0.05)
    return mask


def stone(M, x, z, r, L, rng, y=0.0, moss=0.55, flat=0.7, tones=STONE_R):
    """a rounded stone, a little lumpy, sunk into the ground; moss on its top where [moss] < its upward slope"""
    sl, Xs, Ys, Zs, free = _grid(M, (x - 1.6 * r, y - r, z - 1.6 * r), (x + 1.6 * r, y + 1.6 * r * flat + 0.3, z + 1.6 * r))
    blobs = [((x, y + r * 0.15, z), (r, r * flat, r * 0.85))]
    for _ in range(int(rng.integers(1, 3))):
        a = rng.uniform(0, math.tau)
        rr = r * rng.uniform(0.5, 0.75)
        blobs.append(((x + math.cos(a) * r * 0.55, y + rr * 0.1, z + math.sin(a) * r * 0.5), (rr, rr * flat, rr * 0.9)))
    dep, nx, ny, nz = _blobs(Xs, Ys, Zs, blobs)
    dep = dep + 0.07 * noise3(Xs, Ys, Zs, r * 0.35, int(rng.integers(1 << 30)))
    m = (dep >= 0) & free & (Ys >= y - r * 0.4)
    lam = _lit(nx, ny, nz, L)
    v = 0.42 + 0.36 * lam + 0.08 * noise3(Xs, Ys, Zs, 0.25, int(rng.integers(1 << 30)))
    _ramp(M, sl, m, np.clip(v, 0, 1), tones, rng, 0.04)
    if moss is not None:
        mo = m & (ny > moss + 0.25 * noise3(Xs, Ys, Zs, r * 0.3, int(rng.integers(1 << 30))))
        _ramp(M, sl, mo, np.clip(0.35 + 0.35 * lam + 0.2 * (ny - moss), 0, 1), MOSS_R, rng, 0.05)
    return m


def shroom(M, x, z, s, L, rng, red=True):
    """a mushroom: a pale stem with a little skirt, a domed cap lit round, white spots on a red one"""
    sl, Xs, Ys, Zs, free = _grid(M, (x - 0.8 * s, -0.1, z - 0.8 * s), (x + 0.8 * s, 1.5 * s, z + 0.8 * s))
    h = 0.85 * s
    lean = rng.uniform(-0.12, 0.12, 2) * s
    t = np.clip(Ys / h, 0, 1)
    cx, cz = x + lean[0] * t, z + lean[1] * t
    stem = (np.hypot(Xs - cx, Zs - cz) <= 0.17 * s * (1.15 - 0.3 * t)) & (Ys < h) & (Ys >= -0.05)
    skirt = (np.abs(Ys - h * 0.62) < 0.06 * s + 0.05) & (np.hypot(Xs - cx, Zs - cz) <= 0.24 * s)
    c = np.array([x + lean[0], h * 0.92, z + lean[1]])
    dep, nx, ny, nz = _blobs(Xs, Ys, Zs, [(c, (0.58 * s, 0.42 * s, 0.58 * s))])
    cap = (dep >= 0) & (Ys >= c[1] - 0.06 * s)
    gills = cap & (Ys < c[1] + 0.05 * s)
    lam = _lit(nx, ny, nz, L)
    _ramp(M, sl, (stem | skirt) & free & ~cap, np.clip(0.4 + 0.3 * _side(Xs - cx, Zs - cz, L) + 0.2 * t, 0, 1), STEM_R, rng, 0.04)
    _ramp(M, sl, gills & free, np.full(Xs.shape, 0.5), GILL_R, rng, 0.2)
    _ramp(M, sl, cap & ~gills & free, np.clip(0.42 + 0.4 * lam, 0, 1), CAP_RED if red else CAP_BROWN, rng, 0.04)
    if red:
        spots = np.zeros(Xs.shape, bool)
        for _ in range(int(rng.integers(5, 9))):
            u = rng.normal(size=3)
            u[1] = abs(u[1]) + 0.4
            u /= np.linalg.norm(u)
            p = c + u * np.array([0.58, 0.42, 0.58]) * s
            spots |= (Xs - p[0]) ** 2 + (Ys - p[1]) ** 2 + (Zs - p[2]) ** 2 <= (0.1 + 0.05 * s) ** 2
        _ramp(M, sl, spots & cap & ~gills & free, np.full(Xs.shape, 0.7), STEM_R[2:], rng, 0.2)
    return stem | cap


def _rings(M, sl, mask, rad, rng):
    _ramp(M, sl, mask, np.clip(0.5 + 0.38 * np.sin(rad * 9.0) - 0.1 * (rad > rad.max() * 0.85), 0, 1), RINGS_R, rng, 0.06)


def log(M, x, z, s, L, rng):
    """a fallen log along x: bark lit round, rings at its ends, moss along its top"""
    Lh = (3.0 + 2.0 * s) / 2
    R = 0.55 * s
    cy = R * 0.85
    sl, Xs, Ys, Zs, free = _grid(M, (x - Lh - 0.3, -0.2, z - R - 0.3), (x + Lh + 0.3, cy + R + 0.4, z + R + 0.3))
    dy, dz = Ys - cy, Zs - z
    rad = np.sqrt(dy * dy + dz * dz)
    body = (rad <= R * (1 + 0.05 * np.sin(Xs * 3.1))) & (np.abs(Xs - x) <= Lh) & free
    ends = body & (np.abs(Xs - x) > Lh - 0.17)
    lam = _lit(0 * Xs, dy / (rad + 1e-6), dz / (rad + 1e-6), L)
    ang = np.arctan2(dz, dy)
    v = 0.45 + 0.32 * lam - 0.16 * (np.sin(ang * 8 + Xs * 0.6) > 0.6)
    _ramp(M, sl, body & ~ends, np.clip(v, 0, 1), BARK, rng, 0.04)
    _rings(M, sl, ends, rad / R, rng)
    mo = body & ~ends & (dy / (rad + 1e-6) > 0.55 + 0.25 * noise2(Xs, Zs, 0.5, int(rng.integers(1 << 30))))
    _ramp(M, sl, mo, np.clip(0.4 + 0.4 * lam, 0, 1), MOSS_R, rng, 0.05)
    shroom(M, x + Lh - 0.5, z + R + 0.25, 0.55, L, rng, red=False)
    return body


def stump(M, x, z, s, L, rng):
    """a cut stump: flaring roots, bark lit round, rings on its top"""
    R, h = 0.8 * s, 1.1 * s
    sl, Xs, Ys, Zs, free = _grid(M, (x - 3 * R, -0.4, z - 3 * R), (x + 3 * R, h + 0.3, z + 3 * R))
    rad = np.hypot(Xs - x, Zs - z)
    flare = R * (1 + 0.5 * np.clip(1 - Ys / (0.6 * s), 0, 1) ** 2)
    body = (rad <= flare * (1 + 0.04 * np.sin(np.arctan2(Zs - z, Xs - x) * 9))) & (Ys < h) & (Ys >= -0.2)
    acc = (np.zeros(Xs.shape, bool), np.full(Xs.shape, -9.0), np.zeros(Xs.shape), np.zeros(Xs.shape), np.zeros(Xs.shape))
    for k in range(int(rng.integers(3, 6))):
        a = rng.uniform(0, math.tau)
        Lr = R * rng.uniform(1.6, 2.4)
        _limb(M, sl, Xs, Ys, Zs, acc, [(x, 0.35 * s, z), (x + math.cos(a) * Lr * 0.6, 0.05, z + math.sin(a) * Lr * 0.6),
                                       (x + math.cos(a) * Lr, -0.3, z + math.sin(a) * Lr)], R * 0.4, R * 0.12)
    top = body & (Ys >= h - 0.17)
    nxr, nzr = (Xs - x) / (rad + 1e-6), (Zs - z) / (rad + 1e-6)
    lam = _lit(nxr, 0 * Xs, nzr, L)
    v = 0.45 + 0.32 * lam - 0.15 * (np.sin(np.arctan2(nzr, nxr) * 8 + Ys * 1.5) > 0.6)
    _ramp(M, sl, (body & ~top) & free, np.clip(v, 0, 1), BARK, rng, 0.04)
    _rings(M, sl, top & free, rad / R, rng)
    roots = acc[0] & ~body & free
    _ramp(M, sl, roots, np.clip(0.42 + 0.3 * _lit(acc[2], acc[3], acc[4], L), 0, 1), BARK, rng, 0.04)
    return body | acc[0]


def flower(M, x, z, col, L, rng, h=None):
    """a little flower: a stem with two leaves, a head of five petals round a bright middle"""
    h = h or rng.uniform(0.45, 0.85)
    sl, Xs, Ys, Zs, free = _grid(M, (x - 0.6, -0.1, z - 0.6), (x + 0.6, h + 0.35, z + 0.6))
    lean = rng.uniform(-0.15, 0.15, 2)
    t = np.clip(Ys / h, 0, 1)
    sx, sz = x + lean[0] * t * t, z + lean[1] * t * t
    stem = (np.abs(Xs - sx) < 0.09) & (np.abs(Zs - sz) < 0.09) & (Ys < h) & (Ys >= -0.05)
    leaf = np.zeros(Xs.shape, bool)
    for side in (-1, 1):
        a = rng.uniform(0, math.pi) + (math.pi if side > 0 else 0)
        lx, lz, ly = x + math.cos(a) * 0.17, z + math.sin(a) * 0.17, h * rng.uniform(0.2, 0.45)
        leaf |= ((Xs - lx) / 0.2) ** 2 + ((Ys - ly) / 0.09) ** 2 + ((Zs - lz) / 0.2) ** 2 <= 1
    hx, hz = x + lean[0], z + lean[1]
    petals = np.zeros(Xs.shape, bool)
    a0 = rng.uniform(0, math.tau)
    for k in range(5):
        a = a0 + k * math.tau / 5
        px, pz = hx + math.cos(a) * 0.15, hz + math.sin(a) * 0.15
        petals |= ((Xs - px) ** 2 + (Zs - pz) ** 2 <= 0.13 ** 2) & (np.abs(Ys - h - 0.04 - 0.03 * np.hypot(Xs - hx, Zs - hz)) < 0.09)
    mid = ((Xs - hx) ** 2 + (Zs - hz) ** 2 + (Ys - h - 0.1) ** 2 <= 0.1 ** 2)
    green = ['#3E7A35', '#4B8A3C', '#5A9A44']
    _ramp(M, sl, (stem | leaf) & free, np.clip(0.3 + 0.5 * t, 0, 1), green, rng, 0.1)
    rad = np.hypot(Xs - hx, Zs - hz)
    _ramp(M, sl, petals & ~mid & free, np.clip(0.35 + 0.4 * rad / 0.28 + 0.15 * (Ys > h), 0, 1), ramp_of(col)[1:], rng, 0.08)
    _ramp(M, sl, mid & free, np.full(Xs.shape, 0.6), ['#C98A22', '#E2A930', '#F4C451'], rng, 0.2)
    return stem | petals


def tuft(M, x, z, s, L, rng, tones=GRASS_R, lo=2):
    """a tuft of grass: blades from one spot, leaning out, dark at the foot, light at the tips"""
    sl, Xs, Ys, Zs, free = _grid(M, (x - 0.9 * s, -0.2, z - 0.9 * s), (x + 0.9 * s, 1.2 * s, z + 0.9 * s))
    mask = np.zeros(Xs.shape, bool)
    v = np.zeros(Xs.shape)
    for _ in range(int(rng.integers(5, 10))):
        a = rng.uniform(0, math.tau)
        bx, bz = x + rng.uniform(-0.12, 0.12) * s, z + rng.uniform(-0.12, 0.12) * s
        hh = s * rng.uniform(0.45, 0.95)
        out = s * rng.uniform(0.15, 0.55)
        for t in np.linspace(0, 1, 9):
            px, pz, py = bx + math.cos(a) * out * t * t, bz + math.sin(a) * out * t * t, hh * t
            r = 0.1 * (1 - 0.5 * t)
            b = (Xs - px) ** 2 + (Ys - py) ** 2 + (Zs - pz) ** 2 <= max(r, 0.085) ** 2
            mask |= b
            v = np.where(b, np.maximum(v, 0.2 + 0.75 * t), v)
    _ramp(M, sl, mask & free, np.clip(v * (len(tones) - lo) / len(tones) + lo / len(tones), 0, 1), tones, rng, 0.05)
    return mask


def reeds(M, x, z, L, rng, n=None):
    """a clump of reeds by the water: tall stems, a cattail on some, a long blade or two curving out"""
    sl, Xs, Ys, Zs, free = _grid(M, (x - 1.2, -1.6, z - 1.2), (x + 1.2, 3.6, z + 1.2))
    stems = np.zeros(Xs.shape, bool)
    v = np.zeros(Xs.shape)
    heads = np.zeros(Xs.shape, bool)
    for _ in range(n or int(rng.integers(3, 7))):
        bx, bz = x + rng.uniform(-0.45, 0.45), z + rng.uniform(-0.45, 0.45)
        hh = rng.uniform(1.3, 2.7)
        lx, lz = rng.uniform(-0.3, 0.3, 2)
        t = np.clip((Ys + 1.0) / (hh + 1.0), 0, 1)
        sx, sz = bx + lx * t * t, bz + lz * t * t
        st = (np.abs(Xs - sx) < 0.1) & (np.abs(Zs - sz) < 0.1) & (Ys >= -1.2) & (Ys < hh)
        stems |= st
        v = np.where(st, 0.2 + 0.7 * t, v)
        if rng.random() < 0.45:
            heads |= (np.abs(Xs - (bx + lx * 0.8)) < 0.16) & (np.abs(Zs - (bz + lz * 0.8)) < 0.16) & (Ys >= hh - 0.65) & (Ys < hh - 0.12)
    _ramp(M, sl, stems & ~heads & free, np.clip(v, 0, 1), REED_R, rng, 0.05)
    _ramp(M, sl, heads & free, np.clip(0.45 + 0.3 * _side(Xs - x, Zs - z, L), 0, 1), CATTAIL_R, rng, 0.1)
    tuft(M, x + rng.uniform(-0.3, 0.3), z + rng.uniform(-0.3, 0.3), 1.6, L, rng, REED_R, 0)
    return stems


def lily(M, x, z, rad, y, L, rng, bloom=None):
    """a lily pad on the water, a notch cut in it; on some a flower of upturned petals"""
    sl, Xs, Ys, Zs, free = _grid(M, (x - rad - 0.2, y - 0.1, z - rad - 0.2), (x + rad + 0.2, y + 0.7, z + rad + 0.2))
    a0 = rng.uniform(0, math.tau)
    rr = np.hypot(Xs - x, Zs - z)
    ang = np.angle(np.exp(1j * (np.arctan2(Zs - z, Xs - x) - a0)))
    pad = (rr <= rad) & (np.abs(Ys - y - 0.08) < 0.09) & ~((np.abs(ang) < 0.32) & (rr > rad * 0.15))
    v = 0.4 + 0.3 * (rr / rad) - 0.15 * (np.cos(ang * 7) > 0.85) * (rr > rad * 0.3) + 0.15 * _side(Xs - x, Zs - z, L, 0.6)
    _ramp(M, sl, pad & free, np.clip(v, 0, 1), PAD_R, rng, 0.05)
    if bloom:
        cx, cz = x + rng.uniform(-0.15, 0.15) * rad, z + rng.uniform(-0.15, 0.15) * rad
        pet = np.zeros(Xs.shape, bool)
        for ring, (n, d, up) in enumerate(((7, 0.17, 0.12), (5, 0.08, 0.26))):
            for k in range(n):
                a = k * math.tau / n + ring * 0.4
                px, pz = cx + math.cos(a) * d, cz + math.sin(a) * d
                pet |= ((Xs - px) / 0.11) ** 2 + ((Zs - pz) / 0.11) ** 2 + ((Ys - (y + 0.2 + up)) / 0.16) ** 2 <= 1
        mid = (Xs - cx) ** 2 + (Zs - cz) ** 2 + (Ys - y - 0.3) ** 2 <= 0.08 ** 2
        _ramp(M, sl, pet & ~mid & free, np.clip(0.35 + 1.4 * (Ys - y - 0.15), 0, 1), [tint(bloom, -0.2), bloom, tint(bloom, 0.4), '#FFF6F8'], rng, 0.08)
        _ramp(M, sl, mid & free, np.full(Xs.shape, 0.6), ['#E2A930', '#F4C451'], rng, 0.2)
    return pad


def pebbles(M, x, z, spread, n, L, rng, tones=STONE_R):
    for _ in range(n):
        a, d = rng.uniform(0, math.tau), spread * math.sqrt(rng.random())
        stone(M, x + math.cos(a) * d, z + math.sin(a) * d, rng.uniform(0.12, 0.26), L, rng, y=-0.06, moss=None, flat=0.55, tones=tones[1:])


def foam(M, x, z, w, d, y, L, rng, n=14):
    """white water where a fall lands: soft lumps on the surface"""
    sl, Xs, Ys, Zs, free = _grid(M, (x - w - 0.5, y - 0.3, z - d - 0.5), (x + w + 0.5, y + 0.8, z + d + 0.5))
    blobs = []
    for _ in range(n):
        r = rng.uniform(0.22, 0.5)
        blobs.append(((x + rng.uniform(-w, w), y + r * 0.2, z + rng.uniform(-d, d)), (r, r * 0.55, r)))
    dep, nx, ny, nz = _blobs(Xs, Ys, Zs, blobs)
    m = (dep >= 0) & free & (Ys >= y - 0.05)
    _ramp(M, sl, m, np.clip(0.35 + 0.5 * _lit(nx, ny, nz, L), 0, 1), FOAM_R, rng, 0.06)
    return m


def pine(M, x, z, h, r, L, rng, y=0.0, leaves=PINE_R):
    """a pine in drooping tiers, narrowing to a tip: each tier a flat puff with a ring of lower lobes round it,
    leaf clusters over them; its trunk shows below the lowest"""
    sl, Xs, Ys, Zs, free = _grid(M, (x - 2.2 * r, y - 0.5, z - 2.2 * r), (x + 2.2 * r, y + h + 1.5, z + 2.2 * r))
    n = 5 if h < 10.5 else 6
    puffs = []
    for i in range(n):
        t = i / (n - 1)
        ty = y + 2.0 + t * (h - 2.6)
        R = r * (1.0 - t * 0.78) + 0.35
        puffs.append((np.array([x, ty, z]), R * 0.62, 0.42))
        m = max(4, int(4 + 5 * R / r))
        a0 = rng.uniform(0, math.tau)
        for k in range(m):
            a = a0 + k * math.tau / m + rng.uniform(-0.2, 0.2)
            puffs.append((np.array([x + math.cos(a) * R * 0.62, ty - R * 0.2, z + math.sin(a) * R * 0.62]), R * rng.uniform(0.4, 0.5), 0.5))
    puffs.append((np.array([x, y + h, z]), 0.45, 1.2))
    crown = _crown(M, sl, Xs, Ys, Zs, free, puffs, r, leaves, L, rng, None, 0.0, (x, z), cluster=(0.1, 0.15), density=0.75, under=0.95)
    free &= ~crown
    acc = (np.zeros(Xs.shape, bool), np.full(Xs.shape, -9.0), np.zeros(Xs.shape), np.zeros(Xs.shape), np.zeros(Xs.shape))
    t0 = 0.32 + 0.05 * r
    _limb(M, sl, Xs, Ys, Zs, acc, [(x, y - 0.3, z), (x, y + h * 0.75, z)], t0, t0 * 0.4)
    _limb(M, sl, Xs, Ys, Zs, acc, [(x, y - 0.3, z), (x, y + 0.6, z)], t0 * 1.5, t0)
    for k in range(3):
        a = rng.uniform(0, math.tau)
        _limb(M, sl, Xs, Ys, Zs, acc, [(x, y + 0.4, z), (x + math.cos(a) * t0 * 2.6, y - 0.3, z + math.sin(a) * t0 * 2.6)], t0 * 0.5, t0 * 0.18)
    lw = _lit(acc[2], acc[3], acc[4], L)
    _ramp(M, sl, acc[0] & free, np.clip(0.4 + 0.32 * lw - 0.2 * np.clip(1 - (Ys - y) / 0.6, 0, 1), 0, 1), BARK, rng, 0.04)
    return crown | acc[0]


def own_model(fn, x, z, reach, top, *a, res=6, bottom=-1.5, **kw):
    """[fn](M, x, z, ...) in a fine grid of its own (its coordinate grids let go once it is built)"""
    import voxel
    from voxel import Model
    M = Model((math.floor(x - reach), math.floor(bottom), math.floor(z - reach)), (math.ceil(x + reach), math.ceil(top), math.ceil(z + reach)), [], res=res)
    fn(M, x, z, *a, **kw)
    M.X = M.Y = M.Z = None
    voxel._GRIDS.clear()
    return M

"""Villagers lit by their own rooms, in Blender (Cycles), as animatable layers.

Each villager is placed, at the size and spot where the game draws them, inside the voxel room
they live in (Bram in the Workshop, Mira in the Glasshouse, Pip and Alder in the Trail Guild).
The room is invisible to the camera but still lights them: lanterns, the forge, sun through the
windows and bounce light from walls and floor.

They are rendered in parts (village_npcs tags every voxel body / head / arm) so the game can
animate them: the head nods and tilts about the neck, the arm (with Bram's wrench, Mira's seedling,
Pip's letter, Alder's map) swings about the shoulder, and a blink overlay closes the eyes. Each
part is rendered alone with the other parts hidden from the camera but still casting light and
shadow, so the layers stack back into exactly the full render.

    export(...)      -> NAME.npz: voxel faces per part with smoothed normals, the painted face per
                        expression (texture + projection), framing, placement in the room
    npc_blender.py   -> NAME_<part>.png, NAME_head_<expr>.png, NAME_shadow.png (needs only bpy)
    finish(...)      -> ink outline and inner lines (from the flat renderer, shared out to the parts),
                        floor shadow, crops; plus "classic" flat-shaded layers for comparison

Run through build_village.py (part `npcs`), which needs BPY_PYTHON like the scenes.
"""
from __future__ import annotations

import json
import math
import os
import subprocess
import tempfile

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

from voxel import Camera, Light, collect_faces, fast_rasterize, edges_from_depth, downsample, hexrgb, project_px, render
from decals import Surface, Canvas, quads_to_polys
from characters import paint_face
from palettes import ACCESSORY

HERE = os.path.dirname(os.path.abspath(__file__))

# Where each villager stands on their room's (portrait) plate: the point under their feet as a fraction
# of the plate, whether they are drawn mirrored, and an exposure trim (they stand in the foreground,
# close to each room's big front light, and their pastel colours were picked for the flat renderer).
HOME = {
    'bram': ('workshop', dict(gx=0.41, gy=0.80, mirror=False, ev=-0.45)),
    'mira': ('glasshouse', dict(gx=0.37, gy=0.80, mirror=False, ev=-0.55)),
    'pip': ('lodge', dict(gx=0.27, gy=0.80, mirror=False, ev=-0.2)),
    # Alder stands on the right, drawn mirrored: render him on the left of a mirrored room, so the
    # flipped sprite carries the room's real light direction.
    'alder': ('lodge', dict(gx=0.73, gy=0.80, mirror=True, ev=-0.35)),
    # Sher (wilds_npcs.py), the Wilds' cat: lit by the Trail Guild Lodge, standing between Pip and Alder
    'sher': ('lodge', dict(gx=0.5, gy=0.80, mirror=False, ev=-0.3)),
}
UNIT = 0.0011          # plate height per sprite pixel (x the villager's size): one scale for everyone

FACE_CELL = 0.07
SMOOTH = 1.0           # blend of smoothed vs. voxel face normal used for shading
SMOOTH_SIGMA = 2.2     # voxels (the flat renderer used 3.2)
OUTLINE_PX = 0.21      # x fit.scale: the original villager outline weight
PART_NAMES = ('body', 'head', 'arm')

FACES = [  # normal, 4 corner offsets (voxel min corner), CCW seen from outside
    ((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
    ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
    ((0, 1, 0), [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]),
    ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
    ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
    ((0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)]),
]


# ----------------------------------------------------------------------------- export
def npc_palette(ch, outline):
    pal = dict(ch.palette)
    pal['outline'] = outline
    for k, v in ACCESSORY.items():
        pal['acc_' + k] = v
    return pal


def mat_colours(M, pal):
    cols = {}
    for mid, name in enumerate(M.mats):
        if mid == 0:
            continue
        c = pal.get(name)
        if c is None:
            b = name.split('.')[0]
            c = b if b.startswith('#') else pal.get(b, '#ff00ff')
        cols[mid] = hexrgb(c) if isinstance(c, str) else np.asarray(c, np.float32)
    return cols


def mesh_arrays(M, pal, smooth=SMOOTH, sigma=SMOOTH_SIGMA, seed=11):
    """Exposed voxel faces of every part (a face between two parts belongs to both, so each part is
    closed on its own): corners (N,4,3) in model units, face normal, sRGB colour, per-corner normal, part."""
    filled = M.m > 0
    L = np.where(filled, M.layer.astype(np.int16) + 1, 0)
    pad = np.pad(L, 1)
    surf = Surface(M, sigma=sigma / M.res)   # Surface blurs by sigma * res voxels
    rng = np.random.default_rng(seed)
    jit = 1.0 + (rng.random(M.m.shape).astype(np.float32) - 0.5) * 0.03
    cols = mat_colours(M, pal)
    C, N, COL, VN, PART = [], [], [], [], []
    for normal, corners in FACES:
        nx, ny, nz = normal
        nb = pad[1 + nx:1 + nx + M.m.shape[0], 1 + ny:1 + ny + M.m.shape[1], 1 + nz:1 + nz + M.m.shape[2]]
        idx = np.argwhere(filled & (nb != L))
        if not len(idx):
            continue
        base = idx + M.lo
        P = (base[:, None, :] + np.array(corners)[None]) / float(M.res)
        mids = M.m[idx[:, 0], idx[:, 1], idx[:, 2]]
        col = np.stack([cols[m] for m in mids]) * jit[idx[:, 0], idx[:, 1], idx[:, 2]][:, None]
        sn = surf.normal(P.reshape(-1, 3)).reshape(-1, 4, 3)
        fn = np.broadcast_to(np.array(normal, np.float64), sn.shape)
        vn = smooth * sn + (1 - smooth) * fn
        vn /= np.maximum(np.linalg.norm(vn, axis=-1, keepdims=True), 1e-6)
        C.append(P)
        N.append(np.broadcast_to(np.array(normal, np.float32), (len(idx), 3)))
        COL.append(np.clip(col, 0, 255))
        VN.append(vn)
        PART.append(M.layer[idx[:, 0], idx[:, 1], idx[:, 2]])
    return (np.concatenate(C).astype(np.float32), np.concatenate(N).astype(np.float32),
            np.concatenate(COL).astype(np.float32), np.concatenate(VN).astype(np.float32),
            np.concatenate(PART).astype(np.uint8))


def shadow_proxy(M, pal, sigma=0.6, iso=0.88):
    """A smooth, slightly shrunk stand-in surface (marching cubes) that casts the villager's shadows and
    occludes bounce light. The visible voxel mesh does neither, so its stair-steps never shade themselves."""
    from skimage.measure import marching_cubes
    filled = M.m > 0
    b = ndimage.gaussian_filter(filled.astype(np.float32), sigma, mode='constant')
    b = np.pad(b, 1)
    V, F, _, _ = marching_cubes(b, iso)
    V = V - 1.0                            # index space: integer = voxel centre
    idx = np.clip(np.round(V).astype(int), 0, np.array(M.m.shape) - 1)
    _, near = ndimage.distance_transform_edt(~filled, return_indices=True)
    ni = near[:, idx[:, 0], idx[:, 1], idx[:, 2]]
    mids = M.m[ni[0], ni[1], ni[2]]
    cols = mat_colours(M, pal)
    pc = np.stack([cols.get(int(m), np.array([128, 128, 128], np.float32)) for m in mids]).astype(np.float32)
    P = (V + 0.5 + M.lo) / float(M.res)    # voxel index space -> model units
    return P.astype(np.float32), F.astype(np.int32), pc


def face_projection(ch, C, Nf, PART, tol=0.8):
    """UV of every face corner in the painted-face canvas, and which faces carry the paint.

    The flat renderer projects the canvas along -n onto the smoothed surface; the same projection as
    a texture lands on the voxel faces that are first hit from the front (head part only)."""
    fr = ch.face
    u, v, n = fr.basis()
    c = np.array(fr.center, np.float64)
    u0, u1, v0, v1 = ch.face_extent
    cv = Canvas(u0, u1, v0, v1, cell=FACE_CELL)
    nv, nu = cv.a.shape
    span_u, span_v = nu * FACE_CELL, nv * FACE_CELL
    rel = C.astype(np.float64) - c
    uv = np.stack([((rel @ u) - u0) / span_u, ((rel @ v) - v0) / span_v], -1).astype(np.float32)
    surf = Surface(getattr(ch, 'decal_model', None) or ch.model, sigma=0.75)
    O = c[None] + cv.U.reshape(-1, 1) * u + cv.V.reshape(-1, 1) * v + n * fr.reach
    D = np.repeat(-n[None], len(O), 0)
    H = surf.cast(O, D, tmax=fr.reach * 1.6, step=0.04)
    depth = ((H - c) @ n).reshape(nv, nu)
    cen = rel.mean(1)
    cu, cvv, cn = cen @ u, cen @ v, cen @ n
    i = np.floor((cu - u0) / FACE_CELL).astype(int)
    j = np.floor((cvv - v0) / FACE_CELL).astype(int)
    ok = (i >= 0) & (i < nu) & (j >= 0) & (j < nv)
    d = np.full(len(C), np.nan)
    d[ok] = depth[j[ok], i[ok]]
    facing = Nf @ n.astype(np.float32) > -0.3
    mask = ok & np.isfinite(d) & (cn >= d - tol) & facing & (PART == 1)
    nd = getattr(ch, 'no_decal', None)
    if nd is not None:                       # never on what stands in front of the face (spectacles)
        M = ch.model
        vox = np.floor((cen + c - Nf * (0.5 / M.res)) * M.res).astype(int) - M.lo
        vox = np.clip(vox, 0, np.array(M.m.shape) - 1)
        mask &= ~nd[vox[:, 0], vox[:, 1], vox[:, 2]]
    return uv, mask.astype(np.float32)


def face_canvas(ch, pal, expr):
    cv = Canvas(*ch.face_extent, cell=FACE_CELL)
    paint_face(ch, cv, pal, expr)
    rgba = np.dstack([np.clip(cv.rgb, 0, 255), cv.a[..., None] * 255]).astype(np.uint8)
    lit = (np.clip(cv.lit, 0, 1) * 255).astype(np.uint8)
    return rgba, lit


def eye_boxes(ch, cam, fit, pad=1.0):
    """Sprite-pixel boxes around both eyes (where the blink overlay goes)."""
    fr = ch.face
    u, v, n = fr.basis()
    c = np.array(fr.center, np.float64)
    surf = Surface(getattr(ch, 'decal_model', None) or ch.model, sigma=0.75)
    boxes = []
    for s in (-1, 1):
        us = [s * ch.eye_u - ch.eye_w * 1.35, s * ch.eye_u + ch.eye_w * 1.35]
        vs = [ch.eye_v - ch.eye_h * 0.62, ch.eye_v + ch.eye_h * 0.58]
        pts = np.array([[a, b] for a in np.linspace(*us, 5) for b in np.linspace(*vs, 5)])
        O = c[None] + pts[:, :1] * u + pts[:, 1:] * v + n * fr.reach
        H = surf.cast(O, np.repeat(-n[None], len(O), 0), tmax=fr.reach * 1.6, step=0.04)
        H = H[np.isfinite(H).all(1)]
        if not len(H):
            continue
        px = project_px(cam, fit, H)
        boxes.append([float(px[:, 0].min() - pad), float(px[:, 1].min() - pad),
                      float(px[:, 0].max() + pad), float(px[:, 1].max() + pad)])
    return boxes


def room_camera_ray(cam, W, H, px, py):
    """Ray (origin, dir) through pixel (px, py) of a VScene perspective camera (vertical fov)."""
    pos = np.array(cam['pos'], float)
    fwd = np.array(cam['target'], float) - pos
    fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, [0, 1, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    t = math.tan(math.radians(cam['fov']) / 2)
    sx = (px - W / 2) / (H / 2) * t
    sy = (H / 2 - py) / (H / 2) * t
    d = fwd + right * sx + up * sy
    return pos, d / np.linalg.norm(d), fwd


def stage_layout(ch, fit, lay):
    """How the game draws the villager on the plate: feet at (gx, gy), height hf of the plate."""
    return {'gx': lay['gx'], 'gy': lay['gy'], 'hf': round(UNIT * fit.h * getattr(ch, 'size', 1.0), 4),
            'flip': bool(lay['mirror'])}


def placement(ch, cam: Camera, fit, room_cam, RW, RH, lay):
    """Where (and how big, and turned how far) the villager stands in its room, in room units."""
    st = stage_layout(ch, fit, lay)
    g = np.array(ch.anchors['ground'], float)
    gx = 1 - st['gx'] if lay['mirror'] else st['gx']      # mirrored room: stand on the mirrored spot
    px, py = gx * RW, st['gy'] * RH
    k = st['hf'] * RH / fit.h                    # plate px per sprite px
    o, d, fwd = room_camera_ray(room_cam, RW, RH, px, py)
    t = -o[1] / d[1]                              # floor is y = 0
    P0 = o + d * t
    f_px = (RH / 2) / math.tan(math.radians(room_cam['fov']) / 2)
    depth = (P0 - o) @ fwd
    s = (fit.scale * k) / (f_px / depth)          # room units per model unit
    to_cam = o - P0
    yaw_room = math.degrees(math.atan2(to_cam[0], to_cam[2]))
    return {'P0': P0.tolist(), 's': float(s), 'yaw': float(yaw_room - cam.yaw), 'ground_model': g.tolist()}


def pack_room(room, work):
    import village_scenes as VS
    import scene_pack
    path = os.path.join(work, f'room_{room}.npz')
    vs = VS.SCENES[room]()
    if not os.path.exists(path):
        scene_pack.pack(vs, path)
    return vs, path


def export(name, ch, cam: Camera, fit, outline, work, expressions):
    room, lay = HOME[name]
    vs, room_path = pack_room(room, work)
    pal = npc_palette(ch, outline)
    C, Nf, COL, VN, PART = mesh_arrays(ch.model, pal)
    uv, fmask = face_projection(ch, C, Nf, PART)
    faces = {}
    for e in list(expressions) + ['blink']:
        rgba, lit = face_canvas(ch, pal, expressions.get(e, e))
        faces['face_' + e] = rgba
        faces['lit_' + e] = lit
    PV, PF, PC = shadow_proxy(ch.model, pal)
    pl = placement(ch, cam, fit, vs.cam, vs.w, vs.h, lay)
    parts = sorted(int(p) for p in np.unique(PART))
    meta = dict(name=name, room=room, room_pack=os.path.basename(room_path), mirror=lay['mirror'], w=fit.w, h=fit.h,
                scale=fit.scale, ox=fit.ox, oy=fit.oy, ev=lay.get('ev', 0.0), cam_yaw=cam.yaw, pitch=cam.pitch,
                expressions=list(expressions) + ['blink'], parts=[PART_NAMES[p] for p in parts], grade=vs.grade, **pl)
    path = os.path.join(work, f'{name}.npz')
    np.savez_compressed(path, C=C, N=Nf, COL=COL, VN=VN, UV=uv, FMASK=fmask, PART=PART, PV=PV, PF=PF, PC=PC,
                        meta=json.dumps(meta), **faces)
    return meta, path


# ----------------------------------------------------------------------------- lines + classic layers
def _part_model(M, keep):
    o = M.copy()
    o.m = np.where(np.isin(M.layer, keep) & (M.m > 0), M.m, 0).astype(np.uint8)
    return o


def line_layers(ch, cam: Camera, fit, pal, outline_px, ss=3, inner_thresh=2.2, inner_px=None):
    """Silhouette ring + inner depth lines of the whole villager, exactly where the flat renderer
    draws them, and which part owns each line pixel (the part in front there, or nearest to it)."""
    M = ch.model
    Cq, cols, deps, mids, alps = collect_faces(M, pal, cam, Light())
    img, alpha, idb, dep = fast_rasterize(Cq, cols, deps, mids, alps, cam, fit, ss)
    Mp = M.copy()
    Mp.m = np.where(M.m > 0, M.layer.astype(np.uint8) + 1, 0).astype(np.uint8)
    Mp.mats = ['empty'] + [f'p{i}' for i in range(8)]
    Mp.ids = {n: i for i, n in enumerate(Mp.mats)}
    pc, pcols, pdeps, pmids, palps = collect_faces(Mp, {f'p{i}': '#000000' for i in range(8)}, cam, Light())
    _, _, pid, _ = fast_rasterize(pc, pcols, pdeps, pmids, palps, cam, fit, ss)
    inner_px = inner_px if inner_px is not None else max(0.6, fit.scale * 0.045)
    h, w = fit.h, fit.w
    e = edges_from_depth(dep, idb, inner_thresh)
    k = max(1, int(round(inner_px * ss)))
    e = cv2.dilate(e.astype(np.uint8), np.ones((k, k), np.uint8)).astype(np.float32) * (alpha > 0)
    em = e[:h * ss, :w * ss].reshape(h, ss, w, ss).mean((1, 3))
    inv = (alpha < 0.5).astype(np.uint8)
    dist = cv2.distanceTransform(inv, cv2.DIST_L2, 5)
    ol = np.clip(outline_px * ss + 0.5 - dist, 0, 1).astype(np.float32)
    ring = ol[:h * ss, :w * ss].reshape(h, ss, w, ss).mean((1, 3))
    a = alpha[:h * ss, :w * ss].reshape(h, ss, w, ss).mean((1, 3))
    ref = img[:h * ss, :w * ss].reshape(h, ss, w, ss, 3).mean((1, 3))     # flat, neutral-lit colours
    own = pid[ss // 2::ss, ss // 2::ss][:h, :w]
    if (own == 0).any() and (own > 0).any():
        _, near = ndimage.distance_transform_edt(own == 0, return_indices=True)
        own = own[near[0], near[1]]
    return dict(em=em.astype(np.float32), ring=ring.astype(np.float32), a=a.astype(np.float32),
                ref=ref.astype(np.float32), owner=(own.astype(np.int16) - 1))


def classic_layers(ch, cam, fit, pal, pal_key, expressions, ss=3):
    """The original flat-shaded look, rendered per part (colour only; ink is added like the lit ones)."""
    from charrender import face_quads
    out = {}
    parts = sorted(int(p) for p in np.unique(ch.model.layer[ch.model.m > 0]))
    for p in parts:
        Mp = _part_model(ch.model, [p])
        keys = (list(expressions) + ['blink']) if PART_NAMES[p] == 'head' else [None]
        for e in keys:
            decals = None
            if e is not None:
                q = face_quads(ch, pal, pal_key, expressions.get(e, e))
                decals = quads_to_polys(q, cam, Light(), bias=0.3)
            Cq, cols, deps, mids, alps = collect_faces(Mp, pal, cam, Light())
            img, alpha, idb, dep = fast_rasterize(Cq, cols, deps, mids, alps, cam, fit, ss, decals)
            col, a = downsample(img, alpha, ss)
            out[(PART_NAMES[p], e)] = np.dstack([np.clip(col, 0, 255), np.clip(a * 255, 0, 255)]).astype(np.uint8)
    return out


# ----------------------------------------------------------------------------- finish
LUM = np.array([0.2126, 0.7152, 0.0722], np.float32)


def stack(layers, order):
    """Alpha-over a dict of float RGBA layers (0..1) in z-order."""
    first = layers[order[0]]
    col = first[..., :3] * first[..., 3:4]
    al = first[..., 3].copy()
    for k in order[1:]:
        L = layers[k]
        a = L[..., 3:4]
        col = L[..., :3] * a + col * (1 - a)
        al = L[..., 3] + al * (1 - L[..., 3])
    return np.dstack([col / np.maximum(al[..., None], 1e-6), al])


def cast_gain(rest, lines, keep_cast=0.3):
    """Per-channel gain that removes (1 - keep_cast) of the room light's colour cast, measured on the
    composed villager against its flat, neutral-lit colours. Lantern and forge light is deep orange; at
    full strength it would turn Bram's brown fur ginger and Alder's sage skin yellow."""
    col, al = rest[..., :3], rest[..., 3]
    m = (al > 0.99) & (lines['a'] > 0.99)
    if m.sum() < 100:
        return np.ones(3, np.float32)
    cr = col[m].mean(0) / max(float(col[m].mean(0) @ LUM), 1e-6)
    rr = lines['ref'][m].mean(0) / 255.0
    rr = rr / max(float(rr @ LUM), 1e-6)
    gain = (rr / np.maximum(cr, 1e-6)) ** (1 - keep_cast)
    return (gain / float(gain @ LUM)).astype(np.float32)


def grade(rgba, gain=None, sat=0.9, warm=0.0):
    col = rgba[..., :3]
    if gain is not None:
        col = col * gain
    if sat != 1:
        y = (col @ LUM)[..., None]
        col = y + (col - y) * sat
    if warm:
        col = col * np.array([1 + warm, 1.0, 1 - warm], np.float32)
    return np.dstack([col, rgba[..., 3]])


def ink(rgba, lines, part, outline_col, inner=0.8):
    """Add the part's share of the ink: inner lines on it, and the silhouette ring around it."""
    own = lines['owner'] == part
    oc = hexrgb(outline_col) / 255.0
    col, al = rgba[..., :3], rgba[..., 3]
    em = lines['em'] * own * inner
    col = col * (1 - em[..., None]) + oc * em[..., None]
    ra = lines['ring'] * own
    out_a = al + ra * (1 - al)
    col = (col * al[..., None] + oc * (ra * (1 - al))[..., None]) / np.maximum(out_a[..., None], 1e-6)
    return np.dstack([col, out_a])


def shadow_layer(shadow_rgba, flat_a, ground_px, amt=0.8):
    sa = shadow_rgba[..., 3].astype(np.float32) / 255.0
    hole = flat_a > 0.02            # the held-out character left a hole: close it under the sprite
    sa = np.where(hole, np.maximum(sa, ndimage.grey_dilation(sa, size=(9, 9))), sa)
    h, w = sa.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    gx, gy = ground_px
    r = np.sqrt(((xx - gx) / (w * 0.5)) ** 2 + ((yy - gy) / (h * 0.12)) ** 2)
    sa = np.clip(sa * np.clip(1.25 - r, 0, 1) ** 1.2 * amt, 0, 1)
    sc = np.array([0.16, 0.10, 0.05], np.float32)
    return np.dstack([np.broadcast_to(sc, (h, w, 3)), sa])


def to8(rgba):
    return (np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8)


def bbox(a, pad=3):
    ys, xs = np.nonzero(a > 2)
    if not len(ys):
        return (0, 0, 1, 1)
    h, w = a.shape
    return (max(0, xs.min() - pad), max(0, ys.min() - pad), min(w, xs.max() + 1 + pad), min(h, ys.max() + 1 + pad))


def render_all(out_dir, builders, cam, scale, outline, expressions, fit_for, only=None, samples=None, keep=None,
               gpu=False):
    """Export -> Blender -> finish for every villager. Returns npc.json-style meta."""
    py = os.environ.get('BPY_PYTHON')
    work = keep or tempfile.mkdtemp(prefix='village_npc_')
    os.makedirs(work, exist_ok=True)
    meta = {}
    for name, b in builders.items():
        if only and name not in only:
            continue
        ch = b()
        fit = fit_for([ch.model], cam, scale)
        if getattr(ch, 'whiskers', None):
            # widen the frame for whiskers reaching past the head
            from voxel import model_extent_points, Fit
            P = np.concatenate([model_extent_points(ch.model)] + [wk.points() for wk in ch.whiskers])
            sx, sy, _ = cam.project(P)
            pad = 10
            w = int(np.ceil((sx.max() - sx.min()) * scale + 2 * pad))
            h = int(np.ceil((sy.max() - sy.min()) * scale + 2 * pad))
            fit = Fit(scale, pad - sx.min() * scale, pad - sy.min() * scale, w + w % 2, h + h % 2)
        m, npz = export(name, ch, cam, fit, outline, work, expressions)
        if not os.environ.get('NPC_SKIP_BLENDER'):
            if not py:
                raise SystemExit('npcs: set BPY_PYTHON to a Python with the bpy module (pip install bpy)')
            args = [py, os.path.join(HERE, 'npc_blender.py'), npz, work] + (['--samples', str(samples)] if samples else [])
            subprocess.run(args + (['--gpu'] if gpu else []), check=True)
        meta[name] = finish_npc(name, ch, cam, fit, outline, expressions, work, out_dir, m)
        print('npc', name, 'done', flush=True)
    return meta


def finish_npc(name, ch, cam, fit, outline, expressions, work, out_dir, m):
    pal = npc_palette(ch, outline)
    lines = line_layers(ch, cam, fit, pal, outline_px=max(1.5, fit.scale * OUTLINE_PX))
    g = project_px(cam, fit, [ch.anchors['ground']])[0]
    f = project_px(cam, fit, [ch.anchors['face']])[0]
    top = project_px(cam, fit, [ch.anchors['head_top']])[0]
    parts = [PART_NAMES[p] for p in sorted(int(p) for p in np.unique(ch.model.layer[ch.model.m > 0]))]
    pid = {n: i for i, n in enumerate(PART_NAMES)}
    load = lambda fn: np.asarray(Image.open(os.path.join(work, fn)).convert('RGBA')).astype(np.float32) / 255.0
    sets = {}
    sets['classic'] = {k: v.astype(np.float32) / 255.0
                       for k, v in classic_layers(ch, cam, fit, pal, 'npc_' + name, expressions).items()}
    # lit: the Blender passes (a dry run without them reuses the classic layers, for layout work)
    have_lit = os.path.exists(os.path.join(work, f'{name}_body.png'))
    lit = {}
    for p in parts:
        if p == 'head':
            for e in list(expressions) + ['blink']:
                lit[(p, e)] = load(f'{name}_head_{e}.png') if have_lit else sets['classic'][(p, e)]
        else:
            lit[(p, None)] = load(f'{name}_{p}.png') if have_lit else sets['classic'][(p, None)]
    sets['lit'] = lit
    rest_key = lambda e: [(p, e if p == 'head' else None) for p in parts]
    gains = {'lit': cast_gain(stack(sets['lit'], rest_key('neutral')), lines), 'classic': None}
    warm = m['grade'].get('warm', 0.0)
    sp = os.path.join(work, f'{name}_shadow.png')
    sh = np.asarray(Image.open(sp).convert('RGBA')) if os.path.exists(sp) else np.zeros((fit.h, fit.w, 4), np.uint8)
    shadow = shadow_layer(sh, lines['a'], g)
    boxes = eye_boxes(ch, cam, fit)
    eye_mask = np.zeros((fit.h, fit.w), np.float32)
    for x0, y0, x1, y1 in boxes:
        eye_mask[int(max(0, y0)):int(min(fit.h, y1 + 1)), int(max(0, x0)):int(min(fit.w, x1 + 1))] = 1.0
    eye_mask = cv2.GaussianBlur(eye_mask, (0, 0), 0.8)
    layers_meta = []
    files = {}
    for sname, S in sets.items():
        sfx = '' if sname == 'lit' else '_c'
        done = {}
        for (p, e), L in S.items():
            if sname == 'lit':
                L = grade(L, gains['lit'], sat=0.9, warm=warm)
            done[(p, e)] = ink(L, lines, pid[p], outline)
            if p == 'head' and e != 'blink' and getattr(ch, 'whiskers', None):
                # 3D whiskers ride on the head layer (they turn with it), hidden where the model is nearer
                from whiskers import draw
                if 'dep' not in lines:
                    lines['dep'] = render(ch.model, pal, cam, fit.w, fit.h, fit=fit).depth
                done[(p, e)] = draw(done[(p, e)], lines['dep'], cam, fit, ch.whiskers)
        # flattened expressions (thumbnails, cards, the classic sprite) on the full canvas
        for e in expressions:
            flat = stack({'s': shadow, **{k: v for k, v in done.items()}}, ['s'] + rest_key(e))
            Image.fromarray(to8(flat), 'RGBA').save(os.path.join(out_dir, f'npc_{name}_{e}{sfx}.png'), optimize=True)
        files[sname] = done
    # crops: one box per part (union over sets/expressions), so lit and classic swap in place
    def save_crop(arr, box, fn):
        x0, y0, x1, y1 = box
        Image.fromarray(to8(arr[y0:y1, x0:x1]), 'RGBA').save(os.path.join(out_dir, fn), optimize=True)
    sh_box = bbox(to8(shadow)[..., 3])
    save_crop(shadow, sh_box, f'npc_{name}_shadow.png')
    layers_meta.append({'part': 'shadow', 'box': list(map(int, sh_box)), 'file': f'npc_{name}_shadow.png'})
    for p in parts:
        keys = [k for k in files['lit'] if k[0] == p]
        a = np.zeros((fit.h, fit.w), np.uint8)
        for sname in files:
            for k in keys:
                a = np.maximum(a, to8(files[sname][k])[..., 3])
        box = bbox(a)
        entry = {'part': p, 'box': list(map(int, box))}
        if p in getattr(ch, 'pivots', {}):
            entry['pivot'] = [round(float(v), 1) for v in project_px(cam, fit, [ch.pivots[p]])[0]]
        for sname in files:
            sfx = '' if sname == 'lit' else '_c'
            if p == 'head':
                entry[sname] = {}
                for e in expressions:
                    fn = f'npc_{name}_head_{e}{sfx}.png'
                    save_crop(files[sname][(p, e)], box, fn)
                    entry[sname][e] = fn
                # blink: just the eyes, closed, over whatever expression is showing
                bl = files[sname][(p, 'blink')].copy()
                bl[..., 3] *= eye_mask
                bb = bbox(to8(bl)[..., 3], pad=1)
                fn = f'npc_{name}_blink{sfx}.png'
                save_crop(bl, bb, fn)
                entry.setdefault('blink', {})[sname] = {'file': fn, 'box': list(map(int, bb))}
            else:
                fn = f'npc_{name}_{p}{sfx}.png'
                save_crop(files[sname][(p, None)], box, fn)
                entry[sname] = fn
        layers_meta.append(entry)
    room, lay = HOME[name]
    return {'w': fit.w, 'h': fit.h, 'ground': g.round(1).tolist(), 'face': f.round(1).tolist(),
            'top': top.round(1).tolist(), 'expressions': list(expressions), 'layers': layers_meta,
            'place': room, 'stage': stage_layout(ch, fit, lay)}

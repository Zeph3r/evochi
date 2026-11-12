"""Render helpers for Evochi characters (body + pattern decals + face)."""
from __future__ import annotations

import zlib

import numpy as np

from voxel import Camera, Light, render, fit_camera, model_extent_points, Fit, project_px
from decals import Surface, Canvas, project_canvas, quads_to_polys
from characters import Character, paint_face
from palettes import palette as get_palette, ACCESSORY

FACE_MID = 200
PATTERN_MID = 201

_surf_cache = {}


def _hit(cache, k, model):
    """a cached value for `model`, or None. Keyed by id() but holding the model itself: a freed model's id is
    reused by the next one built (a second Mira in the same run got the first one's face, sunk inside her head)"""
    v = cache.get(k)
    return v[1] if v is not None and v[0] is model else None


CACHE_KEEP = 24     # entries kept: holding the models, an unbounded cache grew by a frame's model and surface
                    # every frame of an animation (the sleep cycle's Elder ran a box out of memory at 60 frames)


def _put(cache, k, model, v):
    cache[k] = (model, v)
    while len(cache) > CACHE_KEEP:
        del cache[next(iter(cache))]


def surface_for(ch: Character, iso=0.5):
    key = (id(ch.model), iso)
    s = _hit(_surf_cache, key, ch.model)
    if s is None:
        # the face is painted on the model without what stands in front of it (Alder's spectacles)
        s = Surface(getattr(ch, 'decal_model', None) or ch.model, sigma=0.75, iso=iso)
        _put(_surf_cache, key, ch.model, s)
    return s


KIT_ISO = 0.22      # the kit's big faces lie on the model's outer shell, clear of every voxel corner


_quad_cache = {}


def pattern_quads(ch: Character, pal: dict, pal_key: str):
    k = (id(ch.model), pal_key, 'pattern')
    hit = _hit(_quad_cache, k, ch.model)
    if hit is not None:
        return hit
    surf = surface_for(ch)
    out = []
    for frame, ext, fn in ch.pattern_decals:
        cv = Canvas(*ext, cell=0.08)
        fn(cv, pal)
        out += project_canvas(surf, frame, cv, PATTERN_MID, lift=0.06)
    _put(_quad_cache, k, ch.model, out)
    return out


FACE_LIFT = 0.08     # how far the face sits off the voxels (the kit faces sit higher: KIT_LIFT)
KIT_LIFT = 0.12


def face_quads(ch: Character, pal: dict, pal_key: str, expr: str):
    k = (id(ch.model), pal_key, expr)
    hit = _hit(_quad_cache, k, ch.model)
    if hit is not None:
        return hit
    from face_kit import parse, extent as kit_extent
    kit = parse(expr) is not None
    surf = surface_for(ch, KIT_ISO if kit else 0.5)
    ext = kit_extent(ch) if kit else ch.face_extent     # the kit's face is a fixed decal: its whole canvas
    cv = Canvas(*ext, cell=0.07)
    paint_face(ch, cv, pal, expr)
    q = project_canvas(surf, ch.face, cv, FACE_MID, lift=KIT_LIFT if kit else FACE_LIFT)
    _put(_quad_cache, k, ch.model, q)
    return q


def char_fit(ch: Character, cam: Camera, w, h, margin=0.06):
    return fit_camera(cam, model_extent_points(ch.model), w, h, margin)


def render_char(ch: Character, variant='amber', expr='default', cam=None, w=512, h=512, fit=None,
                light=None, pal=None, ss=3, outline_px=None, extra_model=None, pal_key=None, cov_prefix=None):
    cam = cam or Camera(yaw=0, pitch=12)
    light = light or Light()
    pal = dict(pal or get_palette(variant))
    for k, v in ACCESSORY.items():
        pal['acc_' + k] = v
    pal_key = pal_key or variant
    fit = fit or char_fit(ch, cam, w, h)
    alt = getattr(ch, 'alt', None)              # its version in this colour (the Obsidian Elder's mane), same frame
    vname = pal.get('variant', variant if isinstance(variant, str) else None)
    if alt and vname in alt:
        ch = alt[vname]()
    model = ch.model if extra_model is None else extra_model
    quads = pattern_quads(ch, pal, pal_key) + face_quads(ch, pal, pal_key, expr)
    decals = quads_to_polys(quads, cam, light, bias=0.3)
    if outline_px is None:
        outline_px = max(1.5, fit.scale * 0.21)
    lut = np.zeros(256, np.int32)
    for i, n in enumerate(model.mats):
        if n.startswith(('crest.', 'crest_mid.', 'crest_hi.', 'crest_lo.')):   # (one crystal's facets one piece)
            lut[i] = 1000 + zlib.crc32(n.split('.')[1].encode()) % 997
        elif n.startswith('acc_'):
            lut[i] = 5
    id_edges = lut
    out = render(model, pal, cam, w, h, fit=fit, light=light, ss=ss, decals=decals, id_edges=id_edges,
                 outline_px=outline_px, outline_col=pal['outline'], inner_thresh=2.2,
                 inner_alpha=0.8, inner_px=max(0.6, fit.scale * 0.045),
                 cov_ids=None if cov_prefix is None else
                 [i for i, n in enumerate(model.mats) if n.startswith(cov_prefix)])
    if getattr(ch, 'whiskers', None):
        from whiskers import draw
        out.rgba = draw(out.rgba, out.depth, cam, fit, ch.whiskers)
    return out

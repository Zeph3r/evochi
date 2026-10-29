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


def surface_for(ch: Character):
    key = id(ch.model)
    if key not in _surf_cache:
        # the face is painted on the model without what stands in front of it (Alder's spectacles)
        _surf_cache[key] = Surface(getattr(ch, 'decal_model', None) or ch.model, sigma=0.75)
    return _surf_cache[key]


_quad_cache = {}


def pattern_quads(ch: Character, pal: dict, pal_key: str):
    k = (id(ch.model), pal_key, 'pattern')
    if k in _quad_cache:
        return _quad_cache[k]
    surf = surface_for(ch)
    out = []
    for frame, ext, fn in ch.pattern_decals:
        cv = Canvas(*ext, cell=0.08)
        fn(cv, pal)
        out += project_canvas(surf, frame, cv, PATTERN_MID, lift=0.06)
    _quad_cache[k] = out
    return out


FACE_LIFT = 0.08     # how far the face sits off the voxels (the cinematic's big close-ups lift it more: cine_pose)


def face_quads(ch: Character, pal: dict, pal_key: str, expr: str):
    k = (id(ch.model), pal_key, expr)
    if k in _quad_cache:
        return _quad_cache[k]
    surf = surface_for(ch)
    cv = Canvas(*ch.face_extent, cell=0.07)
    paint_face(ch, cv, pal, expr)
    q = project_canvas(surf, ch.face, cv, FACE_MID, lift=FACE_LIFT)
    _quad_cache[k] = q
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
    model = ch.model if extra_model is None else extra_model
    fit = fit or char_fit(ch, cam, w, h)
    quads = pattern_quads(ch, pal, pal_key) + face_quads(ch, pal, pal_key, expr)
    decals = quads_to_polys(quads, cam, light, bias=0.3)
    if outline_px is None:
        outline_px = max(1.5, fit.scale * 0.21)
    lut = np.zeros(256, np.int32)
    for i, n in enumerate(model.mats):
        if n.startswith('crest.') or n.startswith('crest_mid.'):
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

"""Blender (Cycles) for the Lumen Wilds' maps (wilds_maps.py): the ground lit by the sun with every prop
casting its shadow on it while hidden from the camera, and each prop kind as its own sprite under the
same light. The camera is the map camera (walk.MAP_PITCH, orthographic, looking north), framed so world
(x, 0, z) lands at ground pixel origin + (x, z * sin(pitch)) * scale, exactly like the flat renderer.

Needs a Python with bpy (pip install bpy).
"""
from __future__ import annotations

import math
import os
import time

import numpy as np
from PIL import Image

import bpy
from mathutils import Matrix, Vector

import village_blender as VB
from voxel import Camera, model_extent_points
from walk import MAP_PITCH

SUN = dict(type='sun', dir=(0.42, -0.78, -0.48), power=3.2, color=5400, angle=5.0)
WORLD = ((0.74, 0.86, 0.98), 0.9)       # a bright sky: the shade under the trees stays green, not black
WATER = ('#5FAFCF', '#58A6C6', '#6BB9D6')


def B(v):
    v = np.asarray(v, np.float64)
    return np.stack([v[..., 0], -v[..., 2], v[..., 1]], -1)


def scene(w, h, samples, transparent):
    VB.reset()
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.resolution_percentage = 100
    sc.cycles.samples = samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.02
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    sc.cycles.max_bounces = 4
    sc.cycles.diffuse_bounces = 3
    sc.cycles.glossy_bounces = 2
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.cycles.sample_clamp_indirect = 6.0
    sc.render.film_transparent = transparent
    sc.view_settings.view_transform = 'Khronos PBR Neutral'
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    VB.add_light(SUN)
    VB.setup_world(*WORLD)
    return sc


def ortho_camera(scale, ox, oy, w, h):
    """An orthographic camera reproducing the flat renderer's framing: world point P lands at pixel
    (sx * scale + ox, sy * scale + oy), sx = P . right, sy = -(P . up)."""
    cam = Camera(yaw=0.0, pitch=MAP_PITCH)
    d, r, u = cam.basis()
    sx_c, sy_c = (w / 2 - ox) / scale, (h / 2 - oy) / scale
    Qc = r * sx_c - u * sy_c
    loc = Qc + d * 3000.0          # far enough that the whole map is in front of it
    X, Y, Z = B(r), B(u), B(d)
    mat = Matrix(((X[0], Y[0], Z[0], 0), (X[1], Y[1], Z[1], 0), (X[2], Y[2], Z[2], 0), (0, 0, 0, 1)))
    mat.translation = Vector(B(loc) * VB.SCALE)
    cd = bpy.data.cameras.new('cam')
    cd.type = 'ORTHO'
    cd.sensor_fit = 'HORIZONTAL'
    cd.ortho_scale = (w / scale) * VB.SCALE
    cd.clip_start = 0.01
    cd.clip_end = 1000.0
    ob = bpy.data.objects.new('cam', cd)
    bpy.context.scene.collection.objects.link(ob)
    ob.matrix_world = mat
    bpy.context.scene.camera = ob
    return ob


def place(ob, x, z, flip):
    ob.location = Vector(B((x, 0.0, z)) * VB.SCALE)
    if flip:
        ob.scale = (-1.0, 1.0, 1.0)


def render_ground(G, props, kinds, out, name, scale=None, quick=False, save_blend=None, samples=None):
    """The ground with the props' shadows, in tiles. With save_blend, the scene is saved there ready to
    render (on a machine with a GPU: tile_ground() then cuts the picture) instead of rendered here."""
    from wilds_maps import GROUND_SCALE, X0, X1, Z0, Z1, TILE
    scale = scale or GROUND_SCALE
    q = 0.25 if quick else 1.0
    s = scale * q
    p = math.radians(MAP_PITCH)
    ymin, ymax = G.lo[1] / G.res, G.hi[1] / G.res
    sy0 = Z0 * math.sin(p) - ymax * math.cos(p)
    sy1 = Z1 * math.sin(p) - ymin * math.cos(p)
    w = int(round((X1 - X0) * s))
    h = int(round((sy1 - sy0) * s))
    ox, oy = -X0 * s, -sy0 * s
    sc = scene(w, h, samples or (8 if quick else 40), transparent=False)
    t = time.time()
    VB.model_mesh(G, 'ground', (), water=WATER)
    meshes = {}
    for k in sorted({pp['kind'] for pp in props}):
        M, _ = kinds[k]()
        ob, _ = VB.model_mesh(M, f'k_{k}', ())
        meshes[k] = ob.data
        bpy.context.scene.collection.objects.unlink(ob)
    for i, pp in enumerate(props):
        ob = bpy.data.objects.new(f'p{i}', meshes[pp['kind']])
        bpy.context.scene.collection.objects.link(ob)
        place(ob, pp['x'], pp['z'], pp['flip'])
        ob.visible_camera = False           # it shades the ground, the game draws the sprite
    ortho_camera(s, ox, oy, w, h)
    print(f'ground: {w}x{h}, {len(props)} props, built in {time.time() - t:.1f}s', flush=True)
    meta = {'w': w, 'h': h, 'origin': [round(ox, 2), round(oy, 2)], 'scale': s}
    if save_blend:
        sc.render.filepath = '//' + f'{name}_ground.png'
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(save_blend), compress=True)
        print('saved', save_blend, flush=True)
        return meta
    path = os.path.join(out, 'work', f'{name}_ground.png')
    sc.render.filepath = path
    t = time.time()
    bpy.ops.render.render(write_still=True)
    print(f'ground rendered in {time.time() - t:.1f}s', flush=True)
    meta['tiles'] = tile_ground(path, out, name)
    return meta


def tile_ground(path, out, name):
    from wilds_maps import TILE
    im = Image.open(path).convert('RGB')
    w, h = im.size
    tiles = []
    for ty in range(0, h, TILE):
        for tx in range(0, w, TILE):
            tw, th = min(TILE, w - tx), min(TILE, h - ty)
            fn = f'{name}_ground_{ty // TILE}_{tx // TILE}.webp'
            im.crop((tx, ty, tx + tw, ty + th)).save(os.path.join(out, fn), quality=86, method=6)
            tiles.append({'image': fn, 'x': tx, 'y': ty, 'w': tw, 'h': th})
    return tiles


def render_props(kinds, out, name, scale=None, quick=False):
    """Every prop kind on a transparent background, its ground point recorded as the anchor."""
    from wilds_maps import GROUND_SCALE
    scale = scale or GROUND_SCALE
    meta = {}
    cam = Camera(yaw=0.0, pitch=MAP_PITCH)
    for k, fn in kinds.items():
        M, radius = fn()
        sx, sy, _ = cam.project(model_extent_points(M))
        pad = 6
        w = int(math.ceil((sx.max() - sx.min()) * scale)) + 2 * pad
        h = int(math.ceil((sy.max() - sy.min()) * scale)) + 2 * pad
        ox, oy = pad - sx.min() * scale, pad - sy.min() * scale
        sc = scene(w, h, 16 if quick else 96, transparent=True)
        VB.model_mesh(M, f'prop_{k}', ())
        ortho_camera(scale, ox, oy, w, h)
        path = os.path.join(out, 'work', f'{name}_prop_{k}.png')
        sc.render.filepath = path
        t = time.time()
        bpy.ops.render.render(write_still=True)
        out_fn = f'{name}_prop_{k}.webp'
        Image.open(path).save(os.path.join(out, out_fn), quality=90, method=6)
        meta[k] = {'image': out_fn, 'w': w, 'h': h, 'anchor': [round(ox, 1), round(oy, 1)], 'radius': radius, 'scale': scale}
        print(f'prop {k}: {w}x{h} in {time.time() - t:.1f}s', flush=True)
    return meta


def save_props_blend(kinds, path, scale=None, samples=96):
    """Every prop kind in one scene, each hidden from renders, with the framing for each (camera matrix,
    ortho scale, size, anchor) in <path>.json: render_props_gpu.py shows one prop at a time and renders it
    (on a machine with a GPU). Returns the prop meta (without the images' existence checked)."""
    import json
    from wilds_maps import GROUND_SCALE
    scale = scale or GROUND_SCALE
    sc = scene(64, 64, samples, transparent=True)
    cam = Camera(yaw=0.0, pitch=MAP_PITCH)
    d, r, u = cam.basis()
    X, Y, Z = B(r), B(u), B(d)
    frames, meta = {}, {}
    camob = None
    for k, fn in kinds.items():
        M, radius = fn()
        sx, sy, _ = cam.project(model_extent_points(M))
        pad = 6
        w = int(math.ceil((sx.max() - sx.min()) * scale)) + 2 * pad
        h = int(math.ceil((sy.max() - sy.min()) * scale)) + 2 * pad
        ox, oy = pad - sx.min() * scale, pad - sy.min() * scale
        ob, _ = VB.model_mesh(M, f'prop_{k}', ())
        ob.hide_render = True
        sx_c, sy_c = (w / 2 - ox) / scale, (h / 2 - oy) / scale
        loc = (r * sx_c - u * sy_c) + d * 3000.0
        mat = [[float(X[0]), float(Y[0]), float(Z[0]), 0.0], [float(X[1]), float(Y[1]), float(Z[1]), 0.0],
               [float(X[2]), float(Y[2]), float(Z[2]), 0.0], [0.0, 0.0, 0.0, 1.0]]
        t = B(loc) * VB.SCALE
        for i in range(3):
            mat[i][3] = float(t[i])
        frames[k] = {'object': ob.name, 'w': w, 'h': h, 'matrix': mat, 'ortho': (w / scale) * VB.SCALE}
        meta[k] = {'image': None, 'w': w, 'h': h, 'anchor': [round(ox, 1), round(oy, 1)], 'radius': radius, 'scale': scale}
        if camob is None:
            camob = ortho_camera(scale, ox, oy, w, h)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(path), compress=True)
    json.dump(frames, open(os.path.splitext(path)[0] + '.json', 'w'), indent=1)
    return meta


RENDER_PROPS_GPU = r'''# Renders each prop of the opened .blend alone (see wilds_blender.save_props_blend), on the GPU if any.
import bpy, os, json, time
from mathutils import Matrix
sc = bpy.context.scene
dev = 'CPU'
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences
    for kind in ('OPTIX', 'CUDA', 'HIP', 'ONEAPI'):
        try:
            prefs.compute_device_type = kind
        except TypeError:
            continue
        prefs.get_devices()
        ds = [d for d in prefs.devices if d.type == kind]
        if ds:
            for d in prefs.devices:
                d.use = d.type == kind
            sc.cycles.device = 'GPU'
            dev = kind
            break
except Exception as e:
    dev = 'CPU (%s)' % e
base = os.path.dirname(bpy.data.filepath)
stem = os.path.splitext(os.path.basename(bpy.data.filepath))[0]
frames = json.load(open(os.path.join(base, stem + '.json')))
log = os.path.join(base, stem + '_render.json')
done = []
t0 = time.time()
for k, f in frames.items():
    for o in bpy.data.objects:
        if o.type == 'MESH':
            o.hide_render = o.name != f['object']
    sc.render.resolution_x, sc.render.resolution_y = f['w'], f['h']
    sc.camera.matrix_world = Matrix(f['matrix'])
    sc.camera.data.ortho_scale = f['ortho']
    sc.render.filepath = os.path.join(base, 'props', k + '.png')
    bpy.ops.render.render(write_still=True)
    done.append(k)
    json.dump({'state': 'rendering', 'device': dev, 'done': done}, open(log, 'w'))
json.dump({'state': 'done', 'device': dev, 'done': done, 'seconds': round(time.time() - t0, 1)}, open(log, 'w'))
'''

"""Render voxel scenes with Blender (Cycles) for real light: lanterns and furnaces that light the
room, soft sun shadows, bounce light. Run with a Python that has the `bpy` module:

    <venv>/bin/python village_blender.py OUT_DIR scene [scene ...] [--preview]

Scenes come from village_scenes.py: each returns a VScene with voxel models (same Model/Painter
language as the rest of the pack), point/area/sun lights, a camera and a world. Voxels become one
mesh per model (only exposed faces), coloured per face; glowing voxels emit.

Coordinates: voxel space is x right, y up, z toward the viewer. Blender is z up, so (x, y, z) maps
to (x, -z, y), scaled by SCALE (one voxel-space unit = 10 cm).
"""
from __future__ import annotations

import json
import math
import os
import sys
import time

import numpy as np

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

SCALE = 0.1

FACES = [  # normal axis, sign, 4 corner offsets (voxel min corner), CCW seen from outside
    (0, 1, [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
    (0, -1, [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
    (1, 1, [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]),
    (1, -1, [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
    (2, 1, [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
    (2, -1, [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)]),
]


def srgb_to_linear(c):
    c = np.asarray(c, np.float32) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def hexrgb(h):
    h = h.lstrip('#')
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def to_blender(p):
    x, y, z = p
    return Vector((x * SCALE, -z * SCALE, y * SCALE))


def shift(a, axis, sign):
    """b[v] = a[v + sign*e_axis] (False outside)."""
    b = np.zeros_like(a)
    sl_dst = [slice(None)] * 3
    sl_src = [slice(None)] * 3
    if sign > 0:
        sl_dst[axis] = slice(0, -1)
        sl_src[axis] = slice(1, None)
    else:
        sl_dst[axis] = slice(1, None)
        sl_src[axis] = slice(0, -1)
    b[tuple(sl_dst)] = a[tuple(sl_src)]
    return b


def model_mesh(M, name, glass=(), cutaway=None, water=()):
    """Exposed faces of a voxel Model as a Blender mesh object with per-face colour and glow."""
    filled = M.m > 0
    gid = [M.ids[c] for c in glass if c in M.ids]
    isglass = np.isin(M.m, gid) if gid else np.zeros_like(filled)
    wid = [M.ids[c] for c in water if c in M.ids]
    iswater = np.isin(M.m, wid) if wid else np.zeros_like(filled)
    opaque = filled & ~isglass
    cols = np.array([[0, 0, 0]] + [hexrgb(c) if c.startswith('#') else [255, 0, 255] for c in M.mats[1:]], np.float32)
    lin = srgb_to_linear(cols)
    verts, quads, fcol, fglow, fmat = [], [], [], [], []
    base = 0
    lo = M.lo.astype(np.float64)
    r = float(M.res)
    for axis, sign, corners in FACES:
        exposed = (opaque & ~shift(opaque, axis, sign)) | (isglass & ~shift(filled, axis, sign))
        if cutaway is not None:
            exposed &= ~cutaway(axis, sign)
        idx = np.argwhere(exposed)
        if not len(idx):
            continue
        n = len(idx)
        mn = (idx + lo) / r
        pts = np.stack([mn + np.array(c, np.float64) / r for c in corners], 1)   # n,4,3 (voxel space)
        verts.append(pts.reshape(-1, 3))
        quads.append(base + np.arange(n * 4).reshape(n, 4))
        base += n * 4
        mids = M.m[idx[:, 0], idx[:, 1], idx[:, 2]]
        fcol.append(lin[mids])
        fglow.append(M.glow[idx[:, 0], idx[:, 1], idx[:, 2]])
        fmat.append(isglass[idx[:, 0], idx[:, 1], idx[:, 2]].astype(np.int32) + 2 * iswater[idx[:, 0], idx[:, 1], idx[:, 2]].astype(np.int32))
    V = np.concatenate(verts)
    Q = np.concatenate(quads)
    C = np.concatenate(fcol)
    G = np.concatenate(fglow).astype(np.float32)
    MI = np.concatenate(fmat)
    Vb = np.stack([V[:, 0], -V[:, 2], V[:, 1]], 1) * SCALE
    me = bpy.data.meshes.new(name)
    me.vertices.add(len(Vb))
    me.vertices.foreach_set('co', Vb.astype(np.float32).ravel())
    nf = len(Q)
    me.loops.add(nf * 4)
    me.loops.foreach_set('vertex_index', Q.astype(np.int32).ravel())
    me.polygons.add(nf)
    me.polygons.foreach_set('loop_start', (np.arange(nf) * 4).astype(np.int32))
    me.polygons.foreach_set('loop_total', np.full(nf, 4, np.int32))
    me.update(calc_edges=True)
    me.validate(verbose=False)
    a = me.attributes.new('col', 'FLOAT_COLOR', 'FACE')
    a.data.foreach_set('color', np.concatenate([C, np.ones((nf, 1), np.float32)], 1).ravel())
    g = me.attributes.new('glow', 'FLOAT', 'FACE')
    g.data.foreach_set('value', G)
    me.polygons.foreach_set('material_index', MI)
    me.materials.append(solid_material())
    me.materials.append(glass_material())
    me.materials.append(water_material())
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob, nf


_MATS = {}


def _attr(nt, name, kind='Color'):
    n = nt.nodes.new('ShaderNodeAttribute')
    n.attribute_type = 'GEOMETRY'
    n.attribute_name = name
    return n.outputs[kind if kind != 'Fac' else 'Fac']


def solid_material(emit=1.3):
    if 'solid' in _MATS:
        return _MATS['solid']
    m = bpy.data.materials.new('voxel_solid')
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes['Principled BSDF']
    col = _attr(nt, 'col')
    nt.links.new(col, p.inputs['Base Color'])
    glow = _attr(nt, 'glow', 'Fac')
    mul = nt.nodes.new('ShaderNodeMath')
    mul.operation = 'MULTIPLY'
    mul.inputs[1].default_value = emit
    nt.links.new(glow, mul.inputs[0])
    nt.links.new(col, p.inputs['Emission Color'])
    nt.links.new(mul.outputs[0], p.inputs['Emission Strength'])
    p.inputs['Roughness'].default_value = 0.78
    _MATS['solid'] = m
    return m


def glass_material():
    if 'glass' in _MATS:
        return _MATS['glass']
    m = bpy.data.materials.new('voxel_glass')
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type != 'OUTPUT_MATERIAL':
            nt.nodes.remove(n)
    out = nt.nodes['Material Output']
    col = _attr(nt, 'col')
    tr = nt.nodes.new('ShaderNodeBsdfTransparent')
    nt.links.new(col, tr.inputs['Color'])
    gl = nt.nodes.new('ShaderNodeBsdfGlossy')
    gl.inputs['Roughness'].default_value = 0.08
    mix = nt.nodes.new('ShaderNodeMixShader')
    mix.inputs[0].default_value = 0.1
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(gl.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs['Surface'])
    _MATS['glass'] = m
    return m


def water_material():
    if 'water' in _MATS:
        return _MATS['water']
    m = bpy.data.materials.new('voxel_water')
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes['Principled BSDF']
    nt.links.new(_attr(nt, 'col'), p.inputs['Base Color'])
    p.inputs['Roughness'].default_value = 0.12
    p.inputs['Specular IOR Level'].default_value = 0.6
    _MATS['water'] = m
    return m


def kelvin(k):
    """Approximate blackbody colour (linear) for a few common temperatures."""
    table = {1900: (1.0, 0.45, 0.12), 2400: (1.0, 0.58, 0.26), 2700: (1.0, 0.66, 0.36), 3200: (1.0, 0.75, 0.52),
             4500: (1.0, 0.88, 0.76), 5500: (1.0, 0.95, 0.9), 6500: (0.95, 0.97, 1.0), 9000: (0.78, 0.86, 1.0)}
    return table[min(table, key=lambda t: abs(t - k))]


def add_light(L):
    kind = L['type']
    if kind == 'point':
        d = bpy.data.lights.new('p', 'POINT')
        d.shadow_soft_size = L.get('radius', 0.6) * SCALE
    elif kind == 'area':
        d = bpy.data.lights.new('a', 'AREA')
        d.shape = 'RECTANGLE'
        d.size = L['size'][0] * SCALE
        d.size_y = L['size'][1] * SCALE
    elif kind == 'sun':
        d = bpy.data.lights.new('s', 'SUN')
        d.angle = math.radians(L.get('angle', 4.0))
    elif kind == 'spot':
        d = bpy.data.lights.new('sp', 'SPOT')
        d.spot_size = math.radians(L.get('cone', 60))
        d.spot_blend = 0.6
        d.shadow_soft_size = L.get('radius', 1.0) * SCALE
    col = L.get('color', (1, 1, 1))
    if isinstance(col, (int, float)):
        col = kelvin(col)
    d.color = col
    d.energy = L['power']
    ob = bpy.data.objects.new('light', d)
    bpy.context.scene.collection.objects.link(ob)
    if kind in ('area', 'spot'):
        ob.visible_camera = False     # big fill panels may sit inside a tall frame
    if kind == 'sun':
        # direction the light travels, in voxel space
        dx, dy, dz = L['dir']
        v = Vector((dx, -dz, dy)).normalized()
        ob.rotation_euler = v.to_track_quat('-Z', 'Y').to_euler()
    else:
        ob.location = to_blender(L['pos'])
        if 'aim' in L:
            v = (to_blender(L['aim']) - ob.location).normalized()
            ob.rotation_euler = v.to_track_quat('-Z', 'Y').to_euler()
    return ob


def setup_world(colour, strength):
    w = bpy.data.worlds.new('w')
    w.use_nodes = True
    bg = w.node_tree.nodes['Background']
    bg.inputs['Color'].default_value = (*colour, 1.0)
    bg.inputs['Strength'].default_value = strength
    bpy.context.scene.world = w


def setup_camera(cam, w, h):
    d = bpy.data.cameras.new('cam')
    d.sensor_fit = 'VERTICAL'
    d.angle = math.radians(cam['fov'])
    d.clip_start = 0.05
    d.clip_end = 400
    ob = bpy.data.objects.new('cam', d)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = to_blender(cam['pos'])
    v = (to_blender(cam['target']) - ob.location).normalized()
    ob.rotation_euler = v.to_track_quat('-Z', 'Y').to_euler()
    if cam.get('shift_y'):
        d.shift_y = cam['shift_y']
    if cam.get('focus'):
        d.dof.use_dof = True
        d.dof.focus_distance = (to_blender(cam['focus']) - ob.location).length
        d.dof.aperture_fstop = cam.get('fstop', 2.8)
    bpy.context.scene.camera = ob
    return ob


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _MATS.clear()


def use_gpu(scene):
    """Render on the GPU if Cycles finds one (OptiX/CUDA for NVIDIA, HIP for AMD, Metal, oneAPI)."""
    try:
        prefs = bpy.context.preferences.addons['cycles'].preferences
    except KeyError:
        return None
    for kind in ('OPTIX', 'CUDA', 'HIP', 'METAL', 'ONEAPI'):
        try:
            prefs.compute_device_type = kind
        except TypeError:
            continue
        prefs.get_devices()
        devs = [d for d in prefs.devices if d.type == kind]
        if devs:
            for d in prefs.devices:
                d.use = d.type == kind
            scene.cycles.device = 'GPU'
            return kind + ': ' + ', '.join(d.name for d in devs)
    return None


def render(vs, out_path, preview=False):
    reset()
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    if GPU:
        print('device:', use_gpu(sc) or 'CPU (no GPU found)', flush=True)
    scale = QUICK or (0.5 if preview else 1.0)
    sc.render.resolution_x = int(vs.w * scale)
    sc.render.resolution_y = int(vs.h * scale)
    sc.render.resolution_percentage = 100
    sc.cycles.samples = 12 if QUICK else vs.samples // (3 if preview else 2)
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.02
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    sc.cycles.max_bounces = 6
    sc.cycles.diffuse_bounces = 4
    sc.cycles.glossy_bounces = 2
    sc.cycles.transparent_max_bounces = 8
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.cycles.sample_clamp_indirect = 6.0
    sc.render.film_transparent = vs.transparent
    sc.view_settings.view_transform = vs.view
    if vs.look and vs.view == 'AgX':
        sc.view_settings.look = vs.look
    sc.view_settings.exposure = vs.exposure
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.threads_mode = 'AUTO'
    t = time.time()
    nf = 0
    for i, item in enumerate(vs.models):
        M, glass = item[0], item[1]
        opts = item[2] if len(item) > 2 else {}
        ob, n = model_mesh(M, f'{vs.name}_{i}', glass, water=tuple(opts.get('water', ())))
        if opts.get('shadow') is False:
            ob.visible_shadow = False
        nf += n
    for L in vs.lights:
        add_light(L)
    setup_world(vs.world[0], vs.world[1])
    cam = setup_camera(vs.cam, vs.w, vs.h)
    print(f'{vs.name}: {nf} faces, {len(vs.lights)} lights, built in {time.time() - t:.1f}s', flush=True)
    sc.render.filepath = out_path
    t = time.time()
    bpy.ops.render.render(write_still=True)
    print(f'{vs.name}: rendered in {time.time() - t:.1f}s -> {out_path}', flush=True)
    anchors = {}
    for k, p in vs.anchors.items():
        co = world_to_camera_view(sc, cam, to_blender(p))
        anchors[k] = [round(co.x * vs.w, 1), round((1 - co.y) * vs.h, 1)]
    return anchors


GPU = False
QUICK = 0.0

if __name__ == '__main__':
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    preview = '--preview' in args
    GPU = '--gpu' in args
    if '--quick' in args:
        QUICK = 0.3
        preview = True
    args = [a for a in args if a != '--quick']
    args = [a for a in args if a != '--gpu']

    def opt(name, default):
        if name in args:
            i = args.index(name)
            v = args[i + 1]
            del args[i:i + 2]
            return v
        return default

    raw_dir = opt('--raw', None)
    meta_name = opt('--meta', 'scenes_blender.json')
    args = [a for a in args if a != '--preview']
    out, names = args[0], args[1:]
    packed = all(n.endswith('.npz') for n in names)
    if not packed:
        import village_scenes as VS2      # needs scipy/cv2/PIL; packed scenes need only numpy
        try:
            import home_scenes                # the Home Map, Garden, Kitchen and Apothecary
            VS2.SCENES.update(home_scenes.SCENES)
        except ImportError as e:
            print('home scenes unavailable:', e, flush=True)
        try:
            import trail_scenes               # Lumen Trails encounter places
            VS2.SCENES.update(trail_scenes.SCENES)
        except ImportError as e:
            print('trail scenes unavailable:', e, flush=True)
        if names == ['all']:
            names = list(VS2.SCENES)
    raw_dir = raw_dir or out
    os.makedirs(out, exist_ok=True)
    os.makedirs(raw_dir, exist_ok=True)
    meta_path = os.path.join(out, meta_name)
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    for n in names:
        if packed:
            # pack from scene_pack.py: render the raw frame only (grading happens where PIL lives)
            import scene_pack
            vs = scene_pack.unpack(n)
            n = vs.name
        else:
            vs = VS2.SCENES[n]()
        raw = os.path.join(raw_dir, f'{n}_raw.png')
        anchors = render(vs, raw, preview)
        if not packed:
            VS2.finish(vs, raw, os.path.join(out, f'{n}.png'), preview)
        meta[n] = {'w': vs.w, 'h': vs.h, 'anchors': anchors}
        json.dump(meta, open(meta_path, 'w'), indent=1)

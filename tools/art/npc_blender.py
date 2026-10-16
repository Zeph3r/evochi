"""Render one villager (exported by village_npc_render.export) inside its room, part by part, with Cycles.

    <bpy python> npc_blender.py NAME.npz WORK_DIR [--samples N] [--gpu] [--only part,part]
    blender -b --python npc_blender.py -- NAME.npz WORK_DIR --gpu          (a stock Blender works too)

Needs only bpy + numpy: the room comes packed (scene_pack.py) next to NAME.npz.

Writes into WORK_DIR:
    NAME_body.png, NAME_arm.png            each part alone (others hidden from the camera only)
    NAME_head_<expr>.png                   the head with each painted face (+ 'blink')
    NAME_shadow.png                        the villager's floor shadow, caught on a transparent plane

The room is hidden from the camera, so it only lights the villager: lanterns, forge, sun, bounce.
Room voxels inside the villager's footprint are cleared. The camera is orthographic and reproduces the
flat renderer's framing pixel for pixel, so the ink lines, anchors and pivots line up.
"""
from __future__ import annotations

import json
import math
import os
import sys
import time

import numpy as np

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import village_blender as VB      # noqa: E402
import scene_pack                 # noqa: E402

SCALE = VB.SCALE
EMIT = 1.0          # unlit face paint (eyes, brows): shown at its own colour


def B(v):
    """voxel-space vector/point (x, y, z) -> Blender (x, -z, y), unscaled."""
    v = np.asarray(v, np.float64)
    return np.stack([v[..., 0], -v[..., 2], v[..., 1]], -1)


def cam_basis(yaw, pitch):
    y, p = math.radians(yaw), math.radians(pitch)
    d = np.array([math.sin(y) * math.cos(p), math.sin(p), math.cos(y) * math.cos(p)])
    r = np.array([math.cos(y), 0.0, -math.sin(y)])
    u = np.cross(d, r)
    return d, r, u


def rot_y(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])     # yaw: +z turns toward +x


def build_room(vs, meta, footprint):
    mirror = meta['mirror']
    cx, cz, r, top = footprint
    if mirror:
        cx = -cx
    for i, (M, glass, opts) in enumerate(vs.models):
        X, Y, Z = M.coords()
        clear = ((X - cx) ** 2 + (Z - cz) ** 2 < r * r) & (Y > 0.02) & (Y < top)
        del X, Y, Z
        M.m = np.where(clear, 0, M.m).astype(np.uint8)
        ob, _ = VB.model_mesh(M, f'room_{i}', glass, water=tuple(opts.get('water', ())))
        ob.visible_camera = False
        if opts.get('shadow') is False:
            ob.visible_shadow = False
        if mirror:
            ob.scale = (-1, 1, 1)
    for L in vs.lights:
        L = dict(L)
        if mirror:
            for k in ('pos', 'aim', 'dir'):
                if k in L:
                    L[k] = (-L[k][0], L[k][1], L[k][2])
        VB.add_light(L)
    VB.setup_world(tuple(vs.world[0]), vs.world[1])


def npc_material(face_img, lit_img):
    m = bpy.data.materials.new('npc')
    m.use_nodes = True
    nt = m.node_tree
    N, L = nt.nodes, nt.links
    p = N['Principled BSDF']
    p.inputs['Roughness'].default_value = 0.72
    p.inputs['Specular IOR Level'].default_value = 0.35
    col = VB._attr(nt, 'col')
    fmask = VB._attr(nt, 'fmask', 'Fac')
    uv = N.new('ShaderNodeUVMap')
    uv.uv_map = 'face'
    tf = N.new('ShaderNodeTexImage')
    tf.image = face_img
    tf.interpolation = 'Closest'
    tf.extension = 'CLIP'
    tl = N.new('ShaderNodeTexImage')
    tl.image = lit_img
    tl.interpolation = 'Closest'
    tl.extension = 'CLIP'
    L.new(uv.outputs['UV'], tf.inputs['Vector'])
    L.new(uv.outputs['UV'], tl.inputs['Vector'])
    fa = N.new('ShaderNodeMath')
    fa.operation = 'MULTIPLY'
    L.new(tf.outputs['Alpha'], fa.inputs[0])
    L.new(fmask, fa.inputs[1])
    mix = N.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    L.new(fa.outputs[0], mix.inputs['Factor'])
    L.new(col, mix.inputs['A'])
    L.new(tf.outputs['Color'], mix.inputs['B'])
    one_minus = N.new('ShaderNodeMath')            # unlit share u = fa * (1 - lit)
    one_minus.operation = 'SUBTRACT'
    one_minus.inputs[0].default_value = 1.0
    L.new(tl.outputs['Color'], one_minus.inputs[1])
    u = N.new('ShaderNodeMath')
    u.operation = 'MULTIPLY'
    L.new(fa.outputs[0], u.inputs[0])
    L.new(one_minus.outputs[0], u.inputs[1])
    dark = N.new('ShaderNodeMix')
    dark.data_type = 'RGBA'
    L.new(u.outputs[0], dark.inputs['Factor'])
    L.new(mix.outputs['Result'], dark.inputs['A'])
    dark.inputs['B'].default_value = (0, 0, 0, 1)
    L.new(dark.outputs['Result'], p.inputs['Base Color'])
    L.new(tf.outputs['Color'], p.inputs['Emission Color'])
    es = N.new('ShaderNodeMath')
    es.operation = 'MULTIPLY'
    es.inputs[1].default_value = EMIT
    L.new(u.outputs[0], es.inputs[0])
    L.new(es.outputs[0], p.inputs['Emission Strength'])
    return m


def place(ob, meta):
    ob.location = Vector(B(meta['P0']) * SCALE)
    ob.rotation_euler = (0.0, 0.0, math.radians(meta['yaw']))
    ob.scale = (meta['s'],) * 3


def build_part(D, meta, sel, name, mat):
    C = D['C'][sel].astype(np.float64)              # (n,4,3) model units
    g = np.array(meta['ground_model'])
    V = B(C - g).reshape(-1, 3) * SCALE
    n = len(C)
    me = bpy.data.meshes.new(name)
    me.vertices.add(len(V))
    me.vertices.foreach_set('co', V.astype(np.float32).ravel())
    me.loops.add(n * 4)
    me.loops.foreach_set('vertex_index', np.arange(n * 4, dtype=np.int32))
    me.polygons.add(n)
    me.polygons.foreach_set('loop_start', (np.arange(n) * 4).astype(np.int32))
    me.polygons.foreach_set('loop_total', np.full(n, 4, np.int32))
    me.update(calc_edges=True)
    lin = VB.srgb_to_linear(D['COL'][sel])
    a = me.attributes.new('col', 'FLOAT_COLOR', 'FACE')
    a.data.foreach_set('color', np.concatenate([lin, np.ones((n, 1), np.float32)], 1).astype(np.float32).ravel())
    fm = me.attributes.new('fmask', 'FLOAT', 'FACE')
    fm.data.foreach_set('value', D['FMASK'][sel].astype(np.float32))
    # smoothed normals as real custom split normals: Cycles then treats them as the surface's own
    # normal (no bump-shadowing term at the voxel steps, which would draw dark lines along them)
    me.shade_smooth()
    me.normals_split_custom_set(B(D['VN'][sel]).reshape(-1, 3).astype(np.float64).tolist())
    uvl = me.uv_layers.new(name='face')
    uvl.uv.foreach_set('vector', D['UV'][sel].reshape(-1, 2).astype(np.float32).ravel())
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    place(ob, meta)
    # the voxel surface neither shadows nor occludes itself; the smooth proxy does that
    ob.visible_shadow = False
    ob.visible_diffuse = False
    ob.visible_glossy = False
    return ob


def build_proxy(D, meta):
    """Smooth stand-in that casts the villager's shadows and blocks bounce light (camera never sees it)."""
    g = np.array(meta['ground_model'])
    V = B(D['PV'].astype(np.float64) - g) * SCALE
    F = D['PF']
    me = bpy.data.meshes.new('proxy')
    me.vertices.add(len(V))
    me.vertices.foreach_set('co', V.astype(np.float32).ravel())
    me.loops.add(F.size)
    me.loops.foreach_set('vertex_index', F.astype(np.int32).ravel())
    me.polygons.add(len(F))
    me.polygons.foreach_set('loop_start', (np.arange(len(F)) * 3).astype(np.int32))
    me.polygons.foreach_set('loop_total', np.full(len(F), 3, np.int32))
    me.update(calc_edges=True)
    a = me.attributes.new('col', 'FLOAT_COLOR', 'POINT')
    lin = VB.srgb_to_linear(D['PC'])
    a.data.foreach_set('color', np.concatenate([lin, np.ones((len(V), 1), np.float32)], 1).astype(np.float32).ravel())
    me.shade_smooth()
    m = bpy.data.materials.new('proxy')
    m.use_nodes = True
    nt = m.node_tree
    nt.links.new(VB._attr(nt, 'col'), nt.nodes['Principled BSDF'].inputs['Base Color'])
    nt.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.8
    me.materials.append(m)
    ob = bpy.data.objects.new('proxy', me)
    bpy.context.scene.collection.objects.link(ob)
    place(ob, meta)
    ob.visible_camera = False
    return ob


def build_camera(meta):
    d, r, u = cam_basis(meta['cam_yaw'], meta['pitch'])
    w, h, sc = meta['w'], meta['h'], meta['scale']
    sx, sy = (w / 2 - meta['ox']) / sc, (h / 2 - meta['oy']) / sc
    g = np.array(meta['ground_model'])
    Qc = r * sx - u * sy - g
    R = rot_y(meta['yaw'])
    s = meta['s']
    loc = np.array(meta['P0']) + s * (R @ (Qc + d * 150.0))
    X, Y, Z = (B(R @ v) for v in (r, u, d))
    mat = Matrix(((X[0], Y[0], Z[0], 0), (X[1], Y[1], Z[1], 0), (X[2], Y[2], Z[2], 0), (0, 0, 0, 1)))
    mat.translation = Vector(B(loc) * SCALE)
    cd = bpy.data.cameras.new('cam')
    cd.type = 'ORTHO'
    cd.sensor_fit = 'HORIZONTAL'
    cd.ortho_scale = s * (w / sc) * SCALE
    cd.clip_start = 0.01
    cd.clip_end = 100.0
    ob = bpy.data.objects.new('cam', cd)
    bpy.context.scene.collection.objects.link(ob)
    ob.matrix_world = mat
    bpy.context.scene.camera = ob
    return ob


def set_image(img, arr):
    if arr.ndim == 2:
        arr = np.dstack([arr, arr, arr, np.full_like(arr, 255)])
    img.pixels.foreach_set((arr.astype(np.float32) / 255.0).ravel())
    img.update()


def shoot(sc, path):
    sc.render.filepath = path
    t = time.time()
    bpy.ops.render.render(write_still=True)
    print(f'  {os.path.basename(path)}: {time.time() - t:.1f}s', flush=True)


def main():
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    samples = None
    only = None
    gpu = '--gpu' in args
    args = [a for a in args if a != '--gpu']
    if '--samples' in args:
        i = args.index('--samples')
        samples = int(args[i + 1])
        del args[i:i + 2]
    if '--only' in args:
        i = args.index('--only')
        only = args[i + 1].split(',')
        del args[i:i + 2]
    npz, work = os.path.abspath(args[0]), os.path.abspath(args[1])
    D = np.load(npz)
    meta = json.loads(str(D['meta']))
    name = meta['name']
    t = time.time()
    vs = scene_pack.unpack(os.path.join(os.path.dirname(npz), meta['room_pack']))
    VB.reset()
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    if gpu:
        print('device:', VB.use_gpu(sc) or 'CPU (no GPU found)', flush=True)
    sc.render.resolution_x = meta['w']
    sc.render.resolution_y = meta['h']
    sc.render.resolution_percentage = 100
    base_samples = samples or (384 if gpu else 192)
    sc.cycles.samples = base_samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.015
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    sc.cycles.max_bounces = 6
    sc.cycles.diffuse_bounces = 4
    sc.cycles.glossy_bounces = 2
    sc.cycles.transparent_max_bounces = 8
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.cycles.sample_clamp_indirect = 6.0
    sc.render.film_transparent = True
    sc.view_settings.view_transform = vs.view
    sc.view_settings.exposure = (vs.exposure or 0.0) + meta.get('ev', 0.0)
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    C = D['C']
    g = np.array(meta['ground_model'])
    rad = float(np.sqrt(((C[..., 0] - g[0]) ** 2 + (C[..., 2] - g[2]) ** 2)).max()) * meta['s'] + 0.6
    top = float((C[..., 1] - g[1]).max()) * meta['s'] + 0.6
    P0 = meta['P0']
    build_room(vs, meta, (P0[0], P0[2], rad, top))
    e0 = meta['expressions'][0]
    fh, fw = D['face_' + e0].shape[:2]
    face_img = bpy.data.images.new('face', fw, fh, alpha=True)
    face_img.colorspace_settings.name = 'sRGB'
    face_img.alpha_mode = 'STRAIGHT'
    lit_img = bpy.data.images.new('lit', fw, fh, alpha=False)
    lit_img.colorspace_settings.name = 'Non-Color'
    mat = npc_material(face_img, lit_img)
    PART = D['PART']
    names = meta['parts']
    obs = {}
    for pid, pname in enumerate(('body', 'head', 'arm')):
        if pname in names:
            obs[pname] = build_part(D, meta, PART == pid, 'npc_' + pname, mat)
    build_proxy(D, meta)
    build_camera(meta)
    print(f'{name}: scene ready in {time.time() - t:.1f}s (room {meta["room"]}, s={meta["s"]:.3f}, '
          f'yaw={meta["yaw"]:.1f}, {len(C)} faces)', flush=True)
    for pname in obs:
        if only and pname not in only:
            continue
        for k, ob in obs.items():
            ob.visible_camera = k == pname
        if pname == 'head':
            for e in meta['expressions']:
                set_image(face_img, D['face_' + e])
                set_image(lit_img, D['lit_' + e])
                shoot(sc, os.path.join(work, f'{name}_head_{e}.png'))
        else:
            shoot(sc, os.path.join(work, f'{name}_{pname}.png'))
    if only and 'shadow' not in only:
        return
    # floor shadow: the villager held out (transparent, still casting via the proxy), caught on a plane
    for ob in obs.values():
        ob.visible_camera = True
        ob.is_holdout = True
    me = bpy.data.meshes.new('catcher')
    span = rad * 3.0 * SCALE
    me.from_pydata([(-span, -span, 0), (span, -span, 0), (span, span, 0), (-span, span, 0)], [], [(0, 1, 2, 3)])
    pl = bpy.data.objects.new('catcher', me)
    bpy.context.scene.collection.objects.link(pl)
    pl.location = Vector(B(np.array(P0, float) + np.array([0, 0.03, 0])) * SCALE)
    pl.is_shadow_catcher = True
    sc.cycles.samples = max(64, base_samples // 2)
    shoot(sc, os.path.join(work, f'{name}_shadow.png'))


if __name__ == '__main__':
    main()

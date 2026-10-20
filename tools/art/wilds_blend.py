"""Sher as a Blender file to open and play with: the rest pose in parts (body, head, his right arm, each
pivoting where the game animates it), his painted face with every expression packed in, his whiskers as
real curves, and the walk cycle as a looping animation (one mesh per frame, shown on its frame).

    python3 wilds_blend.py OUT.blend          (a Python with the bpy module)

Units: 1 voxel unit = 10 cm (village_blender.SCALE), Sher stands on the origin facing -Y (Blender's
front view looks at his face). Cameras: `cam_portrait` (the villagers' dialogue angle) and `cam_wilds`
(the Lumen Wilds map camera). Press play for the walk.
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy                                    # noqa: E402
from mathutils import Matrix, Vector          # noqa: E402

import village_blender as VB                  # noqa: E402
import npc_blender as NB                      # noqa: E402
from village_npc_render import mesh_arrays, face_projection, face_canvas, npc_palette   # noqa: E402
from village_npcs import NPC_EXPRESSIONS, INK, PART_NAMES   # noqa: E402
from wilds_npcs import build_sher             # noqa: E402
from walk import sher_pose, FRAMES, FPS, MAP_PITCH          # noqa: E402

SCALE = VB.SCALE


def B(v):
    v = np.asarray(v, np.float64)
    return np.stack([v[..., 0], -v[..., 2], v[..., 1]], -1)


def make_mesh(name, C, VN, COL, UV, FM, origin, mat, coll):
    """Quads (model units) -> an object whose origin sits at `origin` (model units)."""
    n = len(C)
    V = (B(C.astype(np.float64) - np.asarray(origin)) * SCALE).reshape(-1, 3)
    me = bpy.data.meshes.new(name)
    me.vertices.add(len(V))
    me.vertices.foreach_set('co', V.astype(np.float32).ravel())
    me.loops.add(n * 4)
    me.loops.foreach_set('vertex_index', np.arange(n * 4, dtype=np.int32))
    me.polygons.add(n)
    me.polygons.foreach_set('loop_start', (np.arange(n) * 4).astype(np.int32))
    me.polygons.foreach_set('loop_total', np.full(n, 4, np.int32))
    me.update(calc_edges=True)
    lin = VB.srgb_to_linear(COL)
    a = me.attributes.new('col', 'FLOAT_COLOR', 'FACE')
    a.data.foreach_set('color', np.concatenate([lin, np.ones((n, 1), np.float32)], 1).astype(np.float32).ravel())
    fm = me.attributes.new('fmask', 'FLOAT', 'FACE')
    fm.data.foreach_set('value', FM.astype(np.float32))
    me.shade_smooth()
    me.normals_split_custom_set(B(VN).reshape(-1, 3).astype(np.float64).tolist())
    uvl = me.uv_layers.new(name='face')
    uvl.uv.foreach_set('vector', UV.reshape(-1, 2).astype(np.float32).ravel())
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    ob.location = Vector(B(origin) * SCALE)
    return ob


def whisker_curves(ch, origin, parent, coll, tag):
    """Each whisker as a thin bevelled curve, tapering to its tip, parented to `parent`."""
    m = bpy.data.materials.get('whisker')
    if m is None:
        m = bpy.data.materials.new('whisker')
        m.use_nodes = True
        m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.05, 0.035, 0.03, 1)
        m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.5
    for k, wk in enumerate(getattr(ch, 'whiskers', []) or []):
        P = B(wk.points(12) - np.asarray(origin)) * SCALE
        cu = bpy.data.curves.new(f'{tag}_whisker_{k}', 'CURVE')
        cu.dimensions = '3D'
        cu.bevel_depth = wk.width * 0.5 * SCALE * 0.6
        cu.bevel_resolution = 2
        sp = cu.splines.new('POLY')
        sp.points.add(len(P) - 1)
        for i, p in enumerate(P):
            sp.points[i].co = (float(p[0]), float(p[1]), float(p[2]), 1.0)
            sp.points[i].radius = 1.0 - 0.6 * i / (len(P) - 1)
        cu.materials.append(m)
        ob = bpy.data.objects.new(f'{tag}_whisker_{k}', cu)
        coll.objects.link(ob)
        ob.parent = parent
    return m


def image(name, rgba, colorspace='sRGB'):
    h, w = rgba.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.colorspace_settings.name = colorspace
    NB.set_image(img, rgba)                # the same rows the villager renders feed Blender
    img.pack()
    return img


def ortho_camera(name, yaw, pitch, target, ortho):
    d, r, u = NB.cam_basis(yaw, pitch)
    X, Y, Z = (B(v) for v in (r, u, d))
    mat = Matrix(((X[0], Y[0], Z[0], 0), (X[1], Y[1], Z[1], 0), (X[2], Y[2], Z[2], 0), (0, 0, 0, 1)))
    mat.translation = Vector(B(np.asarray(target) + d * 120.0) * SCALE)
    cd = bpy.data.cameras.new(name)
    cd.type = 'ORTHO'
    cd.ortho_scale = ortho
    cd.clip_end = 100.0
    ob = bpy.data.objects.new(name, cd)
    bpy.context.scene.collection.objects.link(ob)
    ob.matrix_world = mat
    return ob


def main(out):
    VB.reset()
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.fps = FPS
    sc.frame_start, sc.frame_end = 1, FRAMES
    sc.view_settings.view_transform = 'AgX'
    VB.setup_world((0.78, 0.86, 0.97), 0.8)
    VB.add_light({'type': 'sun', 'dir': (0.42, -0.78, -0.48), 'power': 3.0, 'color': 5600, 'angle': 4.0})

    rest = build_sher()
    pal = npc_palette(rest, INK)
    faces = {}
    for e in list(NPC_EXPRESSIONS) + ['blink']:
        rgba, lit = face_canvas(rest, pal, NPC_EXPRESSIONS.get(e, e))
        faces[e] = (image(f'face_{e}', rgba), image(f'lit_{e}', np.dstack([lit] * 3 + [np.full_like(lit, 255)]), 'Non-Color'))
    mat = NB.npc_material(*faces['neutral'])
    mat.name = 'sher'

    # ---- the rest pose, in the villagers' parts
    sher = bpy.data.collections.new('Sher')
    sc.collection.children.link(sher)
    C, Nf, COL, VN, PART = mesh_arrays(rest.model, pal)
    UV, FM = face_projection(rest, C, Nf, PART)
    root = bpy.data.objects.new('Sher', None)
    sher.objects.link(root)
    for pid, pname in enumerate(PART_NAMES):
        sel = PART == pid
        if not sel.any():
            continue
        origin = rest.pivots.get(pname, (0.0, 0.0, 0.0))
        ob = make_mesh(f'sher_{pname}', C[sel], VN[sel], COL[sel], UV[sel], FM[sel], origin, mat, sher)
        ob.parent = root
        if pname == 'head':
            whisker_curves(rest, origin, ob, sher, 'sher')

    # ---- the walk and the run: one mesh per frame, each shown only on its own frame (press play)
    for gi, gait in enumerate(('walk', 'run')):
        pose = sher_pose(gait)
        coll = bpy.data.collections.new(f'Sher {gait}')
        sc.collection.children.link(coll)
        groot = bpy.data.objects.new(f'Sher {gait}', None)
        coll.objects.link(groot)
        groot.location = (5.0 * (gi + 1), 0.0, 0.0)
        for i in range(FRAMES):
            p, bob = pose(i)
            ch = build_sher(2, legs=p['legs'], arms=p['arms'], lo_y=-3, lean=p['lean'])
            C, Nf, COL, VN, PART = mesh_arrays(ch.model, pal)
            UV, FM = face_projection(ch, C, Nf, PART)
            # each frame projects the face itself (it moves with the lean), so the shared material fits
            ob = make_mesh(f'{gait}_{i + 1}', C, VN, COL, UV, FM, (0.0, -bob, 0.0), mat, coll)
            ob.parent = groot
            ob.location = (0.0, 0.0, 0.0)
            whisker_curves(ch, (0.0, -bob, 0.0), ob, coll, f'{gait}_{i + 1}')
            for o in [ob] + list(ob.children):
                for f in range(1, FRAMES + 1):
                    hide = f != i + 1
                    o.hide_viewport = hide
                    o.hide_render = hide
                    o.keyframe_insert('hide_viewport', frame=f)
                    o.keyframe_insert('hide_render', frame=f)
            print(gait, 'frame', i + 1, flush=True)

    # ---- a ground and two cameras
    me = bpy.data.meshes.new('ground')
    me.from_pydata([(-6, -6, 0), (10, -6, 0), (10, 6, 0), (-6, 6, 0)], [], [(0, 1, 2, 3)])
    g = bpy.data.objects.new('ground', me)
    sc.collection.objects.link(g)
    gm = bpy.data.materials.new('grass')
    gm.diffuse_color = (0.33, 0.55, 0.22, 1)
    try:
        gm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.2, 0.42, 0.12, 1)
    except Exception:
        pass
    me.materials.append(gm)
    top = (0.0, 17.0, 0.0)
    cam = ortho_camera('cam_portrait', -24.0, 12.0, top, 4.6)
    ortho_camera('cam_wilds', 0.0, MAP_PITCH, (25.0, 12.0, 0.0), 9.0)
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = 900, 1100

    txt = bpy.data.texts.new('README')
    txt.write(
        'Sher (Evochi, Lumen Wilds)\n\n'
        'Collection "Sher": the rest pose in the villagers\' parts. sher_head and sher_arm pivot where the game\n'
        'animates them (rotate them to try poses). The face is a painted texture: in the "sher" material,\n'
        'swap the two image nodes to face_<expression> / lit_<expression> (neutral, happy, worried, thinking,\n'
        'proud, blink) to change his expression.\n\n'
        'Collections "Sher walk" and "Sher run": the cycles, one mesh per frame. Press play (Spacebar) to watch them loop.\n\n'
        'Cameras: cam_portrait (the dialogue angle) and cam_wilds (the Lumen Wilds map camera).\n'
        'Built from tools/art/wilds_npcs.py; regenerate with tools/art/wilds_blend.py.\n')
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(out), compress=True)
    print('saved', out, flush=True)


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    main(args[0])

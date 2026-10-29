"""Every item model (assets.py) as Blender files: one .blend per category with its items standing on a grid, each
labelled and turning on its own turntable (press play), plus a .glb of each item for any Blender version.

    python3 assets_blend.py OUT_DIR [category ...]      (a Python with the bpy module)
    -> OUT_DIR/assets_<category>.blend, OUT_DIR/glb/<category>/<item>.glb

Each item is its voxel model as a mesh: every voxel face carries its colour (the `Col` colour attribute), the
smoothed normals the game shades with, and glowing parts (lantern glass, lumen crystal, embers) as emission.
Units: 1 voxel unit = 10 cm; items face -Y (Blender's front view looks at their front).
Built from tools/art/assets.py; regenerate with tools/art/assets_blend.py.
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy                                                          # noqa: E402

import village_blender as VB                                        # noqa: E402
from village_npc_render import mesh_arrays                          # noqa: E402
from cast_blend import quads_object, materials, glow_of, ground_y, FRAMES, ortho_camera   # noqa: E402
from assets import CATEGORIES, category                             # noqa: E402

SCALE = VB.SCALE


def footprint(M):
    idx = np.argwhere(M.m > 0)
    if not len(idx):
        return 0.1, 0.1, 0.1
    ext = (idx.max(0) - idx.min(0) + 1) / M.res * SCALE
    return float(ext[0]), float(ext[2]), float(ext[1])     # width, depth, height (m)


def label(text, loc, coll, size):
    cu = bpy.data.curves.new('label ' + text, 'FONT')
    cu.body = text
    cu.size = size
    cu.align_x = 'CENTER'
    ob = bpy.data.objects.new('label ' + text, cu)
    coll.objects.link(ob)
    ob.location = loc
    m = bpy.data.materials.get('label') or bpy.data.materials.new('label')
    m.use_nodes = True
    m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.05, 0.035, 0.03, 1)
    cu.materials.append(m)
    return ob


def spin(root):
    root.rotation_mode = 'XYZ'
    for f, ang in ((1, 0.0), (FRAMES + 1, 2 * math.pi)):
        root.rotation_euler = (0, 0, ang)
        root.keyframe_insert('rotation_euler', index=2, frame=f)
    act = root.animation_data.action
    curves = list(getattr(act, 'fcurves', []) or [])
    if not curves:
        for layer in getattr(act, 'layers', []):
            for strip in layer.strips:
                for bag in strip.channelbags:
                    curves += list(bag.fcurves)
    for fc in curves:
        for kp in fc.keyframe_points:
            kp.interpolation = 'LINEAR'
        fc.modifiers.new('CYCLES')
    root.rotation_euler = (0, 0, 0)


def build_category(cat, title, out):
    VB.reset()
    sc = bpy.context.scene
    for eng in ('BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT'):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            continue
    sc.frame_start, sc.frame_end = 1, FRAMES
    VB.setup_world((0.86, 0.88, 0.95), 0.9)
    VB.add_light({'type': 'sun', 'dir': (0.42, -0.78, -0.48), 'power': 3.2, 'color': 5600, 'angle': 4.0})
    mats = materials()
    items = category(cat)
    top = bpy.data.collections.new(title)
    sc.collection.children.link(top)
    fps = [footprint(a.model) for a in items]
    cell = max(max(w, d) for w, d, _ in fps) * 1.35 + 0.15
    hmax = max(h for _, _, h in fps)
    cols = max(1, int(math.ceil(math.sqrt(len(items) * 1.6))))
    rows = int(math.ceil(len(items) / cols))
    roots = []
    for i, a in enumerate(items):
        r, c = divmod(i, cols)
        x = (c - (cols - 1) / 2) * cell
        y = (r - (rows - 1) / 2) * cell
        coll = bpy.data.collections.new(a.name)
        top.children.link(coll)
        root = bpy.data.objects.new(a.name, None)
        root.empty_display_type = 'CIRCLE'
        root.empty_display_size = cell * 0.35
        coll.objects.link(root)
        root.location = (x, y, -ground_y(a.model) * SCALE)
        C, Nf, COL, VN, PART = mesh_arrays(a.model, a.pal)
        ob = quads_object(a.name + ' model', C, COL, (0.0, 0.0, 0.0), mats['body'], coll, VN=VN,
                          attr={'Glow': glow_of(a.model, C, Nf)})
        ob.parent = root
        spin(root)
        label(a.name, (x, y - cell * 0.42, 0.002), coll, cell * 0.075)
        roots.append((a, root))
        print(cat, a.key, flush=True)
    # the floor, cameras, README
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, 0))
    g = bpy.context.active_object
    g.name = 'floor'
    g.scale = (cols * cell + cell, rows * cell + cell, 1)
    gm = bpy.data.materials.new('floor')
    gm.use_nodes = True
    gm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.86, 0.8, 0.7, 1)
    g.data.materials.append(gm)
    span = max(cols, rows) * cell
    sc.camera = ortho_camera('cam_three_quarter', 30.0, 35.0, (0, 0, hmax * 0.4), span * 1.15)
    ortho_camera('cam_top', 0.0, 89.0, (0, 0, 0), span * 1.1)
    sc.render.resolution_x, sc.render.resolution_y = 1600, 1200
    txt = bpy.data.texts.new('README')
    txt.write('%s: %d items\n\n' % (title, len(items)) + __doc__.split('\n\n', 2)[2])
    bpy.context.preferences.filepaths.save_version = 0
    blend = os.path.join(out, 'assets_%s.blend' % cat)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend), compress=True)
    # a .glb per item: the model alone, at rest
    gdir = os.path.join(out, 'glb', cat)
    os.makedirs(gdir, exist_ok=True)
    for a, root in roots:
        bpy.ops.object.select_all(action='DESELECT')
        for o in root.children_recursive:
            o.select_set(True)
        kw = dict(filepath=os.path.abspath(os.path.join(gdir, a.key + '.glb')), export_format='GLB', use_selection=True,
                  export_animations=False)
        try:
            bpy.ops.export_scene.gltf(**kw, export_vertex_color='MATERIAL')
        except TypeError:
            bpy.ops.export_scene.gltf(**kw)
    return blend


def main(out, only=None):
    os.makedirs(out, exist_ok=True)
    for cat, title in CATEGORIES:
        if only and cat not in only:
            continue
        print('built', build_category(cat, title, out), flush=True)


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    main(args[0], args[1:] or None)

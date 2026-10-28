"""The cast (cast.py) as Blender files: one .blend per character, plus .glb files for any Blender version.

    python3 cast_blend.py OUT_DIR [key ...]          (a Python with the bpy module)
    -> OUT_DIR/<key>.blend, and a .glb per colourway or variant (OUT_DIR/<key>[_<variant>].glb)

In each file, every colourway or variant stands in a row, each in its own collection:
  - the body: the voxel model as a mesh, every voxel face carrying its colour (the `Col` colour attribute,
    the same palette the game draws with), the game's smoothed normals, and glowing voxels (the Hollows'
    violet, Flint's headlamp, the Sentinel's runes) as emission
  - villagers in their animated parts: `body`, `head` and `arm` objects, the head and arm pivoting where the
    game nods and swings them (rotate them to pose)
  - the face as painted decals lying on the head, one object per expression in the "<name> faces" collection
    (only `default`/`neutral` is shown: hide it and show another to change the expression)
  - the Evochi's markings (spots, stripes) as decals on the body, per colourway
  - Sher's whiskers as real curves
Units: 1 voxel unit = 10 cm; each character stands on the ground at its own spot, facing -Y (Blender's front
view looks at its face). Press play to turn them all on a turntable. Cameras: `cam_front`, `cam_three_quarter`.
Built from tools/art/cast.py; regenerate with tools/art/cast_blend.py.
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
from village_npc_render import mesh_arrays    # noqa: E402
from village_npcs import PART_NAMES           # noqa: E402
from cast import cast                         # noqa: E402

SCALE = VB.SCALE
FRAMES = 240
LIFT = 0.3          # model units: how far painted decals stand off the smoothed surface


def B(v):
    """model space (x right, y up, z front) -> Blender (x right, y back, z up)"""
    v = np.asarray(v, np.float64)
    return np.stack([v[..., 0], -v[..., 2], v[..., 1]], -1)


# ---------------------------------------------------------------------------------------------- materials
def _vc_material(name, emit_attr, emit_k, rough=0.62):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes['Principled BSDF']
    vc = nt.nodes.new('ShaderNodeVertexColor')
    vc.layer_name = 'Col'
    nt.links.new(vc.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = rough
    at = nt.nodes.new('ShaderNodeAttribute')
    at.attribute_name = emit_attr
    mul = nt.nodes.new('ShaderNodeMath')
    mul.operation = 'MULTIPLY'
    mul.inputs[1].default_value = emit_k
    nt.links.new(at.outputs['Fac'], mul.inputs[0])
    nt.links.new(vc.outputs['Color'], bsdf.inputs['Emission Color'])
    nt.links.new(mul.outputs['Value'], bsdf.inputs['Emission Strength'])
    return m


def materials():
    return {'body': _vc_material('voxel body', 'Glow', 4.0),
            'decal': _vc_material('painted decal', 'Unlit', 0.35, rough=0.5)}


# ---------------------------------------------------------------------------------------------- meshes
def quads_object(name, Q, COL, origin, mat, coll, VN=None, attr=None):
    """quads (N,4,3, model units) as an object whose origin sits at `origin` (model units); COL sRGB 0-255 per
    quad; VN per-corner normals (model space) or None; attr: {name: per-quad float} face attributes"""
    n = len(Q)
    V = (B(Q.astype(np.float64) - np.asarray(origin)) * SCALE).reshape(-1, 3)
    me = bpy.data.meshes.new(name)
    me.vertices.add(len(V))
    me.vertices.foreach_set('co', V.astype(np.float32).ravel())
    me.loops.add(n * 4)
    me.loops.foreach_set('vertex_index', np.arange(n * 4, dtype=np.int32))
    me.polygons.add(n)
    me.polygons.foreach_set('loop_start', (np.arange(n) * 4).astype(np.int32))
    me.polygons.foreach_set('loop_total', np.full(n, 4, np.int32))
    me.update(calc_edges=True)
    lin = VB.srgb_to_linear(np.asarray(COL, np.float32)[:, :3])
    col = np.repeat(np.concatenate([lin, np.ones((n, 1), np.float32)], 1), 4, 0)
    a = me.color_attributes.new('Col', 'FLOAT_COLOR', 'CORNER')
    a.data.foreach_set('color', col.astype(np.float32).ravel())
    me.color_attributes.active_color = a
    try:
        me.color_attributes.render_color_index = me.color_attributes.active_color_index
    except Exception:
        pass
    for k, vals in (attr or {}).items():
        fa = me.attributes.new(k, 'FLOAT', 'FACE')
        fa.data.foreach_set('value', np.asarray(vals, np.float32))
    if VN is not None:
        me.shade_smooth()
        me.normals_split_custom_set(B(VN).reshape(-1, 3).astype(np.float64).tolist())
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    ob.location = Vector(B(origin) * SCALE)
    return ob


def glow_of(M, C, Nf):
    """the emissive amount of the voxel behind each face"""
    cen = C.astype(np.float64).mean(1) - Nf * (0.5 / M.res)
    vox = np.floor(cen * M.res).astype(int) - np.asarray(M.lo)
    vox = np.clip(vox, 0, np.array(M.m.shape) - 1)
    return M.glow[vox[:, 0], vox[:, 1], vox[:, 2]]


def decal_object(name, quads, origin, mat, coll):
    keep = [q for q in quads if q.alpha >= 0.35]
    if not keep:
        return None
    # lifted clear of the voxel stair-steps (the flat renderer gives them a depth bias for the same reason)
    Q = np.stack([q.pts + np.asarray(q.normal) * LIFT for q in keep])
    COL = np.stack([np.asarray(q.color, np.float32) for q in keep])
    unlit = np.array([1.0 - float(q.lit) for q in keep], np.float32)
    return quads_object(name, Q, COL, origin, mat, coll, attr={'Unlit': unlit})


def ground_y(M):
    return (np.argwhere(M.m > 0)[:, 1].min() + M.lo[1]) / M.res


def width_of(M):
    idx = np.argwhere(M.m > 0)
    return (idx[:, 0].max() - idx[:, 0].min() + 1) / M.res


# ---------------------------------------------------------------------------------------------- one variant
def build_variant(member, v, x, mats, parent_coll):
    from charrender import face_quads, pattern_quads
    tag = member.name if len(member.variants) == 1 else '%s %s' % (member.name, v.label)
    coll = bpy.data.collections.new(tag)
    parent_coll.children.link(coll)
    root = bpy.data.objects.new(tag, None)
    root.empty_display_type = 'CIRCLE'
    root.empty_display_size = 0.4
    coll.objects.link(root)
    M = v.model
    root.location = (x, 0.0, -ground_y(M) * SCALE)

    C, Nf, COL, VN, PART = mesh_arrays(M, v.pal)
    GLOW = glow_of(M, C, Nf)
    parts = {}
    has_parts = v.ch is not None and len(np.unique(PART)) > 1 and getattr(v.ch, 'pivots', None)
    for pid in (np.unique(PART) if has_parts else [None]):
        sel = PART == pid if pid is not None else np.ones(len(C), bool)
        pname = PART_NAMES[pid] if pid is not None else 'body'
        origin = v.ch.pivots.get(pname, (0.0, 0.0, 0.0)) if has_parts else (0.0, 0.0, 0.0)
        ob = quads_object('%s %s' % (tag, pname), C[sel], COL[sel], origin, mats['body'], coll, VN=VN[sel],
                          attr={'Glow': GLOW[sel]})
        ob.parent = root
        parts[pname] = (ob, origin)
    head, horigin = parts.get('head', parts['body'])

    if v.ch is not None:
        ch = v.ch
        # markings (the Evochi's spots and stripes) on the body
        pq = pattern_quads(ch, v.pal, v.pal_key)
        if pq:
            body, borigin = parts['body']
            ob = decal_object('%s markings' % tag, pq, borigin, mats['decal'], coll)
            if ob:
                ob.parent = body
                ob.location = (0, 0, 0)
        # the face, one decal object per expression, all riding on the head
        fc = bpy.data.collections.new('%s faces' % tag)
        coll.children.link(fc)
        shown = None
        for label, expr in member.expressions.items():
            ob = decal_object('%s face %s' % (tag, label), face_quads(ch, v.pal, v.pal_key, expr), horigin, mats['decal'], fc)
            if ob is None:
                continue
            ob.parent = head
            ob.location = (0, 0, 0)
            hide = expr != 'default' or shown is not None
            ob.hide_viewport = ob.hide_render = hide
            if not hide:
                shown = label
        if getattr(ch, 'whiskers', None):
            from wilds_blend import whisker_curves
            whisker_curves(ch, horigin, head, coll, tag.lower())
    # a turntable: one full turn over FRAMES, looping
    root.rotation_mode = 'XYZ'
    for f, ang in ((1, 0.0), (FRAMES + 1, 2 * math.pi)):
        root.rotation_euler = (0, 0, ang)
        root.keyframe_insert('rotation_euler', index=2, frame=f)
    try:
        for fc_ in root.animation_data.action.fcurves:
            for kp in fc_.keyframe_points:
                kp.interpolation = 'LINEAR'
            fc_.modifiers.new('CYCLES')
    except Exception:
        for layer in getattr(root.animation_data.action, 'layers', []):
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for fc_ in bag.fcurves:
                        for kp in fc_.keyframe_points:
                            kp.interpolation = 'LINEAR'
                        fc_.modifiers.new('CYCLES')
    root.rotation_euler = (0, 0, 0)
    return root, width_of(M) * SCALE, (np.ptp(np.argwhere(M.m > 0)[:, 1]) + 1) / M.res * SCALE


def ortho_camera(name, yaw_deg, pitch_deg, target, ortho, dist=30.0):
    y, p = math.radians(yaw_deg), math.radians(pitch_deg)
    d = Vector((math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p)))   # toward the camera
    cd = bpy.data.cameras.new(name)
    cd.type = 'ORTHO'
    cd.ortho_scale = ortho
    cd.clip_end = 200.0
    ob = bpy.data.objects.new(name, cd)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = Vector(target) + d * dist
    ob.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    return ob


def build_file(member, out):
    VB.reset()
    sc = bpy.context.scene
    for eng in ('BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT'):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            continue
    sc.frame_start, sc.frame_end = 1, FRAMES
    sc.render.fps = 30
    sc.view_settings.view_transform = 'AgX' if 'AgX' in [i.identifier for i in sc.view_settings.bl_rna.properties['view_transform'].enum_items] else 'Filmic'
    VB.setup_world((0.86, 0.88, 0.95), 0.9)
    VB.add_light({'type': 'sun', 'dir': (0.42, -0.78, -0.48), 'power': 3.2, 'color': 5600, 'angle': 4.0})
    mats = materials()
    top = bpy.data.collections.new(member.name)
    sc.collection.children.link(top)
    x, roots, hmax = 0.0, [], 0.0
    gap = 0.8
    widths = []
    for v in member.variants:
        widths.append(width_of(v.model) * SCALE)
    for i, v in enumerate(member.variants):
        cx = x + widths[i] / 2
        root, w, h = build_variant(member, v, cx, mats, top)
        roots.append(root)
        hmax = max(hmax, h)
        x += widths[i] + gap
        print(member.key, v.label, flush=True)
    span = x - gap
    # center the row on the origin
    for r in roots:
        r.location.x -= span / 2
    # a ground disc under everyone
    bpy.ops.mesh.primitive_circle_add(vertices=64, radius=max(span, hmax) * 0.75, fill_type='NGON', location=(0, 0, 0))
    g = bpy.context.active_object
    g.name = 'ground'
    gm = bpy.data.materials.new('ground')
    gm.use_nodes = True
    gm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.42, 0.55, 0.30, 1)
    gm.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.9
    g.data.materials.append(gm)
    tgt = (0.0, 0.0, hmax * 0.5)
    ortho = max(span * 1.12, hmax * 1.35)
    sc.camera = ortho_camera('cam_three_quarter', 30.0, 12.0, tgt, ortho)
    ortho_camera('cam_front', 0.0, 8.0, tgt, ortho)
    sc.render.resolution_x = int(1600)
    sc.render.resolution_y = int(max(700, 1600 * (hmax * 1.35) / ortho))
    txt = bpy.data.texts.new('README')
    txt.write(__doc__.split('\n\n', 1)[1].replace('python3 cast_blend.py OUT_DIR [key ...]          (a Python with the bpy module)\n    -> OUT_DIR/<key>.blend, OUT_DIR/<key>.glb\n\n', ''))
    blend = os.path.join(out, member.key + '.blend')
    bpy.context.preferences.filepaths.save_version = 0      # no .blend1 backups
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend), compress=True)
    g.hide_set(True)                                        # the .glb carries the characters only
    # the .glb: one per colourway / variant (what is shown: the default face), without the turntable
    glbs = []
    for v, root in zip(member.variants, roots):
        bpy.ops.object.select_all(action='DESELECT')
        for o in [root] + list(root.children_recursive):
            if o.visible_get():
                o.select_set(True)
        name = member.key if len(member.variants) == 1 else '%s_%s' % (member.key, v.label.lower())
        glb = os.path.join(out, name + '.glb')
        kw = dict(filepath=os.path.abspath(glb), export_format='GLB', use_selection=True, export_animations=False)
        try:
            bpy.ops.export_scene.gltf(**kw, export_vertex_color='MATERIAL')
        except TypeError:
            bpy.ops.export_scene.gltf(**kw)
        glbs.append(glb)
    return blend, glbs


def main(out, only=None):
    os.makedirs(out, exist_ok=True)
    for m in cast(only):
        print('built', build_file(m, out), flush=True)


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    main(args[0], args[1:] or None)

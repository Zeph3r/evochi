"""Cinematic plates for the onboarding (the Fading Paths cold open and the beats after it), rendered in
Cycles like the village scenes (village_blender.py), plus what the storyboard asks for:

  - depth of field (the scene's camera `focus` and `fstop`), and a depth pass saved beside the raw frame
    so the grade can lay haze over the distance (and the app can fog, blur or fade by depth)
  - gradient skies that light the scene (zenith, horizon, ground) rather than a flat world colour
  - the cast in the scene: a villager or an Evochi placed with an expression, a turn and a size, built
    the way cast_blend.py builds them (smoothed normals, painted face and markings as decals, glow)
  - layered renders: any model or actor can be hidden from the camera while it still lights, shadows and
    occludes (`camera=False`), so an egg, a glowing trail or a villager comes out as its own sprite lit by
    the room; a model can also be a shadow catcher (`shadow_catcher=True`)
  - a film grade: bloom, soft glow, haze by depth, warm highlights and cool shadows, lift/gain, a
    vignette and a touch of grain (cine_scenes' GRADES)

    python3 cine_blender.py OUT_DIR scene [scene ...] [--quick | --preview] [--raw RAW_DIR] [--gpu]
    python3 cine_blender.py --regrade OUT_DIR scene ...        (grade again from the saved raw + depth)

Writes OUT_DIR/<scene>.png (graded), RAW_DIR/<scene>_raw.png, RAW_DIR/<scene>_z.exr (depth, metres, in
`depth.V`) and OUT_DIR/cine.json: per scene its size, anchors and polylines projected to pixels, the
camera, and the depth range.
"""
from __future__ import annotations

import json
import math
import os
import sys
import time
from dataclasses import dataclass, field

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import village_blender as VB    # noqa: E402

try:
    import bpy
    from bpy_extras.object_utils import world_to_camera_view
    from mathutils import Vector
except ImportError:              # the grade alone (no Blender) still imports
    bpy = None

SCALE = VB.SCALE


# ------------------------------------------------------------------------------------------------ actors ----
@dataclass
class Actor:
    """A character standing in the scene. `pos` is its ground point in voxel-space units, `yaw` turns it about
    the up axis (0 faces the viewer, +z; positive turns its face toward +x), `scale` its size. `expr` is the
    face it wears; `camera=False` keeps it out of the picture (it still lights and shadows)."""
    name: str
    ch: object                       # the Character (characters.build / village_npcs.build_*)
    pal: dict
    pal_key: str = ''
    expr: str = 'default'
    pos: tuple = (0.0, 0.0, 0.0)
    yaw: float = 0.0
    scale: float = 1.0
    camera: bool = True
    shadow: bool = True
    rot: tuple = (0.0, 0.0, 0.0)     # extra tilt (pitch about x, roll about z, degrees), after the yaw
    glow_k: float = 4.0


def actor_arrays(a: Actor):
    """everything Blender needs to stand the actor in a scene, as plain arrays (so a scene can be packed and
    rendered on a machine with only bpy + numpy): per part its quads, colours, normals, glow and pivot; the
    markings and the face as lifted decal quads with their colours and unlit amounts."""
    from village_npc_render import mesh_arrays
    from cast_blend import glow_of, LIFT, PART_NAMES
    from charrender import face_quads, pattern_quads
    ch = a.ch
    M = ch.model
    C, Nf, COL, VN, PART = mesh_arrays(M, a.pal)
    GLOW = glow_of(M, C, Nf)
    pivots = getattr(ch, 'pivots', None)
    has_parts = len(np.unique(PART)) > 1 and pivots
    parts = []
    for pid in (np.unique(PART) if has_parts else [None]):
        sel = PART == pid if pid is not None else np.ones(len(C), bool)
        pname = PART_NAMES[pid] if pid is not None else 'body'
        origin = pivots.get(pname, (0.0, 0.0, 0.0)) if has_parts else (0.0, 0.0, 0.0)
        parts.append({'name': pname, 'origin': list(origin), 'C': C[sel].astype(np.float32), 'COL': COL[sel].astype(np.float32),
                      'VN': VN[sel].astype(np.float32), 'GLOW': GLOW[sel].astype(np.float32)})

    def decal(quads):
        keep = [q for q in quads if q.alpha >= 0.35]
        if not keep:
            return None
        Q = np.stack([q.pts + np.asarray(q.normal) * LIFT for q in keep]).astype(np.float32)
        COLq = np.stack([np.asarray(q.color, np.float32) for q in keep])
        unlit = np.array([1.0 - float(q.lit) for q in keep], np.float32)
        return {'Q': Q, 'COL': COLq, 'UNLIT': unlit}
    decals = {}
    pq = pattern_quads(ch, a.pal, a.pal_key)
    if pq:
        d = decal(pq)
        if d:
            decals['markings'] = d
    if a.expr:
        d = decal(face_quads(ch, a.pal, a.pal_key, a.expr))
        if d:
            decals['face'] = d
    head = 'head' if any(p['name'] == 'head' for p in parts) else 'body'
    return {'name': a.name, 'pos': list(a.pos), 'yaw': a.yaw, 'rot': list(a.rot), 'scale': a.scale, 'camera': a.camera,
            'shadow': a.shadow, 'glow_k': a.glow_k, 'parts': parts, 'decals': decals, 'head': head}


def B(v):
    """model space (x right, y up, z front) -> Blender (x right, y back, z up)"""
    v = np.asarray(v, np.float64)
    return np.stack([v[..., 0], -v[..., 2], v[..., 1]], -1)


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
    ca = me.color_attributes.new('Col', 'FLOAT_COLOR', 'CORNER')
    ca.data.foreach_set('color', col.astype(np.float32).ravel())
    me.color_attributes.active_color = ca
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


def actor_objects(A, coll):
    """stand a packed actor (actor_arrays) in the scene; returns the root"""
    mats = _actor_materials(A['glow_k'])
    root = bpy.data.objects.new(A['name'], None)
    coll.objects.link(root)
    root.location = VB.to_blender(A['pos'])
    root.rotation_mode = 'XYZ'
    root.rotation_euler = (math.radians(A['rot'][0]), math.radians(A['rot'][1]), A['yaw'])
    root.scale = (A['scale'], A['scale'], A['scale'])
    parts = {}
    for p in A['parts']:
        ob = quads_object('%s %s' % (A['name'], p['name']), p['C'], p['COL'], p['origin'], mats['body'], coll, VN=p['VN'],
                          attr={'Glow': p['GLOW']})
        ob.parent = root
        parts[p['name']] = (ob, p['origin'])
    for key, d in A['decals'].items():
        host, horigin = parts.get(A['head'] if key == 'face' else 'body', parts['body'])
        ob = quads_object('%s %s' % (A['name'], key), d['Q'], d['COL'], horigin, mats['decal'], coll, attr={'Unlit': d['UNLIT']})
        ob.parent = host
        ob.location = (0, 0, 0)
    for ob in list(coll.objects):
        if ob.name.startswith(A['name'] + ' ') and ob.type == 'MESH':
            ob.visible_camera = bool(A['camera'])
            ob.visible_shadow = bool(A['shadow'])
    return root


def build_actor(a: Actor, coll):
    return actor_objects(actor_arrays(a), coll)


_AM = {}


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


def _actor_materials(glow_k):
    key = round(glow_k, 3)
    if key not in _AM:
        _AM[key] = {'body': _vc_material('actor body %g' % glow_k, 'Glow', glow_k, rough=0.62),
                    'decal': _vc_material('actor decal %g' % glow_k, 'Unlit', 0.35, rough=0.5)}
    return _AM[key]


# ------------------------------------------------------------------------------------------------- world ----
def hex3(h):
    h = h.lstrip('#')
    return [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]


def setup_sky_world(sky, strength, ground=None, horizon_width=0.35):
    """A gradient world that lights the scene: `sky` = (zenith hex, horizon hex), `ground` = hex below the
    horizon (a dim version of the horizon when None)."""
    w = bpy.data.worlds.new('w')
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes['Background']
    bg.inputs['Strength'].default_value = strength
    tc = nt.nodes.new('ShaderNodeTexCoord')
    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    nt.links.new(tc.outputs['Generated'], sep.inputs['Vector'])
    mr = nt.nodes.new('ShaderNodeMapRange')
    mr.inputs['From Min'].default_value = -0.08
    mr.inputs['From Max'].default_value = horizon_width + 0.35
    mr.clamp = True
    nt.links.new(sep.outputs['Z'], mr.inputs['Value'])
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    zen, hor = VB.srgb_to_linear(np.array(VB.hexrgb(sky[0]), np.float32)), VB.srgb_to_linear(np.array(VB.hexrgb(sky[1]), np.float32))
    gnd = VB.srgb_to_linear(np.array(VB.hexrgb(ground), np.float32)) if ground else hor * 0.35
    cr = ramp.color_ramp
    cr.elements[0].position = 0.0
    cr.elements[0].color = (*gnd, 1.0)
    e1 = cr.elements.new(0.12)
    e1.color = (*hor, 1.0)
    cr.elements[-1].position = 1.0
    cr.elements[-1].color = (*zen, 1.0)
    nt.links.new(mr.outputs['Result'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], bg.inputs['Color'])
    bpy.context.scene.world = w


# ------------------------------------------------------------------------------------------------ render ----
def _compositor_depth(sc, out_dir, name, zmax):
    """write the Z pass as RAW/<name>_z.exr (metres, clamped to zmax) through the compositor"""
    vl = bpy.context.view_layer
    vl.use_pass_z = True
    nt = bpy.data.node_groups.new('comp_' + name, 'CompositorNodeTree')
    sc.compositing_node_group = nt
    rl = nt.nodes.new('CompositorNodeRLayers')
    mr = nt.nodes.new('ShaderNodeMapRange')
    mr.inputs['From Min'].default_value = 0.0
    mr.inputs['From Max'].default_value = zmax
    mr.inputs['To Min'].default_value = 0.0
    mr.inputs['To Max'].default_value = zmax
    mr.clamp = True
    nt.links.new(rl.outputs['Depth'], mr.inputs['Value'])
    fo = nt.nodes.new('CompositorNodeOutputFile')
    fo.directory = out_dir
    fo.file_name = name + '_z'
    it = fo.file_output_items.new('FLOAT', 'depth')
    it.save_as_render = False
    fo.format.color_depth = '32'
    nt.links.new(mr.outputs['Result'], fo.inputs['depth'])
    go = nt.nodes.new('NodeGroupOutput')
    nt.interface.new_socket('Image', in_out='OUTPUT', socket_type='NodeSocketColor')
    nt.links.new(rl.outputs['Image'], go.inputs[0])


def read_depth(path):
    """the depth EXR as a float32 (h, w) array in metres (clamped at the scene's zmax)"""
    import OpenEXR
    f = OpenEXR.File(path)
    for k, ch in f.channels().items():
        if k.startswith('depth'):
            return np.asarray(ch.pixels, np.float32)
    raise KeyError('no depth channel in ' + path)


def project(sc, cam, p, w, h):
    co = world_to_camera_view(sc, cam, VB.to_blender(p))
    return [round(co.x * w, 1), round((1 - co.y) * h, 1)]


def render(vs, raw_path, mode='full'):
    """mode: 'full' | 'preview' (half size, a third of the samples) | 'quick' (0.3 size, 12 samples)"""
    VB.reset()
    _AM.clear()
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    if GPU:
        print('device:', VB.use_gpu(sc) or 'CPU (no GPU found)', flush=True)
    scale = {'full': 1.0, 'preview': 0.5, 'quick': 0.3}[mode]
    sc.render.resolution_x = int(vs.w * scale)
    sc.render.resolution_y = int(vs.h * scale)
    sc.render.resolution_percentage = 100
    sc.cycles.samples = {'full': vs.samples, 'preview': max(16, vs.samples // 3), 'quick': 12}[mode]
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.02 if mode == 'full' else 0.05
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
        ob, n = VB.model_mesh(M, f'{vs.name}_{i}', glass, water=tuple(opts.get('water', ())))
        if opts.get('shadow') is False:
            ob.visible_shadow = False
        if opts.get('camera') is False:
            ob.visible_camera = False
        if opts.get('shadow_catcher'):
            ob.is_shadow_catcher = True
        if opts.get('holdout'):
            ob.is_holdout = True
        nf += n
    coll = bpy.data.collections.new('cast')
    sc.collection.children.link(coll)
    for a in getattr(vs, 'actors', None) or []:
        build_actor(a, coll)
    for A in getattr(vs, 'actor_arrays', None) or []:
        actor_objects(A, coll)
    for L in vs.lights:
        VB.add_light(L)
    skyw = getattr(vs, 'sky_world', None)
    if skyw:
        setup_sky_world(skyw['sky'], skyw.get('strength', 0.6), skyw.get('ground'), skyw.get('horizon_width', 0.35))
    else:
        VB.setup_world(vs.world[0], vs.world[1])
    zmax = getattr(vs, 'zmax', None) or 60.0
    raw_dir = os.path.dirname(os.path.abspath(raw_path))
    cameras = getattr(vs, 'cameras', None)
    frames = [(vs.name, vs.cam, raw_path)] if not cameras else \
        [('%s_%02d' % (vs.name, i), c, os.path.join(raw_dir, '%s_%02d_raw.png' % (vs.name, i))) for i, c in enumerate(cameras)]
    print(f'{vs.name}: {nf} faces, {len(vs.lights)} lights, {len(getattr(vs, "actors", None) or []) + len(getattr(vs, "actor_arrays", None) or [])} actors, '
          f'built in {time.time() - t:.1f}s, {sc.render.resolution_x}x{sc.render.resolution_y} @ {sc.cycles.samples}'
          + (f', {len(frames)} frames' if cameras else ''), flush=True)
    W, H = vs.w, vs.h
    out = None
    for fname, camd_, fraw in frames:
        for ob in [o for o in sc.objects if o.type == 'CAMERA']:
            bpy.data.objects.remove(ob)
        cam = VB.setup_camera(camd_, W, H)
        if camd_.get('fov_h'):
            cam.data.sensor_fit = 'HORIZONTAL'
            cam.data.angle = math.radians(camd_['fov_h'])
        _compositor_depth(sc, raw_dir, fname, zmax)
        sc.render.filepath = fraw
        t = time.time()
        bpy.ops.render.render(write_still=True)
        print(f'{fname}: rendered in {time.time() - t:.1f}s -> {fraw}', flush=True)
        for fn in os.listdir(raw_dir):
            if fn.startswith(fname + '_z') and fn.endswith('.exr') and fn != fname + '_z.exr':
                os.replace(os.path.join(raw_dir, fn), os.path.join(raw_dir, fname + '_z.exr'))
        anchors = {k: project(sc, cam, p, W, H) for k, p in (vs.anchors or {}).items()}
        lines = {k: [project(sc, cam, p, W, H) for p in pts] for k, pts in (getattr(vs, 'polylines', None) or {}).items()}
        camd = {'pos': list(camd_['pos']), 'target': list(camd_['target']), 'fov': camd_.get('fov')}
        out = {'w': W, 'h': H, 'anchors': anchors, 'lines': lines, 'camera': camd, 'zmax': zmax, 'scale': scale}
        if cameras:
            META_FRAMES[fname] = out
    return out


# ------------------------------------------------------------------------------------------------- grade ----
def _blur(a, radius):
    """gaussian blur of an (h, w, c) float array"""
    from PIL import Image, ImageFilter
    if radius <= 0:
        return a
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(radius))).astype(np.float32)


def _blur1(a, radius):
    from PIL import Image, ImageFilter
    im = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255.0


def grade_image(rgba, depth, g, w, h, sky=None, transparent=False):
    """rgba float (h,w,4) 0-255; depth float (h,w) metres or None. Returns graded rgba float."""
    a = rgba.copy()
    al = a[..., 3:4] / 255.0
    if transparent and sky and not g.get('keep_alpha'):
        top = np.array(VB.hexrgb(sky[0]), np.float32)
        hor = np.array(VB.hexrgb(sky[1]), np.float32)
        t = np.clip(np.linspace(0, 1, h)[:, None] / g.get('sky_mix', 0.55), 0, 1) ** 1.2
        skyc = top * (1 - t[..., None]) + hor * t[..., None]
        a[..., :3] = a[..., :3] * al + skyc * (1 - al)
        al = np.ones_like(al)
        a[..., 3] = 255
    rgb = a[..., :3].astype(np.float32)
    # haze by depth: the far fades toward the haze colour (an aerial perspective) above a start distance
    if depth is not None and g.get('mist'):
        m = g['mist']
        d = depth
        if d.shape != rgb.shape[:2]:
            from PIL import Image
            d = np.asarray(Image.fromarray(d).resize((rgb.shape[1], rgb.shape[0]), Image.BILINEAR), np.float32)
        t = np.clip((d - m.get('start', 6.0)) / max(1e-3, m.get('end', 30.0) - m.get('start', 6.0)), 0, 1) ** m.get('power', 1.4)
        t = t * m.get('amount', 0.6)
        if transparent and not g.get('keep_alpha'):
            t = t * (al[..., 0] > 0.5)   # the composited sky keeps its own colour
        col = np.array(VB.hexrgb(m.get('color', '#C9B9D6')), np.float32)
        rgb = rgb * (1 - t[..., None]) + col * t[..., None]
    # lift / gamma / gain (per-channel optional)
    if g.get('lift') or g.get('gain') or g.get('gamma'):
        x = rgb / 255.0
        lift = np.array(g.get('lift', (0, 0, 0)), np.float32)
        gain = np.array(g.get('gain', (1, 1, 1)), np.float32)
        gam = np.array(g.get('gamma', (1, 1, 1)), np.float32)
        x = np.clip(x * gain + lift * (1 - x), 0, 1) ** (1.0 / gam)
        rgb = x * 255.0
    # split toning: warm the highlights, cool the shadows
    if g.get('split'):
        s = g['split']
        lum = (0.3 * rgb[..., 0] + 0.59 * rgb[..., 1] + 0.11 * rgb[..., 2]) / 255.0
        hi = np.array(VB.hexrgb(s.get('highlights', '#FFD9A0')), np.float32) / 255.0
        lo = np.array(VB.hexrgb(s.get('shadows', '#5A5A9A')), np.float32) / 255.0
        k = s.get('amount', 0.12)
        tint = hi[None, None] * lum[..., None] + lo[None, None] * (1 - lum[..., None])
        rgb = rgb * (1 - k) + rgb * tint * 2.0 * k
    if g.get('saturation') is not None and g['saturation'] != 1.0:
        lum = (0.3 * rgb[..., 0] + 0.59 * rgb[..., 1] + 0.11 * rgb[..., 2])[..., None]
        rgb = lum + (rgb - lum) * g['saturation']
    if g.get('warm'):
        rgb = rgb * np.array([1 + g['warm'], 1.0, 1 - g['warm']], np.float32)
    # bloom: the bright parts bleed softly, twice (tight and wide)
    if g.get('bloom'):
        lum = rgb.mean(-1)
        thr = g.get('bloom_threshold', 170.0)
        hi = np.clip((lum - thr) / 70.0, 0, 1)[..., None] * rgb
        b1 = _blur(hi, w * 0.006)
        b2 = _blur(hi, w * 0.022)
        b3 = _blur(hi, w * 0.06) if g.get('bloom_wide') else 0
        rgb = rgb + g['bloom'] * (0.6 * b1 + 0.8 * b2) + g.get('bloom_wide', 0) * b3
    # soft glow (Orton): a blurred, brightened copy screened in, for the storyboard's painterly softness
    if g.get('glow'):
        soft = _blur(rgb, w * 0.012)
        k = g['glow']
        rgb = rgb * (1 - k) + (255 - (255 - rgb) * (255 - soft) / 255.0) * k
    if g.get('vignette'):
        yy, xx = np.mgrid[0:h, 0:w]
        d = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2) / math.sqrt(2)
        rgb = rgb * (1 - g['vignette'] * np.clip(d - g.get('vignette_start', 0.35), 0, 1) ** 1.5)[..., None]
    if g.get('grain'):
        rng = np.random.default_rng(3)
        rgb = rgb + rng.normal(0, g['grain'] * 255, rgb.shape[:2])[..., None].astype(np.float32) * 0.6
    out = np.concatenate([np.clip(rgb, 0, 255), a[..., 3:4]], -1)
    return out


def finish(vs, raw_path, out_path, depth_path=None):
    from PIL import Image
    im = Image.open(raw_path).convert('RGBA')
    a = np.asarray(im).astype(np.float32)
    depth = None
    if depth_path and os.path.exists(depth_path):
        try:
            depth = read_depth(depth_path)
            if depth.shape[0] != a.shape[0]:
                depth = np.asarray(Image.fromarray(depth).resize((a.shape[1], a.shape[0]), Image.BILINEAR), np.float32)
            depth = depth[::-1] if getattr(vs, 'flip_depth', False) else depth
        except Exception as e:
            print('depth unavailable:', e, flush=True)
    out = grade_image(a, depth, vs.grade, a.shape[1], a.shape[0], sky=vs.sky, transparent=vs.transparent)
    if vs.transparent and (vs.grade.get('keep_alpha') or getattr(vs, 'keep_alpha', False)):
        Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGBA').save(out_path)
    else:
        Image.fromarray(np.clip(out[..., :3], 0, 255).astype(np.uint8)).save(out_path)


GPU = False
META_FRAMES = {}      # per-frame meta of the last multi-camera scene rendered

if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    mode = 'full'
    if '--preview' in args:
        mode = 'preview'
    if '--quick' in args:
        mode = 'quick'
    GPU = '--gpu' in args
    regrade = '--regrade' in args
    args = [x for x in args if x not in ('--preview', '--quick', '--gpu', '--regrade')]

    def opt(name, default):
        if name in args:
            i = args.index(name)
            v = args[i + 1]
            del args[i:i + 2]
            return v
        return default

    raw_dir = opt('--raw', None)
    out, names = args[0], args[1:]
    packed = all(n.endswith('.npz') for n in names)
    if not packed:
        import cine_scenes as CS
        if names == ['all']:
            names = list(CS.SCENES)
    raw_dir = raw_dir or os.path.join(out, 'raw')
    os.makedirs(out, exist_ok=True)
    os.makedirs(raw_dir, exist_ok=True)
    meta_path = os.path.join(out, 'cine.json')
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    for n in names:
        if packed:
            import cine_pack
            vs = cine_pack.unpack(n)
            n = vs.name
        else:
            vs = CS.SCENES[n]()
        raw = os.path.join(raw_dir, f'{n}_raw.png')
        cameras = getattr(vs, 'cameras', None)
        if not regrade:
            META_FRAMES.clear()
            m = render(vs, raw, mode)
            if cameras:
                meta.update(META_FRAMES)
            else:
                meta[n] = m
            json.dump(meta, open(meta_path, 'w'), indent=1)
        try:
            import PIL  # noqa: F401
        except ImportError:
            print(f'{n}: raw only (no PIL here; grade with --regrade where PIL lives)', flush=True)
            continue
        names_out = [n] if not cameras else ['%s_%02d' % (n, i) for i in range(len(cameras))]
        for fname in names_out:
            finish(vs, os.path.join(raw_dir, f'{fname}_raw.png'), os.path.join(out, f'{fname}.png'), os.path.join(raw_dir, f'{fname}_z.exr'))
        print(f'{n}: graded -> {os.path.join(out, names_out[-1] + ".png")}' + (f' ({len(names_out)} frames)' if cameras else ''), flush=True)

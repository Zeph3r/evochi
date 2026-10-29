"""Every place the game draws, as a Blender scene to open and explore: the voxel sets with their colours, the
glowing lanterns and coals, glass and water, every light the game's renders use (lanterns, forge, sun through
the windows), the sky, and the game's own camera with its render settings, so F12 renders it as the game does
(before the game's grade and ink). Built with the same code as the shipped art (village_blender.py).

    python3 places_blend.py OUT_DIR [key ...]       (a Python with the bpy module)   -> OUT_DIR/<key>.blend
    python3 places_blend.py --list

Units: 1 voxel unit = 10 cm. The camera is `cam` (the game's); each scene's README text says where it is used.
The Thicket (the Lumen Wilds' first floor) is built by wilds_maps.py's own Blender path: places_blend.py calls it
for thicket_ground.blend and thicket_props.blend.
"""
from __future__ import annotations

import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


def _scenes():
    import village_scenes as VS
    import home_scenes
    import trail_scenes
    S = dict(VS.SCENES)
    S.update(home_scenes.SCENES)
    S.update(trail_scenes.SCENES)
    return S


def _lazy(mod, fn, *a, **k):
    def make():
        import importlib
        return getattr(importlib.import_module(mod), fn)(*a, **k)
    return make


def _story(name):
    return lambda: _scenes()[name]()


# key, title, where the game shows it, builder
PLACES = [
    ('village_map', 'Sunlit Village', 'the walkable village: the Square, the houses, the stream, the gates',
     _lazy('village_walk', 'scene_village_walk')),
    ('old_trail', 'The Old Trail', 'the walk from the village to the Crossing: Flint\'s camp, the mine, the Thicket gate',
     _lazy('village_trail', 'scene_trail')),
    ('workshop_inside', 'Bram\'s Workshop', 'inside, walkable', _lazy('village_interiors', 'scene_workshop')),
    ('glasshouse_inside', 'Mira\'s Glasshouse', 'inside, walkable', _lazy('village_interiors', 'scene_glasshouse')),
    ('lodge_inside', 'The Guild Lodge', 'inside, walkable', _lazy('village_interiors', 'scene_lodge')),
    ('cottage_inside', 'The Cottage', 'inside, walkable: the kitchen, the apothecary, the hearth', _lazy('cottage_walk', 'scene_cottage_walk')),
    ('home_grounds', 'The Home grounds', 'walkable: the Nest, the Cottage, the farm, the Grove', _lazy('home_walk', 'scene_home_walk')),
    ('nest_hub', 'The Nest hub', 'the home screen: the nest at the fork to the Cottage and the village', _lazy('hub_blender', 'scene_hub_b')),
    ('forge_stage', 'Bram\'s forge', 'the forging minigame\'s stage', _lazy('forge_stage', 'scene')),
    ('square_day', 'The Square', 'story scene, by day', _story('square_day_dim')),
    ('square_lamplit', 'The Square, lamplit', 'story scene, the lamps lit', _story('square_lamp_lit')),
    ('square_restored', 'The Square, the Waystone restored', 'story scene', _story('square_waystone_restored')),
    ('waystone_dormant', 'The Waystone, dormant', 'story scene', _story('waystone_dormant')),
    ('waystone_restored', 'The Waystone, restored', 'story scene', _story('waystone_restored')),
    ('workshop_story', 'Bram\'s Workshop', 'story portrait scene', _story('workshop')),
    ('glasshouse_story', 'Mira\'s Glasshouse', 'story portrait scene', _story('glasshouse')),
    ('lodge_story', 'The Guild Lodge', 'story portrait scene', _story('lodge')),
    ('home_map_ruined', 'The Home Map, in ruins', 'story scene', _story('home_map_ruined')),
    ('home_map_restored', 'The Home Map, restored', 'story scene', _story('home_map_restored')),
    ('garden', 'The Garden', 'the garden beds close up', _story('garden')),
    ('kitchen', 'The Kitchen', 'the cooking station', _story('kitchen')),
    ('apothecary', 'The Apothecary', 'the brewing station', _story('apothecary')),
    ('mossy_ruins', 'The Mossy Ruins', 'a Lumen Trails encounter place', _story('mossy_ruins')),
    ('mossy_ruins_hollow', 'The Mossy Ruins, Hollow', 'the same ruin tangled in Hollow vines', _story('mossy_ruins_hollow')),
    ('sentinel_gate', 'The Sentinel\'s Gate', 'the great broken gate at dusk', _story('sentinel_gate')),
]


# the walkable maps' cameras (village_walk.VIEWS): the main one first, then close-ups worth a look
ORTHO = {'village_map': ['full', 'plaza', 'falls', 'road', 'all'],
         'old_trail': ['trail', 'trail_mine', 'trail_falls', 'trail_portal', 'trail_thicket', 'trail_cliffs'],
         'workshop_inside': ['workshop'], 'glasshouse_inside': ['glasshouse'], 'lodge_inside': ['lodge'],
         'cottage_inside': ['cottage'], 'home_grounds': ['home', 'home_nook']}


def ortho_camera(view, name):
    """the walking camera (village_walk.render_ortho): orthographic, 35 degrees above the horizon, looking north"""
    import math
    import bpy
    from mathutils import Vector
    import village_blender as VB
    import village_walk as VW
    (cx, cz), width, (w, h) = VW.VIEWS[view]
    d = bpy.data.cameras.new(name)
    d.type = 'ORTHO'
    d.ortho_scale = width * VB.SCALE
    d.sensor_fit = 'HORIZONTAL'
    d.clip_start, d.clip_end = 0.05, 400
    ob = bpy.data.objects.new(name, d)
    bpy.context.scene.collection.objects.link(ob)
    p = math.radians(VW.PITCH)
    look = Vector((0.0, -math.sin(p), -math.cos(p)))
    target = Vector((cx, 0.0, cz))
    ob.location = VB.to_blender(tuple(target - look * 150.0))
    v = (VB.to_blender(tuple(target)) - ob.location).normalized()
    ob.rotation_euler = v.to_track_quat('-Z', 'Y').to_euler()
    ob['resolution'] = (w, h)
    return ob, (w, h)


def build(vs, title, where, key=None):
    """village_blender.render without the render: the scene, its lights, world and camera, saved for Blender"""
    import bpy
    import village_blender as VB
    VB.reset()
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.render.resolution_x, sc.render.resolution_y = vs.w, vs.h
    sc.cycles.samples = vs.samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.02
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces, sc.cycles.diffuse_bounces, sc.cycles.glossy_bounces = 6, 4, 2
    sc.cycles.transparent_max_bounces = 8
    sc.cycles.caustics_reflective = sc.cycles.caustics_refractive = False
    sc.cycles.sample_clamp_indirect = 6.0
    sc.render.film_transparent = vs.transparent
    try:
        sc.view_settings.view_transform = vs.view
        if vs.look and vs.view == 'AgX':
            sc.view_settings.look = vs.look
    except TypeError:
        pass
    sc.view_settings.exposure = vs.exposure
    coll = bpy.data.collections.new(title)
    sc.collection.children.link(coll)
    nf = 0
    for i, item in enumerate(vs.models):
        M, glass = item[0], item[1]
        opts = item[2] if len(item) > 2 else {}
        ob, n = VB.model_mesh(M, f'{vs.name}_{i}', glass, water=tuple(opts.get('water', ())))
        sc.collection.objects.unlink(ob)
        coll.objects.link(ob)
        if opts.get('shadow') is False:
            ob.visible_shadow = False
        nf += n
    lights = bpy.data.collections.new('Lights')
    sc.collection.children.link(lights)
    before = set(bpy.data.objects)
    for L in vs.lights:
        VB.add_light(L)
    for ob in set(bpy.data.objects) - before:
        for c in list(ob.users_collection):
            c.objects.unlink(ob)
        lights.objects.link(ob)
    VB.setup_world(vs.world[0], vs.world[1])
    views = ORTHO.get(key)
    if views:
        cams = [ortho_camera(v, 'cam' if i == 0 else 'cam_' + v) for i, v in enumerate(views)]
        sc.camera = cams[0][0]
        vs.w, vs.h = cams[0][1]
        sc.render.resolution_x, sc.render.resolution_y = vs.w, vs.h
    else:
        VB.setup_camera(vs.cam, vs.w, vs.h)
    txt = bpy.data.texts.new('README')
    txt.write(f'{title}\n{where}\n\n'
              f'The voxel set ({nf} faces, colours in the `col` attribute, glow in `glow`), {len(vs.lights)} lights '
              f'(collection "Lights") and the game\'s camera (`cam`, {vs.w}x{vs.h})'
              + (f', plus close-ups: {", ".join("cam_" + v for v in views[1:])} (set one active, and its resolution '
                 f'from its custom property)' if views and len(views) > 1 else '') + '.\nRender (F12) with Cycles as set to '
              f'see it as the game renders it, before the game\'s grade and ink line.\n1 voxel unit = 10 cm.\n'
              f'Built from tools/art ({vs.name}); regenerate with tools/art/places_blend.py.\n')
    return nf, len(vs.lights)


def main(out, only=None):
    import bpy
    os.makedirs(out, exist_ok=True)
    for key, title, where, make in PLACES:
        if only and key not in only:
            continue
        t = time.time()
        vs = make()
        t1 = time.time()
        nf, nl = build(vs, title, where, key)
        bpy.context.preferences.filepaths.save_version = 0
        path = os.path.join(out, key + '.blend')
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(path), compress=True)
        print('%-20s %8d faces %3d lights  made %.0fs, built %.0fs, %.1f MB' % (
            key, nf, nl, t1 - t, time.time() - t1, os.path.getsize(path) / 1e6), flush=True)


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    if args and args[0] == '--list':
        for k, t, w, _ in PLACES:
            print('%-20s %-36s %s' % (k, t, w))
    else:
        main(args[0], args[1:] or None)

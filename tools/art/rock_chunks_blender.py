"""Rock in Blender (Cycles): a rough stone, remeshed into blocks so it sits with the voxel art, its plates split by
molten cracks (a Voronoi edge network, emissive); a warm key, a hot rim, a transparent film; a turntable of N
frames. Made for the Obsidian's Terra Cataclysm boulder (a_: cracks blazing, b_: cold); with CHUNK=1..6 in the
environment, a small broken chunk instead (the tumbling rock of the Quake's gameplay effects, ult_fx_bake.py):
    python3 rock_chunks_blender.py OUT_DIR [N] [SIZE] [SAMPLES]              (bpy: pip install bpy, Python 3.11)
    for c in 1 2 3 4 5 6; do CHUNK=$c python3 rock_chunks_blender.py chunks_bl 12 160; done
"""
import math, os, sys
import bpy
out = os.path.abspath(sys.argv[1]); N = int(sys.argv[2]) if len(sys.argv) > 2 else 36
SIZE = int(sys.argv[3]) if len(sys.argv) > 3 else 640; SAMPLES = int(sys.argv[4]) if len(sys.argv) > 4 else 24
os.makedirs(out, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

def hexc(h, a=1.0):
    h = h.lstrip('#'); c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c) + (a,)

# the rock
CHUNK = os.environ.get('CHUNK')
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=6 if not CHUNK else 3, radius=1.0)
rock = bpy.context.object
if CHUNK:
    import random
    random.seed(int(CHUNK))
    rock.scale = (random.uniform(0.7, 1.2), random.uniform(0.55, 0.9), random.uniform(0.7, 1.1))
tex = bpy.data.textures.new('lumps', 'CLOUDS'); tex.noise_scale = 0.55; tex.noise_depth = 3
d = rock.modifiers.new('lumps', 'DISPLACE'); d.texture = tex; d.strength = 0.22 if not CHUNK else 0.5; d.mid_level = 0.5
if CHUNK:
    tex.noise_scale = 0.4 + 0.1 * int(CHUNK)
tex2 = bpy.data.textures.new('plates', 'VORONOI'); tex2.noise_scale = 0.45; tex2.distance_metric = 'DISTANCE'
d2 = rock.modifiers.new('plates', 'DISPLACE'); d2.texture = tex2; d2.strength = 0.10; d2.mid_level = 0.6
r = rock.modifiers.new('blocks', 'REMESH'); r.mode = 'BLOCKS'; r.octree_depth = 6 if not CHUNK else 4; r.scale = 0.92
r.use_remove_disconnected = True

# its material: stone, the cracks molten
m = bpy.data.materials.new('rock'); m.use_nodes = True
nt = m.node_tree; N_ = nt.nodes; L = nt.links
for n in list(N_): N_.remove(n)
o = N_.new('ShaderNodeOutputMaterial')
tc = N_.new('ShaderNodeTexCoord')
vor = N_.new('ShaderNodeTexVoronoi'); vor.feature = 'DISTANCE_TO_EDGE'; vor.inputs['Scale'].default_value = 1.55 if not CHUNK else 1.1
L.new(tc.outputs['Object'], vor.inputs['Vector'])
crack = N_.new('ShaderNodeMapRange'); crack.inputs['From Min'].default_value = 0.0; crack.inputs['From Max'].default_value = 0.036
crack.inputs['To Min'].default_value = 1.0; crack.inputs['To Max'].default_value = 0.0; crack.clamp = True
L.new(vor.outputs['Distance'], crack.inputs['Value'])
noise = N_.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value = 5.0
L.new(tc.outputs['Object'], noise.inputs['Vector'])
ramp = N_.new('ShaderNodeValToRGB'); ramp.color_ramp.elements[0].color = hexc('#1E1A1C'); ramp.color_ramp.elements[1].color = hexc('#3E3638')
L.new(noise.outputs['Fac'], ramp.inputs['Fac'])
bsdf = N_.new('ShaderNodeBsdfPrincipled'); bsdf.inputs['Roughness'].default_value = 0.82
L.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])
hot = N_.new('ShaderNodeValToRGB')
hot.color_ramp.elements[0].position = 0.0; hot.color_ramp.elements[0].color = hexc('#D63B20')
hot.color_ramp.elements[1].position = 1.0; hot.color_ramp.elements[1].color = hexc('#FFE59F')
L.new(crack.outputs['Result'], hot.inputs['Fac'])
em = N_.new('ShaderNodeEmission'); L.new(hot.outputs['Color'], em.inputs['Color'])
strength = N_.new('ShaderNodeValue'); strength.name = 'heat'; strength.outputs[0].default_value = 8.0
L.new(strength.outputs[0], em.inputs['Strength'])
cold = N_.new('ShaderNodeBsdfPrincipled'); cold.inputs['Base Color'].default_value = hexc('#140E10'); cold.inputs['Roughness'].default_value = 0.9
mixc = N_.new('ShaderNodeMixShader')       # the crack: hot (emission) or cold (dark) by the heat pass
L.new(cold.outputs['BSDF'], mixc.inputs[1]); L.new(em.outputs['Emission'], mixc.inputs[2])
heatmix = N_.new('ShaderNodeValue'); heatmix.name = 'on'; heatmix.outputs[0].default_value = 1.0
L.new(heatmix.outputs[0], mixc.inputs['Fac'])
mix = N_.new('ShaderNodeMixShader')
L.new(crack.outputs['Result'], mix.inputs['Fac'])
L.new(bsdf.outputs['BSDF'], mix.inputs[1]); L.new(mixc.outputs['Shader'], mix.inputs[2])
L.new(mix.outputs['Shader'], o.inputs['Surface'])
rock.data.materials.append(m)

# light: a warm key from above left in front, a hot rim from behind, a faint ember fill from below
def light(name, kind, energy, col, rot, size=1.0):
    ld = bpy.data.lights.new(name, kind); ld.energy = energy; ld.color = hexc(col)[:3]
    if kind == 'SUN':
        ld.angle = math.radians(size)
    ob = bpy.data.objects.new(name, ld); sc.collection.objects.link(ob)
    ob.rotation_euler = tuple(math.radians(a) for a in rot)
light('key', 'SUN', 3.0, '#FFE6D2', (52, 0, -38), 8)
light('rim', 'SUN', 7.0, '#FF5A2A', (-110, 0, 150), 4)
light('under', 'SUN', 0.35, '#FF7A40', (180, 0, 0), 20)
w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True
w.node_tree.nodes['Background'].inputs['Color'].default_value = hexc('#1A0E0C'); w.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.35

# the camera: orthographic, square, a touch from above
cd = bpy.data.cameras.new('cam'); cd.type = 'ORTHO'; cd.ortho_scale = 2.9
cam = bpy.data.objects.new('cam', cd); sc.collection.objects.link(cam); sc.camera = cam
cam.location = (0.0, -8.0, 1.4); cam.rotation_euler = (math.radians(80), 0.0, 0.0)
sc.render.engine = 'CYCLES'; sc.cycles.samples = SAMPLES; sc.cycles.use_denoising = True
sc.render.film_transparent = True; sc.render.resolution_x = sc.render.resolution_y = SIZE
sc.render.image_settings.file_format = 'PNG'; sc.render.image_settings.color_mode = 'RGBA'
sc.view_settings.view_transform = 'Standard'
for i in range(N):
    a = 2 * math.pi * i / N
    rock.rotation_euler = (math.radians(18), 0.0, a) if not CHUNK else (a * 1.3, a * 0.7, a)   # a chunk tumbles
    for tag, on in ((('a', 1.0), ('b', 0.0)) if not CHUNK else (('c%s' % CHUNK, 1.0),)):
        heatmix.outputs[0].default_value = on
        sc.render.filepath = os.path.join(out, '%s_%02d.png' % (tag, i))
        bpy.ops.render.render(write_still=True)
    print('frame', i, flush=True)
print('done', flush=True)

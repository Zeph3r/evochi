"""Render a cast .blend (cast_blend.py) from its cameras with Cycles, to check what was built.

    python3 cast_preview.py FILE.blend OUT.png [cam_three_quarter|cam_front] [samples] [frame]
"""
import sys

import bpy


def main(path, out, cam='cam_three_quarter', samples=24, frame=1):
    bpy.ops.wm.open_mainfile(filepath=path)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = int(samples)
    sc.cycles.use_denoising = True
    sc.camera = bpy.data.objects[cam]
    sc.frame_set(int(frame))
    sc.render.resolution_percentage = 60
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)


if __name__ == '__main__':
    a = sys.argv[1:]
    main(*a)

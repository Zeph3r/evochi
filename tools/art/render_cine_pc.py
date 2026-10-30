"""Render every packed cinematic scene (cine_pack.py .npz) in a folder on this machine's GPU, in a background
Blender: the raw frame and the depth pass go next to the packs, with a status file per scene. Run from
blender/cine/render_cine.bat on the PC; the grade happens back in the pipeline (cine_blender.py --regrade).

    blender -b --python render_cine_pc.py -- PACK_DIR [--preview] [scene ...]
"""
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import cine_blender as CB   # noqa: E402
import cine_pack            # noqa: E402

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
mode = 'preview' if '--preview' in args else 'full'
args = [a for a in args if a != '--preview']
pack_dir = args[0]
only = set(args[1:])
CB.GPU = True
status_path = os.path.join(pack_dir, 'render_status.json')
status = json.load(open(status_path)) if os.path.exists(status_path) else {}
packs = sorted(f for f in os.listdir(pack_dir) if f.endswith('.npz') and (not only or f[:-4] in only))
for f in packs:
    name = f[:-4]
    if status.get(name, {}).get('state') == 'done' and not only:
        continue
    status[name] = {'state': 'rendering', 'started': time.time()}
    json.dump(status, open(status_path, 'w'), indent=1)
    t = time.time()
    try:
        vs = cine_pack.unpack(os.path.join(pack_dir, f))
        raw = os.path.join(pack_dir, name + '_raw.png')
        CB.META_FRAMES.clear()
        meta = CB.render(vs, raw, mode)
        if getattr(vs, 'cameras', None):
            meta = dict(CB.META_FRAMES)
        json.dump(meta, open(os.path.join(pack_dir, name + '_meta.json'), 'w'), indent=1)
        status[name] = {'state': 'done', 'seconds': round(time.time() - t, 1)}
    except Exception as e:
        import traceback
        status[name] = {'state': 'failed', 'error': str(e), 'trace': traceback.format_exc()[-2000:]}
    json.dump(status, open(status_path, 'w'), indent=1)
    print('STATUS', name, status[name].get('state'), status[name].get('seconds', ''), flush=True)

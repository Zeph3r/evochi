"""Village Tales, Chapter 1 art: villagers, quest items, the Windtrail Mantle overlays, story decor,
and the Village scenes. Writes PNG masters into the asset pack, named like the rest of it.

python3 build_village.py ASSETS_DIR [npcs] [items] [mantle] [decor] [scenes]   (no parts = items, mantle, decor)

  ASSETS/village/npc_<name>_<expression>.png        hero sprites (5 expressions each) + npc.json anchors
  ASSETS/items/item_<id>_icon.png                   quest materials + story rewards (picked up by the web packer)
  ASSETS/characters/item_reward_windtrail_mantle_back_s0N_left3q.png   overlays in each stage's hero frame
  ASSETS/habitats/decor_<id>_<slot>.png             story decor in the meadow's perspective (+ decor json)
  ASSETS/village/<scene>_*.png                      Square (3 states), interiors, Waystone close-up

The scenes and the villagers are lit in Blender, so `scenes` and `npcs` need a Python with the bpy
module: set BPY_PYTHON to it. Render the scenes first: the villagers are lit by the same rooms.
"""
import json
import os
import sys
import time

import numpy as np
from PIL import Image

from voxel import Camera, render, save_rgba
from charrender import render_char
from characters import build
from accessories import wear, WEARABLES, FRAME_WEARABLES
from build_characters import HERO_CAM, SCALE_HERO, fit_for
from build_items import render_model, LIGHT
from village_npcs import NPC_BUILDERS, NPC_EXPRESSIONS
from village_items import VILLAGE_ITEMS

NPC_SCALE = 12.0
NPC_CAM = Camera(yaw=-24, pitch=12)     # villagers turn toward the right of the screen (the player)
NPC_OUTLINE = '#3B2923'                 # the Evochi's ink: a bold line around each villager


def npcs(out, only=None):
    """Villagers are lit in Blender inside their own rooms (village_npc_render.py), then inked with the
    flat renderer's outline. Needs BPY_PYTHON, like the scenes."""
    from village_npc_render import render_all
    d = os.path.join(out, 'village')
    os.makedirs(d, exist_ok=True)
    mpath = os.path.join(d, 'npc.json')
    meta = json.load(open(mpath)) if os.path.exists(mpath) else {}
    meta.update(render_all(d, NPC_BUILDERS, NPC_CAM, NPC_SCALE, NPC_OUTLINE, NPC_EXPRESSIONS, fit_for, only=only,
                           keep=os.environ.get('NPC_WORK')))
    json.dump(meta, open(mpath, 'w'), indent=1)


def items(out):
    d = os.path.join(out, 'items')
    os.makedirs(d, exist_ok=True)
    for k, b in VILLAGE_ITEMS.items():
        M, cam = b()
        save_rgba(render_model(M, cam, 256), os.path.join(d, f'item_{k}_icon.png'))
        print('item', k, flush=True)


def mantle(out):
    """Render the story wearable overlays exactly like build_characters does, in the unchanged frame."""
    d = os.path.join(out, 'characters')
    for stage in (1, 2, 3):
        t = time.time()
        ch = build(stage)
        cam = HERO_CAM[stage]
        fit = fit_for([ch.model] + [wear(ch, k) for k in FRAME_WEARABLES], cam, SCALE_HERO)
        ref = Image.open(os.path.join(d, f'evochi_lizard_s{stage:02d}_amber_default_left3q_f000.png'))
        assert ref.size == (fit.w, fit.h), f'stage {stage} frame changed: {ref.size} vs {(fit.w, fit.h)}'
        body = render_char(ch, 'amber', 'default', cam, fit.w, fit.h, fit=fit)
        for k in [k for k in WEARABLES if k not in FRAME_WEARABLES]:
            M = wear(ch, k)
            comb = render_char(ch, 'amber', 'default', cam, fit.w, fit.h, fit=fit, extra_model=M, cov_prefix='acc_')
            ab = body.rgba[..., 3] / 255.0
            ac = comb.rgba[..., 3] / 255.0
            extra = np.clip((ac - ab) / np.maximum(1 - ab, 1e-3), 0, 1)
            a = np.clip(np.maximum(comb.cov, extra) * 1.05, 0, 1)
            ov = comb.rgba.copy()
            ov[..., 3] = (a * 255).astype(np.uint8)
            save_rgba(ov, os.path.join(d, f'item_{k}_{WEARABLES[k][0]}_s{stage:02d}_left3q.png'))
        print('mantle overlay s%02d %.1fs' % (stage, time.time() - t), flush=True)


DECOR = {   # item -> (slots, world scale), same convention as build_decor.PLACEMENTS
    'reward_firefly_hearth': (['nest'], 0.30),
    'reward_waystone_bloom': (['left', 'right', 'back'], 0.22),
}


def decor(out):
    import scenes as S
    H = os.path.join(out, 'habitats')
    sc = S.scene_meadow(1170, 2532)
    fit = S.make_fit(sc)
    mpath = os.path.join(H, 'habitat_meadow_decor.json')
    meta = json.load(open(mpath))
    for item, (slots, s) in DECOR.items():
        M, _ = VILLAGE_ITEMS[item]()
        for slot in slots:
            p = np.array(sc.slots[slot], float)
            c = sc.cam
            cam2 = Camera(yaw=c.yaw, pitch=c.pitch, target=tuple((np.array(c.target) - p) / s), persp=c.persp / s, fov=c.fov)
            o = render(M, {}, cam2, fit.w, fit.h, fit=fit, light=LIGHT, ss=3, outline_px=3.0, outline_col='#3B2923',
                       inner_thresh=2.0 / s * 0.5, inner_alpha=0.45, inner_px=0.7)
            a = o.rgba[..., 3]
            ys, xs = np.where(a > 0)
            x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
            name = f'decor_{item}_{slot}.png'
            save_rgba(o.rgba[y0:y1, x0:x1], os.path.join(H, name))
            meta[f'{item}@{slot}'] = {'file': name, 'x': int(x0), 'y': int(y0), 'w': int(x1 - x0), 'h': int(y1 - y0)}
            print('decor', name, flush=True)
    json.dump(meta, open(mpath, 'w'), indent=1)


def scenes(out):
    import subprocess
    import tempfile
    py = os.environ.get('BPY_PYTHON')
    if not py:
        raise SystemExit('scenes: set BPY_PYTHON to a Python with the bpy module (pip install bpy)')
    here = os.path.dirname(os.path.abspath(__file__))
    subprocess.run([py, os.path.join(here, 'village_blender.py'), os.path.join(out, 'village'), 'all',
                    '--meta', 'scenes.json', '--raw', tempfile.mkdtemp(prefix='village_raw_')], check=True)


PARTS = {'npcs': npcs, 'items': items, 'mantle': mantle, 'decor': decor, 'scenes': scenes}

if __name__ == '__main__':
    out = sys.argv[1]
    for p in (sys.argv[2:] or [k for k in PARTS if k not in ('scenes', 'npcs')]):
        PARTS[p](out)

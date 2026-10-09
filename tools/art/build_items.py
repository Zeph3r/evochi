"""Render inventory item art, scene decorations and the voxel UI icon family."""
import os
import sys

import numpy as np

from voxel import render, Light, Camera, save_rgba
from items import ITEM_BUILDERS, ICON_BUILDERS

LIGHT = Light(smooth=0.55, ao_amt=0.18, jitter=0.02, smooth_sigma=1.0)


def render_model(M, cam, size, outline=None):
    o = render(M, {}, cam, size, size, light=LIGHT, ss=3, margin=0.07,
               outline_px=outline or max(2.0, size / 70), outline_col='#3B2923',
               inner_thresh=2.0, inner_alpha=0.55, inner_px=0.8)
    return o.rgba


def main(out):
    os.makedirs(os.path.join(out, 'items'), exist_ok=True)
    os.makedirs(os.path.join(out, 'ui_icons'), exist_ok=True)
    for k, b in ITEM_BUILDERS.items():
        M, cam = b()
        save_rgba(render_model(M, cam, 256), os.path.join(out, 'items', f'item_{k}_icon.png'))
        print('item', k, flush=True)
    for k, b in ICON_BUILDERS.items():
        M, cam = b()
        save_rgba(render_model(M, cam, 192, outline=2.6), os.path.join(out, 'ui_icons', f'icon_{k}.png'))
        print('icon', k, flush=True)


if __name__ == '__main__':
    main(sys.argv[1])

"""Every item model the game draws, in one place (like cast.py for the characters): asset_sheets.py draws their
art sheets from this and assets_blend.py their Blender files.

    items           the first items and decorations (items.py): wearables, snacks, the nest pieces, the lantern
    village_items   the Village Tales quest materials and story rewards (village_items.py)
    home_items      crops, seeds, Kitchen meals and Apothecary brews (home_items.py)
    rare_items      charms, tonics, treasures, Glimmer and the Season 1 cosmetics (economy_art.py)
    chests          the four daily chests, closed and open (economy_art.py)
    trail_items     Lumen Trails finds and quest clues (trail_art.py)
    mining          Flint's and Bram's mining gear (mining_gear.py), the ore nodes in their four states and
                    the nuggets they drop (mining_art.py)
"""
from __future__ import annotations

import os
import sys
from dataclasses import dataclass

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


@dataclass
class Asset:
    key: str
    name: str
    model: object         # voxel.Model
    cam: object           # the camera its game icon is drawn from
    pal: dict             # {} when the materials are colours


CATEGORIES = [('items', 'Items and decorations'), ('village_items', 'Village quest items and rewards'),
              ('home_items', 'Crops, meals and brews'), ('rare_items', 'Rare items and cosmetics'),
              ('chests', 'Daily chests'), ('trail_items', 'Lumen Trails finds'), ('mining', 'Mining gear and ore')]


def nice(key):
    tags = []
    k = key
    for pre, tag in (('q_', 'quest'), ('reward_', 'story reward'), ('season_', 'Season 1'), ('seed_', None)):
        if k.startswith(pre):
            k = k[len(pre):]
            if tag:
                tags.append(tag)
            if pre == 'seed_':
                k += ' seeds'
    name = k.replace('_', ' ').title().replace(' Of ', ' of ')
    return name + (' (%s)' % ', '.join(tags) if tags else '')


def _pairs(reg):
    out = []
    for k, fn in reg.items():
        M, cam = fn()
        out.append(Asset(k, nice(k), M, cam, {}))
    return out


def category(cat):
    from voxel import Camera
    if cat == 'items':
        import items
        return _pairs(items.ITEM_BUILDERS)
    if cat == 'village_items':
        import village_items
        return _pairs(village_items.VILLAGE_ITEMS)
    if cat == 'home_items':
        import home_items
        return _pairs(home_items.ITEMS)
    if cat == 'rare_items':
        import economy_art
        return _pairs(economy_art.ITEMS)
    if cat == 'trail_items':
        import trail_art
        return _pairs(trail_art.ITEMS)
    if cat == 'chests':
        import economy_art
        cam = Camera(yaw=-22, pitch=16)
        return [Asset(f'chest_{t}_{s}', f'{t.title()} chest, {s}', economy_art.chest(t, s == 'open'), cam, {})
                for t in economy_art.CHEST_TIERS for s in ('closed', 'open')]
    if cat == 'mining':
        import numpy as np
        import mining_gear as MG
        import mining_art as MA
        from characters import build
        from palettes import ACCESSORY
        pal = {MG.A + k: v for k, v in ACCESSORY.items()}
        out = []
        for item, (slot, fn) in MG.GEAR.items():
            ch = build(3)
            M = ch.model.copy()
            MG.ICON['on'] = True
            try:
                fn(ch, M)
            finally:
                MG.ICON['on'] = False
            keep = np.isin(M.m, [i for i, n in enumerate(M.mats) if n.startswith(MG.A)])
            M.m[~keep] = 0
            yaw = {'helmet': 25, 'tool': 70, 'satchel': -55, 'lantern': 40, 'harness': 35, 'paws': 30}[slot]
            out.append(Asset('gear_' + item, nice(item), M, Camera(yaw=yaw, pitch=40 if slot in ('harness', 'paws') else 22), pal))
        for kind in MA.ORES:
            for st, sname in enumerate(('whole', 'chipped', 'cracked', 'burst')):
                out.append(Asset(f'ore_{kind}_{sname}', f'{kind.title()} node, {sname}', MA.ore_node(kind, st), MA.CAM, {}))
            out.append(Asset(f'nugget_{kind}', f'{kind.title()} nugget', MA.nugget(kind), MA.CAM, {}))
        return out
    raise KeyError(cat)


if __name__ == '__main__':
    tot = 0
    for c, title in CATEGORIES:
        a = category(c)
        tot += len(a)
        print('%-14s %3d  %s' % (c, len(a), ', '.join(x.name for x in a[:6]) + (' ...' if len(a) > 6 else '')))
    print('total', tot)

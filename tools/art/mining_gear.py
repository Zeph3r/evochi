"""Mining gear on the Evochi (MINES_PLAN.md): the pieces of the mining loadout, built onto any stage's body
like the wearables (accessories.py), drawn over the walk sheets (worn only on the Old Trail and in the
mines), and as icons for Flint's shop and Bram's forge.

    python3 mining_gear.py ART_WILDS_DIR [--only=s03] [--icons] [--preview OUT]

  copper / iron  headlamp   a hard hat with a lamp at the front (the helmet slot)
                 pick       laid along the back, its head over the shoulder (the tool slot)
                 satchel    a riveted bag at the left side
                 lantern    a little lantern hung at the right side
                 harness    straps over the back and round the chest, a saddle pad with studs
                 paw guards cuffs round the paws

Writes, per walker (s01, s02, s03), gear_<walker>_<id>.webp (one row: a direction per frame, cut out the
way the wearables are) into ART_WILDS_DIR and adds each to wilds_walk.json's walker 'wear' map (so the app
loads it like a wearable); --icons writes flutter/assets/art/items/gear_<id>.webp and lists them in the
art manifest.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from accessories import ACC_MATS_PREFIX as A, HEAD, core_mask  # noqa: E402
from characters import shell_region, tube  # noqa: E402
from palettes import ACCESSORY  # noqa: E402

TIERS = {
    'copper': {'metal': '#D9844A', 'metal_hi': '#F2A867', 'metal_lo': '#A8582C', 'hat': '#C97A3A', 'hat_hi': '#E39A5A', 'hat_lo': '#9A5A28'},
    'iron': {'metal': '#A9B0B8', 'metal_hi': '#D4DAE0', 'metal_lo': '#727A84', 'hat': '#8E969E', 'hat_hi': '#B8C0C8', 'hat_lo': '#666E78'},
}
for tier, cols in TIERS.items():
    for k, v in cols.items():
        ACCESSORY[f'g_{tier}_{k}'] = v
ACCESSORY.update({'g_strap': '#7A4E2E', 'g_strap_hi': '#9A6538', 'g_strap_lo': '#5E3A24', 'g_band': '#3B3A40', 'g_lens': '#FFF2B8',
                  'g_flame': '#FFD27A', 'g_bag': '#9A6538', 'g_bag_hi': '#B98955', 'g_haft': '#A8703F', 'g_haft_lo': '#7A4E2E'})


ICON = {'on': False}   # drawing an icon: the piece is drawn whole, even where it sits inside the body


def _s(M, mask, name, empty=True, glow=None):
    if empty and not ICON['on']:
        mask = mask & (M.m == 0)
    if glow:
        M.set(mask, A + name, glow=glow)
    else:
        M.set(mask, A + name)


def _k(ch):
    return {1: 0.95, 2: 1.0, 3: 1.0}[ch.stage]


def _side(ch, M):
    """The body's half width at the back (where bags and lanterns hang)."""
    bx, by, bz = ch.anchors['back']
    core = core_mask(M)
    near = core & (np.abs(M.Z - bz) < 2.0) & (M.Y > by * 0.25) & (M.Y < by * 0.8)
    return float(np.abs(M.X[near]).max()) if near.any() else 8.0


def headlamp(tier):
    """A miner's hard hat: a dome with a raised crest ridge and two side ribs, a riveted band with a buckle,
    a rolled brim that runs out to a peak at the front, a chin strap, and a headlamp on a bracket (a deep
    bezel, a ringed reflector, a bright lens) with its battery box at the back."""
    def build(ch, M):
        c = np.array(HEAD[ch.stage]['c'], float)
        k = _k(ch)
        X, Y, Z = M.X, M.Y, M.Z
        crest = np.isin(M.m, [i for i, n in enumerate(M.mats) if n.startswith('crest')])
        M.m[crest & (Y >= c[1] - 3.0 * k) & ((X - c[0]) ** 2 + (Z - c[2]) ** 2 <= (11.0 * k) ** 2)] = 0
        hc = c + np.array([0.0, -1.2 * k, -1.6 * k])
        dx, dz, dy = X - hc[0], Z - hc[2], Y - hc[1]
        dome = (dx ** 2 / (9.4 * k) ** 2 + dz ** 2 / (9.6 * k) ** 2 + dy ** 2 / (6.4 * k) ** 2 <= 1) & (dy >= 0)
        outer = (dx ** 2 / (9.9 * k) ** 2 + dz ** 2 / (10.1 * k) ** 2 + dy ** 2 / (6.9 * k) ** 2 <= 1) & (dy >= 0)
        brim = (dx ** 2 / (10.6 * k) ** 2 + dz ** 2 / (10.6 * k) ** 2 <= 1) & (dy >= -0.3) & (dy < 0.8)
        peak = ((dx ** 2 / (8.4 * k) ** 2 + (dz - 3.6 * k) ** 2 / (10.4 * k) ** 2 <= 1) & (dz > 0) & (dy >= -0.3) & (dy < 0.8))
        lip = (brim | peak) & ~((dx ** 2 / (9.9 * k) ** 2 + dz ** 2 / (9.9 * k) ** 2 <= 1) &
                                ~((dx ** 2 / (7.7 * k) ** 2 + (dz - 3.6 * k) ** 2 / (9.6 * k) ** 2 <= 1) & (dz > 0)))
        rolled = lip & (dy >= 0.8 - 0.01) | (lip & (dy < 0.8))
        crest_rib = outer & ~dome & (np.abs(dx) < 1.1 * k) & (dy > 1.6 * k)             # the ridge front to back
        side_ribs = outer & ~dome & (np.abs(np.abs(dx) - 4.6 * k) < 0.7 * k) & (dy > 2.4 * k) & (dz > -6.0 * k)
        M.m[(dome | brim | peak | crest_rib | side_ribs) & (M.m > 0)] = 0
        t = f'g_{tier}_'
        _s(M, dome, t + 'hat', empty=False)
        _s(M, dome & (dy > 4.2 * k) & (dx < 1.5 * k), t + 'hat_hi', empty=False)           # the sun on its crown
        _s(M, crest_rib | side_ribs, t + 'hat_hi', empty=False)
        _s(M, brim | peak, t + 'hat', empty=False)
        _s(M, lip, t + 'hat_lo', empty=False)                                            # a rolled, darker edge
        band = dome & (dy >= 0.8) & (dy < 2.1 * k)
        _s(M, band, 'g_band', empty=False)
        ang = np.arctan2(dx, dz)
        rivets = band & (np.abs(((ang + np.pi) / (2 * np.pi) * 14) % 1 - 0.5) < 0.12) & (np.abs(dy - 1.45 * k) < 0.45)
        _s(M, rivets, t + 'metal_hi', empty=False)
        buckle = band & (np.abs(dx - 8.6 * k) < 1.2 * k) & (np.abs(dz + 1.5 * k) < 1.3 * k)
        _s(M, buckle, t + 'metal_hi', empty=False)
        # the chin strap: from the band down the sides of the face, under the brim
        for sx in (-1, 1):
            strap = tube(M, [(hc[0] + sx * 8.4 * k, hc[1] + 0.6, hc[2] + 2.4 * k), (hc[0] + sx * 7.6 * k, hc[1] - 4.2 * k, hc[2] + 4.0 * k)], [0.45, 0.4], p=2.0)
            _s(M, strap, 'g_strap')
        # the headlamp on a bracket at the front
        lc = hc + np.array([0.0, 3.0 * k, 8.4 * k])
        bracket = (np.abs(X - lc[0]) < 1.0 * k) & (Y > hc[1] + 0.6) & (Y < lc[1] + 0.4) & (Z > lc[2] - 2.2 * k) & (Z < lc[2] - 0.6)
        _s(M, bracket, t + 'metal_lo', empty=False)
        r2 = (X - lc[0]) ** 2 + (Y - lc[1]) ** 2
        cup = (r2 <= (2.7 * k) ** 2) & (Z >= lc[2] - 1.2) & (Z < lc[2] + 1.8)
        _s(M, cup, t + 'metal', empty=False)
        bezel = (r2 <= (2.7 * k) ** 2) & (r2 > (2.0 * k) ** 2) & (Z >= lc[2] + 1.2) & (Z < lc[2] + 2.2)
        _s(M, bezel, t + 'metal_hi', empty=False)
        lens = (r2 <= (2.0 * k) ** 2) & (Z >= lc[2] + 1.0) & (Z < lc[2] + 1.9)
        _s(M, lens, 'g_lens', empty=False, glow=1.0)
        hot = (r2 <= (0.8 * k) ** 2) & (Z >= lc[2] + 1.4) & (Z < lc[2] + 2.0)
        _s(M, hot, 'white', empty=False, glow=1.0)
        # its battery box, at the back of the band
        bat = (np.abs(dx) < 2.0 * k) & (dy > 0.6) & (dy < 3.0 * k) & (dz < -8.6 * k) & (dz > -10.6 * k)
        _s(M, bat, t + 'metal_lo')
        _s(M, bat & (dy > 2.3 * k), t + 'metal', empty=False)
    return build


def pick(tier):
    def build(ch, M):
        bx, by, bz = ch.anchors['back']
        k = _k(ch)
        top = float(M.Y[core_mask(M) & (np.abs(M.Z - bz) < 2) & (np.abs(M.X) < 2)].max()) if core_mask(M).any() else by
        a = np.array([-2.6 * k, top + 0.6, bz - 6.0 * k])
        b = np.array([2.2 * k, top + 1.8 * k, bz + 4.0 * k])
        haft = tube(M, [tuple(a), tuple(b)], [0.75, 0.75], p=2.0)
        _s(M, haft, 'g_haft')
        _s(M, haft & (M.Y < (a[1] + b[1]) / 2 - 0.4), 'g_haft_lo')
        head = tube(M, [(b[0] - 4.2 * k, b[1] - 1.0, b[2] - 0.6), (b[0], b[1] + 0.8, b[2]), (b[0] + 4.0 * k, b[1] - 1.2, b[2] + 0.6)],
                    [0.6, 1.3, 0.55], p=2.2)
        t = f'g_{tier}_'
        _s(M, head, t + 'metal', empty=False)
        _s(M, head & (M.Y > b[1] + 0.5), t + 'metal_hi', empty=False)
        core = core_mask(M)
        strap = shell_region(M, core, 1) & (np.abs(M.Z - (bz - 2.0 * k)) < 0.6) & (M.Y > top - 4.0 * k)
        _s(M, strap, 'g_strap')
    return build


def satchel(tier):
    def build(ch, M):
        bx, by, bz = ch.anchors['back']
        k = _k(ch)
        xw = _side(ch, M)
        cx, cy, cz = -(xw + 1.5 * k), by * 0.5, bz + 1.0 * k
        bag = (np.abs(M.X - cx) <= 1.5 * k) & (np.abs(M.Y - cy) <= 2.4 * k) & (np.abs(M.Z - cz) <= 3.0 * k)
        bag &= ~((np.abs(M.X - cx) > 1.0 * k) & (np.abs(M.Y - cy) > 1.9 * k))       # rounded edges
        _s(M, bag, 'g_bag')
        _s(M, bag & (M.Y > cy + 0.8 * k), 'g_bag_hi', empty=False)
        flap = bag & (M.Y > cy + 0.4 * k) & (M.X < cx - 0.6 * k)
        t = f'g_{tier}_'
        _s(M, flap, t + 'metal', empty=False)
        rivet = flap & (np.abs(M.Z - cz) < 0.5) & (np.abs(M.Y - (cy + 1.0 * k)) < 0.6)
        _s(M, rivet, t + 'metal_hi', empty=False)
        core = core_mask(M)
        strap = shell_region(M, core, 1) & (np.abs(M.Z - cz) < 0.55) & (M.X < 0) & (M.Y > cy)
        _s(M, strap, 'g_strap')
    return build


def lantern(tier):
    def build(ch, M):
        bx, by, bz = ch.anchors['back']
        k = _k(ch)
        xw = _side(ch, M)
        cx, cy, cz = xw + 1.4 * k, by * 0.48, bz + 4.0 * k
        t = f'g_{tier}_'
        frame = (np.abs(M.X - cx) <= 1.2 * k) & (np.abs(M.Y - cy) <= 1.7 * k) & (np.abs(M.Z - cz) <= 1.2 * k)
        glass = (np.abs(M.X - cx) <= 0.8 * k) & (np.abs(M.Y - cy) <= 1.2 * k) & (np.abs(M.Z - cz) <= 0.8 * k)
        _s(M, frame & ~glass, t + 'metal')
        _s(M, frame & (np.abs(M.Y - cy) > 1.3 * k), t + 'metal_lo', empty=False)
        _s(M, glass, 'g_flame', glow=1.0)
        cap = (np.abs(M.X - cx) <= 0.7 * k) & (M.Y > cy + 1.7 * k) & (M.Y <= cy + 2.4 * k) & (np.abs(M.Z - cz) <= 0.7 * k)
        _s(M, cap, t + 'metal_hi')
        hook = tube(M, [(cx, cy + 2.2 * k, cz), (cx - 1.0 * k, cy + 3.4 * k, cz)], [0.35, 0.35], p=2.0)
        _s(M, hook, t + 'metal_lo')
    return build


def harness(tier):
    def build(ch, M):
        bx, by, bz = ch.anchors['back']
        nx, ny, nz = ch.anchors['neck']
        k = _k(ch)
        core = core_mask(M)
        sh = shell_region(M, core, 1)
        t = f'g_{tier}_'
        for dz in (3.2, -4.2):
            ring = sh & (np.abs(M.Z - (bz + dz * k)) < 0.8) & (M.Y > by * 0.35)
            _s(M, ring, 'g_strap')
            _s(M, ring & (np.abs(M.Z - (bz + dz * k)) < 0.3), 'g_strap_hi', empty=False)
        chest = sh & (np.abs(M.Y - (ny + 1.0 * k)) < 0.8) & (M.Z > nz - 2.5 * k)
        _s(M, chest, 'g_strap')
        pad = shell_region(M, core, 2) & ~sh & (np.abs(M.Z - bz) < 3.4 * k) & (np.abs(M.X) < 3.6 * k) & (M.Y > by - 1.0)
        pad |= sh & (np.abs(M.Z - bz) < 3.4 * k) & (np.abs(M.X) < 3.6 * k) & (M.Y > by - 1.0)
        _s(M, pad, 'g_strap_lo')
        rim = pad & ((np.abs(M.X) > 3.0 * k) | (np.abs(M.Z - bz) > 2.8 * k))
        _s(M, rim, t + 'metal', empty=False)
        studs = pad & ((np.floor((M.X + 20) / (1.6 * k)) % 2 == 0) & (np.floor((M.Z + 40) / (1.6 * k)) % 2 == 0)) & ~rim
        _s(M, studs & (np.abs(M.X) < 2.2 * k) & (np.abs(M.Z - bz) < 2.0 * k), t + 'metal_hi', empty=False)
        for sx in (-1, 1):                      # buckles where the straps meet the pad
            bk = sh & (np.abs(M.X - sx * 4.2 * k) < 0.8) & (np.abs(M.Z - (bz + 3.2 * k)) < 0.8) & (M.Y > by - 2.0)
            _s(M, bk, t + 'metal_hi', empty=False)
    return build


def paw_guards(tier):
    def build(ch, M):
        feet = np.isin(M.m, [i for i, n in enumerate(M.mats) if n.startswith('feet')])
        if not feet.any():
            return
        fy = float(M.Y[feet].max())
        cuff = shell_region(M, feet, 1) & (M.Y > fy * 0.3) & (M.Y < fy * 1.05)      # plates over each paw
        t = f'g_{tier}_'
        _s(M, cuff, t + 'metal')
        _s(M, cuff & (M.Y > fy * 0.74), t + 'metal_hi', empty=False)
        _s(M, cuff & (M.Y < fy * 0.52), t + 'metal_lo', empty=False)
    return build


GEAR = {
    'copper_headlamp': ('helmet', headlamp('copper')),
    'copper_pick': ('tool', pick('copper')),
    'copper_satchel': ('satchel', satchel('copper')),
    'copper_lantern': ('lantern', lantern('copper')),
    'copper_harness': ('harness', harness('copper')),
    'copper_paw_guards': ('paws', paw_guards('copper')),
    'iron_pick': ('tool', pick('iron')),
    'iron_harness': ('harness', harness('iron')),
    'iron_paw_guards': ('paws', paw_guards('iron')),
}


def wear_gear(ch, ids):
    M = ch.model.copy()
    for i in ids:
        GEAR[i][1](ch, M)
    return M


def render_gear(out, wk, only=None):
    """Like walk.render_wear: each piece over the walker's idle body, a direction per frame, only what
    shows in front of the body."""
    import walk as W
    from charrender import render_char
    from voxel import Fit
    built = {g: wk.frames(g) for g in wk.gaits}
    G, w, h, gx, gy = W.layout(wk, built)
    base = built['walk'][0][0]
    items = {}
    for item, (slot, _) in GEAR.items():
        if only and item not in only:
            continue
        Mw = wear_gear(base, [item])
        row = Image.new('RGBA', (w * len(W.DIRS), h), (0, 0, 0, 0))
        for r, d in enumerate(W.DIRS):
            cam = W.cam_for(d)
            light = W.light_for(cam.yaw)
            gpx, gpy, _ = cam.project(np.array([[G[0], 0.0, G[2]]]))
            fit = Fit(wk.scale, gx - gpx[0] * wk.scale, gy - gpy[0] * wk.scale, w, h)
            body = render_char(base, 'amber', 'default', cam, w, h, fit=fit, light=light)
            comb = render_char(base, 'amber', 'default', cam, w, h, fit=fit, light=light, extra_model=Mw, cov_prefix='acc_')
            ab = body.rgba[..., 3] / 255.0
            ac = comb.rgba[..., 3] / 255.0
            extra = np.clip((ac - ab) / np.maximum(1 - ab, 1e-3), 0, 1)
            a = np.clip(np.maximum(comb.cov, extra) * 1.05, 0, 1)
            ov = comb.rgba.copy()
            ov[..., 3] = (a * 255).astype(np.uint8)
            row.paste(Image.fromarray(ov), (r * w, 0))
        fn = f'gear_{wk.key}_{item}.webp'
        row.save(os.path.join(out, fn), quality=88, method=6)
        items[item] = {'file': fn, 'slot': 'gear_' + slot}
        print(wk.key, 'gear', item, flush=True)
    return items


def icons():
    """Each piece alone for the shop and the forge, in the items' 3/4 view (the body-shaped harness and paw
    guards from higher up, so their shape reads)."""
    from build_characters import fit_for
    from build_items import LIGHT
    from characters import build
    from charrender import render_char
    from voxel import Camera, render
    art = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'flutter', 'assets', 'art')
    mp = os.path.join(art, 'manifest.json')
    man = json.load(open(mp))
    pal = {A + k: v for k, v in ACCESSORY.items()}
    for item, (slot, fn) in GEAR.items():
        ch = build(3)
        if True:
            M = ch.model.copy()
            ICON['on'] = True
            try:
                fn(ch, M)
            finally:
                ICON['on'] = False
            keep = np.isin(M.m, [i for i, n in enumerate(M.mats) if n.startswith(A)])
            M.m[~keep] = 0
            yaw = {'helmet': 25, 'tool': 70, 'satchel': -55, 'lantern': 40, 'harness': 35, 'paws': 30}[slot]
            o = render(M, pal, Camera(yaw=yaw, pitch=40 if slot in ('harness', 'paws') else 22), 168, 168, light=LIGHT, ss=3, margin=0.07, outline_px=2.4, outline_col='#3B2923',
                       inner_thresh=2.0, inner_alpha=0.55, inner_px=0.8)
            rgba = o.rgba
        Image.fromarray(rgba, 'RGBA').save(os.path.join(art, 'items', f'gear_{item}.webp'), 'WEBP', quality=92, method=6)
        man['items'][f'gear_{item}'] = f'items/gear_{item}.webp'
        print('icon', item, flush=True)
    json.dump(man, open(mp, 'w'), indent=1)


def preview_helmets(out):
    """The copper and iron-free helmet close up on each stage, front three-quarter."""
    from build_characters import fit_for
    from characters import build
    from charrender import render_char
    from voxel import Camera
    ims = []
    for st in (1, 2, 3):
        ch = build(st)
        M = wear_gear(ch, ['copper_headlamp'])
        for yaw in (20, -60):
            cam = Camera(yaw=yaw, pitch=18)
            fit = fit_for([M], cam, 10.0)
            o = render_char(ch, 'amber', 'happy', cam, fit.w, fit.h, fit=fit, extra_model=M)
            ims.append(Image.fromarray(o.rgba, 'RGBA'))
    W = sum(i.width for i in ims) + 30 * len(ims)
    H = max(i.height for i in ims) + 40
    b = Image.new('RGB', (W, H), (54, 48, 58))
    x = 15
    for im in ims:
        b.paste(im, (x, H - 20 - im.height), im)
        x += im.width + 30
    b.save(os.path.join(out, 'helmet_preview.png'))
    print('helmets', b.size)


def preview(out):
    """The copper set on each stage, and each piece alone, for a look."""
    from build_characters import fit_for
    from characters import build
    from charrender import render_char
    from voxel import Camera
    os.makedirs(out, exist_ok=True)
    full = ['copper_headlamp', 'copper_harness', 'copper_paw_guards', 'copper_satchel', 'copper_lantern', 'copper_pick']
    ims = []
    for st in (1, 2, 3):
        ch = build(st)
        M = wear_gear(ch, full)
        cam = Camera(yaw=35, pitch=20)
        fit = fit_for([M], cam, 9.0)
        o = render_char(ch, 'obsidian', 'happy', cam, fit.w, fit.h, fit=fit, extra_model=M)
        ims.append(Image.fromarray(o.rgba, 'RGBA'))
    W = sum(i.width for i in ims) + 40 * len(ims)
    H = max(i.height for i in ims) + 40
    b = Image.new('RGB', (W, H), (54, 48, 58))
    x = 20
    for im in ims:
        b.paste(im, (x, H - 20 - im.height), im)
        x += im.width + 40
    b.save(os.path.join(out, 'gear_preview.png'))
    print('preview', b.size)


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if '--preview' in sys.argv:
        preview(args[0])
        preview_helmets(args[0])
        sys.exit(0)
    if '--icons' in sys.argv:
        icons()
        sys.exit(0)
    import walk as W
    out = args[0]
    only = next((a.split('=', 1)[1].split(',') for a in sys.argv if a.startswith('--only=')), ['s01', 's02', 's03'])
    pieces = next((a.split('=', 1)[1].split(',') for a in sys.argv if a.startswith('--items=')), None)
    mpath = os.path.join(out, 'wilds_walk.json')
    for key in only:
        items = render_gear(out, W.WALKERS[key](), pieces)
        meta = json.load(open(mpath))
        wear = meta['walkers'][key].setdefault('wear', {})
        wear.update(items)
        json.dump(meta, open(mpath, 'w'), indent=1)

"""The onboarding cinematic, cut together: the shot list (onboarding_cine.json, which the app plays) and a Python
compositor that renders the same cut as a preview video from the plates, so the timing, the camera moves and the
reveals can be checked before the Flutter player exists.

The spine of the cut is one golden footprint: it appears alone in the black, lights Alder's map, reignites one
trail with a second step, cracks the egg, and lights the first path after naming.

    python3 onboarding_cine.py PLATE_DIR OUT.mp4 [--w 1080 --h 1920 --fps 30] [--until SECONDS] [--frames DIR]

PLATE_DIR holds the graded plates (cine_blender.py's OUT_DIR) and cine.json (anchors, trail polylines).

The timeline (SHOTS below, written out as onboarding_cine.json) is what the app reads. A shot is a plate (or
black) seen through a camera, with layers drawn over it and a caption:
  camera    {'from': {'cx', 'cy', 'zoom'}, 'to': {...}, 'ease'}: the plate's point (0-1 of its size) under the
            centre of the screen and how much of the screen's height the plate's height fills (zoom 1 = the
            plate's height fits the screen; the plate is 'cover'-fitted first, so nothing ever shows past it)
  layers    reveal: another plate shown through a growing mask ('trails' grows along the trail polylines, in
            order, 'edges' grows in from the picture's edges with noise, 'trail' is one named trail)
            print: the Lumen footprint sprite, additive, at a plate point, with a pulse
            steps: footprints pressed into a named trail, walking from 'start' to 'end' (0-1 of its length)
                   between 'from' and 'to' seconds; each lands, flares and cools to an 'ember' (the app's
                   FootTrail; the preview video leaves them out)
            birds: a few birds flying home across the sky ('y': [top, bottom] of their band in plate px, 'n',
                   'speed' plate px a second, 'size'); the app's only (the plates themselves live through
                   tools/art/fx_zones/cine.py)
            walkers: tiny silhouettes travelling the trails, leaving a few fading prints behind them
            flicker: a reveal that stutters before it holds
            fade: a plain fade from black / to black
  caption   the line, shown in the lower third with a gentle fade
  sfx       a named sound cue (the app's audio service; the preview video is silent)
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))

# ------------------------------------------------------------------------------------------------ the cut ----
SHOTS = [
    {'id': 'black_print', 'dur': 1.4, 'plate': None, 'bg': '#000000',
     'layers': [{'kind': 'print', 'at': [0.5, 0.6], 'size': 0.16, 'in': 0.45, 'rise': 0.25, 'pulse': 1.0}],
     'sfx': {'t': 0.4, 'name': 'footstep'}},
    {'id': 'map_lit', 'dur': 3.2, 'plate': 'map_faded', 'xfade': 0.6,
     'camera': {'from': {'cx': 0.5, 'cy': 0.56, 'zoom': 1.0}, 'to': {'cx': 0.5, 'cy': 0.5, 'zoom': 1.08}, 'ease': 'inout'},
     'layers': [{'kind': 'reveal', 'plate': 'map_lit', 'how': 'trails', 'from': 0.15, 'to': 2.6, 'glow': True}],
     'caption': {'text': 'Once, every path was lit.', 'in': 0.5, 'out': 3.0},
     'sfx': {'t': 0.15, 'name': 'lumen_rise'}},
    {'id': 'map_walkers', 'dur': 3.0, 'plate': 'map_lit',
     'camera': {'from': {'cx': 0.36, 'cy': 0.55, 'zoom': 1.45}, 'to': {'cx': 0.62, 'cy': 0.42, 'zoom': 1.45}, 'ease': 'inout'},
     'layers': [{'kind': 'walkers', 'n': 7, 'speed': 0.12, 'size': 0.012}],
     'caption': {'text': 'The Evochi watched over them.', 'in': 0.3, 'out': 2.8}},
    {'id': 'map_hollow', 'dur': 4.0, 'plate': 'map_faded',
     'camera': {'from': {'cx': 0.5, 'cy': 0.45, 'zoom': 1.25}, 'to': {'cx': 0.5, 'cy': 0.5, 'zoom': 1.0}, 'ease': 'inout'},
     'layers': [{'kind': 'reveal', 'plate': 'map_lit', 'how': 'trails', 'from': -10.0, 'to': -9.0, 'reverse': True, 'dim_from': 0.0, 'dim_to': 2.2},
                {'kind': 'reveal', 'plate': 'map_hollow', 'how': 'edges', 'from': 0.4, 'to': 3.6}],
     'caption': {'text': 'Time and the Hollow dimmed them.', 'in': 0.6, 'out': 3.8},
     'sfx': {'t': 0.4, 'name': 'hollow_creep'}},
    {'id': 'map_reignite', 'dur': 3.0, 'plate': 'map_hollow',
     'camera': {'from': {'cx': 0.33, 'cy': 0.68, 'zoom': 1.9}, 'to': {'cx': 0.33, 'cy': 0.66, 'zoom': 2.0}, 'ease': 'inout'},
     # footsteps walk the dim grove trail, each print landing and cooling to an ember, and the trail lights
     # up just behind them: the footstep on the sound, the light answering it
     'layers': [{'kind': 'reveal', 'plate': 'map_lit', 'how': 'trail', 'trail': 'grove', 'from': 1.1, 'to': 4.1, 'flicker': True, 'glow': True},
                {'kind': 'steps', 'plate': 'map_lit', 'trail': 'grove', 'from': 0.9, 'to': 2.7, 'start': 0.0, 'end': 0.6,
                 'stride': 0.05, 'size': 0.042, 'squash': 0.8, 'ember': 0.4}],
     'caption': {'text': 'But Lumen still answers to footsteps.', 'in': 1.1, 'out': 3.0},
     'sfx': {'t': 0.9, 'name': 'footstep'}},
    {'id': 'village_push', 'dur': 4.0, 'plate': 'village_dusk', 'xfade': 0.6,
     'camera': {'from': {'cx': 0.5, 'cy': 0.5, 'zoom': 1.0}, 'to': {'cx': 'anchor:glasshouse_window', 'zoom': 2.6}, 'ease': 'in'},
     # birds flying home over the ridge (the app draws them; the plate itself lives through fx_zones/cine.py)
     'layers': [{'kind': 'birds', 'n': 5, 'y': [40, 150], 'speed': 55, 'size': 7}],
     'caption': {'text': 'And something here is still glowing.', 'in': 0.4, 'out': 3.4}},
    {'id': 'glasshouse', 'dur': 2.2, 'plate': 'glasshouse_night', 'xfade': 0.8,
     'camera': {'from': {'cx': 'anchor:glasshouse_window', 'zoom': 1.15}, 'to': {'cx': 'anchor:glasshouse_window', 'zoom': 1.35}, 'ease': 'out'},
     'layers': [{'kind': 'fade', 'to': 'black', 'from': 1.6, 'dur': 0.6}]},
]

FPS = 30


def ease(t, kind):
    t = min(max(t, 0.0), 1.0)
    if kind == 'in':
        return t * t
    if kind == 'out':
        return 1 - (1 - t) ** 2
    if kind == 'inout':
        return t * t * (3 - 2 * t)
    return t


def hexrgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ---------------------------------------------------------------------------------------- the compositor ----
class Cut:
    def __init__(self, plate_dir, W=1080, H=1920, fps=FPS):
        self.dir, self.W, self.H, self.fps = plate_dir, W, H, fps
        self.meta = json.load(open(os.path.join(plate_dir, 'cine.json')))
        self.plates = {}
        self.masks = {}
        try:
            self.font = ImageFont.truetype(self._font_path(), int(H * 0.028))
        except Exception:
            self.font = ImageFont.load_default()

    def _font_path(self):
        for p in ('/home/claude/evochi/web/public/assets/fonts/nunito-latin-700-normal.woff2',
                  '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'):
            if os.path.exists(p) and p.endswith('.ttf'):
                return p
        return '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'

    def plate(self, name):
        if name not in self.plates:
            p = os.path.join(self.dir, name + '.png')
            self.plates[name] = Image.open(p).convert('RGBA')
        return self.plates[name]

    def meta_of(self, name):
        m = self.meta.get(name)
        if m is None:
            raise KeyError('no cine.json entry for ' + name)
        return m

    def to_plate_px(self, name, pt):
        """a point given as [x, y] fractions, 'anchor:<name>' or 'trail:<name>:<t>' -> plate pixels at the plate's
        rendered size"""
        m = self.meta_of(name)
        sc = m.get('scale', 1.0)
        if isinstance(pt, str):
            if pt.startswith('anchor:'):
                a = m['anchors'][pt.split(':')[1]]
                return (a[0] * sc, a[1] * sc)
            if pt.startswith('trail:'):
                _, key, t = pt.split(':')
                pts = np.array(m['lines'][key]) * sc
                t = float(t)
                i = t * (len(pts) - 1)
                a, b = pts[int(math.floor(i))], pts[min(int(math.floor(i)) + 1, len(pts) - 1)]
                f = i - math.floor(i)
                return tuple(a * (1 - f) + b * f)
        im = self.plate(name)
        return (pt[0] * im.width, pt[1] * im.height)

    def cam_at(self, shot, u):
        c = shot['camera']
        f, t = c['from'], c['to']
        k = ease(u, c.get('ease', 'inout'))
        name = shot['plate']

        def centre(spec):
            if isinstance(spec.get('cx'), str):
                return self.to_plate_px(name, spec['cx'])
            return self.to_plate_px(name, [spec['cx'], spec['cy']])
        cf, ct = centre(f), centre(t)
        return (cf[0] * (1 - k) + ct[0] * k, cf[1] * (1 - k) + ct[1] * k, f['zoom'] * (1 - k) + t['zoom'] * k)

    def view(self, name, cx, cy, zoom):
        """the screen-sized view of a plate: cover-fit (the plate's height fills the screen at zoom 1), centred on
        (cx, cy) plate pixels, never showing past the plate"""
        im = self.plate(name)
        W, H = self.W, self.H
        base = max(H / im.height, W / im.width)
        s = base * zoom
        vw, vh = W / s, H / s
        x0 = min(max(cx - vw / 2, 0), im.width - vw)
        y0 = min(max(cy - vh / 2, 0), im.height - vh)
        box = (x0, y0, x0 + vw, y0 + vh)
        return im.transform((W, H), Image.EXTENT, box, Image.BICUBIC), (x0, y0, s)

    # ---- masks
    def trail_mask(self, name, keys, progress, width_px):
        """a mask over the plate lit along the trails in order: progress 0..1 over all keys"""
        im = self.plate(name)
        m = self.meta_of(name)
        sc = m.get('scale', 1.0)
        mask = Image.new('L', im.size, 0)
        d = ImageDraw.Draw(mask)
        n = len(keys)
        for i, key in enumerate(keys):
            pts = np.array(m['lines'][key]) * sc
            p = min(max((progress * n - i), 0.0), 1.0)
            if p <= 0:
                continue
            k = p * (len(pts) - 1)
            whole = pts[:int(math.floor(k)) + 1]
            if int(math.floor(k)) + 1 < len(pts):
                f = k - math.floor(k)
                tip = pts[int(math.floor(k))] * (1 - f) + pts[int(math.floor(k)) + 1] * f
                whole = np.vstack([whole, tip])
            if len(whole) >= 2:
                d.line([tuple(q) for q in whole], fill=255, width=int(width_px), joint='curve')
            d.ellipse([whole[-1][0] - width_px / 2, whole[-1][1] - width_px / 2, whole[-1][0] + width_px / 2, whole[-1][1] + width_px / 2], fill=255)
        return mask.filter(ImageFilter.GaussianBlur(width_px * 0.35))

    def edge_mask(self, name, progress, seed=3):
        im = self.plate(name)
        key = (name, 'edges')
        if key not in self.masks:
            w, h = im.width // 8, im.height // 8
            rng = np.random.default_rng(seed)
            yy, xx = np.mgrid[0:h, 0:w]
            d = np.minimum(np.minimum(xx, w - 1 - xx) / w, np.minimum(yy, h - 1 - yy) / h) * 2  # 0 at the edge, 1 mid
            far = 1 - yy / h                                                                        # the top edge first
            noise = np.zeros((h, w))
            for o in range(3):
                f = 2 ** o
                ph = rng.uniform(0, 100, 4)
                noise += (0.5 / f) * (0.5 + 0.25 * (np.sin(xx * 0.08 * f + ph[0]) * np.cos(yy * 0.07 * f + ph[1]) + np.sin((xx + yy) * 0.05 * f + ph[2])))
            field = 0.55 * d + 0.25 * (1 - far) * 0.6 + 0.45 * noise   # low = reached first
            self.masks[key] = (field - field.min()) / (field.max() - field.min() + 1e-6)
        field = self.masks[key]
        thr = progress * 1.15
        a = np.clip((thr - field) / 0.12, 0, 1)
        mask = Image.fromarray((a * 255).astype(np.uint8)).resize(im.size, Image.BILINEAR)
        return mask.filter(ImageFilter.GaussianBlur(im.width * 0.004))

    # ---- sprites
    def print_sprite(self, size_px, strength=1.0):
        key = ('print', size_px, round(strength, 2))
        if key not in self.masks:
            p = os.path.join(self.dir, 'lumen_print.png')
            im = Image.open(p).convert('RGB') if os.path.exists(p) else None
            if im is None:
                im = Image.new('RGB', (64, 64), (255, 200, 90))
            im = im.resize((size_px, size_px), Image.LANCZOS)
            a = np.asarray(im).astype(np.float32) * strength
            self.masks[key] = np.clip(a, 0, 255)
        return self.masks[key]

    def add_sprite(self, frame_arr, spr, cx, cy, heading=0.0):
        h, w = spr.shape[:2]
        if heading:
            spr = np.asarray(Image.fromarray(spr.astype(np.uint8)).rotate(-heading, resample=Image.BICUBIC)).astype(np.float32)
        x0, y0 = int(cx - w / 2), int(cy - h / 2)
        X0, Y0 = max(x0, 0), max(y0, 0)
        X1, Y1 = min(x0 + w, self.W), min(y0 + h, self.H)
        if X1 <= X0 or Y1 <= Y0:
            return
        frame_arr[Y0:Y1, X0:X1] = np.clip(frame_arr[Y0:Y1, X0:X1] + spr[Y0 - y0:Y1 - y0, X0 - x0:X1 - x0], 0, 255)

    # ---- the frame
    def frame(self, shot, t_shot, prev=None):
        W, H = self.W, self.H
        if shot['plate'] is None:
            base = Image.new('RGBA', (W, H), hexrgb(shot.get('bg', '#000000')) + (255,))
            geo = None
        else:
            u = t_shot / shot['dur']
            cx, cy, zoom = self.cam_at(shot, u)
            base, geo = self.view(shot['plate'], cx, cy, zoom)
        arr = np.asarray(base.convert('RGB')).astype(np.float32)
        for L in shot.get('layers', []):
            kind = L['kind']
            if kind == 'reveal' and geo is not None:
                p = (t_shot - L['from']) / max(1e-6, (L['to'] - L['from']))
                if L.get('reverse'):
                    p = 1.0
                p = min(max(p, 0.0), 1.0)
                if L.get('flicker') and 0 < p < 1:
                    p = p * (0.55 + 0.45 * (0.5 + 0.5 * math.sin(t_shot * 47.0) * math.sin(t_shot * 13.0) > 0.25))
                if p <= 0 and not L.get('dim_to'):
                    continue
                over, _ = self.view(L['plate'], cx, cy, zoom)
                over_arr = np.asarray(over.convert('RGB')).astype(np.float32)
                name = shot['plate']
                x0, y0, s = geo
                if L['how'] == 'trails':
                    keys = list(self.meta_of(L['plate'])['lines'].keys())
                    m = self.trail_mask(L['plate'], keys, p, max(6, int(26 * self.meta_of(L['plate']).get('scale', 1.0))))
                elif L['how'] == 'trail':
                    m = self.trail_mask(L['plate'], [L['trail']], p, max(6, int(26 * self.meta_of(L['plate']).get('scale', 1.0))))
                else:
                    m = self.edge_mask(L['plate'], p)
                vw, vh = W / s, H / s
                mv = m.transform((W, H), Image.EXTENT, (x0, y0, x0 + vw, y0 + vh), Image.BILINEAR)
                a = np.asarray(mv).astype(np.float32)[..., None] / 255.0
                if L.get('dim_to'):
                    # the lit plate fades back to the faded one between dim_from and dim_to
                    k = 1.0 - min(max((t_shot - L['dim_from']) / (L['dim_to'] - L['dim_from']), 0.0), 1.0)
                    a = a * k
                arr = arr * (1 - a) + over_arr * a
                if L.get('glow') and 0 < p <= 1:
                    tip = np.asarray(Image.fromarray((a[..., 0] * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(W * 0.01))).astype(np.float32)[..., None] / 255.0
                    arr = np.clip(arr + tip * np.array([70, 48, 10], np.float32) * 0.6, 0, 255)
            elif kind == 'print':
                t0 = L['in']
                if t_shot < t0:
                    continue
                size = int(L['size'] * H)
                pulse = 1.0 + 0.25 * math.sin((t_shot - t0) * 2 * math.pi / max(0.2, L.get('pulse', 1.0)))
                rise = min(1.0, (t_shot - t0) / max(1e-3, L.get('rise', 0.2)))
                strength = rise * (0.85 + 0.15 * pulse)
                spr = self.print_sprite(size, strength)
                if geo is None:
                    px, py = L['at'][0] * W, L['at'][1] * H
                else:
                    pp = self.to_plate_px(shot['plate'], L['at'])
                    x0, y0, s = geo
                    px, py = (pp[0] - x0) * s, (pp[1] - y0) * s
                self.add_sprite(arr, spr, px, py)
            elif kind == 'walkers' and geo is not None:
                m = self.meta_of(shot['plate'])
                sc = m.get('scale', 1.0)
                x0, y0, s = geo
                keys = list(m['lines'].keys())
                for i in range(L['n']):
                    key = keys[i % len(keys)]
                    pts = np.array(m['lines'][key]) * sc
                    ph = (t_shot * L['speed'] + i * 0.37) % 1.0
                    k = ph * (len(pts) - 1)
                    a, b = pts[int(k)], pts[min(int(k) + 1, len(pts) - 1)]
                    f = k - int(k)
                    q = a * (1 - f) + b * f
                    px, py = (q[0] - x0) * s, (q[1] - y0) * s
                    r = L['size'] * H * (1 + 0.1 * math.sin(t_shot * 9 + i))
                    sp = Image.new('RGB', (int(r * 4), int(r * 4)), (0, 0, 0))
                    d = ImageDraw.Draw(sp)
                    d.ellipse([r * 1.2, r * 1.1, r * 2.8, r * 2.9], fill=(70, 50, 16))
                    d.ellipse([r * 1.6, r * 0.7, r * 2.4, r * 1.7], fill=(70, 50, 16))
                    spr = np.asarray(sp).astype(np.float32) * 0.9
                    self.add_sprite(arr, spr, px, py - r * 0.8)
            elif kind == 'fade':
                k = min(max((t_shot - L['from']) / L['dur'], 0.0), 1.0)
                col = np.array(hexrgb('#000000' if L['to'] == 'black' else L['to']), np.float32)
                arr = arr * (1 - k) + col * k
        if shot.get('xfade') and prev is not None and t_shot < shot['xfade']:
            k = ease(t_shot / shot['xfade'], 'inout')
            arr = prev.astype(np.float32) * (1 - k) + arr * k
        out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
        cap = shot.get('caption')
        if cap and cap['in'] <= t_shot <= cap['out']:
            a = min(1.0, (t_shot - cap['in']) / 0.4, (cap['out'] - t_shot) / 0.4)
            self.caption(out, cap['text'], a)
        return out

    def caption(self, im, text, alpha):
        W, H = self.W, self.H
        layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        bbox = d.textbbox((0, 0), text, font=self.font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        x, y = (W - tw) / 2, H * 0.80
        d.rounded_rectangle([x - 28, y - 18, x + tw + 28, y + th + 22], radius=18, fill=(20, 14, 10, int(150 * alpha)))
        d.text((x, y), text, font=self.font, fill=(255, 240, 210, int(255 * alpha)))
        im.paste(Image.alpha_composite(im.convert('RGBA'), layer).convert('RGB'))

    def render(self, out_path, until=None, frames_dir=None):
        import imageio.v2 as imageio
        total = sum(s['dur'] for s in SHOTS)
        if until:
            total = min(total, until)
        writer = imageio.get_writer(out_path, fps=self.fps, codec='libx264', quality=8, pixelformat='yuv420p', macro_block_size=1)
        t, prev_frame, n = 0.0, None, 0
        for shot in SHOTS:
            last = None
            nf = int(round(shot['dur'] * self.fps))
            for i in range(nf):
                if until and t > until:
                    break
                ts = i / self.fps
                im = self.frame(shot, ts, prev=prev_frame if shot.get('xfade') else None)
                writer.append_data(np.asarray(im))
                if frames_dir and i % max(1, nf // 4) == 0:
                    im.save(os.path.join(frames_dir, '%s_%02d.jpg' % (shot['id'], i)), quality=85)
                last = np.asarray(im)
                t += 1 / self.fps
                n += 1
            prev_frame = last
            print(shot['id'], 'done', flush=True)
        writer.close()
        print('wrote', out_path, n, 'frames', round(n / self.fps, 1), 's')


def write_timeline(path):
    json.dump({'fps': FPS, 'shots': SHOTS}, open(path, 'w'), indent=1)


if __name__ == '__main__':
    args = sys.argv[1:]

    def opt(name, default):
        if name in args:
            i = args.index(name)
            v = args[i + 1]
            del args[i:i + 2]
            return v
        return default
    W, H, fps = int(opt('--w', 1080)), int(opt('--h', 1920)), int(opt('--fps', 30))
    until = opt('--until', None)
    frames = opt('--frames', None)
    plate_dir, out = args[0], args[1]
    if frames:
        os.makedirs(frames, exist_ok=True)
    write_timeline(os.path.join(plate_dir, 'onboarding_cine.json'))
    Cut(plate_dir, W, H, fps).render(out, float(until) if until else None, frames)

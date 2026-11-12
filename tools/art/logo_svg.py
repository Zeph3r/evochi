"""The EVOCHI logo as layered SVG, from the logo production sheet (11 Nov 2026): pixel letterforms on the
wordmark font (wordmark.py's FONT, so it matches the screen titles), snapped to a unit grid, with the letter
faces, outline, extrusion, sprout accents, gold crystal crown and sparkles each in their own <g id=...> so the
app (or a motion piece) can bob, sparkle or pop the layers on their own.

    python3 logo_svg.py OUT_DIR [--unit=16] [--png]

writes evochi_logo.svg (full), evochi_wordmark.svg (letters only), evochi_icon.svg (the crown over an E, square),
evochi_logo_mono.svg (two-tone, one hue) and evochi_logo_small.svg (header size: no sprouts or sparkles, a
shallow extrusion), and with --png a 2x raster of each (rsvg-convert) plus a context sheet.
"""
import os
import subprocess
import sys

from wordmark import FONT

PAL = dict(cream='#FFF7E6', espresso='#4A2E1E', cocoa='#9C6A43', cocoa_dk='#7D5234', sprout='#8FD36B',
           sprout_dk='#5E9A45', gold='#F7C84E', gold_hi='#FFE48A', gold_dk='#D9A33A', glow='#FFF1BA')


# ---- pixel geometry: sets of unit cells (x, y; y down) traced into SVG paths -------------------------------
def word_cells(word, gap=1):
    cells, x, starts = set(), 0, []
    for ch in word:
        g = FONT[ch]
        starts.append((x, len(g[0])))
        for r, row in enumerate(g):
            for c, v in enumerate(row):
                if v == '#':
                    cells.add((x + c, r))
        x += len(g[0]) + gap
    return cells, x - gap, starts


def dilate(cells, eight=True):
    out = set(cells)
    for x, y in cells:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if eight or dx == 0 or dy == 0:
                    out.add((x + dx, y + dy))
    return out


def shift(cells, dx, dy):
    return {(x + dx, y + dy) for x, y in cells}


def sweep(cells, depth):
    out = set()
    for d in range(depth + 1):
        out |= shift(cells, 0, d)
    return out


def trace(cells):
    """the boundary loops of a cell set, as lists of (x, y) corners (collinear runs merged)"""
    edges = {}
    for x, y in cells:
        for (nx, ny), a, b in (((x, y - 1), (x, y), (x + 1, y)), ((x + 1, y), (x + 1, y), (x + 1, y + 1)),
                               ((x, y + 1), (x + 1, y + 1), (x, y + 1)), ((x - 1, y), (x, y + 1), (x, y))):
            if (nx, ny) not in cells:
                edges.setdefault(a, []).append(b)
    loops = []
    while edges:
        a = next(iter(edges))
        loop, prev = [a], None
        cur = a
        while True:
            outs = edges[cur]
            if len(outs) == 1 or prev is None:
                nxt = outs.pop()
            else:
                # at a pinch corner, keep turning the same way (right turn first) so loops never cross
                dx, dy = cur[0] - prev[0], cur[1] - prev[1]
                right = (cur[0] - dy, cur[1] + dx)
                nxt = right if right in outs else outs[0]
                outs.remove(nxt)
            if not outs:
                del edges[cur]
            prev, cur = cur, nxt
            if cur == a:
                break
            loop.append(cur)
        # merge collinear corners
        m = []
        n = len(loop)
        for i in range(n):
            p0, p1, p2 = loop[i - 1], loop[i], loop[(i + 1) % n]
            if (p1[0] - p0[0]) * (p2[1] - p1[1]) != (p1[1] - p0[1]) * (p2[0] - p1[0]):
                m.append(p1)
        loops.append(m)
    return loops


def path_d(cells, unit, ox=0.0, oy=0.0, scale=1.0):
    d = []
    for loop in trace(cells):
        pts = [((x * scale + ox) * unit, (y * scale + oy) * unit) for x, y in loop]
        d.append('M' + ' L'.join(f'{x:g} {y:g}' for x, y in pts) + ' Z')
    return ' '.join(d)


def sprite(rows):
    return {(c, r) for r, row in enumerate(rows) for c, v in enumerate(row) if v == '#'}


# ---- the accents (on a half-unit grid, so their outlines stay lighter than the letters') ---------------------
SPROUT = sprite(['##.....##',
                 '###...###',
                 '.###.###.',
                 '..#####..',
                 '...###...',
                 '....#....',
                 '....#....',
                 '....#....'])
CROWN = {  # three crystals: a tall centre and two short sides at its base; the lit facet on the left of each
    'c': sprite(['...##...', '...##...', '..####..', '..####..', '.######.', '.######.', '########', '########', '########', '.######.']),
    'l': sprite(['.##.', '.##.', '####', '####', '####', '####']),
    'r': sprite(['.##.', '.##.', '####', '####', '####', '####']),
}
SPARK = sprite(['..#..', '..#..', '#####', '..#..', '..#..'])
SPARK_S = sprite(['.#.', '###', '.#.'])


def facet(cells):
    """the lit (upper-left) half of a crystal sprite: cells left of its centre column, above its waist"""
    xs = [x for x, _ in cells]
    ys = [y for _, y in cells]
    mx = (min(xs) + max(xs)) / 2
    my = min(ys) + (max(ys) - min(ys)) * 0.75
    return {(x, y) for x, y in cells if x < mx and y < my}


# ---- the drawing ---------------------------------------------------------------------------------------------
def logo_svg(word='EVOCHI', unit=16, layers=('extrusion', 'outline', 'faces', 'sprouts', 'crown', 'sparkles'),
             depth=2, sprouts_on=(0, 4), crown_on=(2, 3), mono=None, pad=1.0):
    cells, width, starts = word_cells(word)
    ring = dilate(cells)
    ext = sweep(ring, depth)
    ext_ring = dilate(ext)
    top = 6.0 if 'crown' in layers else (4.0 if 'sprouts' in layers else 0.0)   # room above the letters for the accents
    ox, oy = 1 + pad, 1 + top + pad
    W, H = (width + 2 + 2 * pad) * unit, (7 + 2 + depth + top + 2 * pad) * unit
    if 'sparkles' in layers:
        ox += 3.0
        W += 6.0 * unit
    P = dict(PAL)
    if mono:
        P = {k: mono for k in P}
        P['cream'] = '#FFFFFF'
        P['glow'] = mono
        P['gold_hi'] = '#FFFFFF'
        P['sprout_dk'] = P['gold_dk'] = P['cocoa_dk'] = mono
    g = []

    def path(cells, fill, unit_scale=1.0, dx=0.0, dy=0.0, extra=''):
        return f'<path d="{path_d(cells, unit, ox + dx, oy + dy, unit_scale)}" fill="{fill}" fill-rule="evenodd"{extra}/>'

    if 'extrusion' in layers:
        g.append('<g id="extrusion">' + path(ext_ring, P['espresso']) + path(ext, P['cocoa'])
                 + path(shift(ring, 0, depth) - shift(ring, 0, depth - 1) if depth else set(), P['cocoa_dk']) + '</g>')
    if 'outline' in layers:
        g.append('<g id="outline">' + path(ring, P['espresso']) + '</g>')
    if 'faces' in layers:
        g.append('<g id="faces">' + path(cells, P['cream']) + '</g>')
    if 'sprouts' in layers:
        s = []
        for li in sprouts_on:
            x0, w = starts[li]
            cx = x0 + w / 2 - 4.5 * 0.5
            cy = -1.0 - 8 * 0.5
            s.append(path(dilate(SPROUT, eight=False), P['espresso'], 0.5, cx, cy))
            s.append(path(SPROUT, P['sprout'], 0.5, cx, cy))
            s.append(path({c for c in SPROUT if c[1] >= 4}, P['sprout_dk'], 0.5, cx, cy))
        g.append('<g id="sprouts">' + ''.join(s) + '</g>')
    if 'crown' in layers:
        xa, wa = starts[crown_on[0]]
        xb, wb = starts[crown_on[1]]
        cx = (xa + xb + wb) / 2 - 4 * 0.5   # centred on the letters it sits over (the centre crystal is 8 half-units wide)
        cy = -1.0 - 10 * 0.5
        parts = [(CROWN['l'], -3.0, 4.0), (CROWN['r'], 7.0, 4.0), (CROWN['c'], 0.0, 0.0)]
        s = [path(dilate(c, eight=False), P['espresso'], 0.5, cx + dx * 0.5, cy + dy * 0.5) for c, dx, dy in parts]
        for c, dx, dy in parts:
            s.append(path(c, P['gold'], 0.5, cx + dx * 0.5, cy + dy * 0.5))
            s.append(path(facet(c), P['gold_hi'], 0.5, cx + dx * 0.5, cy + dy * 0.5))
            s.append(path({p for p in c if p not in facet(c) and p[0] > max(q[0] for q in c) - 2}, P['gold_dk'], 0.5, cx + dx * 0.5, cy + dy * 0.5))
        g.append('<g id="crown">' + ''.join(s) + '</g>')
    if 'sparkles' in layers:
        s = []
        for sp, x, y in ((SPARK, -3.5, -3.5), (SPARK_S, -3.0, 3.0), (SPARK, width + 1.5, -3.0), (SPARK_S, width + 1.8, 4.0),
                         (SPARK_S, width / 2 - 7.0, -6.5), (SPARK_S, width / 2 + 6.0, -6.0)):
            s.append(path(sp, P['glow'], 0.5, x, y))
        g.append('<g id="sparkles">' + ''.join(s) + '</g>')
    body = '\n  '.join(g)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W:g} {H:g}" width="{W:g}" height="{H:g}" '
            f'shape-rendering="crispEdges">\n  <title>{word} logo</title>\n  {body}\n</svg>\n'), (W, H)


def icon_svg(unit=16):
    """the app icon mark: the crystal crown over an E, on a square"""
    svg, (w, h) = logo_svg('E', unit, layers=('extrusion', 'outline', 'faces', 'crown'), depth=2, crown_on=(0, 0), pad=1.5)
    S = max(w, h)
    # centre it on a square canvas
    return svg.replace(f'viewBox="0 0 {w:g} {h:g}" width="{w:g}" height="{h:g}"',
                       f'viewBox="{-(S - w) / 2:g} {-(S - h) / 2:g} {S:g} {S:g}" width="{S:g}" height="{S:g}"'), S


def main(out, unit=16, png=False):
    os.makedirs(out, exist_ok=True)
    files = {}
    full, _ = logo_svg(unit=unit)
    files['evochi_logo.svg'] = full
    files['evochi_wordmark.svg'] = logo_svg(unit=unit, layers=('extrusion', 'outline', 'faces'))[0]
    files['evochi_logo_small.svg'] = logo_svg(unit=unit, layers=('extrusion', 'outline', 'faces', 'crown'), depth=1)[0]
    files['evochi_logo_mono.svg'] = logo_svg(unit=unit, mono=PAL['espresso'])[0]
    files['evochi_icon.svg'] = icon_svg(unit)[0]
    for name, svg in files.items():
        with open(os.path.join(out, name), 'w') as f:
            f.write(svg)
        print(name, len(svg), 'bytes', flush=True)
    if png:
        for name in files:
            p = os.path.join(out, name)
            subprocess.run(['rsvg-convert', '-z', '2', '-o', p[:-4] + '.png', p], check=True)
        context_sheet(out)


def context_sheet(out):
    """the logo over night sky and over grass, and the small and mono variants, on one sheet"""
    from PIL import Image, ImageDraw
    logo = Image.open(os.path.join(out, 'evochi_logo.png')).convert('RGBA')
    small = Image.open(os.path.join(out, 'evochi_logo_small.png')).convert('RGBA')
    mono = Image.open(os.path.join(out, 'evochi_logo_mono.png')).convert('RGBA')
    icon = Image.open(os.path.join(out, 'evochi_icon.png')).convert('RGBA')
    W = logo.width + 80
    sheet = Image.new('RGBA', (W * 2, logo.height + 60 + 260), (250, 244, 232, 255))
    d = ImageDraw.Draw(sheet)
    # night
    d.rectangle((20, 20, 20 + logo.width + 40, 20 + logo.height + 40), fill=(38, 30, 78, 255))
    sheet.alpha_composite(logo, (40, 40))
    # grass
    d.rectangle((W + 20, 20, W + 20 + logo.width + 40, 20 + logo.height + 40), fill=(96, 150, 70, 255))
    sheet.alpha_composite(logo, (W + 40, 40))
    y = logo.height + 90
    hs = 120
    sm = small.resize((int(small.width * hs / small.height), hs), Image.LANCZOS)
    sheet.alpha_composite(sm, (40, y))
    mo = mono.resize((int(mono.width * hs / mono.height), hs), Image.LANCZOS)
    sheet.alpha_composite(mo, (40 + sm.width + 40, y))
    ic = icon.resize((200, 200), Image.LANCZOS)
    sheet.alpha_composite(ic, (sheet.width - 240, y - 20))
    d.text((40, y + hs + 12), 'small (header)', fill=(60, 40, 30, 255))
    d.text((40 + sm.width + 40, y + hs + 12), 'mono', fill=(60, 40, 30, 255))
    d.text((sheet.width - 240, y + 190), 'icon', fill=(60, 40, 30, 255))
    sheet.save(os.path.join(out, 'logo_context.png'))
    print('logo_context.png', sheet.size, flush=True)


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = dict(a[2:].split('=', 1) if '=' in a else (a[2:], '1') for a in sys.argv[1:] if a.startswith('--'))
    main(args[0] if args else 'logo_out', int(opts.get('unit', 16)), png='png' in opts)

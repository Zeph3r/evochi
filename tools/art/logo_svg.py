"""The EVOCHI logo as layered SVG, translated from the approved logo concept sheet (11 Nov 2026).

Six chunky pixel letters, each built on its own from unit cells: a cream face with a pixel-stepped bevel
(highlights along the lit top and left edges, shade along the bottom), its own espresso outline, and a cocoa
extrusion that follows the letter's contour down (so the word's silhouette steps letter by letter). Above the
O-C join an amber crystal cluster (a tall centre crystal and two leaning side crystals, each faceted light /
mid / dark); sprouts whose stems grow out of the tops of the E and the H; sparkles around. Every part is in a
named group, the background is transparent, the geometry snaps to a unit grid (accents to a half unit):

    letter-faces  letter-highlights  letter-outlines  letter-extrusion  letter-shadows
    amber-crystal  green-sprouts  decorative-sparkles

    python3 logo_svg.py OUT_DIR [--unit=16] [--png]

writes evochi_logo.svg (primary), evochi_logo_compact.svg (header: no sprouts or sparkles, a shallower
extrusion), evochi_logo_mono.svg (one colour, the letterforms and the marks as solid shapes) and
evochi_icon.svg (the crystal cluster with its sprouts, square). With --png: rasters at the sizes the game
shows them, a sheet of the construction layers, and a context sheet (backgrounds only in the previews).
"""
import os
import subprocess
import sys

PAL = dict(cream='#FFF7E6', cream_hi='#FFFDF6', cream_lo='#F0DFC3', espresso='#4A2E1E', cocoa='#9C6A43',
           cocoa_dk='#7D5234', sprout='#8FD36B', sprout_lt='#AEE388', sprout_dk='#5E9A45',
           amber_hi='#FFF1BA', amber_lt='#FFE48A', amber='#F7C84E', amber_dk='#D9A33A', amber_deep='#B8812A',
           glow='#FFF1BA')

# the letterforms: 9 tall, 2-unit strokes, chamfered where the concept rounds them (the I a little wider)
FONT = {
    'E': ['#######', '#######', '##.....', '##.....', '#####..', '#####..', '##.....', '#######', '#######'],
    'V': ['##....##', '##....##', '##....##', '##....##', '.##..##.', '.##..##.', '..####..', '..####..', '...##...'],
    'O': ['.######.', '########', '##....##', '##....##', '##....##', '##....##', '##....##', '########', '.######.'],
    'C': ['.#######', '########', '##......', '##......', '##......', '##......', '##......', '########', '.#######'],
    'H': ['##....##', '##....##', '##....##', '##....##', '########', '########', '##....##', '##....##', '##....##'],
    'I': ['###', '###', '###', '###', '###', '###', '###', '###', '###'],
}
GAP = 2        # units between letter faces: each letter's own outline, the outlines just meeting
DEPTH = 2      # the extrusion, in units
LETTER_H = 9
ACCENT = 1.0   # the crystal, sprouts and sparkles, relative to 9-unit letters


def set_font(font, letter_h, gap, depth):
    """letterforms from elsewhere (logo_font.py: a pixel font's outlines snapped to a grid)"""
    global FONT, LETTER_H, GAP, DEPTH, ACCENT
    FONT, LETTER_H, GAP, DEPTH = font, letter_h, gap, depth
    ACCENT = letter_h / 9.0


# ---- pixel geometry: sets of unit cells (x, y; y down) traced into SVG paths -------------------------------
def sprite(rows, on='#'):
    return {(c, r) for r, row in enumerate(rows) for c, v in enumerate(row) if v in on}


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
        loop, prev, cur = [a], None, a
        while True:
            outs = edges[cur]
            if len(outs) == 1 or prev is None:
                nxt = outs.pop()
            else:
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


# ---- the letters ---------------------------------------------------------------------------------------------
def letters(word):
    """each letter's cells in word space, and the word's width"""
    out, x = [], 0
    for ch in word:
        g = FONT[ch]
        out.append((ch, {(x + c, r) for r, row in enumerate(g) for c, v in enumerate(row) if v == '#'}, x, len(g[0])))
        x += len(g[0]) + GAP
    return out, x - GAP


def bevel(F):
    """the lit edges (no cell above, or none to the left) and the shaded ones (the bottom row of the letter's
    lowest strokes), on the face"""
    hi = {(x, y) for x, y in F if (x, y - 1) not in F}
    lo = {(x, y) for x, y in F if (x, y + 1) not in F and y >= LETTER_H - max(2, round(2 * ACCENT))} - hi
    return hi, lo


def filled(cells):
    """the cells with their enclosed holes filled (a flood from outside the bounding box)"""
    xs = [x for x, _ in cells]
    ys = [y for _, y in cells]
    x0, x1, y0, y1 = min(xs) - 1, max(xs) + 1, min(ys) - 1, max(ys) + 1
    outside, stack = set(), [(x0, y0)]
    while stack:
        c = stack.pop()
        if c in outside or c in cells or not (x0 <= c[0] <= x1 and y0 <= c[1] <= y1):
            continue
        outside.add(c)
        stack += [(c[0] + 1, c[1]), (c[0] - 1, c[1]), (c[0], c[1] + 1), (c[0], c[1] - 1)]
    return {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)} - outside


def span_fill(cells):
    """each row filled from its leftmost cell to its rightmost: the letter as a block"""
    rows = {}
    for x, y in cells:
        lo, hi = rows.get(y, (x, x))
        rows[y] = (min(lo, x), max(hi, x))
    return {(x, y) for y, (lo, hi) in rows.items() for x in range(lo, hi + 1)}


def corner_cuts(cells):
    """one unit off each end of the runs along the bottom row of [cells]"""
    ymax = max(y for _, y in cells)
    cut = set()
    xs = sorted(x for x, y in cells if y == ymax)
    runs, start = [], None
    for a, b in zip(xs, xs[1:] + [None]):
        start = a if start is None else start
        if b != a + 1:
            runs.append((start, a))
            start = None
    for a, b in runs:
        if b - a + 1 >= 4:
            cut |= {(a, ymax), (b, ymax)}
    return cut


def word_layers(word, depth=DEPTH):
    """the cell sets of each group for the word: faces, highlights, shadows, outlines, extrusion, extrusion shade"""
    L, width = letters(word)
    faces, hi, lo, rings, ext = set(), set(), set(), set(), set()
    for ch, F, x0, w in L:
        faces |= F
        h, l = bevel(F)
        hi |= h
        lo |= l
        R = dilate(F) - F
        # no outline in a one-unit slot between two strokes (the slab shows through it instead)
        R = {(x, y) for x, y in R if not ((x, y - 1) in F and (x, y + 1) in F) and not ((x - 1, y) in F and (x + 1, y) in F)}
        rings |= R | F
        # the extrusion: the letter as a block (its outlined rows spanned, so its counters and mouths show it)
        # carried down by [depth]
        E = sweep(span_fill(R | F), depth)
        ext |= E - corner_cuts(E)          # a unit off its bottom corners: a notch where neighbours meet
    # the espresso: each letter's ring, and a line round the outside of the extrusion only
    extrusion = ext - rings
    outline = (rings - faces) | (dilate(extrusion) - extrusion - rings)
    ext_shade = {(x, y) for x, y in extrusion if (x, y + 1) not in ext}       # its bottom row
    return dict(faces=faces, highlights=hi, shadows=lo, outlines=outline, extrusion=extrusion, ext_shade=ext_shade), width, L


# ---- the accents (half-unit sprites; letters h/m/d/e = highlight, mid, dark, deep for the crystal) -----------
def facets(rows):
    """a crystal silhouette ('#') lit from the top-left: the left of each row highlight, the right dark, the
    bottom rows deeper"""
    out = {}
    n = len(rows)
    for r, row in enumerate(rows):
        xs = [c for c, v in enumerate(row) if v == '#']
        if not xs:
            continue
        lo_, hi_ = min(xs), max(xs)
        w = hi_ - lo_ + 1
        for c in xs:
            u = (c - lo_ + 0.5) / w
            k = 'h' if u < 0.34 else ('d' if u > 0.7 else 'm')
            if r >= n - 2 and k == 'd':
                k = 'e'
            if r <= 1:
                k = 'm' if k == 'd' else k
            out[(c, r)] = k
    return out


CRYSTAL_C = ['.....##.....', '....####....', '...######...', '...######...', '..########..', '..########..', '.##########.',
             '.##########.', '.##########.', '.##########.', '..########..', '..########..', '...######...']
CRYSTAL_L = ['##......', '###.....', '####....', '.####...', '.#####..', '..#####.', '..######', '...#####', '....####', '.....###']
CRYSTAL_R = [row[::-1] for row in CRYSTAL_L]
SPROUT = ['llll.....llll', 'llggg...gggll', '.lgggg.gggg..', '..ggggggggg..', '...gggkggg...', '....gkkkg....',
          '.....kkk.....', '.....kkk.....', '......k......', '......k......']
SPARK = sprite(['..#..', '..#..', '#####', '..#..', '..#..'])
SPARK_S = sprite(['.#.', '###', '.#.'])


def crystal_paths(path, P, ox, oy, scale=1.0):
    """the cluster: side crystals first, then the centre over them; each outlined, then faceted"""
    parts = [(CRYSTAL_L, -5.0, 3.0), (CRYSTAL_R, 9.0, 3.0), (CRYSTAL_C, 0.0, 0.0)]
    s = []
    for rows, dx, dy in parts:   # each crystal's outline, with a base below it (its own small extrusion)
        cells = sprite(rows)
        base = shift({(x, y) for x, y in cells if (x, y + 1) not in cells}, 0, 1) | shift({(x, y) for x, y in cells if (x, y + 1) not in cells}, 0, 2)
        s.append(path(dilate(cells | base, eight=False), P['espresso'], 0.5 * scale, ox + dx * 0.5 * scale, oy + dy * 0.5 * scale))
        s.append(path(base - cells, P['amber_deep'], 0.5 * scale, ox + dx * 0.5 * scale, oy + dy * 0.5 * scale))
    for rows, dx, dy in parts:
        f = facets(rows)
        for k, col in (('h', 'amber_hi'), ('m', 'amber'), ('d', 'amber_dk'), ('e', 'amber_deep')):
            cells = {c for c, v in f.items() if v == k}
            if cells:
                s.append(path(cells, P[col], 0.5 * scale, ox + dx * 0.5 * scale, oy + dy * 0.5 * scale))
        # a glint on the lit facet
        top = min(y for _, y in f)
        s.append(path({(c, y) for (c, y), v in f.items() if v == 'h' and y == top + 3}, P['amber_lt'], 0.5 * scale, ox + dx * 0.5 * scale, oy + dy * 0.5 * scale))
    return s


def sprout_paths(path, P, ox, oy, scale=1.0):
    cells = sprite(SPROUT, 'lgk')
    s = [path(dilate(cells, eight=False), P['espresso'], 0.5 * scale, ox, oy)]
    for k, col in (('g', 'sprout'), ('l', 'sprout_lt'), ('k', 'sprout_dk')):
        s.append(path(sprite(SPROUT, k), P[col], 0.5 * scale, ox, oy))
    return s


# ---- the drawing ---------------------------------------------------------------------------------------------
GROUPS = ('letter-outlines', 'letter-extrusion', 'letter-shadows', 'letter-faces', 'letter-highlights',
          'green-sprouts', 'amber-crystal', 'decorative-sparkles')


def logo_svg(word='EVOCHI', unit=16, groups=GROUPS, depth=DEPTH, sprouts_on=(0, 4), crystal_over=(2, 3),
             mono=None, pad=1.0, title='EVOCHI logo'):
    lay, width, L = word_layers(word, depth)
    P = dict(PAL)
    if mono:
        P = {k: mono for k in P}
    A = ACCENT
    top = (8.5 if 'amber-crystal' in groups else (5.0 if 'green-sprouts' in groups else 0.0)) * A
    side = 3.0 * A if 'decorative-sparkles' in groups else 0.0
    ox, oy = 2 + pad + side, 1 + top + pad
    W = (width + 4 + 2 * pad + 2 * side) * unit
    H = (LETTER_H + 2 + depth + top + 2 * pad) * unit

    def path(cells, fill, unit_scale=1.0, dx=0.0, dy=0.0):
        if not cells:
            return ''
        return f'<path d="{path_d(cells, unit, ox + dx, oy + dy, unit_scale)}" fill="{fill}" fill-rule="evenodd"/>'

    g = {}
    if mono:
        # one colour: the letterforms and the marks as solid shapes (no outline or extrusion to muddy them)
        g['letter-faces'] = path(lay['faces'], mono)
    else:
        g['letter-outlines'] = path(lay['outlines'], P['espresso'])
        g['letter-extrusion'] = path(lay['extrusion'], P['cocoa'])
        g['letter-shadows'] = path(lay['ext_shade'], P['cocoa_dk']) + path(lay['shadows'], P['cream_lo'])
        g['letter-faces'] = path(lay['faces'], P['cream'])
        g['letter-highlights'] = path(lay['highlights'], P['cream_hi'])
    if 'green-sprouts' in groups:
        s = []
        for li in sprouts_on:
            ch, F, x0, w = L[li]
            col = x0 + w / 2 if (x0 + int(w / 2), 0) in F else x0 + w - 1      # the stem on a stroke: the middle column, else the right stem
            cx = col - 6.5 * 0.5 * A
            s += sprout_paths(path, P, cx, -1.0 - 10 * 0.5 * A + 1.0 * A, A)   # the stem's foot into the face
        g['green-sprouts'] = ''.join(s)
    if 'amber-crystal' in groups:
        xa, wa = L[crystal_over[0]][2], L[crystal_over[0]][3]
        xb, wb = L[crystal_over[1]][2], L[crystal_over[1]][3]
        cs = A * 1.0                                   # the cluster on the letters' grid
        cx = (xa + xb + wb) / 2 - 12 * 0.25 * cs       # the centre crystal (12 half units wide) over the join
        g['amber-crystal'] = ''.join(crystal_paths(path, P, cx, -1.0 - 13 * 0.5 * cs, cs))
    if 'decorative-sparkles' in groups:
        s = []
        for sp, x, y in ((SPARK, -4.5, -4.0), (SPARK_S, -3.5, 4.0), (SPARK, width / A + 2.0, -3.5), (SPARK_S, width / A + 2.5, 5.0),
                         (SPARK_S, width / A / 2 - 9.0, -8.0), (SPARK_S, width / A / 2 + 7.5, -7.5)):
            s.append(path(sp, P['glow'], 0.5 * A, x * A, y * A))
        g['decorative-sparkles'] = ''.join(s)
    body = '\n  '.join(f'<g id="{k}">{g[k]}</g>' for k in GROUPS if k in g and g[k])
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W:g} {H:g}" width="{W:g}" height="{H:g}" '
            f'shape-rendering="crispEdges">\n  <title>{title}</title>\n  {body}\n</svg>\n'), (W, H)


def icon_svg(unit=16, mono=None):
    """the mark on its own: the crystal cluster, a sprout to either side at its foot, on a square"""
    P = dict(PAL) if not mono else {k: mono for k in PAL}
    S = 22.0
    ox, oy = 0.0, 0.0

    def path(cells, fill, unit_scale=1.0, dx=0.0, dy=0.0):
        return f'<path d="{path_d(cells, unit, ox + dx, oy + dy, unit_scale)}" fill="{fill}" fill-rule="evenodd"/>'

    cx, cy = S / 2 - 4.2, 2.5
    parts = [f'<g id="amber-crystal">{"".join(crystal_paths(path, P, cx, cy, 1.4))}</g>',
             f'<g id="green-sprouts">{"".join(sprout_paths(path, P, cx - 6.0, cy + 9.0, 1.1))}{"".join(sprout_paths(path, P, cx + 8.5, cy + 9.0, 1.1))}</g>']
    W = S * unit
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W:g} {W:g}" width="{W:g}" height="{W:g}" shape-rendering="crispEdges">\n'
            f'  <title>EVOCHI icon</title>\n  ' + '\n  '.join(parts) + '\n</svg>\n'), W


def main(out, unit=16, png=False):
    os.makedirs(out, exist_ok=True)
    files = {}
    files['evochi_logo.svg'] = logo_svg(unit=unit)[0]
    files['evochi_logo_compact.svg'] = logo_svg(unit=unit, groups=('letter-outlines', 'letter-extrusion', 'letter-shadows', 'letter-faces', 'letter-highlights', 'amber-crystal'), depth=1, title='EVOCHI')[0]
    files['evochi_logo_mono.svg'] = logo_svg(unit=unit, groups=('letter-faces', 'green-sprouts', 'amber-crystal'), mono=PAL['espresso'], title='EVOCHI logo, one colour')[0]
    files['evochi_icon.svg'] = icon_svg(unit)[0]
    for name, svg in files.items():
        with open(os.path.join(out, name), 'w') as f:
            f.write(svg)
        print(name, len(svg), 'bytes', flush=True)
    if png:
        validation(out, unit)


def raster(svg_path, png_path, width):
    subprocess.run(['rsvg-convert', '-w', str(width), '-o', png_path, svg_path], check=True)


def validation(out, unit):
    """rasters at the sizes the game shows the logo, the construction layers one by one, and a context sheet"""
    from PIL import Image, ImageDraw
    v = os.path.join(out, 'validation')
    os.makedirs(v, exist_ok=True)
    sizes = {'evochi_logo.svg': [760, 281, 160], 'evochi_logo_compact.svg': [240, 120, 84], 'evochi_icon.svg': [192, 64, 32, 24],
             'evochi_logo_mono.svg': [281, 120]}
    tiles = []
    for name, ws in sizes.items():
        for w in ws:
            p = os.path.join(v, f'{name[:-4]}_{w}.png')
            raster(os.path.join(out, name), p, w)
            tiles.append((f'{name[:-4]} @ {w}px', Image.open(p).convert('RGBA')))
    # the sheet: small rasters shown at 1x and at 3x nearest, so the pixels can be checked
    rows = []
    for label, im in tiles:
        z = 3 if im.width < 300 else 1
        big = im.resize((im.width * z, im.height * z), Image.NEAREST)
        rows.append((label + (f' (shown {z}x)' if z > 1 else ''), big))
    W = max(im.width for _, im in rows) + 40
    H = sum(im.height + 34 for _, im in rows) + 20
    sheet = Image.new('RGBA', (W, H), (250, 244, 232, 255))
    d = ImageDraw.Draw(sheet)
    y = 10
    for label, im in rows:
        d.text((20, y), label, fill=(60, 40, 30, 255))
        sheet.alpha_composite(im, (20, y + 16))
        y += im.height + 34
    sheet.save(os.path.join(out, 'logo_sizes.png'))
    # the construction layers, each alone over a checkerboard
    layers = []
    for grp in GROUPS:
        svg, (w, h) = logo_svg(unit=unit)
        # keep only this group (the others emptied) so positions stay the same
        import re
        kept = re.sub(r'<g id="(?!%s")[^"]+">.*?</g>' % grp, '', svg, flags=re.S)
        p = os.path.join(v, f'layer_{grp}.svg')
        open(p, 'w').write(kept)
        raster(p, p[:-4] + '.png', 520)
        layers.append((grp, Image.open(p[:-4] + '.png').convert('RGBA')))
    svg, _ = logo_svg(unit=unit)
    raster(os.path.join(out, 'evochi_logo.svg'), os.path.join(v, 'full_520.png'), 520)
    layers.append(('all layers', Image.open(os.path.join(v, 'full_520.png')).convert('RGBA')))
    lw, lh = layers[0][1].size
    cols = 3
    sheet = Image.new('RGBA', (cols * (lw + 20) + 20, ((len(layers) + cols - 1) // cols) * (lh + 36) + 20), (250, 244, 232, 255))
    d = ImageDraw.Draw(sheet)
    for i, (grp, im) in enumerate(layers):
        x, y = 20 + (i % cols) * (lw + 20), 20 + (i // cols) * (lh + 36)
        for cy in range(0, lh, 12):
            for cx in range(0, lw, 12):
                if (cx // 12 + cy // 12) % 2 == 0:
                    d.rectangle((x + cx, y + 16 + cy, x + cx + 11, y + 16 + cy + 11), fill=(236, 230, 220, 255))
        sheet.alpha_composite(im, (x, y + 16))
        d.text((x, y), grp, fill=(60, 40, 30, 255))
    sheet.save(os.path.join(out, 'logo_layers.png'))
    context_sheet(out, v)


def context_sheet(out, v):
    """the primary logo over night sky and over grass, the compact one on a header bar, the icon on a tile"""
    from PIL import Image, ImageDraw
    logo = Image.open(os.path.join(v, 'evochi_logo_760.png')).convert('RGBA')
    compact = Image.open(os.path.join(v, 'evochi_logo_compact_240.png')).convert('RGBA')
    icon = Image.open(os.path.join(v, 'evochi_icon_192.png')).convert('RGBA')
    mono = Image.open(os.path.join(v, 'evochi_logo_mono_281.png')).convert('RGBA')
    W = logo.width + 60
    sheet = Image.new('RGBA', (W * 2, logo.height + 60 + 300), (250, 244, 232, 255))
    d = ImageDraw.Draw(sheet)
    d.rectangle((20, 20, 20 + logo.width + 20, 20 + logo.height + 20), fill=(38, 30, 78, 255))
    sheet.alpha_composite(logo, (30, 30))
    d.rectangle((W + 20, 20, W + 20 + logo.width + 20, 20 + logo.height + 20), fill=(96, 150, 70, 255))
    sheet.alpha_composite(logo, (W + 30, 30))
    y = logo.height + 70
    d.rectangle((20, y, 20 + 560, y + 64), fill=(255, 240, 222, 255))        # a header bar in the app's shell colour
    d.rectangle((20, y + 62, 20 + 560, y + 64), fill=(201, 167, 140, 255))
    cm = compact.resize((int(compact.width * 48 / compact.height), 48), Image.LANCZOS)
    sheet.alpha_composite(cm, (36, y + 8))
    d.text((20, y + 72), 'compact, in a 64 px header', fill=(60, 40, 30, 255))
    sheet.alpha_composite(mono, (20, y + 100))
    d.text((20, y + 100 + mono.height + 4), 'monochrome', fill=(60, 40, 30, 255))
    d.rounded_rectangle((W + 20, y, W + 20 + 220, y + 220), radius=44, fill=(255, 240, 222, 255), outline=(201, 167, 140, 255), width=3)
    sheet.alpha_composite(icon, (W + 34, y + 14))
    d.text((W + 20, y + 228), 'icon', fill=(60, 40, 30, 255))
    sheet.save(os.path.join(out, 'logo_context.png'))
    print('logo_context.png', sheet.size, flush=True)


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = dict(a[2:].split('=', 1) if '=' in a else (a[2:], '1') for a in sys.argv[1:] if a.startswith('--'))
    main(args[0] if args else 'logo_out', int(opts.get('unit', 16)), png='png' in opts)

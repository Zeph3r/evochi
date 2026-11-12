"""The EVOCHI logo's lettering from Pixelify Sans Bold (OFL; chosen over Jersey 20 and Kenney Pixel Square
against the concept, 11 Nov 2026): each glyph's actual outline, snapped to the font's half-pitch pixel grid
(the Bold's fat pixels sit on a 1-cell pitch, their edges on the half cell), becomes a cell set, stretched a
touch wider to the concept's proportions. logo_svg then builds every letter on its own from those cells:
face, bevel, its own outline, and an extrusion carried down from its silhouette; the crystal, the sprouts and
the sparkles scale up with the taller grid.

    python3 logo_font.py FONT_TTF OUT_DIR [--png] [--stretch=1] [--thin]

The letter paths stay editable: each layer group holds one <path> per glyph (id="face-E", "outline-E", ...).
"""
import os
import sys

from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import RecordingPen

import logo_svg

WORD = 'EVOCHI'

# the concept's departures from the font, by row (after the stretch): the C's mouth opened (the Bold's is a
# slit), the V brought to a point (the Bold's arms end in a slit)
ADJUST = {
    'E': {0: '############', 1: '############', 13: '############', 14: '############',       # the Bold's two-cell chamfers squared off: the concept's corners get a one-unit cut below
          3: '###.........', 4: '###.........', 10: '###.........', 11: '###.........'},   # the Bold's arms hook at the tips; the concept's are plain
    'O': {0: '############', 1: '############', 13: '############', 14: '############'},
    'C': {0: '############', 1: '############', 13: '############', 14: '############',
          5: '###.........', 6: '###.........', 7: '###.........', 8: '###.........', 9: '###.........'},
    'V': {8: '.###....###.', 9: '.###....###.', 10: '..###..###..', 11: '..###..###..', 12: '...######...', 13: '....####....', 14: '....####....'},
}


def glyph_polys(font, ch):
    gs, cmap = font.getGlyphSet(), font.getBestCmap()
    g = gs[cmap[ord(ch)]]
    pen = RecordingPen()
    g.draw(pen)
    polys, cur = [], []
    for op, args in pen.value:
        if op == 'moveTo':
            cur = [args[0]]
        elif op == 'lineTo':
            cur.append(args[0])
        elif op == 'closePath':
            polys.append(cur)
            cur = []
        else:
            raise SystemExit(f'{ch}: curves in a pixel font? ({op})')
    return polys, g.width


def inside(polys, x, y):
    """nonzero-winding point in polygons (TrueType's rule: the Bold's fat pixels overlap as contours)"""
    wn = 0
    for p in polys:
        for (x0, y0), (x1, y1) in zip(p, p[1:] + p[:1]):
            if y0 <= y < y1 or y1 <= y < y0:
                xi = x0 + (y - y0) * (x1 - x0) / (y1 - y0)
                if xi > x:
                    wn += 1 if y1 > y0 else -1
    return wn != 0


def snap_grid(font):
    """the half-pitch grid: from the Bold E's edges (its left edge and its baseline, the pitch between the
    chamfer cell and the stroke)"""
    polys, _ = glyph_polys(font, 'E')
    xs = sorted({round(x) for p in polys for x, _ in p})
    ys = sorted({round(y) for p in polys for _, y in p})
    x0, y0 = xs[0], ys[0]
    # the E is 11 half cells wide and 15 tall in Pixelify Sans Bold
    return x0, y0, (xs[-1] - x0) / 11.0, (ys[-1] - y0) / 15.0


def cells_of(font, ch, grid, stretch=1):
    """the glyph as unit cells (y down, 0 at the cap line), sampled at cell centres, [stretch] extra
    columns duplicated at the glyph's middle"""
    polys, adv = glyph_polys(font, ch)
    x0, y0, ux, uy = grid
    xs = [x for p in polys for x, _ in p]
    ys = [y for p in polys for _, y in p]
    w = round((max(xs) - min(xs)) / ux)
    h = round((max(ys) - min(ys)) / uy)
    gx0, gy0 = min(xs), min(ys)
    cells = set()
    for j in range(h):
        for i in range(w):
            if inside(polys, gx0 + (i + 0.5) * ux, gy0 + (j + 0.5) * uy):
                cells.add((i, h - 1 - j))
    if stretch and w > 4:
        mid = w // 2       # the centre column, duplicated (a bar stays a bar, a counter a counter, a point a point)
        out = set()
        for x, y in cells:
            out.add((x if x <= mid else x + stretch, y))
            if x == mid:
                for k in range(stretch):
                    out.add((x + 1 + k, y))
        cells, w = out, w + stretch
    return cells, w, h


def corner_cuts(cells, w, h):
    """the concept's corners: one unit cut off each end of the runs along the top and bottom rows"""
    cut = set()
    for y in (0, h - 1):
        x = 0
        while x < w:
            if (x, y) in cells:
                x1 = x
                while (x1 + 1, y) in cells:
                    x1 += 1
                if x1 - x + 1 >= 4:
                    cut |= {(x, y), (x1, y)}
                x = x1 + 1
            else:
                x += 1
    return cut


def rows_of(cells, w, h):
    return [''.join('#' if (x, y) in cells else '.' for x in range(w)) for y in range(h)]


def main(ttf, out, png=False, stretch=1, bold=True):
    font = TTFont(ttf)
    grid = snap_grid(font)
    rows = {}
    H = 0
    for ch in WORD:
        cells, w, h = cells_of(font, ch, grid, stretch)
        rows[ch] = rows_of(cells, w, h)
        for r, row in ADJUST.get(ch, {}).items():
            assert len(row) == w, (ch, r, w)
            rows[ch][r] = row
        if bold:   # the concept's strokes are heavier than the Bold's: every glyph grown by one unit all round
            cells = {(x + 1, y + 1) for y, row in enumerate(rows[ch]) for x, v in enumerate(row) if v == '#'}
            # grown sideways and down (not up as well: the concept's counters are half a stroke tall, not a slit)
            cells = cells | {(x + 1, y) for x, y in cells} | {(x - 1, y) for x, y in cells} | {(x, y + 1) for x, y in cells}
            cells = {(x, y - 1) for x, y in cells}
            w, h = w + 2, h + 1
            cells -= corner_cuts(cells, w, h)
            rows[ch] = rows_of(cells, w, h)
        H = max(H, h)
        print(ch, w, 'x', h)
        print('\n'.join('   ' + r for r in rows[ch]))
    logo_svg.set_font(rows, H, gap=2, depth=4)
    logo_svg.main(out, unit=10, png=png)


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = dict(a[2:].split('=', 1) if '=' in a else (a[2:], '1') for a in sys.argv[1:] if a.startswith('--'))
    main(args[0], args[1], png='png' in opts, stretch=int(opts.get('stretch', 1)), bold='thin' not in opts)

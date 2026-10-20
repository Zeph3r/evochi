"""Sunlit Village square: the three lightings share one layout (day_dim, lamp_lit, waystone_restored)."""

# a 780 x 867 overhead of the square; the glasshouse (left), the lodge (top), Bram's workshop (right)
FX = [
    ('grass', [0, 0, 780, 867], 'green'),
    ('none', [0, 316, 242, 522]),  # the glasshouse: no wind indoors
    ('tree', ('e', 30, 60, 52, 78), 'green'),
    ('tree', ('e', 180, 195, 64, 62), 'green'),
    ('tree', ('e', 20, 248, 42, 48), 'green'),
    ('tree', ('e', 552, 40, 54, 52), 'green'),
    ('tree', ('e', 612, 212, 56, 64), 'green'),
    ('tree', ('e', 746, 60, 62, 78), 'green'),
    ('tree', ('e', 760, 252, 52, 88), 'green'),
    ('tree', ('e', 86, 772, 108, 104), 'green'),
    ('tree', ('e', 730, 776, 78, 98), 'green'),
    ('fall', [118, 0, 182, 56]),
    ('still', [52, 58, 238, 132], 'water'),
    ('still', [226, 328, 528, 412], 'water'),
    ('still', [742, 328, 780, 384], 'water'),
    ('smoke', [(690, 250), (735, 250), (778, 118), (720, 112)], 'smoky'),
    ('lamp', [284, 200, 500, 240], 'warm'),
    ('lamp', [284, 258, 506, 298], 'warm'),
    ('lamp', [668, 455, 742, 512], 'warm'),
    ('lamp', [236, 352, 262, 384], 'bright'),
    ('lamp', [216, 434, 252, 458], 'bright'),
    ('lamp', [214, 500, 246, 536], 'bright'),
    ('lamp', [516, 350, 546, 386], 'bright'),
    ('lamp', [534, 440, 552, 462], 'bright'),
    ('lamp', [536, 502, 566, 536], 'bright'),
    ('lamp', [520, 572, 552, 604], 'bright'),
]

SMOKE = {'t': 'smoke', 'x': 714, 'y': 246, 'n': 7, 's': 12, 'h': 190, 'drift': 46, 'c': '#f4efe6', 'a': 0.5}
LEAVES = {'t': 'leaves', 'x': 0, 'y': 120, 'w': 780, 'h': 560, 'n': 3}
POLLEN = {'t': 'motes', 'kind': 'pollen', 'x': 0, 'y': 560, 'w': 780, 'h': 300, 'n': 10, 'c': '#fff6c8', 's': 3}
WINDOWS = [
    {'t': 'glow', 'x': 311, 'y': 221, 'r': 30, 'c': '#ffc561', 'kind': 'lamp', 'a': 0.5},
    {'t': 'glow', 'x': 390, 'y': 221, 'r': 30, 'c': '#ffc561', 'kind': 'lamp', 'a': 0.5},
    {'t': 'glow', 'x': 474, 'y': 221, 'r': 30, 'c': '#ffc561', 'kind': 'lamp', 'a': 0.5},
    {'t': 'glow', 'x': 308, 'y': 277, 'r': 28, 'c': '#ffc561', 'kind': 'lamp', 'a': 0.5},
    {'t': 'glow', 'x': 485, 'y': 277, 'r': 28, 'c': '#ffc561', 'kind': 'lamp', 'a': 0.5},
    {'t': 'glow', 'x': 703, 'y': 484, 'r': 52, 'c': '#ffb04a', 'kind': 'fire', 'a': 0.55},
]
LAMPS = [
    {'t': 'glow', 'x': x, 'y': y, 'r': r, 'c': '#ffd27a', 'kind': 'lamp', 'a': 0.6}
    for x, y, r in ((249, 368, 30), (235, 446, 26), (230, 518, 30), (530, 368, 30), (543, 451, 20), (550, 520, 30), (534, 588, 34))
]

SCENES = {
    'village/square_day_dim.webp': {
        'fx': FX,
        'emit': [SMOKE, LEAVES, POLLEN],
    },
    'village/square_lamp_lit.webp': {
        'fx': FX,
        'emit': [SMOKE, LEAVES, POLLEN] + WINDOWS + LAMPS,
    },
    'village/square_waystone_restored.webp': {
        'fx': FX + [('crystal', [340, 380, 440, 520], 'bright')],
        'emit': [SMOKE, LEAVES] + WINDOWS + LAMPS + [
            {'t': 'glow', 'x': 390, 'y': 455, 'r': 90, 'c': '#b8ffd8', 'kind': 'crystal', 'a': 0.45},
            {'t': 'motes', 'kind': 'firefly', 'x': 60, 'y': 300, 'w': 680, 'h': 420, 'n': 14, 'c': '#f6ff9a', 's': 4},
        ],
    },
}

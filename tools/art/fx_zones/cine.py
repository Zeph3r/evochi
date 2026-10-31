"""The cold open's plates (tools/art/cine_scenes.py), alive under the camera moves: the cinematic player draws a
plate with zones through the same shader as the game's scenes (cinematic_player.dart)."""

# Sunlit Village from above at dusk, 933 x 1400: the hills and their trees behind, the waterfall off the cliff
# left of the Lodge into its pool, the Lodge (top centre), the Glasshouse (left), Bram's workshop (right), the
# market awning, the Waystone, the path down to the gate
VILLAGE_DUSK = [
    # the trees on the far hills: a gentle sway only (the terraces' grass is green too, so keep it small)
    ('tree', [0, 200, 933, 520], 'green', {'amp': 0.3}),
    # the canopies against the sky on the far ridge (hazy blue-grey, so marked by shape), swaying from the top
    ('tree', ('e', 432, 156, 28, 26), 'all', {'amp': 0.6, 'fade': 0.2}),
    ('tree', ('e', 690, 108, 50, 44), 'all', {'amp': 0.6, 'fade': 0.2}),
    ('tree', ('e', 868, 164, 38, 32), 'all', {'amp': 0.6, 'fade': 0.2}),
    ('tree', ('e', 205, 172, 34, 28), 'all', {'amp': 0.5, 'fade': 0.2}),
    # nearer canopies, swaying properly
    ('tree', ('e', 50, 590, 70, 80), 'green', {'amp': 0.85}),
    ('tree', ('e', 160, 520, 50, 45), 'green', {'amp': 0.8}),
    ('tree', ('e', 360, 560, 45, 40), 'green', {'amp': 0.8}),
    ('tree', ('e', 740, 610, 55, 50), 'green', {'amp': 0.8}),
    ('tree', ('e', 895, 590, 45, 60), 'green', {'amp': 0.8}),
    ('tree', ('e', 60, 845, 68, 68), 'green', {'amp': 1.0, 'fade': 0.35}),
    ('tree', ('e', 232, 955, 82, 75), 'green', {'amp': 1.0, 'fade': 0.35}),
    ('tree', ('e', 822, 968, 78, 66), 'green', {'amp': 1.0, 'fade': 0.35}),
    # the waterfall off the cliff, and its pool
    # (at dusk the fall is a dim lilac-grey column, so it is marked by its shape, not its colour)
    ('fall', [280, 366, 338, 512]),
    ('fall', [280, 512, 302, 548]),
    ('still', [205, 540, 380, 610], 'water'),
    # the Glasshouse's lit plants breathe, the market awning stirs
    ('lamp', [140, 660, 390, 810], 'warm'),
    ('lamp', [140, 660, 390, 810], 'bright'),
    ('cloth', [90, 800, 245, 900], 'cloth', {'amp': 0.5}),
    # lit windows: the Lodge, Bram's workshop (his forge flickers), the lanterns
    ('lamp', [420, 600, 660, 730], 'warm'),
    ('lamp', [420, 600, 660, 730], 'bright'),
    ('fire', [770, 800, 870, 875], 'warm'),
    ('fire', [770, 800, 870, 875], 'bright'),
    ('lamp', [560, 760, 720, 960], 'bright'),
    ('lamp', [760, 880, 840, 940], 'bright'),
    ('lamp', [20, 930, 70, 980], 'bright'),
    ('lamp', [370, 680, 420, 720], 'bright'),
]

_WARM = '#ffc561'
VILLAGE_DUSK_EMIT = [
    # the Lodge's windows and door
    {'t': 'glow', 'x': 448, 'y': 640, 'r': 26, 'c': _WARM, 'kind': 'lamp', 'a': 0.45},
    {'t': 'glow', 'x': 530, 'y': 640, 'r': 26, 'c': _WARM, 'kind': 'lamp', 'a': 0.45},
    {'t': 'glow', 'x': 615, 'y': 640, 'r': 26, 'c': _WARM, 'kind': 'lamp', 'a': 0.45},
    {'t': 'glow', 'x': 452, 'y': 690, 'r': 24, 'c': _WARM, 'kind': 'lamp', 'a': 0.4},
    {'t': 'glow', 'x': 612, 'y': 690, 'r': 24, 'c': _WARM, 'kind': 'lamp', 'a': 0.4},
    # the Glasshouse, warm inside
    {'t': 'glow', 'x': 262, 'y': 735, 'r': 95, 'c': '#ffd97a', 'kind': 'lamp', 'a': 0.3},
    # Bram's forge through the workshop window, and his chimney
    {'t': 'glow', 'x': 822, 'y': 836, 'r': 58, 'c': '#ffb04a', 'kind': 'fire', 'a': 0.55},
    {'t': 'smoke', 'x': 826, 'y': 600, 'n': 6, 's': 10, 'h': 170, 'drift': 34, 'c': '#d9d2e6', 'a': 0.4},
    # the lanterns along the paths
    *[{'t': 'glow', 'x': x, 'y': y, 'r': r, 'c': '#ffe08a', 'kind': 'lamp', 'a': 0.55}
      for x, y, r in ((580, 780, 14), (612, 778, 14), (640, 860, 16), (700, 936, 14), (808, 896, 14), (818, 926, 12),
                      (44, 955, 14), (396, 700, 12), (775, 812, 12), (885, 810, 12), (248, 607, 10), (805, 605, 12))],
    # spray where the fall meets the pool
    {'t': 'smoke', 'x': 306, 'y': 556, 'n': 5, 's': 9, 'h': 40, 'drift': 6, 'c': '#e8eef8', 'a': 0.3, 'kind': 'steam'},
    # fireflies over the village
    {'t': 'motes', 'kind': 'firefly', 'x': 20, 'y': 640, 'w': 900, 'h': 420, 'n': 18, 'c': '#f6ff9a', 's': 4},
]

SCENES = {
    'cine/village_dusk.webp': {'fx': VILLAGE_DUSK, 'emit': VILLAGE_DUSK_EMIT},
}

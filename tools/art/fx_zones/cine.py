"""The cold open's plates (tools/art/cine_scenes.py), alive under the camera moves: the cinematic player draws a
plate with zones through the same shader as the game's scenes (cinematic_player.dart)."""

# Sunlit Village from above at dusk, 933 x 1400: the hills and their trees behind, the waterfall off the cliff
# left of the Lodge into its pool, the Lodge (top centre), the Glasshouse (left), Bram's workshop (right), the
# market awning, the Waystone, the path down to the gate
VILLAGE_DUSK = [
    # a breeze over the lawns: the grass shimmers in passing gusts
    ('grass', [0, 980, 933, 1400], 'green'),
    ('grass', [0, 860, 140, 1000], 'green'),
    # the trees on the far hills: a gentle sway only (the terraces' grass is green too, so keep it small)
    ('tree', [0, 200, 933, 520], 'green', {'amp': 0.3}),
    # the canopies against the sky on the far ridge (hazy blue-grey, so marked by shape), swaying from the top
    ('tree', ('e', 432, 156, 28, 26), 'all', {'amp': 0.6, 'fade': 0.2}),
    ('tree', ('e', 690, 108, 50, 44), 'all', {'amp': 0.6, 'fade': 0.2}),
    ('tree', ('e', 868, 164, 38, 32), 'all', {'amp': 0.6, 'fade': 0.2}),
    ('tree', ('e', 205, 172, 34, 28), 'all', {'amp': 0.5, 'fade': 0.2}),
    # nearer canopies: rooted at the trunk, their outlines moving (halo)
    ('tree', ('e', 50, 600, 72, 92), 'green', {'amp': 0.85, 'fade': 0.3, 'halo': 6}),
    ('tree', ('e', 158, 516, 52, 46), 'green', {'amp': 0.8, 'fade': 0.3, 'halo': 6}),
    ('tree', ('e', 362, 560, 46, 42), 'green', {'amp': 0.8, 'fade': 0.3, 'halo': 6}),
    ('tree', ('e', 742, 610, 56, 52), 'green', {'amp': 0.8, 'fade': 0.3, 'halo': 6}),
    ('tree', ('e', 898, 592, 46, 62), 'green', {'amp': 0.8, 'fade': 0.3, 'halo': 6}),
    ('tree', ('e', 64, 842, 70, 70), 'green', {'amp': 1.0, 'fade': 0.25, 'halo': 8}),
    ('tree', ('e', 232, 952, 84, 76), 'green', {'amp': 1.0, 'fade': 0.25, 'halo': 8}),
    ('tree', ('e', 824, 966, 80, 68), 'green', {'amp': 1.0, 'fade': 0.25, 'halo': 8}),
    # the waterfall off the cliff, and its pool
    # (at dusk the fall is a dim lilac-grey column, so it is marked by its shape, not its colour)
    ('fall', [280, 366, 338, 512]),
    ('fall', [280, 512, 302, 548]),
    ('still', [205, 540, 380, 610], 'water'),
    # the Glasshouse's lit plants breathe, the market awning stirs
    ('lamp', [140, 660, 390, 810], 'warm'),
    ('lamp', [140, 660, 390, 810], 'bright'),
    ('cloth', [90, 800, 245, 900], 'cloth', {'amp': 0.5}),
    # lit windows, flame light behind the glass (only the panes: the walls round them get their light from the
    # glows): the Lodge's five, Bram's workshop
    *[('window', r, k) for r in ([434, 625, 465, 656], [517, 628, 546, 656], [599, 629, 629, 658],
                                 [430, 679, 469, 716], [592, 684, 632, 721], [792, 814, 846, 860])
      for k in ('warm', 'bright')],
    # the lanterns, and the little lights along the paths
    *[('window', ('e', x, y, rx, ry), 'bright')
      for x, y, rx, ry in ((586, 778, 10, 12), (613, 778, 7, 7), (581, 841, 7, 7), (665, 833, 8, 11), (663, 869, 6, 7),
                           (643, 875, 10, 13), (777, 814, 7, 7), (791, 873, 7, 7), (808, 896, 7, 7), (806, 919, 7, 7),
                           (817, 924, 7, 7), (702, 938, 7, 7), (44, 956, 8, 8), (377, 776, 7, 7), (385, 731, 7, 11))],
]

_WARM = '#ffc561'
VILLAGE_DUSK_EMIT = [
    # the Lodge's windows and door
    {'t': 'glow', 'x': 449, 'y': 641, 'r': 30, 'c': _WARM, 'kind': 'window', 'a': 0.55},
    {'t': 'glow', 'x': 531, 'y': 642, 'r': 30, 'c': _WARM, 'kind': 'window', 'a': 0.55},
    {'t': 'glow', 'x': 614, 'y': 643, 'r': 30, 'c': _WARM, 'kind': 'window', 'a': 0.55},
    {'t': 'glow', 'x': 449, 'y': 697, 'r': 28, 'c': _WARM, 'kind': 'window', 'a': 0.5},
    {'t': 'glow', 'x': 612, 'y': 702, 'r': 28, 'c': _WARM, 'kind': 'window', 'a': 0.5},
    # the Glasshouse, warm inside
    {'t': 'glow', 'x': 262, 'y': 735, 'r': 95, 'c': '#ffd97a', 'kind': 'lamp', 'a': 0.3},
    # Bram's forge through the workshop window, and his chimney
    {'t': 'glow', 'x': 819, 'y': 837, 'r': 58, 'c': '#ffb04a', 'kind': 'window', 'a': 0.55},
    {'t': 'smoke', 'x': 826, 'y': 600, 'n': 7, 's': 10, 'h': 190, 'drift': 70, 'c': '#d9d2e6', 'a': 0.4},
    # the lanterns along the paths
    *[{'t': 'glow', 'x': x, 'y': y, 'r': r, 'c': '#ffe08a', 'kind': 'window', 'a': 0.6}
      for x, y, r in ((580, 780, 14), (612, 778, 14), (640, 860, 16), (700, 936, 14), (808, 896, 14), (818, 926, 12),
                      (44, 955, 14), (396, 700, 12), (775, 812, 12), (885, 810, 12), (248, 607, 10), (805, 605, 12))],
    # spray where the fall meets the pool
    {'t': 'smoke', 'x': 306, 'y': 556, 'n': 5, 's': 9, 'h': 40, 'drift': 6, 'c': '#e8eef8', 'a': 0.3, 'kind': 'steam'},
    # fireflies over the village
    {'t': 'motes', 'kind': 'firefly', 'x': 20, 'y': 640, 'w': 900, 'h': 420, 'n': 18, 'c': '#f6ff9a', 's': 4},
    # leaves off the trees, blowing across on the wind, near and far
    {'t': 'leaves', 'x': 0, 'y': 780, 'w': 933, 'h': 420, 'n': 9, 'c': ['#6f9a45', '#88b04f', '#a9b95c', '#c49a4a']},
    {'t': 'leaves', 'x': 0, 'y': 430, 'w': 933, 'h': 260, 'n': 5, 'c': ['#5f8a42', '#7aa04c']},
]

SCENES = {
    # seen whole on a phone before the camera pushes in, so a stronger wind than the game's scenes: the trees have
    # to read as moving in a four-second shot
    'cine/village_dusk.webp': {'fx': VILLAGE_DUSK, 'emit': VILLAGE_DUSK_EMIT, 'wind': 3.4, 'rustle': 1.0, 'flicker': 1.0},
}

"""Home Tales: the Home Map (ruined and restored), the Garden, the Cottage, the Kitchen and the Apothecary."""

# ---- the Home Map: 780 x 867 overhead, the cottage top-left, the gate top-right, the garden right
_MAP = [
    ('grass', [0, 0, 780, 867], 'green'),
    ('none', [48, 150, 304, 348]),  # the cottage (moss on the ruined roof must not shimmer)
    ('none', [436, 420, 780, 620]),  # the garden beds and fence
    ('none', [620, 280, 754, 394]),  # the shed's green roof
    ('tree', ('e', 332, 108, 62, 78), 'green'),
    ('tree', ('e', 362, 336, 66, 52), 'green'),
    ('tree', ('e', 448, 812, 62, 66), 'green'),
    ('tree', ('e', 12, 66, 36, 46), 'green'),
    ('tree', ('e', 742, 12, 52, 36), 'green'),
    ('blades', [446, 424, 540, 474], 'green', {'amp': 0.45, 'fade': 0.3}),
    ('blades', [604, 424, 690, 474], 'green', {'amp': 0.45, 'fade': 0.3}),
    ('blades', [620, 512, 700, 574], 'green', {'amp': 0.45, 'fade': 0.3}),
    ('fall', [120, 0, 180, 58]),
    ('still', [52, 58, 232, 128], 'water'),
    ('still', [0, 425, 62, 516], 'water'),
]
_MAP_LEAVES = {'t': 'leaves', 'x': 0, 'y': 140, 'w': 780, 'h': 600, 'n': 3}
_MAP_POLLEN = {'t': 'motes', 'kind': 'pollen', 'x': 0, 'y': 560, 'w': 780, 'h': 300, 'n': 9, 'c': '#fff6c8', 's': 3}

# ---- the Garden: 780 x 867, four beds (crop sprites are drawn over them at runtime: keep them still)
_PLANTS = [  # silhouettes of the sunflowers and stalks behind the back fence
    [(228, 138), (256, 138), (262, 175), (264, 212), (218, 212), (222, 175)],
    [(288, 100), (348, 100), (348, 138), (330, 140), (342, 172), (346, 212), (298, 212), (304, 172), (312, 140), (288, 138)],
    [(398, 138), (424, 138), (426, 212), (384, 212), (392, 175)],
    [(464, 146), (518, 146), (518, 186), (500, 188), (504, 212), (476, 212), (480, 188), (464, 186)],
    [(562, 156), (586, 156), (592, 212), (552, 212), (558, 185)],
    [(632, 110), (696, 110), (696, 152), (672, 154), (680, 212), (632, 212), (640, 154), (632, 152)],
    [(728, 116), (758, 116), (762, 212), (712, 212), (722, 175)],
]
_GARDEN = [
    ('grass', [0, 0, 780, 867], 'green'),
    ('none', [0, 66, 160, 210]),  # the shed's green roof
    ('none', [0, 282, 780, 664]),  # the beds and their path
] + [('blades', p, 'all', {'fade': 0.15}) for p in _PLANTS]

# ---- the Cottage close-up: 780 x 540, the cottage in front of the waterfall and two big trees
_COTTAGE = [
    ('grass', [0, 0, 780, 540], 'green'),
    ('tree', ('e', 92, 56, 112, 78), 'green'),
    ('tree', ('e', 602, 70, 88, 82), 'green'),
    ('tree', ('e', 426, 36, 50, 46), 'green'),
    ('tree', ('e', 762, 412, 62, 122), 'green'),
    ('fall', [278, 0, 346, 84], 'waterfall'),
    ('still', [0, 185, 30, 275], 'water'),
]
_COTTAGE_EMIT = [
    {'t': 'leaves', 'x': 0, 'y': 40, 'w': 780, 'h': 440, 'n': 3},
    {'t': 'motes', 'kind': 'pollen', 'x': 0, 'y': 380, 'w': 780, 'h': 160, 'n': 7, 'c': '#fff6c8', 's': 3},
]

SCENES = {
    'home/home_map_restored.webp': {
        'fx': _MAP + [
            ('smoke', [(228, 108), (262, 108), (292, 0), (226, 0)], 'smoky'),
            ('lamp', [150, 214, 196, 242], 'warm'),
            ('lamp', [94, 280, 142, 322], 'warm'),
            ('lamp', [212, 280, 262, 322], 'warm'),
            ('lamp', [648, 178, 668, 206], 'bright'),
        ],
        'emit': [
            {'t': 'smoke', 'x': 243, 'y': 106, 'n': 6, 's': 10, 'h': 120, 'drift': 26, 'c': '#f4efe6', 'a': 0.5},
            {'t': 'glow', 'x': 172, 'y': 228, 'r': 24, 'c': '#ffc561', 'kind': 'lamp', 'a': 0.5},
            {'t': 'glow', 'x': 118, 'y': 300, 'r': 28, 'c': '#ffc561', 'kind': 'lamp', 'a': 0.5},
            {'t': 'glow', 'x': 237, 'y': 300, 'r': 28, 'c': '#ffc561', 'kind': 'lamp', 'a': 0.5},
            {'t': 'glow', 'x': 657, 'y': 192, 'r': 22, 'c': '#ffd27a', 'kind': 'lamp', 'a': 0.45},
            _MAP_LEAVES, _MAP_POLLEN,
        ],
    },
    'home/home_map_ruined.webp': {
        'fx': _MAP + [
            ('tree', ('e', 252, 56, 54, 54), 'green'),
        ],
        'emit': [_MAP_LEAVES, _MAP_POLLEN],
    },
    'home/garden.webp': {
        'fx': _GARDEN,
        'emit': [
            {'t': 'motes', 'kind': 'pollen', 'x': 0, 'y': 90, 'w': 780, 'h': 170, 'n': 8, 'c': '#fff3b0', 's': 3},
            {'t': 'motes', 'kind': 'pollen', 'x': 0, 'y': 660, 'w': 780, 'h': 200, 'n': 6, 'c': '#fff6c8', 's': 3},
            {'t': 'leaves', 'x': 0, 'y': 60, 'w': 780, 'h': 700, 'n': 2},
        ],
    },
    'home/cottage_restored.webp': {
        'fx': _COTTAGE + [
            ('lamp', [345, 148, 412, 204], 'warm'),
            ('lamp', [232, 280, 306, 332], 'warm'),
            ('lamp', [450, 280, 526, 332], 'warm'),
            ('lamp', [420, 290, 448, 336], 'warm'),
        ],
        'emit': _COTTAGE_EMIT + [
            {'t': 'glow', 'x': 378, 'y': 182, 'r': 34, 'c': '#ffc561', 'kind': 'lamp', 'a': 0.5},
            {'t': 'glow', 'x': 266, 'y': 304, 'r': 40, 'c': '#ffc561', 'kind': 'lamp', 'a': 0.5},
            {'t': 'glow', 'x': 488, 'y': 304, 'r': 40, 'c': '#ffc561', 'kind': 'lamp', 'a': 0.5},
        ],
    },
    'home/cottage_ruined.webp': {
        'fx': _COTTAGE + [
            # the mossy roof and the vines stay put
            ('none', [(150, 214), (196, 84), (602, 84), (612, 214), (612, 272), (566, 386), (196, 386), (150, 272)]),
            ('still', [330, 80, 372, 112], 'water'),  # the waterfall through the roof
        ],
        'emit': _COTTAGE_EMIT,
    },
    # ---- the Kitchen: 780 x 1000 interior, the brick oven left, a lantern over the room
    'home/kitchen.webp': {
        'fx': [
            ('fire', ('e', 209, 500, 50, 38)),  # the oven mouth (and the bricks it lights)
            ('lamp', [342, 240, 390, 292], 'bright'),  # the lantern's pane
        ],
        'emit': [
            {'t': 'glow', 'x': 209, 'y': 500, 'r': 92, 'c': '#ff9a3c', 'kind': 'fire', 'a': 0.55},
            {'t': 'glow', 'x': 200, 'y': 600, 'r': 170, 'c': '#ff8a2a', 'kind': 'fire', 'a': 0.16},
            {'t': 'embers', 'x': 209, 'y': 474, 'w': 64, 'h': 110, 'n': 6, 'c': '#ffb347', 's': 3},
            {'t': 'glow', 'x': 366, 'y': 266, 'r': 48, 'c': '#ffd27a', 'kind': 'lamp', 'a': 0.5},
            {'t': 'motes', 'kind': 'dust', 'x': 60, 'y': 220, 'w': 660, 'h': 520, 'n': 10, 'c': '#ffe2b0', 's': 3},
        ],
    },
    # ---- the Apothecary: 780 x 1000 interior, the cauldron over a little fire, a round window
    'home/apothecary.webp': {
        'fx': [
            ('fire', ('e', 263, 574, 36, 15)),  # the fire under the cauldron
            ('smoke', [(226, 468), (296, 468), (300, 430), (290, 352), (232, 350), (222, 400)], 'all', {'amp': 0.7}),  # the mist
            ('lamp', [428, 240, 464, 276], 'bright'),  # the lantern's pane
            ('cloth', [(0, 298), (722, 298), (722, 350), (430, 350), (430, 357), (0, 357)], 'cloth', {'amp': 0.3}),  # the bunting
        ],
        'emit': [
            {'t': 'glow', 'x': 263, 'y': 572, 'r': 80, 'c': '#ff9a3c', 'kind': 'fire', 'a': 0.55},
            {'t': 'glow', 'x': 263, 'y': 600, 'r': 150, 'c': '#ff8a2a', 'kind': 'fire', 'a': 0.14},
            {'t': 'embers', 'x': 263, 'y': 566, 'w': 56, 'h': 46, 'n': 4, 'c': '#ffb347', 's': 2},
            {'t': 'bubbles', 'x': 260, 'y': 474, 'w': 36, 'h': 5, 'n': 5, 'c': '#e9fff4'},
            {'t': 'smoke', 'kind': 'steam', 'x': 260, 'y': 466, 'n': 6, 's': 10, 'h': 150, 'drift': 10, 'c': '#f2fbff', 'a': 0.45},
            {'t': 'glow', 'x': 446, 'y': 259, 'r': 46, 'c': '#ffd27a', 'kind': 'lamp', 'a': 0.5},
            {'t': 'glow', 'x': 192, 'y': 382, 'r': 72, 'c': '#eafff2', 'kind': 'sun', 'a': 0.3},
            {'t': 'motes', 'kind': 'dust', 'x': 150, 'y': 330, 'w': 280, 'h': 240, 'n': 9, 'c': '#fffbe6', 's': 3},
        ],
    },
}

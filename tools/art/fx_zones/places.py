"""Village places: Bram's Workshop, the Trail Guild Lodge, Mira's Glasshouse (780 x 1000 interiors with
an NPC standing in front) and the Waystone close-ups (667 x 667). Indoors there's no wind: the life
is the forge fire, the lanterns, light and dust; only the Glasshouse plants stir a little."""

# ---- Bram's Workshop: a brick forge on the right, six hanging lanterns, a window at the back
WORKSHOP_LANTERNS = [  # glass box, centre, glow radius, colour (the glass is tinted)
    ([42, 222, 92, 264], (62, 243), 44, '#e6fbff'),
    ([224, 276, 260, 310], (241, 293), 34, '#ffd27a'),
    ([284, 288, 322, 324], (303, 306), 36, '#ffe08a'),
    ([386, 230, 418, 270], (401, 250), 36, '#ffe08a'),
    ([518, 288, 549, 322], (533, 305), 34, '#ffd27a'),
    ([676, 238, 718, 282], (696, 260), 40, '#ffc8c8'),
]

WORKSHOP = {
    'fx': [
        ('fire', [626, 496, 712, 562], 'fire'),
    ] + [('lamp', box, 'bright') for box, _, _, _ in WORKSHOP_LANTERNS],
    'emit': [
        {'t': 'glow', 'x': 668, 'y': 530, 'r': 120, 'c': '#ff8a3c', 'a': 0.55, 'kind': 'fire'},
        {'t': 'glow', 'x': 668, 'y': 528, 'r': 50, 'c': '#ffd08a', 'a': 0.45, 'kind': 'fire'},
        {'t': 'embers', 'x': 668, 'y': 500, 'w': 70, 'h': 150, 'n': 9, 'c': '#ffb347', 's': 3},
    ] + [
        {'t': 'glow', 'x': cx, 'y': cy, 'r': r, 'c': c, 'a': 0.4, 'kind': 'lamp'}
        for _, (cx, cy), r, c in WORKSHOP_LANTERNS
    ] + [
        # dust drifting in the window light over the workbench
        {'t': 'motes', 'kind': 'dust', 'x': 420, 'y': 300, 'w': 180, 'h': 260, 'n': 8, 'c': '#fff4d6', 's': 3},
    ],
}

# ---- Trail Guild Lodge: five lanterns, two Guild banners, a hanging plant, a sunny window right
LODGE_LANTERNS = [
    ([0, 224, 36, 276], (14, 250), 40),
    ([178, 272, 212, 306], (194, 290), 36),
    ([384, 236, 416, 272], (400, 255), 38),
    ([588, 272, 626, 306], (608, 290), 36),
    ([748, 228, 780, 276], (764, 252), 40),
]

LODGE = {
    'fx': [
        ('cloth', [224, 326, 268, 458], 'all', {'amp': 0.3}),
        ('cloth', [526, 326, 574, 448], 'all', {'amp': 0.3}),
        ('tree', [(298, 236), (342, 236), (346, 336), (296, 336)], 'green', {'amp': 0.25}),
    ] + [('lamp', box, 'bright') for box, _, _ in LODGE_LANTERNS],
    'emit': [
        {'t': 'glow', 'x': cx, 'y': cy, 'r': r, 'c': '#ffd27a', 'a': 0.45, 'kind': 'lamp'}
        for _, (cx, cy), r in LODGE_LANTERNS
    ] + [
        {'t': 'glow', 'x': 640, 'y': 380, 'r': 90, 'c': '#fff3cf', 'a': 0.25, 'kind': 'sun'},
        {'t': 'glow', 'x': 640, 'y': 700, 'r': 110, 'c': '#fff0c8', 'a': 0.18, 'kind': 'sun'},
        {'t': 'motes', 'kind': 'dust', 'x': 530, 'y': 360, 'w': 200, 'h': 360, 'n': 10, 'c': '#fff4d6', 's': 3},
    ],
}

# ---- Mira's Glasshouse: three hanging baskets, climbing vines, a flower bed, a bird bath and a water
# barrel. The glass panes are green too, so every shape hugs its plant.
GLASSHOUSE = {
    'fx': [
        # hanging baskets: a slow, gentle sway (leaves and the basket itself)
        ('tree', ('e', 192, 336, 38, 56), 'green', {'amp': 0.35}),
        ('tree', [168, 300, 216, 336], 'all', {'amp': 0.35}),
        ('tree', ('e', 394, 296, 50, 74), 'green', {'amp': 0.35}),
        ('tree', [362, 252, 422, 290], 'all', {'amp': 0.35}),
        ('tree', ('e', 597, 336, 40, 62), 'green', {'amp': 0.35}),
        ('tree', [574, 300, 620, 336], 'all', {'amp': 0.35}),
        # vines climbing the frames: a shimmer more than a sway
        ('tree', [(84, 270), (136, 270), (138, 450), (84, 450)], 'green', {'amp': 0.2}),
        ('tree', [(296, 268), (346, 268), (346, 425), (296, 425)], 'green', {'amp': 0.2}),
        ('tree', [(400, 330), (448, 300), (448, 425), (400, 425)], 'green', {'amp': 0.2}),
        ('tree', [(646, 268), (706, 268), (706, 520), (646, 520)], 'green', {'amp': 0.2}),
        # the flower bed: stems and blooms nod together
        ('tree', [(290, 398), (442, 398), (442, 526), (290, 526)], 'all', {'amp': 0.2, 'fade': 0.3}),
        # potted plants on the floor: light shimmers over the leaves
        ('grass', [506, 648, 566, 706], 'green'),
        ('grass', [654, 614, 738, 700], 'green'),
        # water: the bird bath and the barrel
        ('still', [512, 554, 604, 578], 'water'),
        ('still', [648, 560, 720, 578], 'water'),
    ],
    'emit': [
        {'t': 'glow', 'x': 390, 'y': 230, 'r': 170, 'c': '#fffbe6', 'a': 0.22, 'kind': 'sun'},
        {'t': 'glow', 'x': 240, 'y': 640, 'r': 130, 'c': '#fff4d8', 'a': 0.14, 'kind': 'sun'},
        {'t': 'motes', 'kind': 'dust', 'x': 120, 'y': 200, 'w': 540, 'h': 380, 'n': 14, 'c': '#fffbe0', 's': 3},
        {'t': 'motes', 'kind': 'pollen', 'x': 280, 'y': 380, 'w': 180, 'h': 160, 'n': 6, 'c': '#fff3a0', 's': 3},
    ],
}

# ---- The Waystone close-ups: daytime and dormant, or dusk with the stone awake and glowing
WAYSTONE_FX = [
    ('tree', ('e', 96, 232, 104, 108), 'green'),
    ('tree', ('e', 492, 252, 30, 44), 'green', {'amp': 0.6}),
    ('grass', [0, 318, 210, 404], 'green'),
    ('none', [0, 232, 99, 392]),  # the grey-green house on the left stays put
    ('tree', [84, 376, 188, 446], 'green', {'amp': 0.3}),
    ('tree', [496, 404, 636, 478], 'green', {'amp': 0.3}),
    ('tree', [0, 406, 50, 470], 'green', {'amp': 0.3}),
]

SCENES = {
    'village/workshop.webp': WORKSHOP,
    'village/lodge.webp': LODGE,
    'village/glasshouse.webp': GLASSHOUSE,
    'village/waystone_dormant.webp': {
        'fx': WAYSTONE_FX,
        'emit': [
            {'t': 'leaves', 'x': 0, 'y': 120, 'w': 667, 'h': 360, 'n': 2},
            {'t': 'motes', 'kind': 'pollen', 'x': 0, 'y': 300, 'w': 667, 'h': 260, 'n': 6, 'c': '#fff6c8', 's': 3},
        ],
    },
    'village/waystone_restored.webp': {
        'fx': WAYSTONE_FX + [
            ('crystal', [(236, 186), (414, 186), (414, 470), (236, 470)], 'bright'),
            ('crystal', [(196, 466), (472, 466), (472, 540), (196, 540)], 'bright'),
            ('lamp', [516, 152, 582, 214], 'bright'),
            ('lamp', [236, 258, 268, 306], 'warm'),
            ('lamp', [402, 258, 432, 306], 'warm'),
            ('lamp', [628, 280, 667, 340], 'warm'),
        ],
        'emit': [
            {'t': 'glow', 'x': 334, 'y': 320, 'r': 180, 'c': '#e2ffc8', 'a': 0.4, 'kind': 'crystal'},
            {'t': 'glow', 'x': 334, 'y': 505, 'r': 150, 'c': '#a8f4ff', 'a': 0.35, 'kind': 'crystal'},
            {'t': 'glow', 'x': 552, 'y': 182, 'r': 46, 'c': '#ffd27a', 'a': 0.45, 'kind': 'lamp'},
            {'t': 'glow', 'x': 252, 'y': 282, 'r': 24, 'c': '#ffc561', 'a': 0.35, 'kind': 'lamp'},
            {'t': 'glow', 'x': 417, 'y': 282, 'r': 24, 'c': '#ffc561', 'a': 0.35, 'kind': 'lamp'},
            {'t': 'glow', 'x': 650, 'y': 310, 'r': 26, 'c': '#ffc561', 'a': 0.35, 'kind': 'lamp'},
            {'t': 'motes', 'kind': 'spark', 'x': 210, 'y': 160, 'w': 250, 'h': 360, 'n': 12, 'c': '#f4ffd0', 's': 4},
            {'t': 'motes', 'kind': 'firefly', 'x': 0, 'y': 60, 'w': 667, 'h': 420, 'n': 10, 'c': '#fff6a0', 's': 4},
        ],
    },
}

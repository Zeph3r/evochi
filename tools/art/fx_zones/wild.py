"""The wild: the Nest's meadow, the Market and the welcome scene (layered habitats, 780 x 1688, the
pet stands between mid and near), and the Lumen Trails scenes (780 x 867) with their battle
backdrops (878 x 1316) and battle foregrounds."""

# ---- habitats ---------------------------------------------------------------------------------
MEADOW = {
    # blurred cliffs, two far canopies and the lake
    'habitats/meadow_far.webp': {
        'fx': [
            ('tree', ('e', 55, 62, 82, 82), 'green', {'amp': 0.35}),
            ('tree', ('e', 622, 100, 92, 112), 'green', {'amp': 0.35}),
            ('still', [0, 336, 780, 466], 'water'),
        ],
    },
    # the big tree top-left, the lawn, the fence (left as is) and the lantern on the house wall
    'habitats/meadow_mid.webp': {
        'fx': [
            ('grass', [0, 420, 780, 842], 'green'),
            ('tree', ('e', 78, 108, 112, 142), 'green', {'amp': 0.9}),
            ('cloth', [655, 30, 724, 120], 'cloth', {'amp': 0.35}),  # the red banner on the wall
            ('cloth', [655, 196, 724, 306], 'cloth', {'amp': 0.35}),
            ('lamp', [645, 122, 700, 200], 'bright'),
        ],
        'emit': [
            {'t': 'glow', 'x': 672, 'y': 156, 'r': 62, 'c': '#ffe07a', 'kind': 'lamp', 'a': 0.42},
            {'t': 'leaves', 'x': 0, 'y': 120, 'w': 780, 'h': 560, 'n': 2},
        ],
    },
    # big foreground blades and daisies: rooted, so their tips move most
    'habitats/meadow_near.webp': {
        'fx': [
            ('grass', [0, 656, 780, 1688], 'green'),
            ('blades', [0, 656, 780, 860], 'green', {'fade': 0.3}),
            ('blades', [0, 656, 200, 1500], 'green', {'fade': 0.1}),
            ('blades', [560, 656, 780, 1500], 'green', {'fade': 0.1}),
            ('blades', [0, 680, 150, 1070], 'all', {'fade': 0.2}),
            ('blades', [580, 690, 780, 960], 'all', {'fade': 0.2}),
        ],
        'emit': [
            {'t': 'motes', 'kind': 'pollen', 'x': 0, 'y': 700, 'w': 780, 'h': 560, 'n': 6, 'c': '#fff6c8', 's': 5},
        ],
    },
}

MARKET = {
    'habitats/market_far.webp': {
        'fx': [
            ('tree', ('e', 62, 165, 72, 72), 'green', {'amp': 0.35}),
            ('tree', ('e', 600, 92, 112, 102), 'green', {'amp': 0.35}),
            ('fall', [738, 95, 780, 246], 'waterfall'),
        ],
    },
    # banners and bunting ripple, the awning barely; the corner lanterns breathe
    'habitats/market_mid.webp': {
        'fx': [
            ('cloth', [55, 0, 580, 96], 'all', {'amp': 0.7}),
            ('cloth', [20, 55, 206, 310], 'all', {'amp': 0.6}),
            ('cloth', [574, 55, 766, 310], 'all', {'amp': 0.6}),
            ('cloth', [195, 118, 586, 206], 'all', {'amp': 0.3}),
            ('tree', ('e', 130, 642, 72, 76), 'green', {'amp': 0.45}),
            ('tree', ('e', 662, 632, 86, 76), 'green', {'amp': 0.45}),
            ('lamp', [0, 0, 62, 72], 'bright'),
            ('lamp', [718, 0, 780, 72], 'bright'),
        ],
        'emit': [
            {'t': 'glow', 'x': 26, 'y': 30, 'r': 58, 'c': '#ffe28a', 'kind': 'lamp', 'a': 0.4},
            {'t': 'glow', 'x': 754, 'y': 30, 'r': 58, 'c': '#ffe28a', 'kind': 'lamp', 'a': 0.4},
            {'t': 'motes', 'kind': 'dust', 'x': 0, 'y': 320, 'w': 780, 'h': 480, 'n': 8, 'c': '#fff4d6', 's': 3},
        ],
    },
}

WELCOME = {
    'habitats/welcome_far.webp': {
        'fx': [
            ('tree', ('e', 86, 226, 62, 66), 'green', {'amp': 0.35}),
            ('tree', ('e', 230, 348, 86, 112), 'green', {'amp': 0.35}),
            ('tree', ('e', 326, 546, 86, 86), 'green', {'amp': 0.35}),
            ('tree', ('e', 482, 492, 90, 76), 'green', {'amp': 0.35}),
            ('still', [0, 655, 780, 762], 'water'),
        ],
    },
    'habitats/welcome_mid.webp': {
        'fx': [
            ('grass', [0, 725, 780, 1010], 'green'),
            ('tree', [0, 205, 194, 506], 'green', {'amp': 0.8}),
            ('lamp', [548, 212, 640, 305], 'bright'),
        ],
        'emit': [
            {'t': 'glow', 'x': 595, 'y': 258, 'r': 72, 'c': '#ffe07a', 'kind': 'lamp', 'a': 0.42},
            {'t': 'leaves', 'x': 0, 'y': 220, 'w': 780, 'h': 560, 'n': 2},
        ],
    },
    'habitats/welcome_near.webp': {
        'fx': [
            ('grass', [0, 880, 780, 1560], 'green'),
            ('blades', [0, 880, 780, 1060], 'green', {'fade': 0.3}),
            ('blades', [0, 880, 180, 1500], 'green', {'fade': 0.1}),
            ('blades', [560, 880, 780, 1500], 'green', {'fade': 0.1}),
            ('blades', [0, 890, 90, 1060], 'all', {'fade': 0.25}),
            ('blades', [555, 900, 780, 1120], 'all', {'fade': 0.25}),
        ],
        'emit': [
            {'t': 'motes', 'kind': 'pollen', 'x': 0, 'y': 920, 'w': 780, 'h': 560, 'n': 6, 'c': '#fff6c8', 's': 5},
        ],
    },
}

# ---- Lumen Trails: the discovery scenes -------------------------------------------------------
# mossy ruins: the waterfall left, canopies on the ridge, the mossy arch (stays put) with mint runes
RUINS_TREES = [
    ('tree', ('e', 45, 318, 72, 140), 'green'),
    ('tree', ('e', 140, 170, 70, 40), 'green', {'amp': 0.6}),
    ('tree', ('e', 310, 186, 82, 46), 'green', {'amp': 0.6}),
    ('tree', ('e', 478, 168, 42, 36), 'green', {'amp': 0.6}),
    ('tree', ('e', 540, 135, 30, 30), 'green', {'amp': 0.6}),
    ('tree', ('e', 642, 176, 86, 56), 'green', {'amp': 0.6}),
    ('tree', ('e', 708, 320, 88, 118), 'green'),
]
RUINS_FX = [
    ('grass', [0, 470, 780, 867], 'green'),
] + RUINS_TREES + [
    ('none', [200, 205, 592, 566]),  # the arch: stone and moss stay put
    ('grass', [292, 470, 492, 566], 'green'),  # the lawn seen through it
    ('fall', [112, 208, 212, 484], 'waterfall'),
]
RUINS_EMIT = [
    {'t': 'smoke', 'kind': 'steam', 'x': 172, 'y': 478, 'n': 4, 's': 10, 'h': 48, 'drift': 12, 'c': '#ffffff', 'a': 0.32},
    {'t': 'leaves', 'x': 0, 'y': 150, 'w': 780, 'h': 460, 'n': 3},
]

# sentinel gate at dusk: dark canopies, violet crystals, fireflies
GATE_FX = [  # dusk: the canopies are too dark for the green key, so the big ones take 'all'
    ('tree', ('e', 45, 318, 55, 135), 'all', {'amp': 0.55}),
    ('tree', ('e', 180, 190, 46, 36), 'green', {'amp': 0.6}),
    ('tree', ('e', 370, 170, 46, 36), 'green', {'amp': 0.6}),
    ('tree', ('e', 515, 195, 50, 40), 'green', {'amp': 0.6}),
    ('tree', ('e', 608, 205, 36, 40), 'green', {'amp': 0.6}),
    ('tree', ('e', 746, 236, 40, 66), 'green', {'amp': 0.6}),
    ('tree', ('e', 695, 332, 84, 92), 'all', {'amp': 0.55}),
    ('none', [185, 172, 606, 532]),  # the gate itself
    ('fall', [100, 226, 168, 306], 'waterfall'),
    ('crystal', [60, 440, 780, 780], 'crystal'),
]

TRAILS = {
    'trails/mossy_ruins.webp': {
        'fx': RUINS_FX + [
            ('crystal', [228, 306, 252, 340], 'bright'),
            ('crystal', [228, 372, 252, 418], 'bright'),
            ('crystal', [228, 450, 252, 492], 'bright'),
            ('crystal', [526, 306, 552, 340], 'bright'),
            ('crystal', [526, 372, 552, 418], 'bright'),
            ('crystal', [526, 450, 552, 492], 'bright'),
        ],
        'emit': RUINS_EMIT + [
            {'t': 'glow', 'x': 390, 'y': 250, 'r': 72, 'c': '#fffbe0', 'kind': 'sun', 'a': 0.35},
            {'t': 'glow', 'x': 240, 'y': 400, 'r': 34, 'c': '#bfffe6', 'kind': 'crystal', 'a': 0.3},
            {'t': 'glow', 'x': 539, 'y': 400, 'r': 34, 'c': '#bfffe6', 'kind': 'crystal', 'a': 0.3},
            {'t': 'motes', 'kind': 'spark', 'x': 222, 'y': 300, 'w': 340, 'h': 200, 'n': 5, 'c': '#d8fff0', 's': 3},
            {'t': 'motes', 'kind': 'pollen', 'x': 0, 'y': 480, 'w': 780, 'h': 360, 'n': 7, 'c': '#fff6c8', 's': 3},
        ],
    },
    # the corrupted ruins: the same place, dimmer, violet crystals and tendrils pulse
    'trails/mossy_ruins_hollow.webp': {
        'fx': RUINS_FX + [
            ('crystal', [280, 280, 500, 520], 'crystal'),  # the tendrils over the arch
            ('crystal', [100, 440, 780, 760], 'crystal'),
        ],
        'emit': RUINS_EMIT[:1] + [
            {'t': 'leaves', 'x': 0, 'y': 150, 'w': 780, 'h': 460, 'n': 1},
            {'t': 'glow', 'x': 160, 'y': 512, 'r': 52, 'c': '#c9a0ff', 'kind': 'crystal', 'a': 0.4},
            {'t': 'glow', 'x': 595, 'y': 530, 'r': 62, 'c': '#c9a0ff', 'kind': 'crystal', 'a': 0.4},
            {'t': 'glow', 'x': 395, 'y': 650, 'r': 40, 'c': '#c9a0ff', 'kind': 'crystal', 'a': 0.35},
            {'t': 'glow', 'x': 722, 'y': 560, 'r': 40, 'c': '#c9a0ff', 'kind': 'crystal', 'a': 0.35},
            {'t': 'motes', 'kind': 'spark', 'x': 100, 'y': 430, 'w': 640, 'h': 300, 'n': 8, 'c': '#e2c4ff', 's': 3},
        ],
    },
    'trails/sentinel_gate.webp': {
        'fx': GATE_FX,
        'emit': [
            {'t': 'glow', 'x': 138, 'y': 526, 'r': 56, 'c': '#c58cff', 'kind': 'crystal', 'a': 0.45},
            {'t': 'glow', 'x': 390, 'y': 484, 'r': 44, 'c': '#c58cff', 'kind': 'crystal', 'a': 0.45},
            {'t': 'glow', 'x': 645, 'y': 510, 'r': 60, 'c': '#c58cff', 'kind': 'crystal', 'a': 0.45},
            {'t': 'glow', 'x': 145, 'y': 698, 'r': 56, 'c': '#d6b4ff', 'kind': 'crystal', 'a': 0.4},
            {'t': 'glow', 'x': 530, 'y': 505, 'r': 52, 'c': '#ffd6ff', 'kind': 'crystal', 'a': 0.45},
            {'t': 'glow', 'x': 250, 'y': 505, 'r': 40, 'c': '#ffd6ff', 'kind': 'crystal', 'a': 0.4},
            {'t': 'motes', 'kind': 'firefly', 'x': 0, 'y': 150, 'w': 780, 'h': 520, 'n': 14, 'c': '#e8ff9a', 's': 4},
            {'t': 'motes', 'kind': 'spark', 'x': 80, 'y': 440, 'w': 620, 'h': 300, 'n': 6, 'c': '#e2c4ff', 's': 3},
            {'t': 'leaves', 'x': 0, 'y': 150, 'w': 780, 'h': 420, 'n': 1},
        ],
    },
}

# ---- battle backdrops (878 x 1316) and their blurred foregrounds -------------------------------
BATTLE = {
    'trails/mossy_ruins_battle.webp': {
        'fx': [
            ('grass', [0, 700, 878, 1316], 'green'),
            ('tree', ('e', 95, 470, 122, 232), 'green'),
            ('tree', ('e', 100, 850, 112, 82), 'green', {'amp': 0.5}),
            ('tree', ('e', 742, 862, 150, 72), 'green', {'amp': 0.5}),
            ('none', [205, 100, 878, 700]),  # the arch
            ('crystal', [238, 296, 278, 344], 'bright'),
            ('crystal', [238, 436, 278, 506], 'bright'),
            ('crystal', [238, 596, 278, 666], 'bright'),
        ],
        'emit': [
            {'t': 'glow', 'x': 600, 'y': 110, 'r': 112, 'c': '#fff8d8', 'kind': 'sun', 'a': 0.35},
            {'t': 'glow', 'x': 258, 'y': 470, 'r': 40, 'c': '#bfffe6', 'kind': 'crystal', 'a': 0.3},
            {'t': 'motes', 'kind': 'spark', 'x': 228, 'y': 280, 'w': 70, 'h': 420, 'n': 5, 'c': '#d8fff0', 's': 4},
            {'t': 'motes', 'kind': 'pollen', 'x': 0, 'y': 600, 'w': 878, 'h': 500, 'n': 8, 'c': '#fff6c8', 's': 4},
            {'t': 'leaves', 'x': 0, 'y': 100, 'w': 878, 'h': 700, 'n': 3},
        ],
    },
    'trails/mossy_ruins_battle_fg.webp': {
        'fx': [
            ('tree', [477, 0, 878, 285], 'all', {'amp': 0.9}),
            ('tree', [419, 1039, 878, 1316], 'all', {'amp': 0.45}),
        ],
    },
    'trails/mossy_ruins_hollow_battle.webp': {
        'fx': [
            ('grass', [0, 800, 878, 1316], 'green'),
            ('tree', ('e', 95, 430, 122, 202), 'green'),
            ('none', [205, 100, 878, 700]),
            ('crystal', [0, 250, 878, 1000], 'crystal'),
        ],
        'emit': [
            {'t': 'glow', 'x': 60, 'y': 720, 'r': 92, 'c': '#d9b0ff', 'kind': 'crystal', 'a': 0.45},
            {'t': 'glow', 'x': 430, 'y': 760, 'r': 62, 'c': '#d9b0ff', 'kind': 'crystal', 'a': 0.4},
            {'t': 'glow', 'x': 660, 'y': 752, 'r': 62, 'c': '#d9b0ff', 'kind': 'crystal', 'a': 0.4},
            {'t': 'glow', 'x': 822, 'y': 760, 'r': 72, 'c': '#d9b0ff', 'kind': 'crystal', 'a': 0.4},
            {'t': 'motes', 'kind': 'spark', 'x': 0, 'y': 600, 'w': 878, 'h': 400, 'n': 10, 'c': '#e2c4ff', 's': 4},
            {'t': 'leaves', 'x': 0, 'y': 100, 'w': 878, 'h': 700, 'n': 1},
        ],
    },
    'trails/mossy_ruins_hollow_battle_fg.webp': {
        'fx': [
            ('tree', [485, 0, 878, 265], 'all', {'amp': 0.8}),
            ('crystal', [641, 920, 878, 1316], 'crystal'),
        ],
        'emit': [
            {'t': 'glow', 'x': 800, 'y': 1150, 'r': 120, 'c': '#c99cff', 'kind': 'crystal', 'a': 0.35},
        ],
    },
    'trails/sentinel_gate_battle.webp': {
        'fx': [
            ('tree', ('e', 75, 690, 70, 95), 'all', {'amp': 0.55}),
            ('tree', ('e', 495, 655, 60, 45), 'all', {'amp': 0.5}),
            ('tree', ('e', 645, 665, 55, 38), 'all', {'amp': 0.5}),
            ('tree', ('e', 810, 615, 70, 55), 'all', {'amp': 0.5}),
            ('none', [150, 140, 400, 960]),  # the pillar
            ('none', [200, 90, 878, 420]),   # the beam
            ('crystal', [228, 530, 268, 585], 'water'),  # cyan runes on the pillar
            ('crystal', [228, 676, 268, 725], 'water'),
            ('crystal', [222, 826, 268, 875], 'water'),
            ('crystal', [285, 860, 345, 935], 'crystal'),
            ('crystal', [595, 820, 695, 935], 'crystal'),
        ],
        'emit': [
            {'t': 'glow', 'x': 318, 'y': 895, 'r': 62, 'c': '#d8b0ff', 'kind': 'crystal', 'a': 0.5},
            {'t': 'glow', 'x': 645, 'y': 880, 'r': 82, 'c': '#d8b0ff', 'kind': 'crystal', 'a': 0.5},
            {'t': 'glow', 'x': 246, 'y': 556, 'r': 30, 'c': '#9fe8ff', 'kind': 'crystal', 'a': 0.35},
            {'t': 'glow', 'x': 246, 'y': 700, 'r': 30, 'c': '#9fe8ff', 'kind': 'crystal', 'a': 0.35},
            {'t': 'glow', 'x': 244, 'y': 850, 'r': 30, 'c': '#9fe8ff', 'kind': 'crystal', 'a': 0.35},
            {'t': 'motes', 'kind': 'firefly', 'x': 0, 'y': 450, 'w': 878, 'h': 550, 'n': 12, 'c': '#e8ff9a', 's': 5},
        ],
    },
    'trails/sentinel_gate_battle_fg.webp': {
        'fx': [
            ('tree', [483, 0, 878, 279], 'all', {'amp': 0.8}),
            ('crystal', [639, 816, 878, 1316], 'crystal'),
        ],
        'emit': [
            {'t': 'glow', 'x': 790, 'y': 1100, 'r': 120, 'c': '#c99cff', 'kind': 'crystal', 'a': 0.4},
        ],
    },
}

SCENES = {**MEADOW, **MARKET, **WELCOME, **TRAILS, **BATTLE}

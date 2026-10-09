"""Canonical Evochi colour tokens (from the style guide, sections 04 and 05)."""
import numpy as np


def _hx(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float)


def mixh(a, b, t):
    c = _hx(a) * (1 - t) + _hx(b) * t
    c = np.clip(np.round(c), 0, 255).astype(int)
    return '#%02X%02X%02X' % tuple(c)


def darken(a, f):
    c = np.clip(np.round(_hx(a) * f), 0, 255).astype(int)
    return '#%02X%02X%02X' % tuple(c)


TOKENS = {
    'ink-900': '#3B2923', 'ink-700': '#684C3C', 'ink-500': '#8E7462',
    'cream-50': '#FFF9F0', 'cream-100': '#FFF0DE', 'cream-200': '#F4E2CD',
    'parchment-100': '#F8EBDD', 'parchment-200': '#EED9C2', 'outline-400': '#C9A78C',
    'shadow-600': '#76513B', 'feet-500': '#926244', 'feet-700': '#6D4735', 'claw-100': '#FFF3E7',
    'gold-100': '#FFE5A2', 'gold-300': '#F9CA70', 'gold-500': '#F4B84E', 'gold-700': '#C8832C',
    'gold-900': '#80531F', 'meadow-100': '#E5F2CF', 'meadow-300': '#B7D98B', 'meadow-500': '#82B75E',
    'meadow-700': '#477B3A', 'sky-100': '#D6EDFB', 'sky-400': '#84C4E8', 'water-600': '#399CC7',
    'scene-depth': '#6E9168', 'coral-300': '#F5B0A0', 'coral-500': '#EC947C', 'red-500': '#D85F51',
    'amber-500': '#DB9942', 'violet-400': '#AA8BCF', 'gem-500': '#39BDE3', 'dim-overlay': '#201B17',
}

# variant: shell, pattern, crest, cheeks, feet, foot shadow, eyes, claws
_VARIANTS = {
    'amber': ('#FFF0DE', '#F9CA70', '#F4B84E', '#EC947C', '#926244', '#6D4735', '#282725', '#FFF3E7'),
    'forest': ('#F1F4E5', '#A5CD82', '#78B55B', '#EAA48E', '#816448', '#604835', '#282725', '#FFF3E7'),
    'coral': ('#FFF0E8', '#F3A78D', '#DB745B', '#F39C8B', '#946147', '#6D4539', '#282725', '#FFF3E7'),
    'ocean': ('#F0F7FB', '#97CDEB', '#4C9BCC', '#ECA09C', '#766473', '#524957', '#282725', '#F5F3EF'),
    'amethyst': ('#F6EEFB', '#C8B1E4', '#9975C9', '#E5A1B8', '#806077', '#5D455A', '#282725', '#FFF2F6'),
    'obsidian': ('#3E414B', '#6B6473', '#DD6A5B', '#E9827C', '#59464A', '#352C32', '#FFF0E3', '#E9DCD2'),
}

VARIANT_ORDER = ['amber', 'forest', 'coral', 'ocean', 'amethyst', 'obsidian']
VARIANT_NAMES = {'amber': 'Amber', 'forest': 'Forest', 'coral': 'Coral', 'ocean': 'Ocean',
                 'amethyst': 'Amethyst', 'obsidian': 'Obsidian'}


def palette(variant: str) -> dict:
    shell, pattern, crest, cheek, feet, feet_sh, eye, claw = _VARIANTS[variant]
    dark = variant == 'obsidian'
    p = {
        'shell': shell,
        'belly': mixh(shell, '#FFFFFF', 0.25) if not dark else mixh(shell, '#8A8695', 0.35),
        'pattern': pattern,
        'crest': crest,
        'crest_hi': '#FFE5A2' if variant == 'amber' else mixh(crest, '#FFFFFF', 0.42),
        'crest_mid': mixh(crest, '#FFFFFF', 0.26),
        'crest_lo': '#C8832C' if variant == 'amber' else darken(crest, 0.80),
        'pattern_hi': mixh(pattern, '#FFFFFF', 0.45),
        'pattern_lo': darken(pattern, 0.86),
        'cheek': cheek,
        'feet': feet,
        'feet_shade': feet_sh,
        'eye': eye,
        'eye_hi': '#FFFFFF' if not dark else '#3E414B',
        'claw': claw,
        'mouth': '#5B3A31' if not dark else '#F2E4D8',
        'mouth_in': '#8C3B36' if not dark else '#2A2228',
        'tongue': mixh(cheek, '#FFFFFF', 0.1),
        'brow': mixh(eye, shell, 0.15),
        'outline': '#3B2923' if not dark else '#1F1A1E',
        'tear': '#84C4E8',
        'sweat': '#9BD3F0',
    }
    return p


def muted(p: dict, amount=0.45, tint='#B8B0A0') -> dict:
    """Desaturated / dimmed palette for the sick and memorial states."""
    out = {}
    for k, v in p.items():
        c = _hx(v)
        g = c @ np.array([0.299, 0.587, 0.114])
        c2 = c * (1 - amount) + g * amount
        c2 = c2 * 0.9 + _hx(tint) * 0.1
        c2 = np.clip(np.round(c2), 0, 255).astype(int)
        out[k] = '#%02X%02X%02X' % tuple(c2)
    out['eye'] = p['eye']
    out['outline'] = p['outline']
    return out


ACCESSORY = {
    'leaf': '#6FB24E', 'leaf_hi': '#9BD16B', 'leaf_lo': '#3F7D35', 'leaf_vein': '#4D8E3B',
    'flower': '#FFFDF6', 'flower_c': '#F4B84E',
    'gold': '#F4C04E', 'gold_hi': '#FFE5A2', 'gold_lo': '#C8832C', 'ruby': '#D8434A', 'ruby_hi': '#FF8A8A',
    'straw': '#E2B866', 'straw_hi': '#F6D894', 'straw_lo': '#B98A3E', 'band': '#4F8C3C',
    'leather': '#8A5634', 'leather_hi': '#B07444', 'leather_lo': '#5E3A24',
    'red': '#C8443C', 'red_hi': '#E2645A', 'red_lo': '#8E2E2A', 'buckle': '#E9C46A',
    'blue': '#4D8FD8', 'blue_hi': '#86B9EE', 'blue_lo': '#2F5FA3', 'white': '#F7F3EA',
    'butter': '#F6C24E', 'butter_lo': '#D8962E', 'butter_dot': '#7A4A22',
    'bedroll': '#4E8C4C', 'bedroll_hi': '#78B06A',
    'goggle': '#2E3640', 'goggle_lens': '#5C7FA0', 'feather': '#F2EBD9',
}

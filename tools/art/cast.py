"""The cast of Evochi so far, in one place: every character the game draws, with its colourways or
variants, its palette and the expressions it can wear. turnarounds.py draws their sheets from this and
cast_blend.py builds their Blender files.

    Evochi        Eggling, Juvenile, Elder (characters.py), each in the six colourways
    villagers     Mira, Bram, Pip, Alder (village_npcs.py), Sher (wilds_npcs.py), Flint (flint.py)
    the Wilds     Thornling, Sporecap, Petalune, Hollow Sprout, and the guardians Briarback and the
                  Forgotten Sentinel (wilds_foes.py), each Hollow and calmed
"""
from __future__ import annotations

import os
import sys
from dataclasses import dataclass, field

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


@dataclass
class Variant:
    label: str                 # 'Amber', 'Hollow', ...
    model: object              # voxel.Model
    pal: dict                  # material palette ({} when the model's materials are colours)
    pal_key: str = ''
    ch: object = None          # the Character (faces, patterns, parts, pivots, whiskers), None for creatures


@dataclass
class CastMember:
    key: str
    name: str
    kind: str                  # 'evochi' | 'villager' | 'creature'
    blurb: str
    variants: list = field(default_factory=list)
    expressions: dict = field(default_factory=dict)   # shown name -> the face painter's expression


EVOCHI_EXPR = {'default': 'default', 'happy': 'happy', 'curious': 'curious', 'surprised': 'surprised',
               'determined': 'determined', 'sad': 'sad', 'sleepy': 'sleepy', 'excited': 'excited', 'blink': 'blink'}
CREATURES = [('thornling', 'Thornling', 'a prickly little Hollow that curls into a ball'),
             ('sporecap', 'Sporecap', 'a hopping mushroom Hollow that puffs spores'),
             ('petalune', 'Petalune', 'a shy flower creature of the Thicket'),
             ('hollow_sprout', 'Hollow Sprout', 'a lashing sprout gone Hollow'),
             ('briarback', 'Briarback', 'the Thicket\'s antlered guardian (boss)'),
             ('sentinel', 'Forgotten Sentinel', 'the stone guardian of the Sentinel\'s Gate (boss)')]


def evochi(stage):
    from characters import build
    from palettes import palette, VARIANT_ORDER, VARIANT_NAMES
    ch = build(stage)
    name = {1: 'Eggling', 2: 'Juvenile', 3: 'Elder'}[stage]
    blurb = {1: 'stage 1: the hatchling', 2: 'stage 2', 3: 'stage 3'}[stage]
    vs = [Variant(VARIANT_NAMES[v], ch.model, dict(palette(v)), v, ch) for v in VARIANT_ORDER]
    return CastMember('evochi_%s' % name.lower(), name, 'evochi', blurb, vs, dict(EVOCHI_EXPR))


def villager(key):
    from village_npcs import NPC_EXPRESSIONS, INK
    from village_npc_render import npc_palette
    if key == 'flint':
        from flint import flint, flint_palette
        ch = flint()
        return CastMember('flint', 'Flint', 'villager', 'the old Obsidian Elder who keeps the mines',
                          [Variant('Flint', ch.model, flint_palette(), 'flint', ch)],
                          {'default': 'default', 'happy': 'happy', 'thinking': 'thinking', 'surprised': 'surprised', 'blink': 'blink'})
    if key == 'sher':
        from wilds_npcs import build_sher
        ch, blurb = build_sher(), 'an orange-and-white cat of the Lumen Wilds'
    else:
        import village_npcs as V
        ch = getattr(V, 'build_' + key)()
        blurb = {'mira': 'the Glasshouse gardener', 'bram': 'the lampwright at the forge',
                 'pip': 'the flustered young letter carrier', 'alder': 'the Trail Guild\'s elder'}[key]
    pal = npc_palette(ch, INK)
    return CastMember(key, key.capitalize(), 'villager', blurb, [Variant(key.capitalize(), ch.model, pal, key, ch)],
                      dict(NPC_EXPRESSIONS, blink='blink'))


def creature(key, name, blurb):
    from wilds_foes import FOES
    foe = FOES[key]()
    vs = []
    for v in foe.variants:
        M, anc = foe.build(None, v)
        vs.append(Variant({'hollow': 'Hollow', 'calm': 'Calmed'}.get(v, v.title()), M, {}, v, None))
    return CastMember(key, name, 'creature', blurb, vs, {})


def cast(only=None):
    """every member, in the order the sheets and the lineup show them"""
    makers = [lambda: evochi(1), lambda: evochi(2), lambda: evochi(3)]
    makers += [(lambda k=k: villager(k)) for k in ('mira', 'bram', 'pip', 'alder', 'sher', 'flint')]
    makers += [(lambda k=k, n=n, b=b: creature(k, n, b)) for k, n, b in CREATURES]
    keys = (['evochi_eggling', 'evochi_juvenile', 'evochi_elder', 'mira', 'bram', 'pip', 'alder', 'sher', 'flint']
            + [k for k, _, _ in CREATURES])
    return [mk() for k, mk in zip(keys, makers) if not only or k in only]


if __name__ == '__main__':
    for m in cast():
        print('%-18s %-9s %-34s %s' % (m.name, m.kind, ', '.join(v.label for v in m.variants), m.blurb))

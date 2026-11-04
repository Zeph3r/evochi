"""The Garden's two sounds, on the soundtrack's samples (VSCO 2 CE):
  harvest_pop      the crop popping out of its bed: a marimba hop up a fifth, a pizzicato tip on top
  golden_harvest   a Golden harvest: a glockenspiel run up, a D major sparkle, a soft low pluck under it

    python3 tools/music/garden_sfx.py flutter
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vsco  # noqa: E402
from vsco import note_midi as m  # noqa: E402


def pop():
    mx = vsco.Mix(1.4)
    mx.note('marimba', 0.0, 0.2, m('D5'), 0.62, pan=-0.1, human=0)
    mx.note('marimba', 0.07, 0.25, m('A5'), 0.7, pan=0.1, human=0)
    mx.note('pizz', 0.11, 0.2, m('D6'), 0.5, pan=0.15, human=0)
    mx.send['main'] = 0.18
    return mx.render(rt=1.2)


def golden():
    mx = vsco.Mix(3.2)
    mx.sfx('glock_up', 0.0, gain=0.55, take=0)
    for i, n in enumerate(['D6', 'F#6', 'A6', 'D7']):
        mx.note('glock', 0.42 + i * 0.075, 0.6, m(n), 0.62 - i * 0.04, pan=-0.2 + i * 0.13, human=0)
    mx.note('glock', 0.78, 1.4, m('A6'), 0.45, pan=0.2, human=0)
    mx.note('glock', 0.78, 1.4, m('F#6'), 0.4, pan=-0.2, human=0)
    mx.note('cello_pizz', 0.42, 0.6, m('D3'), 0.55, human=0)
    mx.note('harp', 0.42, 1.2, m('A4'), 0.4, pan=-0.1, human=0)
    mx.note('harp', 0.46, 1.2, m('D5'), 0.4, pan=0.1, human=0)
    return mx.render(rt=1.8)


if __name__ == '__main__':
    game = os.path.abspath(sys.argv[1])
    mp = os.path.join(game, 'assets', 'art', 'manifest.json')
    man = json.load(open(mp))
    for name, fn, lufs in (('harvest_pop', pop, -20.0), ('golden_harvest', golden, -18.0)):
        x = fn()
        path = vsco.master(x, os.path.join(game, 'assets', 'audio', 'sfx', name + '.mp3'), lufs=lufs, fade_out=0.3, vbr=4)
        man['audio'][name] = 'sfx/' + name + '.mp3'
        print(name, os.path.getsize(path) // 1024, 'KB')
    json.dump(man, open(mp, 'w'), indent=1)

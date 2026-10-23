"""The walkable village's first playable piece (village_walk_slice.py): its living-scene zones, worked
out from the 3D layout like the concept's (village_mock/fx_village_walk.py, which this borrows)."""
import importlib.util
import os

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('fx_village_walk', os.path.join(_here, '..', 'village_mock', 'fx_village_walk.py'))
_fx = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_fx)

SCENES = {'village/walk_slice.webp': _fx.zones('slice')}

# Nest hub mock-ups

Pictures of the planned nest hub, composited (PIL) from the real art at the game's layout numbers. They
show the plan; they are not the game.

    python3 ../hub_scene.py OUT --scale 0.6667 [--ruined]          # the backdrop layers + anchors + board
    python3 compose.py OUT restored PREFIX [--panel mockup]         # PREFIX_preview / _map / _scene .png
    python3 storyboard.py OUT restored sheet.jpg                    # the idle screen + the tap, beat by beat

`--panel mockup` lays out the panel as the mockup does (steps, Pet/Play/Inspect, Evolution Family);
without it, today's panel (discovery chip and nameplate too).

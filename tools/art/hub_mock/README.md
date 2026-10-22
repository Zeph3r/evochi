# Nest hub mock-ups

Pictures of the planned nest hub, composited (PIL) from the real art at the game's layout numbers. They
show the plan; they are not the game.

The Blender-lit hub (the one to build):

    python3 ../hub_blender.py OUT --preview [--ruined]               # hub_<state>.png + anchors json
    python3 blender_storyboard.py OUT restored sheet.jpg             # the idle screen + the tap, beat by beat
    python3 blender_preview.py OUT restored shot.jpg [--glow home]   # one frame

hubframe.py holds the frame (scene, Evochi, lettered signs, header and panel, zoom, fade).

The first try, drawn with the meadow's flat renderer (kept for reference):

    python3 ../hub_scene.py OUT --scale 0.6667 [--ruined]
    python3 compose.py OUT restored PREFIX [--panel mockup]
    python3 storyboard.py OUT restored sheet.jpg

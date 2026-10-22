# Shorts from the real game

The Wilds Shorts are recorded from the Flutter game itself, not mocked up: the game runs under a fixed
clock in a test harness, an autopilot plays, and every frame is an exact 1/30 s step at 1080x1920 however
long a frame takes to capture.

1. **Record** (on the PC with Flutter): `flutter/tool/shorts/record_test.dart` with the scripts in
   `flutter/tool/shorts/shorts.dart` (clips, beats, captions, end card).
   ```
   flutter test tool/shorts/record_test.dart --dart-define=SHORTS=sentinel,briarback
   ```
   On the PC the helper does this when `_transfer/run_shorts.flag` exists (its first line names the
   Shorts) and `_transfer/run_check.flag` is dropped. A run that goes wrong stops at the next frame if
   `_transfer/stop_shorts.flag` appears. Writes `_shorts/<id>/frames.rgba` (raw frames), `cues.json` (the
   game's sounds and music calls, timed) and `meta.json`.
   The living-scene shader is left off while recording (it costs seconds a frame in software);
   `--dart-define=SHORTS_FX=true` keeps it. `--dart-define=SHORTS_SCALE=2` records 720x1280 (upscaled).
2. **Encode**: `python3 encode.py SHORT_DIR GAME_ROOT OUT.mp4` lays the sounds at their moments over the
   Short's music bed (or the music the game asked for) and encodes H.264 + AAC.

The game side: `AudioService.record` logs sounds instead of playing them; `WildsScreen.director` lets the
autopilot steer; `WildsScreen.current` reaches the screen's shortcuts; `Raid.holdSentinel` keeps the
Sentinel asleep until the walk-in.

Shorts: `sentinel` (its cinematic, the shield, the Lantern Tonic, restored), `briarback` (its cinematic, a
signature finish), `deep` (fresh floors, the way down, a Hollow Surge), `signatures` (all six Elder moves).

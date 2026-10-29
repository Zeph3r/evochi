# Village Square: final (not yet in the game)

`mus_village.ogg` is the game's loop (Ogg Vorbis, sample-exact, so it repeats with no gap); `mus_village.mp3` is
the same for listening.

- D major, 108.26 BPM, 4/4; 29 bars, 64.29 s, loops seamlessly; -16 LUFS
- Clarinet-led toy-box chamber pop (ACE-Step take 3 of the Village Square prompt), restructured on its own bar grid
- 0:00 the bloom (the band's groove opening up) - the tune - 0:42 the breakdown (the groove muffled, opening back up) - 0:51 the tune returns - wraps to the bloom

Built from `source_mus_village_v3_take3.mp3` (the untouched take) by `tools/music/village_loop.py`
(the clearer mix comes from `rework_village.py`'s EQ):

    python3 tools/music/village_loop.py tools/music/masters/village/source_mus_village_v3_take3.mp3 OUT_DIR

To put it in the game: copy `mus_village.ogg` to `flutter/assets/audio/music/` and give the `village` place its
music in `lib/core/services/audio_service.dart` (`placeSounds`).

## Tweaking it in FL Studio (or any DAW)

`daw/` here holds the tempo/sections/chords MIDI and the how-to; the full package (24-bit WAVs at 108.26 BPM:
the loop, its five sections, the band / shimmer / swells stems, the source take) is on the PC in
`_transfer/music_final/village/daw`. Rebuild it any time:

    python3 tools/music/village_daw.py tools/music/masters/village/source_mus_village_v3_take3.mp3 OUT_DIR

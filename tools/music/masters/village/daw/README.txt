Village Square: the DAW package
================================

Key D major, tempo 108.26 BPM, 4/4, 29 bars (64.29 s), loops seamlessly (the end runs straight into bar 1).
Every audio file starts exactly on bar 1 at 108.26 BPM, so they all line up.

Sections (bars):  Bloom 1 | Tune A 2-7 | Tune B 8-19 | Breakdown 20-23 | Tune C 24-29

FL Studio
---------
1. New project. Set the tempo to 108.260 (right-click the tempo, or type it in) and 4/4.
2. Drag mus_village_tempo_chords.mid onto the Playlist first: it brings the tempo, the section markers and a chord
   track (the chords as heard, two per bar) to play your own instruments over.
3. Drag the WAVs onto the Playlist at bar 1 (hold Shift while dragging to drop several, one per track). With the
   tempo set, they sit on the grid.
   - Just want to rearrange? Use sections/: lay 01 to 05 end to end, then repeat, shorten or reorder them.
   - Want to rebalance the effects? Use stems/: band + shimmer + swells is the mix before mastering. Turn the
     shimmer or swells up or down, or mute them. band_unfiltered.wav has no filter sweeps, so you can draw your own
     (a low-pass on the bloom, bar 1, and on the breakdown, bars 20-23).
   - Want the instruments apart? FL Studio 21.2 or newer can split any of these WAVs into drums, bass and the rest:
     right-click the clip in the Playlist and choose the stem separator.
4. Export as WAV, then the game wants Ogg Vorbis at -16 LUFS for a gapless loop: send it back and it goes in
   (or export OGG from FL directly). Keep the length a whole number of bars so it still loops.

The game's loop is mus_village_loop.wav (= mus_village.ogg one folder up). source_take.flac is the untouched
ACE-Step take it was cut from (first downbeat at 0.113 s), as FLAC (lossless; FL Studio opens it). Rebuild everything with
tools/music/village_daw.py; the loop itself is built by tools/music/village_loop.py.

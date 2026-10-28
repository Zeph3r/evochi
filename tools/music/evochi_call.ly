\version "2.24.0"
\header {
  title = "The Evochi Call"
  subtitle = "Evochi's leitmotif: bars 1-8 of every theme"
  composer = "Evochi soundtrack"
  tagline = ##f
}
\paper { indent = 0 line-width = 180\mm top-margin = 8\mm bottom-margin = 8\mm system-system-spacing.basic-distance = #16 }
harmonies = \chordmode {
  \set majorSevenSymbol = \markup { "maj7" }
  \set additionalPitchPrefix = "add"
  d1 | g:6 | e:m7 | a2:sus4.7 a:7 |
  d1 | g:maj7 | d2/fis a:7 | d1:5.9 |
}
melody = \relative c'' {
  \key d \major \time 4/4
  \tempo "Brightly, lightly swung" 4 = 100
  a8^\markup \italic "the call" ( d fis4. e8 d4 | b8 d e4. d8 b4 |
  g8 b d4 e8 fis g4 | fis4^\markup \italic "the question" e a,2 ) \breathe | \break
  a8^\markup \italic "the answer" ( d fis4. e8 d4 | b8 d g4. fis8 e4 |
  d8 e fis4 a g8 e | d2.^\markup \italic "home" ) r4 \bar "|."
}
\score {
  << \new ChordNames \harmonies \new Staff \with { instrumentName = "" } \melody >>
  \layout { }
}

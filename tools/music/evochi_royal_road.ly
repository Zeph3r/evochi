\version "2.24.0"
\header {
  title = "The Evochi Call on the Royal Road"
  subtitle = "IV - V - iii - vi, never home until the last phrase"
  tagline = ##f
}
\paper { indent = 0 line-width = 180\mm top-margin = 8\mm bottom-margin = 8\mm system-system-spacing.basic-distance = #16 }
harmonies = \chordmode {
  \set majorSevenSymbol = \markup { "maj7" }
  \set additionalPitchPrefix = "add"
  g1:maj7 | a2:sus4.7 a:7 | fis1:m7 | b1:m7 |
  g1:maj7 | a2:sus4.7 a:7 | fis1:m7 | b1:m7 |
  g1:maj7 | a1:7 | e2:m7 a:7 | d1:5.9 |
}
melody = \relative c'' {
  \key d \major \time 4/4
  \tempo "Bright, driving" 4 = 112
  \mark \markup \small "the call, on the road"
  a8 ( d fis4. e8 d4 | b8 d e4. d8 cis4 | fis,8 a cis4 e8 fis a4 | fis4 e d2 ) | \break
  a8 ( d fis4. e8 d4 | b8 d g4. fis8 e4 | cis8 e fis4 a fis8 e | d2. ) r4 | \break
  \mark \markup \small "the road home (last time)"
  a8 ( d fis4. e8 d4 | b8 d g4. fis8 e4 | d8 e fis4 a g8 e | d1 ) \bar "|."
}
\score {
  << \new ChordNames \harmonies \new Staff \melody >>
  \layout { }
}

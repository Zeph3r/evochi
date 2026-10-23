// The walkable village: scene_fx.frag (keep the two in step) plus a depth test, so the same living
// picture can be drawn again over a character, only where it is nearer the camera than the character's
// feet (tools/art/village_walk_slice.py bakes the depth: world z, 16 bits in R and G; B marks what
// stands up off the ground).
// uFront < 0 draws everything (the first pass). The picture comes in tiles: every motion field runs on
// the whole picture's px (uOffset), so it carries on across a tile's edge. Otherwise as scene_fx:
//   R  sway amount (0-1, feathered). B picks how it moves: 40 smoke wavers as it rises, 80 cloth
//      ripples, anything else is foliage (sways in gusts, its leaves shimmer).
//   G  255 falling water (streaks run down), 128 still water (ripples, glints), 64 grass (a faint
//      fine shimmer, nothing moves).
//   B  255 fire (flickers), 200 crystal (pulses), 128 lamp or window (breathes).
// Everything is in the image's own pixels, so a scene looks the same at any size.

#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec4 uDst;   // where the whole image lands on the canvas: left, top, width, height
uniform vec2 uTex;   // the image's size in px (the mask has the same size)
uniform float uTime; // seconds, wrapped on the Dart side
uniform float uWind; // 1 = a breezy day; 0 = still
uniform vec2 uOffset; // where this tile sits in the whole picture (px): all its motion is in the whole's px, so it runs on across a seam

uniform float uFront; // draw only what is nearer than this (0-1 of the depth range); < 0: everything

uniform sampler2D uImage;
uniform sampler2D uMask;
uniform sampler2D uDepth;

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// the mask is data: read the exact texel, never a blend of two
vec4 maskAt(vec2 px) {
  vec2 c = (floor(clamp(px, vec2(0.0), uTex - vec2(1.0))) + vec2(0.5)) / uTex;
  return texture(uMask, c);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 px = (frag - uDst.xy) / uDst.zw * uTex;
  if (uFront >= 0.0) {
    vec2 c = (floor(clamp(px, vec2(0.0), uTex - vec2(1.0))) + vec2(0.5)) / uTex;
    vec4 dz = texture(uDepth, c);
    float z = (floor(dz.r * 255.0 + 0.5) * 256.0 + floor(dz.g * 255.0 + 0.5)) / 65535.0;
    // only what stands up off the ground covers a character (B), and only if it is nearer
    if (dz.b < 0.5 || z <= uFront) {
      fragColor = vec4(0.0);
      return;
    }
  }
  vec4 m = maskAt(px);
  vec2 wp = px + uOffset; // for the motion fields only (one wind over the whole map)
  float sway = m.r;
  float surf = m.g * 255.0;
  float kind = m.b * 255.0;
  float t = uTime;

  vec2 d = vec2(0.0);  // where to read from, in px
  float light = 0.0;   // added light
  float gain = 1.0;    // multiplied light
  vec3 tint = vec3(0.0);

  if (sway > 0.004) {
    float s = sway * uWind;
    if (kind > 30.0 && kind < 50.0) {
      // smoke: a wave climbs the column
      float w = sin(wp.y * 0.09 + t * 2.2) + 0.5 * sin(wp.y * 0.23 + t * 3.3);
      d.x += w * 2.0 * s;
      d.y += 0.6 * s * sin(t * 1.3 + wp.x * 0.05);
    } else if (kind > 70.0 && kind < 90.0) {
      // cloth: a ripple runs along it
      float ph = wp.x * 0.11 - t * 3.6 + wp.y * 0.025;
      d.y += sin(ph) * 1.5 * s;
      d.x += sin(wp.y * 0.09 - t * 2.7) * 0.7 * s;
      light += cos(ph) * 0.045 * sway;
    } else {
      // foliage: gusts roll across the scene; inside a gust the canopy leans and its leaves shimmer
      // a soft 2D field (turned off the pixel grid) so no gust has a straight edge
      vec2 q = vec2(wp.x * 0.8 + wp.y * 0.6, wp.y * 0.8 - wp.x * 0.6) * 0.004;
      float gust = noise(q - vec2(t * 0.18, t * 0.05));
      float g = 0.3 + 0.7 * smoothstep(0.2, 0.8, gust);
      float lean = sin(t * 1.6 + wp.x * 0.011 + wp.y * 0.007) * 0.65 + sin(t * 2.7 + wp.y * 0.045) * 0.35;
      d.x += lean * 2.2 * g * s;
      d.y += sin(t * 2.1 + wp.x * 0.03) * 0.45 * g * s;
      float leaf = noise(wp * 0.085 + vec2(t * 0.8, -t * 0.35)) - 0.5;
      light += leaf * 0.11 * g * sway;
    }
  }

  if (surf > 32.0 && surf < 96.0) {
    // grass: a faint, fine shimmer that drifts with the wind (no broad bands: a band read as a line
    // sweeping across the map)
    light += (noise(wp * 0.065 + vec2(t * 0.45, t * 0.12)) - 0.5) * 0.035 * max(uWind, 0.3);
  } else if (surf > 96.0 && surf < 192.0) {
    // still water: a small ripple and glints that come and go
    d += vec2(sin(wp.y * 0.33 + t * 2.0), cos(wp.x * 0.19 + t * 1.5)) * 0.55;
    float gl = noise(wp * vec2(0.075, 0.21) + vec2(t * 0.55, t * 0.18));
    light += smoothstep(0.78, 0.94, gl) * 0.24;
    light += (noise(wp * 0.03 + vec2(t * 0.25)) - 0.5) * 0.05;
  } else if (surf > 192.0) {
    // falling water: streaks run down and foam glints
    float s1 = noise(vec2(wp.x * 0.32, wp.y * 0.035 - t * 2.4));
    float s2 = noise(vec2(wp.x * 0.55 + 7.0, wp.y * 0.06 - t * 3.6));
    light += (s1 - 0.5) * 0.2 + smoothstep(0.68, 0.95, s2) * 0.22;
    d.x += (s1 - 0.5) * 0.5;
  }

  if (kind > 240.0) {
    // fire: tongues climb, the whole thing flickers
    float tongue = noise(vec2(wp.x * 0.06, wp.y * 0.05 + t * 3.2));
    float flick = noise(vec2(t * 6.5, wp.x * 0.004));
    float f = tongue * 0.6 + flick * 0.4;
    gain *= 0.7 + 0.62 * f;
    tint += vec3(0.11, 0.045, -0.03) * f;
  } else if (kind > 180.0) {
    // crystal: a slow, deep pulse
    float p = 0.5 + 0.5 * sin(t * 1.5 + wp.x * 0.008 + wp.y * 0.006);
    gain *= 0.86 + 0.32 * p;
  } else if (kind > 100.0) {
    // lamp or window: breathes, with a faint flicker; each light keeps its own time
    float own = hash(floor(wp / 48.0)) * 6.2832;
    float p = 0.5 + 0.5 * sin(t * 1.15 + own);
    float fl = noise(vec2(t * 4.5 + own, 0.5));
    gain *= 0.88 + 0.2 * p + 0.08 * (fl - 0.5);
  }

  vec2 at = clamp((px + d) / uTex, vec2(0.5) / uTex, vec2(1.0) - vec2(0.5) / uTex);
  vec4 col = texture(uImage, at);
  // the image is premultiplied: light only where there's something to light
  vec3 rgb = col.rgb * gain + (vec3(light) + tint) * col.a;
  fragColor = vec4(clamp(rgb, vec3(0.0), vec3(col.a)), col.a);
}

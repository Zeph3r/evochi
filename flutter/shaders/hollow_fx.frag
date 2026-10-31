// The Hollow taking Alder's map (the cold open, onboarding_cine.json's 'hollow' layer; hollow_fx.dart).
// tools/art/hollow_field.py bakes when the Hollow reaches each point of the map (R, 0 first .. 1 the village; 255
// never) and where the board is (G). Played forward by uP: just ahead of the front the trail lights flicker and
// die; at the front a violet rim burns, with an ink-dark wake; behind it the map is the Hollow's own plate, drained
// and violet, its veins pulsing outward from where it began. The desk and the room dim, and violet-black smoke
// creeps in at the screen's edges.

#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec4 uDst;    // where the whole plate lands on the canvas: left, top, width, height
uniform vec2 uTex;    // the plate's size in px
uniform vec2 uView;   // the canvas size
uniform float uTime;  // seconds
uniform float uP;     // how far the Hollow has come (0..1)
uniform float uDim;   // how dark the room has grown (0..1)

uniform sampler2D uLit;
uniform sampler2D uFaded;
uniform sampler2D uHollow;
uniform sampler2D uField;

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
  float s = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    s += a * noise(p);
    p = p * 2.03 + vec2(17.1, 9.2);
    a *= 0.5;
  }
  return s / 0.9375;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = clamp((frag - uDst.xy) / uDst.zw, vec2(0.0), vec2(1.0));
  vec2 px = uv * uTex;
  vec3 lit = texture(uLit, uv).rgb;
  vec3 faded = texture(uFaded, uv).rgb;
  vec3 hol = texture(uHollow, uv).rgb;
  vec4 f = texture(uField, uv);
  float board = smoothstep(0.3, 0.7, f.g);
  float T = f.r > 0.995 ? 9.0 : f.r * (255.0 / 254.0) * 1.25;

  // the front's edge, broken up: big crawling fingers and a fine fray
  float n = fbm(px / 46.0 + vec2(0.0, uTime * 0.12));
  float n2 = fbm(px / 9.0 - vec2(uTime * 0.35, uTime * 0.2));
  float d = uP - (T + (n - 0.5) * 0.11 + (n2 - 0.5) * 0.035);   // > 0: taken

  // the lights: they flicker as it nears, and go out just ahead of it; time dims the rest a little
  float near = smoothstep(-0.13, -0.05, d);
  float out1 = smoothstep(-0.05, -0.008, d);
  float flick = near * (1.0 - out1) * step(0.35, noise(vec2(uTime * 22.0, px.x * 0.02 + px.y * 0.013)));
  float litK = clamp((1.0 - out1) * (1.0 - flick * 0.7) * (1.0 - 0.3 * uDim), 0.0, 1.0);
  vec3 base = mix(faded, lit, litK);

  // behind the front: the Hollow's plate, drained to violet dark, veins pulsing outward from its sources
  float lh = dot(hol, vec3(0.3, 0.59, 0.11));
  vec3 corr = mix(vec3(lh), hol, 0.45) * vec3(0.40, 0.33, 0.60);
  float vein = 1.0 - abs(fbm(px / 21.0 + vec2(uTime * 0.04, 0.0)) * 2.0 - 1.0);
  vein = pow(max(vein, 0.0), 9.0);
  float pulse = 0.5 + 0.5 * sin(uTime * 3.2 - T * 16.0);
  float deep = smoothstep(0.0, 0.12, d);
  corr += vec3(0.60, 0.26, 0.95) * vein * (0.15 + 0.45 * pulse) * deep;
  float crystal = clamp((hol.b - hol.g) * 2.2, 0.0, 1.0);
  corr += vec3(0.62, 0.28, 1.0) * crystal * (0.45 + 0.45 * pulse);
  float c = smoothstep(-0.004, 0.018, d) * board;
  vec3 col = mix(base, corr, c);

  // the front itself: a burning violet rim, an ink-dark wake behind
  // (squared by hand: pow() of a negative number is undefined, and some GPUs blow it up)
  float rx = (d - 0.004) / 0.007;
  float wx = (d - 0.03) / 0.022;
  float rim = exp(-rx * rx) * board;
  float wake = exp(-wx * wx) * board;
  col *= 1.0 - 0.45 * wake;
  col += vec3(0.78, 0.36, 1.0) * rim * (0.75 + 0.7 * n2);

  // the room dims: the desk and walls more than the map, toward a cold violet
  float dk = uDim * mix(0.62, 0.28, board);
  col = mix(col, col * vec3(0.50, 0.46, 0.72), dk);

  // smoke creeping in at the screen's edges
  vec2 sv = frag / uView;
  float e = min(min(sv.x, 1.0 - sv.x), min(sv.y, 1.0 - sv.y) * 0.75);
  float sm = fbm(frag / 70.0 + vec2(uTime * 0.18, -uTime * 0.11));
  float reach = 0.02 + uDim * (0.13 + 0.12 * sm);
  float smoke = 1.0 - smoothstep(0.0, reach, e - 0.03 * sm);
  col = mix(col, vec3(0.05, 0.025, 0.09), smoke * 0.9 * uDim);

  fragColor = vec4(col, 1.0);
}

// The world behind the hero and the lore: the floating island at night with the sleeping Elder, the Lumen
// Trails drawn between far islands, the Hollow creeping in, and the Briarback, tangled and then restored by a
// wave of light the reader scrolls through. One fixed WebGL canvas, driven by where the reader is on the page.
//
// The voxels come from the game's own models (tools/art/site_voxels.py): every exposed face with its colour,
// smoothed normal and glow, and the Elder's face and markings as the renderer's decal quads. Without WebGL,
// with reduced motion or Save-Data, the page keeps its poster and the lore's still pictures instead.
import * as THREE from 'three';

const world = document.querySelector('.world');
const canvas = document.getElementById('world-canvas');
const BASE = document.documentElement.dataset.assets || 'assets/';

const FACES = [
  [[1, 0, 0], [[1, 0, 0], [1, 1, 0], [1, 1, 1], [1, 0, 1]]],
  [[-1, 0, 0], [[0, 0, 0], [0, 0, 1], [0, 1, 1], [0, 1, 0]]],
  [[0, 1, 0], [[0, 1, 0], [0, 1, 1], [1, 1, 1], [1, 1, 0]]],
  [[0, -1, 0], [[0, 0, 0], [1, 0, 0], [1, 0, 1], [0, 0, 1]]],
  [[0, 0, 1], [[0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]]],
  [[0, 0, -1], [[0, 0, 0], [0, 1, 0], [1, 1, 0], [1, 0, 0]]],
];
const LIN = new Float32Array(256).map((_, i) => { const c = i / 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); });

function supported() {
  if (!world || !canvas) return false;
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return false;
  if (navigator.connection && navigator.connection.saveData) return false;
  if (!('DecompressionStream' in window)) return false;
  try { const c = document.createElement('canvas'); return !!(c.getContext('webgl2') || c.getContext('webgl')); } catch (e) { return false; }
}

async function bin(url) {
  const r = await fetch(url);
  let ab;
  if (url.endsWith('.txt')) {               // the claude.ai preview serves no binary files: base64 text there
    const t = atob((await r.text()).trim());
    ab = Uint8Array.from(t, (c) => c.charCodeAt(0)).buffer;
  } else ab = await r.arrayBuffer();
  const u8 = new Uint8Array(ab, 0, 2);
  if (u8[0] !== 0x1f || u8[1] !== 0x8b) return ab;   // a host that already unpacked it
  return new Response(new Blob([ab]).stream().pipeThrough(new DecompressionStream('gzip'))).arrayBuffer();
}

// ------------------------------------------------------------------------------------------ geometry
/** A part's faces as two meshes' worth of geometry: lit, and glowing (drawn unlit). */
function partGeometry(buf, p) {
  const n = p.faces;
  let o = p.faceAt;
  const pos = new Uint8Array(buf, o, n * 3); o += n * 3;
  const dir = new Uint8Array(buf, o, n); o += n;
  const col = new Uint8Array(buf, o, n * 3); o += n * 3;
  const nrm = new Int8Array(buf, o, n * 3); o += n * 3;
  const glow = new Uint8Array(buf, o, n);
  const inv = 1 / p.res, [ox, oy, oz] = p.origin;
  const build = (want) => {
    let m = 0;
    for (let i = 0; i < n; i++) if ((glow[i] > 40) === want) m++;
    if (!m) return null;
    const P = new Float32Array(m * 12), N = new Float32Array(m * 12), C = new Float32Array(m * 12), I = new Uint32Array(m * 6);
    let f = 0;
    for (let i = 0; i < n; i++) {
      if ((glow[i] > 40) !== want) continue;
      const cs = FACES[dir[i]][1];
      const x = pos[i * 3] + ox, y = pos[i * 3 + 1] + oy, z = pos[i * 3 + 2] + oz;
      const nx = nrm[i * 3] / 127, ny = nrm[i * 3 + 1] / 127, nz = nrm[i * 3 + 2] / 127;
      const k = want ? 1.12 : 1;
      const r = Math.min(1, LIN[col[i * 3]] * k), g = Math.min(1, LIN[col[i * 3 + 1]] * k), b = Math.min(1, LIN[col[i * 3 + 2]] * k);
      for (let c = 0; c < 4; c++) {
        const v = (f * 4 + c) * 3;
        P[v] = (x + cs[c][0]) * inv; P[v + 1] = (y + cs[c][1]) * inv; P[v + 2] = (z + cs[c][2]) * inv;
        N[v] = nx; N[v + 1] = ny; N[v + 2] = nz;
        C[v] = r; C[v + 1] = g; C[v + 2] = b;
      }
      const q = f * 4, t = f * 6;
      I[t] = q; I[t + 1] = q + 1; I[t + 2] = q + 2; I[t + 3] = q; I[t + 4] = q + 2; I[t + 5] = q + 3;
      f++;
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(P, 3));
    geo.setAttribute('normal', new THREE.BufferAttribute(N, 3));
    geo.setAttribute('color', new THREE.BufferAttribute(C, 3));
    geo.setIndex(new THREE.BufferAttribute(I, 1));
    geo.computeBoundingSphere();
    return geo;
  };
  return { lit: build(false), glow: build(true) };
}

/** The Elder's face and markings: the renderer's decal quads, lit or not. */
function decalGeometry(buf, p) {
  if (!p.decals) return {};
  const n = p.decals, dv = new DataView(buf, p.decalAt, n * 56);
  const build = (want) => {
    const idx = [];
    for (let i = 0; i < n; i++) if ((dv.getUint8(i * 56 + 52) > 127) === want) idx.push(i);
    if (!idx.length) return null;
    const P = new Float32Array(idx.length * 12), C = new Float32Array(idx.length * 16), I = new Uint32Array(idx.length * 6);
    idx.forEach((i, f) => {
      const b = i * 56;
      for (let c = 0; c < 4; c++) for (let a = 0; a < 3; a++) P[f * 12 + c * 3 + a] = dv.getFloat32(b + (c * 3 + a) * 4, true);
      const r = LIN[dv.getUint8(b + 48)], g = LIN[dv.getUint8(b + 49)], bl = LIN[dv.getUint8(b + 50)], al = dv.getUint8(b + 51) / 255;
      for (let c = 0; c < 4; c++) C.set([r, g, bl, al], f * 16 + c * 4);
      const q = f * 4, t = f * 6;
      I.set([q, q + 1, q + 2, q, q + 2, q + 3], t);
    });
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(P, 3));
    geo.setAttribute('color', new THREE.BufferAttribute(C, 4));
    geo.setIndex(new THREE.BufferAttribute(I, 1));
    geo.computeVertexNormals();
    return geo;
  };
  return { lit: build(true), unlit: build(false) };
}

function mats(tint) {
  const c = new THREE.Color(tint || 0xffffff);
  const side = tint ? THREE.DoubleSide : THREE.FrontSide;    // (a mirrored copy turns its faces inside out)
  return {
    lit: new THREE.MeshLambertMaterial({ vertexColors: true, color: c, side }),
    glow: new THREE.MeshBasicMaterial({ vertexColors: true, color: c, side, fog: true }),
    decal: new THREE.MeshLambertMaterial({ vertexColors: true, color: c, transparent: true, side: THREE.DoubleSide,
      polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2, depthWrite: false }),
    decalUnlit: new THREE.MeshBasicMaterial({ vertexColors: true, color: c, transparent: true, side: THREE.DoubleSide,
      polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2, depthWrite: false }),
  };
}

function meshes(geo, dec, M) {
  const g = new THREE.Group();
  if (geo.lit) g.add(new THREE.Mesh(geo.lit, M.lit));
  if (geo.glow) g.add(new THREE.Mesh(geo.glow, M.glow));
  if (dec && dec.lit) g.add(new THREE.Mesh(dec.lit, M.decal));
  if (dec && dec.unlit) g.add(new THREE.Mesh(dec.unlit, M.decalUnlit));
  return g;
}

// ------------------------------------------------------------------------------------------ textures
function radial(stops, size = 128) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const x = c.getContext('2d'), gr = x.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  stops.forEach(([o, col]) => gr.addColorStop(o, col));
  x.fillStyle = gr;
  x.fillRect(0, 0, size, size);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
const glowTex = () => radial([[0, 'rgba(255,255,255,1)'], [0.25, 'rgba(255,255,255,0.55)'], [1, 'rgba(255,255,255,0)']]);
function zTex() {
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const x = c.getContext('2d');
  x.font = '900 52px Nunito, ui-rounded, system-ui, sans-serif';
  x.textAlign = 'center';
  x.textBaseline = 'middle';
  x.lineWidth = 8;
  x.strokeStyle = 'rgba(40,30,80,0.55)';
  x.strokeText('z', 32, 34);
  x.fillStyle = '#fff2cf';
  x.fillText('z', 32, 34);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

// ------------------------------------------------------------------------------------------ the story's states
// s: how far down the page the reader is, in chapters (0 the hero, 1.5 the first chapter's card centred ...)
const ISL = {
  far1: [-470, 70, -250, 1.0], far2: [430, 25, -470, 0.9], far3: [-160, 120, -830, 0.85], far4: [720, 90, -920, 0.8],
};
const THICKET = new THREE.Vector3(-900, 0, -640);
const KEYS = [
  { s: 0.0, pos: [150, 64, 232], at: [0, 14, 0] },
  { s: 1.5, pos: [150, 300, 640], at: [-60, 10, -400] },
  { s: 2.5, pos: [-120, 130, 210], at: [-420, 60, -320] },
  { s: 3.5, pos: [-560, 260, -200], at: [-880, 20, -600] },
  { s: 4.5, pos: [-808, 56, -508], at: [-900, 34, -640] },
  { s: 5.5, pos: [-998, 52, -506], at: [-900, 34, -640] },
  { s: 6.5, pos: [140, 380, 760], at: [-200, 0, -420] },
  { s: 7.5, pos: [140, 380, 760], at: [-200, 0, -420] },
];
const ease = (t) => t * t * (3 - 2 * t);
const clamp01 = (v) => Math.min(1, Math.max(0, v));
const ramp = (s, a, b) => clamp01((s - a) / (b - a));
function key(s) {
  let i = 0;
  while (i < KEYS.length - 2 && s > KEYS[i + 1].s) i++;
  const a = KEYS[i], b = KEYS[i + 1], t = ease(clamp01((s - a.s) / (b.s - a.s)));
  const lerp = (p, q) => p.map((v, j) => v + (q[j] - v) * t);
  return { pos: lerp(a.pos, b.pos), at: lerp(a.at, b.at) };
}
function story(s) {
  const draw = ramp(s, 0.6, 1.8);
  const hollow = ramp(s, 2.6, 3.3) * (1 - ramp(s, 4.9, 5.7));
  const restore = ramp(s, 4.6, 5.35);
  const relit = ramp(s, 5.6, 6.5);
  return { draw, hollow, restore, relit };
}

// ------------------------------------------------------------------------------------------ the world
async function main() {
  const meta = await (await fetch(BASE + '3d/scenes.json')).json();
  const heroBuf = await bin(BASE + '3d/' + meta.hero.file);
  const mobile = matchMedia('(max-width: 899px)').matches;
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: !mobile || devicePixelRatio < 2, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(devicePixelRatio, mobile ? 1.5 : 1.75));
  renderer.localClippingEnabled = true;
  const scene = new THREE.Scene();
  const NIGHT = { top: new THREE.Color('#0d0b2a'), mid: new THREE.Color('#231c5c'), low: new THREE.Color('#4b3c86'), fog: new THREE.Color('#1c1747') };
  const HOLLOW = { top: new THREE.Color('#0b0618'), mid: new THREE.Color('#2a0f45'), low: new THREE.Color('#5a2a78'), fog: new THREE.Color('#251236') };
  const DAWN = { top: new THREE.Color('#1d2160'), mid: new THREE.Color('#6a4f9a'), low: new THREE.Color('#ffbf86'), fog: new THREE.Color('#5a4a86') };
  scene.fog = new THREE.FogExp2(NIGHT.fog.clone(), 0.00052);
  const camera = new THREE.PerspectiveCamera(34, 1, 2, 12000);

  // the sky: a gradient dome, stars, the moon
  const skyU = { top: { value: NIGHT.top.clone() }, mid: { value: NIGHT.mid.clone() }, low: { value: NIGHT.low.clone() } };
  scene.add(new THREE.Mesh(new THREE.SphereGeometry(6000, 32, 16), new THREE.ShaderMaterial({
    uniforms: skyU, side: THREE.BackSide, depthWrite: false, fog: false,
    vertexShader: 'varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
    fragmentShader: 'uniform vec3 top; uniform vec3 mid; uniform vec3 low; varying vec3 vP; void main(){ float h = vP.y; vec3 c = h > 0.18 ? mix(mid, top, smoothstep(0.18, 0.75, h)) : mix(low, mid, smoothstep(-0.05, 0.18, h)); gl_FragColor = vec4(c, 1.0); }',
  })));
  const NS = mobile ? 700 : 1400, sp = new Float32Array(NS * 3), sa = new Float32Array(NS * 2);
  for (let i = 0; i < NS; i++) {
    const u = Math.random() * 2 - 1, th = Math.random() * Math.PI * 2, y = 0.08 + Math.random() * 0.92, r = Math.sqrt(1 - y * y);
    sp.set([Math.cos(th) * r * 5200, y * 5200, Math.sin(th) * r * 5200], i * 3);
    sa.set([1.2 + Math.random() * 2.4 + (u > 0.94 ? 2.5 : 0), Math.random() * 6.28], i * 2);
  }
  const starGeo = new THREE.BufferGeometry();
  starGeo.setAttribute('position', new THREE.BufferAttribute(sp, 3));
  starGeo.setAttribute('sa', new THREE.BufferAttribute(sa, 2));
  const starU = { t: { value: 0 }, dim: { value: 1 }, px: { value: renderer.getPixelRatio() } };
  scene.add(new THREE.Points(starGeo, new THREE.ShaderMaterial({
    uniforms: starU, transparent: true, depthWrite: false, fog: false, blending: THREE.AdditiveBlending,
    vertexShader: 'attribute vec2 sa; uniform float t; uniform float px; varying float vA; void main(){ vA = 0.55 + 0.45 * sin(t * (0.6 + fract(sa.y) * 1.6) + sa.y); gl_PointSize = sa.x * px; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
    fragmentShader: 'uniform float dim; varying float vA; void main(){ vec2 d = gl_PointCoord - 0.5; float a = smoothstep(0.5, 0.0, length(d)); gl_FragColor = vec4(vec3(1.0, 0.97, 0.9), a * vA * dim); }',
  })));
  const MOON = new THREE.Vector3(-0.42, 0.34, -0.84).normalize().multiplyScalar(4200);
  const glow = glowTex();
  const moonGlow = new THREE.Sprite(new THREE.SpriteMaterial({ map: glow, color: 0xf3e3a6, transparent: true, opacity: 0.35, depthWrite: false, fog: false, blending: THREE.AdditiveBlending }));
  moonGlow.position.copy(MOON);
  moonGlow.scale.setScalar(1500);
  scene.add(moonGlow);
  const moonTex = new THREE.TextureLoader().load(BASE + 'img/world/moon.webp');
  moonTex.colorSpace = THREE.SRGBColorSpace;
  moonTex.magFilter = THREE.NearestFilter;
  const moon = new THREE.Sprite(new THREE.SpriteMaterial({ map: moonTex, transparent: true, depthWrite: false, fog: false }));
  moon.position.copy(MOON);
  moon.scale.setScalar(300);
  scene.add(moon);

  // the light: moonlight, a cool sky, and warm lights on the island
  const hemi = new THREE.HemisphereLight(0xb9c3ff, 0x3a2c66, 2.3);
  scene.add(hemi);
  const moonLight = new THREE.DirectionalLight(0xdfe4ff, 1.1);
  moonLight.position.copy(MOON).normalize().multiplyScalar(500);
  scene.add(moonLight);

  // the home island, the Elder asleep on it, the nest and the lantern in front
  const parts = Object.fromEntries(meta.hero.parts.map((p) => [p.name, p]));
  const geo = {};
  for (const name of Object.keys(parts)) geo[name] = partGeometry(heroBuf, parts[name]);
  const decals = decalGeometry(heroBuf, parts.elder);
  const M = mats(), R = mats(0x7a80b8);
  const home = new THREE.Group(), refl = new THREE.Group();
  const elder = meshes(geo.elder, decals, M), elderR = meshes(geo.elder, decals, R);
  const at = parts.elder.at;
  for (const [g, mm, el] of [[home, M, elder], [refl, R, elderR]]) {
    g.add(meshes(geo.island, null, mm), meshes(geo.front, null, mm));
    el.position.set(at[0], at[1], at[2]);
    g.add(el);
    scene.add(g);
  }
  const WATER = -96;
  refl.scale.y = -1;
  refl.position.y = 2 * WATER;
  const lantern = new THREE.Vector3(...parts.front.lantern), egg = new THREE.Vector3(...parts.front.egg);
  const lanternLight = new THREE.PointLight(0xffb85e, 2600, 220, 1.6);
  lanternLight.position.copy(lantern);
  const eggLight = new THREE.PointLight(0xfff0c4, 1400, 120, 1.6);
  eggLight.position.copy(egg).add(new THREE.Vector3(0, 6, 0));
  home.add(lanternLight, eggLight);
  const halo = (pos, col, size, op) => {
    const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: glow, color: col, transparent: true, opacity: op, depthWrite: false, blending: THREE.AdditiveBlending }));
    s.position.copy(pos);
    s.scale.setScalar(size);
    return s;
  };
  const lanternHalo = halo(lantern, 0xffc46b, 70, 0.55), eggHalo = halo(egg.clone().add(new THREE.Vector3(0, 5, 0)), 0xfff1c8, 48, 0.6);
  home.add(lanternHalo, eggHalo);
  // z's rising from the sleeper's head
  const zt = zTex(), zs = [];
  const head = new THREE.Vector3(at[0], at[1], at[2]).add(new THREE.Vector3(-14, 34, 16));
  for (let i = 0; i < 3; i++) {
    const z = new THREE.Sprite(new THREE.SpriteMaterial({ map: zt, transparent: true, depthWrite: false }));
    z.userData.phase = i / 3;
    home.add(z);
    zs.push(z);
  }

  // the lake: dark water, the island mirrored under it, the moon's path glittering toward the eye
  const waterU = THREE.UniformsUtils.merge([THREE.UniformsLib.fog, { t: { value: 0 }, cam: { value: new THREE.Vector3() }, moonDir: { value: MOON.clone().normalize() }, tint: { value: new THREE.Color('#141236') }, sky: { value: new THREE.Color('#4b3c86') }, glint: { value: new THREE.Color('#f6e7b0') } }]);
  const water = new THREE.Mesh(new THREE.PlaneGeometry(16000, 16000), new THREE.ShaderMaterial({
    uniforms: waterU, transparent: true, depthWrite: false, fog: true,
    vertexShader: '#include <fog_pars_vertex>\nvarying vec3 vW; void main(){ vec4 w = modelMatrix * vec4(position, 1.0); vW = w.xyz; vec4 mvPosition = viewMatrix * w; gl_Position = projectionMatrix * mvPosition;\n#include <fog_vertex>\n}',
    fragmentShader: '#include <fog_pars_fragment>\nuniform float t; uniform vec3 cam; uniform vec3 moonDir; uniform vec3 tint; uniform vec3 sky; uniform vec3 glint; varying vec3 vW;\n' +
      'void main(){ vec3 V = vW - cam; float dist = length(V); V /= dist; vec2 p = vW.xz;\n' +
      // three ripple trains running different ways (no grid), their slopes faded with distance so far water stays calm
      'vec2 k1 = vec2(0.21, 0.16), k2 = vec2(-0.14, 0.27), k3 = vec2(0.39, -0.32);\n' +
      'vec2 g = k1 * cos(dot(p, k1) + t * 1.1) + k2 * cos(dot(p, k2) - t * 0.9) + k3 * 0.5 * cos(dot(p, k3) + t * 1.7);\n' +
      'g *= 0.3 / (1.0 + dist * 0.004);\n' +
      'vec3 N = normalize(vec3(-g.x, 1.0, -g.y)); vec3 R = reflect(V, N);\n' +
      'float spec = pow(max(dot(R, moonDir), 0.0), 420.0);\n' +
      'float fres = 0.03 + 0.97 * pow(1.0 - max(dot(-V, N), 0.0), 5.0);\n' +
      'vec3 c = tint + sky * fres * 0.45 + glint * spec * 1.3;\n' +
      'gl_FragColor = vec4(c, 0.84);\n#include <fog_fragment>\n}',
  }));
  water.rotation.x = -Math.PI / 2;
  water.position.y = WATER;
  scene.add(water);

  // far islands (the same island, coarser), and the Lumen Trails between them
  const farGeo = geo.island_far;
  const farGroup = new THREE.Group();
  const islandAt = {};
  for (const [k, [x, y, z, s]] of Object.entries(ISL)) {
    const g = meshes(farGeo, null, M);
    g.position.set(x, y, z);
    g.scale.setScalar(s);
    g.rotation.y = x * 0.01;
    farGroup.add(g);
    islandAt[k] = new THREE.Vector3(x, y + 8 * s, z);
  }
  scene.add(farGroup);
  islandAt.home = new THREE.Vector3(0, 10, 0);
  islandAt.thicket = THICKET.clone().add(new THREE.Vector3(0, 10, 0));
  const arc = (a, b, lift) => {
    const A = islandAt[a], B = islandAt[b], m1 = A.clone().lerp(B, 0.33), m2 = A.clone().lerp(B, 0.66);
    m1.y += lift; m2.y += lift * 0.9;
    return new THREE.CatmullRomCurve3([A, m1, m2, B]);
  };
  const curves = [arc('home', 'far1', 70), arc('far1', 'far3', 90), arc('home', 'far2', 60), arc('far2', 'far4', 80), arc('far3', 'far4', 110), arc('far1', 'thicket', 50)];
  const trailU = { draw: { value: 0 }, t: { value: 0 }, col: { value: new THREE.Color('#ffd27a') }, amt: { value: 1 } };
  const trailMat = (w) => new THREE.ShaderMaterial({
    uniforms: { ...trailU, w: { value: w } }, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false,
    vertexShader: 'varying vec2 vU; void main(){ vU = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
    fragmentShader: 'uniform float draw; uniform float t; uniform vec3 col; uniform float amt; uniform float w; varying vec2 vU;\n' +
      'void main(){ if (vU.x > draw) discard; float head = smoothstep(draw - 0.04, draw, vU.x) * step(draw, 0.999); float pulse = 0.55 + 0.45 * sin(vU.x * 60.0 - t * 2.4);\n' +
      'gl_FragColor = vec4(col * amt * (pulse + head * 2.0), (0.22 + 0.3 * pulse) * w * amt); }',
  });
  const trails = new THREE.Group();
  for (const c of curves) {
    trails.add(new THREE.Mesh(new THREE.TubeGeometry(c, 240, 1.6, 6), trailMat(1)));
    trails.add(new THREE.Mesh(new THREE.TubeGeometry(c, 120, 5.5, 8), trailMat(0.28)));
  }
  scene.add(trails);
  // sparks running along the trails: Lumen made by movement
  const SPK = 30 * curves.length, spkPos = new Float32Array(SPK * 3), spkSeed = Float32Array.from({ length: SPK }, () => Math.random());
  const spkGeo = new THREE.BufferGeometry();
  spkGeo.setAttribute('position', new THREE.BufferAttribute(spkPos, 3));
  const spkMat = new THREE.PointsMaterial({ map: glow, size: 9, color: 0xfff0b0, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, opacity: 0 });
  scene.add(new THREE.Points(spkGeo, spkMat));
  // fireflies round the home island
  const FF = mobile ? 24 : 44, ffPos = new Float32Array(FF * 3), ffSeed = Float32Array.from({ length: FF * 3 }, () => Math.random());
  const ffGeo = new THREE.BufferGeometry();
  ffGeo.setAttribute('position', new THREE.BufferAttribute(ffPos, 3));
  const ffMat = new THREE.PointsMaterial({ map: glow, size: 5, color: 0xffe08a, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, opacity: 0.9 });
  scene.add(new THREE.Points(ffGeo, ffMat));
  // the Hollow: violet motes rising between the islands
  const HM = mobile ? 260 : 520, hmPos = new Float32Array(HM * 3), hmSeed = Float32Array.from({ length: HM * 3 }, () => Math.random());
  const hmGeo = new THREE.BufferGeometry();
  hmGeo.setAttribute('position', new THREE.BufferAttribute(hmPos, 3));
  const hmMat = new THREE.PointsMaterial({ map: glow, size: 12, color: 0xb070ff, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, opacity: 0 });
  scene.add(new THREE.Points(hmGeo, hmMat));

  // the Briarback's thicket (loaded as the reader nears it)
  const thicket = new THREE.Group();
  thicket.position.copy(THICKET);
  scene.add(thicket);
  const violet = new THREE.PointLight(0xa45cff, 0, 260, 1.4);
  violet.position.set(0, 60, 40);
  thicket.add(violet);
  const warmth = new THREE.PointLight(0xffd59a, 0, 260, 1.4);
  warmth.position.set(0, 70, 50);
  thicket.add(warmth);
  const ring = new THREE.Mesh(new THREE.TorusGeometry(46, 1.4, 8, 72), new THREE.MeshBasicMaterial({ color: 0x9cf0c8, transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false, fog: false }));
  ring.rotation.x = Math.PI / 2;
  thicket.add(ring);
  const BP = 240, bpPos = new Float32Array(BP * 3), bpDir = Float32Array.from({ length: BP * 3 }, () => Math.random() * 2 - 1);
  const bpGeo = new THREE.BufferGeometry();
  bpGeo.setAttribute('position', new THREE.BufferAttribute(bpPos, 3));
  const bpMat = new THREE.PointsMaterial({ map: glow, size: 10, color: 0xc08bff, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, opacity: 0 });
  thicket.add(new THREE.Points(bpGeo, bpMat));
  const wipeUp = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), wipeDown = new THREE.Plane(new THREE.Vector3(0, -1, 0), 0);
  let briar = null;
  const loadBriar = async () => {
    if (briar) return;
    briar = 'loading';
    const meta2 = meta.briar, buf = await bin(BASE + '3d/' + meta2.file);
    const P = Object.fromEntries(meta2.parts.map((p) => [p.name, p]));
    thicket.add(meshes(partGeometry(buf, P.thicket), null, M));
    const make = (name, plane) => {
      const mm = mats();
      for (const m of Object.values(mm)) m.clippingPlanes = [plane];
      const g = meshes(partGeometry(buf, P[name]), null, mm);
      g.position.set(0, 2, 0);
      g.rotation.y = 0.55;
      thicket.add(g);
      return g;
    };
    briar = { hollow: make('briar_hollow', wipeUp), calm: make('briar_calm', wipeDown), top: P.briar_hollow.top[1] };
  };

  // ---------------------------------------------------------------------------------------- the clock
  const chapters = [...document.querySelectorAll('[data-chapter]')];
  const hero = document.querySelector('.hero');
  let s = 0, sTarget = 0, px = 0, py = 0, pxT = 0, pyT = 0, running = true, firstFrame = true;
  // ?world=4.6 holds the story there and ?world=snap follows the scroll without easing (posters, stills, checks)
  const pinQ = new URLSearchParams(location.search).get('world'), pin = Number(pinQ), snap = !!pinQ;
  const camPos = new THREE.Vector3(...KEYS[0].pos), camAt = new THREE.Vector3(...KEYS[0].at);
  // s is 1.5 + i when chapter i's card is centred on screen (wherever the layout puts the card in its chapter)
  const cards = chapters.map((el) => el.querySelector('.lore-card') || el);
  function measure() {
    const vh = innerHeight, c = scrollY + vh / 2;
    const mids = cards.map((el) => { const r = el.getBoundingClientRect(); return r.top + scrollY + r.height / 2; });
    if (!mids.length) return 0;
    if (c < mids[0]) return 1.5 * clamp01((c - vh / 2) / Math.max(1, mids[0] - vh / 2));
    for (let i = 0; i + 1 < mids.length; i++) if (c < mids[i + 1]) return 1.5 + i + (c - mids[i]) / Math.max(1, mids[i + 1] - mids[i]);
    return 1.5 + (mids.length - 1) + (c - mids.at(-1)) / vh;
  }
  addEventListener('scroll', () => { sTarget = measure(); }, { passive: true });
  addEventListener('pointermove', (e) => { pxT = e.clientX / innerWidth - 0.5; pyT = e.clientY / innerHeight - 0.5; }, { passive: true });
  function resize() {
    const w = innerWidth, h = innerHeight;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.fov = Math.min(62, Math.max(34, 2 * Math.atan(Math.tan(17 * Math.PI / 180) / camera.aspect) * 180 / Math.PI));
    camera.updateProjectionMatrix();
    sTarget = measure();
  }
  addEventListener('resize', resize);
  resize();
  s = sTarget;
  new IntersectionObserver((es) => { for (const e of es) running = !!pin || e.isIntersecting || scrollY < innerHeight; }, { rootMargin: '0px' })
    .observe(document.querySelector('.lore') || hero);

  const clock = new THREE.Clock();
  const tmp = new THREE.Vector3();
  function frame() {
    requestAnimationFrame(frame);
    if (!running || document.hidden) { clock.getDelta(); return; }
    const dt = Math.min(clock.getDelta(), 0.05), t = clock.elapsedTime;
    if (pin) sTarget = pin;
    s += (sTarget - s) * (snap ? 1 : Math.min(1, dt * 4));
    px += (pxT - px) * Math.min(1, dt * 3); py += (pyT - py) * Math.min(1, dt * 3);
    if (s > 3.0) loadBriar();
    else if (s > 1.2 && !briar) loadBriar();
    const st = story(s);

    // the camera: the story's keyframes, a slow sway, the pointer's tilt at the top
    const k = key(s), aspect = camera.aspect;
    const near = 1 - ramp(s, 0, 1);
    const pull = aspect < 1 ? 1 + (1 - aspect) * (0.25 * near + 0.9 * (1 - near)) : 1;   // tall screens stand back a little
    tmp.set(...k.pos).sub(new THREE.Vector3(...k.at)).multiplyScalar(pull).add(new THREE.Vector3(...k.at));
    tmp.x += Math.sin(t * 0.13) * 10 * near + px * 30 * near;
    tmp.y += Math.sin(t * 0.17) * 4 * near - py * 16 * near;
    camPos.lerp(tmp, firstFrame || snap ? 1 : Math.min(1, dt * 3));
    camAt.lerp(new THREE.Vector3(...k.at), firstFrame || snap ? 1 : Math.min(1, dt * 3));
    camera.position.copy(camPos);
    camera.lookAt(camAt);
    // at the top the island sits to the right of the hero's card (wide screens) or above it (tall ones)
    const w = innerWidth, h = innerHeight;
    // and on tall screens the story's subject sits above the cards, which ride low
    const sx = aspect >= 1.1 ? w * 0.17 * near : 0, sy = aspect < 1.1 ? h * (0.25 - 0.05 * near) : 0;
    if (sx || sy) camera.setViewOffset(w + sx * 2, h + sy * 2, 0, sy * 2, w, h);
    else camera.clearViewOffset();

    // the sky, the fog and the light follow the story: night, the Hollow, the light coming back
    const mix3 = (key) => {
      const c = NIGHT[key].clone().lerp(HOLLOW[key], st.hollow);
      return c.lerp(DAWN[key], st.relit * 0.85);
    };
    skyU.top.value.copy(mix3('top')); skyU.mid.value.copy(mix3('mid')); skyU.low.value.copy(mix3('low'));
    scene.fog.color.copy(mix3('fog'));
    hemi.intensity = 2.3 - 0.9 * st.hollow + 0.5 * st.relit;
    hemi.color.set(0xb9c3ff).lerp(new THREE.Color(0xc9a0ff), st.hollow).lerp(new THREE.Color(0xffe3c4), st.relit * 0.6);
    starU.t.value = t;
    starU.dim.value = 1 - 0.5 * st.hollow - 0.4 * st.relit;
    moon.material.opacity = 1 - 0.6 * st.hollow;

    // the trails: drawn in, dimmed violet by the Hollow, relit gold
    trailU.draw.value = st.draw;
    trailU.t.value = t;
    trailU.col.value.set(0xffd27a).lerp(new THREE.Color(0x7b4bb0), st.hollow);
    trailU.amt.value = (1 - 0.65 * st.hollow) * (1 + 0.5 * st.relit);
    spkMat.opacity = ramp(s, 1.6, 2.2) * (1 - st.hollow) * 0.95 + st.relit * 0.6;
    for (let i = 0; i < SPK; i++) {
      const c = curves[i % curves.length], u = (spkSeed[i] + t * (0.035 + spkSeed[i] * 0.03)) % 1;
      c.getPointAt(Math.min(u, st.draw), tmp);
      spkPos.set([tmp.x, tmp.y + Math.sin(t * 3 + i) * 1.5, tmp.z], i * 3);
    }
    spkGeo.attributes.position.needsUpdate = true;

    // the sleeper breathes; the z's drift up; the lantern flickers, the egg glows
    const br = Math.sin(t * Math.PI * 2 / 3.4);
    for (const e of [elder, elderR]) e.scale.set(1 + br * 0.006, 1 + br * 0.014, 1 + br * 0.006);
    zs.forEach((z) => {
      const u = (t / 3.6 + z.userData.phase) % 1;
      z.position.copy(head).add(new THREE.Vector3(u * 14 + Math.sin(u * 6) * 3, u * 30, u * 6));
      z.scale.setScalar(5 + u * 7);
      z.material.opacity = (u < 0.15 ? u / 0.15 : 1 - (u - 0.15) / 0.85) * near;
    });
    const fl = 0.86 + 0.14 * Math.sin(t * 9.1) * Math.sin(t * 5.3 + 1);
    lanternLight.intensity = 2600 * fl;
    lanternHalo.material.opacity = 0.55 * fl;
    eggLight.intensity = 1400 * (0.8 + 0.2 * Math.sin(t * Math.PI * 2 / 3.6));
    const bob = Math.sin(t * Math.PI * 2 / 6) * 2.2;
    home.position.y = bob;
    refl.position.y = 2 * WATER - bob;
    waterU.t.value = t;
    waterU.cam.value.copy(camera.position);
    waterU.sky.value.copy(skyU.low.value);
    for (let i = 0; i < FF; i++) {
      const a = ffSeed[i * 3] * 6.28 + t * (0.08 + ffSeed[i * 3 + 1] * 0.1), r = 50 + ffSeed[i * 3 + 2] * 70;
      ffPos.set([Math.cos(a) * r, 8 + ffSeed[i * 3 + 1] * 40 + Math.sin(t * 0.7 + i) * 6, Math.sin(a) * r * 0.75], i * 3);
    }
    ffGeo.attributes.position.needsUpdate = true;
    ffMat.opacity = (0.55 + 0.45 * Math.sin(t * 2.1)) * (1 - st.hollow);

    // the Hollow's motes
    hmMat.opacity = st.hollow * 0.85;
    if (st.hollow > 0.01) {
      for (let i = 0; i < HM; i++) {
        const y = ((hmSeed[i * 3 + 1] * 260 + t * (6 + hmSeed[i * 3 + 2] * 8)) % 260) - 60;
        hmPos.set([-1000 + hmSeed[i * 3] * 1300 + Math.sin(t * 0.3 + i) * 8, y, -760 + hmSeed[i * 3 + 2] * 900], i * 3);
      }
      hmGeo.attributes.position.needsUpdate = true;
    }

    // the Briarback: tangled; then the wave of light rises through it and leaves it restored
    if (briar && briar !== 'loading') {
      const top = briar.top + 8, wave = -6 + (top + 12) * st.restore;
      wipeUp.constant = -(wave + THICKET.y + 2);
      wipeDown.constant = wave + THICKET.y + 2;
      briar.hollow.visible = st.restore < 0.999;
      briar.calm.visible = st.restore > 0.001;
      ring.position.y = wave + 2;
      ring.material.opacity = st.restore > 0 && st.restore < 1 ? 0.9 * Math.sin(st.restore * Math.PI) : 0;
      ring.scale.setScalar(0.8 + 0.25 * Math.sin(st.restore * Math.PI));
      violet.intensity = 3200 * clamp01(ramp(s, 3.2, 4.0)) * (1 - st.restore);
      warmth.intensity = 4200 * st.restore * (1 - 0.5 * ramp(s, 6.0, 6.8));
      bpMat.opacity = Math.sin(clamp01(st.restore * 1.2) * Math.PI) * 0.95;
      const e = ease(st.restore);
      for (let i = 0; i < BP; i++) {
        const d = 30 + 120 * e * (0.4 + Math.abs(bpDir[i * 3 + 1]));
        bpPos.set([bpDir[i * 3] * d, 30 + bpDir[i * 3 + 1] * 30 + e * 40 * Math.abs(bpDir[i * 3 + 2]), bpDir[i * 3 + 2] * d], i * 3);
      }
      bpGeo.attributes.position.needsUpdate = true;
      bpMat.color.set(0xc08bff).lerp(new THREE.Color(0xffe39a), e);
    }

    renderer.render(scene, camera);
    if (firstFrame) {
      firstFrame = false;
      world.classList.add('live');
    }
  }
  frame();
}

if (supported()) {
  main().catch((e) => { console.warn('world', e); world.classList.add('no-3d'); });
} else if (world) {
  world.classList.add('no-3d');
}

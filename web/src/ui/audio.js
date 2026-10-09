// Sound effects and ambient loop (WebAudio). Everything respects the sound/music settings,
// and nothing plays before the first user gesture.
import { manifest, url } from './assets.js';

let ctx = null;
const buffers = new Map();
let enabled = { sound: true, music: true };
let ambient = null;
let unlocked = false;

function ac() {
  if (!ctx) {
    const C = window.AudioContext || window.webkitAudioContext;
    if (!C) return null;
    ctx = new C();
  }
  return ctx;
}

async function buffer(name) {
  if (buffers.has(name)) return buffers.get(name);
  const p = (async () => {
    const a = ac();
    if (!a) return null;
    const file = manifest().audio[name];
    if (!file) return null;
    const res = await fetch(url(file));
    const arr = await res.arrayBuffer();
    return await a.decodeAudioData(arr);
  })().catch(() => null);
  buffers.set(name, p);
  return p;
}

export function configure(settings) {
  enabled = { sound: !!settings.sound, music: !!settings.music };
  if (!enabled.music) stopAmbient();
  else if (unlocked) startAmbient();
}

export function unlock() {
  if (unlocked) return;
  unlocked = true;
  const a = ac();
  if (a && a.state === 'suspended') a.resume();
  if (enabled.music) startAmbient();
}

export async function play(name, vol = 0.8) {
  if (!enabled.sound || !unlocked) return;
  const a = ac();
  if (!a) return;
  const b = await buffer(name);
  if (!b) return;
  const src = a.createBufferSource();
  const g = a.createGain();
  g.gain.value = vol;
  src.buffer = b;
  src.connect(g).connect(a.destination);
  src.start();
}

async function startAmbient() {
  if (ambient || !enabled.music) return;
  const a = ac();
  if (!a) return;
  const b = await buffer('ambient_meadow_loop');
  if (!b || ambient || !enabled.music) return;
  const src = a.createBufferSource();
  const g = a.createGain();
  g.gain.value = 0;
  g.gain.linearRampToValueAtTime(0.35, a.currentTime + 2);
  src.buffer = b;
  src.loop = true;
  src.connect(g).connect(a.destination);
  src.start();
  ambient = { src, g };
}

export function stopAmbient() {
  if (!ambient) return;
  try {
    ambient.src.stop();
  } catch {}
  ambient = null;
}

export function haptic(ms = 12, on = true) {
  if (on && navigator.vibrate) {
    try {
      navigator.vibrate(ms);
    } catch {}
  }
}

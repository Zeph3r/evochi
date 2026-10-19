// Sound effects and ambient loop (WebAudio). Everything respects the sound/music settings,
// and nothing plays before the first user gesture.
import { manifest, url } from './assets.js';

let ctx = null;
const buffers = new Map();
let enabled = { sound: true, music: true };
let ambient = null;
let unlocked = false;
const DEFAULT_LOOP = 'ambient_meadow_loop';
let loopName = DEFAULT_LOOP;

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

async function startAmbient(fadeIn = 2) {
  if (ambient || !enabled.music) return;
  const a = ac();
  if (!a) return;
  const name = loopName;
  const b = await buffer(name);
  if (!b || ambient || !enabled.music || name !== loopName) return;
  const src = a.createBufferSource();
  const g = a.createGain();
  g.gain.setValueAtTime(0, a.currentTime);
  g.gain.linearRampToValueAtTime(name === DEFAULT_LOOP ? 0.35 : 0.5, a.currentTime + fadeIn);
  src.buffer = b;
  src.loop = true;
  src.connect(g).connect(a.destination);
  src.start();
  ambient = { src, g, name };
}

export function stopAmbient(fade = 0) {
  if (!ambient) return;
  const { src, g } = ambient;
  ambient = null;
  const a = ac();
  if (fade && a) {
    g.gain.cancelScheduledValues(a.currentTime);
    g.gain.setValueAtTime(g.gain.value, a.currentTime);
    g.gain.linearRampToValueAtTime(0, a.currentTime + fade);
    setTimeout(() => {
      try {
        src.stop();
      } catch {}
    }, fade * 1000 + 50);
    return;
  }
  try {
    src.stop();
  } catch {}
}

/** Switch the looping track (null = the meadow ambience), crossfading. Encounters use their own loops. */
export function setMusic(name, fade = 0.8) {
  const want = name || DEFAULT_LOOP;
  if (want === loopName && (ambient || !enabled.music || !unlocked)) return;
  loopName = want;
  if (!enabled.music || !unlocked) return;
  stopAmbient(fade);
  startAmbient(fade);
}

export function haptic(ms = 12, on = true) {
  if (on && navigator.vibrate) {
    try {
      navigator.vibrate(ms);
    } catch {}
  }
}

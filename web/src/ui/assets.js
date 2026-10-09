// Asset manifest, image cache and sprite helpers.

let MAN = null;
const imgCache = new Map();
const urlCache = new Map();
const BASE = 'assets/';

export async function loadManifest() {
  const r = await fetch(BASE + 'manifest.json');
  MAN = await r.json();
  return MAN;
}

export function manifest() {
  return MAN;
}

export function url(path) {
  return BASE + path;
}

export function loadImage(path) {
  if (imgCache.has(path)) return imgCache.get(path).promise;
  const img = new Image();
  img.decoding = 'async';
  const promise = new Promise((res, rej) => {
    img.onload = () => res(img);
    img.onerror = () => rej(new Error('image failed: ' + path));
  });
  img.src = url(path);
  imgCache.set(path, { img, promise });
  return promise;
}

export function imageIfReady(path) {
  const e = imgCache.get(path);
  return e && e.img.complete && e.img.naturalWidth ? e.img : null;
}

export const icon = (k) => url(MAN.icons[k]);
export const itemImg = (k) => url(MAN.items[k]);
export const title = (k) => MAN.titles[k];

export function charEntry(stage) {
  return MAN.chars['s0' + stage];
}

export function frameRect(stage, palette, expr) {
  const e = charEntry(stage);
  const i = e.expressions.indexOf(expr);
  return e.atlas[palette].rects[i < 0 ? 0 : i];
}

export function preloadPet(stage, palette) {
  const e = charEntry(stage);
  return Promise.all([loadImage(e.atlas[palette].file), loadImage(e.overlays.file)]);
}

/**
 * Crop one sprite frame (optionally with accessory overlays) to a data URL so it can be used
 * in ordinary <img> elements (evolution strip, swatches, dex...). Cached.
 */
export async function spriteURL(stage, palette, expr = 'default', { overlays = [], view = null, trim = true, maxH = 220 } = {}) {
  const key = [stage, palette, expr, overlays.join('+'), view, trim, maxH].join('|');
  if (urlCache.has(key)) return urlCache.get(key);
  const p = (async () => {
    const e = charEntry(stage);
    let src;
    let r;
    const tk = `${stage}|${palette}|${expr}`;
    if (!view && !overlays.length && maxH <= 160 && MAN.thumbs?.rects[tk]) {
      const t = MAN.thumbs.rects[tk];
      const img = await loadImage(MAN.thumbs.file);
      const c = document.createElement('canvas');
      const s = Math.min(1, maxH / t[3]);
      c.width = Math.round(t[2] * s);
      c.height = Math.round(t[3] * s);
      const g = c.getContext('2d');
      g.imageSmoothingQuality = 'high';
      g.drawImage(img, t[0], t[1], t[2], t[3], 0, 0, c.width, c.height);
      return c.toDataURL('image/png');
    }
    if (view) {
      src = await loadImage(e.turn[palette].file);
      r = e.turn[palette].rects[view];
    } else {
      src = await loadImage(e.atlas[palette].file);
      r = frameRect(stage, palette, expr);
    }
    const c = document.createElement('canvas');
    c.width = r[2];
    c.height = r[3];
    const g = c.getContext('2d');
    g.drawImage(src, r[0], r[1], r[2], r[3], 0, 0, r[2], r[3]);
    if (!view && overlays.length) {
      const ov = await loadImage(e.overlays.file);
      for (const o of overlays) {
        const orr = e.overlays.rects[o];
        if (orr) g.drawImage(ov, orr[0], orr[1], orr[2], orr[3], 0, 0, r[2], r[3]);
      }
    }
    let out = c;
    if (trim) out = trimCanvas(c);
    if (out.height > maxH) {
      const s = maxH / out.height;
      const c2 = document.createElement('canvas');
      c2.width = Math.round(out.width * s);
      c2.height = Math.round(out.height * s);
      const g2 = c2.getContext('2d');
      g2.imageSmoothingQuality = 'high';
      g2.drawImage(out, 0, 0, c2.width, c2.height);
      out = c2;
    }
    return out.toDataURL('image/png');
  })();
  urlCache.set(key, p);
  return p;
}

function trimCanvas(c) {
  const g = c.getContext('2d');
  const { data, width, height } = g.getImageData(0, 0, c.width, c.height);
  let x0 = width, y0 = height, x1 = 0, y1 = 0;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if (data[(y * width + x) * 4 + 3] > 8) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < x0) return c;
  const o = document.createElement('canvas');
  o.width = x1 - x0 + 3;
  o.height = y1 - y0 + 3;
  o.getContext('2d').drawImage(c, x0 - 1, y0 - 1, o.width, o.height, 0, 0, o.width, o.height);
  return o;
}

/** Fill <img data-sprite="stage|palette|expr|overlays|view"> placeholders after a render. */
export function hydrateSprites(root) {
  for (const img of root.querySelectorAll('img[data-sprite]')) {
    const [stage, palette, expr, ov, view, maxH] = img.dataset.sprite.split('|');
    const overlays = ov ? ov.split('+').filter(Boolean) : [];
    spriteURL(+stage, palette, expr || 'default', { overlays, view: view || null, maxH: +maxH || 220 }).then((u) => {
      if (img.isConnected) img.src = u;
    });
  }
}

export function spriteAttr(stage, palette, expr = 'default', overlays = [], view = '', maxH = 220) {
  return `${stage}|${palette}|${expr}|${overlays.join('+')}|${view}|${maxH}`;
}

export const BLANK = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';

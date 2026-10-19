// Canvas effects for the encounter stage: particles, trails, rings, rays and glows on two layers (one
// behind the creatures, one in front), drawn from soft pre-rendered sprites with additive light.
//
// Positions are percent of the shot, like shotGeometry; sizes and speeds are in units of 1% of the shot's
// width ("u"), so an effect looks the same on any phone. One clock, driven by requestAnimationFrame, that
// the turn choreography can freeze for a hit-stop.

const DPR_MAX = 3;
const TAU = Math.PI * 2;

// core, mid, edge
export const PAL = {
  gold: ['#FFFFFF', '#FFF1B8', '#FFC24A'],
  violet: ['#FFFFFF', '#E9DBFF', '#9B6BE8'],
  dark: ['#6A48B8', '#3D2670', '#1C1038'],
  teal: ['#FFFFFF', '#CFF7E6', '#4FBF99'],
  pink: ['#FFFFFF', '#FDD6DE', '#F28CA6'],
  dust: ['#F1E9D6', '#D8CBB0', '#B9AB90'],
  white: ['#FFFFFF', '#FFFFFF', '#FFFFFF'],
  red: ['#FFFFFF', '#FFD0C4', '#F06A5A'],
  green: ['#FFFFFF', '#DDF5C8', '#7AC24F'],
};

const rnd = (a, b) => a + Math.random() * (b - a);
const pick = (arr) => arr[(Math.random() * arr.length) | 0];
const easeOut = (t) => 1 - (1 - t) * (1 - t);
const easeIn = (t) => t * t;
const easeInOut = (t) => (t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2);
const clamp01 = (t) => Math.max(0, Math.min(1, t));

// size over life
const SIZE = {
  hold: () => 1,
  shrink: (t) => 1 - t * 0.85,
  grow: (t) => 0.3 + 0.7 * easeOut(t),
  pop: (t) => (t < 0.18 ? 0.4 + 0.75 * (t / 0.18) : 1.15 - 0.3 * ((t - 0.18) / 0.82)),
  spark: (t) => (t < 0.12 ? 0.5 + 0.5 * (t / 0.12) : 1 - 0.9 * ((t - 0.12) / 0.88) ** 1.4),
  bloom: (t) => 0.2 + 1.3 * easeOut(t),
};
// alpha over life
const ALPHA = {
  fade: (t) => 1 - t,
  fade2: (t) => (1 - t) * (1 - t),
  inout: (t) => (t < 0.25 ? t / 0.25 : 1 - (t - 0.25) / 0.75),
  hold: (t) => (t < 0.7 ? 1 : 1 - (t - 0.7) / 0.3),
  flash: (t) => (t < 0.1 ? 1 : (1 - (t - 0.1) / 0.9) ** 2),
  soft: (t) => Math.sin(t * Math.PI),
};

// ------------------------------------------------------------------ sprites
const spriteCache = new Map();
function sprite(shape, pal) {
  const key = shape + '|' + pal;
  if (spriteCache.has(key)) return spriteCache.get(key);
  const [core, mid, edge] = PAL[pal] || PAL.white;
  const S = 64;
  const c = document.createElement('canvas');
  c.width = S;
  c.height = S;
  const g = c.getContext('2d');
  const h = S / 2;
  if (shape === 'glow') {
    const r = g.createRadialGradient(h, h, 0, h, h, h);
    r.addColorStop(0, core);
    r.addColorStop(0.22, mid);
    r.addColorStop(0.55, hexA(edge, 0.55));
    r.addColorStop(1, hexA(edge, 0));
    g.fillStyle = r;
    g.fillRect(0, 0, S, S);
  } else if (shape === 'dot') {
    const r = g.createRadialGradient(h, h, 0, h, h, h);
    r.addColorStop(0, core);
    r.addColorStop(0.5, mid);
    r.addColorStop(0.78, hexA(edge, 0.9));
    r.addColorStop(1, hexA(edge, 0));
    g.fillStyle = r;
    g.fillRect(0, 0, S, S);
  } else if (shape === 'puff') {
    const r = g.createRadialGradient(h, h, 0, h, h, h);
    r.addColorStop(0, hexA(mid, 0.55));
    r.addColorStop(0.6, hexA(edge, 0.25));
    r.addColorStop(1, hexA(edge, 0));
    g.fillStyle = r;
    g.fillRect(0, 0, S, S);
  } else if (shape === 'star') {
    g.translate(h, h);
    g.fillStyle = mid;
    g.shadowColor = edge;
    g.shadowBlur = 6;
    g.beginPath();
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * TAU - Math.PI / 2;
      const rr = i % 2 ? h * 0.3 : h * 0.95;
      g.lineTo(Math.cos(a) * rr, Math.sin(a) * rr);
    }
    g.closePath();
    g.fill();
    g.shadowBlur = 0;
    g.fillStyle = core;
    g.beginPath();
    g.arc(0, 0, h * 0.22, 0, TAU);
    g.fill();
  } else if (shape === 'shard') {
    // a long diamond along x, bright in the middle: drawn stretched in the direction of flight
    const r = g.createLinearGradient(0, 0, S, 0);
    r.addColorStop(0, hexA(edge, 0));
    r.addColorStop(0.35, mid);
    r.addColorStop(0.5, core);
    r.addColorStop(0.65, mid);
    r.addColorStop(1, hexA(edge, 0));
    g.fillStyle = r;
    g.beginPath();
    g.moveTo(0, h);
    g.quadraticCurveTo(h, h - S * 0.16, S, h);
    g.quadraticCurveTo(h, h + S * 0.16, 0, h);
    g.fill();
  } else if (shape === 'petal') {
    g.translate(h, h);
    const r = g.createLinearGradient(-h, 0, h, 0);
    r.addColorStop(0, mid);
    r.addColorStop(1, edge);
    g.fillStyle = r;
    g.beginPath();
    g.moveTo(-h * 0.9, 0);
    g.bezierCurveTo(-h * 0.5, -h * 0.75, h * 0.5, -h * 0.75, h * 0.9, 0);
    g.bezierCurveTo(h * 0.5, h * 0.55, -h * 0.5, h * 0.55, -h * 0.9, 0);
    g.fill();
    g.fillStyle = hexA(core, 0.5);
    g.beginPath();
    g.ellipse(-h * 0.25, -h * 0.15, h * 0.25, h * 0.12, -0.4, 0, TAU);
    g.fill();
  } else if (shape === 'heart') {
    g.translate(h, h * 1.08);
    g.scale(h / 12, h / 12);
    g.fillStyle = edge;
    g.strokeStyle = core;
    g.lineWidth = 1.6;
    g.beginPath();
    g.moveTo(0, 9);
    g.bezierCurveTo(-7.5, 4.4, -9.4, -1.3, -7, -5);
    g.bezierCurveTo(-5, -8, -1.5, -7.5, 0, -4.5);
    g.bezierCurveTo(1.5, -7.5, 5, -8, 7, -5);
    g.bezierCurveTo(9.4, -1.3, 7.5, 4.4, 0, 9);
    g.closePath();
    g.fill();
    g.stroke();
  } else if (shape === 'leafbit') {
    g.translate(h, h);
    g.fillStyle = mid;
    g.beginPath();
    g.ellipse(0, 0, h * 0.8, h * 0.35, 0, 0, TAU);
    g.fill();
  } else if (shape === 'smoke') {
    const r = g.createRadialGradient(h, h, 0, h, h, h);
    r.addColorStop(0, hexA(core, 0.6));
    r.addColorStop(0.45, hexA(mid, 0.5));
    r.addColorStop(1, hexA(edge, 0));
    g.fillStyle = r;
    g.fillRect(0, 0, S, S);
  }
  spriteCache.set(key, c);
  return c;
}

function hexA(hex, a) {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
}

// ------------------------------------------------------------------ the engine
export class StageFX {
  /** world: the element whose box is the shot; back/front: the two canvases inside it. */
  constructor(world, back, front) {
    this.world = world;
    this.cv = { back, front };
    this.ctx = { back: back.getContext('2d'), front: front.getContext('2d') };
    this.ps = [];      // particles
    this.movers = [];  // comets, rings, rays: objects with tick(dt) and draw(g, layer) and dead
    this.ambient = null;
    this.freezeLeft = 0;
    this.last = null;
    this.active = false;
    this.dirty = true;
    this.w = 0;
    this.h = 0;
    this.dpr = 1;
    this.u = 1;
    this.resize();
    if (typeof ResizeObserver !== 'undefined') {
      this.ro = new ResizeObserver(() => this.resize());
      this.ro.observe(world);
    }
  }

  resize() {
    const r = this.world.getBoundingClientRect();
    const dpr = Math.min(DPR_MAX, window.devicePixelRatio || 1);
    const w = Math.max(1, Math.round(r.width * dpr));
    const h = Math.max(1, Math.round(r.height * dpr));
    if (w === this.w && h === this.h) return;
    this.w = w;
    this.h = h;
    this.dpr = dpr;
    this.u = w / 100;
    for (const k of ['back', 'front']) {
      this.cv[k].width = w;
      this.cv[k].height = h;
    }
    this.dirty = true;
  }

  /** percent of the shot -> device pixels */
  px(p) {
    return [(p[0] / 100) * this.w, (p[1] / 100) * this.h];
  }

  start() {
    if (this.active) return;
    this.active = true;
    this.last = null;
    const loop = (now) => {
      if (!this.active) return;
      if (!this.world.isConnected) return this.stop();
      this.tick(now);
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
  }

  stop() {
    this.active = false;
    this.ro?.disconnect();
    this.ps.length = 0;
    this.movers.length = 0;
  }

  /** Hold everything still for a moment (the hit-stop). */
  freeze(ms) {
    this.freezeLeft = Math.max(this.freezeLeft, ms);
  }

  tick(now) {
    if (this.last == null) this.last = now;
    let dt = Math.min(0.05, (now - this.last) / 1000);
    this.last = now;
    if (this.freezeLeft > 0) {
      this.freezeLeft -= dt * 1000;
      return;
    }
    if (this.ambient) {
      this.ambient.left -= dt;
      if (this.ambient.left <= 0) this.emitAmbient();
    }
    const alive = [];
    for (const p of this.ps) {
      p.age += dt;
      if (p.age >= p.life) continue;
      if (p.seek) {
        const k = p.seek.k;
        p.vx += (p.seek.x - p.x) * k * dt;
        p.vy += (p.seek.y - p.y) * k * dt;
      }
      if (p.orbit) {
        p.orbit.a += p.orbit.w * dt;
        p.orbit.r += p.orbit.dr * dt;
        p.x = p.orbit.x + Math.cos(p.orbit.a) * p.orbit.r;
        p.y = p.orbit.y + Math.sin(p.orbit.a) * p.orbit.r * 0.55;
      } else {
        p.vx += p.ax * dt;
        p.vy += p.ay * dt;
        if (p.turb) {
          p.ph += dt * p.turbW;
          p.vx += Math.cos(p.ph) * p.turb * dt;
          p.vy += Math.sin(p.ph * 1.3) * p.turb * 0.6 * dt;
        }
        const d = Math.max(0, 1 - p.drag * dt);
        p.vx *= d;
        p.vy *= d;
        p.x += p.vx * dt;
        p.y += p.vy * dt;
      }
      p.rot += p.spin * dt;
      alive.push(p);
    }
    this.ps = alive;
    const mv = [];
    for (const m of this.movers) {
      m.tick(dt, this);
      if (!m.dead) mv.push(m);
    }
    this.movers = mv;
    this.draw();
  }

  draw() {
    const any = this.ps.length || this.movers.length;
    if (!any && !this.dirty) return;
    this.dirty = !!any;
    for (const layer of ['back', 'front']) {
      const g = this.ctx[layer];
      g.setTransform(1, 0, 0, 1, 0, 0);
      g.clearRect(0, 0, this.w, this.h);
      for (const m of this.movers) if (m.layer === layer && m.drawUnder) m.draw(g, this);
      for (const p of this.ps) {
        if (p.layer !== layer) continue;
        const t = p.age / p.life;
        const a = p.alpha * ALPHA[p.alphaK](t);
        if (a <= 0.002) continue;
        const s = p.size * SIZE[p.sizeK](t);
        g.globalCompositeOperation = p.blend;
        g.globalAlpha = Math.min(1, a);
        let rot = p.rot;
        let sx = 1;
        if (p.align) {
          rot = Math.atan2(p.vy, p.vx);
          if (p.stretch) sx = 1 + Math.min(4, (Math.hypot(p.vx, p.vy) / this.u) * p.stretch);
        }
        g.setTransform(1, 0, 0, 1, p.x, p.y);
        g.rotate(rot);
        g.drawImage(p.sprite, (-s * sx) / 2, -s / 2, s * sx, s);
      }
      g.setTransform(1, 0, 0, 1, 0, 0);
      for (const m of this.movers) if (m.layer === layer && !m.drawUnder) m.draw(g, this);
      g.globalCompositeOperation = 'source-over';
      g.globalAlpha = 1;
    }
  }

  // ---------------------------------------------------------------- particles
  /** One particle. p in percent; size, speed in u; life in seconds. */
  emit(p, o = {}) {
    const [x, y] = Array.isArray(p) && p.length === 2 && o.raw !== true ? this.px(p) : p;
    const u = this.u;
    const sp = (o.speed ?? 0) * u;
    const ang = o.angle ?? rnd(0, TAU);
    const spread = o.spread ?? 0;
    const a = ang + rnd(-spread, spread);
    const part = {
      x: x + rnd(-(o.jitter ?? 0), o.jitter ?? 0) * u,
      y: y + rnd(-(o.jitter ?? 0), o.jitter ?? 0) * u,
      vx: Math.cos(a) * sp + (o.vx ?? 0) * u,
      vy: Math.sin(a) * sp + (o.vy ?? 0) * u,
      ax: (o.ax ?? 0) * u,
      ay: (o.gravity ?? 0) * u,
      drag: o.drag ?? 0,
      life: o.life ?? 0.8,
      age: 0,
      size: (o.size ?? 1.2) * u,
      sizeK: o.sizeK ?? 'shrink',
      alpha: o.alpha ?? 1,
      alphaK: o.alphaK ?? 'fade',
      rot: o.rot ?? rnd(0, TAU),
      spin: o.spin ?? 0,
      align: !!o.align,
      stretch: o.stretch ?? 0,
      sprite: sprite(o.shape ?? 'glow', o.pal ?? 'gold'),
      blend: o.blend ?? 'lighter',
      layer: o.layer ?? 'front',
      turb: (o.turb ?? 0) * u,
      turbW: o.turbW ?? rnd(2, 5),
      ph: rnd(0, TAU),
      seek: o.seek ? { x: this.px(o.seek)[0], y: this.px(o.seek)[1], k: o.seekK ?? 30 } : null,
      orbit: null,
    };
    this.ps.push(part);
    return part;
  }

  /** n particles from one point. */
  burst(p, n, o = {}) {
    for (let i = 0; i < n; i++) {
      const v = (f) => (typeof f === 'function' ? f(i, n) : f);
      this.emit(p, {
        ...o,
        angle: o.angle ?? (o.even ? (i / n) * TAU : rnd(0, TAU)),
        speed: v(o.speed) * rnd(o.vary ? 1 - o.vary : 1, 1),
        size: v(o.size) * rnd(o.vary ? 1 - o.vary * 0.6 : 1, 1),
        life: v(o.life) * rnd(o.vary ? 1 - o.vary * 0.5 : 1, 1),
      });
    }
  }

  /** Light shards flying out of an impact: fast, stretched along their flight, slowing down. */
  shards(p, n, pal = 'gold', scale = 1, o = {}) {
    this.burst(p, n, { shape: 'shard', pal, speed: 110 * scale, vary: 0.6, drag: 4.2, size: 4.2 * scale, sizeK: 'spark', life: 0.6, alphaK: 'fade2', align: true, stretch: 0.012, gravity: 25, ...o });
    this.burst(p, Math.round(n * 0.6), { shape: 'star', pal, speed: 55 * scale, vary: 0.7, drag: 3, size: 2.4 * scale, sizeK: 'spark', life: 0.75, spin: 6, gravity: 40, ...o });
    this.burst(p, Math.round(n * 0.5), { shape: 'glow', pal, speed: 22 * scale, vary: 0.8, drag: 1.2, size: 1.6 * scale, sizeK: 'shrink', life: 1.4, alphaK: 'inout', gravity: -6, turb: 20, ...o });
  }

  /** A soft flash of light at a point (behind or in front). */
  flashAt(p, { size = 30, life = 0.35, pal = 'gold', layer = 'front', alpha = 1, sizeK = 'bloom', alphaK = 'flash' } = {}) {
    this.emit(p, { shape: 'glow', pal, size, life, layer, alpha, sizeK, alphaK, speed: 0 });
  }

  /** A glow that sits still and breathes for a while (a charge, a halo). */
  halo(p, { size = 20, life = 0.6, pal = 'gold', layer = 'back', alpha = 0.9 } = {}) {
    return this.emit(p, { shape: 'glow', pal, size, life, layer, alpha, sizeK: 'grow', alphaK: 'inout', speed: 0 });
  }

  /** Motes gather from a ring around a point into it (a charge-up). */
  converge(p, n, { r = 16, pal = 'gold', life = 0.45, size = 1.6, layer = 'front' } = {}) {
    const [cx, cy] = this.px(p);
    for (let i = 0; i < n; i++) {
      const a = rnd(0, TAU);
      const rr = r * rnd(0.6, 1.2) * this.u;
      const x = cx + Math.cos(a) * rr;
      const y = cy + Math.sin(a) * rr * 0.75;
      const part = this.emit([x, y], { raw: true, shape: i % 3 ? 'glow' : 'star', pal, size: size * rnd(0.6, 1.1), sizeK: 'grow', alphaK: 'inout', life: life * rnd(0.8, 1.1), layer, speed: 0, spin: 4 });
      part.seek = { x: cx, y: cy, k: 60 };
      part.drag = 2.5;
    }
  }

  /** Soft dust puffs at the ground. */
  dust(p, n = 8, { pal = 'dust', scale = 1, up = -12 } = {}) {
    this.burst(p, n, { shape: 'puff', pal, blend: 'source-over', speed: 22 * scale, vary: 0.6, angle: -Math.PI / 2, spread: 1.4, drag: 3.5, size: 7 * scale, sizeK: 'bloom', life: 0.8, alphaK: 'fade2', alpha: 0.9, gravity: up, spin: 1 });
  }

  /** Dark puffs (the Hollow). */
  smoke(p, n = 6, { scale = 1 } = {}) {
    this.burst(p, n, { shape: 'smoke', pal: 'dark', blend: 'source-over', speed: 16 * scale, vary: 0.6, drag: 2.5, size: 9 * scale, sizeK: 'bloom', life: 0.9, alphaK: 'fade2', alpha: 0.85, gravity: -10, spin: 0.8, turb: 10 });
  }

  /** Embers drifting up around a point (the Hollow's energy). */
  embers(p, n, { pal = 'violet', w = 14, h = 10, life = 1.6, layer = 'front', size = 2.2 } = {}) {
    for (let i = 0; i < n; i++) {
      const q = [p[0] + rnd(-w / 2, w / 2), p[1] + rnd(-h / 2, h / 2)];
      this.emit(q, { shape: 'glow', pal, size: size * rnd(0.5, 1.2), sizeK: 'shrink', alphaK: 'inout', life: life * rnd(0.7, 1.2), speed: rnd(2, 6), angle: -Math.PI / 2, spread: 0.5, gravity: -8, turb: 18, layer });
    }
  }

  /** Hearts rising. */
  hearts(p, n = 4, { pal = 'pink', spread = 6 } = {}) {
    for (let i = 0; i < n; i++) {
      const q = [p[0] + rnd(-spread, spread), p[1] + rnd(-2, 2)];
      this.emit(q, { shape: 'heart', pal, blend: 'source-over', size: rnd(3, 4.6), sizeK: 'pop', alphaK: 'hold', life: rnd(1.0, 1.4), speed: rnd(8, 14), angle: -Math.PI / 2, spread: 0.5, drag: 1.2, gravity: -6, turb: 14, spin: rnd(-1, 1) });
    }
  }

  /** Petals (or confetti) carried toward a point along a curve, then swirling around it. */
  stream(a, b, n, { pal = 'pink', shape = 'petal', ms = 700, swirl = true, size = 2.4 } = {}) {
    const [ax, ay] = this.px(a);
    const [bx, by] = this.px(b);
    const m = { layer: 'front', dead: false, t: 0, n, emitted: 0, ms, a: [ax, ay], b: [bx, by], pal, shape, swirl, size };
    m.tick = (dt, fx) => {
      m.t += dt * 1000;
      const want = Math.min(n, Math.floor((m.t / ms) * n) + 1);
      while (m.emitted < want) {
        m.emitted++;
        const d = Math.hypot(bx - ax, by - ay);
        const ang = Math.atan2(by - ay, bx - ax);
        const part = fx.emit([ax + rnd(-3, 3) * fx.u, ay + rnd(-6, 6) * fx.u], { raw: true, shape, pal, blend: 'source-over', size: size * rnd(0.7, 1.2), sizeK: 'hold', alphaK: 'hold', life: 1.8, speed: (d / fx.u) * rnd(0.8, 1.1), angle: ang, spread: 0.2, drag: 0.95, turb: 60, turbW: rnd(5, 9), spin: rnd(-8, 8) });
        part.seek = { x: bx + rnd(-4, 4) * fx.u, y: by + rnd(-4, 4) * fx.u, k: 6 };
        if (swirl) part.swirlAt = m.t / 1000 + rnd(0.7, 1.0);
      }
      if (m.emitted >= n && m.t > ms + 1900) m.dead = true;
    };
    m.draw = () => {};
    this.movers.push(m);
    // the swirl: once near the target, orbit it and fade
    const near = { layer: 'front', dead: false, t: 0 };
    near.tick = (dt, fx) => {
      near.t += dt;
      for (const p of fx.ps) {
        if (p.swirlAt == null || p.orbit) continue;
        const dx = p.x - bx;
        const dy = p.y - by;
        if (Math.hypot(dx, dy) < 9 * fx.u) {
          p.orbit = { x: bx, y: by, r: Math.max(5 * fx.u, Math.hypot(dx, dy)), a: Math.atan2(dy, dx), w: rnd(3, 5), dr: -1.6 * fx.u };
          p.life = p.age + rnd(0.7, 1.1);
          p.alphaK = 'hold';
        }
      }
      if (near.t > ms / 1000 + 2.2) near.dead = true;
    };
    near.draw = () => {};
    this.movers.push(near);
  }

  // ---------------------------------------------------------------- movers
  /** A bright head with a trail that flies from a to b along a bow; calls onArrive at the end. */
  comet(a, b, { ms = 240, pal = 'gold', size = 7, bow = -10, trail = 3, ease = 'in', layer = 'front', onArrive, sparks = true, img = null, imgSize = 6, spin = 0 } = {}) {
    const [ax, ay] = this.px(a);
    const [bx, by] = this.px(b);
    const cx = (ax + bx) / 2;
    const cy = (ay + by) / 2 + bow * this.u;
    const m = { layer, dead: false, t: 0, x: ax, y: ay, px: ax, py: ay, rot: 0 };
    const E = ease === 'in' ? easeIn : ease === 'out' ? easeOut : easeInOut;
    m.tick = (dt, fx) => {
      m.t += (dt * 1000) / ms;
      const k = E(clamp01(m.t));
      m.px = m.x;
      m.py = m.y;
      m.x = (1 - k) * (1 - k) * ax + 2 * (1 - k) * k * cx + k * k * bx;
      m.y = (1 - k) * (1 - k) * ay + 2 * (1 - k) * k * cy + k * k * by;
      // trail: glow dots laid along the path this frame
      for (let i = 0; i < trail; i++) {
        const f = i / trail;
        fx.emit([m.px + (m.x - m.px) * f, m.py + (m.y - m.py) * f], { raw: true, shape: 'glow', pal, size: size * rnd(0.6, 0.9), sizeK: 'shrink', alphaK: 'fade2', life: 0.32, speed: 0, layer });
      }
      if (sparks && Math.random() < 0.8) fx.emit([m.x, m.y], { raw: true, shape: 'star', pal, size: size * 0.35, sizeK: 'spark', life: 0.45, speed: rnd(6, 16), spin: 8, gravity: 30, layer });
      m.rot += spin * dt;
      if (m.t >= 1) {
        m.dead = true;
        onArrive?.();
      }
    };
    m.draw = (g, fx) => {
      const sp = sprite('glow', pal);
      const s = size * fx.u;
      const ang = Math.atan2(m.y - m.py, m.x - m.px);
      const v = Math.hypot(m.y - m.py, m.x - m.px) / fx.u;
      g.globalCompositeOperation = 'lighter';
      g.globalAlpha = 1;
      g.setTransform(1, 0, 0, 1, m.x, m.y);
      g.rotate(ang);
      const sx = 1 + Math.min(2.2, v * 0.25);
      g.drawImage(sp, (-s * sx) / 2, -s / 2, s * sx, s);
      if (!img) g.drawImage(sp, (-s * 0.5) / 2, (-s * 0.5) / 2, s * 0.5, s * 0.5);
      g.setTransform(1, 0, 0, 1, 0, 0);
      if (img && img.complete && img.naturalWidth) {
        // the thrown thing itself, turning over as it flies
        const is = imgSize * fx.u;
        g.globalCompositeOperation = 'source-over';
        g.setTransform(1, 0, 0, 1, m.x, m.y);
        g.rotate(m.rot);
        g.shadowColor = 'rgba(0,0,0,0.35)';
        g.shadowBlur = fx.u * 0.8;
        g.shadowOffsetY = fx.u * 0.5;
        g.drawImage(img, -is / 2, -is / 2, is, is);
        g.shadowBlur = 0;
        g.shadowOffsetY = 0;
        g.setTransform(1, 0, 0, 1, 0, 0);
      }
    };
    this.movers.push(m);
    return m;
  }

  /** A shockwave ring. r0 -> r1 in u. */
  ring(p, { r0 = 2, r1 = 30, ms = 450, pal = 'gold', width = 2.2, layer = 'front', alpha = 1, squash = 0.7, blend = 'lighter' } = {}) {
    const [x, y] = this.px(p);
    const [core, mid, edge] = PAL[pal] || PAL.white;
    const m = { layer, dead: false, t: 0 };
    m.tick = (dt) => {
      m.t += (dt * 1000) / ms;
      if (m.t >= 1) m.dead = true;
    };
    m.draw = (g, fx) => {
      const k = easeOut(clamp01(m.t));
      const r = (r0 + (r1 - r0) * k) * fx.u;
      const a = alpha * (1 - k) ** 1.3;
      const w = Math.max(0.5, width * fx.u * (1 - k * 0.7));
      g.globalCompositeOperation = blend;
      g.setTransform(1, 0, 0, 1, x, y);
      g.scale(1, squash);
      g.globalAlpha = a;
      g.lineWidth = w;
      g.strokeStyle = mid;
      g.shadowColor = edge;
      g.shadowBlur = w * 2.5;
      g.beginPath();
      g.arc(0, 0, r, 0, TAU);
      g.stroke();
      g.shadowBlur = 0;
      g.globalAlpha = a * 0.9;
      g.lineWidth = w * 0.45;
      g.strokeStyle = core;
      g.beginPath();
      g.arc(0, 0, r, 0, TAU);
      g.stroke();
      g.setTransform(1, 0, 0, 1, 0, 0);
    };
    this.movers.push(m);
    return m;
  }

  /** Rays of light turning slowly behind a point. */
  rays(p, { n = 7, r = 60, ms = 1800, pal = 'gold', layer = 'back', alpha = 0.55, spin = 0.5 } = {}) {
    const [x, y] = this.px(p);
    const [core, mid, edge] = PAL[pal] || PAL.white;
    const m = { layer, dead: false, t: 0, drawUnder: true, rot: rnd(0, TAU) };
    m.tick = (dt) => {
      m.t += (dt * 1000) / ms;
      m.rot += spin * dt;
      if (m.t >= 1) m.dead = true;
    };
    m.draw = (g, fx) => {
      const a = alpha * ALPHA.inout(clamp01(m.t));
      const R = r * fx.u * (0.6 + 0.4 * easeOut(clamp01(m.t * 2)));
      const grad = g.createRadialGradient(x, y, 0, x, y, R);
      grad.addColorStop(0, hexA(core, 0.9));
      grad.addColorStop(0.3, hexA(mid, 0.6));
      grad.addColorStop(1, hexA(edge, 0));
      g.globalCompositeOperation = 'lighter';
      g.globalAlpha = a;
      g.fillStyle = grad;
      for (let i = 0; i < n; i++) {
        const a0 = m.rot + (i / n) * TAU;
        const w = (TAU / n) * 0.34;
        g.beginPath();
        g.moveTo(x, y);
        g.arc(x, y, R, a0 - w / 2, a0 + w / 2);
        g.closePath();
        g.fill();
      }
      g.globalAlpha = 1;
    };
    this.movers.push(m);
    return m;
  }

  /** A soft vignette pulse in a colour (the Hollow's surge), drawn in front. */
  pulse({ pal = 'violet', ms = 700, alpha = 0.45 } = {}) {
    const [, mid, edge] = PAL[pal] || PAL.white;
    const m = { layer: 'front', dead: false, t: 0 };
    m.tick = (dt) => {
      m.t += (dt * 1000) / ms;
      if (m.t >= 1) m.dead = true;
    };
    m.draw = (g, fx) => {
      const a = alpha * ALPHA.soft(clamp01(m.t));
      const grad = g.createRadialGradient(fx.w / 2, fx.h / 2, fx.w * 0.25, fx.w / 2, fx.h / 2, fx.w * 0.8);
      grad.addColorStop(0, hexA(mid, 0));
      grad.addColorStop(1, hexA(edge, 1));
      g.globalCompositeOperation = 'source-over';
      g.globalAlpha = a;
      g.fillStyle = grad;
      g.fillRect(0, 0, fx.w, fx.h);
      g.globalAlpha = 1;
    };
    this.movers.push(m);
  }

  /** Motes of light leaving a body (the Hollow dissolving): emitted across a box for ms. */
  dissolve(box, { n = 70, ms = 600, pal = 'gold' } = {}) {
    const m = { layer: 'front', dead: false, t: 0, emitted: 0 };
    m.tick = (dt, fx) => {
      m.t += dt * 1000;
      const want = Math.min(n, Math.floor((m.t / ms) * n) + 1);
      while (m.emitted < want) {
        m.emitted++;
        const p = [box.x + rnd(0, box.w), box.y + rnd(0, box.h)];
        fx.emit(p, { shape: m.emitted % 4 ? 'glow' : 'star', pal, size: rnd(1.4, 3.2), sizeK: 'shrink', alphaK: 'inout', life: rnd(0.9, 1.6), speed: rnd(4, 12), angle: -Math.PI / 2, spread: 0.7, gravity: -14, turb: 24, spin: 5 });
      }
      if (m.emitted >= n) m.dead = true;
    };
    m.draw = () => {};
    this.movers.push(m);
  }

  // ---------------------------------------------------------------- ambient
  /** Slow motes in the air: 'gold' over the grove, 'hollow' (violet embers near the wild one), null off. */
  setAmbient(kind, region) {
    if (!kind) {
      this.ambient = null;
      return;
    }
    this.ambient = { kind, region, left: 0 };
  }

  emitAmbient() {
    const A = this.ambient;
    const R = A.region || { x: 0, y: 20, w: 100, h: 70 };
    if (A.kind === 'hollow') {
      A.left = 0.22;
      const p = [R.x + rnd(0, R.w), R.y + rnd(0, R.h)];
      this.emit(p, { shape: 'glow', pal: 'violet', size: rnd(1.2, 2.6), sizeK: 'shrink', alphaK: 'inout', life: rnd(1.6, 2.6), speed: rnd(2, 5), angle: -Math.PI / 2, spread: 0.6, gravity: -5, turb: 14, layer: Math.random() < 0.5 ? 'back' : 'front', alpha: 0.95 });
      if (Math.random() < 0.3) this.emit(p, { shape: 'smoke', pal: 'dark', blend: 'source-over', size: rnd(5, 9), sizeK: 'bloom', alphaK: 'inout', life: rnd(2, 3), speed: 2, angle: -Math.PI / 2, gravity: -3, alpha: 0.35, layer: 'back' });
    } else {
      A.left = 0.45;
      const p = [R.x + rnd(0, R.w), R.y + rnd(0, R.h)];
      this.emit(p, { shape: 'glow', pal: 'gold', size: rnd(0.9, 2.0), sizeK: 'hold', alphaK: 'inout', life: rnd(3.5, 6), speed: rnd(1, 3), angle: -Math.PI / 2, spread: 1.2, turb: 10, turbW: rnd(0.6, 1.5), layer: Math.random() < 0.6 ? 'back' : 'front', alpha: A.kind === 'won' ? 0.95 : 0.7 });
    }
  }
}

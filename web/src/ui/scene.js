// Layered 2.5D scene + animated pet (style guide §03 layering order, §20 animation).
// Back to front: sky -> far -> mid -> back decorations -> pet shadow -> pet -> front decorations -> near flora -> UI.
import { manifest, url, loadImage, imageIfReady, charEntry, frameRect, icon } from './assets.js';

const WORLD_SCALE = { 1: 0.205, 2: 0.2, 3: 0.165 };
const SPRITE_FPS = 30;

export class Scene {
  constructor(root) {
    this.root = root;
    root.innerHTML = '';
    this.el = document.createElement('div');
    this.el.className = 'scene';
    this.el.setAttribute('aria-hidden', 'false');
    root.appendChild(this.el);
    this.layers = {};
    for (const n of ['sky', 'far', 'mid']) this.layers[n] = this.addImg('layer layer-' + n);
    this.decorBack = this.addDiv();
    this.canvas = document.createElement('canvas');
    this.canvas.className = 'petcanvas';
    this.el.appendChild(this.canvas);
    this.decorFront = this.addDiv();
    this.layers.near = this.addImg('layer layer-near');
    this.tap = document.createElement('button');
    this.tap.className = 'tapzone';
    this.tap.style.background = 'transparent';
    this.tap.style.border = '0';
    this.el.appendChild(this.tap);
    this.cfg = {};
    this.habitat = null;
    this.reaction = null;
    this.particles = [];
    this.nextBlink = 0;
    this.blinkUntil = 0;
    this.nextIdle = 0;
    this.idleUntil = 0;
    this.idleExpr = null;
    this.t0 = performance.now();
    this.parallax = { x: 0, y: 0, tx: 0, ty: 0 };
    this.lastFrame = 0;
    this.running = false;
    this.onTap = null;
    this.tap.addEventListener('click', () => this.onTap && this.onTap());
    this.el.addEventListener('pointermove', (e) => {
      const r = this.el.getBoundingClientRect();
      this.parallax.tx = ((e.clientX - r.left) / r.width - 0.5) * 2;
      this.parallax.ty = ((e.clientY - r.top) / r.height - 0.5) * 2;
    });
    window.addEventListener('resize', () => this.layout());
    document.addEventListener('visibilitychange', () => (document.hidden ? this.stop() : this.start()));
    this.heartImg = null;
    this.starImg = null;
  }

  addImg(cls) {
    const i = document.createElement('img');
    i.className = cls;
    i.alt = '';
    i.decoding = 'async';
    this.el.appendChild(i);
    return i;
  }
  addDiv() {
    const d = document.createElement('div');
    d.style.position = 'absolute';
    d.style.inset = '0';
    d.style.pointerEvents = 'none';
    this.el.appendChild(d);
    return d;
  }

  /**
   * cfg: { habitat, focus: {x, y} (fractions of app size or px), zoom, decor: {slot:item}, platform,
   *        pet: {stage, palette, status, equipped:[ids], visible, scale, sleeping, label},
   *        reducedMotion, background }
   */
  configure(cfg) {
    this.cfg = cfg;
    const M = manifest();
    this.heartImg = this.heartImg || null;
    loadImage(M.icons.heart).then((i) => (this.heartImg = i));
    loadImage(M.icons.star).then((i) => (this.starImg = i));
    if (!cfg.habitat) {
      this.el.style.display = 'none';
      this.stop();
      return;
    }
    this.el.style.display = '';
    this.el.style.background = cfg.background || '#86C95B';
    const H = M.habitats[cfg.habitat];
    if (this.habitat !== cfg.habitat) {
      this.habitat = cfg.habitat;
      for (const n of ['sky', 'far', 'mid', 'near']) {
        const f = H.layers[n];
        this.layers[n].style.display = f ? '' : 'none';
        if (f) this.layers[n].src = url(f);
      }
    }
    // decorations
    const decorKeys = [];
    if (cfg.habitat === 'meadow') {
      if (cfg.platform) decorKeys.push(['platform@nest', 'back']);
      else if (cfg.decor) {
        for (const [slot, item] of Object.entries(cfg.decor)) {
          const key = `${item}@${slot}`;
          if (H.decor && H.decor[key]) decorKeys.push([key, slot === 'left' || slot === 'right' ? 'front' : 'back']);
        }
      }
    }
    this.decorEls = [];
    this.decorBack.innerHTML = '';
    this.decorFront.innerHTML = '';
    for (const [key, where] of decorKeys) {
      const d = H.decor[key];
      const img = document.createElement('img');
      img.src = url(d.file);
      img.alt = '';
      img.style.position = 'absolute';
      (where === 'front' ? this.decorFront : this.decorBack).appendChild(img);
      this.decorEls.push({ img, d });
    }
    const p = cfg.pet;
    if (p && p.visible !== false) {
      const e = charEntry(p.stage);
      loadImage(e.atlas[p.palette].file);
      loadImage(e.overlays.file);
      this.tap.style.display = '';
      this.tap.setAttribute('aria-label', p.label || 'Pet your Evochi');
    } else {
      this.tap.style.display = 'none';
    }
    this.layout();
    this.start();
  }

  layout() {
    const cfg = this.cfg;
    if (!cfg.habitat) return;
    const M = manifest();
    const H = M.habitats[cfg.habitat];
    const W = this.root.clientWidth || 390;
    const Hh = this.root.clientHeight || 844;
    this.W = W;
    this.H = Hh;
    const zoom = cfg.zoom || 1;
    let k = (W / H.w) * zoom;
    const anchor = cfg.anchorPx || H.pet;
    const fx = typeof cfg.focus?.x === 'number' ? (cfg.focus.x <= 1 ? cfg.focus.x * W : cfg.focus.x) : W / 2;
    const fy = typeof cfg.focus?.y === 'number' ? (cfg.focus.y <= 1 ? cfg.focus.y * Hh : cfg.focus.y) : Hh * 0.38;
    let ox = fx - anchor[0] * k;
    let oy = fy - anchor[1] * k;
    // keep the image covering the frame horizontally; never show a gap at the top
    ox = Math.min(0, Math.max(W - H.w * k, ox));
    oy = Math.min(0, oy);
    this.k = k;
    this.ox = ox;
    this.oy = oy;
    for (const n of ['sky', 'far', 'mid', 'near']) {
      const el = this.layers[n];
      el.style.width = H.w * k + 'px';
      el.style.left = ox + 'px';
      el.style.top = oy + 'px';
    }
    for (const { img, d } of this.decorEls || []) {
      img.style.left = ox + d.x * k + 'px';
      img.style.top = oy + d.y * k + 'px';
      img.style.width = d.w * k + 'px';
    }
    const dpr = Math.min(2.5, window.devicePixelRatio || 1);
    this.dpr = dpr;
    if (this.canvas.width !== Math.round(W * dpr) || this.canvas.height !== Math.round(Hh * dpr)) {
      this.canvas.width = Math.round(W * dpr);
      this.canvas.height = Math.round(Hh * dpr);
      this.canvas.style.width = W + 'px';
      this.canvas.style.height = Hh + 'px';
    }
    // pet ground point on screen
    this.ground = [ox + anchor[0] * k, oy + anchor[1] * k];
    const p = cfg.pet;
    if (p) {
      const e = charEntry(p.stage);
      const unit = (cfg.pxPerUnit || H.petPxPerUnit) * k * WORLD_SCALE[p.stage] * (p.scale || 1);
      this.petScale = unit / e.scale;
      const fw = e.w * this.petScale;
      const fh = e.h * this.petScale;
      const gx = this.ground[0];
      const gy = this.ground[1];
      const a = e.anchors.ground;
      const left = gx - a[0] * this.petScale;
      const top = gy - a[1] * this.petScale;
      this.petBox = { left, top, w: fw, h: fh };
      const tw = fw * 0.62;
      const th = fh * 0.8;
      this.tap.style.left = gx - tw / 2 + 'px';
      this.tap.style.top = gy - th + 'px';
      this.tap.style.width = tw + 'px';
      this.tap.style.height = th + 'px';
    }
  }

  /** Screen-space rect of the pet sprite (for positioning UI around it). */
  petRect() {
    return this.petBox;
  }

  react(kind) {
    const now = performance.now();
    const R = {
      pet: { expr: 'happy', motion: 'bounce', dur: 1000, burst: 'hearts' },
      play: { expr: 'excited', motion: 'hop', dur: 1300, burst: 'stars' },
      inspect: { expr: 'curious', motion: 'tilt', dur: 1200, emote: '?' },
      reward: { expr: 'happy', motion: 'bounce', dur: 1100, burst: 'stars' },
      surprised: { expr: 'surprised', motion: 'hop', dur: 900 },
      equip: { expr: 'happy', motion: 'wiggle', dur: 700, burst: 'stars' },
      sad: { expr: 'sad', motion: 'none', dur: 1400 },
      determined: { expr: 'determined', motion: 'bounce', dur: 900 },
    }[kind];
    if (!R) return;
    if (this.cfg.reducedMotion) R.motion = 'none';
    this.reaction = { ...R, start: now, until: now + R.dur };
    if (R.burst) this.burst(R.burst);
    if (R.emote) this.particles.push({ kind: 'emote', text: R.emote, born: now, life: R.dur });
  }

  burst(kind, n = 6) {
    const now = performance.now();
    if (this.cfg.reducedMotion) n = 2;
    for (let i = 0; i < n; i++) {
      this.particles.push({
        kind, born: now + i * 60, life: 1100 + Math.random() * 300,
        x: (Math.random() - 0.5) * 0.6, vx: (Math.random() - 0.5) * 0.25, vy: -0.6 - Math.random() * 0.4,
        s: 0.7 + Math.random() * 0.5, rot: (Math.random() - 0.5) * 0.6,
      });
    }
  }

  start() {
    if (this.running) return;
    this.running = true;
    const loop = (t) => {
      if (!this.running) return;
      if (t - this.lastFrame >= 1000 / SPRITE_FPS - 2) {
        this.lastFrame = t;
        this.draw(t);
      }
      this.raf = requestAnimationFrame(loop);
    };
    this.raf = requestAnimationFrame(loop);
  }

  stop() {
    this.running = false;
    if (this.raf) cancelAnimationFrame(this.raf);
  }

  baseExpr() {
    const p = this.cfg.pet;
    if (!p) return 'default';
    if (p.status === 'dead') return 'memorial';
    if (p.sleeping) return 'sleepy';
    if (p.status === 'sick') return 'sick';
    if (p.status === 'neutral') return 'neutral';
    return p.expr || 'default';
  }

  draw(t) {
    const g = this.canvas.getContext('2d');
    const dpr = this.dpr || 1;
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.clearRect(0, 0, this.W, this.H);
    const cfg = this.cfg;
    const reduce = !!cfg.reducedMotion;
    // parallax drift (pointer driven, very subtle)
    const P = this.parallax;
    P.x += (P.tx - P.x) * 0.05;
    P.y += (P.ty - P.y) * 0.05;
    if (!reduce) {
      const set = (n, f) => (this.layers[n].style.transform = `translate(${(-P.x * f).toFixed(2)}px, ${(-P.y * f * 0.5).toFixed(2)}px)`);
      set('far', 2.5);
      set('mid', 1.0);
      set('near', -2.5);
    }
    const p = cfg.pet;
    if (!p || p.visible === false || !this.petBox) return;
    const e = charEntry(p.stage);
    const atlas = imageIfReady(e.atlas[p.palette].file);
    if (!atlas) return;
    const now = t;
    let expr = this.baseExpr();
    const status = p.status;
    const alive = status !== 'dead';
    // reaction override
    let motion = 'none';
    let mt = 0;
    if (this.reaction && now < this.reaction.until) {
      expr = this.reaction.expr;
      motion = this.reaction.motion;
      mt = (now - this.reaction.start) / (this.reaction.until - this.reaction.start);
    } else this.reaction = null;
    // idle personality: occasional curious glance when healthy
    if (!this.reaction && alive && !p.sleeping && status === 'healthy' && !reduce) {
      if (!this.nextIdle) this.nextIdle = now + 7000 + Math.random() * 6000;
      if (now > this.nextIdle) {
        this.idleUntil = now + 1400;
        this.idleExpr = Math.random() < 0.5 ? 'curious' : 'happy';
        this.nextIdle = now + 9000 + Math.random() * 9000;
      }
      if (now < this.idleUntil) expr = this.idleExpr;
    }
    // blink
    if (alive && (expr === 'default' || expr === 'neutral')) {
      if (!this.nextBlink) this.nextBlink = now + 2500 + Math.random() * 3000;
      if (now > this.nextBlink) {
        this.blinkUntil = now + 130;
        this.nextBlink = now + 2600 + Math.random() * 3200;
      }
      if (now < this.blinkUntil) expr = 'blink';
    }
    if (cfg.forceExpr) expr = cfg.forceExpr;
    const r = frameRect(p.stage, p.palette, expr);
    const s = this.petScale;
    const gx = this.ground[0];
    const gy = this.ground[1];
    const a = e.anchors.ground;
    const tt = (now - this.t0) / 1000;
    // breathing (slower and shallower when unwell)
    const rate = status === 'sick' ? 0.22 : status === 'neutral' ? 0.3 : 0.38;
    const amp = !alive ? 0 : reduce ? 0.004 : status === 'sick' ? 0.008 : 0.014;
    let sx = 1 - amp * 0.5 * Math.sin(tt * Math.PI * 2 * rate);
    let sy = 1 + amp * Math.sin(tt * Math.PI * 2 * rate);
    let dy = 0;
    let rot = 0;
    if (motion === 'bounce') {
      const b = Math.sin(Math.min(1, mt * 2) * Math.PI);
      dy = -b * e.h * s * 0.08;
      sy *= 1 + b * 0.04;
      sx *= 1 - b * 0.03;
      if (mt > 0.5) {
        const b2 = Math.sin((mt - 0.5) * 2 * Math.PI);
        dy = -b2 * e.h * s * 0.035;
      }
    } else if (motion === 'hop') {
      const hops = 2;
      const ph = (mt * hops) % 1;
      const b = Math.sin(ph * Math.PI);
      dy = -b * e.h * s * 0.13;
      const squash = ph < 0.12 || ph > 0.88 ? 0.06 : 0;
      sy *= 1 - squash + b * 0.03;
      sx *= 1 + squash;
    } else if (motion === 'tilt') {
      rot = Math.sin(Math.min(1, mt * 1.6) * Math.PI) * 0.09;
    } else if (motion === 'wiggle') {
      rot = Math.sin(mt * Math.PI * 6) * 0.05 * (1 - mt);
    }
    // shadow
    const shW = e.w * s * (p.stage === 1 ? 0.42 : 0.5) * (1 + dy / (e.h * s) * 0.8);
    g.save();
    g.fillStyle = 'rgba(52, 38, 22, 0.22)';
    g.beginPath();
    g.ellipse(gx, gy - 2, Math.max(4, shW), Math.max(2, shW * 0.16), 0, 0, Math.PI * 2);
    g.fill();
    g.restore();
    // sprite + overlays
    g.save();
    g.translate(gx, gy + dy);
    g.rotate(rot);
    g.scale(s * sx, s * sy);
    if (!alive) g.globalAlpha = 0.92;
    g.imageSmoothingQuality = 'high';
    g.drawImage(atlas, r[0], r[1], r[2], r[3], -a[0], -a[1], r[2], r[3]);
    const ov = imageIfReady(e.overlays.file);
    if (ov && alive) {
      for (const id of p.equipped || []) {
        const orr = e.overlays.rects[id];
        if (orr) g.drawImage(ov, orr[0], orr[1], orr[2], orr[3], -a[0], -a[1], orr[2], orr[3]);
      }
    }
    g.restore();
    // particles & emotes
    const head = [gx + (e.anchors.head_top[0] - a[0]) * s, gy + dy + (e.anchors.head_top[1] - a[1]) * s];
    this.drawParticles(g, now, head, e.h * s);
    if (p.sleeping && alive && !reduce) this.drawZ(g, tt, head);
    if (status === 'sick' && !reduce) this.drawSweat(g, tt, head, e.w * s);
  }

  drawParticles(g, now, head, h) {
    const keep = [];
    for (const q of this.particles) {
      const age = now - q.born;
      if (age < 0) {
        keep.push(q);
        continue;
      }
      if (age > q.life) continue;
      keep.push(q);
      const k = age / q.life;
      const alpha = k < 0.15 ? k / 0.15 : 1 - Math.max(0, (k - 0.6) / 0.4);
      g.save();
      g.globalAlpha = Math.max(0, alpha);
      if (q.kind === 'emote') {
        const bob = Math.sin(k * Math.PI) * 6;
        g.font = '900 34px Nunito, sans-serif';
        g.textAlign = 'center';
        g.lineWidth = 6;
        g.strokeStyle = '#FFF9F0';
        g.fillStyle = '#3B2923';
        g.strokeText(q.text, head[0] + h * 0.32, head[1] - 4 - bob);
        g.fillText(q.text, head[0] + h * 0.32, head[1] - 4 - bob);
      } else {
        const x = head[0] + (q.x + q.vx * k * 2) * h;
        const y = head[1] + h * 0.25 + q.vy * k * h * 0.7;
        const img = q.kind === 'hearts' ? this.heartImg : this.starImg;
        const size = 22 * q.s;
        if (img) {
          g.translate(x, y);
          g.rotate(q.rot * k);
          g.drawImage(img, -size / 2, -size / 2, size, size);
        }
      }
      g.restore();
    }
    this.particles = keep;
  }

  drawZ(g, tt, head) {
    g.save();
    g.font = '900 22px Nunito, sans-serif';
    g.fillStyle = '#3B2923';
    g.strokeStyle = '#FFF9F0';
    g.lineWidth = 5;
    for (let i = 0; i < 2; i++) {
      const k = (tt * 0.35 + i * 0.5) % 1;
      g.globalAlpha = Math.sin(k * Math.PI);
      const x = head[0] + 30 + k * 18;
      const y = head[1] + 10 - k * 34;
      g.font = `900 ${16 + i * 6}px Nunito, sans-serif`;
      g.strokeText('z', x, y);
      g.fillText('z', x, y);
    }
    g.restore();
  }

  drawSweat(g, tt, head, w) {
    const k = (tt * 0.4) % 1;
    g.save();
    g.globalAlpha = Math.sin(k * Math.PI) * 0.9;
    g.fillStyle = '#9BD3F0';
    g.strokeStyle = '#2D6A8C';
    g.lineWidth = 1.5;
    const x = head[0] + w * 0.32;
    const y = head[1] + w * 0.2 + k * 10;
    g.beginPath();
    g.moveTo(x, y - 9);
    g.quadraticCurveTo(x + 6, y, x, y + 4);
    g.quadraticCurveTo(x - 6, y, x, y - 9);
    g.fill();
    g.stroke();
    g.restore();
  }
}

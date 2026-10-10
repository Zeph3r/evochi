// S07 Pet details (Inspect), evolution cinematic (§16) and S12 Recovery / Memorial (§17).
import * as G from '../game/state.js';
import { CONFIG } from '../game/config.js';
import { ITEMS, SLOT_LABEL } from '../game/catalog.js';
import { html, raw, fmt, duration } from '../ui/dom.js';
import { icon, itemImg, spriteAttr, BLANK, charEntry, loadImage, frameRect, manifest } from '../ui/assets.js';
import { ICON } from '../ui/icons.js';
import { stageLabel, statusTag, nav } from '../core/app.js';
import { petScene, openCareSheet } from './home.js';

const KIND = {
  goal: ['Goal met', 'ok', '+'], active: ['Active', 'stage', '+'], light: ['Light day', 'cream', ''], rest: ['Rest day', 'neutral', ''],
  low: ['Low day', 'danger', '-'], grace: ['Grace', 'cream', ''], pending: ['Sync pending', 'neutral', ''], dead: ['Resting', 'neutral', ''],
};

export const inspect = {
  id: 'inspect',
  scene(ctx) {
    return petScene(ctx, { focus: { x: 0.5, y: ctx.ui('inspect').groundY || 0.3 } });
  },
  afterLayout(ctx, el) {
    const sh = el.querySelector('.sheet-bg');
    const top = sh.getBoundingClientRect().top - ctx.app.root.getBoundingClientRect().top;
    ctx.ui('inspect').groundY = Math.round(Math.max(150, Math.min(top - 18, ctx.H * 0.36)));
    return inspect.scene(ctx);
  },
  onPetTap(ctx) {
    ctx.act(G.interact, 'pet');
    ctx.scene.react('pet');
    ctx.sfx('pet_chirp');
  },
  render(ctx) {
    const s = ctx.state;
    const p = s.pet;
    const d = ctx.d;
    const dp = d.pet;
    const ev = dp.evo;
    const u = ctx.ui('inspect');
    const view = u.view || null;
    const recent = dp.vitalityLog.filter((x) => x.key).slice(-7);
    const vitCls = dp.vitality >= 70 ? 'green' : dp.vitality >= 35 ? 'amber' : 'red';
    return html`<main class="screen scroll" aria-label="${p.name} details">
      <div class="hud" style="justify-content:flex-start"><button class="back-btn" data-act="back" aria-label="Back" data-k="iback">${ICON.back}</button></div>
      <div style="flex:none;height:max(190px, 30vh)"></div>
      <section class="sheet-bg stack" style="padding:16px 14px 20px;gap:10px;z-index:3;min-height:60%">
        <div class="row between">
          <div><h1 class="h-page" tabindex="-1" data-autofocus>${p.name}</h1><div class="row" style="gap:6px;margin-top:4px"><span class="tag stage">${stageLabel(p.stage)}</span>${statusTag(dp.status)}<span class="tag cream">${G.PALETTES.find((x) => x.id === p.paletteId).label}</span></div></div>
          <div class="center"><div class="lv">Lv. <b class="num">${dp.level}</b></div><div class="tiny muted">${fmt(dp.totalXp)} XP total</div></div>
        </div>
        <div class="card" style="padding:10px">
          <div class="mini-head"><h2 class="h-card">Turnaround</h2><small>Tap a view</small></div>
          <div class="turn" style="margin-top:6px" role="group" aria-label="Views">
            ${['front', 'left', 'back', 'right', 'top'].map((v) => html`<button aria-pressed="${view === v}" data-act="view" data-arg="${v}" data-k="tv-${v}"><img data-sprite="${spriteAttr(p.stage, p.paletteId, 'default', [], v, 90)}" src="${BLANK}" alt="">${v}</button>`)}
          </div>
          ${view ? html`<div class="center" style="margin-top:8px;background:radial-gradient(circle at 50% 60%,#FFF9EC,#F2E3CF);border-radius:12px;padding:8px"><img data-sprite="${spriteAttr(p.stage, p.paletteId, 'default', [], view, 200)}" src="${BLANK}" alt="${p.name} ${view} view" style="max-height:170px;max-width:100%"></div>` : ''}
        </div>
        <div class="card" style="padding:12px">
          <div class="row"><img src="${icon('heart')}" alt="" width="26" height="26"><b class="h-card grow">Vitality</b><b class="num">${dp.vitality} / 100</b></div>
          <div class="bar ${vitCls}" style="margin:8px 0 6px" role="progressbar" aria-label="Vitality" aria-valuenow="${dp.vitality}" aria-valuemin="0" aria-valuemax="100"><i style="width:${dp.vitality}%"></i></div>
          <div class="row" style="flex-wrap:wrap;gap:4px">${recent.length ? recent.map((x) => html`<span class="tag small ${KIND[x.kind][1]}" title="${x.key}">${x.key.slice(5)} ${KIND[x.kind][0]}${x.delta ? ` ${x.delta > 0 ? '+' : ''}${x.delta}` : ''}</span>`) : html`<span class="small muted">Day results appear here after each day ends.</span>`}</div>
          <div class="row between" style="margin-top:8px"><span class="small muted">Walking 50% of your goal restores +${CONFIG.vitality.restoreHalf}, 100% restores +${CONFIG.vitality.restoreFull}. Two low days a week are protected rest days.</span><button class="btn sm cream" data-act="care" data-k="icare">Care</button></div>
        </div>
        <div class="card" style="padding:12px">
          <div class="row"><img src="${icon('evolve')}" alt="" width="26" height="26"><b class="h-card grow">Evolution Path</b></div>
          ${ev.maxed ? html`<p class="body" style="margin:8px 0 0">${p.name} has reached the Elder form. Keep leveling for cosmetics, quests and future discoveries.</p>` : html`
            <p class="small muted" style="margin:6px 0">Next form: <b>${stageLabel(ev.next)}</b></p>
            <div class="row"><span class="small grow" style="font-weight:700">Level ${dp.level} / ${ev.req.level}</span>${ev.levelOk ? html`<span class="tag small ok">Done</span>` : ''}</div>
            <div class="bar" style="height:10px;margin:4px 0 8px"><i style="width:${ev.levelProgress * 100}%"></i></div>
            <div class="row"><span class="small grow" style="font-weight:700">Active days ${dp.activeDays} / ${ev.req.activeDays}</span>${ev.daysOk ? html`<span class="tag small ok">Done</span>` : ''}</div>
            <div class="bar green" style="height:10px;margin:4px 0 8px"><i style="width:${ev.daysProgress * 100}%"></i></div>
            <p class="small muted" style="margin:0 0 8px">An active day means reaching at least half your step goal.</p>
            <button class="btn block" data-act="evolve" ${ev.eligible && !dp.dead ? '' : raw('disabled')} data-k="i-evolve"><img class="ico" src="${icon('evolve')}" alt=""><span>${ev.eligible ? `Evolve into ${stageLabel(ev.next)}` : 'Not ready yet'}</span></button>`}
        </div>
        <div class="card" style="padding:12px">
          <div class="row between"><b class="h-card">Equipped</b><button class="btn sm cream" data-act="tab" data-arg="bag" data-k="ibag">Open Bag</button></div>
          <div class="row" style="gap:8px;margin-top:8px">${['head', 'neck', 'back'].map((sl) => {
            const id = p.equipped?.[sl];
            return html`<div class="tile" style="flex:1;min-height:0;cursor:default"><img src="${id ? itemImg(id) : icon('wearables')}" alt="" style="width:44px;height:44px;${id ? '' : 'opacity:.3;filter:grayscale(1)'}"><span class="nm">${id ? ITEMS[id].name : SLOT_LABEL[sl] + ': empty'}</span></div>`;
          })}</div>
        </div>
        <div class="card kv" style="padding:12px">
          <span>Bond</span><b>${dp.bond} / 100</b>
          <span>Active days</span><b>${dp.activeDays}</b>
          <span>Verified steps together</span><b>${fmt(dp.lifetimeSteps)}</b>
          <span>Days together</span><b>${dp.daysTogether}</b>
          <span>Hatched</span><b>${new Date(p.createdAt).toLocaleDateString()}</b>
        </div>
      </section>
    </main>`;
  },
  actions: {
    view(ctx, v) {
      const u = ctx.ui('inspect');
      u.view = u.view === v ? null : v;
      ctx.rerender();
    },
    care(ctx) {
      openCareSheet(ctx);
    },
    evolve(ctx) {
      ctx.go('evolve');
    },
  },
};

// ------------------------------------------------------------- evolution
export const evolveScreen = {
  id: 'evolve',
  scene(ctx) {
    return petScene(ctx, { focus: { x: 0.5, y: 0.45 } });
  },
  render(ctx) {
    const u = ctx.ui('evolve');
    return html`<main class="screen" aria-label="Evolution">
      <div class="evolve-overlay">
        <button class="btn sm cream skip" data-act="skip" data-k="evo-skip" aria-label="Skip animation">Skip</button>
        <canvas aria-hidden="true"></canvas>
        <div class="stack center" style="position:absolute;bottom:calc(40px + var(--safe-bottom));left:20px;right:20px;opacity:${u.done ? 1 : 0};transition:opacity .4s" aria-live="polite">
          ${u.done ? html`<div class="card stack center" style="padding:16px">
            <h1 class="h-page">${ctx.state.pet.name} became a ${stageLabel(ctx.state.pet.stage)}!</h1>
            <p class="body" style="margin:0">New form unlocked in your EvoDex. Colours, bond, name and accessories all carried over.</p>
            ${u.removed?.length ? html`<p class="small muted" style="margin:0">Returned to your Bag: ${u.removed.map((id) => ITEMS[id].name).join(', ')}</p>` : ''}
            <button class="btn lg block" data-act="finish" data-autofocus data-k="evo-done">Wonderful!</button></div>` : ''}
        </div>
      </div>
    </main>`;
  },
  mount(ctx, el) {
    const u = ctx.ui('evolve');
    if (u.running || u.done) {
      if (u.running) attachCanvas(ctx, el, u);
      return;
    }
    // commit the evolution first so skipping or closing can never lose it
    const fromStage = ctx.state.pet.stage;
    const r = ctx.act(G.evolve);
    if (r.error) {
      ctx.back();
      return;
    }
    const ev = r.events.find((e) => e.type === 'evolved');
    Object.assign(u, { running: true, from: fromStage, to: ev.stage, removed: ev.removed, start: performance.now() });
    ctx.track('evolution_completed', { stage: ev.stage });
    ctx.sfx('evolve_fanfare', 0.7);
    attachCanvas(ctx, ctx.app.host.firstElementChild, u);
  },
  actions: {
    skip(ctx) {
      const u = ctx.ui('evolve');
      u.running = false;
      u.done = true;
      ctx.rerender();
    },
    finish(ctx) {
      ctx.app.ui.evolve = {};
      ctx.app.tab('home');
      setTimeout(() => ctx.app.scene.react('reward'), 300);
    },
  },
};

function attachCanvas(ctx, el, u) {
  const cv = el.querySelector('canvas');
  if (!cv || cv === u.canvas) return;
  // The screen re-renders when the reveal card appears. Copy the last drawn frame onto the new
  // canvas right away so the pet never blinks out while the atlases are (re)fetched.
  if (u.canvas && u.canvas.width) {
    cv.width = u.canvas.width;
    cv.height = u.canvas.height;
    cv.getContext('2d').drawImage(u.canvas, 0, 0);
  }
  u.canvas = cv;
  const p = ctx.state.pet;
  const eFrom = charEntry(u.from);
  const eTo = charEntry(u.to);
  Promise.all([loadImage(eFrom.atlas[p.paletteId].file), loadImage(eTo.atlas[p.paletteId].file)]).then(([a, b]) => {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const W = cv.clientWidth;
    const H = cv.clientHeight;
    cv.width = W * dpr;
    cv.height = H * dpr;
    const g = cv.getContext('2d');
    const reduce = ctx.app.reducedMotion;
    u.parts = u.parts || Array.from({ length: 40 }, () => ({ a: Math.random() * Math.PI * 2, r: 0.6 + Math.random() * 0.6, s: 2 + Math.random() * 4 }));
    const parts = u.parts;
    const drawSprite = (img, e, expr, alpha, white, scaleMul) => {
      const r = frameRect(u.to === e ? u.to : u.from, p.paletteId, expr);
      const rr = e === eTo ? frameRect(u.to, p.paletteId, expr) : frameRect(u.from, p.paletteId, expr);
      const sc = Math.min((W * 0.8) / e.w, (H * 0.75) / e.h) * scaleMul;
      const gx = W / 2;
      const gy = H * 0.82;
      const an = e.anchors.ground;
      g.save();
      g.globalAlpha = alpha;
      g.translate(gx, gy);
      g.scale(sc, sc);
      if (white) {
        const off = document.createElement('canvas');
        off.width = rr[2];
        off.height = rr[3];
        const og = off.getContext('2d');
        og.drawImage(img, rr[0], rr[1], rr[2], rr[3], 0, 0, rr[2], rr[3]);
        og.globalCompositeOperation = 'source-atop';
        og.fillStyle = `rgba(255, 246, 214, ${white})`;
        og.fillRect(0, 0, rr[2], rr[3]);
        g.drawImage(off, -an[0], -an[1]);
      } else g.drawImage(img, rr[0], rr[1], rr[2], rr[3], -an[0], -an[1], rr[2], rr[3]);
      g.restore();
    };
    const loop = (t) => {
      if (u.canvas !== cv) return; // a newer canvas took over after a re-render
      if (!u.running || !cv.isConnected) return;
      const T = (t - u.start) / 1000;
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.clearRect(0, 0, W, H);
      const cx = W / 2;
      const cy = H * 0.55;
      if (reduce) {
        // crossfade only, no flashes
        const k = Math.min(1, Math.max(0, (T - 0.5) / 1.5));
        drawSprite(a, eFrom, 'default', 1 - k, 0, 1);
        drawSprite(b, eTo, 'happy', k, 0, 1);
      } else if (T < 1.4) {
        const glow = Math.min(1, T / 1.4);
        drawSprite(a, eFrom, 'surprised', 1, glow * 0.65, 1 + 0.02 * Math.sin(T * 30) * glow);
        for (const q of parts) {
          const rr = (1 - glow) * q.r * W * 0.6 + 40;
          g.fillStyle = `rgba(255, 236, 160, ${glow})`;
          g.fillRect(cx + Math.cos(q.a + T) * rr, cy + Math.sin(q.a + T) * rr * 0.7, q.s, q.s);
        }
      } else if (T < 2.3) {
        const k = (T - 1.4) / 0.9;
        const white = 1 - Math.abs(k - 0.5) * 0.4;
        drawSprite(k < 0.5 ? a : b, k < 0.5 ? eFrom : eTo, 'default', 1, white, 0.9 + k * 0.15);
        g.fillStyle = `rgba(255, 245, 210, ${0.35 * Math.sin(k * Math.PI)})`;
        g.beginPath();
        g.arc(cx, cy, W * 0.45, 0, Math.PI * 2);
        g.fill();
      } else {
        const k = Math.min(1, (T - 2.3) / 0.9);
        drawSprite(b, eTo, k < 0.6 ? 'excited' : 'happy', 1, Math.max(0, 0.6 - k), 1.05 - 0.05 * k);
        for (const q of parts) {
          const rr = k * q.r * W * 0.5 + 30;
          g.fillStyle = `rgba(255, 220, 120, ${1 - k})`;
          g.fillRect(cx + Math.cos(q.a) * rr, cy + Math.sin(q.a) * rr * 0.7 - k * 30, q.s, q.s);
        }
      }
      if (T > 3.2 && !u.done) {
        u.done = true;
        ctx.rerender();
      }
      requestAnimationFrame(loop);
    };
    loop(); // draw now: sizing the canvas above cleared it, and the next frame may be a screen later
  });
}

// ------------------------------------------------------------- memorial
export const memorialView = {
  scene(ctx) {
    return petScene(ctx, { focus: { x: 0.5, y: ctx.ui('memorial').groundY || 0.34 } });
  },
  afterLayout(ctx, el) {
    const c = el.querySelector('.memorial-card');
    if (!c) return null;
    const top = c.getBoundingClientRect().top - ctx.app.root.getBoundingClientRect().top;
    ctx.ui('memorial').groundY = Math.round(Math.max(150, top - 20));
    return memorialView.scene(ctx);
  },
  render(ctx) {
    const s = ctx.state;
    const p = s.pet;
    const d = ctx.d;
    const dp = d.pet;
    const herbs = G.ownedQty(s, 'healing_herb');
    const need = CONFIG.care.revive.herbCost;
    const walkPct = Math.min(1, d.todaySteps / d.goal);
    return html`<main class="screen scroll" aria-label="Memorial">
      <div style="position:absolute;inset:0;background:linear-gradient(rgba(70,58,80,0.45),rgba(40,30,30,0.15) 45%,transparent);pointer-events:none"></div>
      <div class="hud"><div></div><div class="hud-col"><button class="sq-btn" data-act="settings" aria-label="Settings" data-k="set"><img src="${icon('settings')}" alt=""></button></div></div>
      <div style="flex:none;height:max(200px, 32vh)"></div>
      <section class="card memorial-card stack" style="margin:0 12px;padding:16px;gap:10px;z-index:3">
        <h1 class="h-page center" tabindex="-1" data-autofocus>${p.name} is resting</h1>
        <p class="body center" style="margin:0">Your Evochi ran out of vitality and has gone quiet in the nest. You can rekindle it, or let it rest and start a new egg.</p>
        <div class="kv card inset" style="padding:10px 12px">
          <span>Peak level</span><b>${dp.level}</b>
          <span>Form reached</span><b>${stageLabel(p.stage)}</b>
          <span>Time together</span><b>${dp.daysTogether} days</b>
          <span>Verified steps together</span><b>${fmt(dp.lifetimeSteps)}</b>
        </div>
        <div class="card" style="padding:10px">
          <div class="row"><img src="${icon('steps')}" alt="" width="30" height="30"><b class="h-card grow">Rekindle with a walk</b><span class="tag small ok">Free</span></div>
          <div class="bar green" style="margin:8px 0 4px"><i style="width:${walkPct * 100}%"></i></div>
          <div class="small muted">${fmt(d.todaySteps)} / ${fmt(d.goal)} steps today</div>
          <button class="btn green block" style="margin-top:8px" data-act="revive-walk" ${walkPct >= 1 ? '' : raw('disabled')} data-k="rv-walk">Rekindle ${p.name}</button>
        </div>
        <div class="card" style="padding:10px">
          <div class="row"><img src="${itemImg('healing_herb')}" alt="" width="34" height="34"><b class="h-card grow">Use ${need} Healing Herbs</b><span class="tag small cream">You have ${herbs}</span></div>
          <button class="btn block" style="margin-top:8px" data-act="revive-herbs" ${herbs >= need ? '' : raw('disabled')} data-k="rv-herb">Rekindle with herbs</button>
          ${herbs < need ? html`<p class="small muted" style="margin:6px 0 0">Herbs are sold for EvoCoins in the Market's Care tab.</p>` : ''}
        </div>
        <button class="btn cream block" data-act="new-egg" data-k="newegg"><img class="ico" src="${icon('paw')}" alt=""><span>Start a New Egg</span></button>
        <p class="small muted center" style="margin:0">Cosmetics, coins and decorations always stay with your account.</p>
      </section>
      <div style="height:12px;flex:none"></div>
      ${nav(ctx, 'home')}
    </main>`;
  },
};

export const memorialActions = {
  'revive-walk'(ctx) {
    const r = ctx.act(G.reviveWithWalk);
    if (!r.error) {
      ctx.toast(`${ctx.state.pet.name} is back!`, 'ok', 'heart');
      ctx.sfx('level_up');
      setTimeout(() => ctx.app.scene.react('reward'), 300);
    }
  },
  'revive-herbs'(ctx) {
    const r = ctx.act(G.reviveWithHerbs);
    if (!r.error) {
      ctx.toast(`${ctx.state.pet.name} is back!`, 'ok', 'heart');
      ctx.sfx('level_up');
      setTimeout(() => ctx.app.scene.react('reward'), 300);
    }
  },
  'new-egg'(ctx) {
    ctx.modal({
      label: 'Start a new egg',
      render: (c) => html`<div class="stack">
        <h2 class="h-sec">Let ${c.state.pet.name} rest?</h2>
        <p class="body">${c.state.pet.name} will be remembered in your EvoDex Hall of Memories. You'll keep every cosmetic, decoration and EvoCoin.</p>
        <button class="btn block" data-act="confirm-egg" data-autofocus>Start a New Egg</button>
        <button class="btn cream block" data-act="modal-close">Not yet</button></div>`,
      actions: {
        'confirm-egg': (c) => {
          c.closeModal();
          c.sfx('memorial', 0.6);
          c.act(G.memorialize);
        },
      },
    });
  },
};

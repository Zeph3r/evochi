// UI core: routing, rendering, HUD/nav chrome, toasts, modals and engine-event fan-out.
import { setLook } from '../ui/puppet.js';
import * as G from '../game/state.js';
import { CONFIG } from '../game/config.js';
import { ITEMS } from '../game/catalog.js';
import { QUEST_MATERIALS, QUESTS } from '../game/story.js';
import { html, raw, esc, fmt, $, $$ } from '../ui/dom.js';
import { icon, itemImg, title, url, hydrateSprites, manifest } from '../ui/assets.js';
import { ICON } from '../ui/icons.js';
import * as audio from '../ui/audio.js';
import { Scene } from '../ui/scene.js';

const TABS = [
  { id: 'home', label: 'Home', icon: 'home' },
  { id: 'journey', label: 'Journey', icon: 'journey' },
  { id: 'bag', label: 'Bag', icon: 'bag' },
  { id: 'shop', label: 'Shop', icon: 'shop' },
  { id: 'evodex', label: 'EvoDex', icon: 'evodex' },
];

export class App {
  constructor(root, store, screens) {
    this.root = root;
    this.store = store;
    this.screens = screens;
    this.ui = {}; // per-screen persistent ui state
    this.route = null;
    this.history = [];
    this.modals = [];
    this.toastQ = [];
    this.scrolls = {};
    root.innerHTML = `<div class="scene-host" style="position:absolute;inset:0"></div><div class="screen-host" style="position:absolute;inset:0;z-index:2"></div><div class="modal-host"></div><div class="toasts" role="status" aria-live="polite"></div><div class="overlay-host"></div>`;
    this.sceneHost = $('.scene-host', root);
    this.host = $('.screen-host', root);
    this.modalHost = $('.modal-host', root);
    this.toastHost = $('.toasts', root);
    this.overlayHost = $('.overlay-host', root);
    this.scene = new Scene(this.sceneHost);
    this.scene.onTap = () => this.screen()?.onPetTap?.(this.ctx());
    store.subscribe(() => this.schedule());
    store.onEvents((evs) => this.handleEvents(evs));
    root.addEventListener('click', (e) => this.onClick(e));
    root.addEventListener('input', (e) => this.onInput(e));
    root.addEventListener('change', (e) => this.onInput(e));
    root.addEventListener('keydown', (e) => this.onKey(e));
    root.addEventListener('pointerdown', () => {
      audio.unlock();
      this.lastInput = Date.now();
      if (this.route?.id === 'home') this.refreshScene();
    }, { passive: true });
    root.addEventListener('keydown', () => (this.lastInput = Date.now()));
    root.addEventListener('scroll', (e) => {
      const t = e.target;
      if (t && t.scrollLeft) t.scrollLeft = 0;
    }, true);
    this.lastInput = Date.now();
    window.addEventListener('resize', () => this.schedule());
    this.applySettings();
    // minute tick: keeps clocks, cooldowns and day rollovers fresh
    setInterval(() => this.schedule(), 30000);
    // quiet-state check: lets the pet doze off when nobody has touched the app for a while
    setInterval(() => {
      if (this.route?.id === 'home') this.refreshScene();
    }, 5000);
  }

  // ------------------------------------------------------------ context
  ctx() {
    const store = this.store;
    const self = this;
    return {
      app: this,
      store,
      state: store.state,
      d: store.derived(),
      now: store.now(),
      ui: (id) => (this.ui[id] = this.ui[id] || {}),
      go: (r, p) => this.go(r, p),
      back: () => this.back(),
      act: (fn, ...args) => this.act(fn, ...args),
      toast: (m, k, i) => this.toast(m, k, i),
      modal: (spec) => this.openModal(spec),
      closeModal: () => this.closeModal(),
      sfx: (n, v) => this.sfx(n, v),
      scene: this.scene,
      rerender: () => this.schedule(),
      track: (n, p) => store.track(n, p),
      get settings() {
        return store.state.player?.settings || {};
      },
      W: self.root.clientWidth,
      H: self.root.clientHeight,
    };
  }

  screen() {
    return this.screens[this.route?.id];
  }

  /** Re-derive only the scene (pet pose/sleep) without touching the DOM, so taps are never swallowed. */
  refreshScene() {
    const scr = this.screen();
    if (!scr?.scene) return;
    const sc = scr.scene(this.ctx());
    if (!sc) return;
    sc.reducedMotion = this.reducedMotion;
    const sig = JSON.stringify(sc);
    if (sig !== this.sceneSig) {
      this.sceneSig = sig;
      this.scene.configure(sc);
    }
  }

  act(fn, ...args) {
    const now = this.store.now();
    const res = this.store.run(fn, ...args, now);
    if (res.error) this.errorToast(res);
    return res;
  }

  errorToast(res) {
    const M = {
      insufficient: [`Not enough EvoCoins - ${fmt(res.short || 0)} more needed`, 'warn', 'coin'],
      owned: ['You already own this', 'warn', 'bag'],
      not_eligible: ['Not ready yet - keep walking!', 'warn', 'steps'],
      pet_dead: ['Your Evochi is resting in the memorial', 'warn', 'heart_empty'],
      full: ['Vitality is already full', 'ok', 'heart'],
      cooldown: ['Recovery items need a short rest between uses', 'warn', 'potion'],
      no_anchor: ['That decoration does not fit this spot', 'warn', 'decorations'],
      all_placed: ['All of those are already placed', 'warn', 'decorations'],
      incompatible: ["This accessory doesn't fit your Evochi's current form", 'warn', 'wearables'],
      invalid_name: [res.message || 'Check the name', 'warn', 'paw'],
      need_herbs: [`You need ${res.need} Healing Herbs`, 'warn', 'care'],
      walk_needed: ["Reach today's step goal to rekindle", 'warn', 'steps'],
      not_owned: ['You do not own this yet', 'warn', 'bag'],
      not_for_sale: ['Story rewards are earned, never sold', 'warn', 'star'],
      story_locked: [res.message || 'Not unlocked yet', 'warn', 'lock'],
      story_not_ready: ['Not ready yet - keep going!', 'warn', 'journey'],
      story_missing_items: ['Something is missing from your Quest Pouch', 'warn', 'journey'],
    };
    const [m, k, i] = M[res.error] || ['Something went wrong - please try again', 'err', 'warning'];
    this.toast(m, k, i);
    this.sfx('error_bonk', 0.5);
  }

  sfx(name, vol) {
    audio.play(name, vol);
  }

  applySettings() {
    const s = this.store.state.player?.settings;
    const rm = s?.reducedMotion || window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    this.root.classList.toggle('reduced-motion', !!rm);
    this.reducedMotion = !!rm;
    setLook(s?.classicVillagers ? 'classic' : 'lit');
    audio.configure({ sound: s ? s.sound : true, music: s ? s.music : true });
  }

  // ------------------------------------------------------------ routing
  go(id, params = {}, { replace = false } = {}) {
    if (this.route && !replace) {
      this.saveScroll();
      this.history.push(this.route);
      if (this.history.length > 20) this.history.shift();
    }
    this.route = { id, params };
    this.closeAllModals();
    this.render(true);
    this.host.scrollTop = 0;
  }

  back() {
    const prev = this.history.pop();
    if (prev) {
      this.saveScroll();
      this.route = prev;
      this.render(true);
    } else this.go('home', {}, { replace: true });
  }

  tab(id) {
    // tabs keep their own state; nested back returns to the initiating tab
    this.saveScroll();
    this.history = [];
    this.route = { id, params: {} };
    this.closeAllModals();
    this.render(true);
  }

  saveScroll() {
    const sc = $('.screen.scroll', this.host);
    if (sc && this.route) this.scrolls[this.route.id] = sc.scrollTop;
  }

  schedule() {
    if (this.pending) return;
    this.pending = true;
    requestAnimationFrame(() => {
      this.pending = false;
      this.render(false);
    });
  }

  resolveRoute() {
    const s = this.store.state;
    const r = this.route;
    const onb = ['welcome', 'create', 'connect', 'goal', 'awakening'];
    if (!s.player || s.onboarding.step !== 'done') {
      const step = !s.player ? 'welcome' : s.onboarding.step;
      if (!r || !onb.includes(r.id) || (r.id !== step && !(r.id === 'welcome' && !s.player))) {
        this.route = { id: step, params: {} };
      }
      return;
    }
    if (!s.pet) {
      this.route = { id: 'create', params: { again: true } };
      return;
    }
    if (!r || onb.includes(r.id)) this.route = { id: 'home', params: {} };
  }

  render(navigated) {
    this.applySettings();
    const prevId = this.route?.id;
    this.resolveRoute();
    const ctx = this.ctx();
    const scr = this.screen();
    if (!scr) return;
    if (prevId !== this.route.id) navigated = true;
    // scene
    const sc = scr.scene ? scr.scene(ctx) : null;
    if (sc) sc.reducedMotion = this.reducedMotion;
    const sig = JSON.stringify(sc);
    if (sig !== this.sceneSig) {
      this.sceneSig = sig;
      this.scene.configure(sc || {});
    }
    // focus restoration
    const active = document.activeElement;
    const fk = active && active.closest && this.root.contains(active) ? active.getAttribute('data-k') : null;
    const sc0 = $('.screen.scroll', this.host);
    const keepScroll = !navigated && sc0 ? sc0.scrollTop : this.scrolls[this.route.id] || 0;
    const body = scr.render(ctx);
    this.host.innerHTML = String(body);
    const el = this.host.firstElementChild;
    if (navigated && el) el.classList.add('fade-in');
    const sc1 = $('.screen.scroll', this.host);
    if (sc1) sc1.scrollTop = keepScroll;
    hydrateSprites(this.host);
    // never let focus or overflow scroll the frame sideways
    for (const n of [this.root, this.host, el]) if (n && n.scrollLeft) n.scrollLeft = 0;
    if (scr.mount) scr.mount(ctx, el);
    // re-layout scene in case the screen measured its chrome
    if (scr.afterLayout) {
      const sc2 = scr.afterLayout(ctx, el);
      if (sc2) {
        sc2.reducedMotion = this.reducedMotion;
        const sig2 = JSON.stringify(sc2);
        if (sig2 !== this.sceneSig) {
          this.sceneSig = sig2;
          this.scene.configure(sc2);
        }
      }
      if (scr.position) scr.position(ctx, el);
    }
    if (fk) {
      const f = this.root.querySelector(`[data-k="${CSS.escape(fk)}"]`);
      if (f) f.focus({ preventScroll: true });
    }
    this.renderModals();
    if (navigated) {
      const h = el?.querySelector('h1, h2, [data-autofocus]');
      if (h && h.hasAttribute('data-autofocus')) h.focus({ preventScroll: true });
    }
  }

  // ------------------------------------------------------------ events
  onClick(e) {
    const t = e.target.closest('[data-act]');
    if (!t || !this.root.contains(t)) return;
    if (t.disabled || t.getAttribute('aria-disabled') === 'true') return;
    const act = t.dataset.act;
    const arg = t.dataset.arg;
    const ctx = this.ctx();
    audio.unlock();
    // modal actions take priority
    const modal = this.modals[this.modals.length - 1];
    if (modal && t.closest('.modal-host') && modal.actions?.[act]) {
      e.preventDefault();
      modal.actions[act](ctx, arg, t, e);
      return;
    }
    const scr = this.screen();
    if (scr.actions?.[act]) {
      e.preventDefault();
      scr.actions[act](ctx, arg, t, e);
      return;
    }
    if (GLOBAL[act]) {
      e.preventDefault();
      GLOBAL[act](ctx, arg, t, e);
    }
  }

  onInput(e) {
    const t = e.target.closest('[data-input]');
    if (!t) return;
    const ctx = this.ctx();
    const modal = this.modals[this.modals.length - 1];
    const fn = (modal && t.closest('.modal-host') && modal.inputs?.[t.dataset.input]) || this.screen().inputs?.[t.dataset.input];
    if (fn) fn(ctx, t.value, t, e);
  }

  onKey(e) {
    if (e.key === 'Escape' && this.modals.length) {
      e.preventDefault();
      this.closeModal();
    }
  }

  handleEvents(evs) {
    const ctx = this.ctx();
    for (const ev of evs) {
      switch (ev.type) {
        case 'xp':
          this.toast(`+${ev.amount} XP for ${esc(ctx.state.pet?.name || 'your Evochi')}`, 'ok', 'xp');
          break;
        case 'level_up':
          this.toast(`Level ${ev.level}! ${esc(ctx.state.pet?.name)} is growing`, 'ok', 'star');
          this.sfx('level_up');
          this.scene.react('reward');
          break;
        case 'goal_met':
          this.toast('Daily goal reached! Bond +1', 'ok', 'heart');
          this.scene.react('reward');
          break;
        case 'evolution_ready':
          this.toast('Something is stirring... evolution is ready!', 'ok', 'evolve');
          this.store.track('evolution_unlocked', { stage: ev.stage });
          break;
        case 'quest_ready':
          this.toast(`Quest ready to claim: ${esc(ev.title)}`, 'ok', 'chest');
          break;
        case 'claimed': {
          const coins = ev.rewards.filter((r) => r.kind === 'coins').reduce((a, r) => a + r.amount, 0);
          const items = ev.rewards.filter((r) => r.kind === 'item').map((r) => ITEMS[r.itemId].name);
          this.toast(`+${coins} EvoCoins${items.length ? ' + ' + items.join(', ') : ''}`, 'ok', 'coin');
          this.sfx('coin');
          break;
        }
        case 'purchased':
          this.sfx('purchase');
          break;
        case 'bond':
          this.toast(`Bond +${ev.amount}`, 'ok', 'heart');
          break;
        case 'recovered':
          this.toast('Your Evochi is feeling better!', 'ok', 'heart');
          break;
        case 'story_item': {
          const name = QUEST_MATERIALS[ev.itemId].name;
          const msg = ev.itemId === 'q_dawn_dew_vial' ? `Morning light collected! ${name} added to your Quest Pouch.`
            : ev.itemId === 'q_windprint_paper' || ev.itemId === 'q_echo_rubbing'
              ? `${name} ${(this.store.state.story?.questPouch?.[ev.itemId] || 1)}/${ev.itemId === 'q_windprint_paper' ? 2 : 3} added to your Quest Pouch`
              : `${name} added to your Quest Pouch`;
          this.toast(esc(msg), 'ok', 'item:' + ev.itemId);
          this.sfx('reward_chime', 0.7);
          break;
        }
        case 'story_ready':
          if (ev.npc && ev.npc !== 'waystone') {
            const who = { npc_mira: 'Mira', npc_bram: 'Bram', npc_pip: 'Pip', npc_alder: 'Alder' }[ev.npc];
            this.toast(`${who} is ready for you in Sunlit Village`, 'ok', 'pin');
          } else if (ev.npc === 'waystone') this.toast('The Waystone is ready to wake', 'ok', 'star');
          break;
        case 'story_completed':
          this.store.track('story_quest_completed', { quest: ev.questId });
          break;
        case 'sync_failed':
          this.toast('Sync failed - your last saved progress is safe', 'err', 'warning');
          break;
        default:
      }
    }
  }

  // ------------------------------------------------------------ toasts
  toast(message, kind = '', iconKey = null) {
    const el = document.createElement('div');
    el.className = 'toast ' + (kind || '');
    const src = iconKey ? (iconKey.startsWith('item:') ? itemImg(iconKey.slice(5)) : icon(iconKey)) : null;
    el.innerHTML = `${src ? `<img alt="" src="${src}">` : ''}<span>${message}</span>`;
    this.toastHost.appendChild(el);
    const all = this.toastHost.children;
    while (all.length > 3) all[0].remove();
    setTimeout(() => {
      el.classList.add('out');
      setTimeout(() => el.remove(), 260);
    }, 2600);
  }

  // ------------------------------------------------------------ modals
  openModal(spec) {
    this.lastFocus = document.activeElement;
    this.modals.push(spec);
    this.renderModals();
    const first = this.modalHost.querySelector('[data-autofocus], button, input');
    if (first) first.focus({ preventScroll: true });
  }

  closeModal() {
    const m = this.modals.pop();
    if (m?.onClose) m.onClose(this.ctx());
    this.renderModals();
    if (this.lastFocus && this.lastFocus.isConnected) this.lastFocus.focus({ preventScroll: true });
  }

  closeAllModals() {
    while (this.modals.length) {
      const m = this.modals.pop();
      if (m?.onClose) m.onClose(this.ctx());
    }
    this.renderModals();
  }

  renderModals() {
    if (!this.modals.length) {
      this.modalHost.innerHTML = '';
      return;
    }
    const ctx = this.ctx();
    const m = this.modals[this.modals.length - 1];
    const prevScroll = $('.modal', this.modalHost)?.scrollTop || 0;
    const same = this.modalHost.dataset.mid === String(this.modals.length);
    this.modalHost.innerHTML = `<div class="scrim ${m.center ? 'center' : ''}" data-act="${m.noDismiss ? '' : 'modal-dismiss'}"><div class="modal" role="dialog" aria-modal="true" aria-label="${esc(m.label || 'Dialog')}" data-stop>${m.grab === false || m.center ? '' : '<div class="grab"></div>'}${m.render(ctx)}</div></div>`;
    this.modalHost.dataset.mid = String(this.modals.length);
    const md = $('.modal', this.modalHost);
    if (same && md) {
      md.scrollTop = prevScroll;
      md.style.animation = 'none';
      const scrim = $('.scrim', this.modalHost);
      if (scrim) scrim.style.animation = 'none';
    }
    hydrateSprites(this.modalHost);
    if (m.mount) m.mount(ctx, md);
  }
}

// global actions available on every screen
const GLOBAL = {
  tab(ctx, id) {
    ctx.app.tab(id);
    ctx.sfx('ui_tap', 0.4);
  },
  back(ctx) {
    ctx.back();
  },
  'modal-dismiss'(ctx, arg, el, e) {
    if (e.target === el) ctx.closeModal();
  },
  'modal-close'(ctx) {
    ctx.closeModal();
  },
  coins(ctx) {
    ctx.modal({
      label: 'EvoCoins',
      render: (c) => html`<div class="stack">
        <div class="row"><img src="${icon('coin')}" alt="" width="44" height="44"><h2 class="h-sec">EvoCoins</h2></div>
        <p class="body">EvoCoins are earned by walking and caring for your Evochi. Complete Journey quests to collect them, then spend them in the Market.</p>
        <p class="body muted">There is no paid currency in this version.</p>
        <button class="btn block" data-act="goto-journey">Open Journey</button>
        <button class="btn cream block" data-act="modal-close">Close</button></div>`,
      actions: { 'goto-journey': (c) => (c.closeModal(), c.app.tab('journey')), 'modal-close': (c) => c.closeModal() },
    });
  },
  settings(ctx) {
    ctx.go('settings');
  },
  mail(ctx) {
    ctx.go('journey');
  },
  'visit-village'(ctx) {
    ctx.sfx('ui_tap', 0.4);
    ctx.go('village');
  },
};

// ------------------------------------------------------------ shared chrome
export function coinPill(ctx) {
  return html`<div class="coin-pill" aria-label="${fmt(ctx.d.balance)} EvoCoins">
    <img src="${icon('coin')}" alt=""><span class="num">${fmt(ctx.d.balance)}</span>
    <button class="plus" data-act="coins" aria-label="How to earn EvoCoins" data-k="coins-plus">+</button></div>`;
}

export function titleImg(key, alt, cls = 'title-img') {
  const t = title(key);
  return html`<img class="${cls}" src="${url(t.file)}" alt="${alt}" width="${t.w}" height="${t.h}">`;
}

export function nav(ctx, current) {
  const d = ctx.d;
  const badges = {
    journey: d.claimable,
    evodex: ctx.state.pet && d.pet?.evo?.eligible ? 1 : 0,
    home: d.pet?.dead ? 1 : 0,
  };
  return html`<nav class="nav" aria-label="Main">
    ${TABS.map((t) => html`<button data-act="tab" data-arg="${t.id}" data-k="tab-${t.id}" ${t.id === current ? raw('aria-current="page"') : ''} aria-label="${t.label}${badges[t.id] ? `, ${badges[t.id]} new` : ''}">
      <img src="${icon(t.icon)}" alt=""><span>${t.label}</span>${badges[t.id] ? raw('<i class="badge-dot" aria-hidden="true"></i>') : ''}</button>`)}
  </nav>`;
}

export function stageLabel(stage) {
  return ['', 'Eggling', 'Juvenile', 'Elder'][stage];
}

export function statusTag(status) {
  const T = {
    healthy: ['ok', 'care', 'Healthy'],
    neutral: ['neutral', 'heart_empty', 'Neutral'],
    sick: ['warn', 'potion', 'Unwell'],
    dead: ['danger', 'heart_empty', 'Resting'],
  }[status];
  return html`<span class="tag ${T[0]}"><img src="${icon(T[1])}" alt="">${T[2]}</span>`;
}

export function rarityTag(id) {
  const it = ITEMS[id];
  if (it.acquisition === 'story') {
    return html`<span class="tag story-tag-sm"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.5l2.9 6 6.6.8-4.9 4.5 1.3 6.5L12 17l-5.9 3.3 1.3-6.5L2.5 9.3l6.6-.8z" fill="#F4B84E" stroke="#80531F" stroke-width="1.4" stroke-linejoin="round"/></svg>Story reward</span>`;
  }
  const R = { common: 'ok', uncommon: 'ok', rare: 'cream', epic: 'cream', legendary: 'stage' }[it.rarity];
  const label = it.rarity[0].toUpperCase() + it.rarity.slice(1);
  const col = { common: '#82B75E', uncommon: '#5FA046', rare: '#39BDE3', epic: '#AA8BCF', legendary: '#F4B84E' }[it.rarity];
  return html`<span class="tag ${R}" style="border-color:${col}"><img src="${icon('care')}" alt="">${label}</span>`;
}

export const ICONS = ICON;

// S01 Welcome, S02 Create, S03 Fitness connect, S04 Goal setup, S05 Awakening (style guide §08, §09, §13).
import * as G from '../game/state.js';
import { CONFIG, PALETTES } from '../game/config.js';
import { html, raw, esc, fmt } from '../ui/dom.js';
import { icon, url, title, spriteAttr, BLANK, manifest, preloadPet } from '../ui/assets.js';
import { ICON } from '../ui/icons.js';
import { titleImg, stageLabel } from '../core/app.js';
import { deviceZone } from '../game/time.js';
import { simulateWalk, manualEntry } from '../game/health.js';

// ---------------------------------------------------------------- welcome
export const welcome = {
  id: 'welcome',
  scene(ctx) {
    return {
      habitat: 'welcome', focus: { x: 0.5, y: ctx.ui('welcome').groundY || 0.52 }, background: '#86C95B',
      pet: { stage: 1, palette: 'amber', status: 'healthy', label: 'Say hello' },
    };
  },
  afterLayout(ctx, el) {
    const auth = el.querySelector('.auth');
    const top = auth.getBoundingClientRect().top - ctx.app.root.getBoundingClientRect().top;
    const u = ctx.ui('welcome');
    const gy = Math.round(top - 34);
    if (u.groundY !== gy) u.groundY = gy;
    return welcome.scene(ctx);
  },
  position(ctx, el) {
    const pr = ctx.scene.petRect();
    if (!pr) return;
    const W = ctx.app.root.clientWidth;
    const L = el.querySelector('.glass-card.l');
    const R = el.querySelector('.glass-card.r');
    const cw = Math.min(140, W * 0.34);
    const ch = cw * 0.78;
    const gy = pr.top + pr.h * 0.88;
    Object.assign(L.style, { width: cw + 'px', height: ch + 'px', left: W * 0.04 + 'px', top: gy - ch - pr.h * 0.42 + 'px' });
    Object.assign(R.style, { width: cw * 1.05 + 'px', height: ch * 1.12 + 'px', left: W - cw * 1.05 - W * 0.02 + 'px', top: gy - ch * 1.12 - pr.h * 0.5 + 'px' });
    const c1 = el.querySelector('.chev1');
    const c2 = el.querySelector('.chev2');
    Object.assign(c1.style, { left: W * 0.04 + cw + 2 + 'px', top: gy - ch * 0.5 - pr.h * 0.42 + 'px' });
    Object.assign(c2.style, { left: W - cw * 1.05 - W * 0.02 - 22 + 'px', top: gy - ch * 0.6 - pr.h * 0.5 + 'px' });
  },
  onPetTap(ctx) {
    ctx.scene.react('pet');
    ctx.sfx('pet_chirp');
  },
  render(ctx) {
    const logo = title('wordmark_evochi');
    return html`<main class="screen welcome" aria-label="Welcome to Evochi">
      <h1 class="sr-only">Evochi</h1>
      <img class="logo" src="${url(logo.file)}" alt="Evochi" width="${logo.w}" height="${logo.h}">
      <p class="tagline">Every step brings your Evochi to life.</p>
      <div class="leaf-div" aria-hidden="true"><i></i><img src="${icon('care')}" alt=""><i></i></div>
      <div class="glass-card l" aria-hidden="true"><img data-sprite="${spriteAttr(2, 'amber', 'determined', [], '', 260)}" src="${BLANK}" alt=""></div>
      <div class="glass-card r" aria-hidden="true"><img data-sprite="${spriteAttr(3, 'amber', 'default', [], '', 260)}" src="${BLANK}" alt=""></div>
      <span class="sparkle chev1" aria-hidden="true" style="position:absolute">&rsaquo;</span>
      <span class="sparkle chev2" aria-hidden="true" style="position:absolute">&rsaquo;</span>
      <div class="spacer"></div>
      <div class="auth">
        <button class="btn lg block" data-act="begin" data-k="begin">${ICON.play}<span>Begin Your Journey</span></button>
        <button class="btn cream block" data-act="signin" data-arg="apple" data-k="apple">${ICON.device}<span>Continue with Apple</span></button>
        <button class="btn cream block" data-act="signin" data-arg="google" data-k="google">${ICON.key}<span>Continue with Google</span></button>
        <button class="btn cream block" data-act="email" data-k="email">${ICON.mail}<span>Continue with Email</span></button>
        <div class="or">Or</div>
        <button class="btn cream sm guest" data-act="guest" data-k="guest">Try as Guest</button>
        <p class="legal">By continuing, you agree to our <button data-act="legal" data-arg="terms">Terms of Service</button> and <button data-act="legal" data-arg="privacy">Privacy Policy</button>.</p>
      </div>
    </main>`;
  },
  actions: {
    begin(ctx) {
      guestNotice(ctx);
    },
    guest(ctx) {
      guestNotice(ctx);
    },
    signin(ctx, provider) {
      const name = provider === 'apple' ? 'Apple' : 'Google';
      ctx.modal({
        label: `Continue with ${name}`,
        render: () => html`<div class="stack">
          <h2 class="h-sec">Continue with ${name}</h2>
          <p class="body">${name} sign-in runs in the iOS and Android apps. This web preview can't open it, so your progress stays on this device as a guest, or under an email profile.</p>
          <button class="btn block" data-act="as-guest" data-autofocus>Continue as Guest</button>
          <button class="btn cream block" data-act="as-email">Use Email instead</button></div>`,
        actions: {
          'as-guest': (c) => (c.closeModal(), guestNotice(c)),
          'as-email': (c) => (c.closeModal(), welcome.actions.email(c)),
        },
      });
    },
    email(ctx) {
      const u = ctx.ui('email');
      ctx.modal({
        label: 'Continue with Email',
        render: () => html`<div class="stack">
          <h2 class="h-sec">Continue with Email</h2>
          <p class="body">Create a local profile with your email. In this preview it's stored only on this device; the mobile app links it to your cloud account.</p>
          <label class="small muted" for="em">Email</label>
          <input id="em" class="input" type="email" inputmode="email" autocomplete="email" data-input="email" value="${u.email || ''}" data-autofocus placeholder="you@example.com">
          ${u.err ? html`<p class="field-err" role="alert">${u.err}</p>` : ''}
          <button class="btn block" data-act="email-go">Continue</button>
          <button class="btn cream block" data-act="modal-close">Cancel</button></div>`,
        inputs: { email: (c, v) => (u.email = v) },
        actions: {
          'email-go': (c) => {
            const v = (u.email || '').trim();
            if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v)) {
              u.err = 'Enter a valid email address.';
              c.app.renderModals();
              return;
            }
            u.err = null;
            c.closeModal();
            c.store.run((st) => G.startAccount(st, v, c.store.now(), deviceZone()));
            c.track('onboarding_started', { method: 'email' });
          },
        },
      });
    },
    legal(ctx, which) {
      ctx.modal({
        label: which === 'terms' ? 'Terms of Service' : 'Privacy Policy',
        render: () => html`<div class="stack"><h2 class="h-sec">${which === 'terms' ? 'Terms of Service' : 'Privacy Policy'}</h2>
          <p class="body">This is a preview build. ${which === 'privacy' ? 'Evochi only uses daily step counts to grow your pet. Step data never leaves this device in the web preview, and you can export or delete everything from Settings.' : 'Placeholder terms: final legal copy is required before release (style guide §23).'}</p>
          <button class="btn cream block" data-act="modal-close">Close</button></div>`,
      });
    },
  },
};

function guestNotice(ctx) {
  ctx.modal({
    label: 'Play as guest',
    render: () => html`<div class="stack">
      <div class="row"><img src="${icon('paw')}" alt="" width="40" height="40"><h2 class="h-sec">Play as a guest</h2></div>
      <p class="body">Your Evochi is saved on this device. If you clear browser data or uninstall, a guest pet can't be recovered. You can add an email later in Settings.</p>
      <button class="btn lg block" data-act="guest-go" data-autofocus>${ICON.play}<span>Start my adventure</span></button>
      <button class="btn cream block" data-act="modal-close">Not now</button></div>`,
    actions: {
      'guest-go': (c) => {
        c.closeModal();
        c.store.run((s) => G.startGuest(s, c.store.now(), deviceZone()));
        c.track('onboarding_started', { method: 'guest' });
        c.sfx('reward_chime', 0.5);
      },
    },
  });
}

// ---------------------------------------------------------------- create
export const create = {
  id: 'create',
  scene(ctx) {
    const dr = ctx.state.onboarding.draft;
    const u = ctx.ui('create');
    return {
      habitat: 'meadow', platform: true, focus: { x: 0.5, y: u.groundY || 0.36 }, background: '#86C95B',
      pet: { stage: 1, palette: dr.paletteId, status: 'healthy', label: 'Preview your Evochi' },
    };
  },
  afterLayout(ctx, el) {
    const panel = el.querySelector('.create-panel');
    const top = panel.getBoundingClientRect().top - ctx.app.root.getBoundingClientRect().top + el.scrollTop;
    const u = ctx.ui('create');
    u.groundY = Math.round(top - 26 - el.scrollTop);
    return create.scene(ctx);
  },
  position(ctx, el) {
    const pr = ctx.scene.petRect();
    if (!pr) return;
    const W = ctx.app.root.clientWidth;
    const y = pr.top + pr.h * 0.48;
    el.querySelector('.arrow-btn.l').style.cssText = `left:${Math.max(12, pr.left - 30)}px;top:${y}px`;
    el.querySelector('.arrow-btn.r').style.cssText = `left:${Math.min(W - 48, pr.left + pr.w - 6)}px;top:${y}px`;
  },
  onPetTap(ctx) {
    ctx.scene.react('pet');
    ctx.sfx('pet_chirp');
  },
  mount(ctx, el) {
    el.addEventListener('scroll', () => {
      const u = ctx.ui('create');
      const panel = el.querySelector('.create-panel');
      const top = panel.getBoundingClientRect().top - ctx.app.root.getBoundingClientRect().top;
      const gy = Math.round(top - 26);
      if (Math.abs((u.groundY || 0) - gy) > 1) {
        u.groundY = gy;
        ctx.scene.configure({ ...create.scene(ctx), reducedMotion: ctx.app.reducedMotion });
        create.position(ctx, el);
      }
    }, { passive: true });
  },
  render(ctx) {
    const s = ctx.state;
    const dr = s.onboarding.draft;
    const u = ctx.ui('create');
    const again = s.pastPets.length > 0;
    const pal = dr.paletteId;
    const t1 = title('title_create_your');
    const t2 = title('wordmark_evochi');
    return html`<main class="screen scroll onb" aria-label="Create your Evochi">
      <div class="onb-head">
        ${again ? html`<span style="width:44px"></span>` : html`<button class="back-btn" data-act="back-welcome" aria-label="Back" data-k="cback">${ICON.back}</button>`}
        <div style="flex:1;display:flex;flex-direction:column;align-items:center;gap:2px;margin-right:44px">
          <h1 class="sr-only">Create your Evochi</h1>
          <img src="${url(t1.file)}" alt="" style="height:28px;width:auto">
          <img src="${url(t2.file)}" alt="" style="height:52px;width:auto;margin-top:-2px">
          <span class="subtitle-tag">A small beginning, a big adventure.</span>
        </div>
      </div>
      <button class="arrow-btn l" data-act="cycle" data-arg="-1" aria-label="Previous colour" data-k="prev">${ICON.back}</button>
      <button class="arrow-btn r" data-act="cycle" data-arg="1" aria-label="Next colour" data-k="next">${ICON.next}</button>
      <div style="flex:none;height:max(230px, 34vh)"></div>
      <div class="create-panel stack" style="position:relative;z-index:4">
        <div class="card name-field">
          <label for="pet-name">Name</label>
          <div class="inp"><input id="pet-name" data-input="name" data-k="name" maxlength="12" value="${dr.name}" placeholder="Ember" autocomplete="off" spellcheck="false" aria-describedby="name-err">${raw(ICON.edit.s.replace('<svg', '<svg width="22" height="22"'))}</div>
        </div>
        ${u.nameErr ? html`<p class="field-err" id="name-err" role="alert">${u.nameErr}</p>` : html`<span id="name-err" hidden></span>`}
        <section class="card" style="padding:10px" aria-labelledby="cc-h">
          <div class="mini-head"><h2 class="h-card" id="cc-h"><img src="${icon('palette')}" alt="">Choose Color</h2><small>This color will carry through all evolutions.</small></div>
          <div class="swatches" role="radiogroup" aria-label="Colour" style="margin-top:8px">
            ${PALETTES.map((p) => html`<button class="swatch" role="radio" aria-checked="${p.id === pal}" aria-label="${p.label}" data-act="palette" data-arg="${p.id}" data-k="sw-${p.id}">
              <img data-sprite="${spriteAttr(1, p.id, 'default', [], '', 120)}" src="${BLANK}" alt="">${p.id === pal ? html`<span class="check-badge">${ICON.check}</span>` : ''}</button>`)}
          </div>
        </section>
        <section class="card" style="padding:10px" aria-labelledby="ep-h">
          <div class="mini-head"><h2 class="h-card" id="ep-h"><img src="${icon('evolve')}" alt="">Evolution Preview</h2><small>See how your Evochi grows!</small></div>
          <div class="evo-strip" style="margin-top:6px">
            ${[1, 2, 3].map((st, i) => html`${i ? html`<div class="chev" aria-hidden="true">&rsaquo;</div>` : ''}<div class="evo-cell ${st === 1 ? 'current' : ''}" aria-label="${stageLabel(st)}">
              <div class="pic"><img data-sprite="${spriteAttr(st, pal, 'default', [], '', 140)}" src="${BLANK}" alt=""></div><span class="lbl">${stageLabel(st)}</span></div>`)}
          </div>
        </section>
        <section class="card" style="padding:10px" aria-labelledby="hb-h">
          <div class="mini-head"><h2 class="h-card" id="hb-h"><img src="${icon('decorations')}" alt="">Your Starting Home</h2><small>This will be your home when the journey begins.</small></div>
          <div style="margin-top:8px" role="radiogroup" aria-label="Habitat">
            <button class="hab-card" role="radio" aria-checked="true" style="width:100%" data-k="hab">
              <img src="${url(manifest().habitats.thumbs.meadow)}" alt="" style="height:96px">
              <span class="nm"><img src="${icon('pin')}" alt="">Sunlit Meadow</span>
              <span class="check-badge" style="top:6px;right:6px">${ICON.check}</span>
            </button>
            <p class="small muted" style="margin:6px 2px 0">More habitats unlock later in your journey.</p>
          </div>
        </section>
        <button class="btn lg block" data-act="confirm" data-k="confirm" style="margin-top:4px"><img class="ico" src="${icon('paw')}" alt=""><span>Confirm Evochi</span>${ICON.next}</button>
      </div>
    </main>`;
  },
  inputs: {
    name(ctx, v) {
      ctx.store.state = G.updateDraft(ctx.store.state, { name: v }).state;
      ctx.store.persist();
      const u = ctx.ui('create');
      if (u.nameErr) {
        u.nameErr = null;
        ctx.rerender();
      }
    },
  },
  actions: {
    'back-welcome'(ctx) {
      // leaving creation keeps the guest profile; return to the welcome screen
      ctx.modal({
        label: 'Leave creation?',
        render: () => html`<div class="stack"><h2 class="h-sec">Leave without hatching?</h2>
          <p class="body">Your choices are saved as a draft. You can come back any time.</p>
          <button class="btn block" data-act="stay" data-autofocus>Keep creating</button>
          <button class="btn cream block" data-act="leave">Back to welcome</button></div>`,
        actions: {
          stay: (c) => c.closeModal(),
          leave: (c) => {
            c.closeModal();
            const s = structuredClone(c.store.state);
            s.player = null;
            s.onboarding.step = 'welcome';
            c.store.replace(s);
          },
        },
      });
    },
    palette(ctx, id) {
      ctx.act((s) => G.updateDraft(s, { paletteId: id }));
      preloadPet(1, id);
      ctx.scene.react('equip');
      ctx.sfx('ui_tap', 0.5);
    },
    cycle(ctx, dir) {
      const ids = PALETTES.map((p) => p.id);
      const i = ids.indexOf(ctx.state.onboarding.draft.paletteId);
      const n = ids[(i + Number(dir) + ids.length) % ids.length];
      create.actions.palette(ctx, n);
    },
    confirm(ctx) {
      const dr = ctx.state.onboarding.draft;
      const v = G.validateName(dr.name);
      const u = ctx.ui('create');
      if (!v.ok) {
        u.nameErr = v.error;
        ctx.rerender();
        setTimeout(() => document.getElementById('pet-name')?.focus(), 30);
        return;
      }
      let req = ctx.state.onboarding.requestId;
      if (!req) {
        req = G.uid('create');
        ctx.store.state = { ...ctx.store.state, onboarding: { ...ctx.store.state.onboarding, requestId: req } };
      }
      const r = ctx.act(G.createPet, { name: v.name, paletteId: dr.paletteId, habitatId: 'sunlit_meadow', requestId: req });
      if (!r.error) {
        ctx.sfx('reward_chime');
        ctx.track('pet_created', { palette: dr.paletteId });
      }
    },
  },
};

// ---------------------------------------------------------------- connect
export const connect = {
  id: 'connect',
  scene(ctx) {
    const p = ctx.state.pet;
    return {
      habitat: 'meadow', decor: ctx.state.nest.placements, focus: { x: 0.5, y: ctx.ui('connect').groundY || 0.36 }, background: '#86C95B',
      pet: { stage: 1, palette: p.paletteId, status: 'healthy', expr: 'curious', label: p.name },
    };
  },
  afterLayout(ctx, el) {
    const panel = el.querySelector('.sheet-bg');
    const top = panel.getBoundingClientRect().top - ctx.app.root.getBoundingClientRect().top;
    ctx.ui('connect').groundY = Math.round(top - 40);
    return connect.scene(ctx);
  },
  onPetTap(ctx) {
    ctx.scene.react('pet');
    ctx.sfx('pet_chirp');
  },
  render(ctx) {
    const p = ctx.state.pet;
    return html`<main class="screen" aria-label="Connect your steps">
      <div class="spacer"></div>
      <section class="sheet-bg stack" style="padding:18px 16px calc(16px + var(--safe-bottom));z-index:3">
        <div class="row"><img src="${icon('steps')}" alt="" width="46" height="46"><h1 class="h-page" tabindex="-1" data-autofocus>Walk together</h1></div>
        <p class="body">${p.name} grows from your real-world steps. Evochi reads only your <b>daily step count</b> - nothing else - to give XP, quests and coins. Step data is optional, and you can change this any time in Settings.</p>
        <div class="card inset" style="padding:10px 12px">
          <p class="small" style="margin:0"><b>On phones</b>, Evochi asks for read-only step access through Apple Health (iOS) or Health Connect (Android). This web preview has no step sensor, so it offers a <b>simulated step device</b> you can drive from the Journey tab.</p>
        </div>
        <button class="btn lg block" data-act="demo" data-autofocus data-k="demo">${ICON.device}<span>Use simulated step device</span></button>
        <button class="btn cream block" data-act="manual" data-k="manual">Enter steps manually</button>
        <button class="btn ghost" data-act="skip" data-k="skip">Connect later</button>
        <p class="small muted center" style="margin:0">Manual steps are marked unverified and don't count toward reward chests.</p>
      </section>
    </main>`;
  },
  actions: {
    demo(ctx) {
      ctx.act(G.setConnection, 'demo');
      ctx.act(G.setOnboardingStep, 'goal');
      ctx.toast('Simulated step device connected', 'ok', 'steps');
      ctx.track('step_source', { source: 'demo' });
    },
    manual(ctx) {
      ctx.act(G.setConnection, 'manual');
      ctx.act(G.setOnboardingStep, 'goal');
      ctx.track('step_source', { source: 'manual' });
    },
    skip(ctx) {
      ctx.act(G.setOnboardingStep, 'goal');
      ctx.track('step_source', { source: 'none' });
    },
  },
};

// ---------------------------------------------------------------- goal
export const goal = {
  id: 'goal',
  scene: connect.scene,
  afterLayout(ctx, el) {
    const panel = el.querySelector('.sheet-bg');
    const top = panel.getBoundingClientRect().top - ctx.app.root.getBoundingClientRect().top;
    ctx.ui('connect').groundY = Math.round(top - 40);
    return connect.scene(ctx);
  },
  onPetTap: connect.onPetTap,
  render(ctx) {
    const u = ctx.ui('goal');
    const sel = u.sel ?? ctx.state.player.goal ?? CONFIG.goal.default;
    const isPreset = CONFIG.goal.presets.some((p) => p.steps === sel);
    return html`<main class="screen" aria-label="Daily goal">
      <div class="spacer"></div>
      <section class="sheet-bg stack" style="padding:18px 16px calc(16px + var(--safe-bottom));z-index:3">
        <div class="row"><img src="${icon('star')}" alt="" width="42" height="42"><h1 class="h-page" tabindex="-1" data-autofocus>Pick a daily goal</h1></div>
        <p class="body" style="margin:0">Choose what feels comfortable. You can change it later - it's a game target, not a health prescription.</p>
        <div class="stack" role="radiogroup" aria-label="Daily step goal">
          ${CONFIG.goal.presets.map((p) => html`<button class="choice" role="radio" aria-checked="${sel === p.steps}" data-act="preset" data-arg="${p.steps}" data-k="g-${p.id}">
            <img src="${icon(p.id === 'beginner' ? 'care' : p.id === 'standard' ? 'steps' : 'trophy')}" alt="">
            <span class="grow"><span class="t">${p.label}</span> <span class="tag small ${p.id === 'standard' ? 'stage' : 'cream'}">${p.blurb}</span><br><span class="d">${fmt(p.steps)} steps a day</span></span></button>`)}
          <div class="choice" role="radio" aria-checked="${!isPreset}" style="cursor:default">
            <img src="${icon('palette')}" alt=""><span class="grow"><span class="t">Custom</span><br><span class="d">500-step increments</span></span>
            <div class="stepper"><button class="icon-btn" data-act="adj" data-arg="-500" aria-label="Decrease goal" data-k="gdec">-</button>
            <span class="num" style="font-size:16px;min-width:58px;text-align:center" aria-live="polite">${fmt(sel)}</span>
            <button class="icon-btn" data-act="adj" data-arg="500" aria-label="Increase goal" data-k="ginc">+</button></div>
          </div>
        </div>
        <button class="btn lg block" data-act="save" data-k="gsave">${ICON.play}<span>Continue</span></button>
      </section>
    </main>`;
  },
  actions: {
    preset(ctx, v) {
      ctx.ui('goal').sel = Number(v);
      ctx.rerender();
    },
    adj(ctx, v) {
      const u = ctx.ui('goal');
      const cur = u.sel ?? ctx.state.player.goal;
      u.sel = Math.max(CONFIG.goal.min, Math.min(CONFIG.goal.max, cur + Number(v)));
      ctx.rerender();
    },
    save(ctx) {
      const u = ctx.ui('goal');
      ctx.act(G.setGoal, u.sel ?? ctx.state.player.goal);
      ctx.act(G.setOnboardingStep, 'awakening');
    },
  },
};

// ---------------------------------------------------------------- awakening
export const awakening = {
  id: 'awakening',
  scene(ctx) {
    const p = ctx.state.pet;
    const u = ctx.ui('awaken');
    return {
      habitat: 'meadow', decor: ctx.state.nest.placements, focus: { x: 0.5, y: 0.44 }, background: '#86C95B',
      pet: { stage: 1, palette: p.paletteId, status: 'healthy', visible: !!u.revealed, label: p.name },
      forceExpr: u.revealed ? null : 'sleepy',
    };
  },
  mount(ctx, el) {
    const u = ctx.ui('awaken');
    if (u.started) return;
    u.started = true;
    const skip = ctx.app.reducedMotion;
    setTimeout(() => {
      u.revealed = true;
      ctx.rerender();
      ctx.scene.react('pet');
      ctx.sfx('evolve_fanfare', 0.5);
    }, skip ? 50 : 900);
  },
  onPetTap(ctx) {
    ctx.scene.react('pet');
    ctx.sfx('pet_chirp');
  },
  render(ctx) {
    const p = ctx.state.pet;
    const u = ctx.ui('awaken');
    return html`<main class="screen" aria-label="Awakening">
      <div class="awaken">
        ${!u.revealed ? html`<div style="position:absolute;top:42%;left:50%;transform:translate(-50%,-50%);width:120px;height:120px;border-radius:50%;background:radial-gradient(circle,#FFF6D0,rgba(255,230,160,0))" aria-hidden="true"></div>` : ''}
        <div class="card stack center" style="width:calc(100% - 32px);padding:16px;z-index:3">
          <h1 class="h-page" tabindex="-1" data-autofocus>${u.revealed ? `${p.name} has hatched!` : 'Something is stirring...'}</h1>
          <p class="body" style="margin:0">${u.revealed ? 'Say hello! Tap your Evochi to pet it. Walk, care and play together to help it grow.' : 'A little light flickers in the nest.'}</p>
          <button class="btn lg block" data-act="done" data-k="awake-go">${u.revealed ? 'Enter the nest' : 'Skip'}</button>
        </div>
      </div>
    </main>`;
  },
  actions: {
    done(ctx) {
      ctx.act(G.finishOnboarding);
      ctx.track('onboarding_completed');
      ctx.app.tab('home');
    },
  },
};

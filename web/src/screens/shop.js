// S10 Shop / Evochi Market (style guide §12, §18).
// Three experiences instead of one cramped screen:
//   BROWSE    a full-height, two-column catalog between the fixed header/tabs and the nav (one scroll)
//   DETAILS   a sheet per item, shaped by its category (wearables preview on your Evochi, care shows its
//             effects, habitat pieces preview in the nest, seeds show how they grow)
//   TRY-ON    a full-screen dressing room for wearables (views, zoom, preview on/off), and the nest
//             preview for habitat pieces; both keep your place in the catalog
// The economy, catalog, prices, ownership and purchase logic are unchanged.
import * as G from '../game/state.js';
import { ITEMS, SLOT_LABEL, DECOR_SLOTS, RARITY } from '../game/catalog.js';
import { html, raw, fmt } from '../ui/dom.js';
import { icon, itemImg, url, title, spriteAttr, BLANK, manifest, hydrateSprites, charEntry, loadImage } from '../ui/assets.js';
import { ICON } from '../ui/icons.js';
import { coinPill, nav, rarityTag, stageLabel } from '../core/app.js';
import { buyMany } from './homeland.js';
import { petScene } from './home.js';
import { CROPS, RECIPES } from '../game/home.js';

const CATS = [
  { id: 'featured', label: 'Featured', icon: 'star' },
  { id: 'wearables', label: 'Wearables', icon: 'wearables' },
  { id: 'care', label: 'Care', icon: 'care' },
  { id: 'habitats', label: 'Habitats', icon: 'habitats' },
  { id: 'garden', label: 'Garden', icon: 'skill_farming' },
];
const TINT = { wearable: ['bg-gold', 'bg-green', 'bg-blue', 'bg-rose', 'bg-violet'], consumable: ['bg-green', 'bg-rose'], decoration: ['bg-gold', 'bg-green'], seed: ['bg-green', 'bg-gold'] };
const SORTS = [['shop', 'Shop order'], ['low', 'Price: low'], ['high', 'Price: high']];
// the dressing room's views: the 3/4 hero both ways round, and from behind (the encounter view)
const VIEWS = [['left', '3/4'], ['right', 'Other side'], ['back', 'Back']];
const CHEV = raw('<i class="chev" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M9 5l7 7-7 7" fill="none" stroke="#B48A5A" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/></svg></i>');
const SEARCH = raw('<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5" fill="none" stroke="#6B4A34" stroke-width="2.6"/><path d="M15.5 15.5l5 5" stroke="#6B4A34" stroke-width="2.8" stroke-linecap="round"/></svg>');
const EYE = raw('<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2 12s3.6-6.5 10-6.5S22 12 22 12s-3.6 6.5-10 6.5S2 12 2 12z" fill="#FFF8E8" stroke="#4A2A14" stroke-width="2"/><circle cx="12" cy="12" r="3.4" fill="#4A2A14"/></svg>');
const LENS = raw('<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5" fill="#FFF8E8" stroke="#4A2A14" stroke-width="2.4"/><path d="M15.5 15.5l5 5" stroke="#4A2A14" stroke-width="2.8" stroke-linecap="round"/><path d="M10.5 7.5v6M7.5 10.5h6" stroke="#4A2A14" stroke-width="2" stroke-linecap="round"/></svg>');

const typeLabel = (it) => (it.category === 'wearable' ? SLOT_LABEL[it.slot] : it.category === 'consumable' ? 'Care' : it.category === 'seed' ? 'Seed' : it.decor === 'nest' ? 'Nest' : 'Nest side');
const catIcon = (it) => ({ wearable: 'wearables', consumable: 'care', seed: 'skill_farming', decoration: 'habitats' }[it.category] || 'habitats');
const rarityDot = (it) => html`<i class="rdot" style="--rc:${RARITY[it.rarity]?.color || '#C9A78C'}" aria-hidden="true"></i>${RARITY[it.rarity]?.label || ''}`;

// moving between the catalog and a preview plays a short entrance once, not on every redraw
const fresh = (t) => !!t && Date.now() - t < 450;

function listFor(cat) {
  const ids = Object.keys(ITEMS);
  if (cat === 'featured') return ids.filter((id) => ITEMS[id].featured);
  return ids.filter((id) => ITEMS[id].shop === cat);
}

/** Everything a tile, a sheet or a button needs to know about an item for this player. */
function stateOf(ctx, id) {
  const s = ctx.state;
  const it = ITEMS[id];
  const qty = G.ownedQty(s, id);
  const stack = it.category === 'consumable' || !!it.stackable;
  const owned = qty > 0 && !stack;
  const equipped = it.category === 'wearable' && s.pet?.equipped?.[it.slot] === id;
  const placed = it.category === 'decoration' && Object.values(s.nest?.placements || {}).includes(id);
  const afford = ctx.d.balance >= it.price;
  const farm = ctx.d.home?.skills?.farming?.level ?? 1;
  const needLv = it.category === 'seed' ? CROPS[it.crop].level : 0;
  return { qty, stack, owned, equipped, placed, afford, short: Math.max(0, it.price - ctx.d.balance), needLv, lowLv: needLv > farm };
}

function overlaysFor(ctx, id, showing) {
  const eq = { ...(ctx.state.pet?.equipped || {}) };
  if (showing && id && ITEMS[id]?.category === 'wearable') eq[ITEMS[id].slot] = id;
  return Object.values(eq).filter(Boolean);
}
function petSprite(ctx, overlays, view = 'left', maxH = 420, expr = 'happy') {
  const p = ctx.state.pet;
  return view === 'back' ? spriteAttr(p.stage, p.paletteId, 'default', overlays, 'battle', maxH) : spriteAttr(p.stage, p.paletteId, expr, overlays, '', maxH);
}

// ------------------------------------------------------------------ browse
function card(ctx, id, i) {
  const it = ITEMS[id];
  const st = stateOf(ctx, id);
  const tints = TINT[it.category] || ['bg-gold'];
  // one place says what you can do: a price tag, or what you already own
  const foot = st.equipped ? html`<span class="pr eq">${ICON.check}Equipped</span>`
    : st.placed ? html`<span class="pr eq">${ICON.check}In your nest</span>`
    : st.owned ? html`<span class="pr owned">Owned</span>`
    : html`<span class="pr ${st.afford ? '' : 'short'}"><img src="${icon('coin')}" alt="">${fmt(it.price)}</span>`;
  const status = st.equipped ? 'Equipped' : st.placed ? 'In your nest' : st.owned ? 'Owned' : `${it.price} EvoCoins${st.afford ? '' : `, ${st.short} more needed`}`;
  return html`<button class="prod2 ${st.equipped || st.placed ? 'is-on' : ''}" data-act="open" data-arg="${id}" data-k="p-${id}"
    aria-label="${it.name}, ${typeLabel(it)}, ${RARITY[it.rarity]?.label || ''}. ${status}${st.stack && st.qty ? `, you have ${st.qty}` : ''}">
    <span class="pp ${tints[i % tints.length]}"><img src="${itemImg(id)}" alt="">${st.stack && st.qty ? html`<span class="mk-badge qty">x${st.qty}</span>` : ''}</span>
    <b class="nm">${it.name}</b>
    <span class="meta"><img src="${icon(catIcon(it))}" alt="">${typeLabel(it)}<span class="sep">·</span>${rarityDot(it)}</span>
    ${it.category === 'seed' && st.lowLv ? html`<span class="lvreq"><img src="${icon('lock')}" alt="">Farming Lv ${st.needLv}</span>` : ''}
    ${foot}</button>`;
}

function heroOffer(ctx) {
  const id = Object.keys(ITEMS).find((k) => ITEMS[k].hero && ITEMS[k].shop) || 'golden_crest_crown';
  const it = ITEMS[id];
  const st = stateOf(ctx, id);
  return html`<section class="hero-offer" aria-label="Featured: ${it.name}">
    <span class="ho-ribbon">Featured</span>
    <div class="ho-pet"><img data-sprite="${petSprite(ctx, overlaysFor(ctx, id, true), 'left', 300)}" src="${BLANK}" alt="${ctx.state.pet.name} wearing the ${it.name}"></div>
    <div class="ho-info"><b>${it.name}</b><span class="meta">${typeLabel(it)}<span class="sep">·</span>${rarityDot(it)}</span>
      <div class="ho-row">${st.owned ? html`<span class="pr owned">${st.equipped ? 'Equipped' : 'Owned'}</span>` : html`<span class="pr ${st.afford ? '' : 'short'}"><img src="${icon('coin')}" alt="">${fmt(it.price)}</span>`}
        <button class="btn sm" data-act="try" data-arg="${id}" data-k="ho-try">${ICON.hanger}<span>Try it on</span></button></div></div>
  </section>`;
}

function filtered(ctx) {
  const u = ctx.ui('shop');
  const q = (u.q || '').trim().toLowerCase();
  let list = listFor(u.cat || 'featured');
  // on the Featured front, the hero offer is already up top
  if ((u.cat || 'featured') === 'featured' && !q) list = list.filter((id) => !ITEMS[id].hero);
  if (q) list = list.filter((id) => ITEMS[id].name.toLowerCase().includes(q) || typeLabel(ITEMS[id]).toLowerCase().includes(q));
  const sort = u.sort || 'shop';
  if (sort !== 'shop') list = [...list].sort((a, b) => (sort === 'low' ? 1 : -1) * (ITEMS[a].price - ITEMS[b].price));
  return list;
}

/** What scrolls: the hero offer (Featured only), the shelf heading and the two-column grid. */
function catalog(ctx) {
  const u = ctx.ui('shop');
  const cat = u.cat || 'featured';
  const C = CATS.find((c) => c.id === cat);
  const list = filtered(ctx);
  return html`${cat === 'featured' && !u.q ? heroOffer(ctx) : ''}
    <h2 class="h-sec sec-head shelf-head">${cat === 'featured' ? (u.q ? 'Featured items' : 'More featured items') : C.label}<span class="count">${list.length} ${list.length === 1 ? 'item' : 'items'}</span></h2>
    ${list.length ? html`<div class="shop-grid">${list.map((id, i) => card(ctx, id, i))}</div>`
      : html`<div class="empty"><img src="${icon(C.icon)}" alt="" width="54" height="54" style="opacity:.6"><p class="body" style="margin:6px 0 10px"><b>Nothing called "${u.q}" in ${C.label}.</b></p><button class="btn sm cream" data-act="clear-q" data-k="clear-q">Clear search</button></div>`}
    <div class="shelf-end" aria-hidden="true"></div>`;
}

function browse(ctx) {
  const u = ctx.ui('shop');
  const cat = u.cat || 'featured';
  const sort = u.sort || 'shop';
  const t1 = title('wordmark_evochi');
  const t2 = title('title_market');
  const C = CATS.find((c) => c.id === cat);
  return html`<main class="screen shop2 ${fresh(u.backAt) ? 'returning' : ''}" aria-label="Evochi Market">
    <header class="hud mk-hud">
      <div class="mk-title"><h1 class="sr-only">Evochi Market</h1><img src="${url(t1.file)}" alt=""><img src="${url(t2.file)}" alt=""></div>
      ${coinPill(ctx)}
    </header>
    <div class="tabs five mk-tabs" role="tablist" aria-label="Market sections">
      ${CATS.map((c) => html`<button class="tab" role="tab" aria-selected="${c.id === cat}" data-act="cat" data-arg="${c.id}" data-k="sc-${c.id}"><img src="${icon(c.icon)}" alt=""><span>${c.label}</span></button>`)}
    </div>
    <div class="shop-search">
      <label class="sq">${SEARCH}<input type="search" enterkeyhint="search" autocomplete="off" data-input="q" data-k="shop-q" placeholder="Find an item..." value="${u.q || ''}" aria-label="Find an item in ${C.label}"></label>
      <button class="sort-btn" data-act="sort" data-k="shop-sort" aria-label="Sort by ${SORTS.find((x) => x[0] === sort)[1]}">${raw('<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 4v16M7 20l-3-3.5M7 20l3-3.5M17 20V4M17 4l-3 3.5M17 4l3 3.5" fill="none" stroke="#4A2A14" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>')}<span>${SORTS.find((x) => x[0] === sort)[1]}</span></button>
    </div>
    <section class="shop-stall" aria-label="${C.label}"><div class="shop-scroll" data-k="shop-scroll">${catalog(ctx)}</div></section>
    ${nav(ctx, 'shop')}
  </main>`;
}

// ------------------------------------------------------------------ details (a sheet; the catalog stays put behind it)
function detailBody(c, id) {
  const it = ITEMS[id];
  const st = stateOf(c, id);
  const tints = TINT[it.category] || ['bg-gold'];
  let extra = '';
  if (it.category === 'wearable') {
    extra = html`<div class="pd-sec"><h3>On ${c.state.pet.name}</h3>
      <button class="pd-prev" data-act="try" data-arg="${id}" data-k="pd-prev" aria-label="Open the dressing room">${VIEWS.map(([v]) => html`<span class="pv ${v === 'right' ? 'flip' : ''}"><img data-sprite="${petSprite(c, overlaysFor(c, id, true), v === 'right' ? 'left' : v, 160)}" src="${BLANK}" alt=""></span>`)}</button>
      <p class="tiny muted" style="margin:4px 0 0">Fits all three forms of the lizard family. Tap to try it on.</p></div>`;
  } else if (it.category === 'consumable') {
    const e = it.effect || {};
    extra = html`<div class="pd-sec"><h3>What it does</h3>
      <div class="pd-fx">${e.vitality ? html`<span class="tag ok"><img src="${icon('heart')}" alt="">+${e.vitality} Vitality</span>` : ''}${e.recovery ? html`<span class="tag cream">12h cooldown</span>` : ''}${e.treat ? html`<span class="tag stage">Treat: Bond +1</span>` : ''}</div>
      <div class="pd-react"><img data-sprite="${petSprite(c, overlaysFor(c, null, false), 'left', 140, 'excited')}" src="${BLANK}" alt=""><span class="hearts-pop" aria-hidden="true"><img src="${icon('heart')}" alt=""><img src="${icon('heart')}" alt=""><img src="${icon('heart')}" alt=""></span>
        <span class="small">${c.state.pet.name} loves a ${it.name.toLowerCase()}. ${st.qty ? `You have ${st.qty}.` : 'Use it from your Bag.'}</span></div></div>`;
  } else if (it.category === 'decoration') {
    extra = html`<div class="pd-sec"><h3>Where it goes</h3><p class="small" style="margin:0">${it.decor === 'nest' ? "Replaces the nest your Evochi sleeps in." : 'Sits beside the nest, on the left, right or back spot.'}</p></div>`;
  } else if (it.category === 'seed') {
    const C = CROPS[it.crop];
    const files = manifest().home.crops.files[it.crop];
    const uses = Object.values(RECIPES).filter((R) => Object.keys(R.needs).some((k) => C.yield[k])).map((R) => ITEMS[R.makes].name);
    const t = C.growMin >= 60 ? `${Math.floor(C.growMin / 60)} h${C.growMin % 60 ? ` ${C.growMin % 60} min` : ''}` : `${C.growMin} min`;
    extra = html`<div class="pd-sec"><h3>How it grows</h3>
      <div class="grow-steps"><span><img src="${itemImg(id)}" alt=""><small>Seed</small></span>${CHEV}
        <span><img src="${url(files.sprout)}" alt=""><small>Sprout</small></span>${CHEV}
        <span><img src="${url(files.growing)}" alt=""><small>Growing</small></span>${CHEV}
        <span><img src="${url(files.ripe)}" alt=""><small>${t}</small></span></div>
      <div class="pd-fx"><span class="tag ok">${Object.entries(C.yield).map(([k, n]) => `${n} × ${ITEMS[k].name}`).join(', ')} a harvest</span><span class="tag ${st.lowLv ? 'warn' : 'cream'}">${st.lowLv ? raw(`<img src="${icon('lock')}" alt="">`) : ''}Farming Lv ${C.level}</span><span class="tag cream">+${C.xp} XP</span></div>
      ${uses.length ? html`<p class="tiny muted" style="margin:6px 0 0">Used in: ${uses.join(', ')}</p>` : ''}
      ${st.lowLv ? html`<p class="tiny" style="margin:4px 0 0;color:var(--gold-900)">You can buy these now and plant them once your Farming reaches Lv ${C.level}.</p>` : ''}</div>`;
  }
  // the state line and the actions: one primary per state, never a price on something you own
  let stateLine = '';
  let acts = '';
  const alone = it.category === 'consumable' || it.category === 'seed' || it.category === 'decoration';
  const buyBtn = st.afford ? html`<button class="btn green grow" data-act="buy" data-arg="${id}" data-k="buy"><img src="${icon('coin')}" alt="" width="22" height="22"><span>${alone ? `Purchase · ${fmt(it.price)}` : 'Purchase'}</span></button>`
    : html`<button class="btn cream grow" data-act="earn" data-arg="${id}" data-k="earn" aria-label="You need ${st.short} more EvoCoins"><img src="${icon('coin')}" alt="" width="22" height="22" class="dim"><span>Need ${fmt(st.short)} more</span></button>`;
  if (it.category === 'wearable') {
    if (st.equipped) {
      stateLine = html`<div class="pd-state eq">${ICON.checkDark}<span>Currently equipped</span></div>`;
      acts = html`<button class="btn danger grow" data-act="unequip" data-arg="${it.slot}" data-k="pd-remove">Take off</button><button class="btn cream grow" data-act="try" data-arg="${id}" data-k="try">${ICON.hanger}<span>Dressing room</span></button>`;
    } else if (st.owned) {
      stateLine = html`<div class="pd-state own">${ICON.checkDark}<span>Owned · in your Bag</span></div>`;
      acts = html`<button class="btn cream grow" data-act="try" data-arg="${id}" data-k="try">${ICON.hanger}<span>Try On</span></button><button class="btn grow" data-act="equip" data-arg="${id}" data-k="pd-equip">${ICON.shirt}<span>Equip</span></button>`;
    } else {
      acts = html`<button class="btn cream grow" data-act="try" data-arg="${id}" data-k="try">${ICON.hanger}<span>Try On</span></button>${buyBtn}`;
    }
  } else if (it.category === 'decoration') {
    if (st.placed) stateLine = html`<div class="pd-state eq">${ICON.checkDark}<span>In your nest</span></div>`;
    else if (st.owned) stateLine = html`<div class="pd-state own">${ICON.checkDark}<span>Owned · in your Bag</span></div>`;
    acts = html`<button class="btn cream grow" data-act="nest" data-arg="${id}" data-k="pd-nest"><img src="${icon('habitats')}" alt="" width="24" height="24"><span>Preview in Nest</span></button>${st.owned && !st.stack ? (st.placed ? '' : html`<button class="btn grow" data-act="place" data-arg="${id}" data-k="pd-place">Place</button>`) : buyBtn}`;
  } else {
    if (st.qty) stateLine = html`<div class="pd-state own">${ICON.checkDark}<span>You have ${st.qty}</span></div>`;
    acts = buyBtn;
  }
  return html`<div class="pd" data-cat="${it.category}" tabindex="-1" data-autofocus>
    <div class="pd-head"><div class="pd-pic ${tints[0]}"><img src="${itemImg(id)}" alt=""></div>
      <div class="pd-id"><h2 class="h-sec">${it.name}</h2><div class="row" style="gap:5px;flex-wrap:wrap"><span class="tag small cream"><img src="${icon(catIcon(it))}" alt="">${typeLabel(it)}</span>${rarityTag(id)}</div></div>
      <button class="icon-btn pd-x" data-act="modal-close" aria-label="Close" data-k="pd-close">${ICON.close}</button></div>
    <p class="pd-desc">${it.desc}</p>
    ${extra}
    ${stateLine}
    ${!st.owned || st.stack ? html`<div class="pd-price"><img src="${icon('coin')}" alt=""><b>${fmt(it.price)}</b><span class="tiny muted">You have ${fmt(c.d.balance)}</span></div>` : ''}
    <div class="pd-acts ${it.category === 'decoration' ? 'col' : ''}">${acts}</div>
  </div>`;
}

function openDetails(ctx, id) {
  ctx.ui('shop').sel = id;
  ctx.track('item_previewed', { item: id });
  ctx.modal({
    label: ITEMS[id].name,
    render: (c) => detailBody(c, id),
    actions: {
      try: (c, iid) => (c.closeModal(), enterTry(c, iid)),
      nest: (c, iid) => (c.closeModal(), enterNest(c, iid)),
      buy: (c, iid) => (c.closeModal(), confirmBuy(c, iid)),
      earn: (c, iid) => (c.closeModal(), earnModal(c, iid)),
      equip: (c, iid) => doEquip(c, iid),
      unequip: (c, slot) => doUnequip(c, slot),
      place: (c, iid) => doPlace(c, iid),
    },
  });
}

// ------------------------------------------------------------------ the dressing room (wearables) and the nest preview (habitat pieces)
// the catalog's scroll position lives in ui state (kept up to date by a scroll listener), so a rerender,
// a purchase, a preview or a trip to another tab all come back to the same shelf
function remember(ctx) {
  const sc = ctx.app.root.querySelector('.shop-scroll');
  if (sc) ctx.ui('shop').scrollY = sc.scrollTop;
}
function enterTry(ctx, id) {
  remember(ctx);
  const u = ctx.ui('shop');
  Object.assign(u, { view: 'try', sel: id, showing: true, tview: 'left', zoom: false, enterAt: Date.now() });
  ctx.sfx('reward_chime', 0.4);
  ctx.track('item_previewed', { item: id, where: 'dressing_room' });
  ctx.rerender();
}
function enterNest(ctx, id) {
  remember(ctx);
  Object.assign(ctx.ui('shop'), { view: 'nest', sel: id, showing: true, enterAt: Date.now() });
  ctx.sfx('ui_tap', 0.5);
  ctx.rerender();
}
function exitPreview(ctx) {
  const u = ctx.ui('shop');
  u.view = null;
  u.backAt = Date.now();
  ctx.sfx('ui_tap', 0.3);
  ctx.rerender();
}

/** Where to zoom: the slot's anchor in the art (the hero frame, or the back view), mirrored for the other side. */
function zoomOrigin(stage, slot, view) {
  const e = charEntry(stage);
  const back = view === 'back' && e.battle;
  const A = back ? e.battle.anchors : e.anchors;
  const W = back ? e.battle.w : e.w;
  const H = back ? e.battle.h : e.h;
  const pt = slot === 'head' ? [A.head_top[0], A.head_top[1] + H * 0.1] : slot === 'back' ? A.back : A.neck;
  if (!pt) return '50% 40%';
  // the other side is the same art mirrored by a wrapper, so the zoom point stays in the art's own coordinates
  const x = (pt[0] / W) * 100;
  return `${x.toFixed(1)}% ${((pt[1] / H) * 100).toFixed(1)}%`;
}

// some pieces sit where the camera can't see them from behind (the Tiny Crown faces forward): say so
const hiddenCache = new Map();
function hiddenFromBehind(stage, id) {
  const key = `${stage}|${id}`;
  if (hiddenCache.has(key)) return hiddenCache.get(key);
  const p = (async () => {
    const O = charEntry(stage).battle?.overlays;
    const r = O?.rects[id];
    if (!r) return true;
    const img = await loadImage(O.file);
    const c = document.createElement('canvas');
    c.width = Math.ceil(r[2] / 4);
    c.height = Math.ceil(r[3] / 4);
    const g = c.getContext('2d', { willReadFrequently: true });
    g.drawImage(img, r[0], r[1], r[2], r[3], 0, 0, c.width, c.height);
    const a = g.getImageData(0, 0, c.width, c.height).data;
    for (let i = 3; i < a.length; i += 4) if (a[i] > 12) return false;
    return true;
  })().catch(() => false);
  hiddenCache.set(key, p);
  return p;
}

function tryRoom(ctx) {
  const u = ctx.ui('shop');
  const id = u.sel;
  const it = ITEMS[id];
  const st = stateOf(ctx, id);
  const p = ctx.state.pet;
  const v = u.tview || 'left';
  const showing = u.showing !== false || st.equipped;
  const ov = overlaysFor(ctx, id, showing);
  const origin = zoomOrigin(p.stage, it.slot, v);
  let primary;
  if (st.equipped) primary = html`<button class="btn danger grow" data-act="unequip" data-arg="${it.slot}" data-k="try-remove">Take off</button>`;
  else if (st.owned) primary = html`<button class="btn grow" data-act="equip" data-arg="${id}" data-k="try-equip">${ICON.shirt}<span>Equip Now</span></button>`;
  else if (st.afford) primary = html`<button class="btn green grow" data-act="buy" data-arg="${id}" data-k="try-buy"><img src="${icon('coin')}" alt="" width="22" height="22"><span>Purchase</span></button>`;
  else primary = html`<button class="btn cream grow" data-act="earn" data-arg="${id}" data-k="try-earn"><img src="${icon('coin')}" alt="" width="22" height="22" class="dim"><span>Need ${fmt(st.short)} more</span></button>`;
  const chip = st.equipped ? html`<span class="mk-chip eq">${ICON.checkDark}Equipped</span>` : st.owned ? html`<span class="mk-chip own">${ICON.checkDark}Owned</span>`
    : showing ? html`<span class="mk-chip prev">Previewing</span>` : html`<span class="mk-chip">Without it</span>`;
  return html`<main class="screen shop-try ${fresh(u.enterAt) ? 'entering' : ''}" aria-label="Dressing room: ${it.name}">
    <header class="hud vhud"><button class="back-btn" data-act="exit" aria-label="Back to the Market" data-k="try-back">${ICON.back}</button>
      <h1 class="place-title"><span class="full">Dressing Room</span><span class="short" aria-hidden="true">Try On</span></h1>${coinPill(ctx)}</header>
    <div class="try-stage">
      <div class="try-top">
        ${st.equipped ? html`<span></span>` : html`<button class="pill" data-act="toggle" aria-pressed="${!showing}" data-k="try-toggle">${EYE}<span>${showing ? 'Show original' : 'Show preview'}</span></button>`}
        <button class="pill" data-act="zoom" aria-pressed="${!!u.zoom}" data-k="try-zoom">${LENS}<span>${u.zoom ? 'Zoom out' : 'Zoom in'}</span></button>
      </div>
      <div class="try-pet ${u.zoom ? 'zoom' : ''} ${v === 'right' ? 'flip' : ''} ${u.cheer && Date.now() - u.cheer < 600 ? 'cheer' : ''}" style="--zo:${origin}" data-act="pet-tap">
        <i class="try-rug" aria-hidden="true"></i>
        <span class="try-flip"><img data-sprite="${petSprite(ctx, ov, v === 'right' ? 'left' : v, 480)}" src="${BLANK}" alt="${p.name}${showing ? ` wearing the ${it.name}` : ''}, ${VIEWS.find((x) => x[0] === v)[1]} view"></span></div>
      <button class="try-arrow l" data-act="rot" data-arg="-1" aria-label="Turn left" data-k="try-l">${ICON.back}</button>
      <button class="try-arrow r" data-act="rot" data-arg="1" aria-label="Turn right" data-k="try-r">${ICON.next}</button>
      <div class="try-views" role="group" aria-label="Views">${VIEWS.map(([vv, label]) => html`<button aria-pressed="${vv === v}" data-act="view" data-arg="${vv}" data-k="tv-${vv}" aria-label="${label} view"><span class="${vv === 'right' ? 'flip' : ''}"><img data-sprite="${petSprite(ctx, ov, vv === 'right' ? 'left' : vv, 120)}" src="${BLANK}" alt=""></span></button>`)}</div>
    </div>
    <section class="try-panel">
      <div class="tp-id"><span class="tp-pic"><img src="${itemImg(id)}" alt=""></span><div class="tp-txt"><b>${it.name}</b><span class="meta">${SLOT_LABEL[it.slot]}<span class="sep">·</span>${rarityDot(it)}</span></div>
        <div class="tp-right">${chip}${st.owned ? '' : html`<span class="pr ${st.afford ? '' : 'short'}"><img src="${icon('coin')}" alt="">${fmt(it.price)}</span>`}</div></div>
      <div class="tp-acts"><button class="btn cream grow" data-act="exit" data-k="try-cancel">${st.owned ? 'Done' : 'Cancel'}</button>${primary}</div>
    </section>
    ${nav(ctx, 'shop')}
  </main>`;
}

function nestSpot(ctx, it) {
  const pl = ctx.state.nest?.placements || {};
  const fits = Object.entries(DECOR_SLOTS).filter(([, sl]) => sl.accepts.includes(it.decor)).map(([sid]) => sid);
  return fits.find((sid) => !pl[sid]) || fits[0];
}
function nestRoom(ctx) {
  const u = ctx.ui('shop');
  const id = u.sel;
  const it = ITEMS[id];
  const st = stateOf(ctx, id);
  const spot = nestSpot(ctx, it);
  const primary = st.owned && !st.stack ? (st.placed ? html`<span class="pr owned">In your nest</span>` : html`<button class="btn grow" data-act="place" data-arg="${id}" data-k="nest-place">Place it here</button>`)
    : st.afford ? html`<button class="btn green grow" data-act="buy" data-arg="${id}" data-k="nest-buy"><img src="${icon('coin')}" alt="" width="22" height="22"><span>Purchase</span></button>`
    : html`<button class="btn cream grow" data-act="earn" data-arg="${id}" data-k="nest-earn"><img src="${icon('coin')}" alt="" width="22" height="22" class="dim"><span>Need ${fmt(st.short)} more</span></button>`;
  const showing = u.showing !== false;
  const chip = st.placed ? html`<span class="mk-chip eq">${ICON.checkDark}In your nest</span>` : st.owned && !st.stack ? html`<span class="mk-chip own">${ICON.checkDark}Owned</span>`
    : showing ? html`<span class="mk-chip prev">Previewing</span>` : html`<span class="mk-chip">Without it</span>`;
  return html`<main class="screen shop-try shop-nestview ${fresh(u.enterAt) ? 'entering' : ''}" aria-label="Preview in nest: ${it.name}">
    <header class="hud vhud"><button class="back-btn" data-act="exit" aria-label="Back to the Market" data-k="nest-back">${ICON.back}</button>
      <h1 class="place-title"><span class="full">Preview in Nest</span><span class="short" aria-hidden="true">Preview</span></h1>${coinPill(ctx)}</header>
    <div class="try-stage nest-stage">
      <div class="try-top">${st.placed ? html`<span></span>` : html`<button class="pill" data-act="toggle" aria-pressed="${!showing}" data-k="nest-toggle">${EYE}<span>${showing ? 'Show original' : 'Show preview'}</span></button>`}
        <span class="spot-tag">${DECOR_SLOTS[spot].label} spot</span></div>
    </div>
    <section class="try-panel">
      <div class="tp-id"><span class="tp-pic"><img src="${itemImg(id)}" alt=""></span><div class="tp-txt"><b>${it.name}</b><span class="meta">${typeLabel(it)}<span class="sep">·</span>${rarityDot(it)}</span></div>
        <div class="tp-right">${chip}${st.owned && !st.stack ? '' : html`<span class="pr ${st.afford ? '' : 'short'}"><img src="${icon('coin')}" alt="">${fmt(it.price)}</span>`}</div></div>
      <div class="tp-acts"><button class="btn cream grow" data-act="exit" data-k="nest-cancel">${st.owned ? 'Done' : 'Cancel'}</button>${primary}</div>
    </section>
    ${nav(ctx, 'shop')}
  </main>`;
}

// ------------------------------------------------------------------ actions shared by the sheet and the previews
function doEquip(ctx, id) {
  const r = ctx.act(G.equip, id);
  if (r.error) return;
  ctx.sfx('reward_chime', 0.5);
  ctx.toast(`${ITEMS[id].name} equipped`, 'ok', 'wearables');
  ctx.track('accessory_equipped', { item: id, where: 'market' });
  const u = ctx.ui('shop');
  if (u.view === 'try') u.cheer = Date.now();
}
function doUnequip(ctx, slot) {
  ctx.act(G.unequip, slot);
  ctx.sfx('ui_tap');
  ctx.ui('shop').showing = false;
}
function doPlace(ctx, id) {
  const it = ITEMS[id];
  const sid = nestSpot(ctx, it);
  const r = ctx.act(G.placeDecoration, id, sid);
  if (r.error) return;
  ctx.toast(`${it.name} placed in the ${DECOR_SLOTS[sid].label.toLowerCase()} spot`, 'ok', 'decorations');
  ctx.sfx('ui_tap');
  ctx.track('decoration_placed', { item: id, where: 'market' });
}
function earnModal(ctx, id) {
  ctx.modal({
    label: 'Not enough EvoCoins',
    render: (c) => {
      const it = ITEMS[id];
      return html`<div class="stack">
        <div class="row"><img src="${icon('coin')}" alt="" width="40" height="40"><h2 class="h-sec">Almost there!</h2></div>
        <p class="body">${it.name} costs ${fmt(it.price)} EvoCoins and you have ${fmt(c.d.balance)}. Complete today's quests on your Journey to earn the rest.</p>
        <button class="btn block" data-act="go-journey" data-autofocus>Open Journey</button>
        <button class="btn cream block" data-act="modal-close">Keep browsing</button></div>`;
    },
    actions: { 'go-journey': (c) => (c.closeModal(), c.app.tab('journey')) },
  });
}
function confirmBuy(ctx, id) {
  const it = ITEMS[id];
  const m = { requestId: G.uid('buy'), pending: false, n: 1 };
  const multi = it.category === 'seed' || it.category === 'consumable';
  ctx.modal({
    center: true,
    label: `Buy ${it.name}`,
    render: (c) => html`<div class="stack center">
      <img src="${itemImg(id)}" alt="" width="104" height="104" style="margin:0 auto">
      <h2 class="h-sec">Buy ${it.name}?</h2>
      ${multi ? html`<div class="qty-pick" role="radiogroup" aria-label="How many">${[1, 3, 5].map((n) => html`<button role="radio" aria-checked="${m.n === n}" data-act="buy-n" data-arg="${n}" ${c.d.balance >= it.price * n ? '' : raw('disabled')}>x${n}<small><img src="${icon('coin')}" alt="">${fmt(it.price * n)}</small></button>`)}</div>` : ''}
      <div class="kv card inset" style="padding:10px 12px;text-align:left">
        <span>Price</span><b>${fmt(it.price * m.n)} EvoCoins</b>
        <span>Balance after</span><b>${fmt(c.d.balance - it.price * m.n)} EvoCoins</b>
      </div>
      ${it.category === 'wearable' ? html`<p class="small muted" style="margin:0">Fits all three forms of the lizard family. Owned by your account and kept forever.</p>` : ''}
      <button class="btn green block ${m.pending ? 'loading' : ''}" data-act="confirm-buy" data-autofocus ${m.pending ? raw('disabled') : ''}><span>Purchase${m.n > 1 ? ` ${m.n}` : ''} for ${fmt(it.price * m.n)}</span><i class="spinner" style="display:${m.pending ? 'block' : 'none'}"></i></button>
      <button class="btn cream block" data-act="modal-close">Cancel</button></div>`,
    actions: {
      'buy-n': (c, n) => {
        m.n = Number(n);
        c.app.renderModals();
      },
      'confirm-buy': (c) => {
        if (m.pending) return; // debounced: one tap only, and one request id for the whole purchase
        m.pending = true;
        c.app.renderModals();
        setTimeout(() => {
          const r = m.n > 1 ? buyMany(c, id, m.n, m.requestId) : c.act(G.purchase, id, m.requestId);
          c.closeModal();
          if (!r.error) {
            c.track('item_purchased', { item: id, price: it.price * m.n, qty: m.n });
            purchasedModal(c, id, m.n);
          }
        }, 380);
      },
    },
  });
}

function purchasedModal(ctx, id, n = 1) {
  const it = ITEMS[id];
  const u = ctx.ui('shop');
  if (u.view === 'try') u.cheer = Date.now();
  ctx.scene.react('reward');
  ctx.sfx('purchase', 0.7);
  ctx.modal({
    center: true,
    label: 'Purchased',
    render: () => html`<div class="stack center bought">
      <div class="story-banner">Purchased!</div>
      <div class="buy-pop" aria-hidden="true"><i class="rays"></i>${Array.from({ length: 10 }, (_, i) => html`<i class="spark" style="--a:${i * 36}deg;--d:${78 + (i % 3) * 20}px"></i>`)}${Array.from({ length: 5 }, (_, i) => html`<img class="coin" src="${icon('coin')}" alt="" style="--i:${i}">`)}<img class="item" src="${itemImg(id)}" alt=""></div>
      <h2 class="h-sec">${n > 1 ? `${n} × ${it.name}` : it.name} ${n > 1 ? 'are' : 'is'} yours!</h2>
      <p class="body" style="margin:0">${it.category === 'seed' ? "They're in your Bag's Pantry." : 'It has been added to your Bag.'}</p>
      ${it.category === 'seed' ? html`<button class="btn green block" data-act="plant-now" data-autofocus>Plant now</button>` : ''}
      ${it.category === 'wearable' ? html`<button class="btn green block" data-act="equip-now" data-autofocus data-k="equip-now">${ICON.shirt}<span>Equip Now</span></button>` : ''}
      ${it.category === 'decoration' ? html`<button class="btn green block" data-act="place-now" data-autofocus>Place in nest</button>` : ''}
      <button class="btn cream block" data-act="view-bag">View in Bag</button>
      <button class="btn ghost block" data-act="modal-close">Keep shopping</button></div>`,
    actions: {
      'equip-now': (c) => {
        c.closeModal();
        doEquip(c, id);
        // stay where you were: the dressing room shows it on, the catalog opens its sheet in the equipped state
        if (u.view !== 'try') openDetails(c, id);
      },
      'plant-now': (c) => (c.closeModal(), c.go('garden')),
      'place-now': (c) => {
        c.closeModal();
        doPlace(c, id);
        if (u.view !== 'nest') openDetails(c, id);
      },
      'view-bag': (c) => {
        c.closeModal();
        const cat = { wearable: 'wearable', consumable: 'consumable', decoration: 'decoration', seed: 'pantry' }[it.category] || 'wearable';
        c.app.ui.bag = { cat, sel: id };
        c.app.ui.shop = { ...u, view: null };
        c.app.tab('bag');
      },
    },
  });
}

// ------------------------------------------------------------------ the screen
export const shop = {
  id: 'shop',
  scene(ctx) {
    const u = ctx.ui('shop');
    if (u.view === 'nest' && ITEMS[u.sel]) {
      // the real nest with the piece in its spot (unless you're comparing with the original)
      const it = ITEMS[u.sel];
      const pl = { ...(ctx.state.nest?.placements || {}) };
      if (u.showing !== false) pl[nestSpot(ctx, it)] = u.sel;
      const sc = petScene(ctx, { decor: pl, focus: { x: 0.5, y: 0.5 } });
      sc.pet.sleeping = false;
      return sc;
    }
    // browsing and the dressing room: the market stall as a backdrop, the Evochi drawn by the page itself
    return { habitat: 'market', zoom: 1.32, background: '#C9A27A', focus: { x: 0.3, y: 0.42 } };
  },
  render(ctx) {
    const u = ctx.ui('shop');
    if (u.view === 'try' && ITEMS[u.sel]?.category === 'wearable' && ctx.state.pet) return tryRoom(ctx);
    if (u.view === 'nest' && ITEMS[u.sel]?.category === 'decoration' && ctx.state.pet) return nestRoom(ctx);
    u.view = null;
    return browse(ctx);
  },
  mount(ctx, el) {
    const u = ctx.ui('shop');
    if (u.view === 'try' && u.tview === 'back' && ITEMS[u.sel]) {
      const st = stateOf(ctx, u.sel);
      if (u.showing !== false || st.equipped) {
        const stage = ctx.state.pet.stage;
        hiddenFromBehind(stage, u.sel).then((hidden) => {
          const stg = el?.isConnected && el.querySelector('.try-stage');
          if (hidden && stg && !stg.querySelector('.try-note')) stg.insertAdjacentHTML('beforeend', `<p class="try-note">The ${ITEMS[u.sel].name} can't be seen from behind.</p>`);
        });
      }
    }
    const sc = el?.querySelector('.shop-scroll');
    if (sc) {
      sc.scrollTop = u.scrollY || 0;
      sc.addEventListener('scroll', () => (u.scrollY = sc.scrollTop), { passive: true });
    }
  },
  onPetTap(ctx) {
    ctx.scene.react('pet');
    ctx.sfx('pet_chirp');
  },
  inputs: {
    // only the shelf is redrawn while typing, so the field (and the phone keyboard) stays put
    q(ctx, v) {
      const u = ctx.ui('shop');
      u.q = v;
      u.scrollY = 0;
      const sc = ctx.app.root.querySelector('.shop-scroll');
      if (!sc) return ctx.rerender();
      sc.innerHTML = String(catalog(ctx));
      hydrateSprites(sc);
      sc.scrollTop = 0;
    },
  },
  actions: {
    cat(ctx, c) {
      const u = ctx.ui('shop');
      if (u.cat === c) return;
      u.cat = c;
      u.q = '';
      u.scrollY = 0;
      ctx.sfx('ui_tap', 0.3);
      ctx.rerender();
    },
    'pet-tap'(ctx) {
      const u = ctx.ui('shop');
      u.cheer = Date.now();
      ctx.sfx('pet_chirp');
      ctx.rerender();
    },
    sort(ctx) {
      const u = ctx.ui('shop');
      u.scrollY = 0;
      const i = SORTS.findIndex((x) => x[0] === (u.sort || 'shop'));
      u.sort = SORTS[(i + 1) % SORTS.length][0];
      ctx.sfx('ui_tap', 0.3);
      ctx.rerender();
    },
    'clear-q'(ctx) {
      const u = ctx.ui('shop');
      u.q = '';
      u.scrollY = 0;
      ctx.rerender();
    },
    open(ctx, id) {
      ctx.sfx('ui_tap', 0.4);
      openDetails(ctx, id);
    },
    // kept for links from elsewhere (the Bag's "Visit the Market", old saves of ui.shop.sel)
    sel(ctx, id) {
      openDetails(ctx, id);
    },
    try(ctx, id) {
      enterTry(ctx, id || ctx.ui('shop').sel);
    },
    nest(ctx, id) {
      enterNest(ctx, id || ctx.ui('shop').sel);
    },
    exit(ctx) {
      exitPreview(ctx);
    },
    rot(ctx, d) {
      const u = ctx.ui('shop');
      const i = VIEWS.findIndex((x) => x[0] === (u.tview || 'left'));
      u.tview = VIEWS[(i + Number(d) + VIEWS.length) % VIEWS.length][0];
      ctx.sfx('ui_tap', 0.3);
      ctx.rerender();
    },
    view(ctx, v) {
      ctx.ui('shop').tview = v;
      ctx.sfx('ui_tap', 0.3);
      ctx.rerender();
    },
    toggle(ctx) {
      const u = ctx.ui('shop');
      u.showing = u.showing === false;
      ctx.sfx(u.showing ? 'reward_chime' : 'ui_tap', 0.35);
      ctx.rerender();
    },
    zoom(ctx) {
      const u = ctx.ui('shop');
      u.zoom = !u.zoom;
      ctx.sfx('ui_tap', 0.3);
      ctx.rerender();
    },
    buy(ctx, id) {
      confirmBuy(ctx, id || ctx.ui('shop').sel);
    },
    earn(ctx, id) {
      earnModal(ctx, id || ctx.ui('shop').sel);
    },
    equip(ctx, id) {
      doEquip(ctx, id);
    },
    unequip(ctx, slot) {
      doUnequip(ctx, slot);
    },
    place(ctx, id) {
      doPlace(ctx, id);
    },
  },
};

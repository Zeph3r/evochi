// S10 Shop / Evochi Market (style guide §12, §18).
import * as G from '../game/state.js';
import { ITEMS, SLOT_LABEL } from '../game/catalog.js';
import { html, raw, fmt } from '../ui/dom.js';
import { icon, itemImg, url, title } from '../ui/assets.js';
import { ICON } from '../ui/icons.js';
import { coinPill, nav, rarityTag } from '../core/app.js';
import { buyMany } from './homeland.js';
import { CROPS } from '../game/home.js';

const CATS = [
  { id: 'featured', label: 'Featured', icon: 'star' },
  { id: 'wearables', label: 'Wearables', icon: 'wearables' },
  { id: 'care', label: 'Care', icon: 'care' },
  { id: 'habitats', label: 'Habitats', icon: 'habitats' },
  { id: 'garden', label: 'Garden', icon: 'skill_farming' },
];
const TINT = { wearable: ['bg-gold', 'bg-green', 'bg-blue', 'bg-rose', 'bg-violet'], consumable: ['bg-green'], decoration: ['bg-gold', 'bg-green'], seed: ['bg-green', 'bg-gold'] };

function listFor(cat) {
  const ids = Object.keys(ITEMS);
  if (cat === 'featured') return ids.filter((id) => ITEMS[id].featured);
  return ids.filter((id) => ITEMS[id].shop === cat);
}

function tagFor(it) {
  if (it.category === 'wearable') return [it.slot === 'neck' ? 'Neck' : SLOT_LABEL[it.slot], 'wearables'];
  if (it.category === 'consumable') return ['Care', 'care'];
  if (it.category === 'seed') return ['Seed', 'skill_farming'];
  return ['Habitat', 'habitats'];
}

export const shop = {
  id: 'shop',
  scene(ctx) {
    const s = ctx.state;
    const u = ctx.ui('shop');
    const p = s.pet;
    const eq = { ...(p.equipped || {}) };
    const sel = ITEMS[u.sel || 'golden_crest_crown'];
    if (u.tryOn && sel?.category === 'wearable') eq[sel.slot] = u.sel || 'golden_crest_crown';
    return {
      habitat: 'market', zoom: 1.32, background: '#C9A27A', focus: { x: 0.26, y: u.groundY || 0.42 },
      pet: { stage: p.stage, palette: p.paletteId, status: ctx.d.pet.status, equipped: Object.values(eq), label: `Pet ${p.name}`, scale: p.stage === 3 ? 0.85 : 1 },
    };
  },
  afterLayout(ctx, el) {
    const g = el.querySelector('.shop-lower');
    const top = g.getBoundingClientRect().top - ctx.app.root.getBoundingClientRect().top;
    ctx.ui('shop').groundY = Math.round(top - 18);
    return shop.scene(ctx);
  },

  onPetTap(ctx) {
    ctx.scene.react('pet');
    ctx.sfx('pet_chirp');
  },
  render(ctx) {
    const s = ctx.state;
    const u = ctx.ui('shop');
    const cat = u.cat || 'featured';
    const list = listFor(cat);
    if (!u.sel || !ITEMS[u.sel]) u.sel = cat === 'featured' ? 'golden_crest_crown' : list[0];
    const id = u.sel;
    const it = ITEMS[id];
    const own = G.ownedQty(s, id);
    const stack = it.category === 'consumable' || it.stackable;
    const owned = own > 0 && !stack;
    const afford = ctx.d.balance >= it.price;
    const [tg, tgi] = tagFor(it);
    const t1 = title('wordmark_evochi');
    const t2 = title('title_market');
    return html`<main class="screen" aria-label="Evochi Market">
      <header class="hud">
        <div style="display:flex;flex-direction:column;align-items:center"><h1 class="sr-only">Evochi Market</h1>
          <img src="${url(t1.file)}" alt="" style="height:36px;width:auto"><img src="${url(t2.file)}" alt="" style="height:30px;width:auto;margin-top:-4px"></div>
        ${coinPill(ctx)}
      </header>
      <div class="tabs five" role="tablist" aria-label="Market sections" style="grid-template-columns:repeat(5,minmax(0,1fr));margin-top:8px;position:relative;z-index:4">
        ${CATS.map((c) => html`<button class="tab" role="tab" aria-selected="${c.id === cat}" data-act="cat" data-arg="${c.id}" data-k="sc-${c.id}"><img src="${icon(c.icon)}" alt=""><span>${c.label}</span></button>`)}
      </div>
      <div class="shop-stage">
      <section class="card shop-feature" aria-live="polite" aria-label="${it.name}">
        <span class="tag red">${cat === 'featured' ? 'FEATURED' : tg.toUpperCase()}</span>
        <div class="thumb"><img src="${itemImg(id)}" alt=""></div>
        <h2 style="margin-right:64px">${it.name}</h2>
        <p class="desc" style="margin:0 0 6px">${it.desc}</p>
        <div class="row" style="gap:4px;flex-wrap:wrap"><span class="tag small cream"><img src="${icon(tgi)}" alt="">${it.category === 'wearable' ? 'Wearable' : it.category === 'consumable' ? 'Consumable' : it.category === 'seed' ? `Farming Lv ${CROPS[it.crop].level}` : 'Decoration'}</span><span class="tag small cream">${tg}</span>${rarityTag(id)}</div>
        <div class="price-row"><img src="${icon('coin')}" alt="">${fmt(it.price)}${stack && own ? html`<span class="tiny muted" style="margin-left:auto">Owned x${own}</span>` : ''}</div>
        <div class="row" style="gap:8px">
          ${it.category === 'wearable' ? html`<button class="btn sm cream" data-act="try" data-k="try" aria-pressed="${!!u.tryOn}">${ICON.hanger}<span>${u.tryOn ? 'Take off' : 'Try On'}</span></button>` : ''}
          ${owned ? html`<button class="btn sm green" data-act="view-bag" data-k="owned">${ICON.checkDark}<span>Owned</span></button>`
            : afford ? html`<button class="btn sm green" data-act="buy" data-k="buy"><img src="${icon('coin')}" alt="" width="22" height="22"><span>Purchase</span></button>`
            : html`<button class="btn sm cream" data-act="earn" data-k="earn" aria-label="Purchase - you need ${fmt(it.price - ctx.d.balance)} more EvoCoins"><img src="${icon('coin')}" alt="" width="22" height="22"><span>Purchase</span></button>`}
        </div>
      </section>
      </div>
      <section class="shop-lower sheet-bg">
        <div class="row between" style="margin-bottom:8px"><h2 class="h-card row" style="gap:6px">${ICON.grid ? raw(ICON.grid.s.replace('<svg', '<svg width="20" height="20"')) : ''}${cat === 'featured' ? 'Featured Items' : CATS.find((c) => c.id === cat).label}</h2>
          ${cat === 'featured' ? html`<button class="btn ghost" style="min-height:28px;padding:0;font-size:13px" data-act="cat" data-arg="wearables" data-k="seeall">See All &rsaquo;</button>` : ''}</div>
        <div class="grid fill-scroll" style="grid-template-columns:repeat(3,minmax(0,1fr))">
          ${list.map((pid, i) => {
            const pit = ITEMS[pid];
            const [ptg, ptgi] = tagFor(pit);
            const tint = (TINT[pit.category] || ['bg-gold'])[i % (TINT[pit.category] || ['bg-gold']).length];
            const pown = G.ownedQty(s, pid) > 0 && !(pit.category === 'consumable' || pit.stackable);
            return html`<button class="prod" aria-pressed="${pid === id}" data-act="sel" data-arg="${pid}" data-k="p-${pid}" aria-label="${pit.name}, ${pit.price} EvoCoins${pown ? ', owned' : ''}">
              <div class="pic ${tint}"><img src="${itemImg(pid)}" alt=""></div>
              ${pown ? html`<span class="owned tag small ok">Owned</span>` : ''}
              <span class="nm">${pit.name}</span>
              <span class="tag small cream" style="align-self:flex-start"><img src="${icon(ptgi)}" alt="">${ptg}</span>
              <span class="price"><img src="${icon('coin')}" alt="">${fmt(pit.price)}</span></button>`;
          })}
        </div>
      </section>
      <div style="height:6px;flex:none"></div>
      ${nav(ctx, 'shop')}
    </main>`;
  },
  actions: {
    cat(ctx, c) {
      const u = ctx.ui('shop');
      u.cat = c;
      u.sel = null;
      u.tryOn = false;
      ctx.rerender();
    },
    sel(ctx, id) {
      const u = ctx.ui('shop');
      u.sel = id;
      u.tryOn = false;
      ctx.sfx('ui_tap', 0.4);
      ctx.track('item_previewed', { item: id });
      ctx.rerender();
    },
    try(ctx) {
      const u = ctx.ui('shop');
      u.tryOn = !u.tryOn;
      if (u.tryOn) {
        ctx.scene.react('equip');
        ctx.sfx('reward_chime', 0.4);
      }
      ctx.rerender();
    },
    earn(ctx) {
      ctx.modal({
        label: 'Not enough EvoCoins',
        render: (c) => {
          const it = ITEMS[c.ui('shop').sel];
          return html`<div class="stack">
            <div class="row"><img src="${icon('coin')}" alt="" width="40" height="40"><h2 class="h-sec">Almost there!</h2></div>
            <p class="body">${it.name} costs ${fmt(it.price)} EvoCoins and you have ${fmt(c.d.balance)}. Complete today's quests on your Journey to earn the rest.</p>
            <button class="btn block" data-act="go-journey" data-autofocus>Open Journey</button>
            <button class="btn cream block" data-act="modal-close">Keep browsing</button></div>`;
        },
        actions: { 'go-journey': (c) => (c.closeModal(), c.app.tab('journey')) },
      });
    },
    'view-bag'(ctx) {
      const id = ctx.ui('shop').sel;
      ctx.app.ui.bag = { cat: ITEMS[id].category, sel: id };
      ctx.app.tab('bag');
    },
    buy(ctx) {
      const id = ctx.ui('shop').sel;
      const it = ITEMS[id];
      const m = { requestId: G.uid('buy'), pending: false, n: 1 };
      const multi = it.category === 'seed';
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
            if (m.pending) return; // debounced: one tap only
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
    },
  },
};

function purchasedModal(ctx, id, n = 1) {
  const it = ITEMS[id];
  ctx.scene.react('reward');
  ctx.modal({
    center: true,
    label: 'Purchased',
    render: () => html`<div class="stack center">
      <img src="${itemImg(id)}" alt="" width="110" height="110" style="margin:0 auto">
      <h2 class="h-sec">${n > 1 ? `${n} × ${it.name}` : it.name} ${n > 1 ? 'are' : 'is'} yours!</h2>
      <p class="body" style="margin:0">${it.category === 'seed' ? 'They\'re in your Bag\'s Pantry.' : 'It\'s waiting in your Bag.'}</p>
      ${it.category === 'seed' ? html`<button class="btn green block" data-act="plant-now" data-autofocus>Plant now</button>` : ''}
      ${it.category === 'wearable' ? html`<button class="btn block" data-act="equip-now" data-autofocus>${ICON.shirt}<span>Equip now</span></button>` : ''}
      ${it.category === 'decoration' ? html`<button class="btn block" data-act="place-now" data-autofocus>Place in nest</button>` : ''}
      <button class="btn cream block" data-act="modal-close">Keep shopping</button></div>`,
    actions: {
      'equip-now': (c) => {
        c.closeModal();
        const r = c.act(G.equip, id);
        if (!r.error) {
          c.toast(`${it.name} equipped`, 'ok', 'wearables');
          c.ui('shop').tryOn = false;
          c.app.ui.bag = { cat: 'wearable', sel: id };
          c.app.tab('bag');
        }
      },
      'plant-now': (c) => {
        c.closeModal();
        c.go('garden');
      },
      'place-now': (c) => {
        c.closeModal();
        c.app.ui.bag = { cat: 'decoration', sel: id };
        c.app.tab('bag');
      },
    },
  });
}

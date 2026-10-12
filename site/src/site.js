// Evochi website: colourway switcher, pet hops, XP calculator, screenshot scroller, copy buttons.
(function () {
  'use strict';
  var doc = document;
  var $$ = function (sel, root) { return Array.prototype.slice.call((root || doc).querySelectorAll(sel)); };
  var reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Put the store the visitor can actually use first.
  var ua = navigator.userAgent || '';
  if (/android/i.test(ua)) doc.documentElement.classList.add('is-android');

  // ------------------------------------------------------------ colourways
  var LABELS = { amber: 'Amber', forest: 'Forest', coral: 'Coral', ocean: 'Ocean', amethyst: 'Amethyst', obsidian: 'Obsidian' };
  var STAGE_NAMES = { s01: 'Eggling', s02: 'Juvenile', s03: 'Elder' };
  function setPalette(pal, remember) {
    if (!LABELS[pal]) return;
    $$('img[data-stage]').forEach(function (img) {
      var st = img.getAttribute('data-stage');
      img.src = 'assets/img/pets/' + st + '-' + pal + '.webp';
      if (img.getAttribute('alt')) img.alt = 'The ' + STAGE_NAMES[st] + ' in the ' + LABELS[pal] + ' colourway';
    });
    $$('.swatch').forEach(function (b) { b.setAttribute('aria-pressed', String(b.getAttribute('data-palette') === pal)); });
    var out = doc.getElementById('pal-name');
    if (out) out.textContent = LABELS[pal];
    if (remember) { try { localStorage.setItem('evochi.palette', pal); } catch (e) { /* storage unavailable */ } }
  }
  $$('.swatch').forEach(function (b) {
    b.addEventListener('click', function () { setPalette(b.getAttribute('data-palette'), true); });
    // warm the cache so the swap is instant
    b.addEventListener('pointerenter', function () {
      var pal = b.getAttribute('data-palette');
      ['s01', 's02', 's03'].forEach(function (st) { var i = new Image(); i.src = 'assets/img/pets/' + st + '-' + pal + '.webp'; });
    }, { once: true });
  });
  try { var saved = localStorage.getItem('evochi.palette'); if (saved && saved !== 'amber') setPalette(saved, false); } catch (e) { /* ignore */ }

  // ------------------------------------------------------------ say hi
  var chirp = null;
  $$('.pet').forEach(function (btn) {
    btn.addEventListener('click', function () {
      if (!reduced) {
        btn.classList.remove('hop');
        void btn.offsetWidth;
        btn.classList.add('hop');
      }
      try {
        if (!chirp) { chirp = new Audio('assets/chirp.mp3'); chirp.volume = 0.5; }
        chirp.currentTime = 0;
        var p = chirp.play();
        if (p && p.catch) p.catch(function () {});
      } catch (e) { /* audio unavailable */ }
    });
    btn.addEventListener('animationend', function () { btn.classList.remove('hop'); });
  });

  // ------------------------------------------------------------ XP calculator (same rules as the game, config v1)
  var XP = { base: 100, milestones: [{ id: 'm25', r: 0.25, xp: 10 }, { id: 'm50', r: 0.5, xp: 15 }, { id: 'm100', r: 1, xp: 25 }], stretchMax: 20, stretchSpan: 0.5 };
  var TO_LEVEL_10 = 3340; // sum of roundToNearest10(120 + 40n + 4n^2) for n = 0..8
  var fmt = function (n) { return n.toLocaleString('en-US'); };
  function activityXp(S, G) {
    var base = Math.floor(XP.base * Math.min(S, G) / G);
    var ms = 0, reached = {};
    XP.milestones.forEach(function (m) { if (S >= m.r * G) { ms += m.xp; reached[m.id] = true; } });
    var span = XP.stretchSpan * G;
    var stretch = Math.floor(XP.stretchMax * Math.min(Math.max(S - G, 0), span) / span);
    return { base: base, milestones: ms, stretch: stretch, total: base + ms + stretch, reached: reached };
  }
  var range = doc.getElementById('steps-today');
  if (range) {
    var out = doc.getElementById('steps-out');
    var total = doc.getElementById('xp-total');
    var bar = doc.getElementById('xp-bar');
    var note = doc.getElementById('xp-note');
    var update = function () {
      var S = Number(range.value);
      var checked = doc.querySelector('input[name="goal"]:checked');
      var G = Number(checked ? checked.value : 7000);
      var r = activityXp(S, G);
      out.textContent = fmt(S);
      total.textContent = fmt(r.total);
      bar.style.width = Math.min(100, Math.round(100 * S / G)) + '%';
      $$('[data-chip]').forEach(function (c) {
        var id = c.getAttribute('data-chip');
        if (id === 'stretch') { c.textContent = 'Extra · +' + r.stretch; c.classList.toggle('on', r.stretch > 0); }
        else c.classList.toggle('on', !!r.reached[id]);
      });
      var msg;
      if (S === 0) msg = 'No steps yet. Rest days are part of the game: two low days a week never cost vitality.';
      else {
        msg = fmt(r.base) + ' XP for the walk' + (r.milestones ? ' plus ' + r.milestones + ' milestone XP' : '') + (r.stretch ? ' and ' + r.stretch + ' extra for going past your goal' : '') + '. ';
        msg += S >= 0.5 * G ? "That's an active day. " : "Under half your goal, so it isn't an active day yet. ";
        msg += 'At this pace an Eggling reaches level 10 in about ' + Math.ceil(TO_LEVEL_10 / r.total) + ' days.';
      }
      note.textContent = msg;
      range.setAttribute('aria-valuetext', fmt(S) + ' steps, ' + fmt(r.total) + ' XP');
    };
    range.addEventListener('input', update);
    $$('input[name="goal"]').forEach(function (g) { g.addEventListener('change', update); });
    update();
  }

  // ------------------------------------------------------------ screenshot scroller
  var shots = doc.getElementById('shots');
  $$('[data-scroll]').forEach(function (b) {
    b.addEventListener('click', function () {
      if (!shots) return;
      var card = shots.querySelector('.shot');
      var step = card ? card.getBoundingClientRect().width + 20 : 280;
      shots.scrollBy({ left: Number(b.getAttribute('data-scroll')) * step, behavior: reduced ? 'auto' : 'smooth' });
    });
  });

  // ------------------------------------------------------------ beta waitlist
  var wl = doc.getElementById('beta');
  if (wl) {
    var api = wl.getAttribute('data-api') || '';
    var goal = Number(String(wl.getAttribute('data-goal')).replace(/,/g, '')) || 5000;
    var spots = Number(String(wl.getAttribute('data-spots')).replace(/,/g, '')) || 1000;
    var site = wl.getAttribute('data-site') || (location.origin + location.pathname.replace(/[^/]*$/, ''));
    var form = doc.getElementById('wl-form');
    var status = doc.getElementById('wl-status');
    var done = doc.getElementById('wl-done');
    var NAMES = { amber: 'Amber', forest: 'Forest', coral: 'Coral', ocean: 'Ocean', amethyst: 'Amethyst', obsidian: 'Obsidian' };
    var store = {
      get: function () { try { return JSON.parse(localStorage.getItem('evochi.wl') || 'null'); } catch (e) { return null; } },
      set: function (v) { try { localStorage.setItem('evochi.wl', JSON.stringify(v)); } catch (e) { /* ignore */ } }
    };
    // ?ref=CODE from a friend's link: remember it, and keep the URL clean
    try {
      var m = location.search.match(/[?&]ref=([A-Za-z0-9_-]{4,24})/);
      if (m) { localStorage.setItem('evochi.ref', m[1]); if (history.replaceState) history.replaceState(null, '', location.pathname + location.hash); }
    } catch (e) { /* ignore */ }
    var refCode = (function () { try { return localStorage.getItem('evochi.ref') || ''; } catch (e) { return ''; } })();

    function renderCount(d) {
      if (!d || typeof d.count !== 'number') return;
      var box = doc.getElementById('wl-count');
      var pct = Math.max(0, Math.min(100, Math.round(100 * d.count / (d.goal || goal))));
      box.hidden = false;
      box.querySelector('[data-count]').textContent = fmt(d.count);
      box.querySelector('[data-goal]').textContent = fmt(d.goal || goal);
      box.querySelector('[data-bar]').style.width = pct + '%';
      var hatch = box.querySelector('[data-hatch]');
      if (d.count >= (d.goal || goal)) hatch.textContent = 'The nest is warm. Mochi has hatched and beta invites are going out in waitlist order.';
      var f = box.querySelector('[data-founders]');
      var left = typeof d.founders_left === 'number' ? d.founders_left : null;
      if (left !== null) { f.hidden = false; f.querySelector('[data-founders-text]').textContent = left > 0 ? fmt(left) + " Founder's Crowns left" : "Founder's Crowns: all claimed"; }
      $$('[data-count-mini]').forEach(function (el) { el.textContent = fmt(d.count); });
    }
    function loadCount() {
      if (!api) return; // the preview has no API; the live count appears on the hosted site
      fetch(api + '/count', { cache: 'no-store' }).then(function (r) { return r.ok ? r.json() : null; }).then(renderCount).catch(function () {});
    }
    function showDone(me) {
      form.hidden = true;
      done.hidden = false;
      done.querySelector('[data-position]').textContent = fmt(me.position);
      done.querySelector('[data-colour-name]').textContent = NAMES[me.colour] || 'Ocean';
      done.querySelector('.wl-done-egg').src = 'assets/img/pets/s01-' + (NAMES[me.colour] ? me.colour : 'ocean') + '.webp';
      done.querySelector('[data-founder-line]').hidden = !me.founder;
      done.querySelector('[data-referrals]').textContent = fmt(me.referrals || 0);
      var link = site.replace(/\/+$/, '') + '/?ref=' + me.code;
      done.querySelector('[data-ref-link]').textContent = link;
      var text = encodeURIComponent("I'm #" + fmt(me.position) + " in line for Evochi, a walking pet that grows from your steps. Join with my link and we both move up:");
      var enc = encodeURIComponent(link);
      done.querySelector('[data-share="x"]').href = 'https://twitter.com/intent/tweet?text=' + text + '&url=' + enc;
      done.querySelector('[data-share="wa"]').href = 'https://wa.me/?text=' + text + '%20' + enc;
      done.querySelector('[data-share="tg"]').href = 'https://t.me/share/url?url=' + enc + '&text=' + text;
      if (me.count !== undefined) renderCount(me);
    }
    var copyRef = done.querySelector('[data-copy-ref]');
    if (copyRef) copyRef.addEventListener('click', function () {
      var el = done.querySelector('[data-ref-link]'); var st = done.querySelector('.copied');
      var ok = function (y) { st.textContent = y ? 'Copied' : 'Select the link and copy it'; setTimeout(function () { st.textContent = ''; }, 2500); };
      try { navigator.clipboard.writeText(el.textContent).then(function () { ok(true); }, function () { ok(false); }); } catch (e) { ok(false); }
    });
    // returning visitor: show their place again, refreshed from the server when possible
    var saved = store.get();
    if (saved && saved.code) {
      showDone(saved);
      if (api) fetch(api + '/me?code=' + encodeURIComponent(saved.code), { cache: 'no-store' }).then(function (r) { return r.ok ? r.json() : null; })
        .then(function (me) { if (me && me.position) { var merged = Object.assign({}, saved, me); store.set(merged); showDone(merged); } }).catch(function () {});
    }
    loadCount();
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var emailEl = doc.getElementById('wl-email');
      var email = (emailEl.value || '').trim();
      var colour = (form.querySelector('input[name="colour"]:checked') || {}).value || 'ocean';
      status.className = 'wl-status';
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) { status.textContent = 'That email address doesn\'t look right.'; emailEl.focus(); return; }
      if (!api) { status.className = 'wl-status ok'; status.textContent = 'This is the preview, so sign-ups aren\'t saved here. On evochigame.com this button adds you to the list.'; return; }
      var tokenEl = form.querySelector('[name="cf-turnstile-response"]');
      var body = { email: email, colour: colour, ref: refCode, token: tokenEl ? tokenEl.value : '' };
      form.classList.add('busy');
      status.textContent = '';
      fetch(api + '/waitlist', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
        .then(function (r) { return r.json().then(function (j) { return { ok: r.ok, status: r.status, body: j }; }); })
        .then(function (res) {
          form.classList.remove('busy');
          if (res.ok || res.status === 409) {
            var me = res.body; me.colour = me.colour || colour;
            store.set(me); showDone(me);
            if (res.status === 409) { var note = done.querySelector('.wl-done-kicker'); note.textContent = "You're already in."; }
            try { if (window.turnstile && tokenEl) window.turnstile.reset(); } catch (err) { /* ignore */ }
          } else {
            status.textContent = (res.body && res.body.error) || 'Something went wrong. Please try again.';
            try { if (window.turnstile) window.turnstile.reset(); } catch (err) { /* ignore */ }
          }
        })
        .catch(function () { form.classList.remove('busy'); status.textContent = 'Couldn\'t reach the sign-up server. Check your connection and try again.'; });
    });
  }

  // ------------------------------------------------------------ copy buttons (email addresses, request template)
  $$('[data-copy]').forEach(function (b) {
    b.addEventListener('click', function () {
      var target = doc.getElementById(b.getAttribute('data-copy'));
      if (!target) return;
      var text = target.textContent.trim();
      var status = b.parentNode.querySelector('.copied');
      var done = function (ok) {
        if (!status) return;
        status.textContent = ok ? 'Copied' : 'Select the text and copy it';
        setTimeout(function () { status.textContent = ''; }, 2500);
      };
      var select = function () {
        var sel = window.getSelection(); var range2 = doc.createRange();
        range2.selectNodeContents(target); sel.removeAllRanges(); sel.addRange(range2);
      };
      try {
        navigator.clipboard.writeText(text).then(function () { done(true); }, function () { select(); done(false); });
      } catch (e) { select(); done(false); }
    });
  });
})();

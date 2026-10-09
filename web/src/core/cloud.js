// Account save for the hosted build: the viewer's private `data/users/<id>/save` document.
// Local storage stays the instant source; the cloud copy makes the Evochi survive cleared
// browser data and follow a signed-in player to another device. Everything degrades to
// local-only when the platform does not offer the store (signed out, view-only, offline).
import { serialize, migrate } from '../game/state.js';

export class CloudSave {
  constructor(store, onRestore, onForeign) {
    this.store = store;
    this.onRestore = onRestore;
    this.onForeign = onForeign || (() => {});
    this.status = 'checking'; // checking | on | off | error
    this.ref = null;
    this.inflight = false;
    this.dirty = false;
    this.timer = null;
    this.lastWritten = null;
  }

  async init() {
    const c = typeof window !== 'undefined' ? window.claude : null;
    if (!c || typeof c.use !== 'function') {
      this.status = 'off';
      return;
    }
    try {
      const [db, user] = await Promise.all([c.use('db'), c.use('user')]);
      const id = user ? await user.id() : null;
      if (!db || !id) {
        this.status = 'off';
        this.store.emit();
        return;
      }
      this.ref = db.doc('data/users/' + id + '/save');
      this.uid = id;
      const snap = await this.ref.get();
      let local = this.store.state;
      // Q15: a local save that belongs to a different signed-in account is never shown or uploaded
      if (local.cloudOwner && local.cloudOwner !== id) {
        this.onForeign();
        local = this.store.state;
      }
      if (snap.exists) {
        const body = snap.data();
        let remote = null;
        try {
          remote = migrate(JSON.parse(body.state));
        } catch {}
        const localAt = local.savedAtMs || 0;
        if (remote && (body.savedAt || 0) > localAt && (remote.player || !local.player)) {
          this.status = 'on';
          remote.cloudOwner = id;
          this.onRestore(remote);
          return;
        }
      }
      this.status = 'on';
      if (local.player) {
        // first link of a local (guest) save to this account
        this.store.state.cloudOwner = id;
        this.queue(0);
      }
      this.store.emit();
    } catch (e) {
      this.status = 'off';
    }
  }

  /** Debounced, single-flight write; only when the serialized save changed. */
  queue(delay = 2500) {
    if (!this.ref || this.status !== 'on') return;
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.flush(), delay);
  }

  async flush() {
    if (!this.ref || this.status !== 'on') return;
    if (this.inflight) {
      this.dirty = true;
      return;
    }
    const s = this.store.state;
    if (!s.player) return;
    if (s.cloudOwner && s.cloudOwner !== this.uid) return;
    if (!s.cloudOwner) s.cloudOwner = this.uid;
    const text = serialize(s);
    const core = text.replace(/"savedAt(Ms)?":\d+/g, "");
    if (core === this.lastCore) return;
    this.inflight = true;
    try {
      await this.ref.set({ v: 1, savedAt: s.savedAtMs || Date.now(), state: text });
      this.lastCore = core;
    } catch (e) {
      const code = e && e.code;
      if (code === 'invalid_argument' || code === 'quota_exceeded' || code === 'revoked' || code === 'not_granted') {
        this.status = 'off';
        this.store.emit();
      } else if (code === 'unavailable') {
        this.dirty = true;
      }
    } finally {
      this.inflight = false;
      if (this.dirty) {
        this.dirty = false;
        this.queue(4000);
      }
    }
  }
}

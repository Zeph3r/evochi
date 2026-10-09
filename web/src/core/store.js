// State container: engine state + clock + persistence + event fan-out.
import * as G from '../game/state.js';
import { deviceZone } from '../game/time.js';

const KEY = 'evochi.save.v1';

export class Store {
  constructor() {
    this.listeners = new Set();
    this.eventListeners = new Set();
    this.storageOk = true;
    this.state = this.load() || G.newState(Date.now(), deviceZone());
    this.saveTimer = null;
  }

  now() {
    return Date.now() + (this.state.debug?.clockOffset || 0);
  }

  derived() {
    const n = this.now();
    if (!this._d || this._dState !== this.state || Math.abs(this._dNow - n) > 15000) {
      this._d = G.derive(this.state, n);
      this._dState = this.state;
      this._dNow = n;
    }
    return this._d;
  }

  load() {
    try {
      const raw = localStorage.getItem(KEY);
      if (!raw) return null;
      return G.migrate(JSON.parse(raw));
    } catch {
      this.storageOk = false;
      return null;
    }
  }

  persist() {
    this.state.savedAtMs = Date.now();
    if (this.cloud) this.cloud.queue();
    clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => {
      try {
        localStorage.setItem(KEY, G.serialize(this.state));
        this.storageOk = true;
      } catch {
        this.storageOk = false;
      }
    }, 120);
  }

  wipe({ keepCloud = true } = {}) {
    try {
      localStorage.removeItem(KEY);
    } catch {}
    this.state = G.newState(Date.now(), deviceZone());
    this.emit();
  }

  replace(state) {
    this.state = state;
    this.persist();
    this.emit();
  }

  /** Run an engine action; on success commit state and broadcast events. */
  run(fn, ...args) {
    const res = fn(this.state, ...args);
    if (!res.error) {
      if (res.state !== this.state) {
        this.state = res.state;
        this.persist();
      }
      for (const l of this.eventListeners) l(res.events || []);
      this.emit();
    }
    return res;
  }

  subscribe(fn) {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }
  onEvents(fn) {
    this.eventListeners.add(fn);
  }
  emit() {
    this._d = null;
    for (const l of this.listeners) l(this.state);
  }

  track(name, props = {}) {
    // privacy-conscious local analytics; only with consent, never raw health telemetry
    if (!this.state.player?.settings?.analytics) return;
    const s = this.state;
    s.analytics = (s.analytics || []).slice(-199);
    s.analytics.push({ name, t: this.now(), ...props });
    this.persist();
  }
}

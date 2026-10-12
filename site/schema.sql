-- Evochi beta waitlist (Cloudflare D1). Apply with:
--   npx wrangler d1 execute evochi-waitlist --remote --file=schema.sql
CREATE TABLE IF NOT EXISTS signups (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  email      TEXT    NOT NULL UNIQUE,
  colour     TEXT    NOT NULL DEFAULT 'ocean',
  code       TEXT    NOT NULL UNIQUE,      -- their referral code
  ref_code   TEXT,                         -- who referred them
  referrals  INTEGER NOT NULL DEFAULT 0,   -- friends who joined with their link (+1 if they were referred)
  founder    INTEGER NOT NULL DEFAULT 0,   -- 1 for the first FOUNDER_SPOTS sign-ups
  created_at INTEGER NOT NULL,             -- ms since epoch
  ip_hash    TEXT                          -- salted hash, for the per-connection rate limit only
);
CREATE INDEX IF NOT EXISTS idx_signups_rank ON signups (referrals DESC, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_signups_ip ON signups (ip_hash, created_at);

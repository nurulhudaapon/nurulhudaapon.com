-- Published subscription links (/calendar/<token>.ics). Only a SHA-256 of each
-- token is kept; detail is 'full' or 'busy'.
ALTER TABLE calendars ADD COLUMN in_feed INTEGER NOT NULL DEFAULT 1;

CREATE TABLE IF NOT EXISTS calendar_feeds (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  label TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  detail TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (CAST(unixepoch() AS TEXT)),
  last_used_at TEXT
);

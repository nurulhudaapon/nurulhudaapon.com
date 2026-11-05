-- Calendars for /admin/calendar: kind 'icloud' (discovered over CalDAV) or 'ics' (feed link).
-- blocks_booking: events here also count as busy time on /schedule.
CREATE TABLE IF NOT EXISTS calendars (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  name TEXT NOT NULL,
  url TEXT NOT NULL UNIQUE,
  color TEXT NOT NULL DEFAULT '',
  visible INTEGER NOT NULL DEFAULT 1,
  blocks_booking INTEGER NOT NULL DEFAULT 1,
  synced_at TEXT
);

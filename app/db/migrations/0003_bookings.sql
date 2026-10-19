CREATE TABLE IF NOT EXISTS bookings (
  id TEXT PRIMARY KEY,
  starts_at INTEGER NOT NULL,
  ends_at INTEGER NOT NULL,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (CAST(unixepoch() AS TEXT))
);

CREATE TABLE IF NOT EXISTS meet_joins (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  booking_id TEXT NOT NULL,
  user_agent TEXT,
  joined_at TEXT NOT NULL DEFAULT (CAST(unixepoch() AS TEXT))
);

CREATE INDEX IF NOT EXISTS meet_joins_booking ON meet_joins (booking_id);

CREATE UNIQUE INDEX IF NOT EXISTS bookings_slot ON bookings (starts_at);

ALTER TABLE bookings ADD COLUMN meet_url TEXT;
ALTER TABLE bookings ADD COLUMN cancelled_at TEXT;

-- Cancelled bookings keep their row, so only active bookings hold a slot.
DROP INDEX IF EXISTS bookings_slot;
CREATE UNIQUE INDEX IF NOT EXISTS bookings_slot_active ON bookings (starts_at) WHERE cancelled_at IS NULL;

CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  val TEXT NOT NULL
);

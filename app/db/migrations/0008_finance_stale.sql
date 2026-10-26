-- Mark accounts as stale to keep them listed while excluding them from portfolio totals.
ALTER TABLE accounts ADD COLUMN stale INTEGER NOT NULL DEFAULT 0;

INSERT OR IGNORE INTO account_types (id, label, sort_order) VALUES
  ('savings', 'Savings', 5);

UPDATE account_types SET sort_order = 6 WHERE id = 'cash';
UPDATE account_types SET sort_order = 7 WHERE id = 'other';

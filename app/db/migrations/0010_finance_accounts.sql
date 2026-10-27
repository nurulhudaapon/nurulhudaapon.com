-- Grouped accounts are summed into one row on the portfolio.
ALTER TABLE accounts ADD COLUMN group_name TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS accounts_group ON accounts (group_name);

-- Times are unix seconds (UTC) in *_at INTEGER columns.
ALTER TABLE accounts ADD COLUMN opened_at INTEGER;

-- Liability balances are amounts owed and count against net worth.
ALTER TABLE account_types ADD COLUMN liability INTEGER NOT NULL DEFAULT 0;

INSERT OR IGNORE INTO account_types (id, label, sort_order, liability) VALUES
  ('loan', 'Loan', 8, 1),
  ('credit_card', 'Credit card', 9, 1);

-- A balance holds from recorded_at (UTC midnight) until the next row.
CREATE TABLE IF NOT EXISTS balance_history (
  account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  recorded_at INTEGER NOT NULL,
  balance REAL NOT NULL,
  PRIMARY KEY (account_id, recorded_at)
);

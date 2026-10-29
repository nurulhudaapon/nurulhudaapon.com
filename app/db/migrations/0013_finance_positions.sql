-- Position detail from IBKR Flex. cost_price is in the holding's currency,
-- *_base columns in the account's base currency.
ALTER TABLE holdings ADD COLUMN cost_price REAL;
ALTER TABLE holdings ADD COLUMN cost_basis_base REAL;
ALTER TABLE holdings ADD COLUMN unrealized_pnl_base REAL;
ALTER TABLE holdings ADD COLUMN exchange TEXT NOT NULL DEFAULT '';

-- Per-currency cash from the Flex Cash Report. Cash not yet settled is
-- amount - settled: it counts toward the account's cash but can't be withdrawn.
CREATE TABLE IF NOT EXISTS cash_balances (
  account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  currency TEXT NOT NULL,
  amount REAL NOT NULL,
  settled REAL NOT NULL,
  amount_base REAL NOT NULL,
  synced_at TEXT,
  PRIMARY KEY (account_id, currency)
);

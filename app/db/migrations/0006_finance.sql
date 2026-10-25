CREATE TABLE IF NOT EXISTS accounts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  broker TEXT NOT NULL DEFAULT 'manual',
  external_id TEXT NOT NULL,
  name TEXT NOT NULL,
  currency TEXT NOT NULL DEFAULT 'USD',
  cash REAL NOT NULL DEFAULT 0,
  net_liquidation REAL NOT NULL DEFAULT 0,
  synced_at TEXT,
  institution TEXT NOT NULL DEFAULT '',
  account_type TEXT NOT NULL DEFAULT 'brokerage',
  asset_class TEXT NOT NULL DEFAULT 'Equities',
  notes TEXT,
  UNIQUE (broker, external_id)
);

CREATE TABLE IF NOT EXISTS holdings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  symbol TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  asset_class TEXT NOT NULL DEFAULT 'STK',
  category TEXT NOT NULL DEFAULT 'Equities',
  currency TEXT NOT NULL DEFAULT 'USD',
  quantity REAL NOT NULL DEFAULT 0,
  market_price REAL NOT NULL DEFAULT 0,
  market_value REAL NOT NULL DEFAULT 0,
  market_value_base REAL NOT NULL DEFAULT 0,
  conid TEXT,
  synced_at TEXT
);

CREATE INDEX IF NOT EXISTS holdings_account ON holdings (account_id);
CREATE INDEX IF NOT EXISTS holdings_category ON holdings (category);

CREATE TABLE IF NOT EXISTS allocations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  target_pct REAL NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0,
  notes TEXT
);

CREATE TABLE IF NOT EXISTS fx_rates (
  currency TEXT PRIMARY KEY,
  rate REAL NOT NULL,
  as_of TEXT NOT NULL DEFAULT '',
  fetched_at INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS account_types (
  id TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS asset_classes (
  name TEXT PRIMARY KEY,
  sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS asset_class_aliases (
  alias TEXT PRIMARY KEY COLLATE NOCASE,
  asset_class TEXT NOT NULL REFERENCES asset_classes(name)
);

CREATE TABLE IF NOT EXISTS zakat_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  year INTEGER NOT NULL UNIQUE,
  amount REAL NOT NULL,
  currency TEXT NOT NULL DEFAULT 'USD',
  paid_on TEXT,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (CAST(strftime('%s', 'now') AS TEXT))
);

INSERT OR IGNORE INTO account_types (id, label, sort_order) VALUES
  ('brokerage', 'Brokerage', 1),
  ('deposit', 'Deposit', 2),
  ('physical', 'Physical', 3),
  ('alternative', 'Alternative', 4),
  ('cash', 'Cash', 5),
  ('other', 'Other', 6);

INSERT OR IGNORE INTO asset_classes (name, sort_order) VALUES
  ('Equities', 1),
  ('Fixed Income', 2),
  ('Cash', 3),
  ('Alternatives', 4),
  ('Commodities', 5);

INSERT OR IGNORE INTO asset_class_aliases (alias, asset_class) VALUES
  ('Equities', 'Equities'),
  ('Equity', 'Equities'),
  ('STK', 'Equities'),
  ('OPT', 'Equities'),
  ('FUND', 'Equities'),
  ('Fixed Income', 'Fixed Income'),
  ('Bonds', 'Fixed Income'),
  ('BOND', 'Fixed Income'),
  ('BILL', 'Fixed Income'),
  ('Cash', 'Cash'),
  ('CASH', 'Cash'),
  ('Commodities', 'Commodities'),
  ('CMDTY', 'Commodities'),
  ('Alternatives', 'Alternatives'),
  ('Other', 'Alternatives');

INSERT OR IGNORE INTO allocations (name, target_pct, sort_order) VALUES
  ('Equities', 55, 1),
  ('Fixed Income', 20, 2),
  ('Cash', 10, 3),
  ('Alternatives', 10, 4),
  ('Commodities', 5, 5);

INSERT OR IGNORE INTO fx_rates (currency, rate, as_of, fetched_at) VALUES
  ('USD', 1, 'seed', 0),
  ('BDT', 122, 'seed', 0),
  ('EUR', 0.92, 'seed', 0),
  ('GBP', 0.79, 'seed', 0),
  ('CAD', 1.36, 'seed', 0),
  ('AUD', 1.52, 'seed', 0),
  ('CHF', 0.88, 'seed', 0),
  ('JPY', 150, 'seed', 0),
  ('INR', 83, 'seed', 0),
  ('SGD', 1.34, 'seed', 0),
  ('HKD', 7.8, 'seed', 0),
  ('CNY', 7.2, 'seed', 0),
  ('XAU', 0.0077, 'seed', 0);

DELETE FROM settings WHERE key IN ('finance_fx_usd_json', 'finance_fx_fetched_at', 'finance_usd_bdt_rate');

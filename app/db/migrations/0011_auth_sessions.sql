-- Sign-in sessions. Only a SHA-256 of the cookie token is stored.
CREATE TABLE IF NOT EXISTS auth_sessions (
  token_hash TEXT PRIMARY KEY,
  provider TEXT NOT NULL,
  account_id TEXT NOT NULL,
  login TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);

-- Passkeys, each owned by the provider account that registered it. Public keys
-- only (base64url), so a leaked table can't sign anyone in.
CREATE TABLE IF NOT EXISTS auth_passkeys (
  credential_id TEXT PRIMARY KEY,
  provider TEXT NOT NULL,
  account_id TEXT NOT NULL,
  login TEXT NOT NULL,
  name TEXT NOT NULL,
  algorithm INTEGER NOT NULL,
  public_key TEXT NOT NULL,
  sign_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  last_used_at INTEGER
);

CREATE INDEX IF NOT EXISTS auth_passkeys_account ON auth_passkeys (provider, account_id);

-- MCP OAuth: clients (DCR), auth codes, access tokens.
CREATE TABLE IF NOT EXISTS mcp_oauth_clients (
  client_id TEXT PRIMARY KEY,
  client_name TEXT,
  redirect_uris TEXT NOT NULL,
  token_endpoint_auth_method TEXT NOT NULL DEFAULT 'none',
  grant_types TEXT,
  response_types TEXT,
  scope TEXT,
  issued_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS mcp_oauth_codes (
  code TEXT PRIMARY KEY,
  client_id TEXT NOT NULL,
  redirect_uri TEXT NOT NULL,
  code_challenge TEXT,
  code_challenge_method TEXT,
  scope TEXT,
  resource TEXT,
  state TEXT,
  approved_by TEXT,
  expires_at INTEGER NOT NULL,
  used_at INTEGER
);

CREATE TABLE IF NOT EXISTS mcp_access_tokens (
  token TEXT PRIMARY KEY,
  client_id TEXT NOT NULL,
  scope TEXT,
  resource TEXT,
  approved_by TEXT,
  expires_at INTEGER NOT NULL,
  revoked INTEGER NOT NULL DEFAULT 0
);

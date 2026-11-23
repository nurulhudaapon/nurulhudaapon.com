-- MCP codes and tokens are now stored as SHA-256 hashes; drop the raw ones.
-- Clients re-authorize through /admin/mcp.
DELETE FROM mcp_oauth_codes;
DELETE FROM mcp_access_tokens;

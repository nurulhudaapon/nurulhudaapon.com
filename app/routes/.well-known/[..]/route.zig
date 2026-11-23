// OAuth metadata at the standard root URLs (RFC 8414 / 9728), e.g.
// `/.well-known/oauth-authorization-server/mcp`; served by the same endpoint as /mcp.
const mcp = @import("../../mcp/[..]/route.zig");
pub const Route = mcp.Route;
pub const options = mcp.options;

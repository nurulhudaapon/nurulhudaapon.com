const zx = @import("zx");
const store = @import("../../../mcp/store.zig");
const server = @import("../../../mcp/server.zig");

// The MCP server and its OAuth (metadata, registration, authorize, token) all
// live under /mcp. Clearing the MCP secret in settings turns all of it off.
pub fn Route(ctx: zx.RouteContext) !void {
    if (!store.enabled(ctx.arena)) return ctx.response.setStatus(.not_found);
    return server.serve(ctx);
}

pub const options: zx.RouteOptions = .{ .rendering = .request };

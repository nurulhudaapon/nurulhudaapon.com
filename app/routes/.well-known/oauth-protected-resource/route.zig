const zx = @import("zx");
const mcp = @import("mcp");
const store = @import("../../mcp/store.zig");

pub fn GET(ctx: zx.RouteContext) !void {
    const resource = try store.resourceUrl(ctx.arena, ctx.request);
    const issuer = try store.authorizationServerIssuer(ctx.arena, ctx.request);
    const body = try mcp.oauth.writeProtectedResource(ctx.arena, .{
        .resource = resource,
        .authorization_servers = &.{issuer},
        .scopes_supported = &.{"mcp"},
        .resource_documentation = "https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization",
    });
    ctx.response.headers.append("Cache-Control", "no-store");
    ctx.response.setContentType(.@"application/json");
    ctx.response.text(body);
}

pub const options: zx.RouteOptions = .{ .rendering = .request };

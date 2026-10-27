const std = @import("std");
const zx = @import("zx");
const mcp = @import("mcp");
const store = @import("../store.zig");
const site = @import("../../../site.zig");

pub fn write(ctx: zx.RouteContext) !void {
    const base = site.origin(ctx.request);
    const issuer = try store.authorizationServerIssuer(ctx.arena, ctx.request);
    const body = try mcp.oauth.writeAuthorizationServer(ctx.arena, .{
        .issuer = issuer,
        .authorization_endpoint = try ctx.arena.print("{s}/mcp/oauth/authorize", .{base}),
        .token_endpoint = try ctx.arena.print("{s}/mcp/oauth/token", .{base}),
        .registration_endpoint = try ctx.arena.print("{s}/mcp/oauth/register", .{base}),
        .scopes_supported = &.{"mcp"},
    });
    ctx.response.headers.add("Cache-Control", "no-store");
    ctx.response.setContentType(.@"application/json");
    ctx.response.text(body);
}

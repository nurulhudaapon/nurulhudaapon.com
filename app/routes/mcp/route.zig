const std = @import("std");
const zx = @import("zx");
const mcp = @import("mcp");
const store = @import("store.zig");
const mcp_server = @import("server.zig");

pub fn GET(ctx: zx.RouteContext) !void {
    return unauthorized(ctx);
}

pub fn POST(ctx: zx.RouteContext) !void {
    const bearer = mcp.http.extractBearer(ctx.request.headers.get("authorization")) orelse {
        return unauthorized(ctx);
    };
    if (!store.authorizeBearer(ctx.arena, bearer)) return unauthorized(ctx);

    const body = ctx.request.text() orelse "";
    if (body.len == 0) {
        ctx.response.setStatus(.bad_request);
        ctx.response.setContentType(.@"application/json");
        const err_body = try mcp.types.stringify(ctx.arena, .{
            .jsonrpc = "2.0",
            .id = null,
            .@"error" = .{ .code = @as(i64, -32600), .message = "Empty body" },
        });
        return ctx.response.text(err_body);
    }

    const reply = try mcp_server.handle(ctx.arena, body);
    ctx.response.headers.add("Cache-Control", "no-store");
    if (reply.len == 0) {
        ctx.response.setStatus(.@"no_content");
        return;
    }
    ctx.response.setContentType(.@"application/json");
    ctx.response.text(reply);
}

fn unauthorized(ctx: zx.RouteContext) !void {
    const meta = try store.protectedResourceMetadataUrl(ctx.arena, ctx.request);
    const www = try mcp.http.wwwAuthenticate(ctx.arena, .{
        .resource_metadata_url = meta,
        .scope = "mcp",
    });
    ctx.response.setStatus(.unauthorized);
    ctx.response.headers.add("WWW-Authenticate", www);
    ctx.response.headers.add("Cache-Control", "no-store");
    ctx.response.setContentType(.@"application/json");
    ctx.response.text(try mcp.oauth.writeOAuthError(ctx.arena, "invalid_token", "Authentication required"));
}

pub const options: zx.RouteOptions = .{ .rendering = .request };

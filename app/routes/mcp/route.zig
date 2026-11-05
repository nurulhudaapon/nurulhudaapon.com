const zx = @import("zx");
const mcp = @import("mcp");
const store = @import("../../mcp/store.zig");
const server = @import("../../mcp/server.zig");

pub const GET = unauthorized;

pub fn POST(ctx: zx.RouteContext) !void {
    const bearer = mcp.http.extractBearer(ctx.request.headers.get("authorization")) orelse return unauthorized(ctx);
    if (!store.authorizeBearer(ctx.arena, ctx.io, bearer)) return unauthorized(ctx);

    const body = ctx.request.text() orelse "";
    if (body.len == 0) {
        ctx.response.setStatus(.bad_request);
        ctx.response.setContentType(.@"application/json");
        return ctx.response.text(try mcp.types.stringify(ctx.arena, .{
            .jsonrpc = "2.0",
            .id = null,
            .@"error" = .{ .code = @as(i64, -32600), .message = "Empty body" },
        }));
    }

    const reply = try server.handle(ctx.arena, ctx.io, body);
    ctx.response.headers.append("Cache-Control", "no-store");
    if (reply.len == 0) return ctx.response.setStatus(.no_content);
    ctx.response.setContentType(.@"application/json");
    ctx.response.text(reply);
}

fn unauthorized(ctx: zx.RouteContext) !void {
    const www = try mcp.http.wwwAuthenticate(ctx.arena, .{
        .resource_metadata_url = try store.metadataUrl(ctx.arena, ctx.request),
        .scope = "mcp",
    });
    ctx.response.setStatus(.unauthorized);
    ctx.response.headers.append("WWW-Authenticate", www);
    ctx.response.headers.append("Cache-Control", "no-store");
    ctx.response.setContentType(.@"application/json");
    ctx.response.text(try mcp.oauth.writeOAuthError(ctx.arena, "invalid_token", "Authentication required"));
}

pub const options: zx.RouteOptions = .{ .rendering = .request };

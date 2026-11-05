const std = @import("std");
const zx = @import("zx");
const mcp = @import("mcp");
const store = @import("../store.zig");

pub fn handle(ctx: zx.RouteContext) !void {
    const body = ctx.request.text() orelse "";
    if (body.len == 0) return fail(ctx, .bad_request, "invalid_client_metadata", "JSON body required");

    const parsed = std.json.parseFromSliceLeaky(std.json.Value, ctx.arena, body, .{
        .allocate = .alloc_always,
    }) catch {
        return fail(ctx, .bad_request, "invalid_client_metadata", "Invalid JSON");
    };
    if (parsed != .object) return fail(ctx, .bad_request, "invalid_client_metadata", "JSON object required");
    const obj = parsed.object;

    const redirect_uris = try parseRedirectUris(ctx.arena, obj.get("redirect_uris")) orelse {
        return fail(ctx, .bad_request, "invalid_redirect_uri", "redirect_uris required");
    };
    if (redirect_uris.len == 0) {
        return fail(ctx, .bad_request, "invalid_redirect_uri", "redirect_uris must be non-empty");
    }

    const client_name = string(obj, "client_name");
    const auth_method = string(obj, "token_endpoint_auth_method") orelse "none";
    const scope = string(obj, "scope");

    const client = store.registerClient(ctx.arena, ctx.io, client_name, redirect_uris, auth_method, scope) catch |err| switch (err) {
        error.InvalidRedirectUris => return fail(ctx, .bad_request, "invalid_redirect_uri", "Only https or localhost http redirect URIs are allowed"),
        else => return fail(ctx, .internal_server_error, "server_error", "Failed to register client"),
    };

    const response = try mcp.oauth.writeClientRegistration(ctx.arena, .{
        .client_id = client.client_id,
        .client_id_issued_at = client.issued_at,
        .client_name = client.client_name,
        .redirect_uris = redirect_uris,
        .token_endpoint_auth_method = client.token_endpoint_auth_method,
        .scope = client.scope,
    });
    ctx.response.setStatus(.created);
    ctx.response.headers.append("Cache-Control", "no-store");
    ctx.response.setContentType(.@"application/json");
    ctx.response.text(response);
}

fn string(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = obj.get(key) orelse return null;
    return if (v == .string) v.string else null;
}

fn parseRedirectUris(arena: std.mem.Allocator, value: ?std.json.Value) !?[]const []const u8 {
    const v = value orelse return null;
    if (v != .array) return null;
    const uris = try arena.alloc([]const u8, v.array.items.len);
    for (v.array.items, uris) |item, *uri| {
        if (item != .string) return null;
        uri.* = item.string;
    }
    return uris;
}

fn fail(ctx: zx.RouteContext, status: std.http.Status, code: []const u8, desc: []const u8) !void {
    const body = try mcp.oauth.writeOAuthError(ctx.arena, code, desc);
    ctx.response.setStatus(status);
    ctx.response.headers.append("Cache-Control", "no-store");
    ctx.response.setContentType(.@"application/json");
    ctx.response.text(body);
}

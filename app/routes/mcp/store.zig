const std = @import("std");
const zx = @import("zx");
const credentials = @import("../../db/credentials.zig");
const booking = @import("../../pages/schedule/booking.zig");
const site = @import("../../site.zig");

pub const code_ttl_secs: i64 = 10 * 60;

pub fn tokenTtlSecs(arena: std.mem.Allocator) i64 {
    return @as(i64, credentials.mcpTokenTtlDays(arena)) * 24 * 60 * 60;
}

pub const AuthCode = struct {
    code: []const u8,
    client_id: []const u8,
    redirect_uri: []const u8,
    code_challenge: ?[]const u8 = null,
    code_challenge_method: ?[]const u8 = null,
    scope: ?[]const u8 = null,
    resource: ?[]const u8 = null,
    state: ?[]const u8 = null,
    approved_by: ?[]const u8 = null,
    expires_at: i64,
};

pub fn randomToken(arena: std.mem.Allocator) ![]const u8 {
    var bytes: [32]u8 = undefined;
    std.Io.random(zx.io(), &bytes);
    return try arena.print("{x}", .{bytes});
}

pub fn mcpSecret(arena: std.mem.Allocator) ?[]const u8 {
    return credentials.get(arena, "mcp_token");
}

// OAuth tokens only (after /admin/mcp consent). MCP_TOKEN is enablement, not a Bearer.
pub fn authorizeBearer(arena: std.mem.Allocator, bearer: []const u8) bool {
    if (mcpSecret(arena) == null) return false;
    const now = booking.nowUnix();
    const row = zx.db.row(arena, struct { ok: i64 },
        \\SELECT 1 AS ok FROM mcp_access_tokens
        \\WHERE token = ?1 AND revoked = 0 AND expires_at > ?2
        \\LIMIT 1
    , .{ bearer, now }) catch return false;
    return row != null;
}

pub fn insertCode(c: AuthCode) !void {
    _ = try zx.db.run(
        \\INSERT INTO mcp_oauth_codes (
        \\  code, client_id, redirect_uri, code_challenge, code_challenge_method,
        \\  scope, resource, state, approved_by, expires_at
        \\) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
    , .{
        c.code,
        c.client_id,
        c.redirect_uri,
        c.code_challenge,
        c.code_challenge_method,
        c.scope,
        c.resource,
        c.state,
        c.approved_by,
        c.expires_at,
    });
}

pub fn consumeCode(arena: std.mem.Allocator, code: []const u8) !?AuthCode {
    const now = booking.nowUnix();
    const row = try zx.db.row(arena, struct {
        code: []const u8,
        client_id: []const u8,
        redirect_uri: []const u8,
        code_challenge: ?[]const u8,
        code_challenge_method: ?[]const u8,
        scope: ?[]const u8,
        resource: ?[]const u8,
        state: ?[]const u8,
        approved_by: ?[]const u8,
        expires_at: i64,
        used_at: ?i64,
    },
        \\SELECT code, client_id, redirect_uri, code_challenge, code_challenge_method,
        \\       scope, resource, state, approved_by, expires_at, used_at
        \\FROM mcp_oauth_codes WHERE code = ?1 LIMIT 1
    , .{code});
    const r = row orelse return null;
    if (r.used_at != null) return null;
    if (r.expires_at <= now) return null;
    _ = try zx.db.run("UPDATE mcp_oauth_codes SET used_at = ?1 WHERE code = ?2", .{ now, code });
    return .{
        .code = r.code,
        .client_id = r.client_id,
        .redirect_uri = r.redirect_uri,
        .code_challenge = r.code_challenge,
        .code_challenge_method = r.code_challenge_method,
        .scope = r.scope,
        .resource = r.resource,
        .state = r.state,
        .approved_by = r.approved_by,
        .expires_at = r.expires_at,
    };
}

pub fn issueAccessToken(
    arena: std.mem.Allocator,
    client_id: []const u8,
    scope: ?[]const u8,
    resource: ?[]const u8,
    approved_by: ?[]const u8,
) !struct { token: []const u8, expires_in: u32 } {
    const token = try randomToken(arena);
    const ttl = tokenTtlSecs(arena);
    const expires_at = booking.nowUnix() + ttl;
    _ = try zx.db.run(
        \\INSERT INTO mcp_access_tokens (token, client_id, scope, resource, approved_by, expires_at)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6)
    , .{ token, client_id, scope, resource, approved_by, expires_at });
    return .{ .token = token, .expires_in = @intCast(ttl) };
}

pub fn resourceUrl(arena: std.mem.Allocator, request: zx.server.Request) ![]const u8 {
    const base = site.origin(request);
    return try arena.print("{s}/mcp", .{base});
}

pub fn authorizationServerIssuer(arena: std.mem.Allocator, request: zx.server.Request) ![]const u8 {
    _ = arena;
    return site.origin(request);
}

pub fn protectedResourceMetadataUrl(arena: std.mem.Allocator, request: zx.server.Request) ![]const u8 {
    const base = site.origin(request);
    return try arena.print("{s}/.well-known/oauth-protected-resource/mcp", .{base});
}

pub const RegisteredClient = struct {
    client_id: []const u8,
    client_name: ?[]const u8 = null,
    redirect_uris_json: []const u8,
    token_endpoint_auth_method: []const u8 = "none",
    scope: ?[]const u8 = null,
    issued_at: i64,
};

pub fn registerClient(
    arena: std.mem.Allocator,
    client_name: ?[]const u8,
    redirect_uris: []const []const u8,
    auth_method: []const u8,
    scope: ?[]const u8,
) !RegisteredClient {
    if (redirect_uris.len == 0) return error.InvalidRedirectUris;
    for (redirect_uris) |uri| {
        if (!isAllowedRedirect(uri)) return error.InvalidRedirectUris;
    }

    var uris_aw: std.Io.Writer.Allocating = .init(arena);
    try uris_aw.writer.writeAll("[");
    for (redirect_uris, 0..) |uri, i| {
        if (i > 0) try uris_aw.writer.writeAll(",");
        try std.json.Stringify.value(uri, .{}, &uris_aw.writer);
    }
    try uris_aw.writer.writeAll("]");
    const redirect_uris_json = uris_aw.written();

    const client_id = try randomToken(arena);
    const issued_at = booking.nowUnix();
    _ = try zx.db.run(
        \\INSERT INTO mcp_oauth_clients (
        \\  client_id, client_name, redirect_uris, token_endpoint_auth_method,
        \\  grant_types, response_types, scope, issued_at
        \\) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
    , .{
        client_id,
        client_name,
        redirect_uris_json,
        auth_method,
        "[\"authorization_code\",\"refresh_token\"]",
        "[\"code\"]",
        scope,
        issued_at,
    });
    return .{
        .client_id = client_id,
        .client_name = client_name,
        .redirect_uris_json = redirect_uris_json,
        .token_endpoint_auth_method = auth_method,
        .scope = scope,
        .issued_at = issued_at,
    };
}

pub fn getClient(arena: std.mem.Allocator, client_id: []const u8) !?RegisteredClient {
    const row = try zx.db.row(arena, struct {
        client_id: []const u8,
        client_name: ?[]const u8,
        redirect_uris: []const u8,
        token_endpoint_auth_method: []const u8,
        scope: ?[]const u8,
        issued_at: i64,
    },
        \\SELECT client_id, client_name, redirect_uris, token_endpoint_auth_method, scope, issued_at
        \\FROM mcp_oauth_clients WHERE client_id = ?1 LIMIT 1
    , .{client_id});
    const r = row orelse return null;
    return .{
        .client_id = r.client_id,
        .client_name = r.client_name,
        .redirect_uris_json = r.redirect_uris,
        .token_endpoint_auth_method = r.token_endpoint_auth_method,
        .scope = r.scope,
        .issued_at = r.issued_at,
    };
}

pub fn clientAllowsRedirect(arena: std.mem.Allocator, client_id: []const u8, redirect_uri: []const u8) !bool {
    const client = (try getClient(arena, client_id)) orelse return false;
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena, client.redirect_uris_json, .{
        .allocate = .alloc_always,
    });
    if (parsed != .array) return false;
    for (parsed.array.items) |item| {
        if (item == .string and std.mem.eql(u8, item.string, redirect_uri)) return true;
    }
    return false;
}

fn isAllowedRedirect(uri: []const u8) bool {
    if (std.mem.startsWith(u8, uri, "https://")) return true;
    // MCP Inspector / local OAuth callbacks.
    if (std.mem.startsWith(u8, uri, "http://localhost") or std.mem.startsWith(u8, uri, "http://127.0.0.1")) return true;
    if (std.mem.startsWith(u8, uri, "http://[::1]")) return true;
    return false;
}

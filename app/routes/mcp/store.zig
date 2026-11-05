const std = @import("std");
const zx = @import("zx");
const credentials = @import("../../db/credentials.zig");
const site = @import("../../site.zig");

pub const code_ttl_s: i64 = 10 * 60;

pub const Code = struct {
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

pub const Client = struct {
    client_id: []const u8,
    client_name: ?[]const u8 = null,
    redirect_uris_json: []const u8,
    token_endpoint_auth_method: []const u8 = "none",
    scope: ?[]const u8 = null,
    issued_at: i64,
};

pub fn randomToken(arena: std.mem.Allocator, io: std.Io) ![]const u8 {
    var bytes: [32]u8 = undefined;
    io.random(&bytes);
    return try arena.print("{x}", .{bytes});
}

// MCP_TOKEN only enables MCP; it is never accepted as a bearer token itself.
pub fn secret(arena: std.mem.Allocator) ?[]const u8 {
    return credentials.get(arena, "mcp_token");
}

pub fn authorizeBearer(arena: std.mem.Allocator, io: std.Io, bearer: []const u8) bool {
    if (secret(arena) == null) return false;
    const row = zx.db.row(arena, struct { ok: i64 },
        \\SELECT 1 AS ok FROM mcp_access_tokens
        \\WHERE token = ?1 AND revoked = 0 AND expires_at > ?2
        \\LIMIT 1
    , .{ bearer, now(io) }) catch return false;
    return row != null;
}

pub fn insertCode(c: Code) !void {
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

pub fn consumeCode(arena: std.mem.Allocator, io: std.Io, code: []const u8) !?Code {
    const t = now(io);
    const c = try zx.db.row(arena, Code,
        \\SELECT code, client_id, redirect_uri, code_challenge, code_challenge_method,
        \\       scope, resource, state, approved_by, expires_at
        \\FROM mcp_oauth_codes WHERE code = ?1 AND used_at IS NULL LIMIT 1
    , .{code}) orelse return null;
    if (c.expires_at <= t) return null;
    _ = try zx.db.run("UPDATE mcp_oauth_codes SET used_at = ?1 WHERE code = ?2", .{ t, code });
    return c;
}

pub fn issueToken(
    arena: std.mem.Allocator,
    io: std.Io,
    client_id: []const u8,
    scope: ?[]const u8,
    resource: ?[]const u8,
    approved_by: ?[]const u8,
) !struct { token: []const u8, expires_in: u32 } {
    const token = try randomToken(arena, io);
    const ttl = @as(i64, credentials.mcpTokenTtlDays(arena)) * std.time.s_per_day;
    _ = try zx.db.run(
        \\INSERT INTO mcp_access_tokens (token, client_id, scope, resource, approved_by, expires_at)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6)
    , .{ token, client_id, scope, resource, approved_by, now(io) + ttl });
    return .{ .token = token, .expires_in = @intCast(ttl) };
}

pub fn resourceUrl(arena: std.mem.Allocator, request: zx.server.Request) ![]const u8 {
    return arena.print("{s}/mcp", .{site.origin(request)});
}

pub fn issuer(request: zx.server.Request) []const u8 {
    return site.origin(request);
}

pub fn metadataUrl(arena: std.mem.Allocator, request: zx.server.Request) ![]const u8 {
    return arena.print("{s}/.well-known/oauth-protected-resource/mcp", .{site.origin(request)});
}

pub fn registerClient(
    arena: std.mem.Allocator,
    io: std.Io,
    client_name: ?[]const u8,
    redirect_uris: []const []const u8,
    auth_method: []const u8,
    scope: ?[]const u8,
) !Client {
    if (redirect_uris.len == 0) return error.InvalidRedirectUris;
    for (redirect_uris) |uri| if (!isAllowedRedirect(uri)) return error.InvalidRedirectUris;

    const client: Client = .{
        .client_id = try randomToken(arena, io),
        .client_name = client_name,
        .redirect_uris_json = try std.json.Stringify.valueAlloc(arena, redirect_uris, .{}),
        .token_endpoint_auth_method = auth_method,
        .scope = scope,
        .issued_at = now(io),
    };
    _ = try zx.db.run(
        \\INSERT INTO mcp_oauth_clients (
        \\  client_id, client_name, redirect_uris, token_endpoint_auth_method,
        \\  grant_types, response_types, scope, issued_at
        \\) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
    , .{
        client.client_id,
        client.client_name,
        client.redirect_uris_json,
        client.token_endpoint_auth_method,
        "[\"authorization_code\",\"refresh_token\"]",
        "[\"code\"]",
        client.scope,
        client.issued_at,
    });
    return client;
}

pub fn getClient(arena: std.mem.Allocator, client_id: []const u8) !?Client {
    return zx.db.row(arena, Client,
        \\SELECT client_id, client_name, redirect_uris AS redirect_uris_json, token_endpoint_auth_method, scope, issued_at
        \\FROM mcp_oauth_clients WHERE client_id = ?1 LIMIT 1
    , .{client_id});
}

pub fn allowsRedirect(arena: std.mem.Allocator, client_id: []const u8, redirect_uri: []const u8) !bool {
    const client = (try getClient(arena, client_id)) orelse return false;
    const uris = try std.json.parseFromSliceLeaky(std.json.Value, arena, client.redirect_uris_json, .{ .allocate = .alloc_always });
    if (uris != .array) return false;
    for (uris.array.items) |uri| {
        if (uri == .string and std.mem.eql(u8, uri.string, redirect_uri)) return true;
    }
    return false;
}

fn isAllowedRedirect(uri: []const u8) bool {
    for ([_][]const u8{ "https://", "http://localhost", "http://127.0.0.1", "http://[::1]" }) |prefix| {
        if (std.mem.startsWith(u8, uri, prefix)) return true;
    }
    return false;
}

fn now(io: std.Io) i64 {
    return std.Io.Timestamp.now(io, .real).toSeconds();
}

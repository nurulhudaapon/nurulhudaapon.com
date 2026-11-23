// `zx.mcp.Endpoint` for this site: OAuth state in D1, consent at /admin/mcp.
const std = @import("std");
const zx = @import("zx");
const credentials = @import("../db/credentials.zig");
const site = @import("../site.zig");

const Endpoint = zx.mcp.Endpoint;

pub const consent_path = "/admin/mcp";

// MCP_TOKEN only enables MCP; it is never accepted as a bearer token itself.
pub fn enabled(arena: std.mem.Allocator) bool {
    return credentials.get(arena, "mcp_token") != null;
}

pub fn endpoint(ctx: anytype) Endpoint {
    return .{
        .io = ctx.io,
        .store = .{ .vtable = &vtable },
        .options = .{
            .origin = site.origin(ctx.request),
            .consent_path = consent_path,
            .token_max_age_s = @as(i64, credentials.mcpTokenTtlDays(ctx.arena)) * std.time.s_per_day,
            .documentation = "https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization",
        },
    };
}

const vtable: Endpoint.Store.VTable = .{
    .putClient = putClient,
    .getClient = getClient,
    .putCode = putCode,
    .takeCode = takeCode,
    .putToken = putToken,
    .getToken = getToken,
};

fn putClient(_: ?*anyopaque, c: Endpoint.Client) anyerror!void {
    const uris = try std.json.Stringify.valueAlloc(zx.allocator, c.redirect_uris, .{});
    defer zx.allocator.free(uris);
    _ = try zx.db.run(
        \\INSERT INTO mcp_oauth_clients (
        \\  client_id, client_name, redirect_uris, token_endpoint_auth_method,
        \\  grant_types, response_types, issued_at
        \\) VALUES (?1, ?2, ?3, 'none', '["authorization_code"]', '["code"]', ?4)
    , .{ c.id, c.name, uris, c.issued_at });
}

fn getClient(_: ?*anyopaque, arena: std.mem.Allocator, id: []const u8) anyerror!?Endpoint.Client {
    const row = try zx.db.row(arena, struct { client_id: []const u8, client_name: ?[]const u8, redirect_uris: []const u8, issued_at: i64 },
        \\SELECT client_id, client_name, redirect_uris, issued_at
        \\FROM mcp_oauth_clients WHERE client_id = ?1 LIMIT 1
    , .{id}) orelse return null;
    return .{
        .id = row.client_id,
        .name = row.client_name,
        .redirect_uris = try std.json.parseFromSliceLeaky([]const []const u8, arena, row.redirect_uris, .{ .allocate = .alloc_always }),
        .issued_at = row.issued_at,
    };
}

fn putCode(_: ?*anyopaque, hash: []const u8, g: Endpoint.Grant) anyerror!void {
    _ = try zx.db.run(
        \\INSERT INTO mcp_oauth_codes (
        \\  code, client_id, redirect_uri, code_challenge, code_challenge_method,
        \\  scope, resource, approved_by, expires_at
        \\) VALUES (?1, ?2, ?3, ?4, 'S256', ?5, ?6, ?7, ?8)
    , .{ hash, g.client_id, g.redirect_uri, g.code_challenge, g.scope, g.resource, g.approved_by, g.expires_at });
}

// The guarded UPDATE keeps a code single-use even when two exchanges race.
fn takeCode(_: ?*anyopaque, arena: std.mem.Allocator, hash: []const u8) anyerror!?Endpoint.Grant {
    const row = try zx.db.row(arena, struct {
        client_id: []const u8,
        redirect_uri: []const u8,
        code_challenge: ?[]const u8,
        scope: ?[]const u8,
        resource: ?[]const u8,
        approved_by: ?[]const u8,
        expires_at: i64,
    },
        \\SELECT client_id, redirect_uri, code_challenge, scope, resource, approved_by, expires_at
        \\FROM mcp_oauth_codes WHERE code = ?1 AND used_at IS NULL LIMIT 1
    , .{hash}) orelse return null;
    const used = try zx.db.run(
        \\UPDATE mcp_oauth_codes SET used_at = CAST(strftime('%s', 'now') AS INTEGER)
        \\WHERE code = ?1 AND used_at IS NULL
    , .{hash});
    if (used.changes == 0) return null;
    return .{
        .client_id = row.client_id,
        .redirect_uri = row.redirect_uri,
        .code_challenge = row.code_challenge orelse "",
        .scope = row.scope,
        .resource = row.resource,
        .approved_by = row.approved_by,
        .expires_at = row.expires_at,
    };
}

fn putToken(_: ?*anyopaque, hash: []const u8, g: Endpoint.Grant) anyerror!void {
    _ = try zx.db.run(
        \\INSERT INTO mcp_access_tokens (token, client_id, scope, resource, approved_by, expires_at)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6)
    , .{ hash, g.client_id, g.scope, g.resource, g.approved_by, g.expires_at });
}

fn getToken(_: ?*anyopaque, arena: std.mem.Allocator, hash: []const u8) anyerror!?Endpoint.Grant {
    const row = try zx.db.row(arena, struct {
        client_id: []const u8,
        scope: ?[]const u8,
        resource: ?[]const u8,
        approved_by: ?[]const u8,
        expires_at: i64,
    },
        \\SELECT client_id, scope, resource, approved_by, expires_at
        \\FROM mcp_access_tokens WHERE token = ?1 AND revoked = 0 LIMIT 1
    , .{hash}) orelse return null;
    return .{
        .client_id = row.client_id,
        .redirect_uri = "",
        .scope = row.scope,
        .resource = row.resource,
        .approved_by = row.approved_by,
        .expires_at = row.expires_at,
    };
}

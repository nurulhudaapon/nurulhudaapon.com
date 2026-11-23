// Provider credentials are the `oauth_<id>_client_id` and `oauth_<id>_client_secret`
// rows in `credentials`; only account ids listed in `oauth_<id>_allowed`
// (comma-separated) may sign in.

const home = "/admin";

pub fn of(ctx: anytype) !Auth {
    return .init(ctx, .{ .vtable = &store }, .{
        .origin = site.origin(ctx.request),
        .site_name = "nurulhudaapon.com",
        .home = home,
        .providers = &.{Auth.Oauth.providers.github},
    });
}

// Sign-in runs on the canonical origin: cookies are per host and providers allow one callback.
pub fn loginPage(arena: std.mem.Allocator, request: zx.server.Request) []const u8 {
    return arena.print("{s}/auth/login", .{site.origin(request)}) catch "/auth/login";
}

pub fn loginUrl(arena: std.mem.Allocator, request: zx.server.Request, next: []const u8) []const u8 {
    return withNext(arena, request, "/auth/login", next) catch "/auth/login";
}

pub fn startUrl(arena: std.mem.Allocator, request: zx.server.Request, p: Auth.Oauth.Provider, next: []const u8) ![]const u8 {
    return withNext(arena, request, try arena.print("/auth/start/{s}", .{p.id}), next);
}

pub fn withNext(arena: std.mem.Allocator, request: zx.server.Request, path: []const u8, next: []const u8) ![]const u8 {
    return Auth.withNext(arena, try arena.print("{s}{s}", .{ site.origin(request), path }), next);
}

pub fn hasPasskeys(arena: std.mem.Allocator) bool {
    const found = zx.db.row(arena, struct { ok: i64 }, "SELECT 1 AS ok FROM auth_passkeys LIMIT 1", .{}) catch return false;
    return found != null;
}

const store: Auth.Store.VTable = .{
    .config = config,
    .authorize = authorize,
    .putSession = putSession,
    .getSession = getSession,
    .deleteSession = deleteSession,
    .putPasskey = putPasskey,
    .getPasskey = getPasskey,
    .listPasskeys = listPasskeys,
    .usePasskey = usePasskey,
    .deletePasskey = deletePasskey,
};

fn config(_: ?*anyopaque, arena: std.mem.Allocator, provider: []const u8) ?Auth.Oauth.Config {
    const prefix = arena.print("oauth_{s}_", .{provider}) catch return null;
    const rows = zx.db.rows(arena, struct { cat: []const u8, val: []const u8 },
        \\SELECT cat, val FROM credentials
        \\WHERE cat IN (?1 || 'client_id', ?1 || 'client_secret')
    , .{prefix}) catch return null;

    var cfg: Auth.Oauth.Config = .{ .client_id = "", .client_secret = "" };
    for (rows) |r| {
        const field = std.meta.stringToEnum(std.meta.FieldEnum(Auth.Oauth.Config), r.cat[prefix.len..]) orelse continue;
        switch (field) {
            inline else => |f| @field(cfg, @tagName(f)) = r.val,
        }
    }
    if (cfg.client_id.len == 0 or cfg.client_secret.len == 0) return null;
    return cfg;
}

fn authorize(_: ?*anyopaque, arena: std.mem.Allocator, owner: Auth.Account) anyerror!bool {
    const allowed = credentials.get(arena, try arena.print("oauth_{s}_allowed", .{owner.provider})) orelse return false;
    var ids = std.mem.tokenizeAny(u8, allowed, ", \t\r\n");
    while (ids.next()) |id| if (std.mem.eql(u8, id, owner.id)) return true;
    return false;
}

fn putSession(_: ?*anyopaque, token_hash: []const u8, owner: Auth.Account, max_age_s: i64) anyerror!void {
    _ = try zx.db.run("DELETE FROM auth_sessions WHERE expires_at <= unixepoch()", .{});
    _ = try zx.db.run(
        \\INSERT INTO auth_sessions (token_hash, provider, account_id, login, created_at, expires_at)
        \\VALUES (?1, ?2, ?3, ?4, unixepoch(), unixepoch() + ?5)
    , .{ token_hash, owner.provider, owner.id, owner.name, max_age_s });
}

fn getSession(_: ?*anyopaque, arena: std.mem.Allocator, token_hash: []const u8) anyerror!?Auth.Account {
    return zx.db.row(arena, Auth.Account,
        \\SELECT provider, account_id AS id, login AS name FROM auth_sessions
        \\WHERE token_hash = ?1 AND expires_at > unixepoch()
    , .{token_hash});
}

fn deleteSession(_: ?*anyopaque, token_hash: []const u8) anyerror!void {
    _ = try zx.db.run("DELETE FROM auth_sessions WHERE token_hash = ?1", .{token_hash});
}

// Public keys are stored base64url-encoded.
const PasskeyRow = struct {
    id: []const u8,
    provider: []const u8,
    account_id: []const u8,
    login: []const u8,
    name: []const u8,
    algorithm: i64,
    public_key: []const u8,
    sign_count: i64,
    created_at: i64,
    last_used_at: ?i64,

    const select =
        \\SELECT credential_id AS id, provider, account_id, login, name, algorithm, public_key, sign_count, created_at, last_used_at
        \\FROM auth_passkeys
    ;

    fn passkey(row: PasskeyRow, arena: std.mem.Allocator) !Auth.Passkey {
        return .{
            .id = row.id,
            .owner = .{ .provider = row.provider, .id = row.account_id, .name = row.login },
            .name = row.name,
            .algorithm = std.enums.fromInt(Auth.WebAuthn.Algorithm, row.algorithm) orelse return error.UnsupportedAlgorithm,
            .public_key = try Auth.WebAuthn.decode(arena, row.public_key),
            .sign_count = std.math.cast(u32, row.sign_count) orelse return error.InvalidSignCount,
            .created_at = row.created_at,
            .last_used_at = row.last_used_at,
        };
    }
};

fn putPasskey(_: ?*anyopaque, p: Auth.Passkey) anyerror!void {
    var buf: [128]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buf);
    _ = try zx.db.run(
        \\INSERT INTO auth_passkeys (credential_id, provider, account_id, login, name, algorithm, public_key, sign_count, created_at)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
    , .{
        p.id,
        p.owner.provider,
        p.owner.id,
        p.owner.name,
        p.name,
        @backingInt(p.algorithm),
        try Auth.WebAuthn.encode(fba.allocator(), p.public_key),
        @as(i64, p.sign_count),
        p.created_at,
    });
}

fn getPasskey(_: ?*anyopaque, arena: std.mem.Allocator, id: []const u8) anyerror!?Auth.Passkey {
    const row = try zx.db.row(arena, PasskeyRow, PasskeyRow.select ++ " WHERE credential_id = ?1", .{id}) orelse return null;
    return try row.passkey(arena);
}

fn listPasskeys(_: ?*anyopaque, arena: std.mem.Allocator, owner: Auth.Account) anyerror![]const Auth.Passkey {
    const rows = try zx.db.rows(arena, PasskeyRow, PasskeyRow.select ++ " WHERE provider = ?1 AND account_id = ?2 ORDER BY created_at", .{ owner.provider, owner.id });
    const out = try arena.alloc(Auth.Passkey, rows.len);
    for (out, rows) |*p, row| p.* = try row.passkey(arena);
    return out;
}

fn usePasskey(_: ?*anyopaque, id: []const u8, sign_count: u32) anyerror!void {
    _ = try zx.db.run("UPDATE auth_passkeys SET sign_count = ?2, last_used_at = unixepoch() WHERE credential_id = ?1", .{ id, @as(i64, sign_count) });
}

fn deletePasskey(_: ?*anyopaque, id: []const u8, owner: Auth.Account) anyerror!void {
    _ = try zx.db.run("DELETE FROM auth_passkeys WHERE credential_id = ?1 AND provider = ?2 AND account_id = ?3", .{ id, owner.provider, owner.id });
}

const std = @import("std");
const zx = @import("zx");
const Auth = zx.Auth;
const credentials = @import("../db/credentials.zig");
const site = @import("../site.zig");

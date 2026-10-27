// The zx host for `Auth`: cookies on the zx request and response, sessions and
// passkeys in D1, provider calls through `zx.fetch`, and provider credentials from
// `credentials` (`oauth_<id>_client_id`, `oauth_<id>_client_secret`, `oauth_<id>_allowed`).

const home = "/admin";

const Host = struct { request: zx.server.Request, response: zx.server.Response };

pub fn of(ctx: anytype) !Auth {
    const host = try ctx.arena.create(Host);
    host.* = .{ .request = ctx.request, .response = ctx.response };
    return .{
        .io = zx.io(),
        .userdata = host,
        .vtable = &vtable,
        .origin = site.origin(ctx.request),
        .name = "nurulhudaapon.com",
        .home = home,
        .providers = &.{Auth.OAuth.providers.github},
    };
}

pub fn account(ctx: anytype) ?Auth.Account {
    const auth = of(ctx) catch return null;
    return auth.account(ctx.arena);
}

// Sign-in runs on the canonical origin: cookies are per host and providers allow one callback.
pub fn loginUrl(arena: std.mem.Allocator, request: zx.server.Request, next: []const u8) []const u8 {
    return withNext(arena, request, "/auth/login", next) catch "/auth/login";
}

pub fn startUrl(arena: std.mem.Allocator, request: zx.server.Request, p: Auth.OAuth.Provider, next: []const u8) ![]const u8 {
    return withNext(arena, request, try arena.print("/auth/start/{s}", .{p.id}), next);
}

pub fn withNext(arena: std.mem.Allocator, request: zx.server.Request, path: []const u8, next: []const u8) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    try out.writer.print("{s}{s}?next=", .{ site.origin(request), path });
    try std.Uri.Component.percentEncode(&out.writer, next, isPathChar);
    return out.toOwnedSlice();
}

fn isPathChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or std.mem.indexOfScalar(u8, "-._~/", c) != null;
}

pub fn hasPasskeys(arena: std.mem.Allocator) bool {
    const found = zx.db.row(arena, struct { ok: i64 }, "SELECT 1 AS ok FROM auth_passkeys LIMIT 1", .{}) catch return false;
    return found != null;
}

const vtable: Auth.VTable = .{
    .cookie = cookie,
    .setCookie = setCookie,
    .config = config,
    .fetch = fetch,
    .putSession = putSession,
    .getSession = getSession,
    .deleteSession = deleteSession,
    .putPasskey = putPasskey,
    .getPasskey = getPasskey,
    .listPasskeys = listPasskeys,
    .usePasskey = usePasskey,
    .deletePasskey = deletePasskey,
};

fn hostOf(ud: ?*anyopaque) *Host {
    return @ptrCast(@alignCast(ud));
}

fn cookie(ud: ?*anyopaque, name: []const u8) ?[]const u8 {
    return hostOf(ud).request.cookies.get(name);
}

fn setCookie(ud: ?*anyopaque, c: Auth.Cookie) void {
    hostOf(ud).response.cookies.set(c.name, c.value, .{
        .path = "/",
        .secure = c.secure,
        .http_only = true,
        .same_site = .lax,
        .max_age = @intCast(c.max_age_s),
    });
}

// Read on every signed-in request (the allow-list is checked each time), so in one query.
fn config(_: ?*anyopaque, arena: std.mem.Allocator, provider: []const u8) ?Auth.OAuth.Config {
    const prefix = arena.print("oauth_{s}_", .{provider}) catch return null;
    const rows = zx.db.rows(arena, struct { cat: []const u8, val: []const u8 },
        \\SELECT cat, val FROM credentials
        \\WHERE cat IN (?1 || 'client_id', ?1 || 'client_secret', ?1 || 'allowed')
    , .{prefix}) catch return null;

    var cfg: Auth.OAuth.Config = .{ .client_id = "", .client_secret = "", .allowed = "" };
    for (rows) |r| {
        const field = std.meta.stringToEnum(std.meta.FieldEnum(Auth.OAuth.Config), r.cat[prefix.len..]) orelse continue;
        switch (field) {
            inline else => |f| @field(cfg, @tagName(f)) = r.val,
        }
    }
    if (cfg.client_id.len == 0 or cfg.client_secret.len == 0 or cfg.allowed.len == 0) return null;
    return cfg;
}

fn fetch(_: ?*anyopaque, arena: std.mem.Allocator, request: Auth.OAuth.Request) anyerror![]const u8 {
    var headers: std.ArrayList(zx.Fetch.RequestInit.Header) = .empty;
    for (request.headers) |h| try headers.append(arena, .{ .name = h.name, .value = h.value });
    try headers.append(arena, .{ .name = "User-Agent", .value = "nurulhudaapon.com" });

    var response = (try zx.fetch(.blocking, arena, request.url, .{
        .method = request.method,
        .headers = headers.items,
        .body = request.body,
        .timeout_ms = 10_000,
    })) orelse return error.NetworkError;
    defer response.deinit();
    if (!response.ok()) {
        zx.log.warn("auth: {s} returned {d}", .{ request.url, response.status });
        return error.ProviderError;
    }
    return arena.dupe(u8, try response.text());
}

fn putSession(_: ?*anyopaque, token_hash: []const u8, owner: Auth.Account, max_age_s: i64) anyerror!void {
    _ = try zx.db.run("DELETE FROM auth_sessions WHERE expires_at <= unixepoch()", .{});
    _ = try zx.db.run(
        \\INSERT INTO auth_sessions (token_hash, provider, account_id, login, created_at, expires_at)
        \\VALUES (?1, ?2, ?3, ?4, unixepoch(), unixepoch() + ?5)
    , .{ token_hash, owner.provider, owner.id, owner.login, max_age_s });
}

fn getSession(_: ?*anyopaque, arena: std.mem.Allocator, token_hash: []const u8) anyerror!?Auth.Account {
    return zx.db.row(arena, Auth.Account,
        \\SELECT provider, account_id AS id, login FROM auth_sessions
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
            .owner = .{ .provider = row.provider, .id = row.account_id, .login = row.login },
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
        p.owner.login,
        p.name,
        @intFromEnum(p.algorithm),
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
const Auth = @import("auth");
const site = @import("../site.zig");

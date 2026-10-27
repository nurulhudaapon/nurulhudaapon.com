// Sign-in with OAuth providers or passkeys, both ending in a session behind an
// opaque cookie. Like `std.Io` or `zx.Kv`, the host supplies the effects (cookies,
// storage, HTTP) through `vtable`; this file holds the flows.
const Auth = @This();

pub const OAuth = @import("Auth/OAuth.zig");
pub const WebAuthn = @import("Auth/WebAuthn.zig");

io: std.Io,
userdata: ?*anyopaque = null,
vtable: *const VTable,
// Where the browser sees the site, e.g. `https://example.com`. Over plain http
// (local dev) browsers refuse `Secure` cookies, so cookies go without it there.
origin: []const u8,
// Shown by the browser when creating a passkey.
name: []const u8,
// Landing page after sign-in, and the only prefix a `next` path may use.
home: []const u8,
callback_path: []const u8 = "/auth/callback/",
providers: []const OAuth.Provider,

pub const VTable = struct {
    cookie: *const fn (?*anyopaque, name: []const u8) ?[]const u8,
    setCookie: *const fn (?*anyopaque, Cookie) void,
    config: *const fn (?*anyopaque, std.mem.Allocator, provider: []const u8) ?OAuth.Config,
    // The body of a 2xx response, or an error.
    fetch: *const fn (?*anyopaque, std.mem.Allocator, OAuth.Request) anyerror![]const u8,

    putSession: *const fn (?*anyopaque, token_hash: []const u8, Account, max_age_s: i64) anyerror!void,
    getSession: *const fn (?*anyopaque, std.mem.Allocator, token_hash: []const u8) anyerror!?Account,
    deleteSession: *const fn (?*anyopaque, token_hash: []const u8) anyerror!void,

    putPasskey: *const fn (?*anyopaque, Passkey) anyerror!void,
    getPasskey: *const fn (?*anyopaque, std.mem.Allocator, id: []const u8) anyerror!?Passkey,
    listPasskeys: *const fn (?*anyopaque, std.mem.Allocator, owner: Account) anyerror![]const Passkey,
    usePasskey: *const fn (?*anyopaque, id: []const u8, sign_count: u32) anyerror!void,
    deletePasskey: *const fn (?*anyopaque, id: []const u8, owner: Account) anyerror!void,
};

pub const Account = struct { provider: []const u8, id: []const u8, login: []const u8 };

// A passkey belongs to the provider account that registered it, and signs in only
// while that account is still allowed.
pub const Passkey = struct {
    id: []const u8,
    owner: Account,
    name: []const u8,
    algorithm: WebAuthn.Algorithm,
    public_key: []const u8,
    sign_count: u32,
    created_at: i64,
    last_used_at: ?i64 = null,
};

// Always HttpOnly, SameSite=Lax and Path=/. A max age of 0 deletes it.
pub const Cookie = struct { name: []const u8, value: []const u8, max_age_s: i64, secure: bool };

pub const Error = error{
    UnknownProvider,
    NotConfigured,
    Expired,
    Denied,
    ProviderFailed,
    NotAllowed,
    PasskeyRejected,
    UnknownPasskey,
    SignInRequired,
};

const CookieSpec = struct { name: []const u8, max_age_s: i64 };

const session_cookie: CookieSpec = .{ .name = "auth_session", .max_age_s = 14 * std.time.s_per_day };
const state_cookie: CookieSpec = .{ .name = "auth_state", .max_age_s = 10 * std.time.s_per_min };
const challenge_cookie: CookieSpec = .{ .name = "auth_challenge", .max_age_s = 5 * std.time.s_per_min };

const max_passkey_name = 60;
const log = std.log.scoped(.auth);

pub fn account(auth: Auth, arena: std.mem.Allocator) ?Account {
    const token = auth.getCookie(session_cookie) orelse return null;
    const owner = (auth.vtable.getSession(auth.userdata, arena, &hashToken(token)) catch null) orelse return null;
    // Taking an account off the allow-list ends its sessions too.
    _, const cfg = auth.resolve(arena, owner.provider) catch return null;
    return if (cfg.allows(owner.id)) owner else null;
}

pub fn signOut(auth: Auth) void {
    const token = auth.takeCookie(session_cookie) orelse return;
    auth.vtable.deleteSession(auth.userdata, &hashToken(token)) catch |err| log.warn("ending session failed: {t}", .{err});
}

pub fn availableProviders(auth: Auth, arena: std.mem.Allocator) ![]const OAuth.Provider {
    var out: std.ArrayList(OAuth.Provider) = .empty;
    for (auth.providers) |p| {
        if (auth.vtable.config(auth.userdata, arena, p.id) != null) try out.append(arena, p);
    }
    return out.items;
}

// The provider URL to send the browser to.
pub fn startOAuth(auth: Auth, arena: std.mem.Allocator, provider_id: []const u8, next: ?[]const u8) ![]const u8 {
    const p, const cfg = try auth.resolve(arena, provider_id);
    const flow: OAuth.Flow = .init(auth.io, auth.safeNext(next));
    auth.setCookie(state_cookie, try flow.encode(arena));
    return OAuth.authorizeUrl(arena, p, cfg, try auth.callbackUrl(arena, p), flow);
}

// Signs in from the provider's callback and returns the path to land on.
pub fn finishOAuth(auth: Auth, arena: std.mem.Allocator, provider_id: []const u8, callback: OAuth.Callback) ![]const u8 {
    const saved = auth.takeCookie(state_cookie);
    const p, const cfg = try auth.resolve(arena, provider_id);
    const flow = OAuth.Flow.decode(arena, saved orelse "", callback.state orelse "") orelse return error.Expired;
    if (callback.@"error" != null) return error.Denied;
    const code = callback.code orelse return error.Denied;

    const identity = auth.exchange(arena, p, cfg, code, &flow.verifier) catch |err| {
        log.warn("{s} sign-in failed: {t}", .{ p.id, err });
        return error.ProviderFailed;
    };
    if (!cfg.allows(identity.id)) {
        log.warn("refused {s} account {s} ({s})", .{ p.id, identity.id, identity.login });
        return error.NotAllowed;
    }
    try auth.startSession(arena, .{ .provider = p.id, .id = identity.id, .login = identity.login });
    return auth.safeNext(flow.next);
}

pub fn passkeys(auth: Auth, arena: std.mem.Allocator) ![]const Passkey {
    const owner = auth.account(arena) orelse return error.SignInRequired;
    return auth.vtable.listPasskeys(auth.userdata, arena, owner);
}

pub fn passkeyCreationOptions(auth: Auth, arena: std.mem.Allocator) ![]const u8 {
    const owner = auth.account(arena) orelse return error.SignInRequired;
    const existing = try auth.vtable.listPasskeys(auth.userdata, arena, owner);
    const exclude = try arena.alloc([]const u8, existing.len);
    for (exclude, existing) |*id, p| id.* = p.id;

    const challenge = try auth.newChallenge(arena);
    const handle = userHandle(owner);
    return WebAuthn.creationOptions(arena, try auth.relyingParty(), .{ .handle = &handle, .name = owner.login }, &challenge, exclude);
}

// `body` is the browser's answer plus an optional `name` for the passkey.
pub fn addPasskey(auth: Auth, arena: std.mem.Allocator, body: []const u8) !void {
    const owner = auth.account(arena) orelse return error.SignInRequired;
    const challenge = try auth.takeChallenge();
    const cred = WebAuthn.verifyRegistration(arena, try auth.relyingParty(), challenge, body) catch |err| {
        log.warn("passkey registration refused: {t}", .{err});
        return error.PasskeyRejected;
    };
    const label = std.json.parseFromSliceLeaky(struct { name: []const u8 = "" }, arena, body, .{ .ignore_unknown_fields = true }) catch
        return error.PasskeyRejected;

    try auth.vtable.putPasskey(auth.userdata, .{
        .id = cred.id,
        .owner = owner,
        .name = passkeyName(label.name),
        .algorithm = cred.algorithm,
        .public_key = cred.public_key,
        .sign_count = cred.sign_count,
        .created_at = std.Io.Timestamp.now(auth.io, .real).toSeconds(),
    });
}

pub fn removePasskey(auth: Auth, arena: std.mem.Allocator, id: []const u8) !void {
    const owner = auth.account(arena) orelse return error.SignInRequired;
    try auth.vtable.deletePasskey(auth.userdata, id, owner);
}

pub fn passkeyRequestOptions(auth: Auth, arena: std.mem.Allocator) ![]const u8 {
    const challenge = try auth.newChallenge(arena);
    return WebAuthn.requestOptions(arena, try auth.relyingParty(), &challenge);
}

// Signs in with the browser's passkey answer and returns the path to land on.
pub fn signInWithPasskey(auth: Auth, arena: std.mem.Allocator, body: []const u8, next: ?[]const u8) ![]const u8 {
    const challenge = try auth.takeChallenge();
    const assertion = WebAuthn.parseAssertion(arena, body) catch return error.PasskeyRejected;
    const key = try auth.vtable.getPasskey(auth.userdata, arena, assertion.credential_id) orelse return error.UnknownPasskey;
    const sign_count = WebAuthn.verifyAssertion(arena, try auth.relyingParty(), challenge, assertion, key.algorithm, key.public_key, key.sign_count) catch |err| {
        log.warn("passkey {s} refused: {t}", .{ key.id, err });
        return error.PasskeyRejected;
    };

    _, const cfg = auth.resolve(arena, key.owner.provider) catch return error.NotAllowed;
    if (!cfg.allows(key.owner.id)) {
        log.warn("passkey owner {s} account {s} is no longer allowed", .{ key.owner.provider, key.owner.id });
        return error.NotAllowed;
    }
    try auth.vtable.usePasskey(auth.userdata, key.id, sign_count);
    try auth.startSession(arena, key.owner);
    return auth.safeNext(next);
}

// Only paths under `home`, so sign-in can't be turned into an open redirect.
pub fn safeNext(auth: Auth, next: ?[]const u8) []const u8 {
    const path = next orelse return auth.home;
    if (!std.mem.startsWith(u8, path, auth.home)) return auth.home;
    const rest = path[auth.home.len..];
    if (rest.len > 0 and rest[0] != '/' and rest[0] != '?') return auth.home;
    if (std.mem.startsWith(u8, path, "//") or std.mem.indexOfAny(u8, path, "\\\r\n") != null) return auth.home;
    return path;
}

fn resolve(auth: Auth, arena: std.mem.Allocator, provider_id: []const u8) !struct { OAuth.Provider, OAuth.Config } {
    for (auth.providers) |p| {
        if (!std.mem.eql(u8, p.id, provider_id)) continue;
        return .{ p, auth.vtable.config(auth.userdata, arena, p.id) orelse return error.NotConfigured };
    }
    return error.UnknownProvider;
}

fn exchange(auth: Auth, arena: std.mem.Allocator, p: OAuth.Provider, cfg: OAuth.Config, code: []const u8, verifier: []const u8) !OAuth.Identity {
    const token = try auth.vtable.fetch(auth.userdata, arena, try OAuth.tokenRequest(arena, p, cfg, code, try auth.callbackUrl(arena, p), verifier));
    const user = try auth.vtable.fetch(auth.userdata, arena, try OAuth.userRequest(arena, p, try OAuth.accessToken(arena, token)));
    return p.parseUser(arena, user);
}

fn callbackUrl(auth: Auth, arena: std.mem.Allocator, p: OAuth.Provider) ![]const u8 {
    return std.mem.concat(arena, u8, &.{ auth.origin, auth.callback_path, p.id });
}

fn relyingParty(auth: Auth) !WebAuthn.RelyingParty {
    return WebAuthn.RelyingParty.fromOrigin(auth.name, auth.origin);
}

// A fresh token on every sign-in, so a token planted before it can't ride along.
fn startSession(auth: Auth, arena: std.mem.Allocator, owner: Account) !void {
    if (auth.getCookie(session_cookie)) |old| auth.vtable.deleteSession(auth.userdata, &hashToken(old)) catch {};
    var bytes: [32]u8 = undefined;
    auth.io.random(&bytes);
    const token = std.fmt.bytesToHex(bytes, .lower);
    try auth.vtable.putSession(auth.userdata, &hashToken(&token), owner, session_cookie.max_age_s);
    auth.setCookie(session_cookie, try arena.dupe(u8, &token));
}

// Only the hash is stored, so a leaked session table can't sign anyone in.
fn hashToken(token: []const u8) [2 * Sha256.digest_length]u8 {
    var digest: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(token, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

fn newChallenge(auth: Auth, arena: std.mem.Allocator) !WebAuthn.Challenge {
    const challenge = WebAuthn.newChallenge(auth.io);
    auth.setCookie(challenge_cookie, try arena.dupe(u8, &challenge));
    return challenge;
}

fn takeChallenge(auth: Auth) !WebAuthn.Challenge {
    const value = auth.takeCookie(challenge_cookie) orelse return error.Expired;
    if (value.len != @sizeOf(WebAuthn.Challenge)) return error.Expired;
    return value[0..@sizeOf(WebAuthn.Challenge)].*;
}

// Stable per account without handing the account id to the authenticator.
fn userHandle(owner: Account) [16]u8 {
    var h: Sha256 = .init(.{});
    h.update(owner.provider);
    h.update(":");
    h.update(owner.id);
    return h.finalResult()[0..16].*;
}

fn passkeyName(raw: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, raw, &std.ascii.whitespace);
    if (trimmed.len == 0) return "Passkey";
    if (trimmed.len <= max_passkey_name) return trimmed;
    // Back up to a code point boundary.
    var end: usize = max_passkey_name;
    while (end > 0 and trimmed[end] & 0xc0 == 0x80) end -= 1;
    return trimmed[0..end];
}

// `__Host-` pins a cookie to this exact host, but needs `Secure`.
fn cookieName(auth: Auth, comptime spec: CookieSpec) []const u8 {
    return if (auth.secure()) "__Host-" ++ spec.name else spec.name;
}

fn secure(auth: Auth) bool {
    return std.mem.startsWith(u8, auth.origin, "https://");
}

fn getCookie(auth: Auth, comptime spec: CookieSpec) ?[]const u8 {
    return auth.vtable.cookie(auth.userdata, auth.cookieName(spec));
}

fn setCookie(auth: Auth, comptime spec: CookieSpec, value: []const u8) void {
    auth.vtable.setCookie(auth.userdata, .{ .name = auth.cookieName(spec), .value = value, .max_age_s = spec.max_age_s, .secure = auth.secure() });
}

// Single use: cleared whether or not it was there.
fn takeCookie(auth: Auth, comptime spec: CookieSpec) ?[]const u8 {
    defer auth.vtable.setCookie(auth.userdata, .{ .name = auth.cookieName(spec), .value = "", .max_age_s = 0, .secure = auth.secure() });
    return auth.getCookie(spec);
}

const Sha256 = std.crypto.hash.sha2.Sha256;

// An in-memory host: one browser's cookie jar and a session table.
const TestHost = struct {
    arena: std.mem.Allocator,
    cookies: std.StringArrayHashMapUnmanaged([]const u8) = .empty,
    sessions: std.StringArrayHashMapUnmanaged(Account) = .empty,
    allowed: []const u8 = "42",

    const vtable: VTable = .{
        .cookie = cookie,
        .setCookie = writeCookie,
        .config = config,
        .fetch = fetch,
        .putSession = putSession,
        .getSession = getSession,
        .deleteSession = deleteSession,
        .putPasskey = undefined,
        .getPasskey = undefined,
        .listPasskeys = undefined,
        .usePasskey = undefined,
        .deletePasskey = undefined,
    };

    fn auth(host: *TestHost) Auth {
        return .{
            .io = std.testing.io,
            .userdata = host,
            .vtable = &vtable,
            .origin = "https://example.com",
            .name = "Example",
            .home = "/admin",
            .providers = &.{OAuth.providers.github},
        };
    }

    fn from(ud: ?*anyopaque) *TestHost {
        return @ptrCast(@alignCast(ud));
    }

    fn cookie(ud: ?*anyopaque, name: []const u8) ?[]const u8 {
        return from(ud).cookies.get(name);
    }

    fn writeCookie(ud: ?*anyopaque, c: Cookie) void {
        const host = from(ud);
        if (c.max_age_s == 0) {
            _ = host.cookies.orderedRemove(c.name);
        } else {
            host.cookies.put(host.arena, c.name, c.value) catch unreachable;
        }
    }

    fn config(ud: ?*anyopaque, _: std.mem.Allocator, _: []const u8) ?OAuth.Config {
        return .{ .client_id = "id", .client_secret = "secret", .allowed = from(ud).allowed };
    }

    fn fetch(_: ?*anyopaque, _: std.mem.Allocator, request: OAuth.Request) anyerror![]const u8 {
        if (std.mem.eql(u8, request.url, OAuth.providers.github.token_url)) {
            if (std.mem.indexOf(u8, request.body.?, "&code_verifier=") == null) return error.MissingVerifier;
            return
                \\{"access_token":"gho_x"}
            ;
        }
        return
            \\{"id":42,"login":"octo"}
        ;
    }

    fn putSession(ud: ?*anyopaque, token_hash: []const u8, owner: Account, _: i64) anyerror!void {
        const host = from(ud);
        try host.sessions.put(host.arena, try host.arena.dupe(u8, token_hash), owner);
    }

    fn getSession(ud: ?*anyopaque, _: std.mem.Allocator, token_hash: []const u8) anyerror!?Account {
        return from(ud).sessions.get(token_hash);
    }

    fn deleteSession(ud: ?*anyopaque, token_hash: []const u8) anyerror!void {
        _ = from(ud).sessions.orderedRemove(token_hash);
    }
};

test "OAuth sign-in, then sign-out" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var host: TestHost = .{ .arena = arena };
    const auth = host.auth();

    const url = try auth.startOAuth(arena, "github", "/admin/finance");
    try std.testing.expect(std.mem.startsWith(u8, url, OAuth.providers.github.authorize_url));
    const forged: [32]u8 = @splat('f');
    try std.testing.expectError(error.Expired, auth.finishOAuth(arena, "github", .{ .state = &forged, .code = "c", .@"error" = null }));
    try std.testing.expect(auth.account(arena) == null);

    _ = try auth.startOAuth(arena, "github", "/admin/finance");
    const state = host.cookies.get("__Host-auth_state").?[0..32];
    try std.testing.expectEqualStrings("/admin/finance", try auth.finishOAuth(arena, "github", .{ .state = state, .code = "c", .@"error" = null }));
    try std.testing.expectEqualStrings("octo", auth.account(arena).?.login);
    try std.testing.expect(host.cookies.get("__Host-auth_state") == null);

    host.allowed = "7";
    try std.testing.expect(auth.account(arena) == null);
    host.allowed = "42";

    auth.signOut();
    try std.testing.expect(auth.account(arena) == null);
    try std.testing.expectEqual(0, host.sessions.count());
}

test "unknown and unconfigured providers" {
    var host: TestHost = .{ .arena = std.testing.allocator };
    try std.testing.expectError(error.UnknownProvider, host.auth().startOAuth(std.testing.allocator, "gitlab", null));
}

test safeNext {
    var host: TestHost = .{ .arena = std.testing.allocator };
    const auth = host.auth();
    try std.testing.expectEqualStrings("/admin", auth.safeNext(null));
    try std.testing.expectEqualStrings("/admin/posts", auth.safeNext("/admin/posts"));
    try std.testing.expectEqualStrings("/admin?x=1", auth.safeNext("/admin?x=1"));
    try std.testing.expectEqualStrings("/admin", auth.safeNext("//evil.example"));
    try std.testing.expectEqualStrings("/admin", auth.safeNext("https://evil.example"));
    try std.testing.expectEqualStrings("/admin", auth.safeNext("/adminx"));
    try std.testing.expectEqualStrings("/admin", auth.safeNext("/admin/\r\nSet-Cookie:x"));
}

test "passkey names" {
    try std.testing.expectEqualStrings("Passkey", passkeyName("  "));
    try std.testing.expectEqualStrings("MacBook", passkeyName(" MacBook\n"));
    const long = "aééééééééééééééééééééééééééééééé";
    try std.testing.expect(std.unicode.utf8ValidateSlice(passkeyName(long)));
    try std.testing.expect(passkeyName(long).len <= max_passkey_name);
}

test {
    _ = OAuth;
    _ = WebAuthn;
    _ = @import("Auth/Cbor.zig");
}

const std = @import("std");

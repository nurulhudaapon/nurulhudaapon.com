// OAuth 2.0 authorization-code flow. Builds the provider requests and parses
// their responses; sending them is left to `Auth.VTable.fetch`.

pub const Identity = struct { id: []const u8, login: []const u8 };

pub const Provider = struct {
    id: []const u8,
    name: []const u8,
    authorize_url: []const u8,
    token_url: []const u8,
    user_url: []const u8,
    scope: []const u8,
    parseUser: *const fn (std.mem.Allocator, []const u8) anyerror!Identity,
};

pub const providers = struct {
    pub const github: Provider = .{
        .id = "github",
        .name = "GitHub",
        .authorize_url = "https://github.com/login/oauth/authorize",
        .token_url = "https://github.com/login/oauth/access_token",
        .user_url = "https://api.github.com/user",
        .scope = "read:user",
        .parseUser = parseGitHubUser,
    };
};

// Numeric ids are stable; logins can be renamed and re-registered by someone else.
fn parseGitHubUser(arena: std.mem.Allocator, body: []const u8) !Identity {
    const user = try std.json.parseFromSliceLeaky(struct { id: u64, login: []const u8 }, arena, body, .{ .ignore_unknown_fields = true });
    return .{ .id = try arena.print("{d}", .{user.id}), .login = user.login };
}

// `allowed` lists the account ids that may sign in, comma-separated.
pub const Config = struct {
    client_id: []const u8,
    client_secret: []const u8,
    allowed: []const u8,

    pub fn allows(cfg: Config, account_id: []const u8) bool {
        var ids = std.mem.tokenizeAny(u8, cfg.allowed, ", \t\r\n");
        while (ids.next()) |id| if (std.mem.eql(u8, id, account_id)) return true;
        return false;
    }
};

pub const Request = struct {
    method: std.http.Method,
    url: []const u8,
    headers: []const std.http.Header,
    body: ?[]const u8 = null,
};

// The query the provider sends back to the callback.
pub const Callback = struct { state: ?[]const u8, code: ?[]const u8, @"error": ?[]const u8 };

pub fn authorizeUrl(arena: std.mem.Allocator, p: Provider, cfg: Config, redirect_uri: []const u8, flow: Flow) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    try out.writer.print("{s}?response_type=code", .{p.authorize_url});
    try param(&out.writer, "client_id", cfg.client_id);
    try param(&out.writer, "redirect_uri", redirect_uri);
    try param(&out.writer, "scope", p.scope);
    try param(&out.writer, "state", &flow.state);
    try param(&out.writer, "code_challenge", &flow.challenge());
    try param(&out.writer, "code_challenge_method", "S256");
    return out.toOwnedSlice();
}

pub fn tokenRequest(arena: std.mem.Allocator, p: Provider, cfg: Config, code: []const u8, redirect_uri: []const u8, verifier: []const u8) !Request {
    var body: std.Io.Writer.Allocating = .init(arena);
    try body.writer.writeAll("grant_type=authorization_code");
    try param(&body.writer, "client_id", cfg.client_id);
    try param(&body.writer, "client_secret", cfg.client_secret);
    try param(&body.writer, "code", code);
    try param(&body.writer, "redirect_uri", redirect_uri);
    try param(&body.writer, "code_verifier", verifier);
    return .{
        .method = .POST,
        .url = p.token_url,
        .body = try body.toOwnedSlice(),
        .headers = try arena.dupe(std.http.Header, &.{
            .{ .name = "Accept", .value = "application/json" },
            .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" },
        }),
    };
}

pub fn accessToken(arena: std.mem.Allocator, body: []const u8) ![]const u8 {
    const token = std.json.parseFromSliceLeaky(struct {
        access_token: ?[]const u8 = null,
        @"error": ?[]const u8 = null,
    }, arena, body, .{ .ignore_unknown_fields = true }) catch return error.TokenExchangeFailed;
    if (token.@"error" != null) return error.TokenExchangeFailed;
    return token.access_token orelse error.TokenExchangeFailed;
}

pub fn userRequest(arena: std.mem.Allocator, p: Provider, access_token: []const u8) !Request {
    return .{
        .method = .GET,
        .url = p.user_url,
        .headers = try arena.dupe(std.http.Header, &.{
            .{ .name = "Accept", .value = "application/json" },
            .{ .name = "Authorization", .value = try arena.print("Bearer {s}", .{access_token}) },
        }),
    };
}

// One sign-in attempt, kept in a cookie as `<state>.<verifier>.<base64url next>`.
// The state ties the provider's callback to this browser, and the PKCE verifier
// makes an intercepted code useless to anyone without the cookie.
pub const Flow = struct {
    state: [32]u8,
    verifier: [43]u8,
    next: []const u8,

    pub fn init(io: std.Io, next: []const u8) Flow {
        var state: [16]u8 = undefined;
        var verifier: [32]u8 = undefined;
        io.random(&state);
        io.random(&verifier);
        var flow: Flow = .{ .state = std.fmt.bytesToHex(state, .lower), .verifier = undefined, .next = next };
        _ = b64.Encoder.encode(&flow.verifier, &verifier);
        return flow;
    }

    pub fn challenge(flow: Flow) [43]u8 {
        var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(&flow.verifier, &digest, .{});
        var out: [43]u8 = undefined;
        _ = b64.Encoder.encode(&out, &digest);
        return out;
    }

    pub fn encode(flow: Flow, arena: std.mem.Allocator) ![]const u8 {
        const next = try arena.alloc(u8, b64.Encoder.calcSize(flow.next.len));
        return std.mem.join(arena, ".", &.{ &flow.state, &flow.verifier, b64.Encoder.encode(next, flow.next) });
    }

    // Null unless `cookie` is well formed and carries the `returned` state.
    pub fn decode(arena: std.mem.Allocator, cookie: []const u8, returned: []const u8) ?Flow {
        var parts = std.mem.splitScalar(u8, cookie, '.');
        const state = parts.next() orelse return null;
        const verifier = parts.next() orelse return null;
        const encoded = parts.next() orelse return null;
        if (parts.next() != null or state.len != 32 or verifier.len != 43 or returned.len != 32) return null;
        if (!std.crypto.timing_safe.eql([32]u8, state[0..32].*, returned[0..32].*)) return null;

        const next = arena.alloc(u8, b64.Decoder.calcSizeForSlice(encoded) catch return null) catch return null;
        b64.Decoder.decode(next, encoded) catch return null;
        return .{ .state = state[0..32].*, .verifier = verifier[0..43].*, .next = next };
    }
};

const b64 = std.base64.url_safe_no_pad;

fn param(w: *std.Io.Writer, name: []const u8, value: []const u8) !void {
    try w.print("&{s}=", .{name});
    try std.Uri.Component.percentEncode(w, value, isUnreserved);
}

fn isUnreserved(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or std.mem.indexOfScalar(u8, "-._~", c) != null;
}

test authorizeUrl {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const flow: Flow = .{ .state = @splat('s'), .verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk".*, .next = "" };
    const url = try authorizeUrl(arena_state.allocator(), providers.github, .{ .client_id = "id 1", .client_secret = "", .allowed = "" }, "https://x.test/cb", flow);
    try std.testing.expectEqualStrings(
        "https://github.com/login/oauth/authorize?response_type=code&client_id=id%201&redirect_uri=https%3A%2F%2Fx.test%2Fcb&scope=read%3Auser" ++
            "&state=ssssssssssssssssssssssssssssssss&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256",
        url,
    );
}

test accessToken {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("gho_x", try accessToken(arena,
        \\{"access_token":"gho_x","token_type":"bearer","scope":"read:user"}
    ));
    try std.testing.expectError(error.TokenExchangeFailed, accessToken(arena,
        \\{"error":"bad_verification_code"}
    ));
    try std.testing.expectError(error.TokenExchangeFailed, accessToken(arena, "not json"));
}

test "Config.allows" {
    const cfg: Config = .{ .client_id = "", .client_secret = "", .allowed = " 1, 22 ,333" };
    try std.testing.expect(cfg.allows("22"));
    try std.testing.expect(cfg.allows("333"));
    try std.testing.expect(!cfg.allows("2"));
    try std.testing.expect(!cfg.allows(""));
}

test Flow {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const flow: Flow = .init(std.testing.io, "/admin/finance");

    const cookie = try flow.encode(arena);
    const back = Flow.decode(arena, cookie, &flow.state).?;
    try std.testing.expectEqualStrings("/admin/finance", back.next);
    try std.testing.expectEqualSlices(u8, &flow.verifier, &back.verifier);
    try std.testing.expect(Flow.decode(arena, cookie, &@as([32]u8, @splat('f'))) == null);
    try std.testing.expect(Flow.decode(arena, cookie, "short") == null);
    try std.testing.expect(Flow.decode(arena, "garbage", &flow.state) == null);
    try std.testing.expect(Flow.decode(arena, try std.mem.concat(arena, u8, &.{ cookie, ".x" }), &flow.state) == null);
}

test "Flow.challenge is the RFC 7636 S256 transform" {
    const flow: Flow = .{ .state = @splat('0'), .verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk".*, .next = "" };
    try std.testing.expectEqualStrings("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", &flow.challenge());
}

const std = @import("std");

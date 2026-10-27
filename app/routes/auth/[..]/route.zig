pub fn Route(ctx: zx.RouteContext) !void {
    return handle(ctx);
}

pub const options: zx.RouteOptions = .{
    .rendering = .request,
};

const login_path = "/auth/login";
const settings_path = "/admin/settings";

const AuthRoute = enum {
    start,
    callback,
    logout,
    @"passkey/login/options",
    @"passkey/login",
    @"passkey/register/options",
    @"passkey/register",
    @"passkey/remove",

    fn method(route: AuthRoute) std.http.Method {
        return switch (route) {
            .start, .callback => .GET,
            else => .POST,
        };
    }

    // `start` and `callback` take the provider id as their last segment.
    fn parse(path: []const u8) ?struct { AuthRoute, []const u8 } {
        const rest = if (std.mem.startsWith(u8, path, prefix)) path[prefix.len..] else return null;
        if (std.meta.stringToEnum(AuthRoute, rest)) |route| return switch (route) {
            .start, .callback => null,
            else => .{ route, "" },
        };
        const slash = std.mem.lastIndexOfScalar(u8, rest, '/') orelse return null;
        const route = std.meta.stringToEnum(AuthRoute, rest[0..slash]) orelse return null;
        return switch (route) {
            .start, .callback => .{ route, rest[slash + 1 ..] },
            else => null,
        };
    }

    const prefix = "/auth/";
};

fn handle(ctx: zx.RouteContext) !void {
    ctx.response.headers.add("Cache-Control", "no-store");
    const route, const provider = AuthRoute.parse(ctx.request.pathname) orelse return ctx.response.setStatus(.not_found);
    if (ctx.request.method != route.method()) return ctx.response.setStatus(.method_not_allowed);

    const auth = try adapter.of(ctx);
    const q = ctx.request.queries;
    switch (route) {
        .start => {
            const url = auth.startOAuth(ctx.arena, provider, q.get("next")) catch |err| return redirect(ctx, try failure(ctx, login_path, err));
            redirect(ctx, url);
        },
        .callback => {
            const next = auth.finishOAuth(ctx.arena, provider, .{ .state = q.get("state"), .code = q.get("code"), .@"error" = q.get("error") }) catch |err|
                return redirect(ctx, try failure(ctx, login_path, err));
            redirect(ctx, next);
        },
        .logout => {
            auth.signOut();
            redirect(ctx, login_path ++ "?ok=signed_out");
        },
        // The passkey endpoints answer the page script in JSON: ceremony options as
        // `{"publicKey": …}`, or `{"redirect": url}` once only a page is left to show.
        .@"passkey/login/options" => opts(ctx, try auth.passkeyRequestOptions(ctx.arena)),
        .@"passkey/login" => {
            const next = auth.signInWithPasskey(ctx.arena, ctx.request.text() orelse "", q.get("next")) catch |err|
                return jsonRedirect(ctx, try failure(ctx, login_path, err));
            jsonRedirect(ctx, next);
        },
        .@"passkey/register/options" => opts(ctx, auth.passkeyCreationOptions(ctx.arena) catch |err|
            return jsonRedirect(ctx, try failure(ctx, settings_path, err))),
        .@"passkey/register" => {
            const body = ctx.request.text() orelse "";
            const label = std.json.parseFromSliceLeaky(struct { name: []const u8 = "" }, ctx.arena, body, .{ .ignore_unknown_fields = true }) catch
                return jsonRedirect(ctx, try failure(ctx, settings_path, error.PasskeyRejected));
            auth.addPasskey(ctx.arena, body, label.name) catch |err|
                return jsonRedirect(ctx, try failure(ctx, settings_path, err));
            jsonRedirect(ctx, settings_path ++ "?ok=passkey_added");
        },
        .@"passkey/remove" => {
            auth.removePasskey(ctx.arena, ctx.request.formData().get("credential_id") orelse "") catch |err|
                return redirect(ctx, try failure(ctx, settings_path, err));
            redirect(ctx, settings_path ++ "?ok=passkey_removed");
        },
    }
}

fn failure(ctx: zx.RouteContext, page: []const u8, err: anyerror) ![]const u8 {
    const code = switch (err) {
        error.SignInRequired => return adapter.loginUrl(ctx.arena, ctx.request, page),
        error.UnknownProvider => "unknown_provider",
        error.NotConfigured => "not_configured",
        error.Expired => "expired",
        error.Denied => "denied",
        error.ProviderFailed => "provider",
        error.NotAllowed => "not_allowed",
        error.PasskeyRejected => "passkey",
        error.UnknownPasskey => "passkey_unknown",
        else => blk: {
            zx.log.err("auth: {t}", .{err});
            break :blk "failed";
        },
    };
    return ctx.arena.print("{s}?err={s}", .{ page, code });
}

// 303 so a redirect after a POST is always followed with a GET.
fn redirect(ctx: zx.RouteContext, url: []const u8) void {
    ctx.response.redirect(url, 303);
}

fn opts(ctx: zx.RouteContext, json: []const u8) void {
    ctx.response.setContentType(.@"application/json");
    ctx.response.text(json);
}

fn jsonRedirect(ctx: zx.RouteContext, url: []const u8) void {
    ctx.response.json(.{ .redirect = url }, .{}) catch {};
}

test "AuthRoute.parse" {
    try std.testing.expectEqualDeep(.{ AuthRoute.start, "github" }, AuthRoute.parse("/auth/start/github").?);
    try std.testing.expectEqualDeep(.{ AuthRoute.callback, "github" }, AuthRoute.parse("/auth/callback/github").?);
    try std.testing.expectEqualDeep(.{ AuthRoute.logout, "" }, AuthRoute.parse("/auth/logout").?);
    try std.testing.expectEqualDeep(.{ AuthRoute.@"passkey/login/options", "" }, AuthRoute.parse("/auth/passkey/login/options").?);
    try std.testing.expectEqualDeep(.{ AuthRoute.@"passkey/register", "" }, AuthRoute.parse("/auth/passkey/register").?);
    try std.testing.expect(AuthRoute.parse("/auth/start") == null);
    try std.testing.expect(AuthRoute.parse("/auth/logout/x") == null);
    try std.testing.expect(AuthRoute.parse("/auth/passkey/login/x") == null);
    try std.testing.expect(AuthRoute.parse("/auth/login") == null);
    try std.testing.expect(AuthRoute.parse("/other/start/github") == null);
}

const std = @import("std");
const zx = @import("zx");
const adapter = @import("../../../auth/adapter.zig");

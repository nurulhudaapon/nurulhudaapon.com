pub fn Proxy(ctx: *zx.ProxyContext) void {
    if (@import("builtin").mode == .debug) return;
    if (signedIn(ctx)) |owner| return ctx.state(@as(?Auth.Account, owner));

    ctx.response.headers.append("Cache-Control", "no-store");
    if (ctx.request.method == .GET) {
        ctx.response.redirect(adapter.loginUrl(ctx.arena, ctx.request, ctx.request.pathname), .found);
    } else {
        ctx.response.setStatus(.unauthorized);
        ctx.response.text("Sign in required");
    }
    ctx.abort();
}

fn signedIn(ctx: *zx.ProxyContext) ?Auth.Account {
    const auth = adapter.of(ctx) catch return null;
    return auth.account(ctx.arena);
}

const zx = @import("zx");
const Auth = @import("auth");
const adapter = @import("../../auth/adapter.zig");

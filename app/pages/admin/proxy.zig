pub fn Proxy(ctx: *zx.ProxyContext) void {
    if (allowed(ctx)) return;

    ctx.response.headers.add("Cache-Control", "no-store");
    if (ctx.request.method == .GET) {
        ctx.response.redirect(adapter.loginUrl(ctx.arena, ctx.request, ctx.request.pathname), 302);
    } else {
        ctx.response.setStatus(.unauthorized);
        ctx.response.text("Sign in required");
    }
    ctx.abort();
}

fn allowed(ctx: *zx.ProxyContext) bool {
    const auth = adapter.of(ctx) catch return false;
    return auth.account(ctx.arena) != null;
}

const zx = @import("zx");
const adapter = @import("../../auth/adapter.zig");

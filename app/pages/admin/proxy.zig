pub fn Proxy(ctx: *zx.ProxyContext) void {
    // Local debug only. Production relies on CF Access + this header check.
    if (builtin.optimize == .debug) return;
    if (ctx.request.headers.get("cf-access-jwt-assertion")) |jwt| if (jwt.len > 0) return;

    ctx.response.setStatus(.forbidden);
    ctx.response.headers.add("Cache-Control", "no-store");
    ctx.response.text("Forbidden");
    ctx.abort();
}

const builtin = @import("builtin");
const zx = @import("zx");

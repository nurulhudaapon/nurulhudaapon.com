pub fn Proxy(ctx: *zx.ProxyContext) void {
    if (@import("builtin").mode == .debug) return;
    const auth = adapter.of(ctx) catch {
        ctx.response.setStatus(.internal_server_error);
        return ctx.abort();
    };
    const owner = auth.guard(ctx, auth.loginUrl(ctx.arena, null) catch "/auth/login") orelse return;
    ctx.state(@as(?Auth.Account, owner));
}

const zx = @import("zx");
const Auth = zx.Auth;
const adapter = @import("../../auth/adapter.zig");

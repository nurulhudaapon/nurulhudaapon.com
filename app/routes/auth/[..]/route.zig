const zx = @import("zx");
const adapter = @import("../../../auth/adapter.zig");

// OAuth start/callback, logout and the passkey endpoints, all from `zx.Auth`.
pub fn Route(ctx: zx.RouteContext) !void {
    return (try adapter.of(ctx)).handle(ctx);
}

pub const options: zx.RouteOptions = .{ .rendering = .request };

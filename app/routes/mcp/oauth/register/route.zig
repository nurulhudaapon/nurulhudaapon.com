const zx = @import("zx");
const register = @import("../register.zig");

pub fn POST(ctx: zx.RouteContext) !void {
    return register.handle(ctx);
}

pub const options: zx.RouteOptions = .{ .rendering = .request };

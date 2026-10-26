const zx = @import("zx");
const authorize = @import("../authorize.zig");

pub fn GET(ctx: zx.RouteContext) !void {
    return authorize.handle(ctx);
}

pub const options: zx.RouteOptions = .{ .rendering = .request };

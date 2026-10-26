const zx = @import("zx");
const token = @import("../token.zig");

pub fn POST(ctx: zx.RouteContext) !void {
    return token.handle(ctx);
}

pub const options: zx.RouteOptions = .{ .rendering = .request };

const zx = @import("zx");

pub const POST = @import("../token.zig").handle;

pub const options: zx.RouteOptions = .{ .rendering = .request };

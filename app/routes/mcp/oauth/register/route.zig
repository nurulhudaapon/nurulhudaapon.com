const zx = @import("zx");

pub const POST = @import("../register.zig").handle;

pub const options: zx.RouteOptions = .{ .rendering = .request };

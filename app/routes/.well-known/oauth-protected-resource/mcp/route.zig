const zx = @import("zx");

pub const GET = @import("../route.zig").GET;

pub const options: zx.RouteOptions = .{ .rendering = .request };

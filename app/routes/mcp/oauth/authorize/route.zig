const zx = @import("zx");

pub const GET = @import("../authorize.zig").handle;

pub const options: zx.RouteOptions = .{ .rendering = .request };

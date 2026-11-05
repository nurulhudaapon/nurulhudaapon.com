const zx = @import("zx");

pub const POST = @import("../../../../mcp/oauth/register.zig").handle;

pub const options: zx.RouteOptions = .{ .rendering = .request };

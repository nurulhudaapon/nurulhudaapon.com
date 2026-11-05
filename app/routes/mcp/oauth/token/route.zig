const zx = @import("zx");

pub const POST = @import("../../../../mcp/oauth/token.zig").handle;

pub const options: zx.RouteOptions = .{ .rendering = .request };

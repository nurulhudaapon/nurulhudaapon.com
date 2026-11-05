const zx = @import("zx");

pub const GET = @import("../../../mcp/oauth/metadata.zig").write;

pub const options: zx.RouteOptions = .{ .rendering = .request };

const zx = @import("zx");
const metadata = @import("../../mcp/oauth/metadata.zig");

pub fn GET(ctx: zx.RouteContext) !void {
    return metadata.write(ctx);
}

pub const options: zx.RouteOptions = .{ .rendering = .request };

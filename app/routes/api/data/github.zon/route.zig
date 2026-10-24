pub fn GET(ctx: zx.RouteContext) !void {
    const repos = github.fetchStats(ctx.arena) catch |err| {
        zx.log.warn("github stats: {s}", .{@errorName(err)});
        // Non-200 responses skip the page cache, so the next request retries.
        ctx.response.setStatus(.bad_gateway);
        return;
    };

    var aw = std.Io.Writer.Allocating.init(ctx.arena);
    try std.zon.stringify.serialize(.{ .repos = repos }, .{ .whitespace = false }, &aw.writer);
    ctx.response.text(aw.written());
}

pub const options: zx.RouteOptions = .{
    .rendering = .request,
    .caching = .tag("1h"),
};

const github = @import("../../../../pages/dev/github.zig");

const zx = @import("zx");
const std = @import("std");

pub fn GET(ctx: zx.RouteContext) !void {
    ctx.response.headers.append("Cache-Control", "no-store");
    const q = ctx.request.query;
    const start = std.fmt.parseInt(i64, q.get("start") orelse "", 10) catch {
        ctx.response.setStatus(.bad_request);
        return ctx.response.text("");
    };
    var state = try view.load(ctx.arena, start, if (q.get("force") != null) 0 else calendars.loadPrefs(ctx.arena).staleSeconds(), q.get("alloc") != null);
    // Final either way: a calendar that still fails mustn't trigger another round.
    state.sync = .idle;

    var aw = std.Io.Writer.Allocating.init(ctx.arena);
    try zx.util.zxon.serialize(state, &aw.writer, .{});
    ctx.response.text(aw.written());
}

pub const options: zx.RouteOptions = .{ .rendering = .request };

const std = @import("std");
const zx = @import("zx");
const view = @import("../view.zig");
const calendars = @import("../../../schedule/calendars.zig");

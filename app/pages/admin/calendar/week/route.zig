pub fn GET(ctx: zx.RouteContext) !void {
    ctx.response.headers.append("Cache-Control", "no-store");
    const q = ctx.request.query;
    const start = std.fmt.parseInt(i64, q.get("start") orelse "", 10) catch {
        ctx.response.setStatus(.bad_request);
        return ctx.response.text("");
    };
    const now = std.Io.Timestamp.now(ctx.io, .real).toSeconds();
    var state = try view.load(ctx.arena, now, start, q.get("alloc") != null);

    // `sync`/`force` queue a sync and start the wait; `since` is a later poll.
    // Copies at least as new as `since` end it.
    const since = if (q.get("force") != null)
        calendars.requestSync(ctx.arena, ctx.io, ctx.response, true)
    else if (q.get("sync") != null)
        calendars.requestSync(ctx.arena, ctx.io, ctx.response, false)
    else
        std.fmt.parseInt(i64, q.get("since") orelse "0", 10) catch 0;
    state.since = since;
    state.sync = if (state.synced_at < since) .waiting else .idle;

    var body: std.Io.Writer.Allocating = .init(ctx.arena);
    try zx.util.zxon.serialize(state, &body.writer, .{});
    ctx.response.text(body.written());
}

pub const options: zx.RouteOptions = .{ .rendering = .request };

const std = @import("std");
const zx = @import("zx");
const view = @import("../view.zig");
const calendars = @import("../../../../schedule.zig").calendars;

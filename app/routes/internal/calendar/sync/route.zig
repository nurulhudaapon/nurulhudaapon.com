// Syncs one calendar (`?id=`). Only the queue consumer in main.ts reaches it:
// the worker's fetch handler refuses every /internal/ path from outside.
pub fn POST(ctx: zx.RouteContext) !void {
    const id = std.fmt.parseInt(i64, ctx.request.query.get("id") orelse "", 10) catch {
        ctx.response.setStatus(.bad_request);
        return ctx.response.text("missing id");
    };
    calendars.sync(ctx.arena, ctx.io, id) catch |err| {
        zx.log.err("calendar: syncing calendar {d} failed: {any}", .{ id, err });
        ctx.response.setStatus(.internal_server_error);
        return ctx.response.text(@errorName(err));
    };
    ctx.response.text("ok");
}

pub const options: zx.RouteOptions = .{ .rendering = .request };

const std = @import("std");
const zx = @import("zx");
const calendars = @import("../../../../schedule.zig").calendars;

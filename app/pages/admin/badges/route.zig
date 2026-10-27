pub const Counts = struct { unanswered: i64 = 0, upcoming: i64 = 0 };

pub fn GET(ctx: zx.RouteContext) !void {
    const counts = try zx.db.row(ctx.arena, Counts,
        \\SELECT
        \\  COALESCE((SELECT SUM(answer IS NULL) FROM questions WHERE deleted = 0), 0) AS unanswered,
        \\  COALESCE((SELECT SUM(cancelled_at IS NULL AND ends_at >= ?1) FROM bookings), 0) AS upcoming
    , .{booking.nowUnix()}) orelse Counts{};

    var aw = std.Io.Writer.Allocating.init(ctx.arena);
    try zx.util.zxon.serialize(counts, &aw.writer, .{});
    ctx.response.headers.add("Cache-Control", "no-store");
    ctx.response.text(aw.written());
}

pub const options: zx.RouteOptions = .{ .rendering = .request };

const std = @import("std");
const zx = @import("zx");
const booking = @import("../../schedule/booking.zig");

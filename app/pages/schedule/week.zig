const std = @import("std");
const slots = @import("slots.zig");

const Interval = slots.Interval;
const day_s = std.time.s_per_day;
const offset = slots.config.utc_offset_s;

pub fn weekStart(unix: i64, first: slots.Weekday) i64 {
    const local_day = @divFloor(unix + offset, day_s);
    // 1970-01-01 was a Thursday.
    const back = @mod(local_day + 4 - @as(i64, @backingInt(first)), 7);
    return (local_day - back) * day_s - offset;
}

pub fn parseDate(text: []const u8) ?i64 {
    if (text.len != 10 or text[4] != '-' or text[7] != '-') return null;
    const y = std.fmt.parseInt(i64, text[0..4], 10) catch return null;
    const m = std.fmt.parseInt(i64, text[5..7], 10) catch return null;
    const d = std.fmt.parseInt(i64, text[8..10], 10) catch return null;
    if (y < 1970 or y > 9999 or m < 1 or m > 12 or d < 1 or d > 31) return null;
    return daysFromCivil(y, m, d) * day_s - offset;
}

fn daysFromCivil(year: i64, month: i64, day: i64) i64 {
    const y = if (month <= 2) year - 1 else year;
    const era = @divFloor(y, 400);
    const yoe = y - era * 400;
    const mp = @mod(month + 9, 12);
    const doy = @divFloor(153 * mp + 2, 5) + day - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

pub fn formatDate(buf: *[10]u8, unix: i64) []const u8 {
    const d = slots.LocalDate.of(unix);
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{ d.year, d.month, d.day }) catch unreachable;
}

pub fn coveredSeconds(scratch: std.mem.Allocator, intervals: []const Interval, window: Interval) !i64 {
    var clipped: std.ArrayList(Interval) = .empty;
    defer clipped.deinit(scratch);
    for (intervals) |i| {
        const s = @max(i.start, window.start);
        const e = @min(i.end, window.end);
        if (e > s) try clipped.append(scratch, .{ .start = s, .end = e });
    }
    std.mem.sort(Interval, clipped.items, {}, byStart);

    var total: i64 = 0;
    var cur: ?Interval = null;
    for (clipped.items) |i| {
        if (cur) |*c| {
            if (i.start <= c.end) {
                c.end = @max(c.end, i.end);
                continue;
            }
            total += c.end - c.start;
        }
        cur = i;
    }
    if (cur) |c| total += c.end - c.start;
    return total;
}

pub fn byStart(_: void, a: Interval, b: Interval) bool {
    return a.start < b.start or (a.start == b.start and a.end > b.end);
}

pub const Lane = struct { lane: u8, lanes: u8 };

// `spans` must be sorted by `byStart`. Overlapping spans share one `lanes` count.
pub fn layout(allocator: std.mem.Allocator, spans: []const Interval) ![]Lane {
    const out = try allocator.alloc(Lane, spans.len);
    var lane_ends: std.ArrayList(i64) = .empty;
    defer lane_ends.deinit(allocator);

    var group_begin: usize = 0;
    var group_end: i64 = std.math.minInt(i64);
    for (spans, 0..) |span, i| {
        if (span.start >= group_end) {
            finishGroup(out[group_begin..i], lane_ends.items.len);
            lane_ends.clearRetainingCapacity();
            group_begin = i;
        }
        const lane = for (lane_ends.items, 0..) |end, l| {
            if (end <= span.start) break l;
        } else blk: {
            try lane_ends.append(allocator, span.end);
            break :blk lane_ends.items.len - 1;
        };
        lane_ends.items[lane] = span.end;
        out[i].lane = @intCast(@min(lane, std.math.maxInt(u8)));
        group_end = @max(group_end, span.end);
    }
    finishGroup(out[group_begin..], lane_ends.items.len);
    return out;
}

fn finishGroup(group: []Lane, lanes: usize) void {
    for (group) |*l| l.lanes = @intCast(@min(@max(lanes, 1), std.math.maxInt(u8)));
}

pub fn formatDuration(allocator: std.mem.Allocator, seconds: i64) ![]const u8 {
    const minutes = @divFloor(@max(seconds, 0) + 30, 60);
    const h = @divFloor(minutes, 60);
    const m = @mod(minutes, 60);
    if (h == 0) return allocator.print("{d}m", .{m});
    if (m == 0) return allocator.print("{d}h", .{h});
    return allocator.print("{d}h {d}m", .{ h, m });
}

const sat_oct24_midnight_dhaka: i64 = 1792778400;
const sun_oct18_midnight_dhaka: i64 = sat_oct24_midnight_dhaka - 6 * day_s;

test weekStart {
    const thu_oct22_10am_dhaka = 1792641600;
    try std.testing.expectEqual(sun_oct18_midnight_dhaka, weekStart(thu_oct22_10am_dhaka, .sun));
    try std.testing.expectEqual(sun_oct18_midnight_dhaka, weekStart(sun_oct18_midnight_dhaka, .sun));
    try std.testing.expectEqual(sun_oct18_midnight_dhaka, weekStart(sun_oct18_midnight_dhaka + 7 * day_s - 1, .sun));
    try std.testing.expectEqual(sun_oct18_midnight_dhaka + 7 * day_s, weekStart(sun_oct18_midnight_dhaka + 7 * day_s, .sun));
    try std.testing.expectEqual(sun_oct18_midnight_dhaka + day_s, weekStart(thu_oct22_10am_dhaka, .mon));
    try std.testing.expectEqual(sun_oct18_midnight_dhaka - day_s, weekStart(thu_oct22_10am_dhaka, .sat));
    try std.testing.expectEqual(sun_oct18_midnight_dhaka - 6 * day_s, weekStart(sun_oct18_midnight_dhaka, .mon));
}

test parseDate {
    try std.testing.expectEqual(sat_oct24_midnight_dhaka, parseDate("2026-10-24").?);
    try std.testing.expectEqual(null, parseDate("2026-13-01"));
    try std.testing.expectEqual(null, parseDate("26-10-24"));
    var buf: [10]u8 = undefined;
    try std.testing.expectEqualStrings("2026-10-24", formatDate(&buf, sat_oct24_midnight_dhaka + 3600));
}

test coveredSeconds {
    const spans = [_]Interval{ .{ .start = 10, .end = 20 }, .{ .start = 0, .end = 5 }, .{ .start = 15, .end = 30 }, .{ .start = 40, .end = 100 } };
    try std.testing.expectEqual(5 + 20 + 10, try coveredSeconds(std.testing.allocator, &spans, .{ .start = 0, .end = 50 }));
}

test layout {
    const spans = [_]Interval{ .{ .start = 0, .end = 10 }, .{ .start = 5, .end = 15 }, .{ .start = 10, .end = 20 }, .{ .start = 30, .end = 40 } };
    const lanes = try layout(std.testing.allocator, &spans);
    defer std.testing.allocator.free(lanes);
    try std.testing.expectEqualSlices(Lane, &.{
        .{ .lane = 0, .lanes = 2 }, .{ .lane = 1, .lanes = 2 }, .{ .lane = 0, .lanes = 2 }, .{ .lane = 0, .lanes = 1 },
    }, lanes);
}

test formatDuration {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("45m", try formatDuration(a, 45 * 60));
    try std.testing.expectEqualStrings("2h", try formatDuration(a, 2 * 3600));
    try std.testing.expectEqualStrings("3h 30m", try formatDuration(a, 3 * 3600 + 1800));
}

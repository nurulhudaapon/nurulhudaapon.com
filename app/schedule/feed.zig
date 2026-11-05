const std = @import("std");
const slots = @import("slots.zig");

pub const Detail = enum {
    full,
    busy,

    pub fn label(self: Detail) []const u8 {
        return switch (self) {
            .full => "Full details",
            .busy => "Busy only",
        };
    }
};

pub const Item = struct {
    uid: []const u8,
    start: i64,
    end: i64,
    all_day: bool,
    busy: bool,
    summary: []const u8,
    location: []const u8,
};

pub fn write(w: *std.Io.Writer, name: []const u8, items: []const Item, detail: Detail, now: i64) !void {
    try line(w, "BEGIN:VCALENDAR", .{});
    try line(w, "VERSION:2.0", .{});
    try line(w, "PRODID:-//nurulhudaapon.com//Calendar//EN", .{});
    try line(w, "CALSCALE:GREGORIAN", .{});
    try line(w, "METHOD:PUBLISH", .{});
    try line(w, "X-WR-CALNAME:{f}", .{Text{ .s = name }});
    try line(w, "X-WR-TIMEZONE:{s}", .{slots.config.timezone});
    try line(w, "REFRESH-INTERVAL;VALUE=DURATION:PT15M", .{});
    try line(w, "X-PUBLISHED-TTL:PT15M", .{});

    var stamp: [16]u8 = undefined;
    const dtstamp = utc(&stamp, now);
    for (items) |it| {
        if (detail == .busy and !it.busy) continue;
        try line(w, "BEGIN:VEVENT", .{});
        try line(w, "UID:{s}", .{it.uid});
        try line(w, "DTSTAMP:{s}", .{dtstamp});
        var a: [16]u8 = undefined;
        var b: [16]u8 = undefined;
        if (it.all_day) {
            const end = if (it.end > it.start) it.end else it.start + std.time.s_per_day;
            try line(w, "DTSTART;VALUE=DATE:{s}", .{localDate(&a, it.start)});
            try line(w, "DTEND;VALUE=DATE:{s}", .{localDate(&b, end)});
        } else {
            try line(w, "DTSTART:{s}", .{utc(&a, it.start)});
            try line(w, "DTEND:{s}", .{utc(&b, it.end)});
        }
        switch (detail) {
            .busy => try line(w, "SUMMARY:Busy", .{}),
            .full => {
                try line(w, "SUMMARY:{f}", .{Text{ .s = if (it.summary.len > 0) it.summary else "(no title)" }});
                if (it.location.len > 0) try line(w, "LOCATION:{f}", .{Text{ .s = it.location }});
            },
        }
        try line(w, "TRANSP:{s}", .{if (it.busy) "OPAQUE" else "TRANSPARENT"});
        try line(w, "END:VEVENT", .{});
    }
    try line(w, "END:VCALENDAR", .{});
}

// Folds at 75 octets without splitting a UTF-8 sequence.
fn line(w: *std.Io.Writer, comptime fmt: []const u8, args: anytype) !void {
    var buf: [4096]u8 = undefined;
    var fixed: std.Io.Writer = .fixed(&buf);
    fixed.print(fmt, args) catch {};
    var rest = fixed.buffered();
    var limit: usize = 75;
    while (rest.len > limit) {
        var cut = limit;
        while (cut > 0 and rest[cut] & 0xC0 == 0x80) cut -= 1;
        try w.writeAll(rest[0..cut]);
        try w.writeAll("\r\n ");
        rest = rest[cut..];
        limit = 74; // the leading space counts
    }
    try w.writeAll(rest);
    try w.writeAll("\r\n");
}

// RFC 5545 §3.3.11.
const Text = struct {
    s: []const u8,

    pub fn format(self: Text, w: *std.Io.Writer) std.Io.Writer.Error!void {
        for (self.s) |ch| switch (ch) {
            '\\' => try w.writeAll("\\\\"),
            ';' => try w.writeAll("\\;"),
            ',' => try w.writeAll("\\,"),
            '\n' => try w.writeAll("\\n"),
            '\r' => {},
            else => if (ch < 0x20 and ch != '\t') {} else try w.writeByte(ch),
        };
    }
};

fn utc(buf: *[16]u8, unix: i64) []const u8 {
    const d = slots.LocalDate.at(unix, 0);
    const secs: u64 = @intCast(@mod(unix, 60));
    return std.fmt.bufPrint(buf, "{d:0>4}{d:0>2}{d:0>2}T{d:0>2}{d:0>2}{d:0>2}Z", .{
        d.year, d.month, d.day, d.minute_of_day / 60, d.minute_of_day % 60, secs,
    }) catch unreachable;
}

fn localDate(buf: *[16]u8, unix: i64) []const u8 {
    const d = slots.LocalDate.of(unix);
    return std.fmt.bufPrint(buf, "{d:0>4}{d:0>2}{d:0>2}", .{ d.year, d.month, d.day }) catch unreachable;
}

const thu_oct22_10am_dhaka: i64 = 1792641600;
const sat_oct24_midnight_dhaka: i64 = 1792778400;

const sample = [_]Item{
    .{ .uid = "a@x", .start = thu_oct22_10am_dhaka, .end = thu_oct22_10am_dhaka + 1800, .all_day = false, .busy = true, .summary = "Call; Ada, Bob", .location = "Room 1\nFloor 2" },
    .{ .uid = "b@x", .start = thu_oct22_10am_dhaka, .end = thu_oct22_10am_dhaka + 3600, .all_day = false, .busy = false, .summary = "Focus", .location = "" },
    .{ .uid = "c@x", .start = sat_oct24_midnight_dhaka, .end = sat_oct24_midnight_dhaka + std.time.s_per_day, .all_day = true, .busy = true, .summary = "Holiday", .location = "" },
};

test "full feed" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try write(&out.writer, "Nurul", &sample, .full, thu_oct22_10am_dhaka);
    const ics = out.written();
    for ([_][]const u8{
        "BEGIN:VCALENDAR\r\n",
        "DTSTART:20261022T040000Z\r\nDTEND:20261022T043000Z\r\n",
        "SUMMARY:Call\\; Ada\\, Bob\r\n",
        "LOCATION:Room 1\\nFloor 2\r\n",
        "SUMMARY:Focus\r\nTRANSP:TRANSPARENT\r\n",
        "DTSTART;VALUE=DATE:20261024\r\nDTEND;VALUE=DATE:20261025\r\n",
        "END:VCALENDAR\r\n",
    }) |needle| try std.testing.expect(std.mem.indexOf(u8, ics, needle) != null);
}

test "busy feed hides everything but the time" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try write(&out.writer, "Nurul", &sample, .busy, thu_oct22_10am_dhaka);
    const ics = out.written();
    try std.testing.expectEqual(2, std.mem.count(u8, ics, "BEGIN:VEVENT"));
    try std.testing.expectEqual(2, std.mem.count(u8, ics, "SUMMARY:Busy"));
    for ([_][]const u8{ "Call", "Room", "Focus", "Holiday", "LOCATION" }) |secret|
        try std.testing.expect(std.mem.indexOf(u8, ics, secret) == null);
}

test "long lines fold without splitting UTF-8" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    const title = "\u{09A2}\u{09BE}\u{0995}\u{09BE} \u{09A2}\u{09BE}\u{0995}\u{09BE} \u{09A2}\u{09BE}\u{0995}\u{09BE} \u{09A2}\u{09BE}\u{0995}\u{09BE} \u{09A2}\u{09BE}\u{0995}\u{09BE} \u{09A2}\u{09BE}\u{0995}\u{09BE} \u{09A2}\u{09BE}\u{0995}\u{09BE} \u{09A2}\u{09BE}\u{0995}\u{09BE} \u{09A2}\u{09BE}\u{0995}\u{09BE} \u{09A2}\u{09BE}\u{0995}\u{09BE} \u{09A2}\u{09BE}\u{0995}\u{09BE} \u{09A2}\u{09BE}\u{0995}\u{09BE} ";
    try line(&out.writer, "SUMMARY:{f}", .{Text{ .s = title }});
    var lines = std.mem.splitSequence(u8, out.written(), "\r\n");
    var joined: std.ArrayList(u8) = .empty;
    defer joined.deinit(std.testing.allocator);
    var first = true;
    while (lines.next()) |l| {
        if (l.len == 0) continue;
        try std.testing.expect(l.len <= 75);
        try std.testing.expect(std.unicode.utf8ValidateSlice(l));
        try joined.appendSlice(std.testing.allocator, if (first) l else l[1..]);
        first = false;
    }
    try std.testing.expectEqualStrings("SUMMARY:" ++ title, joined.items);
}

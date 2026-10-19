const std = @import("std");
const zx = @import("zx");
const slots = @import("slots.zig");

const Rules = slots.Rules;
const Weekday = slots.Weekday;

const int_fields = .{ "slot_minutes", "day_start", "day_end", "horizon_days", "min_notice_hours" };

/// Missing or invalid settings fall back to defaults so /schedule never breaks.
pub fn load(arena: std.mem.Allocator) Rules {
    var rules: Rules = .{};
    const rows = zx.db.rows(arena, struct { key: []const u8, val: []const u8 },
        \\SELECT key, val FROM settings WHERE key LIKE 'schedule_%'
    , .{}) catch |err| {
        zx.log.warn("schedule: failed to load settings: {any}", .{err});
        return rules;
    };
    for (rows) |row| {
        const name = row.key["schedule_".len..];
        if (std.mem.eql(u8, name, "open_days")) rules.open_days = parseDays(row.val);
        inline for (int_fields) |field| {
            if (std.mem.eql(u8, name, field)) @field(rules, field) = std.fmt.parseInt(i64, row.val, 10) catch @field(rules, field);
        }
    }
    validate(rules) catch return .{};
    return rules;
}

pub fn save(arena: std.mem.Allocator, rules: Rules) !void {
    try validate(rules);
    inline for (int_fields) |field| {
        try put("schedule_" ++ field, try std.fmt.allocPrint(arena, "{d}", .{@field(rules, field)}));
    }

    var days: std.ArrayList(u8) = .empty;
    var it = rules.open_days.iterator();
    while (it.next()) |day| {
        if (days.items.len > 0) try days.append(arena, ',');
        try days.appendSlice(arena, @tagName(day));
    }
    try put("schedule_open_days", days.items);
}

fn put(key: []const u8, val: []const u8) !void {
    _ = try zx.db.run(
        \\INSERT INTO settings (key, val) VALUES (?1, ?2)
        \\ON CONFLICT (key) DO UPDATE SET val = excluded.val
    , .{ key, val });
}

fn validate(rules: Rules) error{InvalidRules}!void {
    const ok = rules.slot_minutes >= 5 and rules.slot_minutes <= 240 and
        rules.day_start >= 0 and rules.day_start + rules.slot_minutes <= rules.day_end and
        rules.day_end <= 24 * 60 and
        rules.open_days.count() > 0 and
        rules.horizon_days >= 1 and rules.horizon_days <= 90 and
        rules.min_notice_hours >= 0 and rules.min_notice_hours <= 24 * 14;
    if (!ok) return error.InvalidRules;
}

fn parseDays(val: []const u8) std.EnumSet(Weekday) {
    var set: std.EnumSet(Weekday) = .empty;
    var it = std.mem.tokenizeScalar(u8, val, ',');
    while (it.next()) |name| {
        if (std.meta.stringToEnum(Weekday, name)) |day| set.insert(day);
    }
    return set;
}

/// `HH:MM` (from `<input type="time">`) to minutes after midnight.
pub fn parseTimeOfDay(text: []const u8) ?i64 {
    var parts = std.mem.splitScalar(u8, text, ':');
    const h = std.fmt.parseInt(u8, parts.next() orelse return null, 10) catch return null;
    const m = std.fmt.parseInt(u8, parts.next() orelse return null, 10) catch return null;
    if (h > 24 or m > 59) return null;
    return @as(i64, h) * 60 + m;
}

pub fn formatTimeOfDay(arena: std.mem.Allocator, minutes: i64) []const u8 {
    const m: u64 = @intCast(minutes);
    return std.fmt.allocPrint(arena, "{d:0>2}:{d:0>2}", .{ m / 60, m % 60 }) catch "";
}

/// Where `/meet` redirects when a booking has no link of its own.
pub fn defaultMeetingUrl(arena: std.mem.Allocator) ?[]const u8 {
    const row = zx.db.row(arena, struct { val: []const u8 },
        \\SELECT val FROM credentials WHERE cat = 'caldav_meeting_url' LIMIT 1
    , .{}) catch return null;
    return if (row) |r| r.val else null;
}

pub fn setDefaultMeetingUrl(url: []const u8) !void {
    _ = try zx.db.run("DELETE FROM credentials WHERE cat = 'caldav_meeting_url'", .{});
    if (url.len > 0) _ = try zx.db.run("INSERT INTO credentials (cat, val) VALUES ('caldav_meeting_url', ?1)", .{url});
}

pub fn isHttpUrl(url: []const u8) bool {
    if (url.len > 500) return false;
    for (url) |ch| if (ch <= ' ' or ch == '"' or ch == '<' or ch == '>') return false;
    return std.mem.startsWith(u8, url, "https://") or std.mem.startsWith(u8, url, "http://");
}

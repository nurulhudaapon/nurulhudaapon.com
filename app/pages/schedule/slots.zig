const std = @import("std");

pub const Weekday = enum(u3) { sun, mon, tue, wed, thu, fri, sat };

pub const config = struct {
    pub const timezone = "Asia/Dhaka";
    pub const timezone_label = "GMT+6";
    pub const utc_offset_s: i64 = 6 * std.time.s_per_hour;
};

pub const Rules = struct {
    slot_minutes: i64 = 30,
    /// Minutes after local midnight.
    day_start: i64 = 10 * 60,
    day_end: i64 = 18 * 60,
    open_days: std.EnumSet(Weekday) = .initMany(&.{ .sun, .mon, .tue, .wed, .thu }),
    horizon_days: i64 = 14,
    min_notice_hours: i64 = 12,

    pub fn slotSeconds(self: Rules) i64 {
        return self.slot_minutes * std.time.s_per_min;
    }

    fn minNoticeSeconds(self: Rules) i64 {
        return self.min_notice_hours * std.time.s_per_hour;
    }
};

pub const Interval = struct {
    start: i64,
    end: i64,

    pub fn overlaps(a: Interval, b: Interval) bool {
        return a.start < b.end and b.start < a.end;
    }
};

pub const Day = struct {
    date: []const u8,
    weekday: []const u8,
    month: []const u8,
    day_of_month: u8,
    slots: []const Interval,
};

pub const weekday_names = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
const month_names = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

pub const LocalDate = struct {
    year: u16,
    month: u4,
    day: u5,
    weekday: Weekday,
    minute_of_day: u16,

    pub fn of(unix: i64) LocalDate {
        return at(unix, config.utc_offset_s);
    }

    pub fn at(unix: i64, utc_offset_s: i64) LocalDate {
        const secs: std.time.epoch.EpochSeconds = .{ .secs = @intCast(unix + utc_offset_s) };
        const epoch_day = secs.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_secs = secs.getDaySeconds();
        return .{
            .year = year_day.year,
            .month = month_day.month.numeric(),
            .day = month_day.day_index + 1,
            // 1970-01-01 was a Thursday.
            .weekday = @fromBackingInt(@intCast((epoch_day.day + 4) % 7)),
            .minute_of_day = @as(u16, day_secs.getHoursIntoDay()) * 60 + day_secs.getMinutesIntoHour(),
        };
    }

    pub fn weekdayName(self: LocalDate) []const u8 {
        return weekday_names[@backingInt(self.weekday)];
    }

    pub fn monthName(self: LocalDate) []const u8 {
        return month_names[self.month - 1];
    }
};

pub fn horizon(rules: Rules, now: i64) Interval {
    const local_midnight = @divFloor(now + config.utc_offset_s, std.time.s_per_day) * std.time.s_per_day;
    const start = local_midnight - config.utc_offset_s;
    return .{ .start = start, .end = start + (rules.horizon_days + 1) * std.time.s_per_day };
}

pub fn availableDays(allocator: std.mem.Allocator, rules: Rules, now: i64, busy: []const Interval) ![]const Day {
    const range = horizon(rules, now);
    const earliest = now + rules.minNoticeSeconds();
    const slot_s = rules.slotSeconds();

    var days: std.ArrayList(Day) = .empty;
    var day_start = range.start;
    while (day_start < range.end) : (day_start += std.time.s_per_day) {
        const local = LocalDate.of(day_start);
        if (!rules.open_days.contains(local.weekday)) continue;

        var free: std.ArrayList(Interval) = .empty;
        var t = day_start + rules.day_start * std.time.s_per_min;
        const close = day_start + rules.day_end * std.time.s_per_min;
        while (t + slot_s <= close) : (t += slot_s) {
            const slot: Interval = .{ .start = t, .end = t + slot_s };
            if (slot.start >= earliest and !isBusy(slot, busy)) try free.append(allocator, slot);
        }

        try days.append(allocator, .{
            .date = try allocator.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ local.year, local.month, local.day }),
            .weekday = local.weekdayName(),
            .month = local.monthName(),
            .day_of_month = local.day,
            .slots = try free.toOwnedSlice(allocator),
        });
    }
    return days.toOwnedSlice(allocator);
}

pub fn isBusy(slot: Interval, busy: []const Interval) bool {
    for (busy) |b| if (slot.overlaps(b)) return true;
    return false;
}

pub fn isBookable(rules: Rules, now: i64, start: i64) bool {
    if (start < now + rules.minNoticeSeconds() or start + rules.slotSeconds() > horizon(rules, now).end) return false;
    const local = LocalDate.of(start);
    const minute: i64 = local.minute_of_day;
    return rules.open_days.contains(local.weekday) and
        @mod(minute - rules.day_start, rules.slot_minutes) == 0 and
        minute >= rules.day_start and
        minute + rules.slot_minutes <= rules.day_end;
}

pub fn formatTime(allocator: std.mem.Allocator, unix: i64, utc_offset_s: i64) ![]const u8 {
    const m = LocalDate.at(unix, utc_offset_s).minute_of_day;
    return allocator.print("{d:0>2}:{d:0>2}", .{ m / 60, m % 60 });
}

pub fn formatTime12(allocator: std.mem.Allocator, unix: i64, utc_offset_s: i64) ![]const u8 {
    const m = LocalDate.at(unix, utc_offset_s).minute_of_day;
    const h = m / 60;
    const h12 = if (h % 12 == 0) 12 else h % 12;
    return allocator.print("{d}:{d:0>2} {s}", .{ h12, m % 60, if (h < 12) "AM" else "PM" });
}

pub fn formatOffset(allocator: std.mem.Allocator, utc_offset_s: i64) ![]const u8 {
    const sign: u8 = if (utc_offset_s < 0) '-' else '+';
    const minutes: u64 = @abs(utc_offset_s) / 60;
    if (minutes % 60 == 0) return allocator.print("GMT{c}{d}", .{ sign, minutes / 60 });
    return allocator.print("GMT{c}{d}:{d:0>2}", .{ sign, minutes / 60, minutes % 60 });
}

pub fn formatDate(allocator: std.mem.Allocator, unix: i64, utc_offset_s: i64) ![]const u8 {
    const d = LocalDate.at(unix, utc_offset_s);
    return allocator.print("{s}, {s} {d}", .{ d.weekdayName(), d.monthName(), d.day });
}

const tue_oct20_2am_dhaka: i64 = 1792440000;
const thu_oct22_10am_dhaka: i64 = 1792641600;

test horizon {
    const local = LocalDate.of(horizon(.{}, tue_oct20_2am_dhaka).start);
    try std.testing.expectEqual(0, local.minute_of_day);
    try std.testing.expectEqual(20, local.day);
}

test isBookable {
    const now = tue_oct20_2am_dhaka;
    const rules: Rules = .{};
    const half_hour = 30 * std.time.s_per_min;
    try std.testing.expect(isBookable(rules, now, thu_oct22_10am_dhaka));
    try std.testing.expect(!isBookable(rules, now, thu_oct22_10am_dhaka + 15 * std.time.s_per_min));
    try std.testing.expect(!isBookable(rules, now, thu_oct22_10am_dhaka - half_hour));
    try std.testing.expect(!isBookable(rules, now, thu_oct22_10am_dhaka + std.time.s_per_day));
    try std.testing.expect(!isBookable(rules, now, now + std.time.s_per_hour));

    // Slots are aligned to the start of the day, not the top of the hour.
    const late_start: Rules = .{ .day_start = 10 * 60 + 15, .slot_minutes = 45 };
    try std.testing.expect(isBookable(late_start, now, thu_oct22_10am_dhaka + 15 * std.time.s_per_min));
    try std.testing.expect(!isBookable(late_start, now, thu_oct22_10am_dhaka + 45 * std.time.s_per_min));
}

test formatTime12 {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const offset = config.utc_offset_s;
    try std.testing.expectEqualStrings("10:00 AM", try formatTime12(a, thu_oct22_10am_dhaka, offset));
    try std.testing.expectEqualStrings("12:30 PM", try formatTime12(a, thu_oct22_10am_dhaka + 150 * std.time.s_per_min, offset));
    try std.testing.expectEqualStrings("12:00 AM", try formatTime12(a, thu_oct22_10am_dhaka - 10 * std.time.s_per_hour, offset));
    try std.testing.expectEqualStrings("GMT+6", try formatOffset(a, offset));
    try std.testing.expectEqualStrings("GMT-4", try formatOffset(a, -4 * std.time.s_per_hour));
    try std.testing.expectEqualStrings("GMT+5:30", try formatOffset(a, 330 * std.time.s_per_min));
}

test availableDays {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const busy = [_]Interval{.{ .start = thu_oct22_10am_dhaka, .end = thu_oct22_10am_dhaka + std.time.s_per_hour }};
    const days = try availableDays(arena.allocator(), .{}, tue_oct20_2am_dhaka, &busy);
    const thu = for (days) |d| {
        if (std.mem.eql(u8, d.date, "2026-10-22")) break d;
    } else return error.TestUnexpectedResult;
    try std.testing.expectEqual(14, thu.slots.len);
    try std.testing.expectEqual(thu_oct22_10am_dhaka + std.time.s_per_hour, thu.slots[0].start);
}

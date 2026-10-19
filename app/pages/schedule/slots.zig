const std = @import("std");

pub const Weekday = enum(u3) { sun, mon, tue, wed, thu, fri, sat };

pub const config = struct {
    pub const timezone = "Asia/Dhaka";
    pub const timezone_label = "GMT+6";
    pub const utc_offset_s: i64 = 6 * std.time.s_per_hour;
    pub const slot_minutes: i64 = 30;
    pub const day_start_hour: i64 = 10;
    pub const day_end_hour: i64 = 18;
    pub const open_days: std.EnumSet(Weekday) = .initMany(&.{ .sun, .mon, .tue, .wed, .thu });
    pub const horizon_days: i64 = 14;
    pub const min_notice_s: i64 = 12 * std.time.s_per_hour;
};

pub const slot_s = config.slot_minutes * std.time.s_per_min;

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

const weekday_names = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
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

    fn weekdayName(self: LocalDate) []const u8 {
        return weekday_names[@backingInt(self.weekday)];
    }

    fn monthName(self: LocalDate) []const u8 {
        return month_names[self.month - 1];
    }
};

pub fn horizon(now: i64) Interval {
    const local_midnight = @divFloor(now + config.utc_offset_s, std.time.s_per_day) * std.time.s_per_day;
    const start = local_midnight - config.utc_offset_s;
    return .{ .start = start, .end = start + (config.horizon_days + 1) * std.time.s_per_day };
}

pub fn availableDays(allocator: std.mem.Allocator, now: i64, busy: []const Interval) ![]const Day {
    const range = horizon(now);
    const earliest = now + config.min_notice_s;

    var days: std.ArrayList(Day) = .empty;
    var day_start = range.start;
    while (day_start < range.end) : (day_start += std.time.s_per_day) {
        const local = LocalDate.of(day_start);
        if (!config.open_days.contains(local.weekday)) continue;

        var free: std.ArrayList(Interval) = .empty;
        var t = day_start + config.day_start_hour * std.time.s_per_hour;
        const close = day_start + config.day_end_hour * std.time.s_per_hour;
        while (t + slot_s <= close) : (t += slot_s) {
            const slot: Interval = .{ .start = t, .end = t + slot_s };
            if (slot.start >= earliest and !isBusy(slot, busy)) try free.append(allocator, slot);
        }

        try days.append(allocator, .{
            .date = try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{ local.year, local.month, local.day }),
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

pub fn isBookable(now: i64, start: i64) bool {
    if (start < now + config.min_notice_s or start + slot_s > horizon(now).end) return false;
    const local = LocalDate.of(start);
    const minute: i64 = local.minute_of_day;
    return config.open_days.contains(local.weekday) and
        @mod(minute, config.slot_minutes) == 0 and
        minute >= config.day_start_hour * 60 and
        minute + config.slot_minutes <= config.day_end_hour * 60;
}

pub fn formatTime(allocator: std.mem.Allocator, unix: i64, utc_offset_s: i64) ![]const u8 {
    const m = LocalDate.at(unix, utc_offset_s).minute_of_day;
    return std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2}", .{ m / 60, m % 60 });
}

pub fn formatDate(allocator: std.mem.Allocator, unix: i64, utc_offset_s: i64) ![]const u8 {
    const d = LocalDate.at(unix, utc_offset_s);
    return std.fmt.allocPrint(allocator, "{s}, {s} {d}", .{ d.weekdayName(), d.monthName(), d.day });
}

const tue_oct20_2am_dhaka: i64 = 1792440000;
const thu_oct22_10am_dhaka: i64 = 1792641600;

test horizon {
    const local = LocalDate.of(horizon(tue_oct20_2am_dhaka).start);
    try std.testing.expectEqual(0, local.minute_of_day);
    try std.testing.expectEqual(20, local.day);
}

test isBookable {
    const now = tue_oct20_2am_dhaka;
    try std.testing.expect(isBookable(now, thu_oct22_10am_dhaka));
    try std.testing.expect(!isBookable(now, thu_oct22_10am_dhaka + 15 * std.time.s_per_min));
    try std.testing.expect(!isBookable(now, thu_oct22_10am_dhaka - slot_s));
    try std.testing.expect(!isBookable(now, thu_oct22_10am_dhaka + std.time.s_per_day));
    try std.testing.expect(!isBookable(now, now + std.time.s_per_hour));
}

test availableDays {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const busy = [_]Interval{.{ .start = thu_oct22_10am_dhaka, .end = thu_oct22_10am_dhaka + std.time.s_per_hour }};
    const days = try availableDays(arena.allocator(), tue_oct20_2am_dhaka, &busy);
    const thu = for (days) |d| {
        if (std.mem.eql(u8, d.date, "2026-10-22")) break d;
    } else return error.TestUnexpectedResult;
    try std.testing.expectEqual(14, thu.slots.len);
    try std.testing.expectEqual(thu_oct22_10am_dhaka + std.time.s_per_hour, thu.slots[0].start);
}

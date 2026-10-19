const std = @import("std");
const zx = @import("zx");
const slots = @import("slots.zig");
const ical = @import("ical.zig");

pub const Credentials = struct {
    username: []const u8,
    password: []const u8,
    calendar_url: []const u8,
    organizer_email: []const u8,
    meeting_url: ?[]const u8,
};

pub fn loadCredentials(allocator: std.mem.Allocator) !?Credentials {
    const rows = try zx.db.rows(allocator, struct { cat: []const u8, val: []const u8 },
        \\SELECT cat, val FROM credentials WHERE cat LIKE 'caldav_%'
    , .{});

    var found: struct {
        username: ?[]const u8 = null,
        password: ?[]const u8 = null,
        calendar_url: ?[]const u8 = null,
        organizer_email: ?[]const u8 = null,
        meeting_url: ?[]const u8 = null,
    } = .{};
    for (rows) |row| inline for (comptime std.meta.fieldNames(@TypeOf(found))) |name| {
        if (std.mem.eql(u8, row.cat, "caldav_" ++ name)) @field(found, name) = row.val;
    };

    const username = found.username orelse return null;
    return .{
        .username = username,
        .password = found.password orelse return null,
        .calendar_url = found.calendar_url orelse return null,
        .organizer_email = found.organizer_email orelse username,
        .meeting_url = found.meeting_url,
    };
}

const cache_key = "busy";

pub fn busy(allocator: std.mem.Allocator, creds: Credentials, range: slots.Interval, use_cache: bool) ![]const slots.Interval {
    const kv = zx.kv.scoped(.schedule);
    if (use_cache) if (try kv.get(allocator, cache_key)) |cached| {
        if (zx.util.zxon.parse([]const slots.Interval, allocator, cached, .{})) |intervals| return intervals else |_| {}
    };

    const intervals = try ical.busyIntervals(allocator, try report(allocator, creds, range), range);
    var encoded: std.Io.Writer.Allocating = .init(allocator);
    try zx.util.zxon.serialize(intervals, &encoded.writer, .{});
    kv.put(cache_key, encoded.written(), .{ .ttl = .fromSeconds(120) }) catch |err|
        zx.log.warn("schedule: failed to cache busy times: {any}", .{err});
    return intervals;
}

pub fn invalidateBusy() void {
    zx.kv.scoped(.schedule).delete(cache_key) catch {};
}

fn report(allocator: std.mem.Allocator, creds: Credentials, range: slots.Interval) ![]const u8 {
    var start_buf: [16]u8 = undefined;
    var end_buf: [16]u8 = undefined;
    const body = try std.fmt.allocPrint(allocator,
        \\<?xml version="1.0" encoding="utf-8"?>
        \\<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
        \\  <D:prop><C:calendar-data/></D:prop>
        \\  <C:filter>
        \\    <C:comp-filter name="VCALENDAR">
        \\      <C:comp-filter name="VEVENT">
        \\        <C:time-range start="{s}" end="{s}"/>
        \\      </C:comp-filter>
        \\    </C:comp-filter>
        \\  </C:filter>
        \\</C:calendar-query>
    , .{ formatUtc(&start_buf, range.start), formatUtc(&end_buf, range.end) });

    return send(allocator, creds, creds.calendar_url, "REPORT", &.{
        .{ .name = "Depth", .value = "1" },
        .{ .name = "Content-Type", .value = "application/xml; charset=utf-8" },
    }, body);
}

pub fn putEvent(allocator: std.mem.Allocator, creds: Credentials, resource: []const u8, ics: []const u8) !void {
    _ = try send(allocator, creds, try eventUrl(allocator, creds, resource), "PUT", &.{
        .{ .name = "Content-Type", .value = "text/calendar; charset=utf-8" },
        .{ .name = "If-None-Match", .value = "*" },
    }, ics);
}

pub fn getEvent(allocator: std.mem.Allocator, creds: Credentials, resource: []const u8) ![]const u8 {
    return send(allocator, creds, try eventUrl(allocator, creds, resource), "GET", &.{}, null);
}

fn eventUrl(allocator: std.mem.Allocator, creds: Credentials, resource: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}/{s}.ics", .{ std.mem.trimEnd(u8, creds.calendar_url, "/"), resource });
}

const Header = zx.Fetch.RequestInit.Header;

fn send(
    allocator: std.mem.Allocator,
    creds: Credentials,
    url: []const u8,
    method: []const u8,
    extra_headers: []const Header,
    body: ?[]const u8,
) ![]const u8 {
    const base_headers = [_]Header{
        .{ .name = "Authorization", .value = try basicAuth(allocator, creds) },
        .{ .name = "User-Agent", .value = "nurulhudaapon.com" },
    };
    var response = (try zx.fetch(.blocking, allocator, url, .{
        .method_name = method,
        .headers = try std.mem.concat(allocator, Header, &.{ &base_headers, extra_headers }),
        .body = body,
        .timeout_ms = 15_000,
    })) orelse return error.NetworkError;
    defer response.deinit();
    if (!response.ok()) {
        zx.log.warn("schedule: {s} {s} failed status={d}", .{ method, url, response.status });
        return error.CalDavError;
    }
    return allocator.dupe(u8, try response.text());
}

fn basicAuth(allocator: std.mem.Allocator, creds: Credentials) ![]const u8 {
    const raw = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ creds.username, creds.password });
    const encoder = std.base64.standard.Encoder;
    const out = try allocator.alloc(u8, "Basic ".len + encoder.calcSize(raw.len));
    @memcpy(out[0.."Basic ".len], "Basic ");
    _ = encoder.encode(out["Basic ".len..], raw);
    return out;
}

fn formatUtc(buf: *[16]u8, unix: i64) []const u8 {
    const secs: std.time.epoch.EpochSeconds = .{ .secs = @intCast(unix) };
    const year_day = secs.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_secs = secs.getDaySeconds();
    return std.fmt.bufPrint(buf, "{d:0>4}{d:0>2}{d:0>2}T{d:0>2}{d:0>2}{d:0>2}Z", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_secs.getHoursIntoDay(),
        day_secs.getMinutesIntoHour(),
        day_secs.getSecondsIntoMinute(),
    }) catch unreachable;
}

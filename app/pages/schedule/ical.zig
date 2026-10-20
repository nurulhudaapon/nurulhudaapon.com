const std = @import("std");
const c = @import("ical");
const slots = @import("slots.zig");
const Interval = slots.Interval;

pub fn busyIntervals(allocator: std.mem.Allocator, multistatus: []const u8, range: Interval) ![]const Interval {
    var collector: Collector = .{ .allocator = allocator };
    errdefer collector.list.deinit(allocator);
    const utc = c.icaltimezone_get_utc_timezone();
    const range_start = c.icaltime_from_timet_with_zone(range.start, 0, utc);
    const range_end = c.icaltime_from_timet_with_zone(range.end, 0, utc);

    const end_marker = "END:VCALENDAR";
    var rest = multistatus;
    while (std.mem.indexOf(u8, rest, "BEGIN:VCALENDAR")) |begin| {
        const end = (std.mem.indexOfPos(u8, rest, begin, end_marker) orelse break) + end_marker.len;
        const text = try xmlUnescapeZ(allocator, rest[begin..end]);
        defer allocator.free(text);
        rest = rest[end..];

        const root = c.icalparser_parse_string(text.ptr) orelse continue;
        defer c.icalcomponent_free(root);

        var event = c.icalcomponent_get_first_component(root, c.ICAL_VEVENT_COMPONENT);
        while (event != null) : (event = c.icalcomponent_get_next_component(root, c.ICAL_VEVENT_COMPONENT)) {
            if (!blocksTime(event)) continue;
            // libical reads floating times and all-day dates as UTC; they mean local time.
            collector.shift = if (c.icalcomponent_get_dtstart(event).zone == null) -slots.config.utc_offset_s else 0;
            c.icalcomponent_foreach_recurrence(event, range_start, range_end, Collector.onSpan, &collector);
            if (collector.failed) return error.OutOfMemory;
        }
    }
    return collector.list.toOwnedSlice(allocator);
}

const Collector = struct {
    allocator: std.mem.Allocator,
    list: std.ArrayList(Interval) = .empty,
    shift: i64 = 0,
    failed: bool = false,

    fn onSpan(_: ?*c.icalcomponent, span: [*c]c.icaltime_span, data: ?*anyopaque) callconv(.c) void {
        const self: *Collector = @ptrCast(@alignCast(data));
        const s = span.*;
        if (s.is_busy == 0 or s.end <= s.start) return;
        self.list.append(self.allocator, .{ .start = s.start + self.shift, .end = s.end + self.shift }) catch {
            self.failed = true;
        };
    }
};

fn blocksTime(event: ?*c.icalcomponent) bool {
    if (c.icalcomponent_get_status(event) == c.ICAL_STATUS_CANCELLED) return false;
    const transp = c.icalcomponent_get_first_property(event, c.ICAL_TRANSP_PROPERTY);
    return transp == null or c.icalproperty_get_transp(transp) != c.ICAL_TRANSP_TRANSPARENT;
}

pub const NewEvent = struct {
    uid: []const u8,
    start: i64,
    end: i64,
    now: i64,
    summary: []const u8,
    description: []const u8,
    organizer_email: []const u8,
    organizer_name: []const u8,
    attendee_email: []const u8,
    attendee_name: []const u8,
    url: []const u8,
    meeting_url: ?[]const u8 = null,
};

const tz = slots.config;

const vtimezone = blk: {
    const minutes = @abs(tz.utc_offset_s) / 60;
    const offset = std.fmt.comptimePrint("{c}{d:0>2}{d:0>2}", .{ if (tz.utc_offset_s < 0) '-' else '+', minutes / 60, minutes % 60 });
    break :blk std.fmt.comptimePrint(
        "BEGIN:VCALENDAR\r\nBEGIN:VTIMEZONE\r\nTZID:{0s}\r\nBEGIN:STANDARD\r\nDTSTART:19700101T000000\r\n" ++
            "TZOFFSETFROM:{1s}\r\nTZOFFSETTO:{1s}\r\nTZNAME:{2s}\r\nEND:STANDARD\r\nEND:VTIMEZONE\r\nEND:VCALENDAR\r\n",
        .{ tz.timezone, offset, offset[0..3] },
    );
};

pub fn buildEvent(allocator: std.mem.Allocator, ev: NewEvent) ![]const u8 {
    var arena_state: std.heap.ArenaAllocator = .init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const utc = c.icaltimezone_get_utc_timezone();

    const cal = c.icalcomponent_new(c.ICAL_VCALENDAR_COMPONENT) orelse return error.OutOfMemory;
    defer c.icalcomponent_free(cal);
    c.icalcomponent_add_property(cal, c.icalproperty_new_version("2.0"));
    c.icalcomponent_add_property(cal, c.icalproperty_new_prodid("-//nurulhudaapon.com//Schedule//EN"));

    const zones = c.icalparser_parse_string(vtimezone) orelse return error.OutOfMemory;
    defer c.icalcomponent_free(zones);
    const zone = c.icalcomponent_get_first_component(zones, c.ICAL_VTIMEZONE_COMPONENT) orelse return error.OutOfMemory;
    c.icalcomponent_add_component(cal, c.icalcomponent_new_clone(zone));

    const event = c.icalcomponent_new(c.ICAL_VEVENT_COMPONENT) orelse return error.OutOfMemory;
    c.icalcomponent_add_component(cal, event);
    c.icalcomponent_add_property(event, c.icalproperty_new_uid(try cstr(arena, ev.uid)));
    c.icalcomponent_add_property(event, c.icalproperty_new_dtstamp(c.icaltime_from_timet_with_zone(ev.now, 0, utc)));
    c.icalcomponent_add_property(event, withTzid(c.icalproperty_new_dtstart(localTime(ev.start))));
    c.icalcomponent_add_property(event, withTzid(c.icalproperty_new_dtend(localTime(ev.end))));
    c.icalcomponent_add_property(event, c.icalproperty_new_summary(try cstr(arena, ev.summary)));
    c.icalcomponent_add_property(event, c.icalproperty_new_description(try cstr(arena, ev.description)));
    c.icalcomponent_add_property(event, c.icalproperty_new_status(c.ICAL_STATUS_CONFIRMED));
    c.icalcomponent_add_property(event, c.icalproperty_new_transp(c.ICAL_TRANSP_OPAQUE));
    c.icalcomponent_add_property(event, c.icalproperty_new_url(try cstr(arena, ev.url)));

    if (ev.meeting_url) |url| {
        const url_z = try cstr(arena, url);
        c.icalcomponent_add_property(event, c.icalproperty_new_location(url_z));
        const conference = c.icalproperty_new_conference(url_z);
        c.icalproperty_add_parameter(conference, c.icalparameter_new_value(c.ICAL_VALUE_URI));
        c.icalproperty_add_parameter(conference, c.icalparameter_new_feature(c.ICAL_FEATURE_VIDEO));
        c.icalproperty_add_parameter(conference, c.icalparameter_new_label("Join video call"));
        c.icalcomponent_add_property(event, conference);
    }

    const organizer = c.icalproperty_new_organizer(try mailto(arena, ev.organizer_email));
    c.icalproperty_add_parameter(organizer, c.icalparameter_new_cn(try cstr(arena, ev.organizer_name)));
    c.icalcomponent_add_property(event, organizer);

    const attendee = c.icalproperty_new_attendee(try mailto(arena, ev.attendee_email));
    c.icalproperty_add_parameter(attendee, c.icalparameter_new_cn(try cstr(arena, ev.attendee_name)));
    c.icalproperty_add_parameter(attendee, c.icalparameter_new_role(c.ICAL_ROLE_REQPARTICIPANT));
    c.icalproperty_add_parameter(attendee, c.icalparameter_new_partstat(c.ICAL_PARTSTAT_NEEDSACTION));
    c.icalproperty_add_parameter(attendee, c.icalparameter_new_rsvp(c.ICAL_RSVP_TRUE));
    c.icalcomponent_add_property(event, attendee);

    const out = c.icalcomponent_as_ical_string_r(cal) orelse return error.OutOfMemory;
    defer c.icalmemory_free_buffer(out);
    return allocator.dupe(u8, std.mem.span(out));
}

/// Floating (zone-less) local time; `withTzid` pins it to the owner's zone.
fn localTime(unix: i64) c.icaltimetype {
    return c.icaltime_from_timet_with_zone(unix + tz.utc_offset_s, 0, null);
}

fn withTzid(prop: ?*c.icalproperty) ?*c.icalproperty {
    c.icalproperty_add_parameter(prop, c.icalparameter_new_tzid(tz.timezone));
    return prop;
}

pub const Stored = struct { span: Interval, cancelled: bool };

/// `calendar_data` may still be XML-escaped from a CalDAV response.
pub fn storedEvent(allocator: std.mem.Allocator, calendar_data: []const u8) !?Stored {
    const end_marker = "END:VCALENDAR";
    const begin = std.mem.indexOf(u8, calendar_data, "BEGIN:VCALENDAR") orelse return null;
    const end = (std.mem.indexOfPos(u8, calendar_data, begin, end_marker) orelse return null) + end_marker.len;
    const text = try xmlUnescapeZ(allocator, calendar_data[begin..end]);
    defer allocator.free(text);

    const root = c.icalparser_parse_string(text.ptr) orelse return null;
    defer c.icalcomponent_free(root);
    const event = c.icalcomponent_get_first_component(root, c.ICAL_VEVENT_COMPONENT) orelse return null;
    const start = c.icalcomponent_get_dtstart(event);
    const finish = c.icalcomponent_get_dtend(event);
    if (c.icaltime_is_null_time(start) != 0 or c.icaltime_is_null_time(finish) != 0) return null;
    return .{
        .span = .{ .start = toUnix(start), .end = toUnix(finish) },
        .cancelled = c.icalcomponent_get_status(event) == c.ICAL_STATUS_CANCELLED,
    };
}

fn toUnix(t: c.icaltimetype) i64 {
    const shift: i64 = if (t.zone == null) -tz.utc_offset_s else 0;
    return c.icaltime_as_timet_with_zone(t, t.zone) + shift;
}

fn cstr(arena: std.mem.Allocator, s: []const u8) ![:0]const u8 {
    return arena.dupeSentinel(u8, s, 0);
}

fn mailto(arena: std.mem.Allocator, email: []const u8) ![:0]const u8 {
    return std.fmt.allocPrintSentinel(arena, "mailto:{s}", .{email}, 0);
}

const entities: std.StaticStringMap(u8) = .initComptime(.{
    .{ "amp", '&' }, .{ "lt", '<' }, .{ "gt", '>' }, .{ "quot", '"' }, .{ "apos", '\'' },
});

fn xmlUnescapeZ(allocator: std.mem.Allocator, s: []const u8) ![:0]u8 {
    var out: std.ArrayList(u8) = try .initCapacity(allocator, s.len + 1);
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '&') if (std.mem.indexOfScalarPos(u8, s, i, ';')) |semi| {
            if (decodeEntity(s[i + 1 .. semi])) |ch| {
                out.appendAssumeCapacity(ch);
                i = semi;
                continue;
            }
        };
        out.appendAssumeCapacity(s[i]);
    }
    return out.toOwnedSliceSentinel(allocator, 0);
}

fn decodeEntity(entity: []const u8) ?u8 {
    if (entities.get(entity)) |ch| return ch;
    if (entity.len < 2 or entity[0] != '#') return null;
    const hex = entity[1] == 'x' or entity[1] == 'X';
    return std.fmt.parseInt(u8, entity[if (hex) 2 else 1..], if (hex) 16 else 10) catch null;
}

const range_oct19_to_nov2: Interval = .{ .start = 1792368000, .end = 1793577600 };

test busyIntervals {
    const tue_oct20_11am_dhaka = 1792472400;
    const xml =
        "<multistatus xmlns=\"DAV:\"><response><propstat><prop>" ++
        "<calendar-data xmlns=\"urn:ietf:params:xml:ns:caldav\">BEGIN:VCALENDAR\r\n" ++
        "VERSION:2.0\r\nPRODID:test\r\n" ++
        "BEGIN:VTIMEZONE\r\nTZID:Asia/Dhaka\r\nBEGIN:STANDARD\r\nDTSTART:19700101T000000\r\n" ++
        "TZOFFSETFROM:+0600\r\nTZOFFSETTO:+0600\r\nTZNAME:+06\r\nEND:STANDARD\r\nEND:VTIMEZONE\r\n" ++
        "BEGIN:VEVENT\r\nUID:weekly\r\nDTSTAMP:20261001T000000Z\r\n" ++
        "DTSTART;TZID=Asia/Dhaka:20261020T110000\r\nDTEND;TZID=Asia/Dhaka:20261020T120000\r\n" ++
        "RRULE:FREQ=WEEKLY;COUNT=3\r\nSUMMARY:Standup &amp; sync\r\nEND:VEVENT\r\n" ++
        "BEGIN:VEVENT\r\nUID:cancelled\r\nDTSTAMP:20261001T000000Z\r\n" ++
        "DTSTART:20261021T040000Z\r\nDTEND:20261021T050000Z\r\nSTATUS:CANCELLED\r\nEND:VEVENT\r\n" ++
        "BEGIN:VEVENT\r\nUID:free\r\nDTSTAMP:20261001T000000Z\r\n" ++
        "DTSTART:20261022T040000Z\r\nDTEND:20261022T050000Z\r\nTRANSP:TRANSPARENT\r\nEND:VEVENT\r\n" ++
        "END:VCALENDAR\r\n</calendar-data></prop></propstat></response></multistatus>";

    const busy = try busyIntervals(std.testing.allocator, xml, range_oct19_to_nov2);
    defer std.testing.allocator.free(busy);
    const hour = std.time.s_per_hour;
    const week = std.time.s_per_week;
    try std.testing.expectEqualSlices(Interval, &.{
        .{ .start = tue_oct20_11am_dhaka, .end = tue_oct20_11am_dhaka + hour },
        .{ .start = tue_oct20_11am_dhaka + week, .end = tue_oct20_11am_dhaka + week + hour },
    }, busy);
}

test buildEvent {
    const thu_oct22_10am_dhaka = 1792641600;
    const half_hour = 30 * std.time.s_per_min;
    const ics = try buildEvent(std.testing.allocator, .{
        .uid = "abc@nurulhudaapon.com",
        .start = thu_oct22_10am_dhaka,
        .end = thu_oct22_10am_dhaka + half_hour,
        .now = thu_oct22_10am_dhaka,
        .summary = "Ada <> Nurul",
        .description = "Hello, world; notes",
        .organizer_email = "owner@example.com",
        .organizer_name = "Owner",
        .attendee_email = "ada@example.com",
        .attendee_name = "Ada",
        .url = "https://nurulhudaapon.com/schedule/abc",
        .meeting_url = "https://nurulhudaapon.com/meet?id=abc",
    });
    defer std.testing.allocator.free(ics);

    for ([_][]const u8{
        "TZID:Asia/Dhaka",
        "TZOFFSETTO:+0600",
        "DTSTART;TZID=Asia/Dhaka:20261022T100000",
        "DTEND;TZID=Asia/Dhaka:20261022T103000",
        "UID:abc@nurulhudaapon.com",
        "SUMMARY:Ada <> Nurul",
        "mailto:ada@example.com",
        "Hello\\, world\\; notes",
        "URL:https://nurulhudaapon.com/schedule/abc",
        "LOCATION:https://nurulhudaapon.com/meet?id=abc",
        "CONFERENCE;VALUE=URI;FEATURE=VIDEO;",
    }) |needle| try std.testing.expect(std.mem.indexOf(u8, ics, needle) != null);

    const stored = (try storedEvent(std.testing.allocator, ics)).?;
    try std.testing.expectEqual(Interval{ .start = thu_oct22_10am_dhaka, .end = thu_oct22_10am_dhaka + half_hour }, stored.span);
    try std.testing.expect(!stored.cancelled);

    const busy = try busyIntervals(std.testing.allocator, ics, range_oct19_to_nov2);
    defer std.testing.allocator.free(busy);
    try std.testing.expectEqualSlices(Interval, &.{
        .{ .start = thu_oct22_10am_dhaka, .end = thu_oct22_10am_dhaka + half_hour },
    }, busy);
}

test "all-day events block the whole local day" {
    const sat_oct24_midnight_dhaka = 1792778400;
    const xml =
        "<calendar-data>BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:test\r\n" ++
        "BEGIN:VEVENT\r\nUID:allday\r\nDTSTAMP:20261001T000000Z\r\n" ++
        "DTSTART;VALUE=DATE:20261024\r\nDTEND;VALUE=DATE:20261025\r\nTRANSP:OPAQUE\r\nEND:VEVENT\r\n" ++
        "END:VCALENDAR\r\n</calendar-data>";
    const busy = try busyIntervals(std.testing.allocator, xml, range_oct19_to_nov2);
    defer std.testing.allocator.free(busy);
    try std.testing.expectEqualSlices(Interval, &.{
        .{ .start = sat_oct24_midnight_dhaka, .end = sat_oct24_midnight_dhaka + std.time.s_per_day },
    }, busy);
}

test "storedEvent reads an event moved in the calendar app" {
    const thu_oct22_3pm_dhaka = 1792659600;
    const xml =
        "<response><href>/1/calendars/x/abc.ics</href><propstat><prop>" ++
        "<calendar-data>BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:iCloud\r\n" ++
        "BEGIN:VEVENT\r\nUID:abc@nurulhudaapon.com\r\nDTSTAMP:20261021T000000Z\r\n" ++
        "DTSTART:20261022T090000Z\r\nDURATION:PT45M\r\nSUMMARY:Ada &lt;&gt; Nurul\r\nEND:VEVENT\r\n" ++
        "END:VCALENDAR\r\n</calendar-data></prop></propstat></response>";
    const stored = (try storedEvent(std.testing.allocator, xml)).?;
    try std.testing.expectEqual(Interval{ .start = thu_oct22_3pm_dhaka, .end = thu_oct22_3pm_dhaka + 45 * std.time.s_per_min }, stored.span);
    try std.testing.expectEqual(null, try storedEvent(std.testing.allocator, "<response><status>HTTP/1.1 404 Not Found</status></response>"));
}

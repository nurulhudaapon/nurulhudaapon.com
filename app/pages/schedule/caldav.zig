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

/// Calendar data for each resource, null where the calendar didn't return it.
pub fn getEvents(allocator: std.mem.Allocator, creds: Credentials, resources: []const []const u8) ![]const ?[]const u8 {
    const base = std.mem.trimEnd(u8, urlPath(creds.calendar_url), "/");
    var body: std.Io.Writer.Allocating = .init(allocator);
    try body.writer.writeAll(
        \\<?xml version="1.0" encoding="utf-8"?>
        \\<C:calendar-multiget xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
        \\  <D:prop><C:calendar-data/></D:prop>
    );
    for (resources) |r| try body.writer.print("\n  <D:href>{s}/{s}.ics</D:href>", .{ base, r });
    try body.writer.writeAll("\n</C:calendar-multiget>\n");

    const xml = try send(allocator, creds, creds.calendar_url, "REPORT", &.{
        .{ .name = "Depth", .value = "1" },
        .{ .name = "Content-Type", .value = "application/xml; charset=utf-8" },
    }, body.written());

    const out = try allocator.alloc(?[]const u8, resources.len);
    @memset(out, null);
    for (resources, out) |r, *data| {
        // A <response> starts with its href, so its data runs to the closing tag.
        const name = try std.fmt.allocPrint(allocator, "/{s}.ics<", .{r});
        const at = std.mem.indexOf(u8, xml, name) orelse continue;
        const end = std.mem.indexOfPos(u8, xml, at, "response>") orelse xml.len;
        if (std.mem.indexOf(u8, xml[at..end], "BEGIN:VCALENDAR") != null) data.* = xml[at..end];
    }
    return out;
}

fn urlPath(url: []const u8) []const u8 {
    const scheme = std.mem.indexOf(u8, url, "://") orelse return url;
    const slash = std.mem.indexOfScalarPos(u8, url, scheme + 3, '/') orelse return "/";
    return url[slash..];
}

/// Deleting the organizer's copy makes iCloud send the attendee a cancellation.
pub fn deleteEvent(allocator: std.mem.Allocator, creds: Credentials, resource: []const u8) !void {
    _ = try send(allocator, creds, try eventUrl(allocator, creds, resource), "DELETE", &.{}, null);
}

fn eventUrl(allocator: std.mem.Allocator, creds: Credentials, resource: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}/{s}.ics", .{ std.mem.trimEnd(u8, creds.calendar_url, "/"), resource });
}

pub const Calendar = struct { name: []const u8, url: []const u8 };

/// Event calendars of the account: principal, then calendar home, then its calendars.
pub fn discoverCalendars(allocator: std.mem.Allocator, creds: Credentials, server: []const u8) ![]const Calendar {
    const principal_xml = try propfind(allocator, creds, server, "0", "<D:current-user-principal/>");
    const principal = try resolve(allocator, server, elementText(afterTag(principal_xml, "current-user-principal"), "href") orelse
        return error.NoPrincipal);

    const home_xml = try propfind(allocator, creds, principal, "0", "<C:calendar-home-set/>");
    const home = try resolve(allocator, principal, elementText(afterTag(home_xml, "calendar-home-set"), "href") orelse
        return error.NoCalendarHome);

    const list_xml = try propfind(allocator, creds, home, "1", "<D:displayname/><D:resourcetype/><C:supported-calendar-component-set/>");
    return parseCalendars(allocator, home, list_xml);
}

fn parseCalendars(allocator: std.mem.Allocator, home: []const u8, xml: []const u8) ![]const Calendar {
    var calendars: std.ArrayList(Calendar) = .empty;
    // Splitting on the tag name puts each <response> body in its own piece.
    var pieces = std.mem.splitSequence(u8, xml, "response>");
    while (pieces.next()) |piece| {
        const href = elementText(piece, "href") orelse continue;
        if (elementText(piece, "calendar") == null or std.mem.indexOf(u8, piece, "VEVENT") == null) continue;
        try calendars.append(allocator, .{
            .name = elementText(piece, "displayname") orelse href,
            .url = try resolve(allocator, home, href),
        });
    }
    return calendars.toOwnedSlice(allocator);
}

fn propfind(allocator: std.mem.Allocator, creds: Credentials, url: []const u8, depth: []const u8, comptime props: []const u8) ![]const u8 {
    return send(allocator, creds, url, "PROPFIND", &.{
        .{ .name = "Depth", .value = depth },
        .{ .name = "Content-Type", .value = "application/xml; charset=utf-8" },
    },
        \\<?xml version="1.0" encoding="utf-8"?>
        \\<D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><D:prop>
    ++ props ++
        \\</D:prop></D:propfind>
    );
}

fn resolve(allocator: std.mem.Allocator, base: []const u8, href: []const u8) ![]const u8 {
    if (std.mem.indexOf(u8, href, "://") != null) return href;
    const path_at = base.len - urlPath(base).len;
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ base[0..path_at], href });
}

fn afterTag(xml: []const u8, name: []const u8) []const u8 {
    const at = std.mem.indexOf(u8, xml, name) orelse return "";
    return xml[at + name.len ..];
}

/// Text of the first `<name>` or `<prefix:name>` element, "" when self-closing.
fn elementText(xml: []const u8, name: []const u8) ?[]const u8 {
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, xml, from, name)) |at| {
        from = at + name.len;
        const lt = std.mem.lastIndexOfScalar(u8, xml[0..at], '<') orelse continue;
        const prefix = xml[lt + 1 .. at];
        if (prefix.len > 0 and (prefix[prefix.len - 1] != ':' or std.mem.indexOfAny(u8, prefix, "/ >\"") != null)) continue;
        if (from >= xml.len or std.mem.indexOfScalar(u8, "> /", xml[from]) == null) continue;
        const gt = std.mem.indexOfScalarPos(u8, xml, from, '>') orelse return null;
        if (xml[gt - 1] == '/') return "";
        const end = std.mem.indexOfScalarPos(u8, xml, gt, '<') orelse return null;
        return std.mem.trim(u8, xml[gt + 1 .. end], " \t\r\n");
    }
    return null;
}

test parseCalendars {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const calendars = try parseCalendars(arena.allocator(), "https://p52-caldav.icloud.com/1/calendars/",
        \\<multistatus xmlns="DAV:"><response><href>/1/calendars/</href><propstat><prop>
        \\<resourcetype><collection/></resourcetype></prop></propstat></response>
        \\<response><href>/1/calendars/home/</href><propstat><prop><displayname>Home</displayname>
        \\<resourcetype><collection/><calendar xmlns="urn:ietf:params:xml:ns:caldav"/></resourcetype>
        \\<supported-calendar-component-set xmlns="urn:ietf:params:xml:ns:caldav"><comp name="VEVENT"/></supported-calendar-component-set>
        \\</prop></propstat></response>
        \\<d:response><d:href>/1/calendars/tasks/</d:href><d:propstat><d:prop><d:displayname>Reminders</d:displayname>
        \\<d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
        \\<c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set>
        \\</d:prop></d:propstat></d:response></multistatus>
    );
    try std.testing.expectEqual(1, calendars.len);
    try std.testing.expectEqualStrings("Home", calendars[0].name);
    try std.testing.expectEqualStrings("https://p52-caldav.icloud.com/1/calendars/home/", calendars[0].url);

    try std.testing.expectEqualStrings("/1/principal/", elementText(afterTag(
        "<d:current-user-principal><d:href>/1/principal/</d:href></d:current-user-principal>",
        "current-user-principal",
    ), "href").?);
    try std.testing.expectEqualStrings("https://p52-caldav.icloud.com:443/1/", try resolve(arena.allocator(), "https://caldav.icloud.com/", "https://p52-caldav.icloud.com:443/1/"));
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
        if (response.status == 404) return error.NotFound;
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

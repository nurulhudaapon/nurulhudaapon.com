// Local only: seeds non-secret config from `zx.secrets` (`.env` + process env).
// CalDAV, IBKR, GitHub, MCP and OAuth secrets are read live by `db/credentials.zig`.
// Without CALDAV_CALENDAR_URL the calendar is discovered, picked by CALDAV_CALENDAR
// (name). Prod uses /admin/settings instead.
const std = @import("std");
const zx = @import("zx");
const caldav = @import("schedule.zig").caldav;
const credentials = @import("db/credentials.zig");
const put = credentials.put;

const icloud = "https://caldav.icloud.com/";

pub fn load(init: zx.Init) void {
    if (zx.platform.isWasm() or @TypeOf(init) != std.process.Init) return;

    var arena_state: std.heap.ArenaAllocator = .init(zx.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    apply(arena, init.io) catch |err| zx.log.err("env: failed to set up credentials: {any}", .{err});
}

fn secret(arena: std.mem.Allocator, name: []const u8) ?[]const u8 {
    const val = zx.secrets.get(arena, name) catch return null;
    return if (val) |v| if (v.len > 0) v else null else null;
}

fn apply(arena: std.mem.Allocator, io: std.Io) !void {
    if (secret(arena, "MEET_LINK")) |url| try put("caldav_meeting_url", url);
    if (secret(arena, "IBKR_FLEX_QUERY_ID")) |id| try put("ibkr_flex_query_id", id);
    if (secret(arena, "OAUTH_GITHUB_ALLOWED")) |ids| try put("oauth_github_allowed", ids);

    const user = secret(arena, "CALDAV_USER") orelse return;
    const pass = secret(arena, "CALDAV_PASS") orelse return;
    try put("caldav_organizer_email", secret(arena, "CALDAV_ORGANIZER_EMAIL") orelse user);

    if (secret(arena, "CALDAV_CALENDAR_URL")) |url| return put("caldav_calendar_url", url);
    // Kept while it's still one of this account's calendars
    const current = try stored(arena, "caldav_calendar_url");

    const client: caldav.Client = .{ .arena = arena, .io = io, .creds = .{
        .username = user,
        .password = pass,
        .calendar_url = icloud,
        .organizer_email = user,
        .meeting_url = null,
    } };
    const calendars = try client.discover(icloud);
    if (current) |url| for (calendars) |cal| {
        if (caldav.sameCalendar(cal.url, url)) return;
    };
    if (current) |url| zx.log.warn("env: calendar {s} no longer exists, picking another", .{url});

    const calendar = pick(calendars, user, secret(arena, "CALDAV_CALENDAR")) orelse return;
    try put("caldav_calendar_url", calendar.url);
    zx.log.info("env: using calendar \"{s}\" for {s} ({s})", .{ calendar.name, user, calendar.url });
}

fn pick(calendars: []const caldav.Calendar, user: []const u8, wanted: ?[]const u8) ?caldav.Calendar {
    if (calendars.len == 0) {
        zx.log.warn("env: no event calendars found for {s}", .{user});
        return null;
    }
    if (wanted) |name| for (calendars) |cal| {
        if (std.ascii.eqlIgnoreCase(cal.name, name)) return cal;
    };
    for (calendars) |cal| zx.log.info("env: calendar \"{s}\" {s}", .{ cal.name, cal.url });
    if (wanted) |name| {
        zx.log.warn("env: no calendar named \"{s}\", set CALDAV_CALENDAR to one listed above", .{name});
        return null;
    }
    zx.log.info("env: set CALDAV_CALENDAR to pick another calendar", .{});
    return calendars[0];
}

fn stored(arena: std.mem.Allocator, cat: []const u8) !?[]const u8 {
    const row = try zx.db.row(arena, struct { val: []const u8 }, "SELECT val FROM credentials WHERE cat = ?1 LIMIT 1", .{cat});
    return if (row) |r| r.val else null;
}

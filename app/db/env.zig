//! Local only: fills `credentials` from `.env`, overridden by the process environment.
//! CALDAV_USER, CALDAV_PASS and MEET_LINK; optionally CALDAV_CALENDAR_URL (else
//! discovered), CALDAV_CALENDAR (name to pick) and CALDAV_ORGANIZER_EMAIL.
//! GITHUB_TOKEN, IBKR_FLEX_TOKEN, IBKR_FLEX_QUERY_ID, MCP_TOKEN. Prefer /admin/settings in prod.
//! OAUTH_GITHUB_CLIENT_ID, OAUTH_GITHUB_CLIENT_SECRET and OAUTH_GITHUB_ALLOWED (account ids) for admin sign-in.
const std = @import("std");
const zx = @import("zx");
const caldav = @import("../pages/schedule/caldav.zig");
const github = @import("../pages/dev/github.zig");

const icloud = "https://caldav.icloud.com/";

pub fn load(init: zx.Init) void {
    if (zx.platform.isWasm() or @TypeOf(init) != std.process.Init) return;

    var arena_state: std.heap.ArenaAllocator = .init(zx.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const vars = read(arena, init) catch |err| {
        zx.log.warn("env: failed to read .env: {any}", .{err});
        return;
    };
    apply(arena, vars) catch |err| zx.log.err("env: failed to set up credentials: {any}", .{err});
}

const Vars = std.StringHashMapUnmanaged([]const u8);
const names = .{ "CALDAV_USER", "CALDAV_PASS", "CALDAV_CALENDAR_URL", "CALDAV_CALENDAR", "CALDAV_ORGANIZER_EMAIL", "MEET_LINK", "GITHUB_TOKEN", "IBKR_FLEX_TOKEN", "IBKR_FLEX_QUERY_ID", "MCP_TOKEN", "OAUTH_GITHUB_CLIENT_ID", "OAUTH_GITHUB_CLIENT_SECRET", "OAUTH_GITHUB_ALLOWED" };

fn read(arena: std.mem.Allocator, init: std.process.Init) !Vars {
    var vars: Vars = .empty;
    if (std.Io.Dir.cwd().readFileAlloc(init.io, ".env", arena, .limited(64 * 1024))) |text| {
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |raw| {
            var line = std.mem.trim(u8, raw, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;
            if (std.mem.startsWith(u8, line, "export ")) line = line["export ".len..];
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            var val = std.mem.trim(u8, line[eq + 1 ..], " \t");
            if (val.len >= 2 and (val[0] == '"' or val[0] == '\'') and val[val.len - 1] == val[0]) val = val[1 .. val.len - 1];
            if (val.len > 0) try vars.put(arena, std.mem.trim(u8, line[0..eq], " \t"), val);
        }
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }
    inline for (names) |name| {
        if (init.environ_map.get(name)) |val| if (val.len > 0) try vars.put(arena, name, val);
    }
    return vars;
}

fn apply(arena: std.mem.Allocator, vars: Vars) !void {
    if (vars.get("GITHUB_TOKEN")) |token| {
        try put("github_token", token);
        try github.setToken(token);
    }
    if (vars.get("MCP_TOKEN")) |token| try put("mcp_token", token);
    if (vars.get("MEET_LINK")) |url| try put("caldav_meeting_url", url);
    if (vars.get("IBKR_FLEX_TOKEN")) |token| try put("ibkr_flex_token", token);
    if (vars.get("IBKR_FLEX_QUERY_ID")) |id| try put("ibkr_flex_query_id", id);
    if (vars.get("OAUTH_GITHUB_CLIENT_ID")) |id| try put("oauth_github_client_id", id);
    if (vars.get("OAUTH_GITHUB_CLIENT_SECRET")) |secret| try put("oauth_github_client_secret", secret);
    if (vars.get("OAUTH_GITHUB_ALLOWED")) |ids| try put("oauth_github_allowed", ids);

    const user = vars.get("CALDAV_USER") orelse return;
    const pass = vars.get("CALDAV_PASS") orelse return;
    const unchanged = if (try stored(arena, "caldav_username")) |u| std.mem.eql(u8, u, user) else false;
    try put("caldav_username", user);
    try put("caldav_password", pass);
    try put("caldav_organizer_email", vars.get("CALDAV_ORGANIZER_EMAIL") orelse user);

    if (vars.get("CALDAV_CALENDAR_URL")) |url| return put("caldav_calendar_url", url);
    if (unchanged and try stored(arena, "caldav_calendar_url") != null) return;

    const calendar = try discover(arena, user, pass, vars.get("CALDAV_CALENDAR")) orelse return;
    try put("caldav_calendar_url", calendar.url);
    zx.log.info("env: using calendar \"{s}\" for {s} ({s})", .{ calendar.name, user, calendar.url });
}

fn discover(arena: std.mem.Allocator, user: []const u8, pass: []const u8, wanted: ?[]const u8) !?caldav.Calendar {
    const calendars = try caldav.discoverCalendars(arena, .{
        .username = user,
        .password = pass,
        .calendar_url = icloud,
        .organizer_email = user,
        .meeting_url = null,
    }, icloud);
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

fn put(cat: []const u8, val: []const u8) !void {
    _ = try zx.db.run("DELETE FROM credentials WHERE cat = ?1", .{cat});
    _ = try zx.db.run("INSERT INTO credentials (cat, val) VALUES (?1, ?2)", .{ cat, val });
}

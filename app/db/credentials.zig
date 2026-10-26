const std = @import("std");
const zx = @import("zx");
const github = @import("../pages/dev/github.zig");

pub fn get(arena: std.mem.Allocator, cat: []const u8) ?[]const u8 {
    const row = zx.db.row(arena, struct { val: []const u8 },
        \\SELECT val FROM credentials WHERE cat = ?1 LIMIT 1
    , .{cat}) catch return null;
    return if (row) |r| r.val else null;
}

pub fn put(cat: []const u8, val: []const u8) !void {
    _ = try zx.db.run("DELETE FROM credentials WHERE cat = ?1", .{cat});
    if (val.len > 0) _ = try zx.db.run("INSERT INTO credentials (cat, val) VALUES (?1, ?2)", .{ cat, val });
}

pub fn putUnlessEmpty(cat: []const u8, val: []const u8) !void {
    const trimmed = std.mem.trim(u8, val, " \t\r\n");
    if (trimmed.len == 0) return;
    try put(cat, trimmed);
}

pub fn remove(cat: []const u8) !void {
    _ = try zx.db.run("DELETE FROM credentials WHERE cat = ?1", .{cat});
}

pub fn has(arena: std.mem.Allocator, cat: []const u8) bool {
    return get(arena, cat) != null;
}

pub fn applyRuntime(arena: std.mem.Allocator) void {
    if (get(arena, "github_token")) |token| {
        github.setToken(token) catch |err| zx.log.warn("credentials: github token: {any}", .{err});
    }
}

pub const Ibkr = struct {
    token: []const u8,
    query_id: []const u8,
};

pub fn loadIbkr(arena: std.mem.Allocator) ?Ibkr {
    const token = get(arena, "ibkr_flex_token") orelse return null;
    const query_id = get(arena, "ibkr_flex_query_id") orelse return null;
    if (token.len == 0 or query_id.len == 0) return null;
    return .{ .token = token, .query_id = query_id };
}

pub const CaldavForm = struct {
    username: []const u8 = "",
    password_set: bool = false,
    calendar_url: []const u8 = "",
    organizer_email: []const u8 = "",
    meeting_url: []const u8 = "",
};

pub fn loadCaldavForm(arena: std.mem.Allocator) CaldavForm {
    return .{
        .username = get(arena, "caldav_username") orelse "",
        .password_set = has(arena, "caldav_password"),
        .calendar_url = get(arena, "caldav_calendar_url") orelse "",
        .organizer_email = get(arena, "caldav_organizer_email") orelse "",
        .meeting_url = get(arena, "caldav_meeting_url") orelse "",
    };
}

pub const IbkrForm = struct {
    token_set: bool = false,
    query_id: []const u8 = "",
};

pub fn loadIbkrForm(arena: std.mem.Allocator) IbkrForm {
    const rows = zx.db.rows(arena, struct { cat: []const u8, val: []const u8 },
        \\SELECT cat, val FROM credentials
        \\WHERE cat IN ('ibkr_flex_token', 'ibkr_flex_query_id')
    , .{}) catch return .{};
    var out: IbkrForm = .{};
    for (rows) |r| {
        if (std.mem.eql(u8, r.cat, "ibkr_flex_token")) out.token_set = r.val.len > 0;
        if (std.mem.eql(u8, r.cat, "ibkr_flex_query_id")) out.query_id = r.val;
    }
    return out;
}

pub fn githubTokenSet(arena: std.mem.Allocator) bool {
    return has(arena, "github_token");
}

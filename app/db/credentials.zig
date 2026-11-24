const std = @import("std");
const zx = @import("zx");
const github = @import("../github.zig");

// Secrets from `zx.secrets` (`.env` locally, Worker secrets in prod) win over the db.
const secrets = std.StaticStringMap([]const u8).initComptime(.{
    .{ "caldav_username", "CALDAV_USER" },
    .{ "caldav_password", "CALDAV_PASS" },
    .{ "ibkr_flex_token", "IBKR_FLEX_TOKEN" },
    .{ "github_token", "GITHUB_TOKEN" },
    .{ "mcp_token", "MCP_TOKEN" },
    .{ "oauth_github_client_id", "OAUTH_GITHUB_CLIENT_ID" },
    .{ "oauth_github_client_secret", "OAUTH_GITHUB_CLIENT_SECRET" },
});

pub fn fromSecret(arena: std.mem.Allocator, cat: []const u8) ?[]const u8 {
    const name = secrets.get(cat) orelse return null;
    const val = zx.secrets.get(arena, name) catch return null;
    return if (val) |v| if (v.len > 0) v else null else null;
}

pub fn get(arena: std.mem.Allocator, cat: []const u8) ?[]const u8 {
    if (fromSecret(arena, cat)) |v| return v;
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

pub fn apply(arena: std.mem.Allocator) void {
    if (get(arena, "github_token")) |token| {
        github.setToken(token) catch |err| zx.log.warn("credentials: github token: {any}", .{err});
    }
}

pub const Ibkr = struct {
    token: []const u8,
    query_id: []const u8,

    pub fn load(arena: std.mem.Allocator) ?Ibkr {
        const token = get(arena, "ibkr_flex_token") orelse return null;
        const query_id = get(arena, "ibkr_flex_query_id") orelse return null;
        if (token.len == 0 or query_id.len == 0) return null;
        return .{ .token = token, .query_id = query_id };
    }
};

pub const CaldavForm = struct {
    username: []const u8 = "",
    password_set: bool = false,
    calendar_url: []const u8 = "",
    organizer_email: []const u8 = "",
    meeting_url: []const u8 = "",

    pub fn load(arena: std.mem.Allocator) CaldavForm {
        return .{
            .username = get(arena, "caldav_username") orelse "",
            .password_set = has(arena, "caldav_password"),
            .calendar_url = get(arena, "caldav_calendar_url") orelse "",
            .organizer_email = get(arena, "caldav_organizer_email") orelse "",
            .meeting_url = get(arena, "caldav_meeting_url") orelse "",
        };
    }
};

pub const IbkrForm = struct {
    token_set: bool = false,
    query_id: []const u8 = "",

    pub fn load(arena: std.mem.Allocator) IbkrForm {
        return .{
            .token_set = has(arena, "ibkr_flex_token"),
            .query_id = get(arena, "ibkr_flex_query_id") orelse "",
        };
    }
};

pub fn githubTokenSet(arena: std.mem.Allocator) bool {
    return has(arena, "github_token");
}

pub fn mcpTokenSet(arena: std.mem.Allocator) bool {
    return has(arena, "mcp_token");
}

pub const mcp_token_ttl_days_default: u32 = 1;
pub const mcp_token_ttl_days_max: u32 = 365;

pub fn mcpTokenTtlDays(arena: std.mem.Allocator) u32 {
    const raw = get(arena, "mcp_token_ttl_days") orelse return mcp_token_ttl_days_default;
    const n = std.fmt.parseInt(u32, std.mem.trim(u8, raw, " \t\r\n"), 10) catch return mcp_token_ttl_days_default;
    if (n == 0) return mcp_token_ttl_days_default;
    return @min(n, mcp_token_ttl_days_max);
}
